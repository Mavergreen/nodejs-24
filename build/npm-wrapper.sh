#!/bin/sh
#   usage: sh build/npm-wrapper.sh <prefix> <product> <cli path under lib/node_modules>
#          Prints a sh wrapper that runs <cli> with <prefix>/bin/node, with <prefix>/bin first on PATH so
#          what it launches (scripts, npx tools, node-gyp) finds the same node. It execs, except after a
#          global operation run as root, when it then relinks <product>: link first (a refusal changes
#          nothing and is shown), and only then unlink+link to prune removed commands. It refuses global
#          installs of npm or corepack, which would replace the wrapper; they update with the pkg. For
#          corepack enable/disable it defaults --install-directory to <prefix>/bin, not the link farm.
set -eu
prefix="${1:?usage: npm-wrapper.sh <prefix> <product> <cli>}"; product="${2:?product}"; cli="${3:?cli}"
helper="${MAVERGREEN_HELPER:-/usr/local/bin/mavergreen}"
cat <<WRAPPER
#!/bin/sh
PATH="$prefix/bin:\$PATH"; export PATH
global=no; ownpkg=no; instdir=no; sub=
for a in "\$@"; do
  case "\$a" in
    --) break ;;
    -g|--global|--global=true|--location=global) global=yes ;;
    --install-directory|--install-directory=*) instdir=yes ;;
    -*) ;;
    *) if [ -z "\$sub" ]; then sub="\$a"
       else case "\$a" in npm|npm@*|corepack|corepack@*) ownpkg=yes ;; esac; fi ;;
  esac
done
case "\$sub" in
  install|i|in|isnt|add|update|up|upgrade|uninstall|un|remove|rm|r|link|ln) ;;
  *) ownpkg=no ;;
esac
if [ "\$global" = yes ] && [ "\$ownpkg" = yes ]; then
  echo "$product: npm and corepack are updated with the $product pkg, not with npm -g" >&2
  exit 1
fi
relink=\$global
case "$cli:\${1:-}" in
  corepack/*:enable|corepack/*:disable)
    relink=yes
    [ "\$instdir" = yes ] || set -- "\$@" --install-directory "$prefix/bin" ;;
esac
if [ "\$relink" = yes ] && [ "\$(id -u)" = 0 ] && [ -x "$helper" ]; then
  "$prefix/bin/node" "$prefix/lib/node_modules/$cli" "\$@"
  rc=\$?
  if "$helper" link $product >/dev/null; then
    { "$helper" unlink $product && "$helper" link $product; } >/dev/null \\
      || echo "$product: could not prune removed commands; run: sudo mavergreen link $product" >&2
  else
    echo "$product: its new commands are not on PATH (see above)" >&2
  fi
  exit \$rc
fi
exec "$prefix/bin/node" "$prefix/lib/node_modules/$cli" "\$@"
WRAPPER
