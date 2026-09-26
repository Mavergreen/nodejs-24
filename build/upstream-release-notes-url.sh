#!/bin/sh
# Print the URL of the release notes for one upstream Node.js version. shipyard's
# upstream-notes.sh links it from our release notes when a release ships a NEW upstream.
#   usage: upstream-release-notes-url.sh <upstream-version>      (bare: 24.6.0)
set -eu
printf 'https://nodejs.org/en/blog/release/v%s\n' "${1:?usage: upstream-release-notes-url.sh <upstream-version>}"
