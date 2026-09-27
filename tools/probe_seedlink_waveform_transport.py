"""Read-only raw-header probe; never publishes generated data to the app."""
import argparse
from contextlib import nullcontext
import datetime as dt
import json
import io
from pathlib import Path
import re
import socket
import ssl
import statistics
import struct
import time
import urllib.request
import urllib.parse


def connect_tcp(host, port, receive_buffer_before_connect=0, resolved_address=None):
    if not receive_buffer_before_connect and not resolved_address:
        return socket.create_connection((host, port), timeout=12)
    last_error = None
    addresses = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    if resolved_address:
        addresses = [entry for entry in addresses if entry[4][0] == resolved_address]
        if not addresses:
            raise ValueError('Diagnostic address is not in the current hostname DNS result')
    for family, kind, proto, _, address in addresses:
        sock = socket.socket(family, kind, proto)
        try:
            sock.settimeout(12)
            if receive_buffer_before_connect:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF,
                                receive_buffer_before_connect)
            sock.connect(address)
            return sock
        except OSError as exc:
            last_error = exc
            sock.close()
    if last_error is not None:
        raise last_error
    raise OSError('No TCP addresses returned')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seconds', type=int, default=90)
    parser.add_argument('--vertical', action='store_true')
    transport = parser.add_mutually_exclusive_group()
    transport.add_argument('--wss', action='store_true')
    transport.add_argument('--tcp', action='store_true', help='Diagnostic only: official unencrypted TCP port 18000')
    parser.add_argument('--gq-rate', action='store_true', help='Diagnostic: lowest-rate supported vertical channel using official metadata')
    parser.add_argument('--limit', type=int, default=5000)
    parser.add_argument('--window', type=int, default=32)
    parser.add_argument('--batch', action='store_true', help='Diagnostic WSS BATCH mode; individual subscription ACKs are unavailable')
    parser.add_argument('--receive-buffer', type=int, default=0, help='Diagnostic socket receive buffer in bytes (0 preserves system default)')
    parser.add_argument('--receive-buffer-before-connect', type=int, default=0,
                        help='Diagnostic: set SO_RCVBUF before TCP window negotiation')
    parser.add_argument('--ack-window', type=int, default=0, help='Diagnostic TCP/TLS command window; 0 preserves bulk handshake')
    parser.add_argument('--audit-output', type=Path, help='Save bounded original records and compare ObsPy times with the public stream catalogue')
    parser.add_argument('--selection-file', type=Path, help='Reuse the exact selected NSLC patterns from a previous audit; limit still applies')
    parser.add_argument('--tcp-info', action='store_true', help='Read Windows TCP statistics for this diagnostic socket')
    parser.add_argument('--strict-tls-eof', action='store_true', help='Distinguish missing TLS close_notify from a normal TLS close')
    parser.add_argument('--resolved-address', help='Diagnostic: select one address from current official hostname DNS, preserving TLS hostname verification')
    parser.add_argument('--handshake-timeout', type=float, default=3,
                        help='Diagnostic native socket timeout during subscription writes/ACKs')
    parser.add_argument('--info-once-after', type=float, default=0,
                        help='Diagnostic: one INFO ID request during transfer, never periodic')
    args = parser.parse_args()
    if args.limit < 1 or args.window < 1:
        parser.error('limit and window must be positive')
    if args.handshake_timeout <= 0:
        parser.error('handshake-timeout must be positive')
    if args.batch and not args.wss:
        parser.error('batch diagnostic requires wss')
    if args.tcp_info and args.wss:
        parser.error('tcp-info currently requires native TCP/TLS')
    if args.receive_buffer_before_connect < 0:
        parser.error('receive-buffer-before-connect must be nonnegative')
    if args.receive_buffer_before_connect and (args.wss or args.receive_buffer):
        parser.error('preconnect buffer requires native TCP/TLS and no postconnect buffer override')
    if args.resolved_address and args.wss:
        parser.error('resolved-address diagnostic requires native TCP/TLS')
    if args.info_once_after < 0 or (args.info_once_after and args.wss):
        parser.error('info-once-after requires native TCP/TLS and a nonnegative delay')
    if args.tcp_info:
        from windows_tcp_info import tcp_info
    host = 'rtserve.earthscope.org'
    request = urllib.request.Request('https://' + host + '/streams',
        headers={'User-Agent': 'FlutterRhythmQuake/1.0 diagnostic'})
    with urllib.request.urlopen(request, timeout=60) as response:
        text = response.read().decode('utf-8')
    now = dt.datetime.now(dt.timezone.utc)
    groups = {}
    for line in text.splitlines():
        fields = line.split()
        if len(fields) != 3 or not fields[0].startswith('FDSN:') or not fields[0].endswith('/MSEED'):
            continue
        codes = fields[0][5:-6].split('_')
        if len(codes) != 6:
            continue
        end = dt.datetime.fromisoformat(fields[2].replace('Z', '+00:00'))
        if not 0 <= (now - end).total_seconds() <= 180:
            continue
        channel = ''.join(codes[3:])
        groups.setdefault((codes[0], codes[1]), []).append((end, codes[2], channel))
    selections = []
    rates = {}
    if args.gq_rate:
        query = urllib.parse.urlencode({'channel': 'HNZ,HLZ,HHZ,BHZ,EHZ,SHZ',
            'level': 'channel', 'format': 'text', 'endafter': now.strftime('%Y-%m-%dT%H:%M:%S')})
        with urllib.request.urlopen('https://service.earthscope.org/fdsnws/station/1/query?' + query, timeout=90) as response:
            metadata = response.read().decode('utf-8')
        for line in metadata.splitlines():
            c = [v.strip() for v in line.split('|')]
            if line.startswith('#') or len(c) < 17:
                continue
            try:
                start = dt.datetime.fromisoformat(c[15].removesuffix('Z')).replace(tzinfo=dt.timezone.utc)
                end = dt.datetime.fromisoformat(c[16].removesuffix('Z')).replace(tzinfo=dt.timezone.utc) if c[16] else None
                rate = float(c[14])
                if start > now or (end is not None and end <= now) or rate <= 0 or float(c[11]) <= 0:
                    continue
                rates[tuple(c[:4])] = rate
            except (ValueError, OverflowError):
                continue
        print(json.dumps({'metadataChannels': len(rates)}), flush=True)
    for (network, station), channels in groups.items():
        if args.gq_rate:
            matches = [(rates[(network, station, loc, ch)], loc, ch) for _, loc, ch in channels
                if (network, station, loc, ch) in rates]
            if matches:
                rate, loc, ch = min(matches)
                selections.append((network, station, loc + ch + '.D'))
            continue
        for family in ['HN', 'HL', 'HH', 'BH', 'EH', 'SH']:
            matches = [c for c in channels if c[2].startswith(family) and (not args.vertical or c[2].endswith('Z'))]
            if matches:
                end, location, channel = max(matches)
                selector = location + (channel if args.vertical else family + '?') + '.D'
                selections.append((network, station, selector))
                break
    if args.selection_file:
        selections = json.loads(args.selection_file.read_text(encoding='utf-8'))['selected']
        for entry in selections:
            if (not isinstance(entry, list) or len(entry) != 3
                    or not all(isinstance(x, str) for x in entry)
                    or not re.fullmatch(r'[A-Z0-9]{1,2}', entry[0])
                    or not re.fullmatch(r'[A-Z0-9]{1,5}', entry[1])
                    or not re.fullmatch(r'[A-Z0-9?]{3,5}\.D', entry[2])):
                parser.error('selection-file contains an invalid station or selector')
    selections = selections[:args.limit]
    print(json.dumps({'selected': len(selections), 'vertical': args.vertical, 'gqRate': args.gq_rate, 'wss': args.wss, 'tcp': args.tcp, 'window': args.window}), flush=True)
    if args.wss:
        from websockets.sync.client import connect
    print(json.dumps({'startedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
                      'preconnectReceiveBuffer': args.receive_buffer_before_connect,
                      'strictTlsEof': args.strict_tls_eof}), flush=True)
    with (nullcontext() if args.wss else connect_tcp(host, 18000 if args.tcp else 18500,
            args.receive_buffer_before_connect, args.resolved_address)) as tcp:
        connection = connect('wss://' + host + '/seedlink', open_timeout=20, ping_interval=None,
            close_timeout=3, proxy=None) if args.wss else (tcp if args.tcp else ssl.create_default_context().wrap_socket(tcp, server_hostname=host, suppress_ragged_eofs=not args.strict_tls_eof))
        with connection as sock:
            if not args.wss:
                print(json.dumps({'peerAddress': sock.getpeername(),
                                  'localAddress': sock.getsockname()}), flush=True)
                sock.settimeout(args.handshake_timeout)
                if args.receive_buffer:
                    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, args.receive_buffer)
                print(json.dumps({'receiveBuffer': sock.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)}), flush=True)
                if args.tcp_info:
                    print(json.dumps({'tcpInfoInitial': tcp_info(sock)}), flush=True)
            commands = ''.join(f'STATION {s} {n}\r\nSELECT {c}\r\nDATA\r\n' for n, s, c in selections) + 'END\r\n'
            handshake_started = time.monotonic()
            consumed_replies = 0
            selection_errors = []
            if args.wss:
                sock.send('HELLO\r\n')
                print(repr(sock.recv(timeout=15)), flush=True)
                lines = commands.splitlines()[:-1]
                if args.batch:
                    sock.send('BATCH\r\n')
                    reply = sock.recv(timeout=15)
                    if reply not in ('OK\r\n', b'OK\r\n'):
                        raise RuntimeError(f'BATCH rejected: {reply!r}')
                    for line in lines:
                        sock.send(line + '\r\n')
                for start in range(0, 0 if args.batch else len(lines), args.window):
                    batch = lines[start:start+args.window]
                    for line in batch:
                        sock.send(line + '\r\n')
                    for line in batch:
                        reply = sock.recv(timeout=15)
                        if reply not in ('OK\r\n', b'OK\r\n'):
                            selection_errors.append((line, repr(reply)))
                            if len(selection_errors) <= 5:
                                print(json.dumps({'selectionError': selection_errors[-1]}), flush=True)
                        consumed_replies += 1
                sock.send('END\r\n')
                print(json.dumps({'handshakeSeconds': time.monotonic()-handshake_started, 'replies': consumed_replies, 'selectionErrors': None if args.batch else len(selection_errors), 'batch': args.batch}), flush=True)
            elif args.ack_window:
                lines = commands.splitlines()[:-1]
                ack_buffer = bytearray()
                for start in range(0, len(lines), args.ack_window):
                    batch = lines[start:start + args.ack_window]
                    sock.sendall(('\r\n'.join(batch) + '\r\n').encode('ascii'))
                    for line in batch:
                        while b'\n' not in ack_buffer:
                            part = sock.recv(65536)
                            if not part:
                                raise EOFError('peer closed during handshake')
                            ack_buffer.extend(part)
                        end = ack_buffer.index(10) + 1
                        reply = bytes(ack_buffer[:end])
                        del ack_buffer[:end]
                        if reply != b'OK\r\n':
                            raise RuntimeError(f'{line}: {reply!r}')
                        consumed_replies += 1
                sock.sendall(b'END\r\n')
                print(json.dumps({'handshakeSeconds': time.monotonic()-handshake_started, 'replies': consumed_replies, 'ackWindow': args.ack_window}), flush=True)
            else:
                sock.sendall(commands.encode('ascii'))
            if not args.wss:
                sock.settimeout(3)
            raw = bytearray()
            replies = consumed_replies
            packets = total = 0
            errors = []
            reason = 'deadline'
            ages = []
            latest = {}
            audit_records = {}
            started = last = time.monotonic()
            last_bytes_at = started
            max_gap = 0.0
            info_sent_at = None
            info_packets = []
            while time.monotonic() - started < args.seconds:
                try:
                    if (args.info_once_after and info_sent_at is None
                            and time.monotonic() - started >= args.info_once_after):
                        sock.sendall(b'INFO ID\r\n')
                        info_sent_at = time.monotonic()
                        print(json.dumps({'infoIdSentAtSeconds': info_sent_at - started}), flush=True)
                    chunk = sock.recv(timeout=3) if args.wss else sock.recv(1024 * 1024)
                except socket.timeout:
                    continue
                except OSError as exc:
                    reason = f'{type(exc).__name__}: {exc}'
                    break
                if not chunk:
                    reason = 'peer-close'
                    break
                if isinstance(chunk, str):
                    chunk = chunk.encode('ascii')
                total += len(chunk)
                received_at = time.monotonic()
                max_gap = max(max_gap, received_at - last_bytes_at)
                last_bytes_at = received_at
                raw.extend(chunk)
                while not args.batch and replies < len(selections) * 3 and b'\n' in raw:
                    if raw[:2] == b'SL':
                        break
                    split = raw.index(10) + 1
                    if raw[:split].strip() != b'OK' and len(errors) < 10:
                        errors.append(raw[:split].decode('ascii', errors='replace').strip())
                    del raw[:split]
                    replies += 1
                if not args.batch and replies < len(selections) * 3:
                    continue
                consumed = 0
                while len(raw) - consumed >= 520:
                    packet = raw[consumed:consumed + 520]
                    consumed += 520
                    if packet[:2] != b'SL':
                        raise ValueError(repr(packet[:16]))
                    if packet[:6] == b'SLINFO':
                        info_packet = {'receivedAtSeconds': time.monotonic() - started,
                                       'packetHex': bytes(packet).hex()}
                        info_packets.append(info_packet)
                        print(json.dumps({'infoPacketReceivedAtSeconds': info_packet['receivedAtSeconds'],
                                          'afterRequestSeconds': time.monotonic() - info_sent_at
                                              if info_sent_at is not None else None,
                                          'header': bytes(packet[:8]).decode('ascii')}), flush=True)
                        continue
                    rec = packet[8:]
                    year, day = struct.unpack('>HH', rec[20:24])
                    if not 1900 <= year <= 2200:
                        year, day = struct.unpack('<HH', rec[20:24])
                    observed = dt.datetime(year, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(days=day-1, hours=rec[24], minutes=rec[25], seconds=rec[26])
                    key = bytes(rec[8:13] + rec[18:20]).decode('ascii')
                    if args.audit_output:
                        nslc = '.'.join(bytes(rec[a:b]).decode('ascii').strip()
                            for a, b in ((18, 20), (8, 13), (13, 15), (15, 18)))
                        if nslc in audit_records or len(audit_records) < 32:
                            audit_records[nslc] = {
                                'receivedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
                                'recordHex': bytes(rec).hex(),
                            }
                    latest[key] = max(latest.get(key, observed), observed)
                    ages.append((dt.datetime.now(dt.timezone.utc) - observed).total_seconds())
                    packets += 1
                del raw[:consumed]
                if time.monotonic() - last >= 15:
                    last = time.monotonic()
                    print(json.dumps({'seconds': round(last-started, 1), 'bytes': total, 'packets': packets,
                        'stations': len(latest), 'medianArrivalAge': round(statistics.median(ages), 1) if ages else None,
                        'fresh': sum((dt.datetime.now(dt.timezone.utc)-t).total_seconds() <= 180 for t in latest.values())}), flush=True)
                    if args.tcp_info:
                        print(json.dumps({'tcpInfo': tcp_info(sock), 'maxReceiveGap': max_gap}), flush=True)
                    ages.clear()
            print(json.dumps({'reason': reason, 'seconds': round(time.monotonic()-started, 1),
                'bytes': total, 'replies': replies, 'packets': packets, 'errors': errors,
                'stations': len(latest),
                'fresh': sum(0 <= (dt.datetime.now(dt.timezone.utc)-t).total_seconds() <= 180 for t in latest.values()),
                'bufferHead': raw[:80].decode('ascii', errors='replace')}), flush=True)
            if args.tcp_info:
                print(json.dumps({'tcpInfoFinal': tcp_info(sock),
                    'maxReceiveGap': max_gap,
                    'secondsSinceLastBytes': time.monotonic() - last_bytes_at}), flush=True)
    if args.audit_output:
        from obspy.io.mseed.util import get_record_information
        report = {'transport': 'wss' if args.wss else 'tcp' if args.tcp else 'tls',
            'selected': selections, 'records': audit_records,
            'infoRequestSentAtSeconds': info_sent_at - started if info_sent_at is not None else None,
            'infoPackets': info_packets}
        for entry in audit_records.values():
            info = get_record_information(io.BytesIO(bytes.fromhex(entry['recordHex'])))
            received = dt.datetime.fromisoformat(entry['receivedAt']).timestamp()
            entry.update(startTime=str(info['starttime']), endTime=str(info['endtime']),
                sampleRate=info['samp_rate'], sampleCount=info['npts'],
                startAgeSeconds=received-float(info['starttime']),
                endAgeSeconds=received-float(info['endtime']))
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                catalogue = response.read().decode('utf-8')
            report['catalogueCheckedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
            for line in catalogue.splitlines():
                fields = line.split()
                if len(fields) != 3 or not fields[0].startswith('FDSN:') or not fields[0].endswith('/MSEED'):
                    continue
                codes = fields[0][5:-6].split('_')
                if len(codes) != 6:
                    continue
                entry = audit_records.get('.'.join(codes[:3] + [''.join(codes[3:])]))
                if entry is not None:
                    entry['serverEndTime'] = fields[2]
                    entry['serverAheadSeconds'] = (
                        dt.datetime.fromisoformat(fields[2].replace('Z', '+00:00')).timestamp()
                        - dt.datetime.fromisoformat(entry['endTime'].replace('Z', '+00:00')).timestamp())
        except Exception as exc:
            report['catalogueError'] = str(exc)
        args.audit_output.parent.mkdir(parents=True, exist_ok=True)
        args.audit_output.write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps({'auditOutput': str(args.audit_output), 'records': len(audit_records),
            'medianEndAge': statistics.median(x['endAgeSeconds'] for x in audit_records.values())
                if audit_records else None}), flush=True)


if __name__ == '__main__':
    main()
