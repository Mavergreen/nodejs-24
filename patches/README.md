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

- 0005-python-315.patch: extend configure selection and acceptance to Python 3.15.
  The release build and native-fixture generation exercise this interpreter; applying it is a no-op
  once upstream already selects and accepts 3.15.
- 0006-v8-std-hash.patch: backport V8's fix for inconsistent integral hashes with libc++ 22.
- 0007-runtime-test-assumptions.patch: retain upstream behavioral assertions while accounting for
  install-time builtin code cache, configured loopback addresses, and measured whole-second
  filesystem timestamps. These are test adaptations, not exclusions; all three tests still run.
  The sandbox test also reports codesign stderr when signing fails, so VM failures are diagnosable.
- 0008-buffer-lifetime-positional-writes.patch: preserve concurrent buffer-lifetime stress with
  disjoint explicit offsets instead of the documented-unsafe implicit-offset race. Check every
  write's result and the full expected byte count, rather than accepting overlaps and >1000 bytes.
- 0010-host-prepared-sandbox-fixture.patch: use a host-signed sandbox app when supplied by the
  test bundle, since stock Mavericks lacks codesign_allocate. Match the installed Node's SHA-256,
  verify the signature, require a successful launch, and retain the upstream home-directory denial
  assertion. Without a prepared fixture, the original local-signing path remains available.
- 0011-libuv-sandbox-async-descriptor.patch: lets libuv's EVFILT_USER placeholder
  use `/dev/null` when App Sandbox denies reading `/`. Keeps the upstream
  chroot-without-`/dev/null` behavior from libuv#4689. This changes libuv's choice
  of an unused descriptor, not system API semantics or sandbox permissions.
