#!/bin/sh
# platform: host-agnostic
# A Linux cross build's host-cc/host-c++ (build.sh host-compiler) hand the runner's compiler what gyp's mac
# generator gave the host toolset, minus the flags only Apple's toolchain or clang accept, and link with lld.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/host-compiler.XXXXXX")"; trap 'rm -rf "$t"' EXIT
printf '#!/bin/sh\nfor a do printf "%%s\\n" "$a"; done\n' > "$t/real"; chmod +x "$t/real"
sh "$root/build/build.sh" host-compiler "$t/host-cc" "$t/real"
got="$("$t/host-cc" -O3 -mmacosx-version-min=10.9 -stdlib=libc++ -Werror=undefined-inline -Wno-nullability-completeness \
  -arch x86_64 -isysroot /sdk -framework CoreFoundation -Wl,-search_paths_first -DX=1 -c a.cc -o a.o | tr '\n' ' ')"
want="-fuse-ld=lld -O3 -DX=1 -c a.cc -o a.o "
[ "$got" = "$want" ] || { echo "FAIL: host-cc passed [$got], want [$want]"; exit 1; }
echo "PASS: host-compiler"
