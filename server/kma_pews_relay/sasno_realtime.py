"""SASNO Firebase event document feed used by the relay."""

from __future__ import annotations

import asyncio
import copy
import hashlib
import json
import time
import unicodedata
from collections import OrderedDict
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any, Awaitable, Callable, Mapping

import aiohttp


_SEVERITY_WORDS = {
    "leve": 1,
    "ligero": 1,
    "ligera": 1,
    "moderado": 2,
    "moderada": 2,
    "medio": 2,
    "media": 2,
    "fuerte": 3,
    "intenso": 3,
    "intensa": 3,
    "severo": 3,
    "severa": 3,
    "mayor": 3,
    "extremo": 3,
    "extrema": 3,
    "grave": 3,
    "alto": 3,
    "alta": 3,
    "menor": 1,
    "debil": 1,
    "baja": 1,
    "bajo": 1,
    "considerable": 2,
    "sensible": 2,
    "riesgoso": 3,
    "riesgosa": 3,
    "riesgo": 3,
    "critico": 3,
    "critica": 3,
}

_DISPLAY_SEVERITY_LEVELS = {
    5: {
        "EXTREME", "EXTREMO", "EXTREMA", "CATASTROPHIC",
        "CATASTROFICO", "CATASTRÓFICO",
    },
    4: {"STRONG", "SEVERE", "VIOLENT", "FUERTE", "SEVERO", "SEVERA", "VIOLENTO", "VIOLENTA"},
    3: {"MODERATE", "MODERADO", "MODERADA", "MODERATED"},
    2: {"LIGHT", "WEAK", "MILD", "LEVE", "LEVES", "LIGERO", "LIGERA", "LIGEROS", "LIGERAS"},
    1: {
        "IMPERCEPTIBLE", "MINIMAL", "NEGLIGIBLE", "VERY LIGHT", "MUY LEVE",
        "MINIMO", "MÍNIMO", "MINIMA", "MÍNIMA",
    },
}


def _firestore_value(value: Mapping[str, Any]) -> Any:
    """Convert one Firestore REST Value without changing its value."""

    if "nullValue" in value:
        return None
    if "stringValue" in value:
        return value["stringValue"]
    if "integerValue" in value:
        return int(value["integerValue"])
    if "doubleValue" in value:
        return float(value["doubleValue"])
    if "booleanValue" in value:
        return bool(value["booleanValue"])
    if "timestampValue" in value:
        return value["timestampValue"]
    if "referenceValue" in value:
        return value["referenceValue"]
    if "bytesValue" in value:
        return value["bytesValue"]
    if "geoPointValue" in value:
        return dict(value["geoPointValue"])
    if "mapValue" in value:
        fields = value["mapValue"].get("fields") or {}
        return {
            key: _firestore_value(item)
            for key, item in fields.items()
            if isinstance(item, Mapping)
        }
    if "arrayValue" in value:
        return [
            _firestore_value(item)
            for item in value["arrayValue"].get("values", [])
            if isinstance(item, Mapping)
        ]
    return None


def parse_firestore_document(payload: Mapping[str, Any]) -> dict[str, Any]:
    fields = payload.get("fields") or {}
    if not isinstance(fields, Mapping):
        raise ValueError("SASNO Firestore response has no fields object")
    return {
        key: _firestore_value(value)
        for key, value in fields.items()
        if isinstance(value, Mapping)
    }


def _number(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if result == result else None


def _word_level(value: str, mapping: Mapping[str, int], default: int) -> int:
    normalized = " ".join(value.strip().lower().split())
    if not normalized:
        return default
    if normalized in mapping:
        return mapping[normalized]
    return max(
        (level for word, level in mapping.items() if word in normalized),
        default=default,
    )


def _web_grado(value: str) -> int:
    """Match the SASNO web app's kI() mapping exactly."""

    normalized = "".join(
        char
        for char in unicodedata.normalize("NFD", value.strip().lower())
        if unicodedata.category(char) != "Mn"
    )
    if not normalized:
        return 2
    return _word_level(normalized, _SEVERITY_WORDS, 2)


def _web_severidad(value: str) -> int:
    """Match the SASNO web app's PI() exact-text mapping exactly."""

    normalized = value.strip().upper()
    for level, values in _DISPLAY_SEVERITY_LEVELS.items():
        if normalized in values:
            return level
    return 0


def _event_time_ms(value: Any) -> tuple[int, int]:
    try:
        unix = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("SASNO event has no valid unix timestamp") from exc
    if unix <= 0:
        raise ValueError("SASNO event has a non-positive unix timestamp")
    return (unix * 1000 if unix < 1_000_000_000_000 else unix, unix)


def parse_sasno_event(document: Mapping[str, Any]) -> dict[str, Any]:
    source = document.get("SASNOEVENTDATA") or document.get("sasnoeventdata") or document
    if not isinstance(source, Mapping):
        raise ValueError("SASNO event payload is not an object")

    epoch_ms, unix = _event_time_ms(source.get("unix"))
    epicenter = source.get("epicenter") or source.get("epicentro") or {}
    if not isinstance(epicenter, Mapping):
        epicenter = {}
    latitude = _number(epicenter.get("latitude", epicenter.get("lat")))
    longitude = _number(epicenter.get("longitude", epicenter.get("lng")))
    region = str(source.get("region") or "").strip() or "Desconocido"
    intensity = str(source.get("intensity") or source.get("intensidad") or "").strip()
    raw_severity = str(source.get("severity") or "").strip()
    grade = _web_grado(intensity)
    # Our WS schema uses CAP-style severity names. Firestore provides intensity
    # instead; derive the same three levels as the webpage without changing raw.
    severity = raw_severity or ({1: "Minor", 2: "Moderate", 3: "Severe"}[grade] if intensity else "")
    is_warn = severity.casefold() == "severe"
    event: dict[str, Any] = {
        "source": "sasmex",
        "id": str(epoch_ms),
        "eventId": str(epoch_ms),
        "epochMs": epoch_ms,
        "region": region,
        "lat": latitude if region.lower() != "desconocido" and latitude is not None else None,
        "lng": longitude if region.lower() != "desconocido" and longitude is not None else None,
        "intensidad": intensity or "Sin dato",
        "grado": grade,
        "severidad": _web_severidad(intensity),
        "isWarn": is_warn,
        "original": copy.deepcopy(dict(source)),
    }
    if severity:
        event["severity"] = severity
        event["severityOrigin"] = "severity" if raw_severity else "intensity"
    return event


@dataclass(frozen=True)
class SasnoRealtimeConfig:
    project_id: str
    poll_seconds: float
    timeout_seconds: float
    stale_after_seconds: float

    @property
    def document_url(self) -> str:
        return (
            "https://firestore.googleapis.com/v1/projects/"
            f"{self.project_id}/databases/(default)/documents/app/events"
        )


@dataclass(frozen=True)
class SasnoRealtimeFetched:
    url: str
    status: int
    body: bytes
    headers: dict[str, str]
    round_trip_seconds: float
    received_at_utc: str


@dataclass
class SasnoRealtimeState:
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


class SasnoRealtimeFeed:
    """Poll the same public Firestore document the SASNO web app observes."""

    def __init__(
        self,
        config: SasnoRealtimeConfig,
        on_update: Callable[[dict[str, Any]], Awaitable[None]],
    ) -> None:
        self.config = config
        self.on_update = on_update
        self.state = SasnoRealtimeState()
        self.session: aiohttp.ClientSession | None = None
        self._seen = OrderedDict[str, None]()
        self._baseline_initialized = False

    async def start(self) -> None:
        timeout = aiohttp.ClientTimeout(total=self.config.timeout_seconds)
        connector = aiohttp.TCPConnector(limit=1, ttl_dns_cache=300)
        self.session = aiohttp.ClientSession(
            timeout=timeout,
            connector=connector,
            headers={
                "User-Agent": "RhythmQuake-SASNO-Realtime/1.0",
                "Accept": "application/json",
                "Cache-Control": "no-cache",
                "Pragma": "no-cache",
            },
        )

    async def close(self) -> None:
        if self.session is not None:
            await self.session.close()
            self.session = None

    async def _get(self) -> SasnoRealtimeFetched:
        if self.session is None:
            raise RuntimeError("SASNO realtime feed is not started")
        started = time.monotonic()
        async with self.session.get(
            self.config.document_url,
            params={"_": str(time.time_ns())},
        ) as response:
            body = await response.read()
            return SasnoRealtimeFetched(
                url=str(response.url),
                status=response.status,
                body=body,
                headers={
                    key: value
                    for key, value in response.headers.items()
                    if key.lower() in {"content-type", "date", "etag", "last-modified"}
                },
                round_trip_seconds=time.monotonic() - started,
                received_at_utc=datetime.now(UTC).isoformat(),
            )

    async def poll_once(self) -> dict[str, Any] | None:
        now = datetime.now(UTC)
        self.state.last_poll_at = now
        self.state.last_error = None
        self.state.consecutive_failures = 0
        fetched = await self._get()
        if fetched.status != 200:
            raise ConnectionError(
                f"SASNO Firestore event document returned HTTP {fetched.status}"
            )
        try:
            raw_document = json.loads(fetched.body.decode("utf-8"))
            document = parse_firestore_document(raw_document)
            event = parse_sasno_event(document)
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
            raise ValueError(f"Invalid SASNO Firestore event document: {exc}") from exc

        fingerprint = hashlib.sha256(
            json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode(
                "utf-8"
            )
        ).hexdigest()
        self.state.latest_event = event
        self.state.latest_fingerprint = fingerprint
        if not self._baseline_initialized:
            self._baseline_initialized = True
            self._seen[fingerprint] = None
            return None
        if fingerprint in self._seen:
            return None
        self._seen[fingerprint] = None
        while len(self._seen) > 64:
            self._seen.popitem(last=False)
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
