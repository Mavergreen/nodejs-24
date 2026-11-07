#!/bin/sh
# platform: host-agnostic
# Nothing here runs translated: no build or test script uses Rosetta's arch(1), INGREDIENTS.md declares
# no Rosetta use, a cross build gives gyp a host toolset for the build machine (never clang22's x86_64
# 10.9 target), and a cross-built tree's host tools are the build machine's own format.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
fail=0
say() { echo "FAIL: $*"; fail=1; }

for f in "$root"/build/*.sh "$root"/tests/*.sh "$root"/tests/lib/*.sh "$root"/tests/vm/*.sh; do
  grep -v '^[[:space:]]*#' "$f" | grep -q 'arch[[:space:]][[:space:]]*-x86_64' \
    && say "${f#$root/} runs x86_64 code through Rosetta's arch(1)"
done
grep -q '^- rosetta:' "$root/INGREDIENTS.md" && say "INGREDIENTS.md still declares a Rosetta use"

NODE_WORK=/nw; export NODE_WORK
env_linux="$(MODE=cross NODE_HOST_OS=Linux sh "$root/build/build.sh" host-env)"
[ "$(printf '%s\n' "$env_linux" | sed -n 's/^CC_host=//p')" = /nw/build-tools/host-cc ] \
  || say "a cross build on Linux must compile its host toolset with build-tools/host-cc, got: $env_linux"
[ "$(printf '%s\n' "$env_linux" | sed -n 's/^CXX_host=//p')" = /nw/build-tools/host-c++ ] \
  || say "a cross build on Linux must compile its host toolset with build-tools/host-c++, got: $env_linux"
printf '%s\n' "$env_linux" | grep -qx 'GYP_DEFINES=host_os=linux' \
  || say "a cross build on Linux must tell gyp its host is Linux, got: $env_linux"
env_native="$(MODE=native sh "$root/build/build.sh" host-env)"
[ -z "$env_native" ] || say "a native build must not set a separate host toolchain, got: $env_native"
unset NODE_WORK

SRC="$(sh "$root/build/paths.sh" | sed -n 's/^SRC=//p')"
if [ -f "$SRC/config.status" ] && grep -q -- '--cross-compiling' "$SRC/config.status" \
   && [ -x "$SRC/out/Release/node" ] && [ ! -L "$SRC/out/Release/node" ]; then
  magic() { od -An -tx1 -N4 "$1" | tr -d ' \n'; }
  for t in mksnapshot torque node_js2c bytecode_builtins_list_generator gen-regexp-special-case genccode icupkg; do
    [ -f "$SRC/out/Release/$t" ] || { say "cross build has no host tool $t"; continue; }
    if [ "$(uname -s)" = Linux ]; then
      [ "$(magic "$SRC/out/Release/$t")" = 7f454c46 ] || say "host tool $t is not an ELF executable for this Linux host"
    else
      tcp="$(sh "$root/build/fetch-clang22.sh")"
      got="$("$tcp/bin/llvm-lipo" -info "$SRC/out/Release/$t" 2>/dev/null | sed -n 's/.*: //p' | xargs)"
      [ "$got" = "$(uname -m)" ] || say "host tool $t is '$got', not $(uname -m) -- it would run under Rosetta"
    fi
  done
fi

[ "$fail" -eq 0 ] && echo "PASS: rosetta-free"
exit "$fail"
