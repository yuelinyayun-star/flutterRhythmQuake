import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent
PRIVATE = ROOT/'build/once_mcp_private'


def main():
    settings = json.loads((PRIVATE/'session.json').read_text(encoding='utf8'))
    out = ROOT/'build/one_time_mcp'
    bundle = out/('RhythmQuake-OneTime-MCP-'+settings['sessionId'])
    refreshing = '--refresh' in sys.argv
    if bundle.exists() and not refreshing:
        raise RuntimeError('Bundle already exists; inspect before replacing')
    if refreshing:
        if not (bundle/'manifest.json').is_file():
            raise RuntimeError('Cannot refresh an unknown bundle')
    bundle.mkdir(parents=True, exist_ok=True)
    runtime = ROOT/'build/cloud_windows_mcp/RhythmQuakeCloudMCP/runtime'
    def copy(src, dst):
        try:
            os.link(src, dst)
        except OSError:
            shutil.copy2(src, dst)
        return dst
    if not refreshing:
        shutil.copytree(runtime, bundle/'runtime', copy_function=copy,
            ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copy2(SOURCE/'once_session.py', bundle/'session.py')
    shutil.copy2(SOURCE/'once_network.py', bundle/'network_check.py')
    private = bundle/'private'
    private.mkdir(exist_ok=True)
    for n in ['session.json', 'device_ed25519', 'known_hosts']:
        shutil.copy2(PRIVATE/n, private/n)
    (bundle/'server.toml').write_text('# Temporary MCP; credentials supplied only through child environment.\n', encoding='utf8')
    (bundle/'network-targets.txt').write_text('# 可添加待诊断服务器，每行一个地址，例如 https://example.com/ 或 tcp://example.com:443\n', encoding='utf8')
    for filename, argument in [('Start.cmd', ''), ('Stop.cmd', ' --stop')]:
        (bundle/filename).write_text('@echo off\r\nchcp 65001 >nul\r\nset PYTHONUTF8=1\r\nset PYTHONIOENCODING=utf-8\r\n'
            'cd /d "%~dp0"\r\n"%~dp0runtime\\python.exe" -B "%~dp0session.py"'+argument+'\r\npause\r\n', encoding='utf8')
    (bundle/'README.txt').write_text('公共电脑一次性诊断连接\n\n'
        '1. 完整解压到自己的文件夹，不要在压缩包里直接运行。\n'
        '2. 双击 Start.cmd。出现 CONNECTED 后告诉 Codex。保持窗口打开。\n'
        '3. 关闭该窗口、按 Ctrl+C 或双击 Stop.cmd，即断开本次连接。最多运行两小时。\n'
        '4. 诊断结束后删除解压文件夹和压缩包。正常退出会删除临时私钥和认证文件，强制关闭后请删除整个文件夹。\n'
        '5. 启动时先检查服务器连接，结果在 logs/network.json；即使 MCP 连不上也可把这个文件交给 Codex。\n'
        '   额外待检查地址可写入 network-targets.txt，每行一个 URL。\n\n'
        '无需管理员、不注册服务和开机启动。仅向本机回环地址提供带认证的 MCP，经独立 SSH 隧道连接。\n'
        '这是完整桌面操作权限的临时诊断连接，请在自己的 Windows 登录会话运行。\n'
        '若启动失败，日志在本目录 logs；不要发送 private 目录或将这个包公开分享。\n'
        '凭据有效期至 '+settings['expiresUtc']+'（UTC）；最多一次连续会话。\n'
        '运行环境：Windows 10/11 x64，系统已提供 OpenSSH Client。若系统缺少该组件会明确提示，不会自行安装。\n'
        '上游 Windows-MCP 0.8.8（MIT），随包保留上游运行时、依赖和许可证。\n', encoding='utf8')
    files = [{'path':p.relative_to(bundle).as_posix(), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
        for p in sorted(bundle.rglob('*')) if p.is_file() and p.name not in ['manifest.json', 'session.used'] and 'logs' not in p.relative_to(bundle).parts]
    (bundle/'manifest.json').write_text(json.dumps({'files': files}), encoding='utf8')
    archive = out/'RhythmQuake-OneTime-MCP-Windows-x64.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=4) as z:
        for item in files:
            z.write(bundle/item['path'], bundle.name+'/'+item['path'])
        z.write(bundle/'manifest.json', bundle.name+'/manifest.json')
    sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(sha+'  '+archive.name+'\n', encoding='ascii')
    print(json.dumps({'bundle':str(bundle),'archive':str(archive),'files':len(files),'bytes':archive.stat().st_size,'sha256':sha}))


if __name__ == '__main__':
    main()
