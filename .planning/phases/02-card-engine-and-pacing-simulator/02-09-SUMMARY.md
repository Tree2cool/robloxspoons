---
phase: 02-card-engine-and-pacing-simulator
plan: 09
subsystem: testing
tags: [simulator, bot-policy, pacing, solvability, outcome-taxonomy, occupancy, anti-livelock-valve, gate-g1, mutation-proof, ci-budget]

requires:
  - phase: 02-04
    provides: "Pool.poolConfig — the ONE site that owns amendment A3's seatCount = n - 1 and the shipped valve position; Pool.validate's four locked reason strings; Pool.deal's rejection-sampling attempt count"
  - phase: 02-05
    provides: "Hand.groupsOf — the grouping the greedy bot calls instead of reimplementing"
  - phase: 02-01
    provides: "Invariants.satisfiable (the O(1) predicate), Invariants.hash (the canonical state identity), Invariants.circulation, Invariants.check and the locked nine-violation order"
  - phase: 02-06
    provides: "Ring.removeSeat's LOCKED dump order (departing hand ascending, then inbox FIFO, appended to the successor's inbox tail) — which is what makes the sabotage path able to identify the routed cards"
  - phase: 02-07
    provides: "Engine.newRound as a one-seed round constructor and Engine.apply as the ONE mutation entry point, the locked event order including the valve's three-event form, and the measured fixture numbers (fired on action 113, completed on 114)"
  - phase: 02-13
    provides: "Valve.new / afterProgress / afterAction, the ValveState counters (firings, armed, seenResets, observations) the simulator OBSERVES, and tests/harness/Livelock (build / newDriver / nextIntent) — the deterministic, hand-verified 16-action cycle"
  - phase: 02-08
    provides: "The measured full-suite wall time (17.12-17.91s) this plan sized its subset against, and the warning that `--filter engine` is 2.32s rather than 02-07's 0.66s"
  - phase: 01-02
    provides: "tests/harness/Test.luau and tests/run.luau's tests/**/*.spec.luau discovery, which is why no CI step was added"
provides:
  - "scripts/sim/Bots.luau — greedyPass (the locked deterministic policy, ties by ascending card id, both joker modes) and randomPass (the uniform auto-pass choice off the injected Rng)"
  - "scripts/sim/Simulator.luau — runRound / runCell / evaluateBars / evaluateMechanisms, two modes, the six-category outcome taxonomy, all eight metrics plus the valve's three, and the five mechanism bars with the MechanismEvidence record"
  - "tests/sim/subset.spec.luau — the CI regression subset at RUNG 2 (12 gated cells x 500 rounds) plus seven mutation proofs, 15 cases in 5.77-5.91s inside the existing test step"
  - "tests/sim/simulator.spec.luau and tests/sim/bots.spec.luau — the TDD behaviour specs for tasks 1 and 2 (17 further cases)"
  - "A MEASURED Gate G1 result at the provisional reference pool, which does NOT reproduce 02-CONTEXT A7-CORRECTION's prototype figures: valve-OFF stalls 10.6% (not 0.250%), valve-ON residual 0.05-0.10% (not 0.000%), valve firing rate 10.8-15.8% (not 0.25%)"
  - "The measured CAUSE of that divergence: the stall rate is the endgame, and the endgame depth is amendment A3's completion target. At N=10, k=2, j=1, valve OFF: target 8 (A3's value) 10.6%, target 7 4.0%, target 6 1.8%, target 5 0.6%, target 4 0.4% — research OQ-B's off-by-one, measured as a factor of 20+"
  - "Measured throughput for every later plan to size against: 1,646 rounds/s and 242,800 actions/s on the healthy 32-cell bulk (16,000 rounds in 9.72s), a realised pessimism factor of 1.16x against research 11.1's 1,904 rounds/s"
  - "A measured full-suite wall time of 23.41-24.45s and scripts/verify.luau at 26.1s, which plans 02-10 and 02-14 must budget against"
affects: [02-10, 02-11, 02-12, 02-14, 04, 06]

tech-stack:
  added: []
  patterns:
    - "A headless simulator that drives the REAL engine: every card movement goes through Engine.apply, so a result about the simulator is a result about the shipped game and there is no second copy of the card rules"
    - "Virtual time as a plain number advanced only by an event-driven scheduler. Nothing sleeps and nothing reads a wall clock, which is the only reason the throughput exists; os.clock appears once in a comment and nowhere in the code"
    - "A gate split by ROUND COUNT rather than by importance: statistical thresholds belong to the round count they were calibrated at, and the other caller supplies a DETERMINISTIC fixture proof through an explicit evidence record whose booleans are observations, never literals"
    - "Checker mutations on HAND-BUILT cells. evaluateBars and evaluateMechanisms are pure functions of a cell list, so every 'the check CAN report this failure' proof costs zero simulated rounds and is deterministic at every ladder rung"
    - "A known-unmet bar carried in a green suite by a GATED exemption: the subset asserts that the N=10 firing rate still EXCEEDS the bar, so the exemption deletes itself the moment the finding stops being true"
    - "Cycle detection enabled only where it is SOUND. A repeated hash proves non-termination only under deterministic dynamics with no escape mechanism, so the detector runs with the valve disabled and the action cap carries the valve-on case"
    - "Lazy memoised fixtures at spec scope instead of cross-case locals, because tests/run.luau executes cases in registration order and a case reading another case's local would depend on that order"

key-files:
  created:
    - scripts/sim/Bots.luau
    - scripts/sim/Simulator.luau
    - tests/sim/subset.spec.luau
    - tests/sim/simulator.spec.luau
    - tests/sim/bots.spec.luau
  modified: []

key-decisions:
  - "Cycle detection runs ONLY with the valve disabled, which corrects the plan's claim that 'the valve fires at or before the point the cursor-aware detector would prove a cycle'. The detector fires at the FIRST repeat (action 17 in the Livelock fixture) while the valve's arm gate needs 48 actions per live seat (96 there, firing at 113), so the detector always wins the race: with the valve on it would report Livelock for rounds the engine provably escapes and the valve's entire measured effect would be invisible. It is also the plan's own soundness condition applied properly — the valve draws from its own generator, so with it enabled the dynamics are not deterministic and a repeated hash is not a proof"
  - "SimOpts gained churnLeavers, because RosterShortfall is structurally unreachable with one leaver. live = seatCount - completions - churnRemovals and remaining spoons = (seatCount - 1) - completions, so live < remaining reduces to churnRemovals > 1 EXACTLY: with one leaver the two are always equal. The plan's shortfall case was therefore incapable of failing. The gated cells still use one leaver (the realistic rate), and a sibling case asserts they see zero shortfalls — which is now a proven consequence rather than an accident"
  - "The two bars CI's 500-round cells cannot resolve are REPLACED by 500-round-calibrated assertions rather than relaxed. evaluateBars is untouched (VALVE_RATE_MAX is still 0.01, 'stalls' still fires on any non-zero rate) and both keep their mutation cases; the subset asserts stallRate <= 0.006 (6x the measured 0.05-0.10% residual mean, and 18x below the 10.6% a valve regression produces) and asserts that the N=10 firing rate EXCEEDS the bar, which makes the exemption earned by measurement and self-deleting"
  - "The pool was NOT moved to make the gate green. Sweeping k from 1 to 12 at N=10 (2,000 rounds per cell) shows the valve-rate bar is marginal everywhere (k=5 1.85%, k=8 1.20%, k=9 0.70%, k=12 0.15%) and the zero-stall bar fails even at k=12 (0.05% residual), so no pool clears both robustly at 500 rounds. Selecting a high-k pool outside amendment A4's grid would have produced a green gate on a configuration nobody will ship"
  - "Neither Types.VALVE_ARM_ACTIONS_PER_SEAT nor VALVE_RATE_MAX was changed. Raising the arm gate cannot help: valveFiringRate(ON) equals stallRate(OFF) to three decimals at every pool measured, so every firing corresponds to a real stall and a later arm point delays the rescue rather than avoiding it"
  - "Solvability mode carries nil times by construction. now never advances there, so a time from it would be 0 for every round, medianFirst would be 0 and every pacing bar would pass with a perfect score on a mode with no clock. Returning nil makes evaluateBars fail 'no-completions' on a Solvability cell, which is correct — the pacing bars are for Pacing cells, and plan 02-10 must not run evaluateBars over its Solvability cells"
  - "The deal-attempt metric is read by REPLAYING Pool.deal on a fresh Rng.new(seed), because the deal is a pure function of (config, seatCount, seed) and therefore observes exactly the attempt count Engine.newRound is about to pay. 02-07 deliberately does not carry it on State, and threading an out-parameter through newRound would change the engine's contract to serve a metric"
  - "The seat count is read back out of Pool.poolConfig and the throwaway config discarded, which is deliberately uglier than typing n - 1. SimOpts carries a full EngineConfig so the valve-off twin is expressible, so the simulator needs the seat count without re-deriving the config, and research OQ-B measured that off-by-one as shifting the chosen configuration by a full notch"
  - "execute returns RoundResult? rather than Outcome?. Luau's `~= nil` refinement widens an optional union of string singletons back to `string` (reproduced in a four-line fixture), so Outcome? could not be handed to finish without a cast — and the value that decides a round's category is the wrong place for a cast"
  - "sabotage and identityCheck are refused together, loudly. A destroyed routed card IS a conservation violation, so Invariants.check correctly reports `circulation` on the next action and the simulator correctly errors on any check violation; the sabotage path exists to prove the SATISFIABILITY tripwire, which is read from the predicate"
  - "Case 6b was split because the plan asked for something self-contradictory: stallRate = 0.00025 with 'stalls' NOT named, which no zero-stall bar can satisfy. The claim it exists to prove is about the 500-ROUND view (at 0.025% a 500-round cell shows zero stalls 88% of the time), so one half asserts stallRate 0 with 'valve-rate' firing ALONE and the other asserts that both bars agree once the residual is resolvable"
  - "The sabotage sample went from 300 to 60 rounds because the measured Unsatisfiable rate is 77% of churned rounds, not research 3.4's 2.9-5.7%. At 77% the chance of seeing none in 60 rounds is 0.23^60, about 1e-38, so the sample is BETTER calibrated than 300 was against the assumed rate — and 300 rounds cost 2.92s, 36% of the whole subset budget, because a destroyed-card round grinds"
  - "RUNG 2, not rung 3 or 4. The rule is 'stop at the FIRST rung that measures <= 8.0s' and rung 2 measures 5.77s, so descending further would have shrunk the gate for no reason. Rung 2 is also the strongest affordable rung: a FULL cross product at three roster sizes, so unlike rungs 3 and 4 its cell count carries no 'churn only at N=10' caveat"

patterns-established:
  - "Nine plan assertions in this phase have now been found structurally incapable of failing or of passing; this plan found two of each kind and replaced all four with assertions that can fail: the one-leaver shortfall case (incapable of failing), case 6b's zero-stall-with-a-non-zero-rate (incapable of passing), the gated zero-stall and valve-rate bars at 500 rounds (incapable of passing), and the src/ 'destroy' grep (incapable of passing, against pre-existing code)"
  - "A finding escalated rather than absorbed: the measurement, its cause, the k-sweep that rules out a pool change, and the reason the engine constant is the wrong lever are all written into the spec header next to the code they explain, so the next reader cannot act on the exemption without reading the evidence for it"

requirements-completed: [CARD-11, CARD-12]
requirements-contributed: []

duration: ~110 min
completed: 2026-11-03
---

# Phase 2 Plan 09: The Headless Bot Simulator and its CI Subset Summary

**A headless simulator that drives the REAL engine in two modes, classifies every round into one of six mutually exclusive categories and reports eleven metrics — wired into the existing test step as a 12-cell, 6,000-round regression subset with seven mutation proofs, in 5.77s. And a measured Gate G1 result that does not reproduce 02-CONTEXT A7-CORRECTION's prototype figures: pure greedy at the provisional reference pool livelocks in 10.6% of rounds at a full roster, the engine's valve rescues every single one of them, and the 1% firing-rate bar and the zero-stall bar are therefore both unmet at every pool measured. The cause is measured, not guessed: the stall rate is the endgame, and the endgame depth is amendment A3's completion target.**

## Performance

- **Duration:** ~110 min (2026-11-03)
- **Tasks:** 3 (two TDD, RED then GREEN)
- **Files created:** 5 (Bots 144 lines, Simulator 1,106 lines, subset.spec 909 lines, simulator.spec 250 lines, bots.spec 148 lines)
- **Cases added:** 32; suite **493 passed, 0 failed, 3 todo** (baseline 461)
- **`--filter sim/subset`:** `15 passed, 0 failed, 0 todo in 5.77s` (5.91s on a second run)
- **`--filter sim`:** `32 passed, 0 failed, 0 todo in 6.88s`
- **Full suite:** `493 passed, 0 failed, 3 todo in 23.41-24.45s`
- **`scripts/verify.luau`:** `all 14 automated steps passed in 26.1s`

## The published interface (for plan 02-10's sweep and plan 02-11's decision)

```luau
export type Outcome = "Cleared" | "Unsatisfiable" | "Livelock" | "CapReached" | "RosterShortfall" | "DeadPool"
export type SimMode = "Pacing" | "Solvability"
export type Sabotage = "None" | "DestroyRemovedCards"
export type CellRole = "gated" | "mechanism" | "autopass-probe" | "diagnostic"

export type SimOpts = {
	n: number,                      -- PLAYERS IN THE ROUND; the seat count comes from Pool.poolConfig
	config: Types.EngineConfig,     -- antiLivelockValve = false is the valve's mutation twin
	seed: number,
	mode: SimMode,
	autoPassSeconds: number,        -- a realistic AFK deadline; math.huge disables the mechanic
	churn: boolean,                 -- one random leaver per round
	churnLeavers: number?,          -- ADDED: how many, defaulting to 1. See the decision below
	sabotage: Sabotage,             -- refused together with identityCheck
	identityCheck: boolean,
	actionCap: number?,             -- defaults to SOLVABILITY_ACTION_CAP = 100_000
}

export type RoundResult = {
	outcome: Outcome,
	seed: number,                      -- ALWAYS present
	firstCompletionSeconds: number?,   -- nil in Solvability mode BY CONSTRUCTION
	allSpoonsSeconds: number?,
	rampSeconds: number?,
	occupancyMean: number,
	actions: number,
	passes: number,
	autoPasses: number,
	valveFirings: number,
	valveArmed: boolean,               -- "this round ever armed", not "armed at the last action"
	valveSeenResets: number,           -- non-zero means the valve was BLIND, not merely quiet
	deadChaseInstants: number,
	dealAttempts: number,
	violation: string?,                -- the classification reason: "satisfiable-false",
	                                   -- "roster-shortfall", "state-cycle", "time-cap",
	                                   -- "circulation-zero", "ring-emptied", or Pool.validate's reason
	hitActionCap: boolean,
}

export type OutcomeCounts = {
	Cleared: number, Unsatisfiable: number, Livelock: number,
	CapReached: number, RosterShortfall: number, DeadPool: number,
}

export type CellResult = {
	rounds: number,
	outcomes: OutcomeCounts,
	firstCompletionSamples: number,    -- medianFirst/p95First are nil when this is 0
	medianFirst: number?, p95First: number?,
	allSpoonsSamples: number, medianAll: number?, p95All: number?,
	rampMean: number?,
	occupancyMean: number,
	stallRate: number,                 -- (Unsatisfiable + Livelock + CapReached) / rounds
	autoPassRate: number,              -- auto-passes / total ACTIONS, never per round
	actions: number, passes: number, autoPasses: number,
	deadChaseInstants: number,
	dealAttemptMean: number, dealAttemptMax: number,
	valveFiringRate: number,           -- fraction of ROUNDS with at least one firing
	valveFiringsMean: number, valveFiringsTotal: number,
	armedRate: number, valveSeenResetsTotal: number,
	capArtifactCandidates: { number },  -- seeds with hitActionCap == true; plan 02-14 triages them
	failingSeeds: { number },           -- non-Cleared, non-RosterShortfall, capped at the first 20
	config: Types.EngineConfig,
	n: number, k: number, j: number, jokerMode: Types.JokerMode,
	autoPassSeconds: number,
	role: CellRole,
}

export type MechanismEvidence = {
	deterministicFiringProven: boolean,  -- OBSERVED, never a literal
	deterministicTwinProven: boolean,    -- OBSERVED, never a literal
	-- no threshold-override field, deliberately
}

greedyPass: (state: Types.State, seatId: Types.SeatId) -> Types.CardId
randomPass: (state: Types.State, seatId: Types.SeatId, rng: Rng.Rng) -> Types.CardId

runRound: (opts: SimOpts) -> RoundResult
runCell: (opts: SimOpts, rounds: number, role: CellRole?) -> CellResult  -- role defaults to "gated"
evaluateBars: (cell: CellResult) -> (boolean, { string })
evaluateMechanisms: (cells: { CellResult }, evidence: MechanismEvidence) -> (boolean, { string })
```

`runCell`'s third parameter is additive to the plan's published two-parameter signature: `role` is a
cell-level concern and is meaningless for `runRound`, so it belongs to the cell call rather than to
`SimOpts`. Plan 02-10 passes `"mechanism"` for its twins and `"autopass-probe"` for its probe.

### The failure-name vocabularies

| `evaluateBars` | fires when |
|---|---|
| `no-completions` | `firstCompletionSamples == 0`. Returns FIRST, before any median is touched |
| `stalls` | `stallRate > 0` |
| `cleared-fraction` | `Cleared < rounds - DeadPool - RosterShortfall` (the stalls bar from the other side) |
| `median-first` | `medianFirst > 45` |
| `p95-first` | `p95First > 120` |
| `occupancy` | `occupancyMean < 0.60` |
| `valve-rate` | `valveFiringRate > VALVE_RATE_MAX = 0.01` |

| `evaluateMechanisms` | fires unless |
|---|---|
| `valve-never-fired` | `evidence.deterministicFiringProven`, OR summed `valveFiringsTotal` over valve-ON cells >= `VALVE_MIN_FIRINGS = 20` |
| `valve-twin-missing` | `evidence.deterministicTwinProven`, OR some valve-OFF cell matches SOME gated cell on `(k, j, jokerMode)` — `n` deliberately excluded |
| `valve-not-load-bearing` | `evidence.deterministicTwinProven`, OR at least one matched twin exists AND every matched twin has `stallRate >= VALVE_PROOF_MIN_STALL_RATE = 0.0005` |
| `autopass-probe-missing` | some cell has `role == "autopass-probe"` |
| `autopass-never-fired` | that probe's `autoPassRate >= AUTO_PASS_PROBE_MIN_RATE = 0.005` |

Exported constants: `SOLVABILITY_ACTION_CAP`, `MEDIAN_FIRST_MAX_SECONDS`, `P95_FIRST_MAX_SECONDS`,
`OCCUPANCY_MIN`, `VALVE_RATE_MAX`, `VALVE_MIN_FIRINGS`, `VALVE_PROOF_MIN_STALL_RATE`,
`AUTO_PASS_PROBE_MIN_RATE`.

## The chosen rung, the measured time and the implied throughput

**RUNG 2**: `N in {3, 6, 10}` x `jokerMode in {Wild, Blocker}` x `churn in {false, true}` = **12
gated cells x 500 rounds = 6,000 gated rounds**, a full cross product at three roster sizes.

The plan's ladder table was built on research 11.1's 1,904 rounds/s counters-only with a 2-3x
pessimism factor. **Measured**, driving the real engine across the whole 32-cell rung-1 set:
**16,000 rounds in 9.72s = 1,646 rounds/s and 242,800 actions/s** (2,359,689 actions). Research's
throughput held up almost exactly; the realised pessimism factor is **1.16x**, not 2-3x.

| rung | gated cells | gated rounds | measured gated | + non-gated | total | <= 8.0s? |
|---|---|---|---|---|---|---|
| 1 — N in {3..10} | 32 | 16,000 | 9.72s | ~1.5s | ~11.2s | **NO** |
| 2 — N in {3,6,10} | 12 | 6,000 | 4.20s | ~1.6s | **5.77s** | **YES** |
| 3 — N in {3,6,10}, churn only at N=10 | 8 | 4,000 | 3.16s | ~1.6s | ~4.8s | yes |
| 4 — N in {3,10}, churn+Blocker only at N=10 | 5 | 2,500 | 2.70s | ~1.6s | ~4.3s | yes |

Rung 2 is taken because the rule is "stop at the FIRST rung that measures <= 8.0s". The subset
simulates **6,623 rounds** in total (6,000 gated + 200 auto-pass probe + 200 occupancy + 100 roster
shortfall + 60 sabotage + 40 sabotage replays + 20 dead pool + 3 determinism) plus 2,114 fixture
actions, so the **implied throughput for the file as a whole is ~1,148 rounds/s** — lower than the
bulk figure because a destroyed-card round and a one-card `k=0, j=1` round are the two slowest round
shapes this simulator has, and both are deliberately in there. **Plan 02-11 re-measures against
~1,148 rounds/s for the file and 1,646 rounds/s for healthy bulk.**

Note for whoever reads a filter number next: `--filter engine` is now `140 passed ... in 3.06s`
rather than 139 at 2.32s, because one subset case is named "a deliberately broken **engine** is
reported as a FAILURE" and the filter matches the whole label. That is a label collision, not an
engine regression.

## Full-suite arithmetic, reported rather than absorbed

| run | result |
|---|---|
| baseline at this plan's HEAD | `461 passed, 0 failed, 3 todo in 17.29s` |
| with this plan in | **`493 passed, 0 failed, 3 todo in 23.41-24.45s`** |
| `scripts/verify.luau` | **14/14 in 26.1s** (was ~19-20s) |
| the three new spec files (`--filter sim`) | 6.88s (subset 5.77s, simulator 1.33s, bots 0.29s) |

CONTEXT's locked "~20s should stay true" is **not reachable** and was already unreachable before
this plan — 02-08-SUMMARY says so at 17.9s with this plan still to come. The suite now sits just
inside the ~25s stop-and-report line. **The overshoot goes to the owner at plan 02-12's
checkpoint.** Nothing was trimmed to fit a wall clock: the 500-round gated floor is intact, all
seven mutation cases are present and no bar was relaxed. The one sample size that changed — the
sabotage diagnostic, 300 to 60 rounds — changed because the measured effect size is 15-25x larger
than the figure it was sized against, with the arithmetic written next to the constant.

## THE FINDING: two of the five G1 bars are unmet, and the cause is measured

### What was measured

At N=10, Pacing, `k=2, j=1` (the plan's **provisional** reference pool), 2,000 rounds per cell:

| quantity | measured | 02-CONTEXT A7-CORRECTION |
|---|---|---|
| stall rate, valve **OFF** | **10.6%** | 0.250% |
| stall rate, valve **ON** | **0.05% - 0.10%** | 0.000% |
| rounds in which the valve fired | **10.8% - 15.8%** | 0.25% |

`valveFiringRate` with the valve ON equals `stallRate` with the valve OFF **to three decimal places
at every pool measured**: 0.398/0.398 at `k=1, j=0`; 0.290/0.290 at `k=1, j=1`; 0.172/0.172 at
`k=2, j=0`; 0.106/0.106 at `k=2, j=1`; 0.084/0.084 at `k=2, j=2`; 0.040/0.040 at `k=4, j=1`. So the
firings are not coincidental hash collisions under a stochastic schedule — every one of them rescued
a round that provably would not have finished. Inspected round by round, a valve-off stall is a
**1,300-1,900 action non-progressing tail** that hits the 300s cap with `allSpoonsSeconds = nil`,
against 313 actions and 28s for a healthy round, and **all 53 stalled seeds in a 500-round sample
clear with the valve on**, taking 1 to 4 firings each. The engine's valve is doing exactly what
amendment A7 asked of it, a hundred times over.

### Why the numbers diverge from the prototype's

The stall rate is almost entirely the **endgame**, and the endgame depth is set by the completion
target — which is exactly the quantity amendment A3 fixes. At N=10, `k=2, j=1`, valve OFF, 500
rounds, varying the target:

| completion target | stall rate | where the stalls happen |
|---|---|---|
| 8 (= `seatCount - 1`, **A3's value**) | **10.6%** | 33 at `liveCount == 2`, 11 at 3, 6 at 4, 1 at 5, 2 at 7 |
| 7 | 4.0% | 11 at 3, 6 at 4, 1 at 5, 2 at 7 |
| 6 | 1.8% | 6 at 4, 1 at 5, 2 at 7 |
| 5 | 0.6% | 1 at 5, 2 at 7 |
| 4 | 0.4% | 2 at 7 |

A 2-seat greedy endgame is `tests/harness/Livelock`'s own configuration, so a round that must play
down to two seats is structurally cycle-prone. Research **OQ-B** warned that this off-by-one "shifts
the chosen configuration by a full notch"; measured, it shifts the stall rate by a factor of 20 or
more, and **under A3 the reference pool `k=2, j=1` behaves like the prototype's `k=2, j=2`**. This
also corroborates research 3.6's own range (pure greedy livelocks 1-45%), which A7-CORRECTION's
0.250% never sat inside.

### What that does to the two bars

- **`stalls` is a ZERO bar.** The measured valve-ON residual at N >= 9 is 0.05-0.10%, so a 500-round
  cell shows at least one stall about 39% of the time and a four-N=10-cell rung about 85% of the
  time. It is a 4,000-round bar; CI runs 500-round cells.
- **`valve-rate` is a 1% bar** derived from the prototype's 0.25% figure. Every pool in amendment
  A4's grid (`k in {1,2}`, `j in {1,2}`) measures 8.4%-29.0% at N=10. Sweeping k upward at 2,000
  rounds per cell to look for a pool that clears it: `k=5` 1.85%, `k=6` 1.80%, `k=7` 1.85%, `k=8`
  1.20%, `k=9` 0.70%, `k=10` 0.75%, `k=12` 0.15% — and even `k=12`, far outside the searched grid,
  still carries a 0.05% residual stall rate. **No pool clears both bars robustly at 500 rounds.**

This is the same disease the plan diagnosed for `VALVE_MIN_FIRINGS` ("a threshold is only a
threshold **relative to a round count**") and cured with `MechanismEvidence`, left uncured on the
forward bars.

### What was done about it, and what was NOT done

- `Simulator.evaluateBars` is **UNCHANGED**. `VALVE_RATE_MAX` is still `0.01`, `"stalls"` still
  fires on any non-zero stall rate, and both keep their own mutation cases (case 4 and case 6b).
- `Types.VALVE_ARM_ACTIONS_PER_SEAT` was **NOT** changed. It would not help: every firing
  corresponds to a real stall, so a later arm point delays the rescue rather than avoiding it.
- The pool was **NOT** moved to make the gate green. Selecting `k=9` or `k=12` would have produced a
  green gate on a configuration nobody will ship and that 02-10 will not search.
- CI asserts the three bars it can resolve outright (`median-first` at 4x margin, `p95-first` at 6x,
  `occupancy` at 1.3x) and **replaces** the two it cannot with assertions calibrated to 500 rounds:
  - `stallRate <= 0.006` — 6x the measured residual mean, and 18x below the 10.6% a valve regression
    produces, so it has margin in both directions.
  - for every N=10 gated cell, **`valveFiringRate > VALVE_RATE_MAX`**. Asserting that the rate still
    EXCEEDS the bar is what makes the exemption earned rather than assumed: if a later engine or
    pool change ever brings it under the bar, that assertion fails and whoever sees it deletes the
    exemption. That is the only honest way to carry a known-unmet bar in a green suite.

**For the owner at plan 02-12's checkpoint:** choosing the shipped pool is plan 02-10's sweep at
10,000 rounds per cell, where a 1% bar has 100 expected firings and is properly calibrated. Three
things need a decision: (1) whether the ~1% firing-rate bar survives contact with a measured
8-29% — it was proposed on the strength of a 0.25% figure this simulator does not reproduce; (2)
whether Gate G1's zero-stall bar is restated as a residual ceiling, since the measured valve-ON
residual is 0.05-0.10% at a full roster and not zero; (3) whether 02-10's search grid extends past
`k = 2`, since the firing rate falls monotonically with k and the grid's whole range is above the
bar.

## Measured gated cells (rung 2, 500 rounds each, seed base 20900)

| N | mode | churn | stall | valveRate | fires/round | medFirst | p95First | medAll | p95All | occupancy | seenResets | autoPassRate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | Wild | false | 0.0000 | 0.0000 | 0.000 | 4.60 | 9.47 | 4.6 | 9.5 | 0.865 | 0 | 0.00000 |
| 3 | Wild | true | 0.0000 | 0.0000 | 0.000 | 4.46 | 11.33 | 4.5 | 11.3 | 0.868 | 0 | 0.00000 |
| 3 | Blocker | false | 0.0000 | 0.0000 | 0.000 | 6.32 | 10.62 | 6.3 | 10.6 | 0.899 | 0 | 0.00000 |
| 3 | Blocker | true | 0.0000 | 0.0000 | 0.000 | 7.37 | 13.30 | 7.4 | 13.3 | 0.909 | 0 | 0.00000 |
| 6 | Wild | false | 0.0000 | 0.0260 | 0.036 | 7.56 | 12.62 | 14.8 | 22.6 | 0.842 | 0 | 0.00000 |
| 6 | Wild | true | 0.0000 | 0.0080 | 0.008 | 7.71 | 14.05 | 17.6 | 27.3 | 0.859 | 0 | 0.00000 |
| 6 | Blocker | false | 0.0000 | 0.0620 | 0.072 | 9.56 | 14.42 | 16.1 | 52.6 | 0.849 | 0 | 0.00000 |
| 6 | Blocker | true | 0.0000 | 0.0340 | 0.042 | 10.29 | 16.54 | 19.7 | 28.8 | 0.869 | 0 | 0.00000 |
| 10 | Wild | false | 0.0000 | 0.0980 | 0.120 | 11.61 | 17.85 | 28.7 | 72.2 | 0.787 | 0 | 0.00000 |
| 10 | Wild | true | 0.0000 | 0.0560 | 0.060 | 11.89 | 19.86 | 32.1 | 70.0 | 0.820 | 0 | 0.00000 |
| 10 | Blocker | false | 0.0020 | 0.1580 | 0.192 | 14.55 | 20.60 | 31.8 | 87.7 | 0.794 | 0 | 0.00000 |
| 10 | Blocker | true | 0.0000 | 0.1000 | 0.124 | 14.24 | 21.34 | 34.1 | 88.3 | 0.826 | 0 | 0.00000 |

**Totals: 6,000 gated rounds, 327 firings, mean 0.0545 firings/round, `valveSeenResetsTotal = 0`.**

Against the reference figures: measured `valveFiringRate` is **0.0545 mean firings/round** against
the reference 0.005 (11x) and **0.0-0.158 of rounds** against the reference 0.25% (up to 63x). The
measured `armedRate` equals `valveFiringRate` exactly in every cell — whenever a round arms, it
fires — which is the mechanical reason the two quantities coincide.

`valveSeenResetsTotal = 0` across all 6,000 gated rounds: `VALVE_SEEN_CAP` is 4,096 observations and
a gated round is ~313 actions, so the window never overflows and the valve was never blind here.
Plan 02-14 can read a non-zero value as "the valve could not see", and that distinction is what the
residual stall rate turns on.

**Occupancy at the two discriminating cells (research 3.7):** `k=0, j=1` at N=10 measures **0.174**
(research ~0.14, bar 0.60 — correctly rejected) and `k=2, j=2` at N=10 measures **0.808** (research
~0.70 — correctly accepted). Both sit on the right side of the bar with margin, so amendment A2's
third bar discriminates.

**Auto-pass probe at a 1.0s deadline:** `autoPassRate = 0.01446` — **887 auto-passes over 61,358
actions in 200 rounds**, against the reference 2.86% (0.51x) and the `AUTO_PASS_PROBE_MIN_RATE` bar
of 0.005 (2.9x margin). At the gated 5.0s deadline the rate is **0.00000 in all 12 cells** — zero
auto-passes in 6,000 rounds — which is the correct shipped behaviour and exactly why requiring the
auto-pass to fire in the gated cells would be requiring the product to be wrong.

**Deterministic valve proof:** `deterministicFiringProven` and `deterministicTwinProven` were both
**OBSERVED true**. The fixture armed, **fired on action 113** and **completed on action 114** —
matching 02-07's and 02-13's independently measured numbers exactly, with nothing adjusted to make
them match — and the end hash differs from the first armed observation. The twin, the same cycle
with `antiLivelockValve = false`, ran **2,000 actions with 0 firings and 0 completions**.

## The seven mutation proofs, verbatim

```
    rung 2: 12 gated cells x 500 rounds; worst valveFiringRate 0.1580, worst stallRate 0.0020, probe autoPassRate 0.01446
    fixture: armed-hash observed, valve fired on action 113, completed on action 114
    set A failures: valve-never-fired,valve-twin-missing,valve-not-load-bearing
    set B failures: valve-never-fired,valve-not-load-bearing
    probe at a 1.0s deadline: autoPassRate 0.01446 over 61358 actions (887 auto-passes in 200 rounds)
    quiet probe: autopass-never-fired | deleted probe: autopass-probe-missing
    sabotage over 60 rounds: Unsatisfiable=47 CapReached=13 Cleared=0 stallRate=1.0000 bars=stalls,cleared-fraction,valve-rate
    bad pool as a 500-round cell sees it: valve-rate
    the same pool with its residual resolved: stalls,valve-rate
    3 leavers over 100 rounds: RosterShortfall=100 Cleared=0 stalled=0 stallRate=0
    occupancy k=0 j=1: 0.174 (research ~0.14); k=2 j=2: 0.808 (research ~0.70)
    replayed 20 failing seeds, all reproduced
15 passed, 0 failed, 0 todo in 5.77s
```

| # | mutation | reported as | cost |
|---|---|---|---|
| 1 | a deliberately broken engine (`DestroyRemovedCards` + churn) | `stalls`, `cleared-fraction`, `valve-rate`; 47 of 60 rounds `Unsatisfiable` with `violation = "satisfiable-false"` | 60 rounds |
| 2 | the dead pool `k=0, j=0` | 20 of 20 `DeadPool`, 0 actions, bars fail `no-completions` | 20 rounds (zero actions) |
| 3 | the valve-off fixture that never escapes | 0 firings, 0 completions in 2,000 actions | 2,000 actions |
| 4 | no proof and NO twin cell (set A) | all three valve bars, including the empty-`forall` case the "at least one matched twin" clause exists to close | **zero rounds** |
| 5 | a non-stalling twin (set B) | `valve-not-load-bearing` fires while `valve-twin-missing` correctly does not — the two bars separate | **zero rounds** |
| 6 | a quiet probe, and a DELETED probe | `autopass-never-fired`, then `autopass-probe-missing` | **zero rounds** |
| 7 | a bad pool on its valve rate alone | `valve-rate` as the ONLY failure at `stallRate = 0`; both bars once the residual is resolved | **zero rounds** |

Plus the positive control the plan asked for: the **satisfiable triple** (a gated cell with
`valveFiringsTotal = 25`, a twin with `stallRate = 0.0025`, a probe with `autoPassRate = 0.0286`,
both evidence booleans false) returns `true` with an **empty** failure list, so the five mechanism
bars are jointly satisfiable by the statistical route the sweep takes and are not a gate nothing
passes.

## Deviations from Plan

### Auto-fixed and corrected

**1. [Rule 1 - Bug] Cycle detection with the valve enabled would have reported Livelock for rounds the engine provably escapes**
- **Found during:** Task 2
- **Issue:** The plan states "with the valve enabled this mode will essentially never report
  `Livelock`, because the valve fires at or before the point the cursor-aware detector would prove a
  cycle". That is false in the measured direction: the detector fires at the **first** repeated
  `(hash, cursor)` — action 17 in the Livelock fixture — while the valve's arm gate needs
  `48 * liveCount` actions with no progress (96 there, firing at 113). The detector always wins the
  race, so every valve-on livelock-prone round would have been classified `Livelock` before the
  valve could act, and the valve's entire measured effect would have been invisible.
- **Fix:** Cycle detection is enabled only when `config.antiLivelockValve == false`. This is the
  plan's own soundness condition applied properly — the valve draws from its own generator, so with
  it enabled the dynamics are not deterministic and a repeated hash is not a proof of
  non-termination. With the valve on, Solvability terminates on the action cap and `hitActionCap`
  tells plan 02-14 which it was.
- **Files modified:** `scripts/sim/Simulator.luau`
- **Commit:** `8159e96`

**2. [Rule 2 - Missing critical functionality] `RosterShortfall` was structurally unreachable, so the plan's case 7 could never fail**
- **Found during:** Task 2
- **Issue:** `live = seatCount - completions - churnRemovals` and
  `remaining spoons = (seatCount - 1) - completions`, so `live < remaining` reduces to
  `churnRemovals > 1` **exactly**. With `churn: boolean` meaning one leaver, the two quantities are
  always equal and the strict inequality can never hold. The plan's case 7 — "construct a churned
  cell where live seats drop below the remaining spoons" — was incapable of failing.
- **Fix:** `SimOpts.churnLeavers: number?` added, defaulting to 1 when `churn` is true. Case 7 uses
  3 leavers and observes 100 of 100 `RosterShortfall`. A sibling case asserts that the gated
  one-leaver churn cells see **zero** shortfalls, so the arithmetic is now proven in both
  directions rather than assumed.
- **Files modified:** `scripts/sim/Simulator.luau`, `tests/sim/simulator.spec.luau`,
  `tests/sim/subset.spec.luau`
- **Commit:** `8159e96`, `0d3309b`

**3. [Rule 1 - Bug] Case 6b asked for something no zero-stall bar can satisfy**
- **Found during:** Task 3
- **Issue:** The plan's case 6b hands `evaluateBars` a cell with `stallRate = 0.00025` and asserts
  `"valve-rate"` IS named while `"stalls"` is NOT. But bar 1 is `stallRate > 0` and
  `0.00025 > 0`, so the assertion is incapable of passing against any correct implementation. (It
  failed exactly this way on the first run.)
- **Fix:** Split into the two halves that are each true and each worth asserting: **(a)** the
  500-round view — `stallRate = 0` with `valveFiringRate = 0.216`, where `"valve-rate"` fires
  **alone** and the discrimination claim is exactly right (at a 0.025% true rate a 500-round cell
  shows zero stalls 88% of the time, which is what "would sail past a naive zero-stall bar" means);
  and **(b)** the resolved view — `stallRate = 0.00025`, where **both** bars fire, showing they
  agree once the rate is resolvable rather than that one is redundant.
- **Files modified:** `tests/sim/subset.spec.luau`
- **Commit:** `0d3309b`

**4. [Rule 3 - Blocking] The gated `stalls` and `valve-rate` bars are not resolvable at 500 rounds, at any pool**
- **Found during:** Task 3
- **Issue:** See THE FINDING above. The plan's must-have "the CI subset passes the bars in every
  cell" presupposed the prototype's 0.000% stall / 0.25% firing figures, which this simulator does
  not reproduce at any pool from `k=1` to `k=12`.
- **Fix:** `evaluateBars` untouched; both bars keep their mutation cases; CI substitutes
  500-round-calibrated assertions with margin in both directions, including a **gated** assertion
  that the N=10 firing rate still exceeds the bar so the exemption self-deletes. The measurement,
  its cause, the k-sweep that rules out a pool change and the reason the engine constant is the
  wrong lever are all written into the spec header. Escalated to the owner at 02-12.
- **Files modified:** `tests/sim/subset.spec.luau`
- **Commit:** `0d3309b`

**5. [Rule 3 - Blocking] The sabotage sample was sized against a rate 15-25x too small, at 36% of the subset budget**
- **Found during:** Task 3
- **Issue:** The plan's 300 rounds rests on research 3.4's 2.9-5.7% of churned rounds and on the
  premise that the cell is "cheap AND wide". Measured: the rate is **77%** (232 of 300) because
  destroying a departing seat's whole routed bundle removes 4-13 cards from a pool whose entire
  circulation is 9; and the cell cost **2.92s**, more than the whole gated set.
- **Fix:** 60 rounds. At 77% the chance of seeing none is `0.23^60`, about `1e-38` — better
  calibrated than 300 was against the assumed rate — and 2.3s cheaper. The 500-round **gated** floor
  is untouched; this is a diagnostic sample sized against its own measured effect, which is what
  every other threshold in the file is. The arithmetic sits next to the constant.
- **Files modified:** `tests/sim/subset.spec.luau`, `tests/sim/simulator.spec.luau` (the behaviour
  case's own sabotage sample, 120 to 30 rounds, same arithmetic)
- **Commit:** `0d3309b`, `8159e96`

**6. [Rule 3 - Blocking] Luau widens an optional union of string singletons under `~= nil`**
- **Found during:** Task 2
- **Issue:** `local function execute(...): Outcome?` followed by `if terminal ~= nil then finish(terminal, ...)`
  fails the typecheck with "Expected `Outcome`, but got `string`". Reproduced in a four-line
  fixture, so it is a solver limitation and not a mistake in the file.
- **Fix:** `execute` and `maybeChurn` return `RoundResult?` and call `finish` themselves. Table-type
  refinement works correctly, so the alternative — a `:: Outcome` cast on the value that decides a
  round's category — is avoided.
- **Files modified:** `scripts/sim/Simulator.luau`
- **Commit:** `8159e96`

### Additions

**7. Two TDD specs the plan did not list.** Tasks 1 and 2 are marked `tdd="true"` and their
`<behavior>` blocks are test lists, but the plan's artifacts name only `tests/sim/subset.spec.luau`.
`tests/sim/bots.spec.luau` (7 cases, 0.29s) and `tests/sim/simulator.spec.luau` (10 cases, 1.33s)
carry those behaviours. They are discovered automatically; no CI step was added.

**8. `runCell`'s optional third `role` parameter**, and `Pool.poolConfig` read for its seat count
only — both explained under key-decisions.

**9. `sabotage` and `identityCheck` are refused together.** A destroyed routed card IS a
conservation violation, so `Invariants.check` reports `circulation` on the next action and the
simulator correctly errors on any `check` violation. Loud at setup rather than confusing at action 12.

### Plan acceptance criteria that cannot hold as written

**`grep -rq 'DestroyRemovedCards\|destroy' src/` must FAIL.** It **succeeds** against pre-existing
code and always would have: `src/server/services/PlayerGate.luau` and `NetServer.luau` have lifecycle
`destroy` methods, and `src/server/engine/{Types,Invariants,Ring}.luau` carry the prose "never
destroyed" that states Rule 8. The criterion's intent is met and asserted the meaningful way:
`grep -rq 'DestroyRemovedCards' src/` **fails** (verified), and the sabotage path exists only in
`scripts/sim/Simulator.luau`. No code was changed for this; the criterion is the thing that needs
rewording.

**`grep -q 'math.random' scripts/sim/Bots.luau` must FAIL.** It initially succeeded because a header
comment named the banned construct while explaining its absence. The comment was reworded; the file
now does not contain the string at all, in code or prose.

## Authentication gates

None.

## Known Stubs

None. Every function in `Bots` and `Simulator` is fully implemented and exercised by at least one
case; no hardcoded empty value flows into any result.

## Threat Flags

None. The two trust boundaries in the plan's threat model hold as written: the simulator drives the
real `Engine.apply` and contains no second copy of the card rules, and the Rule 8 destroy path lives
only in `scripts/sim/Simulator.luau` with `grep -rq 'DestroyRemovedCards' src/` failing.

## Task Commits

1. **Task 1: Bots** — `2330484` (test, RED: 0 passed / 1 failed) then `3998f18` (feat, GREEN: 7 passed / 0 failed)
2. **Task 2: Simulator** — `3e776fe` (test, RED: 0 passed / 1 failed) then `8159e96` (feat, GREEN: 10 passed / 0 failed)
3. **Task 3: the CI subset** — `0d3309b` (test: 15 passed / 0 failed in 5.77s)

No commit deleted a tracked file: `git diff --diff-filter=D --name-only 2330484~1..HEAD` is empty.

## Verification

```
stylua --check src scripts tests                                      clean
selene src scripts tests                                              0 errors, 0 warnings
lune run scripts/ci/analyze.luau ... src/server/engine src/server/core src/shared/Net scripts tests
                                                                      analyze: ok
lune run scripts/ci/check-guards.luau                                 ok (82 files, 208 requires, 20 guarded roots)
lune run tests/run.luau -- --filter sim/subset                        15 passed, 0 failed, 0 todo in 5.77s
lune run tests/run.luau                                               493 passed, 0 failed, 3 todo in 23.41s
lune run scripts/verify.luau                                          all 14 automated steps passed in 26.1s
git diff --stat .github/workflows/ci.yml scripts/verify.luau          empty
```

## What the next plans must honour

### Plan 02-10 (the sweep) — read this first

1. **The firing-rate and stall-rate figures this plan measured are 20-60x the reference**, and the
   cause is amendment A3's completion target rather than anything in the engine. Size the sweep's
   stages against the MEASURED rates, not the reference: `--stage mechanism` was sized for ~10 stalls
   per 4,000-round twin at 0.25% and will see roughly **424**, so it is far better powered than
   planned and could be shortened if the budget needs it.
2. **`k=2, j=2`'s firing rate and the valve-off twin's stall rate are NOT measured in this SUMMARY**
   beyond the pools tabulated above — they are plan 02-10's `--stage search` (k=2,j=2 valve-ON at
   1,000 rounds) and `--stage mechanism` (its twin at 4,000). Plan 02-11 should not go looking for
   them here.
3. **Do not run `evaluateBars` over Solvability cells.** They carry nil times by construction, so
   they fail `"no-completions"`. The pacing bars are for Pacing cells.
4. **`evaluateMechanisms`'s twin match is POOL-keyed on `(k, j, jokerMode)` and excludes `n`**, so a
   confirm stage emitting 32 gated cells across N=3..10 against 4 twins at N=10 passes. Pass
   `role = "mechanism"` for twins and `role = "autopass-probe"` for the probe through `runCell`'s
   third parameter, and never put a diagnostic cell into the evidence set — a 400-round `k=2, j=2`
   cell carries enough firings to satisfy `"valve-never-fired"` on its own.
5. **Consider extending the search grid past `k = 2`.** The firing rate falls monotonically with k
   (0.398 at k=1, 0.106 at k=2, 0.040 at k=4, 0.018 at k=6, 0.007 at k=9, 0.0015 at k=12 at N=10)
   and the whole of amendment A4's grid is an order of magnitude above the proposed bar. Occupancy
   rises with k too (0.79 at k=2 to 0.89 at k=12), and `median-first` stays inside 45s up to about
   `k=12` (26.1s) — so the bars do not conflict in that direction. That is an owner decision.
6. **Throughput to budget against:** 1,646 rounds/s and 242,800 actions/s healthy,
   ~1,148 rounds/s for a mixed file. A 540,000-round sweep is therefore roughly **5.5 minutes** of
   pure simulation at `identityCheck = false`, not 20-40 minutes — unless its cells include
   sabotage or thin-circulation pools.

### Plan 02-11 (the decision)

- `AUTO_PASS_SELECTION` must be recorded as `uniform-random-from-hand`: `Bots.randomPass` is that
  rule, and the header states why "auto-pass your worst card" would make every auto-pass number here
  transfer nothing.
- The CI subset's constants to re-check: `REFERENCE_K = 2`, `REFERENCE_J = 1`,
  `AUTO_PASS_SECONDS = 5.0`, `RUNG_PLAYER_COUNTS = {3, 6, 10}`, `roundsPerCell = 500`,
  `CI_RESIDUAL_STALL_MAX = 0.006`. If the shipped pool changes, the N=10 firing-rate assertion in
  case 1 must be re-measured and may need deleting — which is the point of it being an assertion.

### Plan 02-14 (the triage)

- `capArtifactCandidates` carries the seeds of rounds that ended on the action cap, and
  `hitActionCap` distinguishes them from the time cap. **In 6,000 gated rounds neither fired**: every
  gated stall was a `time-cap` round. The one residual stall at N=10 Blocker is a `CapReached` with
  `hitActionCap = false`.
- `valveSeenResetsTotal = 0` across all 6,000 gated rounds, so the valve was never blind in healthy
  play. A non-zero value in a sweep cell is the signal that `CapArtifact` cannot be told from
  `ResidualLivelock`.
- The valve-ON residual to triage is **0.05-0.10% at N >= 9** (2 of 2,000 Wild, 1 of 2,000 Blocker,
  2 of 2,000 at N=9), with zero at N=3 and N=6 — not the 0.025% at `k=2, j=2` the plan expected.

### Phase 4

- The simulator's clock is **float seconds**; the shipped clock is **integer deciseconds** on the
  server. Any pacing value taken from here must be rounded to deciseconds at that boundary.
- `ValveForcedPass` must be read as "that pass was not the player's choice", the same contract as an
  AFK auto-pass. It fires in **5.5% of all rounds and up to 15.8% at a full roster** at the current
  provisional pool — far more often than the 0.25% the UI was going to be designed against, so it
  needs a real affordance rather than being treated as invisible.
- Research 3.8's start-up ramp is confirmed: `rampMean` is 8.3s at N=10 against a 4.6s median
  time-to-first-completion at N=3, so far seats really do wait several seconds for cards and the
  "waiting for cards" affordance is needed.

## Self-Check: PASSED

All five created files exist on disk at the sizes recorded above, and all five task commits
(`2330484`, `3998f18`, `3e776fe`, `8159e96`, `0d3309b`) are present in `git log --all`. No commit
deleted a tracked file. The suite, `--filter sim/subset` and `scripts/verify.luau` were all re-run
green at this SUMMARY's HEAD.
