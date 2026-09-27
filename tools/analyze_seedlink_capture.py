"""Summarize captured TCP headers, without inferring an upstream close cause."""
import argparse
from collections import deque
import datetime as dt
import json
from pathlib import Path
import socket
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
    'tmp/fdsn_connection_review/packet-analysis-deps'))
import dpkt


def utc(value):
    return dt.datetime.fromtimestamp(float(value), dt.timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('capture', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    flows = {}
    skipped = 0
    with args.capture.open('rb') as handle:
        for stamp, raw in dpkt.pcapng.Reader(handle):
            try:
                ip = dpkt.ethernet.Ethernet(raw).data
                # PktMon can export native WLAN frames alongside Ethernet.
                if not isinstance(ip, dpkt.ip.IP):
                    wlan = dpkt.ieee80211.IEEE80211(raw)
                    if wlan.version != 0 or wlan.type != 2:
                        continue
                    ip = dpkt.llc.LLC(wlan.data).data
                if not isinstance(ip, dpkt.ip.IP) or not isinstance(ip.data, dpkt.tcp.TCP):
                    continue
                tcp = ip.data
                incoming = tcp.sport in (18000, 18500, 443)
                if not incoming and tcp.dport not in (18000, 18500, 443):
                    continue
                src, dst = socket.inet_ntoa(ip.src), socket.inet_ntoa(ip.dst)
                key = (dst, tcp.dport, src, tcp.sport) if incoming else (src, tcp.sport, dst, tcp.dport)
                flow = flows.setdefault(key, {
                    'local': list(key[:2]), 'remote': list(key[2:]),
                    'first': utc(stamp), 'directions': {}, 'closePackets': [],
                    'synPackets': [], 'tail': deque(maxlen=30),
                })
                direction = 'server-to-client' if incoming else 'client-to-server'
                stat = flow['directions'].setdefault(direction, {
                    'packets': 0, 'wirePayloadBytes': 0, 'zeroWindowPackets': 0,
                    'minimumWindowField': 65535, 'maximumWindowField': 0,
                    'maximumPacketGapSeconds': 0,
                })
                if 'lastStamp' in stat:
                    stat['maximumPacketGapSeconds'] = max(
                        stat['maximumPacketGapSeconds'], float(stamp) - stat['lastStamp'])
                stat['lastStamp'] = float(stamp)
                stat['packets'] += 1
                payload = max(0, ip.len - ip.hl * 4 - tcp.off * 4)
                stat['wirePayloadBytes'] += payload
                stat['zeroWindowPackets'] += int(tcp.win == 0)
                stat['minimumWindowField'] = min(stat['minimumWindowField'], tcp.win)
                stat['maximumWindowField'] = max(stat['maximumWindowField'], tcp.win)
                row = {'at': utc(stamp), 'direction': direction,
                    'flags': tcp.flags, 'seq': tcp.seq, 'ack': tcp.ack,
                    'windowField': tcp.win, 'payloadBytes': payload}
                flow['tail'].append(row)
                if tcp.flags & (dpkt.tcp.TH_FIN | dpkt.tcp.TH_RST):
                    flow['closePackets'].append(row)
                if tcp.flags & dpkt.tcp.TH_SYN:
                    flow['synPackets'].append({**row, 'optionsHex': tcp.opts.hex()})
                flow['last'] = utc(stamp)
            except (dpkt.UnpackError, ValueError, AttributeError):
                skipped += 1
    for flow in flows.values():
        flow['tail'] = list(flow['tail'])
        for stat in flow['directions'].values():
            del stat['lastStamp']
    result = {'capture': str(args.capture), 'skipped': skipped,
        'notes': 'Window fields are unscaled. Wire bytes may include retransmissions or capture duplicates. NIC headers alone do not identify an upstream application or load-balancer cause.',
        'flows': list(flows.values())}
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    for flow in result['flows']:
        print(json.dumps({k: v for k, v in flow.items() if k != 'tail'}))


if __name__ == '__main__':
    main()
