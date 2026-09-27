"""Bounded, read-only SeedLink v3 discovery and handshake diagnostic."""
import argparse
import collections
import datetime as dt
import json
import pathlib
import socket
import struct
import time
import xml.etree.ElementTree as ET


def discover(host, out):
    raw = bytearray()
    xml = bytearray()
    deadline = time.monotonic() + 25
    with socket.create_connection((host, 18000), timeout=12) as sock:
        sock.settimeout(3)
        sock.sendall(b'INFO STREAMS\r\n')
        while time.monotonic() < deadline:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                break
            raw.extend(chunk)
            while len(raw) >= 520:
                packet = bytes(raw[:520])
                del raw[:520]
                if not packet.startswith(b'SLINFO'):
                    raise ValueError(repr(packet[:40]))
                record = packet[8:]
                offset = struct.unpack('>H', record[44:46])[0]
                count = struct.unpack('>H', record[30:32])[0]
                xml.extend(record[offset:offset + count])
                if packet[7] == 32 or b'</seedlink>' in xml[-1024:]:
                    out.write_bytes(xml)
                    return ET.fromstring(xml)
    out.with_suffix('.partial.xml').write_bytes(xml)
    raise TimeoutError(f'INFO incomplete: {len(xml)} payload bytes; tail={xml[-100:]!r}')


def stream(host, stations, data, seconds):
    commands = []
    for network, station, selector in stations:
        commands += [f'STATION {station} {network}', f'SELECT {selector}']
        if data:
            commands.append('DATA')
    commands.append('END')
    raw = bytearray()
    seen = collections.Counter()
    responses = bytearray()
    latest = None
    reversals = 0
    times = []
    headers = set()
    with socket.create_connection((host, 18000), timeout=12) as sock:
        sock.settimeout(2)
        sock.sendall(('\r\n'.join(commands) + '\r\n').encode('ascii'))
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                break
            raw.extend(chunk)
            while raw:
                if not raw.startswith(b'SL'):
                    pos = raw.find(b'\r\n')
                    if pos < 0:
                        break
                    responses.extend(raw[:pos + 2])
                    del raw[:pos + 2]
                    continue
                if len(raw) < 520:
                    break
                headers.add(bytes(raw[:8]).decode(errors='replace'))
                r = bytes(raw[8:520])
                del raw[:520]
                name = r[18:20].decode().strip() + '.' + r[8:13].decode().strip()
                year, day = struct.unpack('>HH', r[20:24])
                timestamp = dt.datetime(year, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(
                    days=day-1, hours=r[24], minutes=r[25], seconds=r[26])
                reversals += int(latest is not None and timestamp < latest)
                latest = timestamp
                seen[name] += 1
                times.append(timestamp.isoformat())
    return dict(with_data=data, replies=responses.decode(errors='replace'),
                packets=sum(seen.values()), stations=dict(seen), backwards=reversals,
                min_time=min(times) if times else None, max_time=max(times) if times else None,
                headers=sorted(headers)[:20])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--seconds', type=int, default=15)
    args = parser.parse_args()
    out = pathlib.Path('tmp/fdsn_connection_review')
    out.mkdir(parents=True, exist_ok=True)
    for host, stations in [
        ('rtserve.earthscope.org', [('IU', 'ANMO', 'BH?'), ('IU', 'COLA', 'BH?')]),
        ('geofon.gfz.de', [('GE', 'MORC', 'BH?'), ('GE', 'WLF', 'BH?')]),
    ]:
        try:
            root = discover(host, out / f'{host}.xml')
            rows = root.findall('station')
            print(json.dumps(dict(host=host, stations=len(rows), first=[ET.tostring(r, encoding='unicode')[:1200] for r in rows[:2]])), flush=True)
        except Exception as exc:
            print(json.dumps(dict(host=host, discovery_error=str(exc))), flush=True)
        for data in [False, True]:
            try:
                print(json.dumps(dict(host=host, **stream(host, stations, data, args.seconds))), flush=True)
            except Exception as exc:
                print(json.dumps(dict(host=host, with_data=data, error=str(exc))), flush=True)
