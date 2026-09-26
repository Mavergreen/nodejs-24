#!/bin/sh
#   usage: sh build/full-version.sh [auto|local]
#          Prints this build's full version, <UPSTREAM_VERSION>-mavericks.N, via shipyard's
#          resolve-version.sh (which writes the gitignored VERSION). Refuses a VERSION left over from
#          another upstream: the pkg, the updater and the manifest all carry this one string.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/msc.sh"
upstream="$(tr -d '[:space:]' < "$MAVERICKS_ROOT/UPSTREAM_VERSION")"
full="$(sh "$SHIPYARD/resolve-version.sh" "${1:-auto}")"
[ -n "$full" ] || { echo "full-version.sh: resolve-version.sh printed no version" >&2; exit 1; }
[ "${full%-mavericks.*}" = "$upstream" ] \
  || { echo "full-version.sh: VERSION ($full) is stale for upstream $upstream -- delete $MAVERICKS_ROOT/VERSION" >&2; exit 1; }
printf '%s\n' "$full"
