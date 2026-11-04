--!strict
-- MapValidator unit suite. Shape: one valid baseline, then one mutation per case. Every rejection is asserted BY
-- CODE and the case fails if any OTHER code also appears, so a validator that rejected everything (or rejected for
-- the wrong reason) cannot pass. A final case proves every code in MapContract.ISSUE_CODES has a case here.
local MapContract = require("../../src/server/core/MapContract")
local MapValidator = require("../../src/server/core/MapValidator")
local PLACEMENT = require("../../src/shared/Config/Placement")
local Test = require("../harness/Test")

type Node = MapContract.Node

local function node(name: string, className: string, children: { Node }?): Node
	return { name = name, className = className, attributes = {}, tags = {}, children = children or {} }
end

local function part(name: string, x: number, y: number, z: number, tag: string?): Node
	local p = node(name, "Part")
	p.position = { x = x, y = y, z = z }
	p.size = { x = 1, y = 1, z = 1 }
	p.look = { x = 0, y = 0, z = -1 }
	p.up = { x = 0, y = 1, z = 0 }
	p.anchored = true
	p.canCollide = true
	p.shape = "Block"
	if tag ~= nil then
		p.tags = { tag }
	end
	return p
end

-- Nine seats at the given radius and bearings (degrees, clockwise from north) around the TableAnchor at
-- (0, 3, -40), each facing the anchor. Every seat case then states only what it varies.
local function seatRing(radius: number, bearings: { number }): { Node }
	local seats: { Node } = {}
	local anchorX, anchorY, anchorZ = 0, 3, -40
	for i, bearing in bearings do
		local a = math.rad(bearing)
		local sx = anchorX + radius * math.sin(a)
		local sz = anchorZ - radius * math.cos(a)
		local seat = part(`Seat{i}`, sx, anchorY, sz)
		local dx, dz = anchorX - sx, anchorZ - sz
		local d = math.sqrt(dx * dx + dz * dz)
		seat.look = { x = dx / d, y = 0, z = dz / d }
		table.insert(seats, seat)
	end
	return seats
end

-- The placement stage runs whenever the structural pass is clean, so the baseline has to be a world the
-- rules accept. A 1x1x1 floor with spots floating 11 studs up would make every case in this file report a
-- placement issue and the exact-set assertions would all fail for the wrong reason. Note that only the handful
-- of cases which PASS the structural pass pay the bake cost -- the roughly fifty rejection cases return early
-- at the seam (Pitfall 11), so this adds about five bakes to the suite, not fifty.
local function validSnapshot(): Node
	local spots: { Node } = {}
	for i = 1, 16 do
		table.insert(spots, part(`Spot{i}`, (i - 8) * 5, 0.5, 10, MapContract.TAG_DEFAULT_SPOT))
	end
	-- The baseline's seats were a straight line until D-20's winding rule landed, which is exactly the class of
	-- fixture that passes while asserting nothing about geometry. A real radius-6 ring at 40-degree spacing, the
	-- same construction generate-graybox.luau uses, is now the baseline because every seat case has to be surgical.
	local seats = seatRing(6, { 0, 40, 80, 120, 160, 200, 240, 280, 320 })
	local bounds = part("Bounds", 0, 14, 0)
	bounds.size = { x = 124, y = 30, z = 124 }
	local floor = part("Floor", 0, -0.5, 0)
	floor.size = { x = 124, y = 1, z = 124 }
	local root = node("TestMap", "Model", {
		node("Geometry", "Folder", { floor }),
		node("Data", "Folder", {
			bounds,
			part("HiderSpawn", 0, 3, 40),
			node("SeekerSpawns", "Folder", {
				part("S1", -40, 3, -40, MapContract.TAG_SEEKER_SPAWN),
				part("S2", 40, 3, -40, MapContract.TAG_SEEKER_SPAWN),
			}),
			node("DefaultSpots", "Folder", spots),
			node("DecoyAnchors", "Folder", { part("D1", 10, 3, 10, MapContract.TAG_DECOY_ANCHOR) }),
			node("CardTable", "Folder", {
				part("TableAnchor", 0, 3, -40),
				node("Seats", "Folder", seats),
			}),
		}),
	})
	root.attributes = {
		ContractVersion = 2,
		DisplayName = "Test Map",
		MinPlayers = 3,
		MaxPlayers = 10,
		SizeClass = "Medium",
	}
	return root
end

local function find(root: Node, path: string): Node
	local current = root
	for segment in string.gmatch(path, "[^/]+") do
		local nextNode: Node? = nil
		for _, child in current.children do
			if child.name == segment then
				nextNode = child
			end
		end
		assert(nextNode ~= nil, `test helper: no node at {path} (stopped at {segment})`)
		current = nextNode
	end
	return current
end

-- A collidable, anchored axis-aligned block, appended to Geometry by the placement fixtures below.
local function block(name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number): Node
	local b = part(name, x, y, z)
	b.size = { x = sx, y = sy, z = sz }
	return b
end

local function geometryOf(root: Node): Node
	return find(root, "Geometry")
end

-- Rotates a node's look vector about y by `degrees`.
local function rotateLook(n: Node, degrees: number)
	local look = n.look :: MapContract.Vec3
	local c, sn = math.cos(math.rad(degrees)), math.sin(math.rad(degrees))
	n.look = { x = look.x * c + look.z * sn, y = look.y, z = -look.x * sn + look.z * c }
end

local function removeChild(parent: Node, name: string)
	for i, child in parent.children do
		if child.name == name then
			table.remove(parent.children, i)
			return
		end
	end
	error(`test helper: {parent.name} has no child {name}`)
end

local function codesOf(issues: { MapContract.Issue }): { string }
	local seen: { [string]: boolean } = {}
	local list: { string } = {}
	for _, issue in issues do
		if not seen[issue.code] then
			seen[issue.code] = true
			table.insert(list, issue.code)
		end
	end
	table.sort(list)
	return list
end

type Case = {
	name: string,
	code: string,
	pathContains: string?,
	mutate: (root: Node) -> (),
}

local cases: { Case } = {
	{
		name = "missing Geometry folder",
		code = "MAP_MISSING_FOLDER",
		pathContains = "Geometry",
		mutate = function(r)
			removeChild(r, "Geometry")
		end,
	},
	{
		name = "missing Data folder",
		code = "MAP_MISSING_FOLDER",
		pathContains = "Data",
		mutate = function(r)
			removeChild(r, "Data")
		end,
	},
	{
		name = "missing DecoyAnchors folder is an error even though it may be empty",
		code = "MAP_MISSING_FOLDER",
		pathContains = "DecoyAnchors",
		mutate = function(r)
			removeChild(find(r, "Data"), "DecoyAnchors")
		end,
	},
	{
		name = "missing CardTable folder",
		code = "MAP_MISSING_FOLDER",
		pathContains = "CardTable",
		mutate = function(r)
			removeChild(find(r, "Data"), "CardTable")
		end,
	},
	{
		name = "ContractVersion absent",
		code = "MAP_META_INVALID",
		pathContains = "ContractVersion",
		mutate = function(r)
			local kept: { [string]: string | number | boolean } = {}
			for key, value in r.attributes do
				if key ~= "ContractVersion" then
					kept[key] = value
				end
			end
			r.attributes = kept
		end,
	},
	{
		name = "ContractVersion non-numeric",
		code = "MAP_META_INVALID",
		pathContains = "ContractVersion",
		mutate = function(r)
			r.attributes.ContractVersion = "1"
		end,
	},
	{
		name = "ContractVersion not 2",
		code = "MAP_META_INVALID",
		pathContains = "ContractVersion",
		mutate = function(r)
			r.attributes.ContractVersion = 3
		end,
	},
	{
		name = "ContractVersion 1 is rejected outright, not migrated",
		code = "MAP_META_INVALID",
		pathContains = "ContractVersion",
		mutate = function(r)
			r.attributes.ContractVersion = 1
		end,
	},
	{
		name = "a Part node with no up vector",
		code = "MAP_NODE_BASIS_INVALID",
		pathContains = "Floor",
		mutate = function(r)
			find(r, "Geometry/Floor").up = nil
		end,
	},
	{
		name = "a Part node with no canCollide",
		code = "MAP_NODE_BASIS_INVALID",
		pathContains = "Floor",
		mutate = function(r)
			find(r, "Geometry/Floor").canCollide = nil
		end,
	},
	{
		name = "a Part node with no shape",
		code = "MAP_NODE_BASIS_INVALID",
		pathContains = "Floor",
		mutate = function(r)
			find(r, "Geometry/Floor").shape = nil
		end,
	},
	{
		name = "shape set on a Folder",
		code = "MAP_NODE_BASIS_INVALID",
		pathContains = "Geometry",
		mutate = function(r)
			find(r, "Geometry").shape = "Block"
		end,
	},
	{
		name = "look and up not perpendicular",
		code = "MAP_NODE_BASIS_INVALID",
		pathContains = "Floor",
		mutate = function(r)
			find(r, "Geometry/Floor").up = { x = 0, y = 0, z = -1 }
		end,
	},
	{
		-- The ONLY fixture for the up half of the Bounds rotation check. look is unchanged, so under contract
		-- version 1 this map validated clean. Note the rotation does not change the axis-aligned min/max the bounds
		-- volume is computed from, so no MAP_OUT_OF_BOUNDS cascades.
		name = "Bounds rolled about the look axis",
		code = "MAP_BOUNDS_INVALID",
		pathContains = "Bounds",
		mutate = function(r)
			find(r, "Data/Bounds").up = { x = 0.7071067811865476, y = 0.7071067811865476, z = 0 }
		end,
	},
	{
		name = "empty DisplayName",
		code = "MAP_META_INVALID",
		pathContains = "DisplayName",
		mutate = function(r)
			r.attributes.DisplayName = ""
		end,
	},
	{
		name = "over-long DisplayName",
		code = "MAP_META_INVALID",
		pathContains = "DisplayName",
		mutate = function(r)
			r.attributes.DisplayName = string.rep("x", MapContract.MAX_DISPLAY_NAME + 1)
		end,
	},
	{
		name = "MinPlayers 2 is below the 3-player floor",
		code = "MAP_META_INVALID",
		pathContains = "MinPlayers",
		mutate = function(r)
			r.attributes.MinPlayers = 2
		end,
	},
	{
		name = "MaxPlayers 11 is above the 10-player cap",
		code = "MAP_META_INVALID",
		pathContains = "MaxPlayers",
		mutate = function(r)
			r.attributes.MaxPlayers = 11
		end,
	},
	{
		name = "MinPlayers greater than MaxPlayers",
		code = "MAP_META_INVALID",
		pathContains = "MinPlayers",
		mutate = function(r)
			r.attributes.MinPlayers = 8
			r.attributes.MaxPlayers = 5
		end,
	},
	{
		name = "non-integer MinPlayers",
		code = "MAP_META_INVALID",
		pathContains = "MinPlayers",
		mutate = function(r)
			r.attributes.MinPlayers = 3.5
		end,
	},
	{
		name = "SizeClass outside the enum",
		code = "MAP_META_INVALID",
		pathContains = "SizeClass",
		mutate = function(r)
			r.attributes.SizeClass = "Huge"
		end,
	},
	{
		name = "15 tagged default spots",
		code = "MAP_SPOT_COUNT",
		pathContains = "DefaultSpots",
		mutate = function(r)
			removeChild(find(r, "Data/DefaultSpots"), "Spot16")
		end,
	},
	{
		name = "a default spot that lost its tag does not count",
		code = "MAP_SPOT_COUNT",
		pathContains = "DefaultSpots",
		mutate = function(r)
			find(r, "Data/DefaultSpots/Spot1").tags = {}
		end,
	},
	{
		name = "tagged default spot outside the DefaultSpots folder",
		code = "MAP_TAG_OUTSIDE_FOLDER",
		pathContains = "Stray",
		mutate = function(r)
			table.insert(find(r, "Geometry").children, part("Stray", 0, 3, 0, MapContract.TAG_DEFAULT_SPOT))
		end,
	},
	{
		name = "tagged default spot nested one level too deep",
		code = "MAP_TAG_OUTSIDE_FOLDER",
		pathContains = "Deep",
		mutate = function(r)
			local nested = node("Nested", "Folder", { part("Deep", 0, 3, 0, MapContract.TAG_DEFAULT_SPOT) })
			table.insert(find(r, "Data/DefaultSpots").children, nested)
		end,
	},
	{
		name = "zero seeker spawns",
		code = "MAP_SPAWN_COUNT",
		pathContains = "SeekerSpawns",
		mutate = function(r)
			find(r, "Data/SeekerSpawns").children = {}
		end,
	},
	{
		name = "missing HiderSpawn",
		code = "MAP_MISSING_PART",
		pathContains = "HiderSpawn",
		mutate = function(r)
			removeChild(find(r, "Data"), "HiderSpawn")
		end,
	},
	{
		name = "missing TableAnchor",
		code = "MAP_MISSING_PART",
		pathContains = "TableAnchor",
		mutate = function(r)
			removeChild(find(r, "Data/CardTable"), "TableAnchor")
		end,
	},
	{
		name = "8 seats",
		code = "MAP_SEAT_COUNT",
		pathContains = "Seats",
		mutate = function(r)
			removeChild(find(r, "Data/CardTable/Seats"), "Seat9")
		end,
	},
	{
		name = "10 seats",
		code = "MAP_SEAT_COUNT",
		pathContains = "Seats",
		mutate = function(r)
			table.insert(find(r, "Data/CardTable/Seats").children, part("Seat10", 0, 3, -40))
		end,
	},
	{
		name = "seats wound anticlockwise",
		code = "MAP_SEAT_ORDER",
		pathContains = "Seat",
		mutate = function(r)
			find(r, "Data/CardTable").children[2].children = seatRing(6, { 0, 320, 280, 240, 200, 160, 120, 80, 40 })
		end,
	},
	{
		name = "two adjacent seats swapped",
		code = "MAP_SEAT_ORDER",
		pathContains = "Seat5",
		mutate = function(r)
			local a, b = find(r, "Data/CardTable/Seats/Seat4"), find(r, "Data/CardTable/Seats/Seat5")
			a.position, b.position = b.position, a.position
			a.look, b.look = b.look, a.look
		end,
	},
	{
		name = "a seat facing away from the table",
		code = "MAP_SEAT_FACING",
		pathContains = "Seat3",
		mutate = function(r)
			local look = find(r, "Data/CardTable/Seats/Seat3").look :: MapContract.Vec3
			find(r, "Data/CardTable/Seats/Seat3").look = { x = -look.x, y = -look.y, z = -look.z }
		end,
	},
	{
		name = "a seat 8 degrees off the anchor",
		code = "MAP_SEAT_FACING",
		pathContains = "Seat7",
		mutate = function(r)
			rotateLook(find(r, "Data/CardTable/Seats/Seat7"), 8)
		end,
	},
	{
		name = "a seat on the table anchor",
		code = "MAP_SEAT_ORDER",
		pathContains = "Seat2",
		mutate = function(r)
			find(r, "Data/CardTable/Seats/Seat2").position = { x = 0, y = 3, z = -40 }
		end,
	},
	{
		-- Every step is 80 degrees, inside (0, 180), but 9 * 80 = 720: the ring winds twice. Only the
		-- sum-to-360 condition catches this, which is why it is not belt-and-braces.
		name = "seats wound twice round",
		code = "MAP_SEAT_ORDER",
		pathContains = "Seat",
		mutate = function(r)
			find(r, "Data/CardTable").children[2].children = seatRing(6, { 0, 80, 160, 240, 320, 40, 120, 200, 280 })
		end,
	},
	{
		name = "nine seats but one is named Chair9",
		code = "MAP_SEAT_NAME",
		pathContains = "Chair9",
		mutate = function(r)
			find(r, "Data/CardTable/Seats/Seat9").name = "Chair9"
		end,
	},
	{
		name = "nine seats but a name is duplicated",
		code = "MAP_SEAT_NAME",
		pathContains = "Seat1",
		mutate = function(r)
			find(r, "Data/CardTable/Seats/Seat9").name = "Seat1"
		end,
	},
	{
		name = "missing Bounds part",
		code = "MAP_BOUNDS_INVALID",
		pathContains = "Bounds",
		mutate = function(r)
			removeChild(find(r, "Data"), "Bounds")
		end,
	},
	{
		name = "Bounds with a zero size component",
		code = "MAP_BOUNDS_INVALID",
		pathContains = "Bounds",
		mutate = function(r)
			find(r, "Data/Bounds").size = { x = 124, y = 0, z = 124 }
		end,
	},
	{
		name = "Bounds with a negative size component",
		code = "MAP_BOUNDS_INVALID",
		pathContains = "Bounds",
		mutate = function(r)
			find(r, "Data/Bounds").size = { x = -124, y = 30, z = 124 }
		end,
	},
	{
		name = "Bounds that is rotated is not axis-aligned",
		code = "MAP_BOUNDS_INVALID",
		pathContains = "Bounds",
		mutate = function(r)
			find(r, "Data/Bounds").look = { x = 1, y = 0, z = 0 }
		end,
	},
	{
		name = "Script anywhere in the tree",
		code = "MAP_SCRIPT_FORBIDDEN",
		pathContains = "Evil",
		mutate = function(r)
			table.insert(find(r, "Geometry").children, node("Evil", "Script"))
		end,
	},
	{
		name = "LocalScript anywhere in the tree",
		code = "MAP_SCRIPT_FORBIDDEN",
		pathContains = "Evil",
		mutate = function(r)
			table.insert(find(r, "Geometry").children, node("Evil", "LocalScript"))
		end,
	},
	{
		name = "ModuleScript buried deep in Data",
		code = "MAP_SCRIPT_FORBIDDEN",
		pathContains = "Evil",
		mutate = function(r)
			table.insert(find(r, "Data/CardTable/Seats/Seat3").children, node("Evil", "ModuleScript"))
		end,
	},
	{
		name = "default spot outside Bounds",
		code = "MAP_OUT_OF_BOUNDS",
		pathContains = "Spot2",
		mutate = function(r)
			find(r, "Data/DefaultSpots/Spot2").position = { x = 500, y = 3, z = 0 }
		end,
	},
	{
		name = "seat outside Bounds",
		code = "MAP_OUT_OF_BOUNDS",
		pathContains = "Seat4",
		mutate = function(r)
			-- Slide Seat4 outward along its own bearing (120 degrees) so winding and facing stay valid and only
			-- the bounds rule fires. At radius 100 it is at x = 86.6, outside the +-62 Bounds.
			local seat = find(r, "Data/CardTable/Seats/Seat4")
			local a = math.rad(120)
			seat.position = { x = 100 * math.sin(a), y = 3, z = -40 - 100 * math.cos(a) }
		end,
	},
	{
		name = "hider spawn above Bounds",
		code = "MAP_OUT_OF_BOUNDS",
		pathContains = "HiderSpawn",
		mutate = function(r)
			find(r, "Data/HiderSpawn").position = { x = 0, y = 500, z = 0 }
		end,
	},
	{
		-- Floor top is y = 0 and the slab spans y in [-1, 0]; -0.5 is inside it.
		name = "a spot inside the floor slab",
		code = "MAP_SPOT_SOLID",
		pathContains = "Spot1",
		mutate = function(r)
			find(r, "Data/DefaultSpots/Spot1").position = { x = -35, y = -0.5, z = 10 }
		end,
	},
	{
		-- y = 20, not 30: Bounds spans y in [-1, 29], so 30 would report MAP_OUT_OF_BOUNDS instead. The nearest
		-- standable root point is at y = 2.5, so 17.5 away against PICKUP_RANGE 7.0 (10.5 studs of slack).
		name = "a spot 20 studs above the floor",
		code = "MAP_SPOT_NO_FOOTING",
		pathContains = "Spot1",
		mutate = function(r)
			find(r, "Data/DefaultSpots/Spot1").position = { x = -35, y = 20, z = 10 }
		end,
	},
	{
		-- The floor is NOT shrunk (that would strand other spots and both spawns). At (-35, 8.75, 10) the
		-- nearest column centre is 0.707 away horizontally and its root point is at y = 2.5, so the 3D distance
		-- is sqrt(0.5 + 6.25^2) = 6.29: inside PICKUP_RANGE 7.0 by 0.71, outside E = 5.5 by 0.79.
		name = "a spot 8.75 studs above the floor, past E but inside PICKUP_RANGE",
		code = "MAP_SPOT_OUT_OF_REACH",
		pathContains = "Spot1",
		mutate = function(r)
			find(r, "Data/DefaultSpots/Spot1").position = { x = -35, y = 8.75, z = 10 }
		end,
	},
	{
		-- A 10-stud cavity (x, z in [35, 45]) under a roof whose underside is at y = 12, i.e. 12 studs of
		-- headroom against CAPSULE_HEIGHT 7. A tighter box would report NoFooting (no cell survives erosion)
		-- instead of Unreachable. The 12-high walls exceed STEP_UP so the cavity is never connected.
		name = "a spot inside a sealed box",
		code = "MAP_SPOT_UNREACHABLE",
		pathContains = "Spot1",
		mutate = function(r)
			local geometry = geometryOf(r)
			table.insert(geometry.children, block("CellNorth", 40, 6, 34, 14, 12, 2))
			table.insert(geometry.children, block("CellSouth", 40, 6, 46, 14, 12, 2))
			table.insert(geometry.children, block("CellWest", 34, 6, 40, 2, 12, 14))
			table.insert(geometry.children, block("CellEast", 46, 6, 40, 2, 12, 14))
			table.insert(geometry.children, block("CellRoof", 40, 13, 40, 14, 2, 14))
			find(r, "Data/DefaultSpots/Spot1").position = { x = 40, y = 0.5, z = 40 }
		end,
	},
	{
		-- A 6 x 6 slab, underside y = 1.5, half-width w = 3 about the spot. w must satisfy w + 1.5 < 5.123 so a
		-- ring of surviving cells (dh in [4.5, 5.123]) remains in reach, and the underside must satisfy
		-- 0.5 + 10.5 / 5.123 >= 1.5 so every eye point in that ring is blocked.
		name = "a spot tucked under an overhang",
		code = "MAP_SPOT_NO_SIGHT",
		pathContains = "Spot1",
		mutate = function(r)
			table.insert(geometryOf(r).children, block("Overhang", -35, 2.5, 10, 6, 2, 6))
		end,
	},
	{
		-- A bake fault returns a NIL world, so the placement stage emits no spot issue at all: that is why this
		-- fixture is surgical without moving any spot. y = 20 is 20 below nothing: the floor is 20 under the
		-- spawn and SPAWN_DROP_LIMIT is 8.
		name = "a seeker spawn with no footing",
		code = "MAP_SPAWN_NO_FOOTING",
		pathContains = "S1",
		mutate = function(r)
			find(r, "Data/SeekerSpawns/S1").position = { x = 0, y = 20, z = 0 }
		end,
	},
	{
		-- A bake fault returns a NIL world, so no spot issue can be emitted. Two 50-wide slabs with a 20-stud
		-- gap cannot be linked by STEP_UP 1.0 at any grid resolution.
		name = "two spawns on disconnected slabs",
		code = "MAP_SPAWN_DISCONNECTED",
		pathContains = "SeekerSpawns",
		mutate = function(r)
			local geometry = geometryOf(r)
			geometry.children = {
				block("SlabA", -35, -0.5, 0, 50, 1, 124),
				block("SlabB", 35, -0.5, 0, 50, 1, 124),
			}
		end,
	},
	{
		-- A bake fault returns a NIL world, so no spot issue can be emitted. Every spot and spawn is still inside
		-- the enlarged bounds, so no MAP_OUT_OF_BOUNDS appears. 4000 * 4000 = 16,000,000 columns against the
		-- 250,000 ceiling, and the bake refuses before allocating, which is why this is fast.
		name = "a Bounds larger than the bake ceiling",
		code = "MAP_BOUNDS_TOO_LARGE",
		pathContains = "Bounds",
		mutate = function(r)
			find(r, "Data/Bounds").size = { x = 4000, y = 30, z = 4000 }
		end,
	},
	{
		name = "root that is not a Model",
		code = "MAP_ROOT_INVALID",
		mutate = function(r)
			r.className = "Folder"
		end,
	},
}

return function(t: Test.Runner)
	t.test("a valid snapshot returns zero issues and a typed MapSpec", function()
		local issues, spec = MapValidator.validate(validSnapshot(), PLACEMENT)
		t.deepEqual(issues, {})
		assert(spec ~= nil, "valid snapshot must yield a MapSpec")
		t.equal(#spec.defaultSpots, 16)
		t.equal(#spec.cardTable.seats, 9)
		t.equal(#spec.seekerSpawns, 2)
		t.equal(#spec.decoyAnchors, 1)
		t.equal(spec.metadata.id, "TestMap")
		t.equal(spec.metadata.displayName, "Test Map")
		t.equal(spec.metadata.minPlayers, 3)
		t.equal(spec.metadata.maxPlayers, 10)
		t.equal(spec.metadata.sizeClass, "Medium")
		t.deepEqual(spec.bounds.min, { x = -62, y = -1, z = -62 })
		t.deepEqual(spec.bounds.max, { x = 62, y = 29, z = 62 })
	end)

	t.test("seats are indexed by seat number, not by child order", function()
		local root = validSnapshot()
		local seats = find(root, "Data/CardTable/Seats")
		-- Reverse the child order: Seat9 first. The seat table must still be indexed by the number in the name.
		local reversed: { Node } = {}
		for i = #seats.children, 1, -1 do
			table.insert(reversed, seats.children[i])
		end
		seats.children = reversed
		local issues, spec = MapValidator.validate(root, PLACEMENT)
		t.deepEqual(issues, {})
		assert(spec ~= nil, "expected a MapSpec")
		-- Seat 1 is due north of the anchor; seat 9 is at bearing 320 degrees (sin = -0.6428, cos = 0.7660).
		t.deepEqual(spec.cardTable.seats[1].position, { x = 0, y = 3, z = -46 })
		t.truthy(math.abs(spec.cardTable.seats[9].position.x - 6 * math.sin(math.rad(320))) < 1e-9)
		t.truthy(math.abs(spec.cardTable.seats[9].position.z - (-40 - 6 * math.cos(math.rad(320)))) < 1e-9)
	end)

	t.test("a valid ring at a different radius with uneven clockwise spacing passes", function()
		-- Every step is inside (0, 180) and they sum to 360: the rule checks winding, not the graybox's geometry.
		local root = validSnapshot()
		find(root, "Data/CardTable").children[2].children = seatRing(11, { 0, 25, 70, 110, 150, 200, 250, 300, 335 })
		local issues, spec = MapValidator.validate(root, PLACEMENT)
		t.deepEqual(issues, {})
		t.truthy(spec ~= nil)
	end)

	t.test("a seat 3 degrees off the anchor is within tolerance", function()
		-- 5 degrees is deliberate slack for hand authoring in Studio; a generated seat passes exactly.
		local root = validSnapshot()
		rotateLook(find(root, "Data/CardTable/Seats/Seat7"), 3)
		local issues, spec = MapValidator.validate(root, PLACEMENT)
		t.deepEqual(issues, {})
		t.truthy(spec ~= nil)
	end)

	t.test("a map missing a seat reports MAP_SEAT_COUNT and not MAP_SEAT_ORDER", function()
		local root = validSnapshot()
		removeChild(find(root, "Data/CardTable/Seats"), "Seat9")
		local issues = MapValidator.validate(root, PLACEMENT)
		t.deepEqual(codesOf(issues), { "MAP_SEAT_COUNT" })
	end)

	t.test("exactly 16 tagged spots passes (the boundary is inclusive)", function()
		local issues, spec = MapValidator.validate(validSnapshot(), PLACEMENT)
		t.equal(#issues, 0)
		t.truthy(spec ~= nil)
	end)

	t.test("a DecoyAnchors folder that is empty is valid", function()
		local root = validSnapshot()
		find(root, "Data/DecoyAnchors").children = {}
		local issues, spec = MapValidator.validate(root, PLACEMENT)
		t.deepEqual(issues, {})
		assert(spec ~= nil, "expected a MapSpec")
		t.equal(#spec.decoyAnchors, 0)
	end)

	for _, case in cases do
		t.test(`rejects: {case.name} -> {case.code}`, function()
			local root = validSnapshot()
			case.mutate(root)
			local issues, spec = MapValidator.validate(root, PLACEMENT)
			t.truthy(#issues > 0, "expected at least one issue")
			-- Assert the REASON: the only code present is the expected one. A validator that rejected the
			-- baseline for some other reason, or rejected everything, fails here.
			t.deepEqual(codesOf(issues), { case.code })
			t.equal(spec, nil, "a rejected map must not produce a MapSpec")
			local needle = case.pathContains
			if needle ~= nil then
				local found = false
				for _, issue in issues do
					if string.find(issue.path, needle, 1, true) ~= nil then
						found = true
					end
				end
				t.truthy(found, `no issue path contains {needle}`)
			end
		end)
	end

	t.test("validate with no config fails loudly rather than reporting a clean map", function()
		-- A caller that forgot the argument must fail loudly. A validator that silently ran with no
		-- config would report a clean map it never actually checked, which is the worst failure mode
		-- this file has. The call is on its own line on purpose: see the plan's note on the
		-- validate-call sweep. (Do NOT spell the call out in this comment -- the sweep counts lines
		-- holding the call text without a config, so naming it here would make the sweep return 2.)
		t.throws(function()
			MapValidator.validate(validSnapshot(), nil :: any)
		end, "PlacementConfig")
	end)

	t.test("every issue code in the contract is asserted by at least one case", function()
		local covered: { [string]: boolean } = {}
		for _, case in cases do
			covered[case.code] = true
		end
		for _, code in MapContract.ISSUE_CODES do
			t.truthy(covered[code] == true, `no case asserts {code}`)
		end
		-- And the contract lists no code the cases do not know about, i.e. the lists are the same size.
		local coveredCount = 0
		for _ in covered do
			coveredCount += 1
		end
		t.equal(coveredCount, #MapContract.ISSUE_CODES)
		t.equal(#MapContract.ISSUE_CODES, 23)
	end)

	t.test("issues are sorted by code then path and identical across runs", function()
		local function broken(): Node
			local root = validSnapshot()
			removeChild(find(root, "Data"), "HiderSpawn")
			removeChild(find(root, "Data/CardTable"), "TableAnchor")
			root.attributes.SizeClass = "Huge"
			table.insert(find(root, "Geometry").children, node("Evil", "Script"))
			return root
		end
		local first = MapValidator.validate(broken(), PLACEMENT)
		local second = MapValidator.validate(broken(), PLACEMENT)
		t.deepEqual(first, second)
		t.deepEqual(codesOf(first), { "MAP_META_INVALID", "MAP_MISSING_PART", "MAP_SCRIPT_FORBIDDEN" })
		for i = 2, #first do
			local a, b = first[i - 1], first[i]
			t.truthy(a.code < b.code or (a.code == b.code and a.path <= b.path), "issues out of order")
		end
	end)

	t.test("multiple independent faults are all reported, each under its own code", function()
		local root = validSnapshot()
		root.attributes.SizeClass = "Huge"
		removeChild(find(root, "Data/CardTable/Seats"), "Seat9")
		find(root, "Data/SeekerSpawns").children = {}
		local issues, spec = MapValidator.validate(root, PLACEMENT)
		t.deepEqual(codesOf(issues), { "MAP_META_INVALID", "MAP_SEAT_COUNT", "MAP_SPAWN_COUNT" })
		t.equal(spec, nil)
	end)
end
