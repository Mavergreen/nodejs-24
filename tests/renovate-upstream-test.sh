#!/bin/sh
# This repo ships ONE Node major from the root UPSTREAM_VERSION (see build/version.sh) -- lines/ is
# retired. Assert: lines/ does not exist; exactly one Renovate customManager matches the root
# UPSTREAM_VERSION; and that manager is capped (allowedVersions, inline or via a packageRule), so
# Renovate can never walk this repo onto a Node major it was never built for.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
rj="$root/.github/renovate.json"
[ -f "$rj" ] || { echo "FAIL: no $rj"; exit 1; }
[ -d "$root/lines" ] && { echo "FAIL: lines/ still exists"; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "python3 absent — skipping"; exit 77; }

python3 - "$rj" <<'PY'
import json, sys, re
cfg = json.load(open(sys.argv[1]))
mgrs = cfg.get("customManagers", [])
rules = cfg.get("packageRules", [])
path = "UPSTREAM_VERSION"

def matches(m, path):
    for p in m.get("managerFilePatterns", []):
        rx = p[1:-1] if len(p) >= 2 and p[0] == "/" and p.endswith("/") else p
        if re.search(rx, path):
            return True
    return False

def capped(m):
    dep = m.get("depNameTemplate") or ""
    if m.get("allowedVersions"):
        return True
    return any(dep and dep in (r.get("matchDepNames") or []) and r.get("allowedVersions") for r in rules)

owning = [m for m in mgrs if matches(m, path)]
assert owning, "no manager matches root UPSTREAM_VERSION"
assert len(owning) == 1, "more than one manager matches root UPSTREAM_VERSION: %r" % owning
assert capped(owning[0]), "the UPSTREAM_VERSION manager is uncapped"
print("PASS: renovate-upstream")
PY
