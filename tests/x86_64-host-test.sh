#!/bin/sh
# platform: host-agnostic
# tests/lib/x86_64.sh decides from the host whether the shipped x86_64 node may execute here: never on
# Linux, never on an Apple Silicon Mac (whose Rosetta would run it translated), natively on 10.9 or Intel.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/x86_64-host.XXXXXX")"; trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
for tool in arch true; do
  printf '#!/bin/sh\necho "%s ran" >> "%s/ran"\nexit 0\n' "$tool" "$t" > "$t/bin/$tool"; chmod +x "$t/bin/$tool"
done
decide() { # $1 = uname -s, $2 = uname -m, $3 = hw.optional.arm64 ("" = absent)
  printf '#!/bin/sh\ncase "$1" in -s) echo %s ;; -m) echo %s ;; *) echo %s ;; esac\n' "$1" "$2" "$1" > "$t/bin/uname"
  if [ -n "$3" ]; then printf '#!/bin/sh\necho %s\n' "$3" > "$t/bin/sysctl"
  else printf '#!/bin/sh\necho "sysctl: unknown oid" >&2\nexit 1\n' > "$t/bin/sysctl"; fi
  chmod +x "$t/bin/uname" "$t/bin/sysctl"
  rc=0; ( PATH="$t/bin:$PATH"; . "$here/lib/x86_64.sh"; x86_64_or_skip ) >/dev/null || rc=$?
  echo "$rc"
}
fail=0
check() { [ "$2" = "$3" ] || { echo "FAIL: $1: exit $2, want $3"; fail=1; }; }
check "Linux x86_64 runs no Mach-O" "$(decide Linux x86_64 '')" 77
check "Apple Silicon (arm64 shell)" "$(decide Darwin arm64 1)" 77
check "Apple Silicon (a Rosetta shell says x86_64)" "$(decide Darwin x86_64 1)" 77
check "Mac OS X 10.9 (no hw.optional.arm64)" "$(decide Darwin x86_64 '')" 0
check "an Intel Mac" "$(decide Darwin x86_64 0)" 0
[ ! -e "$t/ran" ] || { echo "FAIL: deciding ran a program instead of asking the host: $(cat "$t/ran")"; fail=1; }
[ "$fail" -eq 0 ] && echo "PASS: x86_64-host"
exit "$fail"
