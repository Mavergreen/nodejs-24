#!/bin/sh
# platform: host-agnostic
#   usage: prepare-sandbox-fixture.sh NODE FIXTURES OUTPUT
#          Builds OUTPUT/node_sandboxed.app around a copy of NODE, signed ad hoc with upstream's sandbox
#          entitlements, and records NODE's SHA-256 in OUTPUT/node.sha256. The stock 10.9 guest can verify a
#          signature but lacks the developer tools' signing allocator, so the signing happens here: with
#          rcodesign (build/fetch-rcodesign.sh) on Linux and a modern Mac, with /usr/bin/codesign on 10.9.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
[ "$#" -eq 3 ] || { echo 'usage: prepare-sandbox-fixture.sh NODE FIXTURES OUTPUT' >&2; exit 2; }
node=$1; fixtures=$2; output=$3
[ -x "$node" ]
[ -f "$fixtures/Info.plist" ]
[ -f "$fixtures/node_sandboxed.entitlements" ]
app="$output/node_sandboxed.app"
mkdir -p "$output"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$fixtures/Info.plist" "$app/Contents/Info.plist"
cp "$node" "$app/Contents/MacOS/node"
digest=$(shasum -a 256 "$node")
printf '%s\n' "${digest%% *}" > "$output/node.sha256"
if [ "$(uname -s)" = Darwin ] && [ "$(uname -r | cut -d. -f1)" = 13 ]; then
  # platform: guarded macOS-only call -- Darwin 13 is Mac OS X 10.9, where rcodesign does not run
  /usr/bin/codesign --entitlements "$fixtures/node_sandboxed.entitlements" --force --sign - "$app"
  # platform: guarded macOS-only call -- Darwin 13 is Mac OS X 10.9
  /usr/bin/codesign --verify "$app"
else
  rc="$(sh "$SELF/fetch-rcodesign.sh")"
  "$rc" sign --entitlements-xml-path "$fixtures/node_sandboxed.entitlements" "$app"
  "$rc" verify "$app/Contents/MacOS/node"
fi
