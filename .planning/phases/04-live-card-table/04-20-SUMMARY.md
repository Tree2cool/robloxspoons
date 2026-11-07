---
phase: 04-live-card-table
plan: 20
subsystem: phase-gate
tags: [validation, mutation-ledger, manual-checks, deferred-items, verification-debt]
requires: [04-01 .. 04-19]
provides:
  - completed 04-VALIDATION.md (per-task map, mutation ledger, requirement split, sign-off)
  - deferred-items.md (D-04-01 .. D-04-30)
  - Verification Debt rows V-12/13/24/25/26/27/34/35 updated
  - MANUAL-CHECKS.md Phase 4 blocking block
affects: [Phase 5, Phase 6, Phase 7, Phase 8]
key-files:
  created: [.planning/phases/04-live-card-table/deferred-items.md, .planning/phases/04-live-card-table/04-20-SUMMARY.md]
  modified: [.planning/phases/04-live-card-table/04-VALIDATION.md, .planning/research/SUMMARY.md, .planning/research/ARCHITECTURE.md, MANUAL-CHECKS.md, src/shared/Config/Card.luau]
decisions: []
metrics:
  tasks: "3 of 4 automatable tasks done; 3 owner checkpoints open (AFK deadline, device matrix) -- budget checkpoint closed as settled"
  completed: 2026-11-07
---

# Phase 4 Plan 20: the phase gate Summary

**Phase 4 is NOT complete: it closes only when a human signs M-11, M-12, M-13, M-14, M-15 and M-17 in `MANUAL-CHECKS.md`; the suite is green (858/0/0, `verify.luau` 14/14, `check-guards` ok) but UX-01, UX-02, UX-03 and UX-04 are met by no plan.**

## Budget: settled, holds

The controlled phase-wide pre/post in `04-BUDGET-LOG.md` (23.65 s at 657 cases to 24.89 s at 858)
is **+1.24 s of the +3.00 s allowance, 1.76 s of headroom**. This plan's own readings, 25.47 / 25.23 /
25.70 s (min 25.23), sit ~0.3 s above the post-phase figure and do not contradict it; the pre-phase
tree itself read 23.65 s under the same conditions, so the 23.5 s absolute target is superseded by the
delta method. `tests/card` is 0.54 s for 186 cases against a 2.09 s allocation. No owner decision.
One allocation miss recorded: the four guard fixture roots were allocated ~0.20 s and the budget log
attributes ~0.9 s to wave 1; absorbed because the in-process specs cost little.

## Mutation ledger (first line of the section in 04-VALIDATION.md)

27 table rows + 2 rows the table lacked = 29 gates. Red output recorded: 29/29. **Holes: 5
never-written, 0 never-run, 3 structurally incapable of firing (live)**, plus 4 incapable-as-written
and fixed before shipping. 8 live holes.

- Never written: N1 the literal bench-`Completed` mutant (type error; monkeypatch declined, not
  impossible), N2 sinks-after-publish order, N3 the service-layer wiring (`CardService`, `Main.server`,
  `CardSeatHold` call sites; one source-scan gate is the follow-up), N4 review-only timer paths, N5 the
  per-message Depths truth check.
- Structurally incapable: I1 `privacy.spec` RoundEnd "payload carries no key" and its "mutant" (both
  over literals the test authors; `round_end.spec` is what really covers it), I2 the D-20 healthy
  control cannot separate 96 from 48, I3 04-16's "no string literal" check is really "no literal with a
  space".

### Count mismatches found (plan prose NOT edited)

| Stated | Actual |
|--------|--------|
| 04-12 "fourteen mutations" | 11 in-spec at its close (5 privacy + 6 cardtable); 10 source-edit recorded. The tree reads 14 now only because 04-19 added 3 Depths mutants: coincidence |
| 04-12 summary task "all nine" | 11 / 10; matches the source list only if the crude #10 is dropped. Two different numbers in one plan, both wrong |
| privacy "drives 5" / "five leaks" | correct (`t.equal(mutations, 5)`), for that one case |
| 04-06 `grep -c 'MUTATION:'` "at least 5" | **4**: the acceptance grep as written fails (7 in-spec mutants, 9 source mutations; property holds) |
| 04-08 "assert 8" | 8 rows is right; 9 distinct designs, 12 `red()` calls; the `grep -q 'assert 8'` is satisfied by the assertion's own message string and could never fail; the counter is unconditional |

Spot-check: plan 04-20 re-ran two source mutations (`Layout.STEP` 60 -> 44; `assertPublic` removed
from `makePublisher.toAll`); each turned `tests/card` red with 3 failures, and the tree was restored.
Everything else in the ledger is the executors' recorded output, not re-run.

## Honest requirement split

| Req | Machine-proven | Human-gated |
|-----|----------------|-------------|
| CARD-02 | one `Pass` per second tap; hit geometry | feel: M-13, M-17 |
| CARD-13 | owner-only Sync, recursive leak walk, 5 leak mutants, `Depths` counts-only | M-12 two real clients; **depth data path exists, on-glass half does not** |
| CARD-14 | convergence at 150/300 ms virtual, cumulative ack, watchdog | M-13 |
| CARD-15 | zero-send on single tap, first-tap-commit mutant | double-tap residual (D-03 / D-04-14): M-13, M-17 |
| CARD-16 | D-15 gating, 80 deci reaches `IdleClock`, 3 strikes, bench, uniform pick, D-35 | **V-35 / M-07 open; D-04-13 owner decision** |
| CARD-17 | 1.5 s cap, yield cancel, input during flight, F8 scans (5 kinds) | feel and audio: M-16, M-17 |
| CARD-19 | 50 keys, 50 assets, no colour in a key | legibility: M-14 |
| UX-01 | 48 physical px at 4 viewports + 0.85 floor | glass and thumb reach: M-12; **no plan meets it** |
| UX-02 | hide/restore order, `src/` scan, hold pure core | **M-11, highest risk; no plan meets it** |
| UX-03 | inset containment, 58% region | notch, Largest text: M-12; **no plan meets it** |
| UX-04 | input-kind map, 20 hint cells | gamepad column (V-27): M-11; **no plan meets it** |

`requirements.mark-complete` was NOT run.

## Deviations from plan

1. **STATE.md not edited (instruction from the orchestrator).** Task 3A's "Carried into Phases
   5/6/7/8" section is not written; the carry facts are in `deferred-items.md` (D-04-13, 14, 17, 18,
   26) and below, for the orchestrator to place. Facts to carry, none new beyond the plan's list plus:
   the set-79 blast radius is **five test sites plus the call site** (the plan said four), and the
   call site's first argument is the locked constant `CardPool.AUTO_PASS_MAX_SECONDS`, so 79 is not a
   one-argument tweak; `ROADMAP.md` line 175 still says CardTableView.
2. **Per-spec wall times not individually remeasured**: `tests/run.luau` prints only the suite
   figure and `--filter` is forbidden. The root time (0.54 s vs 2.09 s) and the per-plan figures from
   the summaries stand in.
3. **Stale reference**: `CardTableView` -> `CardSeatsView` in a comment in `Config/Card.luau` and in
   `research/ARCHITECTURE.md` (2 lines). `ROADMAP.md:175` is left for the orchestrator. The local
   variable `CardTableView` inside `CardSeatsView.luau` is code and was not touched.
4. **MANUAL-CHECKS.md already had a blocking paragraph** (from 04-02); a table of what each failure
   means was added beneath it. Nothing ticked.

## Checkpoints open for the owner

1. **AFK deadline (D-04-13), genuine decision:** keep 80 / set 79 / widen the requirement. See the
   arithmetic in `deferred-items.md`.
2. **Device matrix:** M-11 (four separately recorded cheat-client attempts; (a) alone forbidden),
   M-12, M-13, M-14, M-15, M-17.
3. Budget: closed, no decision needed.

## Self-Check: PASSED

Files present: `04-VALIDATION.md`, `deferred-items.md`, this file. Commits `2ca7454`, `1b88f67`,
`d04d30d`, `716e455`, `d8302bc` present. After the edits: full suite `858 passed, 0 failed, 0 todo`,
`verify.luau` all 14 steps, `check-guards: ok (145 files, 436 requires, 36 guarded roots)`; grep
checks for `rankOf`, `GetControls`, `FireClient` are empty; zero `[x] M-1[1-7]`.
