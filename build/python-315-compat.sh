# platform: host-agnostic
# spec: patches/0005-python-315.patch -- no-op once upstream accepts and selects Python 3.15.
apply_python_315_compat_patch() {
  if grep -Fqx 'command -v python3.15 >/dev/null && exec python3.15 "$0" "$@"' "$1/configure" &&
     grep -Eq '^acceptable_pythons = .*\(3, 15\)' "$1/configure"; then
    echo "build.sh: Node source already supports Python 3.15"
  else
    (cd "$1" && patch -V none -p1 < "$2")
  fi
}
