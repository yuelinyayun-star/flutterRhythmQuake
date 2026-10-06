"""Upload the private outbox through YuelinCloud's Telegram remote, not FUSE.

Uses the existing server-side rclone config. Never copies credentials into
RhythmQuake, calls a public upload endpoint, or falls back to local storage.
"""
from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlsplit


FOLDER = "RhythmQuake回放文件夹"
NAME = re.compile(r"RhythmQuake_[a-f0-9]{64}_([a-f0-9]{64})\.rqreplay\Z")


def discover(config: Path) -> tuple[str, Path]:
    # Verified deployment: FileBrowser's Telegram source is tgfs: (an alias),
    # not the unfinished managedstorage registry in the older local snapshot.
    parser = configparser.ConfigParser(interpolation=None)
    with config.open(encoding="utf-8") as handle:
        parser.read_file(handle)
    alias = parser["tgfs"]
    if alias.get("type") != "alias" or alias.get("remote") != "tgfs-webdav:telegram":
        raise ValueError("Expected the verified tgfs Telegram alias")
    remote = parser["tgfs-webdav"]
    endpoint = urlsplit(remote.get("url", ""))
    if (remote.get("type") != "webdav" or endpoint.scheme != "http"
            or endpoint.hostname != "127.0.0.1" or endpoint.port != 1900
            or endpoint.path.rstrip("/") != "/webdav" or endpoint.query
            or endpoint.fragment or endpoint.username is not None):
        raise ValueError("Expected the verified loopback TGFS gateway")
    return "tgfs", config


def digest(handle) -> str:
    value = hashlib.sha256()
    while block := handle.read(1024 * 1024):
        value.update(block)
    return value.hexdigest()


def run_rclone(config: Path, *args: str, output=None) -> None:
    # rclone errors may contain credential-bearing URLs. Never relay stderr.
    command = [os.environ.get("RQ_RCLONE", "/usr/bin/rclone"), *args,
               "--config", str(config), "--retries", "1",
               "--low-level-retries", "1", "--contimeout", "10s",
               "--timeout", "120s"]
    environment = {key: value for key, value in os.environ.items()
                   if key.lower() not in {"http_proxy", "https_proxy", "all_proxy"}}
    environment["NO_PROXY"] = "127.0.0.1,localhost"
    result = subprocess.run(command, stdout=output or subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, env=environment,
                            timeout=1800, check=False)
    if result.returncode:
        raise RuntimeError(f"Telegram transfer failed (exit {result.returncode}); retained")


def upload_file(file: Path, config: Path, connection_id: str) -> None:
    match = NAME.fullmatch(file.name)
    if match is None or file.is_symlink() or not file.is_file():
        raise ValueError("Not a collector-owned replay package")
    with file.open("rb") as handle:
        local_hash = digest(handle)
    if local_hash != match[1]:
        raise ValueError("Local replay checksum mismatch; retained")
    if connection_id != "tgfs":
        raise ValueError("Only the verified Telegram remote is supported")
    destination = f"tgfs:{FOLDER}/{file.name}"
    # Direct WebDAV upload bypasses rclone's asynchronous FUSE write cache.
    # --immutable prevents replacement of an existing different remote object.
    try:
        run_rclone(config, "copyto", str(file), destination, "--immutable", "--no-traverse")
    except (RuntimeError, subprocess.TimeoutExpired):
        # A prior attempt may have committed remotely but lost its response.
        # Only a byte-identical remote readback can recover that outcome.
        pass
    with tempfile.TemporaryFile() as downloaded:
        run_rclone(config, "cat", destination, "--count", str(file.stat().st_size + 1),
                   output=downloaded)
        downloaded.seek(0)
        if digest(downloaded) != local_hash:
            raise ValueError("Telegram gateway readback mismatch; retained")
    # Recheck before unlinking: another writer must not replace a pending file.
    with file.open("rb") as handle:
        if digest(handle) != local_hash:
            raise ValueError("Local replay changed during upload; retained")
    receipt = file.with_suffix(".uploaded.json")
    temporary = receipt.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump({"connectionId": connection_id, "provider": "telegram",
                   "path": f"/{FOLDER}/{file.name}", "sha256": local_hash},
                  handle, ensure_ascii=False)
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(receipt)
    file.unlink()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path,
                        default=Path("/etc/rhythmquake-collector/telegram.conf"))
    parser.add_argument("--outbox", type=Path, default=Path("/var/lib/rhythmquake-collector/outbox"))
    parser.add_argument("--inspect", action="store_true")
    args = parser.parse_args()
    try:
        connection_id, config = discover(args.config)
        if args.inspect:
            print(json.dumps({"provider": "telegram", "connectionId": connection_id,
                              "config": str(config), "folder": FOLDER}, ensure_ascii=False))
            return 0
        # A timer must never run two uploaders against the same outbox.
        import fcntl
        with (args.outbox / ".upload.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for file in sorted(args.outbox.glob("*.rqreplay")):
                upload_file(file, config, connection_id)
                print(f"Verified Telegram gateway upload: {file.name}", flush=True)
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.TimeoutExpired):
        # Do not print registry/config content, tokens, or server response text.
        print("Upload not verified. Pending replays retained; check Telegram connection/config.", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
