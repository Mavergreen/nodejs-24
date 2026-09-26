#!/bin/sh
#   usage: sh build/package.sh identity   print the pkg identity as key=value (no build, no version)
#          sh build/package.sh pkg        package the built tree; prints the .pkg path last
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/paths.sh"
GROUP="node"
IDENTIFIER="dev.mavergreen.nodejs.${PRODUCT}"
TITLE="Node.js ${NODE_LINE} for Mavericks"
OUT="$NODE_WORK/dist"

identity() {
  printf 'product=%s\ngroup=%s\nline=%s\nprefix=%s\nidentifier=%s\ntitle=%s\n' \
    "$PRODUCT" "$GROUP" "$NODE_LINE" "$PREFIX" "$IDENTIFIER" "$TITLE"
}

pkg() {
  . "$SELF/msc.sh"
  FULL="$(sh "$SELF/full-version.sh" "${RELEASE_MODE:-auto}")"
  [ -x "$SRC/out/Release/node" ] || { echo "package.sh: nothing built at $SRC -- run build/build.sh all first" >&2; exit 1; }
  updater="${UPD_APP:-$NODE_WORK/updater/$PRODUCT-updater.app}"
  [ -d "$updater" ] || { echo "package.sh: no updater at $updater -- run build/updater.sh first" >&2; exit 1; }
  upd_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$updater/Contents/Info.plist")"
  [ "$upd_ver" = "$FULL" ] \
    || { echo "package.sh: $updater is version $upd_ver, not $FULL -- rerun build/updater.sh" >&2; exit 1; }
  PY="$(sed -n 's/^PYTHON=//p' "$SRC/config.mk")"
  [ -n "$PY" ] || { echo "package.sh: $SRC/config.mk names no PYTHON -- was this tree configured?" >&2; exit 1; }
  built_as=native
  grep -q -- '--cross-compiling' "$SRC/config.status" && built_as=cross

  stage="$NODE_WORK/stage"; scripts="$NODE_WORK/pkg-scripts"; res="$NODE_WORK/resources"
  rm -rf "$stage" "$scripts" "$res" "$OUT"; mkdir -p "$stage" "$scripts" "$res" "$OUT"
  # platform: Node's `make install` depends on `all`, which re-enters the build without the toolchain
  #           environment build/build.sh sets up; install.py is what that target runs afterwards.
  ( cd "$SRC" && "$PY" tools/install.py install --dest-dir "$stage" --prefix "$PREFIX" ) >&2
  [ -x "$stage$PREFIX/bin/node" ] || { echo "package.sh: staging produced no $PREFIX/bin/node" >&2; exit 1; }

  mkdir -p "$stage$PREFIX/libexec/mavergreen"
  cp "$SELF/startup-snapshot.sh" "$stage$PREFIX/libexec/mavergreen/build-startup-snapshot"
  chmod 755 "$stage$PREFIX/libexec/mavergreen/build-startup-snapshot"
  for w in npm:npm/bin/npm-cli.js npx:npm/bin/npx-cli.js corepack:corepack/dist/corepack.js; do
    [ -e "$stage$PREFIX/lib/node_modules/${w#*:}" ] \
      || { echo "package.sh: staged tree has no lib/node_modules/${w#*:} for bin/${w%%:*}" >&2; exit 1; }
    rm -f "$stage$PREFIX/bin/${w%%:*}"
    sh "$SELF/npm-wrapper.sh" "$PREFIX" "$PRODUCT" "${w#*:}" > "$stage$PREFIX/bin/${w%%:*}"
    chmod 755 "$stage$PREFIX/bin/${w%%:*}"
  done
  # spec: build/npm-wrapper.sh -- npm updates with the pkg, and the wrapper refuses npm -g install npm,
  #       so npm must not advise it.
  printf 'update-notifier=false\n' >> "$stage$PREFIX/lib/node_modules/npm/npmrc"
  prehook="$NODE_WORK/preinstall-hook.sh"; hook="$NODE_WORK/postinstall-hook.sh"
  sh "$SELF/hooks.sh" preinstall "$PREFIX" "$PRODUCT" > "$prehook"
  sh "$SELF/hooks.sh" postinstall "$PREFIX" "$PRODUCT" > "$hook"

  sh "$SHIPYARD/stage_product.sh" --stage "$stage" --product "$PRODUCT" --name "$TITLE" --version "$FULL" \
    --group "$GROUP" --line "$NODE_LINE" --scripts-out "$scripts" --preinstall-hook "$prehook" --postinstall-hook "$hook" \
    --updater-app "$updater" >&2
  comp="$(sh "$SHIPYARD/build_component_pkg.sh" --root "$stage" --identifier "$IDENTIFIER" \
            --version "$FULL" --install-location / --scripts "$scripts" --out "$NODE_WORK/component.pkg")"
  cp "$SRC/LICENSE" "$res/LICENSE.txt"
  pkg="$OUT/nodejs-$FULL.pkg"
  sh "$SHIPYARD/set_install_floor.sh" --identifier "$IDENTIFIER" --title "$TITLE" \
    --component "$comp" --out "$pkg" --resources "$res" --license LICENSE.txt --host-arch x86_64 --require-scripts >&2
  rm -f "$comp"
  [ -f "$pkg" ] || { echo "package.sh: set_install_floor.sh produced no $pkg" >&2; exit 1; }

  toolchain="$(sed -n 's/^VERSION=//p' "$MAVERICKS_ROOT/components/toolchain/version" | head -1)"
  sh "$SHIPYARD/build-info.sh" "$OUT/build-info-$built_as.txt" \
    variant="$built_as" arch=x86_64 prefix="$PREFIX" identifier="$IDENTIFIER" pkg="${pkg##*/}" \
    node_version="$NODE_VERSION" node_line="$NODE_LINE" toolchain="$toolchain" >&2
  echo "$pkg"
}

case "${1:?usage: package.sh <identity|pkg>}" in
  identity) identity ;;
  pkg)      pkg ;;
  *) echo "package.sh: unknown subcommand '$1'" >&2; exit 2 ;;
esac
