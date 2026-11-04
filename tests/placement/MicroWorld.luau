--!strict
-- Hand-built geometry fixtures for the placement specs (plan 03-04). A helper module, not a spec:
-- tests/run.luau discovers only *.spec.luau. Later plans (03-05, 03-06, 03-07) build corpus cases from these.
--
-- Conventions mirror scripts/maps/generate-graybox.luau: floor top at y = 0, perimeter walls 2 thick and 20 high,
-- a block is given by centre plus full size.
--
-- NO KNIFE EDGES (research Pitfall 7, gate 4). No PROBE coordinate may sit within 0.5 studs of a threshold, because
-- plan 03-05's stability probe re-runs every corpus coordinate at E +- 0.25 and requires an identical verdict.
-- This is about probes. Wall faces are different: narrowCorridor deliberately puts its faces ON a cell-centre
-- lattice line, because a corridor of width 3 with GRID_SIZE 1 spans three cell centres wherever it sits and only
-- the aligned placement is eroded to nothing (research Pitfall 4). That alignment is the point of the fixture.
local MapContract = require("../../src/server/core/MapContract")
local Obb = require("../../src/server/core/Obb")

type Vec3 = MapContract.Vec3

export type World = {
	boxes: { Obb.Box },
	bounds: MapContract.Aabb,
	spawns: { Vec3 },
	probes: { [string]: Vec3 },
}

local WALL_HEIGHT = 20
local WALL_THICKNESS = 2
local LOOK = { x = 0, y = 0, z = -1 }
local UP = { x = 0, y = 1, z = 0 }

local MicroWorld = {}

local function v(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

local function block(
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	standable: boolean?
): Obb.Box
	local flag = true
	if standable == false then
		flag = false
	end
	return Obb.fromPose(name, v(x, y, z), v(sx, sy, sz), LOOK, UP, flag)
end

-- A 24 x 24 floor (top y = 0) inside four perimeter walls whose inner faces sit at +-12.
local function roomBoxes(): { Obb.Box }
	return {
		block("Floor", 0, -0.5, 0, 24, 1, 24),
		block("NorthWall", 0, 10, -13, 28, WALL_HEIGHT, WALL_THICKNESS),
		block("SouthWall", 0, 10, 13, 28, WALL_HEIGHT, WALL_THICKNESS),
		block("WestWall", -13, 10, 0, WALL_THICKNESS, WALL_HEIGHT, 24),
		block("EastWall", 13, 10, 0, WALL_THICKNESS, WALL_HEIGHT, 24),
	}
end

local function roomBounds(): MapContract.Aabb
	return { min = v(-14, -2, -14), max = v(14, 24, 14) }
end

-- The baseline every other fixture varies.
function MicroWorld.flatRoom(): World
	return {
		boxes = roomBoxes(),
		bounds = roomBounds(),
		spawns = { v(0, 3, 0) },
		probes = { onFloor = v(4, 0.5, 4) },
	}
end

-- D-19: the over-a-void case. The graybox cannot express this: its perimeter walls fill the +-60..62 band solidly
-- from y 0 to 20, so the "void" the context document described is solid wall. Keeping the case in a synthetic
-- micro-world means regenerating the graybox under D-17 cannot silently delete it. Probe overVoid sits 20 below
-- the floor plane, so no standable cell exists within PICKUP_RANGE of it.
function MicroWorld.pit(): World
	local boxes: { Obb.Box } = {
		block("PitNorth", 0, -0.5, -7.5, 24, 1, 9),
		block("PitSouth", 0, -0.5, 7.5, 24, 1, 9),
		block("PitWest", -7.5, -0.5, 0, 9, 1, 6),
		block("PitEast", 7.5, -0.5, 0, 9, 1, 6),
		block("NorthWall", 0, 10, -13, 28, WALL_HEIGHT, WALL_THICKNESS),
		block("SouthWall", 0, 10, 13, 28, WALL_HEIGHT, WALL_THICKNESS),
		block("WestWall", -13, 10, 0, WALL_THICKNESS, WALL_HEIGHT, 24),
		block("EastWall", 13, 10, 0, WALL_THICKNESS, WALL_HEIGHT, 24),
	}
	return {
		boxes = boxes,
		bounds = { min = v(-14, -40, -14), max = v(14, 24, 14) },
		spawns = { v(0, 3, 8) },
		probes = { overVoid = v(0, -20, 0), onFloor = v(8, 0.5, 8) },
	}
end

-- A fully enclosed 6 x 6 closet (four walls and a ceiling, interior floor present). A standable cell exists
-- inside it and is NOT connected to the spawn's region: the Unreachable case.
function MicroWorld.sealedRoom(): World
	local boxes = roomBoxes()
	table.insert(boxes, block("ClosetWest", -4, 4, 9, 2, 8, 10))
	table.insert(boxes, block("ClosetEast", 4, 4, 9, 2, 8, 10))
	table.insert(boxes, block("ClosetNorth", 0, 4, 5, 10, 8, 2))
	table.insert(boxes, block("ClosetSouth", 0, 4, 13, 10, 8, 2))
	table.insert(boxes, block("ClosetCeiling", 0, 8.5, 9, 10, 1, 10))
	return {
		boxes = boxes,
		bounds = roomBounds(),
		spawns = { v(0, 3, -6) },
		probes = { insideSealed = v(0, 0.5, 9), outside = v(-8, 0.5, -6) },
	}
end

-- A full-width wall of the given thickness (default 0.3, research's measured leak case) splits the room. At
-- GRID_SIZE 1 a 0.3-thick wall at x in [0.75, 1.05] falls between the sample centres 0.5 and 1.5, so a grid-only
-- link test leaks and the whole room reads as one region.
function MicroWorld.thinWall(thickness: number?): World
	local t = thickness or 0.3
	local boxes = roomBoxes()
	table.insert(boxes, block("Divider", 0.9, 10, 0, t, WALL_HEIGHT, 26))
	return {
		boxes = boxes,
		bounds = roomBounds(),
		spawns = { v(-6, 3, 0) },
		probes = { west = v(-6, 0.5, 0), east = v(6, 0.5, 0) },
	}
end

-- A floor, a raised ledge and a ramp connecting them, built the way the graybox's Ramp is: a plank rolled about Z.
-- The default 24.9047 degrees is atan(6.5 / 14), the reference map's slope; the ledge top is the ramp's rise.
function MicroWorld.ramp(slopeDegrees: number?): World
	local degrees = slopeDegrees or 24.9047
	local angle = math.rad(degrees)
	local run = 14
	local rise = run * math.tan(angle)
	local length = math.sqrt(run * run + rise * rise)
	local boxes: { Obb.Box } = {
		block("Floor", -30, -0.5, 0, 100, 1, 40),
		block("Ledge", -48, rise - 0.5, 0, 20, 1, 12),
	}
	local lookVector = v(0, 0, -1)
	-- A roll about Z by -angle: up = (sin, cos, 0), and the plank rises toward -x.
	local upVector = v(math.sin(angle), math.cos(angle), 0)
	local centre = v(-31 - 0.5 * math.sin(angle), rise / 2 - 0.5 * math.cos(angle), 0)
	table.insert(boxes, Obb.fromPose("Ramp", centre, v(length, 1, 6), lookVector, upVector, true))
	return {
		boxes = boxes,
		bounds = { min = v(-80, -2, -20), max = v(20, 30, 20) },
		spawns = { v(-10, 3, 0) },
		probes = { onLedge = v(-48, rise + 0.5, 0), onFloor = v(-10, 0.5, 5) },
	}
end

-- A slab suspended `gap` studs above the floor (default 5.0). Under it the headroom is below CAPSULE_HEIGHT 7.0 so
-- no cell is standable; beside it cells are. At gap 9 the column under the slab holds two cells, which is the
-- multi-layer property (D-07).
function MicroWorld.lowCeiling(gap: number?): World
	local g = gap or 5.0
	local boxes = roomBoxes()
	table.insert(boxes, block("Slab", 0, g + 0.5, 0, 12, 1, 12))
	return {
		boxes = boxes,
		bounds = roomBounds(),
		spawns = { v(-9, 3, 0) },
		probes = { under = v(0, 0.5, 0), beside = v(9, 0.5, 0) },
	}
end

-- Two rooms joined by a corridor of the given width. Authoring rule: width >= 2 * CAPSULE_RADIUS + GRID_SIZE
-- (4.0 at the shipped values), so the default 4.0 passes and 3.0 is eroded to nothing. The corridor faces sit on
-- lattice lines at z = +-width / 2 on purpose (see the header).
function MicroWorld.narrowCorridor(width: number?): World
	local w = width or 4.0
	local sideLength = 12 - w / 2
	local sideCentre = (w / 2 + 12) / 2
	local boxes: { Obb.Box } = {
		block("Floor", 0, -0.5, 0, 56, 1, 24),
		block("NorthWall", 0, 10, -13, 60, WALL_HEIGHT, WALL_THICKNESS),
		block("SouthWall", 0, 10, 13, 60, WALL_HEIGHT, WALL_THICKNESS),
		block("WestWall", -29, 10, 0, WALL_THICKNESS, WALL_HEIGHT, 24),
		block("EastWall", 29, 10, 0, WALL_THICKNESS, WALL_HEIGHT, 24),
		block("CorridorNorth", 0, 10, -sideCentre, 12, WALL_HEIGHT, sideLength),
		block("CorridorSouth", 0, 10, sideCentre, 12, WALL_HEIGHT, sideLength),
	}
	return {
		boxes = boxes,
		bounds = { min = v(-30, -2, -14), max = v(30, 24, 14) },
		spawns = { v(-15, 3, 0) },
		probes = { nearRoom = v(-15, 0.5, 0), farRoom = v(15, 0.5, 0), corridor = v(0, 0.5, 0.5) },
	}
end

-- Two disconnected floors, one spawn on each: the SpawnDisconnected fixture (D-06's check, failing direction).
function MicroWorld.twoIslands(): World
	local boxes: { Obb.Box } = {
		block("IslandWest", -20, -0.5, 0, 20, 1, 20),
		block("IslandEast", 20, -0.5, 0, 20, 1, 20),
	}
	return {
		boxes = boxes,
		bounds = { min = v(-32, -2, -12), max = v(32, 24, 12) },
		spawns = { v(-20, 3, 0), v(20, 3, 0) },
		probes = { west = v(-20, 0.5, 0), east = v(20, 0.5, 0) },
	}
end

-- The flat room with its single spawn far above any floor and beyond any sensible drop limit: SpawnNoFooting
-- (Pitfall 10).
function MicroWorld.spawnInVoid(): World
	local world = MicroWorld.flatRoom()
	world.spawns = { v(0, 30, 0) }
	return world
end

-- The flat room with bounds of +-1000 on x and z, for the bake-size-ceiling fixture of plan 03-05.
function MicroWorld.hugeBounds(): World
	local world = MicroWorld.flatRoom()
	world.bounds = { min = v(-1000, -2, -1000), max = v(1000, 24, 1000) }
	return world
end

return MicroWorld
