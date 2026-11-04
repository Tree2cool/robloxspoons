--!strict
-- D-17's enforcement and MAP-03's evidence (plan 03-06). Every default spot authored on the committed gray-box
-- must pass the REAL placement rules (survivors == authored, not survivors >= 16), with a printed reach margin,
-- and every positive claim here has a negative control, because a positive-only assertion proves nothing:
-- slope 24 (the ledge must disconnect), grid 4 (the resolution coupling), clearance 0.5 (the cliff) and one
-- shared reach/eye height (the reason EYE_HEIGHT exists), plus a wall-clock cap guarded by work counters and a
-- tiny-cap control.
--
-- D-15: if a spot here fails, fix the MAP in scripts/maps/generate-graybox.luau. Never a rule, never a constant,
-- never MIN_DEFAULT_SPOTS.
local MapContract = require("../../src/server/core/MapContract")
local Placement = require("../../src/shared/Config/Placement")
local Snapshot = require("../../scripts/maps/snapshot")
local SpoonPlacement = require("../../src/server/core/SpoonPlacement")
local WalkGrid = require("../../src/server/core/WalkGrid")
local Test = require("../harness/Test")

type Vec3 = MapContract.Vec3
type Node = MapContract.Node

local GRAYBOX = "maps/gray-box.rbxm"
local GRAYBOX_CAP_SECONDS = 0.5
local MIN_MARGIN = 0.5

type Spot = { name: string, position: Vec3 }
type Baked = { world: SpoonPlacement.World?, faults: { SpoonPlacement.BakeFault }, spots: { Spot }, spawns: { Vec3 } }

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

-- Loads the committed map, snapshots it, builds boxes and bakes with the shipped config plus overrides.
-- `emptyBoxes` exists only for the vacuity mutation of gate 3.
local function bakeGraybox(overrides: { [string]: number }, emptyBoxes: boolean?): Baked
	local root, reason = Snapshot.loadFile(GRAYBOX)
	assert(root ~= nil, reason)
	local config: any = table.clone(Placement)
	for key, value in overrides do
		config[key] = value
	end
	local data = childNamed(root, "Data")
	local boundsNode = childNamed(data, "Bounds")
	local centre = boundsNode.position :: Vec3
	local size = boundsNode.size :: Vec3
	local spawns: { Vec3 } = {}
	for _, spawn in childNamed(data, "SeekerSpawns").children do
		table.insert(spawns, spawn.position :: Vec3)
	end
	local spots: { Spot } = {}
	for _, spot in childNamed(data, "DefaultSpots").children do
		table.insert(spots, { name = spot.name, position = spot.position :: Vec3 })
	end
	table.sort(spots, function(a, b)
		return a.name < b.name
	end)
	local boxes = if emptyBoxes == true
		then {}
		else SpoonPlacement.boxesOf(root, config :: SpoonPlacement.PlacementConfig)
	local bounds = {
		min = v(centre.x - size.x / 2, centre.y - size.y / 2, centre.z - size.z / 2),
		max = v(centre.x + size.x / 2, centre.y + size.y / 2, centre.z + size.z / 2),
	}
	local world, faults = SpoonPlacement.bake(boxes, bounds, spawns, config :: SpoonPlacement.PlacementConfig)
	return { world = world, faults = faults, spots = spots, spawns = spawns }
end

local function bakedWorld(b: Baked): SpoonPlacement.World
	assert(b.world ~= nil, `graybox did not bake: {#b.faults} faults`)
	return b.world
end

-- Survivor count plus the verdict of every spot, by name.
local function verdicts(b: Baked): ({ [string]: SpoonPlacement.Verdict }, number)
	local world = bakedWorld(b)
	local out: { [string]: SpoonPlacement.Verdict } = {}
	local survivors = 0
	for _, spot in b.spots do
		local verdict = SpoonPlacement.check(world, spot.position)
		out[spot.name] = verdict
		if verdict.ok then
			survivors += 1
		end
	end
	return out, survivors
end

-- Distance from a spot to its nearest spawn-connected (region 1) cell's reach point, or nil if none is within
-- the pickup range. Margin is effectiveRange minus this.
local function nearestConnected(world: SpoonPlacement.World, p: Vec3): number?
	local grid = world.grid
	local out: { number } = {}
	local count = WalkGrid.cellsNear(grid, p.x, p.z, world.config.PICKUP_RANGE, out)
	local best: number? = nil
	for n = 1, count do
		local c = out[n]
		if grid.region[c] == 1 then
			local dx = grid.cellX[c] - p.x
			local dy = grid.cellH[c] + world.config.REACH_HEIGHT - p.y
			local dz = grid.cellZ[c] - p.z
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if best == nil or d < best then
				best = d
			end
		end
	end
	return best
end

local LEDGE = { "Spot18", "Spot19", "Spot20", "Spot21" }

local function withinCap(elapsed: number, cap: number): boolean
	return elapsed < cap
end

return function(t: Test.Runner)
	local defaultBake: Baked? = nil
	local function defaults(): Baked
		if defaultBake == nil then
			defaultBake = bakeGraybox({})
		end
		return defaultBake :: Baked
	end

	t.test("every authored default spot passes the real placement rules (D-17 STRICT)", function()
		local b = defaults()
		local results, survivors = verdicts(b)
		for _, spot in b.spots do
			local verdict = results[spot.name]
			t.truthy(
				verdict.ok,
				`{spot.name} at ({spot.position.x}, {spot.position.y}, {spot.position.z}) failed: {verdict.reason}`
			)
		end
		-- STRICT means survivors equals authored, not survivors at least 16. A tolerant reading would let a map
		-- ship a spot the hider can place a spoon on that no seeker can find, which is exactly what MAP-02's
		-- "fails the build on any that would be unfindable" forbids.
		t.equal(survivors, #b.spots)
		t.truthy(
			#b.spots >= MapContract.MIN_DEFAULT_SPOTS,
			`{#b.spots} authored against a minimum of {MapContract.MIN_DEFAULT_SPOTS}`
		)
	end)

	t.test("every authored spot carries at least 0.5 studs of reach margin", function()
		local b = defaults()
		local world = bakedWorld(b)
		local lines: { string } = { "graybox spot margins (effective range " .. tostring(world.effectiveRange) .. "):" }
		for _, spot in b.spots do
			local d = nearestConnected(world, spot.position)
			t.truthy(d ~= nil, `{spot.name} has no connected cell within the pickup range`)
			local distance = d :: number
			local margin = world.effectiveRange - distance
			table.insert(
				lines,
				string.format(
					"  %s  surface y %.1f  distance %.3f  margin %.3f",
					spot.name,
					spot.position.y - 0.5,
					distance,
					margin
				)
			)
			t.truthy(margin >= MIN_MARGIN, `{spot.name} margin is {margin}, below {MIN_MARGIN}`)
		end
		-- Research measured the tightest authored spots at 1.44 (crate top) and 1.04 studs of slack at the
		-- shipped values; 0.5 is the floor this asserts, so a future map edit that halves a margin still shows
		-- up as a number rather than as a pass.
		print(table.concat(lines, "\n"))
	end)

	t.test("all four seeker spawns reach one connected region (D-06)", function()
		local b = defaults()
		local world = bakedWorld(b)
		t.equal(#b.faults, 0)
		for _, fault in b.faults do
			t.falsy(fault.kind == "SpawnDisconnected" or fault.kind == "SpawnNoFooting", fault.detail)
		end
		-- The explicit form. On its own this is true by construction (the combined flood is seeded from every
		-- spawn); the per-spawn flood inside bake is what can fail, and `#faults == 0` above is that check.
		t.equal(#b.spawns, 4)
		for i, spawn in b.spawns do
			local seeds = WalkGrid.seedsAt(world.grid, spawn, SpoonPlacement.SPAWN_DROP_LIMIT)
			t.truthy(#seeds > 0, `spawn {i} has no seed cells`)
			for _, c in seeds do
				t.equal(world.grid.region[c], 1, `spawn {i} seed cell is in region {world.grid.region[c]}`)
			end
		end
	end)

	t.test("at MAX_SLOPE_DEGREES 24 the ramp does not connect and the four ledge spots fail", function()
		-- The Ramp is atan(6.5 / 14) = 24.9047 degrees. Research measured 12 of the ORIGINAL 18 spots surviving
		-- at slope 24 (the two shelf spots were already culled for other reasons); with this plan's 21-spot
		-- table the expected figure is 17. If the observed number differs, record it -- do not adjust the
		-- assertion until the difference is understood.
		local results, survivors = verdicts(bakeGraybox({ MAX_SLOPE_DEGREES = 24 }))
		for _, name in LEDGE do
			t.falsy(results[name].ok, `{name} still passes with a 24 degree slope limit`)
			t.equal(results[name].reason, "Unreachable", name)
		end
		t.equal(survivors, 17)
	end)

	t.test("at GRID_SIZE 4 the ledge disconnects by the resolution coupling", function()
		-- Per-cell rise is 4 * tan(24.9047) = 1.86 against STEP_UP 1.0, the invariant
		-- tests/placement/config_lock.spec.luau asserts arithmetically. This case is its executable half.
		local results, survivors = verdicts(bakeGraybox({ GRID_SIZE = 4 }))
		for _, name in LEDGE do
			t.falsy(results[name].ok, `{name} still passes at GRID_SIZE 4`)
			t.equal(results[name].reason, "Unreachable", name)
		end
		local failed: { string } = {}
		for name, verdict in results do
			if not verdict.ok then
				table.insert(failed, `{name}={verdict.reason}`)
			end
		end
		table.sort(failed)
		print(`graybox at GRID_SIZE 4: {survivors} of 21 survive; failing: {table.concat(failed, " ")}`)
		-- Measured 16, not the 17 that the ledge alone would explain: at a 4-stud lattice the east hall crate-top
		-- spot (Spot16) also loses its connected cell and reports Unreachable. Recorded, not absorbed.
		t.equal(results.Spot16.reason, "Unreachable")
		t.equal(survivors, 16)
	end)

	t.test("at SPOT_CLEARANCE 0.5 not one authored spot survives", function()
		-- Every authored anchor sits exactly 0.5 above its surface, so a `<=` comparison at clearance 0.5 culls
		-- all of them. Measured: 0.25, 0.40 and 0.49 all pass; 0.50, 0.6 and 1.0 all give zero. This is the
		-- executable half of the arithmetic guard in config_lock.spec.luau; it is here because only a real bake
		-- over the real map can show the cliff rather than assert a number about it.
		local _, survivors = verdicts(bakeGraybox({ SPOT_CLEARANCE = 0.5 }))
		t.equal(survivors, 0)
		local _, justBelow = verdicts(bakeGraybox({ SPOT_CLEARANCE = 0.49 }))
		t.equal(justBelow, 21)
	end)

	t.test("one shared reach and eye height culls the crate-top spots (Pitfall 1)", function()
		-- This case only runs because assertConfig's height invariant is CAPSULE_HEIGHT > EYE_HEIGHT >=
		-- REACH_HEIGHT with the lower comparison NON-STRICT. REACH_HEIGHT is 2.5, so EYE_HEIGHT = 2.5 is the
		-- degenerate single-height configuration, the exact one research measured. If this throws instead of
		-- producing NoSight verdicts the bug is in assertConfig (plan 03-05), not here. Do NOT move this
		-- override to 2.6: 2.5 is the height research measured the 8.75-stud requirement at, and 2.6 would
		-- require re-deriving which spots are culled rather than reusing a measured number.
		-- Measured, a spoon on a 4-stud crate needs a line of sight of 8.75 / 6.82 / 4.95 / 4.06 studs at eye
		-- heights 2.5 / 3.0 / 3.5 / 4.0. This is the largest single swing in the number ladder and the reason
		-- EYE_HEIGHT is a separate constant. Phase 5's hunt must consume the same value.
		local results, survivors = verdicts(bakeGraybox({ EYE_HEIGHT = 2.5 }))
		t.falsy(results.Spot06.ok)
		t.equal(results.Spot06.reason, "NoSight")
		t.falsy(results.Spot16.ok)
		t.equal(results.Spot16.reason, "NoSight")
		print(`graybox at EYE_HEIGHT 2.5: {survivors} of 21 survive`)
	end)

	t.test("the reference-map bake completes inside the CI cap", function()
		-- Gate 3: a time cap passes vacuously if the bake did nothing, so the DETERMINISTIC work counters are
		-- asserted FIRST and the wall clock is only the backstop. The counter floors below are chosen well
		-- below the measured values so a loaded runner cannot flake them while an empty bake still fails. The
		-- cap is 0.5 s, about 17x headroom over the measured ~28 ms bake (assumption A5: CI 2x to 4x slower).
		local started = os.clock()
		local b = bakeGraybox({})
		local world = bakedWorld(b)
		local _, survivors = verdicts(b)
		local elapsed = os.clock() - started
		print(
			`graybox bake+checks: {elapsed} s; counters boxes={world.counters.boxes} columns={world.counters.columns} `
				.. `spans={world.counters.spans} cells={world.counters.cells} reached={world.counters.reached} `
				.. `linkTests={world.counters.linkTests} eroded={world.counters.eroded}`
		)
		t.truthy(world.counters.columns > 10000, `columns was {world.counters.columns}`)
		t.truthy(world.counters.cells > 5000, `cells was {world.counters.cells}`)
		t.truthy(world.counters.reached > 5000, `reached was {world.counters.reached}`)
		t.truthy(world.counters.linkTests > 1000, `linkTests was {world.counters.linkTests}`)
		t.truthy(world.counters.boxes > 20, `boxes was {world.counters.boxes}`)
		t.equal(survivors, 21)
		t.truthy(
			withinCap(elapsed, GRAYBOX_CAP_SECONDS),
			`bake took {elapsed} s against a cap of {GRAYBOX_CAP_SECONDS}`
		)
	end)

	t.test("a deliberately tiny cap fails, so the cap is a real gate", function()
		local started = os.clock()
		local b = bakeGraybox({})
		bakedWorld(b)
		local elapsed = os.clock() - started
		t.truthy(elapsed > 0, "the bake took no measurable time")
		t.falsy(withinCap(elapsed, 1e-9), `elapsed {elapsed} s unexpectedly beat a cap of 1e-9`)
	end)

	-- Exported for the vacuity mutation: a bake handed an empty box list must be rejected by the counter floors.
	t.test("an empty box list yields counters the floors above would reject", function()
		local b = bakeGraybox({}, true)
		-- No geometry means no footing for any spawn: the bake refuses rather than flooding nothing.
		t.equal(b.world, nil)
		t.truthy(#b.faults > 0, "an empty bake must report faults")
	end)
end
