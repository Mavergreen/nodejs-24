#!/bin/sh
# platform: verify modern macOS signatures on the stock Mavericks runtime guest.
set -eu
mkdir -p vm-results
set -- dist/nodejs-*.pkg
[ "$#" -eq 1 ] && [ -f "$1" ]
sudo installer -pkg "$1" -target /
work=$(mktemp -d /tmp/node-sandbox-diagnostic.XXXXXX)
LC_ALL=en_US.UTF-8 tar -xzf dist/prepared-sandbox.tar.gz -C "$work"
node=/usr/local/mavergreen/node24/bin/node
{
  sw_vers
  digest=$(shasum -a 256 "$node")
  [ "${digest%% *}" = "$(cat "$work/node.sha256")" ]
  /usr/bin/codesign --verify --verbose "$work/node_sandboxed.app"
  expected=$("$node" --version)
  actual=$("$work/node_sandboxed.app/Contents/MacOS/node" --version)
  [ "$actual" = "$expected" ]
  printf 'Verified modern signature, exact installed binary, and executable version: %s\n' "$actual"
  printf 'Full sandbox runtime acceptance remains in normal Node CI after the libuv descriptor fix.\n'
} > vm-results/signature.log 2>&1
cat vm-results/signature.log
