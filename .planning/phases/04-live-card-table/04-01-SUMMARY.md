---
phase: 04-live-card-table
plan: 01
subsystem: card-table-wave0
tags: [test-fake, config, spec-lock, privacy, timing]
requires: []
provides:
  - tests/harness/RecordingPublisher.luau (recording Publisher fake, injectable leak)
  - src/shared/Config/Card.luau (all Phase 4 tunables, seconds)
  - src/server/core/CardTiming.luau (autoPassDeci pure conversion)
  - tests/card/config_lock.spec.luau
affects: [04-05, 04-06, 04-07, 04-10, 04-12, 04-14]
key-files:
  created:
    - tests/harness/RecordingPublisher.luau
    - src/shared/Config/Card.luau
    - src/server/core/CardTiming.luau
    - tests/card/config_lock.spec.luau
  modified:
    - tests/harness/modules.spec.luau
decisions:
  - "Mutation inputs use (0.07, 100) / (0.14, 100), not the plan's (0.7, 10), because 0.7*10 is exactly 7.0 in IEEE double"
metrics:
  completed: 2026-11-06
  tasks: 3
  files: 5
---

# Phase 4 Plan 01: Wave 0 fake, config and spec-lock Summary

RecordingPublisher with an injectable broadcast-leak mode, `Config/Card.luau` holding every Phase 4 tunable, and a pure `CardTiming.autoPassDeci` that a spec drives directly, pinned by `tests/card/config_lock.spec.luau`.

## Commits
- `1b72c80` test(04-01): RecordingPublisher + 3 self-test cases
- `81784c0` feat(04-01): Config.Card and CardTiming
- `181ed2f` test(04-01): config_lock spec

## Shipped signature (plans 04-12 and 04-14 build against this)

```luau
CardTiming.autoPassDeci(maxSeconds: number, decisPerSecond: number): number
-- floor(maxSeconds * decisPerSecond + 1e-9); errors by name on non-finite/non-positive maxSeconds
-- and on non-finite, non-positive or non-integer decisPerSecond
```
`autoPassDeci(8.0, 10) == 80`. `RecordingPublisher.new({ leak = true })` records every `toPlayer` as `method = "toAll", userId = nil`, silently.

## Observed red output (mutations watched fail, then restored)

Leak (clean assertions run against `RecordingPublisher.new({ leak = true })`, via a throwaway spec, deleted):
```
FAIL SCRATCH: clean assertions against leak=true publisher
     expected toPlayer, got toAll
```
Conversion changed to `math.ceil(maxSeconds * decisPerSecond)`:
```
FAIL ...MUTATION: a naive conversion exceeds the ceiling where the real one cannot
     real conversion exceeded the ceiling for (0.07, 100) (expected a truthy value, got false)
```
Epsilon removed (bare floor):
```
FAIL ...MUTATION: ...
     the epsilon rescues the undershoot (expected 29, got 28)
```
Epsilon replaced by `+ 1.0` (the "81" mutation):
```
FAIL ...the SHIPPED conversion lands on 80 and can never exceed the ceiling (D-13, rule 5)
     shipped auto-pass is 80 deciseconds (expected 80, got 81)
FAIL ...MUTATION: ...  real conversion exceeded the ceiling for (8, 10)
```
`CardPool.AUTO_PASS_SELECTION` changed to `"worst-card"`:
```
FAIL ...Gate G1 constants are at their locked positions
     selection rule is a Gate G1 constraint (D-13, A7-CORRECTION) (expected uniform-random-from-hand, got worst-card)
```
Mutations on shipped source were done by temporary edit (the shipped function cannot be injected into itself); each was reverted with `git checkout -- <file>`.

## Measured
- Full suite: `665 passed, 0 failed, 0 todo in 28.07s` (baseline 657 / 20.53 s; +8 cases = 3 harness + 5 card). The wall-time rise is machine load (verify.luau's entire 14-step run took 30.0 s); the new work is in-process arithmetic and takes ~0.01 s. Later plans should compare case count, not seconds, against this.
- `scripts/verify.luau`: all 14 automated steps passed. stylua, selene, check-guards (101 files) clean.

## Deviations from Plan

**1. [Rule 1 - Bug in plan] The plan's mutation example does not violate the ceiling.**
`0.7 * 10` is exactly 7.0 in IEEE double, not 7.000000000000001, so `math.ceil` gives 7 and the first run of case 3 failed its own non-vacuity assertion ("inputs driven: 5, naive violations: 0"). That is the gate doing its job. Fix: the mutation table now includes `(0.07, 100)`, `(0.14, 100)`, `(0.29, 100)` (`0.07*100 = 7.0000000000000009`); direct asserts are `autoPassDeci(0.07,100)==7` and `naive(0.07,100)==8`. `(0.7,10)==7` is still asserted but is no longer claimed to separate real from naive. The epsilon's real job is the opposite direction: `0.29*100 = 28.999999999999996`, so a bare floor returns 28; asserted `autoPassDeci(0.29,100)==29`.

**2. [Rule 1] Ceiling predicate needed a tolerance.** The real function returns 29 for `(0.29,100)` while the float product is 28.999999999999996, so the strict `<=` predicate flagged the correct answer. The predicate now compares against `seconds*perSecond + 1e-6`; a one-deci overshoot (what ceil does) still fails. The claim "can never exceed seconds*perSecond" holds for the decimal product, up to a few ulp in float.

No ceiling gate can detect the bare-floor (undershoot) mutation; that is why the separate `== 29` assertion exists.

## Known Stubs
None. Audio ids in `Config.Card.AUDIO` are intentionally empty strings (human gate, silent by contract).

## Self-Check: PASSED
All four created files exist; commits 1b72c80, 81784c0, 181ed2f present.
