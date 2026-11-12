"""Read-only comparison observer. This service never publishes APP events."""
from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
import hashlib
import json
import logging
import math
from pathlib import Path
import signal

import websockets

from sasmex_archive import SasmexArchive, atomic_json
from sasno_realtime import SasnoRealtimeConfig, SasnoRealtimeFeed, parse_firestore_document
from sidesis_realtime import parse_socket_io_frame, parse_sidesis_message, socket_url_with_engine_query

IO_URL = 'wss://sidesis.iigea.org/socket.io/?EIO=4&transport=websocket'
LOGGER = logging.getLogger(__name__)


def content_fingerprint(document):
    return hashlib.sha256(json.dumps(document['fields'], ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode('utf-8')).hexdigest()


def retry_after_seconds(headers):
    value = next((value for key, value in headers.items() if key.lower() == 'retry-after'), None)
    if value is None:
        return 0
    try:
        seconds = float(value)
    except ValueError:
        try:
            stamp = parsedate_to_datetime(value)
            if stamp.tzinfo is None:
                stamp = stamp.replace(tzinfo=UTC)
            seconds = (stamp - datetime.now(UTC)).total_seconds()
        except (TypeError, ValueError, OverflowError):
            return 0
    return max(0, seconds) if math.isfinite(seconds) else 0


def atomic_bytes(path, body):
    temporary = path.with_suffix('.tmp')
    temporary.write_bytes(body)
    temporary.replace(path)

def now_utc():
    return datetime.now(UTC).isoformat()

def json_bytes(value):
    return json.dumps(value, ensure_ascii=False, indent=2).encode('utf-8')

async def never_publish(*args):
    raise RuntimeError('Comparison observer must not publish APP events')


class DualMonitor:
    def __init__(self, directory: Path, *, project='sasno-d79e1', io_url=IO_URL,
                 poll_seconds=5.0, health_seconds=60.0):
        self.directory = directory
        self.io_url = socket_url_with_engine_query(io_url)
        self.poll_seconds = poll_seconds
        self.health_seconds = health_seconds
        self.archive = SasmexArchive(str(directory / 'outbox'))
        self.firestore = SasnoRealtimeFeed(SasnoRealtimeConfig(project, poll_seconds, 20, 90), never_publish)
        self.stop = asyncio.Event()
        self._health_lock = asyncio.Lock()
        self.started_at = now_utc()
        self.session_id = self.started_at
        self.io = dict(endpoint=self.io_url, connected=False, attempts=0, frames=0,
                       businessFrames=0, eligibleEewFrames=0, newEewContents=0,
                       transportFrames=0, ignoredBusinessFrames=0, duplicateEewFrames=0,
                       lastFrameAtUtc=None, lastBusinessAtUtc=None, lastError=None)
        self.fs = dict(endpoint=self.firestore.config.document_url, connected=False,
                       polls=0, successfulPolls=0, changes=0, unchangedPolls=0,
                       lastAttemptAtUtc=None, lastSuccessAtUtc=None, lastChangeAtUtc=None,
                       lastStatus=None, lastError=None, originalSha256=None,
                       contentSha256=None, sourceUpdateTime=None, sourceUnix=None,
                       consecutiveFailures=0, retryDelaySeconds=poll_seconds, nextAttemptAtUtc=None)
        self._fs_fingerprint = None
        self._fs_error = None
        self._io_seen = set()
        # A service restart must not turn the existing snapshot into a new event.
        for name in ('firestore-latest.original.json', 'firestore-baseline.original.json'):
            path = directory / name
            if path.exists():
                document = json.loads(path.read_bytes().decode('utf-8'))
                if not isinstance(document.get('fields'), dict):
                    raise ValueError('Retained Firestore snapshot has no fields object')
                self._fs_fingerprint = content_fingerprint(document)
                break

    def record(self, transport, kind, originals=None, **details):
        # Only earthquake content belongs in the upload outbox. Operational
        # state stays in connection-status.json, local error files and journald.
        if (transport, kind) not in {('socket-io', 'business-frame'), ('firestore', 'change')}:
            return
        # Name/date evidence by the event's source timestamp, even when received
        # or uploaded on another day. Received time remains separate metadata.
        if transport == 'firestore' and originals and 'raw/firestore-document.json' in originals:
            decoded = parse_firestore_document(json.loads(originals['raw/firestore-document.json'].decode('utf-8')))
            source = decoded.get('SASNOEVENTDATA', decoded.get('sasnoeventdata', decoded))
            unix = source.get('unix') if isinstance(source, dict) else None
            if unix is not None:
                details['eventTimeUtc'] = datetime.fromtimestamp(float(unix), UTC).isoformat()
                details['eventDateBasis'] = 'SASNOEVENTDATA.unix'
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
        return dict(schemaVersion=1, role='comparison-only', appTransport='relay-ws',
                    appPrimarySource='sasno-firestore', publishesToApp=False,
                    firestorePublishedToApp=False, archivePolicy='earthquake-content-only',
                    startedAtUtc=self.started_at, recordedAtUtc=stamp.isoformat(),
                    socketIo=with_age(self.io, 'lastFrameAtUtc', 90),
                    firestore=with_age(self.fs, 'lastSuccessAtUtc', 90), archive=self.archive.status())

    async def wait(self, seconds):
        try:
            await asyncio.wait_for(self.stop.wait(), seconds)
        except TimeoutError:
            pass

    async def write_health(self):
        async with self._health_lock:
            await asyncio.to_thread(atomic_json, self.directory / 'connection-status.json', self.health())

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
            # Keep the actual failed response locally, never in the TG outbox.
            signature = (fetched.status, raw_hash, str(error))
            if signature != self._fs_error:
                atomic_bytes(self.directory / 'firestore-error.original.json', fetched.body)
                atomic_json(self.directory / 'firestore-error.json', dict(error=str(error), **request))
            self._fs_error = signature
            raise
        fingerprint = content_fingerprint(raw)
        self.fs.update(connected=True, lastSuccessAtUtc=fetched.received_at_utc,
                       lastError=None, successfulPolls=self.fs['successfulPolls'] + 1,
                       originalSha256=raw_hash, contentSha256=fingerprint,
                       sourceUpdateTime=raw.get('updateTime'))
        source = decoded.get('SASNOEVENTDATA', decoded.get('sasnoeventdata', decoded))
        self.fs['sourceUnix'] = source.get('unix') if isinstance(source, dict) else None
        if fingerprint != self._fs_fingerprint:
            baseline = self._fs_fingerprint is None
            if not baseline:
                attachments = {'raw/firestore-document.json': fetched.body, 'parsed.json': json_bytes(decoded)}
                self.record('firestore', 'change', attachments,
                            contentSha256=fingerprint, previousContentSha256=self._fs_fingerprint, **request)
                self.fs['changes'] += 1
                self.fs['lastChangeAtUtc'] = fetched.received_at_utc
            atomic_bytes(self.directory / 'firestore-latest.original.json', fetched.body)
            self._fs_fingerprint = fingerprint
            if baseline:
                atomic_bytes(self.directory / 'firestore-baseline.original.json', fetched.body)
        else:
            self.fs['unchangedPolls'] += 1
        if self._fs_error is not None:
            LOGGER.info('Firestore connection recovered (HTTP %s)', fetched.status)
        self._fs_error = None

    async def poll_firestore(self):
        while not self.stop.is_set():
            self.fs['polls'] += 1
            self.fs['lastAttemptAtUtc'] = now_utc()
            fetched = None
            try:
                fetched = await self.firestore._get()
                self.process_firestore(fetched)
                delay = self.poll_seconds
                self.fs['consecutiveFailures'] = 0
            except Exception as error:
                message = f'{type(error).__name__}: {error}'
                failures = self.fs['consecutiveFailures'] + 1
                status = fetched.status if fetched is not None else None
                base, maximum = (60, 900) if status == 429 else (5, 300)
                delay = min(maximum, max(base, self.poll_seconds) * 2 ** min(failures - 1, 10))
                if fetched is not None:
                    delay = max(delay, retry_after_seconds(fetched.headers))
                self.fs.update(connected=False, lastError=message, lastStatus=status,
                               consecutiveFailures=failures)
                LOGGER.warning('Firestore attempt failed (%s); retry in %.1fs', message, delay)
            self.fs.update(retryDelaySeconds=delay,
                           nextAttemptAtUtc=datetime.fromtimestamp(datetime.now(UTC).timestamp() + delay, UTC).isoformat())
            await self.write_health()
            await self.wait(delay)

    def process_io_frame(self, raw):
        original = raw if isinstance(raw, bytes) else raw.encode('utf-8')
        self.io['frames'] += 1
        self.io['lastFrameAtUtc'] = now_utc()
        try:
            frame = original.decode('utf-8')
        except UnicodeDecodeError:
            atomic_bytes(self.directory / 'socketio-error.original.frame', original)
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
                if duplicate:
                    self.io['duplicateEewFrames'] += 1
                else:
                    self.io['newEewContents'] += 1
                    self._io_seen.add(fingerprint)
                    if len(self._io_seen) > 1024:
                        self._io_seen.clear()
                        self._io_seen.add(fingerprint)
                    if event.get('epochMs') is not None:
                        details['eventTimeUtc'] = datetime.fromtimestamp(event['epochMs'] / 1000, UTC).isoformat()
                        details['eventDateBasis'] = 'sent' if event.get('sent') else 'updated'
                    self.record('socket-io', 'business-frame', {'raw/socketio-frame.txt': original}, **details)
            else:
                self.io['ignoredBusinessFrames'] += 1
        else:
            self.io['transportFrames'] += 1
        return frame

    async def listen_io(self):
        while not self.stop.is_set():
            self.io['attempts'] += 1
            LOGGER.info('Socket.IO connecting; attempt=%d', self.io['attempts'])
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
                            LOGGER.info('Socket.IO connected')
                        elif frame.startswith('1') or frame.startswith('41'):
                            break
            except Exception as error:
                self.io['lastError'] = f'{type(error).__name__}: {error}'
            finally:
                self.io['connected'] = False
                LOGGER.info('Socket.IO disconnected; error=%s', self.io['lastError'])
            await self.wait(3)

    async def periodic_health(self):
        while not self.stop.is_set():
            await self.write_health()
            await self.wait(self.health_seconds)

    async def run(self):
        self.directory.mkdir(parents=True, exist_ok=True)
        self.archive.start()
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
            await self.archive.close()
            await self.write_health()


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
    parser.add_argument('--poll-seconds', type=float, default=5)
    args = parser.parse_args()
    if args.poll_seconds <= 0:
        parser.error('--poll-seconds must be positive')
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main(args))
