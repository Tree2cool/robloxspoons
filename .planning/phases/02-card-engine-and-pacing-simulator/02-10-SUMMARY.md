---
phase: 02-card-engine-and-pacing-simulator
plan: 10
subsystem: testing
tags: [sweep, gate-g1, cli, pool-selection, anti-livelock-valve, auto-pass, triage, mutation-proof, smoke-test]

requires:
  - phase: 02-09
    provides: "Simulator.runRound / runCell / evaluateBars / evaluateMechanisms, the CellResult and MechanismEvidence shapes, the CellRole vocabulary, and the MEASURED rates (valve-off 10.6%, valve-ON residual 0.05-0.10%, firing rate 8-29%) this plan's bars are re-derived from"
  - phase: 02-04
    provides: "Pool.poolConfig - the ONE site that owns amendment A3's seatCount = n - 1; the sweep builds every config through it"
  - phase: 02-13
    provides: "the valve itself, whose firing rate is the sweep's most sensitive pool discriminator"
  - phase: 01-02
    provides: "tests/run.luau's tests/**/*.spec.luau discovery, which is why no CI step was added"
provides:
  - "scripts/sim/sweep.luau - the five-stage G1 sweep CLI (search / mechanism / confirm / triage / both), the six-step selection rule with margin and a descending fallback, both artefacts rendered from ONE in-memory table, and evaluateMechanisms ANDed into the exit code"
  - "tests/sim/sweep.spec.luau - 12 cases driving the REAL CLI in 2.24-2.40s, 13 of 13 mutations caught"
  - "The A8-derived selection bars: a 0.5% residual stall ceiling and a 7% valve firing-rate bar, each pinned by TWO measured bounds written next to the constant"
  - "A measured dress rehearsal of the whole pipeline at 300 rounds/cell: 1,132 cells, 339,600 rounds, 306.4s, exit 0, selecting k=6 j=1 at an 8.0s deadline with margin and ZERO stalls in 9,600 gated rounds"
  - "A measured budget for plan 02-14's real run: ~29 minutes (search 14.9 + mechanism 4.6 + confirm 9.7)"
affects: [02-11, 02-12, 02-14, 04]

tech-stack:
  added: []
  patterns:
    - "A tool plan, a run plan and a decision plan kept separate: this plan builds and smoke-tests the CLI, 02-14 produces the data, 02-11 decides. A broken tool now fails in 2.4 seconds instead of after half an hour"
    - "A bar re-derived from measurement is written as the two MEASURED BOUNDS that pin it, not as a round number. The lower bound is what makes the margin rule satisfiable at all; the upper bound is what keeps the bar discriminating. The interval is in the source next to the constant"
    - "The locked checker is called ALONGSIDE the re-derived one and its verdict rides on every cell (lockedVerdict / lockedFailures), so re-deriving a bar changes what the sweep SELECTS without hiding what the locked constants would have said"
    - "A sub-stage names the bars it fails BY CONSTRUCTION, in its own banner and its own help text, so a non-zero exit from a diagnostic run is never mistaken for a regression and never 'fixed' by weakening a bar"
    - "Every guard case in a CLI spec is bounded (`--rounds 1`), because a mutation that removes a guard falls through to the CLI's DEFAULT behaviour - which for a sweep is a half-hour run inside a two-second spec"
    - "An invariant assertion rather than a type assertion where the field has an initialiser: `verdict == (#failures == 0)` catches a dropped record, `typeof(verdict) == 'boolean'` cannot"

key-files:
  created:
    - scripts/sim/sweep.luau
    - tests/sim/sweep.spec.luau
  modified: []

key-decisions:
  - "VALVE_RATE_MAX_SWEEP = 0.07, pinned by two measured bounds rather than chosen. LOWER 0.060: the smallest worst-case firing rate anywhere in the searched grid is k=6 at 0.030, and 'pass with margin' is half the bar, so any bar below 0.060 makes the margin rule structurally incapable of being satisfied by a pool the sweep searches. UPPER 0.076: the quietest pool in amendment A4's original k in {1,2} grid is k=2,j=2 Wild at 0.076, and the bar must stay below it or the firing rate stops discriminating. 0.07 is the round value inside [0.060, 0.076)"
  - "STALL_RATE_MAX = 0.005 (A8 resolution 2). Five times the measured valve-ON residual (0.05-0.10% at N>=9 per 02-09; 0.010% measured here at k=6 over 10,000 rounds) and twenty times below the 10.6% a valve regression produces. The MEASURED residual is printed in the report's section 1 rather than rounded away"
  - "MARGIN IS APPLIED AT THE POOL LEVEL, not only to the auto-pass walk. The plan's rule picks the 'smallest pool that passes' and then demands margin only on the deadline. On the measured curve successive k differ by a factor of 1.6-1.9, so the smallest pool that PASSES a bar always sits within a factor of two of it - which is exactly the margin threshold. Written as planned the rule reports marginal = true on every run at every bar value, and the flag carries no information. The fix is the plan's own margin-and-fallback doctrine extended one axis"
  - "The firing-rate tie-break sorts LAST, after the deadline, and is recorded as UNREACHABLE. Sorted before the deadline it overrides step 6's descending walk with measurement noise - observed selecting a 3.0s deadline over 8.0s at two rounds per cell. Sorted last it is inert, because (k, j, deadline) names exactly one candidate in this grid. It is kept so a future grid with two cells per candidate breaks the tie by measurement, and it is reported as dead rather than presented as a rule that fires"
  - "Search cells carry role = 'diagnostic', not 'gated'. The search is a search, not a gate (the plan says so itself), and admitting 1,080 search cells as gated would make `valve-twin-missing` a claim about every pool searched rather than about the pool that ships - and a single thin-pool search cell carries enough firings to satisfy `valve-never-fired` on its own (02-09's warning)"
  - "k = {0,1,2,3,4,6} and not {0,1,2,3,4,6,8}. A8 measured k=8 at 1.75% against k=6's 1.00%, non-monotone and inside the noise of a 400-round cell, so k=8 buys no information for a sixth more search cost. k=0 is kept because amendment A5 requires the dead pool to be REPORTED, not skipped"
  - "`--n` was added as a triage-only flag. A triage row has to name the roster size the seed came from (the JSON row shape the plan specifies carries `n`), and the plan's flag list gives triage no way to say it. All three triage-only flags (`--seeds`, `--cap`, `--n`) are REFUSED outside triage rather than ignored: a silently ignored flag is the same defect as a misspelled one"
  - "The search stage runs at `--rounds 1` in the spec, not 3. A8's grid extension doubled the search to 1,080 cells; at three rounds the one search invocation costs ~2.6s and the spec misses its budget, while every assertion in cases 1-4d is about the SHAPE of the output and none is about a rate"
  - "A failing run reports BOTH problem classes, not the first. A dead pool forced with `--pool` fails the bars AND the mechanism checks, and a run that printed only the mechanism line would hide the reason the configuration cannot be selected behind a sub-stage scoping failure"

patterns-established:
  - "Thirteen plan assertions in this phase have now been found structurally incapable of failing or of passing. This plan found three more and fixed all three: the pool-level margin rule (incapable of passing), the firing-rate tie-break (incapable of firing), and the `greedy` grep (incapable of passing against a report the spec requires to contain 'pure greedy'). A fourth was found by mutation testing in the spec itself and fixed before commit"
  - "A dress rehearsal at a reduced round count as the validation of a long-running tool: 306 seconds proved the selection path end-to-end, produced the budget for the real run, and predicted its outcome - without producing a verdict at the locked round count, which is plan 02-14's job"

requirements-completed: [CARD-11, CARD-12]
requirements-contributed: []

duration: ~95 min
completed: 2026-11-04
---

# Phase 2 Plan 10: The Full Sweep CLI Summary

**A five-stage sweep CLI whose selection bars are re-derived from the measured engine rather than from a prototype that does not reproduce, smoke-tested against the real binary in 2.4 seconds with 13 of 13 mutations caught, and dress-rehearsed end to end at 300 rounds per cell: 1,132 cells, 339,600 rounds, 306 seconds, exit 0, selecting k=6 j=1 at an 8.0s deadline WITH MARGIN and zero stalls in 9,600 gated rounds. Plan 02-14's real run is budgeted at ~29 minutes.**

## Performance

- **Duration:** ~95 min (2026-11-04)
- **Tasks:** 3 (task 1 a checkpoint, answered by 02-CONTEXT amendment A8 before any sweep cell ran)
- **Files created:** 2 (`sweep.luau` 1,782 lines, `sweep.spec.luau` 402 lines)
- **Cases added:** 12; suite **505 passed, 0 failed, 3 todo in 25.99s** (baseline 493 / 23.4-24.5s)
- **`--filter sim/sweep`:** `12 passed, 0 failed, 0 todo in **2.24-2.40s**`
- **`scripts/verify.luau`:** `all 14 automated steps passed in 27.0-27.4s` (was 26.1s)

## Task 1 — the owner's answers, verbatim

Both questions were answered **before any sweep cell ran**. The answers are 02-CONTEXT.md
amendment **A8** (2026-11-03, "measured + owner"), reproduced verbatim:

> **1. (owner) The valve firing-rate bar is re-derived from the measured curve**, not from the
> prototype's 0.25%. No pool clears the proposed ~1% — the bar is set where the measured curve
> actually separates good pools from bad, preserving the signal that exposed k=2 j=2 as a bad pool
> when stall rate alone could not.
>
> **2. (owner) G1's zero-stall bar becomes an explicit residual ceiling**, around 0.5% — well above
> the measured 0.05–0.10% valve-ON residual and far below the ~10% a valve regression produces —
> with the actual measured residual printed in the G1 report rather than rounded away.
>
> **3. (derived from data, not asked) The search grid extends past k=2.** […] `k` now searches at
> least {1,2,3,4,6}; A4's `k >= 1` floor still holds. This is a search-range correction, not a
> design decision.

And, carried in the same amendment and in the plan's recommended options:

> **Q1 (the joker floor):** `j` searches `{1,2}` per the PROJECT.md Key Decision, with `j = 0`
> measured and reported as a comparison.
>
> **Q2 (the AFK deadline):** search `{1.5, 3.0, 5.0, 8.0, infinity}` and default to the largest
> that clears with margin.

**Not changed, and not changed to make a bar pass:** the 500-round statistical floor, any mutation
case, `VALVE_ARM_ACTIONS_PER_SEAT`, or the pool moving to a green-but-unshippable k.

### `AUTO_PASS_CANDIDATES`, final

```luau
local AUTO_PASS_CANDIDATES = { 1.5, 3.0, 5.0, 8.0, math.huge }
local PROBE_DEADLINE = 1.0
```

`math.huge` is swept as the pure-greedy comparison the report must show and is **never selectable** —
a product cannot ship "no AFK deadline", so the walk considers finite candidates only and the
`auto-pass-disabled` rejection reason is emitted for every infinite candidate.

## The bars, and the measurement each was derived from

`Simulator.evaluateBars` is **UNCHANGED**. It is still called for every Pacing cell and its verdict
rides on every cell in `02-sweep-data.json` as `lockedVerdict` / `lockedFailures`, so the
locked-constant view is in the artefact and nothing is hidden. The **selection** bars are A8's:

| bar | locked constant | SWEEP bar | with margin | derived from |
|---|---|---|---|---|
| stalls | `stallRate > 0` | `<= 0.005` | `<= 0.0025` | 5x the measured valve-ON residual (0.05-0.10% at N>=9, 02-09; **0.010%** measured here at k=6 over 10,000 rounds) and 20x below the 10.6% a valve regression gives |
| cleared fraction | `Cleared < eligible` | `< 1 - 0.005` | `< 1 - 0.0025` | the stalls bar from the other side, same ceiling |
| median first | `> 45s` | `> 45s` (unchanged) | `> 36s` | 02-CONTEXT A2 |
| p95 first | `> 120s` | `> 120s` (unchanged) | `> 96s` | 02-CONTEXT A2 |
| occupancy | `< 0.60` | `< 0.60` (unchanged) | `< 0.66` | A2 / research 3.7 |
| valve rate | `> 0.01` | `> 0.07` | `> 0.035` | **two measured bounds, below** |

### The measured curve the firing-rate bar is pinned by

N=10, Pacing, churn=false, valve ON, **1,000 rounds per cell**, measured for this plan.
`valveFiringRate` is the fraction of rounds the engine had to rescue; it equals the valve-OFF stall
rate to three decimals at every pool measured, so every firing is a real rescue.

| k | j=1 Wild | j=1 Blocker | j=2 Wild | j=2 Blocker | occupancy | medianFirst (Blocker) |
|---|---|---|---|---|---|---|
| 1 | 0.266 | 0.356 | 0.210 | 0.340 | 0.63 | 15.4s |
| 2 | 0.107 | 0.150 | 0.076 | 0.154 | 0.79 | 14.2s |
| 3 | 0.068 | 0.091 | 0.043 | 0.080 | 0.83 | 16.0s |
| 4 | 0.033 | 0.048 | 0.021 | 0.036 | 0.84 | 17.8s |
| 6 | 0.026 | 0.028 | 0.011 | 0.030 | 0.86 | 21.2s |

The curve is smooth, monotone in k, and **has no elbow**, so the bar is a judgement. It is therefore
written in the source as the two **measured bounds** that pin it rather than as a round number:

- **LOWER BOUND 0.060.** The smallest worst-case rate anywhere in the searched grid is **k=6 at
  0.030** (worst over both joker modes and j in {1,2}). Margin is half the bar, so a bar below
  `2 x 0.030 = 0.060` makes the margin rule **structurally incapable of being satisfied by any pool
  the sweep searches**.
- **UPPER BOUND 0.076.** The quietest pool in amendment A4's original `k in {1,2}` grid is
  **k=2,j=2 Wild at 0.076**. The bar must stay below it, or a pool the engine rescues in one round
  in thirteen passes and the firing rate stops discriminating — which is the whole reason A7 made it
  a first-class metric.

`VALVE_RATE_MAX_SWEEP = 0.07` is the round value inside `[0.060, 0.076)`. **It is not a design
target.** That no pool in the searched grid gets the rescue rate below ~2% is itself the finding, and
the report prints a **bar-sensitivity ladder** — the pool every candidate bar from 40% down to 1%
would have selected — so plan 02-11 can audit the choice against the alternative it rejects.

### A second prototype claim that does not reproduce

A7-CORRECTION's discriminator story was "k=2,j=2 is a bad pool the stall rate cannot see". Measured
on the real engine, **k=2,j=2 is indistinguishable from k=2,j=1** (0.076/0.154 against 0.107/0.150 —
j=2 is marginally *better* at Wild, because it adds circulation). What the measured curve actually
separates is **k**, not j. The firing-rate bar still earns its place: it is the only bar that
rejects `k <= 2` at all, since every `k >= 1, j >= 1` pool clears the stall, pacing and occupancy
bars outright. That is stated in the report's section 4.

## The search grid

| axis | values | count |
|---|---|---|
| `k` | 0, 1, 2, 3, 4, 6 | 6 |
| `j` | 0, 1, 2 | 3 |
| auto-pass deadline | 1.5, 3.0, 5.0, 8.0, `math.huge` | 5 |
| `N` | 3, 6, 10 | 3 |
| `jokerMode` | Wild, Blocker | 2 |
| `churn` | false, true | 2 |
| **search cells** | | **1,080** |

Plus **15 valve-disabled twins** (every `k >= 1` pool, N=10, Wild, Solvability, `math.huge`) and
**1 auto-pass probe** (1.0s, N=10, k=2 j=1 Wild, Pacing) in the mechanism stage, and **32 gated
cells** (N=3..10 x 2 joker modes x 2 churn) plus **4 valve-disabled twins** at N=10 in the confirm
stage. A `--stage both` run is **1,132 cells**.

Round counts: `search = 1000`, `mechanism = 4000` (twins), `probe = 1000`, `confirm = 10000`.
`meta.roundsPerCell` is a **MAP KEYED BY STAGE**, because one `both` run uses four different round
counts and one in-memory table can only be written once; every cell also carries its own `rounds`,
which is the authority.

## The selection rule as implemented

1. `k >= 1` (amendment A4: at k=0 the Blocker variant is a cliff, not a flag — measured here,
   `k=0,j=1` Blocker stalls **100.0%** against Wild's 14.7%).
2. `j >= 1` (PROJECT.md's Key Decisions: jokers exist; the sweep **clears** j, it does not minimise
   it). `j = 0` is measured and reported in section 6 as the comparison CONTEXT's literal tiebreak
   would have selected.
3. Every bar passes in **both** joker modes and **both** churn variants, at every N searched.
4. Reject any pool whose `valveFiringRate` exceeds 0.07.
5. Smallest passing pool: fewest extra ranks `k` first, then fewest jokers `j`; ties on the lower
   worst-case valve firing rate.
6. Auto-pass deadline: the largest **finite** candidate that clears, **with margin** where any pool
   can; otherwise descend the same list accepting a bare pass, set `selection.marginal = true` and
   name the bars it only barely cleared. If nothing clears even bare, exit non-zero.

**Margin is applied at the pool level too, and that is a correction to the plan.** See the deviations
below: as written, the rule reports `marginal = true` on every run at every bar value, by
construction.

Every candidate considered — all 90 `(k, j, deadline)` groups, including the ones the `k` and `j`
floors reject — is emitted into both artefacts with its named bar failures, its margin shortfalls
and its `rejectedBy` reason (`k-floor`, `j-floor`, `auto-pass-disabled`, `bars`). A selection rule
whose rejections are invisible cannot be audited (threat T-2-49).

## The report's sections, in order

1. **Verdict** — selected k / j / joker-mode flag / deadline, the five bars' measured values against
   bar and margin, the `marginal` flag, and the honest one-liner: *zero observed stalls for the
   selected pool at the confirmed round count*, with the measured residual printed.
2. **The five bars** — each threshold with the measurement it comes from.
3. **Confirmation stage** — one row per (N, mode, churn): stall, median/p95 first, median/p95 all,
   occupancy, ramp, auto-pass rate, deal-attempt mean/max, all six outcome counts, the sweep bars'
   verdict and the **locked** bars' verdict side by side.
4. **Known worst case: pure greedy with the valve disabled** — every valve-off cell, plus the
   comparison to A7-CORRECTION's prototype table and A8's traced cause.
   **4b. The valve** — firing rate, firings/round, armed rate, **`seenResets`** and action-cap hits
   per cell; the bar-sensitivity ladder; and `### Triage`, which reads `02-triage.json` **if it
   exists** and otherwise emits the single line `TRIAGE PENDING — run --stage triage and fold the
   rows in here`.
5. **Stall rate versus auto-pass timeout** — the curve over every candidate, plus the probe's
   measured rate at 1.0s, labelled as margin evidence.
6. **Documented negative results** — the k=0 cells, the wild/blocker cliff, the `k=0,j=0` DeadPool
   rows and the `j=0` comparison.
7. **Occupancy** — the table justifying A2's third bar, with the dead-table cell next to the
   selection.
8. **Carried debt** — V-35 and the deviation row **verbatim** from `02-VALIDATION.md`, its scope
   note verbatim, and the line recording that A7 retired the old load-bearing assumption.
9. **Reproduction** — the exact command, the base seed and its per-cell blocking, the stages, the
   caps, the Lune version; then the selection rule as implemented, the recorded departures, and the
   full candidate table.

## Stage scoping: `both` is the only verdict-producing invocation

| invocation | exit | why |
|---|---|---|
| `--stage both` | 0 on a pass | the only run that emits every kind of cell `evaluateMechanisms` reads, so all five mechanism bars are both satisfiable AND meaningful |
| `--stage search` | 0 | prints `SEARCH ONLY - NOT A VERDICT`, writes **no** `selection` block, and the mechanism checks are **NOT EVALUATED** (the grid has no twin and no probe by construction) |
| `--stage mechanism` | **1** | `SUB-STAGE`. Fails **`valve-twin-missing`** and **`valve-not-load-bearing`** by construction: it emits no gated cell, so the twin match is empty and both bars fire |
| `--stage confirm` | **1** | `SUB-STAGE`. Fails **`autopass-probe-missing`** by construction: the probe is the mechanism stage's output |
| `--stage triage` | 0 | writes **ONLY** `02-triage.json` |

**Plan 02-14 must not "fix" a sub-stage failure** by weakening a bar or by skipping it when its
evidence is absent. The absent evidence IS the failure; a run that wants a clean exit is a `both`
run.

**A correction to the plan's own sub-stage table:** it predicts a bare `mechanism` run also fails
`valve-never-fired`, on the reasoning that the probe's ~5 expected firings fall below
`VALVE_MIN_FIRINGS = 20`. That arithmetic used the prototype's 0.005 firings/round. Measured, the
1,000-round probe at k=2,j=1 carries ~**145** firings, so at the real round count
`valve-never-fired` does **not** fire — only the two twin bars do. (At the spec's 3 rounds all three
fire, which is why the spec asserts the two that are deterministic at any round count.)

## `--stage triage` writes only `02-triage.json`

The triage branch **returns before any other write exists in the process**; there is no code path
from it to `02-G1-REPORT.md` or `02-sweep-data.json`. Smoke-test case 4c hashes both files, runs
triage, and asserts they are **byte-identical** afterwards. Mutation M5 made triage render them and
the case failed, so the guarantee is proven rather than asserted. Every spec invocation passes
`--out build/sweep-spec*`, and `run()` **errors** if an argument list omits `--out` — so no case can
write into `.planning/`, where plan 02-14 commits the real verdict.

Row shape: `{ seed, k, j, jokerMode, n, classification, outcome, violation, valveSeenResets,
actions, cap }`. `classification` is exactly `"CapArtifact"` or `"ResidualLivelock"`. `outcome` and
`violation` ride alongside because **a round that ended on the 300s TIME cap cannot be rescued by a
raised ACTION cap**, and a reader has to be able to see that from the row.

## This script is the only place three statistics are measured

Plan 02-09's CI subset carries a **deterministic fixture proof** through `MechanismEvidence` and
therefore no longer measures any of these. The sweep passes **both evidence booleans false** and is
held to the statistical thresholds its own round count calibrates:

1. **The valve-off twin stall RATE** — `--stage mechanism`, 15 pools x 4,000 rounds. Measured in the
   rehearsal at 300 rounds: **1.00% to 37.33%** across the 15 twins, every one of them far above
   `VALVE_PROOF_MIN_STALL_RATE = 0.0005`.
2. **A thin pool's firing rate** (the role the prototype's k=2,j=2 played) — `--stage search`.
3. **The firing COUNT behind `VALVE_MIN_FIRINGS = 20`** — the search grid. 1,080,000 search rounds at
   the measured rates expect tens of thousands of firings.

If the mechanism stage is cut or shortened, the RATE behind "the valve is load-bearing" has no
measurement anywhere in the phase — only the fact that one specific trajectory does not escape.

## The dress rehearsal — the whole pipeline, measured

`--stage both --rounds 300 --out build/sweep-rehearsal` (a reduced round count, in a gitignored
directory, producing **no verdict at the locked count** — that is plan 02-14's job):

```
sweep: 1132 cells, 339600 rounds, 306.4s -> build/sweep-rehearsal/...
-- selection: k=6 j=1 ap=8 marginal=false
-- mechanism checks: pass
EXIT=0
```

| | measured |
|---|---|
| selected | **k=6, j=1, 8.0s deadline, `marginal = false`** |
| gated cells | 32, **zero stalls in 9,600 rounds** |
| worst gated valve firing rate | **0.0267** (N=9 Blocker, churn=false) against bar 0.07 and margin 0.035 |
| worst gated medianFirst / p95First | 20.6s / 32.4s against 45s / 120s |
| minimum gated occupancy | 0.856 against 0.60 |
| `valveSeenResetsTotal` across all gated cells | **0** — the valve was never blind |
| action-cap rounds across all gated cells | **0** — every stall this engine produces is a 300s `time-cap` round |
| mechanism twins | stall 1.00%-37.33%, all load-bearing |
| auto-pass probe at 1.0s | `autoPassRate = 0.01407` over 93,598 actions, against the 0.005 bar |

A separate 10,000-round confirm-shaped cell at k=6 j=1 Wild N=10 measured
**`stallRate = 0.00010`** (one round in ten thousand), `valveFiringRate = 0.0182`, occupancy 0.856,
medianFirst 17.5s, p95 28.5s, `seenResets = 0`, `capArtifactCandidates = 0`, in 19.0s. That 0.010%
is the residual the 0.5% ceiling is set five hundred times above and that the report prints.

### Budget for plan 02-14's real run

Scaled from the rehearsal's measured per-stage cost:

| stage | rehearsal (300 rounds) | real round count | projected |
|---|---|---|---|
| search, 1,080 cells | 267.8s | 1,000 | **14.9 min** |
| mechanism, 15 twins | 20.5s | 4,000 | **4.6 min** |
| mechanism, 1 probe | 0.4s | 1,000 | 1.3s |
| confirm, 36 cells | 17.4s | 10,000 | **9.7 min** |
| **total** | **306.4s** | | **~29 min** |

Inside the plan's 20-to-40-minute band. Note that research 11.1's and 02-09's **1,646 rounds/s does
not apply to this grid**: that figure averages N=3..10, and this sweep is dominated by N=10, where
the measured throughput is **600-700 rounds/s** (N=6 ~2,000/s, N=3 ~10,000/s). The thin-pool cells
are the slowest of all — `k=0, j=2` Blocker at N=10 costs 9.7s per 1,000 rounds.

## Deviations from Plan

### Auto-fixed and corrected

**1. [Rule 1 - Bug] The pool-level margin rule as planned is structurally incapable of producing a non-marginal selection**
- **Found during:** Task 2
- **Issue:** The plan applies margin only to the auto-pass walk and picks the pool by "smallest that
  passes". On the measured curve successive `k` differ by a factor of **1.6 to 1.9**, so the smallest
  pool that passes a bar always sits within a factor of two of it — which is exactly the margin
  threshold (half the bar). At **every** bar value, the selected pool fails margin and the run
  reports `marginal = true`, so the flag carries no information and the "defined descending
  fallback" is the only path the rule ever takes.
- **Fix:** Margin is applied at the pool level as well: the walk looks for the smallest pool that
  clears **with margin**, and only then descends to a bare pass with `marginal = true` and the bars
  named. This is the plan's own doctrine extended one axis; the fallback and the flag are unchanged,
  and both passes emit their rejections. Verified end to end: the rehearsal selects k=6 j=1 with
  `marginal = false`, and the k=4 rows in its candidate table show `pass=true, margin=false` — the
  exact state the planned rule would have shipped as the selection.
- **Files modified:** `scripts/sim/sweep.luau`
- **Commit:** `f03629f`

**2. [Rule 1 - Bug] The firing-rate tie-break, sorted where the plan puts it, overrides the auto-pass walk with noise**
- **Found during:** Task 2
- **Issue:** The plan's step 5 ends "tie-break between otherwise equal candidates on the lower valve
  firing rate" and step 6 walks the deadlines downward. Implemented in that order the firing-rate key
  sorts **before** the deadline, so it reorders the deadline walk by measurement noise. Observed: at
  two rounds per cell it selected a **3.0s** deadline over 8.0s purely because that cell's firing
  rate happened to be lower. That is not a tie-break, it is the walk being overridden.
- **Fix:** The key sorts last, after the deadline. It is then **inert** in this grid, because
  `(k, j, deadline)` names exactly one candidate — so no two candidates are ever equal on the first
  three keys and the tie-break can never fire. It is kept, with the reason written next to it, so a
  future grid carrying two cells per candidate breaks the tie by measurement rather than by table
  order; and it is **recorded as unreachable** rather than presented as a rule that fires.
- **Files modified:** `scripts/sim/sweep.luau`
- **Commit:** `f03629f`

**3. [Rule 2 - Missing critical functionality] A failing run reported only one of its two problem classes**
- **Found during:** Task 2
- **Issue:** The first implementation exited on the mechanism failure before reporting the gated bar
  failure. A dead pool forced with `--pool 0,0,...` therefore printed only
  `mechanism checks: valve-never-fired,...` — a sub-stage scoping failure — and said nothing about
  the configuration being unselectable, which is the thing smoke-test case 7 exists to prove.
- **Fix:** Both classes are collected and reported: `the confirmation stage found no passing
  configuration (bars: no-completions); mechanism checks: ...`. Mutation M12 suppressed the gated
  half and case 7 failed.
- **Files modified:** `scripts/sim/sweep.luau`
- **Commit:** `f03629f`

**4. [Rule 2 - Missing critical functionality] `--n` was added, and all three triage-only flags are refused outside triage**
- **Found during:** Task 2
- **Issue:** A triage row must name the roster size the seed came from — the plan specifies `n` in
  the row shape — and the plan's flag list gives triage no way to say it. Separately, `--seeds`,
  `--cap` and `--n` are meaningless outside triage, and a flag that is silently ignored is the same
  defect as a flag that is misspelled: the run does something other than what was asked and exits 0.
- **Fix:** `--n` added (triage only, default 10, which is where 02-09 measured the residual). All
  three are a loud `fail()` outside triage. Smoke-test case 8 asserts it; mutation M9 removed the
  guard and the case failed.
- **Files modified:** `scripts/sim/sweep.luau`, `tests/sim/sweep.spec.luau`
- **Commit:** `f03629f`, `f9db151`

**5. [Rule 1 - Bug] The progress line's cell index was global, not per stage**
- **Found during:** Task 2
- **Issue:** A `both` run printed `[confirm 1130/36]` — the global cell counter against the stage's
  own total. For a run whose entire purpose is to be visibly alive for half an hour (threat T-2-50),
  a progress line that reads 1130/36 is worse than none.
- **Fix:** A per-stage counter reset at each stage entry.
- **Files modified:** `scripts/sim/sweep.luau`
- **Commit:** `f03629f`

**6. [Rule 1 - Bug, in the spec] Case 2's locked-bar assertion could not detect a dropped record**
- **Found during:** Task 3, by mutation testing
- **Issue:** The case asserted `typeof(cell.lockedVerdict) == "boolean"` and
  `typeof(cell.lockedFailures) == "table"`. Both fields are **initialised** (`false` and `{}`) before
  the bars run, so mutation M11 — dropping the two assignments entirely — left a boolean and a table
  in place and **every case still passed**. A type assertion on a field with an initialiser cannot
  detect its absence.
- **Fix:** Assert the **invariant** instead: `lockedVerdict == (#lockedFailures == 0)`, so a false
  verdict must name its reasons and a dropped record is a false verdict with no reasons; at least one
  cell must carry a locked failure; and every sweep failure must also appear in the locked list,
  because every locked threshold is at least as strict as the A8 bar it was re-derived into. M11 now
  fails, and a new mutation M13 (a sweep bar made stricter than its locked counterpart) fails too.
- **Files modified:** `tests/sim/sweep.spec.luau`
- **Commit:** `f9db151`

**7. [Rule 3 - Blocking, in the spec] An unbounded guard case turned a mutation proof into a half-hour run**
- **Found during:** Task 3, by mutation testing
- **Issue:** Case 6 ran `{ "--no-such-flag", "--out", SCRATCH }`. Mutation M8 made an unknown
  argument **ignored**, so the run fell through to the CLI's default — `--stage both` at the default
  round counts — and a 29-minute sweep started inside a two-second spec. It had to be killed after
  eleven minutes of CPU.
- **Fix:** Every guard case is bounded: `--stage search --rounds 1` is passed even though the run
  must die before it reaches a cell. A guard's mutation proof has to fail fast, not run the whole
  sweep. M8 was also re-expressed as "exit 0 on an unknown argument" so the proof is about the exit
  code rather than about reachability.
- **Files modified:** `tests/sim/sweep.spec.luau`
- **Commit:** `f9db151`

### Plan acceptance criteria that cannot hold as written

**`grep -qE 'lognormal|Box|greedy' scripts/sim/sweep.luau` must FAIL.** It **succeeds**, and it
always would have, because the plan requires the report's section 4 to be headed *"Known worst case:
**pure greedy** with the valve disabled"* and requires smoke-test case 4 to assert the report
contains the string `"pure greedy"`. The two criteria are mutually contradictory; satisfying the grep
would mean assembling the word at runtime to defeat a grep, which is obfuscation, not evidence.

The criterion's **intent** — no simulation logic duplicated — is met and asserted the meaningful way:

```
grep -nE 'lognormal|Box|Bots' scripts/sim/sweep.luau   ->   no match (verified)
```

There is no bot policy, no reaction-time model and no card rule in the file. Every number comes from
`Simulator.runCell` / `runRound` and every mechanism verdict from `Simulator.evaluateMechanisms`.

**`--filter sim/sweep` … in under 3s with at least 11 passing cases.** Met — 12 cases in
**2.24-2.40s** — but only because the search invocation runs at `--rounds 1` and is memoised at spec
scope. At the plan's three rounds per cell, with A8's grid at twice the planned size, one search
invocation alone is ~2.6s. The round count is recorded as a decision above rather than left implicit.

## Mutation proofs — verbatim

Thirteen mutations, each applied to a clean tree, `--filter sim/sweep` run, then reverted. **All
thirteen are caught**, each by the case that exists for it.

```
=== M1 shrink the search grid (drop k=6)                                exit=1
   FAIL the search stage runs and writes both outputs
       the search grid's cell count (expected 1080, got 900)
   11 passed, 1 failed, 0 todo in 2.08s

=== M2 silently skip the dead pool                                      exit=1
   FAIL the search stage runs and writes both outputs
       the search grid's cell count (expected 1080, got 1020)
   FAIL the dead pool is a reported cell, not a skipped one
       every k=0,j=0 cell of the grid is present (expected 60, got 0)
   10 passed, 2 failed, 0 todo in 2.33s

=== M3 mislabel the auto-pass probe as a mechanism cell                 exit=1
   FAIL the mechanism stage emits valve-disabled twins and the auto-pass probe, under their own roles
       exactly one cell carries role=autopass-probe at the 1.0s deadline (expected 1, got 0)
   11 passed, 1 failed, 0 todo in 2.42s

=== M4 print the mechanism result instead of ANDing it into the exit code   exit=1
   FAIL the mechanism stage emits valve-disabled twins and the auto-pass probe, under their own roles
       (the exit-code assertion: expected 1, got 0)
   11 passed, 1 failed, 0 todo in 2.30s

=== M5 triage renders the report and the cell table from its own table  exit=1
   FAIL the triage stage classifies a seed and clobbers nothing
       triage must not touch the report
   11 passed, 1 failed, 0 todo in 2.38s

=== M6 a bare search run writes a selection block                       exit=1
   FAIL a bare search run is labelled as not a verdict
       a bare search run writes NO selection block (expected nil, got table)
   11 passed, 1 failed, 0 todo in 2.26s

=== M7 drop the TRIAGE PENDING placeholder                              exit=1
   FAIL the report names every bar, the valve and the carried debt
   11 passed, 1 failed, 0 todo in 2.38s

=== M8 exit 0 on an unknown argument instead of refusing it             exit=1
   FAIL an unknown argument exits 1
   11 passed, 1 failed, 0 todo in 2.17s

=== M9 drop the triage-only flag guard                                  exit=1
   FAIL a triage-only flag outside triage is refused, not ignored
   11 passed, 1 failed, 0 todo in 3.36s

=== M10 emit the confirm twins at N=7 instead of N=10                   exit=1
   FAIL the confirm stage honours --pool
       the twins sit at N=10 only, which is why the twin match is pool-keyed (expected 10, got 7)
   11 passed, 1 failed, 0 todo in 2.17s

=== M11 drop the per-cell locked-bar record                             exit=1
   FAIL every cell carries a verdict and its named failures
       cell 1: a locked verdict must agree with its locked failures (expected true, got false)
   11 passed, 1 failed, 0 todo in 2.28s

=== M12 the gated bar failure is not reported when it cannot select     exit=1
   FAIL the sweep exits non-zero when it cannot select
   11 passed, 1 failed, 0 todo in 2.24s

=== M13 make a sweep bar stricter than the locked bar it replaced       exit=1
   FAIL every cell carries a verdict and its named failures
       cell 80: sweep failure occupancy is absent from the locked failures
   11 passed, 1 failed, 0 todo in 2.27s

restored: True
```

**M11 was NOT caught on the first pass** — see deviation 6. It is in this table because the assertion
was rewritten until it could fail, not because it passed the first time.

## Observed exit codes and failure names from the cases the plan names

| case | invocation | exit | named failures |
|---|---|---|---|
| **4b** | `--stage mechanism --rounds 3` | **1** | `valve-never-fired, valve-twin-missing, valve-not-load-bearing` (at 3 rounds; at the real 1,000-round probe only the latter two — see the correction above), under a `SUB-STAGE` banner |
| **5** | `--stage confirm --rounds 3 --pool 2,1,Wild,5.0` | **1** | `valve-never-fired, valve-not-load-bearing, autopass-probe-missing`; `autopass-probe-missing` is the one that is deterministic at any round count and is what the case asserts |
| **7** | `--stage confirm --rounds 1 --pool 0,0,Wild,1.5` | **1** | `the confirmation stage found no passing configuration (bars: no-completions); mechanism checks: valve-never-fired,valve-not-load-bearing,autopass-probe-missing` |

## Authentication gates

None.

## Known Stubs

None. Every stage, flag and report section is implemented and exercised; no hardcoded empty value
flows into a report row. The `### Triage` subsection's `TRIAGE PENDING` line is a **deliberate,
asserted placeholder** that plan 02-14 replaces, not a stub: the rows it holds are an output of the
confirm stage that rendered the report, so they cannot exist at render time, and the sweep reads
`02-triage.json` and renders the real rows whenever that file is present.

## Threat Flags

None. The plan's threat register holds as written: the Reproduction section records the command, the
base seed and the tool versions (T-2-48); every rejected candidate carries its named failures
(T-2-49); a per-cell progress line with elapsed `os.clock()` and a 2.4s smoke test cover T-2-50;
case 3 and case 7 cover T-2-51; `evaluateMechanisms` is ANDed into the exit code and mutation M4
proves it (T-2-52); the triage stage classifies every seed as exactly one of two strings and carries
`outcome` / `violation` beside it (T-2-53a).

## Task Commits

1. **Task 1: the owner decision** — no file changed; answered by 02-CONTEXT amendment A8 (`ee1c2cc`,
   committed before this plan started) and recorded verbatim above.
2. **Task 2: `sweep.luau`** — `f03629f` (feat)
3. **Task 3: `sweep.spec.luau`** — `f9db151` (test)

No commit deleted a tracked file: `git diff --diff-filter=D --name-only f03629f~1..HEAD` is empty.

## Verification

```
stylua --check src scripts tests                                      clean
selene src scripts tests                                              0 errors, 0 warnings
lune run scripts/ci/analyze.luau ... src/server/engine ... scripts tests   analyze: ok
lune run scripts/ci/check-guards.luau                                 ok (83 files, 215 requires, 20 guarded roots)
lune run scripts/sim/sweep.luau -- --no-such-flag                     exit 1, "unknown argument: --no-such-flag"
lune run tests/run.luau -- --filter sim/sweep                         12 passed, 0 failed, 0 todo in 2.24s
lune run tests/run.luau                                               505 passed, 0 failed, 3 todo in 25.99s
lune run scripts/verify.luau                                          all 14 automated steps passed in 27.4s
git diff --stat .github/workflows/ci.yml scripts/verify.luau          empty
git status --short .planning/phases/02-card-engine-and-pacing-simulator/   unchanged by running the spec
```

No CI step was added: `tests/run.luau` discovers `tests/sim/sweep.spec.luau` automatically, so the
byte-identical `run:` strings in `scripts/verify.luau` and `ci.yml` are untouched.

## What plan 02-14 must honour

**The command, exactly:**

```bash
cd /home/user/robloxspoons && PATH=$HOME/.rokit/bin:$PATH \
  lune run scripts/sim/sweep.luau -- --stage both
```

No `--rounds`, no `--pool`, no `--out`. The defaults are the locked ones (`search 1000`,
`mechanism 4000`, `probe 1000`, `confirm 10000`) and `--out` defaults to this phase directory, which
is where the two artefacts belong. Budget **~29 minutes**; the run prints a progress line per cell.

1. **Run `both` ONCE, in one process.** A bare `mechanism` or `confirm` run exits non-zero **by
   construction** (table above). Do not resolve that by weakening a bar or by skipping a check.
2. **Do not reduce `--rounds`.** The stall ceiling's margin is 0.0025, so **one** stall in a cell of
   fewer than 400 rounds already exceeds it. At 300 rounds the rehearsal reported spurious
   `stalls, cleared-fraction` margin shortfalls for exactly that reason; at 10,000 rounds the margin
   allows 25 stalls against a measured 1.
3. **Expect `k = 6, j = 1`, an 8.0s deadline, `marginal = false`, and zero stalls.** If the run
   selects something else, the candidate table in report section 9 says why, and that is the
   evidence — not this prediction.
4. **The triage stage may have nothing to triage.** `capArtifactCandidates` was **empty in all 32
   gated cells** of the rehearsal and in all 6,000 gated rounds of 02-09: every stall this engine
   produces is a 300s `time-cap` round, which a raised ACTION cap cannot rescue. If the confirm
   stage again yields no action-cap seeds, **replace the `TRIAGE PENDING` line with that statement**
   rather than leaving it dangling or triaging `failingSeeds` as if a raised action cap could help.
   Plan 02-14 owns `02-G1-REPORT.md` for exactly this edit.
5. **If there ARE seeds:**
   `lune run scripts/sim/sweep.luau -- --stage triage --pool 6,1,Wild,8.0 --n 10 --seeds <list>`
   (add `--cap` to override the default of ten times `SOLVABILITY_ACTION_CAP`). It writes **only**
   `02-triage.json`; re-render the report afterwards by nothing — the report reads the file on its
   next render, and 02-14 folds the rows in by hand, which is what makes the edit auditable.
6. **`valveSeenResetsTotal = 0` and `hitActionCap = false` are the healthy readings.** A non-zero
   `seenResets` means the valve was **blind**, not merely quiet, and is the signal that `CapArtifact`
   cannot be told from `ResidualLivelock`.

## What plan 02-11 must honour

- **The firing-rate bar is a judgement on a smooth curve, and the report's bar-sensitivity ladder is
  there to be argued with.** At 0.07 the selection is k=6; a bar of 0.10 selects k=3 and a bar of
  0.15 selects k=2. The design tension is real and is **not** resolved by this plan: by occupancy and
  median-time-to-first-completion, **k=2 is the sweet spot** (occupancy saturates after k=2 at 0.79,
  and medianFirst is at its minimum there at 14.2s, rising to 21.2s by k=6). The only bar pushing k
  upward is the valve firing rate. "Tightness is what makes the scramble tense" is a design claim the
  bars cannot measure.
- **`AUTO_PASS_SELECTION` must still be recorded as `uniform-random-from-hand`** (02-09).
- **The departures to record in PROJECT.md** are the three in `selection.departures`: the `j >= 1`
  floor against CONTEXT's literal "fewest jokers" tiebreak; A8's replacement of the zero-stall bar
  and the 1% firing-rate bar; and the pool-level margin correction.
- **`ValveForcedPass` is an ordinary, visible event for Phase 4.** At the selected pool it fires in
  **1-3% of rounds** (0.0267 worst case) rather than 10-16% at k=2 — far better than 02-09 feared,
  but still roughly one round in forty at a full roster, which needs a real affordance.

## Self-Check: PASSED

Both created files exist on disk (`scripts/sim/sweep.luau` 1,782 lines; `tests/sim/sweep.spec.luau`
402 lines). Both task commits are present in `git log --all`: `f03629f`, `f9db151`. No commit deleted
a tracked file. `--filter sim/sweep`, the full suite and `scripts/verify.luau` were all re-run green
at this SUMMARY's HEAD, and `git status --short` is clean apart from this file. No cell of the real
sweep was run: the only multi-cell runs were the three calibration scripts and the 300-round dress
rehearsal, all written to `build/` (gitignored) and none of them a verdict at the locked round count.
