#!/usr/bin/env bash
set -euo pipefail

edition="${1:-public}"
case "$edition" in
  public|personal) ;;
  *) echo "Usage: bash build_linux_edition.sh [public|personal]" >&2; exit 2 ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")"
if [[ "$(uname -s)" != Linux ]]; then
  echo "Run this script with the Linux Flutter SDK on Linux or WSL 2." >&2
  exit 1
fi

version="$(awk '$1 == "version:" {print $2; exit}' pubspec.yaml)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  echo "Expected pubspec version x.y.z+build." >&2
  exit 1
fi

flutter build linux --release --no-pub "--dart-define=RQ_EDITION=$edition"
bundle="build/linux/x64/release/bundle"
test -f "$bundle/flutterrhythmquake"
test -f "$bundle/lib/libapp.so"
test -f "$bundle/data/icudtl.dat"

mkdir -p build/installer
archive="RhythmQuake_${version/+/.}_${edition}_linux_x64.tar.gz"
tar -czf "build/installer/$archive" -C "$bundle" .
(
  cd build/installer
  sha256sum "$archive" > "$archive.sha256"
)
echo "Created build/installer/$archive"
cat "build/installer/$archive.sha256"
