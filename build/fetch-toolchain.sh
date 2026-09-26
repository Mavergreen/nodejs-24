#!/bin/sh
# build/fetch-toolchain.sh -- resolve a usable mavericks-clang toolchain and print its PREFIX (the dir
# containing bin/clang) on stdout. Everything else goes to stderr; the caller consumes stdout.
#
# Resolution order:
#   1. $MAVERICKS_TOOLCHAIN_PREFIX             -- explicit override (tests, a hand-placed toolchain)
#   2. the pinned install prefix, if populated  -- the .pkg was installed with `installer` (real 10.9 box)
#   3. fetch + verify + unpack into a local cache -- no root, works in CI and on a modern host
#
# (3) is why this exists: the artifact is a macOS component .pkg, but its clang.cfg addresses everything
# through <CFGDIR>-relative paths, so an unpacked payload is a fully working toolchain at any path. We
# unpack rather than `installer`, because a build must not require root.
#
# NOTE ON $SHIPYARD/mavericks_fetch.sh: mav_fetch_pinned is the family's fetch+verify helper, but it ends in
# `tar xf`, and a .pkg is a xar archive -- so it cannot unpack this artifact. The download/verify
# contract below is deliberately identical to it (curl --fail, delete a partial download, checksum
# BEFORE unpacking, never unpack on mismatch), just with pkgutil doing the extraction.
set -eu

SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="${MAVERICKS_ROOT:-$(cd "$SELF/.." && pwd)}"
PIN="$MAVERICKS_ROOT/components/toolchain/version"
[ -f "$PIN" ] || { echo "fetch-toolchain.sh: missing pin: $PIN" >&2; exit 1; }
_pin() { sed -n "s/^$1=//p" "$PIN" | head -1; }

# An explicit prefix short-circuits everything, including the pin.
if [ -n "${MAVERICKS_TOOLCHAIN_PREFIX:-}" ]; then
  echo "$MAVERICKS_TOOLCHAIN_PREFIX"; exit 0
fi

. "$SELF/msc.sh"                                   # sets $SHIPYARD
MODE="${MODE:-$(sh "$SHIPYARD/mavericks_mode.sh")}"     # native on 10.9, else cross

VERSION="$(_pin VERSION)"
RELEASE_BASE="$(_pin RELEASE_BASE)"
case "$MODE" in
  native) VARIANT=native; PREFIX="$(_pin PREFIX_NATIVE)" ;;
  cross)  VARIANT=cross;  PREFIX="$(_pin PREFIX_CROSS)" ;;
  *) echo "fetch-toolchain.sh: unknown MODE '$MODE' (want native|cross)" >&2; exit 1 ;;
esac
[ -n "$VERSION" ] && [ -n "$PREFIX" ] && [ -n "$RELEASE_BASE" ] \
  || { echo "fetch-toolchain.sh: incomplete pin in $PIN" >&2; exit 1; }

CACHE="${MAVERICKS_TOOLCHAIN_CACHE:-$HOME/Library/Caches/mavericks-clang}"   # durable; NOT $TMPDIR
DEST="$CACHE/$VERSION/$VARIANT"

# The Apple 10.9 SDK is never redistributed: the toolchain ships libexec/fetch_sdk.sh and the SDK
# arrives at first use, at the <CFGDIR>-relative path clang.cfg's -isysroot names.
_wire_sdk() {
  _tc="$1"
  if [ -d "$_tc/SDKs/MacOSX10.9.sdk" ]; then return 0; fi
  [ -w "$_tc/SDKs" ] || { echo "fetch-toolchain.sh: $_tc/SDKs is not writable; populate the SDK once with:" >&2
                          echo "  sudo ln -s \"\$(sh $_tc/libexec/fetch_sdk.sh)\" $_tc/SDKs/MacOSX10.9.sdk" >&2
                          return 1; }
  _sdk="$(sh "$_tc/libexec/fetch_sdk.sh")" || { echo "fetch-toolchain.sh: SDK fetch failed" >&2; return 1; }
  ln -sfn "$_sdk" "$_tc/SDKs/MacOSX10.9.sdk"
  echo "fetch-toolchain.sh: wired SDK $_sdk" >&2
}

# 2. Pinned prefix already installed? Use it -- do not download 700MB to duplicate it.
if [ -x "$PREFIX/bin/clang" ]; then
  _wire_sdk "$PREFIX" >&2 || exit 1
  echo "$PREFIX"; exit 0
fi

# 3. Fetch + verify + unpack. Idempotent: an already-unpacked cache entry is reused.
if [ ! -x "$DEST/bin/clang" ]; then
  mkdir -p "$CACHE"
  # The pinned release's own SHA256SUMS is the checksum source, per the family's "consuming a
  # Mavergreen toolchain" convention: VERSION is then the ONE thing to bump, so Renovate can
  # move this pin through the green gate without a human transcribing hashes.
  SUMS="$CACHE/SHA256SUMS-$VERSION"
  [ -f "$SUMS" ] || curl -sL --fail -o "$SUMS" "$RELEASE_BASE/$VERSION/SHA256SUMS" || { rm -f "$SUMS"; echo "fetch-toolchain.sh: cannot fetch SHA256SUMS for $VERSION" >&2; exit 1; }
  # Find the variant's .pkg BY ITS SUFFIX rather than reconstructing the filename: the family has
  # renamed an asset prefix mid-line before (go126- -> golang-), and a pin bump must not 404.
  PKG="$(awk -v v="-$VARIANT-" '$2 ~ /\.pkg$/ && index($2, v) { print $2; exit }' "$SUMS")"
  SHA="$(awk -v v="-$VARIANT-" '$2 ~ /\.pkg$/ && index($2, v) { print $1; exit }' "$SUMS")"
  # An asset that is not listed must FAIL, never pass unverified.
  [ -n "$PKG" ] && [ -n "$SHA" ] || { echo "fetch-toolchain.sh: no '$VARIANT' .pkg listed in $VERSION's SHA256SUMS" >&2; exit 1; }

  TB="$CACHE/$PKG"
  [ -f "$TB" ] || curl -sL --fail -o "$TB" "$RELEASE_BASE/$VERSION/$PKG" || { rm -f "$TB"; echo "fetch-toolchain.sh: download failed: $RELEASE_BASE/$VERSION/$PKG" >&2; exit 1; }
  echo "$SHA  $TB" | shasum -a 256 -c - >&2 || { echo "fetch-toolchain.sh: checksum mismatch; refusing to unpack $TB" >&2; exit 1; }

  TMP="$CACHE/.expand.$VARIANT.$$"
  rm -rf "$TMP"
  trap 'rm -rf "$TMP"' EXIT INT TERM
  pkgutil --expand-full "$TB" "$TMP" >&2
  # install-location is "/", so the payload mirrors the filesystem: strip down to the pinned prefix.
  PAYLOAD="$TMP/Payload$PREFIX"
  [ -x "$PAYLOAD/bin/clang" ] || { echo "fetch-toolchain.sh: no bin/clang under $PAYLOAD -- payload layout changed?" >&2; exit 1; }
  rm -rf "$DEST"; mkdir -p "$(dirname "$DEST")"
  mv "$PAYLOAD" "$DEST"
  rm -rf "$TMP"; trap - EXIT INT TERM
  echo "fetch-toolchain.sh: unpacked $PKG -> $DEST" >&2
fi

_wire_sdk "$DEST" >&2 || exit 1
echo "$DEST"
