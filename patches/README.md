# Line 24 patches

Applied by `build/build.sh` with `patch -p1` (Apple patch 2.0-safe; no --merge) after fetch+verify.
- 0001-availability-macros.patch: include <AvailabilityMacros.h> in V8/libuv sources that need it on 10.9.
- 0002-v8-disable-signpost.patch: drop <os/signpost.h> (absent on 10.9) and disable V8 system instrumentation.
- 0003-default-startup-snapshot.patch: with no embedded startup snapshot (we build --without-node-snapshot),
  load `<prefix>/lib/node/startup.blob` -- generated on the target at install time -- and start without it
  on any problem instead of failing.
- 0004-python-314.patch: backport Node's Python 3.14 configure support when the pinned upstream source
  lacks it, by preferring `python3.14` and accepting `(3, 14)`.

Deterministic source edits awkward as context patches (common.gypi deployment target, V8 safepoint
pthread_override removal) live as a `fixups` step in build/build.sh, not here.
