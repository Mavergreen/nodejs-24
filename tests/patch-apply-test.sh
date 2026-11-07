#!/bin/sh
# platform: host-agnostic
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
grep -q '^command -v python3\.15 .*exec python3\.15 ' "$SRC/configure" || { echo "FAIL: configure Python 3.15 selection missing"; exit 1; }
grep -q '^acceptable_pythons = ((3, 15), (3, 14),' "$SRC/configure" || { echo "FAIL: configure Python 3.15 support missing"; exit 1; }
sh "$root/build/node-gyp-host.sh" "$SRC" "$NODE_WORK/npm-host" >/dev/null \
  || { echo "FAIL: build/node-gyp-host.sh could not give node-gyp's own gyp the Linux-host fix"; exit 1; }
x=gyp/pylib/gyp/xcode_emulation.py
grep -q 'if sys.platform == "darwin":' "$NODE_WORK/npm-host/node_modules/node-gyp/$x" \
  || { echo "FAIL: the host-only node-gyp copy still requires Xcode off macOS"; exit 1; }
if command -v node >/dev/null 2>&1; then
  node -e 'require(process.argv[1] + "/node_modules/node-gyp/lib/node-gyp.js")' "$NODE_WORK/npm-host" \
    || { echo "FAIL: the host-only node-gyp cannot load its modules"; exit 1; }
fi
grep -q 'if sys.platform == "darwin":' "$SRC/deps/npm/node_modules/node-gyp/$x" \
  && { echo "FAIL: the node-gyp that ships inside npm was changed"; exit 1; }
echo "PASS: patch-apply"
