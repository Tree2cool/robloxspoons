--!strict
-- The placement corpus (plan 03-05, ROADMAP criterion 1): known-good and known-bad coordinates, each asserted
-- by REASON CODE, never by prose, over hand-built micro-worlds and the committed graybox.
--
-- Two exactness rules make this corpus meaningful rather than lucky. First, no probe may sit within 0.5 studs of
-- a threshold, and the stability probe at the bottom enforces it by re-baking at E +- 0.25 and requiring an
-- identical verdict. Second, every bake fault has an exact-fault-list case, so the bake's mandated checks are
-- watched firing here rather than first being exercised two waves later by the validator.
local MapContract = require("../../src/server/core/MapContract")
local Placement = require("../../src/shared/Config/Placement")
local Snapshot = require("../../scripts/maps/snapshot")
local MicroWorld = require("./MicroWorld")
local Obb = require("../../src/server/core/Obb")
local WalkGrid = require("../../src/server/core/WalkGrid")
local SpoonPlacement = require("../../src/server/core/SpoonPlacement")
local Test = require("../harness/Test")

type Vec3 = MapContract.Vec3
type Node = MapContract.Node

local GRAYBOX = "maps/gray-box.rbxm"
local GRAY = "graybox"
local FLAT = "flatRoom"

type Case = { name: string, world: string, point: Vec3, reason: SpoonPlacement.Reason? }
-- reason = nil means the point must be VALID.

local function v(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

local function childNamed(n: Node, name: string): Node
	for _, c in n.children do
		if c.name == name then
			return c
		end
	end
	error(`no child {name} under {n.name}`)
end

local function withMargin(margin: number): SpoonPlacement.PlacementConfig
	local copy: any = table.clone(Placement)
	copy.PICKUP_MARGIN = margin
	return copy :: SpoonPlacement.PlacementConfig
end

-- One baked scenario: boxes, bounds, spawns. The graybox is read from the committed .rbxm.
type Scenario = { boxes: { any }, bounds: MapContract.Aabb, spawns: { Vec3 } }

local function scenarioOf(name: string): Scenario
	if name == "graybox" then
		local root, reason = Snapshot.loadFile(GRAYBOX)
		assert(root ~= nil, reason)
		local data = childNamed(root, "Data")
		local boundsNode = childNamed(data, "Bounds")
		local centre = boundsNode.position :: Vec3
		local size = boundsNode.size :: Vec3
		local spawns: { Vec3 } = {}
		for _, spawn in childNamed(data, "SeekerSpawns").children do
			table.insert(spawns, spawn.position :: Vec3)
		end
		return {
			boxes = SpoonPlacement.boxesOf(root, Placement),
			bounds = {
				min = v(centre.x - size.x / 2, centre.y - size.y / 2, centre.z - size.z / 2),
				max = v(centre.x + size.x / 2, centre.y + size.y / 2, centre.z + size.z / 2),
			},
			spawns = spawns,
		}
	end
	local fixture = (MicroWorld :: any)[name]()
	return { boxes = fixture.boxes, bounds = fixture.bounds, spawns = fixture.spawns }
end

local function bakeScenario(
	name: string,
	config: SpoonPlacement.PlacementConfig
): (SpoonPlacement.World?, { SpoonPlacement.BakeFault })
	local s = scenarioOf(name)
	return SpoonPlacement.bake(s.boxes, s.bounds, s.spawns, config)
end

local worldCache: { [string]: SpoonPlacement.World } = {}
local function worldOf(name: string): SpoonPlacement.World
	local cached = worldCache[name]
	if cached ~= nil then
		return cached
	end
	local world, faults = bakeScenario(name, Placement)
	assert(world ~= nil, `{name} did not bake: {#faults} faults`)
	worldCache[name] = world
	return world
end

-- Micro-world rows. Coordinates are exact by construction (MicroWorld's header rule).
local MICRO_ROWS: { Case } = {
	{ name = "flat room: floor spot, 3 from spawn", world = FLAT, point = v(4, 0.5, 4), reason = nil },
	-- D-19: over a void. The graybox cannot express this (its perimeter is solid wall), so it lives here.
	-- 8.7 up: the nearest floor reach point is 6.24 away, inside PICKUP_RANGE 7.0 but outside E = 5.5, with
	-- 0.74 and 0.76 studs of slack either side. The only fixture row that produces OutOfReach, see the shelf
	-- note in GRAYBOX_ROWS.
	{ name = "flat room: 8.7 up is OutOfReach", world = FLAT, point = v(4, 8.7, 4), reason = "OutOfReach" },
	{ name = "pit: over the void is NoFooting", world = "pit", point = v(0, -20, 0), reason = "NoFooting" },
	{ name = "sealed room: closet is Unreachable", world = "sealedRoom", point = v(0, 0.5, 9), reason = "Unreachable" },
	{ name = "flat room: inside the east wall is Solid", world = FLAT, point = v(13, 5, 0), reason = "Solid" },
	{ name = "flat room: outside Bounds", world = FLAT, point = v(20, 1, 0), reason = "OutOfBounds" },
	-- The nine non-finite probes are nine NAMED rows, not a loop, so a failure names the component and the sign.
	{ name = "NaN x", world = FLAT, point = v(0 / 0, 0.5, 4), reason = "OutOfBounds" },
	{ name = "NaN y", world = FLAT, point = v(4, 0 / 0, 4), reason = "OutOfBounds" },
	{ name = "NaN z", world = FLAT, point = v(4, 0.5, 0 / 0), reason = "OutOfBounds" },
	{ name = "+inf x", world = FLAT, point = v(math.huge, 0.5, 4), reason = "OutOfBounds" },
	{ name = "+inf y", world = FLAT, point = v(4, math.huge, 4), reason = "OutOfBounds" },
	{ name = "+inf z", world = FLAT, point = v(4, 0.5, math.huge), reason = "OutOfBounds" },
	{ name = "-inf x", world = FLAT, point = v(-math.huge, 0.5, 4), reason = "OutOfBounds" },
	{ name = "-inf y", world = FLAT, point = v(4, -math.huge, 4), reason = "OutOfBounds" },
	{ name = "-inf z", world = FLAT, point = v(4, 0.5, -math.huge), reason = "OutOfBounds" },
}

-- Graybox rows. Every expectation is a MEASURED value from research's prototype against this exact .rbxm.
-- If the implementation disagrees with one, investigate the disagreement: do not change the expectation to
-- match the code. Research and this implementation are independent derivations of the same rules, so a
-- disagreement is exactly the signal the corpus exists to produce.
local GRAYBOX_ROWS: { Case } = {
	-- Inside the solid Core. Also has no standable cell in reach (floor root 2.5 is 7.5 below), so the
	-- downstream reason would be NoFooting; the locked order says Solid.
	{ name = "graybox: inside the Core is Solid", world = GRAY, point = v(0, 10, 0), reason = "Solid" },
	{ name = "graybox: inside the east wall is Solid", world = GRAY, point = v(61, 0.5, 0), reason = "Solid" },
	-- Under the east wall (y -0.5, the wall starts at y 0): standable cells on the floor are within reach but
	-- the wall's own mass blocks every eye segment.
	{ name = "graybox: under the east wall is NoSight", world = GRAY, point = v(61, -0.5, 0), reason = "NoSight" },
	-- Above the wall top: the only cells in reach are on top of the wall, which no spawn can walk to.
	{ name = "graybox: above the wall top", world = GRAY, point = v(61, 25, 0), reason = "Unreachable" },
	{ name = "graybox: floating over the south hall", world = GRAY, point = v(-20, 14, 44), reason = "NoFooting" },
	-- DISAGREEMENT WITH RESEARCH, INVESTIGATED (see the plan 03-05 summary). Research's measured numbers are
	-- reproduced exactly: nearest CONNECTED cell d*conn = 6.54, asserted independently by the "shelf
	-- thresholds" case below. But research labelled the verdict "REACH" at E = 5.5 and this implementation
	-- reports Unreachable. Both follow the rules: the shelf top carries its own standable cells (region 0, 2.12
	-- from the east-edge spot) which lie INSIDE E but are not walkable from any spawn, so by the locked order
	-- (OutOfReach = no cell of any region within E; Unreachable = cells within E, none connected) the reason is
	-- Unreachable. Research gives the disconnected wall-top cell at (61, 25, 0) the same "out of reach" label,
	-- and this corpus expects that one as Unreachable too; "REACH" is research's coarse bucket for both.
	-- Consequence: the shelf is never OutOfReach at any E below 6.54, so OutOfReach is produced by the
	-- flat-room row instead. Only the reason NAME differs, for the stated cause, and the measured number is
	-- asserted rather than dropped.
	{ name = "graybox: shelf centre", world = GRAY, point = v(50, 9.0, 59), reason = "Unreachable" },
	-- Measured d*conn = 6.54, d*los = 6.54, so at E = 5.5 the shelf east edge fails with 1.04 studs of slack.
	-- At PICKUP_RANGE 8.0 the slack would be 0.04 and the verdict would be decided by float32 rounding, which
	-- is why 7.0 was chosen (research Pitfall 7).
	{ name = "graybox: shelf east edge", world = GRAY, point = v(54, 9.0, 59), reason = "Unreachable" },
	{ name = "graybox: a floor spot is valid", world = GRAY, point = v(-55, 0.5, -55), reason = nil },
	-- Measured d*conn = 4.06 at EYE_HEIGHT 4.0, 1.44 studs inside E = 5.5.
	{ name = "graybox: a crate-top spot is valid", world = GRAY, point = v(-33, 4.5, 33), reason = nil },
	{ name = "graybox: a ledge spot is valid", world = GRAY, point = v(-56, 7.0, -4), reason = nil },
}

local ALL_ROWS: { Case } = {}
for _, row in MICRO_ROWS do
	table.insert(ALL_ROWS, row)
end
for _, row in GRAYBOX_ROWS do
	table.insert(ALL_ROWS, row)
end

local function describe(verdict: SpoonPlacement.Verdict): string
	if verdict.ok then
		return "ok"
	end
	return tostring(verdict.reason)
end

return function(t: Test.Runner)
	for _, row in ALL_ROWS do
		t.test(`{row.name}`, function()
			local verdict = SpoonPlacement.check(worldOf(row.world), row.point)
			t.equal(describe(verdict), if row.reason == nil then "ok" else row.reason)
		end)
	end

	-- C. Precedence, in both directions.
	t.test("a point that is both outside Bounds and inside a solid reports OutOfBounds", function()
		local s = scenarioOf("flatRoom")
		local tight = { min = v(-11, -2, -11), max = v(11, 24, 11) }
		local world = SpoonPlacement.bake(s.boxes, tight, s.spawns, Placement)
		assert(world ~= nil, "tight-bounds bake failed")
		local point = v(13, 5, 0) -- inside the east wall, outside the tightened bounds
		t.equal(describe(SpoonPlacement.check(world, point)), "OutOfBounds")
		-- The same point in the real bounds is Solid, so the earlier reason is what won.
		t.equal(describe(SpoonPlacement.check(worldOf("flatRoom"), point)), "Solid")
	end)

	t.test("a point inside a solid that also has no sightline reports Solid", function()
		local world = worldOf("thinWall")
		-- Inside the divider (x 0.75..1.05). Standable cells in reach exist on both sides, and the divider's
		-- own mass blocks the eye segments, so downstream this would read as a sight failure.
		local point = v(0.9, 1, 0)
		local s = scenarioOf("thinWall")
		local divider = s.boxes[#s.boxes] :: any
		t.equal(Obb.distanceToPoint(divider, point.x, point.y, point.z), 0, "the probe must be inside the divider")
		t.equal(describe(SpoonPlacement.check(world, point)), "Solid")
	end)

	t.test("REASON_ORDER is the locked six-name list", function()
		t.deepEqual(
			SpoonPlacement.REASON_ORDER,
			{ "OutOfBounds", "Solid", "NoFooting", "OutOfReach", "Unreachable", "NoSight" }
		)
	end)

	-- D. Coverage: a reason no fixture produces is a reason nobody has seen fire.
	t.test("every reason in REASON_ORDER is produced by at least one corpus case", function()
		local produced: { [string]: boolean } = {}
		for _, row in ALL_ROWS do
			if row.reason ~= nil then
				produced[row.reason] = true
			end
		end
		for _, reason in SpoonPlacement.REASON_ORDER do
			t.truthy(produced[reason], `no corpus case expects {reason}`)
		end
	end)

	-- E. Bake faults. bake returns (World?, { BakeFault }) and the world is non-nil ONLY when the fault list is
	-- empty, the same (issues, spec) convention MapValidator.validate uses. Assert BOTH halves on every case.
	t.test("a spawn with no footing is a SpawnNoFooting fault, never a silently empty region", function()
		-- Pitfall 10: seedsAt returning empty must become a loud fault. If it were treated as "flood
		-- everything" the BFS would run on an empty queue, report 0 reached, and every spot would then fail
		-- with a misleading reason.
		local world, faults = bakeScenario("spawnInVoid", Placement)
		t.equal(world, nil)
		t.equal(#faults, 1)
		t.equal(faults[1].kind, "SpawnNoFooting")
		t.equal(faults[1].spawnIndex, 1)
	end)

	t.test("two spawns on two disconnected islands are a SpawnDisconnected fault (D-06)", function()
		-- The combined flood in bake is seeded from ALL spawns' cells, so every seed cell has region == 1 by
		-- construction and a combined-region check could never produce this fault. This case is what
		-- distinguishes the mandated per-spawn re-flood from the forbidden shortcut: if an implementation
		-- substitutes the combined-region check, this is the case that goes red.
		local world, faults = bakeScenario("twoIslands", Placement)
		t.equal(world, nil)
		t.equal(#faults, 1)
		t.equal(faults[1].kind, "SpawnDisconnected")
	end)

	t.test("a Bounds past MAX_BAKE_COLUMNS is refused before allocating", function()
		-- The graybox is 15,376 columns and the maze stress fixture 61,504, so the 250,000 ceiling is about 4x
		-- above anything real; hugeBounds is 4,000,000.
		local s = scenarioOf("hugeBounds")
		local started = os.clock()
		local world, faults = SpoonPlacement.bake(s.boxes, s.bounds, s.spawns, Placement)
		local elapsed = os.clock() - started
		t.equal(world, nil)
		t.equal(#faults, 1)
		t.equal(faults[1].kind, "BoundsTooLarge")
		t.truthy(elapsed < 0.05, `refusal took {elapsed}s; a slow refusal means something allocated first`)
	end)

	t.test("a spawn with no footing does not ALSO report SpawnDisconnected", function()
		-- Step 6 must exclude spawns already reported SpawnNoFooting from the per-spawn re-flood. An empty seed
		-- list floods nothing, so every other spawn's seeds are trivially not contained and a spurious
		-- SpawnDisconnected is emitted alongside the real fault. spawnInVoid has a single spawn and cannot see
		-- this; plan 03-08's MAP_SPAWN_NO_FOOTING fixture has two and asserts an EXACT issue set, so this case
		-- keeps that fixture green.
		local s = scenarioOf("flatRoom")
		local world, faults = SpoonPlacement.bake(s.boxes, s.bounds, { v(4, 3, 4), v(0, 20, 0) }, Placement)
		t.equal(world, nil)
		t.equal(#faults, 1)
		t.equal(faults[1].kind, "SpawnNoFooting")
		t.equal(faults[1].spawnIndex, 2)
	end)

	t.test("the fault list and the world are never both populated", function()
		local names = {
			"flatRoom",
			"pit",
			"sealedRoom",
			"thinWall",
			"ramp",
			"lowCeiling",
			"narrowCorridor",
			"twoIslands",
			"spawnInVoid",
			"hugeBounds",
			"graybox",
		}
		for _, name in names do
			local world, faults = bakeScenario(name, Placement)
			t.equal(world == nil, #faults > 0, `{name}: world nil = {world == nil}, faults = {#faults}`)
		end
	end)

	-- Research's measured shelf numbers, asserted directly rather than through a reason name.
	t.test(
		"shelf thresholds: nearest connected cell is 6.54 away, and at range 8.5 the edge is valid and the centre NoSight",
		function()
			local world = worldOf("graybox")
			local grid = world.grid
			local out: { number } = {}
			for _, spot in { v(50, 9.0, 59), v(54, 9.0, 59) } do
				local n = WalkGrid.cellsNear(grid, spot.x, spot.z, 8, out)
				local best = math.huge
				for i = 1, n do
					local c = out[i]
					if grid.region[c] == 1 then
						local dx, dy, dz =
							grid.cellX[c] - spot.x,
							grid.cellH[c] + Placement.REACH_HEIGHT - spot.y,
							grid.cellZ[c] - spot.z
						best = math.min(best, math.sqrt(dx * dx + dy * dy + dz * dz))
					end
				end
				t.truthy(
					math.abs(best - 6.54) < 0.01,
					`d*conn at ({spot.x}, {spot.z}) = {best}, research measured 6.54`
				)
			end
			-- Research ladder row PICKUP_RANGE 8.5 (E = 7.0): Spot09 ok, Spot08 culled by line of sight.
			local config: any = table.clone(Placement)
			config.PICKUP_RANGE = 8.5
			local wide, faults = bakeScenario("graybox", config :: SpoonPlacement.PlacementConfig)
			assert(wide ~= nil, `{#faults} faults`)
			t.equal(describe(SpoonPlacement.check(wide, v(54, 9.0, 59))), "ok")
			t.equal(describe(SpoonPlacement.check(wide, v(50, 9.0, 59))), "NoSight")
		end
	)

	-- F. Stability probe (vacuous-pass gate 4). A corpus whose verdicts sit on thresholds passes today and breaks
	-- on an unrelated numeric change. Moving a coordinate onto its threshold must make this case fail.
	t.test("every corpus verdict is stable at E +- 0.25 (stability)", function()
		-- PICKUP_MARGIN 1.25 and 1.75 give E = 5.75 and 5.25.
		for _, margin in { 1.25, 1.75 } do
			local config = withMargin(margin)
			local baked: { [string]: SpoonPlacement.World } = {}
			for _, row in ALL_ROWS do
				local world = baked[row.world]
				if world == nil then
					local made, faults = bakeScenario(row.world, config)
					assert(made ~= nil, `{row.world} did not bake at margin {margin}: {#faults} faults`)
					baked[row.world] = made
					world = made
				end
				local expected = if row.reason == nil then "ok" else row.reason
				t.equal(
					describe(SpoonPlacement.check(world :: SpoonPlacement.World, row.point)),
					expected,
					`{row.name} flips at E = {config.PICKUP_RANGE - margin}`
				)
			end
		end
	end)
end
