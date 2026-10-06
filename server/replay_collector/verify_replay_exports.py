"""Bounded, independent content verification of original replay checkpoints."""
from __future__ import annotations

import argparse
import base64
from collections import Counter, OrderedDict
import gzip
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import time
import zlib


def canonical(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")


class JsonStream:
    """Use the standard JSON parser for each value with bounded read-ahead."""
    def __init__(self, file):
        self.file, self.buffer, self.position, self.eof = file, "", 0, False
        self.decoder = json.JSONDecoder()

    def fill(self):
        chunk = self.file.read(65536)
        self.buffer = self.buffer[self.position:] + chunk
        self.position = 0
        self.eof = not chunk

    def peek(self):
        while True:
            while self.position < len(self.buffer) and self.buffer[self.position].isspace():
                self.position += 1
            if self.position < len(self.buffer):
                return self.buffer[self.position]
            if self.eof:
                return ""
            self.fill()

    def take(self, token):
        if self.peek() != token:
            raise ValueError(f"Expected JSON token {token!r}")
        self.position += 1

    def value(self):
        self.peek()
        while True:
            try:
                result, end = self.decoder.raw_decode(self.buffer, self.position)
                if end == len(self.buffer) and not self.eof:
                    self.fill()
                    continue
                self.position = end
                return result
            except json.JSONDecodeError:
                if self.eof:
                    raise
                self.fill()

    def array(self, accept):
        self.take("[")
        while self.peek() != "]":
            accept(self.value())
            if self.peek() == "]":
                break
            self.take(",")
        self.take("]")

    def object(self, accept):
        self.take("{")
        while self.peek() != "}":
            key = self.value()
            if not isinstance(key, str):
                raise ValueError("Invalid JSON object key")
            self.take(":")
            accept(key)
            if self.peek() == "}":
                break
            self.take(",")
        self.take("}")


def fingerprint(node, reference):
    if isinstance(node, list):
        if not node or not (node[0] == "l" or (node[0] == "m" and len(node) % 2 == 1)):
            raise ValueError("Invalid archive node")
        value = [node[0], *(reference(index).hex() for index in node[1:])]
    else:
        if isinstance(node, dict):
            raise ValueError("Invalid archive scalar")
        value = node
    return hashlib.sha256(canonical(value)).digest()


class DiskFingerprints:
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.execute("PRAGMA cache_size=-4096")
        self.db.execute("PRAGMA journal_mode=OFF")
        self.db.execute("PRAGMA synchronous=OFF")
        self.db.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, hash BLOB NOT NULL)")
        self.cache = OrderedDict()
        self.count = 0

    def reference(self, index):
        if type(index) is not int or index < 0 or index >= self.count:
            raise ValueError("Invalid archive reference")
        result = self.cache.pop(index, None)
        if result is None:
            result = self.db.execute("SELECT hash FROM nodes WHERE id=?", (index,)).fetchone()[0]
        self.cache[index] = result
        if len(self.cache) > 65536:
            self.cache.popitem(last=False)
        return result

    def append(self, node):
        digest = fingerprint(node, self.reference)
        self.db.execute("INSERT INTO nodes VALUES (?,?)", (self.count, digest))
        self.cache[self.count] = digest
        self.count += 1
        if len(self.cache) > 65536:
            self.cache.popitem(last=False)


def stored_hashes(archive):
    hashes = []
    def reference(index):
        if type(index) is not int or index < 0 or index >= len(hashes):
            raise ValueError("Invalid checkpoint reference")
        return hashes[index]
    for node in archive["nodes"]:
        hashes.append(fingerprint(node, reference))
    return Counter(reference(root) for root in archive["frames"])


def compressed_block_content(block):
    compressed = base64.b64decode(block["data"], validate=True)
    if hashlib.sha256(compressed).hexdigest() != block["sha256"]:
        raise ValueError("Station block checksum mismatch")
    decoder = zlib.decompressobj(31)
    limit = 128 * 1024 * 1024
    raw = decoder.decompress(compressed, limit + 1)
    if len(raw) > limit or not decoder.eof or decoder.unused_data:
        raise ValueError("Invalid or oversized compressed station block")
    archive = json.loads(raw)
    if archive.get("format") != "station-json-table-v1":
        raise ValueError("Invalid compressed station table")
    nodes = archive["nodes"]
    expected = [[nodes[fields(nodes, root)["receivedAt"]],
                 nodes[fields(nodes, fields(nodes, root)["snapshot"])["kind"]]]
                for root in archive["frames"]]
    if block["frames"] != expected:
        raise ValueError("Station block index changed")
    return raw, archive


def compressed_block_hashes(block):
    _, archive = compressed_block_content(block)
    return stored_hashes(archive)


def fields(nodes, root):
    node = nodes[root]
    if not isinstance(node, list) or not node or node[0] != "m":
        raise ValueError("Invalid checkpoint frame")
    return {nodes[node[i]]: node[i + 1] for i in range(1, len(node), 2)}


def verify_file(path: Path, audit: Path) -> dict:
    remaining = Counter()
    remaining_blocks = Counter()
    archive_format = None
    metadata = {}
    with tempfile.TemporaryDirectory(prefix="rq-replay-verify-") as temporary:
        table = DiskFingerprints(Path(temporary) / "hashes.sqlite")
        try:
            with path.open(encoding="utf-8") as file:
                stream = JsonStream(file)
                def archive_field(key):
                    nonlocal archive_format
                    if key == "nodes":
                        stream.array(table.append)
                    elif key == "frames":
                        stream.array(lambda root: remaining.update([table.reference(root)]))
                    elif key == "format":
                        archive_format = stream.value()
                        if archive_format not in ("station-json-table-v1", "station-json-gzip-blocks-v1"):
                            raise ValueError("Invalid archive format")
                    elif key == "blocks":
                        def block_value(block):
                            raw, _ = compressed_block_content(block)
                            remaining_blocks.update([hashlib.sha256(raw).digest()])
                        stream.array(block_value)
                    else:
                        raise ValueError("Unexpected station archive field")
                def outer_field(key):
                    if key == "stationArchive":
                        stream.object(archive_field)
                    else:
                        metadata[key] = stream.value()
                stream.object(outer_field)
                if stream.peek():
                    raise ValueError("Trailing JSON content")
        finally:
            table.db.close()
    if metadata.get("format") != "rhythmquake-replay" or metadata.get("version") not in (1, 2):
        raise ValueError("Invalid replay format")
    first = metadata["reports"][0]
    key = hashlib.sha256(canonical([first["source"], first["eventId"]])).hexdigest()
    manifest = json.loads((audit / key / "event.json").read_text(encoding="utf-8"))
    raw = Counter(canonical(report["sourcePayload"]) for report in metadata["reports"])
    expected = Counter(canonical(report["sourcePayload"]) for report in manifest["group"]["reports"])
    if raw != expected:
        raise ValueError("Original reports changed")
    counts = Counter()
    chunks = sorted((audit / key).glob("*.stations.json"))
    chunks += [audit / "chunks" / name for name in manifest.get("chunks", [])]
    for chunk in chunks:
        raw = gzip.decompress(chunk.read_bytes()) if chunk.suffix == ".gz" else chunk.read_bytes()
        archive = json.loads(raw)
        if archive_format == "station-json-gzip-blocks-v1":
            digest = hashlib.sha256(raw).digest()
            if remaining_blocks[digest] <= 0:
                raise ValueError("Original checkpoint JSON bytes changed")
            remaining_blocks[digest] -= 1
        else:
            for digest, count in stored_hashes(archive).items():
                if remaining[digest] < count:
                    raise ValueError("Checkpoint station JSON changed")
                remaining[digest] -= count
        nodes = archive["nodes"]
        for root in archive["frames"]:
            snapshot = fields(nodes, root)["snapshot"]
            counts[nodes[fields(nodes, snapshot)["kind"]]] += 1
    if any(remaining.values()) or any(remaining_blocks.values()):
        raise ValueError("Extra station frames in export")
    with path.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    return {"epoch": time.time(), "phase": "verified", "origin": "independent-python-stream",
            "name": path.name, "source": first["source"], "frames": dict(counts), "sha256": digest}


def verify_directory(root: Path) -> list[dict]:
    return [verify_file(path, root / "audit") for path in sorted((root / "outbox").glob("*.rqreplay"))]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(verify_directory(args.root), ensure_ascii=False))
