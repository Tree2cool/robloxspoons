---
phase: 02-card-engine-and-pacing-simulator
plan: 08
subsystem: testing
tags: [fuzz, property-testing, conservation, partition-identity, reject-codes, coverage-floors, mutation-proof, anti-livelock-valve]

requires:
  - phase: 02-01
    provides: "Invariants.check (nine violations, locked order), Invariants.hash (the canonical state identity), Invariants.circulation, and the Types vocabulary"
  - phase: 02-04
    provides: "Pool.poolConfig — the ONE site that owns amendment A3's seatCount = N - 1 and the shipped valve position"
  - phase: 02-07
    provides: "Engine.newRound / Engine.apply, the locked reject precedence, the locked event order, and the locked valve call rule"
  - phase: 02-13
    provides: "Valve.new / afterProgress / afterAction and the ValveState counters this suite reads"
  - phase: 01-02
    provides: "tests/harness/Test.luau (FuzzOpts / FuzzDriver) and tests/harness/Fuzz.luau (the injected gen/check driver)"
provides:
  - "tests/engine/fuzz.spec.luau — ONE stateful fuzz case whose iteration is a whole round, running 500 rounds and a measured 194,567 actions with the full four-bucket partition identity checked after every single action"
  - "ROADMAP Phase 2 success criterion 1, proven: across 194,567 fuzzed actions at every seat count from 2 to 9, with random pools, random churn, idle seats, mid-pass departures and deliberately illegal intents, no card was ever lost, duplicated or swapped"
  - "A coverage gate that fails loudly: the suite asserts its own action count, a floor for every event kind, every removal cause, all four ring-shrink milestones, all SEVEN reject codes, the valve's observation depth and checksRun >= totalActions"
  - "The carried Phase 1 todo closed with a number: the harness has run 194,567 actions, not a toy property at 200 iterations"
  - "A measured full-suite wall time of 17.12-17.91s and `--filter engine` at 2.32-2.37s, which is what plan 02-09 must budget its CI subset against"
affects: [02-09, 02-10, 02-11, 02-12, 02-14, 04]

tech-stack:
  added: []
  patterns:
    - "A STATEFUL property on a stateless gen/check driver: `gen` returns a round PLAN rather than a state, `check` builds and drives the whole round, and the coverage totals live in spec-level locals closed over by `check`"
    - "Reproduction stated as TWO explicit purity contracts, because the printed seed is worthless if either breaks: `plan` is a pure function of the base seed and `i` (only `gen` touches the shared rng), and the round is a pure function of `plan` (every draw comes from `Rng.new(plan.roundSeed)`, and `check` only ever WRITES the accumulators). That is why the illegal-shape rotation and the churn cause are derived from `plan.i` plus a per-round counter rather than from a cross-round counter"
    - "A per-action check that feeds a COUNTER plus a captured first-offender reproduction, rather than raising on the spot, wherever raising on the spot would make the end-of-run total structurally incapable of failing"
    - "The coverage gate lives inside the fuzz case on its final iteration, never in a sibling case: a substring filter that selected the fuzz case without a sibling counter case would read GREEN while asserting nothing about coverage"
    - "A load constant written as a literal at the call site AND tied to the spec's own copy by a registration-time check, because a half-edit downward silently skips the coverage block"
    - "An honest non-floor: a quantity the suite cannot meet honestly is RECORDED and reported, not floored at 1 and not quietly floored at 0"

key-files:
  created:
    - tests/engine/fuzz.spec.luau
  modified: []

key-decisions:
  - "The three valve totals are the real gate and the per-action comparison feeds them, rather than the per-action comparison raising and the totals becoming decoration. If the per-action check errored immediately, `valveDepthMismatches == 0`, `valveObservationsOnRejection == 0` and `valveObservations == acceptedActions` would all be unreachable by construction — three un-failable checks, the defect class this phase has now found six times. The per-action comparison therefore increments a counter and captures the FIRST offender's reproduction text, and the end-of-run assertion carries that text in its message. Mutations 3 and 4 are the proof that the result can still fail, and still names the offending round"
  - "`valveDepthMismatches` and `valveObservationsOnRejection` get SEPARATE captured reproductions. A single shared slot reported whichever defect lost the race, which mutation 4 exposed: a valve observed before validation trips both counters and the shared slot showed the depth round for the rejection message"
  - "The two valve defects are counted per action and the two illegal-intent assertions (code and unchanged hash) raise immediately. The split is deliberate: state corruption compounds, so the conservation checks must stop at the first bad action, while a bookkeeping counter is still diagnosable 499 rounds later and is worth more as a failable total"
  - "`iterations = 500` is a literal in the opts (visible load at the call site) and `ITERATIONS = 500` is the spec's copy; a registration-time check ties them. A half-edit UPWARD would run the coverage block early and the floors would fail loudly, but a half-edit DOWNWARD would skip the coverage block entirely and this file would verify nothing about itself. Mutation 1a is the proof"
  - "Eight illegal constructions for seven codes. `NotYourCard` has two shapes because research 7.6 distinguishes them — a card held by another seat, and a card of the actor's own that an auto-pass already moved into an inbox — and plan 02-07's mutation M3 is caught only by the second"
  - "A shape whose precondition the current state cannot express (no dead seat yet, nobody holding five) is SKIPPED and the cycle advances, never weakened to 'some rejection'. Shape 1 (UnknownSeat) needs nothing from the state, so the cycle can always produce something while a seat is live"
  - "The legal-action enumeration buffers are hoisted to round scope. A fresh pair per action allocated twice per action across 170,332 accepted actions and showed up as 0.3-0.5s of GC in the case's wall time; the totals are byte-identical before and after (194,567 both ways), which is itself a check that the buffers carry nothing over"
  - "No floor on the valve's firing count, and not a floor of zero either. Observed: 0 firings across 291 armed rounds of 500. Under near-random play a table deviates constantly, so a whole-table state repeat is legitimately rare and a floor would flake at any value. The firing PROOF stays in 02-13's deterministic cycle fixture and 02-07's end-to-end case"

patterns-established:
  - "Six mutations, six caught, four of them beyond the two the plan named. The two named ones prove the plan's gates; the other four prove the gates this plan invented (the valve totals, checksRun, and the identity scan's own reproduction claim)"
  - "The reproduction claim proven by three runs, not asserted: the same base seed reports the identical failure text twice, and a different base seed reports a different round seed and a different pool — so the printed number really is what drives the trial"

requirements-completed: [CARD-01, CARD-03, CARD-04, CARD-07, CARD-08]
requirements-contributed: []

duration: ~70 min
completed: 2026-11-03
---

# Phase 2 Plan 08: The 100,000-Action Conservation Fuzz Summary

**One stateful fuzz case whose iteration is a whole round: 500 rounds and 194,567 actions across every seat count from 2 to 9, with random pools, 1% churn, 12% deliberately illegal intents and the full four-bucket partition identity checked after every single action — and a coverage gate that asserts its own action count, every event kind, every removal cause, all four ring-shrink milestones, all seven reject codes and the valve's observation depth, so the suite cannot read green while testing nothing. Six mutations applied, watched failing, and restored.**

## Performance

- **Duration:** ~70 min (2026-11-03)
- **Tasks:** 2
- **Files created:** 1 (`tests/engine/fuzz.spec.luau`, 814 lines)
- **Cases added:** 2; suite **461 passed, 0 failed, 3 todo** (baseline 459)

| measurement | value | note |
|---|---|---|
| **this plan's fuzz case** | **1.91 - 2.00s** | budget was 3.0s; measured 1.99 / 2.00 / 1.92 over three runs |
| **full suite** | **461 passed, 0 failed, 3 todo in 17.12 - 17.91s** | **plan 02-09 budgets against this** |
| `--filter engine` | `139 passed, 0 failed, 3 todo in 2.32 - 2.37s` | was 0.66s at 02-07; see "For plan 02-09" below |
| `scripts/verify.luau` | all 14 automated steps passed in **19.0s** | |

The case came in at **2.49s before** the buffer hoist and **1.91-2.00s after**, against the plan's
3.0s stop-and-report line. Research 11.1 budgeted ~0.3s for 100k actions of pure identity scan and
~0.9s with a 3x pessimism factor; the measured 194,567 actions at ~98,000 actions/s is ~3.5x the
scan-only throughput of 343,502 actions/s, and the difference is this suite's own work: the legal-action
enumeration, two `Invariants.hash` calls per illegal attempt (48,470 of them), and the valve hashing
every draw in the 291 rounds that armed. **Nothing was trimmed to fit.**

## The observed load and the full coverage table

Recorded here verbatim so a later regression can be diffed against it. This is the printed output
of the passing case, and it is deterministic — byte-identical across every run at seed 20260203.

```
  fuzz coverage (plan 02-08):
  totalActions       194567   (accepted 170332, rejected 24235)
  checksRun          194567
  rounds             500   (longest 1414 actions, shortest 1)
  events             Drew 84626   Passed 83317   Completed 274   SeatRemoved 2663   ValveForcedPass 0
  completion shapes  4 naturals 152   3+1j 93   2+2j 29
  removal causes     Completed 274   Disconnected 1195   Benched 1194
  ring milestones    dealer removed 484   ring to 2 437   ring to 1 500   ring emptied 464
  reject codes       UnknownSeat 6282   SeatNotLive 2449   UnknownCard 3579   NotYourCard 5112   HandNotFour 2602   HandNotFive 2627   InboxEmpty 1584
  valve              observations 170332   firings 0   armed rounds 291   seen resets 0
  valve defences     depth mismatches 0   observations on a rejection 0
  rounds by seatCount  2:63  3:66  4:71  5:64  6:63  7:54  8:56  9:63
```

| claim | floor | observed | margin |
|---|---|---|---|
| **action count** | 100,000 | **194,567** | 1.95x |
| `Drew` | 20,000 | 84,626 | 4.2x |
| `Passed` | 20,000 | 83,317 | 4.2x |
| `Completed` | 200 | 274 | 1.37x |
| naturals-4 completions | 100 | 152 | 1.52x |
| 3+1 joker completions | 10 | 93 | 9.3x |
| **2+2 joker completions** | 1 | **29** | observed, see below |
| `SeatRemoved{Completed}` | 200 | 274 | 1.37x |
| `SeatRemoved{Disconnected}` | 50 | 1,195 | 23.9x |
| `SeatRemoved{Benched}` | 50 | 1,194 | 23.9x |
| dealer (seat 1) removed | 1 | 484 | |
| a removal reduced the ring to 2 | 1 | 437 | |
| a removal reduced the ring to 1 | 1 | 500 | every round |
| the ring emptied (`terminal` exercised) | 1 | 464 | |
| `UnknownSeat` | 10 | 6,282 | |
| `SeatNotLive` | 10 | 2,449 | |
| `UnknownCard` | 10 | 3,579 | |
| `NotYourCard` | 10 | 5,112 | |
| `HandNotFour` | 10 | 2,602 | |
| `HandNotFive` | 10 | 2,627 | |
| `InboxEmpty` | 10 | 1,584 | |
| `checksRun >= totalActions` | 194,567 | 194,567 | exact |
| `valveObservations == acceptedActions` | 170,332 | 170,332 | exact |

The two tightest floors are `Completed` and `SeatRemoved{Completed}` at **1.37x**. Both are the same
quantity (every completion removes its seat inside the same apply), and both are tighter than they
look safe at, for a reason worth recording: **most rounds end in churn rather than in completions.**
See "What the generator actually explores".

### The 2+2 joker completion shape WAS observed: 29 times

The plan asked for this to be a conscious finding either way. It occurs. Research 3.3's analysis holds
exactly: naturals-first never *chooses* 2+2 because it is strictly worse on both axes, so the shape
only arises when a five-card hand holds **both jokers plus exactly two naturals of the qualifying
rank** and no better rank qualifies. That needs `j = 2` and `jokerMode = "Wild"`, which is 1 in 6 of
this generator's rounds (~83 of 500), and 29 observations across those is consistent with the two
jokers co-occurring in one hand of five a couple of times per such round. Note the shape is
self-limiting within a round: a 2+2 completion retires both jokers, and a 3+1 retires one, so a round
can produce at most one 2+2.

## The valve numbers, and the explicit statement the plan asked for

| quantity | observed | is it zero? |
|---|---|---|
| `valve.observations`, summed | **170,332** | no — and it equals `acceptedActions` **exactly** |
| `valve.observations` on a rejected action | **0** | **yes, and zero is the required value** |
| per-action observation-depth mismatches | **0** | **yes, and zero is the required value** |
| `valve.firings`, summed | **0** | **yes. This is RECORDED, not floored. See below.** |
| rounds whose valve armed | **291** of 500 | no |
| `valve.seenResets`, summed | 0 | yes — no round's seen-window reached `VALVE_SEEN_CAP` (4096) |
| `ValveForcedPass` events | **0** | yes, consistent with 0 firings |

**`valveFirings == 0` across 194,567 actions, and that is the honest result, not a gap.** No floor was
placed on it and none was set to zero to have a floor — that is exactly the `autoPassRate == 0` defect
class the phase checker rejected in this phase's first draft. The reason it is zero is informative
rather than suspicious: the valve fires only when the whole table returns to a state it has already
been in with no completion and no removal since, and this generator plays **uniformly at random**,
which is precisely the policy research 3.6 measured as the one that does not livelock. A random
walk over inbox orderings essentially never revisits an exact prior state.

**`armedRounds = 291` is the surprising number and it is not a defect.** It is high because of the
sole-seat endgame (below): with `liveCount == 1` the arm gate is `48 x 1 = 48` actions of no progress,
which a sole seat crosses easily, so 58% of rounds armed and then hashed every draw without a single
repeat. That is a positive result about the arm gate being a pure COST gate — it armed 291 times and
changed nothing about play 291 times.

The firing PROOF remains where the plan put it: plan 02-13's deterministic cycle fixture, and plan
02-07's case 26, where the fixture fires on action 113 and escapes into a completion on 114.

## What the generator actually explores (and the one thing to know about it)

The plan's termination rule is "`liveCount == 0`, or completions reach `seatCount - 1`, or the
4,000-action cap". Combined with 1% churn that has a consequence worth writing down, because it shapes
every count above:

- churn removes seats faster than completions retire them, so **`liveCount` reaches 1 before
  `completions` reaches `seatCount - 1` in essentially every round** — `ring to 1` fired in **500 of
  500 rounds**;
- the round then continues with a **sole seat passing to itself** until it either completes (round
  ends on the completion target) or is churned out (`ring emptied`, 464 of 500 rounds);
- at 1% per action the sole-seat endgame is ~100 actions in expectation, which is what bounds it, and
  which is why the 4,000-action cap was never approached (longest round **1,414** actions, 2.8x of
  margin).

So roughly a quarter to a third of the 194,567 actions are sole-seat play. That is not wasted: it is
research 7.3's regime, it is the only way `state.terminal` and the no-successor branch get exercised
(464 times here), and the partition identity is checked just as hard there. But it is also **why
`Completed` sits at only 274** against 2,389 churn removals, and why that floor has the least margin
in the table. **A future edit that lowers `churnChance` would raise the completion counts and lower
the ring-emptied count; an edit that raises it would do the reverse and could take `Completed` under
its floor.** Both directions fail loudly, which is the point.

Seat-count coverage is even across the whole legal space: 2:63, 3:66, 4:71, 5:64, 6:63, 7:54, 8:56,
9:63 — every seat count from 2 to 9, which is every roster from 3 to 10 players.

## Mutation proof — verbatim

**Six mutations, six caught.** The plan named two; the other four prove the gates this plan invented,
which the plan's two cannot reach. Every mutation was applied, the suite was run, and the file was
restored (`git status` clean after each; `src/` restored with `git checkout --`). The two named
mutations below were re-run against the FINAL committed file, not an earlier draft.

```
baseline: 2 passed, 0 failed, 0 todo in 1.91s (194,567 actions)
```

### Mutation 1a (named by the plan, half-edit): `iterations = 500 -> 5` only

The registration-time tie fires before a single round runs, which is the whole reason it exists:

```
FAIL tests/engine/fuzz.spec.luau::<register>
     /home/user/robloxspoons/tests/engine/fuzz.spec:795: fuzz.spec: opts.iterations (5) must equal ITERATIONS (500)
0 passed, 1 failed, 0 todo in 0.26s
```

### Mutation 1b (named by the plan): `iterations` AND `ITERATIONS` both `-> 5`

The action-count floor fails with the observed total in the message, as required:

```
FAIL tests/engine/fuzz.spec.luau::500 whole rounds: the partition identity holds after every one of 100,000+ actions
     fuzz "500 whole rounds: ..." failed at iteration 5 with seed 20260203: .../fuzz.spec:783: fuzz coverage FAILED after 5 rounds -- the suite ran but did not exercise everything it claims:
       * action count: 1626 actions over 5 rounds, need at least 100,000. A generator bug that shortens rounds is research 11.3's first way for a fuzz suite to be theatre
       * Drew events: 709, need at least 20,000 (the bulk of play; a floor of 1 would pass on a broken driver)
       * Passed events: 695, need at least 20,000 (the bulk of play; a floor of 1 would pass on a broken driver)
       * Completed events: 3, need at least 200 -- without completions the four-of-a-kind path, the retirement and the completion chain are all untested
       * natural completions (naturalsUsed == 4): 1, need at least 100 -- the ordinary completion shape
       * 3+1 joker completions (naturalsUsed == 3): 1, need at least 10 -- the Wild-mode joker path is otherwise untested
       * SeatRemoved with cause "Completed": 3, need at least 200 -- the removal that happens inside the completing apply
       * SeatRemoved with cause "Disconnected": 9, need at least 50 -- without it mid-pass departures are untested (research 7.6)
       * SeatRemoved with cause "Benched": 10, need at least 50 -- the AFK path through the one generic removal (CLAUDE.md rule 8)
       totalActions       1626   (accepted 1423, rejected 203)
       checksRun          1626
       rounds             5   (longest 747 actions, shortest 11)
1 passed, 1 failed, 0 todo in 0.32s
```

Note what **still passed** at 5 rounds: all four ring-shrink milestones, all seven reject codes and
every valve total. That is the honest reading of this mutation — the milestone and reject floors are
reached quickly and are NOT what defends the load; the action count and the five bulk floors are.

### Mutation 2 (named by the plan): `illegalChance = 0.12 -> 0`

All seven reject codes are named at 0 observations, and the full count table is printed:

```
FAIL tests/engine/fuzz.spec.luau::500 whole rounds: the partition identity holds after every one of 100,000+ actions
     fuzz "500 whole rounds: ..." failed at iteration 500 with seed 20260203: .../fuzz.spec:783: fuzz coverage FAILED after 500 rounds -- the suite ran but did not exercise everything it claims:
       * reject UnknownSeat: 0 observations, need at least 10
       * reject SeatNotLive: 0 observations, need at least 10 (threat T-2-39: an intent for a removed seat)
       * reject UnknownCard: 0 observations, need at least 10
       * reject NotYourCard: 0 observations, need at least 10
       * reject HandNotFour: 0 observations, need at least 10 (CARD-01, the draw-at-five refusal)
       * reject HandNotFive: 0 observations, need at least 10
       * reject InboxEmpty: 0 observations, need at least 10
       totalActions       185121   (accepted 185121, rejected 0)
       checksRun          185121
       rounds             500   (longest 1247 actions, shortest 1)
       events             Drew 91977   Passed 90733   Completed 248   SeatRemoved 2659   ValveForcedPass 0
       completion shapes  4 naturals 128   3+1j 92   2+2j 28
1 passed, 1 failed, 0 todo in 1.79s
```

### Mutation 3 (this plan's gate): the valve block removed from `Engine.apply`

Plan 02-07's M13 proved its own spec catches this; mutation 3 proves THIS plan's three valve totals do
too, and that the captured reproduction names the offending round:

```
       * the valve was observed the wrong number of times on 170332 accepted actions -- a wiring bug that
         skipped it inside a conditional would otherwise leave this suite green while Gate G1's mechanism
         never ran. First: iteration 1, roundSeed 1180063276, seatCount 2, pool ranks=4 jokers=2 mode=Wild
         k=2: valve.observations is 0 after 1 accepted applies in the round, at applies=1
       * valve observations 0 against 170332 accepted actions; they must be equal exactly (plan 02-07
         asserted it at 114 == 114 with a rejection injected)
       valve              observations 0   firings 0   armed rounds 0   seen resets 0
       valve defences     depth mismatches 170332   observations on a rejection 0
1 passed, 1 failed, 0 todo in 2.02s
```

### Mutation 4 (this plan's gate): `state.valve.observations += 1` at the top of `apply`, before validation

The valve runs on the refusal path. **`Invariants.hash` cannot see this** — it excludes `valve` by
design — so this is the mutation that justifies the separate counter:

```
       * the valve was observed the wrong number of times on 170332 accepted actions ... valve.observations
         is 2 after 1 accepted applies in the round, at applies=1
       * the valve was observed on 24235 REJECTED actions, need 0 -- a rejection must leave the state
         unchanged and the valve's counters are part of the state. Invariants.hash cannot catch this: it
         excludes valve by design. First: iteration 1, roundSeed 1180063276, ...
       * valve observations 364899 against 170332 accepted actions; they must be equal exactly
       valve              observations 364899   firings 0   armed rounds 291   seen resets 0
       valve defences     depth mismatches 170332   observations on a rejection 24235
1 passed, 1 failed, 0 todo in 2.17s
```

This mutation is also what exposed the shared-reproduction defect fixed before the commit: both
counters tripped, and a single `valveLeakRepro` slot reported the depth round in the rejection message.
They now capture separately.

### Mutation 5 (this plan's gate): the per-action `Invariants.check` moved inside a conditional

Exactly the defect `checksRun` exists for — "the suite could run 125k actions and check 400 states":

```
       * Invariants.check ran 24235 times over 194567 actions; it must run at least once per action, or
         the conservation claim covers only the states that happened to be checked
       checksRun          24235
1 passed, 1 failed, 0 todo in 1.37s
```

### Mutation 6 (this plan's headline claim): `Ring.draw` SWAPS a card

`table.insert(seat.hand, cardId)` became `table.insert(seat.hand, cardId - 1)`. A swap keeps the card
*count* right, so `partition-count` still passes and **only the full identity scan can see it** — which
is the whole reason research 4.2 put the scan on top of the counters. Caught on the **first action of
the first round**, with the reproducing seed:

```
     fuzz "500 whole rounds: ..." failed at iteration 1 with seed 20260203: .../fuzz.spec:525:
     iteration 1, roundSeed 1180063276, seatCount 2, pool ranks=4 jokers=2 mode=Wild k=2:
     Invariants.check reported "partition-identity" after a Draw at seat 1
     (expected=nil, applies=1, liveCount=2, completions=0) -- reproduce with Rng.new(1180063276)
```

**And the reproduction claim itself was tested, not asserted.** With mutation 6 in place:

- the suite was run **twice** and the failure text was **byte-identical** (`diff -q` clean), so the
  trial is deterministic;
- the base seed was then changed to `777`, and the reported trial changed to a completely different
  round — `iteration 1, roundSeed 813821435, seatCount 7, pool ranks=9 jokers=0 mode=Wild k=2` — so the
  printed number really is what drives the trial rather than decorating it.

The printed line is the unit test: `roundSeed`, `seatCount`, `ranks`, `jokers`, `mode` and `k` are
exactly the arguments of `Engine.newRound(Pool.poolConfig(seatCount + 1, k, j, mode), ids, Rng.new(roundSeed))`.

## Verification

```
stylua --check src scripts tests                                        ok
selene src scripts tests                                                0 errors, 0 warnings
selene --config selene.pure.toml src/server/engine                      0 errors, 0 warnings
lune run tests/run.luau -- --filter engine/fuzz                         2 passed, 0 failed, 0 todo in 1.91-2.00s
lune run tests/run.luau -- --filter engine                              139 passed, 0 failed, 3 todo in 2.32-2.37s
lune run tests/run.luau                                                 461 passed, 0 failed, 3 todo in 17.12-17.91s
lune run scripts/verify.luau                                            all 14 automated steps passed in 19.0s
```

Every acceptance grep for both tasks re-run and passing, including the one that must FAIL:

| grep | required | observed |
|---|---|---|
| `iterations = 500` | present | present |
| `seed = 20260203` | present | present |
| `roundSeed` | >= 5 lines | **21** |
| `Invariants.check` / `Invariants.hash` | present | present |
| `valve.observations` / `ValveForcedPass` / `valveObservations` / `checksRun` / `100_000` | present | present |
| `>= 1` | >= 10 lines | **20** |
| `t.test(\|t.fuzz(` | exactly 2 | **2** |
| **`valveFirings >= 1`** | **must exit 1** | **exits 1 — no dishonest floor** |

## Deviations from Plan

### Auto-fixed

**1. [Rule 2 — un-failable gate] The valve totals made failable, and the three of them are now the real gate**

- **Found during:** Task 1, writing step 7 of the plan's action ("after each accepted apply, assert
  `state.valve.observations` equals the number of accepted applies so far").
- **Issue:** the plan asks for a per-action **assertion** in task 1 and for the end-of-run totals
  `valveObservations == acceptedActions` and `valveObservationsOnRejection == 0` in task 2. Both, as
  written, cannot coexist as gates. If the per-action comparison raises, then the per-action invariant
  holds for every action on any passing run, which makes all three end-of-run totals true **by
  construction** — three checks structurally incapable of failing. That is the seventh plan-level
  assertion gap in this phase and the fourth found by an executor; the plan's own `<must_haves>` names
  the valve depth as one of its eight truths, so leaving it as decoration was not an option.
- **Fix:** the per-action comparison stays (it is still the strong, per-action form — a doubled
  observation on one action and a skipped one on the next would cancel in the global total and is
  caught per action), but it increments `valveDepthMismatches` / `valveObservationsOnRejection` and
  captures the FIRST offender's reproduction text instead of raising. The end-of-run assertions are the
  gate and carry that text. Mutations 3 and 4 are the proof that they fail, and that the message still
  names the offending round, seed and action index.
- **Not applied to the conservation checks.** `Invariants.check`, the reject code and the unchanged
  rejection hash all still raise immediately, because state corruption compounds and the first bad
  action is the only useful one; a bookkeeping counter is just as diagnosable 499 rounds later.
- **Files:** `tests/engine/fuzz.spec.luau`. **Commit:** `6699524`

**2. [Rule 2 — untested wiring] The iteration count tied to the spec's own copy**

- **Issue:** `check` has to know which iteration is the last one in order to run the coverage block,
  and the plan's acceptance criterion requires `iterations = 500` as a literal at the call site. Two
  copies of a number, and the dangerous direction is silent: an edit that lowers the opts literal but
  not the spec's copy means `plan.i == ITERATIONS` is never reached and **the coverage block never
  runs at all** — a file that would then verify nothing about its own load while reading green.
- **Fix:** a registration-time check that the two agree. Mutation 1a is the proof.
- **Files:** `tests/engine/fuzz.spec.luau`. **Commit:** `d8100be`

**3. [Rule 1 — wrong diagnostic] Separate captured reproductions for the two valve defects**

- **Found during:** mutation 4, which trips both counters.
- **Issue:** one shared `valveLeakRepro` slot reported whichever defect happened first, so the
  "observed on a REJECTED action" message printed the reproduction of a *depth mismatch*. A message
  that names the wrong round is worse than no message.
- **Fix:** `valveDepthRepro` and `valveLeakRepro`, captured independently. **Commit:** `6699524`

**4. [Rule 1 — measured cost] The legal-action buffers hoisted out of the action loop**

- **Issue:** the enumeration allocated two fresh tables per action. At 170,332 accepted actions that
  was 0.3-0.5s of the case's wall time, against a 3.0s stop-and-report line — not a failure, but
  spending a sixth of the budget on garbage while plan 02-09 has to fit its subset into what is left.
- **Fix:** both buffers hoisted to round scope and rewritten each action with an explicit `options`
  length. Case wall time 2.49s -> 1.91-2.00s, and `totalActions` is **194,567 before and after**, which
  is itself the check that the buffers carry nothing between actions. **Commit:** `6699524`

### Process notes, not defects

- **`Pool.poolConfig` builds every config.** The plan's `gen` sketch lists `seatCount = rng:nextInt(2, 9)`
  and `antiLivelockValve = true`, and the plan's context says to build the config through
  `Pool.poolConfig`. Both are honoured and the two are cross-checked: `check` asserts that
  `poolConfig(seatCount + 1, ...)` returned `seatCount` (amendment A3's `N - 1`, never written inline
  here) and that it set the shipped valve position (amendment A7). Those two asserts are cheap and they
  are the reason this file cannot silently drift from the single site that owns the arithmetic.
- **Eight illegal constructions, seven codes.** `NotYourCard` is built two ways (a card held by another
  seat; a card sitting in the actor's OWN inbox, research 7.6) because plan 02-07's mutation M3 — a
  predicate that also scans the inbox — is caught only by the second.
- **`Remove{cause = "Completed"}` is never generated**, per 02-07's instruction. The 274
  `SeatRemoved{Completed}` observations all come from completing draws.
- **`Invariants.circulation` is required and used**, for the liveness check (no legal action with
  circulation left is an error, never a quiet break). It fired zero times, as it should.
- **Two commits for two tasks.** The task-1 state (the driver, no floors) was run green at 461 passed
  in 17.91s and committed before the floors were added, so both states are on the record rather than
  the split being reconstructed afterwards.
- **Nothing logged to `deferred-items.md`.** No out-of-scope defect was found; the file was not created.
- **STATE.md, ROADMAP.md and REQUIREMENTS.md were not touched**, per the execution instruction. The
  Phase 2 pending-todo row and the five requirement IDs in this plan's frontmatter
  (CARD-01, CARD-03, CARD-04, CARD-07, CARD-08) are left for the orchestrator.

## Known Stubs

None. There is no placeholder value, no TODO/FIXME and no unwired path in
`tests/engine/fuzz.spec.luau`. Every counter it maintains is read by an assertion or printed in the
coverage report; `valveFirings`, `armedRounds` and `seenResets` are deliberately reported rather than
floored, which is documented at the assertion site and in the file header.

## Threat Flags

None. This plan adds one test file. No network endpoint, no auth path, no file access pattern and no
schema change at a trust boundary. The plan's own register (T-2-37 through T-2-41) is satisfied as
written: T-2-37 by the full identity scan with `checksRun >= totalActions`, T-2-38 by the unchanged
hash plus the empty event list on all 24,235 rejections, T-2-39 by `SeatNotLive` at 2,449
observations, T-2-40 by the action-count and per-kind floors plus six recorded mutations, and T-2-41
accepted unchanged (a headless test process with no network, no storage and no identity).

## Issues Encountered

The case passed on its first run — 194,567 actions, every floor met, and no engine defect found. That
is the expected result rather than a surprise: plans 02-01 through 02-07 each shipped with their own
mutation battery, so this suite's job is to hold the line at scale and against random input rather
than to find the first bug. What it did find is the three gate defects in deviations 1-3, all in this
plan's own assertions.

Two small implementation frictions, both resolved in minutes:

- Luau interpolated strings escape a literal brace as `\{`, not `{{`. Three coverage messages that
  wanted to print `SeatRemoved{cause = "Completed"}` were reworded to `SeatRemoved with cause
  "Completed"` rather than carrying escapes through a `stylua` round-trip.
- `stylua` wrapped a `{tostring(valveLeakRepro)}` interpolation across three lines, which made a
  subsequent textual edit miss it. Caught immediately by `selene` (`undefined_variable`).

## Next Phase Readiness

### For plan 02-09 (the simulator and its CI subset) — read this first

**The number to budget against is the full-suite wall time: 17.12-17.91s** (two runs, 461 passed, 0
failed, 3 todo). `scripts/verify.luau` is **19.0s** end to end, of which the test step is 16.7s.

**`--filter engine` is now 2.32-2.37s, not the 0.66s that 02-07 published.** This plan's case is 1.91-2.00s
of that, and it is inside the `engine` filter by path. If 02-09 derived its CI subset budget from
02-07's 0.66s figure, that derivation needs redoing against 2.32s — the engine filter is no longer a
sub-second thing and cannot be made one without cutting this plan's 100k-action floor, which is the
claim rather than a cost.

The arithmetic the plan's verification block already set out therefore stands and gets sharper:
15.94s (Phase 1) + 8.0s (02-09's derived subset) was already ~23.9s before this plan; the measured
position is **17.9s with this plan in and 02-09 still to come**. CONTEXT's locked "~20s should stay
true" is **not reachable**, and per this plan's instruction that overshoot goes to the owner at
**plan 02-12's checkpoint** rather than being absorbed by anyone trimming cells to fit. Nothing was
trimmed here: this plan's own 3.0s line was the only hard budget and it came in at 1.91-2.00s.

### For plan 02-10 (the negative results)

`k = 0` is never generated here (`k = rng:nextInt(1, 2)`, amendment A4), so `DeadPool` is untouched by
this suite and remains entirely 02-10's. Nothing in the 194,567 actions contradicts the DeadPool
prediction; it was simply never in scope.

### For plan 02-11

The shipped valve position reaches this suite only through `Pool.poolConfig`, and `check` asserts that
`poolConfig` set it. 02-11's assertion that the shipped configuration enables the valve therefore has
one more site depending on it.

### For plan 02-14 (the sweep)

**`valveFirings = 0` over 500 rounds of uniformly random play is a data point for 02-14's reference
comparison, and it is NOT a firing-rate measurement.** The reference numbers (0.25% of rounds at
k=1,j=1; 21.6% at k=2,j=2) were measured under a *greedy* policy, which is the policy that creates
cycles; this suite plays uniformly at random, which research 3.6 measured as the policy that does not.
A divergence between 02-14's figure and the reference must not be explained by anything in this file.
What this file does contribute is that `armedRounds = 291` of 500 — so the arm gate is reachable in
bulk, and 02-14 can expect the hashing cost to be real whenever a round goes 48 actions per live seat
without progress.

### For Phase 4

Three contracts are now load-tested rather than only unit-tested, across 170,332 accepted applies:

1. **Every card movement carries exactly one `Drew` or `Passed`.** The locked event order was asserted
   per apply against the five permitted forms (`Drew`; `Drew,ValveForcedPass,Passed`;
   `Drew,Completed,SeatRemoved`; `Passed`; `SeatRemoved`), with no other form accepted once. An adapter
   may count card movements by counting those two kinds and nothing else.
2. **A rejection moves nothing.** 24,235 rejections, each with the expected code, an empty (never nil)
   event list, an unchanged canonical hash and an unmoved valve.
3. **Exactly one valve entry point per accepted apply, none on a rejection** — 170,332 == 170,332.

---
*Phase: 02-card-engine-and-pacing-simulator*
*Completed: 2026-11-03*

## Self-Check: PASSED

- `tests/engine/fuzz.spec.luau` (814 lines) — FOUND
- commits `d8100be` (task 1) and `6699524` (task 2) — both FOUND in `git log`
- `git diff --diff-filter=D 10f049d..HEAD` is empty: neither commit deleted a tracked file
- working tree clean apart from this summary; `src/server/engine/Engine.luau` and
  `src/server/engine/Ring.luau` restored byte-identical after mutations 3, 4 and 6
- every acceptance grep for both tasks re-run, including `valveFirings >= 1` which must and does
  exit 1
- both plan-named mutations re-run against the FINAL committed file, and the baseline is green at
  `2 passed, 0 failed, 0 todo in 1.91s` with `totalActions = 194567`
