---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 05
subsystem: placement-rules
tags: [luau, pure-zone, placement, corpus, found-05]
requires: [03-01, 03-02, 03-03, 03-04]
provides:
  - "SpoonPlacement: PlacementConfig, REASON_ORDER, assertConfig, boxesOf, bake, check (arity 2)"
  - "placement corpus (25 rows, reason-coded) with E +- 0.25 stability probe"
affects: [03-06, 03-08, phase-05, phase-06]
key-files:
  created:
    - src/server/core/SpoonPlacement.luau
    - tests/placement/corpus.spec.luau
  modified:
    - tests/placement/config_lock.spec.luau
requirements-completed: [HIDE-06, HIDE-07]
duration: ~1h
completed: 2026-11-04
---

# Phase 3 Plan 05: SpoonPlacement and the placement corpus Summary

One pure-zone rule set, `SpoonPlacement.check(world, point)` (arity 2, six locked reasons, first match wins),
over a world baked once from the Node snapshot, with a 25-row reason-coded corpus and an `E +- 0.25` stability probe.

Commits: `7f31d2b` (module), corpus commit, config-lock commit (see `git log`).

## Headline finding for plans 03-06 and 03-08: the shelf is Unreachable, not OutOfReach

Research's corpus expectation for both shelf spots was `OutOfReach`. This implementation reports **`Unreachable`**
for both, and the disagreement was investigated rather than absorbed:

- Research's numbers are reproduced exactly. The nearest spawn-connected cell is 6.538 from both shelf spots
  (cells (49.5/50.5, 0, 58.5) and (53.5/54.5, 0, 58.5)), matching research's d*conn = 6.54. A corpus case
  ("shelf thresholds") asserts 6.54 directly, so the measured value is checked even though the reason name differs.
- The label differs because the shelf top carries its own standable cells (h = 8.5, region 0, 2.12 from the edge
  spot, 2.12 from the centre spot). They are inside E = 5.5 but not walkable from any spawn. By the locked order
  (`OutOfReach` = no cell of ANY region within E; `Unreachable` = cells within E, none connected) the reason is
  `Unreachable`. Research gives the disconnected wall-top cell at (61, 25, 0) the same "out of reach" label, and
  both research and the plan expect that one as `Unreachable`; "REACH" in research's ladder is a coarse bucket for
  both reasons.
- Consequence: **the shelf is never `OutOfReach` at any E below 6.54.** For 03-06's spot table: shelf spots 08 and 09
  are `Unreachable` at the shipped config. Verified against the ladder: at PICKUP_RANGE 8.5 (E = 7.0) Spot09 is valid
  and Spot08 is `NoSight`, as research's ladder row says (asserted in the corpus).
- `OutOfReach` therefore needed another producer for the reason-coverage case: row "flat room: 8.7 up is OutOfReach"
  (nearest floor reach point 6.24 away, inside range 7.0, outside E, 0.74/0.76 slack). **This adds one row and one
  case beyond the plan's arithmetic** (see counts).

This is a deviation from "do not change the expectation to match the code" taken deliberately: the measured number
is preserved and asserted; only the reason name changed, for a stated geometric cause, and the owner/orchestrator
should confirm they accept it.

## Corpus verdicts beside research's measured expectation

All at the shipped config (E = 5.5). "Expected" is the plan/research value; "Got" is this implementation.

| Row | Point | Expected | Got |
|-----|-------|----------|-----|
| flat room: floor spot, 3 from spawn | (4, 0.5, 4) | ok | ok |
| flat room: 8.7 up (added) | (4, 8.7, 4) | n/a (new) | OutOfReach |
| pit: over the void | (0, -20, 0) | NoFooting | NoFooting |
| sealed room: closet | (0, 0.5, 9) | Unreachable | Unreachable |
| flat room: inside east wall | (13, 5, 0) | Solid | Solid |
| flat room: outside Bounds | (20, 1, 0) | OutOfBounds | OutOfBounds |
| NaN / +inf / -inf in x, y, z (9 rows) | base (4, 0.5, 4) | OutOfBounds | OutOfBounds (all nine) |
| graybox: inside Core | (0, 10, 0) | Solid | Solid |
| graybox: inside east wall | (61, 0.5, 0) | Solid | Solid |
| graybox: under east wall | (61, -0.5, 0) | NoSight | NoSight |
| graybox: above wall top | (61, 25, 0) | Unreachable | Unreachable |
| graybox: floating over south hall | (-20, 14, 44) | NoFooting | NoFooting |
| graybox: shelf centre | (50, 9.0, 59) | OutOfReach | **Unreachable** (disagreement, above) |
| graybox: shelf east edge | (54, 9.0, 59) | OutOfReach | **Unreachable** (disagreement, above) |
| graybox: floor spot | (-55, 0.5, -55) | ok | ok |
| graybox: crate top | (-33, 4.5, 33) | ok | ok |
| graybox: ledge | (-56, 7.0, -4) | ok | ok |

Precedence: outside-Bounds beats inside-solid (OutOfBounds; same point in real bounds is Solid); inside-solid beats
no-sightline (Solid). `REASON_ORDER` deep-equals the literal list. All six reasons are produced by a row.

## Case counts (floors reconciled openly)

- `grep -c '{ name = '` = **25** (floor 24): 6 micro behavioural (5 planned + the OutOfReach row), 9 non-finite,
  10 graybox. Row names and a `FLAT`/`GRAY` constant were shortened because stylua wraps any row over 120 columns
  into a multi-line table and the plan's grep counts single-line rows only (plan defect, see below).
- `--filter corpus.spec`: **36 registered** (floor 34): 25 rows + 2 precedence + 1 REASON_ORDER + 1 coverage +
  5 bake-fault + 1 stability + 1 shelf-thresholds (added). Floors not lowered.
- `--filter config_lock`: 18 registered (floor 13).

## Measurements

- One graybox bake (4 spawns, includes 4 per-spawn re-floods plus the combined flood): **27-29 ms** (three runs,
  14,166 cells). Plan 03-06's time cap baseline.
- One flood: 3.9 ms (11,678 cells reached; all four spawns reach the same region). The per-spawn re-flood is
  therefore about 16 ms of the 28.
- One `check` on a crate-top spot: about 10 microseconds.
- Full suite: 613 passed, 0 failed, 28.9 s.
- `check-guards`: `ok (92 files, 244 requires, 22 guarded roots)` before, `ok (94 files, 256 requires, 23 guarded roots)`
  after. The plan said 20 before; the baseline had already drifted to 22 from earlier waves. The delta of +1 is the
  evidence the new root is live.

## Demonstrated-red mutations (verbatim harness output)

**1. Step-6 empty-seed exclusion removed** (footless spawns still pushed into the re-flood list):
```
FAIL tests/placement/corpus.spec.luau::a spawn with no footing does not ALSO report SpawnDisconnected
     expected 1, got 2
35 passed, 1 failed, 0 todo in 0.55s
```
**2. Forbidden shortcut** (per-spawn re-flood disabled; replaced by "every seed cell has region == 1 in the combined
flood", which appends SpawnDisconnected when false):
```
FAIL tests/placement/corpus.spec.luau::two spawns on two disconnected islands are a SpawnDisconnected fault (D-06)
     expected nil, got table: 0x00005559085b8750
35 passed, 1 failed, 0 todo in 0.51s
```
(a world was returned, so the fault list was empty: the shortcut detects nothing.)

**3. Precedence** (Solid check removed, equivalent to moving it after the sight rule where it is dead for blocked
points). My first attempt at this mutation (Solid reported after the other rules but before the final NoSight)
was too weak: the thin-wall precedence case stayed green because it re-labelled NoSight as Solid. The faithful
mutation:
```
FAIL tests/placement/corpus.spec.luau::flat room: inside the east wall is Solid
     expected Solid, got NoSight
FAIL tests/placement/corpus.spec.luau::graybox: inside the Core is Solid
     expected Solid, got NoFooting
FAIL tests/placement/corpus.spec.luau::graybox: inside the east wall is Solid
     expected Solid, got NoSight
FAIL tests/placement/corpus.spec.luau::a point that is both outside Bounds and inside a solid reports OutOfBounds
     expected Solid, got NoSight
FAIL tests/placement/corpus.spec.luau::a point inside a solid that also has no sightline reports Solid
     expected Solid, got NoSight
FAIL tests/placement/corpus.spec.luau::every corpus verdict is stable at E +- 0.25 (stability)
     flat room: inside the east wall is Solid flips at E = 5.75 (expected Solid, got NoSight)
30 passed, 6 failed, 0 todo in 0.55s
```
**4. Gate 4, stability probe.** The plan's mutation (shelf east edge to the coordinate with d*conn = 5.5) cannot be
performed because the shelf is Unreachable (above); applied to the OutOfReach flat-room row instead, moving it from
y = 8.7 to y = 7.9544 (d = 5.5 exactly):
```
FAIL tests/placement/corpus.spec.luau::every corpus verdict is stable at E +- 0.25 (stability)
     flat room: 8.7 up is OutOfReach flips at E = 5.75 (expected OutOfReach, got ok)
35 passed, 1 failed, 0 todo in 0.51s
```
(The row itself still passed at E = 5.5, so only the stability probe detects a threshold coordinate.)

**5. Reason coverage** (OutOfReach row deleted):
```
FAIL tests/placement/corpus.spec.luau::every reason in REASON_ORDER is produced by at least one corpus case
     no corpus case expects OutOfReach (expected a truthy value, got nil)
34 passed, 1 failed, 0 todo in 0.58s
```
**6. Non-strict height asymmetry** (`EYE_HEIGHT >= REACH_HEIGHT` tightened to `>`):
```
FAIL tests/placement/config_lock.spec.luau::a shared reach and eye height is legal, because it is the configuration research measured
     SpoonPlacement: config requires CAPSULE_HEIGHT > EYE_HEIGHT >= REACH_HEIGHT
17 passed, 1 failed, 0 todo in 0.34s
```
**7. Gate 6, arity** (third parameter added to `check`):
```
FAIL tests/placement/config_lock.spec.luau::check takes exactly two parameters: the world and the point (D-10 / HIDE-07)
     expected 2, got 3
17 passed, 1 failed, 0 todo in 0.35s
```
(The idiom itself is validated first in the same case: `debug.info(function(a, b, c) ... end, "a") == 3`.)

**8. Silent default on nil config:**
```
FAIL tests/placement/config_lock.spec.luau::a nil config is a loud error, never a silent default
     expected function to throw, but it returned normally
17 passed, 1 failed, 0 todo in 0.36s
```
**9. Typecheck on a key rename** (`PICKUP_MARGIN` to `PICKUP_MARGIN_STUDS` in Placement.luau), analyze over tests/placement:
```
tests/placement/config_lock.spec.luau(117,3): TypeError: Table type '{ CAPSULE_HEIGHT: number, ... PICKUP_MARGIN_STUDS: number, ... }' not compatible with type 'PlacementConfig' because the former is missing field 'PICKUP_MARGIN'
```
(plus further `Key 'PICKUP_MARGIN' not found` errors at lines 31, 40, 50, 73, 74, 80.) Every file was restored with `git checkout -- <file>` and the suite re-run green.

## Deviations from Plan

**1. [Rule 1 - Reconciliation] Shelf rows expect Unreachable, not OutOfReach.** See headline. One extra corpus
row (OutOfReach producer) and one extra case (shelf thresholds, asserts research's 6.54 and the range-8.5 ladder row).

**2. [Design] SpawnDisconnected containment means "reaches at least one of the other spawn's seed cells", not all.**
A spawn above a crate seeds several height layers and an unreachable lower layer must not make the spawn count as
disconnected. One fault per unordered pair (links are not symmetric: a drop-off walks one way), carrying the later
spawn's index. The step order is per-spawn floods first, combined flood last, so the grid is left holding the
combined region without a restore step.

**3. [Plan defects]**
- The `grep -c '{ name = '` floor of 24 is incompatible with stylua at column 120 as the rows were specified; it only
  holds if rows stay single-line. Fixed by shortening names and using `FLAT`/`GRAY` constants.
- The precedence mutation as worded ("move Solid after the sight branch, Core and precedence cases both fail") is
  ambiguous: moving it to just before the final NoSight return leaves the precedence case green. Recorded above with
  the faithful form.
- The gate-4 mutation targets a coordinate that is Unreachable, not threshold-sensitive, so it was applied to the
  flat-room OutOfReach row.
- The check-guards "20 before" baseline was stale (22 at the base).
- `--ignore '**/fixtures/**'` is refused in this worktree; analyze was run on `src/server/core scripts` and
  `tests/placement` separately.

## Handoff

**03-06 (graybox spot table):** the thresholds a spot table needs are: shelf spots Unreachable at shipped config (not
OutOfReach), valid only at E >= 6.54 (edge) and, via sight, E >= 12.36 (centre, NoSight in between). Floor, crate-top
and ledge spots are valid. `bake` on the graybox takes about 28 ms; use that as the cap baseline (cap 0.5 s leaves
about 18x headroom). Config bake variants: copy `Placement` with `table.clone`, override, pass to `bake`; the shared
2.5 height is legal through `assertConfig`. `check` allocates one small table per call; its scratch arrays are
module-level, so it is not re-entrant across coroutines but contains no yields.

**03-08 (validator stage):** `boxesOf(root, config)` requires every collidable BasePart to carry `up` (it errors
otherwise; run the structural pass first). `bake` returns `(World?, { BakeFault })` with kinds `BoundsTooLarge`,
`SpawnNoFooting` (carries `spawnIndex`), `SpawnDisconnected` (carries the later spawn's index). A footless spawn
reports exactly one fault (two-spawn case locks it). Bake needs Bounds as an Aabb: centre +/- size/2 from
`Data/Bounds`, spawns from `Data/SeekerSpawns` children positions (the corpus spec has a working `scenarioOf`).
The reason-to-issue-code table beside it must carry the same order comment.

## Known Stubs
None.

## Self-Check: PASSED
SpoonPlacement.luau, corpus.spec.luau, config_lock.spec.luau exist; commits present; full suite 613 passed.
