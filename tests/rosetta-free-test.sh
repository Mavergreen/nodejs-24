#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
fail=0
say() { echo "FAIL: $*"; fail=1; }

rosetta_users() { grep -l 'arch[[:space:]][[:space:]]*-x86_64' "$@" 2>/dev/null | while IFS= read -r f; do
  grep -v '^[[:space:]]*#' "$f" | grep -q 'arch[[:space:]][[:space:]]*-x86_64' && printf '%s\n' "${f#$root/}"; done; }
for f in $(rosetta_users "$root"/build/*.sh); do
  say "$f runs x86_64 code through Rosetta's arch(1) -- the build must never need Rosetta"
done
for f in $(rosetta_users "$root"/tests/*.sh "$root"/tests/lib/*.sh); do
  grep -q "^- rosetta:$f: " "$root/INGREDIENTS.md" \
    || say "$f uses Rosetta but INGREDIENTS.md declares no '- rosetta:$f: <what, why, when to reconsider>'"
done

env_cross="$(MODE=cross sh "$root/build/build.sh" host-env)"
cc_host="$(printf '%s\n' "$env_cross" | sed -n 's/^CC_host=//p')"
cxx_host="$(printf '%s\n' "$env_cross" | sed -n 's/^CXX_host=//p')"
[ -n "$cc_host" ] && [ -n "$cxx_host" ] \
  || say "a cross build sets no CC_host/CXX_host -- gyp's host tools would inherit the x86_64 target compiler and run under Rosetta"
case "$cc_host$cxx_host" in *mavericks-clang*) say "CC_host/CXX_host is the mavericks-clang target toolchain ($cc_host)";; esac
env_native="$(MODE=native sh "$root/build/build.sh" host-env)"
[ -z "$env_native" ] || say "a native build must not set a separate host toolchain, got: $env_native"

SRC="$(sh "$root/build/paths.sh" | sed -n 's/^SRC=//p')"
if [ -f "$SRC/config.status" ] && grep -q -- '--cross-compiling' "$SRC/config.status" && [ -x "$SRC/out/Release/node" ]; then
  want="$(uname -m)"
  for t in mksnapshot torque node_js2c bytecode_builtins_list_generator gen-regexp-special-case genccode icupkg; do
    [ -f "$SRC/out/Release/$t" ] || { say "cross build has no host tool $t"; continue; }
    got="$(lipo -info "$SRC/out/Release/$t" 2>/dev/null | sed -n 's/.*: //p' | xargs)"
    [ "$got" = "$want" ] || say "host tool $t is '$got', not $want -- it ran under Rosetta"
  done
fi

[ "$fail" -eq 0 ] && echo "PASS: rosetta-free"
exit "$fail"
