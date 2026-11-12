"""Build an offline, relocatable MCP runtime with separate cloud/client keys."""
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import secrets
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/cloud_windows_mcp_build'
BUNDLE = ROOT / 'build/cloud_windows_mcp/RhythmQuakeCloudMCP'
SOURCE = Path(__file__).resolve().parent


def copytree(source, target):
    def link_or_copy(src, dst):
        if Path(dst).exists():
            return dst
        try:
            os.link(src, dst)
            return dst
        except OSError:
            return shutil.copy2(src, dst)
    shutil.copytree(source, target, dirs_exist_ok=True, copy_function=link_or_copy,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))


def main():
    BUNDLE.mkdir(parents=True, exist_ok=True)
    runtime = next((BUILD / 'python').glob('cpython-3.14.*-windows-x86_64-none'))
    copytree(runtime, BUNDLE / 'runtime')
    copytree(BUILD / 'site-packages', BUNDLE / 'runtime/Lib/site-packages')
    for name in ['Install.ps1', 'Supervise.ps1', 'Stop.ps1', 'Start.cmd', 'Stop.cmd', 'README.md']:
        text = (SOURCE / name).read_text(encoding='utf-8-sig')
        (BUNDLE / name).write_text(text, encoding='utf-8-sig' if name.endswith('.ps1') else 'utf-8')
    (BUNDLE / 'package.id').write_text('rhythmquake-cloud-windows-mcp-v1\n', encoding='ascii')
    private = BUNDLE / 'private'
    private.mkdir(exist_ok=True)
    for name in ['cloud_ed25519', 'known_hosts']:
        shutil.copy2(BUILD / 'secrets' / name, private / name)
    connection = private / 'connection.json'
    if not connection.exists():
        connection.write_text(json.dumps({'authKey': secrets.token_hex(32)}, indent=2), encoding='utf-8')
    dependencies = sorted(f'{d.metadata["Name"]}=={d.version}' for d in
                          importlib.metadata.distributions(path=[str(BUILD / 'site-packages')]))
    (BUNDLE / 'dependencies.txt').write_text('\n'.join(dependencies) + '\n', encoding='utf-8')
    manifest = []
    for file in sorted(BUNDLE.rglob('*')):
        relative = file.relative_to(BUNDLE).as_posix()
        if file.is_file() and relative not in ('manifest.json',) and not relative.startswith('logs/') and '__pycache__' not in file.parts and relative != 'private/processes.json':
            manifest.append({'path': relative, 'sha256': hashlib.sha256(file.read_bytes()).hexdigest()})
    (BUNDLE / 'manifest.json').write_text(json.dumps({'files': manifest}, ensure_ascii=False), encoding='utf-8')
    archive = BUNDLE.parent / 'RhythmQuake-Cloud-MCP-Windows-x64.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=4) as z:
        for entry in manifest:
            z.write(BUNDLE / entry['path'], 'RhythmQuakeCloudMCP/' + entry['path'])
        z.write(BUNDLE / 'manifest.json', 'RhythmQuakeCloudMCP/manifest.json')
    print(json.dumps({'archive': str(archive), 'bytes': archive.stat().st_size,
                      'files': len(manifest), 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
