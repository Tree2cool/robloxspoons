---
phase: 02-card-engine-and-pacing-simulator
plan: 01
subsystem: engine
tags: [types, invariants, conservation, satisfiability, canonical-hash, mutation-proof, anti-livelock-valve]

requires:
  - phase: 02-03
    provides: "check-guards R3 bans on `coroutine` and `os.` inside pure zones and their require closure — the engine is born under CLAUDE.md rules 5 and 6"
  - phase: 01-02
    provides: "tests/run.luau + Test.Runner (assert-the-reason house rule), src/server/engine/Rng.luau"
  - phase: 01-03
    provides: "pure-zone enforcement (selene.pure.toml, luau-lsp --platform standard, R1/R3/R3b/R6)"
provides:
  - "src/server/engine/Types.luau — the one type vocabulary every engine module imports (16 exported types + 7 constants)"
  - "The anti-livelock valve's type surface up front: ValveState, the ValveForcedPass event, EngineConfig.antiLivelockValve, VALVE_ARM_ACTIONS_PER_SEAT, VALVE_SEEN_CAP"
  - "export type Violation — the locked violation vocabulary of Invariants.check, in its locked order, enforced by the typechecker"
  - "src/server/engine/Invariants.luau — circulation, expectedCirculation, satisfiable, hash, check"
  - "CARD-04 as a standing assertion: circulation == 4*(ranks - seatCount) + jokers + 4*churnRemovals, so 'the deck never runs dry' is `circulation >= 1`"
  - "tests/engine/invariants.spec.luau — 15 cases; 8 of the 9 locked violation names produced by a deliberate mutation, each asserting its own name"
affects: [02-04, 02-05, 02-06, 02-07, 02-08, 02-09, 02-11, 02-13]

tech-stack:
  added: []
  patterns:
    - "Derive one side of a conservation check INDEPENDENTLY by walking the real containers; never compare a cached field with itself (research Pitfall 4)"
    - "A locked return vocabulary declared as an `export type` singleton union, so a mistyped violation name is a build error rather than a test that silently stops matching"
    - "A violation ORDER that is itself locked by a test: the liveness row asserts that an actionless state reports `hand-size`, so a reorder fails by name"
    - "Mutation-prove a gate in BOTH directions: break the state and watch the check name it; break the check and watch the spec go red"

key-files:
  created:
    - src/server/engine/Types.luau
    - src/server/engine/Invariants.luau
    - tests/engine/invariants.spec.luau
  modified:
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Added a 16th exported type, `Violation`, carrying the nine violation names in the locked order. The plan's acceptance criterion asked for >= 16 `export type` lines while the interfaces block contained 15; rather than invent a filler type, the locked vocabulary the plan spends three paragraphs protecting was moved into the type system. `check` is annotated `(boolean, Types.Violation?)`, a strict narrowing of the published `(boolean, string?)`"
  - "`check` reports a live-seat COUNT desync as `ring-links` rather than adding a tenth name. `liveCount` gates checks 3, 4 and 9, so a desync would silently disable three invariants; the count of live seats is part of the ring's structure, not a free field"
  - "`liveness` (violation 3) is kept exactly where the plan put it and documented as a SUBSUMED tripwire. Once `hand-size` passes, every live hand holds 4 or 5 cards, so `circulation >= 1` forces a legal action to exist — research 3.1 Claim 3. It is therefore unreachable in that position, which a mutation proof confirms (M3 below). The order was NOT changed to make it reachable"
  - "The partition identity scans dead seats too (counters scan live seats only). A removed seat's cards must be ACCOUNTED FOR, which is Rule 8's 'never destroyed' stated as an assertion"
  - "`makeState` lays cards out with no shuffle — seat s receives all four copies of rank s — so every mutation below is pin-pointable. That deal is illegal under CARD-09, which `check` does not and must not care about: completion is detected on draw, by Engine"
  - "Joker modes are passed to the fixture as literals through a visitor rather than iterated out of a table: Luau widens a singleton-string literal table to `{ string }`, and the widened element no longer satisfies `JokerMode` at the call site (real TypeError, fixed in task 3)"

patterns-established:
  - "Two-way mutation proof as the standard for an invariant module: 8 state mutations (each naming its own violation) plus 14 implementation mutations (13 of which turn the suite red)"

requirements-completed: []
requirements-contributed: [CARD-04]

duration: ~1 session
completed: 2026-11-03
---

# Phase 2 Plan 01: Engine Types and Invariants Summary

**One shared type vocabulary for the whole card engine — including the anti-livelock valve's surface, declared three waves before it is implemented — plus an `Invariants` module whose circulation identity, four-bucket partition identity, O(1) satisfiability histogram and canonical state hash each derive one side independently and have each been watched failing, in both directions.**

## Performance

- **Tasks:** 3 of 3 (task 2 ran as a TDD RED/GREEN pair)
- **Files created:** 3; **modified:** 1 (`REQUIREMENTS.md`)
- **`--filter engine/invariants`:** `15 passed, 0 failed, 0 todo in 0.18s` (0.22s wall, `time` real)
- **`--filter engine`:** `57 passed, 0 failed, 3 todo in 0.33s`
- **Full suite:** `379 passed, 0 failed, 3 todo in 14.68s` (baseline at `168515e` was 336; +15 from this plan, +28 from wave sibling 02-02). Re-run after 02-02's later `Rng` warm-up fix landed: `380 passed, 0 failed, 3 todo in 14.92s`, this plan's 15 rows unaffected
- **`scripts/verify.luau`:** `verify: all 14 automated steps passed in 17.8s`
- **Todo count still 3**, as the plan requires; plan 02-11 drives it to 0.

## Task Commits

1. **Task 1: the shared type vocabulary and constants** — `09f561e` (feat)
2. **Task 2 (RED): failing invariant rows before `Invariants` exists** — `316c9dd` (test)
3. **Task 2 (GREEN): `Invariants` — circulation, partition identity, histogram, hash** — `d315c71` (feat)
4. **Task 3: mutation-prove every reachable invariant** — `73a3104` (test)

No REFACTOR commit: the GREEN implementation needed no cleanup.

## `Types.luau` export list, verbatim

Plans 02-04, 02-05, 02-06, 02-07, 02-09 and 02-13 build against exactly these names.

```
export type CardId = number
export type Rank = number
export type SeatId = number
export type PlayerId = number
export type JokerMode = "Wild" | "Blocker"
export type RemoveCause = "Completed" | "Disconnected" | "Benched"
export type EngineConfig = { ranks, jokers, jokerMode, antiLivelockValve }
export type ValveState = { ... }
export type Seat = { id, playerId, live, hand, inbox, next, prev }
export type Counters = { rankInPlay, jokersInPlay, cnt, completions, churnRemovals }
export type State = { config, seatCount, totalCards, rankOf, seats, liveCount, head,
                      retired, terminal, counters, valve }
export type Intent = Draw | Pass | Remove
export type Reject = "UnknownSeat" | "SeatNotLive" | "UnknownCard" | "NotYourCard"
                   | "HandNotFour" | "HandNotFive" | "InboxEmpty"
export type Violation = (the nine names below, in order)
export type Event = Drew | Passed | Completed | SeatRemoved | ValveForcedPass
export type ApplyResult = { ok: boolean, events: { Event }, reject: Reject? }
```

Constants (seven, all in the returned table):

```
JOKER_RANK = 0
HAND_SIZE = 4
MAX_HAND = 5
MAX_JOKERS = 2
MAX_DEAL_ATTEMPTS = 64
VALVE_ARM_ACTIONS_PER_SEAT = 48
VALVE_SEEN_CAP = 4096
```

The header carries the six points the plan specified, in order: pure zone (rules 2, 5, 6); card IDs
are shuffled deck positions so a leaked ID carries no rank (rule 3, Pitfall 6); `MAX_JOKERS = 2` is
load-bearing; `seatCount` is seated seekers; there is no `locked` flag and never may be; `valve` is
trajectory bookkeeping that `hash` and `check` must ignore.

## The `ValveState` shape (plan 02-13 implements it, 02-07 wires it)

```luau
export type ValveState = {
	rng: any, -- an Rng, derived in Engine.newRound so valve draws never perturb the deal
	actionsSinceProgress: number, -- reset by a completion or a removal
	armed: boolean, -- true once actionsSinceProgress passes VALVE_ARM_ACTIONS_PER_SEAT * liveCount
	seen: { [string]: true }, -- hashes observed since the last completion, removal or firing
	seenCount: number,
	firings: number, -- the first-class metric: a pool whose valve fires often is a bad pool
	seenResets: number, -- times VALVE_SEEN_CAP forced a restart of the window
	observations: number, -- one per SUCCESSFUL apply, none on a rejection (02-08 asserts this)
}
```

Nothing in this plan exercises the valve. `hash` provably ignores it, `check` never inspects it, and
`ValveForcedPass { seat, cardId, to, lap }` carries no hash (an event may cross the network boundary
in Phase 4; CLAUDE.md rule 3).

## The nine violation names, in the locked order

| # | name | condition |
|---|------|-----------|
| 1 | `hand-size` | some live seat has `#hand` outside {4, 5} |
| 2 | `ring-links` | a live seat's `next`/`prev` is not a live seat, the live-seat count disagrees with `liveCount`, or `head` is not live while `liveCount >= 1` |
| 3 | `liveness` | `circulation >= 1`, `liveCount >= 1`, and no live seat has a legal action |
| 4 | `circulation` | `liveCount >= 1` and `circulation(state) ~= expectedCirculation(state)` |
| 5 | `partition-count` | `#hands + #inboxes + #retired + #terminal ~= totalCards` |
| 6 | `partition-identity` | some card ID in `1..totalCards` does not appear exactly once across the four buckets |
| 7 | `counters-rankInPlay` | rank counts recomputed by scanning disagree with `state.counters` |
| 8 | `counters-histogram` | `cnt` recomputed from the scanned `rankInPlay` disagrees with `state.counters.cnt` |
| 9 | `unsatisfiable` | `liveCount >= 1` and `satisfiable(state) == false` |

`circulation` (4) precedes `unsatisfiable` (9) deliberately: a card that vanished is a conservation
bug and must be reported as one, not as a stall statistic. The order is now locked three ways — by
`Types.Violation`, by a comment in both files, and by a test (case 15).

## Mutation proof, part 1: break the STATE, the check must name itself

Eight of the nine names are produced by a deliberate state mutation, each paired with an assertion
that the clean state passes. Verbatim, at `73a3104`:

```
ok   tests/engine/invariants.spec.luau::clean state passes every invariant
ok   tests/engine/invariants.spec.luau::circulation equals 4*(ranks-seats)+jokers at the deal
ok   tests/engine/invariants.spec.luau::a dropped card on pass fails the circulation check
ok   tests/engine/invariants.spec.luau::a duplicated card on draw fails the circulation check
ok   tests/engine/invariants.spec.luau::an extra retired ID fails the partition count
ok   tests/engine/invariants.spec.luau::a swapped card fails the partition identity
ok   tests/engine/invariants.spec.luau::a 6-card hand fails the hand-size check
ok   tests/engine/invariants.spec.luau::a broken ring link fails the ring-links check
ok   tests/engine/invariants.spec.luau::desynced rank counters fail counters-rankInPlay
ok   tests/engine/invariants.spec.luau::desynced histogram alone fails counters-histogram
ok   tests/engine/invariants.spec.luau::a dead multiset is reported unsatisfiable
ok   tests/engine/invariants.spec.luau::satisfiability is an O(1) histogram read, not a scan
ok   tests/engine/invariants.spec.luau::the canonical hash sees an inbox reorder and ignores a hand reorder
ok   tests/engine/invariants.spec.luau::the canonical hash ignores counters, the valve record and rankOf
ok   tests/engine/invariants.spec.luau::the liveness tripwire is subsumed by hand-size, which locks the order
15 passed, 0 failed, 0 todo in 0.18s
```

### How `unsatisfiable` is reached without touching the order

The naive mutation (delete cards from play) drops circulation, and violation 4 precedes violation 9,
so `check` returns `"circulation"` and never reaches the predicate. The fixture is built
conservation-clean instead, from the identity that falls out of `expectedCirculation`:

> `circulation == expectedCirculation` iff `#retired + #terminal == 4 * (seatCount - liveCount - churnRemovals)`
> — four cards out of play per completed (non-churn) removal, and no more.

`ranks = 4`, `jokers = 0`, `seatCount = 3`, `totalCards = 16`, seat 3 removed as `Completed`
(`liveCount = 2`, `churnRemovals = 0`), retirement budget exactly 4 — spent as **one copy of each of
the four ranks**, leaving every rank at 3 copies. Two live seats hold 4 + 2 each, so circulation is 4,
equals `expectedCirculation`, and a legal action exists (otherwise violation 3 would fire first). The
spec asserts both halves of the identity before asserting the name. Adding one joker raises
`totalCards`, circulation and `expectedCirculation` by 1 each, keeping the fixture clean, and flips
`satisfiable` to `true` in Wild while it stays `false` in Blocker — CARD-10 against CARD-12 at the
predicate level.

A retirement of one card from each of four ranks is **not reachable by legal play** (a real
completion retires four of ONE rank), which is exactly why research 3.1 finds structural
unsatisfiability unreachable while Rule 8 holds. The fixture is allowed to build it because `check`
must detect a dead multiset wherever it arises; the claim that play cannot produce one is asserted
empirically by 02-06's destroy mutation and 02-08's fuzz run, not by making the predicate
unreachable.

## Mutation proof, part 2: break the CHECK, the suite must go red

The house standard is a gate watched failing. Fourteen implementation mutations were applied one at a
time to `src/server/engine/Invariants.luau`, each followed by the filtered run and a restore. Verbatim
output (`ok` lines elided):

```
=== M1  hand-size check neutered ===
FAIL tests/engine/invariants.spec.luau::a 6-card hand fails the hand-size check
     wrong violation name (nil) (expected hand-size, got circulation)
FAIL tests/engine/invariants.spec.luau::the liveness tripwire is subsumed by hand-size, which locks the order
     wrong violation name (nil) (expected hand-size, got liveness)
13 passed, 2 failed, 0 todo in 0.18s
exit=1

=== M2  ring-links check neutered ===
FAIL tests/engine/invariants.spec.luau::a broken ring link fails the ring-links check
     wrong violation name (nil) (expected ring-links, got counters-rankInPlay)
14 passed, 1 failed, 0 todo in 0.23s
exit=1

=== M3  liveness check neutered ===
15 passed, 0 failed, 0 todo in 0.16s
exit=0

=== M4  circulation check neutered ===
FAIL tests/engine/invariants.spec.luau::a dropped card on pass fails the circulation check
     wrong violation name (nil) (expected circulation, got partition-count)
FAIL tests/engine/invariants.spec.luau::a duplicated card on draw fails the circulation check
     wrong violation name (nil) (expected circulation, got partition-count)
13 passed, 2 failed, 0 todo in 0.19s
exit=1

=== M5  circulation derived from ONE helper (research Pitfall 4) ===
FAIL tests/engine/invariants.spec.luau::a dropped card on pass fails the circulation check
     wrong violation name (nil) (expected circulation, got partition-count)
FAIL tests/engine/invariants.spec.luau::a duplicated card on draw fails the circulation check
     wrong violation name (nil) (expected circulation, got partition-count)
13 passed, 2 failed, 0 todo in 0.23s
exit=1

=== M6  expectedCirculation drops the churn term ===
FAIL tests/engine/invariants.spec.luau::circulation equals 4*(ranks-seats)+jokers at the deal
     expected 13, got 9
14 passed, 1 failed, 0 todo in 0.23s
exit=1

=== M7  partition-count check neutered ===
FAIL tests/engine/invariants.spec.luau::an extra retired ID fails the partition count
     wrong violation name (nil) (expected partition-count, got partition-identity)
14 passed, 1 failed, 0 todo in 0.34s
exit=1

=== M8  partition-identity tally neutered ===
FAIL tests/engine/invariants.spec.luau::a swapped card fails the partition identity
     wrong violation name (nil) (expected partition-identity, got nil)
14 passed, 1 failed, 0 todo in 0.19s
exit=1

=== M9  counters-rankInPlay check neutered ===
FAIL tests/engine/invariants.spec.luau::desynced rank counters fail counters-rankInPlay
     wrong violation name (nil) (expected counters-rankInPlay, got nil)
14 passed, 1 failed, 0 todo in 0.22s
exit=1

=== M10 counters-histogram check neutered ===
FAIL tests/engine/invariants.spec.luau::desynced histogram alone fails counters-histogram
     wrong violation name (nil) (expected counters-histogram, got nil)
14 passed, 1 failed, 0 todo in 0.18s
exit=1

=== M11 unsatisfiable check neutered ===
FAIL tests/engine/invariants.spec.luau::a dead multiset is reported unsatisfiable
     wrong violation name (nil) (expected unsatisfiable, got nil)
14 passed, 1 failed, 0 todo in 0.17s
exit=1

=== M12 satisfiable loses the Blocker/Wild split ===
FAIL tests/engine/invariants.spec.luau::a dead multiset is reported unsatisfiable
     a blocker joker must not (expected false, got true)
14 passed, 1 failed, 0 todo in 0.17s
exit=1

=== M13 hash sorts the inbox (loses pass order) ===
FAIL tests/engine/invariants.spec.luau::the canonical hash sees an inbox reorder and ignores a hand reorder
     an inbox reorder must change the hash (expected a truthy value, got false)
14 passed, 1 failed, 0 todo in 0.19s
exit=1

=== M14 hash includes a monotonic counter (the valve killer) ===
FAIL tests/engine/invariants.spec.luau::the canonical hash ignores counters, the valve record and rankOf
     counters.completions changed the hash (expected 1|0|1/1,2,3,4/37,38,39,40,41,42,43,44,45|1/5,6,7,8/|1/9,10,11,12/|1/13,14,15,16/|1/17,18,19,20/|1/21,22,23,24/|1/25,26,27,28/|1/29,30,31,32/|1/33,34,35,36/, got 1|1|1/1,2,3,4/37,38,39,40,41,42,43,44,45|1/5,6,7,8/|1/9,10,11,12/|1/13,14,15,16/|1/17,18,19,20/|1/21,22,23,24/|1/25,26,27,28/|1/29,30,31,32/|1/33,34,35,36/)
14 passed, 1 failed, 0 todo in 0.19s
exit=1
```

Restored byte for byte after every mutation: `git status --short` and `git diff --stat` both empty,
and the filtered run back to `15 passed, 0 failed`.

### What those fourteen runs actually prove

1. **Thirteen of fourteen turn the suite red.** Every check except `liveness` is load-bearing on at
   least one row.
2. **The assert-the-reason rule is what makes five of them detectable.** M1, M2, M4, M5 and M7 all
   leave `check` returning `false` — a *later* check catches the mutated state and reports a
   different name. A `t.falsy(ok)` assertion would have read **green** for all five. This is the
   Phase 1 defect class, reproduced on demand, and it is why the plan forbids a bare boolean
   assertion and why `grep -n 't.falsy(ok)'` must return nothing.
3. **M5 is the Pitfall 4 proof.** Replacing `circulating ~= expectedCirculation(state)` with
   `circulating ~= circulation(state)` — the "one helper updates both sides" bug — makes the check
   unfailable, and the suite catches it. The two-sided derivation is not decorative.
4. **M14 is the valve's precondition, demonstrated.** Putting one monotonically increasing counter
   into the hash makes every state unique, which would mean plan 02-13's valve could never fire and
   amendment A7's mechanism would be silently vacuous. The failure message above also records the
   canonical hash format: `head | live/hand-sorted/inbox-FIFO | ...`.
5. **M3 is the honest exception** — see below.

### `liveness` is a subsumed tripwire, and that is the theorem

M3 neuters violation 3 and **nothing fails**. That is not a gap in the spec; it is research 3.1
Claim 3 showing up in the code. Once `hand-size` (1) has passed, every live hand holds 4 or 5 cards,
so `circulation >= 1` forces some seat to hold 5 (it can pass) or to hold 4 with a non-empty inbox
(it can draw). A legal action therefore always exists, and violation 3 is unreachable **in that
position**.

The plan forbids reordering the list, so the check stays at position 3 and its unreachability is made
falsifiable instead. Case 15 builds a state that genuinely satisfies the liveness condition — the
dealer left holding three cards, so `circulation == 3 >= 1` and *no* live seat has a legal action
(the spec counts them and asserts zero) — and then asserts `check` reports `hand-size`. M1 is the
proof that this row is doing work: with `hand-size` neutered, that same row reports `liveness`,
exactly as the subsumption argument predicts. If anyone ever reorders the violation list, this row
fails by name.

## CARD-04, as an assertion rather than a promise

```
circulation(state) == expectedCirculation(state) == 4*k + j
```

asserted at the deal for **k in {1, 2} x j in {0, 1, 2} x m in {2, 5, 9} x both joker modes** (36
states for the clean-state row, 36 for the circulation row), plus the churn case: one `Disconnected`
removal moves `expectedCirculation` from 9 to 13, exactly +4, which is Rule 8's "churn makes the
table looser, never tighter" (research 4.1). `k = 0` is not swept: amendment A4 makes `k >= 1`
mandatory, and `k = 0, j = 0` is the provable instant deadlock that plan 02-11 asserts explicitly
rather than skipping.

`REQUIREMENTS.md` records CARD-04 as **Partial**, following the FOUND-08 and CARD-05/06 precedent: the
arithmetic is locked and asserted, but the ring and the passing that realise it land in 02-06/02-07.

## Gates after the final commit

```
stylua --check src scripts tests                                      EXIT=0
selene src scripts tests                        0 errors / 0 warnings / 0 parse errors
selene --config selene.pure.toml src/server/engine
                                                0 errors / 0 warnings / 0 parse errors
lune run scripts/ci/analyze.luau --platform standard --base-luaurc .luaurc \
    --ignore "**/fixtures/**" src/server/engine scripts tests          analyze: ok
lune run scripts/ci/check-guards.luau    check-guards: ok (64 files, 130 requires, 15 guarded roots)
lune run tests/run.luau -- --filter engine/invariants      15 passed, 0 failed, 0 todo in 0.18s
lune run tests/run.luau -- --filter engine                 57 passed, 0 failed, 3 todo in 0.33s
lune run tests/run.luau                                   379 passed, 0 failed, 3 todo in 14.68s
lune run scripts/verify.luau              verify: all 14 automated steps passed in 17.8s
```

`src/server/engine/Types.luau` and `Invariants.luau` contain no `coroutine` and no `os.` — not even
inside a string or a comment — so plan 02-03's R3 extension holds on the first two real engine
modules. Neither file references a Roblox value or type, and `Invariants` has exactly one require
(`./Types`).

The whole-suite and `verify.luau` runs are reported here even though the plan scoped this execution to
the filtered runs (it executes in wave 2 beside plan 02-02): the orchestrator asked for them, and
02-02's commits were already in the tree, so there was no half-written sibling file to trip over.
Attribution of the +43 over the 336-case baseline: +15 from this plan, +28 from 02-02's seat-order
corpus.

## Deviations from Plan

### Auto-fixed and additive

**1. [Rule 2 - missing critical functionality] A 16th exported type, `Violation`**
- **Found during:** Task 1
- **Issue:** The task's acceptance criterion required `grep -c 'export type'` to return **at least
  16**, while the `<interfaces>` block it told me to write verbatim contains exactly **15**.
- **Fix:** Rather than invent filler, the locked violation vocabulary — which the plan protects in
  three separate paragraphs ("a LOCKED vocabulary AND a LOCKED ORDER", "never reorder the list") —
  was moved into the type system as `export type Violation`, a singleton union in the locked order.
  `check` is annotated `(boolean, Types.Violation?)`, a strict narrowing of the published
  `(boolean, string?)`. Verified safe for downstream plans: assignment to a `string?`, comparison
  against a non-member literal and `tostring`/`assert` use all typecheck cleanly under
  `luau-lsp --platform standard` (checked with a scratch fixture before committing). A mistyped
  violation name is now a build error.
- **Files:** `src/server/engine/Types.luau`, `src/server/engine/Invariants.luau`
- **Commit:** `09f561e`, `d315c71`

**2. [Rule 2 - missing critical functionality] A live-seat count check folded into `ring-links`**
- **Found during:** Task 2
- **Issue:** `state.liveCount` is a plain field that gates checks 3, 4 and 9. A desync between it
  and the actual number of live seats would silently disable three invariants while `check` stayed
  green — the defect class this whole module exists to kill.
- **Fix:** `check` counts live seats while walking them and reports `ring-links` when the count
  disagrees with `liveCount`. No tenth violation name was added: the plan locks the vocabulary at
  nine, and the live-seat count is part of the ring's structure.
- **Files:** `src/server/engine/Invariants.luau`
- **Commit:** `d315c71`

**3. [Rule 2 - missing critical functionality] Two spec rows the plan did not enumerate**
- **Found during:** Task 3
- **Issue:** The plan's 13 cases mutation-prove seven violation names. `counters-histogram` (8) and
  `liveness` (3) would never have been watched failing, and `must_haves.truths` requires that
  "each invariant has been deliberately broken ... so no check is vacuous".
- **Fix:** Added case 10 (histogram desynced alone, `rankInPlay` left correct → `counters-histogram`)
  and case 15 (the liveness subsumption / order lock, described above). Eight of nine names are now
  mutation-proven and the ninth is proven unreachable-by-subsumption, with M1/M3 as the evidence.
- **Files:** `tests/engine/invariants.spec.luau`
- **Commit:** `73a3104`

**4. [Rule 1 - bug] Luau widens a singleton-string literal table, breaking the mode sweep**
- **Found during:** Task 3 verification
- **Issue:** `local MODES: { Types.JokerMode } = { "Wild", "Blocker" }` produced a real TypeError at
  the call site — `Expected '"Blocker" | "Wild"' but got 'string | string'`. Element-wise
  `:: Types.JokerMode` casts did not help either; the top-level local's element type is generalised
  to `string`.
- **Fix:** The cells are visited through `eachCell(visit)`, which passes `"Wild"` and `"Blocker"` as
  literals. Commented in place so the next person does not reintroduce the table.
- **Files:** `tests/engine/invariants.spec.luau`
- **Commit:** `73a3104`

### Noted, not changed

- The plan's `must_haves` names six constants and `success_criteria` says "five constants", while the
  `<interfaces>` block returns **seven**. The interfaces block is the contract three later plans quote,
  so seven it is (`MAX_HAND` is the extra one versus the `must_haves` list).
- `STATE.md` and `ROADMAP.md` were deliberately not touched: the orchestrator owns them and plan
  02-02 shares them in this wave.

## Notes for later plans

- **02-04 (`Pool`)**: card IDs are deck POSITIONS. `rankOf` must be the shuffled permutation, not
  built in rank order — `Types.luau` header item 2, research Pitfall 6. The spec fixture here
  deliberately uses the unshuffled layout and is *not* a model for `newRound`.
- **02-06 (`Ring`)**: a removed seat's containers must end up empty and its cards accounted for in
  the successor's inbox, `retired` or `terminal`. `check`'s partition scan covers dead seats, so a
  seat removal that leaves cards behind on a dead seat will NOT trip `partition-count` — it will trip
  `counters-rankInPlay`, because the counters scan live seats only. Relink before setting
  `live = false`, or `ring-links` fires.
- **02-07 (`Engine`)**: `check` is the per-action assertion for the fuzz suite; `circulation` and
  `satisfiable` are the cheap pair for the big sweeps. There is no tiering inside `check` by design.
- **02-13 (the valve)**: `hash` is the string the valve compares, and M14 above is the standing proof
  that nothing monotonic leaked into it. `ValveState` is already on `State`; populate it in
  `newRound` with an `Rng` derived from the round seed so valve draws never perturb the deal.
- **02-09 / 02-11**: assert `satisfiable(state)` directly rather than asking `check` for
  `"unsatisfiable"` — violation 4 precedes violation 9, so a conservation bug will reach you under the
  name `circulation`, which is the intended behaviour.

## Threat register dispositions discharged

| Threat ID | Disposition | Evidence |
|---|---|---|
| T-2-01 | mitigated | `Types.luau` header item 2 fixes IDs as shuffled deck positions, re-randomised per round; `hash` excludes `rankOf`, and case 14 asserts a `rankOf` permutation does not change the hash |
| T-2-02 | mitigated | `check` derives circulation, card identity, rank counts and the histogram independently by scanning the real containers; eight of nine branches mutation-proven in the spec and thirteen of fourteen implementation mutations turn the suite red (M5 is the Pitfall 4 proof) |
| T-2-03 | mitigated | `State` carries no clock field and `Invariants` takes no clock argument; neither file contains `os.` even in a string, which plan 02-03's R3 now enforces |
| T-2-04 | accepted | the engine has no identity or audit surface; the Phase 4 adapter owns attribution |
| T-2-05 | accepted | no auth surface in a pure data module |

## Known Stubs

None. Both modules are complete against their published interfaces; the valve's *type surface* is
declared here by design (interface-first, plan 02-13 implements it) and is explicitly out of scope
for this plan rather than stubbed — nothing in this plan reads or writes a valve field, and the spec
asserts that `hash` and `check` ignore it.

## Self-Check: PASSED

- `src/server/engine/Types.luau` — FOUND; 16 `export type`, 7 constants, `ValveState`,
  `ValveForcedPass`, `antiLivelockValve`, `VALVE_ARM_ACTIONS_PER_SEAT = 48`, `VALVE_SEEN_CAP = 4096`,
  `JOKER_RANK = 0`, `MAX_DEAL_ATTEMPTS = 64`, `MAX_JOKERS = 2` all present; no
  `game|Instance|Vector3|os.|coroutine`
- `src/server/engine/Invariants.luau` — FOUND; 14 `return false, "` lines, exactly 1 `require(`,
  `local function hash`, `partition-identity`, `counters-rankInPlay` present; no forbidden tokens
- `tests/engine/invariants.spec.luau` — FOUND; 15 `t.test(`, `t.falsy(ok)` absent,
  `"partition-identity"`, `"counters-rankInPlay"`, `"unsatisfiable"`, `valve` present
- Commits `09f561e`, `316c9dd`, `d315c71`, `73a3104` — all FOUND in `git log`
