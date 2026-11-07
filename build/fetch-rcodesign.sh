#!/bin/sh
# platform: host-agnostic
#   usage: sh build/fetch-rcodesign.sh     prints the path of rcodesign (apple-codesign) at the release
#          components/rcodesign/version pins, for this host (x86_64 Linux or a modern Mac), verified against
#          that release's own SHA256SUMS. CI-only: it signs the guest's sandbox test fixture, never the product.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/msc.sh"
. "$SHIPYARD/mavericks_fetch.sh"
v="$(tr -d ' \t\n' < "$SELF/../components/rcodesign/version")"
case "$(uname -s):$(uname -m)" in
  Linux:x86_64) triple=x86_64-unknown-linux-musl ;;
  Darwin:*) triple=macos-universal ;;
  *) echo "fetch-rcodesign: no rcodesign build for $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac
asset="apple-codesign-$v-$triple.tar.gz"
base="https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F$v"
cache="${MAVERGREEN_RCODESIGN_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mavergreen-rcodesign}/$v"
exe="$cache/apple-codesign-$v-$triple/rcodesign"
if [ ! -x "$exe" ]; then
  mkdir -p "$cache"
  shipyard_curl "$base/SHA256SUMS" "$cache/SHA256SUMS"
  sha="$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' "$cache/SHA256SUMS")"
  [ -n "$sha" ] || { echo "fetch-rcodesign: $asset is not listed in the release's SHA256SUMS" >&2; exit 1; }
  shipyard_fetch_verified "$base/$asset" "$sha" "$cache" "$asset" >&2
  tar -xzf "$cache/$asset" -C "$cache"
fi
[ -x "$exe" ] || { echo "fetch-rcodesign: $asset holds no rcodesign at $exe" >&2; exit 1; }
printf '%s\n' "$exe"
