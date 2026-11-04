--!strict
-- The one rule set: "is this coordinate a valid hiding spot?" (plan 03-05, D-04, D-10, D-12, D-13, HIDE-06).
--
-- PURE ZONE: plain data in, plain data out, no Roblox API, no clock, no yields (CLAUDE.md rules 2, 5, 6).
-- Workspace raycasts and PathfindingService are unavailable here and that constraint was accepted rather
-- than worked around (D-01).
--
-- FOUND-05 GUARDED ROOT. This filename is in scripts/ci/zones.luau's guardedNamePrefixes, so check-guards R2
-- computes the transitive import closure from here and forbids any path to cosmetics or shop code. CLAUDE.md
-- rule 1 (no purchase may affect score, findability or competitive outcome) is enforced by that closure, not
-- promised.
--
-- API SHAPE (research Pattern 4: bake once, query many). `bake` is the heavy call, made once per map at load or
-- in CI. `check` is the cheap one the hider's live ghost preview calls per tick in Phases 5 and 6: it scans
-- about 200 columns and exits on the first clear sightline. The world holds the config it was baked with, so
-- `check` takes no config argument and no avatar argument.
--
-- D-10 / HIDE-07, as a structural claim: there is no avatar parameter, so placement validity cannot depend on
-- the hider's avatar scale. The canonical capsule is biased toward rejecting (D-11): short reach, tall
-- headroom, deliberately harder to satisfy than any real avatar, because an unfindable spoon stalls a round
-- while a culled spot costs nothing when the map carries margin.
--
-- THE REASON ORDER IS LOCKED. See the Reason type below. It is recorded in three places and all three must
-- agree: the type, REASON_ORDER, and tests/placement/corpus.spec.luau.
--
-- NAMING CONVENTION. check-guards R3 bans the substring "o" followed by "s" and a dot anywhere in a pure-zone
-- file, string literals included. So point locals are p, q, a, b, pt, at, centre, delta, axis, normal. Write
-- the full word for a position, and never name a cosine or a line of sight with the banned two-letter ending.
--
-- MESH AND CSG DEFAULT (research Pitfall 9, assumption A4), recorded as a decision: only className == "Part"
-- with shape == "Block" is a standable, blocking box. Every other collidable BasePart under Geometry/
-- contributes its world AABB as blocking-only and never standable. This is reject-biased: a mesh floor yields
-- NoFooting and the map author fixes it by modelling floors as Parts. A Ball or Cylinder Part has className
-- "Part", which is why `shape` exists in contract v2. Revisit only if Phase 7a authoring hits it for real.
--
-- ACCEPTED LIMITATION: this is our model of collision, not Roblox's. Phase 5 runs the real hunt in real
-- geometry and is where a divergence will first be observable.
local MapContract = require("./MapContract")
local Obb = require("./Obb")
local WalkGrid = require("./WalkGrid")

type Vec3 = MapContract.Vec3
type Aabb = MapContract.Aabb
type Node = MapContract.Node

-- The injected config. Key names are UPPER_SNAKE so the shipped shared placement config module IS a PlacementConfig with
-- no adapter between them: an adapter would be a second place where CI and the live game could disagree about
-- a number, which is exactly what D-01 exists to prevent.
export type PlacementConfig = {
	GRID_SIZE: number,
	STEP_UP: number,
	MAX_SLOPE_DEGREES: number,
	CAPSULE_RADIUS: number,
	CAPSULE_HEIGHT: number,
	REACH_HEIGHT: number,
	EYE_HEIGHT: number,
	SPOT_CLEARANCE: number,
	PICKUP_RANGE: number,
	PICKUP_MARGIN: number,
}

-- THE ORDER IS LOCKED. Declaration order IS evaluation order, first match wins, exactly one reason per point.
-- Never reorder this to make an assertion pass. The rules are four (D-12: in-bounds, standable, reach,
-- line-of-sight) and the reasons split two of them.
--
-- A spot inside the solid Core must report Solid, NOT a downstream sightline failure. Reporting a fundamental
-- failure as a downstream symptom is the most expensive way for this module to be wrong, which is the same
-- reasoning that put `circulation` before `unsatisfiable` in Invariants.check. OutOfReach precedes Unreachable
-- for the same reason: a geometric distance failure is more fundamental than a connectivity failure.
--
-- This order is recorded in THREE places and all three must agree: this type, the REASON_ORDER array below, and
-- tests/placement/corpus.spec.luau. MapValidator.luau carries the same comment beside its reason-to-issue-code
-- table.
export type Reason = "OutOfBounds" | "Solid" | "NoFooting" | "OutOfReach" | "Unreachable" | "NoSight"

export type Verdict = { ok: boolean, reason: Reason? }

export type BakeFault = {
	kind: "BoundsTooLarge" | "SpawnNoFooting" | "SpawnDisconnected",
	detail: string,
	spawnIndex: number?,
}

export type World = {
	bounds: Aabb,
	boxes: { Obb.Box },
	index: Obb.Index,
	grid: WalkGrid.Grid,
	config: PlacementConfig,
	effectiveRange: number, -- PICKUP_RANGE - PICKUP_MARGIN, derived once at bake time
	counters: WalkGrid.Counters,
}

local GEOM_EPSILON = Obb.GEOM_EPSILON
local MAX_BAKE_COLUMNS = 250000
local BUCKET_SIZE = 8
local SPAWN_DROP_LIMIT = 8

local REASON_ORDER: { Reason } = { "OutOfBounds", "Solid", "NoFooting", "OutOfReach", "Unreachable", "NoSight" }

local REQUIRED_KEYS = {
	"GRID_SIZE",
	"STEP_UP",
	"MAX_SLOPE_DEGREES",
	"CAPSULE_RADIUS",
	"CAPSULE_HEIGHT",
	"REACH_HEIGHT",
	"EYE_HEIGHT",
	"SPOT_CLEARANCE",
	"PICKUP_RANGE",
	"PICKUP_MARGIN",
}

local sqrt = math.sqrt
local huge = math.huge

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function assertConfig(config: any): PlacementConfig
	if config == nil then
		-- Loud on purpose. A silent default table would mean CI and the live game could validate the same map
		-- against different numbers, which is the one failure D-01 and D-13 exist to prevent, and it would be
		-- invisible until a spoon turned out to be unfindable in play.
		error("SpoonPlacement: a PlacementConfig is required", 0)
	end
	if type(config) ~= "table" then
		error("SpoonPlacement: a PlacementConfig must be a table", 0)
	end
	for _, key in REQUIRED_KEYS do
		local v = config[key]
		if not (finite(v) and v > 0) then
			error(`SpoonPlacement: config.{key} must be a positive finite number`, 0)
		end
	end
	if not (config.PICKUP_MARGIN < config.PICKUP_RANGE) then
		error("SpoonPlacement: config.PICKUP_MARGIN must be below PICKUP_RANGE", 0)
	end
	-- An eye at or above the capsule height is incoherent, so that half is strict. A reach point above the eye
	-- is incoherent too, but a reach point EQUAL to the eye is the degenerate single-height configuration, and
	-- that configuration is the entire justification for EYE_HEIGHT existing as a separate constant: research
	-- measured that with one shared reach/eye height the crate-top spot needs an effective range of 8.75, is
	-- culled, and the reference map falls to 15 survivors. A strict > would make the exact configuration
	-- research measured inexpressible, so plan 03-06 case 7 could not bake it. The lower comparison is
	-- therefore non-strict on purpose: do not tighten this to `>`.
	if not (config.CAPSULE_HEIGHT > config.EYE_HEIGHT and config.EYE_HEIGHT >= config.REACH_HEIGHT) then
		error("SpoonPlacement: config requires CAPSULE_HEIGHT > EYE_HEIGHT >= REACH_HEIGHT", 0)
	end
	-- Deliberately NOT checked here: the STEP_UP / GRID_SIZE coupling. That is a config-authoring invariant owned
	-- by tests/placement/config_lock.spec.luau; a hard error would stop a legitimate diagnostic run at a coarse
	-- resolution.
	return config :: PlacementConfig
end

local function boxesOf(root: Node, config: PlacementConfig): { Obb.Box }
	assertConfig(config)
	local boxes: { Obb.Box } = {}
	local geometry: Node? = nil
	for _, child in root.children do
		if child.name == "Geometry" then
			geometry = child
			break
		end
	end
	if geometry == nil then
		return boxes
	end
	local function walk(node: Node, path: string)
		local centre, size, look = node.position, node.size, node.look
		if centre ~= nil and size ~= nil and look ~= nil and node.canCollide ~= false then
			-- This module assumes the structural pass already ran (Pitfall 11): MapValidator only reaches the
			-- placement stage when its issue list is empty, and MAP_NODE_BASIS_INVALID rejects a BasePart
			-- without `up`.
			local up = node.up
			if up == nil then
				error(`SpoonPlacement.boxesOf: {path} has no up vector; run the structural validation first`, 0)
			end
			local standable = node.className == "Part" and node.shape == "Block"
			table.insert(boxes, Obb.fromPose(path, centre, size, look, up, standable))
		end
		for _, child in node.children do
			walk(child, `{path}/{child.name}`)
		end
	end
	-- Data/ is never walked: those are server-only anchors, not geometry.
	walk(geometry, `{root.name}/Geometry`)
	return boxes
end

local function bake(
	boxes: { Obb.Box },
	bounds: Aabb,
	spawns: { Vec3 },
	config: PlacementConfig
): (World?, { BakeFault })
	assertConfig(config)
	local faults: { BakeFault } = {}

	-- A mis-authored 2,000-stud Bounds would be 4,000,000 columns and would hang the server at map load. This
	-- check is bounds-and-resolution only, which is what makes refusing it cheap. The graybox is 15,376 columns
	-- and the maze stress fixture is 61,504, so the 250,000 ceiling is about 4x above anything real.
	local columns = WalkGrid.columnCountFor(bounds, config.GRID_SIZE)
	if columns > MAX_BAKE_COLUMNS then
		table.insert(faults, {
			kind = "BoundsTooLarge",
			detail = `Bounds would need {columns} grid columns, above the {MAX_BAKE_COLUMNS} ceiling`,
		})
		return nil, faults
	end

	local index = Obb.newIndex(boxes, BUCKET_SIZE)
	local grid = WalkGrid.build(boxes, bounds, config, index)

	local allSeeds: { number } = {}
	local seeded: { { number } } = {} -- seed lists of the spawns that produced any, in spawn order
	local seededSpawn: { number } = {}
	for i, spawn in spawns do
		local seeds = WalkGrid.seedsAt(grid, spawn, SPAWN_DROP_LIMIT)
		if #seeds == 0 then
			-- Pitfall 10: an empty seed list must be loud, never "flood everything".
			table.insert(faults, {
				kind = "SpawnNoFooting",
				detail = `spawn {i} has no standable cell within {SPAWN_DROP_LIMIT} studs below it`,
				spawnIndex = i,
			})
		else
			table.insert(seeded, seeds)
			table.insert(seededSpawn, i)
			for _, c in seeds do
				table.insert(allSeeds, c)
			end
		end
	end

	-- D-06 sanity check, in its failing direction: flood from each spawn alone and require that it reaches the
	-- others. The combined flood is seeded from ALL spawns' cells, so every seed cell has region == 1 by
	-- construction: "assert every spawn's seed cells are in the combined region" can NEVER fail and detects
	-- nothing. Only a per-spawn flood can. Only spawns that produced seeds take part, and the check is skipped
	-- when fewer than two remain: a footless spawn has an empty seed list, floods nothing, and would otherwise
	-- add a spurious SpawnDisconnected on top of its real SpawnNoFooting.
	-- Containment means "reaches at least one of the other spawn's seed cells": a spawn above a crate seeds
	-- several layers, and an unreachable lower layer must not count as the spawn being disconnected.
	if #seeded >= 2 then
		local region = grid.region
		local reportedPair: { [string]: boolean } = {}
		for a = 1, #seeded do
			WalkGrid.flood(grid, boxes, index, seeded[a], config)
			for b = 1, #seeded do
				if b ~= a then
					local reached = false
					for _, c in seeded[b] do
						if region[c] == 1 then
							reached = true
							break
						end
					end
					-- One fault per unordered pair, even if both directions fail (links are not symmetric: a
					-- drop-off is walkable one way).
					local pairKey = `{math.min(a, b)}:{math.max(a, b)}`
					if not reached and not reportedPair[pairKey] then
						reportedPair[pairKey] = true
						table.insert(faults, {
							kind = "SpawnDisconnected",
							detail = `spawn {seededSpawn[a]} cannot reach spawn {seededSpawn[b]}`,
							spawnIndex = seededSpawn[b],
						})
					end
				end
			end
		end
	end

	-- The combined flood runs last so the grid is left holding the combined region and counters.
	WalkGrid.flood(grid, boxes, index, allSeeds, config)

	if #faults > 0 then
		return nil, faults
	end
	local world: World = {
		bounds = bounds,
		boxes = boxes,
		index = index,
		grid = grid,
		config = config,
		effectiveRange = config.PICKUP_RANGE - config.PICKUP_MARGIN,
		counters = grid.counters,
	}
	return world, faults
end

local boxScratch: { number } = {}
local cellScratch: { number } = {}
local distScratch: { number } = {}

local function reject(reason: Reason): Verdict
	return { ok = false, reason = reason }
end

local function check(world: World, point: Vec3): Verdict
	local config = world.config
	local grid = world.grid
	local bounds = world.bounds
	local px, py, pz = point.x, point.y, point.z

	-- 1. OutOfBounds (rule: in-bounds). Positive comparisons plus an explicit finite test: `p.x < min or
	-- p.x > max` is FALSE for NaN and would wave it through (research Pitfall 6).
	if
		not (finite(px) and finite(py) and finite(pz))
		or not (
			px >= bounds.min.x
			and px <= bounds.max.x
			and py >= bounds.min.y
			and py <= bounds.max.y
			and pz >= bounds.min.z
			and pz <= bounds.max.z
		)
	then
		return reject("OutOfBounds")
	end

	local range = config.PICKUP_RANGE

	-- 2. Solid (rule: standable, part a). Inside or within SPOT_CLEARANCE of a collidable box.
	local boxCount = Obb.queryIndex(world.index, px - range, pz - range, px + range, pz + range, boxScratch)
	for n = 1, boxCount do
		local box = world.boxes[boxScratch[n]]
		if Obb.distanceToPoint(box, px, py, pz) <= config.SPOT_CLEARANCE + GEOM_EPSILON then
			return reject("Solid")
		end
	end

	-- 3. NoFooting (rule: standable, part b). Some standable cell of ANY region within PICKUP_RANGE of the
	-- point, measured from the cell's reach point.
	local reachHeight = config.REACH_HEIGHT
	local cellCount = WalkGrid.cellsNear(grid, px, pz, range, cellScratch)
	local kept = 0
	for n = 1, cellCount do
		local c = cellScratch[n]
		local dx = grid.cellX[c] - px
		local dy = grid.cellH[c] + reachHeight - py
		local dz = grid.cellZ[c] - pz
		local d = sqrt(dx * dx + dy * dy + dz * dz)
		if d <= range then
			kept += 1
			cellScratch[kept] = c
			distScratch[kept] = d
		end
	end
	if kept == 0 then
		return reject("NoFooting")
	end

	-- 4. OutOfReach (rule: reach, part a). Some cell within the effective range E.
	local limit = world.effectiveRange - GEOM_EPSILON
	local inReach = 0
	for n = 1, kept do
		if distScratch[n] <= limit then
			inReach += 1
			cellScratch[inReach] = cellScratch[n]
			distScratch[inReach] = distScratch[n]
		end
	end
	if inReach == 0 then
		return reject("OutOfReach")
	end

	-- 5. Unreachable (rule: reach, part b). Some in-reach cell connected to the seeker spawns.
	local connected = 0
	local region = grid.region
	for n = 1, inReach do
		local c = cellScratch[n]
		if region[c] == 1 then
			connected += 1
			cellScratch[connected] = c
			distScratch[connected] = distScratch[n]
		end
	end
	if connected == 0 then
		return reject("Unreachable")
	end

	-- 6. NoSight (rule: line-of-sight). Nearest first, so the common case exits on the first candidate. The
	-- inflate of GEOM_EPSILON makes a graze count as blocked.
	for i = 2, connected do
		local c, d = cellScratch[i], distScratch[i]
		local j = i - 1
		while j >= 1 and distScratch[j] > d do
			cellScratch[j + 1] = cellScratch[j]
			distScratch[j + 1] = distScratch[j]
			j -= 1
		end
		cellScratch[j + 1] = c
		distScratch[j + 1] = d
	end
	local eyeHeight = config.EYE_HEIGHT
	for n = 1, connected do
		local c = cellScratch[n]
		local ex, ey, ez = grid.cellX[c], grid.cellH[c] + eyeHeight, grid.cellZ[c]
		local blocked = false
		for m = 1, boxCount do
			if Obb.segmentHits(world.boxes[boxScratch[m]], ex, ey, ez, px, py, pz, GEOM_EPSILON) then
				blocked = true
				break
			end
		end
		if not blocked then
			return { ok = true }
		end
	end
	return reject("NoSight")
end

return {
	REASON_ORDER = REASON_ORDER,
	MAX_BAKE_COLUMNS = MAX_BAKE_COLUMNS,
	BUCKET_SIZE = BUCKET_SIZE,
	SPAWN_DROP_LIMIT = SPAWN_DROP_LIMIT,
	assertConfig = assertConfig,
	boxesOf = boxesOf,
	bake = bake,
	check = check,
}
