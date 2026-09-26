#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
V="$(tr -d '[:space:]' < "$root/UPSTREAM_VERSION")"; L="${V%%.*}"
fail=0
check() { [ "$2" = "$3" ] || { echo "FAIL $1: expected '$3', got '$2'"; fail=1; }; }
get() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

out="$(unset NODE_WORK; MAVERICKS_BUILD_ROOT=/mbr sh "$root/build/paths.sh")"
check NODE_LINE    "$(get "$out" NODE_LINE)"    "$L"
check NODE_VERSION "$(get "$out" NODE_VERSION)" "$V"
check PREFIX       "$(get "$out" PREFIX)"       "/usr/local/mavergreen/node$L"
check "NODE_WORK under MAVERICKS_BUILD_ROOT" "$(get "$out" NODE_WORK)" "/mbr/nodejs"
check SRC          "$(get "$out" SRC)"          "/mbr/nodejs/node-v$V"

out="$(unset NODE_WORK MAVERICKS_BUILD_ROOT; TMPDIR=/t sh "$root/build/paths.sh")"
check "NODE_WORK falls back to TMPDIR/mm-build (never the possibly-NFS source tree)" \
      "$(get "$out" NODE_WORK)" "/t/mm-build/nodejs"

out="$(NODE_WORK=/nw MAVERICKS_BUILD_ROOT=/mbr sh "$root/build/paths.sh")"
check "an explicit NODE_WORK wins" "$(get "$out" NODE_WORK)" "/nw"

if NODE_LINE=99 sh "$root/build/paths.sh" >/dev/null 2>&1; then
  echo "FAIL a failed derivation must exit non-zero, or callers read empty values as a real (unbuilt) tree"; fail=1
fi

[ "$fail" -eq 0 ] && echo "PASS: paths"
exit "$fail"
