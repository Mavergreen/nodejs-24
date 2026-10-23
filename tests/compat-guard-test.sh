#!/bin/sh
# platform: macOS-only -- exercises the Darwin build, package, or target executable.
set -eu
# platform: stock Mavericks has CLT stubs; installed-pkg execution is covered by tests/vm/run.sh.
[ -n "${OTOOL:-}" ] || xcode-select -p >/dev/null 2>&1 \
  || { echo "no Mach-O inspection tools -- skipping"; exit 77; }
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
. "$root/build/msc.sh"
paths="$(sh "$root/build/paths.sh")"
BIN="$(printf '%s\n' "$paths" | sed -n 's/^SRC=//p')/out/Release/node"
[ -x "$BIN" ] || { echo "not built ($BIN) -- skipping"; exit 77; }
sh "$SHIPYARD/assert_binary_compatible.sh" "$BIN" \
  || { echo "FAIL: compat guard (floor > 10.9, wrong arch, or a post-10.9 import)"; exit 1; }
echo "PASS: compat-guard"
