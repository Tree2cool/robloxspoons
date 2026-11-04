# Phase 3 Gate G2 Report

**Date:** 2026-11-04. **Plan:** 03-10. **Base:** `51c9df2` (all of 03-01..03-09 merged).
**Nature of this document:** a collection of evidence recorded by nine executors plus one fresh chain run by this
plan. The executable half of the evidence is `scripts/verify.luau` and `tests/run.luau`, which anyone can re-run.
The nine-gate table in section 3 is **self-attestation** and must be read as such.

## 1. Verdict

**Gate G2: PASSED**, with named carried debt (section 6), one open owner decision (suite timing) and two blocking
Studio checks that are unsigned (M-08, M-10). Passing G2 means the *automated* half holds; it does not mean Phase 3
can close, because M-08 and M-10 block that and need Studio.

ROADMAP wording: *the validator is green on the reference map and the full corpus, and the maze bake stress test
(worst-case reachability) completes, so the five map builds may be authored.* The two conditions, separately:

- **Condition A, validator green on the reference map and the full corpus.**
  `lune run scripts/maps/validate-map.luau maps/gray-box.rbxm` printed `validate-map: ok (21 spots, 9 seats)`.
  `lune run tests/run.luau --filter corpus` printed `40 passed, 0 failed, 0 todo in 0.58s` (25 reason-coded rows plus
  precedence, REASON_ORDER, coverage, bake-fault, stability and shelf-threshold cases, per 03-05). The per-spot
  result is 21 of 21 authored spots valid under STRICT (D-17), tightest margin 1.438 studs (the two 4-stud crate tops),
  every floor and ledge spot 3.379 (`03-06-SUMMARY.md`).
- **Condition B, the maze bake stress test completes.** 5,193 boxes, 63,001 columns, 102,804 cells, 25,551 reached.
  The capped case (`boxesOf` + bake + 19 checks) measured **0.212 to 0.219 s against a 2.0 s cap, ratio about 0.11,
  about 9x headroom** (`03-07-SUMMARY.md`). `--filter maze` printed `11 passed, 0 failed, 0 todo in 1.48s`.

Fresh chain run by this plan (container, this worktree):

| Command | Result |
|---|---|
| `lune run scripts/verify.luau` | `verify: all 14 automated steps passed in 32.1s`; step 12 (tests) 29.3 s |
| `lune run tests/run.luau` | `657 passed, 0 failed, 0 todo in 29.06s` |
| `--filter placement` | `120 passed, 0 failed, 0 todo in 2.91s` |
| `--filter maps` | `88 passed, 0 failed, 0 todo in 1.55s` |
| `validate-map maps/gray-box.rbxm` | `validate-map: ok (21 spots, 9 seats)` |

### The four ROADMAP success criteria, individually

1. **Corpus accept/reject with a reason.** Met. 25 reason-coded corpus rows over micro-worlds and the graybox,
   covering shelf, inside-a-wall, no sightline and over-a-void, with all six reasons in `REASON_ORDER` produced by at
   least one row (the coverage case went red when the `OutOfReach` row was deleted, 03-05 mutation 5). A spot is valid
   only with a reachable standable cell within effective range and clear sight. **Caveat:** the shelf rows report
   `Unreachable`, not the `OutOfReach` the locked corpus named (accepted departure, finding 2 below).
2. **Same verdict for different body scales.** Met by construction: `SpoonPlacement.check` takes `(world, point)` and
   no avatar argument, locked by `debug.info(SpoonPlacement.check, "a") == 2` (gate 6, red-demonstrated). This proves
   the function cannot depend on a scale; it does **not** prove the canonical capsule bounds real avatars. That is M-09.
3. **Validator fails the build on an unfindable spot; reference map has at least 16 surviving spots.** Met. Eight
   placement issue codes each fire alone on a dedicated fixture (gate 1); the graybox has **21** spots, 5 above the
   minimum, all valid under the real rules.
4. **Gate G2.** Met, per the two conditions above.

## 2. The honest form of the claim

- **The rules are a model of collision, not Roblox's.** Boxes are exact; meshes and CSG contribute blocking-only
  bounding boxes (assumption A4). Phase 5 runs the real hunt in real geometry and is where any divergence is first
  observable.
- **The capsule rests on two platform facts no primary source confirmed** (A2 and A6, V-19). Both feed
  rejecting-biased choices, so being wrong costs map culls rather than unfindable spoons. That is a bound, not a
  proof, and it is M-09.
- **Timings were measured on this container.** CI runners are assumed 2x to 4x slower (A5), which is why the caps
  carry 4x and 20x headroom and why deterministic work counters, not the clock, are the real gate.
- **Slope-allowance erosion is not load-bearing where it ships.** At the shipped `GRID_SIZE = 1.0` it is inert for the
  graybox ramp. See finding 1.

## 3. The nine-gate observation table

**What this table is.** It is **self-attestation**: a transcription of observations that each plan's own summary
recorded. Its acceptance criteria can be satisfied by nine citations that carry no content, so its value is entirely
in the `Observed red` column being a verbatim quoted failure line. *Every `Observed red` cell quotes the harness's
actual failure output, in backticks; a cell that paraphrases is an empty cell, and an empty cell is a finding.* The
executable half of the evidence is `scripts/verify.luau` and `tests/run.luau`, not this table. Nine executors made
these observations on their own mutations; this plan re-ran only gate 9 itself.

| # | Gate | Owning plan | Mutation applied | Observed red (verbatim) | Evidence |
|---|------|-------------|------------------|-------------------------|----------|
| 1 | Issue-code coverage (exact set) | 03-01, 03-08, 03-09 | neuter the rule behind each new code; and separately a validator that emits one stray `MAP_SPAWN_COUNT` | `FAIL tests/maps/validator.spec.luau::rejects: a spot inside the floor slab -> MAP_SPOT_SOLID` / `expected { [1] = "MAP_SPOT_SOLID" }, got { [1] = "MAP_SPOT_NO_SIGHT" }` ; stage skipped: `51 passed, 8 failed`; stray code: exact-set `54 passed, 5 failed` against loosened-to-contains `59 passed, 0 failed` ; 03-09: `FAIL tests/maps/validator.spec.luau::rejects: seats wound anticlockwise -> MAP_SEAT_ORDER` / `expected at least one issue (expected a truthy value, got false)` | `03-08-SUMMARY.md` (eight codes + exactness pair), `03-09-SUMMARY.md` (M1-M5), `03-01-SUMMARY.md` |
| 2 | Maze oracle (positive and negative half) | 03-07 | corridor 3 with the generator refusal removed; flood seeded from a sealed pocket | `FAIL tests/placement/maze.spec.luau::every open maze cell is reached from the spawn (the oracle's positive half)` / `0/3841 open cells reached (bake faulted: SpawnNoFooting: spawn 1 has no standable cell within 8 studs below it) (expected 3841, got 0)` ; counterfactual probe: `sealed-half-only assertion: 0 of 3 sealed cells reached -> would PASS` beside `positive half: 0/3841 open cells reached -> FAILS` ; pocket seed: `0/1217 open cells reached (expected 1217, got 0)` | `03-07-SUMMARY.md` |
| 3 | Time cap (covered across two plans, see note) | 03-06 and 03-07 | tiny cap; empty bake; sealed-pocket flood | 03-06 cap: `bake took 0.06338439200044377 s against a cap of 0.000001 (expected a truthy value, got false)` ; 03-06 empty bake: `graybox did not bake: 4 faults` ; 03-07 cap: `maze work took 0.2118083099994692 s, cap is 0.000001 s (expected a truthy value, got false)` ; 03-07 counter floors: `counters.linkTests = 8, expected above 10000 (expected a truthy value, got false)` | `03-06-SUMMARY.md`, `03-07-SUMMARY.md` |
| 4 | Corpus stability at E +/- 0.25 | 03-05 | a coordinate moved onto its threshold (applied to the flat-room `OutOfReach` row, see note) | `FAIL tests/placement/corpus.spec.luau::every corpus verdict is stable at E +- 0.25 (stability)` / `flat room: 8.7 up is OutOfReach flips at E = 5.75 (expected OutOfReach, got ok)` | `03-05-SUMMARY.md` mutation 4 |
| 5 | Spec-lock: runtime uses shipped values | 03-08 | the `Placement` require in `MapLoader.luau` commented out | plain grep: `PLAIN GREP PASSES (vacuous: the text is still in the file, as a comment)` ; stripped assertion: `FAIL tests/placement/config_lock.spec.luau::the runtime loader injects the shipped placement values (vacuous-pass gate 5)` / `" to contain "local Placement = require(ReplicatedStorage.Shared.Config.Placement)"` / `25 passed, 1 failed, 0 todo` | `03-08-SUMMARY.md` gate 5 |
| 6 | Signature arity lock (D-10) | 03-05 | a third parameter added to `check` | `FAIL tests/placement/config_lock.spec.luau::check takes exactly two parameters: the world and the point (D-10 / HIDE-07)` / `expected 2, got 3` | `03-05-SUMMARY.md` mutation 7 |
| 7 | Ramp connectivity (negative controls) | 03-04, 03-06 | slope limit 24 | 03-04: `FAIL tests/placement/walkgrid.spec.luau::ramp at the shipped config: the ledge is in the spawn's region` / `ledge: region at probe (-48, 6.999979562793435, 0) (expected 1, got 0)` ; 03-06 (control override changed 24 to 30): `FAIL tests/placement/graybox_spots.spec.luau::at MAX_SLOPE_DEGREES 24 the ramp does not connect and the four ledge spots fail` / `Spot18 still passes with a 24 degree slope limit (expected a falsy value, got true)` | `03-04-SUMMARY.md` mutation 1, `03-06-SUMMARY.md` mutation 1 |
| 8 | Snapshot shape parity (**weaker than its name**, see note) | 03-01 | `node.canCollide = part.CanCollide == true` deleted from `scripts/maps/snapshot.luau` | `FAIL tests/maps/graybox.spec.luau::both snapshotters emit the identical Node key set (must_have 1)` / `12 passed, 5 failed, 0 todo in 0.79s` ; also `MAP_NODE_BASIS_INVALID ... a BasePart node must carry canCollide (contract version 2)` | `03-01-SUMMARY.md` mutation 3 |
| 9 | Typecheck over new files | 03-10 (this plan) | deliberate type error in a new `src/` file and a new `tests/` file | `src/server/core/SpoonPlacement.luau(414,1): TypeError: Expected this to be 'number', but got 'string'` / `analyze: FAILED: luau-lsp exited 1` ; `tests/placement/obb.spec.luau(2,1): TypeError: Expected this to be 'number', but got 'string'` / `analyze: FAILED: luau-lsp exited 1` | this report, section 3a |

**Row notes, none of which soften the table:**

- **Gate 1 value was measured, not assumed.** With a validator emitting one stray code, the exact-set form fails 5
  cases while a "contains" form passes **59 of 59** (`03-08-SUMMARY.md`). That number is the justification for the
  exact-set convention across the eight `MAP_SPOT_*`/bake-fault fixtures, and 03-09 carried the same convention.
- **Gate 2 has the strongest evidence in the phase.** 03-07's scratch probe shows both halves side by side:
  `sealed-half-only assertion: 0 of 3 sealed cells reached -> would PASS` and `positive half: 0/3841 open cells reached
  -> FAILS`. The first line is the vacuous assertion passing; the second is the positive half catching it. The
  counterfactual is the evidence.
- **Gate 3 is demonstrated, but NOT by the plan that owned it.** 03-06 found it could not exercise the counter floors:
  `bake` refuses an empty world with 4 faults before the floors are reached, so its mutation went red at
  `bakedWorld`, not at a floor. 03-07's sealed-pocket mutation **did** exercise them (`counters.linkTests = 8,
  expected above 10000`). The tiny-cap half is shown on both maps. Recorded as covered across plans, with both halves
  named; it is not a clean tick on 03-06. 03-07 also notes the cap does not detect a wrong flood: the oracle and the
  counter floors do, which is the intended division of labour.
- **Gate 4's planned mutation could not be performed.** Its target was the shelf east edge, which is `Unreachable`, not
  threshold-sensitive (finding 2). 03-05 applied it to the flat-room `OutOfReach` row at d = 5.5 exactly. That row
  still passed at E = 5.5, so only the stability probe detected the threshold coordinate.
- **Gate 8 is shallower than its row suggests, and no CI arrangement closes it.** The CI snapshotter gets a real
  key-set comparison. The runtime side (`MapLoader`) gets only a comment-stripped source check that `node.<field>`
  appears. **A field assigned under the wrong condition in `MapLoader` would not be caught.** `MapLoader` reads a live
  `ServerStorage` tree through Roblox APIs and cannot run under Lune, so there is no CI context in which both
  snapshotters receive the same input, and nothing compares the **values** they emit. 03-01 reached this from the
  implementation and the plan-checker reached it independently from the plan text. The gate proves `MapLoader`
  mentions every field and the CI Node carries every field; it does not prove `MapLoader`'s `canCollide` means what
  `snapshot.luau`'s does. **Value-level parity is unobserved. `M-10` is the only check that closes it.**
- **Gate 7's value in practice:** the grid-4 control survives 16 of 21, not the plan's 17 (finding 3).

### 3a. Gate 9 demonstration, this plan's own output

Phase 1's trap: `luau-lsp` exits 0 when its sourcemap fails to load, so a green typecheck is not evidence of analysis.
Closed here by demonstration. `sourcemap.json` contains entries for `Obb`, `Placement`, `SpoonPlacement` and
`WalkGrid` (one `"name"` occurrence each). A first attempt appended the probe after the files' trailing `return` and
produced `SyntaxError: Expected <eof>, got 'local'`, which is also red but not a type error, so it was redone with the
line inserted before the return (src, line 414) and at line 2 (tests). Probe line: `local gate9Probe: number = "not a number"`.

```
### BASELINE            analyze: ok / exit=0   (roblox platform src; standard platform src/server/core scripts; standard tests/placement)
### MUTATED src/server/core/SpoonPlacement.luau (roblox platform)
src/server/core/SpoonPlacement.luau(414,7): LocalUnused: Variable 'gate9Probe' is never used; prefix with '_' to silence
.../src/server/core/SpoonPlacement.luau [game/ServerScriptService/Server/core/SpoonPlacement](414,1): TypeError: Expected this to be 'number', but got 'string'
analyze: FAILED: luau-lsp exited 1
### MUTATED src/server/core/SpoonPlacement.luau (standard platform, pure zones)
src/server/core/SpoonPlacement.luau(414,1): TypeError: Expected this to be 'number', but got 'string'
analyze: FAILED: luau-lsp exited 1
### MUTATED tests/placement/obb.spec.luau
tests/placement/obb.spec.luau(2,1): TypeError: Expected this to be 'number', but got 'string'
analyze: FAILED: luau-lsp exited 1
### RESTORED           analyze: ok / exit=0 for all three; git status clean
```

**Worktree limitation, stated:** the `--ignore "**/fixtures/**"` glob is refused inside a worktree, so analyze was run
per directory (`src` on the roblox platform; `src/server/core scripts` and `tests/placement` on the standard
platform) rather than the repo-wide form `verify.luau` uses. Wave 4 merged with two type errors in `scripts/maps/` for
exactly this reason, caught only by the post-merge chain. `verify.luau` itself, which does use the repo-wide form,
was green in this worktree (steps 8 and 9 `ok`). The probes were not committed.

## 4. Measured numbers

| Quantity | Value | Source |
|---|---|---|
| Graybox spots | 21 authored, 21 valid (14 floor, 1 at y 2, 2 crate tops, 4 ledge); minimum 16 | 03-06 |
| Graybox margins (effective range 5.5) | floor/ledge 3.379; Spot17 1.964; crate tops (Spot06, Spot16) 1.438 | 03-06 |
| Graybox bake counters | boxes=41 columns=15376 spans=15764 cells=14146 reached=11642 linkTests=11638 eroded=1246 | 03-06 |
| Graybox bake time | 28-29 ms in isolation; load+bake+21 checks 0.030-0.072 s against 0.5 s cap | 03-05, 03-06 |
| Maze fixture | footprint 248, 4 levels, corridor 6; 5,193 boxes; 63,001 columns; 244,036 spans; 102,804 cells; 25,551 reached; linkTests 25,553; eroded 68,616; 1,217 open and 8 sealed cells | 03-07 |
| Maze wall clock | 0.212-0.219 s of 2.0 s cap, ratio about 0.11; bake+flood alone 0.226 s | 03-07 |
| `slope 24` control | 17 of 21 survive; ledge Spot18-21 `Unreachable` | 03-06 |
| `grid 4` control | **16** of 21 survive (Spot16 and Spot18-21 `Unreachable`) | 03-06 |
| `clearance 0.5` control | 0 of 21 survive; 0.49 gives 21 | 03-06 |
| shared reach/eye height 2.5 | 19 of 21 survive (Spot06 and Spot16 `NoSight`) | 03-06 |
| Validator fixture slack | OutOfReach 8.0-9.45 (fixture 8.75); NoSight half-width flips near 3.45 (fixture 3.0); underside 0.80-2.80 NoSight (fixture 1.5) | 03-08 |
| Issue codes | 23 (13 at start of phase, 21 after 03-08, 23 after 03-09) | `MapContract.ISSUE_CODES` |
| Test counts | 657 passed, 0 failed, 0 todo (517 after 03-01) | this run |
| Guarded roots | 23 | 03-05/03-09 |

### Suite wall clock (OPEN OWNER DECISION, not accepted)

| Point | Full suite |
|---|---|
| Phase 1 baseline | 15.94 s |
| Phase 2 close | about 25-26 s (owner-accepted departure, STATE.md) |
| Phase 3 wave 1 | 26.7 s |
| Phase 3 wave 2 | 29.6 s |
| Phase 3 now (this run) | **29.06 s** `tests/run.luau`; **32.1 s** for the whole `verify.luau` chain (orchestrator measured about 28.4 s and about 31.9 s on its run; the two agree to within run-to-run noise) |

That is roughly **1.8x Phase 1's baseline**, and a second overshoot beyond the one the owner accepted for Phase 2.
**The owner has not been asked about this one.** It needs an explicit accept-or-trim decision before phase close.
It is not recorded as accepted here. The bake cost is bounded by D-09's cap, but 03-07's maze generation, the maze
spec (1.48 s) and the repeated validator bakes (about 28 ms each, 03-08 estimated 0.2 s extra in `validator.spec`)
all add to it; the dominant cost is older suites, so a trim decision would need a profile, which this plan did not take.

## 5. Phase 7a authoring handoff

- **Constants** live in `src/shared/Config/Placement.luau` (injected, never imported by gameplay code): `GRID_SIZE 1.0`,
  `STEP_UP 1.0`, `MAX_SLOPE_DEGREES 30`, `CAPSULE_RADIUS 1.5`, `CAPSULE_HEIGHT 7.0`, `REACH_HEIGHT 2.5`,
  `EYE_HEIGHT 4.0`, `SPOT_CLEARANCE 0.25`, `PICKUP_RANGE 7.0`, `PICKUP_MARGIN 1.5`. Effective range E = 5.5.
  `MAX_BAKE_COLUMNS` lives in `src/server/core/SpoonPlacement.luau`.
- **Two capsule-implied authoring rules:** **no walkable ceiling below 7 studs** (`CAPSULE_HEIGHT`), and corridors at
  least `2 * CAPSULE_RADIUS + GRID_SIZE` = **4.0 studs** wide. This second rule is sufficient, not exact: a width-3 gap
  erodes to nothing only when its faces sit on lattice centre lines (03-04); off the lattice a width-3 gap can
  survive at `GRID_SIZE` 1.
- **Bake-size ceiling: `MAX_BAKE_COLUMNS = 250000`.** As a footprint, at `GRID_SIZE` 1 that is roughly a
  **500 x 500-stud** `Bounds` (500 x 500 = 250,000 columns). A `Bounds` past it is refused outright with
  `MAP_BOUNDS_TOO_LARGE` before the bake allocates anything. Reference points: the graybox is **15,376** columns and
  the maze stress fixture **63,001** (the plan's 61,504 was a planning-time estimate; 03-07 measured 63,001). A 600-stud
  map would be 360,000 columns and would be refused.
- **Bake budget / performance target:** the maze's measured **~5,200 boxes and ~0.25 s bake** (0.226 s bake+flood,
  0.212-0.219 s full capped case) is the target to stay under. `MAX_BAKE_COLUMNS` is about 4x above the maze's column
  count. CI cap for the maze is 2.0 s and for the graybox 0.5 s; runners are assumed 2x to 4x slower.
- **Model floors as block-shaped `Part`s.** A `MeshPart` or a CSG union contributes a blocking-only bounding box and
  yields `NoFooting` (assumption A4).
- **Keep at least 1 stud of slack on both sides of any threshold.** The 03-06 margin table is the worked example. The
  tightest fixture dial in the validator suite is the overhang half-width: its flip is near **3.45**, where the
  derivation said 3.62, so the derivation was optimistic and must not be reused as an exact figure.
- **`validate-map` is the author's loop:** `lune run scripts/maps/validate-map.luau <map>` prints
  `<CODE> <path> <message>` per issue.
- **The 23 issue codes:** `MAP_BOUNDS_INVALID`, `MAP_BOUNDS_TOO_LARGE`, `MAP_META_INVALID`, `MAP_MISSING_FOLDER`,
  `MAP_MISSING_PART`, `MAP_NODE_BASIS_INVALID`, `MAP_OUT_OF_BOUNDS`, `MAP_ROOT_INVALID`, `MAP_SCRIPT_FORBIDDEN`,
  `MAP_SEAT_COUNT`, `MAP_SEAT_FACING`, `MAP_SEAT_NAME`, `MAP_SEAT_ORDER`, `MAP_SPAWN_COUNT`,
  `MAP_SPAWN_DISCONNECTED`, `MAP_SPAWN_NO_FOOTING`, `MAP_SPOT_COUNT`, `MAP_SPOT_NO_FOOTING`, `MAP_SPOT_NO_SIGHT`,
  `MAP_SPOT_OUT_OF_REACH`, `MAP_SPOT_SOLID`, `MAP_SPOT_UNREACHABLE`, `MAP_TAG_OUTSIDE_FOLDER`.
- **Shelf-style spots (top surface cut off from the floor) report `MAP_SPOT_UNREACHABLE`, not `MAP_SPOT_OUT_OF_REACH`.**
  `OutOfReach` is produced only when no standable cell of any region lies within E.
- **Seats** must wind clockwise, one step strictly inside (0, 180) degrees, nine steps summing to 360 within 1 degree,
  and each face the `TableAnchor` within 5 degrees (`MAP_SEAT_ORDER`, `MAP_SEAT_FACING`, 03-09).
- Do not paste real shipped-map spot coordinates into public documents (T-3-62).

## 6. Carried debt and what this phase did not close

Verbatim, not inferred.

1. **Runtime/CI snapshot VALUE parity is unverifiable in CI, and it is `M-10`.** Gate 8 compares the runtime
   snapshotter by substring over comment-stripped source and the CI snapshotter by key set; the two are never fed the
   same input and their emitted values are never compared. `MapLoader` cannot run under Lune, so no CI arrangement
   closes this. It is carried as a manual gate, not left implied by a green key-set comparison. The residual risk is
   CI and the live game disagreeing about whether a spoon is findable. It is bounded because `MapLoader` runs the same
   `MapValidator.validate` over its own snapshot at load time against the same `Config.Placement`, so a value-level
   divergence large enough to change a verdict shows up as a validation failure naming an issue code in Studio.
   **A divergence too small to change any verdict on the 21-spot graybox would not be seen.**
2. **`M-10`** (load the v2 21-spot graybox through `MapLoader` in Studio) is unsigned and needs Studio. Blocking.
3. **`M-08`** (the place's `CharacterMaxSlopeAngle` at or above 30) is unsigned and needs Studio. Blocking.
4. **`M-06` is signed, but its observation was made against the ContractVersion 1 18-spot map.** 03-06 struck the old
   counts in the file's own `~~18~~ **21**` convention and left the signature line byte-for-byte untouched. Do not read
   M-06's tick as covering the v2 map; `M-10` is the re-run, including the `Data`/`GrayBox`-absent-from-`Workspace`
   check that M-06's note records as never having been eyeballed.
5. **`M-09`** (the reference capsule at the avatar scale extremes) is unsigned and needs a full-roster playtest. Not
   blocking Phase 3.
6. **Phase 5 landmine: `RaycastParams.RespectCanCollide` defaults to `false`, the OPPOSITE of D-03.** Phase 5's
   line-of-sight raycast must set it to `true`, or CI and the live game will disagree about what blocks sight and a
   spot the validator passed can hide a spoon in play. One line, invisible until it bites.
7. **Phase 5 must consume the same `EYE_HEIGHT` and `PICKUP_RANGE`** from `src/shared/Config/Placement.luau`, measured
   from the same root point, or the shared name means nothing.
8. **Phase 6 must keep the baked `world` server-side and rate-limit `check` at the gateway.**
9. **Slope-allowance erosion is inert at the shipped `GRID_SIZE = 1.0`** (finding 1). It is correct, tested at
   `GRID_SIZE 0.5`, and must never be cited as the reason the ramp connects the ledge. The real reason is the
   30-degree slope limit against the ramp's 24.9 degrees.
10. **Suite timing is an open owner decision** (section 4). Not accepted.
11. **Gate rows left incomplete:** none are empty. Gates 3, 4 and 8 carry qualifications recorded above rather than
    clean ticks; gate 8's is the structural limit in item 1.

### Findings carried into the permanent record

1. **Slope-allowance erosion inert at the shipped grid.** 03-04's own test could not detect the allowance being
   deleted (no FAIL line at all). A discriminating pair at `GRID_SIZE 0.5` was added and the original labelled
   non-discriminating. Correct and tested, not load-bearing where it ships.
2. **Accepted departure: the two shelf corpus rows report `Unreachable`, not `OutOfReach`.** Measured value unchanged
   (6.538 against research's 6.54); only the label moved, because the shelf top carries its own standable cells 2.12
   away, inside E but region 0. Research used "REACH" as a coarse bucket that predates D-12's six-reason taxonomy.
   Corroborated at a second operating point (`PICKUP_RANGE 8.5`: shelf edge ok, shelf centre `NoSight`). Accepted by
   the orchestrator in writing.
3. **The grid-4 negative control is 16 survivors, not the plan's 17.** Spot16 (east hall crate top) also goes
   `Unreachable`. 03-06 asserted 16 exactly and recorded the plan as defective rather than widening the assertion.
4. **"A comment that names the thing a grep forbids" bit four times:** a plan snippet's own comment; 03-02's `require`
   floor; 03-05's `Config/Placement` comment (caught by 03-08); and 03-08's own sweep. Rule: a grep gate over raw
   source is only sound if nothing in the file may describe what it searches for. Prefer `lex.stripComments`.
5. **Nine assertions structurally incapable of firing were found this phase:** three by the plan-checker across three
   passes, six by executors. This is the headline process finding. Phase 2 found about 22, so the pattern recurs even
   when everyone is looking for it.
6. **`MAP_NO_SIGHT`'s overhang half-width flips at about 3.45 where the derivation said 3.62.** The fixture is fine at
   `w = 3`; the derivation was slightly optimistic. Do not reuse as exact.
7. **Line numbers and repo-wide counts quoted in plans went stale twice** (guarded roots 20 to 22 to 23;
   `graybox.spec` `validate(` sites 2 to 3). Locate by pattern at execution time.
8. **CI suite timing is an open owner decision.** See section 4.

## 7. Mutations recorded elsewhere in the phase (not gate rows)

03-02: three config mutations (`GRID_SIZE = 4.0`, `SPOT_CLEARANCE = 0.5`, `PICKUP_RANGE = 8.0`), the third caught by
the `E == 5.5` equality before the slack assertions. 03-03: swapped slab test, flipped normal sign, anti-vacuity
shift. 03-04: dropped link condition 3 and a generator floor that caught over-partitioning. 03-05: precedence, empty
seed exclusion, forbidden shortcut, reason coverage, silent default. 03-09: M3 (sum-to-360 load-bearing), M4 and M5
(tolerance bounded both ways).

---

## Owner sign-off

**Gate G2: PASSED (owner, 2026-11-04).**

Phase 7a may author the five map builds against the rules in section 5.

### What the owner verified directly

Both blocking manual checks were observed in one Studio session on `build/spoons.rbxl`, and both
are recorded with their readings in `MANUAL-CHECKS.md`:

- **M-08 — PASSES.** `StarterPlayer.CharacterMaxSlopeAngle = 89`, against the `MAX_SLOPE_DEGREES = 30`
  requirement. 59 degrees of headroom, and the value is the platform default with no project override.
- **M-10 — PASSES.** `[Spoons] map loaded: GrayBox` with **no `MapValidator` error**;
  `ServerStorage.Maps.GrayBox` present with `Geometry` and `Data`; `Workspace` held `Geometry` only;
  `CollectionService:GetTagged("SpoonDefaultSpot")` returned **21**.

**M-10's clean load is the evidence that closes gate 8's named structural gap** as far as it can be
closed. `MapLoader` ran the same `MapValidator.validate` over its **own** snapshot of the live tree
against the same `Config.Placement` values, so any value-level disagreement between the runtime and
CI snapshotters large enough to change a verdict would have surfaced here as a validation failure
naming an issue code. It did not. CI compares their key sets only, and no CI arrangement can do more.

**The anti-ESP property has now been observed directly for the first time.** `Data` and `GrayBox`
were both absent from `Workspace`; only `Geometry` was cloned. M-06's own note recorded that this
had never been eyeballed. `CrateNorthEastRoom` appearing in `Workspace.Geometry` independently
confirms the session ran against the ContractVersion 2 map, since plan 03-06 added that crate for
the fourth spot height.

### Decisions taken at sign-off

- **CI suite timing: ACCEPTED as a second approved departure.** 15.94 s (Phase 1) -> ~25-26 s
  (Phase 2, accepted) -> **29.9 s** (Phase 3), with the `verify.luau` chain at **32.6 s**. Nothing
  was trimmed to reach it: the 21-spot graybox bake, the maze oracle, the differential fuzzes and
  all nine gate mutations are intact, and the quick runs stay fast (`--filter placement` 2.91 s,
  `--filter maps` 1.55 s), so per-task feedback is unharmed. Recorded the way Phase 2's overshoot
  was — measured, dated and approved rather than silent. **Phase 4 should expect to revisit it**, as
  it adds the most test weight of any remaining phase.
- **Section 5's Phase 7a authoring rules were reviewed and stand**, including "no walkable ceiling
  below 7 studs", "corridors at least 4.0 studs wide" and "model floors as block-shaped Parts,
  because a MeshPart yields no footing".

### What remains open, carried not closed

- **M-09** (the reference capsule at the avatar scale extremes) is **not blocking** and needs a
  full-roster playtest in Phase 4/6. It is the human gate under **V-19**, the phase's one genuinely
  soft claim: the per-axis avatar scale limits, the R15 default `HipHeight` and any camera-height
  formula were never found in primary documentation. Until it is signed, **D-11's bias toward
  rejecting is the mitigation, not a verification.**
- **M-07** (simulator human-model calibration) is Phase 2's and is unaffected by this phase.
- The three things Phase 5 must not rediscover stand as written in section 6, chief among them that
  **`RaycastParams.RespectCanCollide` defaults to `false`** — the opposite of this phase's collision
  model (D-03).
