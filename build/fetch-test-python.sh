#!/bin/sh
# platform: host-agnostic -- fetch on the runner, install this verified pkg in the VM.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/msc.sh"
. "$SHIPYARD/mavericks_fetch.sh"
version="$(cat "$SELF/../components/test-python/version")"
asset="python-$version.pkg"
base="https://github.com/Mavergreen/python-315/releases/download/$version"
dest="${1:?usage: fetch-test-python.sh DEST}"
mkdir -p "$dest"
shipyard_curl "$base/SHA256SUMS" "$dest/SHA256SUMS"
sha="$(awk -v name="$asset" '$2 == name {print $1}' "$dest/SHA256SUMS")"
[ -n "$sha" ] || { echo "$asset missing from SHA256SUMS" >&2; exit 1; }
shipyard_fetch_verified "$base/$asset" "$sha" "$dest" "$asset"
