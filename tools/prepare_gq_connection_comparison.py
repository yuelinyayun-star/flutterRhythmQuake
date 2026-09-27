"""Build isolated connection-test inputs from unmodified provider metadata."""
import argparse
import csv
import datetime as dt
import fnmatch
import json
import math
from pathlib import Path


def instant(value):
    return dt.datetime.fromisoformat(value.rstrip('Z')).replace(tzinfo=dt.timezone.utc)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--selection', type=Path, required=True)
    parser.add_argument('--channels', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    selected = json.loads(args.selection.read_text(encoding='utf-8'))['selected']
    now = dt.datetime.now(dt.timezone.utc)
    channels = {}
    with args.channels.open(encoding='utf-8', newline='') as handle:
        for row in csv.reader(handle, delimiter='|'):
            if not row or row[0].startswith('#') or len(row) < 17:
                continue
            if instant(row[15]) > now or (row[16] and instant(row[16]) <= now):
                continue
            channels.setdefault((row[0], row[1]), []).append(row)
    entries, missing = [], []
    for network, station, selector in selected:
        candidates = [row for row in channels.get((network, station), [])
                      if fnmatch.fnmatchcase(row[2] + row[3] + '.D', selector)]
        if not candidates:
            missing.append([network, station, selector])
            continue
        row = max(candidates, key=lambda r: (r[3].endswith('Z'), instant(r[15])))
        try:
            numbers = [float(row[i]) for i in (4, 5, 6, 11, 14)]
        except ValueError:
            missing.append([network, station, selector])
            continue
        if not all(math.isfinite(x) for x in numbers):
            missing.append([network, station, selector])
            continue
        entries.append({'network': network, 'station': station, 'selector': selector,
                        'metadataRow': row, 'latitude': numbers[0], 'longitude': numbers[1],
                        'elevation': numbers[2], 'sensitivity': numbers[3], 'sampleRate': numbers[4]})
    result = {'preparedAt': now.isoformat(), 'originalSelectionCount': len(selected),
              'selected': [[e['network'], e['station'], e['selector']] for e in entries],
              'entries': entries, 'missingMetadata': missing}
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'original': len(selected), 'comparable': len(entries),
                      'missingMetadata': len(missing), 'output': str(args.output)}))


if __name__ == '__main__':
    main()
