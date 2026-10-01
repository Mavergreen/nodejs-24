#!/bin/sh
# Backport Node's Python 3.14 configure support when the pinned Node source lacks it.
apply_python_314_compat_patch() {
  python_314_src=$1
  python_314_patch=$2
  if grep -Fqx 'command -v python3.14 >/dev/null && exec python3.14 "$0" "$@"' "$python_314_src/configure" &&
     grep -Fqx 'acceptable_pythons = ((3, 14), (3, 13), (3, 12), (3, 11), (3, 10), (3, 9))' "$python_314_src/configure"; then
    echo "build.sh: Node source already supports Python 3.14"
  else
    (cd "$python_314_src" && patch -p1 < "$python_314_patch")
  fi
}
