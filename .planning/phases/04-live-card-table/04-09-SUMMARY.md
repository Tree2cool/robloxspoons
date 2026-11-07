---
phase: 04-live-card-table
plan: 09
subsystem: client-prediction
tags: [prediction, reconciliation, pure-zone, CARD-02, CARD-14, CARD-15]
requires: [04-01, 04-03, 04-04]
provides: [src/shared/Card/Prediction.luau, tests/card/prediction.spec.luau]
affects: [04-14, 04-16, 04-17, 04-18]
tech-stack:
  patterns: [closure-record reducer, auth + pending fold, cumulative ack, age watchdog]
key-files:
  created:
    - src/shared/Card/Prediction.luau
    - tests/card/prediction.spec.luau
decisions:
  - "Open Question 5: watchdog rolls back locally, no Resync intent; server push on onReject is primary"
  - "The fold skips a predicted action the server is certain to reject (Pass unless hand 5, Draw unless hand 4 and inbox >= 1)"
  - "Change.Removed carries cardId: number? so a rolled-back Draw placeholder can be Removed"
metrics:
  tasks: 2
  completed: 2026-11-07
---

# Phase 4 Plan 09: Prediction and reconciliation Summary

A pure reducer over `auth + pending[]` with a cumulative `ackSeq` and a pending-age watchdog; the second tap on the same card commits, nothing else ever emits, and a rejection, a correction and a lost message are the same reason-free `Returned`.

Commits: `54f04c0` (Prediction.luau), `5693f3d` (prediction.spec.luau).

## Measured results

- `tests/run.luau -- --root tests/card`: `77 passed, 1 failed` before the test-side fix, then `77 passed, 0 failed, 0 todo in 0.09s / 0.10s / 0.11s` over three runs (tests/card is well inside its 2.09 s allocation).
- Full suite `tests/run.luau`: `749 passed, 0 failed, 0 todo in 24.14s` (wall clock is container noise; compare case counts).
- `scripts/verify.luau`: exit 0, all 14 stages ok, including Typecheck (standard platform), Structural guards and Tests.
- stylua, selene, selene.pure.toml and check-guards clean. `grep rankOf src/shared src/client` prints nothing.
- **Fuzz:** `prediction fuzz: iterations=30 steps=1230 emits=73 returned=23 removed=23 lostSends=10 forced=15 elapsed=0.007s` (budget 0.3 s; measured 0.006-0.007 s on three runs). Non-vacuity asserted inside the final iteration: emits, rollbacks, forced passes and lost sends are all > 0, and elapsed < 0.3 s.

## Shipped type text (plans 04-16 / 04-17 / 04-18 build against this)

```luau
export type Change =
	{ kind: "Added", cardId: number? }
	| { kind: "Flipped", cardId: number }
	| { kind: "Returned", cardId: number }
	| { kind: "Removed", cardId: number? }

export type Emit = { name: "Draw" | "Pass", payload: { [string]: number } }
```

`Prediction.new(pendingTimeoutDeci)`; plan 04-18 passes `Card.PENDING_TIMEOUT_SECONDS * 10`. `tapRightPile` takes `nowDeci` as in the interface. All other signatures are exactly as in the plan.

## Open Question 5, restated

Local rollback, no `Resync` intent. A gateway-level reject never reaches the card core, so its seq is never acked individually; the primary mechanism is the server pushing a `Sync` carrying the current `ackSeq` from the existing `onReject` sink (plan 04-14), which resolves pending cumulatively. `tickWatchdog` is the backstop for a genuinely lost message: an entry older than the timeout is dropped and the fold re-run, emitting `Returned` for a Pass and an id-less `Removed` for a Draw placeholder. A dropped entry leaves `pending`, which is what stops re-firing. Trade-off accepted: a merely slow Sync can make a card return and then leave again.

## Mutations, watched red

Every spec mutation is an injected broken reducer run through the same scenario as its clean control, with the real reducer asserted green in the same case. Verbatim output:

```
MUTATION: onSync does not drop acked pending -> red: pending not resolved at 0.2s (expected 0, got 1)
MUTATION: watchdog never fires -> red: the watchdog did not roll the lost message back (expected 1, got 0)
MUTATION: tapSlot commits on the first tap (firstTapCommits) -> red: a single tap emitted an intent (expected nil, got table: 0x000055580e41a950)
MUTATION: payload carries a to key and a hand index -> red: payload key set (rule 7: no seat, no target, no index) (expected cardId,seq, got cardId,index,seq,to)
MUTATION: a Pass naming a nil-id placeholder is allowed -> red: a Pass naming a placeholder was emitted (expected nil, got table: 0x000055580e536470)
```

I also edited the PRODUCTION file one line at a time (restored byte-identical afterwards, `cmp` confirmed) and ran the card suite:

| Production mutant | Result |
|---|---|
| `onSync` keeps all pending | 5 failures: happy path `pending not resolved at 0.2s (expected 0, got 1)`, cumulative ack `A: pending not resolved by the single cumulative ack (expected 0, got 3)`, forced pass, rejection, and the mutation case's clean control |
| watchdog dead | 4 failures incl. `the watchdog did not roll the lost message back (expected 1, got 0)` and fuzz `pending 1 after the drain` at iteration 2 |
| first tap commits | 5+ failures incl. `a single tap emitted an intent`, `the second tap on the same card did not commit`, `three intents in flight (expected 3, got 1)` |
| payload gains `index` | 3 failures incl. `payload key set ... (expected cardId,seq, got cardId,index,seq)` and fuzz `emitted keys cardId,index,seq` |
| nil placeholder passable | 3 failures incl. `a Pass naming a placeholder was emitted` and fuzz `Pass without a cardId` |
| hand-4 slots tappable (F6) | 1 failure: `second emit at hand 4 (expected nil, got table)` |
| stale Sync not ignored | 1 failure: `a stale Sync returned changes` (9 Added/Removed entries) |

Note the fuzz (not just the dedicated case) catches the dead watchdog, the payload key and the nil-placeholder mutants, which is the intended defence in depth.

## Deviations from Plan

**1. [Rule 1 - design gap] `Change.Removed.cardId` is `number?`.** The plan says the watchdog emits `Removed` "for the placeholder of a Draw", but its type text has `Removed { cardId: number }` and a placeholder has no id. Making it optional is the minimal fix; `Added` already had the same shape. Plans 04-16/17/18 must handle a `Removed` with no id as "a face-down placeholder leaves".

**2. [Rule 1 - invariant] The fold skips predicted actions the server is certain to reject** (Pass unless display hand is 5; Draw unless hand is 4 and inbox >= 1). Without it, a server-initiated removal landing while my own Pass is in flight (forced pass leaves auth at 4, pending Pass would take the display to 3) breaks the plan's own fuzz invariant "hand is 4 or 5". Consequence recorded in case 11: in that race the card of my doomed Pass returns as soon as the forced-pass Sync lands (before its own ack), while the forced card is `Removed` and the pending entry is untouched until acked. The plan's "forced card produces Removed, pending untouched" holds exactly; a `Returned` for my own doomed Pass is additional and is truthful (the server will reject it with HandNotFive). Valve forcing and a player's own Pass are mutually exclusive in the engine, so this only occurs in the race window.

**3. Case 9 uses Pass, Draw, Pass rather than two Passes.** Two Passes before any Sync are impossible because F6 makes slots inert at hand 4. The interleaved script exercises the same cumulative-ack property and both orderings (reject first; reject last).

**4. Case 11 is split in two** (selection-clear + Removed with no pending; then pending Pass in flight) because F6 makes it impossible to hold a selection while a Pass is pending.

No STATE.md, ROADMAP.md or REQUIREMENTS.md changes and no `requirements.mark-complete`, per the brief. SUMMARY committed alone.

## Known limits (not defects)

- D-03 residual stands: a fumbled fast double-tap on one card sends it. No debounce exists and none should be added.
- Virtual time proves convergence, not feel. The card being visibly gone within a frame, and the return reading as a smooth motion, remain M-13 / M-17.
- The "correction" case is hand-crafted (an `onSync` with a reordered hand and different inbox) because the stub server has no real correcting path; the reducer-level identity with a rejection is what is asserted.
- `ackSeq` restarting at a new round is not handled here (a new round needs a new reducer or a round-start reset); plan 04-18 should construct a fresh reducer per round.

## Self-Check: PASSED

- src/shared/Card/Prediction.luau: FOUND
- tests/card/prediction.spec.luau: FOUND
- commits 54f04c0 and 5693f3d: FOUND
