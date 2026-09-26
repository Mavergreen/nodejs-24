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

## Conformance deviations

None.
