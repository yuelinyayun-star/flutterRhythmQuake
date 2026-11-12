"""Inventory and migrate API JSON call sites; original bytes are backed up.

This changes the JSON decoder only, not HTTP/WS policy or domain conversion.
Run from the repository root. Existing source encoding/newlines are preserved.
"""
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
BACKUP = ROOT / 'build/performance/backups/api-json-20261015-113352'
EXCLUDED = {
    'api_json_decoder.dart': 'shared native adapter and non-native implementation',
    'station_json_decoder_io.dart': 'native FFI adapter and explicit non-native implementation',
    'station_json_decoder_stub.dart': 'non-IO platform implementation',
    'mock_input_service.dart': 'local debug/replay import, not upstream API',
    'sasmex_report_sequence.dart': 'local stored sequence snapshot decode, not ingress',
    'whews_nied_station_metadata.dart': 'bundled station metadata asset, not ingress',
}
CALL = re.compile(r'\bjsonDecode\b|\bjson\.decode\b')
files = list((ROOT / 'lib/services/sources').rglob('*.dart'))
files += [ROOT / 'lib/services' / name for name in (
    'location_service.dart', 'jian_auth_service.dart', 'ntp_service.dart',
    'wauth_service.dart', 'obs_websocket_service.dart', 'collector/jian_collector_feed.dart',
)]
files += [ROOT / 'lib' / name for name in (
    'models/cenc_ir_data.dart', 'models/weather_alert_map_item.dart',
    'core/cwa_intensity_prediction.dart', 'core/cwa_report_intensities.dart',
    'core/utils/alert_voice_helper.dart',
    'core/source_estimation/jshis_surface_structure_api.dart',
)]
rows = []
for path in sorted(files):
    if path.name in EXCLUDED:
        continue
    original = path.read_bytes()
    source = original.decode('utf-8')
    matches = list(CALL.finditer(source))
    if not matches:
        continue
    relative = path.relative_to(ROOT)
    saved = BACKUP / path.relative_to(ROOT / 'lib')
    if saved.read_bytes() != original:
        raise RuntimeError(f'Backup mismatch: {relative}')
    migrated = CALL.sub('decodeApiJson', source)
    newline = '\r\n' if '\r\n' in source else '\n'
    adapter = Path(__import__('os').path.relpath(
        ROOT / 'lib/services/sources/api_json_decoder.dart', path.parent,
    )).as_posix()
    # Insert after the first existing import, before class declarations.
    first = re.search(r"^import [^;]+;", migrated, re.MULTILINE)
    if first is None:
        raise RuntimeError(f'No import section: {relative}')
    migrated = migrated[:first.end()] + newline + f"import '{adapter}';" + migrated[first.end():]
    rows.append({
        'path': relative.as_posix(), 'call_sites': len(matches),
        'original_sha256': hashlib.sha256(original).hexdigest(),
        'original_lines': [source.count('\n', 0, m.start()) + 1 for m in matches],
    })
    if '--apply' in sys.argv:
        path.write_bytes(migrated.encode('utf-8'))
destination = ROOT / 'build/performance/api_json_migration_inventory_20261015.json'
if destination.exists():
    prior = json.loads(destination.read_text(encoding='utf-8'))['entries']
    merged = {row['path']: row for row in prior}
    merged.update({row['path']: row for row in rows})
    rows = sorted(merged.values(), key=lambda row: row['path'])
report = {'files': len(rows), 'call_sites': sum(r['call_sites'] for r in rows),
          'entries': rows, 'intentional_exclusions': EXCLUDED}
if '--verify' in sys.argv:
    native_calls = re.compile(r'\bdecodeApiJson\b')
    imports = re.compile(r"^import ['\"][^'\"]*(?:dart:convert|api_json_decoder\.dart)['\"];\r?\n?", re.MULTILINE)
    for row in rows:
        current = (ROOT / row['path']).read_text(encoding='utf-8')
        if CALL.search(current) or len(native_calls.findall(current)) != row['call_sites']:
            raise RuntimeError(f"Incomplete native API ingress: {row['path']}")
        original = (BACKUP / Path(row['path']).relative_to('lib')).read_text(encoding='utf-8')
        before = imports.sub('', CALL.sub('__JSON_DECODE__', original)).split()
        after = imports.sub('', native_calls.sub('__JSON_DECODE__', current)).split()
        if before != after:
            raise RuntimeError(f"Changes beyond decoder/imports require review: {row['path']}")
    print(f"Verified all {len(rows)} files / {report['call_sites']} migrated call sites")
destination.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(json.dumps({'files': report['files'], 'call_sites': report['call_sites']}, ensure_ascii=False))
