"""Public SASMEX-CIRES CAP feed used by the KMA relay service."""

from __future__ import annotations

import asyncio
import hashlib
import json
import re
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any, Awaitable, Callable, Mapping
from urllib.parse import urljoin

import aiohttp


_CIRCLE_RE = re.compile(
    r"^\s*([+-]?\d+(?:\.\d+)?)\s*,\s*"
    r"([+-]?\d+(?:\.\d+)?)(?:\s+([+-]?\d+(?:\.\d+)?))?\s*$"
)


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _children(element: ET.Element, name: str) -> list[ET.Element]:
    return [child for child in element if _local_name(child.tag) == name]


def _first(element: ET.Element | None, name: str) -> ET.Element | None:
    if element is None:
        return None
    for child in element.iter():
        if child is not element and _local_name(child.tag) == name:
            return child
    return None


def _text(element: ET.Element | None, name: str) -> str | None:
    child = _first(element, name)
    if child is None or child.text is None:
        return None
    value = child.text.strip()
    return value or None


def _parse_circle(value: str | None) -> dict[str, float] | None:
    if not value:
        return None
    match = _CIRCLE_RE.match(value)
    if match is None:
        return None
    latitude = float(match.group(1))
    longitude = float(match.group(2))
    radius = float(match.group(3)) if match.group(3) else None
    result: dict[str, float] = {
        "latitude": latitude,
        "longitude": longitude,
    }
    if radius is not None:
        result["radiusKm"] = radius
    return result


def _nonempty_texts(element: ET.Element | None, name: str) -> list[str]:
    if element is None:
        return []
    values: list[str] = []
    for child in _children(element, name):
        if child.text is None:
            continue
        value = child.text.strip()
        if value:
            values.append(value)
    return values


def _sasmex_alert_issued(response_type: str | None) -> bool:
    """Return whether CAP confirms an alert action was issued."""

    normalized = (response_type or "").strip().lower()
    return normalized in {"execute", "shelter", "evacuate"}


def parse_alert_summary(payload: Mapping[str, Any]) -> dict[str, Any]:
    """Keep the public list response unchanged while normalizing its fields."""

    references = []
    for reference in payload.get("references") or []:
        if not isinstance(reference, Mapping):
            continue
        normalized: dict[str, Any] = {}
        for source_key, target_key in (
            ("id", "id"),
            ("is_event", "isEvent"),
            ("region", "region"),
            ("states", "states"),
            ("time", "time"),
        ):
            if source_key in reference:
                normalized[target_key] = reference[source_key]
        if normalized:
            references.append(normalized)

    return {
        "id": str(payload.get("id") or ""),
        "isEvent": bool(payload.get("is_event")),
        "references": references,
        "region": payload.get("region"),
        "states": list(payload.get("states") or []),
        "time": payload.get("time"),
    }


def parse_cap_xml(xml_text: str) -> dict[str, Any]:
    """Parse CAP XML into structured JSON fields for the client payload."""

    root = ET.fromstring(xml_text)
    alert = root if _local_name(root.tag) == "alert" else _first(root, "alert")
    if alert is None:
        raise ValueError("CAP XML does not contain an alert element")
    info = _first(alert, "info")
    if info is None:
        raise ValueError("CAP XML does not contain an info element")

    event_codes = []
    for code in _children(info, "eventCode"):
        name = _text(code, "valueName")
        value = _text(code, "value")
        if name is not None or value is not None:
            event_codes.append({"valueName": name, "value": value})

    parameters = []
    for parameter in _children(info, "parameter"):
        name = _text(parameter, "valueName")
        value = _text(parameter, "value")
        if name is not None or value is not None:
            parameters.append({"valueName": name, "value": value})

    areas = []
    for area in _children(info, "area"):
        circles = _nonempty_texts(area, "circle")
        polygons = _nonempty_texts(area, "polygon")
        points = _nonempty_texts(area, "point")
        areas.append(
            {
                "areaDesc": _text(area, "areaDesc"),
                "circles": [
                    {"raw": value, "data": _parse_circle(value)}
                    for value in circles
                ],
                "points": points,
                "polygons": polygons,
            }
        )

    return {
        "identifier": _text(alert, "identifier"),
        "sender": _text(alert, "sender"),
        "sent": _text(alert, "sent"),
        "status": _text(alert, "status"),
        "msgType": _text(alert, "msgType"),
        "scope": _text(alert, "scope"),
        "language": _text(info, "language"),
        "category": _text(info, "category"),
        "event": _text(info, "event"),
        "responseType": _text(info, "responseType"),
        "urgency": _text(info, "urgency"),
        "severity": _text(info, "severity"),
        "certainty": _text(info, "certainty"),
        "effective": _text(info, "effective"),
        "expires": _text(info, "expires"),
        "senderName": _text(info, "senderName"),
        "headline": _text(info, "headline"),
        "description": _text(info, "description"),
        "instruction": _text(info, "instruction"),
        "web": _text(info, "web"),
        "contact": _text(info, "contact"),
        "eventCodes": event_codes,
        "parameters": parameters,
        "areas": areas,
    }


def _fingerprint(summary: Mapping[str, Any], cap: Mapping[str, Any]) -> str:
    value = {
        "summary": summary,
        "cap": cap,
    }
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        .encode("utf-8")
    ).hexdigest()


def to_client_payload(
    summary: Mapping[str, Any], cap: Mapping[str, Any]
) -> dict[str, Any]:
    """Convert CAP into a compact JSON payload containing real SASMEX fields."""

    raw_areas = [
        area for area in cap.get("areas", []) if isinstance(area, Mapping)
    ]
    areas: list[dict[str, Any]] = []
    for area in raw_areas:
        item: dict[str, Any] = {}
        area_desc = area.get("areaDesc")
        if area_desc:
            item["name"] = area_desc

        circles = []
        for circle in area.get("circles", []):
            if not isinstance(circle, Mapping):
                continue
            circle_item: dict[str, Any] = {}
            raw = circle.get("raw")
            data = circle.get("data")
            if raw:
                circle_item["raw"] = raw
            if isinstance(data, Mapping):
                circle_item.update(data)
            if circle_item:
                circles.append(circle_item)
        if circles:
            item["circles"] = circles

        points = [value for value in area.get("points", []) if value]
        if points:
            item["points"] = points
        polygons = [value for value in area.get("polygons", []) if value]
        if polygons:
            item["polygons"] = polygons
        if item:
            areas.append(item)

    response_type = cap.get("responseType")
    alert_issued = _sasmex_alert_issued(response_type)
    event_id = str(summary.get("id") or "")
    payload: dict[str, Any] = {
        "source": "sasmex",
        "id": event_id,
        "eventId": event_id,
        "sasmexAlertIssued": alert_issued,
        "sasmexAlertAction": response_type,
        "msgType": cap.get("msgType"),
        "time": summary.get("time"),
        "sent": cap.get("sent"),
        "effective": cap.get("effective"),
        "expires": cap.get("expires"),
        "event": cap.get("event"),
        "headline": cap.get("headline"),
        "description": cap.get("description"),
        "category": cap.get("category"),
        "urgency": cap.get("urgency"),
        "severity": cap.get("severity"),
        "certainty": cap.get("certainty"),
        "region": summary.get("region"),
        "states": list(summary.get("states") or []),
        "areas": areas,
    }
    references = list(summary.get("references") or [])
    if references:
        payload["references"] = references
    return {key: value for key, value in payload.items() if value is not None}


@dataclass(frozen=True)
class SasmexConfig:
    base_url: str
    poll_seconds: float
    timeout_seconds: float
    stale_after_seconds: float


@dataclass
class SasmexState:
    latest_event: dict[str, Any] | None = None
    latest_fingerprint: str | None = None
    last_poll_at: datetime | None = None
    last_change_at: datetime | None = None
    last_error: str | None = None
    consecutive_failures: int = 0
    accepted_updates: int = 0

    def snapshot(self) -> dict[str, Any]:
        return {
            "source": "sasmex",
            "Data": self.latest_event,
            "lastPollAtUtc": self.last_poll_at.isoformat()
            if self.last_poll_at
            else None,
            "lastChangeAtUtc": self.last_change_at.isoformat()
            if self.last_change_at
            else None,
            "fingerprint": self.latest_fingerprint,
        }

    def health(self, stale_after_seconds: float) -> dict[str, Any]:
        age = None
        if self.last_poll_at is not None:
            age = max(0.0, (datetime.now(UTC) - self.last_poll_at).total_seconds())
        healthy = age is not None and age <= stale_after_seconds and self.last_error is None
        return {
            "status": "ok" if healthy else "degraded",
            "healthy": healthy,
            "lastPollAtUtc": self.last_poll_at.isoformat()
            if self.last_poll_at
            else None,
            "lastChangeAtUtc": self.last_change_at.isoformat()
            if self.last_change_at
            else None,
            "lastPollAgeSeconds": round(age, 3) if age is not None else None,
            "lastError": self.last_error,
            "consecutiveFailures": self.consecutive_failures,
            "acceptedUpdates": self.accepted_updates,
            "latestEventId": (self.latest_event or {}).get("id"),
        }


class SasmexFeed:
    def __init__(
        self,
        config: SasmexConfig,
        on_update: Callable[[dict[str, Any]], Awaitable[None]],
    ) -> None:
        self.config = config
        self.on_update = on_update
        self.state = SasmexState()
        self.session: aiohttp.ClientSession | None = None

    async def start(self) -> None:
        timeout = aiohttp.ClientTimeout(total=self.config.timeout_seconds)
        connector = aiohttp.TCPConnector(limit=2, ttl_dns_cache=300)
        self.session = aiohttp.ClientSession(
            timeout=timeout,
            connector=connector,
            headers={
                "User-Agent": "RhythmQuake-SASMEX-Relay/1.0",
                "Accept": "application/json, text/xml, */*",
                "Cache-Control": "no-cache",
            },
        )

    async def close(self) -> None:
        if self.session is not None:
            await self.session.close()
            self.session = None

    async def _get(self, path: str) -> tuple[int, bytes, str]:
        if self.session is None:
            raise RuntimeError("SASMEX HTTP client hasn't been started")
        url = urljoin(f"{self.config.base_url.rstrip('/')}/", path.lstrip("/"))
        try:
            async with self.session.get(url) as response:
                return response.status, await response.read(), response.headers.get(
                    "Content-Type", ""
                )
        except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
            raise ConnectionError(f"GET {url} failed: {exc}") from exc

    async def poll_once(self) -> dict[str, Any] | None:
        now = datetime.now(UTC)
        status, body, _ = await self._get("/api/v1/alerts/latest/")
        if status != 200:
            raise ConnectionError(f"SASMEX latest endpoint returned HTTP {status}")
        try:
            summary_payload = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError("SASMEX latest response is not valid UTF-8 JSON") from exc
        if not isinstance(summary_payload, dict):
            raise ValueError("SASMEX latest response is not an object")
        summary = parse_alert_summary(summary_payload)
        if not summary["id"]:
            raise ValueError("SASMEX latest response has no event id")

        cap_status, cap_body, _ = await self._get(
            f"/api/v1/alerts/{summary['id']}/cap/"
        )
        if cap_status != 200:
            raise ConnectionError(
                f"SASMEX CAP endpoint returned HTTP {cap_status} for {summary['id']}"
            )
        try:
            cap_xml = cap_body.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ValueError("SASMEX CAP response is not UTF-8") from exc
        cap = parse_cap_xml(cap_xml)
        event = to_client_payload(summary, cap)
        fingerprint = _fingerprint(summary, cap)
        self.state.last_poll_at = now
        self.state.last_error = None
        self.state.consecutive_failures = 0
        if fingerprint == self.state.latest_fingerprint:
            return None

        self.state.latest_event = event
        self.state.latest_fingerprint = fingerprint
        self.state.last_change_at = now
        self.state.accepted_updates += 1
        await self.on_update(event)
        return event

    async def poll_forever(self, stop_event: asyncio.Event) -> None:
        while not stop_event.is_set():
            try:
                await self.poll_once()
            except Exception as exc:
                self.state.last_error = str(exc)
                self.state.consecutive_failures += 1
            try:
                await asyncio.wait_for(
                    stop_event.wait(), timeout=self.config.poll_seconds
                )
            except TimeoutError:
                pass
