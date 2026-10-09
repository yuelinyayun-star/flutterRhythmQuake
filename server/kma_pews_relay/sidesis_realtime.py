"""Sidesis Socket.IO realtime feed used by the SASMEX relay."""

from __future__ import annotations

import asyncio
import hashlib
import json
import math
import time
from collections import OrderedDict
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any, Awaitable, Callable, Mapping
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import websockets


# Keys and order from the real Socket.IO handler's extractStateFromMessage().
# The page's default coordinates are deliberately not copied into the relay.
_WEB_STATE_NAMES = (
    "Jalisco", "Colima", "Michoacan", "Guerrero", "Oaxaca", "Chiapas",
    "Puebla", "Veracruz", "Morelos", "Ciudad de Mexico", "Estado de Mexico",
    "Hidalgo", "Tlaxcala", "Tabasco", "Nayarit", "Sonora", "Sinaloa",
    "Baja California", "Baja California Sur", "Chihuahua", "Coahuila",
    "Durango", "Guanajuato", "Aguascalientes", "Zacatecas", "San Luis Potosi",
    "Tamaulipas", "Nuevo Leon", "Campeche", "Yucatan", "Quintana Roo",
)


def _string(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value)
    return text if text.strip() else None


def _number(value: Any) -> int | float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return value if math.isfinite(value) else None
    try:
        text = str(value).strip()
        if not text:
            return None
        number = float(text)
        if not math.isfinite(number):
            return None
        return int(number) if number.is_integer() else number
    except (TypeError, ValueError):
        return None


def _first_info(data: Mapping[str, Any]) -> Mapping[str, Any] | None:
    info = data.get("info")
    if not isinstance(info, list) or not info or not isinstance(info[0], Mapping):
        return None
    return info[0]


def parse_circle_coordinates(value: Any) -> tuple[int | float, int | float] | None:
    """Read only the first lat,lon pair of the page's top-level circle.

    The raw circle (including its radius) is retained separately. Missing or
    invalid coordinates are never replaced with the page's default location.
    """
    if not isinstance(value, str) or not value.strip():
        return None
    pair = value.split()[0].split(",")
    if len(pair) != 2:
        return None
    latitude, longitude = (_number(part) for part in pair)
    if latitude is None or longitude is None:
        return None
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        return None
    return latitude, longitude


def _state_from_message(data: Mapping[str, Any]) -> str | None:
    info = _first_info(data)
    for value in ((info or {}).get("description"), data.get("description"), data.get("title")):
        text = _string(value)
        if text is not None:
            for state in _WEB_STATE_NAMES:
                if state.lower() in text.lower():
                    return state
    return None


def _timestamp_ms(value: Any) -> int | None:
    text = _string(value)
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=UTC)
        return int(parsed.timestamp() * 1000)
    except ValueError:
        return None


def socket_url_with_engine_query(url: str) -> str:
    parsed = urlsplit(url)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    query.update({"EIO": "4", "transport": "websocket"})
    return urlunsplit(
        (parsed.scheme, parsed.netloc, parsed.path, urlencode(query), parsed.fragment)
    )


def parse_socket_io_frame(frame: str) -> tuple[str, Any] | None:
    """Return an event name and payload from an Engine.IO 4 event frame."""

    if not frame or frame[0] != "4" or len(frame) < 3:
        return None
    socket_packet = frame[1:]
    if socket_packet[0] != "2":
        return None
    try:
        packet = json.loads(socket_packet[1:])
    except json.JSONDecodeError:
        return None
    if not isinstance(packet, list) or not packet or not isinstance(packet[0], str):
        return None
    return packet[0], packet[1] if len(packet) > 1 else None


def parse_sidesis_message(event_name: str, raw_data: Any) -> dict[str, Any] | None:
    """Map the page's real new_message handler to our SASMEX JSON shape.

    DOM simulated_alert/replay paths are not inputs to this parser. Upstream
    packets explicitly marked as simulation or replay are excluded as well.
    The original input is not modified; the feed archives its original frame.
    """

    if event_name != "new_message" or not isinstance(raw_data, Mapping):
        return None
    data = raw_data
    if data.get("type") == "heartbeat" or data.get("isSimulation") or data.get("isReplay"):
        return None
    info = _first_info(data)
    raw_severity = _string((info or {}).get("severity") or data.get("severity"))

    identifier = _string(data.get("identifier") or data.get("id"))
    if not identifier:
        identifier = _string(data.get("sent") or data.get("updated"))
    if not identifier:
        return None

    event: dict[str, Any] = {
        "source": "sasmex",
        "id": identifier,
        "eventId": identifier,
        "isWarn": raw_severity is not None and raw_severity.casefold() == "severe",
    }
    if raw_severity is not None:
        event["severity"] = raw_severity

    # The real page uses sent as the event timestamp; updated is a report time.
    epoch_ms = _timestamp_ms(data.get("sent"))
    if epoch_ms is None:
        epoch_ms = _timestamp_ms(data.get("updated"))
    if epoch_ms is not None:
        event["epochMs"] = epoch_ms

    for target, value in (
        ("title", data.get("title")),
        ("updated", data.get("updated")),
        ("sent", data.get("sent")),
        ("msgType", data.get("msgType")),
        ("event", (info or {}).get("event") or data.get("event")),
        (
            "description",
            (info or {}).get("description") or data.get("description") or data.get("title"),
        ),
        ("circle", data.get("circle")),
    ):
        text = _string(value)
        if text:
            event[target] = text

    for target, candidates in (
        ("region", ("region", "place", "location")),
        ("intensidad", ("intensidad", "intensity")),
        ("grado", ("grado",)),
        ("severidad", ("severidad",)),
    ):
        value = next((data.get(key) for key in candidates if data.get(key) is not None), None)
        if target in {"grado", "severidad"}:
            value = _number(value)
        else:
            value = _string(value)
        if value is not None:
            event[target] = value

    state = _state_from_message(data)
    if state is not None:
        event["region"] = state
    coordinates = parse_circle_coordinates(data.get("circle"))
    if coordinates is not None:
        event["lat"], event["lng"] = coordinates

    return event


@dataclass(frozen=True)
class SidesisRealtimeConfig:
    url: str
    reconnect_seconds: float
    timeout_seconds: float
    stale_after_seconds: float


@dataclass
class SidesisRealtimeState:
    latest_event: dict[str, Any] | None = None
    latest_fingerprint: str | None = None
    last_frame_at: datetime | None = None
    last_change_at: datetime | None = None
    last_error: str | None = None
    consecutive_failures: int = 0
    accepted_updates: int = 0
    connected: bool = False

    def snapshot(self) -> dict[str, Any]:
        return {
            "source": "sasmex",
            "Data": self.latest_event,
            "endpoint": "wss://sidesis.iigea.org/socket.io/",
            "connected": self.connected,
            "lastFrameAtUtc": self.last_frame_at.isoformat()
            if self.last_frame_at
            else None,
            "lastChangeAtUtc": self.last_change_at.isoformat()
            if self.last_change_at
            else None,
            "fingerprint": self.latest_fingerprint,
        }

    def health(self, stale_after_seconds: float) -> dict[str, Any]:
        age = None
        if self.last_frame_at is not None:
            age = max(0.0, (datetime.now(UTC) - self.last_frame_at).total_seconds())
        healthy = age is not None and age <= stale_after_seconds and self.connected
        return {
            "status": "ok" if healthy else "degraded",
            "healthy": healthy,
            "endpoint": "wss://sidesis.iigea.org/socket.io/",
            "connected": self.connected,
            "lastFrameAtUtc": self.last_frame_at.isoformat()
            if self.last_frame_at
            else None,
            "lastChangeAtUtc": self.last_change_at.isoformat()
            if self.last_change_at
            else None,
            "lastFrameAgeSeconds": round(age, 3) if age is not None else None,
            "lastError": self.last_error,
            "consecutiveFailures": self.consecutive_failures,
            "acceptedUpdates": self.accepted_updates,
            "latestEventId": (self.latest_event or {}).get("id"),
        }


class SidesisRealtimeFeed:
    """Listen to the same Socket.IO root namespace used by the website."""

    def __init__(
        self,
        config: SidesisRealtimeConfig,
        on_update: Callable[[dict[str, Any], bytes, str], Awaitable[None]],
    ) -> None:
        self.config = config
        self.on_update = on_update
        self.state = SidesisRealtimeState()
        self._stop_event: asyncio.Event | None = None
        self._seen: OrderedDict[str, None] = OrderedDict()

    async def start(self) -> None:
        return None

    async def close(self) -> None:
        if self._stop_event is not None:
            self._stop_event.set()

    async def _receive_connection(self, stop_event: asyncio.Event) -> None:
        uri = socket_url_with_engine_query(self.config.url)
        async with websockets.connect(
            uri,
            open_timeout=self.config.timeout_seconds,
            close_timeout=self.config.timeout_seconds,
            ping_interval=None,
            max_size=2 * 1024 * 1024,
            additional_headers={"User-Agent": "RhythmQuake-SASMEX-Relay/1.0"},
        ) as socket:
            self.state.connected = False
            async for raw in socket:
                if stop_event.is_set():
                    return
                raw_frame = raw if isinstance(raw, bytes) else raw.encode("utf-8")
                frame = raw.decode("utf-8") if isinstance(raw, bytes) else raw
                if not isinstance(frame, str) or not frame:
                    continue
                self.state.last_frame_at = datetime.now(UTC)
                self.state.last_error = None
                self.state.consecutive_failures = 0
                engine_type = frame[0]
                if engine_type == "0":
                    await socket.send("40")
                    continue
                if engine_type == "2":
                    await socket.send("3")
                    continue
                if engine_type == "1":
                    return
                if engine_type != "4":
                    continue
                if frame[1:2] == "0":
                    self.state.connected = True
                    continue
                parsed = parse_socket_io_frame(frame)
                if parsed is None:
                    continue
                event_name, raw_data = parsed
                event = parse_sidesis_message(event_name, raw_data)
                if event is None:
                    continue
                fingerprint = hashlib.sha256(
                    json.dumps(
                        raw_data,
                        ensure_ascii=False,
                        sort_keys=True,
                        separators=(",", ":"),
                    ).encode("utf-8")
                ).hexdigest()
                if fingerprint in self._seen:
                    continue
                self._seen[fingerprint] = None
                while len(self._seen) > 128:
                    self._seen.popitem(last=False)
                self.state.latest_event = event
                self.state.latest_fingerprint = fingerprint
                self.state.last_change_at = datetime.now(UTC)
                self.state.accepted_updates += 1
                await self.on_update(event, raw_frame, event_name)

    async def poll_forever(self, stop_event: asyncio.Event) -> None:
        self._stop_event = stop_event
        while not stop_event.is_set():
            try:
                await self._receive_connection(stop_event)
            except Exception as exc:
                self.state.last_error = str(exc)
                self.state.consecutive_failures += 1
            self.state.connected = False
            try:
                await asyncio.wait_for(
                    stop_event.wait(), timeout=self.config.reconnect_seconds
                )
            except TimeoutError:
                pass
