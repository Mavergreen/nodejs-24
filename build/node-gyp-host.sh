#!/bin/sh
# platform: host-agnostic
#   usage: sh build/node-gyp-host.sh SRC DEST
#          Copies SRC's bundled npm to DEST (node-gyp needs npm's other modules beside it) with the gyp fix of
#          patches/0012-linux-host-toolset.patch applied to node-gyp's own gyp copy, so a host with neither
#          Xcode nor the Command Line Tools can build the guest's addon fixtures with
#          DEST/node_modules/node-gyp/bin/node-gyp.js. The npm that ships keeps upstream's bytes.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
src="${1:?usage: node-gyp-host.sh SRC DEST}"; dest="${2:?usage: node-gyp-host.sh SRC DEST}"
rm -rf "$dest"
cp -R "$src/deps/npm" "$dest"
hunk="$(awk '/^--- a\//{ on = ($2 == "a/tools/gyp/pylib/gyp/xcode_emulation.py") } on' "$SELF/../patches/0012-linux-host-toolset.patch")"
[ -n "$hunk" ] || { echo "node-gyp-host: patches/0012 carries no xcode_emulation.py hunk" >&2; exit 1; }
printf '%s\n' "$hunk" | sed 's|/tools/gyp/pylib/|/gyp/pylib/|' | patch -p1 -V none -d "$dest/node_modules/node-gyp"
