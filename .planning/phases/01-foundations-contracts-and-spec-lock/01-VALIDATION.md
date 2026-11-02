---
phase: 1
slug: foundations-contracts-and-spec-lock
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-11-02
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `01-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | In-repo harness on Lune 0.11.1 (`tests/run.luau`, `tests/harness/`). No Jest — the fuzz suite must run headless in CI, which in-Studio Jest cannot do (research contradiction #1) |
| **Config file** | none — `.luaurc` + `rokit.toml` pin the environment. Wave 0 creates `tests/run.luau` |
| **Quick run command** | `lune run tests/run.luau -- --filter <substring>` |
| **Full suite command** | `lune run scripts/verify.luau` (runs every CI step in order, then prints the manual-check list) |
| **Estimated runtime** | quick: target < 5s · full: unmeasured (nothing has been executed yet) |
| **CI** | `.github/workflows/ci.yml` — same steps, on every push and PR (D-02) |

**Greenfield:** no test infrastructure exists. Wave 0 creates all of it.

---

## Sampling Rate

- **After every task commit:** pre-commit hook (stylua + selene on staged files, per D-03) plus
  `lune run tests/run.luau -- --filter <area>`
- **After every plan wave:** `lune run scripts/verify.luau` (full CI mirror, locally)
- **Before `/gsd-verify-work`:** CI green on the branch head, `scripts/verify.luau` output attached,
  and every MANUAL-CHECKS item M-01..M-06 signed off
- **Max feedback latency:** < 5s for the filtered quick run

---

## Per-Requirement Verification Map

| Req ID | Behavior | Test Type | Automated Command | File Exists | Status |
|--------|----------|-----------|-------------------|-------------|--------|
| FOUND-01 | `Workspace` node has `$ignoreUnknownInstances == true`; project assembles; map mounts under `ServerStorage.Maps`; `.rbxm` has one root | unit + build | `lune run tests/run.luau -- --filter project` ; `rojo build default.project.json -o build/spoons.rbxl` | ❌ W0 | ⬜ pending |
| FOUND-02 | `rokit.toml` pins exact versions; every `.luau` starts `--!strict`; strict typecheck passes; an ill-typed fixture fails | unit + CI | `--filter project` ; `lune run scripts/ci/check-guards.luau` ; both `luau-lsp analyze` commands | ❌ W0 | ⬜ pending |
| FOUND-03 | Specs and fuzz run under Lune; a failing spec makes the runner exit non-zero | unit + meta | `lune run tests/run.luau` ; `--filter harness` | ❌ W0 | ⬜ pending |
| FOUND-03 | Same source resolves under both Lune and Roblox `require` rules | spike + CI | `tests/spike/require.spec.luau` ; `lune run scripts/ci/check-built-place.luau build/spoons.rbxl` | ❌ W0 | ⬜ pending |
| FOUND-04 | Malformed / NaN / inf / wrong-phase / over-rate / unknown-intent all rejected and never dispatched; per-player buckets refill over time; only `NetServer` uses `OnServerEvent` | unit + guard | `--filter gateway` ; guard rule R4 + fixture | ❌ W0 | ⬜ pending |
| FOUND-05 | Direct, transitive **and non-literal** imports of cosmetics/shop from guarded modules fail; clean tree passes | fixture via real CLI | `--filter guards` | ❌ W0 | ⬜ pending |
| FOUND-06 | Roblox value reference, **type-only** reference, and suppressed reference inside the engine all fail; clean engine passes | fixture via real CLI | `--filter guards` (invokes `selene --config selene.pure.toml`, standard-platform `luau-lsp`, `check-guards`) | ❌ W0 | ⬜ pending |
| FOUND-07 | Environment config present; Mock selection when `DataStoreState ~= "Access"`; `servePlaceIds` recorded after the gate | unit + **human gate** | `--filter persistence` ; MANUAL-CHECKS M-04 | ❌ W0 | ⬜ pending |
| FOUND-08 | `Admission` boundary table (0, 2, 3, 9, 10, 11, bad inputs); `canStartMatch` | unit | `--filter admission` | ❌ W0 | ⬜ pending |
| MAP-01 | Valid snapshot passes; each missing/wrong element yields its stable issue code; gray-box `.rbxm` validates; no script instances; 16 tagged spots; 9 seat anchors | unit + integration | `--filter maps` ; `lune run scripts/maps/validate-map.luau maps/gray-box.rbxm` | ❌ W0 | ⬜ pending |
| SCORE-06 | Exactly one round end; stale callback inert (with **and without** a working `task.cancel`); boundary in both arrival orders; `endRound` idempotent | unit | `--filter round` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/dev/bootstrap-tools.sh` — direct-download pinned tools (**`api.github.com` returns 403 in this container, so `rokit install` cannot work here**) + permission to execute them
- [ ] `rokit.toml`, `stylua.toml`, `selene.toml`, `selene.pure.toml`, `.luaurc`, `.styluaignore`, `.gitattributes`, `.gitignore`
- [ ] `tools/types/globalTypes.None.d.luau` (vendored, pinned by sha256 — `luau-lsp analyze` never downloads type definitions), `roblox.yml` via `selene generate-roblox-std`
- [ ] `tests/run.luau`, `tests/harness/{Test,Fuzz,FakeClock,FakeScheduler}.luau`, plus a harness meta-test
- [ ] The require spike — A/B files, spec, `check-built-place.luau`
- [ ] `scripts/ci/check-guards.luau` and every guard fixture
- [ ] `.github/workflows/ci.yml`, `.githooks/pre-commit`, `scripts/verify.luau`, `MANUAL-CHECKS.md`
- [ ] **One end-to-end run of the whole CI chain** — nothing in the research was executed

---

## Exit-Code Traps (must be honoured or the hard-fail gate silently passes)

D-01 makes every check hard-fail. Research found three ways that promise breaks silently:

1. **`.luaurc` must set `"lintErrors": true`** — without it, luau-lsp lint warnings exit 0.
2. **`--formatter plain` always exits 0** — must not be used in the CI gate.
3. **`luau-lsp analyze` defaults to `--platform roblox` and never downloads Roblox type
   definitions** — the vendored `globalTypes.None.d.luau` is load-bearing, and the
   engine-purity run needs `--platform standard` to catch type-only `Instance` references.

Also: **Selene 0.32.0's `luau` std lacks `math.isfinite` / `isnan` / `isinf`**, so FOUND-04's
NaN check must be hand-written portably rather than relying on a stdlib helper.

---

## Manual-Only Verifications

Six checks need a human; this container has no Roblox Studio. These populate `MANUAL-CHECKS.md` (D-04).

| ID | Behavior | Requirement | Why Manual | Test Instructions |
|----|----------|-------------|------------|-------------------|
| M-01 | Studio sync does not delete Workspace content | FOUND-01 | Needs a real Rojo↔Studio sync | Open a fresh clone, `rojo serve`, connect the Studio plugin, place a Part in Workspace, sync again, confirm the Part survives |
| M-02 | `require` resolves in a real Studio server | FOUND-03 | Roblox runtime resolution can only be exercised in-engine | Run the built place in Studio, confirm engine modules load with no resolution error |
| M-03 | A live client firing a malformed payload is rejected | FOUND-04 | Needs a real client-server boundary | In a Studio playtest, fire the envelope remote with a NaN field; confirm rejection and no dispatch |
| M-04 | Separate test universe exists; production Studio API access is OFF | FOUND-07 | **Owner-only Creator Hub step** | Create the test experience, enable Studio API access on it only, record its place ids, confirm production has the toggle off |
| M-05 | Place Maximum Players = 10; an 11th join is refused | FOUND-08 | `Players.MaxPlayers` is ReadOnly — a place setting, not script-settable (confirmed from Roblox docs this phase) | Set Maximum Players to 10 in place settings; confirm the code-side kick path on overflow |
| M-06 | Gray-box map loads via `MapLoader` with no per-map branch; tags visible; sightlines sane | MAP-01 | Visual and in-engine | Load the gray-box map in Studio, inspect tagged spots and the 9 seat anchors, walk the sightlines |

---

## Validation Sign-Off

- [ ] All tasks have an automated verify command or a Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without an automated verify
- [ ] Wave 0 covers every MISSING reference above
- [ ] No watch-mode flags in any CI command
- [ ] Feedback latency < 5s for the filtered quick run
- [ ] The three exit-code traps are each covered by a test that proves the gate fails
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
