---
phase: 02-card-engine-and-pacing-simulator
plan: 11
subsystem: config
tags: [gate-g1, card-pool, spec-lock, auto-pass, anti-livelock-valve, validation-contract, mutation-proof, drift-guard]

requires:
  - phase: 02-14
    provides: "02-G1-REPORT.md and 02-sweep-data.json - the committed verdict this plan records, re-run at the owner's chosen operating point so the shipped pool is also the confirmed one"
  - phase: 02-09
    provides: "tests/sim/subset.spec.luau (the CI regression subset, its rung ladder, its seven mutation proofs and the MEASURED 8.0s budget this plan re-measures against) and Bots.randomPass, the auto-pass selection rule being recorded"
  - phase: 02-04
    provides: "Pool.poolConfig (amendment A3's seatCount = n - 1, the only site that owns it), Pool.deal's returned attempt counter and Pool.openingHandIsBad - CARD-09's assertions are built on all three"
  - phase: 02-05
    provides: "Hand.detectCompletion's Completion record (rank, retired, fifth, naturalsUsed, jokersUsed) - CARD-10 asserts the exact retired list against it"
  - phase: 02-07
    provides: "Engine.newRound / Engine.apply and the locked event order - CARD-12 drives both joker modes through them in one process"
  - phase: 01-02
    provides: "tests/run.luau's todo counting, its exit-1-on-a-filter-that-matches-nothing rule, and tests/harness/Test.luau's contains/deepEqual"
provides:
  - "src/shared/Config/CardPool.luau - the shipped pool (EXTRA_RANKS 3, JOKERS 1, JOKER_MODE Wild, ANTI_LIVELOCK_VALVE true, AUTO_PASS_MAX_SECONDS 8.0, AUTO_PASS_SELECTION uniform-random-from-hand) with the report cited and the owner's k=3-over-k=6 reasoning recorded"
  - "A CI subset whose GATED cells are built from CardPool, so the gate cannot be green for a configuration that is not the one that ships"
  - "tests/engine/spec_lock.spec.luau - CARD-09, CARD-10 and CARD-12 as real tests; the runner's todo count is 0 and no spec anywhere registers a todo"
  - "A drift guard between the shipped config and its committed evidence: the CARD-12 case reads 02-G1-REPORT.md's Verdict and diffs k, j, the deadline, the mode and marginal=false against CardPool"
  - "02-VALIDATION.md signed off: every documented --filter runs and exits 0, the five mechanism checks and seven mutation proofs are in the falsifiability table, the satisfiability row is corrected, nyquist_compliant true"
affects: [02-12, 04]

tech-stack:
  added: []
  patterns:
    - "A decision lives in a module, not in a markdown table, so a later phase that contradicts it fails a test rather than a review"
    - "A config module records what the numbers are NOT: the stall claim is written as the measured residual (0.012% aggregate / 0.070% worst cell against a 0.500% ceiling), never as zero and never as a theorem about the engine"
    - "The gate reads the shipped configuration; the MUTATION EVIDENCE does not. Diagnostics stay at the pool their effect sizes were calibrated at, renamed DIAGNOSTIC_* so the split is visible - pointing them at the shipped config would make them follow the thing they exist to falsify"
    - "A shipped-configuration gate asserts EQUALITY against cells already simulated rather than re-running them: zero added rounds, and strictly stronger than a duplicate run (a duplicate proves the pool passes, the equality proves the pool the GATE ran is the shipped one)"
    - "Two drift directions need two guards: config-versus-construction-path is caught by the subset's equality case, config-versus-committed-evidence only by a case that reads the report. Each was mutation-proven separately"
    - "A falsifiability claim states what the check CANNOT catch as well as what it can, so the next reader does not over-trust it"
    - "A validation contract's own commands are executable artefacts: a documented --filter that matches nothing exits 1, so an unreconciled requirements map is a set of documented commands that fail"

key-files:
  created:
    - src/shared/Config/CardPool.luau
    - .planning/phases/02-card-engine-and-pacing-simulator/02-11-SUMMARY.md
  modified:
    - tests/sim/subset.spec.luau
    - tests/engine/spec_lock.spec.luau
    - .planning/phases/02-card-engine-and-pacing-simulator/02-VALIDATION.md

key-decisions:
  - "Gate G1 ships k = 3 extra ranks, j = 1 joker, Wild as the default mode with Blocker behind the flag, the anti-livelock valve ON and an 8.0s auto-pass deadline, with AUTO_PASS_SELECTION = uniform-random-from-hand as a constraint on Phase 4"
  - "k=3 over the bar's k=6 is a GAMEPLAY decision, not a measurement: every candidate k=2..6 clears all five bars and the firing-rate curve is smooth with no elbow, so the bar chooses rather than discovers. k=3 is the tightest pool with a clean search-grid zero, gives up ~2s of starting-gun speed against k=2 and avoids k=6's ~45% slower start"
  - "The stall claim is recorded as a measured RESIDUAL, not as zero: the confirm stage observed 37 stalled rounds in 320,000 with the valve ON"
  - "The subset's diagnostic and mutation cells deliberately keep the provisional k=2, j=1 pool at a 5.0s deadline; only the gated cells read CardPool"
  - "The shipped-configuration case adds zero simulated rounds and asserts equality instead, so the --filter sim/subset budget is unchanged"
  - "02-VALIDATION.md's filter commands were reconciled toward the real spec filenames; no near-empty spec file was created to match the document"

metrics:
  duration: ~2h
  completed: 2026-11-04
  tasks: 3
  files_created: 2
  files_modified: 3
---

# Phase 2 Plan 11: Close Gate G1 in Code Summary

**Gate G1's verdict is now a module the suite enforces, not a paragraph in a report: `k = 3, j = 1`,
Wild with Blocker behind the flag, valve ON, an 8.0s auto-pass deadline and
`AUTO_PASS_SELECTION = "uniform-random-from-hand"` live in `src/shared/Config/CardPool.luau`, the CI
subset's gated cells are built from it, a spec-lock case diffs it against the committed report, and
the three spec-lock todos are real tests — the runner reports `509 passed, 0 failed, 0 todo`, which
is Phase 2's exit condition.**

## The six shipped `CardPool` values, verbatim

Plan 02-12 copies these into CARD-16's requirement line, ROADMAP's Phase 4 note and PROJECT.md's Key
Decisions table.

```luau
return {
	EXTRA_RANKS = 3,
	JOKERS = 1,
	JOKER_MODE = "Wild",
	ANTI_LIVELOCK_VALVE = true,
	AUTO_PASS_MAX_SECONDS = 8.0,
	AUTO_PASS_SELECTION = "uniform-random-from-hand",
}
```

`ranks = seatCount + 3` with `seatCount = (players in round) - 1`; circulation `= 4k + j = 13`.

## The five bars at that configuration

From `02-G1-REPORT.md` section 1, measured over the confirmed cells at **10,000 rounds per cell**
(320,000 gated rounds, N = 3..10 x both joker modes x both churn variants):

| bar | measured worst case | bar | with margin |
|---|---|---|---|
| stalls | **0.070%** (0.012% aggregate — 37 stalled rounds in 320,000) | <= 0.500% | <= 0.250% |
| cleared fraction | every eligible round cleared to within the same ceiling | = 1 - the stall ceiling | |
| median first completion | **16.2s** | <= 45s | <= 36.0s |
| p95 first completion | **23.7s** | <= 120s | <= 96.0s |
| occupancy | **0.825** | >= 0.600 | >= 0.660 |
| valve firing rate | **8.240%** | <= 20.000% | <= 10.000% |

`marginal = false`. **G1 PASSES on this evidence** — as a measured property of a SELECTED
configuration, never as an unconditional property of the engine.

### The selected pool's valve firing rate, and why it is a feel cost

Per-cell at the shipped pool (report section 4b, confirm stage): N=3 0.00–0.16%, N=6 0.64–3.12%,
N=10 **3.59–8.24%** (Wild/no-churn 5.86%, Wild/churn 3.59%, Blocker/no-churn 8.24%, Blocker/churn
4.77%). The valve-DISABLED twins at the same pool and round count stall at **3.58–8.31%**, matching
the firing rate — so every firing is a real rescue and the valve is load-bearing at roughly 500x the
valve-on residual.

**Why k=3 and not the bar's k=6** (recorded because the number alone is not the decision): every
candidate from k=2 to k=6 clears all five bars, and the firing-rate curve is smooth and monotone with
no elbow, so the bar CHOOSES rather than discovers — 7% selects k=6, 20% selects k=3, 40% selects
k=2. The owner set the bar at the k=3 operating point and the sweep was then re-run at it, so the
shipped pool is also the confirmed one. k=3 is the tightest pool reaching a clean zero on the search
grid; it gives up ~2s of starting-gun speed against k=2 while cutting forced passes by about a third,
and avoids k=6's ~45% slower start (median first 20.9s against 16.2s). A `ValveForcedPass` is **not
invisible** — a card leaves a hand the player did not choose — so the firing rate is a feel cost, not
only a safety statistic.

### The auto-pass, and the constraint on Phase 4

`AUTO_PASS_MAX_SECONDS = 8.0` is a product value now that the valve carries the stall job (amendment
A7 demoted the auto-pass to a secondary mitigation, and CARD-16 benches a player after repeated
strikes, so a short deadline would strike ordinary players several times a round). Measured
auto-passes by deadline across the sweep's 216-cell slices: **0 at 8.0s**, 2 at 5.0s, 58 at 3.0s,
38,516 at 1.5s. The mechanism therefore cannot be gated on the shipped cells and is proven by a
dedicated 1.0s probe cell instead: `autoPassRate = 0.01446` of actions (887 auto-passes in 200
rounds) against the `AUTO_PASS_PROBE_MIN_RATE = 0.005` bar.

`AUTO_PASS_SELECTION = "uniform-random-from-hand"` is **not** derived from the report — it is the rule
`Bots.randomPass` modelled, and recording it is what stops Phase 4 shipping "auto-pass your worst
card". That would be the player's own greedy choice: deviation exactly zero, and the simulator's
auto-pass numbers transfer nothing to the shipped game. It is now asserted in two specs and will be
stated in four places once plan 02-12 lands.

## `--filter sim/subset` after the edit, beside plan 02-09's

| | plan 02-09 | plan 02-11 (this plan) |
|---|---|---|
| gated cells | 12 at 500 rounds = 6,000 | 12 at 500 rounds = 6,000 (**unchanged**) |
| gated pool | k=2, j=1 at a 5.0s deadline (provisional) | **k=3, j=1 at 8.0s, read from `CardPool`** |
| cases | 15 | 16 |
| rounds simulated by the file | 6,623 | **6,623 (identical — the new case adds none)** |
| measured wall time | 5.77s, 5.92s on a re-run | **5.73s / 5.74s / 5.83s / 5.97s** over four runs |
| implied throughput | ~1,148 rounds/s | **~1,138 rounds/s** (5.82s mean) |
| budget | 8.0s (derived in 02-09's rung table) | 8.0s — **2.0s of headroom** |

The number barely moved, which is the expected result: the edit adds no rounds, and the shipped pool
costs slightly more per round (circulation 13 against 9) while completing slightly sooner. No rung of
the ladder was descended, the 500-round gated floor is intact and all seven mutation cases are
present. The `totalRounds` identity is asserted in the spec itself —
`t.truthy(gatedCells() == cells, ...)` proves the new case reuses the memoised cell list rather than
building a second one.

Worst values the gated run reports at the shipped pool: `worst valveFiringRate 0.0840`,
`worst stallRate 0.0020` (one stalled round in one 500-round cell, against the
`CI_RESIDUAL_STALL_MAX = 0.006` ceiling), `probe autoPassRate 0.01446`.

## The three spec-lock cases, and what each asserts

`--filter engine/spec_lock` → **3 passed, 0 failed, 0 todo in 0.34–0.40s**.

**CARD-09** — 4,000 deals at the shipped pool (seats 2..9 x seeds 1..500) took **4,028 attempts**:
every accepted hand is legal by the engine's own `openingHandIsBad` in both of its conditions, and the
28-attempt surplus is what makes the predicate falsifiable (research §10: a predicate that never fires
is indistinguishable from a correct one). Bounded on both sides, and every seat count from 2 to 9
contributes at least one rejection, so the counter is non-vacuous per cell and not only in aggregate.
The rejection rate at the shipped pool is ~0.7% of deals, against the ~10% `pool.spec.luau`'s k=1,j=2
corpus sees — which is why 500 seeds per seat count, not 50.

**CARD-10** — crafted hands with **interleaved** card ids, so "naturals first, then jokers, each group
ascending" is a different list from "the hand in its own order". At 3 naturals + 2 jokers:
`retired = {2, 4, 5, 1}`, `fifth = 3` (a joker), `naturalsUsed = 3`, `jokersUsed = 1`. At 4 naturals +
1 joker: `retired = {1, 3, 4, 5}`, `fifth = 2`, `jokersUsed = 0` — no joker spent. The same five cards
complete nothing in Blocker.

**CARD-12** — four parts, because the decision has four: (a) the mode is one of exactly two literals;
(b) both variants run in one process — two rounds differing ONLY in `jokerMode` at the shipped pool,
`rankOf` asserted identical, the identical 3-intent trace yielding
`Drew, Passed, Drew, Completed, SeatRemoved` in Wild and `Drew, Passed, Drew` in Blocker, with a joker
in the retired set so the divergence is the wild standing in for a fourth natural; (c) the verdict's
two preconditions (`ANTI_LIVELOCK_VALVE == true`, `AUTO_PASS_SELECTION == "uniform-random-from-hand"`);
(d) the **drift guard** — `02-G1-REPORT.md`'s Verdict section is read with `@lune/fs` and its
`**Selected pool:` line is diffed against `CardPool` on k, j and the deadline, with the mode and
`Marginal: **false**` checked against the section.

## Mutation proofs, verbatim

House standard: a check is not trusted until it has been made to fail. Each mutation below was applied,
run, and reverted; the working tree was clean after each.

```
=== M1 CARD-09: the deal loop stops checking the WILD half (openingHandIsBad called with "Blocker") ===
FAIL tests/engine/spec_lock.spec.luau::CARD-09 deal-time four of a kind: re-shuffle so no seat starts complete, including hands completable by a wild
     seats=2 seed=73: seat 2 started on a complete or wild-completable hand (expected false, got true)

=== M2 CARD-09: the deal predicate is made vacuous (openingHandIsBad returns false immediately) ===
FAIL tests/engine/spec_lock.spec.luau::CARD-09 deal-time four of a kind: re-shuffle so no seat starts complete, including hands completable by a wild
     4000 deals took 4000 attempts: not one rejection fired, so the CARD-09 predicate is vacuous and a seat could start complete without this case noticing (expected a truthy value, got false)

=== M3 CARD-10: jokers are spent before naturals (naturalsUsed capped by the joker count) ===
FAIL tests/engine/spec_lock.spec.luau::CARD-10 joker completion: spend naturals first, so the four cards that leave are the natural ranks before any wild
     the three naturals ascending, THEN the lowest joker (expected { [1] = 2, [2] = 4, [3] = 5, [4] = 1 }, got { [1] = 2, [2] = 4, [3] = 1, [4] = 3 })

=== M4 CARD-12: the Blocker branch is removed, so both modes behave as Wild ===
FAIL tests/engine/spec_lock.spec.luau::CARD-10 joker completion: spend naturals first, so the four cards that leave are the natural ranks before any wild
     in Blocker a joker completes nothing, so 3 naturals + 2 jokers is just a 5-card hand (expected nil, got table: 0x00005620380c6ee0)
FAIL tests/engine/spec_lock.spec.luau::CARD-12 fallback: if Gate G1 fails, jokers ship as blockers instead of wilds, both variants behind a flag from the start
     the Blocker event list: the same hand is just a draw (expected { [1] = "Drew", [2] = "Passed", [3] = "Drew" }, got { [1] = "Drew", [2] = "Passed", [3] = "Drew", [4] = "Completed", [5] = "SeatRemoved" })

=== M5 CARD-12: a third joker mode (JOKER_MODE = "Wild" -> "Chaos") ===
FAIL tests/engine/spec_lock.spec.luau::CARD-12 fallback: ...
     CardPool.JOKER_MODE is "Chaos", which is neither variant the engine implements (expected a truthy value, got false)

=== M6 CARD-12: the valve ships disabled (ANTI_LIVELOCK_VALVE = true -> false) ===
FAIL tests/engine/spec_lock.spec.luau::CARD-12 fallback: ...
     G1's stall result is a measurement taken with the valve ON (expected true, got false)

=== M7 CARD-12: the auto-pass ships a greedy selection rule ("uniform-random-from-hand" -> "greedy-worst-card") ===
FAIL tests/engine/spec_lock.spec.luau::CARD-12 fallback: ...
     the auto-pass selection rule is a constraint on Phase 4, not a tuning knob (expected uniform-random-from-hand, got greedy-worst-card)

=== M8 CARD-12 drift: the config claims a deadline the report did not select (8.0 -> 5.0) ===
FAIL tests/engine/spec_lock.spec.luau::CARD-12 fallback: ...
     the report's Verdict does not name CardPool.AUTO_PASS_MAX_SECONDS as the selected deadline (expected "**Selected pool: k = 3 extra ranks, j = 1 joker(s), auto-pass deadline 8.0s.**" to contain "deadline 5.0s")

=== M9 CARD-12 drift, the other direction: a later sweep re-run selects a different pool and the REPORT says so, while CardPool still says k=3 ===
FAIL tests/engine/spec_lock.spec.luau::CARD-12 fallback: ...
     the report's Verdict does not select CardPool.EXTRA_RANKS = 3 (expected "**Selected pool: k = 5 extra ranks, j = 2 joker(s), auto-pass deadline 3.0s.**" to contain "k = 3 extra ranks")

=== M10 CARD-12 drift: the report comes back marginal ===
FAIL tests/engine/spec_lock.spec.luau::CARD-12 fallback: ...
     the shipped pool must be selected from a NON-marginal verdict (expected a truthy value, got false)

=== M11 the subset: the shipped config turns the valve off ===
FAIL tests/sim/subset.spec.luau::the shipped configuration IS the configuration the gate ran
     n=3 Wild: the gated valve position is not CardPool.ANTI_LIVELOCK_VALVE (expected false, got true)

=== M12 the subset: the shipped config changes the auto-pass selection rule ===
FAIL tests/sim/subset.spec.luau::the shipped configuration IS the configuration the gate ran
     an auto-pass that picks the player's own greedy card deviates by exactly zero, so the simulator's auto-pass numbers would transfer nothing to the shipped game (expected uniform-random-from-hand, got lowest-rank-group-first)

=== M13 the subset: the construction path stops reading CardPool (gatedOpts hardcodes k=2 and a 5.0s deadline) ===
FAIL tests/sim/subset.spec.luau::the shipped configuration IS the configuration the gate ran
     n=3 Wild: gated k is not CardPool.EXTRA_RANKS (expected 3, got 2)
```

**One mutation deliberately does NOT fail, and the spec says so.** Changing
`CardPool.EXTRA_RANKS` alone leaves the subset's shipped-configuration case GREEN, because the gated
cells are built from `CardPool` and therefore follow it (case 1's bars are then what judge the new
pool, and the spec-lock drift guard M9 is what catches the config disagreeing with the evidence). That
limitation is written into the case rather than left for a reader to discover, with M13 as the
regression it actually catches.

## `02-VALIDATION.md`: every documented filter, run

The five rows that named a `--filter` matching no spec file each exited **1** with
`FAIL filter <name> matched no cases: a typo must not look green` — documented commands that failed.
Reconciled toward the real filenames (the retired strings are recorded here rather than in the
document, so that grepping the document for a dead filter stays a usable guard):

| row | retired filter | now |
|---|---|---|
| CARD-03 | `engine/pass` | `--filter engine/ring` |
| CARD-07 | `engine/complete` | `--filter engine/apply` and `--filter engine/hand` |
| CARD-09 | `engine/deal` | `--filter engine/pool` (+ `engine/spec_lock` for the locked decision) |
| CARD-10 | `engine/joker` | `--filter engine/hand` (+ `engine/spec_lock`) |
| CARD-12 | `sim/blocker` | `--filter sim/subset` (+ `engine/spec_lock`) |

Every filter the document now names, run at this plan's HEAD:

| filter | exit | result |
|---|---|---|
| `engine` | 0 | 143 passed, 0 failed, 0 todo in 2.91s |
| `engine/apply` | 0 | 28 passed, 0 failed, 0 todo in 0.31s |
| `engine/hand` | 0 | 10 passed, 0 failed, 0 todo in 0.27s |
| `engine/pool` | 0 | 12 passed, 0 failed, 0 todo in 0.28s |
| `engine/removal` | 0 | 10 passed, 0 failed, 0 todo in 0.30s |
| `engine/ring` | 0 | 8 passed, 0 failed, 0 todo in 0.26s |
| `engine/seatorder` | 0 | 28 passed, 0 failed, 0 todo in 0.26s |
| `engine/spec_lock` | 0 | 3 passed, 0 failed, 0 todo in 0.38s |
| `engine/valve` | 0 | 11 passed, 0 failed, 0 todo in 0.37s |
| `purity` | 0 | 7 passed, 0 failed, 0 todo in 0.46s |
| `sim/subset` | 0 | 16 passed, 0 failed, 0 todo in 5.74s |
| `sim/sweep` | 0 | 12 passed, 0 failed, 0 todo in 2.35s |

Also in the document now: the four Wave 0 artefacts the original list never named
(`tests/engine/valve.spec.luau`, `tests/harness/Livelock.luau`, `tests/engine/apply.spec.luau`,
`tests/sim/sweep.spec.luau`), a requirements-map row for the valve itself (CARD-11) and one for Gate
G1's shipped configuration, the corrected satisfiability row (`Invariants.satisfiable(state) == false`
asserted directly, because `circulation` precedes it in the locked violation order — plus the measured
77%-of-churned-rounds effect size against research's 2.9–5.7% estimate), a row for the **five**
mechanism checks stating the standard as *a threshold OR a deterministic fixture proof, calibrated to
the round count it is applied at* with the note that CI satisfies three of the five by fixture, and the
seven simulator mutation proofs named alongside. Frontmatter is `status: complete`,
`nyquist_compliant: true`, `wave_0_complete: true`; Approval is dated 2026-11-04. The scope note about
the pacing half measuring the bot and the Manual-Only table are untouched — plan 02-14's report quotes
them verbatim.

## Verification

```
stylua --check src scripts tests                                   clean
selene src scripts tests                                           0 errors, 0 warnings
selene --config selene.pure.toml src/server/engine src/server/core src/shared/Net   0 errors, 0 warnings
lune run scripts/ci/analyze.luau ... (standard platform)            analyze: ok
lune run scripts/ci/check-guards.luau                               ok (85 files, 227 requires, 20 guarded roots)
grep -rq 'Config/CardPool' src/server/engine/                       exit 1 (the engine requires nothing from src/shared)
grep -rn 't\.todo(' tests/                                          nothing (no spec registers a todo)
lune run tests/run.luau -- --filter engine/spec_lock                3 passed, 0 failed, 0 todo in 0.38s
lune run tests/run.luau -- --filter sim/subset                      16 passed, 0 failed, 0 todo in 5.73-5.97s
lune run tests/run.luau                                             509 passed, 0 failed, 0 todo in 24.74s
lune run scripts/verify.luau                                        all 14 automated steps passed in 26.4s
git diff --stat .github/workflows/ci.yml scripts/verify.luau        empty (no CI step added)
```

The suite grew by 4 cases (505 -> 509) and 3 todos became 0: +1 in `sim/subset` (the
shipped-configuration case) and +3 real cases replacing the three todos in `spec_lock`.

## Deviations from Plan

### Auto-fixed

**1. [Rule 1 - Bug] The plan's draft `CardPool` header carried three figures the committed evidence
contradicts**

- **Found during:** Task 1, while filling in the template comment.
- **Issue:** The plan's draft text said (a) the claim is "zero observed stalls for this pool", (b)
  "at k=2,j=2 the valve-on stall rate measured 0.025%", and (c) auto-pass firing rates of "2.86% at
  1.0s, 0.21% at 1.5s, 0.019% at 2.0s". None survives the committed report: (a) the confirm stage
  observed **37** stalled rounds in 320,000 at the shipped pool, so "zero observed stalls" is false;
  (b) 0.025% is the A7-CORRECTION **prototype** figure, and amendment A8 plus the report both record
  that the prototype does not reproduce — "k=2,j=2 was its bad pool, and measured it is
  indistinguishable from k=2,j=1"; (c) those rates mix per-pass tail figures from A7 with per-action
  rates from the simulator.
- **Fix:** The header states the measured residual (0.012% aggregate, 0.070% worst cell against the
  0.500% ceiling), cites the shipped pool's own valve-OFF twins (3.58–8.31%) as the
  valve-is-load-bearing evidence instead of the prototype's k=2,j=2 number, and gives the auto-pass
  figures as the report's own counts by deadline (0 at 8.0s, 2 at 5.0s, 58 at 3.0s, 38,516 at 1.5s)
  plus the probe's 1.38% of actions at 1.0s.
- **Files modified:** `src/shared/Config/CardPool.luau`.
- **Commit:** `56ead34`.

**2. [Rule 3 - Blocking] The plan's "the provisional hardcoded k/j constants are gone" and "the
diagnostics stay exactly as written" cannot both be literally true**

- **Found during:** Task 1. Six diagnostic and mutation cells read `REFERENCE_K` / `REFERENCE_J`, and
  their sample sizes are calibrated against effect sizes measured at that pool (the sabotage cell's
  77% of churned rounds, the 0.216 bad-pool firing rate, the k=0,j=1 occupancy floor).
- **Fix:** The constants are renamed `DIAGNOSTIC_K` / `DIAGNOSTIC_J` / `DIAGNOSTIC_AUTO_PASS_SECONDS`
  with a header note explaining that only the GATED cells read `CardPool` and why re-pointing the
  diagnostics would invalidate their arithmetic. No provisional constant governs anything gated.
- **Commit:** `56ead34`.

**3. [Rule 1 - Bug] Two acceptance greps in the plan are structurally incapable of passing**

- `grep -rn 't.todo' tests/` "must return nothing" matches `table.insert(todos, name)` in
  `tests/harness/Test.luau` — the regex `t.todo` matches `t(todo` inside `insert(todos`. The harness
  cannot register todos without a `todos` table, so the check as written can never pass. The
  meaningful form is `grep -rn 't\.todo(' tests/`, which returns nothing (exit 1) and is what the
  Verification block above runs.
- `grep -c 't.todo' tests/engine/spec_lock.spec.luau` "returns 0" was failing on the file's own
  header prose describing what it used to hold. Rather than weaken the check, the header was reworded
  to avoid the literal string, and it now says WHY: the grep is the automated guard that the count
  stays at zero, so the string must not appear even in a comment. The grep returns 0.
- **Commit:** `07d8804`.

**4. [Rule 2 - Missing falsifiability statement] The subset's k/j/deadline equalities cannot fail on
a `CardPool` mutation, and the plan did not say so**

- **Found during:** Task 1 mutation testing. `EXTRA_RANKS = 3 -> 4` left the new case green, because
  the gated cells are built from `CardPool` and follow it. The plan presented the equality as "the
  gate cannot be green for a configuration that is not the one that ships", which is only true of the
  construction path, not of the config.
- **Fix:** The case documents exactly what each half can and cannot catch, names the drift the
  spec-lock CARD-12 case owns instead, and the construction-path mutation (M13) was run to prove the
  equality is not decorative. The valve and selection-rule assertions in the same case DO fail on a
  `CardPool` mutation (M11, M12).
- **Commit:** `56ead34`.

**5. [Rule 2 - Missing critical functionality] `02-VALIDATION.md`'s sign-off needed an honest
answer on feedback latency, not a tick**

- The checklist's "Feedback latency < 20s" box cannot be ticked for the full suite, which measures
  24.74–25.18s. It is ticked **for the per-task sampling loop** (`--filter engine` 2.91s, every
  single-spec filter under 0.5s) with the full-suite overshoot written out beside it and routed to the
  owner at plan 02-12's checkpoint, which is where 02-08 and 02-09 already sent it (deferred item
  D-02-09-3). A silent tick would have been the exact failure mode this document exists to prevent.
- **Commit:** `ce84f81`.

### Not fixed (out of scope, logged)

Nothing new. `deferred-items.md` is unchanged: D-02-09-3 (the suite is over CONTEXT's locked ~20s) is
now measured at 24.74s and still an owner decision at plan 02-12's checkpoint, and D-02-09-4 (the
locked zero-stall and 1% firing-rate bars are unmet at every pool) is **resolved by the committed
report rather than by this plan** — amendment A8 re-derived both bars, `Simulator.evaluateBars` is
still untouched, and the subset still asserts that the N=10 firing rate EXCEEDS `VALVE_RATE_MAX` so
the exemption stays earned and self-deleting.

## What plan 02-12 must honour

- **The six values above, verbatim.** They go into CARD-16's requirement line, ROADMAP's Phase 4 note
  and PROJECT.md's Key Decisions table. `AUTO_PASS_SELECTION = "uniform-random-from-hand"` is the one
  most easily lost, and it is the one whose loss silently invalidates the simulator's transfer.
- **Record k=3 as a gameplay decision taken from the bar-sensitivity ladder**, not as a measurement.
  The report's ladder is in section 4b; the bar was set to the chosen operating point and the sweep
  re-run, so the shipped pool is also the confirmed one.
- **The three departures in `selection.departures`** (the `j >= 1` floor against CONTEXT's literal
  "fewest jokers" tiebreak; A8's replacement of the zero-stall bar and the 1% firing-rate bar; the
  pool-level margin correction) are in `02-sweep-data.json` and report section 9.
- **`ValveForcedPass` is an ordinary, visible event for Phase 4.** At the shipped pool it fires in
  3.59–8.24% of rounds at a full roster — roughly one round in fifteen — so it needs a real affordance,
  not an edge-case path.
- **CARD-09/10/11/12 are implemented and tested but NOT marked complete in `REQUIREMENTS.md`.** This
  plan deliberately did not touch that file: the orchestrator reserved the planning documents for 02-12.
- **`02-G1-REPORT.md` section 4b still reads `TRIAGE PENDING`.** Plan 02-10 task 4 says to replace it
  with the statement that there was nothing to triage when the confirm stage yields no action-cap
  seeds — and it yielded none (`hitActionCap = 0` in every confirm row, `valveSeenResetsTotal = 0`).
  That edit belongs to whoever owns the report; `spec_lock`'s drift guard reads only the Verdict
  section, so it does not block.

## Known Stubs

None. No file this plan touched contains a placeholder, a hardcoded empty collection or a TODO.

## Self-Check: PASSED

```
FOUND: src/shared/Config/CardPool.luau
FOUND: tests/engine/spec_lock.spec.luau
FOUND: tests/sim/subset.spec.luau
FOUND: .planning/phases/02-card-engine-and-pacing-simulator/02-VALIDATION.md
FOUND commit 56ead34 (task 1), 07d8804 (task 2), ce84f81 (task 3)
```

No commit deleted a tracked file (`git diff --diff-filter=D` is empty for all three). The full suite,
`scripts/verify.luau` and every documented `--filter` were re-run green at this SUMMARY's HEAD, and
`git status --short` is clean apart from this file. Every mutation applied during this plan was
reverted and the tree verified clean before each commit.
