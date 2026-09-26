#!/bin/sh
#   usage: sh build/updater.sh
#          Builds node<line>-updater.app out of tree under $NODE_WORK/updater with shipyard-cmake, refuses
#          one that links a product tree, and prints the .app path last.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/msc.sh"
. "$SELF/paths.sh"
FULL="$(sh "$SELF/full-version.sh" "${RELEASE_MODE:-auto}")"
bld="$NODE_WORK/updater"
# platform: shipyard-cmake lives in the /usr/local/mavergreen/bin link farm, which only login shells
#           have on PATH.
sc="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
"$sc" -S "$MAVERICKS_ROOT" -B "$bld" -DNODE_FULL_VERSION="$FULL" -DMAVERICKS_ALLOW_GENERIC_ICON=ON \
  -DCMAKE_OBJC_COMPILER=/usr/bin/clang -DCMAKE_TOOLCHAIN_FILE="$SHIPYARD/../MavericksToolchain.cmake" >&2
# platform: shipyard copies Info.plist into the .app only when the executable relinks, and a new
#           version changes only the plist, so an incremental rebuild keeps the previous version.
"$sc" --build "$bld" --target "$PRODUCT-updater" --clean-first >&2
app="$bld/$PRODUCT-updater.app"
got="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[ "$got" = "$FULL" ] \
  || { echo "updater.sh: $PRODUCT-updater.app says $got, not $FULL -- installed, it would offer this same release forever" >&2; exit 1; }
deps="$(otool -L "$app/Contents/MacOS/$PRODUCT-updater")"
if printf '%s\n' "$deps" | sed 1d | grep -qi 'usr/local/mavergreen/'; then
  echo "updater.sh: $PRODUCT-updater links a product tree -- it could not run while replacing it" >&2; exit 1
fi
echo "$app"
