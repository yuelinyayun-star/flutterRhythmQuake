"""Move network JSON ingress without changing payloads or domain conversion."""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKUP = ROOT / 'build/performance/backups/api-bytes-20261015'
MANIFEST = ROOT / 'docs/api_byte_ingress_manifest_20261015.json'
DIRECT = re.compile(r'decodeApiJson\(utf8\.decode\((\w+\.bodyBytes)\)\)')
RESPONSE = re.compile(r'decodeApiJson\((\w+)\.body\)')

# Full-expression replacements recorded from the pre-change backup. Verification
# permits formatting and unused dart:convert removal, but no payload literals,
# filtering, reconnect rules, field conversions, or connection policy changes.
MANUAL = {
    'jian_service.dart': [("""final decoded = decodeApiJson(
        message is String ? message : utf8.decode(message as List<int>),
      );""", """final decoded = message is String ? decodeApiJson(message) :
          decodeApiJsonBytes(message as List<int>);""", 'binary_ws')],
    'jian_icl_service.dart': [("""final decoded = decodeApiJson(
        message is String ? message : utf8.decode(message as List<int>),
      );""", """final decoded = message is String ? decodeApiJson(message) :
          decodeApiJsonBytes(message as List<int>);""", 'binary_ws')],
    'emsc_eqlist_service.dart': [("""final text = frame is List<int> ? utf8.decode(frame) : frame as String;
      final message = decodeApiJson(text);""", """final message = frame is List<int> ? decodeApiJsonBytes(frame) :
          decodeApiJson(frame as String);""", 'binary_ws')],
    'sasmex_service.dart': [("""final text = message is String
          ? message
          : utf8.decode(message as List<int>);
      final decoded = decodeApiJson(text);""", """final decoded = message is String ? decodeApiJson(message) :
          decodeApiJsonBytes(message as List<int>);""", 'binary_ws')],
    'nowquake_cenc_intensity_service.dart': [("""final text = raw is List<int> ? utf8.decode(raw) : raw.toString();
      final decoded = decodeApiJson(text);""", """final decoded = raw is List<int> ? decodeApiJsonBytes(raw) :
          decodeApiJson(raw.toString());""", 'binary_ws')],
    'jian_station_service.dart': [("""final raw = message is String
          ? message
          : utf8.decode(message as List<int>);
      final decoded = _coordinates.isEmpty
          ? decodeApiJson(raw)
          : _jsonDecoder.decode(raw);""", """final decoded = _coordinates.isEmpty
          ? (message is String ? decodeApiJson(message) :
              decodeApiJsonBytes(message as List<int>))
          : (message is String ? _jsonDecoder.decode(message) :
              _jsonDecoder.decodeUtf8(message as List<int>));""", 'binary_ws')],
}
TOKEN = re.compile(r'''r?(?:"""[\s\S]*?"""|''' + "'''[\\s\\S]*?'''" + r'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|//[^\n]*|/\*[\s\S]*?\*/|\s+|.''')


def tokens(source):
    source = re.sub(r"^import 'dart:convert';\s*", '', source, flags=re.MULTILINE)
    items = [t for t in TOKEN.findall(source) if not t.isspace()]
    return [t for i, t in enumerate(items)
            if not (t == ',' and i + 1 < len(items) and items[i + 1] in ')]}')]


def manual_convert(text, name, counts):
    for old, new, kind in MANUAL.get(name, []):
        pattern = r'\s*'.join(re.escape(part) for part in old.split())
        text, count = re.subn(pattern, lambda _: new, text)
        if count != 1:
            raise RuntimeError(f'Expected one original WS ingress: {name}')
        counts[kind] += count
    if name == 'cwa_station_service.dart':
        text, simple = re.subn(r'await (\w+)\.transform\(utf8\.decoder\)\.join\(\)',
                              r'await readApiJsonBytes(\1)', text)
        text, timed = re.subn(r'await (\w+)\s*\.transform\(utf8\.decoder\)\s*\.join\(\)\s*\.timeout\(_requestTimeout\)',
                             r'await readApiJsonBytes(\1, timeout: _requestTimeout)', text)
        if (simple, timed) != (2, 3):
            raise RuntimeError('Unexpected CWA stream ingress count')
        text, decodes = re.subn(r'decodeApiJson\(body\)', 'decodeApiJsonBytes(body)', text)
        if decodes != 5:
            raise RuntimeError('Unexpected CWA stream decode count')
        counts['streamed_http'] = decodes
    return text


def convert(text):
    text, direct = DIRECT.subn(r'decodeApiJsonBytes(\1)', text)
    text, response = RESPONSE.subn(r'decodeApiJsonResponse(\1)', text)
    old = 'decodeApiJson(utf8.decode((raw as List).cast<int>()))'
    binary = text.count(old)
    text = text.replace(old, 'decodeApiJsonBytes((raw as List).cast<int>())')
    return text, dict(utf8_bytes=direct, http_charset=response, binary_ws=binary)


if __name__ == '__main__':
    if '--verify' not in sys.argv:
        raise SystemExit('Use --verify. Source rewriting is disabled after manual review.')
    rows = []
    for original in sorted((BACKUP / 'services').rglob('*.dart')):
        relative = Path('lib/services') / original.relative_to(BACKUP / 'services')
        if original.name in {'api_json_decoder.dart', 'station_json_decoder_io.dart',
                              'station_json_decoder_stub.dart'}:
            continue
        before = original.read_text(encoding='utf-8')
        after, counts = convert(before)
        after = manual_convert(after, original.name, counts)
        if not sum(counts.values()):
            continue
        target = ROOT / relative
        if tokens(after) != tokens(target.read_text(encoding='utf-8')):
            raise RuntimeError(f'Changes beyond recorded ingress migration: {relative}')
        rows.append(dict(path=relative.as_posix(), **counts,
                         original_sha256=hashlib.sha256(original.read_bytes()).hexdigest()))
    MANIFEST.write_text(json.dumps(rows, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    fixtures = json.loads((BACKUP / 'fixture_hashes.json').read_text(encoding='utf-8'))
    for path, expected in fixtures.items():
        if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != expected:
            raise RuntimeError(f'Original fixture was modified: {path}')
    print(json.dumps(dict(files=len(rows), calls=sum(sum(r[k] for k in
        ['utf8_bytes','http_charset','binary_ws','streamed_http'] if k in r) for r in rows),
        original_fixtures=len(fixtures)), ensure_ascii=False))
