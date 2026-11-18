set -Eeuo pipefail

unit=kma-pews-relay.service
relay=/opt/rhythmquake/kma-pews-relay
python="$relay/.venv/bin/python"
live="$relay/kma_pews_relay.py"
verify_url=https://ws.yuelinrhythm.top

systemctl is-active --quiet "$unit"
test "$(systemctl show "$unit" -p WorkingDirectory --value)" = "$relay"
test -f "$live"
test ! -L "$live"
exec 9>/run/lock/rhythmquake-kma-eew-deploy.lock
flock -n 9

stage="$(mktemp -d "$relay/.kma-eew-release.XXXXXXXX")"
candidate="$stage/kma_pews_relay.py"
rollback=0
backup=
finish() {
    local status=$?
    trap - EXIT
    if (( rollback )); then
        echo "Restoring the pre-release relay from $backup" >&2
        if ! cp -a "$backup" "$candidate" || ! mv -f "$candidate" "$live" ||
            ! systemctl restart "$unit" || ! systemctl is-active --quiet "$unit"; then
            echo "Relay rollback failed; backup is $backup" >&2
            status=1
        fi
    fi
    rm -rf -- "$stage"
    exit "$status"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM

tar -xzf - -C "$stage"
cp -a "$live" "$candidate"
before="$(sha256sum "$candidate" | awk '{print $1}')"
cd "$stage"
if git apply --check -p3 kma-eew.patch; then
    git apply -p3 kma-eew.patch
elif git apply --reverse --check -p3 kma-eew.patch; then
    echo "KMA EEW source already present"
else
    echo "KMA EEW release does not match the current relay source ($before)" >&2
    exit 1
fi

PYTHONPATH="$relay" "$python" -B -m unittest -v test_kma_pews_relay.KmaPewsEewEndpointTest
for attempt in {1..3}; do
    if "$python" -B verify_kma_eew.py "$verify_url" --existing; then
        break
    fi
    if (( attempt == 3 )); then
        exit 1
    fi
    sleep 2
done
after="$(sha256sum "$candidate" | awk '{print $1}')"
test "$before" = "$(sha256sum "$live" | awk '{print $1}')"
if [[ "$after" != "$before" ]]; then
    backup_dir="$(mktemp -d /opt/rhythmquake/backups/kma-eew.XXXXXXXX)"
    backup="$backup_dir/kma_pews_relay.py"
    cp -a "$live" "$backup"
    chown --reference="$live" "$candidate"
    chmod --reference="$live" "$candidate"
    rollback=1
    mv -f "$candidate" "$live"
    systemctl restart "$unit"
    echo "Relay backup: $backup"
fi

for attempt in {1..12}; do
    if systemctl is-active --quiet "$unit" &&
        "$python" -B verify_kma_eew.py "$verify_url"; then
        rollback=0
        echo "Verified production relay SHA256 $after"
        exit 0
    fi
    sleep 2
done
exit 1
