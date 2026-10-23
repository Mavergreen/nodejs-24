#!/bin/sh
# platform: macOS-only -- required acceptance of the run's installed pkg on Mac OS X 10.9.
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
: "${FULL:?workflow must supply its resolved release version}"
[ "$(sw_vers -productVersion)" = 10.9.5 ]
upstream="$(cat UPSTREAM_VERSION)"
line="${upstream%%.*}"
prefix="/usr/local/mavergreen/node$line"
pkg="$root/dist/nodejs-$FULL.pkg"
[ -f "$pkg" ]
sudo installer -pkg "$pkg" -target /
manifest="$prefix/mavergreen.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :version' "$manifest")" = "$FULL" ]
[ "$("$prefix/bin/node" --version)" = "v$upstream" ]
PATH="$prefix/bin:/usr/local/mavergreen/bin:$PATH"; export PATH
for command in npm npx corepack; do "$prefix/bin/$command" --version; done
# spec: build/hooks.sh -- postinstall generates the startup snapshot on the actual target.
[ -s "$prefix/lib/node/startup.blob" ]
app="/Library/Application Support/Mavergreen/node$line-updater.app"
[ -x "$app/Contents/MacOS/node$line-updater" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$FULL" ]
[ -f "/Library/LaunchAgents/dev.mavergreen.nodejs.node$line-updatecheck.plist" ]
NODE_DEBUG_NATIVE=SNAPSHOT_SERDES "$prefix/bin/node" -e 'console.log("installed node runs")' 2>snapshot.log
grep 'SnapshotData::FromBlob() read [0-9]* bytes' snapshot.log
python_pkg="$(cat components/test-python/version)"
sudo installer -pkg "$root/test-tools/python-$python_pkg.pkg" -target /
PYTHON=/usr/local/mavergreen/python315/bin/python3.15
"$PYTHON" --version
PATH="$(dirname "$PYTHON"):$PATH"; export PATH
SHIPYARD_SCRIPTS="$root/.shipyard-scripts"; export SHIPYARD_SCRIPTS
work="$(mktemp -d /tmp/node-vm-tests.XXXXXX)"
fixture_link=""
trap '[ -z "$fixture_link" ] || sudo rm -f "$fixture_link"; rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/node-v$upstream"
tar -xzf dist/node-vm-tests.tar.gz -C "$work/node-v$upstream"
[ "$(cat "$work/node-v$upstream/MAVERGREEN_UPSTREAM_VERSION")" = "$upstream" ]
# platform: upstream resolves companion test binaries beside process.execPath, the installed Node.
[ ! -e "$prefix/bin/embedtest" ] && [ ! -L "$prefix/bin/embedtest" ]
sudo ln -s "$work/node-v$upstream/out/Release/embedtest" "$prefix/bin/embedtest"
fixture_link="$prefix/bin/embedtest"
NODE_WORK="$work"; export NODE_WORK
# spec: acceptance on real 10.9 -- mandatory guest checks must not turn exit 77 into green.
sh tests/smoke-test.sh
sh tests/startup-snapshot-test.sh
cd "$work/node-v$upstream"
mkdir -p "$root/vm-results"
out/Release/cctest --gtest_output="xml:$root/vm-results/cctest.xml"
"$PYTHON" tools/test.py --mode=release --shell="$prefix/bin/node" \
  -j 2 -p tap --logfile "$root/vm-results/upstream.tap" \
  default pummel addons js-native-api node-api sqlite embedding benchmark
cd "$root"
MAVERICKS_TAGS="" MAVERICKS_TEST_JOBS=1 SHIPYARD_SCRIPTS="$root/.shipyard-scripts" \
  sh .shipyard-scripts/run-repo-tests.sh
