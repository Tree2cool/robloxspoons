---
phase: 02-card-engine-and-pacing-simulator
plan: 07
subsystem: engine
tags: [engine, apply, newRound, reject-codes, completion-chain, anti-livelock-valve, rule-6, rule-7, rule-8, mutation-proof]

requires:
  - phase: 02-01
    provides: "Types.State / Intent / Event / Reject / ApplyResult / Counters / ValveState, and Invariants.check / hash / circulation"
  - phase: 02-03
    provides: "check-guards R3 bans on the yield-capable standard library and the `os.` needle inside pure zones"
  - phase: 02-04
    provides: "Pool.deal (CARD-09 rejection sampling) and the LOCKED deal layout"
  - phase: 02-05
    provides: "Hand.detectCompletion and the Completion record (rank / retired / fifth / naturalsUsed / jokersUsed)"
  - phase: 02-06
    provides: "Ring.build / pass / draw / removeSeat, the locked dump order, the terminal bucket, and the counter-ownership split"
  - phase: 02-13
    provides: "Valve.new / afterProgress / afterAction, the locked firing and choice rules, and tests/harness/Livelock"
provides:
  - "src/server/engine/Engine.luau — newRound(config, seatPlayerIds, rng) and apply(state, intent) -> ApplyResult: the round constructor and the ONE mutation entry point"
  - "The locked reject precedence, implemented and mutation-proven in BOTH directions (UnknownCard before HandNotFive, HandNotFour before InboxEmpty)"
  - "All seven reject codes reachable, each with its own case asserting the code, an empty event list, an unchanged canonical hash AND an unmoved valve"
  - "The locked event order, including the valve's three-event form Drew -> ValveForcedPass -> Passed"
  - "The anti-livelock valve wired INSIDE apply where no caller can forget it: exactly one entry point per successful apply, none on a rejection"
  - "CARD-11 proven end to end through the REAL apply: the Livelock fixture escapes on action 113 and provably does not with the valve disabled"
  - "A loud caller-bug error on Remove{cause = \"Completed\"} — the one cause an intent may not carry"
  - "tests/engine/apply.spec.luau (28 cases)"
affects: [02-08, 02-09, 02-10, 02-11, 02-12, 02-14, 04]

tech-stack:
  added: []
  patterns:
    - "A rejection asserts FOUR things, not one: the code, an empty event list, an unchanged canonical hash, and an unmoved valve. The fourth is not implied by the third -- `Invariants.hash` excludes `valve` by design, so a valve call on a rejection leaves the hash identical and would slip through every rejection case in the file"
    - "A liveness mechanism is wired INSIDE the mutation entry point rather than exposed as a tick, because a mechanism a caller has to remember is a mechanism a later phase forgets, and the measurement that justified it would silently stop applying to the shipped product"
    - "Counters derived from a DIFFERENT source than the checker reads: `newRound` scans `rankOf`, `Invariants.check` walks the seat containers, so a layout mistake is a reported violation rather than two sides agreeing with each other (research Pitfall 4)"
    - "A precedence table is a contract and needs a case per ORDERED PAIR, not per code: an intent illegal on both counts is the only thing that can distinguish two correct-looking implementations"
    - "`error` for a caller wiring bug whose alternative is silent state corruption; a reject code only for a legal answer to an illegal request. The two are never interchangeable, and adding an eighth reject code would have broken plan 02-08's coverage contract"
    - "Prove a tripwire by a PAIRED mutation: break the thing it guards with the tripwire in place, then again with it removed, and show the failure moves from one named violation at the deal to scattered damage several layers downstream"

key-files:
  created:
    - src/server/engine/Engine.luau
    - tests/engine/apply.spec.luau
  modified: []

key-decisions:
  - "A `Remove` intent may NOT carry the `Completed` cause: `apply` raises a caller-bug error. `Completed` is net zero on circulation only because the completion path retires four cards BEFORE calling `removeSeat`, and `removeSeat` deliberately leaves `churnRemovals` alone for it. An externally supplied `Remove{cause = \"Completed\"}` skips the retirement, routes four cards into the successor's inbox with nothing leaving play, and leaves `circulation` permanently +4 against `expectedCirculation` for the rest of the round (threat T-2-35). Deliberately NOT an eighth reject code: there are exactly seven and plan 02-08 asserts that, and a reject is a legal answer to an illegal request rather than a report of caller corruption"
  - "`UnknownCard` also covers a fractional or NaN card id, because an id that is not an integer in `1..totalCards` names no card and that IS the legality answer. The shape layer (`src/shared/Net/Validate`) still owns refusing it as a malformed payload; the two layers are not redundant (research Security Domain V5)"
  - "`newRound` derives its counters by scanning `rankOf`, not by walking the containers it just filled. `Invariants.check` recomputes the same quantities FROM the containers, so the two sides are independent and a layout bug surfaces as `counters-rankInPlay` or `partition-identity` instead of agreeing with itself"
  - "`Pool.deal`'s second return (the attempt count) is deliberately not captured. `State` stays a pure description of the table, and plan 02-09's simulator reads the metric from `Pool.deal` directly"
  - "`newRound` keeps its own `seatCount < 1` error even though `Pool.validate` would answer `BadConfig`, because an empty seat list is a round-lifecycle mistake and a bad pool is a configuration mistake, and they are fixed in different files. It is mutation-detectable (the message differs), so it is not an unfalsifiable check"
  - "Case 17 (`HandNotFour` before `InboxEmpty`) was NOT in the plan and exists because a mutation survived the whole spec without it. The plan locked both Draw and Pass precedence but only supplied a case for the Pass pair. The situation is reached exactly as the live round reaches it -- seat 1 draws, passes, and seat 2 draws the single card it was given"
  - "Case 3 asserts that the valve's generator is DERIVED from the round's (same round seed -> same valve draws, different round seed -> different valve draws). Nothing else in the file could notice a constant seed: `snapshot` cannot compare `valve.rng` because it is a table of closures, and the end-to-end valve cases seed the fixture directly. Mutation M24 is the proof"

patterns-established:
  - "28 cases and a 28-mutation battery (25 planned plus 3 reworked survivors), every mutation applied to shipped code, watched failing, and restored with `git checkout --`"
  - "The valve's necessity proven by a PAIR of cases that fail for opposite reasons: case 26 fails if the valve is not wired, case 27 fails if the fixture is not really a cycle"

requirements-completed: [CARD-01, CARD-03, CARD-07, CARD-08, CARD-11, CARD-12]
requirements-contributed: []

duration: ~55 min
completed: 2026-11-03
---

# Phase 2 Plan 07: Engine.apply and Engine.newRound Summary

**The engine's single mutation entry point: a synchronous two-parameter `apply` that validates in a locked precedence, returns one of seven named reject codes with the state byte-identical and the valve unmoved, detects four of a kind only on the draw path and removes the seat inside the same call, and has the anti-livelock valve wired in where no caller can forget it — proven end to end by driving plan 02-13's hand-verified cycle through the REAL `apply`, where it escapes on action 113 and completes on 114, and provably never escapes at all with the valve disabled.**

## Performance

- **Duration:** ~55 min (2026-11-03)
- **Tasks:** 3 (two TDD, RED then GREEN)
- **Files created:** 2 (385 + 795 = 1,180 lines)
- **Cases added:** 28; suite **459 passed, 0 failed, 3 todo** (baseline 431)
- **`--filter engine`:** `137 passed, 0 failed, 3 todo in 0.66s` (0.699s wall, `time` real) — the budget plans 02-08 and 02-09 size against
- **`--filter engine/apply`:** `28 passed, 0 failed, 0 todo in 0.25s`
- **`scripts/verify.luau`:** `verify: all 14 automated steps passed in 17.5s`

## The published interface (for plan 02-08, plan 02-09 and Phase 4)

```luau
-- Builds a fully dealt round. Errors by name, through Pool.deal, on an invalid pool, and errors
-- with the violation name if its own Invariants.check is not clean.
-- seatPlayerIds is already IN SEAT ORDER: index 1 is the dealer (SeatOrder, plan 02-02).
newRound: (config: Types.EngineConfig, seatPlayerIds: { Types.PlayerId }, rng: any) -> Types.State

-- The ONLY mutation entry point. Synchronous. Two parameters. No handler function, no sink, no
-- clock. Events are RETURNED; the caller feeds them to its own stream after apply has returned.
apply: (state: Types.State, intent: Types.Intent) -> Types.ApplyResult
```

`ApplyResult` is `{ ok: boolean, events: { Event }, reject: Reject? }`. On a rejection `events` is an
**empty table, never nil**, `reject` is set, and nothing in `State` moves — including `state.valve`.

### The locked reject precedence (first match wins)

| intent | order of checks |
|--------|-----------------|
| any | `UnknownSeat` (no such seat index) -> `SeatNotLive` (`live == false`) |
| `Draw` | ... -> `HandNotFour` (`#hand ~= 4`) -> `InboxEmpty` (`#inbox == 0`) |
| `Pass` | ... -> `UnknownCard` (`cardId` not an integer in `1..totalCards`) -> `HandNotFive` (`#hand ~= 5`) -> `NotYourCard` |
| `Remove` | ... no further checks; the cause comes from outside, except that `"Completed"` is refused (below) |

**Both ordered pairs have their own case** (16 and 17), because an intent illegal on only one count
cannot distinguish two implementations. `NotYourCard` covers BOTH "held by another seat" and "in play
but sitting in an inbox" (research 7.6, the auto-passed card); case 15 asserts the inbox situation
separately, and mutation M3 (a predicate that also scans the inbox) is caught by it alone.

**Seven codes, not six.** Research §11.3 says six; §9 lists seven and all seven are reachable. The
spec records that in a comment: **plan 02-08 must assert coverage of SEVEN**, each at its minimum
observation count.

### The locked event order

| apply | events, in order |
|-------|------------------|
| non-completing `Draw` | `Drew` |
| non-completing `Draw`, valve fires | `Drew` -> `ValveForcedPass` -> `Passed` |
| completing `Draw` | `Drew` -> `Completed` -> `SeatRemoved{cause = "Completed"}` |
| `Pass` | `Passed` |
| `Remove` | `SeatRemoved` |
| any rejection | *(empty)* |

`ValveForcedPass` precedes the `Passed` it explains, and the `Passed` is emitted as well rather than
folded into the marker, so **every card movement in the engine has exactly one `Drew` or `Passed`
event**. Phase 4's adapter and plan 02-08's fuzz suite can both rely on that uniform rule instead of
knowing that one event kind is secretly also a pass. Phase 4 must read `ValveForcedPass` as "that
pass was not the player's choice" — the same contract as an AFK auto-pass.

### The locked valve call rule

At the end of every **successful** apply, exactly one of:

- `Valve.afterProgress(state)` when the events include a `Completed` or a `SeatRemoved`
- `Valve.afterAction(state, drewAtSeat)` otherwise, with `drewAtSeat` the drawing seat on a
  non-completing draw and `nil` on a pass

**Neither on a rejection.** Plan 02-08 asserts `state.valve.observations == acceptedActions`; case 26
asserts it here (114 == 114) with one illegal intent injected mid-run.

`ValveForcedPass` carries `lap = state.valve.actionsSinceProgress` **read after the valve observed the
action** (mutation M19 proves the off-by-one is caught). It carries no hash: the hash encodes every
hand and an event crosses the network boundary in Phase 4 (CLAUDE.md rule 3).

## Hardcoded seeds and measured action indices

| what | value | recorded where |
|---|---|---|
| case 19, the completion chain (3 seats, k=1, j=0, Wild) | **seed 1**, completion on action **17** | `tests/engine/apply.spec.luau` case 19 |
| case 20, Wild vs Blocker divergence (3 seats, k=1, j=1) | **seed 5**, Wild completes on action **13**, Blocker emits only `Drew` | case 20 |
| case 26, the `Livelock` fixture through the REAL `apply` | valve seed **1**, first firing on action **113**, escape into a completion on action **114** | case 26 |
| case 27, the same fixture with the valve off | 2,000 actions, 0 firings, 0 completions, `hashes[17] == hashes[33] == hashes[49]`, `hashes[2000] == hashes[16]` | case 27 |

The **113** matches plan 02-13's independently measured number exactly, and it reproduced for every
valve seed tried (1, 2, 3, 11) — `armed` flips during action 96 (a Pass, so nothing is hashed), the
first armed observation is 97, and the firing lands one full 16-action lap later at 113. Nothing in
this plan was adjusted to make it match.

The escape is the strongest part of the result: a table that provably never completes in 2,000
actions with the valve off, and whose observation-point hash recurs every 16 actions forever, is
forced to pass card 1 at action 113 and **completes rank 2 (retiring `{3, 4, 9, 10}`, fifth = 2) at
action 114**. Verbatim from the firing and the escape:

```
action 113: Drew,ValveForcedPass,Passed
   [1] Drew seat=1 card=9
   [2] ValveForcedPass seat=1 card=1 to=2 lap=113
   [3] Passed seat=1 card=1 to=2
   seat 1 hand size right after = 4
   valve.firings=1 lap=113 completions=0
action 114: Drew,Completed,SeatRemoved
   [1] Drew seat=1 card=10
   [2] Completed seat=1 rank=2 retired=3,4,9,10 fifth=2
   [3] SeatRemoved seat=1 cause=Completed routedTo=2 cards=1
   liveCount=1 head=2 accepted=114 observations=114
```

**The honest claim, as written into the module and the spec:** the valve eliminated **observed**
stalls for a good pool — 0 of 4,000 rounds at k=1,j=1 and at k=2,j=1 — and reduced but did not
eliminate them at k=2,j=2 (21.600% to **0.025%**). It is a demonstrated property of a selected
configuration, never an unconditional property of the engine, and
`grep -qiE 'guarantees zero|theorem about the engine' src/server/engine/Engine.luau` exits 1.

## Counter ownership, as actually implemented

| concern | owner |
|---|---|
| `churnRemovals += 1` when `cause ~= "Completed"` | `Ring.removeSeat` |
| `rankInPlay` / `jokersInPlay` / `cnt` for cards dumped to `terminal` | `Ring.removeSeat`, no-successor branch only |
| the same counters for ROUTED cards | nobody — routing to an inbox does not take a card out of play |
| `rankInPlay` / `jokersInPlay` / `cnt` for the four RETIRED cards, and `completions` | `Engine.apply`, completion path only |
| `valve.*` | `Valve`, through the one block at the end of `apply` |

The retirement runs **before** `removeSeat(..., "Completed")`, so the hand holds only the fifth card
when the seat leaves. Net effect on circulation across a completion: zero. Mutations M9 (retirement
skipped) and M10 (`churnRemovals` double-counted) are both caught.

## Task Commits

1. **Task 1: `Engine.newRound`**
   - `2d72a75` test(02-07): failing newRound spec (RED)
   - `2c99339` feat(02-07): Engine.newRound — assemble a dealt state (GREEN)
2. **Task 2: `Engine.apply`**
   - `02138fa` test(02-07): failing apply spec — the seven reject codes (RED)
   - `f822e12` feat(02-07): Engine.apply — validation, the seven codes, the completion chain (GREEN)
3. **Task 3: the spec completed**
   - `bbfb3aa` test(02-07): apply.spec — the completion chain, CARD-12 and the valve end to end
   - `938955b` test(02-07): lock the Draw precedence too — HandNotFour before InboxEmpty

No REFACTOR commit: `apply` passed all 27 cases on its first GREEN run and there was nothing to
clean up. The 28th case came out of the mutation battery, not out of a refactor.

## The 28 cases

| # | case | what it pins |
|---|------|--------------|
| 1 | newRound deals 9 seats of 4 with the whole supply in the dealer's inbox | CARD-09 via `Pool.deal`, research 3.8 |
| 2 | the LOCKED deal layout, exact arrays | replay determinism |
| 3 | the valve cold, the counters scanned, the valve seed DERIVED from the round's | M24 |
| 4 | DeadPool and an empty seat list are refused by name | amendment A5 |
| 5 | reproducible from the seed alone | deepEqual over a closure-free snapshot |
| 6-17 | **twelve rejection rows** covering all seven codes | the code, `#events == 0`, an unchanged hash, an unmoved valve |
| 15 | `NotYourCard` for a card in the actor's OWN inbox | research 7.6 |
| 16 | `UnknownCard` before `HandNotFive` | precedence pair 1 |
| 17 | `HandNotFour` before `InboxEmpty` | precedence pair 2 (added by mutation M1) |
| 18 | a legal draw at exactly 4 | CARD-01 positive |
| 19 | a legal pass at exactly 5 lands at the successor's inbox TAIL | CARD-03 positive |
| 20 | the completion chain from ONE apply, seat already gone on return | CARD-07 |
| 21 | the IDENTICAL recorded sequence completes in Wild, not in Blocker | CARD-12 |
| 22 | all three — two — removal causes route identically | CARD-08, rule 8 |
| 23 | a `Remove` intent may not carry `Completed` | T-2-35 |
| 24 | a departed seat's own intents are refused while a pass TARGETING it lands downstream | research 7.6, both ends |
| 25 | the whole seats 2..9 x k x j x mode grid is clean and reproducible | 96 rounds, 192 deals |
| 26 | the valve fires end to end through the real `apply` | CARD-11 |
| 27 | **MUTATION:** with `antiLivelockValve = false` the identical fixture never escapes | the fixture really is a cycle |
| 28 | `apply` never yields and hands control to nobody | rules 5 and 6, static scan |

Cases 26 and 27 fail for **opposite** reasons: 26 if the valve is not wired, 27 if the fixture is not
really a cycle. Case 27's completion-freedom is **scanned** at every one of 2,000 actions (every live
hand, four copies of a rank), not read off `counters.completions`, which would also pass if the
engine simply stopped detecting completions — the same correction plan 02-13 made to its own case 4.

## Mutation proof — verbatim

**28 mutations, 28 caught.** Each was applied to `src/server/engine/Engine.luau`, the spec was run,
and the file was restored with `git checkout --` (`git status` clean afterwards). The first pass ran
25 mutations and **three survived**; all three are resolved below.

```
baseline: 28 passed, 0 failed, 0 todo in 0.25s (exit 0)
M1  RED (caught) -- Draw precedence inverted: InboxEmpty checked before HandNotFour
     27 passed, 1 failed
     FAIL HandNotFour is checked BEFORE InboxEmpty: the reject code (expected HandNotFour, got InboxEmpty)
M2  RED (caught) -- Pass precedence inverted: HandNotFive checked before UnknownCard
     24 passed, 3 failed  (Pass of card id 0; Pass of totalCards + 1; UnknownCard before HandNotFive)
M3  RED (caught) -- NotYourCard scans EVERY container, so a card in the actor's own inbox is accepted
     26 passed, 1 failed  (NotYourCard also covers a card sitting in the actor's OWN inbox)
M4  RED (caught) -- the SeatNotLive check removed: a dead seat may act
     25 passed, 2 failed
M5  RED (caught) -- every rejection returns ONE generic code (the Phase 1 defect class)
     16 passed, 11 failed
M6  RED (caught) -- a rejection mutates: the valve is observed before validation
     13 passed, 14 failed
M7  RED (caught) -- a rejection returns a nil event list instead of an empty table
     15 passed, 12 failed
M8  RED (caught) -- a "defensive" completion check added AFTER the pass
     21 passed, 7 failed
     FAIL a legal pass at exactly 5 ...: Hand.detectCompletion: hand must hold 5, got 4
M9  RED (caught) -- the retirement is skipped, so the completed four never leave play
     25 passed, 2 failed
M10 RED (caught) -- churnRemovals incremented here too, double-counting what removeSeat owns
     25 passed, 2 failed
M11 RED (caught) -- the removal is split out of the completing apply, leaving the seat live
     25 passed, 2 failed
M12 RED (caught) -- the event order inverted: Completed is emitted before Drew
     20 passed, 7 failed
M13 RED (caught) -- the valve block removed: nothing calls it (what a Phase 4 tick would have risked)
     25 passed, 2 failed
M14 RED (caught) -- the progress entry point used for a non-completing draw, so the window never fills
     25 passed, 2 failed
M15 RED (caught) -- drewAtSeat is always nil, so the valve can never fire
     26 passed, 1 failed
M16 RED (caught) -- the forced pass is marked but never performed
     26 passed, 1 failed
M17 RED (caught) -- the ValveForcedPass marker dropped, so a forced pass looks like a choice
     26 passed, 1 failed
M18 RED (caught) -- the Passed event folded into the marker, breaking one-event-per-movement
     26 passed, 1 failed
M19 RED (caught) -- lap read BEFORE the valve observes the action, so the metric is stale by one
     26 passed, 1 failed
M20 RED (caught) -- a Remove intent may carry Completed, so one intent breaks conservation
     26 passed, 1 failed
M21 RED (caught) -- newRound deals the dealer's inbox DESCENDING
     21 passed, 6 failed
M22 RED (caught) -- newRound overlaps the hands: seat s gets ids s..s+3
     4 passed, 23 failed
M23 RED (caught) -- newRound leaves the histogram at zero
     4 passed, 23 failed
M24 RED (caught) -- newRound seeds the valve with a constant instead of a draw off the round's rng
     26 passed, 1 failed  (newRound initialises the valve cold and the counters by scanning)
M25a RED (caught) -- newRound's layout broken, self-check INTACT
     4 passed, 24 failed
     Engine:155: Engine.newRound: the deal produced an illegal state (partition-identity)
M25b RED (caught) -- the SAME layout break with newRound's self-check REMOVED
     19 passed, 9 failed
     a freshly dealt round reported partition-identity (expected a truthy value, got false)
     seat 2 holds ids 5..8 (expected { 5, 6, 7, 8 }, got { 2, 3, 4, 5 })
     the state after a legal draw reported partition-identity
restored: 28 passed, 0 failed, 0 todo in 0.28s (exit 0)
```

### The three first-pass survivors, and what each one meant

**M1 — a real gate gap, and the plan's.** Inverting the Draw precedence survived the entire spec:
the plan locked both precedence pairs but supplied a distinguishing case only for the Pass pair
(`UnknownCard` before `HandNotFive`). Nothing named an intent illegal on *both* Draw counts, so
`HandNotFour` and `InboxEmpty` were interchangeable as far as the suite could tell. **Fixed by adding
case 17**, which builds the situation the way the live round builds it — seat 1 draws, passes, and
seat 2 draws the single card it was given, reaching a hand of five with an empty inbox. This is the
sixth plan-level assertion gap found in this phase and the third found by an executor.

**M8 — the plan's variant was unobservable by theorem, so the gate is the grep.** A completion check
added to the pass path *after* the pass can never fire: the hand is 4 there, and a correct
`detectCompletion` on the *pre*-pass hand cannot fire either, because the hand has not changed since
the draw that already failed to complete ("passing can only leave a subset of a hand that already had
none"). So the dead-code variant is genuinely unfalsifiable at runtime and its only possible gate is
the static one the plan already specified — `grep -c 'detectCompletion' == 1`, verified. The mutation
recorded above is the realistic shape instead: the "defensive" check a later developer would add
without a hand-size guard, which errors out of `Hand.detectCompletion` and takes 7 cases down.

**M25 — a tripwire, proven by a PAIRED mutation.** Removing `newRound`'s own `Invariants.check`
changes nothing while the deal is correct, so it cannot fail alone — by construction, like
`Invariants`' own violation 9. It is proven load-bearing by breaking the layout twice: with the check
in place the failure is **one named violation raised at the deal** (`partition-identity`, from
`Engine.luau` line 155, 24 cases down); with the check removed the corrupt round is **playable** and
the damage surfaces as 9 scattered downstream assertion failures instead. That difference is the
whole value of the check, and it is now on the record.

## Verification

```
stylua --check src scripts tests                                        ok
selene src scripts tests                                                0 errors, 0 warnings
selene --config selene.pure.toml src/server/engine                      0 errors, 0 warnings
analyze --platform standard (src/server/engine, scripts, tests)         ok
check-guards                                                            ok (76 files, 176 requires, 20 guarded roots)
lune run tests/run.luau -- --filter engine/apply                        28 passed, 0 failed
lune run tests/run.luau -- --filter engine                              137 passed, 0 failed, 3 todo in 0.66s
lune run tests/run.luau                                                 459 passed, 0 failed, 3 todo in 15.60s
lune run scripts/verify.luau                                            all 14 automated steps passed in 17.5s
```

Every acceptance grep for all three tasks re-run and passing, including the six that must FAIL:
`os\.|coroutine|game|Instance|math.random`, `state.attempts`, `Invariants.hash` (in `Engine.luau`),
`guarantees zero|theorem about the engine`, a three-parameter `apply`, and
`publish|emit\(|listener|subscribe|callback`. Counted greps: `require(` = **6**, `detectCompletion`
= **1**, `Valve.afterAction|Valve.afterProgress` = **2**.

## Deviations from Plan

### Auto-fixed

**1. [Rule 2 — missing critical functionality] A `Remove` intent may not carry the `Completed` cause**
- **Found during:** Task 3, writing case 22 (the plan's case 8)
- **Issue:** the plan asks for all three causes through one `Remove` intent with `Invariants.check`
  clean after each. That is **impossible** for `Completed`, and the plan's own dependency summary
  explains why: `removeSeat` leaves `churnRemovals` alone for that cause because the completion path
  has already retired four cards. A `Remove{cause = "Completed"}` skips the retirement, so its four
  resting cards route into the successor's inbox with nothing leaving play, `circulation` gains 4,
  `expectedCirculation` does not, and `check` reports `circulation` — permanently, for the rest of
  the round, from ONE intent. That is threat T-2-35 (crafted intent desynchronising card accounting,
  disposition *mitigate*) with no mitigation, at the exact trust boundary the plan's threat model
  names.
- **Fix:** `apply` raises a caller-bug `error` naming the cause and the correct path. Deliberately
  **not** an eighth reject code: the plan locks seven, plan 02-08 asserts seven, and the house rule
  from `Ring` is that `error` fires only where the alternative is silent corruption and never where a
  reject code exists. Case 22 now covers the two causes an intent may legitimately carry (asserting
  identical routing by exact array AND canonical hash, with `churnRemovals` 1 for both), and case 23
  asserts the throw, the unchanged hash and the still-live seat.
- **Files:** `src/server/engine/Engine.luau`, `tests/engine/apply.spec.luau`
- **Commit:** `bbfb3aa`
- **For plan 02-08:** do **not** generate `Remove{cause = "Completed"}` in the fuzzer; it throws by
  design. Generate `Disconnected` and `Benched`; `SeatRemoved{cause = "Completed"}` coverage comes
  from completing draws, which is where research §11.3 wants it from anyway.
- **For Phase 4:** the adapter must bind the cause from the lifecycle event (a disconnect or an AFK
  strike-out) and can never obtain this one.

**2. [Rule 2 — unassertable gate] Case 17, the second precedence pair**
- **Issue:** see M1 above. The plan locked both ordered pairs in its `<interfaces>` block but
  supplied a distinguishing case for only one of them.
- **Fix:** case 17 added. **Commit:** `938955b`

**3. [Rule 2 — untested wiring] The valve seed's derivation asserted**
- **Issue:** the plan's step 3 explains carefully why the valve's generator is derived from the
  deal's rather than shared with it, and nothing in the spec could have noticed a hardcoded
  constant: `snapshot` cannot compare `valve.rng` (a table of closures) and the end-to-end valve
  cases seed `Livelock` directly.
- **Fix:** case 3 now asserts both directions — the same round seed replays the same valve draws, a
  different round seed does not. Mutation M24 makes it fail. **Commit:** `bbfb3aa`

**4. [Rule 2 — un-catchable corruption] The `rejects` helper asserts the valve did not move**
- **Issue:** the plan's `rejects` helper asserts an unchanged `Invariants.hash`. That cannot catch a
  valve entry point called on a rejection, because `Invariants.hash` **excludes** `valve` by design
  (it must, or no state could ever repeat and the valve could never fire). The locked valve call rule
  says "neither on a rejection", and without this the rule was asserted nowhere for 11 of the 12
  rejection rows.
- **Fix:** every rejection row also asserts `valve.observations` and `valve.actionsSinceProgress`
  unchanged. Mutation M6 takes 14 cases down because of it. **Commit:** `02138fa`

### Process notes, not defects

- **`UnknownCard` covers a fractional or NaN card id.** The plan says "`cardId` outside
  `1..totalCards`"; a NaN compares false against both bounds, so a literal reading would fall through
  to `NotYourCard`. An id that is not an integer in range names no card, so `UnknownCard` is the
  legality answer, and the shape layer still owns refusing it as a malformed payload. Recorded in the
  code.
- **`Pool.deal`'s attempt count is not captured at all** rather than captured into an unused local
  as the plan's step 2 writes it: an unused local is a `selene` warning, and the plan's own acceptance
  criterion wants `attempts` absent from `State`. The reason it is not captured is commented at the
  call site.
- **TDD shape.** Tasks 1 and 2 are `tdd="true"` but own only `src/server/engine/Engine.luau`, while
  the spec belongs to task 3. Following plan 02-06's precedent, each task's RED commit was written
  into the spec file anyway rather than skipping the gate: `2d72a75` (RED, 1 failed — the module does
  not exist) and `02138fa` (RED, 13 failed — `apply` does not exist). See TDD Gate Compliance below.
- **Whole-suite and `scripts/verify.luau` runs.** Run as instructed; this plan is wave 4 and runs
  alone, so no sibling can be mid-TDD.
- **Nothing was logged to `deferred-items.md`.** No out-of-scope defect was found; the file was not
  created.

## TDD Gate Compliance

Gate sequence from `git log`, oldest first:

- `2d72a75` **test** — RED, 0 passed / 1 failed (`Engine` does not exist)
- `2c99339` **feat** — GREEN, 5 passed / 0 failed (`newRound`)
- `02138fa` **test** — RED, 5 passed / 13 failed (`apply` does not exist)
- `f822e12` **feat** — GREEN, 18 passed / 0 failed (`apply`)
- `bbfb3aa` **test** — the spec completed, 27 passed / 0 failed
- `938955b` **test** — the mutation-driven 28th case

Both RED and GREEN gates are present, in order, twice. No REFACTOR gate: nothing needed cleaning.

## Known Stubs

None. `Engine.luau` has no placeholder value, no TODO/FIXME and no unwired data path. Every branch is
exercised by a case: both joker modes, all seven reject codes, all three removal causes (two by
intent and `Completed` by the completion path), the valve's fire and no-fire paths, and the
`routedTo == nil` ring-emptied path through `Ring` (covered by plan 02-06's removal spec rather than
re-tested here).

## Issues Encountered

None. The suite went green on the first GREEN run for both `newRound` (5/5) and `apply` (18/18); the
only correction came from the mutation battery.

## Next Phase Readiness

**Plan 02-08 (the fuzz suite)** can build directly on the interface above. Five things it must honour:

1. **Seven reject codes, not six.** Research §11.3 undercounts. Assert minimum observations for each
   of `UnknownSeat`, `SeatNotLive`, `UnknownCard`, `NotYourCard`, `HandNotFour`, `HandNotFive`,
   `InboxEmpty`.
2. **`state.valve.observations == acceptedActions`** holds exactly, and a rejection does not move it.
   Case 26 already proves it at 114 accepted applies with one rejection injected.
3. **Do not fuzz `Remove{cause = "Completed"}`** — it throws by design (see deviation 1).
4. **Every card movement has exactly one `Drew` or `Passed`**, including a forced pass, whose
   `ValveForcedPass` marker precedes its `Passed`.
5. **`apply` does not call `Invariants.check`.** Calling it after every fuzzed action is 02-08's job
   and the cost belongs there (research §11.1: 1.7x the counters alone).

**Plan 02-09 (the simulator)** gets `newRound` as a one-seed round constructor, `Pool.deal`'s attempt
count from `Pool.deal` rather than from `State`, and `--filter engine` at **0.66s** as the wall-time
baseline to budget its CI subset against.

**Plan 02-14** inherits plan 02-13's warning unchanged: if a measured firing rate diverges from the
reference, the arm gate is only one of three candidate causes. This plan changed neither the firing
point nor the choice rule, and it adds no fourth candidate — `apply` performs the pass the valve
names and nothing else.

**Phase 4** gets the three contracts above plus: `Intent.Pass` has no `to`, `target` or `index`
field, so a wire payload has nowhere to put one; `Intent.seat` must be BOUND by the adapter from the
authenticated player and never read from a payload (the engine's own defences are `SeatNotLive` and
`NotYourCard`); and the dealer's inbox holds the whole circulating supply at the deal, so far seats
need a "waiting for cards" affordance for the first ~8 seconds at a full roster (research §3.8).

---
*Phase: 02-card-engine-and-pacing-simulator*
*Completed: 2026-11-03*

## Self-Check: PASSED

- `src/server/engine/Engine.luau` (385 lines) — FOUND
- `tests/engine/apply.spec.luau` (795 lines) — FOUND
- commits `2d72a75`, `2c99339`, `02138fa`, `f822e12`, `bbfb3aa`, `938955b` — all FOUND in `git log`
- working tree clean apart from this summary
- every acceptance grep for all three tasks re-run; all 28 mutations re-run from the restored file
  and the baseline is green at `28 passed, 0 failed`
