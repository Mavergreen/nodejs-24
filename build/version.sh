#!/bin/sh
# Thin wrapper: the logic lives in shipyard (scripts/version.sh) so it cannot drift between repos.
# Every call site -- tests/version-test.sh, build/build.sh, the release workflow, and a plain
# `sh build/version.sh auto` -- keeps working through this.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT

# One repo ships ONE Node major LINE, from the root UPSTREAM_VERSION -- never a per-line file. The
# LINE is derived from the upstream version (24.6.0 -> 24), never configured separately: a caller-
# supplied $NODE_LINE is honoured only as a CHECK against the derived value, never as an override --
# pairing NODE_LINE=99 with a 24.x UPSTREAM_VERSION is a bug, not a way to build a different line.
_up_root="$MAVERICKS_ROOT/UPSTREAM_VERSION"
[ -f "$_up_root" ] || { echo "version.sh: no UPSTREAM_VERSION at repo root" >&2; exit 1; }
_derived_line="$(tr -d '[:space:]' < "$_up_root" | sed -n 's/^\([0-9][0-9]*\)\..*$/\1/p')"
[ -n "$_derived_line" ] || { echo "version.sh: cannot derive NODE_LINE from $_up_root" >&2; exit 1; }
if [ -n "${NODE_LINE:-}" ] && [ "$NODE_LINE" != "$_derived_line" ]; then
  echo "version.sh: NODE_LINE=$NODE_LINE was given but $_up_root derives $_derived_line -- one source of truth" >&2
  exit 1
fi
NODE_LINE="$_derived_line"
export NODE_LINE
MAVERICKS_UPSTREAM_FILE="$_up_root"; export MAVERICKS_UPSTREAM_FILE
if [ "${1:-}" = line ]; then printf '%s\n' "$NODE_LINE"; exit 0; fi

. "$SELF/msc.sh"
exec sh "$SHIPYARD/version.sh" "$@"
