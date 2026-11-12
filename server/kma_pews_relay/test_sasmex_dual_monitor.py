"""Regression checks using immutable, actually captured upstream bytes."""
import asyncio
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from sasmex_dual_monitor import DualMonitor, now_utc
from sasno_realtime import SasnoRealtimeFetched
from unittest.mock import AsyncMock
from sasmex_dual_monitor import retry_after_seconds
from upload_sasmex import COMPARISON_FOLDER, prepare, validate_manifest

FIXTURES = Path(__file__).with_name('test_fixtures')

class DualMonitorTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.monitor = DualMonitor(self.root)
        self.monitor.archive.start()
        self.original = (FIXTURES / 'sasmex_firestore_20261008.original.json').read_bytes()

    async def asyncTearDown(self):
        await self.monitor.archive.close()
        self.temporary.cleanup()

    def fetched(self, status=200):
        return SasnoRealtimeFetched(self.monitor.fs['endpoint'], status, self.original,
                                     {'content-type': 'application/json'}, .1, now_utc())

    async def test_old_firestore_baseline_is_exact_and_never_published_or_repeated(self):
        before = hashlib.sha256(self.original).hexdigest()
        self.monitor.process_firestore(self.fetched())
        self.monitor.process_firestore(self.fetched())
        await self.monitor.archive.queue.join()
        files = list((self.root / 'outbox').glob('*.zip'))
        self.assertEqual(files, [])
        self.assertEqual(self.monitor.fs['changes'], 0)
        self.assertEqual(self.monitor.fs['unchangedPolls'], 1)
        self.assertEqual(before, hashlib.sha256(self.original).hexdigest())
        self.assertEqual((self.root / 'firestore-baseline.original.json').read_bytes(), self.original)

    async def test_failed_http_preserves_actual_body_locally_and_has_no_upload(self):
        original = (FIXTURES / 'sasmex_firestore_429_20261012.original.json').read_bytes()
        fetched = SasnoRealtimeFetched(self.monitor.fs['endpoint'], 429, original,
                                      {'content-type': 'application/json'}, .1, now_utc())
        with self.assertRaises(ConnectionError):
            self.monitor.process_firestore(fetched)
        with self.assertRaises(ConnectionError):
            self.monitor.process_firestore(fetched)
        await self.monitor.archive.queue.join()
        files = list((self.root / 'outbox').glob('*.zip'))
        self.assertEqual(files, [])
        self.assertEqual((self.root / 'firestore-error.original.json').read_bytes(), original)
        self.assertEqual(json.loads((self.root / 'firestore-error.json').read_text(encoding='utf-8'))['httpStatus'], 429)
        self.assertIsNone(self.monitor.fs['lastSuccessAtUtc'])

    async def test_actual_engine_handshakes_are_not_business_or_eew(self):
        for name in ['sidesis_handshake_20261008.original.frame',
                     'sidesis_namespace_20261008.original.frame',
                     'sidesis_ping_20261008.original.frame']:
            original = (FIXTURES / name).read_bytes()
            self.monitor.process_io_frame(original)
            await self.monitor.archive.queue.join()
        self.assertEqual(self.monitor.io['frames'], 3)
        self.assertEqual(self.monitor.io['businessFrames'], 0)
        self.assertEqual(self.monitor.io['eligibleEewFrames'], 0)
        self.assertEqual(self.monitor.io['transportFrames'], 3)
        self.assertIsNone(prepare(self.root, COMPARISON_FOLDER))

    async def test_operational_states_cannot_enter_upload_outbox(self):
        for kind in ['connecting', 'connected', 'disconnected', 'connection-status',
                     'connection-error', 'invalid-response', 'recovered', 'implementation-backup',
                     'stopped', 'transport-frame']:
            self.monitor.record('both', kind)
        await self.monitor.archive.queue.join()
        self.assertIsNone(prepare(self.root, COMPARISON_FOLDER))

    async def test_business_archive_preserves_real_document_and_verified_manifest(self):
        # Exercise storage with captured bytes; no source values are changed and
        # no synthetic earthquake is injected into the observer or APP.
        self.monitor.record('firestore', 'change', {'raw/firestore-document.json': self.original})
        await self.monitor.archive.queue.join()
        manifest = prepare(self.root, COMPARISON_FOLDER)
        validate_manifest(manifest, COMPARISON_FOLDER)
        self.assertIn('/双连接对照/2026-10-06/', manifest['destination'])
        self.assertEqual(len(manifest['records']), 1)
        file = self.root / 'outbox' / manifest['records'][0]['name']
        with zipfile.ZipFile(file) as record:
            self.assertEqual(record.read('raw/firestore-document.json'), self.original)
            metadata=json.loads(record.read('report.json'))
            self.assertFalse(metadata['publishedToApp'])
            self.assertEqual(metadata['eventTimeUtc'], '2026-10-06T04:09:46+00:00')
            self.assertEqual(metadata['eventDateBasis'], 'SASNOEVENTDATA.unix')
        with self.assertRaises(ValueError):
            validate_manifest(manifest, COMPARISON_FOLDER + '/../')

    async def test_restart_reuses_snapshot_and_does_not_upload_old_document(self):
        self.monitor.process_firestore(self.fetched())
        other = DualMonitor(self.root)
        other.process_firestore(self.fetched())
        self.assertEqual(other.fs['changes'], 0)
        self.assertEqual(other.fs['unchangedPolls'], 1)
        self.assertEqual(other.archive.queue.qsize(), 0)

    async def test_health_snapshot_only_updates_local_file(self):
        async def stop_after_snapshot(seconds):
            self.monitor.stop.set()
        self.monitor.wait = stop_after_snapshot
        await self.monitor.periodic_health()
        status = json.loads((self.root / 'connection-status.json').read_text(encoding='utf-8'))
        self.assertEqual(status['archivePolicy'], 'earthquake-content-only')
        self.assertIsNone(prepare(self.root, COMPARISON_FOLDER))

    async def test_quota_errors_back_off_and_success_resets_interval(self):
        original = (FIXTURES / 'sasmex_firestore_429_20261012.original.json').read_bytes()
        error = SasnoRealtimeFetched(self.monitor.fs['endpoint'], 429, original, {}, .1, now_utc())
        self.monitor.firestore._get = AsyncMock(side_effect=[error, error, error, self.fetched(), error])
        delays = []
        async def collect_delay(seconds):
            delays.append(seconds)
            if len(delays) == 5:
                self.monitor.stop.set()
        self.monitor.wait = collect_delay
        await self.monitor.poll_firestore()
        self.assertEqual(delays, [60, 120, 240, 5, 60])
        self.assertEqual(self.monitor.fs['consecutiveFailures'], 1)
        self.assertIsNone(prepare(self.root, COMPARISON_FOLDER))

    async def test_network_errors_have_bounded_backoff_and_clear_http_status(self):
        self.monitor.fs['lastStatus'] = 429
        self.monitor.firestore._get = AsyncMock(side_effect=TimeoutError('network timeout'))
        delays = []
        async def collect_delay(seconds):
            delays.append(seconds)
            if len(delays) == 10:
                self.monitor.stop.set()
        self.monitor.wait = collect_delay
        await self.monitor.poll_firestore()
        self.assertEqual(delays[:4], [5, 10, 20, 40])
        self.assertEqual(delays[-1], 300)
        self.assertIsNone(self.monitor.fs['lastStatus'])

    def test_retry_after_accepts_seconds_and_http_date(self):
        from datetime import UTC, datetime, timedelta
        from email.utils import format_datetime
        self.assertEqual(retry_after_seconds({'Retry-After': '1200'}), 1200)
        future = format_datetime(datetime.now(UTC) + timedelta(seconds=1200), usegmt=True)
        self.assertGreater(retry_after_seconds({'retry-after': future}), 1198)
        for value in ['invalid', '-1', 'nan', 'inf']:
            self.assertEqual(retry_after_seconds({'Retry-After': value}), 0)

if __name__ == '__main__':
    unittest.main()
