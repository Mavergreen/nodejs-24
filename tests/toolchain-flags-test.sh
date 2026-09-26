#!/bin/sh
# Both toolchain providers must emit exactly the inputs the Node build expects. Compiler-free: we
# assert the emitted CC/CXX/*FLAGS, we never run the compiler. Each provider is driven through a
# synthetic components/toolchain/version so BOTH are covered regardless of which one is active in the
# real pin, and through MAVERICKS_TOOLCHAIN_PREFIX so no toolchain is fetched.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/tcflags.XXXXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/components/toolchain"
NODE_SRC=/tmp/nodesrc                    # stand-in build-tree root for the force-include path

check()    { if [ "$2" != "$3" ]; then echo "FAIL $1:"; echo "  expected: $2"; echo "  actual:   $3"; return 1; fi; }
lacks()    { case "$2" in *"$3"*) echo "FAIL $1: '$2' must not carry '$3'"; return 1 ;; *) : ;; esac; }

fail=0

# --- macports (Phase 2a): reproduces the monolith's exact toolchain inputs. Must not drift. ---
printf 'PROVIDER=macports\n' > "$T/components/toolchain/version"
( set -eu; f=0
  MAVERICKS_ROOT="$T" NODE_SRC="$NODE_SRC" . "$root/build/toolchain.sh"
  check CC  "/opt/local/bin/clang-mp-18"   "$CC"  || f=1
  check CXX "/opt/local/bin/clang++-mp-18" "$CXX" || f=1
  check CXXFLAGS \
    "-std=c++20 -include $NODE_SRC/deps/mavericks-compat/polyfills.h -isystem /opt/local/include/LegacySupport -nostdinc++ -isystem /opt/local/libexec/llvm-18/include/c++/v1 -mmacosx-version-min=10.9 -DMAC_OS_X_VERSION_MIN_REQUIRED=1090 -D_LIBCPP_DISABLE_AVAILABILITY -faligned-allocation -fno-aligned-new" \
    "$CXXFLAGS" || f=1
  check CFLAGS \
    "-I/opt/local/include/LegacySupport -mmacosx-version-min=10.9 -DMAC_OS_X_VERSION_MIN_REQUIRED=1090" \
    "$CFLAGS" || f=1
  check CPPFLAGS "-mmacosx-version-min=10.9 -DMAC_OS_X_VERSION_MIN_REQUIRED=1090" "$CPPFLAGS" || f=1
  check LDFLAGS \
    "-nostdlib++ -mmacosx-version-min=10.9 -L/opt/local/lib /opt/local/libexec/llvm-18/lib/libc++/libc++.a /opt/local/libexec/llvm-18/lib/libc++/libc++abi.a /opt/local/lib/libMacportsLegacySupport.a -lSystem" \
    "$LDFLAGS" || f=1
  check DEPLOY "10.9" "$MACOSX_DEPLOYMENT_TARGET" || f=1
  exit "$f" ) || fail=1

# --- mavericks-clang: the toolchain's own clang.cfg/clang++.cfg supply the target triple, -isysroot,
# -mmacosx-version-min, the LegacySupport/mavericks-compat header shadows, static libc++/libc++abi/
# libunwind and the Apple frameworks. The seam must therefore emit ONLY the Node/V8-specific flags --
# repeating the macports apparatus here would fight the cfg. The `lacks` assertions are the point.
printf 'PROVIDER=mavericks-clang\n' > "$T/components/toolchain/version"
( set -eu; f=0
  MAVERICKS_ROOT="$T" NODE_SRC="$NODE_SRC" MAVERICKS_TOOLCHAIN_PREFIX=/tc . "$root/build/toolchain.sh"
  check CC  "/tc/bin/clang"   "$CC"  || f=1
  check CXX "/tc/bin/clang++" "$CXX" || f=1
  check CXXFLAGS \
    "-std=c++20 -include $NODE_SRC/deps/mavericks-compat/polyfills.h -D_LIBCPP_DISABLE_AVAILABILITY -faligned-allocation -fno-aligned-new" \
    "$CXXFLAGS" || f=1
  check CFLAGS   "" "$CFLAGS"   || f=1
  check CPPFLAGS "" "$CPPFLAGS" || f=1
  check LDFLAGS  "" "$LDFLAGS"  || f=1
  check DEPLOY "10.9" "$MACOSX_DEPLOYMENT_TARGET" || f=1
  for v in "$CFLAGS" "$CXXFLAGS" "$CPPFLAGS" "$LDFLAGS"; do
    lacks flags "$v" "/opt/local"           || f=1  # no MacPorts apparatus
    lacks flags "$v" "-isysroot"            || f=1  # clang.cfg owns the sysroot
    lacks flags "$v" "-mmacosx-version-min" || f=1  # clang.cfg owns the deployment target
    lacks flags "$v" "-arch"                || f=1  # clang.cfg owns the target triple
    lacks flags "$v" "-nostdinc++"          || f=1  # clang.cfg owns the C++ runtime
  done
  exit "$f" ) || fail=1

[ "$fail" -eq 0 ] && echo "PASS: toolchain-flags (macports, mavericks-clang)"
exit "$fail"
