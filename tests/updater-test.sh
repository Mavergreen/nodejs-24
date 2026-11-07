#!/bin/sh
# platform: host-agnostic
# The node<line>-updater.app build/updater.sh built (read with clang22's llvm tools, on any host): its
# registry-derived identity and feed, the family's org key, this build's version, x86_64 for 10.9, no link
# into a product tree, and a record of the tools that built it.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
MAVERICKS_ROOT="$root"; export MAVERICKS_ROOT
fail() { echo "FAIL: $*"; exit 1; }
L="$(sh "$root/build/version.sh" line)"
NODE_WORK="$(sh "$root/build/paths.sh" | sed -n 's/^NODE_WORK=//p')"
app="$NODE_WORK/updater/node$L-updater.app"
[ -d "$app" ] || { echo "no updater built at $app -- run build/updater.sh; skipping"; exit 77; }
plist="$app/Contents/Info.plist"
get() { sh "$root/build/plist-string.sh" "$1" "$plist" || fail "Info.plist has no $1"; }
check() { [ "$2" = "$3" ] || fail "$1 is '$2', not '$3'"; }
check CFBundleIdentifier "$(get CFBundleIdentifier)" "dev.mavergreen.nodejs.node$L.updater"
check SUFeedURL "$(get SUFeedURL)" "https://github.com/Mavergreen/nodejs-$L/releases/latest/download/node$L.xml"
. "$root/build/msc.sh"
org_key="$(tr -d '[:space:]' < "$SHIPYARD/../updater/ed25519_key.pub")" \
  || fail "cannot read the family's org key at $SHIPYARD/../updater/ed25519_key.pub"
[ -n "$org_key" ] || fail "the family's org key is empty"
check "committed updater/ed25519_key.pub (every installed updater trusts only the org key)" \
  "$(tr -d '[:space:]' < "$root/updater/ed25519_key.pub")" "$org_key"
check SUPublicEDKey "$(get SUPublicEDKey)" "$org_key"
check CFBundleShortVersionString "$(get CFBundleShortVersionString)" "$(sh "$root/build/full-version.sh")"
CL="$(sh "$root/build/fetch-clang22.sh")"
exe="$app/Contents/MacOS/node$L-updater"
check "updater architecture" "$("$CL/bin/llvm-lipo" -info "$exe" 2>/dev/null | sed -n 's/.*: //p' | xargs)" "x86_64"
check "updater deployment target (it must run on 10.9)" \
  "$("$CL/bin/llvm-otool" -l "$exe" | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&/version /{print $2; exit}')" "10.9"
deps="$("$CL/bin/llvm-otool" -L "$exe")" || fail "llvm-otool cannot read $exe"
printf '%s\n' "$deps" | sed 1d | grep -qi 'usr/local/mavergreen/' \
  && fail "the updater links a product tree -- it could not run while replacing it"
tools="$(dirname "$app")/build-tools.txt"
grep -q '^updater-cmake=.' "$tools" 2>/dev/null && grep -q '^updater-build-tool=.' "$tools" \
  || fail "$tools does not record the cmake and build tool that built the updater"
echo "PASS: updater"
