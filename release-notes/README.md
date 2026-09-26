# Release notes

Each release's notes are written by shipyard's `release-notes.sh` (called from `release.yml`): a title, what
changed (with a link to Node's own notes for a new upstream), any patches or build ingredients that
moved, and the install floor. That one file becomes both the Sparkle appcast `<description>` and the
GitHub Release body.

Optional hand-written prose for a release goes in `release-notes/<full-version>.md` (for example
`24.6.0-mavericks.1.md`). It is inserted verbatim after the generated title, so it must NOT carry a
title of its own.
