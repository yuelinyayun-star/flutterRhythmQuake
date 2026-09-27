"""Read-only transport check for the documented EarthScope SeedLink endpoints."""
import argparse
import socket
import ssl
import time
import struct
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--tls', action='store_true')
parser.add_argument('--seconds', type=int, default=180)
args = parser.parse_args()
host = 'rtserve.earthscope.org'
port = 18500 if args.tls else 18000
started = time.monotonic()
raw = bytearray()
xml = bytearray()
last = started
with socket.create_connection((host, port), timeout=12) as tcp:
    sock = ssl.create_default_context().wrap_socket(tcp, server_hostname=host) if args.tls else tcp
    sock.settimeout(5)
    sock.sendall(b'INFO STREAMS\r\n')
    reason = 'deadline'
    while time.monotonic() - started < args.seconds:
        try:
            chunk = sock.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            reason = 'peer-close'
            break
        raw.extend(chunk)
        consumed = 0
        done = False
        while len(raw) - consumed >= 520:
            packet = raw[consumed:consumed+520]
            consumed += 520
            if packet[:6] != b'SLINFO':
                raise ValueError(repr(packet[:16]))
            offset = struct.unpack('>H', packet[52:54])[0]
            count = struct.unpack('>H', packet[38:40])[0]
            xml.extend(packet[8+offset:8+offset+count])
            if packet[7] == 32:
                done = True
                break
        del raw[:consumed]
        if time.monotonic() - last > 30:
            last = time.monotonic()
            print(f'{port} elapsed={last-started:.1f}s xml_bytes={len(xml)}', flush=True)
        if done:
            reason = 'complete'
            break
    sock.close()
print(f'{port} reason={reason} elapsed={time.monotonic()-started:.1f}s xml_bytes={len(xml)}', flush=True)
if reason == 'complete':
    root = ET.fromstring(xml)
    print('stations=', len(root.findall('station')), 'streams=', len(root.findall('.//stream')), flush=True)
