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
        self.assertEqual(len(files), 1)
        with zipfile.ZipFile(files[0]) as record:
            report = json.loads(record.read('report.json'))
            source = json.loads(record.read('parsed.json'))['SASNOEVENTDATA']
            self.assertEqual(record.read('raw/firestore-document.json'), self.original)
            self.assertEqual(report['recordKind'], 'baseline')
            self.assertFalse(report['publishedToApp'])
            self.assertEqual(source['unix'], 1791259786)
            self.assertEqual(source['epicenter']['latitude'], 16.29569)
            self.assertNotIn('severity', source)
            self.assertNotIn('grado', source)
            self.assertNotIn('lat', source)
        self.assertEqual(self.monitor.fs['changes'], 0)
        self.assertEqual(self.monitor.fs['unchangedPolls'], 1)
        self.assertEqual(before, hashlib.sha256(self.original).hexdigest())
        self.assertEqual((self.root / 'firestore-baseline.original.json').read_bytes(), self.original)

    async def test_failed_http_preserves_actual_body_and_has_no_success(self):
        with self.assertRaises(ConnectionError):
            self.monitor.process_firestore(self.fetched(status=503))
        with self.assertRaises(ConnectionError):
            self.monitor.process_firestore(self.fetched(status=503))
        await self.monitor.archive.queue.join()
        files = list((self.root / 'outbox').glob('*.zip'))
        self.assertEqual(len(files), 1)
        with zipfile.ZipFile(files[0]) as record:
            self.assertEqual(record.read('raw/firestore-document.json'), self.original)
            self.assertEqual(json.loads(record.read('report.json'))['httpStatus'], 503)
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
        for file in (self.root / 'outbox').glob('*.zip'):
            with zipfile.ZipFile(file) as record:
                self.assertFalse(json.loads(record.read('report.json'))['publishedToApp'])
                self.assertEqual(json.loads(record.read('report.json'))['recordKind'], 'transport-frame')
        manifest = prepare(self.root, COMPARISON_FOLDER)
        validate_manifest(manifest, COMPARISON_FOLDER)
        self.assertIn('/双连接对照/', manifest['destination'])
        self.assertEqual(len(manifest['records']), 3)
        with self.assertRaises(ValueError):
            validate_manifest(manifest, COMPARISON_FOLDER + '/../')

if __name__ == '__main__':
    unittest.main()
