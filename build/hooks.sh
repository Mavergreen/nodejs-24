#!/bin/sh
#   usage: sh build/hooks.sh <preinstall|postinstall> <prefix> <product>
#          Prints this product's hook body for stage_product.sh --preinstall-hook/--postinstall-hook.
#          preinstall stashes the user's npm global packages (every lib/node_modules entry but npm and
#          corepack, and the bin/ links into them) under var/<product>, which survives the upgrade's
#          removal of the tree; postinstall puts them back, relinks the product, and (boot volume only)
#          generates the startup snapshot. Hooks see Installer's target volume as $ROOT.
set -eu
kind="${1:?usage: hooks.sh <preinstall|postinstall> <prefix> <product>}"; prefix="${2:?prefix}"; product="${3:?product}"
cat <<HEAD
_tree="\$ROOT$prefix"
_stash="\$ROOT/usr/local/mavergreen/var/$product/npm-globals"
HEAD
case "$kind" in
  preinstall) cat <<'PRE'
_rc=0
if [ -d "$_tree/lib/node_modules" ]; then
  mkdir -p "$_stash/lib/node_modules" "$_stash/bin" || _rc=1
  if [ "$_rc" -eq 0 ]; then
    for _m in "$_tree"/lib/node_modules/*; do
      [ -e "$_m" ] || [ -L "$_m" ] || continue
      case "${_m##*/}" in npm|corepack) continue ;; esac
      [ -e "$_stash/lib/node_modules/${_m##*/}" ] || [ -L "$_stash/lib/node_modules/${_m##*/}" ] \
        || mv "$_m" "$_stash/lib/node_modules/" || _rc=1
    done
    for _b in "$_tree"/bin/*; do
      [ -L "$_b" ] || continue
      case "${_b##*/}" in npm|npx|corepack) continue ;; esac
      case "$(readlink "$_b")" in
        ../lib/node_modules/*) [ -e "$_stash/bin/${_b##*/}" ] || [ -L "$_stash/bin/${_b##*/}" ] || mv "$_b" "$_stash/bin/" || _rc=1 ;;
      esac
    done
  fi
  [ "$_rc" -eq 0 ] || echo "npm globals could not be saved under $_stash; stopping so the upgrade cannot delete them" >&2
fi
[ "$_rc" -eq 0 ]
PRE
  ;;
  postinstall) cat <<'POST'
if [ -d "$_stash" ]; then
  for _m in "$_stash"/lib/node_modules/*; do
    [ -e "$_m" ] || [ -L "$_m" ] || continue
    [ -e "$_tree/lib/node_modules/${_m##*/}" ] || [ -L "$_tree/lib/node_modules/${_m##*/}" ] || mv "$_m" "$_tree/lib/node_modules/"
  done
  for _b in "$_stash"/bin/*; do
    [ -L "$_b" ] || continue
    [ -e "$_tree/bin/${_b##*/}" ] || [ -L "$_tree/bin/${_b##*/}" ] || mv "$_b" "$_tree/bin/"
  done
  rmdir "$_stash/lib/node_modules" "$_stash/lib" "$_stash/bin" "$_stash" 2>/dev/null || true
POST
  printf '  if [ -n "$ROOT" ]; then "$ROOT/usr/local/bin/mavergreen" --root "$ROOT" link %s; else /usr/local/bin/mavergreen link %s; fi >/dev/null \\\n    || echo "%s: restored npm globals are not all on PATH (see above)" >&2\nfi\n' "$product" "$product" "$product"
  printf 'if [ -z "$ROOT" ]; then\n  %s/libexec/mavergreen/build-startup-snapshot || true\nfi\n' "$prefix"
  ;;
  *) echo "hooks.sh: unknown hook '$kind'" >&2; exit 2 ;;
esac
