#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
fail() { echo "FAIL: $*"; exit 1; }
x="$(mktemp -d "${TMPDIR:-/tmp}/npm-wrapper-test.XXXXXX")"; trap 'rm -rf "$x"' EXIT
p="$x/prefix"; mkdir -p "$p/bin" "$p/lib/node_modules/npm/bin" "$x/stubs"
printf '#!/bin/sh\necho "node pid=$$ path1=${PATH%%%%:*} $*" >> "%s/log"\nexit "${STUB_RC:-0}"\n' "$x" > "$p/bin/node"; chmod +x "$p/bin/node"
cat > "$x/helper" <<HELPER
#!/bin/sh
echo "helper \$*" >> "$x/log"
if [ "\$1" = link ] && [ -n "\${STUB_REFUSE:-}" ]; then echo "mavergreen: refusing to link \$2: bin/clang-format is owned by clang22" >&2; exit 1; fi
HELPER
chmod +x "$x/helper"
printf '#!/bin/sh\necho "$STUB_UID"\n' > "$x/stubs/id"; chmod +x "$x/stubs/id"
render() {  # $1 = command name, $2 = cli path
  MAVERGREEN_HELPER="$x/helper" sh "$root/build/npm-wrapper.sh" "$p" node99 "$2" > "$p/bin/$1" \
    || fail "npm-wrapper.sh could not render $1"
  chmod +x "$p/bin/$1"
}
render npm npm/bin/npm-cli.js; render corepack corepack/dist/corepack.js
head -1 "$p/bin/npm" | grep -qx '#!/bin/sh' || fail "the wrapper is not a sh script"

run() {  # $1 = uid, $2 = node's exit status, $3 = command; rest = its args
  : > "$x/log"; set +e; STUB_UID="$1" STUB_RC="$2" PATH="$x/stubs:$PATH"; export STUB_UID STUB_RC PATH
  _c="$3"; shift 3; "$p/bin/$_c" "$@" 2>"$x/err" & _pid=$!; wait "$_pid"; rc=$?; set -e; }
helpers() { grep '^helper' "$x/log" | tr '\n' ';'; }

run 501 0 npm install left-pad
grep -q "^node pid=$_pid path1=$p/bin $p/lib/node_modules/npm/bin/npm-cli.js install left-pad\$" "$x/log" \
  || fail "npm must exec its own node on its own CLI, with its own bin first on PATH (scripts, npx tools and node-gyp find this node): $(cat "$x/log")"
[ -z "$(helpers)" ] || fail "a non-global npm command relinked the product"
run 501 7 npm view left-pad
[ "$rc" = 7 ] || fail "npm's exit status was not preserved (got $rc, want 7)"
for g in -g --global --global=true --location=global; do
  run 0 0 npm install "$g" left-pad
  [ "$(helpers)" = "helper link node99;helper unlink node99;helper link node99;" ] \
    || fail "root npm $g must link (a refusal changes nothing), then unlink+link to prune: $(helpers)"
done
run 0 0 npm install -- -g
[ -z "$(helpers)" ] || fail "an argument after -- is not a flag, but it relinked"
STUB_REFUSE=1; export STUB_REFUSE
run 0 0 npm install -g clang-format
unset STUB_REFUSE
[ "$(helpers)" = "helper link node99;" ] || fail "a refused link must not be followed by unlink (that drops node24 from PATH): $(helpers)"
grep -q 'owned by clang22' "$x/err" || fail "the helper's refusal must reach the user, not /dev/null"
[ "$rc" = 0 ] || fail "npm's own success must survive a refused relink (got $rc)"
for spec in npm npm@latest corepack corepack@0.34.0; do
  run 0 0 npm install -g "$spec"
  [ "$rc" != 0 ] || fail "npm install -g $spec must be refused: it would replace the pinned wrapper"
  grep -q '^node' "$x/log" && fail "npm install -g $spec reached npm"
done
run 0 0 npm ls -g npm
[ "$rc" = 0 ] && grep -q '^node' "$x/log" || fail "a read-only global command naming npm (npm ls -g npm) must not be refused"
run 0 0 corepack enable
grep -q "corepack.js enable --install-directory $p/bin\$" "$x/log" \
  || fail "corepack enable must put its shims in node99's own bin, not the link farm: $(cat "$x/log")"
[ "$(helpers)" = "helper link node99;helper unlink node99;helper link node99;" ] || fail "corepack enable did not relink: $(helpers)"
run 0 0 corepack enable --install-directory /elsewhere
grep -q "enable --install-directory /elsewhere\$" "$x/log" || fail "an explicit --install-directory was overridden"
echo "PASS: npm-wrapper"
