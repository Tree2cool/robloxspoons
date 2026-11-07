---
phase: 04-live-card-table
plan: 10
subsystem: card-table
tags: [flourish, CARD-17, CARD-18, D-30, D-32, F8, pure-zone]
requires: [04-01, 04-04]
provides: [src/shared/Card/Flourish.luau, tests/card/flourish.spec.luau]
affects: [04-11, 04-19, Phase 7]
key-files:
  created: [src/shared/Card/Flourish.luau, tests/card/flourish.spec.luau]
decisions:
  - "Surface gained destroyOffenders so a mid-flight scan finding stops sinking input immediately, not at the cut-off"
metrics:
  tests: "tests/card 75 passed in 0.08 s (min of 3); full suite 747 passed"
---

# Phase 4 Plan 10: Flourish driver Summary

Pure-zone fixed-duration driver: teardown and a 0.25 s periodic scan are armed before `play` is spawned, the registry/Surface/Scheduler are injected, and Deal is constrained to a ScreenGui with DisplayOrder 5 under the hand's 10.

## Measured

- `tests/card`: 75 passed, 0 failed, 0.08 s on all three readings (allocation 2.09 s).
- Full suite: `747 passed, 0 failed, 0 todo in 23.94s`.
- `scripts/verify.luau`: `verify: all 14 automated steps passed in 27.3s`, exit 0.
- Scans per flight, asserted `>= floor(1.5/0.25) = 6`: **7** measured (`F8 scans per flight ...: 7`). FakeScheduler floors 0.25 s to 2 deci, so scans land at 0.2, 0.4 ... 1.4 s.
- A mid-flight object appearing at 0.5 s is detected at 0.6 s (deci 6, asserted <= 7).

## Mutation results (all watched red, then restored; clean control in the same case)

Source edits to `Flourish.luau`:

1. Teardown timer removed (delay x1000): 6 failures. `(a) ... not destroyed at exactly 1.5 s: an off-by-one late (expected 1, got 0)`; `(b) teardown did not land at 1.5 s (expected 1, got 0)`; `(d)`, `(e)`, `(f) clean control: the real driver must land at 1.5 s`, throwing-flourish case.
2. Teardown armed AFTER play (block moved after spawn): 1 failure, `the call order is ... only 1 timers armed when play was entered`. **Only the ordering case catches a source reorder**: with a spawn that returns at first yield, (b) still passes. The behavioural half is covered by an injected inline-play mutant in `(f)` (teardown never lands while the flourish yields).
3. Periodic scan never armed: 3 failures, `F8 ... violation detected at deci 15, not by 0.75 s`; ordering case `only 1 timers armed`; `(f) expected 3 mutations exercised (expected 3, got 2)` (cascade, see below).
4. Extra: diff skipped: `(e) diff finding not reported`. destroyOffenders skipped: `(e) offenders not destroyed` and F8 case.

Injected (in-spec) mutants: cut-off removed (delay of exactly 1.5 s dropped), cut-off armed after play (inline), no periodic scan (0.25 s delay dropped). Counter asserts 3.

## Deviations

- **[Rule 2] Surface gained `destroyOffenders(root) -> number`.** The contract had `scan` return descriptions only, so "the offending instance is destroyed" was unimplementable and a mid-flight finding would only be reported, not stop sinking input. Plan 04-19 must implement it.
- **[Rule 3] Void `pcall` helper (`attempt`).** `verify.luau`'s standard-platform typecheck rejected `local ok, err = pcall(voidFn)` ("Function only returns 1 value"); `tests/run.luau` did not. Wave-2 finding confirmed.
- Spec-lock for rule 1 reads the driver source and asserts its only require is `../Config/Card` and none names shop/cosmetics.

## Gate weaknesses recorded

- The "3 mutations exercised" counter is order-dependent module state: when the F8 case fails first, the (f) assertion fails too as a cascade. Harmless, but a failure there is not an independent signal.
- Source-reorder mutation 2 is caught by exactly one case (ordering via `pending()` inside `play`).

## Shipped types (04-19 and Phase 7 implement against these)

```luau
export type Kind = "Deal" | "Completion"
export type Root = any
export type FlourishContext = { root: Root, kind: Kind, seat: number, isLocalSeat: boolean, durationSeconds: number, faces: { number } }
export type Entry = { kind: Kind, play: (ctx: FlourishContext) -> () }
export type Surface = {
	createRoot: (kind: Kind) -> Root,
	destroyRoot: (root: Root) -> (),
	scan: (root: Root) -> { string },
	destroyOffenders: (root: Root) -> number,   -- ADDED
	snapshot: () -> any,
	diff: (snapshot: any) -> { string },
	destroyEscaped: (snapshot: any) -> number,
}
export type Scheduler = {
	nowDeci: () -> number,
	delay: (seconds: number, fn: () -> ()) -> () -> (),
	spawn: (fn: () -> ()) -> Thread,
	cancel: (thread: Thread) -> (),
}
```

Note `tests/harness/FakeScheduler` has no spawn/cancel; the spec wraps it with coroutine-based ones locally (coroutine is banned only in the pure zone).

Scan breadth: the driver calls `Surface.scan` and trusts it; the five input-taking kinds are plan 04-19's Surface responsibility and are NOT proven here.

## Accepted limits

A synchronous infinite loop in `play` cannot be stopped in Luau, and "every parent a flourish could reach" cannot be enumerated (snapshot/diff is a scan, not a proof). Feel of the starting gun is M-17; audio asset ids are M-16 (D-33: empty id silent) and are not claimed here.

## Commits

- 73a4fef feat(04-10): driver
- test(04-10) commit: spec plus typecheck fix to the driver

## Self-Check: PASSED
