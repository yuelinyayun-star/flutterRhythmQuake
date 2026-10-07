from __future__ import annotations

import asyncio
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from sasmex_archive import SasmexArchive


class SasmexArchiveTest(unittest.TestCase):
    def test_record_contains_raw_requests_parsed_and_emitted_json(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = SasmexArchive(str(root / "outbox"))
            report = {
                "schemaVersion": 1,
                "source": "sasmex",
                "recordedAtUtc": "2026-10-07T06:00:00+00:00",
                "eventTimeUtc": "2026-10-07T05:59:58-06:00",
                "eventId": "20261007055958",
                "requests": [{"method": "GET", "path": "/api/v1/alerts/latest/"}],
            }
            originals = {
                "raw/latest.json": b'{"id":"20261007055958"}',
                "raw/alerts.json": b'{"alerts":[]}',
                "raw/cap-20261007055958.xml": b"<feed/>",
                "parsed.json": json.dumps({"id": "20261007055958"}).encode("utf-8"),
                "emitted.json": json.dumps({"type": "update"}).encode("utf-8"),
            }
            path = archive.write(report, originals)
            with zipfile.ZipFile(path) as saved:
                self.assertEqual(
                    set(saved.namelist()),
                    {"report.json", *originals},
                )
                manifest = json.loads(saved.read("report.json"))
                self.assertEqual(manifest["eventId"], "20261007055958")
                self.assertEqual(
                    manifest["originals"]["raw/latest.json"]["size"],
                    len(originals["raw/latest.json"]),
                )
                self.assertEqual(saved.read("raw/cap-20261007055958.xml"), b"<feed/>")

    def test_submit_is_bounded_and_runs_off_loop(self) -> None:
        async def run() -> None:
            with tempfile.TemporaryDirectory() as temporary:
                archive = SasmexArchive(str(Path(temporary) / "outbox"))
                archive.start()
                archive.submit(
                    {
                        "recordedAtUtc": "2026-10-07T06:00:00+00:00",
                        "eventTimeUtc": "2026-10-07T06:00:00+00:00",
                        "eventId": "event",
                    },
                    {
                        "parsed.json": b"{}",
                        "emitted.json": b"{}",
                    },
                )
                await archive.queue.join()
                self.assertEqual(archive.saved, 1)
                self.assertEqual(archive.failed, 0)
                await archive.close()

        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
