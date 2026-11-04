---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 04
subsystem: placement-reachability
tags: [walkgrid, height-field, flood-fill, erosion, pure-zone, micro-world]
requires: ["03-02", "03-03"]
provides:
  - "WalkGrid.columnCountFor / build / flood / seedsAt / columnIndexOf / cellsNear"
  - "MicroWorld: ten hand-built fixtures (flatRoom, pit, sealedRoom, thinWall, ramp, lowCeiling, narrowCorridor, twoIslands, spawnInVoid, hugeBounds)"
affects: [03-05, 03-06, 03-07]
key-files:
  created:
    - src/server/core/WalkGrid.luau
    - tests/placement/MicroWorld.luau
    - tests/placement/walkgrid.spec.luau
decisions:
  - "counters.cells is the FINAL cell count (after headroom, erosion and bounds), so a flat room has cells == reached"
  - "Insertion sort per column instead of table.sort: deterministic, allocation-free, columns hold a handful of intervals"
  - "narrowCorridor puts its faces on lattice centre lines on purpose (see Plan defects 2)"
metrics:
  tasks: 3
  files: 3
requirements: [HIDE-06]
---

# Phase 3 Plan 04: WalkGrid reachability layer Summary

Multi-layer Recast-style height field (per-column span merge, face-normal slope test, headroom, slope-allowance erosion) with an iterative array-queue 4-neighbour BFS whose every link is verified by an exact segment test at two body heights, plus ten MicroWorld fixtures (including D-19's over-a-void pit) and a 26-case spec in which every mechanism has an adjacent negative control.

Commits: d675698 (WalkGrid.luau), 8f5241c (MicroWorld + spec), 2cc5322 (discriminating erosion pair added after the mutation found a plan defect).

## Gates

stylua --check, selene, selene.pure.toml, check-guards (`ok (92 files, 244 requires, 22 guarded roots)`), analyze (src/server/core, tests/placement), full suite `569 passed, 0 failed`, `scripts/verify.luau` all green. `--filter walkgrid.spec`: 26 cases, 0 failed. No-recursion pipeline returns 0 on the real file.

## Demonstrated-red mutations (verbatim harness output)

**1. Gate 7: ramp positive case run at MAX_SLOPE_DEGREES = 24**
```
FAIL tests/placement/walkgrid.spec.luau::ramp at the shipped config: the ledge is in the spawn's region
     ledge: region at probe (-48, 6.999979562793435, 0) (expected 1, got 0)
```
Assertion failure (not a crash). Restored, green.

**2. Drop the slope allowance (`offAllow[k] = di, dj, 0` instead of `distance * tanSlope`)**
The plan's own case (g=1, STEP_UP=0.5) did NOT go red: no FAIL line at all. See Plan defects 1. After adding the discriminating g=0.5 pair:
```
FAIL tests/placement/walkgrid.spec.luau::slope allowance (discriminating): at GRID_SIZE 0.5 the ramp connects at STEP_UP = 0.5 < 0.696
     ledge: region at probe (-48, 6.999979562793435, 0) (expected 1, got 0)
```
Restored, green.

**3. Drop link condition 3 (segment loop in flood changed to `for q = 1, 0 do`)**
```
FAIL tests/placement/walkgrid.spec.luau::a wall thinner than one cell does not leak: the two sides are different regions
     east: region at probe (6, 0.5, 0) (expected 0, got 1)
FAIL tests/placement/walkgrid.spec.luau::the flood region equals an independent union-find over the same verified links
     fuzz "the flood region equals an independent union-find over the same verified links" failed at iteration 1 with seed 1: cell 195 at (10.5, 0, -2.5): flood says 1, union-find says false
FAIL tests/placement/walkgrid.spec.luau::the flood differential produced both fully-connected and partitioned layouts
     every trial ran (expected 300, got 1)
23 passed, 3 failed, 0 todo in 0.46s
```
(The third failure is the fuzz aborting at iteration 1, so the coverage counter case reports 1 trial.) Restored, 26 passed.

**4. Anti-vacuity floor (observed live, first run, before the generator was tuned)**
```
walkgrid fuzz coverage: trials=300 connected=15 partitioned=270 skipped=15
FAIL tests/placement/walkgrid.spec.luau::the flood differential produced both fully-connected and partitioned layouts
     only 15 fully-connected layouts (floor 20) (expected a truthy value, got false)
```
The generator was over-partitioning; the floor caught it. Tuned (wall 15%, low step 70%, crate 15%).

**5. No-recursion grep:** with a `flood(grid, boxes, index, seeds, config)` call injected into the body of a scratch copy, the plan's `sed ... | tail -n +2 | grep -c 'flood('` printed `1`; on the real file it prints `0`.

## Measured values (for plan 03-07's ceilings)

Shipped config, seed 1.
- Flat room: `boxes=5 columns=784 spans=784 cells=484 reached=484 linkTests=483 eroded=92`
- Ramp micro-world (3 boxes): `columns=4000 spans=4312 cells=3918 reached=3918 linkTests=3917 eroded=82` (reached == cells: the ledge is in the region)
- Flood differential: `trials=300 connected=69 partitioned=230 skipped=1` (skipped = spawn column covered, no seed; floor 20 per outcome)
- 6000 x 8 strip (recursion stress): reaches more than 20,000 cells with no recursion.
- Whole `--filter walkgrid.spec` run about 1.0 s.

## Deviations from Plan

### Plan defects (acceptance criteria that could not fail, or were wrong)

**1. [Plan defect] The g=1, STEP_UP=0.5 "slope allowance" case cannot detect a dropped allowance.** At GRID_SIZE 1 and CAPSULE_RADIUS 1.5 the lattice has no neighbour at distance 1.5; the erosion window is +-1 cell, the worst rise it sees is 1 * tan(24.9) = 0.466 < 0.5, so the allowance changes nothing. Research's 0.696 figure assumes a neighbour exactly CAPSULE_RADIUS away, which exists only when GRID_SIZE divides the radius into 3 or more cells. Fix applied: a discriminating pair at GRID_SIZE 0.5 (STEP_UP 0.5 connects, below 0.696 and above 0.232; STEP_UP 0.2, below 0.232, disconnects). The plan's g=1 pair (0.5 connects, 0.4 disconnects) is kept as a link-rule check and is labelled as non-discriminating for the allowance. Consequence for the config lock: at the shipped g=1 the erosion allowance is currently inert for ramps of this slope; it protects only finer grids.

**2. [Plan defect] "Corridor width 3.0 erodes to nothing" is only true when the corridor faces are lattice-aligned.** Width 3 spans exactly three cell centres wherever it sits unless a face lands on a centre line, and the middle one survives erosion (its +-1 neighbours are floor). The fixture therefore places faces at z = +-width/2 on lattice lines (which are cell centres at integer GRID_SIZE with the origin on the world lattice). Recorded in the MicroWorld header. A map author's 3-wide corridor off the lattice would survive at g=1; the authoring rule `width >= 2*capR + g` is therefore a sufficient condition, not an exact boundary.

**3. [Rule 3 - tooling] `--ignore "**/fixtures/**"` is refused by this worktree sandbox** (glob inside a command it cannot verify), so analyze was run on `src/server/core` and `tests/placement` separately; whole-`tests` analyze without the ignore fails only on the deliberately broken `tests/guards/fixtures`. The orchestrator's normal gate chain is unaffected.

### Worktree base note
The commit named in the spawn prompt (51f76b8794b2...) does not exist in this repository; the actual HEAD was 51f76b8 (`merge(worktree-agent-ad2baafbe7f926193): wave 1 plan...`) which contains all wave-1 output. Proceeded from it without a reset.

### Other
- Corridor fixture, thin wall, sealed closet and the rest were exact per plan; sealed closet interior sits at z 6..12 so the plan's probe (0, 0.5, 9) is inside it.
- Added beyond plan: determinism case, loud-config case, `columnCountFor` case, long-strip no-recursion case, clock-after-counters case, sealed-closet case, pit nearest-cell case.

## Known Stubs
None.

## Handoff for plan 03-05 (SpoonPlacement consumes WalkGrid and MicroWorld)

- **Usage order:** `Obb.newIndex(boxes, 8)` -> `WalkGrid.build(boxes, bounds, config, index)` -> collect seeds from EVERY spawn with `WalkGrid.seedsAt(grid, spawn, dropLimit)` (tests use dropLimit 10) -> `WalkGrid.flood(grid, boxes, index, seeds, config)`. Flood resets `region` and `reached`/`linkTests` itself, so re-flooding the same grid with other seeds is safe (the specs do).
- **Empty seed list is the loud signal.** `seedsAt` returns `{}` for a spawn with no footing; `flood` with `{}` reaches 0. Turn it into `MAP_SPAWN_NO_FOOTING`; never flood anyway. `flood` errors on a seed that is not a valid cell index.
- **Config is a parameter.** `GridConfig` = the five Placement fields GRID_SIZE, STEP_UP, MAX_SLOPE_DEGREES, CAPSULE_RADIUS, CAPSULE_HEIGHT (the full Placement table is structurally accepted). A missing field raises `WalkGrid: config.<KEY> is missing...` (no default).
- **Bake-size ceiling:** call `WalkGrid.columnCountFor(bounds, gridSize)` BEFORE `build`; `MicroWorld.hugeBounds()` gives 2000 x 2000 = 4,000,000 columns.
- **Grid layout:** cells are flat parallel arrays; column idx = j * nx + i + 1; `colFirst/colCount` give a column's cells ascending in height; `region[c]` is 0 or 1. `counters.cells` is the final count. Cell centre is `cellX/cellZ`, floor is `cellH`, headroom limit is `cellCeil`.
- **`cellsNear(grid, x, z, radius, out)`** fills `out` from index 1 and returns the count (columns by centre distance, all layers). Allocation-free.
- **Obb caveat honoured:** `queryIndex` is bucket-granular; flood runs the exact `segmentHits` on every returned box.
- **Non-standable boxes** (`standable = false`) still act as solids (erosion, headroom, segments) but never as floors.
- **MicroWorld API:** each builder returns `{ boxes, bounds, spawns, probes }`. Probes sit 0.5 above a surface. Probe names: flatRoom `onFloor`; pit `overVoid`, `onFloor`; sealedRoom `insideSealed`, `outside`; thinWall `west`, `east`; ramp `onLedge`, `onFloor`; lowCeiling `under`, `beside`; narrowCorridor `nearRoom`, `farRoom`, `corridor`; twoIslands `west`, `east` (two spawns); spawnInVoid spawn at (0,30,0). spawnInVoid and hugeBounds reuse flatRoom's boxes. Perimeter walls are 2 thick, 20 high, inner faces at +-12, so default Bounds y max 24 leaves wall tops non-standable by headroom.
- **Spec helper worth copying:** `expectRegion` asserts a cell EXISTS at the probe before asserting its region, so "not reached" can never mean "not there".
- Placement-eroded margin: cells within CAPSULE_RADIUS of a tall obstruction are removed (flat room 484 of 576 floor columns), so spot checks near walls will have no nearby cell; that is by design, not a bug.

## Self-Check: PASSED
Files exist: WalkGrid.luau, MicroWorld.luau, walkgrid.spec.luau. Commits d675698, 8f5241c, 2cc5322 present.
