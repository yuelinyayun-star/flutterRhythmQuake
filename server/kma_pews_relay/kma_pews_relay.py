"""KMA PEWS binary feed to WebSocket relay.

The relay uses the KMA ``ST`` response header as its only remote clock source.
It never queries FAN or an external NTP service.
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import logging
import os
import signal
import sys
import time
import uuid
from collections import Counter
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta, timezone
from http import HTTPStatus
from typing import Any
from urllib.parse import parse_qs, urlsplit

import aiohttp
from websockets.asyncio.server import ServerConnection, serve
from websockets.http11 import Request, Response


KST = timezone(timedelta(hours=9), "KST")
LOGGER = logging.getLogger("kma_pews_relay")


@dataclass(frozen=True)
class Config:
    host: str = os.environ.get("KMA_RELAY_HOST", "0.0.0.0")
    port: int = int(os.environ.get("KMA_RELAY_PORT", "8765"))
    official_base_url: str = os.environ.get(
        "KMA_PEWS_BASE_URL", "https://www.weather.go.kr/pews"
    ).rstrip("/")
    target_lag_seconds: int = int(os.environ.get("KMA_TARGET_LAG_SECONDS", "1"))
    lag_retry_seconds: int = int(os.environ.get("KMA_LAG_RETRY_SECONDS", "2"))
    request_timeout_seconds: float = float(
        os.environ.get("KMA_REQUEST_TIMEOUT_SECONDS", "3")
    )
    stale_after_seconds: float = float(
        os.environ.get("KMA_STALE_AFTER_SECONDS", "5")
    )
    heartbeat_seconds: float = float(os.environ.get("KMA_HEARTBEAT_SECONDS", "25"))
    max_clients: int = int(os.environ.get("KMA_MAX_CLIENTS", "500"))
    access_token: str = os.environ.get("KMA_RELAY_TOKEN", "")


@dataclass(frozen=True)
class Station:
    latitude: float
    longitude: float

    def to_json(self) -> dict[str, float]:
        return {"latitude": self.latitude, "longitude": self.longitude}


@dataclass(frozen=True)
class FrameHeader:
    station_table_changed: bool
    phase: int
    phase_bits: int
    event_id: str


@dataclass(frozen=True)
class Fetched:
    status: int
    body: bytes
    headers: dict[str, str]
    round_trip_seconds: float


@dataclass
class RelayState:
    stations: list[Station] = field(default_factory=list)
    station_digest: str | None = None
    latest_data: dict[str, Any] | None = None
    latest_raw_mmi: list[int] | None = None
    latest_timestamp_utc: str | None = None
    latest_phase: int | None = None
    latest_event_id: str | None = None
    latest_md5: str | None = None
    latest_frame_utc: datetime | None = None
    latest_received_monotonic: float | None = None
    last_official_status: int | None = None
    consecutive_failures: int = 0
    accepted_frames: int = 0


class KmaServerClock:
    """Monotonic clock anchored only by KMA's ST response header."""

    def __init__(self) -> None:
        self._server_epoch_at_sync: float | None = None
        self._monotonic_at_sync: float | None = None
        self.last_sync_utc: datetime | None = None
        self.last_round_trip_seconds: float | None = None

    @property
    def is_synced(self) -> bool:
        return self._server_epoch_at_sync is not None

    def update(
        self,
        st_header: str | None,
        request_started_monotonic: float,
        response_received_monotonic: float,
    ) -> bool:
        if not st_header:
            return False
        try:
            server_epoch = float(st_header)
        except (TypeError, ValueError):
            return False
        if not (1_500_000_000 < server_epoch < 4_000_000_000):
            return False

        round_trip = max(
            0.0, response_received_monotonic - request_started_monotonic
        )
        midpoint = request_started_monotonic + round_trip / 2
        self._server_epoch_at_sync = server_epoch
        self._monotonic_at_sync = midpoint
        self.last_sync_utc = datetime.fromtimestamp(server_epoch, UTC)
        self.last_round_trip_seconds = round_trip
        return True

    def now_epoch(self) -> float:
        if self._server_epoch_at_sync is None or self._monotonic_at_sync is None:
            raise RuntimeError("KMA ST clock has not been synchronized")
        return self._server_epoch_at_sync + (
            time.monotonic() - self._monotonic_at_sync
        )

    def now_utc(self) -> datetime:
        return datetime.fromtimestamp(self.now_epoch(), UTC)


def decode_header(data: bytes) -> FrameHeader:
    if len(data) < 4:
        raise ValueError(f"KMA frame is shorter than the 4-byte header: {len(data)}")
    word = int.from_bytes(data[:4], "big")
    station_table_changed = bool((word >> 31) & 1)
    phase_bits = (word >> 29) & 0b11
    phase = {0b00: 1, 0b10: 2, 0b11: 3, 0b01: 4}[phase_bits]
    event_suffix = word & ((1 << 26) - 1)
    return FrameHeader(
        station_table_changed=station_table_changed,
        phase=phase,
        phase_bits=phase_bits,
        event_id=f"20{event_suffix}",
    )


def decode_stations(data: bytes) -> list[Station]:
    """Decode complete 20-bit coordinates and discard trailing padding bits."""

    total_bits = len(data) * 8
    if total_bits < 20:
        raise ValueError("KMA station table doesn't contain a complete station")
    packed = int.from_bytes(data, "big")
    stations: list[Station] = []

    def read_bits(offset: int, width: int) -> int:
        shift = total_bits - offset - width
        return (packed >> shift) & ((1 << width) - 1)

    for offset in range(0, total_bits - 19, 20):
        lat_raw = read_bits(offset, 10)
        lon_raw = read_bits(offset + 10, 10)
        latitude = 30 + lat_raw / 100
        longitude_base = (
            130
            if (lat_raw, lon_raw) in {(748, 89), (751, 81)}
            else 120
        )
        longitude = longitude_base + lon_raw / 100
        if not (30 <= latitude <= 40 and 120 <= longitude <= 132):
            raise ValueError(
                f"invalid KMA station coordinate at bit {offset}: "
                f"{latitude}, {longitude}"
            )
        stations.append(Station(round(latitude, 2), round(longitude, 2)))

    return stations


def decode_raw_levels(frame: bytes, station_count: int) -> list[int]:
    if station_count <= 0:
        raise ValueError("station_count must be positive")
    nibbles: list[int] = []
    for value in frame[4:]:
        nibbles.append(value >> 4)
        nibbles.append(value & 0x0F)
        if len(nibbles) >= station_count:
            return nibbles[:station_count]
    raise ValueError(
        f"KMA frame contains {len(nibbles)} levels for {station_count} stations"
    )


def frame_level_capacity(frame: bytes) -> int:
    """Return the number of station values available after the frame header."""

    return max(0, (len(frame) - 4) * 2)


def fan_compatible_mmi(raw_level: int) -> int:
    """Convert the PEWS 4-bit station code to the existing client scale.

    The ordering is the one used by the current KMA station relay. The relay
    also publishes rawMmi so the source value is always retained.
    """

    if raw_level == 0:
        return -3
    if raw_level == 1:
        return -2
    if 12 <= raw_level <= 15:
        return raw_level - 13
    if 2 <= raw_level <= 11:
        return min(raw_level + 1, 11)
    raise ValueError(f"KMA raw level is outside 0..15: {raw_level}")


class KmaPewsClient:
    def __init__(self, config: Config, clock: KmaServerClock) -> None:
        self.config = config
        self.clock = clock
        self.session: aiohttp.ClientSession | None = None

    async def start(self) -> None:
        timeout = aiohttp.ClientTimeout(total=self.config.request_timeout_seconds)
        connector = aiohttp.TCPConnector(limit=4, ttl_dns_cache=300)
        self.session = aiohttp.ClientSession(
            timeout=timeout,
            connector=connector,
            headers={
                "User-Agent": "RhythmQuake-KMA-PEWS-Relay/1.0",
                "Referer": f"{self.config.official_base_url}/",
                "Accept": "application/octet-stream,*/*;q=0.8",
            },
        )

    async def close(self) -> None:
        if self.session is not None:
            await self.session.close()
            self.session = None

    async def fetch(self, path: str) -> Fetched:
        if self.session is None:
            raise RuntimeError("KMA HTTP client hasn't been started")
        url = f"{self.config.official_base_url}/{path.lstrip('/')}"
        started = time.monotonic()
        try:
            async with self.session.get(url) as response:
                body = await response.read()
                ended = time.monotonic()
                st_header = response.headers.get("ST")
                headers = {key: value for key, value in response.headers.items()}
                self.clock.update(st_header, started, ended)
                return Fetched(
                    status=response.status,
                    body=body,
                    headers=headers,
                    round_trip_seconds=ended - started,
                )
        except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
            raise ConnectionError(f"GET {url} failed: {exc}") from exc

    async def synchronize_clock(self) -> None:
        response = await self.fetch("")
        if response.status != HTTPStatus.OK:
            raise ConnectionError(
                f"KMA clock endpoint returned HTTP {response.status}"
            )
        if not self.clock.is_synced:
            raise ConnectionError("KMA response didn't contain a valid ST header")


class KmaRelay:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.clock = KmaServerClock()
        self.state = RelayState()
        self.http = KmaPewsClient(config, self.clock)
        self.clients: set[ServerConnection] = set()
        self.client_send_locks: dict[ServerConnection, asyncio.Lock] = {}
        self.stop_event = asyncio.Event()
        self._last_attempted_utc: datetime | None = None
        self._last_summary_log_monotonic = 0.0

    def _authorized(self, request: Request) -> bool:
        if not self.config.access_token:
            return True
        parsed = urlsplit(request.path)
        query_token = parse_qs(parsed.query).get("token", [""])[0]
        auth = request.headers.get("Authorization", "")
        bearer = auth[7:] if auth.startswith("Bearer ") else ""
        return query_token == self.config.access_token or bearer == self.config.access_token

    def _json_response(
        self,
        connection: ServerConnection,
        status: HTTPStatus,
        payload: dict[str, Any],
    ) -> Response:
        response = connection.respond(
            status,
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        )
        del response.headers["Content-Type"]
        response.headers["Content-Type"] = "application/json; charset=utf-8"
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Cache-Control"] = "no-store"
        return response

    async def process_request(
        self, connection: ServerConnection, request: Request
    ) -> Response | None:
        parsed = urlsplit(request.path)
        path = parsed.path.rstrip("/") or "/"
        upgrade = request.headers.get("Upgrade", "").lower() == "websocket"

        if upgrade and path in {"/kma-station", "/ws"}:
            if self._authorized(request):
                return None
            return self._json_response(
                connection, HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"}
            )

        if request.headers.get("Access-Control-Request-Method"):
            response = connection.respond(HTTPStatus.NO_CONTENT, "")
            response.headers["Access-Control-Allow-Origin"] = "*"
            response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "Authorization"
            return response

        if not self._authorized(request):
            return self._json_response(
                connection, HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"}
            )
        if path == "/health":
            payload, healthy = self.health_payload()
            return self._json_response(
                connection,
                HTTPStatus.OK if healthy else HTTPStatus.SERVICE_UNAVAILABLE,
                payload,
            )
        if path == "/snapshot":
            return self._json_response(
                connection, HTTPStatus.OK, self.snapshot_payload()
            )
        if path == "/":
            return self._json_response(
                connection,
                HTTPStatus.OK,
                {
                    "service": "KMA PEWS relay",
                    "websocket": "/kma-station",
                    "health": "/health",
                    "snapshot": "/snapshot",
                    "timeSource": "KMA ST response header",
                },
            )
        return self._json_response(
            connection, HTTPStatus.NOT_FOUND, {"error": "not found"}
        )

    async def handle_websocket(self, websocket: ServerConnection) -> None:
        if len(self.clients) >= self.config.max_clients:
            await websocket.send(
                self._encode({"type": "error", "message": "连接数超限"})
            )
            await websocket.close(code=1013, reason="server capacity reached")
            return

        self.clients.add(websocket)
        self.client_send_locks[websocket] = asyncio.Lock()
        peer = websocket.remote_address
        LOGGER.info("WebSocket connected: %s; clients=%d", peer, len(self.clients))
        try:
            await self._send(websocket, self._heartbeat_message())
            if self.state.stations:
                await self._send(websocket, self._station_message("initial_stations"))
            if self.state.latest_data is not None:
                await self._send(websocket, self._data_message("initial"))

            async for raw_message in websocket:
                text = raw_message.decode("utf-8") if isinstance(raw_message, bytes) else raw_message
                message: Any = None
                is_ping = text.strip().lower() == "ping"
                if not is_ping:
                    try:
                        message = json.loads(text)
                        is_ping = message.get("type") == "ping"
                    except (json.JSONDecodeError, AttributeError):
                        is_ping = False
                if is_ping:
                    await self._send(
                        websocket,
                        {"type": "pong", "timestamp": self._clock_timestamp()},
                    )
                elif text.strip().lower() == "query" or (
                    isinstance(message, dict) and message.get("type") == "query"
                ):
                    await self._send(
                        websocket,
                        {
                            "type": "query_response",
                            "data": self.state.latest_data,
                        },
                    )
        except Exception as exc:
            LOGGER.debug("WebSocket %s ended: %s", peer, exc)
        finally:
            self.clients.discard(websocket)
            self.client_send_locks.pop(websocket, None)
            LOGGER.info("WebSocket disconnected: %s; clients=%d", peer, len(self.clients))

    async def _send(self, websocket: ServerConnection, payload: dict[str, Any]) -> None:
        lock = self.client_send_locks.get(websocket)
        if lock is None:
            return
        async with lock:
            await websocket.send(self._encode(payload))

    async def broadcast(self, payload: dict[str, Any]) -> None:
        if not self.clients:
            return
        clients = list(self.clients)
        results = await asyncio.gather(
            *(self._send(client, payload) for client in clients),
            return_exceptions=True,
        )
        for client, result in zip(clients, results):
            if isinstance(result, Exception):
                self.clients.discard(client)
                self.client_send_locks.pop(client, None)

    @staticmethod
    def _encode(payload: dict[str, Any]) -> str:
        return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

    def _clock_timestamp(self) -> int | None:
        if not self.clock.is_synced:
            return None
        return int(self.clock.now_epoch() * 1000)

    def _heartbeat_message(self) -> dict[str, Any]:
        timestamp = self._clock_timestamp()
        return {
            "type": "heartbeat",
            "ver": "1.1.0",
            "id": str(uuid.uuid4()),
            "timestamp": timestamp,
        }

    def _station_message(self, message_type: str) -> dict[str, Any]:
        return {
            "type": message_type,
            "timestamp": self._clock_timestamp(),
            "stations": [station.to_json() for station in self.state.stations],
        }

    def _data_message(self, message_type: str) -> dict[str, Any]:
        return {
            "type": message_type,
            "source": "kma-station",
            "Data": self.state.latest_data,
            "md5": self.state.latest_md5,
        }

    async def _refresh_station_table(self, stamp: str) -> bool:
        response = await self.http.fetch(f"data/{stamp}.s")
        self.state.last_official_status = response.status
        if response.status != HTTPStatus.OK:
            LOGGER.warning("KMA station table %s.s returned HTTP %s", stamp, response.status)
            return False
        stations = decode_stations(response.body)
        digest = hashlib.sha256(response.body).hexdigest()
        changed = digest != self.state.station_digest
        self.state.stations = stations
        self.state.station_digest = digest
        if changed:
            LOGGER.info("KMA station table loaded: %d stations", len(stations))
            await self.broadcast(self._station_message("kma_stations_update"))
        return True

    async def _accept_frame(self, stamp_utc: datetime, frame: bytes) -> None:
        header = decode_header(frame)
        stamp = stamp_utc.strftime("%Y%m%d%H%M%S")
        level_capacity = frame_level_capacity(frame)
        if (
            not self.state.stations
            or header.station_table_changed
            or len(self.state.stations) > level_capacity
        ):
            if self.state.stations and len(self.state.stations) > level_capacity:
                LOGGER.info(
                    "KMA station table has %d stations but frame %s provides "
                    "%d values; refreshing station table",
                    len(self.state.stations),
                    stamp,
                    level_capacity,
                )
            if not await self._refresh_station_table(stamp):
                raise ValueError("station table required by frame is unavailable")

        raw_mmi = decode_raw_levels(frame, len(self.state.stations))
        mmi = [fan_compatible_mmi(level) for level in raw_mmi]
        timestamp_kst = stamp_utc.astimezone(KST).strftime("%Y-%m-%d %H:%M:%S")
        timestamp_utc = stamp_utc.isoformat().replace("+00:00", "Z")
        data = {
            "timestamp": timestamp_kst,
            "mmi": mmi,
        }
        canonical = json.dumps(
            data, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
        self.state.latest_data = data
        self.state.latest_raw_mmi = raw_mmi
        self.state.latest_timestamp_utc = timestamp_utc
        self.state.latest_phase = header.phase
        self.state.latest_event_id = header.event_id
        self.state.latest_md5 = hashlib.md5(canonical).hexdigest()
        self.state.latest_frame_utc = stamp_utc
        self.state.latest_received_monotonic = time.monotonic()
        self.state.consecutive_failures = 0
        self.state.accepted_frames += 1
        await self.broadcast(self._data_message("update"))

        now_mono = time.monotonic()
        max_mmi = max(mmi, default=-3)
        if (
            now_mono - self._last_summary_log_monotonic >= 60
            or max_mmi >= 2
            or self.state.accepted_frames == 1
        ):
            self._last_summary_log_monotonic = now_mono
            LOGGER.info(
                "KMA frame %s accepted: stations=%d maxMmi=%d raw=%s",
                timestamp_kst,
                len(mmi),
                max_mmi,
                dict(sorted(Counter(raw_mmi).items())),
            )

    async def poll_forever(self) -> None:
        while not self.stop_event.is_set():
            if not self.clock.is_synced:
                try:
                    await self.http.synchronize_clock()
                    LOGGER.info(
                        "KMA ST clock synchronized: %s; RTT=%.3fs",
                        self.clock.last_sync_utc.isoformat()
                        if self.clock.last_sync_utc
                        else "unknown",
                        self.clock.last_round_trip_seconds or 0,
                    )
                except Exception as exc:
                    self.state.consecutive_failures += 1
                    LOGGER.warning("KMA ST clock synchronization failed: %s", exc)
                    await self._sleep_or_stop(2)
                    continue

            target_epoch = int(self.clock.now_epoch()) - self.config.target_lag_seconds
            target_utc = datetime.fromtimestamp(target_epoch, UTC)
            if self._last_attempted_utc == target_utc:
                await self._sleep_or_stop(0.05)
                continue
            self._last_attempted_utc = target_utc

            accepted = False
            for extra_lag in range(self.config.lag_retry_seconds + 1):
                candidate = target_utc - timedelta(seconds=extra_lag)
                latest = self.state.latest_frame_utc
                if latest is not None and candidate <= latest:
                    continue
                stamp = candidate.strftime("%Y%m%d%H%M%S")
                try:
                    response = await self.http.fetch(f"data/{stamp}.b")
                    self.state.last_official_status = response.status
                    if response.status == HTTPStatus.NOT_FOUND:
                        continue
                    if response.status != HTTPStatus.OK:
                        raise ConnectionError(
                            f"KMA frame {stamp}.b returned HTTP {response.status}"
                        )
                    await self._accept_frame(candidate, response.body)
                    accepted = True
                    break
                except Exception as exc:
                    LOGGER.warning("KMA frame %s rejected: %s", stamp, exc)
                    break

            if not accepted:
                self.state.consecutive_failures += 1
                if self.state.consecutive_failures >= 3:
                    try:
                        await self.http.synchronize_clock()
                    except Exception as exc:
                        LOGGER.warning("KMA ST resynchronization failed: %s", exc)
            await self._sleep_or_stop(0.05)

    async def heartbeat_forever(self) -> None:
        while not self.stop_event.is_set():
            await self._sleep_or_stop(self.config.heartbeat_seconds)
            if self.stop_event.is_set():
                return
            await self.broadcast(
                self._heartbeat_message()
            )

    async def _sleep_or_stop(self, seconds: float) -> None:
        try:
            await asyncio.wait_for(self.stop_event.wait(), timeout=seconds)
        except TimeoutError:
            pass

    def health_payload(self) -> tuple[dict[str, Any], bool]:
        age: float | None = None
        if self.state.latest_received_monotonic is not None:
            age = max(0.0, time.monotonic() - self.state.latest_received_monotonic)
        healthy = bool(
            self.clock.is_synced
            and self.state.stations
            and age is not None
            and age <= self.config.stale_after_seconds
        )
        payload = {
            "status": "ok" if healthy else "degraded",
            "timeSource": "KMA-ST",
            "clockSynced": self.clock.is_synced,
            "lastClockSyncUtc": self.clock.last_sync_utc.isoformat()
            if self.clock.last_sync_utc
            else None,
            "clockRoundTripMs": round(
                (self.clock.last_round_trip_seconds or 0) * 1000, 1
            ),
            "lastFrameUtc": self.state.latest_frame_utc.isoformat()
            if self.state.latest_frame_utc
            else None,
            "lastFrameAgeSeconds": round(age, 3) if age is not None else None,
            "stationCount": len(self.state.stations),
            "clientCount": len(self.clients),
            "consecutiveFailures": self.state.consecutive_failures,
            "lastOfficialHttpStatus": self.state.last_official_status,
            "acceptedFrames": self.state.accepted_frames,
        }
        return payload, healthy

    def snapshot_payload(self) -> dict[str, Any]:
        health, _ = self.health_payload()
        return {
            "health": health,
            "stations": [station.to_json() for station in self.state.stations],
            "Data": self.state.latest_data,
            "md5": self.state.latest_md5,
            "diagnostics": {
                "rawMmi": self.state.latest_raw_mmi,
                "timestampUtc": self.state.latest_timestamp_utc,
                "phase": self.state.latest_phase,
                "eventId": self.state.latest_event_id,
                "timeSource": "KMA-ST",
            },
        }

    async def run(self) -> None:
        await self.http.start()
        poll_task = asyncio.create_task(self.poll_forever(), name="kma-poller")
        heartbeat_task = asyncio.create_task(
            self.heartbeat_forever(), name="websocket-heartbeat"
        )
        try:
            async with serve(
                self.handle_websocket,
                self.config.host,
                self.config.port,
                process_request=self.process_request,
                ping_interval=20,
                ping_timeout=20,
                close_timeout=5,
                max_size=64 * 1024,
                compression=None,
            ):
                LOGGER.info(
                    "KMA PEWS relay listening on %s:%d/kma-station",
                    self.config.host,
                    self.config.port,
                )
                await self.stop_event.wait()
        finally:
            self.stop_event.set()
            for task in (poll_task, heartbeat_task):
                task.cancel()
            await asyncio.gather(poll_task, heartbeat_task, return_exceptions=True)
            await self.http.close()


async def check_once(config: Config) -> int:
    clock = KmaServerClock()
    client = KmaPewsClient(config, clock)
    await client.start()
    try:
        await client.synchronize_clock()
        target = datetime.fromtimestamp(
            int(clock.now_epoch()) - config.target_lag_seconds, UTC
        )
        last_error = "no candidate requested"
        for extra_lag in range(config.lag_retry_seconds + 1):
            candidate = target - timedelta(seconds=extra_lag)
            stamp = candidate.strftime("%Y%m%d%H%M%S")
            frame = await client.fetch(f"data/{stamp}.b")
            if frame.status == HTTPStatus.NOT_FOUND:
                last_error = f"{stamp}.b returned 404"
                continue
            if frame.status != HTTPStatus.OK:
                raise RuntimeError(f"{stamp}.b returned HTTP {frame.status}")
            table = await client.fetch(f"data/{stamp}.s")
            if table.status != HTTPStatus.OK:
                raise RuntimeError(f"{stamp}.s returned HTTP {table.status}")
            stations = decode_stations(table.body)
            header = decode_header(frame.body)
            raw = decode_raw_levels(frame.body, len(stations))
            converted = [fan_compatible_mmi(value) for value in raw]
            print(
                json.dumps(
                    {
                        "timeSource": "KMA-ST",
                        "frameUtc": candidate.isoformat(),
                        "frameKst": candidate.astimezone(KST).isoformat(),
                        "stationCount": len(stations),
                        "phase": header.phase,
                        "eventId": header.event_id,
                        "rawDistribution": dict(sorted(Counter(raw).items())),
                        "mmiDistribution": dict(sorted(Counter(converted).items())),
                    },
                    ensure_ascii=False,
                    indent=2,
                )
            )
            return 0
        raise RuntimeError(last_error)
    finally:
        await client.close()


def configure_utf8_console() -> None:
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8", errors="replace")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="KMA PEWS WebSocket relay")
    parser.add_argument(
        "--check-once",
        action="store_true",
        help="fetch and decode one live official KMA frame, then exit",
    )
    return parser.parse_args()


def main() -> int:
    configure_utf8_console()
    logging.basicConfig(
        level=os.environ.get("KMA_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    args = parse_args()
    config = Config()
    if args.check_once:
        return asyncio.run(check_once(config))

    relay = KmaRelay(config)
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def request_stop(*_: Any) -> None:
        loop.call_soon_threadsafe(relay.stop_event.set)

    signal.signal(signal.SIGINT, request_stop)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, request_stop)
    try:
        loop.run_until_complete(relay.run())
        return 0
    finally:
        loop.close()


if __name__ == "__main__":
    raise SystemExit(main())
