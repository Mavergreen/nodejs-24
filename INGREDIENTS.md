# Ingredients

Everything baked into a `Node.js for Mavericks` release, where it is pinned, and how it auto-updates.
A Node *major* is a product; this repo ships exactly ONE major, derived from the root
`UPSTREAM_VERSION` (see `build/version.sh`). A new Node major is a new repo, not a new file here.

| Ingredient | Pinned in | Renovate | A bump does |
|---|---|---|---|
| Node.js (line 24) | `UPSTREAM_VERSION` | ✅ capped `github-tags` on `nodejs/node` (`<25`) | fetch+verify+build a new `24.x`, cut `24.x-mavericks.1` |
| Toolchain | `components/toolchain/version` (`VERSION`) | ✅ `github-releases` on `Mavergreen/clang`, SHA256SUMS-verified | fetch+verify this host's variant of the pinned `.pkg`, rebuild with it, and re-cut as `-mavericks.N+1` (via `repackage-on-ingredient-bump`) |
| shipyard | `.github/workflows/*.yml` `uses: …@v1` | ✅ built-in github-actions manager | pulls new shared scripts/gate; does not change the node binary |
| GitHub Actions | `.github/workflows/*.yml` `uses:` | ✅ built-in github-actions manager | CI-only; does not change the node binary |

Node's bundled dependencies (V8, libuv, ICU, npm, nghttp2, …) ride inside the Node tarball and are
**not** independent pins — they move only when the root `UPSTREAM_VERSION` moves.

## Build and packaging

`sh build/build.sh all` builds an `x86_64-apple-macos10.9` `node` natively on a real 10.9 box and as a
cross build on an Apple-Silicon host. The toolchain is mavericks-clang, and `build/fetch-toolchain.sh`
picks its variant from the build MODE. A cross build additionally needs Node's `--dest-cpu=x64
--dest-os=mac --cross-compiling`. gyp then builds the tools that run during the build (torque,
mksnapshot, node_js2c, the ICU generators) in a separate host toolset, as native arm64 with Apple's
clang (`CC_host`/`CXX_host` from `build.sh host-env`) against the build machine's SDK. **No step of
either build runs under Rosetta.** On an arm64 Mac without Rosetta, the cross build completes, its V8
`snapshot.cc` and `embedded.S` are byte-identical to the native 10.9 build's, and its `node` matches the
committed native equivalence fingerprint on 10.9. The tests that execute the x86_64 `node` (smoke,
equivalence-fingerprint, startup-snapshot) run it natively on an x86_64 host such as the real 10.9 box,
under Rosetta where an Apple-Silicon host has it (declared below), and SKIP elsewhere.
`tests/rosetta-free-test.sh` fails if the build ever uses Rosetta, or a test uses it undeclared.

Both builds configure `--without-node-snapshot`. Node's startup snapshot is made by running Node's
bootstrap as target-arch code, and V8 has no x64 simulator, so an arm64 host could only make it under
Rosetta. Node's configure already drops it when cross-compiling, so the native build drops it too, or
the two builds would differ. The snapshot is generated on the target instead. The pkg ships
`libexec/mavergreen/build-startup-snapshot`, and its postinstall runs it: best-effort, and only when
installing to the boot volume. It writes `lib/node/startup.blob` with `node --build-snapshot`, and
checks the blob starts node before putting it in place. `patches/0003-default-startup-snapshot.patch`
makes node load that blob wherever the embedded snapshot would have loaded, and start without it if the
blob is missing or rejected. On 10.9 hardware, `node -e 0` takes about 43 ms with the blob and about 86 ms
without. A Mac that cannot run the x86_64 node (Apple Silicon without Rosetta) simply has no blob.

## Conformance deviations

- rosetta:tests/lib/x86_64.sh: runs the shipped x86_64 node under `arch -x86_64` when Rosetta is installed, and SKIPs otherwise, so smoke, equivalence-fingerprint and startup-snapshot also exercise the 10.9-targeted binary on Apple-Silicon hosts and CI. Best-effort test coverage, never a build dependency: the build itself uses no Rosetta. Reconsider when these tests run on a Mavericks VM runner in CI (what vm-guest is building toward), and at the latest before macOS 28 removes Rosetta; until then, a native x86_64 host (the real 10.9 box) runs them without it.

