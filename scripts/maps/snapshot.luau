--!strict
-- CI snapshotter: turns a deserialized .rbxm object tree into the plain MapContract.Node shape the pure validator
-- consumes. The runtime loader (plan 01-10, MapLoader) must emit the IDENTICAL shape so one validator serves both.
--
-- Node shape emitted (see src/server/core/MapContract.luau):
--   { name, className, attributes = { [string]: string|number|boolean }, tags = { string } (sorted),
--     position/size/look/up/anchored/canCollide = present for BasePart descendants only,
--     shape = present only when className == "Part", children = { Node } (document order) }
-- Twin of src/server/services/MapLoader.luau: a field added to one and not the other means CI and the live game
-- disagree about whether a spoon is findable.
--
-- Position and look are read from the CFrame (assumption A5): the derived Position property is NOT readable on a
-- deserialized Part under Lune 0.11.1 ("Failed to get property 'Position' - missing default value").
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local MapContract = require("../../src/server/core/MapContract")

type Node = MapContract.Node
type Vec3 = MapContract.Vec3

local function clean(n: number): number
	-- Adding zero turns IEEE negative zero into positive zero, which would otherwise print as "-0" and fail
	-- deepEqual-style comparisons against hand-written fixtures.
	return n + 0
end

local function vec3Of(value: any): Vec3
	return { x = clean(value.X), y = clean(value.Y), z = clean(value.Z) }
end

local function snapshot(inst: roblox.Instance): Node
	local attributes: { [string]: string | number | boolean } = {}
	for key, value in inst:GetAttributes() do
		if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
			attributes[key] = value
		end
	end
	local tags = inst:GetTags()
	table.sort(tags)

	local node: Node = {
		name = inst.Name,
		className = inst.ClassName,
		attributes = attributes,
		tags = tags,
		children = {},
	}
	if inst:IsA("BasePart") then
		-- Part properties and datatypes are untyped in @lune/roblox (see generate-graybox.luau); this is the one
		-- boundary where a property is read, and everything downstream is typed.
		local part: any = inst
		local cframe = part.CFrame
		node.position = vec3Of(cframe.Position)
		node.look = vec3Of(cframe.LookVector)
		node.up = vec3Of(cframe.UpVector)
		node.size = vec3Of(part.Size)
		node.anchored = part.Anchored == true
		node.canCollide = part.CanCollide == true
		if inst.ClassName == "Part" then
			-- Shape is a Part property only. Enum values are untyped in @lune/roblox, so go through
			-- the Name field and fall back to tostring (V-4: Part.Shape reads as Enum.PartType.Block
			-- or Ball on a deserialized Part, and a Ball Part still has className "Part").
			local shape: any = part.Shape
			node.shape = tostring(shape.Name or shape)
		end
	end
	for _, child in inst:GetChildren() do
		table.insert(node.children, snapshot(child))
	end
	return node
end

-- Lune errors carry a multi-line stack trace; the first line is the reason.
local function firstLine(message: string): string
	return string.match(message, "^[^\n]*") or message
end

-- Reads a .rbxm and returns its single root snapshotted, or nil plus a reason.
local function loadFile(path: string): (Node?, string?)
	local readOk, contents = pcall(fs.readFile, path)
	if not readOk then
		return nil, `cannot read {path}: {firstLine(tostring(contents))}`
	end
	local parseOk, roots = pcall(roblox.deserializeModel, contents :: string)
	if not parseOk then
		return nil, `cannot parse {path} as a model: {firstLine(tostring(roots))}`
	end
	local list = roots :: { roblox.Instance }
	if #list ~= 1 then
		return nil, `{path} must contain exactly one top-level instance, found {#list}`
	end
	return snapshot(list[1]), nil
end

return {
	snapshot = snapshot,
	loadFile = loadFile,
}
