"""Compare EarthScope's published client against an unchanged audited selection."""

import argparse
import io
import json
from pathlib import Path
import statistics
import sys
import threading
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--client-path', type=Path, required=True)
    parser.add_argument('--selection', type=Path, required=True)
    parser.add_argument('--protocol', choices=['3', '4'], default='4')
    parser.add_argument('--seconds', type=int, default=120)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.client_path.resolve()))
    from seedlink_client import SeedLink
    from seedlink_client.protocol import Protocol
    from obspy.io.mseed.util import get_record_information

    selected = json.loads(args.selection.read_text(encoding='utf-8'))['selected']
    report = {'client': 'EarthScope seedlink-client 0.2.0',
        'protocol': args.protocol, 'selected': selected, 'samples': []}
    client = SeedLink('rtserve.earthscope.org', port=18500, timeout=15,
        protocol=Protocol.V4 if args.protocol == '4' else Protocol.V3,
        keepalive=None, idle_timeout=180)
    for network, station, selector in selected:
        client.add_stream(f'{network}_{station}', selector)
    started = time.monotonic()
    latest = {}
    ages = []
    packets = byte_count = 0
    timer = None
    deadline = threading.Event()
    try:
        client.connect()
        client.negotiate()
        report['handshakeSeconds'] = time.monotonic() - started
        print(json.dumps({'handshakeSeconds': report['handshakeSeconds'],
            'stations': len(selected), 'protocol': args.protocol}), flush=True)
        started = last = time.monotonic()

        def finish():
            deadline.set()
            client.close()

        timer = threading.Timer(args.seconds, finish)
        timer.start()
        for packet in client.collect(reconnect=False):
            info = get_record_information(io.BytesIO(packet.payload))
            now = time.time()
            end = float(info['endtime'])
            key = (info['network'], info['station'])
            latest[key] = max(latest.get(key, end), end)
            ages.append(now - end)
            packets += 1
            byte_count += len(packet.payload)
            elapsed = time.monotonic()
            if elapsed - last >= 15:
                row = {'seconds': elapsed-started, 'packets': packets,
                    'bytes': byte_count, 'seen': len(latest),
                    'fresh': sum(0 <= now-t <= 180 for t in latest.values()),
                    'medianEndAgeSeconds': statistics.median(ages)}
                report['samples'].append(row)
                print(json.dumps(row), flush=True)
                ages.clear()
                last = elapsed
        report['reason'] = 'deadline' if deadline.is_set() else 'stream ended'
    except Exception as exc:
        report['reason'] = 'deadline' if deadline.is_set() else f'{type(exc).__name__}: {exc}'
    finally:
        if timer:
            timer.cancel()
        client.close()
        if timer:
            timer.join()
        report['packets'] = packets
        report['bytes'] = byte_count
        report['fresh'] = sum(0 <= time.time()-t <= 180 for t in latest.values())
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps({k: report[k] for k in ('reason', 'packets', 'bytes', 'fresh')}), flush=True)


if __name__ == '__main__':
    main()
