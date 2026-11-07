# platform: host-agnostic
# build/toolchain.sh -- sourced. Exports CC/CXX (clang22, components/clang22/version) and the *FLAGS the
# Node build adds to clang22's own clang.cfg/clang++.cfg. Requires $NODE_SRC for the force-include path.
: "${MAVERICKS_ROOT:=$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." 2>/dev/null && pwd || pwd)}"
: "${NODE_SRC:?toolchain.sh: NODE_SRC (build-tree root) must be set}"

TCP="${MAVERICKS_TOOLCHAIN_PREFIX:-$(sh "$MAVERICKS_ROOT/build/fetch-clang22.sh")}" || return 1 2>/dev/null || exit 1
CC="$TCP/bin/clang"
CXX="$TCP/bin/clang++"
# The cfg files inject the target, the pinned 10.9 SDK, the floor, Recaulk's headers and archive, static
# libc++ and the frameworks, so only Node/V8's own needs are added here:
#   -include polyfills.h            selects Recaulk QoS declarations for V8; Node crypto includes Security itself.
#   -DMAVERGREEN_USE_RECAULK        selects shared declarations and disables local definitions.
#   -D_LIBCPP_DISABLE_AVAILABILITY  libc++ is linked statically, so its "unavailable before 10.13" marks do not apply.
#   -faligned-allocation -fno-aligned-new  as the monolith had them, for the same reason.
CXXFLAGS="-std=c++20 -DMAVERGREEN_USE_RECAULK -include $NODE_SRC/deps/mavericks-compat/polyfills.h -D_LIBCPP_DISABLE_AVAILABILITY -faligned-allocation -fno-aligned-new"
CFLAGS="-DMAVERGREEN_USE_RECAULK"
CPPFLAGS=""
LDFLAGS=""
MACOSX_DEPLOYMENT_TARGET="10.9"
export TCP CC CXX CFLAGS CXXFLAGS CPPFLAGS LDFLAGS MACOSX_DEPLOYMENT_TARGET
