---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 01
subsystem: map-contract
tags: [map, contract, validator, snapshot, luau]
requires: []
provides:
  - "Node v2 (up, canCollide, shape), CONTRACT_VERSION = 2"
  - "MAP_NODE_BASIS_INVALID (13 issue codes)"
  - "maps/gray-box.rbxm regenerated at ContractVersion 2"
affects: [03-02, 03-03, 03-06, 03-08, 03-09]
key-files:
  modified:
    - src/server/core/MapContract.luau
    - src/server/core/MapValidator.luau
    - scripts/maps/snapshot.luau
    - src/server/services/MapLoader.luau
    - scripts/maps/generate-graybox.luau
    - maps/gray-box.rbxm
    - tests/maps/validator.spec.luau
    - tests/maps/graybox.spec.luau
decisions:
  - "shape in scope for v2; only Part+Block is standable (recorded in MapContract header)"
  - "ContractVersion 1 maps rejected outright, not migrated"
metrics:
  tasks: 3
  completed: 2026-11-04
---

# Phase 3 Plan 01: Map contract v2 Summary

Node v2 (`up`, `canCollide`, `shape`) with `CONTRACT_VERSION = 2`, a structural `MAP_NODE_BASIS_INVALID` check, twin snapshotters emitting an identical shape, and a regenerated graybox whose Ramp reads back as a 24.90 degree incline.

## Commits
- f4b2d23 feat(03-01): Node v2 contract with MAP_NODE_BASIS_INVALID (Task 1)
- 38535b6 feat(03-01): snapshotters emit up/canCollide/shape; graybox at v2 (Task 2)
- test commit (Task 3): v2 fixtures and shape-parity gate

## Verification
`scripts/verify.luau`: all 14 automated steps passed. `tests/run.luau`: 517 passed, 0 failed, 0 todo. Regenerated `.rbxm` is byte-identical to a second regeneration (`cmp`). The graybox spot table is untouched (CLI still prints 18 spots).

## Demonstrated-red mutations (verbatim harness output)

**1. Rolled-Bounds case** (mutation: `or up ~= nil` -> `or false and up ~= nil` in the Bounds check; plan said "comment out", this disables the same branch):
```
FAIL tests/maps/validator.spec.luau::rejects: Bounds rolled about the look axis -> MAP_BOUNDS_INVALID
     expected at least one issue (expected a truthy value, got false)
51 passed, 1 failed, 0 todo in 0.32s
```

**2. Gate 1, no-up case** (mutation: `if up == nil then` -> `if false and up == nil then`):
```
FAIL tests/maps/validator.spec.luau::rejects: a Part node with no up vector -> MAP_NODE_BASIS_INVALID
     /home/user/robloxspoons/.claude/worktrees/agent-a6c1144f59e0c1bb7/src/server/core/MapValidator:84: attempt to index nil with 'x'
51 passed, 1 failed, 0 todo in 0.32s
```
Note: this goes red by a crash (`lengthOf(nil up)`), not by a missing issue. That is a legitimate red, but it shows the mutation also removed the nil guard the branch provides.

**3. Gate 8, shape parity** (mutation: deleted `node.canCollide = part.CanCollide == true` from `scripts/maps/snapshot.luau`), parity case, output truncated by the harness at 300 columns:
```
FAIL tests/maps/graybox.spec.luau::both snapshotters emit the identical Node key set (must_have 1)
     expected { [10] = "size", [11] = "tags", [12] = "up", [1] = "anchored", [2] = "attributes", [3] = "canCollide", [4] = "children", [5] = "className", [6] = "look", [7] = "name", [8] = "position", [9] = "shape" }, got { [10] = "tags", [11] = "up", [1] = "anchored", [2] = "attributes", [3] = "chil
...
12 passed, 5 failed, 0 todo in 0.79s
```
The same mutation also failed 4 other graybox cases (CLI validate, MapSpec, etc.) via `MAP_NODE_BASIS_INVALID ... a BasePart node must carry canCollide (contract version 2)`, so CI and the validator independently catch it. All three files restored with `git checkout -- <file>`; full suite green afterwards (517/0/0).

## Deviations from Plan

**1. [Rule 3 - Blocking] Tooling invocation.** The sandbox rejects `PATH=... cmd` prefixes; I used `/root/.rokit/bin/<tool>` and `env PATH=/root/.rokit/bin:/usr/bin:/bin` (needed so `analyze.luau` and the tests can spawn `luau-lsp`/`lune` by name). No code impact.

**2. [Plan defect, minor] Gate 8 loader half is weaker than named.** `MapLoader.luau` cannot run under Lune, so the "identical key set" gate checks the CI snapshotter by real key-set comparison and the runtime snapshotter only by comment-stripped source assertion that `node.<field>` appears. A field assigned under the wrong condition in the loader would not be caught. This is what the plan specified; flagging it for the plan 03-10 gate table.

**3. [Plan defect, minor] Shape-on-non-BasePart check.** The plan table checks `shape ~= nil` on `className ~= "Part"` only for BasePart-shaped nodes, but its own Folder fixture ("shape set on a Folder") has no position/size/look. I added an `elseif node.shape ~= nil` branch for non-BasePart nodes so the fixture fires with the same message and code.

## Known Stubs
None.

## Threat Flags
None.

## Self-Check: PASSED
Commits f4b2d23, 38535b6 and the test commit exist; modified files present; STATE.md and ROADMAP.md untouched.
