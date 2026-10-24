#!/bin/sh
# platform: macOS-only -- reproduce sandbox signing on the stock Mavericks guest.
set -eu
root=$(pwd)
mkdir -p vm-results
set -- dist/nodejs-*.pkg
[ "$#" -eq 1 ] && [ -f "$1" ]
sudo installer -pkg "$1" -target /
work=$(mktemp -d /tmp/node-sandbox-diagnostic.XXXXXX)
LC_ALL=en_US.UTF-8 tar -xzf dist/node-vm-tests.tar.gz -C "$work"
{
  sw_vers
  ls -l /usr/bin/codesign /usr/bin/codesign_allocate || :
  /usr/bin/xcode-select --print-path || :
} > vm-results/toolchain.txt 2>&1
cat vm-results/toolchain.txt
set +e
/usr/local/mavergreen/node24/bin/node --require "$root/tests/vm/log-codesign.cjs" \
  "$work/test/parallel/test-macos-app-sandbox.js" > vm-results/sandbox.log 2>&1
result=$?
cat vm-results/sandbox.log
printf '%s\n' "$result" > vm-results/exit-status
exit "$result"
