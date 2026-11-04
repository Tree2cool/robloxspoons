---
phase: 3
slug: placement-rules-map-pipeline-and-validator
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-11-04
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `03-RESEARCH.md` § "Validation Architecture". Task IDs are filled in by the
> planner; the requirement-level map below is authoritative until then.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | The project's own harness, `tests/harness/Test.luau`, discovered by `tests/run.luau` (`*.spec.luau`, excluding `fixtures/`). No Jest-Lua, no external framework — nothing to install. |
| **Config file** | none — `tests/run.luau` takes `--filter`, `--root`, `--seed` |
| **Quick run command** | `lune run tests/run.luau --filter placement` (plus `--filter maps`; the maps suite runs 60 cases in ~0.7s today) |
| **Full suite command** | `lune run tests/run.luau` then `lune run scripts/verify.luau` (14 steps) |
| **Estimated runtime** | ~25–26s for the full suite today (Phase 1 baseline 15.94s; the overshoot is an owner-accepted departure recorded in STATE.md). Phase 3 adds the bake, capped per D-09. |

---

## Sampling Rate

- **After every task commit:** Run `lune run tests/run.luau --filter placement` and `--filter maps`
- **After every plan wave:** Run `lune run tests/run.luau`
- **Before `/gsd-verify-work`:** `lune run scripts/verify.luau` green, **and every new gate demonstrated red** (see Observability below)
- **Max feedback latency:** ~1s for the quick run, ~26s for the full suite

---

## Per-Task Verification Map

Task IDs are assigned by the planner. Until plans exist, this maps **requirements** to their
automated commands; the planner must attach each row to at least one task.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD-plan | — | — | HIDE-06 | — | Corpus: known-good and known-bad coordinates, each with its reason code | unit | `lune run tests/run.luau --filter corpus` | ❌ W0 | ⬜ pending |
| TBD-plan | — | — | HIDE-06 | — | OBB maths agrees with a brute-force sampler; flood agrees with an independent union-find | fuzz (`tests/harness/Fuzz.luau`) | `lune run tests/run.luau --filter obb` / `--filter walkgrid` | ❌ W0 | ⬜ pending |
| TBD-plan | — | — | HIDE-07 | — | `check` takes no avatar argument (arity lock via `debug.info`); identical verdicts across repeated calls | unit | `lune run tests/run.luau --filter placement` | ❌ W0 | ⬜ pending |
| TBD-plan | — | — | MAP-02 | T-3-01 | Each new issue code fires on a dedicated fixture, **alone** (exact issue-set equality) | unit | `lune run tests/run.luau --filter validator` | ⚠️ extend | ⬜ pending |
| TBD-plan | — | — | MAP-02 | — | CLI exits 1 and prints `<CODE> <path> <message>` on a bad spot | integration | `lune run tests/run.luau --filter graybox` | ⚠️ extend | ⬜ pending |
| TBD-plan | — | — | MAP-03 | — | Graybox v2 passes with ≥16 and **every** authored spot valid (D-17 STRICT) | integration | `lune run tests/run.luau --filter graybox` | ⚠️ extend | ⬜ pending |
| TBD-plan | — | — | Gate G2 | — | Maze oracle (positive **and** negative), work counters, wall-clock cap | integration | `lune run tests/run.luau --filter maze` | ❌ W0 | ⬜ pending |
| TBD-plan | — | — | D-13/D-18 | T-3-02 | Config shape, injected-config loud failure, shipped-value lock, both coupling invariants | unit | `lune run tests/run.luau --filter config` | ❌ W0 | ⬜ pending |
| TBD-plan | — | — | must_have 1 | T-3-03 | Both snapshotters emit an identical `Node` shape incl. `up`, `canCollide`, `shape` | integration | `lune run tests/run.luau --filter graybox` | ⚠️ extend | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Observability of every new gate (the Phase 1/2 lesson)

**A green check is evidence only once someone has watched it go red.** Phase 2 found ~22 plan
assertions structurally incapable of failing. Research identified **nine** gates in this phase
that can pass vacuously. Each needs the stated mutation demonstrated, and the demonstration is
part of the task's done-condition, not a nice-to-have.

| # | Gate | How it passes vacuously | Required mutation / control |
|---|---|---|---|
| 1 | Issue-code coverage | A code is declared but never emitted | Fixture asserts the exact issue set **equals** `{that code}`, not "contains". Delete the rule → case must fail |
| 2 | Maze oracle | Erosion removes every corridor, so "sealed region not reached" is trivially true | Assert the positive half first (`cells > 0`, all non-sealed centres reached). Set corridor width 3 → must fail naming the empty region |
| 3 | Time cap | The bake did nothing | Assert non-zero deterministic work counters **before** reading the clock. Meta-case runs the same fixture under a deliberately tiny cap and asserts failure |
| 4 | Corpus | A verdict sits exactly on a threshold | Stability probe: re-run every corpus coordinate at `E ± 0.25` and require identical verdicts. Move one coordinate onto its threshold → probe must fail |
| 5 | Spec-lock "runtime uses shipped values" | `MapLoader` can't run headlessly (needs Roblox API), so a `grep` that also matches comments passes | Source assertion after comment-stripping (reuse `scripts/ci/lex.luau`'s `stripComments`): require a literal `Config.Placement` and that `validate(` receives a config. Remove the require → must fail |
| 6 | Signature lock (D-10) | A third parameter sneaks in | `debug.info(SpoonPlacement.check, "a") == 2`. Add a parameter → must fail |
| 7 | Ramp connectivity | Only the passing case is tested | Include the negative control `maxSlope = 24` (ledge culled, survivors 12) beside the positive case |
| 8 | Identical snapshot shapes | A field is missing from one snapshotter | Compare key sets field by field incl. `up`, `canCollide`, `shape`. A Node missing `canCollide` must fail |
| 9 | Typecheck / guards | `luau-lsp` exits 0 when its sourcemap fails to load (Phase 1's fourth exit-code trap) | Confirm the typecheck step actually analysed the new files; run `check-guards` and add pure-zone fixtures only if new guard rules are introduced |

---

## Wave 0 Requirements

- [ ] `tests/placement/obb.spec.luau` — slab degenerate cases, brute-force differential fuzz
- [ ] `tests/placement/walkgrid.spec.luau` — ramp, thin wall, erosion, link verification, flood differential
- [ ] `tests/placement/corpus.spec.luau` — micro-world corpus (exact, no knife-edges) plus graybox corpus, reason codes only
- [ ] `tests/placement/config_lock.spec.luau` — invariants and shipped-value lock
- [ ] `tests/placement/maze.spec.luau` — oracle, counters, cap, negative control
- [ ] `scripts/maps/generate-maze.luau` — the adversarial fixture generator (D-08)
- [ ] Regenerated `maps/gray-box.rbxm` at ContractVersion 2 with **every** authored spot valid and real margin above 16 (D-17), plus updated `tests/maps/graybox.spec.luau` and `tests/maps/validator.spec.luau` (~12 `validate(` call sites, and the version-1 assertions at `validator.spec` lines 56 and 166-170 and `graybox.spec` line 92)
- [ ] **Framework install: none needed** — the in-repo harness already exists

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Reference-capsule dimensions match real Roblox avatars | HIDE-07 / D-10 | V-19 is only partly primary-sourced: per-axis avatar scale limits, the R15 default HipHeight and any camera-height formula were **not** found in docs. The 90–105% height / 70–100% width figures came from a web-search summary, not a primary source. | At the first full-roster playtest, stand avatars at the scale extremes beside a validated spot and confirm each can reach it. Until then D-11's bias-toward-rejecting is the mitigation, not a verification. |
| The place's `CharacterMaxSlopeAngle` is ≥ the rule's `MAX_SLOPE_DEGREES` | HIDE-06 / D-18 | It is a place setting outside the repo, like `Players.MaxPlayers` (MANUAL-CHECKS M-05) and the FOUND-07 persistence toggle. Nothing in the repo can detect it being changed. | Confirm in Studio / Creator Hub that it is at or above 30. Record alongside the other out-of-repo controls. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] **All nine vacuous-pass gates demonstrated red** before sign-off
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
