#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
command -v shipyard-cmake >/dev/null 2>&1 || [ -x /usr/local/mavergreen/bin/shipyard-cmake ] \
  || { echo "no shipyard-cmake -- skipping"; exit 77; }
fail() { echo "FAIL: $*"; exit 1; }
L="$(sh "$root/build/version.sh" line)"

app="$(sh "$root/build/updater.sh" | tail -1)" || fail "build/updater.sh failed"
[ -d "$app" ] || fail "build/updater.sh printed '$app', which is not an .app"
[ "${app##*/}" = "node$L-updater.app" ] || fail "updater is named ${app##*/}, not node$L-updater.app"
plist="$app/Contents/Info.plist"
get() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || fail "Info.plist has no $1"; }
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
exe="$app/Contents/MacOS/node$L-updater"
check "updater architecture" "$(lipo -info "$exe" 2>/dev/null | sed -n 's/.*: //p' | xargs)" "x86_64"
check "updater deployment target (it must run on 10.9)" \
  "$(otool -l "$exe" | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&/version /{print $2; exit}')" "10.9"
deps="$(otool -L "$exe")" || fail "otool cannot read $exe"
printf '%s\n' "$deps" | sed 1d | grep -qi 'usr/local/mavergreen/' \
  && fail "the updater links a product tree -- it could not run while replacing it"
full="$(sh "$root/build/full-version.sh")"
next="${full%.*}.$(( ${full##*.} + 1 ))"
trap 'printf "%s\n" "$full" > "$root/VERSION"' EXIT
printf '%s\n' "$next" > "$root/VERSION"
app="$(sh "$root/build/updater.sh" | tail -1)" || fail "build/updater.sh failed on a repackage"
check "CFBundleShortVersionString after a repackage rebuilt in the same build dir (an old one offers the same update daily)" \
  "$(get CFBundleShortVersionString)" "$next"
echo "PASS: updater"
