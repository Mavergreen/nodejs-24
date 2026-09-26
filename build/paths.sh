#   usage: . build/paths.sh    (with MAVERICKS_ROOT set) sets NODE_LINE NODE_VERSION PRODUCT PREFIX NODE_WORK SRC
#          sh build/paths.sh   prints them as key=value
case "$0" in *paths.sh) set -eu ;; esac
: "${MAVERICKS_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
NODE_LINE="$(sh "$MAVERICKS_ROOT/build/version.sh" line)"
NODE_VERSION="$(tr -d '[:space:]' < "$MAVERICKS_ROOT/UPSTREAM_VERSION")"
PRODUCT="node${NODE_LINE}"
PREFIX="/usr/local/mavergreen/${PRODUCT}"
# platform: a family checkout may live on NFS, where a build spends most of its wall time in I/O wait.
: "${MAVERICKS_BUILD_ROOT:=${TMPDIR:-/tmp}/mm-build}"
NODE_WORK="${NODE_WORK:-$MAVERICKS_BUILD_ROOT/nodejs}"
SRC="$NODE_WORK/node-v${NODE_VERSION}"
export MAVERICKS_ROOT MAVERICKS_BUILD_ROOT NODE_LINE NODE_VERSION PRODUCT PREFIX NODE_WORK SRC
case "$0" in
  *paths.sh) printf 'NODE_LINE=%s\nNODE_VERSION=%s\nPREFIX=%s\nNODE_WORK=%s\nSRC=%s\n' \
               "$NODE_LINE" "$NODE_VERSION" "$PREFIX" "$NODE_WORK" "$SRC" ;;
esac
