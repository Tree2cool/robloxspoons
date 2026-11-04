---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 02
subsystem: placement-config
tags: [config, placement, invariants, manual-checks]
requires: []
provides:
  - src/shared/Config/Placement.luau (ten owner-confirmed D-18 constants, UPPER_SNAKE, injected not imported)
  - tests/placement/config_lock.spec.luau (value lock, coupling invariants, clearance cliff, ordering)
  - MANUAL-CHECKS.md M-08 and M-09
affects: [03-05, 03-06, 03-08, phase-5-hunt]
key-files:
  created:
    - src/shared/Config/Placement.luau
    - tests/placement/config_lock.spec.luau
  modified:
    - MANUAL-CHECKS.md
decisions:
  - "Values copied verbatim from D-18; none tuned"
  - "Lower ordering comparison is non-strict (EYE_HEIGHT >= REACH_HEIGHT), kept on purpose"
metrics:
  tasks: 3
  completed: 2026-11-04
---

# Phase 3 Plan 02: Placement constants and lock Summary

Ten owner-confirmed placement constants in one non-importing config module, locked by a 10-case spec
(three invariants each with a negative control, plus the 0.5 clearance cliff), with M-08 and M-09 added
as human gates.

## Commits

- 4eec2b5 feat(03-02): placement constants with measured rationale
- f37f83e test(03-02): config lock spec
- 9c21cc8 docs(03-02): M-08 and M-09 in MANUAL-CHECKS.md

## Verification

stylua, selene, check-guards (ok, 87 files), `tests/run.luau` 519 passed 0 failed 0 todo,
`scripts/verify.luau` 14/14 automated steps green and prints M-07, M-08, M-09 as unsigned.
`grep -rn 'Config/Placement' src/` finds nothing outside the module itself.

## Demonstrated-red mutations (verbatim harness output)

Each was applied to `src/shared/Config/Placement.luau`, run with `lune run tests/run.luau --filter config`,
and restored (config file confirmed clean in `git status` afterwards).

### 1. GRID_SIZE = 4.0 (both coupling cases fire, naming the computed numbers)

```
FAIL tests/placement/config_lock.spec.luau::the ten shipped placement values are exactly the owner-confirmed set (D-18)
     expected 1, got 4
FAIL tests/placement/config_lock.spec.luau::STEP_UP covers a legal slope at the shipped resolution (the ramp coupling)
     STEP_UP 1 < GRID_SIZE * tan(slope) = 2.309401076758503 (expected a truthy value, got false)
FAIL tests/placement/config_lock.spec.luau::PICKUP_MARGIN covers the grid half-diagonal
     PICKUP_MARGIN 1.5 < half-diagonal 2.8284271247461903 (expected a truthy value, got false)
10 passed, 3 failed, 0 todo in 4.83s
```

### 2. SPOT_CLEARANCE = 0.5 (cliff case fires)

```
FAIL tests/placement/config_lock.spec.luau::the ten shipped placement values are exactly the owner-confirmed set (D-18)
     expected 0.25, got 0.5
FAIL tests/placement/config_lock.spec.luau::the clearance cliff exists: 0.5 would cull every authored spot
     SPOT_CLEARANCE 0.5 is on the cliff (expected a truthy value, got false)
11 passed, 2 failed, 0 todo in 4.44s
```

### 3. PICKUP_RANGE = 8.0 (extra, not required by the plan; exercises the knife-edge case)

```
FAIL tests/placement/config_lock.spec.luau::the ten shipped placement values are exactly the owner-confirmed set (D-18)
     expected 7, got 8
FAIL tests/placement/config_lock.spec.luau::effective range is 5.5 and every authored graybox spot sits at least 1 stud clear of a flip
     expected 5.5, got 6.5
11 passed, 2 failed, 0 todo in 4.90s
```

Note on mutation 3: it is caught by `t.equal(E, 5.5)` (the first line of the case), not by the slack
assertions. Those two slack assertions are computed from `E` as required, but the `E == 5.5` equality
fires first, so the slack lines are not independently demonstrated red by this mutation. The negative
control case ("fires at PICKUP_RANGE 8.0") shows the slack arithmetic discriminates at 8.0 (it passes
there, meaning the slack really is under 1.0 at E8 = 6.5).

## Deviations from Plan

**Plan defect (acceptance criterion vs. instruction):** Task 1 acceptance requires
`grep -c 'require' src/shared/Config/Placement.luau` to return 0, but the task's own instructed header
prose uses the words "requires", "require(...)" and "requirement". Reworded those to "imports",
"loading", "reaches across", "load" and "need" so the criterion holds; no meaning lost.

No other deviations. All ten values verbatim; `>=` on the lower height comparison retained.

## Known Stubs

None.

## Self-Check: PASSED

Files exist (Placement.luau, config_lock.spec.luau, MANUAL-CHECKS.md edits); commits 4eec2b5 and f37f83e
exist; STATE.md and ROADMAP.md untouched.
