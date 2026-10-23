#!/bin/sh
# platform: host-agnostic
# spec: extraction delegates verification/component selection to shipyard and repairs the relocated SDK link.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/node-toolchain.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/shipyard" "$tmp/sdk"
cat > "$tmp/shipyard/fetch_product_pkg.sh" <<'SH'
#!/bin/sh
set -eu
[ "${FAIL_FETCH:-0}" = 0 ] || exit 1
printf '%s\n' "$@" > "$CALL_LOG"
[ "$1" = --asset ]; shift 2
mkdir -p "$3/bin"
printf '#!/bin/sh\nexit 0\n' > "$3/bin/clang"
chmod +x "$3/bin/clang"
[ -e "$3/SDKs" ] || [ -L "$3/SDKs" ] || ln -s ../sdk109/SDKs "$3/SDKs"
SH
printf '#!/bin/sh\nprintf "%%s\\n" "$SDK_FIXTURE"\n' > "$tmp/shipyard/fetch_sdk.sh"
export SHIPYARD_SCRIPTS="$tmp/shipyard" MAVERICKS_TOOLCHAIN_CACHE="$tmp/cache"
export CALL_LOG="$tmp/call" SDK_FIXTURE="$tmp/sdk"
version="$(sed -n 's/^VERSION=//p' "$root/components/toolchain/version")"
line="${version%%.*}"
for mode in native cross; do
  short="clang$line"; [ "$mode" = native ] || short="$short-cross"
  dest="$(MODE="$mode" sh "$root/build/fetch-toolchain.sh")"
  [ "$dest" = "$tmp/cache/$version/$mode" ]
  [ -x "$dest/bin/clang" ]
  [ "$(readlink "$dest/SDKs/MacOSX10.9.sdk")" = "$tmp/sdk" ]
  printf '%s\n' --asset "mavericks-clang-$line-$mode-$version.pkg" "$short" "$version" "$dest" > "$tmp/want"
  cmp "$tmp/want" "$tmp/call"
  [ "$(MODE="$mode" sh "$root/build/fetch-toolchain.sh")" = "$dest" ]
done
if FAIL_FETCH=1 MODE=cross sh "$root/build/fetch-toolchain.sh" >/dev/null 2>&1; then
  echo 'FAIL: ignored shared fetch failure'; exit 1
fi
[ "$(MAVERICKS_TOOLCHAIN_PREFIX=/explicit sh "$root/build/fetch-toolchain.sh")" = /explicit ]
echo 'PASS: fetch-toolchain'
