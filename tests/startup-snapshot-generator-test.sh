#!/bin/sh
# platform: host-agnostic
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
node="${HOST_NODE:-$(command -v node || true)}"
[ -n "$node" ] || { echo 'no native Node available -- skipping'; exit 77; }
line="$(cut -d. -f1 "$root/UPSTREAM_VERSION")"
[ "$("$node" -p 'process.versions.node.split(".")[0]')" = "$line" ] || {
  echo "requires native Node $line -- skipping"; exit 77;
}
work="$(mktemp -d "${TMPDIR:-/tmp}/snapshot-generator.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/libexec/mavergreen"
cp "$node" "$work/bin/node"
cp "$root/build/startup-snapshot.sh" "$work/libexec/mavergreen/build-startup-snapshot"
sh "$work/libexec/mavergreen/build-startup-snapshot"
# spec: the install-time snapshot must preserve Console and REPL initialization.
"$work/bin/node" --snapshot-blob "$work/lib/node/startup.blob" -e '
  const assert = require("node:assert/strict");
  const { Console } = require("node:console");
  const { PassThrough, Readable } = require("node:stream");
  const output = new PassThrough();
  let text = "";
  output.on("data", chunk => { text += chunk; });
  new Console(output).log("snapshot console works");
  assert.equal(text, "snapshot console works\n");
  const repl = require("node:repl").start({ input: Readable.from([]), output });
  repl.close();
'
echo 'PASS: startup snapshot preserves Console and REPL'
