# Public Release Telegram Archive

Public read-only folder: [RhythmQuake public packages](https://file.yuelinrhythm.top/public/share/Rfvwpk6z7f0uEcMWc_sa1g).

Independent single-worker server job. Reads the public GitHub release API for
`yuelinyayun-star/flutterRhythmQuake`; no GitHub write token or frontend session
is needed. Initial execution archives the current latest public release. Later
executions include all public releases published from that initial timestamp,
so releases published between polls are not lost. Older releases are not
automatically backfilled. Development builds and unrelated assets are ignored.

Destination in the existing Telegram cloud source:

```text
RhythmQuake公开版/
  v1.0.5.21-public/
    Windows/   (EXE and .sha256)
    Android/   (APK and .sha256)
    Linux/     (tar.gz and .sha256)
    Web/       (ZIP and .sha256)
```

Uses the verified `tgfs` alias and loopback WebDAV gateway directly, not the
asynchronous FUSE upload cache. Each original asset is streamed to one reusable
staging file, checked against GitHub's SHA-256 digest, uploaded immutably, and
read back with a streaming SHA-256 check before a durable receipt is recorded.
Failures retain staging and retry; verified receipts prevent repeat uploads.
An existing different object is never overwritten. Readback occurs at upload
time, not as a recurring full integrity scan.

Deploy `mirror.py` to `/opt/rhythmquake-release-mirror/`. Provide a root-owned
`/etc/rhythmquake-release-mirror/telegram.conf` readable by group `filebrowser`
(0640), containing only the existing `tgfs` and `tgfs-webdav` sections. Do not
put credentials in this repository. Create state directory
`/var/lib/rhythmquake-release-mirror` owned by `filebrowser`, mode 0700.
Install the included systemd units into `/etc/systemd/system`, reload, and enable
`rhythmquake-release-mirror.timer`. Run the service once for initial archival.

The timer checks every 15 minutes after the previous run ends. Transfers are
serial with 1 MiB buffers and no multi-thread transfers. The unit caps memory
at 256 MiB and CPU at 20% of one core; it does not change the replay collector,
KMA, FileBrowser, or TGFS service configuration. Staging is limited to one asset
of at most 512 MiB, with a required 128 MiB free-space reserve. Verified staging
is immediately deleted. Only small JSON receipts remain on the server.

Tests: `python -m unittest discover -s server/release_mirror -p "test_*.py"`.
