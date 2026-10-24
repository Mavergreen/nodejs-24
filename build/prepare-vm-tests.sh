#!/bin/sh
# platform: macOS-only -- cross-compiles Node's native test fixtures for the stock 10.9 guest.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/msc.sh"
. "$SELF/paths.sh"
NODE_SRC="$SRC"; export NODE_SRC
. "$SELF/toolchain.sh"
: "${HOST_NODE:?set HOST_NODE to a native host node executable}"
[ "$("$HOST_NODE" -p process.arch)" = "$(uname -m | sed 's/x86_64/x64/')" ] || {
  echo 'HOST_NODE must run natively on the build host' >&2; exit 1;
}
cd "$SRC"
# platform: upstream build_addons.py executes OUT/node to drive node-gyp; that must be host code.
mkdir -p "$NODE_WORK/addon-host"
printf '#!/bin/sh\nexec "%s" "$@" --arch=x64\n' "$HOST_NODE" > "$NODE_WORK/addon-host/node"
chmod +x "$NODE_WORK/addon-host/node"
headers="$NODE_WORK/addon-headers"
python3 tools/install.py install --headers-only --dest-dir "$headers" --prefix /
export AR="$(dirname "$CC")/llvm-ar" CC CXX CFLAGS CXXFLAGS CPPFLAGS MACOSX_DEPLOYMENT_TARGET
# platform: gyp's Darwin generator calls libtool by name; reuse the build's LLVM archiver shim.
PATH="$NODE_WORK/build-tools:$PATH"; export PATH
LDFLAGS="$SRC/deps/mavericks-compat/polyfills.o"; export LDFLAGS
for suite in test/addons test/js-native-api test/node-api test/sqlite benchmark/napi; do
  python3 tools/build_addons.py --headers-dir "$headers" \
    --out-dir "$NODE_WORK/addon-host" --loglevel info "$suite"
done
# platform: only target executables enter the guest; gyp's arm64 generator tools remain on the host.
for binary in cctest embedtest; do
  [ -x "out/Release/$binary" ]
  [ "$(lipo -info "out/Release/$binary" | sed -n 's/.*: //p' | xargs)" = x86_64 ]
done
bundle="$NODE_WORK/vm-tests"
rm -rf "$bundle"; mkdir -p "$bundle/out/Release"
# spec: upstream test suites read source fixtures and config.gypi relative to their original tree.
# platform: Mavericks tar under the C locale mangles non-ASCII fixture names on round-trip.
LC_ALL=en_US.UTF-8 tar --exclude='./out' --exclude='./.git' -cf "$NODE_WORK/vm-source.tar" .
LC_ALL=en_US.UTF-8 tar -xf "$NODE_WORK/vm-source.tar" -C "$bundle"
rm "$NODE_WORK/vm-source.tar"
cp out/Release/cctest out/Release/embedtest "$bundle/out/Release/"
# platform: tests use both process.execPath and out/Release/node; both must resolve the installed pkg.
ln -s "$PREFIX/bin/node" "$bundle/out/Release/node"
cp "$MAVERICKS_ROOT/UPSTREAM_VERSION" "$bundle/MAVERGREEN_UPSTREAM_VERSION"
LC_ALL=en_US.UTF-8 tar -czf "$NODE_WORK/node-vm-tests.tar.gz" -C "$bundle" .
