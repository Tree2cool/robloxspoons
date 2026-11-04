# Phase 3: Placement Rules, Map Pipeline and Validator - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-04
**Phase:** 3 - Placement Rules, Map Pipeline and Validator
**Areas discussed:** Geometry source & rule engine; Reachability model; Avatar scale (Open Question 12); Rule list, reason codes & the actual numbers
**Mode:** interactive (`discuss`), advisor mode off (no USER-PROFILE.md), all four offered areas selected

---

## Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Geometry source & rule engine | Pure-data OBB world vs real raycasts vs two-tier | ✓ |
| Reachability model | Flood-fill vs PathfindingService; the ramp/ledge trap | ✓ |
| Avatar scale (Open Question 12) | Canonical reference avatar vs per-player normalisation | ✓ |
| Rule list, reason codes & the actual numbers | Rule set, verdict semantics, constants | ✓ |

---

## Geometry source & rule engine

### Q: How should the placement rules see the map's collision geometry?

| Option | Description | Selected |
|--------|-------------|----------|
| Pure-data OBB world | Extend Node with orientation; own raycast + walkability in the pure zone; one implementation for CI and runtime | ✓ |
| Real Roblox raycasts + Pathfinding | Max fidelity; leaves the pure zone; CI no longer headless; rests on unverified platform behaviour | |
| Two-tier: pure CI + real runtime | Best tool per tier; two implementations of one rule set that can disagree | |
| Pure in CI, no runtime check | Smallest phase; HIDE-06 would cover default spots only, not free placement | |

**User's choice:** Pure-data OBB world (recommended)
**Notes:** Driven by the pure-zone constraint — `src/server/core/` is in `zones.luau`'s `pureZones`, and `check-guards` R3 bans Roblox API there with no suppression mechanism. MAP-02's wording ("the real placement rules") makes a second CI-only implementation a contract violation rather than a shortcut. Accepted limitation recorded in CONTEXT: this is our model of collision, not Roblox's.

### Q: How far should the Node orientation contract change go?

| Option | Description | Selected |
|--------|-------------|----------|
| Add an up vector, bump to v2 | `up` alongside `look`, third basis by cross product; graybox regenerated | ✓ |
| Add up + right explicitly | All three basis vectors; redundant but allows an orthonormality assertion | |
| Quaternion or 3x3 | Compact and unambiguous; reads poorly in the existing hand-written fixtures | |
| Keep v1, ban rotated geometry | No contract change; would ban ramps and slopes from every map | |

**User's choice:** Add an up vector, bump to v2 (recommended)
**Notes:** Surfaced before the question as a booby trap, not discovered during it. Phase 1 logged the gap at `01-07-SUMMARY.md:239`. A roll about Z does not change the look vector, so the graybox `Ramp` snapshots flat under v1; the ramp is the only route onto the `Ledge`; 4 of 18 default spots are on that ledge; culling them leaves 14 against `MIN_DEFAULT_SPOTS = 16`. Also closes the "Bounds roll" deferred item for free.

### Q: Which parts count as solid for walkability and line-of-sight?

| Option | Description | Selected |
|--------|-------------|----------|
| CanCollide=true only, add canCollide to Node | Matches what blocks a player; stops set dressing inventing surfaces or blocking sight | ✓ |
| Every BasePart under Geometry/ is solid | No new field; conservative for walkability, wrong for line-of-sight in the unsafe direction | |
| Separate collision and sight sets | Most faithful (glass, foliage); two fields plus per-part authoring burden in all five maps | |

**User's choice:** CanCollide=true only (recommended)
**Notes:** Taken while the contract was being bumped anyway. The rejected third option is recorded as a deferred idea for Phase 7a.

### Q: Where should the rule set live, given FOUND-05 guards the name `SpoonPlacement`?

| Option | Description | Selected |
|--------|-------------|----------|
| src/server/core/SpoonPlacement.luau | Standalone pure module; MapValidator and the runtime hider check call the same function | ✓ |
| Inside MapValidator.luau | What D-12's comment literally describes; puts a geometry engine in a structural validator | |
| Split: rules module + geometry module | Clearest seam; the policy half still needs the guarded name | |

**User's choice:** `src/server/core/SpoonPlacement.luau` (recommended)
**Notes:** Lands on the exact filename already in `check-guards`'s `guardedNamePrefixes`, so the FOUND-05 guard stops being hypothetical. Internal file count left to Claude's discretion.

---

## Reachability model

### Q: How should 'reachable' be computed?

| Option | Description | Selected |
|--------|-------------|----------|
| Walkable-grid flood-fill | Pure, deterministic, headless; the grid is the natural maze-bake artefact | ✓ |
| PathfindingService queries | Matches real navigation; cannot live in the pure zone, contradicts the geometry decision | |
| Local standability only, no path | Much cheaper; a spot sealed in the core would pass and "reachable" goes unchecked | |

**User's choice:** Walkable-grid flood-fill (recommended)
**Notes:** Roadmap flagged this for a spike on the maze. The second option was already excluded by the geometry decision one question earlier.

### Q: What should 'reachable' be measured FROM?

| Option | Description | Selected |
|--------|-------------|----------|
| Flood-fill from all seeker spawns | Encodes the real requirement: a seeker starting where seekers start can get there | ✓ |
| From the hider spawn | Answers whether the hider could place it, not whether it is findable (HIDE-09 separates them) | |
| Any single connected walkable region | Robust to spawn authoring mistakes; stops catching the real bug | |

**User's choice:** Flood-fill from all seeker spawns (recommended)
**Notes:** Free sanity check noted — the graybox's 4 corner-room spawns should all land in one connected region, and a test asserting that validates map and flood-fill together.

### Q: How should the walkable grid be structured?

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-layer height field | 2D columns each holding a list of standable heights; cost scales with footprint x layers | ✓ |
| Full 3D voxel grid | Multi-floor for free; ~461,000 mostly-air cells over the graybox bounds alone | |
| Surface sampling from geometry | Cost proportional to part count; cross-part stitching is where a bug would hide | |
| Single-height 2D grid | Smallest and fastest; cannot represent a floor above a floor, rules out MAP-07 | |

**User's choice:** Multi-layer height field (recommended)
**Notes:** The mansion (MAP-07) being multi-floor is what eliminates the fourth option outright.

### Q: Where should Gate G2's maze stress fixture come from, given MAP-08 is Phase 7a?

| Option | Description | Selected |
|--------|-------------|----------|
| Lune-generated synthetic maze | Follows D-18's precedent; parameterised so stress is a dial; gives Phase 7a a target | ✓ |
| Scale up the graybox | One generator to maintain; tests grid size but not maze-like connectivity | |
| Synthetic grid only, no .rbxm | Tightest measurement; never exercises snapshot -> OBB -> grid, the path CI actually runs | |

**User's choice:** Lune-generated synthetic maze (recommended)

### Q: What's the CI time budget for the reachability bake?

| Option | Description | Selected |
|--------|-------------|----------|
| Hard cap, asserted by a test | Budget becomes a locked contract; a map that blows it fails loudly | ✓ |
| Measure and record, don't gate | No flaky timing test; nothing stops drift and Phase 7a authors against no budget | |
| Gate on cell count, not wall time | Immune to runner variance; a proxy can stay green while real time regresses | |

**User's choice:** Hard cap, asserted by a test (recommended)
**Notes:** Context given: Phase 1 baseline 15.94s, suite now ~25-26s as an owner-accepted overshoot, so headroom is already spent.

---

## Avatar scale (Open Question 12)

### Q: How should avatar scale be handled?

| Option | Description | Selected |
|--------|-------------|----------|
| Canonical reference avatar | One fixed capsule for everyone; the rule function takes no avatar argument, so HIDE-07 is true by construction | ✓ |
| Per-player actual avatar, then normalise | Most faithful; criterion 2 becomes sampled not proven, and the validator has no real avatar at build time anyway | |
| Two-capsule envelope | Conservative in both directions at once; roughly doubles bake cost, can reject spots fine for every real avatar | |

**User's choice:** Canonical reference avatar (recommended)
**Notes:** **Open Question 12 is resolved by this answer** — the roadmap listed it as due this phase. Chosen so criterion 2 is proven structurally (a signature test) rather than sampled across a scale corpus, matching how Non-Negotiable Rules 1 and 2 are lint-enforced rather than promised. Also the option needing least platform verification.

### Q: Which way should the single capsule be biased when reach and headroom disagree?

| Option | Description | Selected |
|--------|-------------|----------|
| Bias toward rejecting | Short reach AND tall headroom; harder to satisfy than any real avatar | ✓ |
| Bias toward the default avatar | Matches the common case, culls fewest spots; extremes get someone else's verdict | |
| Bias toward accepting | Most hider expressiveness; admits spots some avatars cannot reach | |

**User's choice:** Bias toward rejecting (recommended)
**Notes:** The sharp edge was surfaced before the question: a single capsule cannot be conservative in both directions, because reach wants the shortest avatar and headroom wants the tallest. Rationale for the direction — an unfindable spoon stalls a round, a culled spot costs nothing while the map carries margin.

---

## Rule list, reason codes & the actual numbers

### Q: When a spot fails several rules at once, what should the verdict be?

| Option | Description | Selected |
|--------|-------------|----------|
| First match wins, locked rule order | One reason per spot; the pattern Phase 2 locked for engine rejects and the Invariants order | ✓ |
| Collect all failures per spot | Consistent with existing structural output; runtime still has to pick one, in untested UI code | |
| First match for runtime, collect-all in CI | Best per audience; two evaluation modes that can drift | |

**User's choice:** First match wins, locked rule order (recommended)
**Notes:** Order recorded as in-bounds → standable → reach → line-of-sight, cheapest and most fundamental first, by the same reasoning that put `circulation` before `unsatisfiable` in `Invariants.check`. To be locked three ways (types, comment, test) following Phase 2's nine-name precedent.

### Q: How should the placement constants be held, given R6 blocks a pure-zone cross-mount import?

| Option | Description | Selected |
|--------|-------------|----------|
| Injected config + shared module + spec-lock test | The CardPool pattern; R6 effectively forces it | ✓ |
| Constants inside SpoonPlacement.luau | No plumbing; no single place to read or change shipped values, no spec-lock target | |
| Constants in MapContract.luau | One module, already shared; conflates map format with gameplay tuning | |

**User's choice:** Injected config + `src/shared/Config/Placement.luau` + spec-lock test (recommended)
**Notes:** Surfaced during the discussion, not assumed: `check-guards` R6 fails a pure-zone file requiring across a Rojo mount boundary (proven by `tests/guards/fixtures/cross-mount/`). Verified that **no file under `src/` requires `CardPool.luau` at all** — only tests do, and the engine takes its pool as `Pool.poolConfig`. So this is the forced solution, not merely the precedented one. Missing config must be a loud error (the `SeatOrder` rng precedent).

### Q: Should the validator use the hunt's real pickup range, or demand margin?

| Option | Description | Selected |
|--------|-------------|----------|
| Validator demands a margin | One shared PICKUP_RANGE Phase 5 must consume; validator requires the standable spot comfortably inside it | ✓ |
| Exactly the hunt's pickup range | Impossible to drift; boundary spots may be unreachable in practice, invisibly | |
| Two independent constants | Max tuning freedom; a Phase 5/8 tweak could silently invalidate every map with no test to catch it | |

**User's choice:** Validator demands a margin (recommended)
**Notes:** Consistent with the bias-toward-rejecting avatar choice. The margin must be a named constant with its own test, not a magic number in a comparison.

### Q: If the real rules cull the graybox below 16, what gives?

| Option | Description | Selected |
|--------|-------------|----------|
| Fix the map, never the rules | Rules express HIDE-06 and 16 is a contract; regenerate the graybox with more margin | ✓ |
| Loosen rules to keep 18 valid | Fastest green gate; rules become a curve fitted to one map | |
| Lower MIN_DEFAULT_SPOTS | Honest in its own way; MAP-03 is an explicit v1 requirement and HIDE-05 auto-fill depends on the count | |

**User's choice:** Fix the map, never the rules (recommended)
**Notes:** Weight came from this phase gating Phase 7a, which authors five more maps against these same rules.

### Q: Who should pick the actual numeric values?

| Option | Description | Selected |
|--------|-------------|----------|
| Research proposes, owner confirms at plan time | Candidates presented with which graybox spots each accepts or culls, before locking | ✓ |
| Pick sensible values now, tune if tests fail | Fastest; thresholds chosen without seeing their effect | |
| Derive every number from the reference avatar | Fewest knobs, most defensible; couples grid cost to avatar size, no capsule analogue for max slope | |

**User's choice:** Research proposes, you confirm at plan time (recommended)
**Notes:** Explicitly the bar-sensitivity-ladder approach that produced `k = 3` in Phase 2 — the owner chooses the operating point with the trade-off visible. Graybox reference heights to be used as the ladder: floor 0, crates 4, ledge 6.5, shelf 8.5, ramp 24.9 degrees.

---

## Claude's Discretion

- Internal structure of `SpoonPlacement` (whether geometry primitives split into their own module).
- Mesh and CSG handling — graybox is all `Part`s; shipped maps are Phase 7a.
- Whether `ContractVersion` v1 maps are rejected outright or migrated.
- The exact new issue-code names, following the `MAP_` prefix and `ISSUE_CODES` coverage-test convention.
- Grid origin/alignment and non-integer-multiple bounds handling.

## Scope question raised for the planner

`MapValidator.luau`'s Phase 1 deferred comment lists six items; two are not placement rules — **seat winding / seat-looks-at-table** (currently graybox-only assertions) and **Bounds roll** (now closed for free by the up vector). Seat winding is not named by any of this phase's four requirements. Recommendation recorded in CONTEXT: include it, or exclude it explicitly and move the comment lines to the owning phase — do not let it become nobody's.

## Deferred Ideas

- Clamping avatar scaling in the place's avatar settings — hunt fairness, Phase 5 or Phase 8.
- Union-of-volumes bounds — D-19's own anticipated escape hatch; revisit only if mansion validation needs it.
- Separate collision vs sight sets (glass, foliage) — rejected for v1; revisit if Phase 7a hits it.
- `ProximityPrompt.Triggered` and friends unguarded by `check-guards` R4 — carried from Phase 1 verification, a **Phase 5** item, named here only so it is not lost.
