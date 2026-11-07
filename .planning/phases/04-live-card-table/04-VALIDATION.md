---
phase: 4
slug: live-card-table
status: gate-open (machine-green; device matrix unsigned)
nyquist_compliant: true
wave_0_complete: true
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
| **Phase budget** | **+3 s of real work. The 23.5 s figure is a target, NOT a tripwire — see the load warning below.** All new specs in-process and pure. No new subprocess gates beyond the **four** guard fixture roots plan 04-02 justifies (**~0.20 s**) and the new pure zone's selene run (~0.4 s). Allocated total is **2.73 s against 3.0 s** (2.09 s of specs), reserve 0.27 s — the per-spec table in plan 04-20 is the authoritative breakdown |

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

- **After every task commit:** `lune run tests/run.luau -- --root tests/card` (allocated **2.09 s**; see plan 04-20's per-spec table, which is the gate) **and**
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
| CARD-02 | Select then commit emits exactly one `Pass{seq,cardId}`; selection follows tap; tap-off clears | unit (reducer) | `--root tests/card` | `prediction.spec` | ✅ green (device-gated: M-13) |
| CARD-13 | Owner-only `Sync`; public batch carries depths only; no rank outside `Completed` | unit (recording publisher) | `--root tests/card` | `privacy.spec` | ✅ machine green (human gate outstanding, see completed map) |
| CARD-14 | Display changes in the commit call; rollback on reject; watchdog; cumulative ack at 150/300 ms virtual latency | unit (link sim) | `--root tests/card` | `prediction.spec` | ✅ green (device-gated: M-13) |
| CARD-15 | A single tap never emits an intent; **no debounce exists** (D-02/D-03 spec-lock) | unit + spec-lock | `--root tests/card` | `prediction.spec` | ✅ green (device-gated: M-13) |
| CARD-16 | D-15 gating, 80 deci, 3 strikes, reset on action, bench via `Benched`, uniform-random choice, **D-35 hand-4 is strike-only with no draw** | unit | `--root tests/card` | `idle.spec` | ✅ machine green (human gate outstanding, see completed map) |
| CARD-17 | Flourish hard-capped at 1.5 s, yield cancelled, **input fires during it**, scan catches `Active`/escaped instances | unit (mocked clock) | `--root tests/card` | `flourish.spec` | ✅ machine green (human gate outstanding, see completed map) |
| CARD-19 | 50-face identity key injective; **distinct drawn asset per key**; copy permutation; joker map exhaustive | unit | `--root tests/card` | `faces.spec` | ✅ machine green (human gate outstanding, see completed map) |
| UX-01 | Every hit rect >= 48 **physical** px at 4 viewports and the 0.85 scale floor | unit (`Layout`) | `--root tests/card` | `layout.spec` | ✅ machine green (human gate outstanding, see completed map) |
| UX-02 | `Controls.hide/restore` call order and idempotence against a fake; **no `GetControls`/`PlayerModule` string anywhere in `src/`** | unit + grep guard | `--root tests/card` + `check-guards` | `controls.spec` | ✅ machine green (human gate outstanding, see completed map) |
| UX-03 | Interactive rects inside the inset rect; `ScreenInsets` constant is `CoreUISafeInsets`; **strip fits at `PreferredTextSize` = Largest (D-36)** | unit | `--root tests/card` | `layout.spec` | ✅ machine green (human gate outstanding, see completed map) |
| UX-04 | Input-kind map exhaustive; hint table complete and <= 38 chars | unit | `--root tests/card` | `hints.spec` | ✅ machine green (human gate outstanding, see completed map) |
| rule 7 | `Draw`/`Pass` reject `seat`/`to`/`target`/`index`/NaN/extra keys | unit | `--root tests/net` | extend `manifest.spec` | ✅ green |
| rule 1 | `CardTable*` has no import path to cosmetics/shop | guard | `check-guards.luau` | existing (filename-covered) | ✅ green |
| rule 3 | `rankOf` not referenced in `src/client` or `src/shared` | guard | `check-guards.luau` | edit `zones.luau` | ✅ green |
| R4 | Only `NetServer.luau` names `FireClient`/`FireAllClients` | guard (existing) | `check-guards.luau` | `zones.luau:44-45` | ✅ exists |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky · W0 = needs Wave 0 scaffolding*

---

## Wave 0 Requirements

- [x] `tests/harness/RecordingPublisher.luau` — records `toPlayer`/`toSeated`/`toAll` calls so the
      privacy assertions can inspect routing rather than trusting it
- [x] `tests/card/` root with the seven spec files above
- [x] `scripts/ci/zones.luau` — add `rankOf` to the client/shared secret-name scan (rule 3)
- [x] `MANUAL-CHECKS.md` — write the device rows (M-11 onward) **before** execution, so nothing
      device-dependent can be silently ticked as done
- [x] No framework install needed — existing harness covers everything

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
| Bench path | **Row rewritten 2026-11-06 — the original mutation was not reachable.** It read "bench issues `Remove` with cause `Completed`", but `ShellRemoveCause` excludes `Completed`, so a shell issuing it is a **type error** rather than a test failure, and the real `CardTable` cannot be made to pass it because `Engine` is required directly. Reaching it would need a monkeypatch of the unfrozen `Engine.apply`, which risks cross-test leakage. **What is tested instead:** an injected `IdleClock` mutant returns a malformed command — containment holds, the following command still runs, the collected batches still publish, `Invariants.check` stays clean and the card count is conserved. The engine's own refusal is asserted directly in 04-12 case 4, and a shell that issued `Completed` would additionally fail case 2 on the real path (no `SeatRemoved{Benched}`). The table is corrected to match the plans, not the reverse |
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

## Measured at the phase gate (plan 04-20)

**Budget: SETTLED. It holds.** The authoritative figure is the orchestrator's one controlled
phase-wide pre/post in `04-BUDGET-LOG.md`, taken back to back on the same machine:

| | Commit | Cases | Min of 2 |
|---|---|---|---|
| Pre-phase | `ae376d6` | 657 | 23.65 s |
| Post-phase | after wave 9 | 858 | 24.89 s |
| **Phase cost** | | **+201 cases** | **+1.24 s of the +3.00 s allowance (1.76 s of headroom)** |

Summing the nine per-wave deltas gives ~2.20 s, which is noise-inflated: five of the nine waves
(2, 4, 7, 8, 9) measured at or below zero, which is not possible for a real cost. Per-wave rows are
for attribution only; the phase-wide row is the number.

**Plan 04-20's own readings** (worktree at `ac06749`, all 19 implementation plans merged, taken
while nothing else of mine was running): full suite **25.47 s, 25.23 s, 25.70 s**, all
`858 passed, 0 failed, 0 todo`; minimum **25.23 s**. `tests/card` root: `186 passed, 0 failed, 0 todo
in 0.54 s`. `scripts/verify.luau`: all 14 automated steps, 28.4 s (its Tests step 25.6 s).

These do **not** contradict the controlled figure. They sit ~0.3 s above the orchestrator's 24.89 s
post-phase minimum, which is ordinary container noise, and the absolute 23.5 s "target" in this file's
Test Infrastructure block is not reproducible on this container today: the *pre-phase* tree itself
read 23.65 s under the same conditions. That target was built on a 20.15 s quiet-machine reading, and
this file's own load warning says to use the delta, not the absolute. **No owner decision is needed
on the budget.**

**Per-source attribution.** `tests/card` is 0.54 s against its 2.09 s allocation (it carries 186 of
the 201 new cases). The remaining ~0.7 s of the +1.24 s is subprocess work: wave 1's +1.10 s was the
four new guard fixture roots. **The allocation table under-estimated that item**: it allocated
~0.20 s and the budget log attributes ~0.9 s of subprocess work to wave 1. The total still holds
because the pure in-process specs cost little: taking wave 1's 1.10 s at face value, the phase-wide
1.24 s leaves only ~0.14 s for everything after it (the per-wave figures are noisy, so treat this as
shape, not arithmetic). The over-run in one line was absorbed by slack in the others. Recorded rather than hidden: the
allocation table is right about *shape* and wrong about that one line. The extra `selene` pass for
the `src/shared/Card` pure zone was below run-to-run noise (wave 2). Per-spec wall times are not
printed by `tests/run.luau`; the per-plan figures each summary measured are the evidence (for
example `cardtable.spec` 0.12-0.14 s against a 0.35 s cap), and none reported a spec over its
allocation. `round_end.spec` (04-19) is the one spec not in the allocation table.

## Per-task map, completed at sign-off

All commands run from the repo root with `export PATH=$HOME/.rokit/bin:$PATH`. "Machine" means
`lune run tests/run.luau -- --root tests/card` plus `lune run scripts/ci/check-guards.luau` unless a
row says otherwise. **A row marked "device-gated" is NOT green; it is machine-green with a named human
gate outstanding.**

| Req | Plans | Spec files | Machine status | Human gate | Reads as |
|-----|-------|------------|----------------|------------|----------|
| CARD-02 | 04-09, 04-17, 04-18 | `prediction.spec`, `layout.spec` | green | M-13, M-17 | device-gated |
| CARD-13 | 04-01, 04-05, 04-12, 04-13, 04-19 | `privacy.spec`, `routing.spec`, `netguard.spec`, `cardtable.spec`, `round_end.spec` | green | M-12 (two real clients) | device-gated; depth data path exists, on-glass rendering unproven |
| CARD-14 | 04-09 | `prediction.spec` | green | M-13 | device-gated |
| CARD-15 | 04-03, 04-09 | `prediction.spec`, `manifest.spec` (`--root tests/net`) | green | M-13, M-17 | device-gated; double-tap residual is D-04-14 |
| CARD-16 | 04-01, 04-06, 04-07, 04-12, 04-14 | `config_lock.spec`, `idle.spec`, `stall.spec`, `reject_throttle.spec`, `cardtable.spec`, `deci_lock.spec` | green | V-35 / M-07 (open since Phase 2), M-17 | **machine-green; plus an OPEN owner decision, D-04-13** |
| CARD-17 | 04-10, 04-11, 04-19 | `flourish.spec`, `flourish_surface.spec`, `controls.spec` | green | M-16, M-17 | device-gated; the feel is human-only |
| CARD-19 | 04-04, 04-16, 04-17 | `faces.spec`, `renderer_discipline.spec` | green | M-14, M-16 | device-gated; legibility is M-14 |
| UX-01 | 04-08 | `layout.spec` | green | M-12 | **human-only for the thing the requirement is about** |
| UX-02 | 04-11, 04-15, 04-18 | `controls.spec`, `seathold.spec`, `renderer_discipline.spec` | green | **M-11 (highest risk)** | **human-only for whether it works** |
| UX-03 | 04-08, 04-16 | `layout.spec`, `renderer_discipline.spec` | green | M-12 | **human-only for notch and Largest text** |
| UX-04 | 04-11, 04-18 | `hints.spec`, `renderer_discipline.spec` | green | M-11 (gamepad column, V-27) | **human-only for the gamepad column** |
| rule 7 | 04-03 | `manifest.spec` | green | - | machine-closed |
| rule 1 | 04-02, 04-10 | `check-guards`, `flourish.spec` spec-lock | green | - | machine-closed (renderer deliberately not a guarded root, see STATE carry) |
| rule 3 | 04-02 | `check-guards` (`rankOf`) | green | - | machine-closed |
| R4 | 04-13 | `check-guards`, `netguard.spec` | green | M-12 (`toPlayer` -> `FireClient(player)`) | machine-closed except the four-line adapter |

## Mutation ledger

**LEDGER COUNTS: 27 table rows + 2 rows the table was missing = 29 gates accounted for. Red output
recorded: 29 of 29 (several with a qualifier, below). HOLES: 5 never written, 0 never run, 3
structurally incapable of firing (live) -- plus 4 more that were structurally incapable as originally
written and were caught and corrected before shipping. 8 live holes in total.** None of the 8 turns a
table row's own mutant into a false pass; they are gaps beside the rows, found by reading the specs
as written. Method: spec files re-read; counts re-derived from the specs rather than the prose; the
red outputs below are the executors' recorded ones, and plan 04-20 additionally re-ran two source
mutations as a spot-check (`Layout.STEP` 60 -> 44, and the `assertPublic` guard removed from
`makePublisher.toAll`): each turned `tests/card` red (3 failed), and the tree was restored clean.
"Never run" is 0 because every in-spec mutant executes on every suite run and asserts its own
redness, and every source-edit mutation is recorded in a summary; it is **not** a claim that plan
04-20 re-ran all of them.

### The 27 rows (+2)

| # | Gate | Plan | Spec :: case | Red output recorded in summary | Clean control / non-vacuity beside it |
|---|------|------|--------------|--------------------------------|----------------------------------------|
| 1 | Face record private | 04-01, 04-05, 04-12 | `privacy` :: "MUTATION: five leaks"; `routing` :: "MUTATION: a Publisher fake that routes Sync via a broadcast" | yes: 04-01 `expected toPlayer, got toAll`; 04-12 #2 (6 failed) | real path passes in the same case; "2 private calls routed", 51 problems |
| 2 | Forced pass private (D-18) | 04-05, 04-12 | `routing` :: "MUTATION: a router that passes ValveForcedPass through"; `privacy` leak 3 | yes: 04-05 `defects clean=0 mutant=1`; on-disk 3 FAIL | clean 0; mutant forwarded 3 events |
| 3 | No rank leak | 04-05, 04-12 | `routing` :: "MUTATION: a Table payload that gains a rank"; `privacy` leak 4 | yes: `rankLeaks clean=0 mutant=2 of 3`; 12 problems | **qualifier:** no production-source mutant exists (`split` never reads `rankOf`); the mutant is a decorating publisher |
| 4 | NetServer guard | 04-05, 04-13 | `netguard` :: "MUTATION: a publisher assembled without the guard"; `routing` :: "makePublisher is the shipped assembly" | yes: 04-13 M1/M2 (3 failed), M7 swap | per-closure-body assertion; bodies 185/211/89/38 chars; comment negative control |
| 5 | 48 px floor | 04-08 | `layout` :: "MUTATION: eight broken designs" (rows 1-3) | yes: STEP=44 8/8; SCALE_MIN=0.7 8/8 (+ physical 2/2); HIT_W=48 2/8 | clean control per mutant; "ran the same pairs" |
| 6 | Safe area | 04-08 | `layout` rows 7-8 | yes: insets ignored 4/4; PILE_MARGIN=-12 8/8; FAN_BOTTOM_MARGIN=-16 8/8, offender named | clean outside = 0 on every viewport; no mis-blame |
| 7 | TableRegion >= 58% | 04-08 | `layout` row 4 | yes: HANDZONE_H=170 red 6/8 | tightest real fraction 59.08% printed |
| 8 | Lifted card vs strip | 04-08 | `layout` row 5 | yes: LIFT=20, `gap 0` 8/8 | touching counts as a violation (the F1 case) |
| 9 | Greyscale key injective | 04-04 | `faces` :: "MUTATION: collapsing two pip silhouettes" | yes: 6 cases red | 50 keys counted |
| 10 | Greyscale drawn asset | 04-04 | `faces` :: "MUTATION: pointing two pip ids at the same drawn asset" | yes: `duplicate drawn asset`; the proxy-audit mutant fails only this case | asset count asserted |
| 11 | Joker map exhaustive | 04-04 | `faces` :: "the joker map is exhaustive in both directions"; "MUTATION: two joker modes sharing a band shape" | yes for the band; **qualifier:** the third-mode ("Chaos") case is an injected audit argument asserting `{"unmapped joker mode: Chaos"}`, green by design | frozen-table and length checks |
| 12 | Copy assignment | 04-05 | `routing` :: "MUTATION: skipping the ascending visit or reusing a copy index" | yes: reuse rejected; descending differs on 40/41 ids | permutation gate **stays green** on descending; only the compare-to-production assertion catches it (a single net) |
| 13 | D-15 idle gating | 04-06 | `idle` :: "MUTATION: 81-deci, a too-wide predicate, a hand-4-only predicate" | yes: 4 failed / 9 failed | 100-tick ramp has its own clock-level view-rewrite mutant |
| 14 | 8.0 s ceiling | 04-01, 04-06, 04-12, 04-14 | `config_lock` :: "MUTATION: a naive conversion"; `cardtable` case 1b; `deci_lock` | yes: 04-01 `got 81`; 04-14 M1 reddens 5 cases over 3 plans; M3, M4 | non-vacuity forced the `(0.07, 100)` inputs |
| 15 | D-35 hand-4 no draw | 04-06 | `idle` :: "MUTATION: a clock that auto-draws at hand 4"; open-set `noCardMoved` | yes: 2 failed | mutant emits `AutoPass` and a `Draw` kind; **row reworded** (AutoDraw is unrepresentable) |
| 16 | Strike reset | 04-06 | `idle` :: "MUTATION: a strike that does not reset" | yes: 2 failed | reset-less wrapper fails `resetProblems` |
| 17 | Bench path | 04-12 | `cardtable` :: "the AFK path benches through Remove{Benched}"; "MUTATION: a bench that destroys the cards"; "MUTATION: one bad command does not abort the sweep"; "the shell never issues Remove{Completed}" | yes: 04-12 #7 (type bypassed with `any`: 2 failed) | **row rewritten; literal mutant never written (hole N1).** The destroying-bench mutant edits a hand-built state and tests the helper; the real-path control is what can fire |
| 18 | D-14 uniform selection | 04-06 | `idle` :: "MUTATION: a greedy pick" | yes: 5000 picks of card 11 | 5000 seeded draws |
| 19 | Stall independence (D-20) | 04-07 | `stall` :: "MUTATION: a valve-keyed detector is silent" | yes: `valve-keyed cues = 0; real = 8`; on-disk edits 2, 3 | stuck scenario fires at deci 864, repeats every 300; **see hole I2** |
| 20 | Prediction rollback | 04-09 | `prediction` :: "MUTATION: five broken reducers" (two of the five) | yes: verbatim | counter asserts 5 |
| 21 | Prediction rule 7 | 04-09 | same case | yes: key set `cardId,index,seq,to` | |
| 22 | Prediction placeholder | 04-09 | same case | yes | |
| 23 | Flourish cut-off | 04-10 | `flourish` :: "(f) MUTATION: the cut-off removed, and the cut-off armed AFTER play" | yes: 6 failures; order case | **weak: order-dependent counter (W1)** |
| 24 | Flourish scan | 04-10, 04-19 | `flourish`, `flourish_surface` (6 mutants + twin) | yes: 04-10 mutation 3; 04-19 | all five input kinds executed over 8 fakes; the 04-19 predicate is the one `destroyOffenders` uses |
| 25 | Hints | 04-11 | `hints` :: "MUTATION: a deleted cell, an over-long string, an exclamation mark and error copy" | yes: `missing cell: Selected/Gamepad` | counter asserts 4 |
| 26 | Manifest | 04-03 | `manifest` :: "rule 7 MUTATION" (a)-(d) | yes: 1 / 2 / 14 / 14 red; on-disk 6 failed | hard `seen == 14` |
| 27 | Controls | 04-11 | `controls` :: "MUTATION: three broken orderings"; `src/` walk | yes: never-restores, flourish-first, reenable-first | 50 files walked, 0 hits, negative control fires exactly once |
| 28 | Notice to the wrong player (was missing) | 04-05, 04-12 | `privacy` leak 5; `routing` | yes: `recipient clean=102 mutant=103`; 04-12 #1 (2 failed) | broadcast gate sees 0 for this mutant, proving it needs its own row |
| 29 | Bench issues `Remove` cause `Completed` (was missing) | 04-12 | **never written**; engine refusal asserted directly | the replacement is recorded | see hole N1 |

Rows whose shape legitimately changed (the table is reconciled to the plans, not the reverse): 15
(open-set `noCardMoved` replaced the unfireable `cmd.kind ~= "AutoDraw"`), 4 (now the shipped
`makePublisher` assembly), 6 (now two margin mutants naming the offender), 14 (now drives the shipped
`CardTiming.autoPassDeci`), and 17.

### The holes, classified

**(i) Never written: 5**

| id | Hole | Where | Route |
|----|------|-------|-------|
| N1 | The literal "bench issues `Remove` cause `Completed`" mutant. Unwritable as stated (`ShellRemoveCause` excludes it, so it is a **type error**); reachable only by monkeypatching the unfrozen `Engine`, which was **declined for cross-test leakage, not because it is impossible**. The engine's own refusal is asserted directly and a shell issuing it would also fail the `SeatRemoved{Benched}` case. | 04-12 | D-04-15 follow-up; low value |
| N2 | Sinks-after-publish ordering is not directly asserted; mutation 10 was a crude double-fire. | 04-12 | D-04-16 |
| N3 | The service layer: `CardService` and `Main.server` cannot load in Lune, so the Heartbeat accumulator, the reject sink, `PlayerRemoving`, the `CardSeatHold` call sites and the release-before-flourish order are source-checked only. One source-scan gate covering all of them is the obvious follow-up (the `RoundEnd` publish already has one in `round_end.spec`). | 04-13, 04-14, 04-15 | D-04-15 |
| N4 | Review-only timer paths with no executed test: the strip's `task.delay` cancellation, the held-return `task.delay` and `Tween.Completed:Once`, the table-place `pcall`, `CardHud.new`'s possible yield. | 04-16 to 04-19 | D-04-20 |
| N5 | A per-message Depths truth check: only the final `Depths` message is compared with the engine's true inbox sizes. | 04-19 | D-04-29 |

**(ii) Written but never run red: 0.** See the method note above.

**(iii) Structurally incapable of firing, live in the tree: 3**

| id | Assertion | Why it cannot fire | What actually covers the claim |
|----|-----------|--------------------|-------------------------------|
| I1 | `privacy.spec` :: "RoundEnd is a public kind with no private payload", the lines "the real payload carries no key at all" and "mutant: a payload carrying a hand must be flagged" | The recorded payload is `{}` that the test itself passes to `rec.toSeated("RoundEnd", {})`, and the mutant is a literal handed to a local helper. Neither touches shipped code, so no change to production can turn them red. (The `audienceOf` / `PRIVATE_KINDS` / `assertPublic` assertions beside them are real and can fire.) | `round_end.spec`'s source scan of `CardService` with 7 real-text mutants |
| I2 | `stall.spec` healthy-control `margin >= 2` | A threshold halved to 48 per seat gives ~2.05x and still passes, so the control cannot separate 96 from 48. Reported by 04-07 as a finding exactly as instructed. | `Types.VALVE_ARM_ACTIONS_PER_SEAT` is asserted in the spec; Phase 8 tunes on telemetry (D-04-17) |
| I3 | `renderer_discipline` case 6, "no string literal other than empty" | Asserts only "no literal containing a space", so a space-free prose literal cannot trip it. M14 exercises the real strength. | the `UITextSizeConstraint` and one-line assertions beside it |

**Structurally incapable as originally written, caught and fixed before shipping: 4.** The D-35
`cmd.kind ~= "AutoDraw"` assertion (AutoDraw is unrepresentable); the 8.0 s ceiling "81" mutation
(a tautology over literals); the NetServer guard (unreachable while `NetServer` assembled the
publisher, which Lune cannot load); and the plans' naive-conversion example `(0.7, 10)` (04-01 and
04-14 both shipped the same wrong float example; the non-vacuity assertion caught it both times).

**Weak but able to fire (recorded, not counted as holes).**
W1 `flourish.spec`'s `mutationsRed` is order-dependent module state, so a failure there after the F8
case fails is a cascade and not an independent signal. W2 `layout.spec`'s `mutations += 1` is
unconditional and counts **rows**: it detects a deleted row but not a deleted `red(...)` call inside
one. W3 04-17 M6: the dedicated "`CardPiles` has N `Active` sinks" problem is not what fires first
(the non-vacuity assertion combines the count with another condition); the in-spec lost-sink mutants do
hit it. W4 04-18 M1 is likewise caught first by non-vacuity. W5 04-12's per-command `tick` mutant is
caught **only** by the structural first-publish assertion (the plan's "does not commute" claim was
false and 04-12 disproved it); that assertion exists because plan-checker flag 4 demanded it. W6
04-05's descending-copy mutant is caught by one assertion only. W7 the `Depths` privacy check was
caught by four tests on an on-disk mutation but its per-seat truth check sees the last message only
(also N5). W8 `readViewport` possibly double-counting insets under `CoreUISafeInsets` is untested
(M-12).

### Count reconciliation -- FINDINGS (the plan prose was NOT edited to match)

A stated count that is wrong is a non-vacuity assertion that has stopped working. Re-derived from the
spec files as written:

| # | Stated | Where | Actual | Verdict |
|---|--------|-------|--------|---------|
| F1 | "**fourteen** mutations in total across `privacy.spec` and `cardtable.spec`" | 04-12 success criteria | At 04-12's close: 5 (privacy) + 6 (`cardtable`: `autoPassDeci+1`, destroying bench, malformed command, publish-between-apply-and-sync, per-command `tick`, by-reference `RoundStart`) = **11** in-spec mutants; the summary records **10** numbered source-edit mutations (9 sound, #10 crude). The plan's own enumeration names 9 kinds. | **MISMATCH.** The tree now holds 8 + 6 = 14 only because plan 04-19 later added 3 `Depths` mutants to `privacy.spec`. That agreement is a coincidence, not a vindication |
| F2 | "the red output of **all nine** mutations" | 04-12 summary task | 11 in-spec / 10 source-edit recorded. "Nine" equals the source list only if the crude #10 is dropped, which 04-12's own summary discounts | **MISMATCH** with the same plan's "fourteen": two numbers in one plan, at least one wrong, and both are |
| F3 | privacy case "**drives 5**" / "**five leaks**" | 04-12 task 2 acceptance and `<done>` | `t.equal(mutations, 5)` over five `mutations += 1` (lines 697-735) | **CORRECT**, but true of that one case only. `privacy.spec` now has 2 mutation cases (5 + 3) and a literal-only RoundEnd "mutant" (I1) |
| F4 | `grep -c 'MUTATION:' tests/card/idle.spec.luau` returns "**at least 5**" | 04-06 acceptance | **4** `MUTATION:` cases. In-spec mutants number 7 (AutoPass-at-4, `Draw` kind, greedy, 81, too-wide, hand-4-only, reset-less) plus the D-15 view-rewrite = 8; the summary lists 9 source mutations | **MISMATCH.** The acceptance grep as written fails; the property it stood for holds. 04-06's summary does not mention the shortfall |
| F5 | "Count the mutations exercised and **assert 8**" / `grep -q 'assert 8'` | 04-08 | The counter is 8 and correct as **rows**. Distinct broken designs: **9** (`PILE_MARGIN` and `FAN_BOTTOM_MARGIN` share a row); `red(...)` is called **12** times. The `grep -q 'assert 8'` is satisfied by the assertion's own message string, so it could never fail | **CORRECT as stated, but the grep is vacuous and the counter is unconditional (W2).** 04-08 recorded that the plan said seven/six/8 in different places |
| F6 | "at least 6 checks" | 04-15 | actual 5 | self-caught by 04-15's non-vacuity assertion; the fourth thing that requirement caught this phase |
| F7 | "four new fixture roots ~0.20 s" | allocation table | the budget log attributes ~0.9 s to wave 1's fixtures | allocation mismatch, absorbed (see Measured) |
| F8 | the table's "27 rows" | this file | 27, verified by enumeration | correct |

Other in-spec mutation counters, all matching their cases: `controls` 3, `hints` 4, `seathold` 4,
`flourish_surface` 6, `round_end` 7, `prediction` 5, `manifest` 4 (+ 14 forbidden-key cases),
`flourish` 3 (order-dependent), `cardtable` by-reference forward 1.

### Gates added by the phase beyond the 27-row table (all with in-spec mutants)

`deci_lock` (04-14, M1-M5 on disk), `seathold` (04-15, 4 in-spec + a real-source release-order swap),
`renderer_discipline` (04-16..04-18, 24 `MUTATION` cases; on-disk mutations recorded: 16 in 04-16, a table in 04-17, 8 in 04-18),
`flourish_surface` (04-19), `round_end` (04-19, 7 real-text mutants), and the four guard fixture roots
(04-02, each watched red under a mutated `zones.luau`).

## Requirement coverage, honestly stated

| Req | Machine gate closes | Human gate must close |
|---|---|---|
| CARD-02 | a second tap on the same card emits exactly one `Pass`; the hit model's geometry | that it feels immediate under a thumb: M-13, M-17 |
| CARD-13 | owner-only `Sync`; a recursive key-name walk over every public payload; five leak mutants; the new `Depths` kind carries counts only (counts, never ids) and matches the engine | two real clients, one seeing only its own hand: M-12. **The depth half now has a server-supplied data path (04-19); its on-glass half (that stacks read) has none** |
| CARD-14 | convergence at 150/300 ms virtual latency; cumulative ack; watchdog; rollback | that the card is *visibly* gone within a frame and a return is not a teleport: M-13 |
| CARD-15 | a single tap emits nothing (zero-send assertion and a first-tap-commit mutant) | the fumbled fast double-tap, which **D-03 deliberately does not prevent**: M-13, M-17 (D-04-14) |
| CARD-16 | D-15 gating, the shipped 80 deci proven to reach `IdleClock`, 3 strikes, reset, bench via `Benched`, uniform choice, D-35 with a reachable mutant | whether 8.0 s is right for humans: **V-35 / M-07, open since Phase 2**; plus the **owner decision D-04-13** (realised window (7.9, 8.1] s vs a locked 8.0 s) |
| CARD-17 | the 1.5 s cap, yield cancellation, input during the flight, the F8 scans over all five input kinds | that it *reads* as a starting gun, and the audio existing at all: M-16, M-17. **The feel half is open** |
| CARD-19 | 50 distinct identity keys and 50 distinct drawn assets; colour absent from every key | spade vs club at 16 px in greyscale: M-14 (the legibility half), M-16 |
| UX-01 | every interactive rect >= 48 physical px at four viewports and the 0.85 floor | 48 px on glass and thumb reach: M-12. **Not met by any plan** |
| UX-02 | `hide`/`restore` order and idempotence; the `src/`-wide forbidden-identifier scan; the seat-hold pure core | **whether any of it works on a device, under both IAS settings: M-11, the phase's highest-risk row.** The cheat-client cell is four separate attempts and ticking on (a) alone is forbidden. **Not met by any plan** |
| UX-03 | inset containment; the `ScreenInsets` constant end to end; 58% table region | notched-device behaviour and the strip at `PreferredTextSize = Largest`: M-12. **Not met by any plan** |
| UX-04 | the input-kind map over 22 names; 20 complete hint cells within the cap | the gamepad column, V-27 unverified: M-11. **Not met by any plan** |

## Success criteria

| # | ROADMAP criterion | Machine | Human |
|---|-------------------|---------|-------|
| 1 | tap selects, second tap sends, an accidental single tap never sends | reducer logic and the zero-send assertion | feel; the fumbled double-tap: M-13, M-17 |
| 2 | own five cards, only others' pile depths, immediate at 150-300 ms | owner-only `Sync`, `Depths` counts-only, virtual-latency convergence | on-glass depth rendering: M-12; immediacy: M-13 |
| 3 | phone landscape, >= 48 px, controls hidden, safe areas, hints match input | geometry, hint table, control-seam order | **M-11, M-12, M-15: none of it is machine-closable** |
| 4 | idle seat auto-passed in the timeout, benched through the same removal path | essentially all of it (subject to V-35 and D-04-13) | none required beyond V-35 |
| 5 | distinct starting-gun moment; faces legible for a colour-blind player | the 1.5 s cap, key/asset injectivity | M-14, M-17 |

**Four of the five criteria (1, 2, 3, 5) have a device-dependent half, and criterion 3 is entirely
human-gated. Only criterion 4 is essentially machine-closed. This phase cannot be called complete on
a green suite.**

## Sign-off notes (plan 04-20)

`nyquist_compliant: true` is set because every one of the eleven requirement rows has a named
automated gate, a named human gate, or both, and no 3 consecutive tasks lacked an automated verify.
**That is a statement about sampling continuity, not about the phase being done**: it is compatible
with, and does not override, the open device matrix. The un-ticked item below is the one place the
file declines to claim more than it can show.

---

## Validation Sign-Off

Ticked by plan 04-20 on 2026-11-07. A line is ticked only where it can be shown; the rest carry the reason.

- [x] All tasks have an `<automated>` verify or a Wave 0 dependency
- [x] Sampling continuity: no 3 consecutive tasks without an automated verify (every plan summary records a suite run and, from wave 3, a `verify.luau` run)
- [x] Wave 0 covers every MISSING reference (RecordingPublisher, `tests/card`, the `rankOf` zone entry, the M-11..M-17 rows)
- [x] No watch-mode flags
- [x] Feedback latency < 3 s per task (`tests/card` root: 0.54 s for 186 cases)
- [ ] Every gate in the mutation table has a clean control **and** a non-vacuity assertion -- **NOT ticked.** 27 of 27 rows (+2) have recorded red output, but the ledger found 3 live structurally-incapable assertions (I1, I2, I3), 5 never-written ones (N1-N5), and 4 stated counts that do not match the specs (F1, F2, F4, F5). See the Mutation ledger
- [x] Suite runtime: the **controlled phase-wide pre/post** is +1.24 s against +3.00 s (23.65 s -> 24.89 s, 657 -> 858 cases), headroom 1.76 s. This plan's own three absolute readings were 25.47 / 25.23 / 25.70 s, which are above the 23.5 s target but not evidence of a breach: the pre-phase tree itself read 23.65 s under the same conditions, and the load warning above says the delta, not the absolute, is the gate. No cut was made to any mutation, non-vacuity assertion or clean control
- [x] Device rows written to `MANUAL-CHECKS.md` before execution, not after (plan 04-02)
- [x] `nyquist_compliant: true` set in frontmatter -- justified in the Sign-off notes: it records sampling continuity, **not** a complete phase

**Approval:** **NOT APPROVED. Phase 4 is not complete.** M-11, M-12, M-13, M-14, M-15 and M-17 are unsigned, and
UX-01, UX-02, UX-03 and UX-04 are met by no plan. The phase closes when a human signs those rows.
