"""Mirror published public GitHub assets into the verified Telegram remote."""
from __future__ import annotations

import argparse
import configparser
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from urllib.request import Request, urlopen

REPO = "yuelinyayun-star/flutterRhythmQuake"
API = f"https://api.github.com/repos/{REPO}"
FOLDER = "RhythmQuake公开版"
TAG = re.compile(r"v(\d+\.\d+\.\d+\.\d+)-public\Z")
MAX_ASSET = 512 * 1024 * 1024
CHUNK = 1024 * 1024


def api(path: str):
    request = Request(API + path, headers={"Accept": "application/vnd.github+json",
                      "User-Agent": "RhythmQuake-release-mirror"})
    with urlopen(request, timeout=30) as response:
        raw = response.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024:
        raise ValueError("GitHub metadata exceeds limit")
    return json.loads(raw)


def atomic_json(path: Path, value) -> None:
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(path)


def validate_config(config: Path) -> None:
    parser = configparser.ConfigParser(interpolation=None)
    with config.open(encoding="utf-8") as handle:
        parser.read_file(handle)
    if (parser["tgfs"].get("type") != "alias"
            or parser["tgfs"].get("remote") != "tgfs-webdav:telegram"
            or parser["tgfs-webdav"].get("type") != "webdav"
            or parser["tgfs-webdav"].get("url", "").rstrip("/")
            != "http://127.0.0.1:1900/webdav"):
        raise ValueError("Not the verified loopback Telegram remote")


def asset_info(release, asset):
    match = TAG.fullmatch(release.get("tag_name", ""))
    if not match or release.get("draft") or release.get("prerelease"):
        raise ValueError("Not a published public release")
    version = match[1]
    names = {f"RhythmQuake_Setup_{version}_public_x64.exe": "Windows",
             f"RhythmQuake_{version}_public.apk": "Android",
             f"RhythmQuake_{version}_public_linux_x64.tar.gz": "Linux",
             f"RhythmQuake_{version}_public_web.zip": "Web"}
    name = asset.get("name", "")
    base = name.removesuffix(".sha256")
    if base not in names:
        return None
    expected_url = f"https://github.com/{REPO}/releases/download/{release['tag_name']}/{name}"
    checksum = asset.get("digest", "")
    if (asset.get("browser_download_url") != expected_url
            or asset.get("state") != "uploaded"
            or not isinstance(asset.get("id"), int)
            or not isinstance(asset.get("size"), int)
            or not 0 < asset["size"] <= MAX_ASSET
            or not re.fullmatch(r"sha256:[a-f0-9]{64}", checksum)):
        raise ValueError("Asset URL, size, state or SHA-256 is invalid")
    return names[base], checksum[7:]


def file_hash(path: Path) -> str:
    with path.open("rb") as handle:
        return hash_stream(handle)[0]


def hash_stream(handle):
    result = hashlib.sha256()
    size = 0
    while block := handle.read(CHUNK):
        size += len(block)
        result.update(block)
    return result.hexdigest(), size


def download(asset, checksum: str, path: Path) -> None:
    if path.is_file() and path.stat().st_size == asset["size"] and file_hash(path) == checksum:
        return
    # A single reusable staging file bounds disk consumption across failures.
    path.unlink(missing_ok=True)
    if shutil.disk_usage(path.parent).free < asset["size"] + 128 * CHUNK:
        raise OSError("Insufficient staging disk space")
    request = Request(asset["browser_download_url"], headers={"User-Agent": "RhythmQuake-release-mirror"})
    value = hashlib.sha256()
    size = 0
    with urlopen(request, timeout=120) as response, path.open("wb") as output:
        while block := response.read(CHUNK):
            size += len(block)
            if size > asset["size"]:
                raise ValueError("GitHub download exceeded declared size")
            output.write(block)
            value.update(block)
        output.flush()
        os.fsync(output.fileno())
    if size != asset["size"] or value.hexdigest() != checksum:
        raise ValueError("GitHub download checksum mismatch")


def command(config: Path, *args):
    return ["/usr/bin/rclone", *args, "--config", str(config), "--retries", "1",
            "--low-level-retries", "1", "--contimeout", "10s", "--timeout", "120s",
            "--buffer-size", "1M", "--transfers", "1", "--checkers", "1",
            "--multi-thread-streams", "0"]


def transfer_environment():
    env = {k: v for k, v in os.environ.items()
           if k.lower() not in {"http_proxy", "https_proxy", "all_proxy"}}
    env["NO_PROXY"] = "127.0.0.1,localhost"
    return env


def upload(config: Path, local: Path, remote: str, checksum: str, size: int) -> None:
    try:
        subprocess.run(command(config, "copyto", str(local), remote, "--immutable", "--no-traverse"),
                       env=transfer_environment(), stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=True, timeout=1800)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        # A lost upload response is recoverable only after identical readback.
        pass
    with subprocess.Popen(command(config, "cat", remote, "--count", str(size + 1)),
                          env=transfer_environment(), stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL) as process:
        try:
            actual, actual_size = hash_stream(process.stdout)
            status = process.wait(timeout=10)
        except BaseException:
            process.kill()
            process.wait()
            raise
    if status or actual != checksum or actual_size != size:
        raise ValueError("Telegram readback not verified; staging retained")


def select_releases(state):
    if "since" not in state:
        release = api("/releases/latest")
        if not TAG.fullmatch(release.get("tag_name", "")):
            raise ValueError("Latest release is not a public version")
        state["since"] = release["published_at"]
        return [release]
    releases = []
    for page in range(1, 21):
        batch = api(f"/releases?per_page=100&page={page}")
        if not isinstance(batch, list):
            raise ValueError("Invalid GitHub releases response")
        releases.extend(r for r in batch if not r.get("draft") and not r.get("prerelease")
                        and TAG.fullmatch(r.get("tag_name", ""))
                        and r.get("published_at", "") >= state["since"])
        if len(batch) < 100:
            return sorted(releases, key=lambda r: r["published_at"])
    raise ValueError("Release pagination limit reached; no silent truncation")


def mirror(config: Path, directory: Path) -> None:
    validate_config(config)
    state_path = directory / "state.json"
    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else {"assets": {}}
    releases = select_releases(state)
    atomic_json(state_path, state)
    uploaded = skipped = 0
    for release in releases:
        for asset in release["assets"]:
            info = asset_info(release, asset)
            if info is None:
                continue
            platform, checksum = info
            destination = f"tgfs:{FOLDER}/{release['tag_name']}/{platform}/{asset['name']}"
            key = str(asset["id"])
            identity = {"sha256": checksum, "size": asset["size"], "destination": destination}
            if all(state["assets"].get(key, {}).get(k) == v for k, v in identity.items()):
                skipped += 1
                continue
            print(f"Archiving {release['tag_name']}/{platform}/{asset['name']}", flush=True)
            staging = directory / "download.part"
            download(asset, checksum, staging)
            upload(config, staging, destination, checksum, asset["size"])
            identity["verified_at"] = datetime.now(timezone.utc).isoformat()
            state["assets"][key] = identity
            atomic_json(state_path, state)
            staging.unlink()
            uploaded += 1
            print(f"Verified {asset['name']} SHA256={checksum}", flush=True)
    print(f"Complete: uploaded={uploaded} already_verified={skipped}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path("/etc/rhythmquake-release-mirror/telegram.conf"))
    parser.add_argument("--state-dir", type=Path, default=Path("/var/lib/rhythmquake-release-mirror"))
    args = parser.parse_args()
    import fcntl
    try:
        with (args.state_dir / ".lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            mirror(args.config, args.state_dir)
        return 0
    except BlockingIOError:
        print("Another mirror is active", flush=True)
        return 0
    except Exception as error:
        # Network/config response text can contain credentials. Log type only.
        print(f"Archive incomplete ({type(error).__name__}); retry next timer run", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
