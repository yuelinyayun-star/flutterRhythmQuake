"""Export untouched ObsPy-decoded records and exact channel epochs for Dart QA."""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
from obspy import read, UTCDateTime
from obspy.io.mseed.util import get_record_information


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('waveform', type=Path)
    parser.add_argument('metadata', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    raw = args.waveform.read_bytes()
    rows = list(csv.reader(args.metadata.read_text(encoding='utf-8').splitlines(), delimiter='|'))
    records = []
    offset = 0
    while offset < len(raw):
        info = get_record_information(io.BytesIO(raw[offset:]))
        size = info['record_length']
        trace = read(io.BytesIO(raw[offset:offset + size]))[0]
        candidates = [r for r in rows if len(r) >= 17 and r[:4] ==
                      [trace.stats.network, trace.stats.station, trace.stats.location, trace.stats.channel]
                      and UTCDateTime(r[15]) <= trace.stats.starttime
                      and (not r[16] or trace.stats.starttime < UTCDateTime(r[16]))]
        metadata = max(candidates, key=lambda r: UTCDateTime(r[15]))
        records.append({'offset': offset, 'length': size, 'id': trace.id,
                        'start': str(trace.stats.starttime), 'end': str(trace.stats.endtime),
                        'sampleRate': trace.stats.sampling_rate, 'metadataRow': metadata,
                        'samples': trace.data.tolist()})
        offset += size
    result = {'waveform': str(args.waveform.resolve()), 'sha256': hashlib.sha256(raw).hexdigest(),
              'metadata': str(args.metadata.resolve()), 'records': records}
    args.output.write_text(json.dumps(result), encoding='utf-8')
    print(json.dumps({'records': len(records), 'sha256': result['sha256']}))


if __name__ == '__main__':
    main()
