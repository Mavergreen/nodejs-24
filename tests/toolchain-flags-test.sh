#!/bin/sh
# platform: host-agnostic
# build/toolchain.sh must emit exactly the inputs the Node build adds to clang22. Compiler-free: the
# emitted CC/CXX/*FLAGS are asserted, the compiler is never run, and MAVERICKS_TOOLCHAIN_PREFIX means no
# toolchain is fetched. clang22's clang.cfg/clang++.cfg supply the target triple, -isysroot, the floor,
# Recaulk's headers and archive, static libc++ and the frameworks, so restating any of them would fight
# the cfg: the `lacks` assertions are the point.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
NODE_SRC=/tmp/nodesrc
check() { if [ "$2" != "$3" ]; then echo "FAIL $1:"; echo "  expected: $2"; echo "  actual:   $3"; return 1; fi; }
lacks() { case "$2" in *"$3"*) echo "FAIL $1: '$2' must not carry '$3'"; return 1 ;; *) : ;; esac; }
fail=0
( set -eu; f=0
  MAVERICKS_ROOT="$root" NODE_SRC="$NODE_SRC" MAVERICKS_TOOLCHAIN_PREFIX=/tc . "$root/build/toolchain.sh"
  check CC  "/tc/bin/clang"   "$CC"  || f=1
  check CXX "/tc/bin/clang++" "$CXX" || f=1
  check TCP "/tc" "$TCP" || f=1
  check CXXFLAGS \
    "-std=c++20 -DMAVERGREEN_USE_RECAULK -include $NODE_SRC/deps/mavericks-compat/polyfills.h -D_LIBCPP_DISABLE_AVAILABILITY -faligned-allocation -fno-aligned-new" \
    "$CXXFLAGS" || f=1
  check CFLAGS   "-DMAVERGREEN_USE_RECAULK" "$CFLAGS"   || f=1
  check CPPFLAGS "" "$CPPFLAGS" || f=1
  check LDFLAGS  "" "$LDFLAGS"  || f=1
  check DEPLOY "10.9" "$MACOSX_DEPLOYMENT_TARGET" || f=1
  for v in "$CFLAGS" "$CXXFLAGS" "$CPPFLAGS" "$LDFLAGS"; do
    lacks flags "$v" "/opt/local"           || f=1
    lacks flags "$v" "-isysroot"            || f=1
    lacks flags "$v" "-mmacosx-version-min" || f=1
    lacks flags "$v" "-arch"                || f=1
    lacks flags "$v" "-nostdinc++"          || f=1
  done
  exit "$f" ) || fail=1
[ "$fail" -eq 0 ] && echo "PASS: toolchain-flags"
exit "$fail"
