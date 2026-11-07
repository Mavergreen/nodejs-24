#!/bin/sh
# platform: host-agnostic
# The built node passes shipyard's compat guard (floor, arch, SDK, post-10.9 imports), read with clang22's
# llvm tools on any host. A tree whose out/Release/node is a link (the 10.9 guest's test bundle points it at
# the installed product) is not a build and is not checked here.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
paths="$(sh "$root/build/paths.sh")"
BIN="$(printf '%s\n' "$paths" | sed -n 's/^SRC=//p')/out/Release/node"
[ -x "$BIN" ] || { echo "not built ($BIN) -- skipping"; exit 77; }
[ ! -L "$BIN" ] || { echo "$BIN is a link to an installed node, not a build -- skipping"; exit 77; }
sh "$root/build/build.sh" guard \
  || { echo "FAIL: compat guard (floor > 10.9, wrong arch or SDK, or a post-10.9 import)"; exit 1; }
echo "PASS: compat-guard"
