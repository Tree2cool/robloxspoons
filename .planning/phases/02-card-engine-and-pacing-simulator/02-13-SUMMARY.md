---
phase: 02-card-engine-and-pacing-simulator
plan: 13
subsystem: engine
tags: [anti-livelock-valve, repeated-state-detection, liveness, mutation-proof, deterministic-fixture, CARD-11]

requires:
  - phase: 02-01
    provides: "Types.ValveState, Types.VALVE_ARM_ACTIONS_PER_SEAT (48), Types.VALVE_SEEN_CAP (4096), Types.JOKER_RANK, Types.MAX_HAND, the ValveForcedPass event shape, and Invariants.hash — whose exclusion of counters, valve and rankOf is this plan's load-bearing precondition"
  - phase: 02-03
    provides: "check-guards R3: `coroutine` and `os.` banned inside pure zones, so the valve is deterministic under a seed rather than under a clock"
  - phase: 01-02
    provides: "tests/run.luau + Test.Runner (assert-the-reason house rule), src/server/engine/Rng.luau"
provides:
  - "src/server/engine/Valve.luau — new, afterProgress, afterAction: the repeated-state detector and the forced-card chooser, pure and synchronous, no card mutation"
  - "The locked firing rule and the locked choice rule, implemented and mutation-proven"
  - "tests/harness/Livelock.luau — build, newDriver, nextIntent, applyWithoutEngine, export type Driver: a legal, check-clean, completion-free 2-seat cycle whose observation-point hash first recurs at action 17"
  - "tests/engine/valve.spec.luau — 11 cases including the disabled-valve MUTATION twin; the valve is shown to fire on a deterministic cycle and to be necessary"
affects: [02-07, 02-08, 02-09, 02-11, 02-14]

tech-stack:
  added: []
  patterns:
    - "A liveness mechanism, not a bot policy: the valve consults no policy and chooses uniformly at random, which is why it is allowed in the pure zone that research section 15 closes to the reaction-time model"
    - "A detector whose state space must be allowed to repeat: anything monotonic inside Invariants.hash would make the mechanism silently vacuous, so the dependency is stated in the module header rather than re-asserted"
    - "Clearing a window is soundness; un-arming would be cost — the two halves of afterProgress are commented as different KINDS of reason, and the two sites that leave `armed` alone are cross-referenced so the module cannot contradict itself"
    - "Prove a mechanism fires with a deterministic fixture and a stated action index (113), never with a timeout or a statistic"
    - "Promote a fixture to tests/harness/ when more than one plan consumes it, and export the driver record the consumers need (an earlier plan draft left `newDriver` out of the exports that three plans call)"

key-files:
  created:
    - src/server/engine/Valve.luau
    - tests/harness/Livelock.luau
    - tests/engine/valve.spec.luau
  modified: []

key-decisions:
  - "Malformed-call validation runs BEFORE the counter bumps, so a bad `drewAtSeat` throws without being counted as an observation. The plan fixed the order of steps 1-6 but not where the loud error sits; counting an apply that is about to be aborted would corrupt plan 02-08's `observations == acceptedActions` assertion"
  - "Added case 11 (not in the plan's list of ten): a joker-bearing hand over 60 seeds never has its joker forced out, and an all-joker hand returns the lowest card id. The naturals-only rule and its fallback branch were otherwise untested, because the fixture has no jokers — the fallback would have shipped as dead, unexercised code"
  - "Added a SCANNED four-of-a-kind check to case 4. The plan asked for `counters.completions == 0`, which can never fail here: `applyWithoutEngine` performs no completion detection, so that counter is structurally frozen at 0. This phase's planning found four checks that could not fail and the brief forbids a fifth, so completion-freedom is now asserted by scanning every live hand for four of a rank at every action — and mutation F1 below makes it fail"
  - "`newRun` takes the fixture's options table rather than two positional booleans, so the literal `antiLivelockValve = false` is visible inside the MUTATION case that depends on it (it was also an acceptance grep this executor failed on the first attempt and fixed in a follow-up commit)"
  - "VALVE_SEEN_CAP is asserted on a pre-filled window rather than driven for real, which the plan permits and which is not a shortcut: this fixture's armed state space is the 8 observation points of its 16-action cycle, so 4,096 DISTINCT armed observations are unreachable on it at any wall-time budget"
  - "The firing point (immediately after a non-completing draw, on the drawing seat) and the naturals-only choice rule are recorded in the module as THIS plan's choices, held constant so the reference prototype's measured numbers stay comparable — not as rules amendment A7 or A7-CORRECTION state. Plan 02-14's divergence check depends on that distinction"

patterns-established:
  - "Mutation battery as a table: 8 implementation mutations and 2 fixture mutations, each with the verbatim failing assertion message recorded in the summary"

requirements-completed: [CARD-11]
requirements-contributed: []

duration: ~1 session
completed: 2026-11-03
---

# Phase 2 Plan 13: The Anti-Livelock Safety Valve Summary

**The engine now breaks a greedy-hoarding livelock itself: `Valve.afterAction` notices that the whole
table has returned to a state it has already been in with no completion or removal since, and forces
one uniformly random pass from the seat that just drew — proven to fire on action 113 of a
deterministic completion-free cycle, proven necessary by the same fixture never escaping with the
valve disabled, and claimed only as honestly as it was measured (observed stalls eliminated for a
good pool; a 0.025% residual at k=2,j=2).**

## Performance

- **Tasks:** 3 of 3
- **Files created:** 3; **modified:** 0 (no shared planning file was touched — the orchestrator owns `STATE.md`, `ROADMAP.md` and `REQUIREMENTS.md` this wave)
- **`--filter engine/valve`:** `11 passed, 0 failed, 0 todo in 0.30s` (0.337s wall, `time` real; repeat runs 0.30–0.44s — well under the 1.0s bar)
- **`--filter engine`:** `107 passed, 0 failed, 3 todo in 0.52s`; `--filter engine/`: `103 passed, 0 failed, 3 todo in 0.35s`
- **Full suite (run at the end of the wave, after the siblings landed):** `429 passed, 0 failed, 3 todo in 15.58s` — baseline at `0e3bbba` was 380; +11 from this plan, the rest from wave-3 siblings 02-04, 02-05 and 02-06
- **`scripts/verify.luau`:** `verify: all 14 automated steps passed in 16.9s`
- **`check-guards`:** `ok (74 files, 163 requires, 19 guarded roots)`
- **Both purity layers:** `selene --config selene.pure.toml src/server/engine` → `0 errors`; `luau-lsp --platform standard` → `analyze: ok`

## Task Commits

1. **Task 1: `Valve` — the repeated-state detector and the forced-card chooser** — `1881881` (feat)
2. **Task 2: `tests/harness/Livelock.luau` — a deterministic, completion-free cycle** — `b8c1695` (test)
3. **Task 3: `valve.spec` — it fires, it is silent when healthy, and with it off nothing escapes** — `7c910b0` (test)
4. **Follow-up: spell the disabled flag out in the MUTATION case, and scan for four of a kind** — `d045596` (test)

## `Valve.luau` exports, verbatim (plan 02-07 wires these)

```luau
-- A fresh valve state. `seed` comes from Engine.newRound as a draw off the round's own generator.
new: (seed: number) -> Types.ValveState

-- Called at the end of a successful apply that produced a Completed or SeatRemoved event.
-- Bumps observations, zeroes actionsSinceProgress, empties `seen`. Does NOT touch `armed`.
afterProgress: (state: Types.State) -> ()

-- Called at the end of every OTHER successful apply. `drewAtSeat` is the seat that just drew (it
-- now holds MAX_HAND and must pass next), or nil when the action was a pass. Returns the card id
-- the engine must force that seat to pass, or nil for "do nothing".
afterAction: (state: Types.State, drewAtSeat: Types.SeatId?) -> Types.CardId?
```

Exactly one of the two is called per successful `apply`, neither on a rejection, and both bump
`observations` — so plan 02-08 can assert `observations == acceptedActions`. Requires exactly
`./Types`, `./Invariants` and `./Rng` (`grep -c 'require('` → 3). No `Ring`: the valve returns a
card id and `Engine.apply` performs the pass through the one container mutator, inside the same
synchronous apply (CLAUDE.md rules 6 and 7).

### The locked firing rule

It fires when ALL of these hold:

1. `state.config.antiLivelockValve` is true
2. `drewAtSeat ~= nil` — immediately after a non-completing draw is the only instant at which a
   known seat holds `MAX_HAND` and therefore provably has a legal pass, and it is about to pass
   anyway, so the valve changes WHICH card leaves and not whether a pass happens
3. `state.valve.armed` — set once `actionsSinceProgress >= VALVE_ARM_ACTIONS_PER_SEAT * liveCount`
   (48 × liveCount) and never cleared again
4. `Invariants.hash(state)` is already in `state.valve.seen`

No hashing happens unless 1-3 hold; that is the entire purpose of the arm gate, which is a COST gate
and nothing else. On a firing: `firings += 1`, the window restarts (`seen = {}`, `seenCount = 0`),
`armed` stays true.

### The locked choice rule

The drawing seat's card ids whose rank is not `JOKER_RANK`, **sorted ascending**, index
`rng:nextInt(1, #naturals)` off the valve's own seeded generator. Sorted so the choice depends on the
hand's contents and not on the order the cards happen to sit in. If the hand holds no natural —
unreachable at `j <= 2` — it falls back to the lowest card id in the hand.

### These two are THIS PLAN'S CHOICES, held constant for comparability

Neither amendment A7 nor A7-CORRECTION names a firing point or a choice rule. Both are held exactly
as the reference prototype had them so the measured 0.25%-fires / 0.000%-stalls numbers remain
comparable. **Plan 02-14: if your measured firing rate diverges from the reference, the arm gate is
only ONE of three candidate causes** — the others are this firing point and the naturals-only choice
rule. Attributing a divergence to the arm gate alone would close the investigation on the wrong
suspect.

### The honest claim, as written into the module header

Measured at N=10 over 4,000 rounds per cell: k=1,j=1 went from 0.275% to zero observed stalls,
k=2,j=1 from 0.250% to zero, both while firing in only ~0.25% of rounds; k=2,j=2 went from 21.600%
to **0.025% — a residual, not zero** — while firing in 21.6% of rounds. So the recorded claim is
"observed stalls eliminated FOR A GOOD POOL, demonstrated rather than assumed", plus "the firing rate
is a better pool discriminator than the stall rate". The module says so and says nothing stronger:
`grep -qiE 'guarantees zero|theorem about the engine' src/server/engine/Valve.luau` exits 1.

## `Livelock.luau` exports, verbatim (plans 02-07, 02-09 and 02-11 all call these)

```luau
export type Driver = { state: Types.State, cursor: Types.SeatId, lastDrawn: Types.CardId? }

build: (opts: { antiLivelockValve: boolean, valveSeed: number? }) -> Types.State
newDriver: (state: Types.State) -> Driver
nextIntent: (fx: Driver) -> Types.Intent
applyWithoutEngine: (state: Types.State, intent: Types.Intent) -> Types.CardId?
```

`newDriver` is in the RETURNED table, not merely a local: `grep -q 'newDriver = newDriver'` succeeds.

The fixture: `ranks = 3`, `jokers = 0`, `jokerMode = "Wild"`, `seatCount = 2`, `totalCards = 12`,
`circulation = 4 * (3 - 2) + 0 = 4`. Seat 1 rests on `{1,2,3,4}` (ranks 1,1,2,2) with inbox
`{9,10}`; seat 2 on `{5,6,7,8}` (ranks 3,3,1,1) with inbox `{11,12}`. `build` asserts
`Invariants.check` and errors with the violation name if the layout is not a legal state; counters
are scanned off the containers, never asserted from the layout.

**Verified numbers, re-derived in this execution and matching the plan exactly:**

| quantity | value |
|---|---|
| cycle length | 16 actions (8 of them draw observations) |
| first recurrence of the observation-point hash | **action 17** (`hashes[17] == hashes[33] == hashes[49]`, and still cycling at action 2,000) |
| four of a kind, anywhere, ever | never — scanned at every action across 2,000 actions |
| `armed` flips | during action **96** (a Pass, so nothing is hashed there) |
| first armed observation | action **97** (window empty, can only record) |
| **first firing** | action **113** = 96 + 16 + 1, for every one of the 200 valve seeds tested |

`applyWithoutEngine` exists only because this plan runs in wave 3, where `Engine` does not exist.
It is documented, in the file, that **consumers in later waves must drive the fixture through
`Engine.apply` and must NOT use it** — a fixture only ever driven by its own private mutator proves
nothing about the shipped engine.

## The spec: 11 cases

| # | case | what it pins |
|---|------|--------------|
| 1 | the valve is silent in the arm window | 95 actions: `firings == 0`, `armed == false`, `seenCount == 0` — the cost gate |
| 2 | the valve arms and then fires on the repeated state | `armedAt == 96`, first firing on action **113**, the forced card was in the drawing seat's hand |
| 3 | the forced card is one the greedy policy would have kept | 200 independent firings (fresh fixture, fresh seed): **5 distinct card ids** (`{1,2,3,4,9}` — the whole hand), never a joker, every one firing on action 113 |
| 4 | **MUTATION: with the valve disabled, nothing escapes** | valve off, 2,000 actions: no firing, no four of a kind, `check` clean at every action, identical hash at 17/33/49 and still cycling at 2,000. Valve on, same 2,000 actions: it fires and 1,887 of the 2,000 states it visits are states the disabled run never reaches |
| 5 | a repeat seen on a pass does not fire | the same recurrence returns nil as a pass and fires as the draw it actually was |
| 6 | afterProgress restarts the window but not the arm | `seenCount == 0`, `actionsSinceProgress == 0`, **`armed` still true**, and the next firing costs 18 actions (one 16-action lap plus the Draw/Pass parity) instead of a fresh 96-action arm period |
| 7 | the valve is deterministic under its seed | seed 11 replays to the identical 29-entry list of forced cards; seed 1 produces a different list (both halves asserted) |
| 8 | exactly one observation per action | mixed `afterAction`/`afterProgress` sequence, plus 5 driven actions |
| 9 | the seen window is bounded | `seenResets >= 1` and `seenCount <= VALVE_SEEN_CAP`, asserted on a pre-filled window (see decisions) |
| 10 | a malformed call is a loud error | a resting seat, an unknown seat and a dead seat each throw, asserting the message; the clean call is asserted alongside |
| 11 | the choice rule skips jokers and falls back to the lowest card id | 60 seeds never force the joker out; an all-joker hand returns card id 1 |

## Mutation proofs — verbatim output

Every gate below was deliberately broken, watched failing, and restored with
`git checkout -- <file>`. Ten mutations, ten reds.

```
=== M1 arm gate always on (Valve)  (exit 1)
FAIL tests/engine/valve.spec.luau::the valve is silent in the arm window
FAIL tests/engine/valve.spec.luau::the valve arms and then fires on the repeated state
FAIL tests/engine/valve.spec.luau::the forced card is one the greedy policy would have kept
FAIL tests/engine/valve.spec.luau::a repeat seen on a pass does not fire
FAIL tests/engine/valve.spec.luau::afterProgress restarts the window but not the arm
FAIL tests/engine/valve.spec.luau::a malformed call is a loud error
5 passed, 6 failed, 0 todo in 0.30s

=== M2 afterProgress un-arms (Valve)  (exit 1)
FAIL tests/engine/valve.spec.luau::afterProgress restarts the window but not the arm
     afterProgress un-armed a round that had already proven it needs watching (expected true, got false)
10 passed, 1 failed, 0 todo in 0.34s

=== M3 choice rule deterministic, always the lowest natural (Valve)  (exit 1)
FAIL tests/engine/valve.spec.luau::the forced card is one the greedy policy would have kept
     only 1 distinct forced cards over 200 firings (expected a truthy value, got false)
FAIL tests/engine/valve.spec.luau::the valve is deterministic under its seed
     a different seed produced the identical list of forced cards (expected a truthy value, got false)
FAIL tests/engine/valve.spec.luau::the choice rule skips jokers and falls back to the lowest card id
     only 1 distinct naturals over 60 seeds (expected a truthy value, got false)
8 passed, 3 failed, 0 todo in 0.34s

=== M4 the antiLivelockValve flag ignored (Valve)  (exit 1)
FAIL tests/engine/valve.spec.luau::MUTATION: with the valve disabled, nothing escapes
     a disabled valve fired (expected 0, got 112)
10 passed, 1 failed, 0 todo in 0.30s

=== M5 the valve never fires (Valve)  (exit 1)
FAIL tests/engine/valve.spec.luau::the valve arms and then fires on the repeated state
FAIL tests/engine/valve.spec.luau::the forced card is one the greedy policy would have kept
FAIL tests/engine/valve.spec.luau::MUTATION: with the valve disabled, nothing escapes
FAIL tests/engine/valve.spec.luau::a repeat seen on a pass does not fire
FAIL tests/engine/valve.spec.luau::afterProgress restarts the window but not the arm
FAIL tests/engine/valve.spec.luau::the valve is deterministic under its seed
FAIL tests/engine/valve.spec.luau::the choice rule skips jokers and falls back to the lowest card id
4 passed, 7 failed, 0 todo in 0.27s

=== M6 the malformed-call errors removed (Valve)  (exit 1)
FAIL tests/engine/valve.spec.luau::a malformed call is a loud error
10 passed, 1 failed, 0 todo in 0.36s

=== M7 the seen cap removed (Valve)  (exit 1)
FAIL tests/engine/valve.spec.luau::the seen window is bounded
     the cap did not restart the window (expected a truthy value, got false)
10 passed, 1 failed, 0 todo in 0.31s

=== M8 pass observations allowed to fire (Valve)  (exit 1)
FAIL tests/engine/valve.spec.luau::the valve arms and then fires on the repeated state
FAIL tests/engine/valve.spec.luau::the forced card is one the greedy policy would have kept
FAIL tests/engine/valve.spec.luau::MUTATION: with the valve disabled, nothing escapes
FAIL tests/engine/valve.spec.luau::a repeat seen on a pass does not fire
FAIL tests/engine/valve.spec.luau::afterProgress restarts the window but not the arm
FAIL tests/engine/valve.spec.luau::the valve is deterministic under its seed
5 passed, 6 failed, 0 todo in 0.26s

=== F1 the fixture's rank layout permuted so a seat can complete (Livelock)  (exit 1)
FAIL tests/engine/valve.spec.luau::MUTATION: with the valve disabled, nothing escapes
     a seat reached four of a kind, so the fixture is not completion-free (expected 0, got 4000)
10 passed, 1 failed, 0 todo in 0.30s

=== F2 the fixture's Invariants.check guard fed an illegal hand (Livelock)  (exit 1)
0 passed, 11 failed, 0 todo in 0.23s
```

M1 is the most informative red: with the arm gate removed the valve starts firing inside the first
96 actions and six independent cases notice, including case 10's malformed-call pair (a firing
perturbs the trajectory the malformed-call fixture stands on). F2 shows the fixture's own
`Invariants.check` guard is load-bearing: an illegal layout takes down all 11 cases by name rather
than producing quiet nonsense.

## Deviations from Plan

### Auto-fixed

**1. [Rule 2 — missing critical coverage] The plan's `counters.completions == 0` assertion could not fail**
- **Found during:** Task 3, writing case 4
- **Issue:** `applyWithoutEngine` performs no completion detection, so `state.counters.completions`
  is structurally frozen at 0 on this path. Asserting it would have been the fifth un-failable check
  this phase has found, which the brief explicitly forbids.
- **Fix:** added a scanned four-of-a-kind check under `checkEach` — every live hand, every action,
  four copies of a rank. Mutation F1 above makes it fail (`expected 0, got 4000`). The original
  assertion is kept alongside it, as a cheap tripwire for the day a consumer wires real completions in.
- **Files:** `tests/engine/valve.spec.luau`
- **Commit:** `d045596`

**2. [Rule 2 — untested branch] Case 11 added beyond the plan's ten cases**
- **Issue:** the fixture has no jokers, so neither the naturals-only filter nor the lowest-card-id
  fallback was exercised by any case. The fallback would have shipped as dead code.
- **Fix:** case 11 drives 60 seeds against a hand whose drawn card has been re-ranked as a joker
  (asserting the joker is never the forced card), then an all-joker hand (asserting card id 1).
  Both fixtures override `rankOf` directly and run no `check`, which the case documents: the valve
  reads only `rankOf` and the hand on this path.
- **Commit:** `7c910b0`

**3. [Rule 2 — correctness] Malformed-call validation placed before the counter bumps**
- **Issue:** the plan fixes the order of `afterAction`'s six steps but not where the loud error sits.
  Counting an `observations` bump for an apply that is about to be aborted would corrupt plan 02-08's
  `observations == acceptedActions` assertion.
- **Fix:** validation runs first; a malformed call throws without being counted.
- **Commit:** `1881881`

**4. [Rule 3 — acceptance criterion] `newRun` refactored to take an options table**
- **Issue:** the first version of the spec called `newRun(false, 1)`, so the acceptance grep
  `grep -q 'antiLivelockValve = false'` exited 1 — and, more to the point, the flag that CREATES the
  mutation was invisible in the case that depends on it.
- **Fix:** `newRun` now takes `{ antiLivelockValve, valveSeed }`, mirroring `Livelock.build`.
- **Commit:** `d045596`

### Process notes, not defects

- **Task 1 was marked `tdd="true"` but owns only `Valve.luau`.** Its spec is task 3's file, so a RED
  commit was not possible inside task 1's file ownership; it landed as a single `feat` commit and the
  falsifiability a RED gate buys is supplied instead by task 3's ten-mutation battery above (M1-M8
  break the implementation and watch the suite go red). See TDD Gate Compliance below.
- **Whole-suite and `scripts/verify.luau` runs.** The plan forbids them for a wave-3 plan, because a
  sibling's half-written file can fail them. The orchestrator's brief requires them before finishing.
  Resolution: the plan's own verification block was run throughout, and the whole suite plus the
  14-step gate were run once at the END of the wave, after 02-04, 02-05 and 02-06 had landed their
  GREEN commits. Both are green (`429 passed, 0 failed, 3 todo`; `all 14 automated steps passed`).
- **Two transient sibling typecheck failures were observed and deliberately NOT logged to
  `deferred-items.md`:** `tests/engine/hand.spec.luau` (the `JokerMode` widening TypeError that plan
  02-01's summary already documents) while it was uncommitted in the working tree, and
  `tests/engine/removal.spec.luau` referencing `Ring.removeSeat` while plan 02-06 sat between its RED
  and GREEN commits. Both are expected mid-TDD states of another plan's file rather than defects, and
  both are green in the final whole-suite and `verify.luau` runs above. No file outside this plan's
  three was touched.

## TDD Gate Compliance

Gate sequence for this plan, from `git log`:

- `1881881` **feat** — `Valve.luau` (task 1)
- `b8c1695` **test** — the `Livelock` harness (task 2)
- `7c910b0` **test** — `valve.spec`, 11 cases (task 3)
- `d045596` **test** — the follow-up fix

**No `test(...)` RED commit precedes the `feat(...)` commit**, and that is a consequence of the
plan's own task decomposition rather than a skipped gate: task 1 (`tdd="true"`) owns
`src/server/engine/Valve.luau` alone, while the spec that could have failed first belongs to task 3
and depends on the task 2 harness, which in turn requires `Valve.new`. A RED commit was therefore
unreachable without writing outside the task's declared file list. The property a RED gate protects —
that the suite can actually fail — is instead established explicitly by the ten mutations recorded
above, each with its verbatim failing assertion.

## For plan 02-07 (the only shipped caller)

- Call **exactly one** of `Valve.afterProgress(state)` / `Valve.afterAction(state, drewAtSeat)` per
  successful `apply`, and **neither on a rejection**. `afterProgress` when the apply produced a
  `Completed` or `SeatRemoved` event; `afterAction` otherwise.
- Pass `drewAtSeat` **only** when the apply's action was a draw that did not complete, and only the
  seat that drew. It must be live and holding `MAX_HAND` at the moment of the call or `afterAction`
  throws by design.
- When `afterAction` returns a card id, perform the pass **inside the same synchronous apply**
  through the container mutator, and emit
  `ValveForcedPass { seat, cardId, to, lap = state.valve.actionsSinceProgress }`. Never put the hash
  in an event (CLAUDE.md rule 3).
- Seed the valve in `newRound` with a draw off the round's generator (`rng:nextUint()`), so valve
  draws never perturb the deal.
- Case 11 of plan 02-07 is the end-to-end proof: drive `tests/harness/Livelock` through the real
  `Engine.apply` (NOT `applyWithoutEngine`) and expect the first firing on action 113. Plan 02-07
  needs no hand-applied forced pass — `Engine.apply` performs it.

## Self-Check: PASSED

- `src/server/engine/Valve.luau` — FOUND
- `tests/harness/Livelock.luau` — FOUND (121 lines, under the 130 cap)
- `tests/engine/valve.spec.luau` — FOUND
- commits `1881881`, `b8c1695`, `7c910b0`, `d045596` — all FOUND in `git log`
- every acceptance grep for all three tasks re-run and passing, including the three that must FAIL:
  `Ring`, `guarantees zero|theorem about the engine`, and `os\.|coroutine|game|Instance|math.random`
