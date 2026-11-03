---
phase: 02-card-engine-and-pacing-simulator
plan: 06
subsystem: engine
tags: [ring, circular-linked-list, fifo, pass, draw, seat-removal, rule-8, terminal-bucket, mutation-proof]

requires:
  - phase: 02-01
    provides: "Types.State / Seat / Counters / RemoveCause / Violation, and Invariants.circulation / expectedCirculation / satisfiable / hash / check"
  - phase: 02-03
    provides: "check-guards R3 bans on `coroutine` and the `os.` needle inside pure zones"
  - phase: 01-02
    provides: "tests/run.luau + Test.Runner (deepEqual, throws, assert-the-reason house rule)"
provides:
  - "src/server/engine/Ring.luau — build, successorOf, pass, draw, removeSeat; the ring's only DATA operations, with no legality checking anywhere"
  - "CARD-03 as an assertion: a passed card lands at the tail of the next LIVE seat's inbox, with the target resolved at execution time and no target parameter to steer"
  - "CARD-04 as an assertion: the last seat's pass lands beneath the dealer's deck with no last-seat branch in the code, and circulation is unchanged across 200 alternating operations"
  - "CARD-08 as an assertion: ONE removeSeat for Completed / Disconnected / Benched, routing proven identical by exact inbox array AND canonical hash"
  - "The locked dump order (OQ-G / research 7.4): departing hand ascending, then departing inbox in FIFO order, appended to the successor's inbox tail"
  - "The `terminal` bucket wired (research 7.3): the sole seat leaving routes to state.terminal, liveCount 0, head 0, and every card is still accounted for"
  - "tests/engine/ring.spec.luau (8 cases) and tests/engine/removal.spec.luau (10 cases), including the deterministic Rule 8 destroy mutation"
affects: [02-07, 02-08, 02-09, 02-11, 02-13]

tech-stack:
  added: []
  patterns:
    - "UNCHECKED data primitives with a documented single owner of legality (Engine.apply): a second validation layer would create two places that can disagree, and only one of them would be the one the tests assert"
    - "Caller-bug `error()` separated in the header from reject codes: `error` fires only where the alternative is silent corruption, never where a reject code exists"
    - "Express a structural rule ONCE and prove the absence of a branch by grep plus a boundary test (m = 2 and m = 1) rather than by code reading"
    - "A no-successor edge case gets a BUCKET, not a nil path: `terminal` keeps 'never destroyed' literally assertable by the partition identity"
    - "Mutation-prove from the TEST side the thing no shipped path may do, so the forbidden operation has no implementation to be called by accident"

key-files:
  created:
    - src/server/engine/Ring.luau
    - tests/engine/ring.spec.luau
    - tests/engine/removal.spec.luau
  modified: []

key-decisions:
  - "`pass` and `draw` raise a caller-bug `error` when the named card is not in the hand or the inbox is empty, rather than returning nil or silently corrupting. `table.remove(hand, nil)` would quietly drop the hand's LAST card, and `draw`'s return type is a non-optional CardId. The header distinguishes these from reject codes: NotYourCard and InboxEmpty are Engine.apply's answers and remain its sole property, so there is no second legality layer"
  - "`successorOf` tests the LIVENESS OF THE TARGET (`seats[seat.next].live`), not of `seatId`. A removed seat is pointed at itself, so it answers nil, which is exactly the documented contract; a live sole seat answers itself. Still no skip loop: if one were ever needed the unlink is broken and `Invariants.check` reports `ring-links`"
  - "`removeSeat` owns exactly one counter responsibility and only in the no-successor branch: it decrements rankInPlay / jokersInPlay / cnt for every dumped card, because a card in `terminal` is accounted for but OUT of play. The routed branch touches no counter at all, since routing a card to an inbox does not take it out of play (note for plan 02-07: do not double-count)"
  - "Case 9 makes the three causes' states identical at the moment of the call INCLUDING the caller-side retirement, and compares the successor's inbox array and the canonical hash. The retirement is the caller's work in every cause, so performing it in all three isolates the routing. Conservation after a churn-caused removal is asserted separately in case 15, where no retirement happened"
  - "The removal spec passes RemoveCause values as LITERALS at the call site through a local `routeWith(cause)` helper, because Luau widens a singleton-string literal table to `{ string }` and the widened element no longer satisfies `RemoveCause` — the same real TypeError plan 02-01 documented for `JokerMode`. Caught by `analyze`, not by the test run"
  - "Case 17 asserts `Invariants.satisfiable(state) == false` DIRECTLY and that `check` returns `(false, \"circulation\")`. The violation order was NOT touched: `circulation` is violation 4 and the satisfiability tripwire is violation 9, so a conservation break can never reach violation 9. The literal string for violation 9 appears nowhere in the spec, which the plan's grep criterion enforces"

patterns-established:
  - "The ring's wrap is expressed exactly once, in `build`, as `next = (i % n) + 1` / `prev = ((i - 2) % n) + 1`; every downstream rule (CARD-04, the dealer's deck, the 2-ring relink) is a consequence rather than a branch"
  - "15 implementation mutations, each one caught, as the acceptance standard for a data-structure module — including the Rule 8 destroy mutation applied to shipped code (M9) on top of the test-side destroy mutation in case 17"

requirements-completed: [CARD-03, CARD-04, CARD-08]
requirements-contributed: []

duration: ~25 min
completed: 2026-11-03
---

# Phase 2 Plan 06: The Ring, Pass/Draw and Rule 8 Summary

**A circular doubly-linked ring over seat INDICES whose wrap is written once and therefore needs no last-seat branch, FIFO pass/draw primitives that validate nothing and leave every reject code to `Engine.apply`, and ONE `removeSeat` that serves completion, disconnect and AFK with provably identical routing — including the research 7.3 collision where the sole seat leaves and its cards move to a `terminal` bucket so that Rule 8's "never destroyed" stays literally assertable.**

## Performance

- **Duration:** ~25 min (2026-11-03T20:24:00Z to 2026-11-03T20:49:00Z)
- **Tasks:** 3 (two of them TDD, RED then GREEN)
- **Files created:** 3 (244 + 257 + 454 = 955 lines)
- **Cases added:** 18 (8 ring, 10 removal); suite 431 passed, 0 failed, 3 todo

## The published interface (for plan 02-07)

```luau
build: (state: Types.State, playerIds: { Types.PlayerId }) -> ()
successorOf: (state: Types.State, seatId: Types.SeatId) -> Types.SeatId?
pass: (state: Types.State, seatId: Types.SeatId, cardId: Types.CardId) -> Types.SeatId -- the target
draw: (state: Types.State, seatId: Types.SeatId) -> Types.CardId
removeSeat: (state: Types.State, seatId: Types.SeatId, cause: Types.RemoveCause) -> (Types.SeatId?, number)
```

`removeSeat` returns `(routedTo, cardsRouted)`. `routedTo` is `nil` exactly when the ring emptied and
the cards went to `state.terminal` instead; `cardsRouted` is `#dumped`, which is what the
`SeatRemoved` event's `cards` field wants.

**What `removeSeat` does and does not own:**

| Concern | Owner |
|---|---|
| `churnRemovals += 1` when `cause ~= "Completed"` | **this function** (the cause's only effect) |
| `rankInPlay` / `jokersInPlay` / `cnt` decrements | **this function, ONLY in the no-successor branch** — a card in `terminal` is accounted for but out of play |
| the same counters on the routed branch | nobody: routing to an inbox does not take a card out of play |
| retiring the completed four, `completions`, events, `valve` | `Engine.apply` (plan 02-07) — **do not double-count** |
| every legality check and every reject code | `Engine.apply` |

**Locked dump order (OQ-G, research 7.4):** the departing **hand first, in ascending card id**, then
the departing **inbox in FIFO order**, all appended to the successor's inbox tail. Case 10 asserts the
exact array `{ 9, 10, 11, 12, 21, 22 }` after permuting the departing hand, so the sort is proven to
do work rather than inherit the fixture's order. This is a replay-determinism lock: a different order
is a different draw order for the successor and therefore a different round.

**Ring-emptied sentinel:** `head = 0`, `liveCount = 0`, cards in `state.terminal`, dead seat pointed
at itself. `Invariants.check` already special-cases `liveCount == 0`, where the partition identity is
the only live proof left — and it is the one Rule 8 needs.

## Accomplishments

- `Ring.luau`: 244 lines, one require (`./Types`), zero Roblox API, zero banned constructs, zero
  last-seat branches, zero `liveCount == 2` branches, zero per-cause removal functions.
- CARD-03 proven at execution time: ring case 7 removes seat 5's neighbour and then passes from
  seat 5; the card lands in the **departed seat's** successor (seat 7), behind the four cards seat 6
  routed there, with no rejection and no special handling. `pass` has no target parameter for a
  client to supply.
- CARD-04 proven twice: the last seat's pass lands at the tail of the dealer's inbox with the deck's
  own cards still ahead of it, and circulation holds at exactly 9 with `check` clean after **each of
  200** alternating draws and passes across a 9-ring.
- CARD-08 proven four ways: identical routing across all three causes (exact array **and** canonical
  hash, with only `churnRemovals` differing `{0, 1, 1}`); `+4` circulation on a churn removal at a
  hand of 4 **and** at a hand of 5; net-zero across a completion; and the `terminal` bucket holding
  all 24 cards the sole seat held, with `#retired + #terminal == totalCards`.
- Rings of 2 and 1 are **played**, not merely inspected: a pass both ways round at m = 2 and a
  self-pass plus self-draw at m = 1, with `Invariants.check` clean at every step.

## Task Commits

1. **Task 1: Ring — build, pass, draw, successorOf**
   - `bb9ccbb` test(02-06): failing ring spec (RED)
   - `39dbfe8` feat(02-06): Ring — build, successorOf, pass and draw (GREEN)
2. **Task 2: removeSeat — one operation, three causes, the terminal bucket**
   - `fbefea8` test(02-06): failing removal spec (RED)
   - `d21e352` feat(02-06): removeSeat (GREEN)
3. **Task 3: the specs completed — apply-time resolution and the Rule 8 destroy mutation**
   - `21eb2f5` test(02-06): apply-time target resolution and the Rule 8 destroy mutation

No REFACTOR commit: `removeSeat` passed all nine removal cases on its first GREEN run and there was
nothing to clean up.

## Files Created

- `src/server/engine/Ring.luau` — the ring and its five operations. Header states the division of
  labour with `Engine.apply`, the index-not-reference decision, the absence of a last-seat branch,
  Rule 6 (no yields: synchronous, no callbacks, publishes nothing) and Rule 8 (no shipped path
  destroys a card, and none may be added).
- `tests/engine/ring.spec.luau` — 8 cases (CARD-03, CARD-04), 9 `deepEqual` assertions on exact inbox
  and hand arrays.
- `tests/engine/removal.spec.luau` — 10 cases (CARD-08), including the deterministic Rule 8 destroy
  mutation and its crafted one-intact-rank fixture.

## Mutation proof — verbatim

**15 implementation mutations, 15 caught.** Each was applied to `src/server/engine/Ring.luau`, both
specs were run, and the file was restored from a byte-identical backup (`git status` clean
afterwards). Verbatim harness output:

```
baseline:
  engine/ring: 8 passed, 0 failed, 0 todo in 0.21s (exit 0)
  engine/removal: 10 passed, 0 failed, 0 todo in 0.23s (exit 0)
M1 RED (caught) -- pass inserts at the FRONT of next's inbox instead of the tail
     engine/ring: 3 passed, 5 failed, 0 todo in 0.22s (exit 1)
     engine/removal: 7 passed, 3 failed, 0 todo in 0.22s (exit 1)
M2 RED (caught) -- draw pops the TAIL of the inbox instead of the front
     engine/ring: 7 passed, 1 failed, 0 todo in 0.21s (exit 1)
     engine/removal: 9 passed, 1 failed, 0 todo in 0.21s (exit 1)
M3 RED (caught) -- pass resolves the target as seat.prev instead of seat.next
     engine/ring: 5 passed, 3 failed, 0 todo in 0.22s (exit 1)
     engine/removal: 9 passed, 1 failed, 0 todo in 0.22s (exit 1)
M4 RED (caught) -- build wires prev naively as i - 1, so the dealer's prev is 0
     engine/ring: 4 passed, 4 failed, 0 todo in 0.22s (exit 1)
     engine/removal: 3 passed, 7 failed, 0 todo in 0.23s (exit 1)
M5 RED (caught) -- dump order reversed: the departing inbox before the departing hand
     engine/ring: 8 passed, 0 failed, 0 todo in 0.23s (exit 0)
     engine/removal: 5 passed, 5 failed, 0 todo in 0.20s (exit 1)
M6 RED (caught) -- the departing hand is dumped in storage order instead of ascending card id
     engine/ring: 8 passed, 0 failed, 0 todo in 0.21s (exit 0)
     engine/removal: 9 passed, 1 failed, 0 todo in 0.28s (exit 1)
M7 RED (caught) -- churnRemovals is incremented for EVERY cause, so a completion counts as churn
     engine/ring: 8 passed, 0 failed, 0 todo in 0.21s (exit 0)
     engine/removal: 8 passed, 2 failed, 0 todo in 0.21s (exit 1)
M8 RED (caught) -- churnRemovals is never incremented, so churn is invisible to the identity
     engine/ring: 8 passed, 0 failed, 0 todo in 0.21s (exit 0)
     engine/removal: 1 passed, 9 failed, 0 todo in 0.21s (exit 1)
M9 RED (caught) -- RULE 8 DESTROY: the no-successor cards are dropped instead of moved to state.terminal
     engine/ring: 8 passed, 0 failed, 0 todo in 0.23s (exit 0)
     engine/removal: 9 passed, 1 failed, 0 todo in 0.21s (exit 1)
M10 RED (caught) -- the terminal move leaves rankInPlay / cnt untouched, so cards are in play after the ring emptied
     engine/ring: 8 passed, 0 failed, 0 todo in 0.23s (exit 0)
     engine/removal: 9 passed, 1 failed, 0 todo in 0.23s (exit 1)
M11 RED (caught) -- the unlink forgets seats[seat.next].prev, the shape a removal takes when it half-relinks
     engine/ring: 8 passed, 0 failed, 0 todo in 0.22s (exit 0)
     engine/removal: 1 passed, 9 failed, 0 todo in 0.25s (exit 1)
M12 RED (caught) -- head is left pointing at the removed seat
     engine/ring: 8 passed, 0 failed, 0 todo in 0.20s (exit 0)
     engine/removal: 7 passed, 3 failed, 0 todo in 0.23s (exit 1)
M13 RED (caught) -- a double removal returns quietly instead of erroring
     engine/ring: 8 passed, 0 failed, 0 todo in 0.25s (exit 0)
     engine/removal: 9 passed, 1 failed, 0 todo in 0.21s (exit 1)
M14 RED (caught) -- successorOf skips the liveness check and names a dead seat
     engine/ring: 7 passed, 1 failed, 0 todo in 0.22s (exit 1)
     engine/removal: 10 passed, 0 failed, 0 todo in 0.26s (exit 0)
M15 RED (caught) -- routedTo drops the liveCount guard, so the sole seat routes its cards to itself
     engine/ring: 8 passed, 0 failed, 0 todo in 0.20s (exit 0)
     engine/removal: 9 passed, 1 failed, 0 todo in 0.22s (exit 1)
restored
```

The three Rule-8-critical mutations, with the failing assertion verbatim:

```
----- M9 (shipped-code destroy: cards dropped instead of moved to terminal) -----
FAIL tests/engine/removal.spec.luau::the ring empties and nothing is destroyed
     terminal holds exactly the cards the seat held (expected { [10] = 18, [11] = 19, [12] = 20, [13] = 13, [14] = 14, [15] = 15, [16] = 16, [17] = 9, [18] = 10, [19] = 11, [1] = 21, [20] = 12, [21] = 5, [22] = 6, [23] = 7, [24] = 8, [2] = 22, [3] = 23, [4] = 24, [5] = 25, [6] = 26, [7] = 27, [8] = 28, [9] = 17 }, got {  })
9 passed, 1 failed, 0 todo in 0.21s

----- M10 (terminal move leaves the counters alone) -----
FAIL tests/engine/removal.spec.luau::the ring empties and nothing is destroyed
     a well-formed state reported a violation (the emptied ring) (expected nil, got counters-rankInPlay)
9 passed, 1 failed, 0 todo in 0.27s

----- M6 (dump order not sorted) -----
FAIL tests/engine/removal.spec.luau::the dump order is hand-first then inbox in FIFO order
     hand ascending, THEN inbox in FIFO order (expected { [1] = 9, [2] = 10, [3] = 11, [4] = 12, [5] = 21, [6] = 22 }, got { [1] = 12, [2] = 9, [3] = 11, [4] = 10, [5] = 21, [6] = 22 })
9 passed, 1 failed, 0 todo in 0.24s
```

**The test-side Rule 8 destroy mutation (case 17)** is the other half, and it is the one the plan
specified: a crafted fixture in which exactly one rank is still fully intact (`cnt[5] == 1`) and all
four of its copies sit in seat 1's hand and inbox, conservation-clean at the start
(`#retired + #terminal == 4 * (seatCount - liveCount - churnRemovals)` → `8 == 4 * (4 - 2 - 0)`).

- Honest path: `removeSeat` routes the eight cards, `Invariants.satisfiable == true`, `check` clean.
- Destroy path: the eight routed cards are deleted from the successor's inbox and from the counters
  **from the test side**, and then `Invariants.satisfiable(state) == false` is asserted **directly**,
  alongside `check(state) == (false, "circulation")`, `circulation == 4` and
  `expectedCirculation == 12`.

`check` reports `circulation` and never reaches violation 9, because the violation order is locked
and `circulation` is violation 4. **The order was not touched.** Reordering it to make violation 9
surface here would make every genuine conservation bug report as a stall statistic in the simulator
instead of as an error, inverting the whole design of `Invariants.check`; the spec records that next
to the case, and the literal string for violation 9 appears nowhere in the file (a plan acceptance
criterion greps for its absence). Research 3.4's measured rates (2.9–5.7% firing for the destroy
variant across 12,800 rounds, 0.0% honest) are recorded in the same comment as the reason a crafted
deterministic fixture is paired with plan 02-09's statistical version.

## Verification

```
stylua --check src scripts tests                                        ok
selene src scripts tests                                                0 errors, 0 warnings
selene --config selene.pure.toml src/server/engine                      0 errors, 0 warnings
analyze --platform standard (src/server/engine, scripts, tests)         ok
check-guards                                                            ok (74 files, 163 requires, 19 guarded roots)
lune run tests/run.luau -- --filter engine/ring                         8 passed, 0 failed
lune run tests/run.luau -- --filter engine/removal                      10 passed, 0 failed
lune run tests/run.luau                                                 431 passed, 0 failed, 3 todo
lune run scripts/verify.luau                                            all 14 automated steps passed in 18.1s
```

Grep criteria (all as the plan specified): no `if seatId == state.seatCount|isLastSeat|lastSeat`, no
`os.|coroutine|game|Instance|math.random`, exactly 1 `require(`, no `liveCount == 2` branch, 0
per-cause removal functions, `terminal` / `Invariants.satisfiable` / `"circulation"` / `forbidden` /
`2.9` present in the removal spec, the quoted violation-9 name absent, 9 `deepEqual` in the ring spec.

The whole suite and `scripts/verify.luau` were run despite the plan's wave-parallel caution, on the
orchestrator's instruction; both were green with the wave-3 siblings' work already landed.

## Decisions Made

See `key-decisions` in the frontmatter. The two that future plans must not re-litigate:

1. **The dump order** (hand ascending, then inbox FIFO). Replay determinism depends on it and case 10
   asserts the exact array.
2. **`terminal` rather than a nil path or a self-route.** Routing to self resurrects a dead seat;
   destroying breaks Rule 8. `head = 0` is the ring-emptied sentinel, and `removeSeat` decrements the
   play counters only on that branch.

## Deviations from Plan

**None of substance — one typed-fixture adjustment inside task 3's own file.** The removal spec
originally iterated the three causes out of `local causes: { Types.RemoveCause } = {...}`, which
`analyze` rejected (`Expected '"Benched" | "Completed" | "Disconnected"', but got 'string'`) because
Luau widens a singleton-string literal table. Replaced with a local `routeWith(cause)` helper called
with literals, which is the pattern plan 02-01 already documented for `JokerMode`. Caught by the
typechecker, not by the test run — fixed inside `d21e352`, no behaviour change.

No Rule 1/2/3 auto-fixes were needed; no Rule 4 situation arose. Nothing was logged to
`deferred-items.md`.

## Known Stubs

None. `Ring.luau` has no placeholder values, no TODO/FIXME, and no unwired data path; `Engine.apply`
(plan 02-07) is its only shipped caller and is a planned dependency, not a stub.

## Issues Encountered

- A sibling wave-3 plan's half-written `tests/engine/hand.spec.luau` surfaced as a load failure in
  one early run of `--filter engine/ring` (it required a `Hand` module that did not exist yet). It
  resolved itself when that plan landed its module, and it never touched this plan's files. Recorded
  as the concrete instance of the hazard the plan's verification block warns about.

## Next Phase Readiness

Plan 02-07 (`Engine.apply`) can be written directly against the interface above. Three things it must
honour and nothing here enforces for it:

1. It is the **only** place legality lives. Do not add checks to `Ring`; the reject codes in
   `Types.Reject` are its contract.
2. It must move the retired four out of the hand **before** calling `removeSeat(..., "Completed")`,
   and must not increment `churnRemovals` itself.
3. It must not touch `rankInPlay` / `jokersInPlay` / `cnt` for routed cards — only for retirement.
   The terminal decrements already happened inside `removeSeat`.

Plan 02-09's simulator gets the `+4`-per-churn-removal fact as a tested property, and plan 02-13's
valve gets a ring whose canonical hash is stable under index-based links.

---
*Phase: 02-card-engine-and-pacing-simulator*
*Completed: 2026-11-03*

## Self-Check: PASSED

All three created files exist on disk; all five task commits (`bb9ccbb`, `39dbfe8`, `fbefea8`,
`d21e352`, `21eb2f5`) are present in `git log`; the working tree is clean apart from this summary.
