---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 08
subsystem: map-validator
tags: [validator, placement, issue-codes, spec-lock, MAP-02, MAP-03, HIDE-06]
requires: [03-05, 03-06, 03-07]
provides:
  - "MapValidator.validate(root, placement) with a placement stage after the structural pass"
  - "ISSUE_CODES 13 -> 21, each new code with a fixture that emits it alone"
  - "gate 5: comment-stripped source lock on the runtime config injection"
affects: [03-09, 03-10]
key-files:
  modified:
    - src/server/core/MapContract.luau
    - src/server/core/MapValidator.luau
    - src/server/core/SpoonPlacement.luau (one comment reworded, see Deviations)
    - src/server/services/MapLoader.luau
    - scripts/maps/validate-map.luau
    - tests/maps/validator.spec.luau
    - tests/maps/graybox.spec.luau
    - tests/placement/config_lock.spec.luau
decisions:
  - "Spot and spawn paths are carried in parallel lists (defaultSpotPaths, seekerPaths) rather than reusing `anchors`: fewer changed lines."
  - "One table.sort, moved to after the placement stage, so the merged list is totally ordered."
metrics:
  tasks: 3
  tests: "648 passed, 0 failed, 0 todo (was 613 after 03-05); verify 14/14"
---

# Phase 3 Plan 08: Placement stage in the validator Summary

`validate(root, placement)` asserts the config, runs the structural pass, and only if that is clean bakes
the world once and reports one issue per bake fault and one per failing default spot through a total
reason-to-code table. Both callers inject the shipped numbers; the runtime one is locked from
comment-stripped source.

Commits: `6e87ab0` (task 1), task 2 and task 3 follow it on the branch (`git log --oneline 415339b..HEAD`).

## Results against the graybox

`validate-map maps/gray-box.rbxm` prints `validate-map: ok (21 spots, 9 seats)`. No stage change was
needed to get there, as 03-06 predicted.

## Gate 1: eight demonstrated-red mutations (verbatim harness output)

Each mutation neuters the rule that emits the code (spot reasons: the `return reject(...)` in
`SpoonPlacement.check`; bake-fault codes: the `report(...)` call in `MapValidator`). Suite filter
`validator.spec`. Every one restored afterwards.

```
MAP_SPOT_SOLID          FAIL tests/maps/validator.spec.luau::rejects: a spot inside the floor slab -> MAP_SPOT_SOLID
                             expected { [1] = "MAP_SPOT_SOLID" }, got { [1] = "MAP_SPOT_NO_SIGHT" }
                        58 passed, 1 failed, 0 todo in 0.62s
MAP_SPOT_NO_FOOTING     FAIL tests/maps/validator.spec.luau::rejects: a spot 20 studs above the floor -> MAP_SPOT_NO_FOOTING
                             expected { [1] = "MAP_SPOT_NO_FOOTING" }, got { [1] = "MAP_SPOT_OUT_OF_REACH" }
                        58 passed, 1 failed, 0 todo in 0.56s
MAP_SPOT_OUT_OF_REACH   FAIL tests/maps/validator.spec.luau::rejects: a spot 8.75 studs above the floor, past E but inside PICKUP_RANGE -> MAP_SPOT_OUT_OF_REACH
                             expected { [1] = "MAP_SPOT_OUT_OF_REACH" }, got { [1] = "MAP_SPOT_UNREACHABLE" }
                        58 passed, 1 failed, 0 todo in 0.62s
MAP_SPOT_UNREACHABLE    FAIL tests/maps/validator.spec.luau::rejects: a spot inside a sealed box -> MAP_SPOT_UNREACHABLE
                             expected { [1] = "MAP_SPOT_UNREACHABLE" }, got { [1] = "MAP_SPOT_NO_SIGHT" }
                        58 passed, 1 failed, 0 todo in 0.56s
MAP_SPOT_NO_SIGHT       (return reject("NoSight") -> return { ok = true })
                        FAIL tests/maps/validator.spec.luau::rejects: a spot tucked under an overhang -> MAP_SPOT_NO_SIGHT
                             expected at least one issue (expected a truthy value, got false)
                        58 passed, 1 failed, 0 todo in 0.59s
MAP_SPAWN_NO_FOOTING    FAIL tests/maps/validator.spec.luau::rejects: a seeker spawn with no footing -> MAP_SPAWN_NO_FOOTING
                             expected at least one issue (expected a truthy value, got false)
                        58 passed, 1 failed, 0 todo in 0.54s
MAP_SPAWN_DISCONNECTED  FAIL tests/maps/validator.spec.luau::rejects: two spawns on disconnected slabs -> MAP_SPAWN_DISCONNECTED
                             expected at least one issue (expected a truthy value, got false)
                        58 passed, 1 failed, 0 todo in 0.56s
MAP_BOUNDS_TOO_LARGE    FAIL tests/maps/validator.spec.luau::rejects: a Bounds larger than the bake ceiling -> MAP_BOUNDS_TOO_LARGE
                             expected at least one issue (expected a truthy value, got false)
                        58 passed, 1 failed, 0 todo in 0.57s
```

Each mutation failed exactly its own case and no other (1 failed of 59). The first four also show the
reason cascade working: with a rule removed, the spot falls through to the next reason, which is the locked
order doing its job.

**Skip the whole stage** (`if false and #issues == 0 and box ~= nil then`): `51 passed, 8 failed`. The eight
failures are exactly the eight new fixtures, each `expected at least one issue (expected a truthy value, got
false)`. Plan asked for at least five.

**Gate 1 exactness.** With the validator additionally emitting a stray `MAP_SPAWN_COUNT` beside every
placement issue:

```
exact-set assertion:   54 passed, 5 failed   (e.g. expected { [1] = "MAP_SPOT_SOLID" }, got { [1] = "MAP_SPAWN_COUNT", [2] = "MAP_SPOT_SOLID" })
loosened to contains:  59 passed, 0 failed
```

So the exact-set form catches a validator that rejects for one right reason and one wrong one, and a
"contains" form is blind to it. All eight new fixtures were already surgical on first run (no fixture
needed adjusting, no extra codes appeared), so this mutation, not a fixture bug, is the evidence.

## Gate 5: comment-stripped source lock, both forms side by side

`MapLoader.luau` line 26 commented out (`-- local Placement = require(ReplicatedStorage.Shared.Config.Placement)`):

```
plain grep -q 'local Placement = require(ReplicatedStorage.Shared.Config.Placement)' src/server/services/MapLoader.luau
    -> PLAIN GREP PASSES (vacuous: the text is still in the file, as a comment)

lune run tests/run.luau --filter config
    FAIL tests/placement/config_lock.spec.luau::the runtime loader injects the shipped placement values (vacuous-pass gate 5)
         expected " \            <- the harness then dumps the whole comment-stripped MapLoader source (comments blanked, no Placement require); elided here
         ...
         " to contain "local Placement = require(ReplicatedStorage.Shared.Config.Placement)"
    25 passed, 1 failed, 0 todo
```

Restored: 26 passed. The stripped assertion went red where the plain grep stayed green, which is the
distinction the gate exists to prove.

**validate-map demonstrated red:** removing the `Placement` argument gives, from
`analyze.luau --platform standard scripts`:
`scripts/maps/validate-map.luau(40,23): TypeError: Argument count mismatch. Function 'MapValidator.validate' expects 2 arguments, but only 1 is specified`
(plus `ImportUnused: Import 'Placement' is never used`). Restored: `analyze: ok`.

## Observed margins for the five placement fixtures

Measured by sweeping the fixture's own parameter with a throwaway probe (deleted; step sizes 0.05 to 0.25).

| Fixture | Predicted | Observed |
|---|---|---|
| OUT_OF_REACH, spot y = 8.75 | OutOfReach for y in (7.93, 9.40] | `ok` through 7.95, **OutOfReach 8.00 to 9.45**, NoFooting from 9.50. 8.75 is 0.75 above one flip and 0.70 below the other |
| NO_FOOTING, spot y = 20 | flips at ~9.4 | NoFooting from 9.50; 20 is 10.5 studs past the flip |
| UNREACHABLE, roof underside 12 | NoFooting below 7 | NoFooting at 4.0 to 6.75, **Unreachable from 7.00**. Underside 12 has 5 studs of headroom margin |
| NO_SIGHT, half-width w = 3 | w + 1.5 < 5.123 so w < 3.62 | `ok` at w = 1.0, **NoSight 1.3 to 3.4, OutOfReach from 3.5**. Upper limit is nearer 3.45 than 3.62; w = 3 keeps ~0.4 |
| NO_SIGHT, underside 1.5 | blocked while underside < ~2.55 | Solid at 0.75, **NoSight 0.80 to 2.80, ok from 2.85**. Underside 1.5 is 1.35 below the ok flip and 0.7 above Solid |

Half-width stayed at 3; no adjustment. The one place the derivation was optimistic is the NO_SIGHT upper
bound on `w` (3.45 observed against 3.62 derived): the erosion ring is quantised to 1-stud cells. It is
still comfortable at w = 3 but is the tightest margin in the set (0.4 studs on the half-width, which a Phase
7a author sizing an overhang should treat as the binding dial). `Spot2` at (-30, 0.5, 10) beside the overhang
stays `ok`, as predicted.

## Bake cost

Predicted about five extra bakes. Measured `validator.spec`: 0.38 s with the stage skipped (mutation run),
0.54 to 0.65 s with it live: about 0.2 s, consistent with roughly five to seven 28 ms bakes (the positive
cases plus the three nil-world faults, which bake but exit early). A true before/after of the committed
base was not taken. Full suite: 648 passed in 29.3 s; `verify` 14/14 in 32.6 s.

## Deviations from Plan

**1. [Rule 1 - Plan defect] The raw-source sweep failed on correct code.** The task 2 criterion
`grep -rl 'Config/Placement\|Config\.Placement' src/` must list exactly `MapLoader` and `Placement.luau`, but
`SpoonPlacement.luau:46` already carried `src/shared/Config/Placement.luau` in a comment (plan 03-05's own
criterion said that grep must fail, so 03-05 let it slip). Reworded the comment; sweep now lists exactly the
two files. Comment-only change in a gameplay-adjacent file, no behaviour change.

**2. [Plan defect] Call-site line numbers and count.** `graybox.spec.luau` had **three** `validate(` sites
(not two, at lines 175, 253 and 314, not 110 and 229); `validator.spec.luau` had eight at different lines too.
All injected. Sweep `grep -rn 'MapValidator.validate(' tests/ src/ scripts/ | grep -cv 'PLACEMENT\|Placement'`
returns exactly 1, the nil-config line, and `grep 'MapValidator.validate(validSnapshot(), nil :: any)' ... |
grep -cv Placement` returns 1.

**3. [Prompt over plan] Deferred-checks header rewritten here**, not left for 03-09, per the orchestrator's
instruction. It now states what the placement stage covers, lists seat winding and look-at-anchor as the one
remaining item (03-09), and records the Bounds roll item as closed by the `up` vector.

**4. [Rule 3 - typecheck] `verdict.reason :: string` is rejected** (`Reason?` to `string` unrelated cast).
Used `local reason: string = verdict.reason or "OutOfBounds"`. The fallback is unreachable (`ok == false`
always carries a reason); if it were ever hit it would surface as MAP_OUT_OF_BOUNDS, not silence.

**5. Task 2's verify chain** includes `analyze ... --ignore "**/fixtures/**"`, which is refused in a worktree.
Ran analyze per directory instead: `src` (roblox platform), `src/server/core`, `scripts`, `tests/maps`,
`tests/placement`, `tests/harness`, `tests/engine` (standard platform), all `analyze: ok`. Whole-`tests` fails
only on `tests/guards/fixtures/*` (intentional bad fixtures). `scripts/` was touched and typechecked explicitly.
The orchestrator should run the repo-wide form.

**Dead-end noted:** the plan's tdd flag on task 3 implied a red-first order; fixtures went green on first run
because the stage was built in task 1, so red was established afterwards by the nine mutations above.

## Handoff

**03-09 (seat winding):** the structural pass and the placement stage both live in `validate`. Seat checks go
in the structural region (they need `seats[1..9]` and `tableAnchor`, both collected there) so they run before
the placement stage and a winding failure suppresses placement, as any structural issue does. The header
comment's "STILL DEFERRED" block names exactly the item you close; edit it when done (it says plan 03-09 and
to re-home rather than drop). New codes must be declared in `MapContract.ISSUE_CODES` and covered by a fixture
in the same plan, and `t.equal(#MapContract.ISSUE_CODES, 21)` in `validator.spec.luau` is the number to bump.
`validSnapshot()` seats are on a straight line at z = -40 with `TableAnchor` at (0, 3, -40), so seat winding
or look checks will need the baseline's seats rearranged onto a ring first, and any new fixture in this file
now pays a bake only if it passes the structural pass.

**03-10 (G2 report):** gate rows available from here, all with verbatim output above: gate 1 (eight codes plus
skip-stage, plus the exactness pair), gate 5 (stripped assertion vs plain grep). Fixture slack table above is
the one to cite for threshold margins. The tightest is NO_SIGHT's `w`: 3.0 against an observed limit near
3.45.

## Known Stubs
None.

## Threat Flags
None. `validate` gained no I/O; `MapLoader` gained one require of the shipped config.

## Self-Check: PASSED
Files modified exist; commits present on branch; `tests/run.luau` 648 passed 0 failed; `verify.luau` 14/14;
sweep returns 1; `ISSUE_CODES` has 21 entries. STATE.md and ROADMAP.md untouched.
