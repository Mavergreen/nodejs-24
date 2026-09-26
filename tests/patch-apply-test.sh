#!/bin/sh
# Proves the extracted patches + fixups apply cleanly to the pinned Node source. No compiler.
# Uses a throwaway local work dir; SKIPs (77) when offline.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
NODE_WORK="$(mktemp -d "${TMPDIR:-/tmp}/nodepatch.XXXXXX")"
export NODE_WORK
trap 'rm -rf "$NODE_WORK"' EXIT

curl -fsI https://nodejs.org/dist/ >/dev/null 2>&1 || { echo "offline — skipping"; exit 77; }

sh "$root/build/build.sh" fetch  >/dev/null || { echo "fetch failed"; exit 1; }
sh "$root/build/build.sh" patch  || { echo "FAIL: patches/fixups did not apply cleanly"; exit 1; }

V="$(tr -d '[:space:]' < "$root/UPSTREAM_VERSION")"
SRC="$NODE_WORK/node-v$V"
# Assert the fixups actually changed the sources (guards against a silent no-op on a new Node layout).
grep -q "void\* qos_override" "$SRC/deps/v8/src/heap/safepoint.h" || { echo "FAIL: safepoint.h fixup missing"; exit 1; }
grep -q "'10.9'" "$SRC/common.gypi" || { echo "FAIL: common.gypi target fixup missing"; exit 1; }
echo "PASS: patch-apply"
