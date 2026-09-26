#!/bin/sh
#   usage: <prefix>/libexec/mavergreen/build-startup-snapshot
#          (Re)generates <prefix>/lib/node/startup.blob with <prefix>/bin/node, which loads it at every
#          start. Installed into the product tree and run by the pkg's postinstall; safe to rerun by hand.
#          A blob that does not start node is never put in place.
set -eu
here="$(cd "$(dirname "$0")" && pwd -P)"
prefix="$(cd "$here/../.." && pwd -P)"
node="$prefix/bin/node"; out="$prefix/lib/node/startup.blob"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/node-startup-snapshot.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/empty.js"
( cd "$tmp" && "$node" --snapshot-blob "$tmp/startup.blob" --build-snapshot "$tmp/empty.js" ) >/dev/null
"$node" --snapshot-blob "$tmp/startup.blob" -e 0
mkdir -p "$prefix/lib/node"
cp "$tmp/startup.blob" "$out.new.$$"
mv -f "$out.new.$$" "$out"
