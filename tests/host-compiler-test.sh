#!/bin/sh
# platform: host-agnostic
# A Linux cross build's host-cc/host-c++ (build.sh host-compiler) hand clang22 its Linux-host flags and what gyp's
# mac generator gave the host toolset, minus the flags only an Apple target accepts; a link adds -fuse-ld=lld
# and the host libc++ after every input, a compile does not.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/host-compiler.XXXXXX")"; trap 'rm -rf "$t"' EXIT
printf '#!/bin/sh\nfor a do printf "%%s\\n" "$a"; done\n' > "$t/real"; chmod +x "$t/real"
sh "$root/build/build.sh" host-compiler "$t/host-c++" "$t/real" "--target=x86_64-unknown-linux-gnu -nostdinc++" "-nostdlib++ /l/libc++.a"
got="$("$t/host-c++" -O3 -mmacosx-version-min=10.9 -stdlib=libc++ -Werror=undefined-inline -Wno-nullability-completeness \
  -arch x86_64 -isysroot /sdk -framework CoreFoundation -Wl,-search_paths_first -DX=1 -c a.cc -o a.o | tr '\n' ' ')"
want="--target=x86_64-unknown-linux-gnu -nostdinc++ -O3 -DX=1 -c a.cc -o a.o "
[ "$got" = "$want" ] || { echo "FAIL: a compile passed [$got], want [$want]"; exit 1; }
got="$("$t/host-c++" -stdlib=libc++ -framework CoreFoundation a.o b.a -o tool | tr '\n' ' ')"
want="--target=x86_64-unknown-linux-gnu -nostdinc++ -fuse-ld=lld a.o b.a -o tool -nostdlib++ /l/libc++.a "
[ "$got" = "$want" ] || { echo "FAIL: a link passed [$got], want [$want]"; exit 1; }
echo "PASS: host-compiler"
