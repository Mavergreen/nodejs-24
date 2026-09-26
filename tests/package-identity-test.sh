#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
V="$(tr -d '[:space:]' < "$root/UPSTREAM_VERSION")"; L="${V%%.*}"
out="$(sh "$root/build/package.sh" identity)"
get() { printf '%s\n' "$out" | sed -n "s/^$1=//p"; }
fail=0
check() { [ "$2" = "$3" ] || { echo "FAIL $1: expected '$3', got '$2'"; fail=1; }; }
check product    "$(get product)"    "node$L"
check group      "$(get group)"      "node"
check line       "$(get line)"       "$L"
check prefix     "$(get prefix)"     "/usr/local/mavergreen/node$L"
check identifier "$(get identifier)" "dev.mavergreen.nodejs.node$L"
check title      "$(get title)"      "Node.js $L for Mavericks"
[ "$fail" -eq 0 ] && echo "PASS: package-identity"
exit "$fail"
