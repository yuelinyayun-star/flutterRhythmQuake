"""Full primary route checks with untouched October 6/16 document responses."""
import asyncio
from datetime import UTC, datetime, timedelta
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from kma_pews_relay import Config, KmaRelay
from sasno_realtime import SasnoRealtimeFeed, SasnoRealtimeFetched

FIXTURES = Path(__file__).with_name('test_fixtures')
OLD = (FIXTURES / 'sasmex_firestore_20261008.original.json').read_bytes()
OCT16 = (FIXTURES / 'sasno_firestore_20261016.original.json').read_bytes()
EVENT_TIME = datetime(2026, 10, 16, 11, 40, 11, tzinfo=UTC)

class SasnoPrimaryTest(unittest.IsolatedAsyncioTestCase):
    async def test_original_document_reaches_existing_ws_and_exact_archive(self):
        self.assertEqual(hashlib.sha256(OCT16).hexdigest(),
            '72b44c5f5cc7e2a667905a0ea0b6a34472b00b2a1b572aedad72a75f3c68adef')
        with tempfile.TemporaryDirectory() as directory:
            relay = KmaRelay(Config(sasmex_archive_directory=directory))
            self.assertIsInstance(relay.sasno_realtime, SasnoRealtimeFeed)
            feed = relay.sasno_realtime
            clock = [EVENT_TIME + timedelta(seconds=15)]
            feed._clock = lambda: clock[0]
            originals = [OLD, OCT16, OCT16, OLD]
            async def get():
                return SasnoRealtimeFetched(feed.config.document_url, 200,
                    originals.pop(0), {'content-type':'application/json'}, .25, clock[0].isoformat())
            feed._get = get
            messages = []
            async def broadcast(message): messages.append(message)
            relay.broadcast_sasmex = broadcast
            relay.sasmex_archive.start()
            try:
                self.assertIsNone(await feed.poll_once())
                self.assertIsNone(feed.client_event())
                event = await feed.poll_once()
                self.assertEqual(event['id'], '1792150811000')
                self.assertEqual(event['severity'], 'Minor')
                self.assertEqual(event['msgType'], 'Alert')
                self.assertNotIn('msgTypeOrigin', event)
                self.assertFalse(event['isWarn'])
                self.assertEqual((event['lat'], event['lng']), (15.1385, -92.46365))
                self.assertIsNone(await feed.poll_once())
                self.assertIsNone(await feed.poll_once())
                self.assertEqual(len(messages), 1)
                self.assertEqual(messages[0], {'type':'update','source':'sasmex','Data':event})
                self.assertEqual(feed.client_event(), event)
                clock[0] = EVENT_TIME + timedelta(minutes=3)
                self.assertIsNone(feed.client_event())
                await relay.sasmex_archive.queue.join()
                paths = list(Path(directory).glob('*.zip'))
                self.assertEqual(len(paths), 1)
                with zipfile.ZipFile(paths[0]) as z:
                    self.assertEqual(z.read('raw/firestore-document.json'), OCT16)
                    report = json.loads(z.read('report.json'))
                    self.assertTrue(report['publishedToApp'])
                    self.assertEqual(report['transport'], 'firestore')
                    self.assertEqual(report['eventTimeUtc'], '2026-10-16T11:40:11+00:00')
                    self.assertEqual(json.loads(z.read('emitted.json')), messages[0])
            finally:
                await relay.sasmex_archive.close()

    async def test_changed_old_document_does_not_reappear_as_new_warning(self):
        async def ignore(event): self.fail('stale event was published')
        relay = KmaRelay(Config())
        feed = relay.sasno_realtime
        feed.on_update = ignore
        feed._clock = lambda: EVENT_TIME + timedelta(days=1)
        originals = [OLD, OCT16]
        async def get():
            return SasnoRealtimeFetched(feed.config.document_url, 200, originals.pop(0), {}, 0,
                                       feed._clock().isoformat())
        feed._get = get
        self.assertIsNone(await feed.poll_once())
        self.assertIsNone(await feed.poll_once())
        self.assertEqual(feed.state.ignored_old_events, 1)
        self.assertIsNone(feed.client_event())

    async def test_429_respects_retry_after_and_health_does_not_count_a_success(self):
        relay=KmaRelay(Config())
        feed=relay.sasno_realtime
        original=(FIXTURES/'sasmex_firestore_429_20261012.original.json').read_bytes()
        stop=asyncio.Event()
        async def get():
            stop.set()
            return SasnoRealtimeFetched(feed.config.document_url,429,original,
                {'Retry-After':'180'},0,datetime.now(UTC).isoformat())
        feed._get=get
        await feed.poll_forever(stop)
        self.assertEqual(feed.state.retry_delay_seconds,180)
        self.assertEqual(feed.state.consecutive_failures,1)
        self.assertIsNone(feed.state.last_poll_at)
        self.assertIsNone(feed.client_event())

if __name__ == '__main__': unittest.main()
