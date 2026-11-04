--!strict
-- Integration spec for the committed gray-box map. It is also the proof that Lune can read attributes, tags, CFrame
-- and Size back out of a serialized .rbxm (research assumption A4), and that the CI path reaches the same pure
-- validator the unit tests exercise (T-1-33). Failure-expecting cases assert the REASON (an exact issue code or
-- message), not only a non-zero exit.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local MapContract = require("../../src/server/core/MapContract")
local MapValidator = require("../../src/server/core/MapValidator")
local Snapshot = require("../../scripts/maps/snapshot")
local Lex = require("../../scripts/ci/lex")
local Test = require("../harness/Test")

type Node = MapContract.Node

local GRAYBOX = "maps/gray-box.rbxm"
local SCRATCH = "build/maps-spec"

local function runCli(path: string): process.ExecResult
	return process.exec("lune", { "run", "scripts/maps/validate-map.luau", path })
end

local function loadGrayBox(): Node
	local root, reason = Snapshot.loadFile(GRAYBOX)
	assert(root ~= nil, reason)
	return root
end

local function descendants(root: Node): { Node }
	local out: { Node } = {}
	local function walk(n: Node)
		table.insert(out, n)
		for _, child in n.children do
			walk(child)
		end
	end
	walk(root)
	return out
end

local function hasTag(n: Node, tag: string): boolean
	return table.find(n.tags, tag) ~= nil
end

local function child(n: Node, name: string): Node
	for _, c in n.children do
		if c.name == name then
			return c
		end
	end
	error(`no child {name} under {n.name}`)
end

local function writeScratch(name: string, contents: string): string
	fs.writeDir(SCRATCH)
	local path = `{SCRATCH}/{name}`
	fs.writeFile(path, contents)
	return path
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

return function(t: Test.Runner)
	t.test("the real CLI validates the committed gray-box clean", function()
		local r = runCli(GRAYBOX)
		t.equal(r.code, 0, `expected exit 0, got {r.code}: {r.stdout}{r.stderr}`)
		t.contains(r.stdout, "validate-map: ok (18 spots, 9 seats)")
	end)

	t.test("the committed file deserializes to exactly one root, a Model named GrayBox", function()
		local roots = roblox.deserializeModel(fs.readFile(GRAYBOX))
		t.equal(#roots, 1)
		t.equal(roots[1].Name, "GrayBox")
		t.equal(roots[1].ClassName, "Model")
	end)

	t.test("attributes, tags, CFrame and Size round-trip out of the .rbxm (A4/A5)", function()
		local root = loadGrayBox()
		-- Attributes keep their Luau types.
		t.equal(root.attributes.ContractVersion, 2)
		t.equal(root.attributes.DisplayName, "Gray Box")
		t.equal(root.attributes.MinPlayers, 3)
		t.equal(root.attributes.MaxPlayers, 10)
		t.equal(root.attributes.SizeClass, "Medium")
		-- Tags survive.
		local spot = child(child(child(root, "Data"), "DefaultSpots"), "Spot01")
		t.deepEqual(spot.tags, { MapContract.TAG_DEFAULT_SPOT })
		-- CFrame position and Size survive with the values the generator wrote.
		t.deepEqual(spot.position, { x = -55, y = 0.5, z = -55 })
		t.deepEqual(spot.size, { x = 1, y = 1, z = 1 })
		t.equal(spot.anchored, true)
		local bounds = child(child(root, "Data"), "Bounds")
		t.deepEqual(bounds.size, { x = 124, y = 30, z = 124 })
		t.deepEqual(bounds.position, { x = 0, y = 14, z = 0 })
		-- D-02: the Ramp is built by a roll about Z, which does NOT change the look vector. Under
		-- contract version 1 it snapshotted as a flat floating slab, which culled the four ledge
		-- spots and failed MIN_DEFAULT_SPOTS. These numbers are V-4's measured values under Lune
		-- 0.11.1; acos(0.90701294) = 24.90 degrees, matching the generator's atan(6.5 / 14).
		local ramp = child(child(root, "Geometry"), "Ramp")
		local rampUp = ramp.up :: MapContract.Vec3
		t.truthy(math.abs(rampUp.x - 0.42111206) < 1e-5, `Ramp up.x is {rampUp.x}`)
		t.truthy(math.abs(rampUp.y - 0.90701294) < 1e-5, `Ramp up.y is {rampUp.y}`)
		t.truthy(math.abs(rampUp.z) < 1e-5, `Ramp up.z is {rampUp.z}`)
		t.equal(ramp.canCollide, true)
		t.equal(ramp.shape, "Block")
		-- An anchor under Data is non-collidable and must say so, or it would invent a standable surface.
		t.equal(spot.canCollide, false)
		t.deepEqual(spot.up, { x = 0, y = 1, z = 0 })
	end)

	t.test("both snapshotters emit the identical Node key set (must_have 1)", function()
		-- The runtime snapshotter cannot run under Lune, so assert against its comment-stripped source that it
		-- assigns every field. A field named only in a comment does not satisfy the gate.
		local loader = Lex.stripComments(fs.readFile("src/server/services/MapLoader.luau"))
		for _, field in { "position", "size", "look", "up", "anchored", "canCollide", "shape" } do
			t.contains(loader, `node.{field}`, `MapLoader does not assign node.{field}`)
		end
		local expected = {
			"anchored",
			"attributes",
			"canCollide",
			"children",
			"className",
			"look",
			"name",
			"position",
			"shape",
			"size",
			"tags",
			"up",
		}
		local function keysOf(n: Node): { string }
			local list: { string } = {}
			for key in n :: any do
				table.insert(list, key)
			end
			table.sort(list)
			return list
		end
		local function keysMatch(n: Node): boolean
			local actual = keysOf(n)
			if #actual ~= #expected then
				return false
			end
			for i, key in expected do
				if actual[i] ~= key then
					return false
				end
			end
			return true
		end
		local floor = child(child(loadGrayBox(), "Geometry"), "Ramp")
		t.deepEqual(keysOf(floor), expected)
		t.truthy(keysMatch(floor))
		-- The gate can fail: removing canCollide from the snapshotted Node makes the comparison differ.
		local withoutCanCollide = table.clone(floor)
		withoutCanCollide.canCollide = nil
		t.falsy(keysMatch(withoutCanCollide))
	end)

	t.test("the snapshot yields the expected MapSpec through the shared validator", function()
		local issues, spec = MapValidator.validate(loadGrayBox())
		t.deepEqual(issues, {})
		assert(spec ~= nil, "gray-box must produce a MapSpec")
		t.equal(spec.metadata.contractVersion, 2)
		t.equal(spec.metadata.displayName, "Gray Box")
		t.equal(spec.metadata.minPlayers, 3)
		t.equal(spec.metadata.maxPlayers, 10)
		t.equal(spec.metadata.sizeClass, "Medium")
		t.equal(spec.metadata.id, "GrayBox")
		t.equal(#spec.defaultSpots, 18)
		t.equal(#spec.cardTable.seats, 9)
		t.equal(#spec.seekerSpawns, 4)
		t.equal(#spec.decoyAnchors, 4)
	end)

	t.test("tag and seat counts straight from the tree: 18 spots, 4 spawns, 4 decoys, exactly 9 seats", function()
		local all = descendants(loadGrayBox())
		local spots, spawns, decoys, seats = 0, 0, 0, 0
		for _, n in all do
			if hasTag(n, MapContract.TAG_DEFAULT_SPOT) then
				spots += 1
			end
			if hasTag(n, MapContract.TAG_SEEKER_SPAWN) then
				spawns += 1
			end
			if hasTag(n, MapContract.TAG_DECOY_ANCHOR) then
				decoys += 1
			end
			if string.match(n.name, "^Seat%d+$") ~= nil then
				seats += 1
			end
		end
		t.equal(spots, 18)
		t.equal(spawns, 4)
		t.equal(decoys, 4)
		t.equal(seats, 9)
	end)

	t.test("no Script, LocalScript or ModuleScript anywhere in the committed map", function()
		for _, n in descendants(loadGrayBox()) do
			t.falsy(
				n.className == "Script" or n.className == "LocalScript" or n.className == "ModuleScript",
				`code found at {n.name}`
			)
		end
	end)

	t.test("spots are at varied heights: at least four at y >= 6 and at least four distinct heights", function()
		local root = loadGrayBox()
		local high = 0
		local heights: { [number]: boolean } = {}
		local distinct = 0
		for _, spot in child(child(root, "Data"), "DefaultSpots").children do
			local y = (spot.position :: MapContract.Vec3).y
			if y >= 6 then
				high += 1
			end
			if not heights[y] then
				heights[y] = true
				distinct += 1
			end
		end
		t.truthy(high >= 4, `only {high} spots at y >= 6`)
		t.truthy(distinct >= 4, `only {distinct} distinct spot heights`)
	end)

	t.test("hidden data stays out of Geometry, which is the only thing ever cloned to Workspace (rule 3)", function()
		local geometry = child(loadGrayBox(), "Geometry")
		for _, n in descendants(geometry) do
			t.falsy(hasTag(n, MapContract.TAG_DEFAULT_SPOT), `{n.name} carries the spot tag inside Geometry`)
			t.falsy(hasTag(n, MapContract.TAG_SEEKER_SPAWN), `{n.name} carries the spawn tag inside Geometry`)
			t.falsy(hasTag(n, MapContract.TAG_DECOY_ANCHOR), `{n.name} carries the decoy tag inside Geometry`)
		end
	end)

	t.test("seats sit on a radius-6 ring around the table, look at it, and run clockwise", function()
		local data = child(loadGrayBox(), "Data")
		local anchorPos = child(child(data, "CardTable"), "TableAnchor").position :: MapContract.Vec3
		local seats = child(child(data, "CardTable"), "Seats")
		local previousAngle: number? = nil
		for i = 1, 9 do
			local seat = child(seats, `Seat{i}`)
			local p = seat.position :: MapContract.Vec3
			local look = seat.look :: MapContract.Vec3
			local dx, dz = anchorPos.x - p.x, anchorPos.z - p.z
			local distance = math.sqrt(dx * dx + dz * dz)
			t.truthy(math.abs(distance - 6) < 0.01, `Seat{i} is {distance} from the table, expected 6`)
			-- Look vector is the unit direction from the seat to the table anchor.
			t.truthy(math.abs(look.x - dx / distance) < 0.01, `Seat{i} look.x does not point at the table`)
			t.truthy(math.abs(look.z - dz / distance) < 0.01, `Seat{i} look.z does not point at the table`)
			t.truthy(math.abs(look.y) < 0.01, `Seat{i} looks up or down`)
			-- Clockwise seen from above with x east and z south: the angle atan2(x, -z) from north increases.
			local angle = math.deg(math.atan2(p.x - anchorPos.x, -(p.z - anchorPos.z)))
			if angle < 0 then
				angle += 360
			end
			if previousAngle ~= nil then
				t.truthy(
					math.abs(angle - previousAngle - 40) < 0.1,
					`Seat{i} is not 40 degrees clockwise of Seat{i - 1}`
				)
			end
			previousAngle = angle
		end
	end)

	t.test("the committed .rbxm is exactly what the generator produces (it cannot go stale)", function()
		fs.writeDir(SCRATCH)
		local out = `{SCRATCH}/regenerated.rbxm`
		local r = process.exec("lune", { "run", "scripts/maps/generate-graybox.luau", out })
		t.equal(r.code, 0, `generator failed: {r.stdout}{r.stderr}`)
		t.truthy(fs.readFile(out) == fs.readFile(GRAYBOX), "regenerated bytes differ from the committed file")
		fs.removeFile(out)
	end)

	t.test("a mutated snapshot (one seat removed in memory) fails with MAP_SEAT_COUNT and nothing else", function()
		local root = loadGrayBox()
		local seats = child(child(child(root, "Data"), "CardTable"), "Seats")
		table.remove(seats.children, #seats.children)
		local issues, spec = MapValidator.validate(root)
		t.deepEqual(codesOf(issues), { "MAP_SEAT_COUNT" })
		t.equal(spec, nil)
	end)

	t.test("the CLI exits 1 and prints MAP_SEAT_COUNT for a copy with a seat deleted", function()
		local roots = roblox.deserializeModel(fs.readFile(GRAYBOX))
		local seat = roots[1]:FindFirstChild("Seat9", true)
		assert(seat ~= nil, "Seat9 should exist in the committed map")
		seat:Destroy()
		local path = writeScratch("broken-seat.rbxm", roblox.serializeModel({ roots[1] }))
		local r = runCli(path)
		fs.removeFile(path)
		t.equal(r.code, 1, `expected exit 1, got {r.code}`)
		t.contains(r.stdout, "MAP_SEAT_COUNT")
		t.contains(r.stdout, "GrayBox/Data/CardTable/Seats")
		t.falsy(string.find(r.stdout, "validate-map: ok", 1, true) ~= nil, "a broken map must not print ok")
	end)

	t.test("the CLI exits 1 and prints MAP_SCRIPT_FORBIDDEN when a Script is smuggled into Geometry", function()
		local roots = roblox.deserializeModel(fs.readFile(GRAYBOX))
		local geometry = roots[1]:FindFirstChild("Geometry")
		assert(geometry ~= nil, "Geometry should exist in the committed map")
		local evil = roblox.Instance.new("Script")
		evil.Name = "Evil"
		evil.Parent = geometry
		local path = writeScratch("broken-script.rbxm", roblox.serializeModel({ roots[1] }))
		local r = runCli(path)
		fs.removeFile(path)
		t.equal(r.code, 1)
		t.contains(r.stdout, "MAP_SCRIPT_FORBIDDEN GrayBox/Geometry/Evil")
	end)

	t.test("the CLI exits 1 with a parse reason for a truncated file", function()
		local whole = fs.readFile(GRAYBOX)
		local path = writeScratch("truncated.rbxm", string.sub(whole, 1, 200))
		local r = runCli(path)
		fs.removeFile(path)
		t.equal(r.code, 1)
		t.contains(r.stdout, "cannot parse")
	end)

	t.test("the CLI exits 1 with a read reason for a missing file and a usage line for no argument", function()
		local missing = runCli(`{SCRATCH}/does-not-exist.rbxm`)
		t.equal(missing.code, 1)
		t.contains(missing.stdout, "cannot read")
		local none = process.exec("lune", { "run", "scripts/maps/validate-map.luau" })
		t.equal(none.code, 1)
		t.contains(none.stdout, "usage:")
	end)

	t.test("a file with two top-level instances is refused (Rojo cannot mount it either)", function()
		local a = roblox.Instance.new("Model")
		a.Name = "A"
		local b = roblox.Instance.new("Model")
		b.Name = "B"
		local path = writeScratch("two-roots.rbxm", roblox.serializeModel({ a, b }))
		local r = runCli(path)
		fs.removeFile(path)
		t.equal(r.code, 1)
		t.contains(r.stdout, "exactly one top-level instance")
	end)
end
