#!/bin/sh
# platform: host-agnostic
# spec: Recaulk owns these symbols; compiling the local fallback must not duplicate its definitions.
set -eu
# platform: the stock 10.9 acceptance guest has compiler stubs, so it cannot run a compile test.
if [ "$(uname -s)" = Darwin ]; then
  xcode-select -p >/dev/null 2>&1 || { echo 'no compiler tools -- skipping'; exit 77; }
fi
command -v cc >/dev/null 2>&1 || { echo 'no C compiler -- skipping'; exit 77; }
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/node-polyfills.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cc -D__APPLE__ -DMAVERGREEN_USE_RECAULK -c "$root/compat/polyfills.c" -o "$tmp/polyfills.o"
cat > "$tmp/provider.c" <<'C'
void pthread_set_qos_class_self_np(void) {}
void recvmsg_x(void) {}
void sendmsg_x(void) {}
void SecTrustEvaluateWithError(void) {}
int main(void) { return 0; }
C
cc "$tmp/provider.c" "$tmp/polyfills.o" -o "$tmp/link-test"
"$tmp/link-test"
echo 'PASS: polyfill-provider (shared definitions link without duplicates)'
