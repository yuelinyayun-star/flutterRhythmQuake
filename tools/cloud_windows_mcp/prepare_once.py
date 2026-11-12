"""Provision independent, expiring forwarding keys without changing cloud MCP."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex

import paramiko

from prepare_relay import keypair

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT/'build/once_mcp_private'


def main():
    PRIVATE.mkdir(exist_ok=True)
    settings_file = PRIVATE/'session.json'
    if settings_file.exists():
        raise RuntimeError('Existing session must be inspected rather than overwritten')
    sid = secrets.token_hex(4)
    host, remote_port = '64.90.20.78', 18779
    expires = dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=24)
    cloud_user, reader_user = 'rq-tmp-'+sid, 'rq-rd-'+sid
    cloud_key = keypair(PRIVATE/'device_ed25519')
    reader_key = keypair(PRIVATE/'reader_ed25519')
    c = paramiko.SSHClient()
    c.load_system_host_keys()
    c.set_missing_host_key_policy(paramiko.RejectPolicy())
    c.connect(host, username='root', password=os.environ['RQ_RELAY_PASSWORD'],
              allow_agent=False, look_for_keys=False, timeout=15)
    def run(command):
        _, out, err = c.exec_command(command, timeout=20)
        output, error = out.read().decode(), err.read().decode()
        if out.channel.recv_exit_status():
            raise RuntimeError(error or output or 'Relay command failed')
        return output
    try:
        run(f"test -z \"$(ss -lntH 'sport = :{remote_port}')\"; ! id {cloud_user} >/dev/null 2>&1; ! id {reader_user} >/dev/null 2>&1")
        key = c.get_transport().get_remote_server_key()
        (PRIVATE/'known_hosts').write_text(f'{host} {key.get_name()} {key.get_base64()}\n', encoding='ascii')
        for user, public, direction in [(cloud_user, cloud_key, 'remote'), (reader_user, reader_key, 'local')]:
            permission = 'permitlisten' if direction == 'remote' else 'permitopen'
            options = f'restrict,port-forwarding,{permission}="127.0.0.1:{remote_port}",expiry-time="{expires.strftime("%Y%m%d%H%M%SZ")}",command="/bin/false"'
            authorized = options+' '+public+'\n'
            run(f'''set -eu
useradd --create-home --shell /bin/sh {user}
install -d -m 700 -o {user} -g {user} /home/{user}/.ssh
printf %s {shlex.quote(authorized)} > /home/{user}/.ssh/authorized_keys
chmod 600 /home/{user}/.ssh/authorized_keys
chown {user}:{user} /home/{user}/.ssh/authorized_keys
''')
        block = f'''
# BEGIN RHYTHMQUAKE TEMP MCP {sid} expires {expires.isoformat()}
Match all
Match User {cloud_user},{reader_user}
    PubkeyAuthentication yes
    PasswordAuthentication no
    AuthenticationMethods publickey
    PermitTTY no
    X11Forwarding no
    AllowAgentForwarding no
    ForceCommand /bin/false
Match User {cloud_user}
    AllowTcpForwarding remote
    PermitListen 127.0.0.1:{remote_port}
    PermitOpen none
Match User {reader_user}
    AllowTcpForwarding local
    PermitListen none
    PermitOpen 127.0.0.1:{remote_port}
Match all
# END RHYTHMQUAKE TEMP MCP {sid}
'''
        with c.open_sftp() as s:
            path = '/etc/ssh/sshd_config'
            original = s.open(path, 'rb').read()
            try:
                with s.open(path, 'wb') as f:
                    f.write(original.rstrip()+b'\n'+block.encode('ascii'))
                run('/usr/sbin/sshd -t && systemctl reload ssh')
            except Exception:
                with s.open(path, 'wb') as f:
                    f.write(original)
                run('/usr/sbin/sshd -t && systemctl reload ssh')
                raise
        settings = {'sessionId': sid, 'host': host, 'remotePort': remote_port,
            'devicePort': 18780, 'readerPort': 18781,
            'deviceUser': cloud_user, 'readerUser': reader_user,
            'expiresUtc': expires.isoformat(), 'authKey': secrets.token_hex(32),
            'maxSessionSeconds': 7200}
        settings_file.write_text(json.dumps(settings, indent=2), encoding='utf8')
        print(json.dumps({k:v for k,v in settings.items() if k != 'authKey'}))
    finally:
        c.close()


if __name__ == '__main__':
    main()
