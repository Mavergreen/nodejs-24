#!/bin/sh
# platform: host-agnostic
#   usage: package-pkg-test.sh     (the one nodejs-*.pkg build/package.sh left in $NODE_WORK/dist)
#          Reads the pkg with stevedore and cpio, as any host can: a full Node install in its mavergreen tree
#          whose node is byte-identical to the built one, the manifest the helper links by, the pinned npm
#          wrappers, the updater and its LaunchAgent, the npm-globals and startup-snapshot hooks, and a
#          build-info that names the tools that built what ships. Then it checks artifact conformance, reading
#          Mach-O with clang22's llvm tools on any host.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
MAVERICKS_ROOT="$root"; export MAVERICKS_ROOT
. "$root/build/msc.sh"
fail() { echo "FAIL: $*"; exit 1; }
paths="$(sh "$root/build/paths.sh")"
SRC="$(printf '%s\n' "$paths" | sed -n 's/^SRC=//p')"
NODE_WORK="$(printf '%s\n' "$paths" | sed -n 's/^NODE_WORK=//p')"
set -- "$NODE_WORK"/dist/nodejs-*.pkg
[ -f "$1" ] || { echo "not packaged (no $NODE_WORK/dist/nodejs-*.pkg) -- run build/build.sh all, build/updater.sh, build/package.sh pkg; skipping"; exit 77; }
[ "$#" -eq 1 ] || fail "$NODE_WORK/dist holds $# nodejs pkgs; one packaging makes one"
pkg="$1"
CL="$(sh "$root/build/fetch-clang22.sh")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; STRINGS="$CL/bin/llvm-strings"
export LIPO OTOOL NM STRINGS
L="$(sh "$root/build/version.sh" line)"
T="usr/local/mavergreen/node$L"
x="$(mktemp -d "${TMPDIR:-/tmp}/package-pkg-test.XXXXXX")"; trap 'rm -rf "$x"' EXIT
SD="$(sh "$SHIPYARD/fetch_stevedore.sh")"
"$SD" expand "$pkg" "$x/p" >/dev/null || fail "stevedore cannot expand $pkg"
comp="$(grep -l "identifier=\"dev.mavergreen.nodejs.node$L\"" "$x"/p/*/PackageInfo | sed 1q)"
[ -n "$comp" ] || fail "no component PackageInfo names dev.mavergreen.nodejs.node$L"
comp="$(dirname "$comp")"
gzip -dc < "$comp/Payload" > "$x/payload.cpio" || fail "the node$L payload must decompress"
mkdir "$x/root"
( cd "$x/root" && cpio -id --quiet < "$x/payload.cpio" ) || fail "cpio must extract the node$L payload"
for f in bin/node bin/npm bin/npx include/node/node.h mavergreen.plist libexec/mavergreen/build-startup-snapshot; do
  [ -e "$x/root/$T/$f" ] || fail "payload lacks /$T/$f -- not a full Node install inside its mavergreen tree"
done
for f in "Library/Application Support/Mavergreen/node$L-updater.app/Contents/MacOS/node$L-updater" \
         "Library/LaunchAgents/dev.mavergreen.nodejs.node$L-updatecheck.plist"; do
  [ -f "$x/root/$f" ] || fail "payload lacks /$f -- installs would never update"
done
[ -f "$SRC/out/Release/node" ] || fail "no built $SRC/out/Release/node to compare the packaged one with"
cmp -s "$x/root/$T/bin/node" "$SRC/out/Release/node" || fail "the packaged node is not byte-identical to the built one"
m="$x/root/$T/mavergreen.plist"
for kv in "product=node$L" "group=node" "line=$L" "identifier=dev.mavergreen.nodejs.node$L"; do
  got="$(sh "$root/build/plist-string.sh" "${kv%%=*}" "$m")" || fail "manifest has no ${kv%%=*}"
  [ "$got" = "${kv#*=}" ] || fail "manifest ${kv%%=*} is '$got', not '${kv#*=}' -- the helper would link the wrong names"
done
for c in npm npx corepack; do
  [ -f "$x/root/$T/bin/$c" ] && [ ! -L "$x/root/$T/bin/$c" ] \
    || fail "bin/$c is not the pinned wrapper (a regular file) -- it would run whichever node is first on PATH"
done
grep -qx 'update-notifier=false' "$x/root/$T/lib/node_modules/npm/npmrc" 2>/dev/null \
  || fail "npm's builtin npmrc does not disable the update notifier -- it would tell users to npm -g install npm, which the wrapper refuses"
pre="$comp/Scripts/preinstall"; post="$comp/Scripts/postinstall"
[ -f "$pre" ] || fail "the node$L component has no preinstall"
grep -q "var/node$L/npm-globals" "$pre" \
  || fail "preinstall does not stash npm globals -- every upgrade would delete the user's global packages"
[ -f "$post" ] || fail "the node$L component has no postinstall"
grep -q "var/node$L/npm-globals" "$post" || fail "postinstall does not restore npm globals"
awk '/^if \[ -z "\$ROOT" \]; then$/{g=1} g&&/build-startup-snapshot \|\| true$/{f=1} /^fi$/{g=0} END{exit !f}' "$post" \
  || fail "postinstall does not run build-startup-snapshot, best-effort, only for the boot volume -- installs would start ~2x slower"
built_as=native; grep -q -- '--cross-compiling' "$SRC/config.status" 2>/dev/null && built_as=cross
info="$(dirname "$pkg")/build-info-$built_as.txt"
[ -f "$info" ] \
  || fail "no build-info-$built_as.txt: build-info must describe how the tree was BUILT ($built_as, per config.status), not the packaging host"
grep -qx "variant=$built_as" "$info" || fail "build-info-$built_as.txt does not say variant=$built_as"
grep -qx "clang22=$(tr -d ' \t\n' < "$root/components/clang22/version")" "$info" || fail "build-info does not name the pinned clang22"
keys="build-make updater-cmake updater-build-tool"
[ "$built_as" = native ] || keys="$keys build-host-cc build-host-cxx"
for k in $keys; do
  grep -q "^$k=." "$info" || fail "build-info does not name $k, a tool that built what ships"
done
sh "$SHIPYARD/assert_pkg_installs_in_place.sh" "$pkg" \
  || fail "the pkg would relocate or version-skip over an existing install"
ver="$(sh "$root/build/plist-string.sh" version "$m")"
d="$x/dist"; mkdir "$d"; cp "$pkg" "$info" "$d/"
# spec: stand-in-feeds.sh usage -- an unsigned dist gets an unsigned node$L.xml so conformance can require
#       the feed of every updater its pkg installs; never publish this dist.
sh "$SHIPYARD/stand-in-feeds.sh" "$d" "$ver" >&2 || fail "stand-in-feeds.sh failed"
facts="$(sh "$SHIPYARD/artifact-facts.sh" "$d" "$ver" "$root")" || fail "artifact-facts.sh could not read $d"
printf '%s\n' "$facts" | sh "$SHIPYARD/check-artifact-conformance.sh" \
  || fail "artifact conformance (identity, manifest, base, line, install path, 10.9.5 floor) -- read the lines above"
echo "PASS: package-pkg"
