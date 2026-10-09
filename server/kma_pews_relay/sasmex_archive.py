"""Bounded, off-loop archive of exact SASMEX requests and emitted JSON."""
from __future__ import annotations

import asyncio
from datetime import UTC, datetime
import hashlib
import json
import logging
import os
from pathlib import Path
import re
import tempfile
import time
import zipfile

LOGGER = logging.getLogger("kma_pews_relay.sasmex_archive")
REPORT_NAME = re.compile(r"SASMEX_(\d{8}T\d{6}Z)_([a-f0-9]{64})\.zip\Z")
MAX_INPUT_BYTES = 8 * 1024 * 1024
ALLOWED_FILES = re.compile(
    r"(?:raw/(?:latest|alerts|cap-[A-Za-z0-9_.-]+)\.(?:json|xml)|"
    r"raw/socketio-frame\.txt|raw/firestore-document\.json|"
    r"backup/sasno_realtime\.py|backup/firestore-original\.json|"
    r"connection\.json|parsed\.json|emitted\.json)\Z"
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def atomic_json(path: Path, value) -> None:
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(path)


def pending_size(directory: Path) -> int:
    total = 0
    for path in directory.iterdir():
        try:
            if path.is_file() and not path.is_symlink():
                total += path.stat().st_size
        except FileNotFoundError:
            continue
    return total


class SasmexArchive:
    def __init__(self, directory: str, max_pending_bytes: int = 64 * 1024 * 1024):
        self.directory = Path(directory) if directory else None
        self.max_pending_bytes = max_pending_bytes
        self.queue = asyncio.Queue(maxsize=8)
        self.worker = None
        self.saved = 0
        self.failed = 0
        self.last_error = None
        self.pending_bytes = 0
        self._last_scan = 0.0

    def start(self):
        if self.directory is not None:
            self.worker = asyncio.create_task(self._work(), name="sasmex-archive")

    def submit(self, report: dict, originals: dict[str, bytes]) -> None:
        if self.directory is None:
            return
        if sum(len(value) for value in originals.values()) > MAX_INPUT_BYTES:
            self._failure("original input exceeds 8 MiB; not truncated")
            return
        try:
            self.queue.put_nowait((report, originals))
        except asyncio.QueueFull:
            self._failure("archive queue full; event was not saved")

    def _failure(self, reason: str):
        self.failed += 1
        self.last_error = reason
        LOGGER.error("SASMEX archive failed: %s; failures=%d", reason, self.failed)

    def status(self):
        return {
            "enabled": self.directory is not None,
            "queued": self.queue.qsize(),
            "savedSinceStart": self.saved,
            "failedSinceStart": self.failed,
            "lastError": self.last_error,
        }

    async def _work(self):
        while True:
            item = await self.queue.get()
            try:
                if item is None:
                    return
                path = await asyncio.to_thread(self.write, *item)
                self.saved += 1
                LOGGER.info("SASMEX archive saved: %s", path.name)
            except Exception as error:
                self._failure(type(error).__name__)
            finally:
                self.queue.task_done()

    async def close(self):
        if self.worker is not None:
            await self.queue.put(None)
            await self.worker
            self.worker = None

    def write(self, report: dict, originals: dict[str, bytes]) -> Path:
        if self.directory is None:
            raise ValueError("Archive disabled")
        for name in originals:
            if not ALLOWED_FILES.fullmatch(name):
                raise ValueError(f"Invalid original attachment path: {name}")

        report = dict(report)
        report["originals"] = {
            name: {"size": len(body), "sha256": hashlib.sha256(body).hexdigest()}
            for name, body in originals.items()
        }
        metadata = json.dumps(report, ensure_ascii=False, indent=2).encode("utf-8")
        total = sum(len(value) for value in originals.values()) + len(metadata)
        if total > MAX_INPUT_BYTES:
            raise ValueError("Complete report exceeds 8 MiB; no original data truncated")

        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        now = time.monotonic()
        if now - self._last_scan >= 30 or self.pending_bytes + MAX_INPUT_BYTES > self.max_pending_bytes:
            self.pending_bytes = pending_size(self.directory)
            self._last_scan = now
        required = total + 4096
        if self.pending_bytes + required > self.max_pending_bytes:
            raise OSError("Pending SASMEX archive quota reached; existing records retained")

        stamp_text = str(report.get("eventTimeUtc") or report.get("recordedAtUtc"))
        try:
            stamp = datetime.fromisoformat(stamp_text.replace("Z", "+00:00")).astimezone(UTC)
        except ValueError:
            stamp = datetime.now(UTC)

        fd, temporary_name = tempfile.mkstemp(prefix=".record-", suffix=".tmp", dir=self.directory)
        temporary = Path(temporary_name)
        try:
            with os.fdopen(fd, "w+b") as handle:
                with zipfile.ZipFile(handle, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=3) as archive:
                    archive.writestr("report.json", metadata)
                    for name, body in originals.items():
                        archive.writestr(name, body)
                handle.flush()
                os.fsync(handle.fileno())
            digest = sha256_file(temporary)
            destination = self.directory / f"SASMEX_{stamp.strftime('%Y%m%dT%H%M%SZ')}_{digest}.zip"
            temporary.replace(destination)
            self.pending_bytes += destination.stat().st_size
            return destination
        finally:
            temporary.unlink(missing_ok=True)
