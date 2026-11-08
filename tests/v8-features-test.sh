#!/bin/sh
# platform: host-agnostic
# The V8 a configured tree builds has the features a native 10.9 build has, whatever the build host: Node's
# configure picks wasm SIMD256 revectorization by the HOST's platform (on for any non-macOS host), which
# patches/0012-linux-host-toolset.patch makes the target's, so a Linux-built node matches a Mac-built one.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
SRC="$(sh "$root/build/paths.sh" | sed -n 's/^SRC=//p')"
[ -f "$SRC/config.gypi" ] || { echo "not configured ($SRC/config.gypi) -- skipping"; exit 77; }
if grep -Eq "[\"']v8_enable_wasm_simd256_revec[\"']: 1" "$SRC/config.gypi"; then
  echo "FAIL: $SRC/config.gypi enables V8's wasm SIMD256 revectorizer, which a 10.9 build of this node does not have"; exit 1
fi
grep -Eq "[\"']target_arch[\"']: [\"']x64[\"']" "$SRC/config.gypi" \
  || { echo "FAIL: $SRC/config.gypi does not describe an x64 target"; exit 1; }
echo "PASS: v8-features"
