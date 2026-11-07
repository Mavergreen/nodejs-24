#!/bin/sh
# platform: host-agnostic
# build/build.sh <subcommand> -- the Node build, decomposed. This repo ships ONE Node major line,
# derived from the root UPSTREAM_VERSION (see build/version.sh). Subcommands:
#   configure-args   print the ./configure argv for this line (dry; no compiler)
#   host-env         print the host-toolset environment a cross build gives ./configure and make (dry)
#   fetch            download + checksum-verify + extract this line's Node source into $NODE_WORK
#   patch            apply patches/* + deterministic 10.9 fixups to the extracted tree
#   stage-compat     copy compat/ polyfills into the tree
#   configure        run ./configure (needs the toolchain)
#   make             run make (needs the toolchain); records the build tools in $NODE_WORK/build-tools.txt
#   guard            assert the built binary is 10.9-safe
#   all              fetch -> patch -> stage-compat -> configure -> make -> guard
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/msc.sh"
. "$SHIPYARD/mavericks_fetch.sh"
. "$SELF/paths.sh"
. "$SELF/python-314-compat.sh"
. "$SELF/python-315-compat.sh"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
HOST_OS="${NODE_HOST_OS:-$(uname -s)}"
SHIM="$NODE_WORK/build-tools"

# Resolved ONCE and exported, so ./configure, the toolchain seam and fetch-clang22.sh cannot disagree
# about which host we are building for. Overridable for tests.
MODE="${MODE:-$(sh "$SHIPYARD/mavericks_mode.sh")}"; export MODE

_write_libtool() {
  printf '#!/bin/sh\nAR=%s\n' "'$TCP/bin/llvm-ar'" > "$1"
  cat >> "$1" <<'SHIM'
out=; want_out=; skip=
for a do
  shift
  if [ -n "$want_out" ]; then out="$a"; want_out=; continue; fi
  if [ -n "$skip" ]; then skip=; continue; fi
  case "$a" in
    -o) want_out=1; continue ;;
    -framework) skip=1; continue ;;
    -static|-Wl,*|-no_warning_for_no_symbols) continue ;;
    -*) echo "libtool shim: unsupported option $a" >&2; exit 2 ;;
  esac
  set -- "$@" "$a"
done
[ -n "$out" ] || { echo "libtool shim: no -o OUTPUT" >&2; exit 2; }
rm -f "$out"
exec "$AR" qcs "$out" "$@"
SHIM
  chmod +x "$1"
}

_write_host_compiler() {
  printf '#!/bin/sh\nREAL=%s\n' "'$2'" > "$1"
  cat >> "$1" <<'SHIM'
skip=
for a do
  shift
  if [ -n "$skip" ]; then skip=; continue; fi
  case "$a" in
    -mmacosx-version-min=*|-stdlib=*|-Wl,-search_paths_first|-Wno-nullability-completeness) continue ;;
    -arch|-isysroot|-framework) skip=1; continue ;;
  esac
  set -- "$@" "$a"
done
exec "$REAL" -fuse-ld=lld "$@"
SHIM
  chmod +x "$1"
}

# Node's gyp archives with `libtool -static` and calls ar/ranlib/nm/strip/lipo/install_name_tool by bare
# name. All of them are clang22's LLVM tools here, through a shim directory first on PATH: the archiver
# matched to the linker, the same on every host. The libtool shim archives with llvm-ar, which writes a
# Darwin archive of Mach-O members and a GNU one of a Linux host tool's ELF members; frameworks link at
# the final link through clang.cfg, never into a static archive. A cross build on Linux also gets
# host-cc/host-c++ (see host_env). Call AFTER _toolchain: it reads $TCP.
_build_tools_shim() {
  rm -rf "$SHIM"; mkdir -p "$SHIM"
  _write_libtool "$SHIM/libtool"
  ln -sf "$TCP/bin/llvm-ar"     "$SHIM/ar"
  ln -sf "$TCP/bin/llvm-ranlib" "$SHIM/ranlib"
  ln -sf "$TCP/bin/llvm-nm"     "$SHIM/nm"
  ln -sf "$TCP/bin/llvm-strip"  "$SHIM/strip"
  ln -sf "$TCP/bin/llvm-lipo"   "$SHIM/lipo"
  ln -sf "$TCP/bin/llvm-install-name-tool" "$SHIM/install_name_tool"
  if [ "$MODE" = cross ] && [ "$HOST_OS" = Linux ]; then
    _write_host_compiler "$SHIM/host-cc" "$(_host_compiler "${NODE_HOST_CC:-cc}")"
    _write_host_compiler "$SHIM/host-c++" "$(_host_compiler "${NODE_HOST_CXX:-c++}")"
    ln -sf "$TCP/bin/ld.lld" "$SHIM/ld.lld"
  fi
  PATH="$SHIM:$PATH"; export PATH
}

_host_compiler() {
  command -v "$1" || { echo "build.sh: no host compiler '$1' on PATH" >&2; exit 1; }
}

configure_args() {
  # platform: node_mksnapshot runs Node's bootstrap as target-arch code and V8 has no x64 simulator, so
  #           a host of another arch or OS could not run it; Node's configure already drops it when
  #           cross-compiling, so the native build drops it too or the two builds differ.
  base="--prefix=$PREFIX --with-intl=full-icu --download=all --fully-static --enable-static --without-node-snapshot"
  # Cross: Node otherwise infers the target from the host it is running on.
  # --cross-compiling additionally stops it from running target binaries it builds.
  if [ "$MODE" = cross ]; then
    echo "$base --dest-cpu=x64 --dest-os=mac --cross-compiling"
  else
    echo "$base"
  fi
}

# A cross build's host toolset (torque, mksnapshot, node_js2c, the ICU generators: the tools that run
# DURING the build) is compiled for the build machine, never as x86_64 10.9 code, so no step runs
# translated. gyp takes its compiler from CC_host/CXX_host at configure time and otherwise falls back to
# CC, clang22's x86_64 10.9 target.
host_env() {
  [ "$MODE" = cross ] || return 0
  case "$HOST_OS" in
    Linux)
      # spec: patches/0012-linux-host-toolset.patch -- host_os=linux gives the host toolset libuv's and
      #       V8's Linux platform sources; gyp's mac generator still emits Darwin flags for it, which
      #       host-cc/host-c++ drop before running the runner's compiler.
      printf 'CC_host=%s\nCXX_host=%s\nGYP_DEFINES=host_os=linux\n' "$SHIM/host-cc" "$SHIM/host-c++" ;;
    Darwin)
      # spec: INGREDIENTS.md "Conformance deviations", apple-clang:build/build.sh -- the host toolset of a
      #       cross build on an Apple Silicon Mac needs a C++20 runtime for arm64, which clang22 does not ship.
      # platform: guarded macOS-only call -- the Darwin case of HOST_OS
      printf 'CC_host=%s\nCXX_host=%s\n' "$(xcrun -f clang)" "$(xcrun -f clang++)" ;;
    *) echo "build.sh: no host toolset for a cross build on $HOST_OS" >&2; exit 1 ;;
  esac
}

fetch() {
  mkdir -p "$NODE_WORK"
  tarball="$NODE_WORK/node-v${NODE_VERSION}.tar.gz"
  base="https://nodejs.org/dist/v${NODE_VERSION}"
  [ -f "$tarball" ] || shipyard_curl "$base/node-v${NODE_VERSION}.tar.gz" "$tarball"
  # Verify against Node's published, per-release SHASUMS256.txt (frozen by the pinned version).
  sums="$NODE_WORK/SHASUMS256-${NODE_VERSION}.txt"
  [ -f "$sums" ] || shipyard_curl "$base/SHASUMS256.txt" "$sums"
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
    echo "  applying $(basename "$p")"
    if [ "$(basename "$p")" = 0004-python-314.patch ]; then
      apply_python_314_compat_patch "$SRC" "$p"
    elif [ "$(basename "$p")" = 0005-python-315.patch ]; then
      apply_python_315_compat_patch "$SRC" "$p"
    else
      ( cd "$SRC" && patch -p1 < "$p" )
    fi
  done
  fixups
}

_sed_in_place() {
  f="$1"; shift
  sed "$@" "$f" > "$f.mavergreen-tmp" && mv "$f.mavergreen-tmp" "$f"
}

# Deterministic source edits that are awkward as context patches (they are simple, version-tolerant seds).
fixups() {
  # common.gypi: force the 10.9 deployment target / min-version.
  if [ -f "$SRC/common.gypi" ]; then
    _sed_in_place "$SRC/common.gypi" -e "s|'MACOSX_DEPLOYMENT_TARGET': '[0-9.]*'|'MACOSX_DEPLOYMENT_TARGET': '10.9'|g" \
      -e 's|-mmacosx-version-min=[0-9.]*|-mmacosx-version-min=10.9|g'
  fi
  # V8 safepoint: pthread_override_t is absent on 10.9 -> void*, and drop the start/end calls.
  _sed_in_place "$SRC/deps/v8/src/heap/safepoint.h" -e 's/pthread_override_t qos_override;/void* qos_override; \/\/ pthread_override not available on 10.9/'
  _sed_in_place "$SRC/deps/v8/src/heap/safepoint.cc" -e 's/pthread_override_t qos_override = nullptr;/void* qos_override = nullptr;/' \
    -e '/qos_override = pthread_override_qos_class_start_np/,/CHECK_NOT_NULL(qos_override);/d'
  _sed_in_place "$SRC/deps/v8/src/heap/safepoint.cc" -e '/CHECK_EQ($/{N;N;/pthread_override_qos_class_end_np/d;}'
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
  # generators in ways ./configure never records. A cross build's HOST toolset runs on the build machine
  # and needs no polyfill, so the library is scoped with target_conditions to _toolset=="target".
  if ! grep -q 'mavericks-compat/polyfills.o' "$SRC/common.gypi"; then
    awk -v lib="$poly" '{print} /default_configuration.*Release/ && !d {printf "    \047target_conditions\047: [ [ \047_toolset==\"target\"\047, { \047libraries\047: [ \047%s\047 ] } ] ],\n", lib; d=1}' \
      "$SRC/common.gypi" > "$SRC/common.gypi.tmp" && mv "$SRC/common.gypi.tmp" "$SRC/common.gypi"
  fi
  echo "build.sh: MODE=$MODE host=$HOST_OS prefix=$PREFIX"
  ( cd "$SRC" && CC="$CC" CXX="$CXX" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" \
      CPPFLAGS="$CPPFLAGS" MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
      env $(host_env) python3 ./configure $(configure_args) )
}

_first_line() { "$@" --version 2>/dev/null | sed -n 1p; }

record_build_tools() {
  {
    echo "build-make=$(_first_line make)"
    if [ "$MODE" = cross ]; then
      echo "build-host-cc=$(_first_line "$(host_env | sed -n 's/^CC_host=//p')")"
      echo "build-host-cxx=$(_first_line "$(host_env | sed -n 's/^CXX_host=//p')")"
    fi
  } > "$NODE_WORK/build-tools.txt"
}

make_() {
  _toolchain
  _build_tools_shim
  if [ "$MODE" = cross ] && [ "$HOST_OS" = Darwin ]; then
    # platform: Apple's clang, called by its real path rather than the /usr/bin xcrun shim, uses no SDK
    #           unless told, and finds no system headers.
    # platform: gyp gives the host toolset the target's -mmacosx-version-min=10.9 too, and the modern
    #           SDK's libc++ refuses aligned allocation below 10.13; a later -mmacosx-version-min wins.
    # platform: guarded macOS-only call -- HOST_OS is Darwin
    host_sdk="-isysroot $(xcrun --sdk macosx --show-sdk-path) -mmacosx-version-min=11.0"
    export CFLAGS_host="" CXXFLAGS_host="" CPPFLAGS_host="$host_sdk" LDFLAGS_host="$host_sdk"
  fi
  record_build_tools
  ( cd "$SRC" && CC="$CC" CXX="$CXX" CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" \
      CPPFLAGS="$CPPFLAGS" MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
      env $(host_env) make -j"$JOBS" )
}

guard() {
  bin="$SRC/out/Release/node"
  [ -x "$bin" ] || { echo "build.sh: not built ($bin absent) — skipping guard"; exit 77; }
  _toolchain
  OTOOL="$TCP/bin/llvm-otool" LIPO="$TCP/bin/llvm-lipo" NM="$TCP/bin/llvm-nm" STRINGS="$TCP/bin/llvm-strings" \
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
