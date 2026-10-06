"""Install only the independent collector files; never edit the cloud drive."""
from __future__ import annotations

import configparser
import os
from pathlib import Path
import pwd
import shutil
import subprocess

from upload_telegram import discover


def main() -> None:
    if os.geteuid() != 0:
        raise SystemExit("Run the deployment installer as root")
    source = Path(__file__).resolve().parent
    existing = Path('/etc/rclone/yuelincloud.conf')
    discover(existing)
    account = pwd.getpwnam('filebrowser')
    base = Path('/opt/rhythmquake-collector')
    config = Path('/etc/rhythmquake-collector')
    state = Path('/var/lib/rhythmquake-collector')
    for directory, owner, group, mode in [
        (base, 0, 0, 0o755), (config, 0, account.pw_gid, 0o750),
        (state, account.pw_uid, account.pw_gid, 0o700),
        (state / 'active', account.pw_uid, account.pw_gid, 0o700),
        (state / 'outbox', account.pw_uid, account.pw_gid, 0o700),
        (state / 'runtime', account.pw_uid, account.pw_gid, 0o700),
    ]:
        if directory.is_symlink():
            raise SystemExit('Refusing symlink deployment directory')
        directory.mkdir(parents=True, exist_ok=True)
        os.chown(directory, owner, group)
        directory.chmod(mode)

    # Give the uploader only the two Telegram sections, not R2 credentials.
    current = configparser.ConfigParser(interpolation=None)
    current.read(existing, encoding='utf-8')
    restricted = configparser.ConfigParser(interpolation=None)
    for name in ['tgfs', 'tgfs-webdav']:
        restricted[name] = dict(current[name])
    temp = config / 'telegram.conf.tmp'
    with temp.open('w', encoding='utf-8') as output:
        os.fchmod(output.fileno(), 0o640)
        os.fchown(output.fileno(), 0, account.pw_gid)
        restricted.write(output)
        output.flush()
        os.fsync(output.fileno())
    temp.replace(config / 'telegram.conf')

    env = config / 'collector.env'
    if not env.exists():
        shutil.copyfile(source / 'collector.env.example', env)
        os.chown(env, 0, account.pw_gid)
        env.chmod(0o640)
    for filename in ['upload_telegram.py', 'README.md']:
        shutil.copyfile(source / filename, base / filename)
        (base / filename).chmod(0o644)
    for filename in ['rhythmquake-collector.service',
                     'rhythmquake-replay-upload.service',
                     'rhythmquake-replay-upload.timer']:
        target = Path('/etc/systemd/system') / filename
        shutil.copyfile(source / filename, target)
        target.chmod(0o644)
    subprocess.run(['systemctl', 'daemon-reload'], check=True)
    print('Independent service files installed. No collector or timer started.')


if __name__ == '__main__':
    main()
