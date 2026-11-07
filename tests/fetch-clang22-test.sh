#!/bin/sh
# platform: host-agnostic
# build/fetch-clang22.sh fetches through shipyard's fetch_clang22.sh (the cross pkg on a modern Mac, the
# native pkg on 10.9, the Linux archive on Linux), refuses a prefix lacking a tool or library the Node build
# uses, and leaves clang.cfg reaching the pinned 10.9 SDK: setup-sdk on Linux (only when the link is not
# already right), the SDK link in a fetched pkg's prefix on a Mac.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/node-clang22-test.XXXXXX")"; trap 'chmod -R u+w "$t"; rm -rf "$t"' EXIT INT TERM
mkdir -p "$t/sy" "$t/inst/bin" "$t/sdk/usr/include"
. "$ROOT/build/msc.sh"; cp -R "$SHIPYARD_SCRIPTS"/. "$t/sy/"
tools='clang clang++ ld64.lld ld.lld llvm-ar llvm-ranlib llvm-nm llvm-strip llvm-lipo llvm-install-name-tool llvm-otool llvm-strings'
printf '#!/bin/sh\necho "%s"\n' "$t/sdk" > "$t/sy/fetch_sdk.sh"
for f in fetch_product_pkg.sh fetch_product_tar.sh; do
cat > "$t/sy/$f" <<EOF2
#!/bin/sh
echo "$f \$*" >> "$t/calls"; d="\$(eval echo "\\\${\$#}")"; mkdir -p "\$d/bin" "\$d/lib"
for b in $tools; do [ "\$b" = "\${FAKE_MISSING:-}" ] || { printf '#!/bin/sh\n' > "\$d/bin/\$b"; chmod +x "\$d/bin/\$b"; }; done
for l in libc++.a librecaulk.a; do [ "\$l" = "\${FAKE_MISSING:-}" ] || : > "\$d/lib/\$l"; done
printf '#!/bin/sh\necho "setup-sdk \$*" >> "$t/calls"\nmkdir -p "\$(dirname "\$0")/../SDKs"\nln -sfn "\$1" "\$(dirname "\$0")/../SDKs/MacOSX10.9.sdk"\n' > "\$d/bin/setup-sdk"
chmod +x "\$d/bin/setup-sdk"
EOF2
done
run() { SHIPYARD_SCRIPTS="$t/sy" MAVERGREEN_CLANG22_CACHE="$t/cache" CLANG22_INSTALLED="$t/inst" sh "$ROOT/build/fetch-clang22.sh"; }
V="$(cat "$ROOT/components/clang22/version")"

p="$(CLANG22_HOST=mac run)" || fail "a modern Mac's fetch failed"
grep -qx -- "fetch_product_pkg.sh --asset mavericks-clang-22-cross-$V.pkg clang22-cross $V $p" "$t/calls" \
  || fail "a modern Mac must fetch clang22-cross $V (calls: $(cat "$t/calls"))"
[ "$(cd "$p/SDKs/MacOSX10.9.sdk" && pwd -P)" = "$(cd "$t/sdk" && pwd -P)" ] \
  || fail "a fetched pkg's clang.cfg must reach the pinned SDK through SDKs/MacOSX10.9.sdk"
: > "$t/calls"; p="$(CLANG22_HOST=mac109 run)" || fail "10.9's fetch failed"
grep -qx -- "fetch_product_pkg.sh --asset mavericks-clang-22-native-$V.pkg clang22 $V $p" "$t/calls" \
  || fail "10.9 must fetch the native clang22 $V (calls: $(cat "$t/calls"))"
: > "$t/calls"; p="$(CLANG22_HOST=linux run)" || fail "Linux's fetch failed"
grep -q "^fetch_product_tar.sh clang22 $V " "$t/calls" || fail "Linux must fetch the clang22 $V archive (calls: $(cat "$t/calls"))"
grep -qx "setup-sdk $t/sdk" "$t/calls" || fail "Linux must point clang.cfg at the pinned SDK with setup-sdk (calls: $(cat "$t/calls"))"
: > "$t/calls"; (CLANG22_HOST=linux run) >/dev/null || fail "a second Linux fetch failed"
if grep -q '^setup-sdk' "$t/calls"; then fail "setup-sdk must not rerun when clang.cfg already reaches the pinned SDK"; fi
for missing in llvm-install-name-tool ld.lld librecaulk.a; do
  rm -rf "$t/cache"
  if (FAKE_MISSING=$missing CLANG22_HOST=mac run) > "$t/out" 2>&1; then fail "a prefix lacking $missing must be refused"; fi
  grep -q "$missing" "$t/out" || fail "the refusal must name $missing (got: $(cat "$t/out"))"
done
rm -rf "$t/cache"; p="$(CLANG22_HOST=mac run)"
rm -rf "$p/SDKs"; chmod a-w "$p"
if (CLANG22_HOST=mac run) > "$t/out" 2>&1; then fail "a prefix that cannot reach the SDK and cannot be repaired must be refused"; fi
grep -q 'SDK' "$t/out" || fail "the refusal must name the SDK (got: $(cat "$t/out"))"
echo "PASS: fetch-clang22"
