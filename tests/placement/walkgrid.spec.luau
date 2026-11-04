--!strict
-- Plan 03-04 (HIDE-06): the reachability layer. Every mechanism here is proven in PAIRS: a positive case and an
-- adjacent negative control on the same fixture with one varied parameter, so the check is shown able to fail.
--
-- Mutations that make this spec go red (each was performed and the output recorded in the plan SUMMARY):
--   * ramp positive case at MAX_SLOPE_DEGREES = 24      -> the ledge probe is not reached
--   * drop the `distance * tanSlope` allowance (erosion) -> the STEP_UP = 0.5 ramp case fails
--   * drop link condition 3 (segment test) in flood      -> the thin-wall case fails, two sides become one region
local Obb = require("../../src/server/core/Obb")
local Placement = require("../../src/shared/Config/Placement")
local WalkGrid = require("../../src/server/core/WalkGrid")
local MapContract = require("../../src/server/core/MapContract")
local MicroWorld = require("./MicroWorld")
local Test = require("../harness/Test")

type Vec3 = MapContract.Vec3

-- Seekers spawn at most this far above a floor in every fixture.
local SPAWN_DROP = 10
local FUZZ_TRIALS = 300
local MIN_PER_OUTCOME = 20

-- The ramp is atan(6.5 / 14) = 24.9047 degrees. The per-cell rise is GRID_SIZE * tan(slope),
-- so the minimum workable STEP_UP is 0.232 at g = 0.5, 0.464 at g = 1 and 0.929 at g = 2.
-- Any MAX_SLOPE_DEGREES below 24.9047 silently disconnects the ledge and, on the real graybox,
-- takes four default spots with it.
local RAMP_DEGREES = 24.9047

-- Measured: with grid-only links a 0.3-thick full-width wall left ALL 1,600 cells in one
-- region -- the wall was invisible -- against 840 with the exact segment test at two body
-- heights. The leak direction is the dangerous one: a sealed spot marked reachable ships an
-- unfindable spoon.
local THIN_WALL = 0.3

local function gridConfig(overrides: { [string]: number }?): WalkGrid.GridConfig
	local config: { [string]: number } = {
		GRID_SIZE = Placement.GRID_SIZE,
		STEP_UP = Placement.STEP_UP,
		MAX_SLOPE_DEGREES = Placement.MAX_SLOPE_DEGREES,
		CAPSULE_RADIUS = Placement.CAPSULE_RADIUS,
		CAPSULE_HEIGHT = Placement.CAPSULE_HEIGHT,
	}
	if overrides ~= nil then
		for key, value in overrides do
			config[key] = value
		end
	end
	return config :: any
end

type Baked = {
	grid: WalkGrid.Grid,
	boxes: { Obb.Box },
	index: Obb.Index,
	config: WalkGrid.GridConfig,
	seeds: { number },
}

local function seedsFor(grid: WalkGrid.Grid, spawns: { Vec3 }): { number }
	local seeds: { number } = {}
	for _, spawn in spawns do
		for _, c in WalkGrid.seedsAt(grid, spawn, SPAWN_DROP) do
			table.insert(seeds, c)
		end
	end
	return seeds
end

local function bake(world: MicroWorld.World, overrides: { [string]: number }?, spawns: { Vec3 }?): Baked
	local config = gridConfig(overrides)
	local index = Obb.newIndex(world.boxes, 8)
	local grid = WalkGrid.build(world.boxes, world.bounds, config, index)
	local seeds = seedsFor(grid, spawns or world.spawns)
	WalkGrid.flood(grid, world.boxes, index, seeds, config)
	return { grid = grid, boxes = world.boxes, index = index, config = config, seeds = seeds }
end

-- A probe sits 0.5 above a surface. The cell is the one in the probe's column whose floor is nearest that surface.
local function cellAt(grid: WalkGrid.Grid, probe: Vec3): number?
	local idx = WalkGrid.columnIndexOf(grid, probe.x, probe.z)
	if idx == nil then
		return nil
	end
	local first = grid.colFirst[idx]
	local best: number? = nil
	local bestGap = 1.0
	for c = first, first + grid.colCount[idx] - 1 do
		local gap = math.abs(grid.cellH[c] - (probe.y - 0.5))
		if gap <= bestGap then
			best, bestGap = c, gap
		end
	end
	return best
end

-- The positive half comes first: a cell must EXIST at the probe, so "not reached" can never mean "not there".
local function expectRegion(t: Test.Runner, baked: Baked, probe: Vec3, expected: number, label: string)
	local c = cellAt(baked.grid, probe)
	t.truthy(c ~= nil, `{label}: no standable cell at probe ({probe.x}, {probe.y}, {probe.z})`)
	if c ~= nil then
		t.equal(baked.grid.region[c], expected, `{label}: region at probe ({probe.x}, {probe.y}, {probe.z})`)
	end
end

local function countWhere(grid: WalkGrid.Grid, predicate: (number) -> boolean): number
	local n = 0
	for c = 1, #grid.cellH do
		if predicate(c) then
			n += 1
		end
	end
	return n
end

local function v(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

-- Fuzz coverage, filled by the check function and asserted by the anti-vacuity case at the end.
local fuzzConnected, fuzzPartitioned, fuzzSkipped, fuzzRan = 0, 0, 0, 0

local function describeLayout(boxes: { Obb.Box }): string
	local parts: { string } = {}
	for _, box in boxes do
		table.insert(
			parts,
			string.format(
				"%s c=(%.3f,%.3f,%.3f) h=(%.3f,%.3f,%.3f) look=(%.3f,%.3f,%.3f)",
				box.name,
				box.cx,
				box.cy,
				box.cz,
				box.h[1],
				box.h[2],
				box.h[3],
				box.ax[3],
				box.ay[3],
				box.az[3]
			)
		)
	end
	return table.concat(parts, "\n")
end

local function find(parent: { number }, a: number): number
	local root = a
	while parent[root] ~= root do
		root = parent[root]
	end
	-- Path compression, iterative.
	local at = a
	while parent[at] ~= root do
		local nextAt = parent[at]
		parent[at] = root
		at = nextAt
	end
	return root
end

return function(t: Test.Runner)
	-- A. baseline and counters ------------------------------------------------------------------------------
	t.test("flat room: every floor cell is reached from the single spawn and the counters are non-zero", function()
		local baked = bake(MicroWorld.flatRoom())
		local counters = baked.grid.counters
		-- Counters first, before any clock exists in this case: a cap on an empty bake passes vacuously.
		t.truthy(counters.boxes > 0 and counters.columns > 0 and counters.spans > 0, "bake counted no work")
		t.truthy(counters.cells > 0, "no cells")
		t.truthy(counters.reached > 0, "nothing reached")
		t.truthy(counters.linkTests > 0, "no link was verified")
		t.truthy(counters.eroded > 0, "erosion never ran")
		t.equal(counters.cells, counters.reached, "every cell of the flat room is reached")
		-- Floor +-12, perimeter inner face at 12: cells within 1.5 of a wall are eroded, leaving centres
		-- -10.5 .. 10.5 on each axis, 22 x 22.
		t.equal(counters.cells, 22 * 22, "flat room cell count")
		t.equal(counters.columns, 28 * 28, "flat room column count")
		t.equal(counters.boxes, 5, "flat room box count")
		print(
			`walkgrid counters (flat room): boxes={counters.boxes} columns={counters.columns} spans={counters.spans} cells={counters.cells} reached={counters.reached} linkTests={counters.linkTests} eroded={counters.eroded}`
		)
	end)

	t.test("the bake is deterministic: two bakes of the same world return identical counters and cells", function()
		local a = bake(MicroWorld.ramp())
		local b = bake(MicroWorld.ramp())
		t.deepEqual(a.grid.counters, b.grid.counters)
		t.deepEqual(a.grid.cellH, b.grid.cellH)
		t.deepEqual(a.grid.region, b.grid.region)
	end)

	t.test("a missing or non-numeric config field is a loud error, never a silent default (D-13)", function()
		local world = MicroWorld.flatRoom()
		local index = Obb.newIndex(world.boxes, 8)
		t.throws(function()
			WalkGrid.build(world.boxes, world.bounds, {} :: any, index)
		end, "GRID_SIZE")
		local broken: any = gridConfig()
		broken.CAPSULE_HEIGHT = nil
		t.throws(function()
			WalkGrid.build(world.boxes, world.bounds, broken, index)
		end, "CAPSULE_HEIGHT")
	end)

	t.test("columnCountFor is bounds-only and matches what build allocates", function()
		local world = MicroWorld.flatRoom()
		t.equal(WalkGrid.columnCountFor(world.bounds, 1), 28 * 28)
		t.equal(WalkGrid.columnCountFor(MicroWorld.hugeBounds().bounds, 1), 2000 * 2000)
		t.equal(WalkGrid.columnCountFor(world.bounds, 2), 14 * 14)
	end)

	-- B. the ramp: positive case and three independent negative controls ---------------------------------------
	t.test("ramp at the shipped config: the ledge is in the spawn's region", function()
		local world = MicroWorld.ramp(RAMP_DEGREES)
		local baked = bake(world)
		expectRegion(t, baked, world.probes.onFloor, 1, "floor")
		expectRegion(t, baked, world.probes.onLedge, 1, "ledge")
		print(
			`walkgrid counters (ramp): columns={baked.grid.counters.columns} spans={baked.grid.counters.spans} cells={baked.grid.counters.cells} reached={baked.grid.counters.reached} linkTests={baked.grid.counters.linkTests} eroded={baked.grid.counters.eroded}`
		)
	end)

	t.test(
		"negative control: ramp with MAX_SLOPE_DEGREES = 24 disconnects the ledge and removes the ramp cells",
		function()
			local world = MicroWorld.ramp(RAMP_DEGREES)
			local baked = bake(world, { MAX_SLOPE_DEGREES = 24 })
			expectRegion(t, baked, world.probes.onFloor, 1, "floor")
			expectRegion(t, baked, world.probes.onLedge, 0, "ledge")
			-- The face normal fails the slope test, so no cell stands on the ramp at all (heights strictly between).
			local onRamp = countWhere(baked.grid, function(c)
				return baked.grid.cellX[c] < -25 and baked.grid.cellX[c] > -37 and baked.grid.cellH[c] > 0.5
			end)
			t.equal(onRamp, 0, "ramp cells that should fail the slope test")
			local positive = bake(world)
			local onRampPositive = countWhere(positive.grid, function(c)
				return positive.grid.cellX[c] < -25 and positive.grid.cellX[c] > -37 and positive.grid.cellH[c] > 0.5
			end)
			t.truthy(onRampPositive > 20, `positive case should have ramp cells, got {onRampPositive}`)
		end
	)

	t.test("negative control: ramp at GRID_SIZE = 4 disconnects the ledge (rise 4 * tan = 1.86 > STEP_UP)", function()
		local world = MicroWorld.ramp(RAMP_DEGREES)
		local baked = bake(world, { GRID_SIZE = 4 })
		expectRegion(t, baked, world.probes.onFloor, 1, "floor")
		expectRegion(t, baked, world.probes.onLedge, 0, "ledge")
	end)

	t.test(
		"ramp connects at STEP_UP = 0.5, GRID_SIZE 1 (does not discriminate the allowance, see the next case)",
		function()
			local world = MicroWorld.ramp(RAMP_DEGREES)
			local baked = bake(world, { STEP_UP = 0.5 })
			expectRegion(t, baked, world.probes.onFloor, 1, "floor")
			expectRegion(t, baked, world.probes.onLedge, 1, "ledge")
		end
	)

	-- PLAN DEFECT, found by performing the mutation: the case above does NOT discriminate. At GRID_SIZE 1 and
	-- CAPSULE_RADIUS 1.5 the erosion window only reaches +-1 cell (the lattice has no neighbour at distance 1.5),
	-- so the worst rise it sees is 1 * tan(24.9) = 0.466 < 0.5 and dropping the allowance changes nothing. The
	-- allowance matters only when the window reaches CAPSULE_RADIUS: at GRID_SIZE 0.5 it reaches 3 cells, a rise of
	-- 1.5 * tan(24.9) = 0.696 > STEP_UP 0.5, while the link rule only needs 0.5 * tan(24.9) = 0.232.
	t.test("slope allowance (discriminating): at GRID_SIZE 0.5 the ramp connects at STEP_UP = 0.5 < 0.696", function()
		local world = MicroWorld.ramp(RAMP_DEGREES)
		local baked = bake(world, { GRID_SIZE = 0.5, STEP_UP = 0.5 })
		expectRegion(t, baked, world.probes.onFloor, 1, "floor")
		expectRegion(t, baked, world.probes.onLedge, 1, "ledge")
	end)

	t.test(
		"negative control: at GRID_SIZE 0.5 STEP_UP = 0.2, below 0.5 * tan(24.9) = 0.232, disconnects the ledge",
		function()
			local world = MicroWorld.ramp(RAMP_DEGREES)
			local baked = bake(world, { GRID_SIZE = 0.5, STEP_UP = 0.2 })
			expectRegion(t, baked, world.probes.onFloor, 1, "floor")
			expectRegion(t, baked, world.probes.onLedge, 0, "ledge")
		end
	)

	t.test("negative control: STEP_UP = 0.4, below GRID_SIZE * tan(24.9) = 0.464, disconnects the ledge", function()
		local world = MicroWorld.ramp(RAMP_DEGREES)
		local baked = bake(world, { STEP_UP = 0.4 })
		expectRegion(t, baked, world.probes.onFloor, 1, "floor")
		expectRegion(t, baked, world.probes.onLedge, 0, "ledge")
	end)

	-- C. thin walls --------------------------------------------------------------------------------------------
	t.test("a wall thinner than one cell does not leak: the two sides are different regions", function()
		local world = MicroWorld.thinWall(THIN_WALL)
		local baked = bake(world)
		expectRegion(t, baked, world.probes.west, 1, "west")
		expectRegion(t, baked, world.probes.east, 0, "east")
		local flat = bake(MicroWorld.flatRoom())
		t.truthy(
			baked.grid.counters.reached < flat.grid.counters.reached * 0.6,
			`thin wall reached {baked.grid.counters.reached} of the flat room's {flat.grid.counters.reached}`
		)
	end)

	t.test("negative control: the same room without the wall reaches the east probe", function()
		local world = MicroWorld.thinWall(THIN_WALL)
		local flat = bake(MicroWorld.flatRoom(), nil, { v(-6, 3, 0) })
		expectRegion(t, flat, world.probes.west, 1, "west")
		expectRegion(t, flat, world.probes.east, 1, "east")
	end)

	t.test("a wall thicker than a cell separates the sides too, so the segment test is not alone", function()
		local world = MicroWorld.thinWall(2.0)
		local baked = bake(world)
		expectRegion(t, baked, world.probes.west, 1, "west")
		expectRegion(t, baked, world.probes.east, 0, "east")
	end)

	-- D. headroom and the multi-layer field --------------------------------------------------------------------
	t.test("low ceiling at gap 5.0: no cell stands under the slab, and cells beside it are reached", function()
		local world = MicroWorld.lowCeiling(5.0)
		local baked = bake(world)
		expectRegion(t, baked, world.probes.beside, 1, "beside")
		local under = countWhere(baked.grid, function(c)
			return math.abs(baked.grid.cellX[c]) < 5 and math.abs(baked.grid.cellZ[c]) < 5 and baked.grid.cellH[c] < 1
		end)
		t.equal(under, 0, "ground cells under a 5-stud ceiling")
	end)

	t.test("negative control: low ceiling at gap 9.0 keeps the ground cells AND a second layer on the slab", function()
		local world = MicroWorld.lowCeiling(9.0)
		local baked = bake(world)
		local idx = WalkGrid.columnIndexOf(baked.grid, 0.5, 0.5)
		t.truthy(idx ~= nil, "column exists")
		if idx ~= nil then
			t.equal(baked.grid.colCount[idx], 2, "a floor above a floor: two cells in one column (D-07)")
			local first = baked.grid.colFirst[idx]
			t.truthy(baked.grid.cellH[first] < 1, "lower layer is the ground")
			t.truthy(baked.grid.cellH[first + 1] > 9, "upper layer is the slab top")
			t.equal(baked.grid.region[first], 1, "ground under a high slab is reached")
			t.equal(baked.grid.region[first + 1], 0, "the slab top is not reachable from the ground")
		end
	end)

	-- E. corridors ---------------------------------------------------------------------------------------------
	t.test("corridor at width 4.0: the near and far rooms are one region", function()
		local world = MicroWorld.narrowCorridor(4.0)
		local baked = bake(world)
		t.truthy(baked.grid.counters.cells > 0, "no cells at all")
		expectRegion(t, baked, world.probes.nearRoom, 1, "near room")
		expectRegion(t, baked, world.probes.farRoom, 1, "far room")
	end)

	-- Pitfall 4: corridor 3 with CAPSULE_RADIUS 1.5 at g = 1 leaves ZERO cells inside the corridor, and a test
	-- that only asserted "the far room is not reached" would pass for the wrong reason if the whole map had been
	-- eroded away. So the positive half is asserted first: cells exist, and the near room IS reached. Plan 03-07's
	-- maze fixture depends on the same discipline.
	t.test("negative control: corridor at width 3.0 erodes to nothing and separates the rooms", function()
		local world = MicroWorld.narrowCorridor(3.0)
		local baked = bake(world)
		t.truthy(baked.grid.counters.cells > 0, "no cells at all: the separation below would be vacuous")
		expectRegion(t, baked, world.probes.nearRoom, 1, "near room")
		expectRegion(t, baked, world.probes.farRoom, 0, "far room")
		local inCorridor = countWhere(baked.grid, function(c)
			return math.abs(baked.grid.cellX[c]) <= 5
		end)
		t.equal(inCorridor, 0, "cells left inside a 3-wide corridor")
		local wide = bake(MicroWorld.narrowCorridor(4.0))
		local wideCorridor = countWhere(wide.grid, function(c)
			return math.abs(wide.grid.cellX[c]) <= 5
		end)
		t.truthy(wideCorridor > 0, "the 4-wide corridor must keep cells, or the control proves nothing")
	end)

	-- F. spawns ------------------------------------------------------------------------------------------------
	t.test("two islands: seeding from both reaches both, seeding from one reaches only that one", function()
		local world = MicroWorld.twoIslands()
		local both = bake(world)
		expectRegion(t, both, world.probes.west, 1, "west (both seeds)")
		expectRegion(t, both, world.probes.east, 1, "east (both seeds)")
		local westOnly = bake(world, nil, { world.spawns[1] })
		expectRegion(t, westOnly, world.probes.west, 1, "west (west seed)")
		expectRegion(t, westOnly, world.probes.east, 0, "east (west seed)")
		local eastOnly = bake(world, nil, { world.spawns[2] })
		expectRegion(t, eastOnly, world.probes.west, 0, "west (east seed)")
		expectRegion(t, eastOnly, world.probes.east, 1, "east (east seed)")
	end)

	t.test("a spawn with no footing yields an empty seed list, never a silent full flood", function()
		local world = MicroWorld.spawnInVoid()
		local config = gridConfig()
		local index = Obb.newIndex(world.boxes, 8)
		local grid = WalkGrid.build(world.boxes, world.bounds, config, index)
		t.truthy(grid.counters.cells > 0, "the room itself must have cells")
		t.equal(#WalkGrid.seedsAt(grid, world.spawns[1], SPAWN_DROP), 0, "void spawn seeds")
		local normal = MicroWorld.flatRoom()
		t.truthy(#WalkGrid.seedsAt(grid, normal.spawns[1], SPAWN_DROP) > 0, "control: a spawn on the floor does seed")
		WalkGrid.flood(grid, world.boxes, index, {}, config)
		t.equal(grid.counters.reached, 0, "an empty seed list floods nothing")
	end)

	t.test("the pit has no standable cell within PICKUP_RANGE of the over-a-void probe (D-19)", function()
		local world = MicroWorld.pit()
		local baked = bake(world)
		local out: { number } = {}
		local probe = world.probes.overVoid
		t.equal(
			WalkGrid.cellsNear(baked.grid, probe.x, probe.z, Placement.PICKUP_RANGE, out) > 0,
			true,
			"cells in the column footprint"
		)
		local nearest = math.huge
		for c = 1, #baked.grid.cellH do
			local dx, dy, dz =
				baked.grid.cellX[c] - probe.x, baked.grid.cellH[c] - probe.y, baked.grid.cellZ[c] - probe.z
			nearest = math.min(nearest, math.sqrt(dx * dx + dy * dy + dz * dz))
		end
		t.truthy(nearest > Placement.PICKUP_RANGE + 10, `nearest cell is {nearest} away`)
		expectRegion(t, baked, world.probes.onFloor, 1, "floor beside the pit")
	end)

	t.test("a sealed closet has standable cells that the spawn does not reach", function()
		local world = MicroWorld.sealedRoom()
		local baked = bake(world)
		expectRegion(t, baked, world.probes.outside, 1, "outside")
		expectRegion(t, baked, world.probes.insideSealed, 0, "inside the closet")
	end)

	-- G. scale and structure -------------------------------------------------------------------------------------
	t.test("a long corridor floods without recursion", function()
		-- 6000 x 8 strip: a recursive fill would exceed Luau's call depth long before the far end.
		local boxes: { Obb.Box } = {
			Obb.fromPose("Strip", v(0, -0.5, 0), v(6000, 1, 8), v(0, 0, -1), v(0, 1, 0), true),
		}
		local world: MicroWorld.World = {
			boxes = boxes,
			bounds = { min = v(-3002, -2, -6), max = v(3002, 24, 6) },
			spawns = { v(-2990, 3, 0) },
			probes = { far = v(2990, 0.5, 0) },
		}
		local baked = bake(world)
		t.truthy(baked.grid.counters.reached > 20000, `reached only {baked.grid.counters.reached}`)
		expectRegion(t, baked, world.probes.far, 1, "far end")
	end)

	t.test("counters are asserted non-zero before a clock is read, then the bake meets a generous time cap", function()
		local started = os.clock()
		local baked = bake(MicroWorld.ramp())
		local counters = baked.grid.counters
		t.truthy(counters.columns > 0 and counters.cells > 0 and counters.reached > 0 and counters.linkTests > 0)
		local elapsed = os.clock() - started
		t.truthy(elapsed < 2.0, `ramp micro-world took {elapsed}s`)
	end)

	-- H. flood differential against union-find ------------------------------------------------------------------
	t.fuzz("the flood region equals an independent union-find over the same verified links", {
		iterations = FUZZ_TRIALS,
		gen = function(rng, i)
			local boxes = MicroWorld.flatRoom().boxes
			local extras = rng:nextInt(5, 15)
			for n = 1, extras do
				local kind = rng:nextNumber()
				local x = (rng:nextNumber() - 0.5) * 20
				local z = (rng:nextNumber() - 0.5) * 20
				-- Keep the spawn column at the origin clear.
				if math.abs(x) < 3.5 and math.abs(z) < 3.5 then
					x += if x < 0 then -5 else 5
				end
				local yaw = if rng:nextNumber() < 0.5 then 0 else rng:nextNumber() * math.pi
				local look = v(math.sin(yaw), 0, -math.cos(yaw))
				if kind < 0.15 then
					local length = 3 + rng:nextNumber() * 6
					local thickness = 0.3 + rng:nextNumber() * 1.7
					table.insert(
						boxes,
						Obb.fromPose(`wall{n}`, v(x, 10, z), v(length, 20, thickness), look, v(0, 1, 0), true)
					)
				elseif kind < 0.85 then
					local height = 0.3 + rng:nextNumber() * 0.6
					local sx, sz = 2 + rng:nextNumber() * 4, 2 + rng:nextNumber() * 4
					table.insert(
						boxes,
						Obb.fromPose(`step{n}`, v(x, height / 2, z), v(sx, height, sz), look, v(0, 1, 0), true)
					)
				else
					local height = 2 + rng:nextNumber() * 4
					local sx, sz = 2 + rng:nextNumber() * 3, 2 + rng:nextNumber() * 3
					table.insert(
						boxes,
						Obb.fromPose(`crate{n}`, v(x, height / 2, z), v(sx, height, sz), look, v(0, 1, 0), true)
					)
				end
			end
			return { boxes = boxes, i = i }
		end,
		check = function(value)
			local boxes: { Obb.Box } = value.boxes
			local bounds = MicroWorld.flatRoom().bounds
			local config = gridConfig()
			local index = Obb.newIndex(boxes, 8)
			local grid = WalkGrid.build(boxes, bounds, config, index)
			local seeds = WalkGrid.seedsAt(grid, v(0, 3, 0), SPAWN_DROP)
			fuzzRan += 1
			if #seeds == 0 then
				fuzzSkipped += 1
				return
			end
			WalkGrid.flood(grid, boxes, index, seeds, config)

			-- Independent side: every adjacent pair evaluated against EVERY box, no bucket index, no queue.
			local cellTotal = #grid.cellH
			local parent: { number } = table.create(cellTotal, 0)
			for c = 1, cellTotal do
				parent[c] = c
			end
			local stepUp, capHeight = config.STEP_UP, config.CAPSULE_HEIGHT
			for c = 1, cellTotal do
				local col = grid.colOf[c] - 1
				local ci, cj = col % grid.nx, col // grid.nx
				for _, delta in { { 1, 0 }, { 0, 1 } } do
					local ni, nj = ci + delta[1], cj + delta[2]
					if ni < grid.nx and nj < grid.nz then
						local nidx = nj * grid.nx + ni + 1
						for n = grid.colFirst[nidx], grid.colFirst[nidx] + grid.colCount[nidx] - 1 do
							local top = math.max(grid.cellH[c], grid.cellH[n])
							local linked = math.abs(grid.cellH[c] - grid.cellH[n]) <= stepUp
								and math.min(grid.cellCeil[c], grid.cellCeil[n]) - top >= capHeight
							if linked then
								for _, y in { top + stepUp + 0.25, top + capHeight - 0.25 } do
									for _, box in boxes do
										if
											Obb.segmentHits(
												box,
												grid.cellX[c],
												y,
												grid.cellZ[c],
												grid.cellX[n],
												y,
												grid.cellZ[n],
												Obb.GEOM_EPSILON
											)
										then
											linked = false
										end
									end
								end
							end
							if linked then
								parent[find(parent, c)] = find(parent, n)
							end
						end
					end
				end
			end
			local seedRoots: { [number]: boolean } = {}
			for _, s in seeds do
				seedRoots[find(parent, s)] = true
			end
			local reached = 0
			for c = 1, cellTotal do
				local expected = seedRoots[find(parent, c)] == true
				if expected then
					reached += 1
				end
				if (grid.region[c] == 1) ~= expected then
					error(
						`cell {c} at ({grid.cellX[c]}, {grid.cellH[c]}, {grid.cellZ[c]}): flood says {grid.region[c]}, union-find says {tostring(
							expected
						)}\nlayout:\n{describeLayout(boxes)}`,
						0
					)
				end
			end
			if reached == cellTotal then
				fuzzConnected += 1
			else
				fuzzPartitioned += 1
			end
		end,
	})

	t.test("the flood differential produced both fully-connected and partitioned layouts", function()
		print(
			`walkgrid fuzz coverage: trials={fuzzRan} connected={fuzzConnected} partitioned={fuzzPartitioned} skipped={fuzzSkipped}`
		)
		t.equal(fuzzRan, FUZZ_TRIALS, "every trial ran")
		t.truthy(
			fuzzConnected > MIN_PER_OUTCOME,
			`only {fuzzConnected} fully-connected layouts (floor {MIN_PER_OUTCOME})`
		)
		t.truthy(
			fuzzPartitioned > MIN_PER_OUTCOME,
			`only {fuzzPartitioned} partitioned layouts (floor {MIN_PER_OUTCOME})`
		)
	end)
end
