# Phase 3: Placement Rules, Map Pipeline and Validator - Context

**Gathered:** 2026-11-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 3 delivers **one shared placement rule set** and the validator extension that proves
every authored default spot obeys it:

- `SpoonPlacement` — the single rule set answering "is this coordinate a valid hiding spot?"
  with a reason. Used by the build-time validator now and by the hider's live check in
  Phases 5/6. (HIDE-06, HIDE-07)
- `MapValidator` gains the real placement checks after its structural pass, each with its own
  stable issue code, and the build fails on any default spot that would be unfindable.
  (MAP-02)
- The reference map still yields **at least 16** default spots that survive the real rules
  after exclusions. (MAP-03)
- **Gate G2:** validator green on the reference map and the full placement corpus, and the
  maze bake stress test completes — the precondition for authoring the five shipped maps.

**Not this phase:** the hide-phase UI and ghost preview (HIDE-01..05, Phase 6), the hunt and
glint visibility (Phase 5), the five shipped maps (Phase 7a), scoring (Phase 4). This phase
builds the rules those phases consume, not the experiences that consume them.

</domain>

<decisions>
## Implementation Decisions

### Geometry source and the rule engine

- **D-01: One pure-data OBB world; no Roblox API in the rules.** The rules see geometry as
  oriented bounding boxes built from the `MapContract.Node` snapshot, with our own
  segment-vs-OBB raycast and walkability math. **One implementation serves CI and runtime** —
  this is what makes MAP-02's "the real placement rules" literally true rather than
  aspirational. `src/server/core/` is a pure zone (`check-guards` R3, no suppression
  mechanism), so `Workspace:Raycast` and `PathfindingService` are not available here and that
  constraint was accepted rather than worked around.
  - **Accepted limitation, stated plainly:** this is *our* model of collision, not Roblox's.
    Boxes are exact; meshes, CSG and non-collidable parts are only as correct as the snapshot
    makes them. Phase 5 runs the real hunt in real geometry and is where any divergence will
    first be observable.

- **D-02: `Node` gains an `up` vector; `ContractVersion` goes 1 → 2.** The third basis vector
  is the cross product of `look` and `up`. Reuses the existing `LOOK_EPSILON = 1e-3`
  convention. The graybox is regenerated at v2.
  - **Why this is load-bearing, not cosmetic.** Phase 1 recorded the gap
    (`01-07-SUMMARY.md:239`): `Node` carries a look vector but no up vector, so a roll about
    the look axis is invisible. The graybox's `Ramp` is rotated by a roll about Z, and **a roll
    about Z does not change the look vector** — so under v1 the ramp snapshots as a flat
    floating slab. The ramp is the only route onto the `Ledge`, and **4 of the graybox's 18
    default spots sit on that ledge**. Without `up`, a correct reachability pass culls all four,
    leaves 14, and fails `MIN_DEFAULT_SPOTS = 16` on the reference map. The contract bump is the
    fix for a wrong answer, not a tidy-up.
  - Side effect: it also closes the "Bounds roll" item in `MapValidator`'s deferred list for free.

- **D-03: `Node` gains `canCollide`; only collidable parts are solid.** Applies to both
  walkability and line-of-sight. Keeps non-collidable set dressing from inventing standable
  surfaces or falsely blocking a sightline. One extra field, taken while the contract is being
  bumped anyway.

- **D-04: The rules live in `src/server/core/SpoonPlacement.luau`.** This is the exact filename
  `check-guards` already guards as a FOUND-05 no-pay-to-win root (`guardedNamePrefixes =
  { "Scoring", "CardTable", "SpoonPlacement" }`), so the guard stops being hypothetical the
  moment the file exists. `MapValidator` calls it per default spot; the Phase 5/6 hider check
  calls the same function. Internal structure (whether geometry primitives split into their own
  module) is Claude's discretion.

### Reachability

- **D-05: Walkable-grid flood-fill, not `PathfindingService`.** Pure, deterministic, headless,
  same answer every run. `PathfindingService` is a Roblox API and cannot live in the pure zone,
  so choosing it would have forced the two-tier split D-01 rejected.

- **D-06: Reachability is measured from ALL seeker spawns.** A spot is reachable only when its
  nearby standable cell lies in the connected region containing the seeker spawns — the literal
  requirement, "a seeker starting where seekers start can get there". Not from the hider spawn
  (HIDE-09 puts seekers in a closed parkour room, so the hider's region answers the wrong
  question), and not "any largest connected region" (which stops catching the real bug).
  - Free sanity check: the graybox has 4 spawns, one per corner room. A test asserting they all
    land in one connected region validates the map and the flood-fill at once.

- **D-07: The grid is a multi-layer height field.** A 2D lattice of columns, each holding a
  **list** of standable heights found by casting down the column; neighbours link when adjacent
  columns have candidate heights within the step-up limit. Cost scales with footprint x layers
  rather than bounds volume. A single-height 2D grid was rejected because it cannot represent a
  floor above a floor and would make the mansion (MAP-07) unvalidatable; a full 3D voxel grid
  was rejected as ~461,000 mostly-air cells over the graybox bounds alone.

- **D-08: Gate G2's maze stress fixture is a Lune-generated synthetic adversarial maze.** A
  generator beside `scripts/maps/generate-graybox.luau`, following D-18's precedent, emitting
  long corridors, dead ends, maximum walkable-cell count and a deliberately sealed region.
  Parameterised, so stress level is a dial rather than a guess. The real maze map (MAP-08) is
  Phase 7a; this fixture gives its author a performance target to stay under.
  - Scaling up the graybox was rejected: its topology is open halls and rooms, so it would test
    grid *size* but not the maze-like connectivity that actually stresses a flood-fill.

- **D-09: The bake carries a hard CI time cap, asserted by a test.** The budget is a locked
  contract, not a hope — a later map that blows it fails loudly instead of slowly rotting CI.
  Context for choosing the number: Phase 1's baseline was 15.94s and the suite now runs
  ~25-26s as an owner-accepted overshoot, so headroom is already spent and the cap should be
  chosen deliberately rather than generously.

### Avatar scale — Open Question 12 RESOLVED

- **D-10: One canonical reference avatar capsule, used for every validity test, for every
  player, in CI and at runtime.** The rule function **takes no avatar argument**, so HIDE-07's
  scale-invariance is true *by construction* and criterion 2 is proven structurally rather than
  sampled. A test asserting the signature locks it. This is the same move that makes
  Non-Negotiable Rules 1 and 2 lint-enforced rather than promised, and it resolves OQ-12 in the
  direction that needs no platform verification.
  - **OQ-12 (avatar normalisation scope: spawn-time versus canonical reference avatar) is
    answered: canonical reference avatar.** Remove it from the open-decisions list.

- **D-11: The capsule is biased toward rejecting — short reach, tall headroom.** A single
  capsule cannot be conservative in both directions: for *reach* the safe choice is the
  shortest avatar, for *headroom and standability* the tallest. Deliberately harder to satisfy
  than any real avatar, so a spot the validator accepts is reachable for everyone. An
  unfindable spoon stalls a round; a culled spot costs nothing when the map carries margin
  (D-15). Erring toward rejection is the cheap direction.

### Rule list, reason codes and the numbers

- **D-12: First match wins over a locked rule order; exactly one reason per spot.** The same
  pattern Phase 2 locked for the engine's seven reject codes and the nine-name `Invariants`
  order. HIDE-02 shows the hider one reason, so runtime needs this anyway.
  - **Order: in-bounds → standable → reach → line-of-sight** — cheapest and most fundamental
    first, so a spot inside a wall reports *that* rather than a sightline failure. This is the
    same reasoning that put `circulation` (conservation) before `unsatisfiable` (stall
    statistics) in `Invariants.check`: the most expensive way to be wrong is to report a
    fundamental failure as a downstream symptom. **Lock the order the way Phase 2 locked its
    nine: in the types, in a comment, and in a test.**

- **D-13: Injected config + `src/shared/Config/Placement.luau` + a spec-lock test.**
  `SpoonPlacement` takes a `PlacementConfig` parameter and **never imports it**;
  `src/shared/Config/Placement.luau` holds the shipped numbers; a spec-lock test asserts the
  validator and the runtime both run on the shipped values.
  - **This is forced, not preferred.** `check-guards` R6 fails a pure-zone file that requires
    across a Rojo mount boundary — the `cross-mount` fixture proves it. It is exactly how
    `CardPool.luau` works today: **no file under `src/` requires it at all**, only tests do, and
    the engine takes its pool as `Pool.poolConfig`. Follow that precedent exactly.
  - **A missing or malformed config must be a loud error, never a silent default** — the
    `SeatOrder` injected-rng precedent from Phase 2.

- **D-14: One shared `PICKUP_RANGE` that Phase 5's hunt must consume, but the validator demands
  margin inside it.** A validated spot stays reachable despite character-controller jitter,
  imperfect footing, or a standing position that differs from the sampled cell centre.
  Consistent with D-11's bias. Two fully independent constants were rejected: nothing would tie
  them, so a Phase 5 or Phase 8 pickup-range tweak could silently invalidate every map's
  validation with no test to catch it. **The margin must be a named constant with its own test,
  not a magic number inside a comparison.**

- **D-15: If the real rules cull the graybox below 16, fix the map — never the rules, never the
  minimum.** The rules express HIDE-06 and 16 is a contract (MAP-03); if the reference map
  cannot satisfy both, the map is wrong. Regenerate the graybox with more spots and better
  margin. This keeps the rules a statement about findability rather than a curve fitted to one
  map — the same discipline as Phase 2 re-running its sweep at the selected operating point
  instead of trusting the fit. It matters more than usual because this phase gates Phase 7a
  authoring five more maps against these same rules.

- **D-16: The numeric values are proposed by research with their per-spot consequences, and
  confirmed by the owner at plan time.** Grid resolution, step-up height, max walkable slope,
  reach, clearance, pickup range and its margin. Research derives candidates from Roblox
  character dimensions and from the graybox's own geometry — the ramp is **24.9 degrees**
  (rise 6.5 over run 14), the ledge top is **6.5**, crates are **4**, the shelf top is **8.5**,
  the floor is **0** — and presents, for each candidate value, **which graybox spots it accepts
  and which it culls**, before anything is locked.
  - This is the bar-sensitivity-ladder approach that produced `k = 3`: the owner chooses the
    operating point with the trade-off visible, rather than ratifying a threshold nobody has
    seen the effect of.

### Confirmed after research (owner, 2026-11-04)

- **D-17: STRICT exclusion policy, and the graybox is regenerated.** Resolves Open Question 1
  above. Every authored default spot must pass; one issue per failing spot; any failure fails
  the build. Because the confirmed values leave exactly 16 of 18 surviving with zero spare,
  regenerating `scripts/maps/generate-graybox.luau` with spots that **all** pass, plus real
  margin above 16, is in scope for this phase. `Spot08` (shelf centre) is genuinely unfindable —
  blocked by line of sight from every floor position within 12.36 studs — and must not be
  re-authored in place. The tests that assert exactly 18 spots change with it
  (`tests/maps/graybox.spec.luau`, and the ~12 `validate(` call sites research identified).

- **D-18: the placement constants are CONFIRMED at research's recommended set.** These are the
  D-16 values, now locked, to live in `src/shared/Config/Placement.luau` per D-13:

  | Constant | Value |
  |---|---|
  | `GRID_SIZE` | 1.0 |
  | `STEP_UP` | 1.0 |
  | `MAX_SLOPE_DEGREES` | 30 |
  | `CAPSULE_RADIUS` | 1.5 |
  | `CAPSULE_HEIGHT` | 7.0 |
  | `REACH_HEIGHT` (root) | 2.5 |
  | `EYE_HEIGHT` | 4.0 |
  | `SPOT_CLEARANCE` | 0.25 |
  | `PICKUP_RANGE` | 7.0 |
  | `PICKUP_MARGIN` | 1.5 (effective range 5.5) |

  - **`EYE_HEIGHT` is a SEPARATE constant and that is load-bearing, not tidiness.** With one
    shared reach/eye height the crate-top spot (`Spot06`) requires an effective range of 8.75,
    gets culled, and the map falls to 15 — failing MAP-03. With a separate 4.0 eye height it
    requires 4.06. **Phase 5's hunt must consume the same `EYE_HEIGHT` and the same
    `PICKUP_RANGE`**, measured from the same root point.
  - **`PICKUP_RANGE` 7.0 was chosen for clean separation, not to rescue a spot.** At range 8.0
    with margin 1.5, `Spot09`'s verdict flips on a **0.04-stud** difference — decided by float32
    rounding. At 7.0 every authored spot sits at least 1 stud clear of a flip (`Spot06` 1.44,
    `Spot09` 1.04). Range 8.5 would buy a 17th survivor; it was rejected because choosing a
    gameplay constant to make map validation pass is D-15 running backwards.
  - **Two coupling invariants need their own tests, not comments.** `STEP_UP >= GRID_SIZE *
    tan(MAX_SLOPE_DEGREES)` — at `GRID_SIZE` 4 with step 1.0 the ramp disconnects. And
    `PICKUP_MARGIN >= GRID_SIZE * sqrt(2) / 2` (0.71 at g=1), so a later resolution change
    cannot silently invalidate the margin.
  - **The clearance cliff:** `SPOT_CLEARANCE >= 0.5` culls **all 18** spots, because every
    authored spot sits exactly 0.5 above its surface. 0.25 is deliberate headroom under a cliff
    edge; a test should assert the cliff exists so nobody "rounds it up" later.

- **D-19: the over-a-void corpus case is a synthetic micro-world fixture.** The graybox has no
  void (corrected above — the perimeter walls fill the ±60..62 band). A small hand-built
  geometry fixture in the test suite carries "no footing" and any other corpus case the
  reference map cannot express. Keeps corpus cases independent of map geometry, so regenerating
  the graybox under D-17 cannot silently delete a test case.

- **D-20: seat winding and seat-facing validation IS in scope.** Resolves the scope note below.
  Research sizes it at 60-90 lines, 2 issue codes, ~6 fixtures, about half a day, and it does
  **not** need the `up` vector (only the Bounds-roll item did, and D-02 closes that). Without
  it, every Phase 7a map could author seats in the wrong order with only a graybox-specific test
  to catch it.

### Claude's Discretion

- Internal structure of `SpoonPlacement` — whether the OBB/raycast/grid primitives split into
  their own module behind the policy. (D-04 fixed the guarded filename, not the file count.)
- Mesh and CSG handling. The graybox is all `Part`s; shipped maps are Phase 7a. Decide a
  defensible default and record it rather than solving it speculatively.
- Whether `ContractVersion` v1 maps are rejected outright or migrated. The graybox is the only
  v1 map and it is regenerated, so outright rejection is likely correct and cheapest.
- The exact new issue-code names, following the existing `MAP_` prefix convention and the
  `MapContract.ISSUE_CODES` coverage-test pattern.
- Grid origin/alignment and how bounds that are not an integer multiple of the resolution are
  handled.

</decisions>

<scope_note>
## One scope question the planner must settle explicitly — RESOLVED by D-20 (include it)

`MapValidator.luau`'s deferred-checks comment (written in Phase 1, D-12) lists **six** items as
Phase 3 work. Four are placement rules and clearly in scope. Two are not placement rules at all:

- **seat winding** (seats 1..9 clockwise) and **each seat's look vector pointing at the
  `TableAnchor`** — currently asserted for the graybox only, in `tests/maps/graybox.spec.luau`,
  not validated for arbitrary maps.
- **`Bounds` roll** — now solved for free by D-02's up vector, so this one closes itself.

Seat winding is structural, not placement, and is **not** named by any of this phase's four
requirements (HIDE-06, HIDE-07, MAP-02, MAP-03). **Recommendation: include it.** It is cheap
once `up` exists, it is already written down as Phase 3 work where the next planner will find
it, and leaving it means every Phase 7a map can author seats in the wrong order with only a
graybox-specific test to catch it. If the planner excludes it, say so explicitly and move the
comment's remaining lines to the phase that will own them — do not let it silently become
nobody's.

</scope_note>

<resolved_question_1>
## Open Question 1 — RESOLVED 2026-11-04 (owner): STRICT

"After exclusions" was undefined, and MAP-02 ("fails the build on **any** that would be
unfindable"), ROADMAP criterion 3 ("at least 16 ... after exclusions") and Phase 1's 18-spot
rationale ("so one can be culled") could not all hold.

**The owner chose STRICT: one issue per failing spot; every authored default spot must pass, and
the build fails on any failure.** It matches MAP-02's literal text and the phase goal. The
tolerant reading and a tag-based opt-out were both rejected — the latter because an author-
settable escape hatch reproduces the FOUND-05 filename-deny-list weakness the project already
knows about.

**Direct consequence, now in scope:** research measures exactly 16 of 18 graybox spots surviving
at the confirmed values, so under STRICT the **graybox must be regenerated** (D-17). This is
mandatory work in this phase, not a follow-up.

</resolved_question_1>
<must_haves>
## Non-negotiable for this phase

1. **The two snapshotters must emit identical `Node` shapes, and the test must cover `up` and
   `canCollide`.** This stops being hygiene and becomes the correctness foundation: with D-01,
   all geometric truth flows through the snapshot, so `scripts/maps/snapshot.luau` (CI, from a
   `.rbxm`) and `src/server/services/MapLoader.luau` (runtime, from a live tree) disagreeing
   means CI and the live game disagree about whether a spoon is findable. Phase 1 asserted this
   for the original three fields; extend it, do not assume it carries.

2. **Watch every new gate go red before trusting it green.** Phase 2's dominant lesson: roughly
   22 plan assertions proved structurally incapable of passing or firing, most caught by
   executors mutation-testing their own gates. Phase 1 contributed a fourth exit-code trap
   (`luau-lsp` exits 0 when the sourcemap fails to load). Every new issue code here needs a
   fixture that fails for that reason and only that reason — the nine-fixture `check-guards`
   pattern.

3. **Re-check the Verification Debt rows naming Phase 3 first** — V-17 to V-20 and V-4 in
   `.planning/research/SUMMARY.md` — and record what was confirmed or changed. Per CLAUDE.md,
   confidence may not be upgraded without re-fetching the primary source. The five Roblox doc
   hosts were still DNS-blocked as of Phase 2 close. D-01, D-05 and D-10 were each chosen partly
   to reduce how much this phase depends on unverified platform behaviour, but the reference
   avatar's dimensions and the walkable-slope limit are still platform facts.

4. **The placement corpus is the deliverable criterion 1 names**, not a by-product: known-good
   and known-bad coordinates — shelf out of reach, inside a wall, no line of sight, over a void
   — each producing the expected verdict *with its reason*. The graybox was built with this
   corpus in mind (`Core` is solid, `ShelfSouthEastRoom` is high, the pillars occlude, the floor
   stops at ±60 inside bounds of ±62). Assert reason codes, never prose — the existing
   validator-test convention.

</must_haves>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The map contract and validator being extended
- `src/server/core/MapContract.luau` — `Node`, `MapSpec`, `Issue`, `Pose`, `Aabb` types;
  `CONTRACT_VERSION`, `MIN_DEFAULT_SPOTS = 16`, `SEAT_COUNT = 9`, the three tags, and the
  12-entry `ISSUE_CODES` list the tests assert full coverage of.
- `src/server/core/MapValidator.luau` — the structural validator. **Lines 7-14 are Phase 1's
  explicit deferred-checks list for this phase.** Issues sorted by (code, path, message);
  `spec` is non-nil only when `issues` is empty.
- `scripts/maps/snapshot.luau` — the CI snapshotter. Note assumption A5 in its header: position
  and look are read from the CFrame because the derived `Position` property is not readable on a
  deserialized Part under Lune 0.11.1.
- `src/server/services/MapLoader.luau` — the runtime snapshotter. Must stay shape-identical.
- `scripts/maps/validate-map.luau` — the CI/dev CLI; prints `<CODE> <path> <message>`, exits 1
  on any issue.
- `scripts/maps/generate-graybox.luau` — the reference map generator. The 18-spot table with
  per-spot comments, the `Ramp` construction, `Ledge`, `ShelfSouthEastRoom`, `Core`, the
  pillars and crates.
- `tests/maps/validator.spec.luau` (525 lines) and `tests/maps/graybox.spec.luau` (291 lines) —
  the existing assertion conventions, including the exactly-18-spots assertion.

### Guards that constrain where code may live
- `scripts/ci/zones.luau` — `pureZones = { "src/server/engine", "src/server/core",
  "src/shared/Net" }`. `src/server/core` is a pure zone, which is the origin of D-01 and D-13.
- `scripts/ci/check-guards.luau` — R1 strict header, R2 FOUND-05 transitive import ban
  (`guardedNamePrefixes` includes `SpoonPlacement`), R3 pure-zone construct bans incl.
  `coroutine` and `os.`, R3b suppression ban, **R6 DataModel/disk require agreement — the
  cross-mount rule that forces D-13**.
- `tests/guards/fixtures/cross-mount/` — the fixture proving a pure-zone cross-mount require
  fails.

### Prior decisions and the precedents being followed
- `.planning/phases/01-foundations-contracts-and-spec-lock/01-CONTEXT.md` — **D-12** (structural
  now, placement rules in Phase 3, same tool), **D-18** (graybox is Lune-generated; the
  precedent D-08 follows), **D-19** (bounds is one axis-aligned box; its own escape hatch for
  a union of volumes), **D-07**, **D-08**, **D-20**.
- `.planning/phases/01-foundations-contracts-and-spec-lock/01-07-SUMMARY.md` — §"Deferred to
  Phase 3" and line 239, the up-vector gap D-02 closes. Also the 18-vs-16 rationale.
- `.planning/phases/02-card-engine-and-pacing-simulator/02-CONTEXT.md` — the locked-order and
  first-match-wins precedents D-12 follows.
- `src/shared/Config/CardPool.luau` + `tests/engine/spec_lock.spec.luau` — **the exact pattern
  D-13 replicates.** Read both together: the config module holds the shipped values, nothing
  under `src/` imports it, the spec-lock test asserts agreement.
- `.planning/research/SUMMARY.md` — the Verification Debt table; re-check the rows naming
  Phase 3 (V-17..V-20, V-4) before anything else.
- `.planning/ROADMAP.md` §"Phase 3" — the four success criteria and Gate G2.
- `.planning/REQUIREMENTS.md` — HIDE-06 (line 59), HIDE-07 (60), MAP-02 (107), MAP-03 (108).
  Also HIDE-01/02/05 and HUNT-02/03 for what later phases will consume from this rule set.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- **`MapValidator.validate(root)`** — extend in place per D-12. Its sorted-deterministic-issues
  convention, `requireFolder`/`requirePart` helpers and `LOOK_EPSILON` are all directly reusable.
- **The graybox's geometry is already the placement corpus.** It was authored for this phase:
  `Core` (32x32 solid) for inside-a-wall, `ShelfSouthEastRoom` (top 8.5) for out-of-reach,
  `PillarWest`/`PillarEast` for occlusion in an open room, `CrateEastHall`/
  `CrateSouthWestRoom` (top 4) for standable-beside, and the `Ledge` + `Ramp` for step-up and
  slope.
  - **CORRECTED 2026-11-04 (03-RESEARCH, verified independently): the graybox has NO
    over-a-void case.** This document previously claimed the ±60..62 band was in-bounds with no
    floor. It is wrong: `WALL_HEIGHT = 20` and `WALL_THICKNESS = 2`, so each perimeter wall
    (e.g. `WestWall` at x = -61) fills x ±60..62 solidly from y 0 to 20. Probing there yields
    inside-a-wall, no-line-of-sight or out-of-reach depending on height — never "no footing".
    A real no-footing case must be authored: research recommends a **synthetic micro-world
    fixture** over adding a pit to the graybox. Criterion 1 names "over a void" explicitly, so
    this is required work, not optional.
- **18 spots against a 16 minimum**, deliberately, "so Phase 3's placement rules can cull some
  without breaking the contract". Heights: **11 floor (y=0)**, 1 crate-top (4), 4 ledge (6.5),
  2 shelf (8.5). The 2 shelf spots are indeed what research's recommended values cull — leaving
  **exactly 16, with zero spare**, which triggers D-15 immediately.
  - **This collides with MAP-02 and is now Open Question 1** — see `<open_question_1>` below.
- **`tests/harness/Fuzz.luau`** — the stateful fuzz driver from Phase 1/2. The OBB raycast and
  the flood-fill are both good fuzz targets (e.g. a cell marked reachable must have a path, a
  ray must agree with a brute-force box test).

### Established patterns
- Pure module takes injected config; shipped values live in a non-pure config module; a
  spec-lock test asserts agreement. (`CardPool` / `Pool.poolConfig` / `spec_lock.spec.luau`)
- Stable string codes, asserted by code and never by prose, with a coverage test over the
  declared code list. (`MapContract.ISSUE_CODES`)
- Locked evaluation order recorded three ways — in the types, in a comment in both files, and in
  a test. (`Invariants.check`'s nine violation names)
- Guard rules proven by fixtures that fail for exactly one reason. (`tests/guards/fixtures/`,
  nine of them)
- Injected dependencies are mandatory; absence is a loud error, never a fallback. (`SeatOrder`'s
  rng)

### Integration points
- `MapValidator` ← `SpoonPlacement` (new): per-default-spot verdict after the structural pass.
- `MapContract.Node` → both snapshotters: the v2 fields must land in `snapshot.luau` **and**
  `MapLoader.luau`.
- `MapContract.ISSUE_CODES` → the new placement codes, plus the coverage test.
- `scripts/verify.luau` (currently 14/14) and the CI gate chain → the maze bake cap (D-09).
- `src/shared/Config/Placement.luau` (new) → consumed by Phase 5's hunt for `PICKUP_RANGE`
  (D-14) and by Phase 6's hide UI for the reason codes (D-12).

</code_context>

<specifics>
## Specific Ideas

- The ramp is **24.9 degrees** (rise 6.5 over run 14, from the generator's own math). Any
  max-walkable-slope value below that silently disconnects the ledge and takes 4 spots with it.
  This number should appear in a test comment, not be rediscovered.
- `Bounds` is ±62 on x/z and -1..29 on y while the `Floor` is 120x120 (±60) — but the band
  between ±60 and ±62 is **filled by the perimeter walls** (thickness 2, height 20, y 0..20),
  so it is not a void. See the correction under Reusable assets.
- Seat anchors are on a radius-6 ring at 40-degree spacing around `(0, 3, -40)`, oriented by
  `CFrame.lookAt` at the table anchor — the ground truth if seat winding is included per the
  scope note.
- The graybox is `Medium` `SizeClass`, 3..10 players, `ContractVersion 1` — all four attributes
  move to v2 together.

</specifics>

<deferred>
## Deferred Ideas

- **Clamping avatar scaling in the place's avatar settings.** Raised while discussing HIDE-07:
  D-10 makes *placement validity* scale-independent, but a very small avatar may still be
  genuinely harder to *see* during the hunt. That is a hunt-fairness question for Phase 5, or a
  tuning question for Phase 8 on telemetry — not a placement rule. Note that `Players.MaxPlayers`
  is already a Creator-Dashboard-only setting (MANUAL-CHECKS M-05), so this would likely be
  another out-of-repo control with the same auditability problem as FOUND-07.
- **Union-of-volumes bounds.** D-19 explicitly anticipated this: "if Phase 3's placement work
  shows this is too loose, the contract can move to a union of volumes then — it is a contract
  change, not a rewrite." Multi-layer height fields (D-07) may make the coarse single AABB
  tolerable. Revisit only if the mansion's multi-floor validation actually needs it; do not
  pre-emptively change the contract.
- **Separate collision and sight sets** (glass blocks walking but not seeing; foliage the
  reverse). Considered and rejected for v1 under D-03 — two solidity fields plus a per-part
  authoring decision in all five shipped maps. Revisit if Phase 7a authoring hits it for real.
- **`ProximityPrompt.Triggered` and friends are unguarded client-to-server paths.** Carried from
  Phase 1 verification and still open: `check-guards` R4's `netOwners` guard covers only
  `Remote*` members. Phase 5's spoon-pickup affordance is where the first one appears. Named here
  only so it is not lost — it is a **Phase 5** item, not this phase's.

</deferred>

---

*Phase: 03-placement-rules-map-pipeline-and-validator*
*Context gathered: 2026-11-04*
