#!/bin/sh
# version.sh: derives <upstream>-mavericks.N + RELEASE decision. Upstream is read from the root
# UPSTREAM_VERSION (NOT hardcoded) so a Renovate bump never breaks this test.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../build/version.sh"
R="$here/.."
U="$(tr -d '[:space:]' < "$R/UPSTREAM_VERSION")"

# auto, no existing tags -> N=1, RELEASE=yes
out="$(MAVERICKS_TAGS='' sh "$script" auto)"
printf '%s\n' "$out" | grep -q "^FULL=${U}-mavericks.1$" || { echo "FAIL auto/new FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^RELEASE=yes$'           || { echo "FAIL auto/new REL: $out"; exit 1; }

# auto, existing tags -> N=max, RELEASE=no
out="$(MAVERICKS_TAGS="${U}-mavericks.1
${U}-mavericks.3
${U}-mavericks.2" sh "$script" auto)"
printf '%s\n' "$out" | grep -q "^FULL=${U}-mavericks.3$" || { echo "FAIL auto/exist FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^RELEASE=no$'            || { echo "FAIL auto/exist REL: $out"; exit 1; }

# local -> N=max+1, RELEASE=yes
out="$(MAVERICKS_TAGS="${U}-mavericks.3" sh "$script" local)"
printf '%s\n' "$out" | grep -q "^FULL=${U}-mavericks.4$" || { echo "FAIL local FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -q '^RELEASE=yes$'           || { echo "FAIL local REL: $out"; exit 1; }

echo "PASS: version"

# NODE_LINE is DERIVED from the upstream version's MAJOR (root UPSTREAM_VERSION), not configured.
# Two sources of truth for "which line is this" is how a repo ends up building 24.x and stamping a
# node26 pkg identifier.
expected_major="$(printf '%s' "$U" | sed -n 's/^\([0-9][0-9]*\)\..*$/\1/p')"
derived="$(NODE_LINE= sh "$script" line)"
[ "$derived" = "$expected_major" ] || { echo "FAIL: derived line '$derived', expected '$expected_major'"; exit 1; }
echo "PASS: line derivation"

# A caller-supplied NODE_LINE is a CHECK, not an override: pairing NODE_LINE=99 with a 24.x
# UPSTREAM_VERSION must fail loudly, not silently build the wrong line.
mismatch_out="$(NODE_LINE=99 sh "$script" line 2>&1)" && { echo "FAIL: NODE_LINE=99 sh build/version.sh line should have failed, printed: $mismatch_out"; exit 1; }
echo "PASS: NODE_LINE mismatch rejected"
