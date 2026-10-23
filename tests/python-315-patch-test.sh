#!/bin/sh
# platform: host-agnostic
# spec: Python configure backport must apply once, preserve 3.14 support, and reject future versions.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/python315.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cp "$root/tests/fixtures/configure-python314" "$tmp/configure"
. "$root/build/python-315-compat.sh"
. "$root/build/python-314-compat.sh"
apply_python_315_compat_patch "$tmp" "$root/patches/0005-python-315.patch"
cp "$tmp/configure" "$tmp/once"
apply_python_315_compat_patch "$tmp" "$root/patches/0005-python-315.patch"
apply_python_314_compat_patch "$tmp" "$root/patches/0004-python-314.patch"
cmp "$tmp/once" "$tmp/configure"
printf 'configured = True\n' > "$tmp/configure.py"
python3 - "$tmp" <<'PY'
import pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
for version, expected in [((3, 14, 0), 0), ((3, 15, 0), 0), ((3, 16, 0), 1)]:
    code = f'import sys, runpy; sys.path.insert(0, {str(root)!r}); sys.version_info = {version!r}; runpy.run_path({str(root / "configure")!r})'
    result = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True)
    assert result.returncode == expected, result.stdout + result.stderr
PY
# spec: unexpected upstream layouts must fail visibly instead of silently leaving support absent.
printf 'changed upstream layout\n' > "$tmp/configure"
if apply_python_315_compat_patch "$tmp" "$root/patches/0005-python-315.patch" >/dev/null 2>&1; then
  echo 'FAIL: accepted an unpatchable configure'; exit 1
fi
echo 'PASS: python-315-patch'
