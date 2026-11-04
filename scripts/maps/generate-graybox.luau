--!strict
-- Generates the gray-box reference map and writes it as a single-root .rbxm (D-05, D-08, D-18).
--
--   lune run scripts/maps/generate-graybox.luau [outputPath]        (default: maps/gray-box.rbxm)
--
-- D-18: this is a deliberate, scoped exception to D-07 (instances authored in Studio). There is no Studio in the
-- build container and Phases 3 and 5 need real geometry to validate placement against. Shipped art maps stay
-- Studio-authored; a human may refine this map in Studio and re-export over the committed file.
--
-- D-08: mechanically complete, no art. Four corner rooms joined by doorways, a ring corridor around a solid core,
-- a lobby holding the visible card table, a raised ledge with a ramp, pillars, a shelf and crates, so spots exist
-- at several heights and some sightlines are broken. The placement rules now exist in
-- src/server/core/SpoonPlacement.luau and the authored spot table is validated against them by
-- tests/placement/graybox_spots.spec.luau (plan 03-06). The NE room also holds a 2-stud crate; the SE room holds
-- a shelf that no spot is authored on (it is the "shelf out of reach" corpus fixture, see the spot table).
--
-- Layout (x east, z south, y up, studs; floor top is y = 0):
--
--        x=-60        -28        28         60
--   z=-60 +-----------+----------+-----------+
--         |  NW room  |  LOBBY   |  NE room  |   lobby: card table at (0, 3, -40)
--   z=-28 +-----doorway+  ------  +doorway----+
--         |  W hall   | ring+core|  E hall   |   ring corridor around the solid core (|x|,|z| < 16)
--   z= 28 +-----doorway+  ------  +doorway----+
--         |  SW room  | S hall   |  SE room  |   hider spawn at (0, 3, 40)
--   z= 60 +-----------+----------+-----------+
--
-- The Lune roblox library types only Instance.new; its datatype constructors exist at runtime but are untyped
-- ("TODO: Make typedefs for all of the datatypes"). Everything that touches a datatype or a property goes through
-- the two small helpers below, which are the only places a cast to `any` appears.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local rbx = roblox :: any

type Inst = roblox.Instance

local OUTPUT_PATH = process.args[1] or "maps/gray-box.rbxm"

-- Contract constants. Duplicated as literals on purpose: this script must stay runnable even if the contract
-- module moves, and the validator round-trip in tests/maps/graybox.spec.luau catches any drift.
local TAG_DEFAULT_SPOT = "SpoonDefaultSpot"
local TAG_SEEKER_SPAWN = "SeekerSpawn"
local TAG_DECOY_ANCHOR = "DecoyAnchor"

local WALL_HEIGHT = 20
local WALL_THICKNESS = 2

local function vec3(x: number, y: number, z: number): any
	return rbx.Vector3.new(x, y, z)
end

local function cframeAt(x: number, y: number, z: number): any
	return rbx.CFrame.new(x, y, z)
end

local function setProps(inst: Inst, props: { [string]: any })
	local untyped = inst :: any
	for key, value in props do
		untyped[key] = value
	end
end

local function make(className: string, name: string, parent: Inst?): Inst
	local inst = roblox.Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

-- A solid, anchored, visible block of geometry centred at (x, y, z).
local function block(
	parent: Inst,
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number
): Inst
	local part = make("Part", name, parent)
	setProps(part, { Size = vec3(sx, sy, sz), CFrame = cframeAt(x, y, z), Anchored = true, CanCollide = true })
	return part
end

-- Anchors are invisible, non-colliding 1x1x1 Parts (not Attachments) so position and orientation read out of a
-- .rbxm through CFrame without world-transform maths.
local function anchor(parent: Inst, name: string, cframe: any, tag: string?): Inst
	local part = make("Part", name, parent)
	setProps(part, {
		Size = vec3(1, 1, 1),
		CFrame = cframe,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
	})
	if tag ~= nil then
		part:AddTag(tag)
	end
	return part
end

local function anchorAt(parent: Inst, name: string, x: number, y: number, z: number, tag: string?): Inst
	return anchor(parent, name, cframeAt(x, y, z), tag)
end

-- A wall running along the z axis at x, from z0 to z1, with an optional doorway gap [g0, g1].
local function wallAlongZ(parent: Inst, name: string, x: number, z0: number, z1: number, g0: number?, g1: number?)
	local y = WALL_HEIGHT / 2
	if g0 == nil or g1 == nil then
		block(parent, name, x, y, (z0 + z1) / 2, WALL_THICKNESS, WALL_HEIGHT, z1 - z0)
		return
	end
	block(parent, `{name}A`, x, y, (z0 + g0) / 2, WALL_THICKNESS, WALL_HEIGHT, g0 - z0)
	block(parent, `{name}B`, x, y, (g1 + z1) / 2, WALL_THICKNESS, WALL_HEIGHT, z1 - g1)
end

-- A wall running along the x axis at z, from x0 to x1, with an optional doorway gap [g0, g1].
local function wallAlongX(parent: Inst, name: string, z: number, x0: number, x1: number, g0: number?, g1: number?)
	local y = WALL_HEIGHT / 2
	if g0 == nil or g1 == nil then
		block(parent, name, (x0 + x1) / 2, y, z, x1 - x0, WALL_HEIGHT, WALL_THICKNESS)
		return
	end
	block(parent, `{name}A`, (x0 + g0) / 2, y, z, g0 - x0, WALL_HEIGHT, WALL_THICKNESS)
	block(parent, `{name}B`, (g1 + x1) / 2, y, z, x1 - g1, WALL_HEIGHT, WALL_THICKNESS)
end

local function buildGeometry(geometry: Inst)
	-- Floor 120 x 1 x 120, top surface at y = 0.
	block(geometry, "Floor", 0, -0.5, 0, 120, 1, 120)

	-- Closed perimeter. North/south are 124 long so the four corners are sealed (side walls are 120 long).
	local perimeter = make("Folder", "Perimeter", geometry)
	block(perimeter, "NorthWall", 0, 10, -61, 124, WALL_HEIGHT, WALL_THICKNESS)
	block(perimeter, "SouthWall", 0, 10, 61, 124, WALL_HEIGHT, WALL_THICKNESS)
	block(perimeter, "WestWall", -61, 10, 0, WALL_THICKNESS, WALL_HEIGHT, 120)
	block(perimeter, "EastWall", 61, 10, 0, WALL_THICKNESS, WALL_HEIGHT, 120)

	-- Four corner rooms. Each has an inner wall facing the lobby/south hall and one facing the side hall,
	-- with a 12-stud doorway in each, so every room has two ways in and the corridor loop stays connected.
	local rooms = make("Folder", "Rooms", geometry)
	wallAlongZ(rooms, "NwEastWall", -28, -60, -28, -46, -34)
	wallAlongX(rooms, "NwSouthWall", -28, -60, -28, -50, -38)
	wallAlongZ(rooms, "NeWestWall", 28, -60, -28, -46, -34)
	wallAlongX(rooms, "NeSouthWall", -28, 28, 60, 38, 50)
	wallAlongZ(rooms, "SwEastWall", -28, 28, 60, 34, 46)
	wallAlongX(rooms, "SwNorthWall", 28, -60, -28, -50, -38)
	wallAlongZ(rooms, "SeWestWall", 28, 28, 60, 34, 46)
	wallAlongX(rooms, "SeNorthWall", 28, 28, 60, 38, 50)

	-- Solid core. The open area around it is the ring corridor (12 studs wide, walkable all the way round).
	block(geometry, "Core", 0, 10, 0, 32, WALL_HEIGHT, 32)

	-- West hall: raised ledge (20 x 1 x 12, top at y = 6.5) with a ramp up from the east.
	block(geometry, "Ledge", -48, 6, 0, 20, 1, 12)
	local runX = 14 -- ground at x = -24, ledge lip at x = -38
	local rise = 6.5
	local length = math.sqrt(runX * runX + rise * rise)
	local angle = math.atan(rise / runX)
	-- Plank centre sits half a thickness below the line through the two surface endpoints, along the normal.
	local ramp = make("Part", "Ramp", geometry)
	local centreX = -31 - 0.5 * math.sin(angle)
	local centreY = rise / 2 - 0.5 * math.cos(angle)
	setProps(ramp, {
		Size = vec3(length, 1, 6),
		-- Negative roll about z: rises toward -x.
		CFrame = cframeAt(centreX, centreY, 0) * rbx.CFrame.Angles(0, 0, -angle),
		Anchored = true,
		CanCollide = true,
	})

	-- Pillars in the south hall (occlusion in an open room), crates, and a high shelf.
	block(geometry, "PillarWest", -14, 10, 44, 4, WALL_HEIGHT, 4)
	block(geometry, "PillarEast", 14, 10, 44, 4, WALL_HEIGHT, 4)
	block(geometry, "CrateEastHall", 48, 2, -12, 4, 4, 4)
	block(geometry, "CrateSouthWestRoom", -33, 2, 33, 4, 4, 4)
	block(geometry, "ShelfSouthEastRoom", 50, 8, 59, 8, 1, 2)
	-- A 2-stud crate so the authored spots cover a fourth distinct height. Its top is NOT walkable at STEP_UP 1.0,
	-- so like the other crates it is a "standable beside" case rather than terrain.
	block(geometry, "CrateNorthEastRoom", 33, 1, -45, 4, 2, 4)

	-- Lobby set dressing: the visible table and chairs. The anchors live under Data, not here.
	-- Plan said 12 x 1 x 12; at that size the table would overlap the radius-6 seat ring, so it is 8 x 1 x 8.
	local lobby = make("Folder", "Lobby", geometry)
	block(lobby, "TablePedestal", 0, 1.5, -40, 2, 3, 2)
	block(lobby, "TableTop", 0, 3, -40, 8, 1, 8)
	for i = 1, 9 do
		local a = math.rad((i - 1) * 40)
		block(lobby, `Chair{i}`, 6 * math.sin(a), 1, -40 - 6 * math.cos(a), 2, 2, 2)
	end
end

local function buildData(data: Inst)
	-- One axis-aligned box (D-19), identity rotation, centred so it spans x/z +-62 and y -1..29.
	local bounds = anchorAt(data, "Bounds", 0, 14, 0, nil)
	setProps(bounds, { Size = vec3(124, 30, 124) })

	anchorAt(data, "HiderSpawn", 0, 3, 40, nil)

	local seekerSpawns = make("Folder", "SeekerSpawns", data)
	anchorAt(seekerSpawns, "Spawn1", -40, 3, -40, TAG_SEEKER_SPAWN)
	anchorAt(seekerSpawns, "Spawn2", 40, 3, -40, TAG_SEEKER_SPAWN)
	anchorAt(seekerSpawns, "Spawn3", -40, 3, 40, TAG_SEEKER_SPAWN)
	anchorAt(seekerSpawns, "Spawn4", 40, 3, 40, TAG_SEEKER_SPAWN)

	-- 21 spots against the 16-spot MIN_DEFAULT_SPOTS, five spare (D-15). Each is { x, surfaceY, z };
	-- the anchor sits half a stud above its surface, which is why SPOT_CLEARANCE must stay below 0.5
	-- (at 0.5 a `<=` comparison culls every one of them -- measured).
	--
	-- D-17 is STRICT: every authored spot must pass the real placement rules and any failure fails
	-- the build. tests/placement/graybox_spots.spec.luau proves it spot by spot WITH the margin, so
	-- a spot added here without checking will fail CI rather than quietly become a 17th survivor.
	--
	-- TWO SPOTS WERE REMOVED IN PHASE 3 AND MUST NOT BE RE-AUTHORED:
	--   the shelf centre (50, 8.5, 59) -- measured d*los = 12.36. Blocked by the shelf slab from
	--     every floor position within 12 studs. Genuinely unfindable at any sane pickup range; this
	--     was never a tuning problem.
	--   the shelf east edge (54, 8.5, 59) -- measured d*conn = d*los = 6.54 against an effective
	--     range of 5.5. PICKUP_RANGE 8.5 would admit it and was rejected: choosing a gameplay
	--     constant to make map validation pass is D-15 running backwards.
	-- Both report Unreachable (not OutOfReach) at the shipped config: the shelf top carries its own standable
	-- cells that are inside E but not spawn-connected (plan 03-05).
	-- The SHELF ITSELF STAYS. It is the "shelf out of reach" corpus fixture (03-05 corpus.spec
	-- probes (50, 9.0, 59) and (54, 9.0, 59)), so deleting it would delete two corpus cases.
	-- The four ledge spots connect because the Ramp's 24.9 degrees is under the 30 degree slope limit.
	-- Heights: 14 floor (0), 1 at 2, 2 crate tops (4), 4 ledge (6.5) -- four distinct, four at y >= 6.
	local spots: { { number } } = {
		{ -55, 0, -55 }, -- 01 NW room, far corner
		{ -33, 0, -55 }, -- 02 NW room
		{ 55, 0, -55 }, -- 03 NE room, far corner
		{ 33, 0, -33 }, -- 04 NE room, behind the doorway wall
		{ -55, 0, 55 }, -- 05 SW room, far corner
		{ -33, 4, 33 }, -- 06 SW room, on top of CrateSouthWestRoom
		{ 33, 0, 55 }, -- 07 SE room
		{ 50, 0, 50 }, -- 08 SE room floor, below the shelf's open side (was the shelf centre)
		{ 55, 0, 40 }, -- 09 SE room floor, by the east wall (was the shelf east edge)
		{ -20, 0, -56 }, -- 10 lobby, behind the table from the east door
		{ 20, 0, -56 }, -- 11 lobby
		{ 0, 0, -22 }, -- 12 ring corridor, north of the core
		{ 22, 0, 0 }, -- 13 ring corridor, east of the core
		{ 0, 0, 22 }, -- 14 ring corridor, south of the core
		{ -22, 0, 0 }, -- 15 ring corridor, west of the core
		{ 48, 4, -12 }, -- 16 east hall, on top of CrateEastHall
		{ 33, 2, -45 }, -- 17 NE room, on top of CrateNorthEastRoom
		{ -56, 6.5, -4 }, -- 18 ledge
		{ -56, 6.5, 4 }, -- 19 ledge
		{ -44, 6.5, -4 }, -- 20 ledge
		{ -44, 6.5, 4 }, -- 21 ledge
	}
	local defaultSpots = make("Folder", "DefaultSpots", data)
	for i, s in spots do
		anchorAt(defaultSpots, string.format("Spot%02d", i), s[1], s[2] + 0.5, s[3], TAG_DEFAULT_SPOT)
	end

	local decoys = make("Folder", "DecoyAnchors", data)
	anchorAt(decoys, "Decoy1", -22, 0.5, -22, TAG_DECOY_ANCHOR)
	anchorAt(decoys, "Decoy2", 22, 0.5, -22, TAG_DECOY_ANCHOR)
	anchorAt(decoys, "Decoy3", -22, 0.5, 22, TAG_DECOY_ANCHOR)
	anchorAt(decoys, "Decoy4", 22, 0.5, 22, TAG_DECOY_ANCHOR)

	local cardTable = make("Folder", "CardTable", data)
	local tableX, tableY, tableZ = 0, 3, -40
	anchorAt(cardTable, "TableAnchor", tableX, tableY, tableZ, nil)
	local seats = make("Folder", "Seats", cardTable)
	local radius = 6
	for i = 1, 9 do
		-- Clockwise seen from above (x east, z south): start at north and sweep toward east. Nine seats, 40 degrees apart.
		local a = math.rad((i - 1) * 40)
		local sx = tableX + radius * math.sin(a)
		local sz = tableZ - radius * math.cos(a)
		-- CFrame.lookAt orients the seat's look vector at the table anchor.
		local facing = rbx.CFrame.lookAt(vec3(sx, tableY, sz), vec3(tableX, tableY, tableZ))
		anchor(seats, `Seat{i}`, facing, nil)
	end
end

local function build(): Inst
	local root = make("Model", "GrayBox", nil)
	root:SetAttribute("ContractVersion", 2)
	root:SetAttribute("DisplayName", "Gray Box")
	root:SetAttribute("MinPlayers", 3)
	root:SetAttribute("MaxPlayers", 10)
	root:SetAttribute("SizeClass", "Medium")
	buildGeometry(make("Folder", "Geometry", root))
	buildData(make("Folder", "Data", root))
	return root
end

local contents = roblox.serializeModel({ build() })
fs.writeFile(OUTPUT_PATH, contents)
print(`generate-graybox: wrote {OUTPUT_PATH} ({#contents} bytes)`)
