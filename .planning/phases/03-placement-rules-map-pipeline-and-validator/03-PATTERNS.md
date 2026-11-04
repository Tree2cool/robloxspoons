# Phase 3: Placement Rules, Map Pipeline and Validator - Pattern Map

**Mapped:** 2026-11-04
**Files analyzed:** 17 (8 new, 9 modified)
**Analogs found:** 17 / 17 (one new file, `Placement.luau`, has a role-match analog with a deliberate wiring difference)

## Two hazards (read first)

### Hazard 1: `check-guards` R3 bans the substring `os.` in pure zones

`scripts/ci/check-guards.luau` lines 394-409: a plain `string.find(sf.text, "os.", from, true)` over text that
KEEPS string literals. Comments are stripped (so comments are safe in the guard itself, but do not rely on that for
anything inside a string). Pure zones are `src/server/engine`, `src/server/core`, `src/shared/Net`
(`scripts/ci/zones.luau` line 9). `src/server/core/SpoonPlacement.luau` and any new core helper are in scope;
`src/shared/Config/Placement.luau` is NOT a pure zone but keep the same discipline (it is also read by pure-zone-adjacent tests).

Things that FAIL: `pos.x`, `cos.`, `dos.`, `los.` (line of sight), `repos.`, `typos.`, and any string literal
or message such as `"zeros."` or `` `...{count} photos.` ``. `math.cos(` is fine (`cos(` is not `os.`), `math.cos` alone
is fine; `local cos = math.cos(a)` is fine but then `cos.` never appears. The hazard is an identifier or word
ending in `os` immediately followed by `.`.

Existing convention (verified by grep: zero `os.` in `src/server/core` and `src/server/engine`): the files never
abbreviate to `pos`. `MapValidator.luau` uses the full word `position` (`node.position`, `poseOf`), `p` for a
point (`inside(box, p)` lines 72-79), `box`, `size`, `look`, `seat`, `pose`.

Recommended convention for this phase (state it in the SpoonPlacement header comment):
- Point/vector locals: `p`, `q`, `a`, `b`, `pt`, `at`, `centre`, `origin`, `delta`, `axis`, `normal`, `corner`.
- Never `pos`, `cos`, `los`, `dos`. Write `position` in full, and name a cosine `cosine`, a line-of-sight value `sight`.
- Rotation helpers: `cosine`/`sine` locals (`local cosine = math.cos(angle)`).
- Do not end a sentence in a string or message with a word ending `os` (`"zeros."`, `"photos."`). Prefer `{x}` templates.
- Run `lune run scripts/ci/check-guards.luau` (or `scripts/verify.luau`) after every edit of a pure-zone file, not
  only at the end. The match is also case-sensitive, so `OS.` passes but do not rely on that.

### Hazard 2: R6 cross-mount rule, and what it means for `Placement.luau`

`check-guards` R6 fails a file under `src/server` that requires `src/shared` (resolves on disk, fails in the
DataModel). Fixture: `tests/guards/fixtures/cross-mount/src/server/engine/Bad.luau`:
```luau
--!strict
local Config = require("../../shared/Config")
return { limit = Config.limit }
```
Consequences, verified in the repo:
- No file under `src/server/core` or `src/server/engine` may `require` `src/shared/Config/Placement`.
  `SpoonPlacement.check` and `MapValidator.validate` RECEIVE the config as a parameter (D-13/D-18).
- `src/shared/Config/CardPool.luau` is required by NO `src/` file (grep: only tests). It is a bare
  `return { ... }` table with a long rationale header (see below).
- The ONLY `src/` consumer pattern is a service (not pure) requiring through the DataModel path:
  `src/server/services/RoundDriver.luau` line 18 `local Config = require(ReplicatedStorage.Shared.Config.Round)`,
  `src/server/services/Persistence.luau` line 17 `require(ReplicatedStorage.Shared.Config.Environments)`.
  So `MapLoader` (a service) is the runtime wiring point: `require(ReplicatedStorage.Shared.Config.Placement)` and pass
  it into `MapValidator.validate(snapshot, Placement)`. The Lune CLI `scripts/maps/validate-map.luau` and tests require
  by relative path `../../src/shared/Config/Placement` (scripts and tests are outside R6's `shippedDirs`).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/server/core/SpoonPlacement.luau` (new) | service-logic (pure rule set) | transform | `src/server/core/MapValidator.luau` + `src/server/engine/Invariants.luau` | role-match |
| `src/shared/Config/Placement.luau` (new) | config | none (constants) | `src/shared/Config/CardPool.luau` | exact |
| `src/server/core/MapContract.luau` (mod) | model/contract | transform | itself (lines 17-80) | exact |
| `src/server/core/MapValidator.luau` (mod) | validator | transform | itself (lines 1-14 deferred list; 330-375 tail) | exact |
| `src/server/services/MapLoader.luau` (mod) | service (Roblox snapshotter) | request-response | `scripts/maps/snapshot.luau` (twin) | exact |
| `scripts/maps/snapshot.luau` (mod) | utility (Lune snapshotter) | file-I/O | `src/server/services/MapLoader.luau` (twin) | exact |
| `scripts/maps/validate-map.luau` (mod, config arg) | CLI | file-I/O | itself | exact |
| `scripts/maps/generate-graybox.luau` (mod, v2) | generator | file-I/O | itself | exact |
| `scripts/maps/generate-maze.luau` (new) | generator | file-I/O | `scripts/maps/generate-graybox.luau` | exact |
| `maps/gray-box.rbxm` (regenerated) | asset | file-I/O | itself | exact |
| `tests/placement/obb.spec.luau` (new) | test | fuzz | `tests/engine/pool.spec.luau` (`t.fuzz`) + `tests/engine/fuzz.spec.luau` | role-match |
| `tests/placement/walkgrid.spec.luau` (new) | test | fuzz + unit | `tests/engine/fuzz.spec.luau`, `tests/engine/valve.spec.luau` | role-match |
| `tests/placement/corpus.spec.luau` (new) | test | table-driven unit | `tests/maps/validator.spec.luau` (case table, lines 396-470) | role-match |
| `tests/placement/config_lock.spec.luau` (new) | test | unit | `tests/engine/spec_lock.spec.luau` | exact |
| `tests/placement/maze.spec.luau` (new) | test | integration | `tests/maps/graybox.spec.luau` | role-match |
| `tests/maps/validator.spec.luau` (mod) | test | unit | itself | exact |
| `tests/maps/graybox.spec.luau` (mod) | test | integration | itself | exact |

## Pattern Assignments

### `src/server/core/SpoonPlacement.luau` (pure rule set, transform)

**Analogs:** `src/server/core/MapValidator.luau` (shape of module) and `src/server/engine/Invariants.luau` (locked order).

**Header and type-import pattern** (`MapValidator.luau` lines 1-26):
```luau
--!strict
-- MAP-01 structural validator. PURE ZONE: plain data in, plain data out, no Roblox API.
--
-- validate(root) returns (issues, spec). `spec` is non-nil ONLY when `issues` is empty. Issues are sorted by
-- (code, path, message) so output is deterministic. Tests assert the CODE, never the prose.
local MapContract = require("./MapContract")

type Node = MapContract.Node
type Issue = MapContract.Issue
type Vec3 = MapContract.Vec3
type Aabb = MapContract.Aabb
```
Relative `./` requires only, string literals only (R3). `--!strict` first line (R-strict).

**Stable codes as locals + plain-data helpers** (lines 28-79):
```luau
local BOUNDS_INVALID = "MAP_BOUNDS_INVALID"
...
local function inside(box: Aabb, p: Vec3): boolean
	return p.x >= box.min.x
		and p.x <= box.max.x
		and p.y >= box.min.y
		...
end
```
Copy: point named `p`, box named `box`, full-word `position`. New placement codes become locals in the same style
and MUST also be added to `MapContract.ISSUE_CODES` (the spec asserts every listed code has a case, see
`validator.spec.luau` lines 485-493).

**Deterministic ordering** (`MapValidator.luau` ~line 322-332, the `table.sort(issues, ...)` ending
`return a.message < b.message`). Reuse the same comparator (code, then path, then message) for placement issues so
the merged list stays sorted; the placement pass runs AFTER the structural pass and the sort must cover both
(sort once at the end, or sort the placement issues with the identical comparator and re-sort the union).

**Locked order recorded three ways** (`Invariants.luau` lines 12-17 comment; `Types.luau` lines 107-118 the
`Violation` union with comment "Never reorder this to make an assertion pass"; plus a spec that asserts the order).
Apply to the REASON-CODE precedence of `check` (the first failing rule wins, per D-decisions): put the ordered
list in (1) the exported type (`export type Reason = "..." | ...` in declaration order), (2) a comment in BOTH
SpoonPlacement and Placement-related test, (3) a corpus/test case that builds a spot violating two rules and asserts
the earlier one is reported. Copy the Invariants phrase: "The order is LOCKED ... Never reorder this to make an
assertion pass."

**Signature lock (D-10, vacuous gate 6):** `check(spot, world, config)` has exactly 2 params after currying or 3
total per RESEARCH; VALIDATION says `debug.info(SpoonPlacement.check, "a") == 2`, so confirm against 03-RESEARCH
(no avatar argument). No existing `debug.info` use in repo (grep returned none), so this is a new idiom: build it in
`config_lock.spec.luau` or `placement` spec as `t.equal(debug.info(SpoonPlacement.check, "a"), 2)`.

**Injected config, loud failure** (analog `src/server/engine/SeatOrder.luau` lines 130-136):
```luau
local rng: any = input.rng
if rng == nil then
	-- Loud on purpose. A silent fallback to the global generator would make round 1
	-- unreproducible and break every seeded simulator trial.
	error("SeatOrder: round 1 requires an rng")
end
```
Copy for config: `if config == nil then error("SpoonPlacement: a PlacementConfig is required") end`. Prefix
message with the module name, comment WHY it is loud, no default table anywhere in `src/server/**`. Also validate the
config shape (finite positive numbers, the two coupling invariants of D-13/D-18) with the same style as
`Admission.luau` `isCount` (lines 12-21: `type(v) == "number"` first, `v == v` for NaN, inf comparisons).

**Return shape:** export `return { check = check, ... }` table of functions like `MapValidator.luau` lines 372-375
(`return { validate = validate }`).

**Purity:** no `os`, no `coroutine`, no yields, no Roblox types (Vector3, CFrame, `Instance`, `workspace`). `math.*`
and `table.*` only. No yielding, no clock. No require of any cosmetics or shop module (non-negotiable rule 1).

---

### `src/shared/Config/Placement.luau` (config)

**Analog:** `src/shared/Config/CardPool.luau` (lines 1-58). Pattern:
```luau
--!strict
-- <long rationale header: decision IDs, evidence file, why each value, which constraints are on a later phase>
return {
	EXTRA_RANKS = 3,
	JOKERS = 1,
	JOKER_MODE = "Wild",
	ANTI_LIVELOCK_VALVE = true,
	AUTO_PASS_MAX_SECONDS = 8.0,
	AUTO_PASS_SELECTION = "uniform-random-from-hand",
}
```
Copy: bare `return {}` of UPPER_SNAKE constants, no functions, no requires, header states explicitly "The engine
never requires this module ... guard rule R6 forbids it; the adapter reads from here and passes the values in"
(`CardPool.luau` lines 14-17). Header should name D-IDs and the manual check that `CharacterMaxSlopeAngle >= MAX_SLOPE_DEGREES`
(VALIDATION manual-only row). Keep `MAX_SLOPE_DEGREES` etc as plain numbers. If a type is useful, define the config
TYPE in `SpoonPlacement.luau` (the pure zone) and let this file stay untyped values, so no `src/shared` -> `src/server`
require is needed either (a shared file requiring `src/server` is also cross-mount).

**Shipped-value lock:** `tests/engine/spec_lock.spec.luau` lines 17-45 requires `../../src/shared/Config/CardPool`
by relative path and builds the injected value from it (`shippedConfig(seatCount)`), then asserts the DECISION
(lines 1-15 of its header: zero todos, narrow cases). Mirror in `config_lock.spec.luau`.

---

### `src/server/core/MapContract.luau` (modify)

Existing excerpts to extend (lines 29-33, 40-50, 52-80):
- `Node` (lines 40-50): add `up: Vec3?`, `canCollide: boolean?`, `shape: string?` (or the enum the research chose)
  beside `look`, `anchored`. Keep the comment "position/size/look are present for Parts and absent for Models and Folders"
  updated to name the new fields.
- `CONTRACT_VERSION = 1` -> `2` (line 53).
- `ISSUE_CODES` (lines 61-74): list is ALPHABETICALLY sorted; insert new `MAP_*` placement codes in sorted position
  and keep `:: { string }`.
- Update the header layout comment if `Data/` structure changes; MapSpec stays consumer-facing.
Also note a version bump breaks `validator.spec.luau` line 56 (`ContractVersion = 1` in `validSnapshot`) and
lines 166-170, and `graybox.spec.luau` line 92 (`t.equal(root.attributes.ContractVersion, 1)`).

---

### `src/server/core/MapValidator.luau` (modify)

- Signature change: `local function validate(root: Node): ({ Issue }, MapSpec?)` (line ~85) becomes
  `validate(root: Node, placement: PlacementConfig)`, with the same loud-failure rule for a nil config (SeatOrder
  pattern above). Return export unchanged (`return { validate = validate }`, lines 372-375).
- Replace the "PHASE 3 DEFERRED (D-12)" comment (lines 7-14) with a "what Phase 3 implemented / what is still
  deferred" list; items in it that this phase does NOT do (seat winding, Bounds roll now possible via `up`) must stay
  listed or be resolved, not silently dropped.
- The early exit at line 334 (`if #issues > 0 or box == nil ... then return issues, nil end`) is the seam: run the
  placement pass after the structural sort and BEFORE spec construction, only when the structure is sound, then
  append placement issues, re-sort with the existing comparator, and let `spec` stay nil whenever `#issues > 0`.
- `ContractVersion` check (lines 122-128) reads `MapContract.CONTRACT_VERSION`, so it follows the bump automatically.

---

### `src/server/services/MapLoader.luau` and `scripts/maps/snapshot.luau` (modify, BOTH identically)

The two are deliberate twins; the file headers say "must emit the IDENTICAL shape". Current Part branch:

MapLoader (lines 47-53):
```luau
if instance:IsA("BasePart") then
	local cframe = instance.CFrame
	node.position = vec3Of(cframe.Position)
	node.look = vec3Of(cframe.LookVector)
	node.size = vec3Of(instance.Size)
	node.anchored = instance.Anchored
end
```
snapshot (lines 52-59):
```luau
local part: any = inst
local cframe = part.CFrame
node.position = vec3Of(cframe.Position)
node.look = vec3Of(cframe.LookVector)
node.size = vec3Of(part.Size)
node.anchored = part.Anchored == true
```
Add in both: `node.up = vec3Of(cframe.UpVector)` and `node.canCollide = part.CanCollide == true` (Lune side keeps
`== true` because properties are untyped; runtime side reads the typed property), and `shape` from `part.Shape`
(Enum, convert to a plain string via `.Name`; on Lune, enums are untyped, guard with `tostring`). Keep `clean()`
(`n + 0`, negative-zero scrub) on every number, including `up`. Update BOTH header comments listing the Node shape.
Gate 8: the graybox spec compares key sets field by field, so any asymmetry fails.

MapLoader wiring (line 83): `MapValidator.validate(MapLoader.snapshot(map))` ->
`MapValidator.validate(MapLoader.snapshot(map), Placement)` with, near the top (service pattern from
`RoundDriver.luau` line 18, add `local ReplicatedStorage = game:GetService("ReplicatedStorage")` next to the other
`GetService` lines 11-13):
```luau
local Placement = require(ReplicatedStorage.Shared.Config.Placement)
```
Gate 5: the spec-lock asserts after `lex.luau` `stripComments` that this literal `Config.Placement` require is present.
Check `default.project.json` already mounts `src/shared` at `ReplicatedStorage.Shared` (RoundDriver relies on it).

`scripts/maps/validate-map.luau` (line 36): `MapValidator.validate(root)` -> pass
`require("../../src/shared/Config/Placement")`. Keep the output contract: `<CODE> <path> <message>` per issue, exit 1
(lines 38-44); the success line prints counts (line 46).

---

### `scripts/maps/generate-maze.luau` (new)

**Analog:** `scripts/maps/generate-graybox.luau` (268 lines). Copy: `--!strict`; header with usage line
`lune run scripts/maps/generate-maze.luau [outputPath]`; `local fs = require("@lune/fs")`,
`process`, `roblox`; `local rbx = roblox :: any`; `OUTPUT_PATH = process.args[1] or "<default>"` (line 29);
contract constants duplicated as literals with the comment "Duplicated as literals on purpose" (lines 31-35); the
`vec3(x, y, z): any` datatype helper (lines 40-42) and the single-boundary `any` cast convention. Be careful: a new
`.rbxm` output path should go under `build/` (the tests use `SCRATCH = "build/maps-spec"`, graybox.spec line 14) and
not be committed unless the research says so. Scripts are outside the pure zone so `os.` is not banned there, but
keep numeric `pos`-style names out anyway for uniformity.

---

### `scripts/maps/generate-graybox.luau` (modify, regenerate at v2 per D-17)

Constants at lines 31-38 (TAG_* and WALL_*); `root.attributes = { ContractVersion = 1, ...}` equivalent in the
generator must become 2. Header lines 13-14 "Real placement/reachability rules are Phase 3's (D-12)" need updating.
Every authored spot must pass `SpoonPlacement.check` with real margin and >= 16 spots (D-17 STRICT); the graybox spec
(below) is the gate. Make the generator emit `UpVector`-bearing CFrames (it already authors orientation via CFrame)
and set `CanCollide` explicitly on all parts.

---

### Tests

**Common spec skeleton** (every spec): `--!strict`, header comment stating what is proven and which mutation proves
it, requires by relative path, `local Test = require("../harness/Test")`, then
`return function(t: Test.Runner) ... t.test("...", function() ... end) end` (see `validator.spec.luau` line 400,
and `t.fuzz` below). Assertions available: `t.equal`, `t.deepEqual`, `t.truthy`, `t.test`, `t.fuzz`. Never assert on
`issue.message`; assert `issue.code` (`validator.spec` header line 4).

**Fuzz** (`tests/engine/pool.spec.luau` lines 198-210; `tests/harness/Fuzz.luau` lines 1-45):
```luau
t.fuzz("the shuffle is a permutation of the multiset", {
	iterations = PERMUTATION_ITERATIONS,
	gen = function(rng, i)
		local seatCount = rng:nextInt(2, 9)
		return { config = config, rankOf = Pool.shuffledRanks(config, rng), i = i }
	end,
	check = function(v)
		assert(cond, `message naming the failing values`)
	end,
})
```
Driver is stateless; `gen(rng, i)` is the ONLY consumer of the shared rng; `check` must be a pure function of the
generated value (`fuzz.spec.luau` header points 1-2), failure messages must include the seed material so a failing
trial pastes into a unit test. For `obb.spec` and `walkgrid.spec`: differential fuzz = production result vs
independent brute-force sampler / union-find, floors on how many positive and negative cases were generated
(fuzz.spec header point 3: "A suite that cannot prove it ran is theatre").

**`tests/placement/obb.spec.luau`, `walkgrid.spec.luau`:** fuzz as above plus deterministic edge cases following
`valve.spec.luau` style (a named fixture type, comments explaining the exact numbers, e.g. the `FIRST_FIRE` comment
lines 14-19 which justifies an off-by-one constant with a derivation). Use for ramp, thin wall, erosion.

**`tests/placement/corpus.spec.luau`:** table-driven like `validator.spec.luau` lines 396-470, where a list of
`{ name, code, mutate }` cases is looped and each asserts exact code-set equality (`codesOf(issues)`, lines 40-60
of the spec, deduped sorted list) rather than "contains". Add the `E +/- 0.25` stability probe (gate 4).

**`tests/placement/config_lock.spec.luau`:** analog `tests/engine/spec_lock.spec.luau`: `local fs = require("@lune/fs")`
(to read sources for the gate-5 grep), require `../../src/shared/Config/Placement` relatively, build the injected
config from the shipped values, assert the two coupling invariants and shape, assert `error` on a nil config
(use `pcall`), and the source assertion using `require("../../scripts/ci/lex")` `.stripComments` (exported, lex.luau
line 141) over `src/server/services/MapLoader.luau`. Keep the zero-todo discipline (no todo registration anywhere,
and do not even write the todo word registered by the harness in a comment: spec_lock header lines 5-8).

**`tests/placement/maze.spec.luau`:** analog `tests/maps/graybox.spec.luau` lines 1-60: uses `@lune/fs`, `@lune/process`,
`Snapshot.loadFile`, `SCRATCH = "build/maps-spec"`, `process.exec("lune", { "run", "scripts/maps/...", path })`.
Assert work counters before the clock, positive half before negative (gates 2 and 3). Clock use is fine in tests
(Lune `os.clock` is outside the pure zone) but check how `tests/` already reads time before inventing; `tests/harness/FakeClock.luau`
exists for fakes, but the wall-clock cap needs a real clock.

**`tests/maps/validator.spec.luau` (modify):** `validSnapshot()` sets `ContractVersion = 1` (line 56) -> 2; version
assertions around lines 166-170; the ~12 `MapValidator.validate(` call sites (lines 410, 435, 443, 451, 461, 506, 507,
521) pass the placement config. Define ONE local `PLACEMENT = require("../../src/shared/Config/Placement")` at the top
and pass it everywhere. `validSnapshot` Part nodes need `up`, `canCollide` fields once the validator requires them.
Closing coverage case (lines 485-493) walks `MapContract.ISSUE_CODES`; every new code needs a case with exact-set
equality (gate 1).

**`tests/maps/graybox.spec.luau` (modify):** line 92 `t.equal(root.attributes.ContractVersion, 1)` -> 2; calls at
lines 110 and 229 get the config argument; add snapshot key-set comparison against the runtime shape (gate 8); add
>= 16 and every-spot-valid assertion; CLI case asserts exit 1 and `<CODE> <path> <message>` for a bad spot via
`runCli` (line 19).

## Shared Patterns

### Purity and import discipline
**Source:** `scripts/ci/check-guards.luau` R3/R3b/R6; `scripts/ci/zones.luau` line 9.
**Apply to:** `SpoonPlacement.luau`, `MapContract.luau`, `MapValidator.luau`.
String-literal relative requires only, no non-relative require in pure zones, no suppression comments (selene allow,
nocheck), no `os.`, no `coroutine`, no `getfenv`/`setfenv`/`loadstring`, no `_G`. Gameplay-adjacent code cannot import
cosmetics or shop modules (rule 1). Two things must not drift: the scan is substring-based and case-sensitive.

### Injected config, loud failure
**Source:** `SeatOrder.luau` lines 130-136; shape validation `Admission.luau` lines 12-21.
**Apply to:** `SpoonPlacement.check`, `MapValidator.validate`.

### Stable issue codes asserted by code, sorted deterministically
**Source:** `MapValidator.luau` lines 28-39, comparator ~322-332; `validator.spec.luau` lines 40-60, 485-493.
**Apply to:** every new rule and every new spec.

### Twin snapshotters emit one Node shape
**Source:** `MapLoader.luau` lines 47-53, `snapshot.luau` lines 52-59, with `clean()` negative-zero scrub.
**Apply to:** `up`, `canCollide`, `shape`.

### Observability: each gate demonstrated red
**Source:** `03-VALIDATION.md` nine gates; precedent `fuzz.spec.luau` header point 3 and `valve.spec.luau` paired
"fires / never escapes with valve disabled" fixtures.
**Apply to:** each new spec. Record the mutation and its failure in the task summary.

## No Analog Found

| File / idiom | Role | Data Flow | Reason |
|---|---|---|---|
| `debug.info(fn, "a")` arity lock | test idiom | unit | No `debug.info` use exists in the repo; write it fresh (gate 6) |
| Oriented-box / slab-intersection and walk-grid flood maths | algorithm | transform | No geometry code exists; `MapValidator.inside` is the only vector helper (axis-aligned). Use RESEARCH.md code examples, subject to the `os.` naming rule |
| Wall-clock cap test | test idiom | integration | No existing test reads a real clock; `tests/harness/FakeClock.luau` is a fake. Use Lune's clock and counters-before-clock per gate 3 |
| Work-counter instrumentation in `SpoonPlacement` | utility | transform | Nothing comparable in core; engine `state.counters` (Invariants) is the nearest idea, but counters must stay pure data returned to the caller |

## Metadata

**Analog search scope:** `src/server/core`, `src/server/engine`, `src/server/services`, `src/shared/Config`,
`scripts/maps`, `scripts/ci`, `tests/engine`, `tests/maps`, `tests/guards/fixtures`, `tests/harness`.
**Files scanned:** about 30 read or grepped; 03-RESEARCH.md and 03-CONTEXT.md were not re-read in this pass
(VALIDATION.md and the orchestrator brief supplied the file list); the planner should cross-check exact `check`
parameter names against RESEARCH.md Code Examples.
**Pattern extraction date:** 2026-11-04
