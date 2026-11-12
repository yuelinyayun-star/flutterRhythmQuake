"""Visible, bounded Windows MCP session. No service, task, or autorun."""
import argparse
import csv
import ctypes
from ctypes import wintypes as w
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent
LOGS = ROOT/'logs'
STATE = LOGS/'session-state.json'
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def current_sid():
    data = subprocess.check_output(['whoami.exe', '/user', '/fo', 'csv', '/nh'], creationflags=subprocess.CREATE_NO_WINDOW)
    return next(v for row in csv.reader(data.decode(errors='replace').splitlines()) for v in row if v.startswith('S-1-'))


def protect(path, sid):
    adv = ctypes.WinDLL('advapi32', use_last_error=True)
    adv.ConvertStringSecurityDescriptorToSecurityDescriptorW.argtypes = [w.LPCWSTR, w.DWORD, ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p]
    adv.GetSecurityDescriptorDacl.argtypes = [ctypes.c_void_p, ctypes.POINTER(w.BOOL), ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(w.BOOL)]
    adv.SetNamedSecurityInfoW.argtypes = [w.LPWSTR, ctypes.c_int, w.DWORD, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    adv.SetNamedSecurityInfoW.restype = w.DWORD
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    sd = ctypes.c_void_p()
    flags = 'OICI' if path.is_dir() else ''
    if not adv.ConvertStringSecurityDescriptorToSecurityDescriptorW(f'D:P(A;{flags};FA;;;{sid})(A;{flags};FA;;;SY)', 1, ctypes.byref(sd), None):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        present, defaulted, dacl = w.BOOL(), w.BOOL(), ctypes.c_void_p()
        if not adv.GetSecurityDescriptorDacl(sd, ctypes.byref(present), ctypes.byref(dacl), ctypes.byref(defaulted)):
            raise ctypes.WinError(ctypes.get_last_error())
        error = adv.SetNamedSecurityInfoW(str(path), 1, 0x80000004, None, None, dacl, None)
        if error:
            raise ctypes.WinError(error)
    finally:
        kernel.LocalFree(sd)


class Limits(ctypes.Structure):
    _fields_ = [('processTime', ctypes.c_longlong), ('jobTime', ctypes.c_longlong),
        ('flags', w.DWORD), ('minWorking', ctypes.c_size_t), ('maxWorking', ctypes.c_size_t),
        ('activeLimit', w.DWORD), ('affinity', ctypes.c_size_t),
        ('priority', w.DWORD), ('scheduling', w.DWORD)]


class IoCounters(ctypes.Structure):
    _fields_ = [(n, ctypes.c_ulonglong) for n in ['readOps', 'writeOps', 'otherOps', 'readBytes', 'writeBytes', 'otherBytes']]


class Extended(ctypes.Structure):
    _fields_ = [('basic', Limits), ('io', IoCounters), ('processMemory', ctypes.c_size_t),
        ('jobMemory', ctypes.c_size_t), ('peakProcess', ctypes.c_size_t), ('peakJob', ctypes.c_size_t)]


def job_object():
    k = ctypes.WinDLL('kernel32', use_last_error=True)
    k.CreateJobObjectW.argtypes = [ctypes.c_void_p, w.LPCWSTR]
    k.CreateJobObjectW.restype = w.HANDLE
    k.SetInformationJobObject.argtypes = [w.HANDLE, ctypes.c_int, ctypes.c_void_p, w.DWORD]
    k.SetInformationJobObject.restype = w.BOOL
    k.AssignProcessToJobObject.argtypes = [w.HANDLE, w.HANDLE]
    k.AssignProcessToJobObject.restype = w.BOOL
    k.CloseHandle.argtypes = [w.HANDLE]
    handle = k.CreateJobObjectW(None, None)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    info = Extended()
    info.basic.flags = 0x2000  # KILL_ON_JOB_CLOSE
    if not k.SetInformationJobObject(handle, 9, ctypes.byref(info), ctypes.sizeof(info)):
        k.CloseHandle(handle)
        raise ctypes.WinError(ctypes.get_last_error())
    return k, handle


def probe(port, token=None):
    headers = {'Authorization': 'Bearer '+token} if token else {}
    try:
        with OPENER.open(urllib.request.Request(f'http://127.0.0.1:{port}/mcp', headers=headers), timeout=2) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except (OSError, TimeoutError):
        return None


def verify():
    manifest = json.loads((ROOT/'manifest.json').read_text(encoding='utf8'))
    files = manifest['files']
    for i, entry in enumerate(files, 1):
        p = (ROOT/entry['path']).resolve()
        if not p.is_relative_to(ROOT) or not p.is_file():
            raise RuntimeError('Package file missing: '+entry['path'])
        if entry['path'] != 'network-targets.txt' and hashlib.sha256(p.read_bytes()).hexdigest() != entry['sha256']:
            raise RuntimeError('Package checksum mismatch: '+entry['path'])
        if i % 500 == 0 or i == len(files):
            print(f'Verified {i}/{len(files)} files', flush=True)


def stop():
    import psutil
    if not STATE.exists():
        print('No active session state.')
        return
    info = json.loads(STATE.read_text(encoding='utf8'))
    p = psutil.Process(info['pid'])
    if abs(p.create_time()-info['created']) > .01 or not os.path.samefile(p.exe(), sys.executable):
        raise RuntimeError('Session identity no longer matches; no process was stopped.')
    if not any(str(ROOT/'session.py').lower() == a.lower() for a in p.cmdline()):
        raise RuntimeError('Session command does not match; no process was stopped.')
    p.terminate()  # job handle closes; only this session's children are killed
    p.wait(10)
    print('Temporary MCP stopped.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stop', action='store_true')
    parser.add_argument('--test-seconds', type=int)
    args = parser.parse_args()
    LOGS.mkdir(exist_ok=True)
    if args.stop:
        stop()
        return
    if (ROOT/'session.used').exists():
        raise RuntimeError('This extracted session has already ended. Request a new session.')
    verify()
    settings = json.loads((ROOT/'private/session.json').read_text(encoding='utf8'))
    expiry = dt.datetime.fromisoformat(settings['expiresUtc'])
    if dt.datetime.now(dt.timezone.utc) >= expiry:
        raise RuntimeError('This temporary package has expired. Request a new session.')
    from network_check import run as check_network
    print('Checking server connectivity; results will be saved to logs/network.json...', flush=True)
    check_network(ROOT)
    seconds = min(settings['maxSessionSeconds'], max(1, int((expiry-dt.datetime.now(dt.timezone.utc)).total_seconds())))
    if args.test_seconds:
        seconds = min(seconds, args.test_seconds)
    port = settings['devicePort']
    with socket.socket() as s:
        s.bind(('127.0.0.1', port))
    ssh = Path(os.environ.get('SystemRoot', r'C:\Windows'))/'System32/OpenSSH/ssh.exe'
    if not ssh.is_file():
        raise RuntimeError('Windows OpenSSH Client is missing. See logs; no installation was attempted.')
    sid = current_sid()
    for p in [ROOT/'private', ROOT/'private/device_ed25519']:
        protect(p, sid)
    import psutil
    STATE.write_text(json.dumps({'pid': os.getpid(), 'created': psutil.Process().create_time()}), encoding='utf8')
    k, job = job_object()
    children = []
    handles = []
    connected = False
    started = time.monotonic()
    def launch(command, label, env=None):
        output = (LOGS/(label+'.out.log')).open('wb')
        error = (LOGS/(label+'.err.log')).open('wb')
        handles.extend([output, error])
        p = subprocess.Popen(command, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
            stdout=output, stderr=error, creationflags=subprocess.CREATE_NO_WINDOW)
        children.append(p)
        if not k.AssignProcessToJobObject(job, w.HANDLE(int(p._handle))):
            raise ctypes.WinError(ctypes.get_last_error())
        return p
    try:
        env = os.environ.copy()
        env.update({'WINDOWS_MCP_AUTH_KEY': settings['authKey'], 'PYTHONUTF8': '1',
            'PYTHONIOENCODING': 'utf-8', 'ANONYMIZED_TELEMETRY': 'false',
            'PYTHONDONTWRITEBYTECODE': '1', 'FASTMCP_HOME': str(LOGS/'fastmcp')})
        print('[1/2] Starting authenticated MCP...', flush=True)
        mcp = launch([sys.executable, '-B', '-m', 'windows_mcp', 'serve', '--config', str(ROOT/'server.toml'),
            '--transport', 'streamable-http', '--host', '127.0.0.1', '--port', str(port), '--stateless-http'], 'mcp', env)
        deadline = time.monotonic()+75
        while probe(port) != 401:
            if mcp.poll() is not None:
                raise RuntimeError(f'MCP exited ({mcp.returncode}); see logs/mcp.err.log')
            if time.monotonic() > deadline:
                raise RuntimeError('MCP startup timed out; see logs/mcp.err.log')
            time.sleep(.5)
        args = [str(ssh), '-N', '-T', '-v', '-i', str(ROOT/'private/device_ed25519'),
            '-o', 'UserKnownHostsFile="'+str(ROOT/'private/known_hosts')+'"', '-o', 'StrictHostKeyChecking=yes',
            '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes',
            '-o', 'ConnectTimeout=12', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2',
            '-R', f'127.0.0.1:{settings["remotePort"]}:127.0.0.1:{port}',
            settings['deviceUser']+'@'+settings['host']]
        print('[2/2] Connecting temporary outbound tunnel...', flush=True)
        tunnel = launch(args, 'ssh')
        deadline = time.monotonic()+35
        target = f'remote forward success for: listen 127.0.0.1:{settings["remotePort"]}'
        while target not in (LOGS/'ssh.err.log').read_text(encoding='utf8', errors='replace'):
            if tunnel.poll() is not None:
                raise RuntimeError(f'Tunnel exited ({tunnel.returncode}); see logs/ssh.err.log')
            if time.monotonic() > deadline:
                raise RuntimeError('Tunnel timed out; see logs/ssh.err.log')
            time.sleep(.5)
        ready = {'state': 'ready', 'session': settings['sessionId'], 'pid': os.getpid(),
            'expiresUtc': min(expiry, dt.datetime.now(dt.timezone.utc)+dt.timedelta(seconds=max(0, seconds-(time.monotonic()-started)))).isoformat()}
        (LOGS/'status.json').write_text(json.dumps(ready), encoding='utf8')
        connected = True
        (ROOT/'session.used').write_text('active\n', encoding='ascii')
        print('\nCONNECTED. Tell Codex the temporary MCP is ready.\nKeep this window open. Close it or press Ctrl+C to disconnect.\nSession lasts at most 2 hours; no autorun is installed.', flush=True)
        while time.monotonic()-started < seconds:
            for p in children:
                if p.poll() is not None:
                    raise RuntimeError(f'A session process exited ({p.returncode}); inspect logs.')
            time.sleep(.5)
        print('Session time limit reached.', flush=True)
    finally:
        k.CloseHandle(job)
        for p in children:
            if p.poll() is None:
                try:
                    p.wait(8)
                except subprocess.TimeoutExpired:
                    p.kill()
        for f in handles:
            f.close()
        STATE.unlink(missing_ok=True)
        (LOGS/'status.json').write_text(json.dumps({'state': 'stopped'}), encoding='utf8')
        if connected:
            (ROOT/'session.used').write_text('ended\n', encoding='ascii')
            (ROOT/'private/device_ed25519').unlink(missing_ok=True)
            (ROOT/'private/session.json').unlink(missing_ok=True)


if __name__ == '__main__':
    for s in [sys.stdout, sys.stderr]:
        if hasattr(s, 'reconfigure'):
            s.reconfigure(encoding='utf8')
    try:
        main()
    except KeyboardInterrupt:
        print('Session stopped.')
    except Exception:
        LOGS.mkdir(exist_ok=True)
        (LOGS/'startup-error.txt').write_text(traceback.format_exc(), encoding='utf8')
        print('START FAILED. See logs/startup-error.txt and logs/*.err.log', flush=True)
        traceback.print_exc()
        sys.exit(1)
