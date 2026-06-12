"""
SeedLink to WebSocket relay for FDSN motion samples.

Requires:
  pip install obspy websockets numpy

Run:
  python tools/fdsn_seedlink_relay.py

Flutter listens on:
  ws://127.0.0.1:8791/fdsn-motion

This relay subscribes to a small default stream set. Expand STREAMS carefully;
subscribing to full global networks is not practical for a desktop client.
"""

from __future__ import annotations

import asyncio
import json
import math
import os
import signal
import threading
import time
from dataclasses import dataclass
from typing import Any

import numpy as np
import websockets
from obspy import UTCDateTime
from obspy.clients.fdsn import Client as FdsnClient
from obspy.clients.seedlink.easyseedlink import EasySeedLinkClient


HOST = os.environ.get("FDSN_RELAY_HOST", "127.0.0.1")
PORT = int(os.environ.get("FDSN_RELAY_PORT", "8791"))


@dataclass(frozen=True)
class StreamSpec:
    source: str
    seedlink: str
    fdsn_base: str
    network: str
    station: str
    selector: str


STREAMS = [
    StreamSpec("EarthScope", "rtserve.earthscope.org:18000", "https://service.earthscope.org", "IU", "ANMO", "BH?"),
    StreamSpec("EarthScope", "rtserve.earthscope.org:18000", "https://service.earthscope.org", "IU", "COLA", "BH?"),
    StreamSpec("EarthScope", "rtserve.earthscope.org:18000", "https://service.earthscope.org", "II", "PFO", "BH?"),
    StreamSpec("GEOFON", "geofon.gfz.de:18000", "https://geofon.gfz-potsdam.de", "GE", "ACRG", "BH?"),
    StreamSpec("GEOFON", "geofon.gfz.de:18000", "https://geofon.gfz-potsdam.de", "GE", "MORC", "BH?"),
    StreamSpec("GEOFON", "geofon.gfz.de:18000", "https://geofon.gfz-potsdam.de", "GE", "WLF", "BH?"),
]


class MotionBroadcaster:
    def __init__(self) -> None:
        self.clients: set[Any] = set()
        self.loop: asyncio.AbstractEventLoop | None = None
        self.last_samples: dict[str, dict[str, Any]] = {}

    def attach_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        self.loop = loop

    async def add_client(self, websocket: Any) -> None:
        self.clients.add(websocket)
        for sample in self.last_samples.values():
            await websocket.send(json.dumps(sample, separators=(",", ":")))

    def remove_client(self, websocket: Any) -> None:
        self.clients.discard(websocket)

    def publish_threadsafe(self, sample: dict[str, Any]) -> None:
        key = f"{sample.get('network')}.{sample.get('station')}.{sample.get('channel')}"
        self.last_samples[key] = sample
        loop = self.loop
        if loop is None:
            return
        loop.call_soon_threadsafe(asyncio.create_task, self._broadcast(sample))

    async def _broadcast(self, sample: dict[str, Any]) -> None:
        if not self.clients:
            return
        payload = json.dumps(sample, separators=(",", ":"))
        dead = []
        for ws in list(self.clients):
            try:
                await ws.send(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.clients.discard(ws)


class ResponseCache:
    def __init__(self) -> None:
        self._clients: dict[str, FdsnClient] = {}
        self._inventory: dict[str, Any] = {}
        self._lock = threading.Lock()

    def get_inventory(self, spec: StreamSpec, channel: str, starttime: UTCDateTime, endtime: UTCDateTime) -> Any | None:
        key = f"{spec.fdsn_base}|{spec.network}|{spec.station}|{channel}"
        with self._lock:
            if key in self._inventory:
                return self._inventory[key]
            client = self._clients.get(spec.fdsn_base)
            if client is None:
                client = FdsnClient(base_url=spec.fdsn_base)
                self._clients[spec.fdsn_base] = client

        try:
            inventory = client.get_stations(
                network=spec.network,
                station=spec.station,
                channel=channel,
                level="response",
                starttime=starttime - 300,
                endtime=endtime + 300,
            )
        except Exception as exc:
            print(f"[inventory] {key} failed: {exc}")
            return None

        with self._lock:
            self._inventory[key] = inventory
        return inventory


def _prefilter(trace: Any) -> tuple[float, float, float, float]:
    nyquist = max(trace.stats.sampling_rate / 2.0, 1.0)
    f4 = min(nyquist * 0.9, 20.0)
    f3 = min(f4 * 0.8, 10.0)
    return (0.02, 0.05, f3, f4)


def _calc_motion(trace: Any, inventory: Any | None) -> tuple[float | None, float | None, float | None]:
    if trace.stats.npts < 4:
        return None, None, None

    tr = trace.copy()
    tr.detrend("demean")
    tr.taper(max_percentage=0.05, type="hann")
    sample_rate = float(tr.stats.sampling_rate or 0.0)
    if sample_rate <= 0:
        return None, None, None

    pga = None
    pgv = None

    if inventory is not None:
        try:
            vel = tr.copy()
            vel.remove_response(
                inventory=inventory,
                output="VEL",
                pre_filt=_prefilter(tr),
                water_level=60,
            )
            velocity_m_s = np.asarray(vel.data, dtype=float)
            if velocity_m_s.size > 0:
                pgv = float(np.nanmax(np.abs(velocity_m_s)) * 100.0)
                accel_m_s2 = np.gradient(velocity_m_s, 1.0 / sample_rate)
                pga = float(np.nanmax(np.abs(accel_m_s2)) * 100.0)
        except Exception as exc:
            print(f"[response] {trace.id} failed: {exc}")

    intensity = None
    if pga is not None and math.isfinite(pga) and pga > 0.001:
        intensity = 2.68 + 1.72 * math.log10(pga)
    return pga, pgv, intensity


def _is_active(pga: float | None, pgv: float | None, intensity: float | None) -> bool:
    if intensity is not None and intensity >= 0.5:
        return True
    if pga is not None and pga >= 0.8:
        return True
    if pgv is not None and pgv >= 0.05:
        return True
    return False


class RelaySeedLinkClient(EasySeedLinkClient):
    def __init__(self, seedlink_url: str, specs: list[StreamSpec], broadcaster: MotionBroadcaster, responses: ResponseCache) -> None:
        super().__init__(seedlink_url, autoconnect=True)
        self.specs = specs
        self.broadcaster = broadcaster
        self.responses = responses
        self.spec_by_station = {f"{s.network}.{s.station}": s for s in specs}

    def on_data(self, trace: Any) -> None:
        spec = self.spec_by_station.get(f"{trace.stats.network}.{trace.stats.station}")
        if spec is None:
            return

        inventory = self.responses.get_inventory(
            spec,
            trace.stats.channel,
            trace.stats.starttime,
            trace.stats.endtime,
        )
        pga, pgv, intensity = _calc_motion(trace, inventory)
        sample = {
            "type": "motion",
            "source": spec.source,
            "network": trace.stats.network,
            "station": trace.stats.station,
            "channel": trace.stats.channel,
            "pga": pga,
            "pgv": pgv,
            "intensity": intensity,
            "active": _is_active(pga, pgv, intensity),
            "timestamp": trace.stats.endtime.datetime.isoformat() + "Z",
        }
        self.broadcaster.publish_threadsafe(sample)

    def on_seedlink_error(self, exc: Exception) -> None:
        print(f"[seedlink] error: {exc}")

    def on_terminate(self) -> None:
        print("[seedlink] terminated")


def _run_seedlink_group(seedlink_url: str, specs: list[StreamSpec], broadcaster: MotionBroadcaster, responses: ResponseCache) -> None:
    while True:
        try:
            client = RelaySeedLinkClient(seedlink_url, specs, broadcaster, responses)
            for spec in specs:
                print(f"[seedlink] select {seedlink_url} {spec.network}.{spec.station} {spec.selector}")
                client.select_stream(spec.network, spec.station, spec.selector)
            client.run()
        except Exception as exc:
            print(f"[seedlink] {seedlink_url} failed: {exc}")
            time.sleep(10)


async def _handler(websocket: Any) -> None:
    await BROADCASTER.add_client(websocket)
    try:
        async for _ in websocket:
            pass
    finally:
        BROADCASTER.remove_client(websocket)


def _start_seedlink_threads() -> None:
    responses = ResponseCache()
    by_server: dict[str, list[StreamSpec]] = {}
    for spec in STREAMS:
        by_server.setdefault(spec.seedlink, []).append(spec)

    for seedlink_url, specs in by_server.items():
        thread = threading.Thread(
            target=_run_seedlink_group,
            args=(seedlink_url, specs, BROADCASTER, responses),
            name=f"seedlink-{seedlink_url}",
            daemon=True,
        )
        thread.start()


async def main() -> None:
    loop = asyncio.get_running_loop()
    BROADCASTER.attach_loop(loop)
    _start_seedlink_threads()

    stop_event = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except NotImplementedError:
            pass

    async with websockets.serve(_handler, HOST, PORT):
        print(f"FDSN SeedLink relay listening on ws://{HOST}:{PORT}/fdsn-motion")
        await stop_event.wait()


BROADCASTER = MotionBroadcaster()


if __name__ == "__main__":
    asyncio.run(main())
