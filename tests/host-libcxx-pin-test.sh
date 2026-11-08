#!/bin/sh
# platform: host-agnostic
# build/host-libcxx.sh builds the Linux host's libc++ only from the LLVM release clang22 itself is: a
# components/clang22/llvm-project naming another LLVM is refused, by name, before anything is fetched.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/host-libcxx-pin.XXXXXX")"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/repo"; cp -R "$root/build" "$root/components" "$t/repo/"
cv="$(tr -d ' \t\n' < "$root/components/clang22/version")"
case "$cv" in "$(awk '{ print $1 }' "$root/components/clang22/llvm-project")"-*) ;;
  *) echo "FAIL: components/clang22/llvm-project does not name the LLVM clang22 $cv is built from"; exit 1 ;; esac
printf '21.1.0 %064d\n' 0 > "$t/repo/components/clang22/llvm-project"
if out="$(MAVERGREEN_HOST_LIBCXX_CACHE="$t/cache" sh "$t/repo/build/host-libcxx.sh" /nonexistent 2>&1)"; then
  echo "FAIL: a libc++ pin for another LLVM than clang22's was accepted"; exit 1
fi
case "$out" in *"not LLVM 21.1.0"*) ;; *) echo "FAIL: the refusal must name the mismatch (got: $out)"; exit 1 ;; esac
[ ! -e "$t/cache" ] || { echo "FAIL: a refused pin must fetch nothing"; exit 1; }
echo "PASS: host-libcxx-pin"
