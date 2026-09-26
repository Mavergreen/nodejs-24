#!/bin/sh
# native≡cross equivalence: the same Node line, built native-on-10.9 and cross-from-modern, must be the
# SAME product. The binaries differ byte-for-byte (embedded build paths etc.), so we fingerprint
# SEMANTICS: version + process.versions (V8/uv/openssl/icu/...), the 10.9 floor, the linked dylibs, and
# a deterministic behavioral hash exercising OpenSSL (crypto), ICU (Intl/normalize/locale) and V8 (JS +
# number formatting). The two builds MUST yield an identical fingerprint.
#
# Usage: [MODE=native|cross] equivalence-fingerprint.sh [node-binary]
# Compares the current build's fingerprint to the committed native reference
# (equivalence-fingerprint.txt); with no reference yet, it just prints one to commit.
# SKIPs (77) when the binary is absent, or when this host cannot execute x86_64 (tests/lib/x86_64.sh).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
paths="$(sh "$root/build/paths.sh")"
BIN="${1:-$(printf '%s\n' "$paths" | sed -n 's/^SRC=//p')/out/Release/node}"
[ -x "$BIN" ] || { echo "not built ($BIN) — skipping"; exit 77; }
. "$here/lib/x86_64.sh"
x86_64_or_skip
MODE="${MODE:-$(uname -m | grep -q arm64 && echo cross || echo native)}"
run() { x86_64_run "$BIN" "$@"; }

js='const c=require("crypto");const a=[];
a.push(process.version,process.arch,process.platform);
a.push(Object.entries(process.versions).sort().map(([k,v])=>k+"="+v).join(","));
a.push(c.createHash("sha256").update("mavericks").digest("hex"));
a.push(c.createHmac("sha256","key").update("node").digest("hex"));
a.push(c.publicEncrypt===undefined?"nopke":"pke");
a.push(new Intl.NumberFormat("de-DE").format(1234567.89));
a.push(new Intl.DateTimeFormat("ja-JP",{dateStyle:"full",timeStyle:"long",timeZone:"UTC"}).format(new Date(0)));
a.push("straße".toLocaleUpperCase("de-DE"));
a.push("Å".normalize("NFC")==="Å"?"nfc-ok":"nfc-bad");
a.push(JSON.stringify([..."café☕→𝕏"].map(x=>x.codePointAt(0))));
a.push(String(0.1+0.2),Math.PI.toFixed(15),(2n**100n).toString());
a.push(Buffer.from("héllo","utf8").toString("base64"));
process.stdout.write(c.createHash("sha256").update(a.join("|")).digest("hex"));'

tmp="$(mktemp -t maveq)"; trap 'rm -f "$tmp"' EXIT
{
  echo "version: $(run --version)"
  echo "versions: $(run -p 'Object.entries(process.versions).sort().map(([k,v])=>k+"="+v).join(",")')"
  echo "arch-platform: $(run -p 'process.arch+" "+process.platform')"
  echo "floor: $(otool -l "$BIN" | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&/version /{print $2; exit}')"
  echo "dylibs: $(otool -L "$BIN" | awk 'NR>1{print $1}' | LC_ALL=C sort | tr '\n' ',')"
  echo "behavior-sha256: $(run -e "$js")"
} > "$tmp"

ref="$root/equivalence-fingerprint.txt"
if [ -f "$ref" ]; then
  if diff -u "$ref" "$tmp"; then
    echo "PASS: equivalence ($MODE fingerprint matches the committed native reference)"
  else
    echo "FAIL: native≢cross — the $MODE build differs from the committed native reference above"; exit 1
  fi
else
  cat "$tmp"
  echo "# no committed reference yet — commit the above as equivalence-fingerprint.txt"
fi
