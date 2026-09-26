#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
x="$(mktemp -d "${TMPDIR:-/tmp}/package-version-test.XXXXXX")"; trap 'rm -rf "$x"' EXIT
mkdir -p "$x/repo"
cp -R "$root/build" "$root/components" "$root/UPSTREAM_VERSION" "$x/repo/"
V="$(tr -d '[:space:]' < "$root/UPSTREAM_VERSION")"
echo "0.0.1-mavericks.1" > "$x/repo/VERSION"
if out="$(NODE_WORK="$x/work" sh "$x/repo/build/package.sh" pkg 2>&1)"; then
  echo "FAIL: packaging with VERSION 0.0.1-mavericks.1 for upstream $V succeeded -- the pkg would be mislabeled"; exit 1
fi
printf '%s\n' "$out" | grep -q 'stale' \
  || { echo "FAIL: a stale VERSION must be refused by name, got: $out"; exit 1; }
if out="$(sh "$x/repo/build/full-version.sh" 2>&1)"; then
  echo "FAIL: full-version.sh accepted VERSION 0.0.1-mavericks.1 for upstream $V"; exit 1
fi
printf '%s\n' "$out" | grep -q 'stale' || { echo "FAIL: full-version.sh must name a stale VERSION, got: $out"; exit 1; }
rm -f "$x/repo/VERSION"
full="$(sh "$x/repo/build/full-version.sh")" || { echo "FAIL: full-version.sh failed with no VERSION"; exit 1; }
case "$full" in "$V"-mavericks.[0-9]*) ;; *) echo "FAIL: full-version.sh printed '$full', not $V-mavericks.N"; exit 1 ;; esac
echo "PASS: package-version"
