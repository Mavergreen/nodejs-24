#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
. "$here/lib/x86_64.sh"
V="$(tr -d '[:space:]' < "$root/UPSTREAM_VERSION")"
paths="$(sh "$root/build/paths.sh")"
BIN="$(printf '%s\n' "$paths" | sed -n 's/^SRC=//p')/out/Release/node"
[ -x "$BIN" ] || { echo "not built ($BIN) -- skipping"; exit 77; }
x86_64_or_skip
got="$(x86_64_run "$BIN" --version 2>/dev/null || true)"
[ "$got" = "v$V" ] || { echo "FAIL: smoke: expected v$V, got '$got'"; exit 1; }
echo "PASS: smoke"
