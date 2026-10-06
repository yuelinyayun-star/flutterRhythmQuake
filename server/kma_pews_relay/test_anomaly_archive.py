import asyncio
from datetime import UTC, datetime
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import AsyncMock, patch, MagicMock
import zipfile

from anomaly_archive import AnomalyArchive, REPORT_NAME, sha256_file
from kma_pews_relay import Config, Fetched, KmaRelay, Station
from upload_anomalies import prepare, transfer, upload_batch, validate_manifest


class ArchiveTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.relay = KmaRelay(Config(anomaly_directory=str(self.root / "outbox")))
        self.relay.state.stations = [Station(36.41, 128.94), Station(37.48, 130.89)]
        self.relay.broadcast = AsyncMock()
        self.stamp = datetime(2026, 10, 6, 3, 31, 11, tzinfo=UTC)
        self.relay.anomalies.start()

    async def asyncTearDown(self):
        await self.relay.anomalies.close()
        self.temp.cleanup()

    async def records(self):
        await self.relay.anomalies.queue.join()
        return sorted((self.root / "outbox").glob("*.zip"))

    async def test_screened_frame_preserves_exact_input_and_forwarding(self):
        frame = bytes.fromhex("0000000001")
        table = Fetched(200, bytes.fromhex("a063dbb859"), {"ST": "1791257471", "Set-Cookie": "private"}, .07)
        self.relay._station_input = ("20261006033000", table)
        fetched = Fetched(200, frame, {"ST": "1791257472", "Content-Type": "application/octet-stream"}, .06)
        await self.relay._accept_frame(self.stamp, frame, fetched)
        files = await self.records()
        self.assertEqual(len(files), 1)
        self.assertEqual(REPORT_NAME.fullmatch(files[0].name)[2], sha256_file(files[0]))
        with zipfile.ZipFile(files[0]) as archive:
            self.assertEqual(archive.read("raw/frame.b"), frame)
            self.assertEqual(archive.read("raw/stations.s"), table.body)
            report = json.loads(archive.read("report.json"))
        self.assertEqual(report["decoded"]["rawMmi"], [0, 1])
        self.assertEqual(report["decoded"]["Data"]["mmi"], [-3, -2])
        self.assertEqual(report["decoded"]["clientRejectedStationIndices"], [0])
        self.assertEqual(report["reasons"], ["client_contains_minus3"])
        self.assertTrue(report["relayWillForward"])
        self.assertNotIn("Set-Cookie", report["stationTableUsed"]["headers"])
        self.relay.broadcast.assert_awaited_once()
        message = self.relay.broadcast.call_args.args[0]
        self.assertEqual(set(message), {"type", "source", "Data", "md5"})
        self.assertEqual(message["Data"], self.relay.state.latest_data)

    async def test_high_mmi_alone_is_not_anomaly(self):
        await self.relay._accept_frame(self.stamp, bytes.fromhex("00000000aa"))
        self.assertEqual(await self.records(), [])
        self.assertEqual(self.relay.state.latest_data["mmi"], [11, 11])

    async def test_short_frame_keeps_input_and_null_output(self):
        frame = b"\x01\x02"
        with self.assertRaises(ValueError):
            await self.relay._accept_frame(self.stamp, frame)
        files = await self.records()
        with zipfile.ZipFile(files[0]) as archive:
            self.assertEqual(archive.read("raw/frame.b"), frame)
            report = json.loads(archive.read("report.json"))
        self.assertEqual(report["parseStage"], "header")
        self.assertIsNone(report["decoded"]["header"])
        self.assertIsNone(report["decoded"]["Data"])
        self.relay.broadcast.assert_not_awaited()

    async def test_failed_station_decode_keeps_both_tables(self):
        old = Fetched(200, b"old-original-table", {}, .01)
        self.relay._station_input = ("20261006033000", old)
        attempted = Fetched(200, b"\xff\xff\xff", {"ST": "1791257472"}, .06)
        self.relay.http.fetch = AsyncMock(return_value=attempted)
        frame = bytes.fromhex("8000000001")
        with self.assertRaises(ValueError):
            await self.relay._accept_frame(self.stamp, frame)
        files = await self.records()
        with zipfile.ZipFile(files[0]) as archive:
            self.assertEqual(archive.read("raw/stations.s"), old.body)
            self.assertEqual(archive.read("raw/station_attempt.s"), attempted.body)
            report = json.loads(archive.read("report.json"))
        self.assertEqual(report["parseStage"], "station_table")
        self.assertIn("invalidCoordinate", report["decoded"]["partial"])
        self.relay.broadcast.assert_not_awaited()

    async def test_station_count_failure_retains_partial_levels(self):
        self.relay.state.stations.append(Station(36.0, 127.0))
        self.relay._refresh_station_table = AsyncMock(return_value=True)
        with self.assertRaises(ValueError):
            await self.relay._accept_frame(self.stamp, bytes.fromhex("000000001c"))
        files = await self.records()
        with zipfile.ZipFile(files[0]) as archive:
            report = json.loads(archive.read("report.json"))
        self.assertEqual(report["decoded"]["partial"]["rawMmi"], [1, 12])

    async def test_http_error_records_original_without_fake_decoding(self):
        epoch = self.stamp.timestamp() + 1
        self.relay.clock.update(str(epoch), 0, 0)
        self.relay.clock.now_epoch = lambda: epoch
        self.relay.http.fetch = AsyncMock(return_value=Fetched(502, b"upstream-error-original", {}, .1))
        async def stop(_):
            self.relay.stop_event.set()
        self.relay._sleep_or_stop = stop
        await self.relay.poll_forever()
        files = await self.records()
        with zipfile.ZipFile(files[0]) as archive:
            self.assertEqual(archive.read("raw/frame.b"), b"upstream-error-original")
            report = json.loads(archive.read("report.json"))
        self.assertEqual(report["reasons"], ["upstream_http_error"])
        self.assertEqual(report["frameRequest"]["httpStatus"], 502)
        self.assertIsNone(report["decoded"]["Data"])
        self.relay.broadcast.assert_not_awaited()

    async def test_routine_404_is_not_archived(self):
        epoch = self.stamp.timestamp() + 1
        self.relay.clock.update(str(epoch), 0, 0)
        self.relay.clock.now_epoch = lambda: epoch
        self.relay.http.fetch = AsyncMock(return_value=Fetched(404, b"not-found", {}, .1))
        async def stop(_):
            self.relay.stop_event.set()
        self.relay._sleep_or_stop = stop
        await self.relay.poll_forever()
        self.assertEqual(await self.records(), [])

    async def test_recording_failure_does_not_change_forwarded_data(self):
        self.relay.anomalies.max_pending_bytes = 0
        await self.relay._accept_frame(self.stamp, bytes.fromhex("0000000001"))
        self.assertEqual(await self.records(), [])
        self.relay.broadcast.assert_awaited_once()
        self.assertEqual(self.relay.anomalies.failed, 1)

    async def test_queue_is_bounded_and_failure_visible(self):
        archive = AnomalyArchive(str(self.root / "separate"))
        for _ in range(9):
            archive.submit({"frameUtc": self.stamp.isoformat()}, {"raw/frame.b": b"input"})
        self.assertEqual(archive.queue.qsize(), 8)
        self.assertEqual(archive.failed, 1)
        self.assertIn("queue full", archive.last_error)


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.outbox = self.root / "outbox"
        self.writer = AnomalyArchive(str(self.outbox))
        self.report = {"schemaVersion": 1, "frameUtc": "2026-10-06T03:31:11+00:00", "reasons": ["unit_test"]}
        self.file = self.writer.write(self.report, {"raw/frame.b": b"unit-test-original"})
        self.config = self.root / "telegram.conf"
        self.config.write_text("[tgfs]\ntype=alias\nremote=tgfs-webdav:telegram\n[tgfs-webdav]\ntype=webdav\nurl=http://127.0.0.1:1900/webdav\n", encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def test_batch_preserves_inner_archives_and_restart_identity(self):
        manifest = prepare(self.root)
        self.assertEqual(manifest, prepare(self.root))
        with zipfile.ZipFile(self.root / ".upload.zip") as archive:
            self.assertEqual(archive.read(self.file.name), self.file.read_bytes())
        self.assertTrue(manifest["destination"].startswith("tgfs:KMA异常记录/2026-10-06/"))

    def test_upload_failure_retains_original_records(self):
        with patch("upload_anomalies.transfer", side_effect=ValueError("mismatch")):
            with self.assertRaises(ValueError):
                upload_batch(self.root, self.config)
        self.assertTrue(self.file.exists())
        self.assertTrue((self.root / "transfer.json").exists())
        self.assertFalse((self.root / "last-upload.json").exists())

    def test_verified_upload_cleans_staging_and_reports(self):
        with patch("upload_anomalies.transfer"):
            upload_batch(self.root, self.config)
        self.assertFalse(self.file.exists())
        self.assertFalse((self.root / ".upload.zip").exists())
        self.assertFalse((self.root / "transfer.json").exists())
        self.assertTrue((self.root / "last-upload.json").exists())

    def test_pending_data_changed_is_not_deleted(self):
        prepare(self.root)
        self.file.write_bytes(b"changed")
        with patch("upload_anomalies.transfer"):
            with self.assertRaises(ValueError):
                upload_batch(self.root, self.config)
        self.assertTrue(self.file.exists())

    def test_wrong_destination_or_path_is_rejected(self):
        manifest = prepare(self.root)
        manifest["destination"] = "tgfs:other-folder/file.zip"
        with self.assertRaises(ValueError):
            validate_manifest(manifest)
        manifest["records"][0]["name"] = "../file.zip"
        with self.assertRaises(ValueError):
            validate_manifest(manifest)

    def test_readback_mismatch_and_lost_upload_response(self):
        manifest = prepare(self.root)
        data = (self.root / ".upload.zip").read_bytes()
        process = MagicMock()
        process.__enter__.return_value = process
        process.stdout = io.BytesIO(data)
        process.wait.return_value = 0
        with patch("upload_anomalies.subprocess.run", side_effect=subprocess.CalledProcessError(1, "rclone")), \
                patch("upload_anomalies.subprocess.Popen", return_value=process):
            transfer(self.config, self.root / ".upload.zip", manifest)
        process.stdout = io.BytesIO(b"different")
        with patch("upload_anomalies.subprocess.run"), patch("upload_anomalies.subprocess.Popen", return_value=process):
            with self.assertRaises(ValueError):
                transfer(self.config, self.root / ".upload.zip", manifest)

    def test_wrong_alias_does_not_transfer(self):
        self.config.write_text("[tgfs]\ntype=alias\nremote=local:path\n", encoding="utf-8")
        with patch("upload_anomalies.transfer") as upload:
            with self.assertRaises(ValueError):
                upload_batch(self.root, self.config)
            upload.assert_not_called()


if __name__ == "__main__":
    unittest.main()
