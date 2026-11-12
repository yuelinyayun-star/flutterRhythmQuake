"""Local client tunnel; it never ships to the public computer."""
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import time
from once_session import current_sid, protect

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT/'build/once_mcp_private'
settings = json.loads((PRIVATE/'session.json').read_text(encoding='utf8'))
sid = current_sid()
protect(PRIVATE, sid)
protect(PRIVATE/'reader_ed25519', sid)
ssh = Path(os.environ['SystemRoot'])/'System32/OpenSSH/ssh.exe'
args = [str(ssh), '-N', '-T', '-i', str(PRIVATE/'reader_ed25519'),
    '-o', 'UserKnownHostsFile="'+str(PRIVATE/'known_hosts')+'"', '-o', 'StrictHostKeyChecking=yes',
    '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes',
    '-o', 'ConnectTimeout=12', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2',
    '-L', f'127.0.0.1:{settings["readerPort"]}:127.0.0.1:{settings["remotePort"]}',
    settings['readerUser']+'@'+settings['host']]
with (PRIVATE/'reader.err.log').open('wb') as err:
    p = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=err, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        (PRIVATE/'reader-state.json').write_text(json.dumps({'pid':p.pid, 'supervisor':os.getpid()}), encoding='utf8')
        while dt.datetime.now(dt.timezone.utc) < dt.datetime.fromisoformat(settings['expiresUtc']):
            if p.poll() is not None:
                raise RuntimeError('Reader tunnel exited; inspect reader.err.log')
            time.sleep(1)
    finally:
        if p.poll() is None:
            p.terminate()
            p.wait(10)
