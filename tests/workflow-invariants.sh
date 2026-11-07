#!/bin/sh
# platform: host-agnostic
#   usage: workflow-invariants.sh [RELEASE_YML [VM_RUN_SH]]
#          release.yml builds, tests and packages on Linux with no macOS job, and publishes only after the
#          10.9 guest installed this run's pkg and executed it: on-mavericks runs tests/vm/run.sh, which
#          installs the pkg, checks its version, and runs smoke and startup-snapshot against the installed node.
set -eu
cd "$(dirname "$0")/.."
w="${1:-.github/workflows/release.yml}"; vm="${2:-tests/vm/run.sh}"
fail() { echo "FAIL: $*"; exit 1; }
job() { sed -n "/^  $1:\$/,/^  [a-z-]*:\$/p" "$w" | sed '$d' | grep -v '^ *#'; }
lineof() { grep -n "$1" "$w" | grep -v '^[0-9]*: *#' | head -1 | cut -d: -f1; }
! grep -Eq '^[[:space:]]*tags:' "$w" || fail "a tag must not trigger a release"
grep -q "^    branches-ignore: \['renovate/\*\*'\]$" "$w" || fail "a push to any branch but Renovate's must build"
! grep -Eq '^ +runs-on: .*macos' "$w" || fail "no job runs on a macOS runner"
job build | grep -q '^    runs-on: ubuntu-latest$' || fail "the build job runs on Linux"
for f in "$w" .github/workflows/*.yml; do
  ! grep -n -i -E 'rosetta|arch[[:space:]]+-x86_64' "$f" || fail "$f relies on Rosetta"
done
b="$(lineof 'run: sh build/build.sh all$')"; u="$(lineof 'run: sh build/updater.sh$')"
p="$(lineof 'out="$(sh build/package.sh pkg)"')"; t="$(lineof 'run-repo-tests.sh" --strict-host$')"
[ -n "$b" ] && [ -n "$u" ] && [ -n "$p" ] && [ -n "$t" ] && [ "$b" -lt "$u" ] && [ "$u" -lt "$p" ] && [ "$p" -lt "$t" ] \
  || fail "the build job builds node, then the updater, then packages, then runs every host-agnostic test with --strict-host"
om="$(job on-mavericks)"
[ -n "$om" ] || fail "no on-mavericks job"
for want in 'needs: \[build\]' 'uses: Mavergreen/mavericks-vm@v1' 'image-key: \$\{\{ secrets.MAVERICKS_VM_KEY \}\}' \
    'FULL: \$\{\{ needs.build.outputs.version \}\}' 'envs: FULL' 'run: sh tests/vm/run.sh'; do
  printf '%s\n' "$om" | grep -Eq "^ *(- )?$want\$" || fail "the on-mavericks job lacks a line $want"
done
[ "$(printf '%s\n' "$om" | grep -c '^    if:')" -eq 1 ] \
  && printf '%s\n' "$om" | grep -qxF "    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository" \
  || fail "on-mavericks may be skipped only for a fork's pull request"
! printf '%s\n' "$om" | grep -q 'continue-on-error' || fail "on-mavericks must not continue on error: publish needs it to pass"
for want in 'sudo installer -pkg "\$pkg" -target /' \
    '\[ "\$\(/usr/libexec/PlistBuddy -c .Print :version. "\$manifest"\)" = "\$FULL" \]' \
    'sh tests/smoke-test.sh' 'sh tests/startup-snapshot-test.sh' \
    'ln -s "\$PREFIX/bin/node" "\$bundle/out/Release/node"'; do
  case "$want" in ln*) f=build/prepare-vm-tests.sh ;; *) f="$vm" ;; esac
  grep -Eq "^ *$want\$" "$f" || fail "$f lacks a line $want"
done
sed -n '/^  publish:$/,/^  [a-z-]*:$/p' "$w" | grep -Eq 'needs: \[.*on-mavericks.*\]' || fail "publish must wait for on-mavericks"
req="$(job required | sed -n 's/^    needs: \[\(.*\)\]$/\1/p' | tr -d ' ' | tr ',' '\n' | LC_ALL=C sort)"
others="$(sed -n '/^jobs:$/,$p' "$w" | grep -E '^  [a-z-]+:$' | sed 's/^  //; s/:$//' | grep -vx required | LC_ALL=C sort)"
[ -n "$req" ] && [ "$req" = "$others" ] || fail "required (release) must need every other job: needs [$(printf '%s ' $req)], jobs [$(printf '%s ' $others)]"
! grep -q 'secrets: inherit' "$w" || fail "no job inherits every secret"
stray="$(awk '/^  [a-z-]+:$/ { j = $1 } /^      - / { st = $0 } /SPARKLE_PRIVATE_KEY/ && j != "scan:" && !(j == "build:" && st ~ /- name: Sign the pkg and write its feed/) { print NR ": " $0 }' "$w")"
[ -z "$stray" ] || fail "SPARKLE_PRIVATE_KEY may appear only in the build job's signing step and the scan job: $stray"
echo "PASS: workflow-invariants"
