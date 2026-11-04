--!strict
-- MapLoader (MAP-01): the Roblox snapshotter. It turns a live map Instance tree into the SAME plain-data Node
-- shape the Lune snapshotter (scripts/maps/snapshot.luau) emits, runs the one pure MapValidator over it, and
-- only then mounts the map's Geometry into Workspace.
--
-- There is deliberately NO per-map branch here: every map goes through the same contract. Tag names come from
-- MapContract so the hidden-data vocabulary lives in exactly one place (guard rule R5).
--
-- Node v2 adds up, canCollide and (className == "Part" only) shape. This file and scripts/maps/snapshot.luau are
-- deliberate twins: a field added to one and not the other means CI and the live game disagree about whether a
-- spoon is findable.
--
-- Position and look are derived from CFrame only. On a deserialized Part the derived Position property errors
-- (plan 01-07, assumption A5), so CFrame.Position and CFrame.LookVector are the one readable source.
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MapContract = require("../core/MapContract")
local MapValidator = require("../core/MapValidator")

type Node = MapContract.Node
type Vec3 = MapContract.Vec3

local MapLoader = {}

-- Adding zero turns IEEE negative zero into positive zero (parity with the CI snapshotter).
local function clean(n: number): number
	return n + 0
end

local function vec3Of(v: Vector3): Vec3
	return { x = clean(v.X), y = clean(v.Y), z = clean(v.Z) }
end

function MapLoader.snapshot(instance: Instance): Node
	local attributes: { [string]: string | number | boolean } = {}
	for key, value in instance:GetAttributes() do
		-- Non-primitive attributes (Vector3, Color3, ...) are dropped, as in the CI snapshotter.
		if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
			attributes[key] = value
		end
	end
	local tags = CollectionService:GetTags(instance)
	table.sort(tags)

	local node: Node = {
		name = instance.Name,
		className = instance.ClassName,
		attributes = attributes,
		tags = tags,
		children = {},
	}
	if instance:IsA("BasePart") then
		local cframe = instance.CFrame
		node.position = vec3Of(cframe.Position)
		node.look = vec3Of(cframe.LookVector)
		node.up = vec3Of(cframe.UpVector)
		node.size = vec3Of(instance.Size)
		node.anchored = instance.Anchored
		node.canCollide = instance.CanCollide
		if instance.ClassName == "Part" then
			node.shape = (instance :: Part).Shape.Name
		end
	end
	for _, child in instance:GetChildren() do
		table.insert(node.children, MapLoader.snapshot(child))
	end
	return node
end

local function formatIssues(mapId: string, issues: { MapContract.Issue }): string
	local lines: { string } = {}
	for _, issue in issues do
		table.insert(lines, `{issue.code} {issue.path} {issue.message}`)
	end
	return `map {mapId} does not satisfy the map contract ({#issues} issue(s)):\n{table.concat(lines, "\n")}`
end

-- Validates ServerStorage.Maps[mapId] and mounts ONLY its Geometry folder into Workspace. Data stays in
-- ServerStorage (CLAUDE.md rule 3). An invalid map errors with the formatted issue list and mounts nothing.
function MapLoader.load(mapId: string): (Instance, MapContract.MapSpec)
	local maps = ServerStorage:FindFirstChild("Maps")
	if maps == nil then
		error("ServerStorage.Maps does not exist: the place was not built from default.project.json")
	end
	local map = maps:FindFirstChild(mapId)
	if map == nil then
		error(`map {mapId} not found under ServerStorage.Maps`)
	end

	local issues, spec = MapValidator.validate(MapLoader.snapshot(map))
	if #issues > 0 or spec == nil then
		error(formatIssues(mapId, issues))
	end

	local geometry = map:FindFirstChild("Geometry")
	if geometry == nil then
		error(`map {mapId} passed validation but has no Geometry folder`)
	end
	local mounted = geometry:Clone()
	mounted.Parent = Workspace
	return mounted, spec
end

return MapLoader
