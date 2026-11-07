#!/bin/sh
# platform: host-agnostic
# build/package.sh refuses, by name and before packaging anything, an updater that is not a built app and
# a build whose tools went unrecorded: build-info must name the tools that built what ships.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
fail() { echo "FAIL: $*"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/package-refuses.XXXXXX")"; trap 'rm -rf "$t"' EXIT
V="$(tr -d '[:space:]' < "$root/UPSTREAM_VERSION")"; L="${V%%.*}"
mkdir -p "$t/repo" "$t/work/node-v$V/out/Release" "$t/work/updater/node$L-updater.app/Contents"
cp -R "$root/build" "$root/components" "$root/UPSTREAM_VERSION" "$t/repo/"
printf '%s-mavericks.1\n' "$V" > "$t/repo/VERSION"
printf '#!/bin/sh\n' > "$t/work/node-v$V/out/Release/node"; chmod +x "$t/work/node-v$V/out/Release/node"
app="$t/work/updater/node$L-updater.app"
printf '<plist><dict><key>CFBundleShortVersionString</key><string>%s-mavericks.1</string></dict></plist>\n' "$V" > "$app/Contents/Info.plist"
pkg() { NODE_WORK="$t/work" sh "$t/repo/build/package.sh" pkg 2>&1; }
out="$(pkg)" && fail "packaging an updater with no executable succeeded"
case "$out" in *"Contents/MacOS/node$L-updater"*) ;; *) fail "the refusal must name the missing executable (got: $out)" ;; esac
mkdir -p "$app/Contents/MacOS"; printf '#!/bin/sh\n' > "$app/Contents/MacOS/node$L-updater"; chmod +x "$app/Contents/MacOS/node$L-updater"
out="$(pkg)" && fail "packaging with no record of the build tools succeeded"
case "$out" in *"$t/work/build-tools.txt"*) ;; *) fail "the refusal must name the missing build-tools.txt (got: $out)" ;; esac
echo 'build-make=GNU Make 9' > "$t/work/build-tools.txt"
out="$(pkg)" && fail "packaging with no record of the updater's build tools succeeded"
case "$out" in *"$t/work/updater/build-tools.txt"*) ;; *) fail "the refusal must name the updater's missing build-tools.txt (got: $out)" ;; esac
[ ! -e "$t/work/dist" ] || fail "a refused package must leave no dist"
echo "PASS: package-refuses"
