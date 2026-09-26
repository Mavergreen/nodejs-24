#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
. "$here/lib/x86_64.sh"
paths="$(sh "$root/build/paths.sh")"
BIN="$(printf '%s\n' "$paths" | sed -n 's/^SRC=//p')/out/Release/node"
[ -x "$BIN" ] || { echo "not built ($BIN) -- skipping"; exit 77; }
x86_64_or_skip
fail() { echo "FAIL: $*"; exit 1; }

x="$(mktemp -d "${TMPDIR:-/tmp}/startup-snapshot-test.XXXXXX")"; trap 'rm -rf "$x"' EXIT
p="$x/prefix"; mkdir -p "$p/bin" "$p/libexec/mavergreen"
cp "$BIN" "$p/bin/node"
cp "$root/build/startup-snapshot.sh" "$p/libexec/mavergreen/build-startup-snapshot"
blob="$p/lib/node/startup.blob"

x86_64_run /bin/sh "$p/libexec/mavergreen/build-startup-snapshot" \
  || fail "build-startup-snapshot failed"
[ -s "$blob" ] || fail "build-startup-snapshot wrote no $blob"

loads() {  # $1 = label; rest = node args. Succeeds when node ran AND deserialized a startup snapshot.
  _label="$1"; shift
  _out="$(NODE_DEBUG_NATIVE=SNAPSHOT_SERDES x86_64_run "$@" -e 'console.log("ran")' 2>"$x/err")" \
    || fail "$_label: node failed to start -- a default snapshot must never stop node: $(cat "$x/err")"
  [ "$_out" = ran ] || fail "$_label: node did not run the script (got '$_out')"
  grep -q 'SnapshotData::FromBlob() read [0-9]* bytes' "$x/err"
}

loads "default blob" "$p/bin/node" \
  || fail "node did not load $blob -- the startup snapshot generated at install time is ignored"
mkdir "$x/elsewhere"; ln -s "$p/bin/node" "$x/elsewhere/node"
loads "through a symlink" "$x/elsewhere/node" \
  || fail "node reached through a link-farm symlink did not load its tree's blob"
loads "--no-node-snapshot" "$p/bin/node" --no-node-snapshot \
  && fail "--no-node-snapshot still loaded the default blob"

cp "$blob" "$x/good.blob"
perl -0777 -pi -e 's/\Q24.\E(\d+)\.(\d+)/"24.$1." . ($2 == 9 ? 8 : 9)/e' "$blob"
cmp -s "$blob" "$x/good.blob" && fail "could not forge a stale blob for the test"
loads "stale blob" "$p/bin/node" \
  && fail "a blob from another Node version was loaded"

head -c 100000 /dev/urandom > "$blob"
loads "garbage blob" "$p/bin/node" \
  && fail "a garbage blob was loaded"
echo "PASS: startup-snapshot"
