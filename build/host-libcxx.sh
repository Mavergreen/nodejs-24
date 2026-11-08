#!/bin/sh
# platform: host-agnostic
#   usage: sh build/host-libcxx.sh CLANG22_PREFIX
#          Prints a prefix holding libc++ and libc++abi (static, include/c++/v1 and lib/libc++.a) for this x86_64
#          Linux host, built by that clang22 from the llvm-project release clang22 is built from
#          (components/clang22/llvm-project: VERSION SHA256, the release's own published digest), and cached.
#          A cross build's host toolset uses it, so V8's host tools on Linux use clang22 and its own libc++ as on
#          every Mac host. clang22's Linux archive ships a libc++ for Darwin targets only.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/msc.sh"
. "$SHIPYARD/mavericks_fetch.sh"
CL="${1:?usage: host-libcxx.sh CLANG22_PREFIX}"
pin="$SELF/../components/clang22/llvm-project"
v="$(awk '{ print $1 }' "$pin")"; sha="$(awk '{ print $2 }' "$pin")"
cv="$(tr -d ' \t\n' < "$SELF/../components/clang22/version")"
case "$cv" in "$v"-*) ;; *) echo "host-libcxx: clang22 $cv is not LLVM $v; update components/clang22/llvm-project" >&2; exit 1 ;; esac
base="${MAVERGREEN_HOST_LIBCXX_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/mavergreen-host-libcxx}"
dest="$base/$cv"
if [ -f "$dest/lib/libc++.a" ] && [ -f "$dest/include/c++/v1/__config_site" ]; then echo "$dest"; exit 0; fi
asset="llvm-project-$v.src.tar.xz"
shipyard_fetch_verified "https://github.com/llvm/llvm-project/releases/download/llvmorg-$v/$asset" "$sha" "$base/dl" "$asset" >&2
work="$(mktemp -d "${TMPDIR:-/tmp}/host-libcxx.XXXXXX")"; trap 'rm -rf "$work"' EXIT
tar -xJf "$base/dl/$asset" -C "$work"
s="$work/llvm-project-$v.src"
cm="$(command -v cmake)" || { echo "host-libcxx: no cmake on PATH" >&2; exit 1; }
flags="--no-default-config -rtlib=libgcc --unwindlib=libgcc -stdlib=libstdc++"
"$cm" -S "$s/runtimes" -B "$work/b" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$dest.tmp" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF -DLLVM_INCLUDE_TESTS=OFF \
  -DCMAKE_C_COMPILER="$CL/bin/clang" -DCMAKE_CXX_COMPILER="$CL/bin/clang++" \
  -DCMAKE_C_COMPILER_TARGET=x86_64-unknown-linux-gnu -DCMAKE_CXX_COMPILER_TARGET=x86_64-unknown-linux-gnu \
  -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" \
  -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld --ld-path=$CL/bin/ld.lld" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld --ld-path=$CL/bin/ld.lld" \
  -DCMAKE_AR="$CL/bin/llvm-ar" -DCMAKE_RANLIB="$CL/bin/llvm-ranlib" \
  -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLIBCXXABI_USE_LLVM_UNWINDER=OFF -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF >&2
"$cm" --build "$work/b" --target install-cxx install-cxxabi -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" >&2
rm -rf "$dest"; mv "$dest.tmp" "$dest"
[ -f "$dest/lib/libc++.a" ] && [ -f "$dest/include/c++/v1/__config_site" ] \
  || { echo "host-libcxx: the build installed no lib/libc++.a or include/c++/v1/__config_site under $dest" >&2; exit 1; }
echo "$dest"
