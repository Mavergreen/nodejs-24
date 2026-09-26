#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
fail() { echo "FAIL: $*"; exit 1; }
x="$(mktemp -d "${TMPDIR:-/tmp}/npm-globals-hooks-test.XXXXXX")"; trap 'rm -rf "$x"' EXIT
R="$x/Install Volume"; P=/usr/local/mavergreen/node99; T="$R$P"
mkdir -p "$R/usr/local/bin"
printf '#!/bin/sh\necho "helper $*" >> "%s/log"\n' "$x" > "$R/usr/local/bin/mavergreen"; chmod +x "$R/usr/local/bin/mavergreen"

fresh_tree() {  # $1 = version marker for the bundled npm/corepack
  mkdir -p "$T/bin" "$T/lib/node_modules/npm" "$T/lib/node_modules/corepack"
  echo "$1" > "$T/lib/node_modules/npm/VERSION"; echo "$1" > "$T/lib/node_modules/corepack/VERSION"
  : > "$T/bin/node"; : > "$T/bin/npm"
}
fresh_tree old
mkdir -p "$T/lib/node_modules/left-pad" "$T/lib/node_modules/@scope/pkg"
: > "$T/lib/node_modules/left-pad/cli.js"; : > "$T/lib/node_modules/@scope/pkg/bin.js"
ln -s ../lib/node_modules/left-pad/cli.js "$T/bin/left-pad"
ln -s ../lib/node_modules/@scope/pkg/bin.js "$T/bin/scopecmd"
mkdir -p "$x/dev/linked-pkg"; : > "$x/dev/linked-pkg/cli.js"
ln -s "../../../../../../../dev/linked-pkg" "$T/lib/node_modules/linked-pkg"
[ -f "$T/lib/node_modules/linked-pkg/cli.js" ] || fail "test setup: the npm-link symlink does not resolve"
ln -s ../lib/node_modules/corepack/dist/yarn.js "$T/bin/yarn"

sh "$root/build/hooks.sh" preinstall "$P" node99 > "$x/pre.sh" || fail "could not render the preinstall hook"
sh "$root/build/hooks.sh" postinstall "$P" node99 > "$x/post.sh" || fail "could not render the postinstall hook"
sh -n "$x/pre.sh" && sh -n "$x/post.sh" || fail "a rendered hook does not parse"
grep -Eq '(^|[^_])exit|set -e' "$x/pre.sh" "$x/post.sh" && fail "a hook may contain no exit and no set -e (stage_product's rule)"

: > "$x/log"
ROOT="$R" sh "$x/pre.sh" || fail "the preinstall hook failed -- that would stop the upgrade"
rm -rf "$T"; fresh_tree new
ROOT="$R" sh "$x/post.sh" || fail "the postinstall hook failed"

[ -f "$T/lib/node_modules/left-pad/cli.js" ] || fail "global left-pad did not survive the upgrade"
[ -f "$T/lib/node_modules/@scope/pkg/bin.js" ] || fail "scoped global @scope/pkg did not survive the upgrade"
[ -e "$T/bin/left-pad" ] && [ -e "$T/bin/scopecmd" ] || fail "global commands' bin links did not survive (or dangle)"
[ -L "$T/lib/node_modules/linked-pkg" ] && [ -f "$T/lib/node_modules/linked-pkg/cli.js" ] \
  || fail "an npm-linked global (a relative symlink that dangles while stashed) did not survive"
[ -L "$T/bin/yarn" ] || fail "corepack's yarn shim link did not survive the upgrade"
[ "$(cat "$T/lib/node_modules/npm/VERSION")" = new ] || fail "the upgrade's own npm was replaced by the stashed old one"
[ "$(cat "$T/lib/node_modules/corepack/VERSION")" = new ] || fail "the upgrade's own corepack was replaced"
[ ! -e "$R/usr/local/mavergreen/var/node99/npm-globals" ] || fail "the stash was left behind after a clean restore"
grep -qx "helper --root $R link node99" "$x/log" || fail "postinstall did not relink node99, so restored commands miss PATH: $(cat "$x/log")"

rm -rf "$T"; fresh_tree again
mkdir -p "$T/lib/node_modules/left-pad"; : > "$T/lib/node_modules/left-pad/cli.js"
rm -rf "$R/usr/local/mavergreen/var"; mkdir -p "$R/usr/local/mavergreen"; : > "$R/usr/local/mavergreen/var"
if ROOT="$R" sh "$x/pre.sh" 2>/dev/null; then
  fail "the preinstall hook succeeded although it could not stash the globals -- the upgrade would delete them"
fi
[ -f "$T/lib/node_modules/left-pad/cli.js" ] || fail "a failed stash must leave the globals in place"
rm -f "$R/usr/local/mavergreen/var"

rm -rf "$T"; fresh_tree first; : > "$x/log"
ROOT="$R" sh "$x/pre.sh" && ROOT="$R" sh "$x/post.sh" || fail "hooks failed on a first install with no globals"
echo "PASS: npm-globals-hooks"
