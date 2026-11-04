--!strict
-- Gate G2's stress fixture (plan 03-07, D-08, D-09): a Lune-generated adversarial maze with a KNOWN ANSWER, and a
-- wall-clock cap on the bake. It owns two gates, each with the mutation that proves it can fail:
--
--   Gate 2, the oracle in both directions. Mutation: seed the flood from a sealed pocket instead of the spawn (the
--   positive-half case fails naming how many open cells were reached). Vacuity mutation: remove the generator's
--   corridor refusal and generate at --corridor 3 (the positive half fails with 0 of N, where a sealed-half-only
--   assertion would have passed).
--   Gate 3, the time cap. Mutation: MAZE_CAP_SECONDS = 1e-6 (the cap case fails, printing the real elapsed time).
--
-- The maze is an ORACLE FIRST and a stressor second: bake cost is O(boxes x covered columns) and flood cost is
-- O(reached cells), so a maze is not a time stressor. Its value is that reachability is proven CORRECT.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local MapContract = require("../../src/server/core/MapContract")
local SpoonPlacement = require("../../src/server/core/SpoonPlacement")
local WalkGrid = require("../../src/server/core/WalkGrid")
local Placement = require("../../src/shared/Config/Placement")
local Snapshot = require("../../scripts/maps/snapshot")
local Test = require("../harness/Test")

type Node = MapContract.Node
type Vec3 = MapContract.Vec3

local SCRATCH = "build/maze-spec"
local GENERATOR = "scripts/maps/generate-maze.luau"

-- Gate 3: a time cap passes vacuously if the bake did nothing, so the deterministic work counters are the real
-- gate and the wall clock is the backstop. Measured on this container: see 03-07-SUMMARY.md. The cap is 2.0 s,
-- roughly 4x headroom over the research figure of about 0.5 s, because a CI runner is assumed 2x to 4x slower
-- (assumption A5).
local MAZE_CAP_SECONDS = 2.0

type Point = { x: number, y: number, z: number }
type Oracle = {
	seed: number,
	footprint: number,
	corridor: number,
	levels: number,
	open: { Point },
	sealed: { Point },
	spotsInSealed: { string },
}

type Fixture = {
	root: Node,
	oracle: Oracle,
	boxes: { any },
	bounds: MapContract.Aabb,
	spawns: { Vec3 },
	spots: { Node },
}

type Baked = { fixture: Fixture, world: SpoonPlacement.World?, faults: { SpoonPlacement.BakeFault } }

local function child(n: Node, name: string): Node
	for _, c in n.children do
		if c.name == name then
			return c
		end
	end
	error(`no child {name} under {n.name}`)
end

local function generate(path: string, extra: { string }): process.ExecResult
	fs.writeDir(SCRATCH)
	local args = { "run", GENERATOR, path }
	for _, a in extra do
		table.insert(args, a)
	end
	return process.exec("lune", args)
end

local function loadFixture(path: string): Fixture
	local root, reason = Snapshot.loadFile(path)
	assert(root ~= nil, reason)
	local oracle = serde.decode("json", fs.readFile(`{path}.oracle.json`)) :: Oracle
	local data = child(root, "Data")
	local boundsNode = child(data, "Bounds")
	local centre, size = boundsNode.position :: Vec3, boundsNode.size :: Vec3
	local spawns: { Vec3 } = {}
	for _, spawn in child(data, "SeekerSpawns").children do
		table.insert(spawns, spawn.position :: Vec3)
	end
	return {
		root = root,
		oracle = oracle,
		boxes = SpoonPlacement.boxesOf(root, Placement),
		bounds = {
			min = { x = centre.x - size.x / 2, y = centre.y - size.y / 2, z = centre.z - size.z / 2 },
			max = { x = centre.x + size.x / 2, y = centre.y + size.y / 2, z = centre.z + size.z / 2 },
		},
		spawns = spawns,
		spots = child(data, "DefaultSpots").children,
	}
end

local function bakeFixture(fixture: Fixture): Baked
	local world, faults = SpoonPlacement.bake(fixture.boxes, fixture.bounds, fixture.spawns, Placement)
	return { fixture = fixture, world = world, faults = faults }
end

local function describeFaults(faults: { SpoonPlacement.BakeFault }): string
	local parts: { string } = {}
	for _, f in faults do
		table.insert(parts, `{f.kind}: {f.detail}`)
	end
	return table.concat(parts, "; ")
end

-- How many of `points` have a cell in their column that is in region 1. A nil world (bake faulted) reaches none.
local function countReached(baked: Baked, points: { Point }): number
	local world = baked.world
	if world == nil then
		return 0
	end
	local grid = world.grid
	local count = 0
	for _, p in points do
		local idx = WalkGrid.columnIndexOf(grid, p.x, p.z)
		if idx ~= nil then
			local first = grid.colFirst[idx]
			for c = first, first + grid.colCount[idx] - 1 do
				if grid.region[c] == 1 then
					count += 1
					break
				end
			end
		end
	end
	return count
end

-- Both oracle halves, POSITIVE FIRST. At corridor 3 erosion leaves zero reached cells, so "the sealed region was
-- not reached" is trivially true and the fixture reads green while testing nothing. Research measured 529/529
-- centres reached at corridors 4 to 6 and 0/841 at corridor 3.
local function assertOracle(t: Test.Runner, baked: Baked, label: string)
	local oracle = baked.fixture.oracle
	local matched = countReached(baked, oracle.open)
	local why = if baked.world == nil then ` (bake faulted: {describeFaults(baked.faults)})` else ""
	t.equal(matched, #oracle.open, `{label}: {matched}/{#oracle.open} open cells reached{why}`)
	local leaked = countReached(baked, oracle.sealed)
	t.equal(leaked, 0, `{label}: {leaked} of {#oracle.sealed} sealed cells were reached`)
end

local function spotPosition(fixture: Fixture, name: string): Vec3
	for _, spot in fixture.spots do
		if spot.name == name then
			return spot.position :: Vec3
		end
	end
	error(`no default spot {name}`)
end

return function(t: Test.Runner)
	local main: Baked? = nil
	local function mainBaked(): Baked
		if main == nil then
			local result = generate(`{SCRATCH}/maze.rbxm`, {})
			assert(result.code == 0, `generator failed: {result.stdout}{result.stderr}`)
			main = bakeFixture(loadFixture(`{SCRATCH}/maze.rbxm`))
		end
		return main :: Baked
	end

	t.test("the generator emits a disjoint, non-empty oracle", function()
		local oracle = mainBaked().fixture.oracle
		t.truthy(#oracle.open > 0, "open set is empty")
		t.truthy(#oracle.sealed > 0, "sealed set is empty")
		local seen: { [string]: boolean } = {}
		for _, p in oracle.open do
			seen[`{p.x}:{p.z}`] = true
		end
		local overlap = 0
		for _, p in oracle.sealed do
			if seen[`{p.x}:{p.z}`] then
				overlap += 1
			end
		end
		t.equal(overlap, 0, "cells present in both the open and sealed sets")
	end)

	t.test("the maze bakes with no faults", function()
		local baked = mainBaked()
		t.equal(#baked.faults, 0, describeFaults(baked.faults))
		t.truthy(baked.world ~= nil, "world is nil")
	end)

	t.test("every open maze cell is reached from the spawn (the oracle's positive half)", function()
		-- Gate 2. This is asserted BEFORE the sealed half on purpose. At corridor 3 erosion leaves zero reached
		-- cells, so "the sealed region was not reached" is trivially true and the fixture reads green while
		-- testing nothing. Research measured 529/529 centres reached at corridors 4 to 6 and 0/841 at corridor 3.
		local baked = mainBaked()
		local world = baked.world
		if world ~= nil then
			t.truthy(world.counters.cells > 0, "the bake produced no standable cells")
		end
		local oracle = baked.fixture.oracle
		local matched = countReached(baked, oracle.open)
		local why = if world == nil then ` (bake faulted: {describeFaults(baked.faults)})` else ""
		t.equal(matched, #oracle.open, `{matched}/{#oracle.open} open cells reached{why}`)
	end)

	t.test("no sealed maze cell is reached (the oracle's negative half)", function()
		local baked = mainBaked()
		-- Guard the vacuity at the point of use: the negative half means nothing unless something WAS reached.
		t.truthy(countReached(baked, baked.fixture.oracle.open) > 0, "nothing was reached, so this half is vacuous")
		local leaked = countReached(baked, baked.fixture.oracle.sealed)
		t.equal(leaked, 0, `{leaked} of {#baked.fixture.oracle.sealed} sealed cells were reached`)
	end)

	t.test("a default spot inside a sealed pocket is rejected as Unreachable", function()
		-- MAP-02 at the rule level: "fails the build on any that would be unfindable". Plan 03-08 adds the
		-- CLI-level half over this same map.
		local baked = mainBaked()
		local world = baked.world :: SpoonPlacement.World
		t.truthy(#baked.fixture.oracle.spotsInSealed > 0, "the generator placed no spot in a pocket")
		for _, name in baked.fixture.oracle.spotsInSealed do
			local verdict = SpoonPlacement.check(world, spotPosition(baked.fixture, name))
			t.equal(verdict.reason, "Unreachable", `{name} should be Unreachable`)
		end
	end)

	t.test("every default spot at an open cell is valid", function()
		-- The complement, so the fixture is not simply rejecting everything. Without this case the one above would
		-- pass for a check that returned Unreachable unconditionally.
		local baked = mainBaked()
		local world = baked.world :: SpoonPlacement.World
		local pockets: { [string]: boolean } = {}
		for _, name in baked.fixture.oracle.spotsInSealed do
			pockets[name] = true
		end
		local checked = 0
		for _, spot in baked.fixture.spots do
			if not pockets[spot.name] then
				local verdict = SpoonPlacement.check(world, spot.position :: Vec3)
				t.equal(verdict.ok, true, `{spot.name} should be valid, got {verdict.reason}`)
				checked += 1
			end
		end
		t.truthy(checked >= MapContract.MIN_DEFAULT_SPOTS, `only {checked} open spots were checked`)
	end)

	t.test("the bake's work counters are non-zero and above the measured floors", function()
		local counters = (mainBaked().world :: SpoonPlacement.World).counters
		-- Floors are well below the measured values (03-07-SUMMARY.md) so tuning cannot trip them, and far above
		-- zero so a bake that did nothing cannot pass.
		local floors: { [string]: number } = {
			boxes = 4000,
			columns = 50000,
			spans = 50000,
			cells = 50000,
			reached = 10000,
			linkTests = 10000,
			eroded = 1000,
		}
		local actual: { [string]: number } = {
			boxes = counters.boxes,
			columns = counters.columns,
			spans = counters.spans,
			cells = counters.cells,
			reached = counters.reached,
			linkTests = counters.linkTests,
			eroded = counters.eroded,
		}
		for name, floor in floors do
			t.truthy(actual[name] > floor, `counters.{name} = {actual[name]}, expected above {floor}`)
		end
		print(
			`maze counters: boxes={counters.boxes} columns={counters.columns} spans={counters.spans} cells={counters.cells} reached={counters.reached} linkTests={counters.linkTests} eroded={counters.eroded}`
		)
	end)

	-- Times a fresh boxesOf + bake + one check per authored spot, asserts the counters, and returns the elapsed time.
	local function timedWork(): number
		local fixture = mainBaked().fixture
		local started = os.clock()
		local boxes = SpoonPlacement.boxesOf(fixture.root, Placement)
		local world, faults = SpoonPlacement.bake(boxes, fixture.bounds, fixture.spawns, Placement)
		assert(world ~= nil, describeFaults(faults))
		for _, spot in fixture.spots do
			SpoonPlacement.check(world, spot.position :: Vec3)
		end
		local elapsed = os.clock() - started
		-- Counters are asserted BEFORE the elapsed time is compared with anything: a time cap passes vacuously
		-- if the bake did nothing.
		local counters = world.counters
		t.truthy(counters.boxes > 0 and counters.columns > 0 and counters.cells > 0, "the bake did no work")
		t.truthy(counters.reached > 0 and counters.linkTests > 0, "the flood did no work")
		return elapsed
	end

	t.test("bake, flood and a check per spot complete inside the wall-clock cap", function()
		local elapsed = timedWork()
		print(`maze wall clock: {string.format("%.3f", elapsed)} s of {MAZE_CAP_SECONDS} s cap`)
		t.truthy(elapsed < MAZE_CAP_SECONDS, `maze work took {elapsed} s, cap is {MAZE_CAP_SECONDS} s`)
	end)

	t.test("a deliberately tiny cap fails, so the cap is a real gate", function()
		local elapsed = timedWork()
		t.falsy(elapsed < 1e-9, "a 1e-9 s cap should be impossible to meet")
	end)

	t.test("a corridor below the erosion minimum is refused by the generator, not detected here", function()
		-- Pitfall 4 prevented at the source: the spec cannot reach the vacuous state because the generator will
		-- not produce it.
		local result = generate(`{SCRATCH}/narrow.rbxm`, { "--corridor", "3" })
		t.equal(result.code, 1, `expected exit 1, got {result.code}`)
		t.contains(result.stdout, "minimum 4")
		t.contains(result.stdout, "pass vacuously")
	end)

	t.test("the oracle's positive and negative halves both hold at a second dial setting", function()
		-- This case does NOT discriminate a recursive flood, and must not be mistaken for the protection: a perfect
		-- maze at footprint 64 with corridor 4 reaches on the order of a thousand cells, nowhere near Luau's
		-- call-depth limit. The two things that actually guard against a recursive flood are case 3's default
		-- 248-footprint maze (about 61,500 columns, where a recursive flood does blow the stack) and plan 03-04's
		-- body-scoped no-recursion grep over WalkGrid.flood. Keep both.
		--
		-- What this case IS for: the only evidence in the spec that the generator and its sidecar agree for more
		-- than one parameter combination. An oracle that happened to be right at the defaults and wrong elsewhere
		-- would otherwise go unnoticed.
		local path = `{SCRATCH}/second.rbxm`
		local result =
			generate(path, { "--footprint", "64", "--corridor", "4", "--wall", "1", "--braid", "0", "--levels", "1" })
		t.equal(result.code, 0, `generator failed: {result.stdout}{result.stderr}`)
		local baked = bakeFixture(loadFixture(path))
		t.equal(#baked.faults, 0, describeFaults(baked.faults))
		assertOracle(t, baked, "second setting")
		local world = baked.world :: SpoonPlacement.World
		t.truthy(world.counters.reached > 200, `counters.reached = {world.counters.reached}, expected above 200`)
		fs.removeFile(path)
		fs.removeFile(`{path}.oracle.json`)
	end)
end
