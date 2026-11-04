--!strict
-- MAP-01 structural validator. PURE ZONE: plain data in, plain data out, no Roblox API.
--
-- validate(root) returns (issues, spec). `spec` is non-nil ONLY when `issues` is empty. Issues are sorted by
-- (code, path, message) so output is deterministic. Tests assert the CODE, never the prose.
--
-- validate(root, placement) runs two stages. The structural pass (MAP-01) checks shape. The placement stage
-- (MAP-02, D-17 STRICT) runs only when the structural pass is clean and sends every authored default spot through
-- the same SpoonPlacement bake and check the hider will use, so walkable footing, the per-spot rules,
-- reachability from the seeker spawns and sightlines are all covered by real geometry, one issue per failing spot.
-- The placement numbers arrive as a parameter: this pure zone may not require across the Rojo mount boundary (R6).
--
-- STILL DEFERRED (D-12), after this plan:
--   * seat winding (seats 1..9 clockwise) and each seat's look vector pointing at the TableAnchor -- plan 03-09
--     closes this inside Phase 3; if it is ever descoped, re-home it here rather than dropping it.
--   * CLOSED, not deferred: the Bounds roll item. Node v2 carries an up vector, so a roll about the look axis is
--     visible and rejected as MAP_BOUNDS_INVALID.
local MapContract = require("./MapContract")
local SpoonPlacement = require("./SpoonPlacement")

type Node = MapContract.Node
type Issue = MapContract.Issue
type MapSpec = MapContract.MapSpec
type Pose = MapContract.Pose
type PlacementConfig = SpoonPlacement.PlacementConfig
type Vec3 = MapContract.Vec3
type Aabb = MapContract.Aabb
type SizeClass = MapContract.SizeClass

local BOUNDS_INVALID = "MAP_BOUNDS_INVALID"
local BOUNDS_TOO_LARGE = "MAP_BOUNDS_TOO_LARGE"
local META_INVALID = "MAP_META_INVALID"
local MISSING_FOLDER = "MAP_MISSING_FOLDER"
local MISSING_PART = "MAP_MISSING_PART"
local NODE_BASIS_INVALID = "MAP_NODE_BASIS_INVALID"
local OUT_OF_BOUNDS = "MAP_OUT_OF_BOUNDS"
local ROOT_INVALID = "MAP_ROOT_INVALID"
local SCRIPT_FORBIDDEN = "MAP_SCRIPT_FORBIDDEN"
local SEAT_COUNT = "MAP_SEAT_COUNT"
local SEAT_NAME = "MAP_SEAT_NAME"
local SPAWN_COUNT = "MAP_SPAWN_COUNT"
local SPAWN_DISCONNECTED = "MAP_SPAWN_DISCONNECTED"
local SPAWN_NO_FOOTING = "MAP_SPAWN_NO_FOOTING"
local SPOT_COUNT = "MAP_SPOT_COUNT"
local SPOT_NO_FOOTING = "MAP_SPOT_NO_FOOTING"
local SPOT_NO_SIGHT = "MAP_SPOT_NO_SIGHT"
local SPOT_OUT_OF_REACH = "MAP_SPOT_OUT_OF_REACH"
local SPOT_SOLID = "MAP_SPOT_SOLID"
local SPOT_UNREACHABLE = "MAP_SPOT_UNREACHABLE"
local TAG_OUTSIDE_FOLDER = "MAP_TAG_OUTSIDE_FOLDER"

local CODE_CLASSES: { [string]: boolean } = { Script = true, LocalScript = true, ModuleScript = true }
local DEFAULT_LOOK: Vec3 = { x = 0, y = 0, z = -1 }
local DEFAULT_UP: Vec3 = { x = 0, y = 1, z = 0 }
local LOOK_EPSILON = 1e-3

local function hasTag(node: Node, tag: string): boolean
	return table.find(node.tags, tag) ~= nil
end

local function childNamed(node: Node, name: string): Node?
	for _, child in node.children do
		if child.name == name then
			return child
		end
	end
	return nil
end

local function isPart(node: Node): boolean
	return node.className == "Part" and node.position ~= nil
end

local function poseOf(node: Node): Pose
	local position = node.position or { x = 0, y = 0, z = 0 }
	return { position = position, look = node.look or DEFAULT_LOOK }
end

local function isInteger(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value == math.floor(value)
end

local function inside(box: Aabb, p: Vec3): boolean
	return p.x >= box.min.x
		and p.x <= box.max.x
		and p.y >= box.min.y
		and p.y <= box.max.y
		and p.z >= box.min.z
		and p.z <= box.max.z
end

local function lengthOf(v: Vec3): number
	return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function dotOf(a: Vec3, b: Vec3): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

-- SpoonPlacement.Reason -> stable issue code. The ORDER of the reasons is LOCKED and recorded in
-- THREE places: SpoonPlacement.luau's `Reason` type union, the comment there, and this table plus
-- tests/placement/corpus.spec.luau. Never reorder it to make an assertion pass.
--
--   1 OutOfBounds   in-bounds        -> MAP_OUT_OF_BOUNDS (the structural pass fires first, so this
--                                      row never triggers inside validate; it exists so the mapping
--                                      is TOTAL and a future caller cannot hit a nil code. The
--                                      reason itself is live for the Phase 6 hider check, where the
--                                      point comes from a client.)
--   2 Solid         standable (a)    -> MAP_SPOT_SOLID
--   3 NoFooting     standable (b)    -> MAP_SPOT_NO_FOOTING
--   4 OutOfReach    reach (a)        -> MAP_SPOT_OUT_OF_REACH
--   5 Unreachable   reach (b)        -> MAP_SPOT_UNREACHABLE
--   6 NoSight       line-of-sight    -> MAP_SPOT_NO_SIGHT
--
-- A spot inside the solid Core must report Solid, NOT a downstream sightline failure. Reporting a
-- fundamental failure as a downstream symptom is the most expensive way to be wrong, which is the
-- same reasoning that put `circulation` before `unsatisfiable` in Invariants.check.
local CODE_OF_REASON: { [string]: string } = {
	OutOfBounds = OUT_OF_BOUNDS,
	Solid = SPOT_SOLID,
	NoFooting = SPOT_NO_FOOTING,
	OutOfReach = SPOT_OUT_OF_REACH,
	Unreachable = SPOT_UNREACHABLE,
	NoSight = SPOT_NO_SIGHT,
}

local function validate(root: Node, placement: PlacementConfig): ({ Issue }, MapSpec?)
	-- Loud on purpose (D-13, the SeatOrder precedent). A nil config here would mean a map validated against NOTHING and reported clean, which is the single worst failure mode this validator has.
	SpoonPlacement.assertConfig(placement)
	local issues: { Issue } = {}
	local function report(code: string, path: string, message: string)
		table.insert(issues, { code = code, path = path, message = message })
	end

	local rootPath = root.name
	if root.className ~= "Model" then
		report(ROOT_INVALID, rootPath, `the map root must be a Model, found {root.className}`)
		return issues, nil
	end

	-- Whole-tree walk: forbidden code classes anywhere (a free model could smuggle behaviour in, T-1-06), and
	-- the default-spot tag anywhere outside Data/DefaultSpots (tags are authoritative, folders are organisation).
	local defaultSpotsPath = `{rootPath}/Data/DefaultSpots`
	local function walk(node: Node, path: string, parentPath: string)
		if CODE_CLASSES[node.className] then
			report(SCRIPT_FORBIDDEN, path, `{node.className} is not allowed anywhere in a map`)
		end
		-- Contract version 2 field check: at most one issue per node, first failing condition wins.
		local look, up = node.look, node.up
		if node.position ~= nil and node.size ~= nil and look ~= nil then
			if up == nil then
				report(
					NODE_BASIS_INVALID,
					path,
					`a BasePart node must carry an up vector (contract version {MapContract.CONTRACT_VERSION})`
				)
			elseif node.canCollide == nil then
				report(
					NODE_BASIS_INVALID,
					path,
					`a BasePart node must carry canCollide (contract version {MapContract.CONTRACT_VERSION})`
				)
			elseif node.className == "Part" and node.shape == nil then
				report(
					NODE_BASIS_INVALID,
					path,
					`a Part node must carry shape (contract version {MapContract.CONTRACT_VERSION})`
				)
			elseif node.className ~= "Part" and node.shape ~= nil then
				report(NODE_BASIS_INVALID, path, `shape is a Part property and must be absent on a {node.className}`)
			elseif
				math.abs(lengthOf(look) - 1) > LOOK_EPSILON
				or math.abs(lengthOf(up) - 1) > LOOK_EPSILON
				or math.abs(dotOf(look, up)) > LOOK_EPSILON
			then
				report(
					NODE_BASIS_INVALID,
					path,
					`look and up must be unit length and perpendicular within {LOOK_EPSILON}`
				)
			end
		elseif node.shape ~= nil then
			report(NODE_BASIS_INVALID, path, `shape is a Part property and must be absent on a {node.className}`)
		end
		if hasTag(node, MapContract.TAG_DEFAULT_SPOT) then
			if parentPath ~= defaultSpotsPath then
				report(
					TAG_OUTSIDE_FOLDER,
					path,
					`tagged {MapContract.TAG_DEFAULT_SPOT} but not directly inside {defaultSpotsPath}`
				)
			end
		end
		for _, child in node.children do
			walk(child, `{path}/{child.name}`, path)
		end
	end
	walk(root, rootPath, "")

	-- Metadata: attributes on the root, so the .rbxm carries no code.
	local attrs = root.attributes
	local contractVersion = attrs.ContractVersion
	if contractVersion ~= MapContract.CONTRACT_VERSION then
		report(
			META_INVALID,
			`{rootPath}#ContractVersion`,
			`ContractVersion must be the number {MapContract.CONTRACT_VERSION}`
		)
	end
	local displayName = attrs.DisplayName
	if type(displayName) ~= "string" or #displayName == 0 or #displayName > MapContract.MAX_DISPLAY_NAME then
		report(
			META_INVALID,
			`{rootPath}#DisplayName`,
			`DisplayName must be a string of 1 to {MapContract.MAX_DISPLAY_NAME} characters`
		)
	end
	local minPlayers = attrs.MinPlayers
	local maxPlayers = attrs.MaxPlayers
	local minOk = isInteger(minPlayers)
		and (minPlayers :: number) >= MapContract.MIN_PLAYERS_FLOOR
		and (minPlayers :: number) <= MapContract.MAX_PLAYERS_CEILING
	local maxOk = isInteger(maxPlayers)
		and (maxPlayers :: number) >= MapContract.MIN_PLAYERS_FLOOR
		and (maxPlayers :: number) <= MapContract.MAX_PLAYERS_CEILING
	if not minOk then
		report(
			META_INVALID,
			`{rootPath}#MinPlayers`,
			`MinPlayers must be an integer from {MapContract.MIN_PLAYERS_FLOOR} to {MapContract.MAX_PLAYERS_CEILING}`
		)
	end
	if not maxOk then
		report(
			META_INVALID,
			`{rootPath}#MaxPlayers`,
			`MaxPlayers must be an integer from {MapContract.MIN_PLAYERS_FLOOR} to {MapContract.MAX_PLAYERS_CEILING}`
		)
	end
	if minOk and maxOk and (minPlayers :: number) > (maxPlayers :: number) then
		report(META_INVALID, `{rootPath}#MinPlayers`, "MinPlayers must not exceed MaxPlayers")
	end
	local sizeClass = attrs.SizeClass
	if sizeClass ~= "Small" and sizeClass ~= "Medium" and sizeClass ~= "Large" then
		report(META_INVALID, `{rootPath}#SizeClass`, "SizeClass must be Small, Medium or Large")
	end

	-- Top-level folders.
	local function requireFolder(parent: Node, parentPath: string, name: string): (Node?, string)
		local path = `{parentPath}/{name}`
		local found = childNamed(parent, name)
		if found == nil or found.className ~= "Folder" then
			report(MISSING_FOLDER, path, `required Folder {name} is missing`)
			return nil, path
		end
		return found, path
	end
	local function requirePart(parent: Node, parentPath: string, name: string): (Node?, string)
		local path = `{parentPath}/{name}`
		local found = childNamed(parent, name)
		if found == nil or not isPart(found) then
			report(MISSING_PART, path, `required Part {name} is missing`)
			return nil, path
		end
		return found, path
	end

	requireFolder(root, rootPath, "Geometry")
	local data, dataPath = requireFolder(root, rootPath, "Data")

	local boundsBox: Aabb? = nil
	local hiderSpawn: Node? = nil
	local tableAnchor: Node? = nil
	local seekerSpawns: { Node } = {}
	local seekerPaths: { string } = {} -- parallel to seekerSpawns, so a SpawnNoFooting fault can name its spawn
	local defaultSpots: { Node } = {}
	local defaultSpotPaths: { string } = {} -- parallel to defaultSpots
	local decoyAnchors: { Node } = {}
	local seats: { [number]: Node } = {}
	-- Every anchor that must lie inside Bounds, with its path.
	local anchors: { { node: Node, path: string } } = {}

	if data ~= nil then
		-- Bounds: one axis-aligned box centred on its position (D-19).
		local boundsPath = `{dataPath}/Bounds`
		local bounds = childNamed(data, "Bounds")
		if bounds == nil or not isPart(bounds) or bounds.size == nil then
			report(BOUNDS_INVALID, boundsPath, "Bounds must be a Part with a size")
		else
			local size = bounds.size :: Vec3
			local centre = bounds.position :: Vec3
			local look = bounds.look
			local up = bounds.up
			if size.x <= 0 or size.y <= 0 or size.z <= 0 then
				report(BOUNDS_INVALID, boundsPath, "Bounds size must be positive on all three axes")
			elseif
				look ~= nil
					and (math.abs(look.x - DEFAULT_LOOK.x) > LOOK_EPSILON or math.abs(look.y - DEFAULT_LOOK.y) > LOOK_EPSILON or math.abs(
						look.z - DEFAULT_LOOK.z
					) > LOOK_EPSILON)
				-- v2: a roll about the look axis is now visible, so an axis-aligned Bounds (D-19) is actually checkable.
				or up ~= nil
					and (math.abs(up.x - DEFAULT_UP.x) > LOOK_EPSILON or math.abs(up.y - DEFAULT_UP.y) > LOOK_EPSILON or math.abs(
						up.z - DEFAULT_UP.z
					) > LOOK_EPSILON)
			then
				report(BOUNDS_INVALID, boundsPath, "Bounds must be axis-aligned (identity rotation)")
			else
				boundsBox = {
					min = { x = centre.x - size.x / 2, y = centre.y - size.y / 2, z = centre.z - size.z / 2 },
					max = { x = centre.x + size.x / 2, y = centre.y + size.y / 2, z = centre.z + size.z / 2 },
				}
			end
		end

		local hider, hiderPath = requirePart(data, dataPath, "HiderSpawn")
		hiderSpawn = hider
		if hider ~= nil then
			table.insert(anchors, { node = hider, path = hiderPath })
		end

		local seekerFolder, seekerPath = requireFolder(data, dataPath, "SeekerSpawns")
		if seekerFolder ~= nil then
			for _, child in seekerFolder.children do
				if isPart(child) and hasTag(child, MapContract.TAG_SEEKER_SPAWN) then
					table.insert(seekerSpawns, child)
					table.insert(seekerPaths, `{seekerPath}/{child.name}`)
					table.insert(anchors, { node = child, path = `{seekerPath}/{child.name}` })
				end
			end
			if #seekerSpawns < 1 then
				report(SPAWN_COUNT, seekerPath, `needs at least 1 Part tagged {MapContract.TAG_SEEKER_SPAWN}`)
			end
		end

		local spotFolder, spotPath = requireFolder(data, dataPath, "DefaultSpots")
		if spotFolder ~= nil then
			for _, child in spotFolder.children do
				if isPart(child) and hasTag(child, MapContract.TAG_DEFAULT_SPOT) then
					table.insert(defaultSpots, child)
					table.insert(defaultSpotPaths, `{spotPath}/{child.name}`)
					table.insert(anchors, { node = child, path = `{spotPath}/{child.name}` })
				end
			end
			if #defaultSpots < MapContract.MIN_DEFAULT_SPOTS then
				report(
					SPOT_COUNT,
					spotPath,
					`needs at least {MapContract.MIN_DEFAULT_SPOTS} Parts tagged {MapContract.TAG_DEFAULT_SPOT}, found {#defaultSpots}`
				)
			end
		end

		local decoyFolder, decoyPath = requireFolder(data, dataPath, "DecoyAnchors")
		if decoyFolder ~= nil then
			for _, child in decoyFolder.children do
				if isPart(child) and hasTag(child, MapContract.TAG_DECOY_ANCHOR) then
					table.insert(decoyAnchors, child)
					table.insert(anchors, { node = child, path = `{decoyPath}/{child.name}` })
				end
			end
		end

		local tableFolder, tablePath = requireFolder(data, dataPath, "CardTable")
		if tableFolder ~= nil then
			local anchor, anchorPath = requirePart(tableFolder, tablePath, "TableAnchor")
			tableAnchor = anchor
			if anchor ~= nil then
				table.insert(anchors, { node = anchor, path = anchorPath })
			end

			local seatFolder, seatPath = requireFolder(tableFolder, tablePath, "Seats")
			if seatFolder ~= nil then
				local seatParts: { Node } = {}
				for _, child in seatFolder.children do
					if isPart(child) then
						table.insert(seatParts, child)
					end
				end
				if #seatParts ~= MapContract.SEAT_COUNT then
					report(
						SEAT_COUNT,
						seatPath,
						`needs exactly {MapContract.SEAT_COUNT} seat Parts, found {#seatParts}`
					)
				else
					for _, seat in seatParts do
						local digits = string.match(seat.name, "^Seat([1-9])$")
						local number = if digits ~= nil then tonumber(digits) else nil
						if number == nil or seats[number] ~= nil then
							report(
								SEAT_NAME,
								`{seatPath}/{seat.name}`,
								"seats must be named Seat1 to Seat9, each used once"
							)
						else
							seats[number] = seat
							table.insert(anchors, { node = seat, path = `{seatPath}/{seat.name}` })
						end
					end
				end
			end
		end
	end

	-- Cheap point-in-box test of every anchor against Bounds (T-1-35).
	local box = boundsBox
	if box ~= nil then
		for _, entry in anchors do
			local position = entry.node.position
			if position ~= nil and not inside(box, position) then
				report(OUT_OF_BOUNDS, entry.path, "anchor lies outside the Bounds volume")
			end
		end
	end

	-- PLACEMENT STAGE (MAP-02, D-17 STRICT). Runs ONLY when the structural pass is clean: research
	-- Pitfall 11 -- placement over a map that already failed structure would dereference folders the
	-- structural pass just reported missing. A spot outside Bounds is already MAP_OUT_OF_BOUNDS from
	-- the structural pass, so the OutOfBounds reason never fires here; it is live for the Phase 6
	-- hider check, where the point comes from a client.
	if #issues == 0 and box ~= nil then
		local boxes = SpoonPlacement.boxesOf(root, placement)
		local spawnPoints: { Vec3 } = {}
		for _, spawn in seekerSpawns do
			local spawnPosition = spawn.position
			if spawnPosition ~= nil then
				table.insert(spawnPoints, spawnPosition)
			end
		end
		local world, faults = SpoonPlacement.bake(boxes, box, spawnPoints, placement)
		local dataFolderPath = `{rootPath}/Data`
		for _, fault in faults do
			-- one issue per fault, never "the first fault wins": a map with two bad spawns must
			-- tell its author about both (the same discipline D-17 applies to spots).
			if fault.kind == "BoundsTooLarge" then
				report(BOUNDS_TOO_LARGE, `{dataFolderPath}/Bounds`, fault.detail)
			elseif fault.kind == "SpawnNoFooting" then
				local index = fault.spawnIndex
				local spawnPath = if index ~= nil then seekerPaths[index] else nil
				report(SPAWN_NO_FOOTING, spawnPath or `{dataFolderPath}/SeekerSpawns`, fault.detail)
			else
				report(SPAWN_DISCONNECTED, `{dataFolderPath}/SeekerSpawns`, fault.detail)
			end
		end
		if world ~= nil then
			local reachRange = placement.PICKUP_RANGE - placement.PICKUP_MARGIN
			for index, spot in defaultSpots do
				local spotPosition = spot.position
				if spotPosition ~= nil then
					local verdict = SpoonPlacement.check(world, spotPosition)
					if not verdict.ok then
						local reason: string = verdict.reason or "OutOfBounds"
						report(
							CODE_OF_REASON[reason],
							defaultSpotPaths[index],
							`placement rule {reason} failed: no seeker could find a spoon here (effective range {reachRange} studs)`
						)
					end
				end
			end
		end
	end

	-- The merged structural + placement list must stay totally ordered so CLI output is byte-deterministic
	-- across runs. This is the ONLY sort, and it runs after the placement stage has contributed.
	table.sort(issues, function(a: Issue, b: Issue): boolean
		if a.code ~= b.code then
			return a.code < b.code
		end
		if a.path ~= b.path then
			return a.path < b.path
		end
		return a.message < b.message
	end)

	if #issues > 0 or box == nil or hiderSpawn == nil or tableAnchor == nil then
		return issues, nil
	end

	local seatPoses: { Pose } = {}
	for number = 1, MapContract.SEAT_COUNT do
		local seat = seats[number]
		if seat == nil then
			return issues, nil
		end
		seatPoses[number] = poseOf(seat)
	end
	local function posesOf(nodes: { Node }): { Pose }
		local poses: { Pose } = {}
		for _, node in nodes do
			table.insert(poses, poseOf(node))
		end
		return poses
	end

	local spec: MapSpec = {
		metadata = {
			contractVersion = contractVersion :: number,
			id = root.name,
			displayName = displayName :: string,
			minPlayers = minPlayers :: number,
			maxPlayers = maxPlayers :: number,
			sizeClass = sizeClass :: SizeClass,
		},
		bounds = box,
		hiderSpawn = poseOf(hiderSpawn),
		seekerSpawns = posesOf(seekerSpawns),
		defaultSpots = posesOf(defaultSpots),
		decoyAnchors = posesOf(decoyAnchors),
		cardTable = { anchor = poseOf(tableAnchor), seats = seatPoses },
	}
	return issues, spec
end

return {
	validate = validate,
}
