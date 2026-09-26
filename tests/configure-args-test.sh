#!/bin/sh
# build.sh must assemble the same ./configure invocation the monolith used, with the per-line prefix --
# plus, in cross MODE, the flags that tell Node it is not building for the host it runs on.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
L="$(tr -d '[:space:]' < "$root/UPSTREAM_VERSION" | sed 's/\..*//')"
base="--prefix=/usr/local/mavergreen/node$L --with-intl=full-icu --download=all --fully-static --enable-static --without-node-snapshot"
fail=0

check() { # name expected actual
  if [ "$2" != "$3" ]; then echo "FAIL $1:"; echo "  expected: $2"; echo "  actual:   $3"; fail=1; fi
}

out_native="$(MODE=native sh "$root/build/build.sh" configure-args)"
check native "$base" "$out_native"

out_cross="$(MODE=cross sh "$root/build/build.sh" configure-args)"
check cross "$base --dest-cpu=x64 --dest-os=mac --cross-compiling" "$out_cross"

[ "$fail" -eq 0 ] && echo "PASS: configure-args"
exit "$fail"
