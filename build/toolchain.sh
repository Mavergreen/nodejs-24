# build/toolchain.sh -- sourced. Resolves the toolchain provider from components/toolchain/version and
# exports CC/CXX and the *FLAGS the Node build uses. The ONLY place that knows which provider is active.
# Requires $NODE_SRC (the Node build-tree root) for the force-include path.
: "${MAVERICKS_ROOT:=$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." 2>/dev/null && pwd || pwd)}"
: "${NODE_SRC:?toolchain.sh: NODE_SRC (build-tree root) must be set}"

_tc_provider() { sed -n 's/^PROVIDER=//p' "$MAVERICKS_ROOT/components/toolchain/version" | head -1; }

case "$(_tc_provider)" in
  macports)
    CC="/opt/local/bin/clang-mp-18"
    CXX="/opt/local/bin/clang++-mp-18"
    CXXFLAGS="-std=c++20 -include $NODE_SRC/deps/mavericks-compat/polyfills.h -isystem /opt/local/include/LegacySupport -nostdinc++ -isystem /opt/local/libexec/llvm-18/include/c++/v1 -mmacosx-version-min=10.9 -DMAC_OS_X_VERSION_MIN_REQUIRED=1090 -D_LIBCPP_DISABLE_AVAILABILITY -faligned-allocation -fno-aligned-new"
    CFLAGS="-I/opt/local/include/LegacySupport -mmacosx-version-min=10.9 -DMAC_OS_X_VERSION_MIN_REQUIRED=1090"
    CPPFLAGS="-mmacosx-version-min=10.9 -DMAC_OS_X_VERSION_MIN_REQUIRED=1090"
    LDFLAGS="-nostdlib++ -mmacosx-version-min=10.9 -L/opt/local/lib /opt/local/libexec/llvm-18/lib/libc++/libc++.a /opt/local/libexec/llvm-18/lib/libc++/libc++abi.a /opt/local/lib/libMacportsLegacySupport.a -lSystem"
    ;;
  mavericks-clang)
    # build/fetch-toolchain.sh owns variant selection (native on 10.9, cross elsewhere), verification
    # and the SDK wiring, and prints the prefix. That is where the MODE-awareness lives, so the flags
    # below are the same on both hosts.
    TCP="${MAVERICKS_TOOLCHAIN_PREFIX:-$(sh "$MAVERICKS_ROOT/build/fetch-toolchain.sh")}"
    CC="$TCP/bin/clang"
    CXX="$TCP/bin/clang++"
    # The toolchain's own clang.cfg/clang++.cfg already inject --target=x86_64-apple-macos10.9,
    # -isysroot <prefix>/SDKs/MacOSX10.9.sdk, -mmacosx-version-min=10.9, the mavericks-compat and
    # LegacySupport header shadows, static libc++/libc++abi/libunwind and the Apple frameworks. So the
    # seam adds ONLY what is specific to Node/V8 -- restating the macports apparatus would fight the cfg:
    #   -include polyfills.h  Node and V8 call newer-than-10.9 APIs the toolchain's shims do not cover
    #                         (os_signpost_*, pthread_set_qos_class_self_np, recvmsg_x/sendmsg_x,
    #                         SecTrustEvaluateWithError); compat/polyfills.c supplies the definitions.
    #   -D_LIBCPP_DISABLE_AVAILABILITY  we link our OWN libc++ statically, so libc++'s "unavailable
    #                         before 10.13/10.14" annotations (std::optional's bad_optional_access,
    #                         std::filesystem, ...) do not apply to us.
    #   -faligned-allocation -fno-aligned-new  as the monolith had them, for the same reason.
    CXXFLAGS="-std=c++20 -include $NODE_SRC/deps/mavericks-compat/polyfills.h -D_LIBCPP_DISABLE_AVAILABILITY -faligned-allocation -fno-aligned-new"
    CFLAGS=""
    CPPFLAGS=""
    LDFLAGS=""
    ;;
  *)
    echo "toolchain.sh: unknown provider in components/toolchain/version" >&2; return 1 2>/dev/null || exit 1
    ;;
esac
MACOSX_DEPLOYMENT_TARGET="10.9"
export CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS MACOSX_DEPLOYMENT_TARGET
