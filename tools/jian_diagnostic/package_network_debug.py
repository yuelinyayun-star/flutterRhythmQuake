"""Package the built Debug application without copying local caches/databases."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import struct
import zipfile

root = Path(__file__).resolve().parents[2]
source = root / 'build/windows/x64/runner/Debug'
bundle = root / 'build/diagnostics/RhythmQuake_NetworkDebug_x64'
app = bundle / 'APP'
app.mkdir(parents=True, exist_ok=True)
shutil.copytree(source, app, dirs_exist_ok=True, ignore=shutil.ignore_patterns('*.pdb', '.dart_tool', '*.log', 'release_manifest.json'))

def imports(path):
    b = path.read_bytes()
    if b[:2] != b'MZ':
        return []
    pe = struct.unpack_from('<I', b, 0x3c)[0]
    count = struct.unpack_from('<H', b, pe + 6)[0]
    size = struct.unpack_from('<H', b, pe + 20)[0]
    optional = pe + 24
    directory = optional + (112 if struct.unpack_from('<H', b, optional)[0] == 0x20b else 96)
    sections = []
    for n in range(count):
        vsize, va, rawsize, raw = struct.unpack_from('<IIII', b, optional + size + n * 40 + 8)
        sections.append((va, max(vsize, rawsize), raw))
    def offset(rva):
        for va, length, raw in sections:
            if va <= rva < va + length:
                return raw + rva - va
        raise ValueError(f'Invalid PE RVA in {path.name}')
    rva = struct.unpack_from('<I', b, directory + 8)[0]
    if not rva:
        return []
    cursor = offset(rva)
    result = []
    while any(b[cursor:cursor + 20]):
        name = offset(struct.unpack_from('<I', b, cursor + 12)[0])
        result.append(b[name:b.index(0, name)].decode('ascii'))
        cursor += 20
    return result

# Debug builds need app-local MSVC debug CRT on a machine without Visual Studio.
# Copy only runtime imports actually required by these binaries, never OS DLLs.
runtime = re.compile(r'^(?:vcruntime140|msvcp140|concrt140|ucrtbased).*\.dll$', re.I)
pending = list(app.rglob('*.dll')) + list(app.glob('*.exe'))
visited = set()
copied = []
while pending:
    path = pending.pop()
    if path in visited:
        continue
    visited.add(path)
    for name in imports(path):
        if not runtime.match(name) or (app / name).exists():
            continue
        dependency = Path(os.environ['SystemRoot']) / 'System32' / name
        if not dependency.is_file():
            raise FileNotFoundError(f'Required debug runtime: {name}')
        shutil.copy2(dependency, app / name)
        copied.append(name)
        pending.append(app / name)

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

files = ['flutterrhythmquake.exe', 'rq_station_core.dll', 'flutter_windows.dll', 'data/flutter_assets/kernel_blob.bin']
manifest = {'schema': 'rhythmquake_network_debug_build_v1', 'entrypoint': 'lib/main_network_diagnostic.dart', 'mode': 'Debug', 'files': [{'path': name, 'sha256': sha(app / name)} for name in files], 'appLocalRuntime': copied}
(app / 'network_diagnostic_build.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
shutil.copy2(root / 'build/diagnostics/NetworkDiagnosticExport.exe', bundle / 'NetworkDiagnosticExport.exe')
shutil.copy2(Path(__file__).with_name('README.md'), bundle / '使用说明.md')
output = bundle.with_suffix('.zip')
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for file in bundle.rglob('*'):
        if file.is_file():
            archive.write(file, file.relative_to(bundle))
print(json.dumps({'zip': str(output), 'bytes': output.stat().st_size, 'sha256': sha(output), 'appLocalRuntime': copied}, ensure_ascii=False))
