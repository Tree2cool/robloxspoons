# Phase 3: Placement Rules, Map Pipeline and Validator - Research

**Researched:** 2026-11-04
**Domain:** Pure-Luau geometry (OBB world, multi-layer walkable height field, segment-vs-OBB), Lune `.rbxm` snapshotting, build-time map validation
**Confidence:** MEDIUM-HIGH. The computational findings were measured by a working prototype run against the real `maps/gray-box.rbxm` under Lune 0.11.1. The platform-dimension inputs to the capsule (V-19) are only partly primary-sourced and are labelled.

## How to read the evidence tags

- `[VERIFIED: prototype]` was measured in this session by a scratch prototype (Lune 0.11.1, the committed `maps/gray-box.rbxm`). The prototype is NOT in the repo. Its numbers are reproducible but Wave 0 must re-derive them in real tests.
- `[VERIFIED: lune spike]` was measured by a small Lune script against a serialized-then-deserialized `.rbxm`.
- `[CITED: <url>]` was fetched from the primary source this session.
- `[ASSUMED]` is training knowledge, not verified here. These are collected in the Assumptions Log.

<user_constraints>
## User Constraints (from CONTEXT.md)

Copied from `03-CONTEXT.md`. Decision statements are verbatim; the long rationale sub-bullets are omitted here (read them in `03-CONTEXT.md` lines 29-187 before planning).

### Locked Decisions

- **D-01: One pure-data OBB world; no Roblox API in the rules.** The rules see geometry as oriented bounding boxes built from the `MapContract.Node` snapshot, with our own segment-vs-OBB raycast and walkability math. **One implementation serves CI and runtime**. `src/server/core/` is a pure zone (`check-guards` R3, no suppression mechanism), so `Workspace:Raycast` and `PathfindingService` are not available here. Accepted limitation: this is *our* model of collision, not Roblox's.
- **D-02: `Node` gains an `up` vector; `ContractVersion` goes 1 -> 2.** The third basis vector is the cross product of `look` and `up`. Reuses the existing `LOOK_EPSILON = 1e-3` convention. The graybox is regenerated at v2. It also closes the "Bounds roll" item for free.
- **D-03: `Node` gains `canCollide`; only collidable parts are solid.** Applies to both walkability and line-of-sight.
- **D-04: The rules live in `src/server/core/SpoonPlacement.luau`.** `MapValidator` calls it per default spot; the Phase 5/6 hider check calls the same function. Internal structure (whether geometry primitives split into their own module) is Claude's discretion.
- **D-05: Walkable-grid flood-fill, not `PathfindingService`.** Pure, deterministic, headless.
- **D-06: Reachability is measured from ALL seeker spawns.** A spot is reachable only when its nearby standable cell lies in the connected region containing the seeker spawns. Not from the hider spawn, and not "any largest connected region". A test asserting the four graybox spawns land in one connected region validates the map and the flood-fill at once.
- **D-07: The grid is a multi-layer height field.** A 2D lattice of columns, each holding a **list** of standable heights found by casting down the column; neighbours link when adjacent columns have candidate heights within the step-up limit. A single-height 2D grid and a full 3D voxel grid were rejected.
- **D-08: Gate G2's maze stress fixture is a Lune-generated synthetic adversarial maze.** A generator beside `scripts/maps/generate-graybox.luau`, emitting long corridors, dead ends, maximum walkable-cell count and a deliberately sealed region. Parameterised, so stress level is a dial rather than a guess.
- **D-09: The bake carries a hard CI time cap, asserted by a test.** The cap should be chosen deliberately rather than generously (suite already ~25-26s vs a 15.94s Phase 1 baseline).
- **D-10: One canonical reference avatar capsule, used for every validity test, for every player, in CI and at runtime.** The rule function **takes no avatar argument**, so HIDE-07's scale-invariance is true by construction. A test asserting the signature locks it. OQ-12 is answered: canonical reference avatar.
- **D-11: The capsule is biased toward rejecting — short reach, tall headroom.** Erring toward rejection is the cheap direction.
- **D-12: First match wins over a locked rule order; exactly one reason per spot.** Order: **in-bounds -> standable -> reach -> line-of-sight**. Lock the order the way Phase 2 locked its nine: in the types, in a comment, and in a test.
- **D-13: Injected config + `src/shared/Config/Placement.luau` + a spec-lock test.** `SpoonPlacement` takes a `PlacementConfig` parameter and never imports it; the config module holds the shipped numbers; a spec-lock test asserts the validator and the runtime both run on the shipped values. Follow `CardPool` exactly. A missing or malformed config must be a loud error, never a silent default.
- **D-14: One shared `PICKUP_RANGE` that Phase 5's hunt must consume, but the validator demands margin inside it.** The margin must be a named constant with its own test, not a magic number inside a comparison.
- **D-15: If the real rules cull the graybox below 16, fix the map — never the rules, never the minimum.**
- **D-16: The numeric values are proposed by research with their per-spot consequences, and confirmed by the owner at plan time.** Grid resolution, step-up height, max walkable slope, reach, clearance, pickup range and its margin.

### Claude's Discretion

- Internal structure of `SpoonPlacement` — whether the OBB/raycast/grid primitives split into their own module behind the policy.
- Mesh and CSG handling. Decide a defensible default and record it.
- Whether `ContractVersion` v1 maps are rejected outright or migrated (outright rejection likely correct and cheapest).
- The exact new issue-code names, following the `MAP_` prefix convention and the `MapContract.ISSUE_CODES` coverage-test pattern.
- Grid origin/alignment and how bounds that are not an integer multiple of the resolution are handled.

### Deferred Ideas (OUT OF SCOPE)

- Clamping avatar scaling in the place's avatar settings (hunt-fairness for Phase 5 / tuning for Phase 8).
- Union-of-volumes bounds (D-19 escape hatch; revisit only if the mansion needs it).
- Separate collision and sight sets (glass/foliage); rejected for v1 under D-03.
- `ProximityPrompt.Triggered` unguarded client-to-server paths (a Phase 5 item).

### Scope note (planner must settle explicitly)
Seat winding and seat-looks-at-table are in Phase 1's deferred list but named by none of HIDE-06/07, MAP-02/03. `Bounds` roll closes itself via D-02. See "Scope Question" below for the recommendation.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HIDE-06 | A spot is valid only when a reachable standable position exists within pickup range of it with clear line of sight | Height-field bake + 4-neighbour flood from all seeker spawns + exact segment-vs-OBB LOS; the Number Ladder gives the values; reason order in Architecture |
| HIDE-07 | Placement validity is unaffected by the hider's avatar scale | D-10 canonical capsule; `check(world, point)` has no avatar parameter; arity-lock test via `debug.info` (see Validation Architecture) |
| MAP-02 | Validator runs every default spot through the real placement rules and fails the build on any unfindable | `MapValidator.validate(root, config)` extended after the structural pass; one issue code per reason; strict reading recommended (Open Question 1) |
| MAP-03 | Every map provides at least 16 validated default hiding spots | Graybox survivor counts per candidate set in the Number Ladder; recommended set leaves exactly 16 of 18, so the map must be regenerated with spare spots (D-15) |
</phase_requirements>

## Summary

The phase is tractable and cheap in CI. A multi-layer height field over the graybox bounds (124 x 124) bakes in about 19 ms at 1-stud resolution, floods in 4 ms, and the same code on a synthetic 240 x 240, 4-level, 4,640-box maze bakes in about 0.4 s. The cost is dominated by the bake (per-column span construction), not the flood, and the flood is `O(reached cells)`. Resolution is the only knob that matters for time: 0.5 studs costs about 7-10x more than 1 stud. [VERIFIED: prototype]

The headline findings the owner needs before confirming numbers, all measured against the real graybox:

1. **Eye height must be a separate constant from reach (root) height.** With one shared height the crate-top spot (Spot06) needs an effective range of 8.75 studs, is culled, and the map falls to 15 survivors. With a separate 4.0 eye height it needs 4.06. This is the largest single swing in the ladder.
2. **The shelf is culled, but by two different rules depending on range.** Spot08 (x=50) can never be seen from the floor (the shelf blocks it from below; it needs an effective range of 12.36). Spot09 (x=54) sits on the shelf's east edge, so it is visible from the east at an effective range of 6.54. A pickup range / margin that puts the effective range between 6.3 and 6.8 makes Spot09's verdict a knife-edge.
3. **Honest survivors are 16 of 18 with zero spare.** Any recommended set culls Spot08 and Spot09, leaving exactly `MIN_DEFAULT_SPOTS`. D-15 therefore applies immediately: the graybox must be regenerated with more spots.
4. **Two premises in CONTEXT/`must_haves` are factually off and change the corpus** (see "Corrections to CONTEXT premises"): the "over a void" band is occupied by the perimeter walls, and there are 11 floor spots, not 12. The slope-24 failure drops the map to **12**, not 14, because the two shelf spots are already culled.
5. **V-4 is answered:** `CanCollide`, `UpVector` and `RightVector` all read correctly from a deserialized Part under Lune 0.11.1. Only `Position` has the missing-default problem. D-02 and D-03 need no workaround. [VERIFIED: lune spike]

**Primary recommendation:** Build `SpoonPlacement` as a pure bake-once / query-many module (`bake(boxes, bounds, spawns, config) -> world`, `check(world, point) -> verdict`) over a Recast-style span height field, with 4-neighbour links verified by an exact segment test, slope-allowance erosion, a separate eye height, and a strict per-spot issue code. Adopt the recommended number set below, subject to owner confirmation.

## The Number Ladder (D-16)

**Method.** Every figure below comes from one prototype that implements the proposed rules over the real graybox: vertical-line-vs-OBB span construction, merge, slope test on the exact face normal, headroom, slope-allowance erosion, 4-neighbour links, link verification by exact segment test, BFS from all four seeker spawns, then per-spot minimum distances. [VERIFIED: prototype] All other parameters are held at the Recommended set unless the row varies them.

**How to read the survivor columns.** A spot's verdict is a pure function of three numbers: `d*any` (nearest standable cell of any region), `d*conn` (nearest cell connected to the spawns) and `d*los` (nearest connected cell with a clear sight line). Effective range `E = PICKUP_RANGE - PICKUP_MARGIN`. A spot passes the reach rule when `d*conn <= E` and the sight rule when `d*los <= E`. So one table of `d*` values answers every PICKUP_RANGE question at once.

### Per-spot thresholds (Recommended geometry: reach 2.5, eye 4.0, g=1, step 1.0, slope 30, capR 1.5, capH 7.0)

There are **11 floor spots** (not 12), 1 crate spot, 4 ledge spots, 2 shelf spots.

| Spot | Where | Surface y | d*conn | d*los | Passes when E >= |
|------|-------|-----------|--------|-------|------------------|
| 01,02,03,04,05,07,10,11,12,13,14 | floor, 11 spots | 0 | 2.12 | 2.12 | 2.12 |
| 15,16,17,18 | ledge (reachable only via the ramp) | 6.5 | 2.12 | 2.12 | 2.12, **and the ramp must connect** |
| 06 | on top of `CrateSouthWestRoom` (-33, 4.5, 33) | 4 | 4.06 | 4.06 | 4.06 |
| 09 | shelf east edge (54, 9.0, 59), seen from the east | 8.5 | 6.54 | 6.54 | **6.54** |
| 08 | shelf centre (50, 9.0, 59) | 8.5 | 6.54 | 12.36 | **12.36** (never in practice) |

With reach 3.0 / eye 4.5 the same spots need: floor 2.60, Spot06 3.84, Spot09 6.04, Spot08 11.25. [VERIFIED: prototype]

Why the shelf behaves this way (geometry, verified): the shelf is a 2-deep slab at y 7.5 to 8.5, z 58 to 60, against the south wall. A seeker on the floor below is only 6.0-6.5 studs from the spoon, so the *reach* is fine, but the slab sits between hand and spoon from any approach except the open east end. Spot09 is authored exactly on the east face plane (x=54) so a floor cell at (57, 58) sees it. Spot08 is 4 studs in from that end and is blocked from every floor position within 12 studs.

### Effective-range and PICKUP_RANGE ladder (M = 1.5)

| PICKUP_RANGE | E | Spot06 (crate) | Spot09 (shelf E) | Spot08 (shelf C) | Survivors of 18 | Clears 16? |
|--------------|---|----------------|------------------|------------------|-----------------|-----------|
| 3.5 | 2.0 | cull | cull | cull | 0 (nothing reachable) | no |
| 5.0 | 3.5 | cull REACH | cull REACH | cull REACH | 15 | no |
| 5.5 | 4.0 | cull REACH | cull REACH | cull REACH | 15 | no |
| 6.0 | 4.5 | ok | cull REACH | cull REACH | 16 | zero spare |
| **7.0** | **5.5** | ok | cull REACH (slack 1.04) | cull REACH | **16** | zero spare, **clean separation** |
| 7.5 | 6.0 | ok | cull REACH (slack 0.54) | cull REACH | 16 | zero spare |
| 8.0 | 6.5 | ok | cull REACH (slack **0.04**) | cull REACH | 16 | **knife-edge** |
| 8.5 | 7.0 | ok | ok | cull LOS | 17 | yes, 1 spare |
| 10.0 | 8.5 | ok | ok | cull LOS | 17 | yes |
| 14.0 | 12.5 | ok | ok | ok | 18 | yes (no reasonable hunt uses this) |

[VERIFIED: prototype] Floor and ledge spots never change across this ladder; only the three interesting spots move.

**Recommendation: PICKUP_RANGE 7.0.** It puts E=5.5 where every authored spot is at least 1 stud away from a flip (Spot06 has 1.44 slack, Spot09 has 1.04). Do not use 8.0 with margin 1.5: the verdict on Spot09 flips on a 0.04-stud difference, which is a coin toss decided by float32 rounding.

**Range of defensible values:** 6.0 to 7.5 with M=1.5. Below 6.0 the crate-top spot is culled. Between 8.0 and 8.5 the shelf flips. The owner can pick a larger range if the hunt feel wants it, but the *map* then needs shelf spots that are honestly findable.

### PICKUP_MARGIN (D-14)

| Candidate | Rationale | Verdict |
|-----------|-----------|---------|
| 0.75 | barely above the grid half-diagonal at g=1 (0.707) | too thin; no allowance for movement jitter |
| **1.5** | grid half-diagonal 0.71 + about 0.8 for controller jitter, imperfect footing, server-known position lag | **Recommended** |
| 2.0 | very safe | costs 0.5 stud of usable range everywhere |
| 3.0 | V-23's "few studs" of lag | removes about 40% of a 7-stud range; only if Phase 5 measures large lag |

Drivers: (a) grid quantisation, bounded by `g * sqrt(2) / 2` (0.71 at g=1, 1.41 at g=2, 0.35 at g=0.5); (b) V-23 server-known HRP lag, **LOW confidence** and a Phase 5/8 measurement. **Named constant `PICKUP_MARGIN` with its own test asserting `PICKUP_MARGIN >= gridSize * math.sqrt(2) / 2`**, so a later resolution change cannot silently invalidate it.

### Walkable-grid resolution (g)

| g (studs) | Columns (124 x 124) | Graybox bake + flood | Stress fixture* | Graybox survivors | Notes |
|-----------|---------------------|----------------------|-----------------|-------------------|-------|
| 0.25 | 246,016 | 1.51 s + 0.07 s | far over any cap | 16 | not viable for CI |
| 0.5 | 61,504 | 0.13 s + 0.02 s | 3.8 s | 16 | 4x cost; sampling error 0.35 |
| **1.0** | **15,376** | **0.019 s + 0.004 s** | **0.4 s** | **16** | Recommended; sampling error 0.71 |
| 2.0 | 3,844 | 0.003 s | 0.1 s | 16 (only because step 1.0 >= 0.93) | sampling error 1.41 exceeds a 1.5 margin; thin 2-stud surfaces can fall between samples |
| 4.0 | 961 | 0.001 s | tiny | **11-12** | fails: ramp needs stepUp >= 1.86 |

\*Stress fixture = 240 x 240 footprint, 4 levels, corridor 6, 4,640 boxes. [VERIFIED: prototype]

**Coupling that must be a config invariant:** the ramp rise per cell is `g * tan(slope)`, so `stepUp >= g * tan(maxSlope)` or a legal slope disconnects. Measured minimum stepUp for the 24.9 degree ramp: g=0.5 needs 0.232, g=1 needs 0.464, g=2 needs 0.929, exactly `g * tan(24.9047 deg)`. [VERIFIED: prototype]

**Grid origin:** anchor to the world lattice (`origin = floor(bounds.min / g) * g`), not to `bounds.min`, so cell edges coincide with Studio's integer snap grid. Ledge connectivity held for origin shifts of 0, 0.1, 0.25, 0.37, 0.5 at g=1 and g=2, so the answer is insensitive to alignment on this map. Cells whose centre falls outside Bounds are discarded.

### Step-up height

| stepUp | Survivors | What changes |
|--------|-----------|--------------|
| 0.25, 0.40 | **12** | ramp disconnected (needs 0.464 at g=1); ledge spots 15-18 culled, plus the shelf pair |
| 0.50 | 16 | ramp connects with 0.036 to spare: too thin |
| 0.75 | 16 | |
| **1.0** | **16** | Recommended |
| 1.5 | 16 | |
| 2.0 | 16 | chair tops (y=2) become walkable, the 8 x 8 table top becomes reachable via a chair |
| 4.0 | 16 | crate tops walkable; `CrateSouthWestRoom` stops being a "standable beside" corpus case |

Driver: the platform. Roblox does not document the auto-step height of a Humanoid, so the value is a design choice (Assumption A1). Lower is the rejecting direction (D-11). **Recommend 1.0**, defensible range 0.75 to 1.5; at 2.0 or above, furniture becomes terrain. Note also `stepUp` is not jump: `Humanoid.JumpHeight` defaults to 7.2 studs [CITED: create.roblox.com/docs/reference/engine/classes/Humanoid.md], so real players can jump onto the 6.5 ledge and the 4.0 crates. The flood deliberately does not model jumping (rejecting direction); say so in a comment.

### Max walkable slope

| maxSlope | Survivors | What changes |
|----------|-----------|--------------|
| 15, 20, 24 | **12** (not 14) | ramp (24.9047 degrees) is not walkable; ledge spots 15-18 culled; shelf pair already culled |
| 25 | 16 | passes with a **0.095 degree** margin: float32 rounding in the snapshot (about 1e-5 degrees) is safe, but any authoring change breaks it |
| **30** | **16** | Recommended: 5.1 degrees of margin over the ramp |
| 45, 60 | 16 | admits steeper decor; no effect on the 18 spots |

Driver: the platform default is `Humanoid.MaxSlopeAngle = 89` and `StarterPlayer.CharacterMaxSlopeAngle` defaults to 89 [CITED: create.roblox.com/docs/reference/engine/classes/Humanoid.md, StarterPlayer.md]. So the rule at 30 is stricter than the live game, which is the safe direction. If the owner ever lowers `CharacterMaxSlopeAngle` in the place, it must not go below the rule value (add to MANUAL-CHECKS like M-05). **The ramp angle (24.9047) is computed from `atan(6.5 / 14)`; put that number in a test comment.** The slope test must use the exact face normal of the OBB (`ny >= cos(maxSlope)`), never height differences between grid cells, so it does not depend on resolution.

### Canonical reference capsule (D-10 / D-11)

| Value | Candidates | Recommended | Driver |
|-------|-----------|-------------|--------|
| **Headroom height `capH`** | 5.0, 6.0, 6.5, **7.0**, 7.4, 8.0 | **7.0** | Humanoid-style avatars are about 6 to 6.5 studs [CITED: create.roblox.com/docs/studio/avatar-settings.md]; Pathfinding's default `AgentHeight` is 5 [CITED: PathfindingService.md]. The documented catalog height range is 90 to 105 percent [CITED: web search summary, not re-fetched] so a 6.5 avatar can reach about 6.8. 7.0 covers that. |
| **Radius `capR`** | 0.5, 0.75, 1.0, **1.5**, 2.0, 2.5 | **1.5** | R15 torso is about 2 wide (Assumption A2); Pathfinding default `AgentRadius` is 2 [CITED: PathfindingService.md]. 1.5 adds bias without forcing 4-stud-wide doorways to be culled. |
| **Reach (root) height** | 2.0, **2.5**, 3.0, 3.5 | **2.5** | `Height = 0.5 * RootPart.Size.Y + HipHeight` [CITED: Humanoid.md]; R15 root centre is about 3.0 at scale 1 (A2); the shortest catalog avatar is about 0.9x = 2.7, rounded down to 2.5 for the rejecting bias. Matches the graybox seeker spawns at y=3. |
| **Eye height** | 2.5 (= root), 3.0, 3.5, **4.0**, 4.5 | **4.0** | head centre about 4.5 at scale 1 (A2), x0.9 = 4.05, rounded to 4.0. |

Effect on the 18 spots, at E=5.5 (reach, eye):

| reach / eye | Survivors | Culled |
|-------------|-----------|--------|
| 2.5 / 2.5 (single height) | **15** | Spot06 LOS, 08, 09 |
| 2.5 / 3.0 | 15 | Spot06 LOS, 08, 09 |
| 2.5 / 3.5 | 16 | 08, 09 |
| **2.5 / 4.0** | **16** | 08, 09 |
| 3.0 / 3.0 | 15 | Spot06, 08, 09 |
| 3.0 / 4.5 | 16 | 08, 09 |

[VERIFIED: prototype] **Spot06's line-of-sight requirement is 8.75 / 6.82 / 4.95 / 4.06 studs at eye 2.5 / 3.0 / 3.5 / 4.0.** A spoon on a 4-stud crate cannot be seen from a low root point standing beside it. This is why LOS must originate at a separate eye point; **Phase 5 must use the same `EYE_HEIGHT`** (the server only knows the HumanoidRootPart position, so it will add this constant to it).

`capR` and `capH` change no survivor counts on the graybox (capR 0.5 to 2.5 and capH 5 to 8 all give 16). They matter for shipped maps: `capH` 7.0 means **no walkable ceiling below 7 studs** (the graybox ledge underside at 5.5 is not standable; the shelf underside at 7.5 passes only while `capH <= 7.4`), and corridors need width `>= 2 * capR + g` (4.0 with the recommended values). Both are authoring rules for Phase 7a. [VERIFIED: prototype]

### Reach distance (how far the capsule reaches from a standable position)

This is not an independent constant. It is `PICKUP_RANGE`, measured from the root point (`cell height + reachY`) to the spoon, minus `PICKUP_MARGIN`. There is no separate "arm length". Recommended: **7.0 and 1.5**, as above.

### Clearance radius around a spot (`SPOT_CLEARANCE`)

| Candidate | Survivors | Note |
|-----------|-----------|------|
| 0.25, 0.40, 0.49 | 16 | all pass |
| **0.50** | **0** | every authored spot sits exactly 0.5 above its surface, so a `<=` test culls all 18 |
| 0.6, 1.0 | 0 | same |

[VERIFIED: prototype] The cliff is exactly the authoring convention `anchor y = surface + 0.5`. **Recommend 0.25**, and a config invariant test `SPOT_CLEARANCE < SPOT_SURFACE_OFFSET` where the offset is 0.5. The real driver is the spoon skin template's fixed bounding box (CLAUDE.md rule 4, Phase 7b), which does not exist yet: record that 0.25 is a placeholder to be re-derived when the template lands (A3).

### The recommended set (for the owner to confirm)

| Value | Recommended | Defensible range |
|-------|-------------|------------------|
| Grid resolution | 1.0 | 0.5 to 1.0 |
| Step-up | 1.0 | 0.75 to 1.5 |
| Max slope | 30 degrees | 26 to 45 |
| Capsule headroom / radius | 7.0 / 1.5 | 6.5 to 8.0 / 1.0 to 2.0 |
| Reach (root) / eye height | 2.5 / 4.0 | 2.5 to 3.0 / 3.5 to 4.5 |
| Spot clearance | 0.25 | 0.1 to 0.45 |
| PICKUP_RANGE / PICKUP_MARGIN | 7.0 / 1.5 (E = 5.5) | range 6.0 to 7.5; margin 1.0 to 2.0 |

Three coherent whole-set comparisons, same graybox [VERIFIED: prototype]:

| Set | Parameters | Survivors | Culled |
|-----|-----------|-----------|--------|
| STRICT | g1, step 0.75, slope 25, capR 2.0, capH 8.0, reach 2.5, eye 3.5, clr 0.25, R6/M1.5 (E 4.5) | **15** | Spot06 (needs 4.74 > 4.5), Spot08, Spot09 (shelf cells eroded) |
| **RECOMMENDED** | g1, step 1.0, slope 30, capR 1.5, capH 7.0, reach 2.5, eye 4.0, clr 0.25, R7/M1.5 (E 5.5) | **16** | Spot08, Spot09 (REACH) |
| LENIENT | g0.5, step 1.5, slope 45, capR 1.0, capH 6.0, reach 3.0, eye 4.5, clr 0.4, R10/M1.5 (E 8.5) | **17** | Spot08 (LOS); Spot09 admitted |

**Consequence under D-15:** even the Recommended set leaves exactly 16, with no spare. The graybox must be regenerated in this phase. Suggested map fix: convert the two shelf spots to floor spots in the SE room (keep the shelf geometry: it is the "out of reach" corpus fixture), and add at least 2 and preferably 4 more valid spots so 18 to 20 are authored and every one passes. Do not tune the rules to keep 18.

D-06 sanity check: with the recommended set all four spawns reach the same 11,678-cell region when each is flooded alone. [VERIFIED: prototype]

## Corrections to CONTEXT premises

These do not block any decision but they change what the planner writes. Neither contradicts a locked decision.

1. **"Over a void for free" is wrong.** `must_haves` item 4 and the `<code_context>` say the floor stopping at +-60 inside Bounds of +-62 gives a void. It does not: the four perimeter walls are 2 thick centred at +-61 (`NorthWall` z=-61, depth 2, spans z -62..-60), y 0 to 20. The band x or z in (60, 62) is **solid wall** from y 0 to 20. Only a 1-stud slab beneath the walls (y -1 to 0) and the air above them (y 20 to 29) are empty. Measured verdicts: `(61, 0.5, 0)` = inside solid; `(61, -0.5, 0)` = **no line of sight** (cells 3.94 away exist, the wall blocks them); `(61, 25, 0)` = out of reach (a wall-top cell exists but is disconnected). None of these is a "void" reason. [VERIFIED: prototype + generator source]
   - Under HIDE-06's literal wording a spot is invalid only when no connected standable position is within range with clear sight. So "over a void" has no dedicated reason: a deep void is `NO_FOOTING` (no standable cell within `PICKUP_RANGE`), a shallow pit visible from its rim is legitimately valid. Use `(-20, 14, 44)` (floating 14 above the south hall) for a `NO_FOOTING` corpus case, or add a real pit to the regenerated graybox, or build the void case in a synthetic micro-world (recommended, see Validation Architecture).
2. **Floor spots are 11, not 12.** Heights: 0 x11, 4 x1, 6.5 x4, 8.5 x2. [VERIFIED: generator source]
3. **Slope < 24.9 degrees leaves 12 spots, not 14,** because the shelf pair is culled independently. It fails MAP-03 either way.
4. **"The `PICKUP_RANGE` + reach values alone decide whether the shelf spots are valid" is only half true.** They decide Spot09 (the shelf edge). Spot08 is decided by *line of sight*, not reach, and survives only if E >= 12.36. So the shelf is never both valid and a "shelf out of reach" corpus case at once.

## Verification Debt Re-check

**Host status.** `create.roblox.com` was reachable this run via `curl` through the agent proxy, using the `.md` form of documentation URLs (`https://create.roblox.com/docs/<path>.md`) and `https://create.roblox.com/docs/llms.txt` as an index. The `WebFetch` tool itself failed with `ENOTFOUND create.roblox.com`, so `curl` via Bash was the working path. `devforum.roblox.com` and `robloxapi.github.io` answered HTTP 200 on their root but were not used. `madstudioroblox.github.io`, `jsdotlua.github.io` and `lune-org.github.io` remain unreachable (HTTP 000/403 from the proxy). GitHub repository access via `gh` was refused for `Roblox/creator-docs`. Pages that did not respond (HTTP 502) on the first try: the HTML form of some reference pages. The `.md` form worked.

| ID | Original claim | Status after re-check | Evidence | Confidence |
|----|----------------|----------------------|----------|------------|
| **V-17** | `PathfindingService:ComputeAsync` limitations | **RETIRED by D-05 for this phase.** Confirmed useful facts only: defaults `AgentRadius=2`, `AgentHeight=5`, `AgentCanJump=true`; `ComputeAsync` yields; thread-safety "Unsafe". Used as a cross-check for capsule sizing, not as a dependency. | [CITED: create.roblox.com/docs/reference/engine/classes/PathfindingService.md, Path.md] | HIGH |
| **V-18** | `FindPartOnRay` legacy; use `Workspace:Raycast` | **CONFIRMED, and retired for this phase** (no Roblox raycast in the rules). `WorldRoot:FindPartOnRay` is marked "Deprecated... Use WorldRoot:Raycast()". **Still live for Phase 5.** New and important for Phase 5: `RaycastParams.RespectCanCollide` **defaults to `false`**, so a default `Workspace:Raycast` hits non-collidable parts, which is the opposite of D-03's model. Phase 5's glint line-of-sight must set `RespectCanCollide = true` (and note `CanQuery=false` parts are never hit) or CI and the live game disagree about sightlines. | [CITED: WorldRoot.md lines 121 and 805, RaycastParams.md, BasePart.md CanQuery] | HIGH |
| **V-19** | Server-set character scale via `HumanoidDescription`; effect on reach and camera height | **PARTLY CONFIRMED, upgraded for what was re-fetched.** `HumanoidDescription.HeightScale` etc. map to `BodyHeightScale` NumberValues on the Humanoid when applied through `Humanoid:ApplyDescriptionAsync()`; `Humanoid.AutomaticScalingEnabled` gates whether the six scale values resize parts; Avatar Settings offers "Player Choice" (default) or "Custom Scale" with an absolute height in studs and Minimum/Maximum; classic avatars are about 5 studs, humanoid proportions 6 to 6.5; `HipHeight` formula is documented; `JumpHeight` default 7.2. **Not found in primary docs:** per-axis scale limits (the 90-105 percent height / 70-100 percent width figures came only from a web-search summary), the R15 default `HipHeight` value, any camera-height formula, and the humanoid auto-step height. "Reach" is not a platform concept at all: it is game-defined, which is exactly why D-10's canonical capsule needs no platform fact beyond the envelope. | [CITED: HumanoidDescription.md, Humanoid.md, studio/avatar-settings.md]; limits [web search only] | MEDIUM (docs) / LOW (limits) |
| **V-20** | `StreamingEnabled` and client raycasts for placement preview | **Deferral to Phase 6 is sound.** Streaming applies only to Workspace descendants; `ServerStorage` and `ReplicatedStorage` contents are not streamed; defaults are `StreamingMinRadius = 64`, `StreamingTargetRadius = 1024`; instances stream in/out around the replication focus. This phase's rules run on a snapshot of `ServerStorage.Maps[mapId]`, never on Workspace, so they have no streaming dependence. For Phase 6: the ghost preview is advisory; the server's `check` is authoritative; a 7-stud pickup range is well inside the 64-stud minimum radius. The statement "a client raycast only sees streamed-in parts" is an inference from the docs, not a quoted sentence. | [CITED: create.roblox.com/docs/workspace/streaming.md] | MEDIUM-HIGH |
| **V-4** | Lune reads Roblox model files; CI map-validation workflow | **CONFIRMED and extended for D-02/D-03.** On a part serialized then deserialized under **Lune 0.11.1**: `CFrame.UpVector` and `CFrame.RightVector` read correctly (committed `Ramp`: up = 0.42111206, 0.90701294, 0; right = 0.90701294, -0.42111206, 0); `CanCollide` reads correctly for default-true, explicitly-false and never-assigned parts; `CanQuery`, `CanTouch`, `Anchored`, `Transparency`, `Size` and `CFrame.Position` also read. **Only the derived `Position` property fails** ("missing default value"), as assumption A5 says. Values are float32-quantised (error about 1e-7 on unit vectors) and `LookVector` prints `-0`, which the existing `clean(n) = n + 0` handles. `Part.Shape` reads (`Enum.PartType.Block` / `Ball`), but **a `Ball` Part has className `"Part"`** and `WedgePart` / `MeshPart` have their own classNames. No workaround is needed for D-03. | [VERIFIED: lune spike, Lune 0.11.1] | HIGH |

**Net for the planner:** no verification debt blocks this phase. The two remaining platform facts that are still training-knowledge-only are the Humanoid auto-step height and the R15 hip height / head height (Assumptions A1 and A2); both feed *rejecting-biased design choices*, so being wrong costs map culls, not unfindable spoons.

## Blocking Findings

**None.** No locked decision is provably impossible. The items under "Corrections to CONTEXT premises" and "Open Questions" are corrections and ambiguities, not impossibilities.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| OBB world construction from snapshot | Pure core (`src/server/core`) | CI snapshotter + runtime loader feed it | Same code in CI and runtime (D-01) |
| Walkable height-field bake + flood fill | Pure core | — | Needs no Roblox API; headless in CI |
| Per-spot verdict (`check`) | Pure core | Server service calls it (Phase 6) | Rule has no avatar argument (D-10) |
| Snapshotting `.rbxm` -> `Node` | Lune script (`scripts/maps/snapshot.luau`) | — | Roblox/Lune API boundary |
| Snapshotting live tree -> `Node` | Server service (`MapLoader`) | — | Roblox API boundary; must be shape-identical |
| Shipped numbers | Shared config (`src/shared/Config/Placement.luau`) | Injected by callers | R6 forbids a pure-zone cross-mount require |
| Reason display (HIDE-02) | Client UI (Phase 6) | Server returns the code | Only the reason code crosses the wire |
| Hidden spot data | Server only | — | CLAUDE.md rule 3; nothing here is replicated |

## Standard Stack

### Core

No third-party library is added. Everything is pure Luau in the existing zones.

| Component | Version | Purpose | Why |
|-----------|---------|---------|-----|
| Luau (via Lune) | Lune 0.11.1 | Run the pure modules, the bake, tests | Already pinned in `rokit.toml` [VERIFIED: file read] |
| `@lune/roblox` | bundled with Lune 0.11.1 | Read `.rbxm` in the CI snapshotter and generators | Existing `scripts/maps/snapshot.luau` path |
| Existing harness | `tests/harness/Test.luau`, `Fuzz.luau` | Specs, fuzz targets | Already the project standard |

### Alternatives Considered (only where the lock leaves room)

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Per-column table allocation in the bake | Flat parallel arrays | Faster for 400k-cell maps; not needed at 1-stud resolution (0.4 s on the stress fixture). Start simple. |
| Linear scan of boxes in LOS | 2D bucket index (8-stud buckets) | Needed for the *link verification* and strongly advised for LOS on large maps; the prototype's 24-spot LOS pass over 4,640 boxes without buckets took 0.05 s, so buckets are for headroom, not necessity |

**No installation step.** Tools are present (see Environment Availability).

## Architecture Patterns

### System Architecture Diagram

```
 CI path                                      Runtime path
 -------                                      ------------
 maps/*.rbxm                                  ServerStorage.Maps.<id> (live tree)
    | roblox.deserializeModel                    |
    v                                            v
 scripts/maps/snapshot.luau                   MapLoader.snapshot
    |   reads CFrame.Position/Look/Up,           |   (SAME Node shape, SAME fields:
    |   CanCollide, Size, Anchored               |    position look up size anchored canCollide)
    +------------------+-------------------------+
                       v
              Node tree (plain data)
                       |
                       v
         MapValidator.validate(root, config)       config: src/shared/Config/Placement.luau
            1. structural pass (existing, v2)        injected by: validate-map.luau (CI) and
               -> any issue: STOP, no placement      MapLoader (runtime); NEVER required by core
            2. SpoonPlacement.bake(boxes, bounds,
                                   spawns, config)
                 a. Node -> OBB list (collidable only)
                 b. per OBB: rasterise onto columns -> vertical-line interval + top-face normal
                 c. per column: merge intervals -> spans (floor candidates, ceilings)
                 d. keep span tops with ny >= cos(slope) and headroom >= capH
                 e. erode: drop cells with an obstacle within capR above (stepUp + slope allowance)
                 f. link 4-neighbours: |dh| <= stepUp, shared headroom >= capH,
                    AND exact segment test between centres at body height (thin walls)
                 g. BFS from ALL seeker spawns -> region[]    (spawn with no cell: loud issue)
                 -> world { cells, region, boxes(bucketed), config }
            3. per default spot:  SpoonPlacement.check(world, spotPos)
                 in-bounds -> standable -> reach -> line-of-sight   (first failure wins)
            4. one issue per failing spot, code = reason; sort; spec only if no issues
            5. count check (MAP_SPOT_COUNT) on the full authored set
                       |
                       v
         issues + spec + (world)  -->  validate-map.luau exits 1 on any issue
                                       MapLoader errors; Phase 6 keeps `world` for the live hider check
```

### Recommended Project Structure

```
src/server/core/
├── MapContract.luau        # Node += up, canCollide (+ shape?); CONTRACT_VERSION = 2; new ISSUE_CODES
├── MapValidator.luau       # validate(root, config); placement stage after the structural pass
├── SpoonPlacement.luau     # GUARDED NAME. Policy: reasons, locked order, config validation, bake/check API
├── Obb.luau                # pure: basis from look+up, point/segment vs OBB, signed distance
└── WalkGrid.luau           # pure: spans, erosion, links, BFS  (names NOT starting with a guarded prefix are fine;
                            #   they are still reached by R2's transitive closure and R3 applies by directory)
src/shared/Config/Placement.luau   # shipped numbers; required by nobody under src/ except the MapLoader service
scripts/maps/snapshot.luau         # emits up + canCollide
scripts/maps/generate-graybox.luau # v2, regenerated, >= 18 valid spots
scripts/maps/generate-maze.luau    # D-08 adversarial fixture generator, parameterised
tests/placement/                   # obb.spec, walkgrid.spec, corpus.spec, config_lock.spec, maze.spec
```

### Pattern 1: Recast-style span height field (the established multi-layer pattern)

**What:** Recast Navigation's solid heightfield stores, per xz column, a *list of spans* `[smin, smax]`; walkable surfaces are span tops; neighbours link when the floor difference is within `walkableClimb` and the shared open height is at least `walkableHeight`; the walkable area is eroded by `walkableRadius`; slope is judged from the surface normal (`walkableSlopeAngle`). Our parameters map one-to-one: `capH` = walkableHeight, `stepUp` = walkableClimb, `capR` = walkableRadius, `maxSlope` = walkableSlopeAngle, `g` = cell size. [CITED: github.com/recastnavigation/recastnavigation, Recast/Include/Recast.h lines 243-254, 1003-1008]
**When:** always, for the bake.
**Example (verified prototype, simplified):**
```lua
-- Vertical line (x, z) against one OBB. Returns lo, hi, and the Y component of the outward normal at the top exit.
-- b.ax[k], b.ay[k], b.az[k] = x/y/z of local axis k (right, up, look); b.h[k] = half size.
local function columnSpan(b, x, z)
	local tlo, thi, nyTop = -math.huge, math.huge, 0
	local dx, dz = x - b.cx, z - b.cz
	for k = 1, 3 do
		local a, bb, h = dx * b.ax[k] + dz * b.az[k], b.ay[k], b.h[k]
		if math.abs(bb) < 1e-9 then
			if math.abs(a) > h then return nil end -- axis is horizontal: either always inside its slab or never
		else
			local t1, t2 = (-h - a) / bb, (h - a) / bb
			local tmin, tmax, sign
			if t1 < t2 then tmin, tmax, sign = t1, t2, 1 else tmin, tmax, sign = t2, t1, -1 end
			if tmin > tlo then tlo = tmin end
			if tmax < thi then thi = tmax; nyTop = sign * bb end -- outward normal Y at the TOP exit
		end
	end
	if thi - tlo < 1e-6 then return nil end
	return b.cy + tlo, b.cy + thi, nyTop
end
```
Walkable if `nyTop >= math.cos(math.rad(maxSlope)) - 1e-4`. Because the normal comes from the exact face, the ramp's 24.9 degrees is independent of `g`, and the ramp's high end face (normal about 65 degrees off vertical) is correctly rejected as a floor.

### Pattern 2: Slope-allowance erosion (this was the non-obvious part)

**What:** A naive erosion "drop a cell if any neighbour within `capR` has a solid above `h + stepUp`" **erodes the walkable slope itself**: on a ramp the neighbour `capR` away is `capR * tan(slope)` higher. Measured: with naive erosion the ramp needs `stepUp >= capR * tan(24.9) = 0.696` at `capR` 1.5, so the legal-slope/step coupling breaks silently. Add the slope allowance to the window floor: a neighbour at horizontal distance `d` blocks only if its top exceeds `h + stepUp + d * tan(maxSlope)`. With it, the minimum stepUp falls back to exactly `g * tan(slope)`. [VERIFIED: prototype]
```lua
local allow = math.sqrt(di * di + dj * dj) * g * math.tan(math.rad(maxSlope))
if neighbourSpan.hi > h + stepUp + allow and neighbourSpan.lo < h + capH then blocked = true end
```
Do not erode away from drop-offs (Recast does; we must not, because ledge spots 2 studs from an edge and shelf-edge standing are real). Only obstructions above `stepUp` erode.

### Pattern 3: Verify every link with an exact segment, not just the grid

**What:** Cell-centre sampling misses any solid thinner than `g` that falls between two sample centres. Measured on a 0.3-thick full-width wall at x in [0.75, 1.05]: with grid-only links **all 1,600 cells were one region (the wall leaked)**; with an exact horizontal segment test between each linked pair at two body heights (`maxH + stepUp + 0.25` and `maxH + capH - 0.25`), 840 cells were reached. Same at g=0.5 (6,400 vs 3,280). The leak direction is the dangerous one (a sealed spot marked reachable). [VERIFIED: prototype]
**Cost:** with an 8-stud bucket index, 1.5M link tests on the 440k-cell stress fixture added 0.15 s.
**Do not** rely on an authoring rule such as "no part thinner than g" as the only defence; it is invisible in a 1,000-part mansion.

### Pattern 4: Bake once, query many

`SpoonPlacement.bake(...) -> world` is the heavy call (map load / CI). `SpoonPlacement.check(world, point) -> { ok, reason? }` is the cheap one the Phase 6 hider calls per ghost-preview tick or placement: it scans only columns within `PICKUP_RANGE` (about 200 columns at g=1) and sorts candidate cells by distance for early exit. The world holds the config it was baked with, so `check` takes no config and **no avatar** argument (D-10).

### Pattern 5: Locked reason order, recorded three ways

`REASON_ORDER = { "OutOfBounds", "Solid", "NoFooting", "OutOfReach", "NoSight" }` (names illustrative) in the types, in a comment in both `SpoonPlacement` and `MapValidator`, and in a test, exactly as `Invariants.check` did with its nine names. Per D-12 the *rules* are four; reasons may split a rule (standable -> Solid/NoFooting; reach -> OutOfReach/Unreachable). Recommended meaning:
- **in-bounds:** point inside Bounds (use positive comparisons `x >= min and x <= max` so NaN fails; also require finite).
- **standable:** (a) *Solid*: signed distance to any collidable OBB `<= SPOT_CLEARANCE`; (b) *NoFooting*: no standable cell of ANY region within `PICKUP_RANGE`.
- **reach:** a spawn-connected cell with `distance(cell + reachY, spot) <= E - GEOM_EPSILON`; if cells exist in range but none connected, report `Unreachable`; else `OutOfReach`.
- **line-of-sight:** among those cells, one whose eye point (`cell + eyeY`) has an unobstructed segment to the spot.

### Anti-Patterns to Avoid

- **Recursive flood fill.** Luau has a call-depth limit; a long corridor exceeds it. Use an array queue. The maze fixture exists to catch this.
- **One flood per spot.** One BFS from all seeker spawns, once per map.
- **Computing slope from grid height deltas.** Resolution-dependent; use the face normal.
- **8-connectivity.** Allows diagonal leakage through corner gaps and complicates the corner clearance proof. 4-connectivity is sound and conservative for reachability.
- **Config defaults inside `SpoonPlacement`.** A missing or malformed config is a loud error (D-13).
- **A silent empty region.** If a spawn finds no standable cell the region is empty and every spot fails with a misleading reason (or, with several spawns, the survivors are quietly a subset). Treat it as its own loud issue.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Orientation of a part | Euler-angle or quaternion conversion | Basis vectors straight from the CFrame: `RightVector`, `UpVector`, `LookVector` (right is `look x up`, D-02) | Eliminates a whole class of rotation-order bugs; the snapshot already carries exactly this |
| Walkability / pathing | Any A*, funnel, or path smoothing | Reachability only: BFS over span cells | HIDE-06 needs connectivity and a distance, never a path |
| Roblox raycasts or `PathfindingService` | A wrapper around them | Nothing: not available in a pure zone (D-01, D-05) | R3 forbids it, and it would split CI from runtime |
| Polygon clipping / GJK / SAT for solids | General convex collision | The slab method for segment-vs-OBB and a closest-point formula for point-vs-OBB | The world is oriented boxes only |
| Hash of cell coordinates | String keys like `"12,-7"` | Integer index `j * nx + i + 1` into flat arrays | String keys allocate; 60k+ cells |
| Time measurement inside the rules | `os.clock` | Measure in `tests/` only | `check-guards` R3 bans the substring `os.` in pure zones (rule 5) |

**Key insight:** the only genuinely custom pieces are the OBB-vs-line/segment maths and the span builder, both about 60 lines. Everything else (BFS, sorting, buckets) is textbook. The risk is not complexity; it is silent wrongness (empty regions, leaks, vacuous gates), which is why the verification section is as large as it is.

## Segment-vs-OBB: algorithm and numerical discipline

**Algorithm:** the slab method in box-local axes (Kay-Kajiya). Express the segment origin and direction in the box axes (`o_k = (p - c) . axis_k`, `d_k = dir . axis_k`); per axis intersect `[-h_k, h_k]`; keep the running `[t0, t1]` clipped to `[0, 1]`; hit iff `t0 <= t1`. [VERIFIED: prototype, used for all LOS and link tests]

**Degenerate cases (each needs a named test):**
1. **Segment parallel to a slab** (`|d_k| ~ 0`): hit only if `|o_k| <= h_k`; never divide. Division by zero yields `inf` and, when `o_k` equals `+-h_k`, `0 * inf = NaN`, which compares false everywhere and silently reports "no hit". Branch on `|d_k| < 1e-12` first.
2. **Zero-length segment** (hand point == spot): handled by the same branch; define it as a point test.
3. **Segment starts or ends inside the box:** counts as a hit (the clip keeps `t0 = 0`). For LOS the spot is already proven outside every solid by the `Solid` rule, which runs earlier in D-12's order; that ordering is what makes this safe.
4. **Grazing / tangent contact:** decide once. Inflate every half-extent by `GEOM_EPSILON` so grazing counts as **blocked** (rejecting direction, consistent with D-11). A spot authored exactly on a face plane (Spot09 at the shelf's east face) is clear only because it is *above* the top at y=9.0 vs 8.5, not because of tolerance.
5. **World-AABB prefilter:** compute each box's world AABB from `sum_k |axis_k.component| * h_k`; reject the segment against it first. The slab test only runs on survivors.
6. **Non-orthonormal input:** snapshots come from real CFrames so they are orthonormal to about 1e-7, but hand-built test Nodes may not be. Validate `|look|`, `|up|` within `LOOK_EPSILON` of 1 and `look . up` within `LOOK_EPSILON` of 0 and issue a stable code rather than normalising silently.

**Epsilon discipline.** The codebase's `LOOK_EPSILON = 1e-3` is an *angular/component* tolerance on unit vectors. Introduce a separate named `GEOM_EPSILON = 1e-3` (studs) and use it everywhere a length is compared, never a bare `1e-6`. All acceptance comparisons shave it (`d <= E - GEOM_EPSILON`), all rejection comparisons add it, so every borderline outcome falls on the rejecting side. float32 snapshot error (about 1e-7 on unit vectors, about 1e-5 on a 100-stud position) is four orders of magnitude below `1e-3`.

## Common Pitfalls

### Pitfall 1: One height for both reach and sight
**What goes wrong:** the crate-top spot is culled and the map drops to 15. **Why:** a root-height sight line cannot clear a 4-stud crate edge from nearby. **Avoid:** separate `REACH_HEIGHT` and `EYE_HEIGHT` constants; Phase 5 consumes both. **Warning sign:** a spot on any raised surface needs `d*los` far above `d*conn`.

### Pitfall 2: Grid resolution, step-up and slope are one coupled system
**What goes wrong:** a legal ramp silently disconnects (g=4 with stepUp 1.0 drops survivors to 11-12). **Avoid:** config invariant test `stepUp >= g * tan(maxSlope)`; and slope-allowance erosion (Pattern 2), without which the effective requirement becomes `capR * tan(slope)`.

### Pitfall 3: Thin solids between samples
**What goes wrong:** a 0.3-thick wall is invisible at g=1, a sealed room reads as reachable, an unfindable spoon ships. **Avoid:** Pattern 3 link verification. **Warning sign:** a region count that does not drop when you add a wall in a test.

### Pitfall 4: A corridor narrower than the erosion leaves nothing, and the gate still reads green
**What goes wrong:** measured on the maze, corridor width 3 with `capR` 1.5 at g=1 gives **0 reached cells** (the whole walkable area eroded away), while widths 4, 5, 6 reach all N^2 maze-cell centres. A fixture that only asserts "sealed region not reached" passes vacuously at width 3. **Avoid:** the fixture's oracle must assert that all non-sealed maze-cell centres ARE reached (a positive count), and the generator must refuse `corridor < 2 * capR + g`. [VERIFIED: prototype]

### Pitfall 5: `check-guards` R3 bans the substring `os.` even inside identifiers and strings
**What goes wrong:** `pos.x`, `cos.`, `dos.`, `ratios.`, `zeros.`, `typos.` and any message ending a sentence with such a word all contain `os.`. Comments are stripped, **string literals are not** (see the comment at `check-guards.luau` lines 394-397). A vector named `pos` fails the whole gate. **Avoid:** name vectors `p`, `point`, `at`, `spotPos` is fine only if followed by a non-dot; use `point.x`. Write error text so no sentence ends in a word ending `os`. Grep `os\.` over new pure-zone files before committing. **Also banned:** `coroutine`, `getfenv`, `setfenv`, `loadstring`, `rawget(_G`, `_G[`, non-literal `require`.

### Pitfall 6: NaN and infinity from a client coordinate
**What goes wrong:** the Phase 6 hider sends a point; `x < min or x > max` is false for NaN, so an "out of bounds" test written as a rejection passes NaN straight through. **Avoid:** positive comparisons plus an explicit finite check (`p == p and p ~= math.huge and p ~= -math.huge`, as `MapValidator.isInteger` already does).

### Pitfall 7: Knife-edge verdicts
**What goes wrong:** an authored spot within a few hundredths of a stud of a threshold flips on a numeric change (Spot09 at E=6.5). **Avoid:** pick numbers with at least 1 stud of slack on both sides for every authored spot; add the corpus stability probe (below).

### Pitfall 8: Existing tests that hard-code contract version 1
`tests/maps/validator.spec.luau` lines 56 and 166-170 ("ContractVersion not 1" sets the attribute to **2**) and `tests/maps/graybox.spec.luau` line 92 (`equal(... 1)`), plus `generate-graybox.luau` line 256 and a regenerate-and-compare-bytes case. After the bump, the `= 2` case becomes a *valid* version and its test flips from asserting a rejection to asserting nothing useful; change it to 3 (and add a case that a **1** is rejected, with a message that says to regenerate). 8 call sites of `validate(` in `validator.spec`, 2 in `graybox.spec`, 1 in `validate-map.luau`, 1 in `MapLoader` need the new config argument.

### Pitfall 9: Mesh, CSG and non-block Parts
`Part.Shape` reads under Lune, but a Ball or Cylinder Part has className `"Part"`, so a sphere would be modelled as a box. `MeshPart`, `UnionOperation`, `WedgePart` carry their own classNames. **Recommended default (A4):** only `className == "Part"` with block shape is a standable, blocking OBB. Every other BasePart in `Geometry/` contributes its bounding box as **blocking-only** (erosion and sight) and **never as a standable surface**. Reject-biased: a mesh floor yields no footing and the map author fixes it by modelling floors as Parts. Add `shape: string?` to `Node` in the same v2 bump (one optional field) so a block-shaped Part can be told from a Ball; it is the same cost as `canCollide` and the identical-shape test must cover it. This is discretionary; flag it in the plan.

### Pitfall 10: A stale `reached = 0`
If no spawn finds a standable cell the BFS runs on an empty queue and reports 0 reached. `MAP_SPAWN_NO_FOOTING` (a spawn with no cell at or below its y within a bounded drop) and `MAP_SPAWN_DISCONNECTED` (not all spawns in one region, D-06's sanity check) must be real issue codes with fixtures.

### Pitfall 11: Placement runs on a map that already failed the structural pass
`validate` returns `spec == nil` when any issue exists. Run the placement stage only when the structural pass is clean, or placement will dereference missing folders. Spots outside Bounds are already `MAP_OUT_OF_BOUNDS` from the structural pass, so rule 1 of D-12 never fires inside `validate`; it exists for the runtime hider check.

## Code Examples

### Segment vs OBB (slab), world-AABB prefilter first
```lua
-- Verified prototype. inflate = GEOM_EPSILON so grazing counts as blocked.
local function segHitsBox(b, px, py, pz, qx, qy, qz, inflate)
	if math.max(px, qx) < b.minx - inflate or math.min(px, qx) > b.maxx + inflate then return false end
	if math.max(py, qy) < b.miny - inflate or math.min(py, qy) > b.maxy + inflate then return false end
	if math.max(pz, qz) < b.minz - inflate or math.min(pz, qz) > b.maxz + inflate then return false end
	local dx, dy, dz = qx - px, qy - py, qz - pz
	local ox, oy, oz = px - b.cx, py - b.cy, pz - b.cz
	local t0, t1 = 0, 1
	for k = 1, 3 do
		local o = ox * b.ax[k] + oy * b.ay[k] + oz * b.az[k]
		local d = dx * b.ax[k] + dy * b.ay[k] + dz * b.az[k]
		local h = b.h[k] + inflate
		if math.abs(d) < 1e-12 then
			if math.abs(o) > h then return false end
		else
			local ta, tb = (-h - o) / d, (h - o) / d
			if ta > tb then ta, tb = tb, ta end
			if ta > t0 then t0 = ta end
			if tb < t1 then t1 = tb end
			if t0 > t1 then return false end
		end
	end
	return true
end
```

### Iterative 4-neighbour BFS over layered cells
```lua
-- cells.col[c] column index (1-based, idx = j * nx + i + 1), cells.h[c] floor height, cells.ceil[c] ceiling.
-- colFirst[idx], colCount[idx] index a column's cells in the flat arrays. NO recursion, one queue.
local head, tail = 1, #seedCells
while head <= tail do
	local c = queue[head]; head += 1
	-- for each of 4 neighbours, for each cell n in that column not yet in `region`:
	--   link if |h[n] - h[c]| <= stepUp
	--   and min(ceil[c], ceil[n]) - max(h[c], h[n]) >= capH
	--   and no OBB intersects the centre-to-centre segment at (max(h) + stepUp + 0.25) and (max(h) + capH - 0.25)
	--   then region[n] = 1; tail += 1; queue[tail] = n
end
```

### Config injection and loud failure (mirrors `CardPool` / `Pool.poolConfig`)
```lua
-- SpoonPlacement.luau (pure): never requires the config.
export type PlacementConfig = {
	gridSize: number, stepUp: number, maxSlopeDegrees: number,
	capsuleHeight: number, capsuleRadius: number, reachHeight: number, eyeHeight: number,
	spotClearance: number, pickupRange: number, pickupMargin: number,
}
local function assertConfig(c: any): PlacementConfig
	assert(type(c) == "table", "SpoonPlacement: config is required")
	for _, key in REQUIRED_KEYS do
		local v = c[key]
		assert(type(v) == "number" and v == v and v > 0 and v < math.huge, `SpoonPlacement: config.{key} must be a positive finite number`)
	end
	assert(c.pickupMargin < c.pickupRange, "SpoonPlacement: pickupMargin must be smaller than pickupRange")
	return c :: PlacementConfig
end
```
Spec-lock tests (in `tests/`, where requiring across mounts is allowed): `local cfg: SpoonPlacement.PlacementConfig = require("../../src/shared/Config/Placement")` gives a typecheck-level shape lock, plus invariants: `stepUp >= gridSize * tan(slope)`, `pickupMargin >= gridSize * sqrt(2) / 2`, `spotClearance < 0.5`, `capsuleHeight > eyeHeight > reachHeight`.

### Reading the new fields in the CI snapshotter (verified readable under Lune 0.11.1)
```lua
-- inside the BasePart branch of scripts/maps/snapshot.luau, after the CFrame read
node.up = vec3Of(cframe.UpVector)
node.canCollide = part.CanCollide == true
-- MapLoader.snapshot: node.up = vec3Of(cframe.UpVector); node.canCollide = instance.CanCollide
```

## Flood-fill scale and the CI cap (D-09)

Measured on this container, Lune 0.11.1. CI runners are usually slower; plan for 2x to 4x. [VERIFIED: prototype; runner speed is A5]

| Scenario | Columns | Cells | Boxes | Bake | Flood + link verify | 24-spot LOS pass |
|----------|---------|-------|-------|------|---------------------|------------------|
| Graybox, g=1 | 15,376 | 14,166 | 40 | 0.019 s | 0.004 s | 0.002 s |
| Graybox, g=0.5 | 61,504 | 54,657 | 40 | 0.133 s | 0.018 s | — |
| Maze 120, 4 levels, g=1 | 15,376 | 35,080 | 1,172 | 0.092 s | 0.010 s | — |
| Maze 120, 4 levels, g=0.5 | 61,504 | 110,972 | 1,172 | 0.76 s | 0.038 s | — |
| **Maze 240, 4 levels, g=1** | 59,536 | 115,178 | 4,640 | **0.38 s** | **0.036 s** | **0.054 s** |
| Maze 240, 4 levels, g=0.5 | 238,144 | 440,599 | 4,640 | 3.7 s | 0.158 s | 0.092 s |
| Maze 240, 8 levels, g=0.5 | 238,144 | 844,383 | 9,280 | 10.7 s | 0.27 s | — |

Reading a `.rbxm` is not a cost: 5,000 Parts deserialize in 0.02 s and the snapshot read takes 0.03 s. [VERIFIED: lune spike]

**Scaling.** Bake cost is `O(sum over boxes of covered columns) + O(columns x spans)`, dominated by per-column table allocation, and grows with levels and with `1/g^2`. Flood cost is `O(reached cells x 4 x layers per column)` and is tiny. **A maze is therefore NOT a time stressor for BFS** (path length does not affect a queue); its value is (a) an exact reachability oracle, (b) many boxes and layers for the bake and the bucket index, (c) catching recursion and vacuous-empty-region mistakes.

**Recommended cap (D-09):**
- Resolution 1.0 is what makes a tight cap affordable: g=0.5 on the stress fixture is already 3.7 s.
- **Stress fixture** (248 x 248 footprint, 4 levels, corridor 6, 1-stud walls, about 4,640 boxes, one sealed pocket): assert `bake + flood + 24 spot checks <= 2.0 s` wall-clock (measured about 0.5 s, 4x headroom for a slower runner). This adds about 0.6 s to the suite.
- **Graybox:** assert `<= 0.5 s` (measured 0.025 s).
- Also assert **deterministic work counters** returned from the bake (`columns`, `cells`, `reached`, `linkTests`, `boxes`) are non-zero and within fixed ceilings, so the gate cannot flake on a loaded runner and cannot pass on an empty bake. The wall-clock cap is the backstop, not the only gate.
- Add a **runtime structural cap**: the bake refuses (loud issue `MAP_BOUNDS_TOO_LARGE` or similar) when `columns * expectedLayers` exceeds a ceiling, so a mis-authored 2,000-stud Bounds cannot hang the server at map load.
- `os.clock` is allowed in `tests/`; it is banned only under the pure zones. The suite currently runs about 25-26 s against a 15.94 s Phase 1 baseline; the fixture adds under 1 s.

## The adversarial maze fixture (D-08)

**What makes a maze worst-case rather than merely large.** Total cells set bake cost; BFS cost is just reached cells. What a maze adds is correctness pressure: long single-width paths (queue depth, recursion depth), dead ends, many thin walls (leak detection), and a **known answer**. So design the fixture as an oracle first, a stress second.

**Generator dials** (`scripts/maps/generate-maze.luau`, deterministic from a seed; use an integer LCG, not `math.random`, so the bytes are stable across Lune versions):

| Dial | Default | Stresses |
|------|---------|----------|
| `footprint` | 248 | bake columns |
| `cellSize` / `corridor` + `wallThickness` | 6 + 1 | box count; **refuse `corridor < 2 * capR + g`** (Pitfall 4) |
| `braid` (0..1) | 0 | 0 = perfect maze (one path, longest dead ends), >0 knocks extra walls out |
| `levels` | 4 | layers per column; stacked slabs 24 apart |
| `sealedPockets` | 1 | unreachable cells containing spots, to prove the cull fires |
| `thinWalls` | 1 | a 0.3-thick full-width wall to prove link verification |
| `seed` | fixed | reproducibility |

**Oracle (the part that makes the gate meaningful):** the generator emits, alongside the `.rbxm`, the set of maze-cell centres and which are sealed. The test asserts `reached(non-sealed centres) == all of them` AND `reached(sealed centres) == none` AND `cells > 0`. The prototype confirmed this oracle: 529/529 centres reached at corridor 4 to 6, and 0/841 at corridor 3 (Pitfall 4). Without the positive half the fixture passes vacuously whenever erosion removes the corridors.

**Seeds:** use spawns at a maze cell centre on level 0; the other levels are intentionally unreachable apart from what the generator links, and their cells still count toward bake cost (this is what makes the fixture a bake stress).

## Luau / Lune specifics for pure-zone numeric work

- `--!strict` everywhere (R1). Typed arrays of numbers are fine; avoid `any` except at the Lune datatype boundary in `scripts/`.
- **Banned in the pure zone** (R3): `coroutine`, `getfenv`, `setfenv`, `loadstring`, `rawget(_G`, `_G[`, any non-literal `require`, and the substring `os.` (Pitfall 5). R3b: no suppression comments (`--!nocheck`, `selene: allow`, ...).
- **Requires** inside the pure zone must be relative literal strings (`require("./Obb")`). `src/server/core` cannot reach `src/shared` (R6). The config is injected.
- **Performance:** flat parallel arrays beat tables of tables; pre-size with `table.create(n)`; integer division `//` exists; precompute `math.cos(math.rad(slope))` once; hoist `math.abs`/`math.sqrt` locals in hot loops. `table.sort` with a comparator is the bake's sort; sort only columns with more than one interval.
- **No yields inside mutation** (CLAUDE.md rule 6): the bake and `check` are synchronous and pure. Do not add `task.wait` or any yielding call.
- **Determinism:** iterate arrays in index order, never `pairs` over a hash for anything that affects output; sort issues by (code, path, message) as the validator already does.
- **Numeric precision:** doubles in Luau, float32 inputs from the snapshot. Compare lengths with `GEOM_EPSILON`; never compare floats with `==`.
- **`debug.info(fn, "a")`** returns arity and vararg and can lock `check`'s signature in a test (HIDE-07/D-10). It is a test-side tool.

## Scope Question: seat winding and seat facing

**Recommendation: include it,** as one small task. Cost estimate: about 60-90 lines in `MapValidator` (pure geometry on data already in the spec), 2 new issue codes (`MAP_SEAT_ORDER`, `MAP_SEAT_FACING`), about 6 fixtures (reversed order, two swapped seats, wrong facing, sub-tolerance facing, a good non-graybox ring, a degenerate seat on the anchor), plus enabling the two `ISSUE_CODES` coverage cases. About half a day, no new dependencies.
- **It does not need `up`** (the scope note says it does: it does not). Winding needs only seat positions; facing needs `look`, already in v1. Only the `Bounds` roll item needs `up`.
- *Winding:* for seats 1..9 compute the bearing `atan2(dx, -dz)` about `TableAnchor`; require each consecutive step (including 9 to 1) to be in `(0, 180)` degrees and the nine steps to sum to 360 within a tolerance. The graybox is 40 degrees apart by construction [CITED: generate-graybox.luau lines ~237-248].
- *Facing:* `dot(seat.look, normalize(anchor - seat))` must be at least `cos(5 degrees)` (about 0.996) so a hand-authored Studio seat is allowed human error, while the generated `CFrame.lookAt` seats (exact to float32) pass.
- *Bounds roll:* extend the existing identity-rotation check to also require `up` within `LOOK_EPSILON` of (0,1,0).
If excluded, the planner must move those two lines of the deferred comment to Phase 7a explicitly.

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| `Workspace:FindPartOnRay` | `Workspace:Raycast` with `RaycastParams` (and `RespectCanCollide`) | [CITED] deprecated; irrelevant to this phase, relevant to Phase 5 |
| Single-layer 2D walk grid | Recast-style multi-layer span heightfield | Handles floors above floors (D-07) |
| Pathfinding service for validity | Own flood fill over baked cells | D-05; deterministic, headless |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A Roblox Humanoid auto-steps roughly up to about 1 stud; step height is not documented | Ladder: step-up | Low: the rule is a design choice biased to reject; too low only culls |
| A2 | R15 default `HipHeight` is 2 (root centre about 3.0 above the floor), torso about 2 wide, head centre about 4.5 at scale 1 | Ladder: capsule | Medium: shifts reach/eye by about 0.3-0.5 studs; the recommended values already round down |
| A3 | Spoon skin template (Phase 7b) will fit a 0.25 clearance | Ladder: clearance | Medium: if the bounding half-extent exceeds 0.25, every skin's spots need re-validating |
| A4 | Reject-biased default for mesh/CSG/non-block geometry (blocking, never standable) is acceptable to the owner | Pitfall 9 | Low for the graybox (all Blocks); Phase 7a authoring ergonomics |
| A5 | CI runners are 2x to 4x slower than this container | Flood scale | Low: caps are set with 4x headroom plus deterministic counters |
| A6 | Catalog height range is 90 to 105 percent and width 70 to 100 percent (web search summary only; Avatar Settings can override either way, and scripts can exceed them) | V-19 | Medium: if an avatar can be shorter than 2.5 root height the reach guarantee fails in the permissive direction; D-10 holds only inside the envelope, so record it as a place-settings dependency |
| A7 | `ProximityPrompt.MaxActivationDistance` default is 10 | Ladder: PICKUP_RANGE | Low: the docs fetched here did not state a default; only matters if Phase 5 uses a prompt (V-22) |
| A8 | Server-known HRP position lags by a few studs (V-23, LOW) | PICKUP_MARGIN | Medium: Phase 5/8 measure it; the margin is a named constant so it can move |

## Open Questions

1. **MAP-02 strict versus "after exclusions" (planner and owner decision, blocks plan shape).**
   - Known: MAP-02 says the validator "fails the build on any [default spot] that would be unfindable". ROADMAP criterion 3 says the reference map must pass "with at least 16 default spots that each survive the real placement rules after exclusions". Phase 1 authored 18 so Phase 3 "can cull some". "Exclusions" is not defined anywhere in `.planning/` (searched).
   - Unclear: whether a culled spot is a build failure (strict) or is silently dropped while the count stays >= 16 (tolerant).
   - **Recommendation: strict.** One issue per failing spot, build fails, count rule applies to the authored set. It matches MAP-02's literal text, gives Phase 7a authors immediate feedback, and means HIDE-05's auto-fill "from validated default spots" is trivially satisfied. Consequence: the graybox's two shelf spots fail the build today, so the regenerate-the-map task is mandatory, not optional.
2. **Separate `EYE_HEIGHT`.** Recommended; the owner confirms with the ladder, and Phase 5 must consume it.
3. **Non-block shapes.** Whether to add `Node.shape` in the same v2 bump (recommended) or to infer block-only from className and accept that Ball/Cylinder Parts are modelled as boxes.
4. **Place avatar-scale envelope.** D-10 is exact only for avatars whose root height is at least the canonical 2.5 and whose height is at most the headroom. Custom Scale in Avatar Settings or a script can leave that envelope. Clamping is a deferred idea; decide whether to record a MANUAL-CHECK (like M-05) so the envelope is at least auditable.
5. **`CharacterMaxSlopeAngle` in the place.** Defaults to 89. Record that it must stay at or above the rule's slope.
6. **Pickup range origin.** Phase 5 must measure from the same root point and add the same eye offset, or `PICKUP_RANGE` is shared in name only.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Lune | tests, scripts, spikes | yes, at `/root/.rokit/bin/lune` (not on the default `PATH` in this shell; export it) | 0.11.1 | — |
| StyLua / Selene / luau-lsp / Rojo | `scripts/verify.luau` chain | yes (in `/root/.rokit/bin`) | pinned in `rokit.toml` | — |
| `maps/gray-box.rbxm` | corpus and validator integration | yes (committed) | v1 today, regenerated at v2 in this phase | — |
| Roblox Studio | none needed | not required | — | The graybox and maze are Lune-generated (D-18, D-08) |
| `create.roblox.com` docs | verification | yes via `curl` and `.md` URLs, not via `WebFetch` | — | training knowledge, labelled |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | the project's own harness, `tests/harness/Test.luau`, discovered by `tests/run.luau` (`*.spec.luau`, not under `fixtures/`) |
| Config file | none; `tests/run.luau` flags `--filter`, `--root`, `--seed` |
| Quick run command | `lune run tests/run.luau --filter placement` (and `--filter maps`; the maps suite runs 60 cases in about 0.7 s today) |
| Full suite command | `lune run tests/run.luau` then `lune run scripts/verify.luau` (14 steps, about 25-26 s) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HIDE-06 | corpus: known-good and known-bad coordinates, each with its reason code | unit | `lune run tests/run.luau --filter corpus` | Wave 0 |
| HIDE-06 | OBB maths agrees with a brute-force sampler; flood agrees with an independent union-find | fuzz (use `tests/harness/Fuzz.luau`) | `--filter obb`, `--filter walkgrid` | Wave 0 |
| HIDE-07 | `check` takes no avatar argument (arity lock via `debug.info`) and gives identical verdicts for repeated calls | unit | `--filter placement` | Wave 0 |
| MAP-02 | each new issue code fires on a dedicated fixture, alone | unit | `--filter validator` | extend |
| MAP-02 | CLI exits 1 and prints `<CODE> <path> <message>` on a bad spot | integration | `--filter graybox` | extend |
| MAP-03 | graybox v2 passes with >= 16 and every authored spot valid | integration | `--filter graybox` | extend |
| G2 | maze: oracle (positive and negative), work counters, wall-clock cap | integration | `--filter maze` | Wave 0 |
| D-13 | config shape, injected-config loud failure, shipped-value lock | unit | `--filter config` | Wave 0 |
| must_have 1 | both snapshotters emit identical `Node` shape incl. `up`, `canCollide`, `shape` | integration | `--filter graybox` | extend |

### Sampling Rate
- **Per task commit:** `lune run tests/run.luau --filter placement` plus `--filter maps`.
- **Per wave merge:** `lune run tests/run.luau`.
- **Phase gate:** `lune run scripts/verify.luau` green, and every new gate demonstrated red (below), before `/gsd-verify-work`.

### Make every gate observable (the Phase 1/2 lesson)

Each of these can pass vacuously unless handled; the verification step must watch it go red.
1. **Issue-code coverage** passes if a code is declared but never emitted. Each fixture must assert the **exact issue set equals `{that code}`**, not "contains". Mutation: delete the rule, the case must fail.
2. **Maze oracle** passes if erosion removes the corridors. Assert the positive count first (`cells > 0`, `reached(non-sealed) == all`). Mutation: set corridor 3, the case must fail with a reason that names the empty region.
3. **Time cap** passes if the bake did nothing. Assert non-zero deterministic counters before the clock. Negative control: a meta-case runs the same fixture under a deliberately tiny cap and asserts it fails.
4. **Corpus** passes if a verdict sits on a threshold. Add a **stability probe**: re-run every corpus coordinate with `E +- 0.25` and require identical verdicts; mutation: move one coordinate onto its threshold, the probe must fail.
5. **Spec-lock "runtime uses the shipped values"** cannot execute `MapLoader` headlessly (it needs the Roblox API). Do it as a source assertion over `MapLoader.luau` after comment-stripping (reuse `scripts/ci/lex.luau`'s `stripComments`), requiring a literal `Config.Placement` and that `validate(` is passed a config. Mutation: remove the require, the case must fail. A raw `grep` that also matches comments passes vacuously.
6. **Signature lock** (D-10): assert `debug.info(SpoonPlacement.check, "a") == 2` (world, point). Mutation: add a third parameter, the case must fail.
7. **Ramp connectivity**: include the negative control `maxSlope = 24` (ledge culled, survivors 12) alongside the positive case so the test proves it can fail.
8. **Identical snapshot shapes**: compare the key sets of a Node from `snapshot.luau` and a hand-built Node mirroring what `MapLoader.snapshot` emits, field by field including `up`, `canCollide`, `shape`. A snapshot missing `canCollide` must fail the test.
9. **Guard fixtures**: add pure-zone fixtures proving the new files obey R3 (`os.` substring, `pos.x`) only if the planner adds new guard rules; otherwise just run `check-guards`. Remember the lesson from Phase 1: `luau-lsp` exits 0 when its sourcemap fails to load, so confirm the typecheck step actually analysed the new files.

### Wave 0 Gaps
- [ ] `tests/placement/obb.spec.luau`: slab degenerate cases, brute-force differential fuzz
- [ ] `tests/placement/walkgrid.spec.luau`: ramp, thin wall, erosion, link verification, flood differential
- [ ] `tests/placement/corpus.spec.luau`: micro-world corpus (exact, no knife-edges) plus graybox corpus, reason codes only
- [ ] `tests/placement/config_lock.spec.luau`: invariants and shipped-value lock
- [ ] `tests/placement/maze.spec.luau`: oracle, counters, cap, negative control
- [ ] `scripts/maps/generate-maze.luau`
- [ ] regenerated `maps/gray-box.rbxm` at v2 with >= 18 valid spots, plus updated `graybox.spec` / `validator.spec`
- [ ] Framework install: none needed

## Security Domain

`security_enforcement` is absent from `.planning/config.json`, so this section applies.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | yes | The hider's placement point is client-supplied; the server alone calls `check`. The client never names a hand index or pass target (rule 7); likewise it never supplies a verdict |
| V5 Input Validation | yes | Finite-number and range checks on every client coordinate (Pitfall 6); loud errors on malformed config (D-13); orthonormal-basis check on snapshots |
| V6 Cryptography | no | — |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| NaN / infinity / huge coordinate from a client defeats a range check | Tampering | Positive comparisons plus explicit finite check in `check` |
| Cheat client reads hidden spot data | Information disclosure | Spot positions and the baked world live server-side only (rule 3); the client receives only the verdict reason for its own candidate point |
| Placement-check spam used as a CPU denial | DoS | Each `check` scans about 200 columns and early-exits; rate-limit at the gateway in Phase 6 (`RateLimits`) |
| Map smuggles code or oversized bounds | Tampering / DoS | Existing `MAP_SCRIPT_FORBIDDEN`; add the bake-size ceiling (Flood-fill scale) |
| A purchase affecting findability | Elevation | `SpoonPlacement*` is a guarded name: R2 forbids any import path to cosmetics/shop; the capsule is a canonical constant, not per-player |

## Sources

### Primary (HIGH confidence)
- https://create.roblox.com/docs/reference/engine/classes/Humanoid.md (HipHeight formula, MaxSlopeAngle default 89, JumpHeight default 7.2, AutomaticScalingEnabled) - fetched 2026-11-04
- https://create.roblox.com/docs/reference/engine/classes/StarterPlayer.md (CharacterMaxSlopeAngle default 89)
- https://create.roblox.com/docs/reference/engine/classes/HumanoidDescription.md (scale properties map to Body*Scale NumberValues via ApplyDescriptionAsync)
- https://create.roblox.com/docs/studio/avatar-settings.md (Player Choice vs Custom Scale; classic about 5 studs, humanoid 6-6.5)
- https://create.roblox.com/docs/reference/engine/classes/PathfindingService.md and Path.md (AgentRadius 2, AgentHeight 5, yields, thread safety)
- https://create.roblox.com/docs/reference/engine/classes/WorldRoot.md (FindPartOnRay deprecated; RespectCanCollide default false), RaycastParams.md, BasePart.md (CanCollide, CanQuery)
- https://create.roblox.com/docs/workspace/streaming.md (streaming scope, MinRadius 64, TargetRadius 1024)
- https://raw.githubusercontent.com/recastnavigation/recastnavigation/main/Recast/Include/Recast.h (walkableSlopeAngle / Height / Climb / Radius semantics)
- Lune 0.11.1 behaviour: local spikes against the committed `maps/gray-box.rbxm`

### Secondary (MEDIUM confidence)
- Web search summary of Roblox scaling limits (height 90-105 percent, width 70-100 percent), citing roblox.fandom.com/wiki/Body_scaling and devforum.roblox.com threads; not re-fetched

### Tertiary (LOW confidence)
- Humanoid auto-step height, R15 default HipHeight and head height, CI runner speed: training knowledge only (A1, A2, A5)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. No third-party dependency; all tooling present and pinned.
- Architecture: HIGH. The pattern is Recast's, and the prototype ran it end to end on the real map.
- Number ladder: HIGH for the per-spot consequences (measured on the real geometry), MEDIUM for the platform-derived capsule dimensions.
- Pitfalls: HIGH for those reproduced by the prototype (thin wall leak, empty region, slope erosion, clearance cliff, eye height); MEDIUM for the rest.
- Verification debt: V-17, V-18, V-4 HIGH; V-19 MEDIUM; V-20 MEDIUM-HIGH.

**Research date:** 2026-11-04
**Valid until:** 2026-12-04 (geometry and measurements are stable; re-check the Roblox doc claims if Lune or the platform version pins change)
