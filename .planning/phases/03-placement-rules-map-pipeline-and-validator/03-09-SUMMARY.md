---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 09
subsystem: map-validator
tags: [validator, seats, D-20, MAP-02]
requires: [03-08]
provides: [MAP_SEAT_ORDER, MAP_SEAT_FACING, ISSUE_CODES at 23]
key-files:
  modified:
    - src/server/core/MapContract.luau
    - src/server/core/MapValidator.luau
    - tests/maps/validator.spec.luau
metrics:
  completed: 2026-11-04
---

# Phase 3 Plan 09: Seat winding and facing Summary

Every map's nine seats are now validated for clockwise winding (each step strictly in (0,180), nine steps summing to 360 within 1 degree, wrap included) and for facing the TableAnchor within 5 degrees, as `MAP_SEAT_ORDER` / `MAP_SEAT_FACING`.

Commits: eb53875 (validator + contract), 40a8977 (spec).

## What was done
- `ISSUE_CODES` 21 -> 23; count assertion bumped. The checks sit in the structural card-table pass, guarded on a complete ring and a present anchor, so `MAP_SEAT_COUNT` / `MAP_SEAT_NAME` never co-fire with them and a winding failure suppresses the placement stage.
- Baseline seats moved from a straight line to a real radius-6 ring (via a new `seatRing` helper) BEFORE the winding fixtures; the indexing case now expects seat 1 at (0,3,-46) and seat 9 by computed ring position.
- Six rejection fixtures (anticlockwise, swapped 4/5, facing away, 8 degrees off, on the anchor, wound twice) plus three controls (different-radius uneven ring, 3 degrees off, missing seat gives COUNT only).
- Deferred-checks header rewritten: only the two implemented items were moved to IMPLEMENTED; Bounds-roll noted closed; Phase 5 / Phase 6 / union-of-volumes / collision-vs-sight-sets kept with owners.

## Deviations
1. **[Rule 1 - plan defect] The existing `"seat outside Bounds"` fixture** moved Seat4 to (0,3,-900), which under the new rules also fires FACING and ORDER, failing its exact-set assertion. Re-made surgical: Seat4 slid outward along its own 120 degree bearing to radius 100 (x = 86.6, outside +-62) with its look unchanged. The plan did not anticipate this.
2. **Plan defect: `t.near` does not exist** in the harness; seat 9's position is asserted with `t.truthy(math.abs(..) < 1e-9)`.
3. **Plan defect (acceptance criterion):** the `--ignore "**/fixtures/**"` analyze form is refused in a worktree; analyze was run per directory (`src/server/core`, `tests/maps`), both `analyze: ok`. `scripts/` was not touched.
4. The wound-twice fixture reports on Seat1 (the sum fault has no later seat of a bad step); the plan did not specify a seat for it.
5. A look vector with no horizontal component is reported as `MAP_SEAT_FACING` (180 degrees) rather than dividing by zero; not in the plan.

## Demonstrated-red mutations (verbatim harness output; spec run with `--filter validator.spec`)

M1: winding check deleted (step test, sum test, and the on-anchor report all disabled):
```
FAIL tests/maps/validator.spec.luau::rejects: seats wound anticlockwise -> MAP_SEAT_ORDER
     expected at least one issue (expected a truthy value, got false)
FAIL tests/maps/validator.spec.luau::rejects: two adjacent seats swapped -> MAP_SEAT_ORDER
     expected at least one issue (expected a truthy value, got false)
FAIL tests/maps/validator.spec.luau::rejects: a seat on the table anchor -> MAP_SEAT_ORDER
     expected at least one issue (expected a truthy value, got false)
FAIL tests/maps/validator.spec.luau::rejects: seats wound twice round -> MAP_SEAT_ORDER
     expected at least one issue (expected a truthy value, got false)
64 passed, 4 failed, 0 todo in 0.74s
```
M2: facing check deleted (`if cosine < math.cos(...)` -> `if false`):
```
FAIL tests/maps/validator.spec.luau::rejects: a seat facing away from the table -> MAP_SEAT_FACING
     expected at least one issue (expected a truthy value, got false)
FAIL tests/maps/validator.spec.luau::rejects: a seat 8 degrees off the anchor -> MAP_SEAT_FACING
     expected at least one issue (expected a truthy value, got false)
66 passed, 2 failed, 0 todo in 0.86s
```
M3: sum-to-360 dropped, per-step test kept (only wound-twice goes red; the other three ORDER cases pass):
```
FAIL tests/maps/validator.spec.luau::rejects: seats wound twice round -> MAP_SEAT_ORDER
     expected at least one issue (expected a truthy value, got false)
67 passed, 1 failed, 0 todo in 0.66s
```
M4: `FACING_TOLERANCE_DEGREES = 1.0`:
```
FAIL tests/maps/validator.spec.luau::a seat 3 degrees off the anchor is within tolerance
     expected {  }, got { [1] = { [code] = "MAP_SEAT_FACING", [message] = "seat faces 3.0 degrees away from the table anchor (tolerance 1)", [path] = "TestMap/Data/CardTable/Seats/Seat7" } }
67 passed, 1 failed, 0 todo in 0.63s
```
M5: `FACING_TOLERANCE_DEGREES = 20.0`:
```
FAIL tests/maps/validator.spec.luau::rejects: a seat 8 degrees off the anchor -> MAP_SEAT_FACING
     expected at least one issue (expected a truthy value, got false)
67 passed, 1 failed, 0 todo in 0.69s
```
Each mutation restored from a backup; the tree was verified clean afterwards.

## Verification
validator.spec 68 passed 0 failed; graybox.spec 19 passed 0 failed (its seat case kept); full suite 657 passed, 0 failed, 28.86s; selene.pure clean; check-guards ok (97 files, 283 requires, 23 guarded roots); analyze ok on `src/server/core` and `tests/maps`; `validate-map maps/gray-box.rbxm` -> `ok (21 spots, 9 seats)`; `scripts/verify.luau` ran through (reports 3 unsigned manual checks, non-failing).

## Handoff for 03-10
- Gate rows for the nine-gate table: use M1-M5 above verbatim. M3 is the load-bearing-sum proof; M4+M5 bound the tolerance both ways.
- Suite time is now 28.86s (up from 29.6s wave-2 figure being the last tracked; roughly flat). The new passing controls add 2 bakes.
- Counts re-measured at execution time: guarded roots 23, ISSUE_CODES 23, validator.spec 68 cases.
- Known weakness: the sum fault is reported on Seat1 by convention, not on a "culprit" seat.

## Self-Check: PASSED
Files and both commits exist.
