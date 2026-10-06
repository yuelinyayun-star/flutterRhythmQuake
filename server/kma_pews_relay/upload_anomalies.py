"""Batch pending KMA evidence into the verified Telegram cloud, with readback."""
from __future__ import annotations

import argparse
import configparser
from datetime import UTC, datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

from anomaly_archive import REPORT_NAME, atomic_json, sha256_file

FOLDER = "KMA异常记录"
MAX_BATCH_BYTES = 8 * 1024 * 1024


def validate_manifest(manifest, folder=FOLDER):
    if folder not in {FOLDER, FOLDER + "/验证"}:
        raise ValueError("Unexpected archive folder")
    entries = manifest["records"]
    if not isinstance(entries, list) or not 1 <= len(entries) <= 120:
        raise ValueError("Invalid retained batch")
    matches = []
    for entry in entries:
        match = REPORT_NAME.fullmatch(entry["name"])
        if not match or match[2] != entry["sha256"] or not 0 < entry["size"] <= MAX_BATCH_BYTES:
            raise ValueError("Invalid retained record")
        matches.append(match)
    day = matches[0][1][:8]
    if any(match[1][:8] != day for match in matches) or len({entry["name"] for entry in entries}) != len(entries):
        raise ValueError("Invalid retained dates or duplicate records")
    date = f"{day[:4]}-{day[4:6]}-{day[6:8]}"
    checksum = manifest["sha256"]
    destination = f"tgfs:{folder}/{date}/KMA_{matches[0][1]}_{matches[-1][1]}_{checksum}.zip"
    if (not isinstance(checksum, str) or not re.fullmatch(r"[a-f0-9]{64}", checksum)
            or manifest["destination"] != destination
            or not 0 < manifest["size"] <= MAX_BATCH_BYTES + 128 * 1024):
        raise ValueError("Invalid retained destination or size")


def validate_config(path: Path):
    parser = configparser.ConfigParser(interpolation=None)
    with path.open(encoding="utf-8") as handle:
        parser.read_file(handle)
    if (parser["tgfs"].get("type") != "alias"
            or parser["tgfs"].get("remote") != "tgfs-webdav:telegram"
            or parser["tgfs-webdav"].get("type") != "webdav"
            or parser["tgfs-webdav"].get("url", "").rstrip("/") != "http://127.0.0.1:1900/webdav"):
        raise ValueError("Not the verified loopback Telegram remote")


def prepare(directory: Path, folder=FOLDER):
    manifest_path = directory / "transfer.json"
    archive_path = directory / ".upload.zip"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        validate_manifest(manifest, folder)
        if (not archive_path.is_file() or archive_path.is_symlink()
                or archive_path.stat().st_size != manifest["size"]
                or sha256_file(archive_path) != manifest["sha256"]):
            raise ValueError("Retained transfer archive changed or missing")
        return manifest
    entries = []
    size = 0
    day = None
    for path in sorted((directory / "outbox").glob("*.zip")):
        match = REPORT_NAME.fullmatch(path.name)
        if not match or path.is_symlink() or not path.is_file():
            raise ValueError("Unexpected pending record")
        if day is not None and match[1][:8] != day:
            break
        if entries and (len(entries) >= 120 or size + path.stat().st_size > MAX_BATCH_BYTES):
            break
        checksum = sha256_file(path)
        if checksum != match[2] or path.stat().st_size > MAX_BATCH_BYTES:
            raise ValueError("Pending record checksum or size invalid")
        day = match[1][:8]
        entries.append({"name": path.name, "sha256": checksum, "size": path.stat().st_size})
        size += path.stat().st_size
    if not entries:
        return None
    temporary = directory / ".upload.tmp"
    with temporary.open("w+b") as handle:
        # Each inner record is already compressed. Store it intact, not recompressed.
        with zipfile.ZipFile(handle, "w", compression=zipfile.ZIP_STORED) as archive:
            for entry in entries:
                archive.write(directory / "outbox" / entry["name"], entry["name"])
            archive.writestr("index.json", json.dumps({"schemaVersion": 1, "records": entries}, indent=2))
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(archive_path)
    checksum = sha256_file(archive_path)
    first = REPORT_NAME.fullmatch(entries[0]["name"])[1]
    last = REPORT_NAME.fullmatch(entries[-1]["name"])[1]
    name = f"KMA_{first}_{last}_{checksum}.zip"
    date = f"{day[:4]}-{day[4:6]}-{day[6:8]}"
    manifest = {"sha256": checksum, "size": archive_path.stat().st_size,
                "destination": f"tgfs:{folder}/{date}/{name}", "records": entries}
    validate_manifest(manifest, folder)
    atomic_json(manifest_path, manifest)
    return manifest


def command(config, *args):
    return ["/usr/bin/rclone", *args, "--config", str(config), "--retries", "1",
            "--low-level-retries", "1", "--contimeout", "10s", "--timeout", "120s",
            "--buffer-size", "1M", "--transfers", "1", "--checkers", "1", "--multi-thread-streams", "0"]


def transfer(config: Path, archive: Path, manifest: dict):
    env = {key: value for key, value in os.environ.items()
           if key.lower() not in {"http_proxy", "https_proxy", "all_proxy"}}
    env["NO_PROXY"] = "127.0.0.1,localhost"
    try:
        subprocess.run(command(config, "copyto", str(archive), manifest["destination"], "--immutable", "--no-traverse"),
                       env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600, check=True)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        pass
    with subprocess.Popen(command(config, "cat", manifest["destination"], "--count", str(manifest["size"] + 1)),
                          env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
        checksum = hashlib.sha256()
        size = 0
        try:
            while block := process.stdout.read(1024 * 1024):
                checksum.update(block)
                size += len(block)
            status = process.wait(timeout=10)
        except BaseException:
            process.kill()
            process.wait()
            raise
    if status or checksum.hexdigest() != manifest["sha256"] or size != manifest["size"]:
        raise ValueError("Telegram readback mismatch; pending evidence retained")


def upload_batch(directory: Path, config: Path, folder=FOLDER):
    validate_config(config)
    manifest = prepare(directory, folder)
    if manifest is None:
        print("No pending KMA anomaly records", flush=True)
        return
    transfer(config, directory / ".upload.zip", manifest)
    # A restart after remote commit may find some records already deleted.
    for entry in manifest["records"]:
        if not REPORT_NAME.fullmatch(entry["name"]):
            raise ValueError("Invalid retained record name")
        path = directory / "outbox" / entry["name"]
        if path.exists() and (path.is_symlink() or sha256_file(path) != entry["sha256"]):
            raise ValueError("Pending evidence changed; not deleted")
    atomic_json(directory / "last-upload.json", {"verifiedAtUtc": datetime.now(UTC).isoformat(), **manifest})
    for entry in manifest["records"]:
        (directory / "outbox" / entry["name"]).unlink(missing_ok=True)
    # Remove the manifest first; a crash leaves only a replaceable staging file.
    (directory / "transfer.json").unlink()
    (directory / ".upload.zip").unlink(missing_ok=True)
    print(f"Verified Telegram KMA batch: records={len(manifest['records'])} "
          f"bytes={manifest['size']} path={manifest['destination']} SHA256={manifest['sha256']}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=Path, default=Path("/var/lib/rhythmquake-kma-anomalies"))
    parser.add_argument("--config", type=Path, default=Path("/etc/rhythmquake-kma-anomalies/telegram.conf"))
    parser.add_argument("--validation", action="store_true", help="use the separate validation folder, not production evidence")
    args = parser.parse_args()
    import fcntl
    try:
        with (args.directory / ".upload.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            upload_batch(args.directory, args.config, FOLDER + "/验证" if args.validation else FOLDER)
        return 0
    except BlockingIOError:
        return 0
    except Exception as error:
        print(f"KMA anomaly upload failed ({type(error).__name__}); evidence retained", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
