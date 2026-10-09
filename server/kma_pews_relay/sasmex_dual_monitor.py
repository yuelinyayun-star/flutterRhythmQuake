"""Read-only comparison observer. This service never publishes APP events."""
from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime
import hashlib
import json
import logging
from pathlib import Path
import signal

import websockets

from sasmex_archive import SasmexArchive, atomic_json
from sasno_realtime import SasnoRealtimeConfig, SasnoRealtimeFeed, parse_firestore_document
from sidesis_realtime import parse_socket_io_frame, parse_sidesis_message, socket_url_with_engine_query

IO_URL = 'wss://sidesis.iigea.org/socket.io/?EIO=4&transport=websocket'

def now_utc():
    return datetime.now(UTC).isoformat()

def json_bytes(value):
    return json.dumps(value, ensure_ascii=False, indent=2).encode('utf-8')

async def never_publish(*args):
    raise RuntimeError('Comparison observer must not publish APP events')


class DualMonitor:
    def __init__(self, directory: Path, *, project='sasno-d79e1', io_url=IO_URL,
                 poll_seconds=1.0, health_seconds=60.0):
        self.directory = directory
        self.io_url = socket_url_with_engine_query(io_url)
        self.poll_seconds = poll_seconds
        self.health_seconds = health_seconds
        self.archive = SasmexArchive(str(directory / 'outbox'))
        self.firestore = SasnoRealtimeFeed(SasnoRealtimeConfig(project, poll_seconds, 20, 90), never_publish)
        self.stop = asyncio.Event()
        self.started_at = now_utc()
        self.session_id = self.started_at
        self.io = dict(endpoint=self.io_url, connected=False, attempts=0, frames=0,
                       businessFrames=0, eligibleEewFrames=0, newEewContents=0,
                       lastFrameAtUtc=None, lastBusinessAtUtc=None, lastError=None)
        self.fs = dict(endpoint=self.firestore.config.document_url, connected=False,
                       polls=0, successfulPolls=0, changes=0, unchangedPolls=0,
                       lastAttemptAtUtc=None, lastSuccessAtUtc=None, lastChangeAtUtc=None,
                       lastStatus=None, lastError=None, originalSha256=None,
                       contentSha256=None, sourceUpdateTime=None, sourceUnix=None)
        self._fs_fingerprint = None
        self._fs_error = None
        self._io_seen = set()

    def record(self, transport, kind, originals=None, **details):
        self.archive.submit(dict(schemaVersion=1, sessionId=self.session_id,
                                 recordedAtUtc=now_utc(), transport=transport,
                                 recordKind=kind, publishedToApp=False, **details), originals or {})

    def health(self):
        stamp = datetime.now(UTC)
        def with_age(state, field, threshold):
            result = dict(state)
            text = state.get(field)
            age = (stamp - datetime.fromisoformat(text)).total_seconds() if text else None
            result['lastSuccessAgeSeconds'] = round(age, 3) if age is not None else None
            result['healthy'] = bool(state['connected'] and age is not None and age < threshold)
            return result
        return dict(schemaVersion=1, role='comparison-only', appTransport='existing-sidesis-ws',
                    firestorePublishedToApp=False, startedAtUtc=self.started_at, recordedAtUtc=stamp.isoformat(),
                    socketIo=with_age(self.io, 'lastFrameAtUtc', 90),
                    firestore=with_age(self.fs, 'lastSuccessAtUtc', 90), archive=self.archive.status())

    async def wait(self, seconds):
        try:
            await asyncio.wait_for(self.stop.wait(), seconds)
        except TimeoutError:
            pass

    def process_firestore(self, fetched):
        """Decode received bytes unchanged; never use the legacy EEW adapter."""
        self.fs['lastStatus'] = fetched.status
        raw_hash = hashlib.sha256(fetched.body).hexdigest()
        request = dict(endpoint=fetched.url, httpStatus=fetched.status,
                       responseHeaders=fetched.headers, receivedAtUtc=fetched.received_at_utc,
                       roundTripSeconds=fetched.round_trip_seconds, originalSha256=raw_hash)
        try:
            if fetched.status != 200:
                raise ConnectionError(f'HTTP {fetched.status}')
            raw = json.loads(fetched.body.decode('utf-8'))
            if not isinstance(raw, dict) or not isinstance(raw.get('fields'), dict):
                raise ValueError('Firestore response has no fields object')
            decoded = parse_firestore_document(raw)
        except Exception as error:
            # Retain actual failed response once per distinct response/error; counters remain in health.
            signature = (fetched.status, raw_hash, str(error))
            if signature != self._fs_error:
                self.record('firestore', 'invalid-response', {'raw/firestore-document.json': fetched.body},
                            error=str(error), **request)
            self._fs_error = signature
            raise
        fingerprint = hashlib.sha256(json.dumps(raw, ensure_ascii=False, sort_keys=True,
                                                separators=(',', ':')).encode('utf-8')).hexdigest()
        self.fs.update(connected=True, lastSuccessAtUtc=fetched.received_at_utc,
                       lastError=None, successfulPolls=self.fs['successfulPolls'] + 1,
                       originalSha256=raw_hash, contentSha256=fingerprint,
                       sourceUpdateTime=raw.get('updateTime'))
        source = decoded.get('SASNOEVENTDATA', decoded.get('sasnoeventdata', decoded))
        self.fs['sourceUnix'] = source.get('unix') if isinstance(source, dict) else None
        if fingerprint != self._fs_fingerprint:
            baseline = self._fs_fingerprint is None
            attachments = {'raw/firestore-document.json': fetched.body, 'parsed.json': json_bytes(decoded)}
            self.record('firestore', 'baseline' if baseline else 'change', attachments,
                        contentSha256=fingerprint, previousContentSha256=self._fs_fingerprint, **request)
            if not baseline:
                self.fs['changes'] += 1
                self.fs['lastChangeAtUtc'] = fetched.received_at_utc
            self._fs_fingerprint = fingerprint
            if baseline:
                # Exact response is retained on the server as well as in Telegram evidence.
                (self.directory / 'firestore-baseline.original.json').write_bytes(fetched.body)
        else:
            self.fs['unchangedPolls'] += 1
        if self._fs_error is not None:
            self.record('firestore', 'recovered', **request)
        self._fs_error = None

    async def poll_firestore(self):
        while not self.stop.is_set():
            self.fs['polls'] += 1
            self.fs['lastAttemptAtUtc'] = now_utc()
            try:
                fetched = await self.firestore._get()
                self.process_firestore(fetched)
            except Exception as error:
                message = f'{type(error).__name__}: {error}'
                if self.fs['lastError'] != message:
                    self.record('firestore', 'connection-error', error=message, endpoint=self.fs['endpoint'])
                self.fs.update(connected=False, lastError=message)
            await self.wait(self.poll_seconds)

    def process_io_frame(self, raw):
        original = raw if isinstance(raw, bytes) else raw.encode('utf-8')
        self.io['frames'] += 1
        self.io['lastFrameAtUtc'] = now_utc()
        try:
            frame = original.decode('utf-8')
        except UnicodeDecodeError:
            self.record('socket-io', 'invalid-encoding', {'raw/socketio-frame.txt': original},
                        endpoint=self.io_url, receivedAtUtc=self.io['lastFrameAtUtc'])
            raise
        parsed = parse_socket_io_frame(frame)
        details = dict(endpoint=self.io_url, receivedAtUtc=self.io['lastFrameAtUtc'],
                       enginePacketType=frame[:1], socketPacketType=frame[1:2] if frame.startswith('4') else None)
        if parsed is not None:
            event_name, payload = parsed
            self.io['businessFrames'] += 1
            self.io['lastBusinessAtUtc'] = self.io['lastFrameAtUtc']
            event = parse_sidesis_message(event_name, payload)
            details.update(eventName=event_name, eligibleForExistingAppParser=event is not None)
            if event is not None:
                self.io['eligibleEewFrames'] += 1
                fingerprint = hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True,
                                                        separators=(',', ':')).encode('utf-8')).hexdigest()
                duplicate = fingerprint in self._io_seen
                details['duplicateContent'] = duplicate
                if not duplicate:
                    self.io['newEewContents'] += 1
                    self._io_seen.add(fingerprint)
                    if len(self._io_seen) > 1024:
                        self._io_seen.clear()
                        self._io_seen.add(fingerprint)
            self.record('socket-io', 'business-frame', {'raw/socketio-frame.txt': original}, **details)
        else:
            self.record('socket-io', 'transport-frame', {'raw/socketio-frame.txt': original}, **details)
        return frame

    async def listen_io(self):
        while not self.stop.is_set():
            self.io['attempts'] += 1
            self.record('socket-io', 'connecting', endpoint=self.io_url, attempt=self.io['attempts'])
            try:
                async with websockets.connect(self.io_url, open_timeout=20, close_timeout=5,
                                              ping_interval=None, max_size=2 * 1024 * 1024,
                                              additional_headers={'User-Agent': 'RhythmQuake-SASMEX-Compare/1.0'}) as socket:
                    while not self.stop.is_set():
                        # Engine.IO sends a ping every 25 seconds. Silence causes reconnection.
                        raw = await asyncio.wait_for(socket.recv(), timeout=60)
                        frame = self.process_io_frame(raw)
                        if frame.startswith('0'):
                            await socket.send('40')
                        elif frame == '2':
                            await socket.send('3')
                        elif frame.startswith('40'):
                            self.io.update(connected=True, lastError=None)
                            self.record('socket-io', 'connected', endpoint=self.io_url, namespace='/')
                        elif frame.startswith('1') or frame.startswith('41'):
                            break
            except Exception as error:
                self.io['lastError'] = f'{type(error).__name__}: {error}'
            finally:
                self.io['connected'] = False
                self.record('socket-io', 'disconnected', endpoint=self.io_url, error=self.io['lastError'])
            await self.wait(3)

    async def periodic_health(self):
        while not self.stop.is_set():
            health = self.health()
            await asyncio.to_thread(atomic_json, self.directory / 'connection-status.json', health)
            self.record('both', 'connection-status', {'connection.json': json_bytes(health)})
            await self.wait(self.health_seconds)

    async def run(self):
        self.directory.mkdir(parents=True, exist_ok=True)
        self.archive.start()
        backup = Path(__file__).with_name('backup')
        attachments = {'backup/sasno_realtime.py': (backup / 'sasno_realtime.py').read_bytes()}
        if (backup / 'firestore-original.json').exists():
            attachments['backup/firestore-original.json'] = (backup / 'firestore-original.json').read_bytes()
        self.record('firestore', 'implementation-backup', attachments, legacyParserUsedForComparison=False)
        await self.firestore.start()
        tasks = [asyncio.create_task(method()) for method in [self.poll_firestore, self.listen_io, self.periodic_health]]
        try:
            # A background task failure must fail the service so systemd can restart it.
            waiter = asyncio.create_task(self.stop.wait())
            completed, _ = await asyncio.wait([*tasks, waiter], return_when=asyncio.FIRST_COMPLETED)
            for task in completed:
                if task is not waiter:
                    task.result()
        finally:
            self.stop.set()
            waiter.cancel()
            for task in tasks:
                task.cancel()
            await asyncio.gather(waiter, *tasks, return_exceptions=True)
            await self.firestore.close()
            self.record('both', 'stopped', {'connection.json': json_bytes(self.health())})
            await self.archive.close()


async def main(args):
    monitor = DualMonitor(args.directory, poll_seconds=args.poll_seconds)
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, monitor.stop.set)
        except NotImplementedError:
            pass
    await monitor.run()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path('/var/lib/rhythmquake-sasmex-compare'))
    parser.add_argument('--poll-seconds', type=float, default=1)
    args = parser.parse_args()
    if args.poll_seconds <= 0:
        parser.error('--poll-seconds must be positive')
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main(args))
