---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 07
subsystem: testing
tags: [maze, oracle, walkgrid, reachability, wall-clock-cap, lune]
requires:
  - phase: 03-05
    provides: SpoonPlacement.boxesOf / bake / check
provides:
  - scripts/maps/generate-maze.luau (parameterised adversarial maze plus oracle sidecar)
  - tests/placement/maze.spec.luau (Gate 2 oracle, Gate 3 cap)
affects: [03-08, 03-10, 07a]
key-files:
  created:
    - scripts/maps/generate-maze.luau
    - tests/placement/maze.spec.luau
decisions:
  - Oracle is computed from the generator's FINAL graph by BFS, not assumed from which cells were walled off
  - Maze origin is 0.5 so every wall face sits on a lattice centre line (corridor-3 control depends on it)
metrics:
  completed: 2026-11-04
---

# Phase 3 Plan 07: Maze oracle and capped bake Summary

A Lune-generated 4-level adversarial maze with an exact reachability oracle (positive half asserted first),
sealed-pocket and thin-wall cases, a corridor-below-minimum refusal, and a 2.0 s asserted bake cap guarded by work counters.

## Commits
- 828fb4a feat(03-07): generator
- f204c73 test(03-07): spec

## Measured figures (target for Phase 7a's real maze)

Generator at defaults (`footprint 248, corridor 6, wall 1, levels 4`, seed 20261104):

```
generate-maze: wrote build/maze.rbxm (10614 bytes, 5193 boxes, 1217 open cells, 8 sealed cells) and build/maze.rbxm.oracle.json
```

Research figures were 4,640 boxes and 59,536 columns. Actual: 5,193 boxes (n = 35 cells per axis, 4 levels,
perimeter and intersection-filling segments) and 63,001 columns (Bounds has 2 studs of slack each side). Dials were not
tuned to hit research; the cap is set from measured time. 8 sealed cells = 1 pocket + 7 cut off by the thin wall.

Seven counters (`maze counters:` line):
`boxes=5193 columns=63001 spans=244036 cells=102804 reached=25551 linkTests=25553 eroded=68616`

Floors asserted: boxes 4000, columns/spans/cells 50000, reached/linkTests 10000, eroded 1000.

Wall clock: boxesOf 0.006 s, bake + flood 0.226 s; the capped case (boxesOf + bake + 19 checks) measured
**0.212 to 0.219 s of the 2.0 s cap, ratio about 0.11 (9x headroom)**. Generation takes 0.15 s.
**Phase 7a target: stay under ~63,000 columns / 5,200 boxes / 0.25 s bake; `MAX_BAKE_COLUMNS` (250,000) is ~4x above it.**

Second dial setting (`--footprint 64 --corridor 4 --levels 1`): 172 boxes, 141 open cells, 3 sealed cells; oracle holds both halves.

Full suite: 624 passed, 0 failed in 27.19 s. stylua, selene and check-guards clean (guarded roots 23, unchanged).

## Demonstrated-red mutations (verbatim harness output)

### Gate 2: flood seeded from a sealed pocket instead of the spawn
```
ok   tests/placement/maze.spec.luau::the maze bakes with no faults
FAIL tests/placement/maze.spec.luau::every open maze cell is reached from the spawn (the oracle's positive half)
     0/1217 open cells reached (expected 1217, got 0)
FAIL tests/placement/maze.spec.luau::no sealed maze cell is reached (the oracle's negative half)
     nothing was reached, so this half is vacuous (expected a truthy value, got false)
FAIL tests/placement/maze.spec.luau::a default spot inside a sealed pocket is rejected as Unreachable
     Spot19 should be Unreachable (expected Unreachable, got nil)
FAIL tests/placement/maze.spec.luau::every default spot at an open cell is valid
     Spot01 should be valid, got Unreachable (expected true, got false)
FAIL tests/placement/maze.spec.luau::the bake's work counters are non-zero and above the measured floors
     counters.linkTests = 8, expected above 10000 (expected a truthy value, got false)
FAIL tests/placement/maze.spec.luau::the oracle's positive and negative halves both hold at a second dial setting
     second setting: 0/141 open cells reached (expected 141, got 0)
5 passed, 6 failed, 0 todo
```
Note: the wall-clock case PASSED under this mutation (the flood did something, just the wrong something). The cap does
not detect a wrong flood; the oracle and the counter floors do. That is the intended division of labour.

### Gate 2 vacuity: generator refusal removed, generated at `--corridor 3`
Refusal in place (the shipped behaviour), exit 1:
```
generate-maze: corridor 3 is below the minimum 4 (2 * capsuleRadius 1.5 + gridSize 1.0);
  erosion would leave zero walkable cells and every reachability assertion would pass vacuously
```
Refusal removed (`if false and corridor < minimum`), spec generating at corridor 3:
```
FAIL tests/placement/maze.spec.luau::the maze bakes with no faults
     SpawnNoFooting: spawn 1 has no standable cell within 8 studs below it (expected 0, got 1)
FAIL tests/placement/maze.spec.luau::every open maze cell is reached from the spawn (the oracle's positive half)
     0/3841 open cells reached (bake faulted: SpawnNoFooting: spawn 1 has no standable cell within 8 studs below it) (expected 3841, got 0)
FAIL tests/placement/maze.spec.luau::no sealed maze cell is reached (the oracle's negative half)
     nothing was reached, so this half is vacuous (expected a truthy value, got false)
FAIL tests/placement/maze.spec.luau::a corridor below the erosion minimum is refused by the generator, not detected here
     expected exit 1, got 0 (expected 1, got 0)
```
Side by side, a sealed-half-only assertion (scratch probe baking the grid directly, bypassing the spawn fault):
```
corridor 3 grid: cells=0 seeds=0 reached=0
sealed-half-only assertion: 0 of 3 sealed cells reached -> would PASS
positive half: 0/3841 open cells reached -> FAILS
```
`cells=0`: erosion removed every standable cell, confirming the lattice alignment (MAZE_ORIGIN 0.5) makes the corridor-3
control demonstrate what the plan claims. Generator and spec were restored afterwards (diffed identical to the committed files).

### Gate 3: `MAZE_CAP_SECONDS = 1e-6`
```
maze wall clock: 0.212 s of 0.000001 s cap
FAIL tests/placement/maze.spec.luau::bake, flood and a check per spot complete inside the wall-clock cap
     maze work took 0.2118083099994692 s, cap is 0.000001 s (expected a truthy value, got false)
```

## Deviations from Plan

1. **[Plan defect - Rule 1] Positive-half mutation cannot report "0 of N" through `bake` alone at corridor 3.** With zero
   standable cells the spawn has no footing, so `bake` returns a nil world with a `SpawnNoFooting` fault. The spec's
   `countReached` treats a nil world as zero reached and the failure message appends the fault, so the positive half still
   fails with "0/3841 open cells reached". The "sealed-half-only would have passed" evidence needed a scratch probe that
   floods the grid directly, since a faulted bake cannot be queried. Recorded above.
2. **[Plan defect - Rule 1] Acceptance grep `passes vacuously` vs. the specified message `would pass vacuously`.** The
   interface text and the grep disagree. The message follows the interface text; the generator header comment carries the
   literal `passes vacuously` so both hold. The spec asserts `pass vacuously`.
3. **[Rule 3] Thin wall is placed across one carved passage, not "full-width".** A full-width 0.3 wall would sever the
   whole level and make the oracle's open set meaningless. It spans one passage (width = corridor) chosen so that cutting
   it removes at most 10% of the open cells; the oracle comes from BFS over the final graph so it stays exact.
4. **[Rule 2] Added two guards not in the plan:** positive-half case asserts `cells > 0`; negative-half case asserts something
   was reached, so it can never pass vacuously on its own. Also a separate "bakes with no faults" case (11 cases total).
5. **Case 10 footprint-64 maze** reaches a few hundred cells, not 2,000; the case carries the corrected rationale (second
   dial setting only, not a recursion discriminator) and names the two real protections.
6. **LCG exactness:** the product is split into 16-bit halves because `state * 1103515245` exceeds 2^53.

## Known Stubs
None.

## Threat Flags
None. The generator emits no scripts; the oracle sidecar lives in gitignored `build/`.

## Self-Check: PASSED
Both files exist; commits 828fb4a and f204c73 present.
