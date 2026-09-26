#!/bin/sh
# build/build.sh <subcommand> -- the Node build, decomposed. This repo ships ONE Node major line,
# derived from the root UPSTREAM_VERSION (see build/version.sh). Subcommands:
#   configure-args   print the ./configure argv for this line (dry; no compiler)
#   fetch            download + checksum-verify + extract this line's Node source into $NODE_WORK
#   patch            apply patches/* + deterministic 10.9 fixups to the extracted tree
#   stage-compat     copy compat/ polyfills into the tree
#   configure        run ./configure (needs the toolchain)
#   make             run make (needs the toolchain)
#   guard            assert the built binary is 10.9-safe
#   all              fetch -> patch -> stage-compat -> configure -> make -> guard  (the parked compile)
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/msc.sh"                                   # sets $SHIPYARD
. "$SELF/paths.sh"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# Node's gyp invokes `libtool -static` / `ar` / `ranlib` by BARE NAME to build static archives. Two
# hazards: (1) a MacPorts/pkgsrc GNU libtool on PATH shadows the real one and rejects '-static'; (2) on a
# real 10.9 box the *ancient* Apple libtool produces large archives (libv8_base_without_compiler.a) that
# the toolchain's linker (ld64.lld) cannot read ("truncated or malformed archive"), and it rejects the
# `-framework X` gyp passes for V8 targets. Fix both by archiving with the TOOLCHAIN's own LLVM tools
# (archiver matched to linker) via a narrow shim dir, wrapping libtool to strip `-framework <name>` pairs
# (frameworks link at the final link via clang.cfg, never into a static .a). Works on a modern host and a
# real 10.9 box alike. Call AFTER _toolchain: it locates the toolchain bin from $CC.
_build_tools_shim() {
  shim="$NODE_WORK/build-tools"; rm -rf "$shim"; mkdir -p "$shim"
  tbin="$(dirname "$CC")"                      # toolchain bin dir, from the resolved seam
  # (object/output paths under $NODE_WORK have no spaces, so word-splitting in the wrapper is safe)
  printf '#!/bin/sh\nLT="%s/llvm-libtool-darwin"\nna=""; skip=0\nfor a in "$@"; do\n  [ "$skip" = 1 ] && { skip=0; continue; }\n  [ "$a" = "-framework" ] && { skip=1; continue; }\n  na="$na $a"\ndone\nexec $LT $na\n' "$tbin" > "$shim/libtool"
  chmod +x "$shim/libtool"
  ln -sf "$tbin/llvm-ar"     "$shim/ar"
  ln -sf "$tbin/llvm-ranlib" "$shim/ranlib"
  # Mach-O post-processing tools stay Apple's.
  for t in nm strip lipo install_name_tool; do
    [ -x "/usr/bin/$t" ] && ln -sf "/usr/bin/$t" "$shim/$t"
  done
  PATH="$shim:$PATH"; export PATH
}

# Resolved ONCE and exported, so ./configure, the toolchain seam and fetch-toolchain.sh cannot disagree
# about which host we are building for. Overridable for tests.
MODE="${MODE:-$(sh "$SHIPYARD/mavericks_mode.sh")}"; export MODE

configure_args() {
  # platform: node_mksnapshot runs Node's bootstrap as target-arch code and V8 has no x64 simulator, so
  #           an arm64 host could only build it under Rosetta; Node's configure already drops it when
  #           cross-compiling, so the native build drops it too or the two builds differ.
  base="--prefix=$PREFIX --with-intl=full-icu --download=all --fully-static --enable-static --without-node-snapshot"
  # Cross: Node otherwise infers the target from the host it is running on and would configure an
  # arm64 build. --cross-compiling additionally stops it from running target binaries it builds.
  if [ "$MODE" = cross ]; then
    echo "$base --dest-cpu=x64 --dest-os=mac --cross-compiling"
  else
    echo "$base"
  fi
}

fetch() {
  mkdir -p "$NODE_WORK"
  tarball="$NODE_WORK/node-v${NODE_VERSION}.tar.gz"
  base="https://nodejs.org/dist/v${NODE_VERSION}"
  [ -f "$tarball" ] || curl -fL -o "$tarball" "$base/node-v${NODE_VERSION}.tar.gz"
  # Verify against Node's published, per-release SHASUMS256.txt (frozen by the pinned version).
  sums="$NODE_WORK/SHASUMS256-${NODE_VERSION}.txt"
  [ -f "$sums" ] || curl -fL -o "$sums" "$base/SHASUMS256.txt"
  want="$(awk -v f="node-v${NODE_VERSION}.tar.gz" '$2==f{print $1}' "$sums")"
  [ -n "$want" ] || { echo "build.sh: node-v${NODE_VERSION}.tar.gz not listed in SHASUMS256.txt" >&2; exit 1; }
  got="$(shasum -a 256 "$tarball" | awk '{print $1}')"
  [ "$want" = "$got" ] || { echo "build.sh: checksum mismatch for $tarball" >&2; echo "  want $want"; echo "  got  $got"; exit 1; }
  rm -rf "$SRC"; tar -xzf "$tarball" -C "$NODE_WORK"
  echo "fetched+verified: $SRC"
}

apply_patches() {
  [ -d "$SRC" ] || { echo "build.sh: no extracted source at $SRC (run fetch first)" >&2; exit 1; }
  for p in "$MAVERICKS_ROOT/patches"/*.patch; do
    [ -e "$p" ] || continue
    echo "  applying $(basename "$p")"; ( cd "$SRC" && patch -p1 < "$p" )
  done
  fixups
}

# Deterministic source edits that are awkward as context patches (they are simple, version-tolerant seds).
fixups() {
  # common.gypi: force the 10.9 deployment target / min-version.
  if [ -f "$SRC/common.gypi" ]; then
    sed -i '' "s|'MACOSX_DEPLOYMENT_TARGET': '[0-9.]*'|'MACOSX_DEPLOYMENT_TARGET': '10.9'|g" "$SRC/common.gypi"
    sed -i '' 's|-mmacosx-version-min=[0-9.]*|-mmacosx-version-min=10.9|g' "$SRC/common.gypi"
  fi
  # V8 safepoint: pthread_override_t is absent on 10.9 -> void*, and drop the start/end calls.
  sed -i '' 's/pthread_override_t qos_override;/void* qos_override; \/\/ pthread_override not available on 10.9/' "$SRC/deps/v8/src/heap/safepoint.h"
  sed -i '' 's/pthread_override_t qos_override = nullptr;/void* qos_override = nullptr;/' "$SRC/deps/v8/src/heap/safepoint.cc"
  sed -i '' '/qos_override = pthread_override_qos_class_start_np/,/CHECK_NOT_NULL(qos_override);/d' "$SRC/deps/v8/src/heap/safepoint.cc"
  sed -i '' '/CHECK_EQ($/{N;N;/pthread_override_qos_class_end_np/d;}' "$SRC/deps/v8/src/heap/safepoint.cc"
}

stage_compat() {
  [ -d "$SRC" ] || { echo "build.sh: no extracted source (run fetch first)" >&2; exit 1; }
  mkdir -p "$SRC/deps/mavericks-compat"
  cp "$MAVERICKS_ROOT/compat/polyfills.h" "$SRC/deps/mavericks-compat/polyfills.h"
  cp "$MAVERICKS_ROOT/compat/polyfills.c" "$SRC/deps/mavericks-compat/polyfills.c"
}

_toolchain() { NODE_SRC="$SRC" . "$SELF/toolchain.sh"; }

configure() {
  _toolchain
  _build_tools_shim
  # Compile the Node/V8 10.9 shim definitions.
  poly="$SRC/deps/mavericks-compat/polyfills.o"
  "$CC" $CFLAGS -c "$SRC/deps/mavericks-compat/polyfills.c" -o "$poly"
  # Link those definitions into every executable of gyp's TARGET toolset (not just `node`), as a global
  # library in common.gypi's target_defaults. Appending to LDFLAGS is not enough: gyp reads flags for its
  # generators in ways ./configure never records. In a cross build, the HOST toolset (node_js2c, torque,
  # mksnapshot -- the tools that run during the build) is arm64 against the build machine's own SDK and
  # needs no polyfill, so the library is scoped with target_conditions to _toolset=="target".
  if ! grep -q 'mavericks-compat/polyfills.o' "$SRC/common.gypi"; then
    awk -v lib="$poly" '{print} /default_configuration.*Release/ && !d {printf "    \047target_conditions\047: [ [ \047_toolset==\"target\"\047, { \047libraries\047: [ \047%s\047 ] } ] ],\n", lib; d=1}' \
      "$SRC/common.gypi" > "$SRC/common.gypi.tmp" && mv "$SRC/common.gypi.tmp" "$SRC/common.gypi"
  fi
  echo "build.sh: MODE=$MODE prefix=$PREFIX"
  ( cd "$SRC" && CC="$CC" CXX="$CXX" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" \
      CPPFLAGS="$CPPFLAGS" MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
      env $(host_env) python3 ./configure $(configure_args) )
}

make_() {
  _toolchain
  _build_tools_shim
  # Cross only: gyp builds the tools that run DURING the build (node_js2c, torque, mksnapshot, the ICU
  # generators) in a separate "host" toolset, compiled by CC_host (see host_env) and given its compile
  # and link flags from the environment at make time (`CXXFLAGS.host ?= $(CPPFLAGS_host) ...`). They
  # are native arm64 tools for the build machine, so they get its SDK and none of the 10.9 target flags.
  # A native 10.9 build has no separate host toolset.
  if [ "$MODE" = cross ]; then
    # platform: Apple's clang, called by its real path rather than the /usr/bin xcrun shim, uses no SDK
    #           unless told, and finds no system headers.
    # platform: gyp gives the host toolset the target's -mmacosx-version-min=10.9 too, and the modern
    #           SDK's libc++ refuses aligned allocation below 10.13; a later -mmacosx-version-min wins.
    host_sdk="-isysroot $(xcrun --sdk macosx --show-sdk-path) -mmacosx-version-min=11.0"
    export CFLAGS_host="" CXXFLAGS_host="" CPPFLAGS_host="$host_sdk" LDFLAGS_host="$host_sdk"
  fi
  ( cd "$SRC" && CC="$CC" CXX="$CXX" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" \
      CPPFLAGS="$CPPFLAGS" MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" make -j"$JOBS" )
}

host_env() {
  # platform: gyp takes the host toolset's compiler from CC_host at configure time and otherwise
  #           falls back to CC, the x86_64 mavericks-clang, whose tools an arm64 host runs under Rosetta.
  if [ "$MODE" = cross ]; then
    printf 'CC_host=%s\nCXX_host=%s\n' "$(xcrun -f clang)" "$(xcrun -f clang++)"
  fi
}

guard() {
  bin="$SRC/out/Release/node"
  [ -x "$bin" ] || { echo "build.sh: not built ($bin absent) — skipping guard"; exit 77; }
  sh "$SHIPYARD/assert_binary_compatible.sh" "$bin"
}

case "${1:?usage: build.sh <configure-args|host-env|fetch|patch|stage-compat|configure|make|guard|all>}" in
  configure-args) configure_args ;;
  host-env)       host_env ;;
  fetch)          fetch ;;
  patch)          apply_patches ;;
  stage-compat)   stage_compat ;;
  configure)      configure ;;
  make)           make_ ;;
  guard)          guard ;;
  all)            fetch; apply_patches; stage_compat; configure; make_; guard ;;
  *) echo "build.sh: unknown subcommand '$1'" >&2; exit 2 ;;
esac
