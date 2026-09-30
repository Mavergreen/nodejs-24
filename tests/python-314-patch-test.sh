#!/bin/sh
# The Node 24.6 configure shim must prefer Python 3.14 and accept it.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/python314.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

cat > "$tmp/configure" <<'CONFIGURE'
#!/bin/sh

# Locate an acceptable Python interpreter and then re-execute the script.
# Note that the mix of single and double quotes is intentional,
# as is the fact that the ] goes on a new line.
_=[ 'exec' '/bin/sh' '-c' '''
command -v python3.13 >/dev/null && exec python3.13 "$0" "$@"
command -v python3.12 >/dev/null && exec python3.12 "$0" "$@"
command -v python3.11 >/dev/null && exec python3.11 "$0" "$@"
command -v python3.10 >/dev/null && exec python3.10 "$0" "$@"
command -v python3.9 >/dev/null && exec python3.9 "$0" "$@"
command -v python3 >/dev/null && exec python3 "$0" "$@"
exec python "$0" "$@"
''' "$0" "$@"
]
del _

import sys
try:
  from shutil import which
except ImportError:
  from distutils.spawn import find_executable as which

print('Node.js configure: Found Python {}.{}.{}...'.format(*sys.version_info))
acceptable_pythons = ((3, 13), (3, 12), (3, 11), (3, 10), (3, 9))
if sys.version_info[:2] in acceptable_pythons:
CONFIGURE
. "$root/build/python-314-compat.sh"
apply_python_314_compat_patch "$tmp" "$root/patches/0004-python-314.patch"
grep -q '^command -v python3\.14 .*exec python3\.14 ' "$tmp/configure"
grep -q '^acceptable_pythons = ((3, 14), (3, 13),' "$tmp/configure"
apply_python_314_compat_patch "$tmp" "$root/patches/0004-python-314.patch"
[ "$(grep -c '^command -v python3\.14 ' "$tmp/configure")" -eq 1 ]
echo "PASS: python-314-patch"
