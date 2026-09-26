# Line 24 patches

Applied by `build/build.sh` with `patch -p1` (Apple patch 2.0-safe; no --merge) after fetch+verify.
- 0001-availability-macros.patch: include <AvailabilityMacros.h> in V8/libuv sources that need it on 10.9.
- 0002-v8-disable-signpost.patch: drop <os/signpost.h> (absent on 10.9) and disable V8 system instrumentation.

Deterministic source edits awkward as context patches (common.gypi deployment target, V8 safepoint
pthread_override removal) live as a `fixups` step in build/build.sh, not here.
