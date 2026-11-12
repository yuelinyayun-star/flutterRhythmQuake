"""Provision restricted SSH forwarding accounts; never deploy APP source."""
import argparse
import json
import os
from pathlib import Path
import shlex
import time

import paramiko
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def keypair(path: Path) -> str:
    if not path.exists():
        key = Ed25519PrivateKey.generate()
        path.write_bytes(key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH,
            serialization.NoEncryption()))
        path.with_suffix('.pub').write_bytes(key.public_key().public_bytes(
            serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH))
    return path.with_suffix('.pub').read_text(encoding='ascii').strip()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--secrets', type=Path, required=True)
    p.add_argument('--host', required=True)
    p.add_argument('--port', type=int, default=18769)
    a = p.parse_args()
    a.secrets.mkdir(parents=True, exist_ok=True)
    cloud = keypair(a.secrets / 'cloud_ed25519')
    reader = keypair(a.secrets / 'reader_ed25519')
    c = paramiko.SSHClient()
    c.load_system_host_keys()
    c.set_missing_host_key_policy(paramiko.RejectPolicy())
    c.connect(a.host, username='root', password=os.environ['RQ_RELAY_PASSWORD'],
              allow_agent=False, look_for_keys=False, timeout=15)
    try:
        hostkey = c.get_transport().get_remote_server_key()
        (a.secrets / 'known_hosts').write_text(
            f'{a.host} {hostkey.get_name()} {hostkey.get_base64()}\n', encoding='ascii')
        for user, public_key in [('rq-mcp-cloud', cloud), ('rq-mcp-reader', reader)]:
            options = (f'restrict,port-forwarding,permitlisten="127.0.0.1:{a.port}",'
                       f'permitopen="127.0.0.1:{a.port}",command="/bin/false"')
            authorized = options + ' ' + public_key + '\n'
            commands = f'''set -eu
if ! id {user} >/dev/null 2>&1; then useradd --create-home --shell /bin/sh {user}; fi
test "$(getent passwd {user} | cut -d: -f6)" = /home/{user}
install -d -m 700 -o {user} -g {user} /home/{user}/.ssh
if test -e /home/{user}/.ssh/authorized_keys; then
  test "$(cat /home/{user}/.ssh/authorized_keys)" = {shlex.quote(authorized.strip())}
else
  printf %s {shlex.quote(authorized)} > /home/{user}/.ssh/authorized_keys
fi
chmod 600 /home/{user}/.ssh/authorized_keys
chown {user}:{user} /home/{user}/.ssh/authorized_keys
'''
            _, out, err = c.exec_command(commands, timeout=15)
            error = err.read().decode('utf-8')
            if out.channel.recv_exit_status():
                raise RuntimeError(error)
        # This host disables public keys globally. Scope the override to these
        # forwarding-only accounts and validate before reloading SSH.
        block = f'''# BEGIN RHYTHMQUAKE CLOUD MCP
Match User rq-mcp-cloud,rq-mcp-reader
    PubkeyAuthentication yes
    PasswordAuthentication no
    AuthenticationMethods publickey
    PermitTTY no
    X11Forwarding no
    AllowAgentForwarding no
    ForceCommand /bin/false
Match User rq-mcp-cloud
    AllowTcpForwarding remote
    PermitListen 127.0.0.1:{a.port}
    PermitOpen none
Match User rq-mcp-reader
    AllowTcpForwarding local
    PermitListen none
    PermitOpen 127.0.0.1:{a.port}
# END RHYTHMQUAKE CLOUD MCP
'''
        sftp = c.open_sftp()
        try:
            path = '/etc/ssh/sshd_config'
            original = sftp.open(path, 'rb').read()
            if b'# BEGIN RHYTHMQUAKE CLOUD MCP' not in original:
                backup = path + '.rq-mcp-' + str(int(time.time())) + '.bak'
                with sftp.open(backup, 'wb') as f:
                    f.write(original)
                with sftp.open(path, 'wb') as f:
                    f.write(original.rstrip() + b'\n\n' + block.encode('ascii'))
                _, out, err = c.exec_command('/usr/sbin/sshd -t && systemctl reload ssh', timeout=15)
                error = err.read().decode('utf-8')
                if out.channel.recv_exit_status():
                    with sftp.open(path, 'wb') as f:
                        f.write(original)
                    raise RuntimeError('SSH validation/reload failed; original config restored: ' + error)
        finally:
            sftp.close()
        print(json.dumps({'host': a.host, 'port': a.port,
                          'accounts': ['rq-mcp-cloud', 'rq-mcp-reader'],
                          'hostKeyType': hostkey.get_name()}))
    finally:
        c.close()


if __name__ == '__main__':
    main()
