#!/bin/sh
# platform: host-agnostic
# A configured tree describes the macOS target, whatever the build host: its config.gypi (shipped as
# process.config) names a .dylib shlib_suffix and an xcode_version, and the V8 it builds has the features a
# native 10.9 build has. Node's configure picks wasm SIMD256 revectorization by the HOST's platform (on for any non-macOS host), which
# patches/0012-linux-host-toolset.patch makes the target's; and mksnapshot picks some builtins' code by the host
# compiler's __SSE3__, which a Mac host defines and a Linux host-cc must too; and V8's heap must confine its
# mmap hints for a macOS target on any host, since mksnapshot writes those addresses into the snapshot.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
SRC="$(sh "$root/build/paths.sh" | sed -n 's/^SRC=//p')"
[ -f "$SRC/config.gypi" ] || { echo "not configured ($SRC/config.gypi) -- skipping"; exit 77; }
if grep -Eq "[\"']v8_enable_wasm_simd256_revec[\"']: 1" "$SRC/config.gypi"; then
  echo "FAIL: $SRC/config.gypi enables V8's wasm SIMD256 revectorizer, which a 10.9 build of this node does not have"; exit 1
fi
grep -Eq "[\"']shlib_suffix[\"']: [\"'][0-9]+\.dylib[\"']" "$SRC/config.gypi" \
  && grep -Eq "[\"']xcode_version[\"']:" "$SRC/config.gypi" \
  || { echo "FAIL: $SRC/config.gypi describes the build host (shlib_suffix, xcode_version), not the macOS target; node carries it as process.config"; exit 1; }
grep -Eq "[\"']target_arch[\"']: [\"']x64[\"']" "$SRC/config.gypi" \
  || { echo "FAIL: $SRC/config.gypi does not describe an x64 target"; exit 1; }
grep -q '^#if V8_OS_DARWIN || defined(V8_TARGET_OS_MACOS)$' "$SRC/deps/v8/src/heap/heap.h" \
  || { echo "FAIL: $SRC's V8 heap confines its mmap hints only on a Darwin host, so a Linux-built mksnapshot writes other heap addresses into the startup snapshot"; exit 1; }
hcc="$(sh "$root/build/paths.sh" | sed -n 's/^NODE_WORK=//p')/build-tools/host-cc"
if [ -x "$hcc" ]; then
  "$hcc" -dM -E -x c /dev/null | grep -q '^#define __SSE3__ 1$' \
    || { echo "FAIL: $hcc does not define __SSE3__, so mksnapshot would leave ArrayIncludes/IndexOf's SIMD path out of the snapshot"; exit 1; }
fi
echo "PASS: v8-features"
