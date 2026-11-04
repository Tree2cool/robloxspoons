---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 03
subsystem: placement-geometry
tags: [obb, slab, geometry, pure-zone, fuzz]
requires: []
provides:
  - "Obb.fromPose / isOrthonormal / distanceToPoint / segmentHits / columnSpan / newIndex / queryIndex / GEOM_EPSILON"
affects: [03-04, 03-05]
key-files:
  created:
    - src/server/core/Obb.luau
    - tests/placement/obb.spec.luau
decisions:
  - "Index carries stamp and queryId fields (dedupe state lives in the index, allocation-free queries)"
metrics:
  tasks: 2
  files: 2
requirements: [HIDE-06]
---

# Phase 3 Plan 03: Obb geometry Summary

Pure-zone oriented-box geometry (basis from look x up, Kay-Kajiya slab segment test with a pre-division parallel guard, exact top-exit face normal for slope, integer-keyed bucket index) with a spec whose two differential fuzz properties were watched go red.

Commits: 540416e (Obb.luau), then the spec commit (test(03-03)).

## Fuzz coverage (for plan 03-04)

Seed 1, measured: `obb fuzz coverage: segments hit=127 miss=473; columns hit=105 miss=495` (600 trials each; floor of 50 per outcome asserted). Boxes: size 1-8 per axis, centre within +-3, random yaw/pitch/roll basis; segment endpoints in +-8; columns within +-6.

## Demonstrated-red mutations (verbatim harness output)

### 1. Swap inverted in segmentHits (`if ta > tb` changed to `if ta < tb`)

```
FAIL tests/placement/obb.spec.luau::degenerate 1: a segment parallel to a slab never divides, and grazing counts as blocked
     straight through the middle hits (expected true, got false)
FAIL tests/placement/obb.spec.luau::degenerate 3: a segment starting inside the box is a hit
     starts inside, ends far outside (expected true, got false)
FAIL tests/placement/obb.spec.luau::degenerate 4: a grazing or tangent contact is blocked, not clear (D-11's rejecting bias)
     ending exactly on a face plane is blocked (expected true, got false)
FAIL tests/placement/obb.spec.luau::degenerate 5: the world-AABB prefilter rejects before the slab test runs
     along the plank diagonal still hits (expected true, got false)
FAIL tests/placement/obb.spec.luau::segmentHits agrees with a brute-force sampler over random oriented boxes
     fuzz "segmentHits agrees with a brute-force sampler over random oriented boxes" failed at iteration 2 with seed 1: sampler found a point inside the box but segmentHits said miss: centre=(-2.937649,-0.817728,0.409387) h=(3.614834,1.634169,3.476364) right=(-0.991722,0.029156,-0.125052) up=(0.122348,-0.081039,-0.989173) look=(0.038974,0.996284,-0.076801) p=(-6.756887,-4.167838,2.325227) q=(-7.785699,4.712929,-7.800008)
FAIL tests/placement/obb.spec.luau::the differential fuzz generated both hits and misses
     only 0 segment trials hit (floor 50) (expected a truthy value, got false)
10 passed, 6 failed, 0 todo in 0.32s
```
Restored; green.

### 2. columnSpan normal sign (`nyTop = sign * bb` changed to `-sign * bb`)

```
FAIL tests/placement/obb.spec.luau::columnSpan through a flat floor reports lo, hi and a vertical top normal
     nyTop -1 expected 1 (expected a truthy value, got false)
FAIL tests/placement/obb.spec.luau::columnSpan through the Ramp reports a 24.90 degree face normal
     nyTop -0.90701294 expected 0.90701294 (expected a truthy value, got false)
FAIL tests/placement/obb.spec.luau::columnSpan agrees with a dense vertical sampler
     fuzz "columnSpan agrees with a dense vertical sampler" failed at iteration 7 with seed 1: nyTop -0.957658 is not a top-exit normal: centre=(-0.925199,2.606042,0.855192) h=(3.853237,2.534787,2.405968) right=(-0.965701,-0.248076,0.076678) up=(-0.040946,-0.146117,-0.988420) look=(-0.256407,0.957658,-0.130948) x=-1.884171 z=2.686802
FAIL tests/placement/obb.spec.luau::the differential fuzz generated both hits and misses
     only 1 column trials hit (floor 50) (expected a truthy value, got false)
12 passed, 4 failed, 0 todo in 0.52s
```
Restored; green. (The Ramp case fails on the 0.90701294 comparison, which precedes the explicit 24.90 degree assertion in the same case.)

### 3. Anti-vacuity (segment endpoints shifted +100 in X so every segment misses)

```
FAIL tests/placement/obb.spec.luau::the differential fuzz generated both hits and misses
     only 0 segment trials hit (floor 50) (expected a truthy value, got false)
15 passed, 1 failed, 0 todo in 0.68s
```
The differential property itself stayed green (it agrees with everything when nothing hits), which is exactly why the floor case exists. Restored; green.

## Deviations from Plan

1. **[Plan defect, test geometry]** My first draft of degenerate 5 used a segment that crossed the plank's diagonal, so it genuinely hit; replaced with (3,0,-3)->(3,0,-1), inside the AABB but 4.2 studs off the plank. Not a plan defect in the acceptance criteria, a test authoring error caught on first run.
2. **[Tolerance]** The Ramp's committed up vector has norm error of a few 1e-6 (float32 digits), so the distanceToPoint case uses 1e-4, not 1e-6. Still four orders under GEOM_EPSILON.
3. **[Interface addition]** `Index` gained `stamp` and `queryId` fields (the plan requires a stamp-array dedupe but its type listing omitted where the stamp lives). Plans 03-04/05 should treat these as opaque.
4. **[Plan defect, minor]** Acceptance text says `--filter obb` reports "at least 14 cases"; the filter is a substring match on labels, so it also picks up unrelated tests; the spec itself registers 17 cases. Use `--filter obb.spec` for a clean count. The "24.90" mutation expectation is met via the 0.90701294 assertion preceding it.
5. `queryIndex` is bucket-granular: it may return a box that shares a bucket with the rectangle but does not touch it. Callers must run their exact test; the spec asserts no false negatives and no duplicates.

## Verification

stylua, selene (standard and pure config), check-guards (ok, 87 files), luau analyze on src/server/core and tests/placement, and the full suite (525 passed, 0 failed) all green. STATE.md and ROADMAP.md untouched. `scripts/verify.luau` and the repo-wide analyze were not run separately (the `--ignore` glob invocation is blocked in this sandbox); the orchestrator should run them post-merge.

## Known Stubs

None.

## Self-Check: PASSED
