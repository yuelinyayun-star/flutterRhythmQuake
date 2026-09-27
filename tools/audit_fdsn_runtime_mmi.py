"""Read only FDSN state through a local Debug VM; never evaluates app code."""
import argparse
import datetime as dt
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('runtime_log', type=Path)
    parser.add_argument('selection', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    base = re.search(r'http://127\.0\.0\.1:\d+/[^\s]+/', args.runtime_log.read_text(encoding='utf-8')).group()

    def rpc(method, **params):
        with urllib.request.urlopen(base + method + '?' + urllib.parse.urlencode(params), timeout=20) as response:
            result = json.load(response)
        if 'error' in result:
            raise RuntimeError(result['error'])
        return result['result']

    isolate = next(i['id'] for i in rpc('getVM')['isolates'] if i['name'] == 'main')

    def obj(ref, **params):
        return rpc('getObject', isolateId=isolate, objectId=ref['id'], **params)

    def fields(ref):
        return {f['decl']['name']: f['value'] for f in obj(ref).get('fields', [])}

    def scalar(ref):
        if ref.get('kind') == 'Null':
            return None
        if 'valueAsString' in ref:
            value = ref['valueAsString']
            if ref.get('kind') in ('Int', 'Double', 'Bool'):
                return json.loads(value)
            return value
        if ref.get('class', {}).get('name') == 'DateTime':
            f = fields(ref)
            micros = scalar(f['_value'])
            return dt.datetime.fromtimestamp(micros / 1e6, dt.timezone.utc).isoformat()
        return {'class': ref.get('class', {}).get('name'), 'length': ref.get('length')}

    libraries = rpc('getIsolate', isolateId=isolate)['libraries']
    classes = {}
    for lib in libraries:
        if lib['uri'].endswith(('quake_map_view.dart', 'fdsn_motion_service_io.dart')):
            classes.update({c['name']: c for c in obj(lib)['classes']})

    def instances(name):
        return rpc('getInstances', isolateId=isolate, objectId=classes[name]['id'], limit=8)['instances']

    state = fields(instances('_QuakeMapViewState')[0])
    records = obj(state['_latestFdsnMotionSamples'], count=10000)['associations']
    selection = json.loads(args.selection.read_text(encoding='utf-8'))
    selected = {e['network'] + '.' + e['station']: e for e in selection['entries']
                if 7 <= e['latitude'] <= 12 and -87 <= e['longitude'] <= -81}
    result = {'capturedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
              'region': {'minLat': 7, 'maxLat': 12, 'minLon': -87, 'maxLon': -81},
              'latestSampleCount': len(records), 'samples': [], 'connections': []}
    for entry in records:
        key = scalar(entry['key'])
        if key.split(':', 1)[-1] not in selected:
            continue
        value = {k: scalar(v) for k, v in fields(entry['value']).items()}
        value['key'] = key
        result['samples'].append(value)
    for ref in instances('_SeedLinkConnection'):
        f = fields(ref)
        names = ['host', 'port', '_connected', '_running', '_packetCount', '_staleCount',
                 '_lastPacketAt', '_lastCloseReason', '_connectionAttempts', '_receivedStations',
                 '_measurementJobs', '_responseCache', '_decodeRejected']
        result['connections'].append({k: scalar(f[k]) for k in names if k in f})
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
