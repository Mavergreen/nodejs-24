#!/bin/sh
# platform: host-agnostic
# The V8 a configured tree builds has the features a native 10.9 build has, whatever the build host: Node's
# configure picks wasm SIMD256 revectorization by the HOST's platform (on for any non-macOS host), which
# patches/0012-linux-host-toolset.patch makes the target's; and mksnapshot picks some builtins' code by the host
# compiler's __SSE3__, which a Mac host defines and a Linux host-cc must too, so a Linux-built node matches.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
SRC="$(sh "$root/build/paths.sh" | sed -n 's/^SRC=//p')"
[ -f "$SRC/config.gypi" ] || { echo "not configured ($SRC/config.gypi) -- skipping"; exit 77; }
if grep -Eq "[\"']v8_enable_wasm_simd256_revec[\"']: 1" "$SRC/config.gypi"; then
  echo "FAIL: $SRC/config.gypi enables V8's wasm SIMD256 revectorizer, which a 10.9 build of this node does not have"; exit 1
fi
grep -Eq "[\"']target_arch[\"']: [\"']x64[\"']" "$SRC/config.gypi" \
  || { echo "FAIL: $SRC/config.gypi does not describe an x64 target"; exit 1; }
hcc="$(sh "$root/build/paths.sh" | sed -n 's/^NODE_WORK=//p')/build-tools/host-cc"
if [ -x "$hcc" ]; then
  "$hcc" -dM -E -x c /dev/null | grep -q '^#define __SSE3__ 1$' \
    || { echo "FAIL: $hcc does not define __SSE3__, so mksnapshot would leave ArrayIncludes/IndexOf's SIMD path out of the snapshot"; exit 1; }
fi
echo "PASS: v8-features"
