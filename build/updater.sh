#!/bin/sh
# platform: host-agnostic
#   usage: sh build/updater.sh
#          Builds node<line>-updater.app, x86_64 for 10.9 with clang22 (build/fetch-clang22.sh), configured
#          afresh under $NODE_WORK/updater by the host's cmake on Linux and shipyard-cmake on a Mac. Refuses
#          one that is not this build's version or that links a product tree, writes the tools that built it
#          to build-tools.txt beside it, and prints the .app path last.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/msc.sh"
. "$SELF/paths.sh"
FULL="$(sh "$SELF/full-version.sh" "${RELEASE_MODE:-auto}")"
if [ "$(uname -s)" = Linux ]; then
  sc="$(command -v cmake)" || { echo "updater.sh: no cmake on PATH" >&2; exit 1; }
else
  # platform: shipyard-cmake lives in the /usr/local/mavergreen/bin link farm, which only login shells
  #           have on PATH.
  sc="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
fi
sy="$(dirname "$SHIPYARD")"
CL="$(sh "$SELF/fetch-clang22.sh")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; NM="$CL/bin/llvm-nm"; STRINGS="$CL/bin/llvm-strings"
export LIPO OTOOL NM STRINGS
bld="$NODE_WORK/updater"
rm -rf "$bld"
"$sc" -S "$MAVERICKS_ROOT" -B "$bld" -DCMAKE_TOOLCHAIN_FILE="$sy/MavericksToolchain.cmake" \
  -DMavericksShipyard_DIR="$sy" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OBJC_COMPILER="$CL/bin/clang" -DCMAKE_OBJC_COMPILER_TARGET=x86_64-apple-macos10.9 \
  -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld --ld-path=$CL/bin/ld64.lld" \
  -DNODE_FULL_VERSION="$FULL" -DMAVERICKS_ALLOW_GENERIC_ICON=ON >&2
"$sc" --build "$bld" --target "$PRODUCT-updater" >&2
app="$bld/$PRODUCT-updater.app"
got="$(sh "$SELF/plist-string.sh" CFBundleShortVersionString "$app/Contents/Info.plist")"
[ "$got" = "$FULL" ] \
  || { echo "updater.sh: $PRODUCT-updater.app says $got, not $FULL -- installed, it would offer this same release forever" >&2; exit 1; }
deps="$("$OTOOL" -L "$app/Contents/MacOS/$PRODUCT-updater")"
if printf '%s\n' "$deps" | sed 1d | grep -qi 'usr/local/mavergreen/'; then
  echo "updater.sh: $PRODUCT-updater links a product tree -- it could not run while replacing it" >&2; exit 1
fi
sh "$SELF/build-tools.sh" "$bld" updater > "$bld/build-tools.txt"
echo "$app"
