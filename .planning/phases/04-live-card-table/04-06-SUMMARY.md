---
phase: 04-live-card-table
plan: 06
subsystem: server-core
tags: [afk, idle-clock, card-16, d-13, d-14, d-15, d-17, d-35]
requires: [04-01, 04-02]
provides: [IdleClock.new, IdleClock.legal, IdleClock.pickUniform]
affects: [04-12 CardTable, 04-14 CardService]
key-files:
  created: [src/server/core/IdleClock.luau, tests/card/idle.spec.luau]
decisions:
  - "Hand-4 expiry is a Strike with no card movement; the Command union has no auto-draw variant (D-35)"
  - "Strike bookkeeping is shell state beside the engine"
metrics:
  tasks: 2
  completed: 2026-11-07
---

# Phase 4 Plan 06: IdleClock Summary

Pure-zone AFK clock: per-seat deadline and strikes, the D-15 legal-action predicate, a uniform auto-pass pick,
and a `Command` union (`AutoPass | Strike | Bench`) with no auto-draw variant. `autoPassDeci` and `maxStrikes`
arrive through `Deps`; this file performs no seconds-to-deciseconds conversion.

## Commits
- feat: IdleClock core (`src/server/core/IdleClock.luau`)
- test: CARD-16 gate (`tests/card/idle.spec.luau`, 14 cases)
- fix: typed command lists in the spec (found by `scripts/verify.luau`'s standard-platform typecheck, not by the unit run)

## Measured
- `tests/card`: 19 passed, 0 failed in 0.02 s (readings 0.02 / 0.02 / 0.01 s), far inside the 2.09 s allocation.
- Full suite: 691 passed, 0 failed, 24.47 s. `scripts/verify.luau`: all 14 automated steps passed.
- `check-guards: ok (102 files, 292 requires, 25 guarded roots)`; selene (shipped and pure configs) 0 errors; analyze ok.
- D-15 ramp case: `idle D-15 ramp: 100 ticks, 0 commands`.
- D-14 uniformity (seeded `Rng.new(1000003)`, 5000 draws): counts `985,976,1017,1031,991`, 0.0007 s.

## Mutations (each run against the real spec, restored afterwards; all went red)
Source mutations on IdleClock.luau (failing case names shown):
- predicate without inbox condition: 4 failed (empty-inbox ramp, predicate table, pauses-and-keeps, mutation case)
- predicate hand-4 only: 9 failed
- strikes never reset: `FAIL D-17: any real player action resets...` and `FAIL MUTATION: a strike that does not reset...`, 2 failed
- hand-4 expiry also emits AutoPass: `FAIL D-35: a hand-4 expiry emits a Strike and NOTHING else, ever` and `FAIL MUTATION: a clock that auto-draws at hand 4...`, 2 failed
- pickUniform returns lowest card: `FAIL D-14: ... uniform` and `FAIL MUTATION: a greedy pick...`, 2 failed
- window refreshed on every sync: `FAIL a card arriving in an idle seat's inbox does not refresh its window`, 1 failed
- strikes cleared on pause: `FAIL becoming illegal pauses the clock and KEEPS the strike record`, 1 failed
- Bench never emitted: 2 failed
- `autoPassDeci = 81` (Deps in the spec): 8 failed, including `FAIL a hand-5 seat expires at exactly +80 deci`

Injected mutants inside the spec (caught, assertion green): AutoPass-at-hand-4, a `Draw` kind, a command carrying
`cardId` all reported by `noCardMoved`; greedy `pickLowest` reports 5000 picks of card 11; `autoPassDeci = 81`
does not fire at +80; too-wide predicate fails the `(4,0)` row (also injected at clock level as a view rewrite
that makes the 100-tick ramp emit commands); hand-4-only fails `(5,3)`; reset-less wrapper fails `resetProblems`.

## Deviations
- [Rule 1] Luau inferred `owes` as `string` after the `== "Pass"` comparison in `tick`; added a typed local `owed: Owes`.
- [Rule 3] `analyze.luau` invoked with `--ignore '**/fixtures/**'` is refused by the sandbox; ran it without `--ignore`
  (passes), and the full `scripts/verify.luau` passes.
- Added a clock-level view-rewrite mutant for D-15 (beyond the plan) so the 100-tick ramp assertion is itself proven able to fail.

## Notes
- No gate was found structurally unfireable; every mutation above was observed red.
- `Bench` and `AutoPass` carry no card: CardTable (04-12) calls `pickUniform` and turns `Bench` into `Remove{cause="Benched"}`.
- V-35 / M-07 remains open: 8.0 s is not validated for real humans. Realised window is [7.9, 8.0] before the 10 Hz sweep, about 8.1 s after; `autoPassDeci = 79` decision belongs to plan 04-20.
- STATE.md, ROADMAP.md, REQUIREMENTS.md untouched per instructions.

## Self-Check: PASSED
