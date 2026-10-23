#!/bin/sh
# platform: macOS-only -- shipyard extracts the pinned component with pkgutil, including on 10.9.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="${MAVERICKS_ROOT:-$(cd "$SELF/.." && pwd)}"
if [ -n "${MAVERICKS_TOOLCHAIN_PREFIX:-}" ]; then
  echo "$MAVERICKS_TOOLCHAIN_PREFIX"; exit 0
fi
. "$SELF/msc.sh"
PIN="$MAVERICKS_ROOT/components/toolchain/version"
VERSION="$(sed -n 's/^VERSION=//p' "$PIN")"
LINE="${VERSION%%.*}"
MODE="${MODE:-$(sh "$SHIPYARD/mavericks_mode.sh")}"
case "$MODE" in
  native) SHORT="clang$LINE"; VARIANT=native ;;
  cross) SHORT="clang$LINE-cross"; VARIANT=cross ;;
  *) echo "fetch-toolchain.sh: invalid mode: $MODE" >&2; exit 1 ;;
esac
CACHE="${MAVERICKS_TOOLCHAIN_CACHE:-$HOME/Library/Caches/mavericks-clang}"
DEST="$CACHE/$VERSION/$VARIANT"
sh "$SHIPYARD/fetch_product_pkg.sh" \
  --asset "mavericks-clang-$LINE-$VARIANT-$VERSION.pkg" "$SHORT" "$VERSION" "$DEST" >&2
[ -x "$DEST/bin/clang" ] || { echo "fetch-toolchain.sh: missing clang in $DEST" >&2; exit 1; }
# platform: packaged SDKs is a sibling-product symlink; this relocatable build cache uses shipyard's SDK.
sdk="$(sh "$SHIPYARD/fetch_sdk.sh")"
if [ -L "$DEST/SDKs" ]; then rm "$DEST/SDKs"; fi
mkdir -p "$DEST/SDKs"
ln -sfn "$sdk" "$DEST/SDKs/MacOSX10.9.sdk"
printf '%s\n' "$DEST"
