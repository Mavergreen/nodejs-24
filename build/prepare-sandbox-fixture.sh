#!/bin/sh
# platform: macOS-only -- codesign_allocate is a developer tool absent from the stock runtime guest.
set -eu
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
set -- --entitlements "$fixtures/node_sandboxed.entitlements" --force --sign -
# platform: pre-10.11 signers use SHA-1; modern signers must retain that legacy code directory.
# spec: https://developer.apple.com/documentation/technotes/tn3126-inside-code-signing-hashes
case "$(sw_vers -productVersion)" in
  10.9|10.9.*|10.10|10.10.*) ;;
  *) set -- "$@" --digest-algorithm=sha1,sha256 ;;
esac
/usr/bin/codesign "$@" "$app"
/usr/bin/codesign --verify "$app"
