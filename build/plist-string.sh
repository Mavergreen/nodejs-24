#!/bin/sh
# platform: host-agnostic
#   usage: sh build/plist-string.sh KEY PLIST
#          Prints the <string> value of top-level KEY in an XML property list; exit 1 when KEY has none.
set -eu
k="${1:?usage: plist-string.sh KEY PLIST}"; f="${2:?usage: plist-string.sh KEY PLIST}"
awk -v k="<key>$k</key>" '
  index($0, k) { want = 1; sub(".*" k, "") }
  want && /<string>/ { sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print; found = 1; exit }
  want && /<(true|false|integer|array|dict)/ { exit }
  END { exit !found }' "$f"
