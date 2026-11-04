---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 06
subsystem: map-pipeline
tags: [luau, graybox, placement, d-17, d-15]
requires: [03-02, 03-05]
provides:
  - "gray-box reference map with 21 authored default spots, every one passing the real placement rules (D-17 STRICT)"
  - "tests/placement/graybox_spots.spec.luau: per-spot proof, margin table, four negative controls, bake time cap"
affects: [03-08, 03-10]
key-files:
  modified:
    - scripts/maps/generate-graybox.luau
    - maps/gray-box.rbxm
    - tests/maps/graybox.spec.luau
    - MANUAL-CHECKS.md
  created:
    - tests/placement/graybox_spots.spec.luau
requirements-completed: [MAP-03, HIDE-06]
completed: 2026-11-04
---

# Phase 3 Plan 06: Graybox regenerated to 21 passing spots Summary

The reference map now authors 21 default spots (14 floor, 1 at y=2, 2 crate tops, 4 ledge), all passing the real
`SpoonPlacement` rules under STRICT, 5 above the 16 minimum. No rule, constant or `MIN_DEFAULT_SPOTS` was touched (D-15).

Commits: `dc74b1f` (generator + map), `294fbde` (graybox_spots spec), `b2b11f3` (graybox.spec + M-06).

## What shipped

- `CrateNorthEastRoom` (4x2x4 at 33,1,-45) added; `ShelfSouthEastRoom` geometry kept (03-05 corpus probes it).
- Spots 08/09 moved to SE-room floor (50,0,50), (55,0,40); spot 15 (-22,0,0) and 17 (33,2,-45) added. The shelf centre
  (measured d*los 12.36) and shelf east edge (d*conn 6.54 vs E 5.5) are recorded in the generator under
  "MUST NOT BE RE-AUTHORED". The comment gives the ledge's survival reason as the 30-degree slope limit against the ramp's
  24.9 degrees; it does not cite the slope-allowance erosion (inert at grid 1.0). It also records that the shelf reports
  `Unreachable` rather than `OutOfReach` (accepted departure).
- Regenerating twice gives byte-identical output (`cmp` clean, 2581 bytes).
- `validate-map`: `ok (21 spots, 9 seats)`.
- M-06: `~~**18**~~ **21**` and `reports ~~18~~ **21**` struck-and-replaced; dated note points at M-10 (not added here; 03-10
  owns it). `- [x] M-06 signed off: alejandrog_m 2026-11-03` unchanged; `verify.luau` still reports 6 signed, 3 unsigned
  (M-07, M-08, M-09).

## Per-spot margin table (verbatim, effective range 5.5)

```
  Spot01  surface y 0.0  distance 2.121  margin 3.379
  Spot02  surface y 0.0  distance 2.121  margin 3.379
  Spot03  surface y 0.0  distance 2.121  margin 3.379
  Spot04  surface y 0.0  distance 2.121  margin 3.379
  Spot05  surface y 0.0  distance 2.121  margin 3.379
  Spot06  surface y 4.0  distance 4.062  margin 1.438
  Spot07  surface y 0.0  distance 2.121  margin 3.379
  Spot08  surface y 0.0  distance 2.121  margin 3.379
  Spot09  surface y 0.0  distance 2.121  margin 3.379
  Spot10  surface y 0.0  distance 2.121  margin 3.379
  Spot11  surface y 0.0  distance 2.121  margin 3.379
  Spot12  surface y 0.0  distance 2.121  margin 3.379
  Spot13  surface y 0.0  distance 2.121  margin 3.379
  Spot14  surface y 0.0  distance 2.121  margin 3.379
  Spot15  surface y 0.0  distance 2.121  margin 3.379
  Spot16  surface y 4.0  distance 4.062  margin 1.438
  Spot17  surface y 2.0  distance 3.536  margin 1.964
  Spot18  surface y 6.5  distance 2.121  margin 3.379
  Spot19  surface y 6.5  distance 2.121  margin 3.379
  Spot20  surface y 6.5  distance 2.121  margin 3.379
  Spot21  surface y 6.5  distance 2.121  margin 3.379
```
Tightest margin is the 4-stud crate tops at 1.438 (matches research's 1.44). Floor/ledge spots all sit on a cell
centre 2.121 away (half-diagonal of a 1.0 cell plus 0.5 anchor height). Margin measures reach only; the sight rule
has no scalar margin here.

## Negative controls: observed vs research

| Control | Observed | Research / plan | Note |
|---|---|---|---|
| slope 24 | 17 of 21 survive; ledge Spot18-21 all `Unreachable` | plan expected 17 (12 on the old 18) | agrees |
| grid 4 (STEP_UP 1.0) | **16** of 21; failing Spot16, Spot18-21, all `Unreachable` | research 11-12 on the old table | DISAGREEMENT with the plan's implied 17: Spot16 (east-hall crate top) also loses its connected cell on a 4-stud lattice. Asserted exactly (16) and recorded, not absorbed. The plan said "same four ledge spots fail"; true but not the whole set |
| clearance 0.5 | 0 survive; 0.49 gives 21 | all 18 culled at 0.5 | agrees |
| EYE_HEIGHT 2.5 (shared) | 19 of 21; Spot06 and Spot16 `NoSight` | research 15 of the old 18 (also culling the two shelf spots and others) | assertConfig accepts it (non-strict `>=`); only the two crate tops are culled on this map |

## Bake measurements

Wall clock for load + bake + 21 checks: 0.030-0.072 s over runs (28-29 ms bake in isolation per 03-05), cap 0.5 s.
Counters: boxes=41, columns=15376, spans=15764, cells=14146, reached=11642, linkTests=11638, eroded=1246.
Seven recorded; asserted floors (columns>10000, cells>5000, reached>5000, linkTests>1000, boxes>20) sit well below.

## Demonstrated-red mutations (verbatim)

**1. Slope control, override 24 -> 30:**
```
FAIL tests/placement/graybox_spots.spec.luau::at MAX_SLOPE_DEGREES 24 the ramp does not connect and the four ledge spots fail
     Spot18 still passes with a 24 degree slope limit (expected a falsy value, got true)
0 passed, 1 failed, 0 todo in 0.44s
```
**2. Cap, `GRAYBOX_CAP_SECONDS` = 1e-6:**
```
FAIL tests/placement/graybox_spots.spec.luau::the reference-map bake completes inside the CI cap
     bake took 0.06338439200044377 s against a cap of 0.000001 (expected a truthy value, got false)
0 passed, 1 failed, 0 todo in 0.59s
```
**3. Vacuity, `bakeGraybox` given an empty box list:**
```
FAIL tests/placement/graybox_spots.spec.luau::the reference-map bake completes inside the CI cap
     /home/user/robloxspoons/.claude/worktrees/agent-a0c04fc5792ab31eb/tests/placement/graybox_spots.spec:77: graybox did not bake: 4 faults
0 passed, 1 failed, 0 todo in 0.41s
```
This fires before the counter floors, not at them: `bake` itself refuses an empty world (every spawn is `SpawnNoFooting`),
so the floors are never reached. Still red before the clock is read, which is the property that matters. The counter
floors are therefore a second line that no mutation here exercised directly (see plan defect 2).

**4. D-17, 22nd spot at (50, 8.5, 59) added to the generator:**
```
FAIL tests/placement/graybox_spots.spec.luau::every authored default spot passes the real placement rules (D-17 STRICT)
     Spot22 at (50, 9, 59) failed: Unreachable (expected a truthy value, got false)
0 passed, 1 failed, 0 todo in 0.39s
```
and the margin case: `Spot22 margin is -1.0383484153110105, below 0.5`. (Reason is `Unreachable`, as 03-05 said.)

**5. Height variety, Spot17 surface 2 -> 4 in the generator:**
```
FAIL tests/maps/graybox.spec.luau::spots are at exactly four heights: 14 floor, 1 at 2, 2 crate tops, 4 on the ledge
     expected { [1] = 0.5, [2] = 2.5, [3] = 4.5, [4] = 7 }, got { [1] = 0.5, [2] = 4.5, [3] = 7 }
FAIL tests/placement/graybox_spots.spec.luau::at SPOT_CLEARANCE 0.5 not one authored spot survives
     expected 0, got 1
37 passed, 2 failed, 0 todo in 1.06s
```
(Second failure is a side effect: a spot floating 2 studs above the crate escapes the 0.5 cliff.) All mutations restored by
`git checkout --` on the files or by restoring a saved copy; suite then green.

## Deviations from Plan

**1. [Plan defect] Grid-4 expectation.** The plan said only the ledge fails; Spot16 also fails, giving 16 not 17. Asserted
exactly and recorded above.

**2. [Plan defect] Gate-3 vacuity mutation cannot reach the counter floors.** An empty box list makes `bake` return nil with
faults, so the `bakedWorld` assertion fires first. The floors still guard against a bake that runs but traverses nothing;
no mutation exercises that path directly. I added a case asserting the empty-box bake yields nil and faults, so the
refusal itself is covered.

**3. [Plan defect] `build/` did not exist** in a fresh worktree; the plan's `build/graybox-check.rbxm` command needs
`mkdir -p build`.

**4. [Additions]** SPOT_CLEARANCE 0.49 positive half in the clearance case (21 survive), so 0 at 0.5 is shown to be the cliff
and not general breakage.

Commits used `--no-verify` per instruction; stylua, selene, check-guards (`ok 95 files, 262 requires, 23 guarded roots`)
and the full suite (624 passed, 0 failed, 26.8 s) were run manually. `verify.luau`: all 14 steps passed.

## Handoff for 03-08 (validator placement stage)

- `maps/gray-box.rbxm` now has 21 spots, all `ok` at `src/shared/Config/Placement.luau`; `validate-map` prints
  `ok (21 spots, 9 seats)` today and must continue to once the placement stage is on. If it prints a spot issue, the
  stage is wrong, not the map.
- Loading recipe is in `tests/placement/graybox_spots.spec.luau::bakeGraybox`: `Snapshot.loadFile`, `boxesOf(root, config)`,
  bounds = centre +/- size/2, spawns from `Data/SeekerSpawns`, `bake` then `check` per spot. Bake faults are empty for this map.
- Reasons you should see for known-bad inputs: shelf spots `Unreachable`, slope-24 ledge `Unreachable`, grid-4 `Unreachable`.
- The `validate-map` test count asserted in `tests/maps/graybox.spec.luau` is 21; the test suite is now 624 cases.

## Known Stubs
None.

## Self-Check: PASSED
