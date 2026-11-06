---
phase: 4
slug: live-card-table
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-11-05
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `04-RESEARCH.md` § "Validation Architecture". **Task IDs are filled in at sign-off**
> from the plan summaries, as in Phase 3 — plans do not exist yet at the time this file is created.

**Read this first:** every command assumes `export PATH=$HOME/.rokit/bin:$PATH` — the `lune` binary
lives at `~/.rokit/bin/lune` and is **not on `PATH`**. Use `--root`, never `--filter`: the
`--filter` label collides across suites (Phase 2 deferred item D-02-09-2).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Project harness `tests/harness/Test.luau` (`t.test/equal/deepEqual/truthy/throws/fuzz`) on Lune 0.11.1 |
| **Config file** | `tests/run.luau` — discovers `**/*.spec.luau`; exits non-zero on failing, unloadable, empty, or filter-matching-nothing runs |
| **Reusable fakes** | `tests/harness/FakeClock.luau` (seconds), `FakeScheduler.luau`, `Fuzz.luau`. **Wave 0 adds** `tests/harness/RecordingPublisher.luau` |
| **Quick run command** | `lune run tests/run.luau -- --root tests/card` |
| **Full suite command** | `lune run tests/run.luau` |
| **Baseline runtime** | **657 passing in ~20.5 s** before this phase. Measured three times: 23.07 s (research), 20.53 s (planner), **20.15 s (orchestrator, `lune run tests/run.luau`)**. The 23.07 s reading was taken under load and is NOT the baseline — using it would have handed this phase ~2.5 s of slack that does not exist |
| **Phase budget** | **+3 s of real work. The 23.5 s figure is a target, NOT a tripwire — see the load warning below.** All new specs in-process and pure. No new subprocess gates beyond the three guard fixtures plan 04-02 justifies (~0.15 s) and the new pure zone's selene run (~0.4 s) |

### Container load swamps this budget — read this before declaring a breach

**An UNCHANGED tree measured 31.54 s during planning** (657 cases, no source touched) against the
same tree's 20.15 s floor. That is an 11 s spread from container load alone, roughly **3.7x this
phase's entire +3 s allowance**. A single reading therefore proves nothing about this phase's cost.

**Protocol, which overrides any single-number reading:**
1. Take **three** readings and compare the **minimum**, not the mean or the latest.
2. If even the minimum looks implausible, **record the load condition and re-measure when quiet** —
   do NOT declare a breach. A false breach spends an owner decision on noise, which is worse than
   no gate at all.
3. **The real gate is the case count plus the per-spec allocation table in plan 04-20**, which
   measures work rather than wall clock. Wall clock is corroboration.
4. Never cut a mutation, a non-vacuity assertion or a clean control to save time. If the budget
   genuinely cannot hold, that is the owner's decision at 04-20's checkpoint.

### Why the budget exists at all

CI was 15.94 s at the Phase 1 baseline, ~25-26 s at Phase 2 close (owner-accepted departure), and
29.9 s at Phase 3 close (a **second** approved departure). STATE.md records that this phase adds
the most test weight of any remaining phase. A third silent overshoot is not available: if the
+3 s budget cannot hold, that is an explicit owner decision before phase close, not a shrug.

---

## Sampling Rate

- **After every task commit:** `lune run tests/run.luau -- --root tests/card` (target <= 3 s) **and**
  `lune run scripts/ci/check-guards.luau`
- **After every plan wave:** `lune run tests/run.luau` (full suite) + `lune run scripts/verify.luau`
- **Before `/gsd-verify-work`:** full suite green, `verify.luau` all steps green
- **Max feedback latency:** ~3 s per task, ~27 s per wave

**Rationale.** The pure tests run in milliseconds, so the whole `tests/card` root runs on every
task commit. The one failure mode sampling can miss is a **time-dependent interleaving**, so the
prediction and idle specs use fixed virtual-time scripts *plus* a seeded fuzz over
`{latency 150..300 ms, reject mask, forced-pass injection}` with a bounded iteration count.

---

## Per-Task Verification Map

Task IDs are assigned when plans are written; this table is completed at sign-off. The
**requirement-to-behaviour map below is fixed now** and is what the planner must satisfy.

| Req ID | Behaviour under test | Test Type | Automated Command | Spec file | Status |
|--------|---------------------|-----------|-------------------|-----------|--------|
| CARD-02 | Select then commit emits exactly one `Pass{seq,cardId}`; selection follows tap; tap-off clears | unit (reducer) | `--root tests/card` | `prediction.spec` | ⬜ W0 |
| CARD-13 | Owner-only `Sync`; public batch carries depths only; no rank outside `Completed` | unit (recording publisher) | `--root tests/card` | `privacy.spec` | ⬜ W0 |
| CARD-14 | Display changes in the commit call; rollback on reject; watchdog; cumulative ack at 150/300 ms virtual latency | unit (link sim) | `--root tests/card` | `prediction.spec` | ⬜ W0 |
| CARD-15 | A single tap never emits an intent; **no debounce exists** (D-02/D-03 spec-lock) | unit + spec-lock | `--root tests/card` | `prediction.spec` | ⬜ W0 |
| CARD-16 | D-15 gating, 80 deci, 3 strikes, reset on action, bench via `Benched`, uniform-random choice, **D-35 hand-4 is strike-only with no draw** | unit | `--root tests/card` | `idle.spec` | ⬜ W0 |
| CARD-17 | Flourish hard-capped at 1.5 s, yield cancelled, **input fires during it**, scan catches `Active`/escaped instances | unit (mocked clock) | `--root tests/card` | `flourish.spec` | ⬜ W0 |
| CARD-19 | 50-face identity key injective; **distinct drawn asset per key**; copy permutation; joker map exhaustive | unit | `--root tests/card` | `faces.spec` | ⬜ W0 |
| UX-01 | Every hit rect >= 48 **physical** px at 4 viewports and the 0.85 scale floor | unit (`Layout`) | `--root tests/card` | `layout.spec` | ⬜ W0 |
| UX-02 | `Controls.hide/restore` call order and idempotence against a fake; **no `GetControls`/`PlayerModule` string anywhere in `src/`** | unit + grep guard | `--root tests/card` + `check-guards` | `controls.spec` | ⬜ W0 |
| UX-03 | Interactive rects inside the inset rect; `ScreenInsets` constant is `CoreUISafeInsets`; **strip fits at `PreferredTextSize` = Largest (D-36)** | unit | `--root tests/card` | `layout.spec` | ⬜ W0 |
| UX-04 | Input-kind map exhaustive; hint table complete and <= 38 chars | unit | `--root tests/card` | `hints.spec` | ⬜ W0 |
| rule 7 | `Draw`/`Pass` reject `seat`/`to`/`target`/`index`/NaN/extra keys | unit | `--root tests/net` | extend `manifest.spec` | ⬜ |
| rule 1 | `CardTable*` has no import path to cosmetics/shop | guard | `check-guards.luau` | existing (filename-covered) | ⬜ |
| rule 3 | `rankOf` not referenced in `src/client` or `src/shared` | guard | `check-guards.luau` | edit `zones.luau` | ⬜ |
| R4 | Only `NetServer.luau` names `FireClient`/`FireAllClients` | guard (existing) | `check-guards.luau` | `zones.luau:44-45` | ✅ exists |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky · W0 = needs Wave 0 scaffolding*

---

## Wave 0 Requirements

- [ ] `tests/harness/RecordingPublisher.luau` — records `toPlayer`/`toSeated`/`toAll` calls so the
      privacy assertions can inspect routing rather than trusting it
- [ ] `tests/card/` root with the seven spec files above
- [ ] `scripts/ci/zones.luau` — add `rankOf` to the client/shared secret-name scan (rule 3)
- [ ] `MANUAL-CHECKS.md` — write the device rows (M-11 onward) **before** execution, so nothing
      device-dependent can be silently ticked as done
- [ ] No framework install needed — existing harness covers everything

---

## Mutation Tests (mandatory per gate)

The project's own record is that **~31 assertions structurally incapable of firing** were found
across Phases 2 and 3, found by plan-checkers and executors who were actively looking for them. So
every gate here carries three obligations, following the `valve.spec` "MUTATION" pattern:

1. a **clean control** that passes against the real implementation;
2. a **non-vacuity assertion** — the count of cases / viewports / faces / players / rejects actually
   exercised, so a gate that silently tests nothing fails;
3. the mutation expressed by **injecting a broken dependency**, never by editing source.

| Gate | Mutation that must turn it red |
|------|-------------------------------|
| Face record private | Publisher fake routes `Sync` via `toSeated`/`toAll` |
| Forced pass private (D-18) | `ValveForcedPass` placed in the public batch, or the `Notice` sent to the wrong player |
| No rank leak | `Table` payload gains a `rank` for a non-retired card |
| NetServer guard | A real `toAll("Sync")` fails to throw |
| 48 px floor | `STEP` 60 -> 44; scale floor 0.85 -> 0.7; hit strip shrunk by the 12 px overlap |
| Safe area | Layout ignores the inset; hand rect extends under it |
| TableRegion >= 58% | HandZone 144 -> 170 |
| Lifted card vs strip | lift 16 -> 20 — **this is the checker's F1 case, which was live in the spec** |
| Greyscale key injective | collapse two pip shapes in the data |
| Greyscale drawn asset | point two pip ids at the same asset |
| Joker map exhaustive | add a third `JokerMode` string; must fail until mapped |
| Copy assignment | skip the ascending sort, or reuse a copy index |
| D-15 idle gating | clock also runs at hand 4 with an empty inbox, or runs at hand 4 only |
| 8.0 s ceiling | `AUTO_PASS_DECI` 80 -> 81 |
| D-35 hand-4 behaviour | an auto-**draw** fires at hand 4; must fail |
| Strike reset | an accepted action does not reset strikes |
| Bench path | bench issues `Remove` with cause `Completed`, or bypasses `Remove` |
| D-14 selection rule | auto-pass picks the lowest-rank card (greedy) instead of uniform-random |
| Stall independence (D-20) | detector keyed on `ValveForcedPass` — must fail the "stuck, valve silent" case |
| Prediction rollback | `onSync` does not drop acked pending; watchdog never fires |
| Prediction rule 7 | commit emits a hand index or a `to` key |
| Prediction placeholder | `Pass` allowed for a nil-id placeholder |
| Flourish cut-off | remove the teardown timer; arm the cut-off *after* `play` |
| Flourish scan | an `Active` GuiObject or an instance outside `ctx.root` goes uncaught; a scan that never runs must fail the control |
| Hints | delete one cell of the (state x input) table |
| Manifest | add `seat`/`index` as allowed keys |
| Controls | `restore()` not called on `Completed`; a `GetControls` string present in `src/` |

---

## Manual-Only Verifications

**This phase is the least machine-verifiable so far — four of the five ROADMAP success criteria are
device-dependent.** That is a property of the phase, not a gap in this strategy, and it must be
stated in the phase gate rather than discovered there.

| Behaviour | Requirement | Why manual | Where |
|-----------|-------------|-----------|-------|
| Tap feel; a single tap never sends | CARD-02, CARD-15 | Needs a real thumb on glass | M-11+ |
| Immediacy at 150-300 ms real latency, no visible glitch | CARD-14 | Virtual time proves convergence, not *feel* | M-11+ |
| Thumb reach, physical target size, safe area on a notched device | UX-01, UX-03 | Needs real hardware; `ScreenInsets` behaviour observable only on glass | M-11+ |
| **Control hide/restore actually works, and restores cleanly** | UX-02, D-29 | **`GetControls()` is undocumented and slated for removal; no replacement is proven under IAS.** Community reports describe stuck-touch and held-key bugs on re-enable | M-11+ (**highest-risk row**) |
| Card pips and greyscale legibility at fan size | CARD-19 | Automated test proves key injectivity, not human legibility. Spade vs club at 16 px is the hardest pair | M-11+ |
| Text at `PreferredTextSize` = Largest | UX-03, D-36 | Rendered width is device/setting dependent | M-11+ |
| Starting-gun feel and audio | CARD-17, D-33 | Subjective | M-11+ |
| Landscape lock | D-28 | **Creator Dashboard setting — human-only** | `NEEDS_HUMAN.md` |
| IAS flag pinned explicitly | D-29 note | Studio/Dashboard, and the value needs observation | `NEEDS_HUMAN.md` |
| Audio asset ids; suit-pip sprite upload if glyphs fail | D-33, CARD-19 | Owner-uploaded assets | `NEEDS_HUMAN.md` |
| V-35 human reaction model | CARD-16 evidence | **Cannot be closed by any test or doc** — needs a real playtest (M-07) | Phase 6/8 |

---

## Validation Sign-Off

- [ ] All tasks have an `<automated>` verify or a Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without an automated verify
- [ ] Wave 0 covers every MISSING reference
- [ ] No watch-mode flags
- [ ] Feedback latency < 3 s per task
- [ ] Every gate in the mutation table has a clean control **and** a non-vacuity assertion
- [ ] Suite runtime: **minimum of three readings** <= 23.5 s, or the load condition recorded and a quiet re-measure taken. Per-spec allocations in 04-20 within budget (2.73 s allocated against 3.0 s). Never satisfied by cutting a mutation, a non-vacuity assertion or a clean control
- [ ] Device rows written to `MANUAL-CHECKS.md` before execution, not after
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
