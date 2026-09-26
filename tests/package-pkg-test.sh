#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
paths="$(sh "$root/build/paths.sh")"
SRC="$(printf '%s\n' "$paths" | sed -n 's/^SRC=//p')"
[ -x "$SRC/out/Release/node" ] || { echo "not built ($SRC) -- skipping"; exit 77; }
MAVERICKS_ROOT="$root"; export MAVERICKS_ROOT
. "$root/build/msc.sh"
fail() { echo "FAIL: $*"; exit 1; }
L="$(sh "$root/build/version.sh" line)"
T="usr/local/mavergreen/node$L"

sh "$root/build/updater.sh" >/dev/null || fail "build/updater.sh failed"
pkg="$(sh "$root/build/package.sh" pkg | tail -1)"
[ -f "$pkg" ] || fail "package.sh printed '$pkg', which is not a file"

x="$(mktemp -d "${TMPDIR:-/tmp}/package-pkg-test.XXXXXX")"; trap 'rm -rf "$x"' EXIT
pkgutil --expand "$pkg" "$x/p" || fail "pkgutil cannot expand $pkg"
comp="$(grep -l "node$L" "$x"/p/*.pkg/PackageInfo | head -1)"
[ -n "$comp" ] || fail "no component PackageInfo names node$L"
mkdir "$x/root"
gzip -dc "$(dirname "$comp")/Payload" > "$x/payload.cpio" || fail "cannot decompress the node$L payload"
# platform: modern pkgutil --payload-files lists only a product archive's first component (the base), so
#           the node component's payload is listed from its own cpio.
files="$(cpio -it < "$x/payload.cpio" 2>/dev/null)" || fail "cannot list the node$L payload"
for f in bin/node bin/npm bin/npx include/node/node.h mavergreen.plist libexec/mavergreen/build-startup-snapshot; do
  printf '%s\n' "$files" | grep -qx "\./$T/$f" \
    || fail "payload lacks /$T/$f -- not a full Node install inside its mavergreen tree"
done
for f in "Library/Application Support/Mavergreen/node$L-updater.app/Contents/MacOS/node$L-updater" \
         "Library/LaunchAgents/dev.mavergreen.nodejs.node$L-updatecheck.plist"; do
  printf '%s\n' "$files" | grep -qxF "./$f" || fail "payload lacks /$f -- installs would never update"
done
( cd "$x/root" && cpio -id "./$T/mavergreen.plist" < "$x/payload.cpio" 2>/dev/null ) || fail "cannot extract the manifest"
m="$x/root/$T/mavergreen.plist"
for kv in "product=node$L" "group=node" "line=$L" "identifier=dev.mavergreen.nodejs.node$L"; do
  got="$(/usr/libexec/PlistBuddy -c "Print :${kv%%=*}" "$m")" || fail "manifest has no ${kv%%=*}"
  [ "$got" = "${kv#*=}" ] || fail "manifest ${kv%%=*} is '$got', not '${kv#*=}' -- the helper would link the wrong names"
done

long="$(cpio -itv < "$x/payload.cpio" 2>/dev/null)" || fail "cannot list the node$L payload in long form"
for c in npm npx corepack; do
  printf '%s\n' "$long" | grep -E " \./$T/bin/$c( |$)" | grep -q '^-' \
    || fail "bin/$c is not the pinned wrapper (a regular file) -- it would run whichever node is first on PATH"
done
( cd "$x/root" && cpio -id "./$T/lib/node_modules/npm/npmrc" < "$x/payload.cpio" 2>/dev/null ) || true
grep -qx 'update-notifier=false' "$x/root/$T/lib/node_modules/npm/npmrc" 2>/dev/null \
  || fail "npm's builtin npmrc does not disable the update notifier -- it would tell users to npm -g install npm, which the wrapper refuses"
pre="$(dirname "$comp")/Scripts/preinstall"
[ -f "$pre" ] || fail "the node$L component has no preinstall"
grep -q "var/node$L/npm-globals" "$pre" \
  || fail "preinstall does not stash npm globals -- every upgrade would delete the user's global packages"
post="$(dirname "$comp")/Scripts/postinstall"
[ -f "$post" ] || fail "the node$L component has no postinstall"
grep -q "var/node$L/npm-globals" "$post" || fail "postinstall does not restore npm globals"
awk '/^if \[ -z "\$ROOT" \]; then$/{g=1} g&&/build-startup-snapshot \|\| true$/{f=1} /^fi$/{g=0} END{exit !f}' "$post" \
  || fail "postinstall does not run build-startup-snapshot, best-effort, only for the boot volume -- installs would start ~2x slower"

built_as=native; grep -q -- '--cross-compiling' "$SRC/config.status" && built_as=cross
[ -f "$(dirname "$pkg")/build-info-$built_as.txt" ] \
  || fail "no build-info-$built_as.txt: build-info must describe how the tree was BUILT ($built_as, per config.status), not the packaging host"
grep -qx "variant=$built_as" "$(dirname "$pkg")/build-info-$built_as.txt" \
  || fail "build-info-$built_as.txt does not say variant=$built_as"

sh "$SHIPYARD/assert_pkg_installs_in_place.sh" "$pkg" \
  || fail "the pkg would relocate or version-skip over an existing install"

ver="$(cat "$root/VERSION")"
# spec: stand-in-feeds.sh usage -- an unsigned dist gets an unsigned node$L.xml so conformance can require
#       the feed of every updater its pkg installs; never publish this dist.
sh "$SHIPYARD/stand-in-feeds.sh" "$(dirname "$pkg")" "$ver" >&2 || fail "stand-in-feeds.sh failed"
facts="$(sh "$SHIPYARD/artifact-facts.sh" "$(dirname "$pkg")" "$ver" "$root")" \
  || fail "artifact-facts.sh could not read $(dirname "$pkg")"
printf '%s\n' "$facts" | sh "$SHIPYARD/check-artifact-conformance.sh" \
  || fail "artifact conformance (identity, manifest, base, line, install path, 10.9.5 floor) -- read the lines above"
echo "PASS: package-pkg"
