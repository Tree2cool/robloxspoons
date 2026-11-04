--!strict
-- Reachability layer for the placement rules (plan 03-04, HIDE-06): a multi-layer walkable height field over the
-- map bounds and an iterative flood fill from every seeker spawn.
--
-- PURE ZONE: plain data in, plain data out, no Roblox API, no clock, no yields (CLAUDE.md rules 2, 5, 6).
-- NAMING CONVENTION. check-guards R3 bans the two-letter pair "o" then "s" followed by a dot anywhere in a
-- pure-zone file, and the ban reaches INSIDE string literals. So locals are p, q, a, b, pt, at, centre, delta,
-- axis, normal, and the full word "position". A cosine local is named `cosine`. Never abbreviate those words.
--
-- PROVENANCE. A Recast-style solid height field. The parameter mapping is one to one: CAPSULE_HEIGHT is
-- walkableHeight, STEP_UP is walkableClimb, CAPSULE_RADIUS is walkableRadius, MAX_SLOPE_DEGREES is
-- walkableSlopeAngle and GRID_SIZE is the cell size.
--
-- D-05: no PathfindingService. It is a Roblox API and cannot live in the pure zone, and choosing it would split CI
-- from runtime. A walkable-grid flood fill is pure, deterministic, headless and gives one answer every run.
-- D-07: each XZ column holds a LIST of standable heights. A single-height grid cannot represent a floor above a
-- floor (the mansion would be unvalidatable) and a 3D voxel grid is about 461,000 mostly-air cells over the
-- graybox bounds alone.
--
-- THE FLOOD DELIBERATELY DOES NOT MODEL JUMPING, even though Humanoid.JumpHeight defaults to 7.2 studs and a
-- real player can therefore jump onto the 6.5 ledge and the 4.0 crates. Not modelling it is the rejecting
-- direction (D-11): a spot that needs a jump is culled, never wrongly accepted.
--
-- TWO NON-OBVIOUS RULES, both measured.
--   1. Slope allowance in erosion. The naive rule "drop a cell if a neighbour within CAPSULE_RADIUS has a solid
--      above h + STEP_UP" erodes the walkable slope itself, because the neighbour a radius away is
--      radius * tan(slope) higher. Without the allowance the ramp needs STEP_UP >= 1.5 * tan(24.9) = 0.696
--      instead of GRID_SIZE * tan(24.9) = 0.464, and the config invariant plan 03-02 locked stops protecting
--      anything. We never erode away from drop-offs (Recast does): a ledge spot 2 studs from an edge is real.
--   2. Every neighbour link is verified by an exact segment test. A 0.3-thick wall falls between cell centres,
--      so with grid-only links all 1,600 cells of a test room read as one region; with the segment test at two
--      body heights 840 are reached. The leak direction marks a sealed spot reachable and ships an unfindable
--      spoon.
--
-- `counters` is deterministic work accounting. It exists so a time-cap gate can prove the bake DID something
-- before it reads a clock: a cap on an empty bake passes vacuously.
--
-- D-13: the config is a PARAMETER and never an import. A missing field is a loud error, not a default.
local MapContract = require("./MapContract")
local Obb = require("./Obb")

type Vec3 = MapContract.Vec3
type Aabb = MapContract.Aabb
type Box = Obb.Box

export type Counters = {
	boxes: number,
	columns: number,
	spans: number,
	cells: number,
	reached: number,
	linkTests: number,
	eroded: number,
}

export type Grid = {
	gridSize: number,
	originX: number,
	originZ: number,
	nx: number,
	nz: number,
	colFirst: { number },
	colCount: { number },
	colOf: { number },
	cellX: { number },
	cellZ: { number },
	cellH: { number },
	cellCeil: { number },
	region: { number },
	counters: Counters,
}

export type GridConfig = {
	GRID_SIZE: number,
	STEP_UP: number,
	MAX_SLOPE_DEGREES: number,
	CAPSULE_RADIUS: number,
	CAPSULE_HEIGHT: number,
}

local GEOM_EPSILON = Obb.GEOM_EPSILON
local TOP_TIE = 1e-9
local BODY_MARGIN = 0.25

local abs = math.abs
local min = math.min
local max = math.max
local sqrt = math.sqrt
local floor = math.floor
local ceil = math.ceil
local huge = math.huge

local CONFIG_KEYS = { "GRID_SIZE", "STEP_UP", "MAX_SLOPE_DEGREES", "CAPSULE_RADIUS", "CAPSULE_HEIGHT" }

local function checkConfig(config: GridConfig)
	for _, key in CONFIG_KEYS do
		local value = (config :: any)[key]
		if type(value) ~= "number" or value ~= value or value == huge or value == -huge then
			error(`WalkGrid: config.{key} is missing or not a finite number (D-13: no silent default)`, 0)
		end
	end
	if config.GRID_SIZE <= 0 then
		error("WalkGrid: config.GRID_SIZE must be positive", 0)
	end
end

local function finite(value: number): boolean
	return value == value and value ~= huge and value ~= -huge
end

local function latticeSize(bounds: Aabb, gridSize: number): (number, number, number, number)
	local lowest = bounds.min
	local highest = bounds.max
	if
		not (
			finite(lowest.x)
			and finite(lowest.z)
			and finite(highest.x)
			and finite(highest.z)
			and finite(lowest.y)
			and finite(highest.y)
		)
	then
		error("WalkGrid: bounds must be finite", 0)
	end
	local originX = math.floor(bounds.min.x / gridSize) * gridSize
	local originZ = math.floor(bounds.min.z / gridSize) * gridSize
	local nx = max(1, ceil((highest.x - originX) / gridSize))
	local nz = max(1, ceil((highest.z - originZ) / gridSize))
	return originX, originZ, nx, nz
end

-- Cheap and allocation-free: the bake-size ceiling in plan 03-05 calls this BEFORE building anything.
local function columnCountFor(bounds: Aabb, gridSize: number): number
	if type(gridSize) ~= "number" or not (gridSize > 0) or not finite(gridSize) then
		error("WalkGrid.columnCountFor: gridSize must be a positive finite number", 0)
	end
	local _, _, nx, nz = latticeSize(bounds, gridSize)
	return nx * nz
end

local function build(boxes: { Box }, bounds: Aabb, config: GridConfig, index: Obb.Index): Grid
	checkConfig(config)
	local gridSize = config.GRID_SIZE
	local stepUp = config.STEP_UP
	local capRadius = config.CAPSULE_RADIUS
	local capHeight = config.CAPSULE_HEIGHT
	local originX, originZ, nx, nz = latticeSize(bounds, gridSize)
	local total = nx * nz
	local cosine = math.cos(math.rad(config.MAX_SLOPE_DEGREES)) - 1e-4
	local tanSlope = math.tan(math.rad(config.MAX_SLOPE_DEGREES))
	local boundsMinX, boundsMaxX = bounds.min.x, bounds.max.x
	local boundsMinZ, boundsMaxZ = bounds.min.z, bounds.max.z
	local boundsMinY, boundsMaxY = bounds.min.y, bounds.max.y

	-- Pass 1: per column, the merged solid spans. Flat arrays; column idx owns spans
	-- spanFirst[idx] .. spanFirst[idx] + spanCount[idx] - 1, ascending.
	local spanFirst: { number } = table.create(total, 0)
	local spanCount: { number } = table.create(total, 0)
	local spanLo: { number } = {}
	local spanHi: { number } = {}
	local spanOk: { boolean } = {}
	local spanTotal = 0

	local near: { number } = {}
	local ivLo: { number } = {}
	local ivHi: { number } = {}
	local ivOk: { boolean } = {}

	for j = 0, nz - 1 do
		local centreZ = originZ + (j + 0.5) * gridSize
		for i = 0, nx - 1 do
			local centreX = originX + (i + 0.5) * gridSize
			local idx = j * nx + i + 1
			local found = Obb.queryIndex(index, centreX, centreZ, centreX, centreZ, near)
			local n = 0
			for q = 1, found do
				local box = boxes[near[q]]
				local lo, hi, ny = Obb.columnSpan(box, centreX, centreZ)
				if lo ~= nil and hi ~= nil then
					n += 1
					-- Insertion sort by lo. Columns hold a handful of intervals, so this beats table.sort and is
					-- deterministic; a column with a single interval never enters the loop.
					local at = n
					while at > 1 and ivLo[at - 1] > lo do
						ivLo[at] = ivLo[at - 1]
						ivHi[at] = ivHi[at - 1]
						ivOk[at] = ivOk[at - 1]
						at -= 1
					end
					ivLo[at] = lo
					ivHi[at] = hi
					ivOk[at] = box.standable and ny >= cosine
				end
			end
			spanFirst[idx] = spanTotal + 1
			local count = 0
			if n > 0 then
				local curLo, curHi, curOk = ivLo[1], ivHi[1], ivOk[1]
				for q = 2, n do
					local lo, hi = ivLo[q], ivHi[q]
					if lo <= curHi + GEOM_EPSILON then
						if hi > curHi + TOP_TIE then
							curHi, curOk = hi, ivOk[q]
						elseif hi >= curHi - TOP_TIE and ivOk[q] then
							curOk = true
						end
					else
						spanTotal += 1
						count += 1
						spanLo[spanTotal], spanHi[spanTotal], spanOk[spanTotal] = curLo, curHi, curOk
						curLo, curHi, curOk = lo, hi, ivOk[q]
					end
				end
				spanTotal += 1
				count += 1
				spanLo[spanTotal], spanHi[spanTotal], spanOk[spanTotal] = curLo, curHi, curOk
			end
			spanCount[idx] = count
		end
	end

	-- Erosion window: neighbour columns whose centre lies within CAPSULE_RADIUS, each with its slope allowance.
	local reach = floor(capRadius / gridSize + 1e-9)
	local offDi: { number } = {}
	local offDj: { number } = {}
	local offAllow: { number } = {}
	for dj = -reach, reach do
		for di = -reach, reach do
			if di ~= 0 or dj ~= 0 then
				local distance = sqrt(di * di + dj * dj) * gridSize
				if distance <= capRadius + 1e-9 then
					local k = #offDi + 1
					offDi[k], offDj[k], offAllow[k] = di, dj, distance * tanSlope
				end
			end
		end
	end
	local offsetCount = #offDi

	-- Pass 2: floor candidates, headroom, erosion, bounds; fill the flat cell arrays column-major.
	local colFirst: { number } = table.create(total, 0)
	local colCount: { number } = table.create(total, 0)
	local colOf: { number } = {}
	local cellX: { number } = {}
	local cellZ: { number } = {}
	local cellH: { number } = {}
	local cellCeil: { number } = {}
	local cellTotal = 0
	local eroded = 0

	for j = 0, nz - 1 do
		local centreZ = originZ + (j + 0.5) * gridSize
		local zInside = centreZ >= boundsMinZ and centreZ <= boundsMaxZ
		for i = 0, nx - 1 do
			local centreX = originX + (i + 0.5) * gridSize
			local idx = j * nx + i + 1
			colFirst[idx] = cellTotal + 1
			local first = spanFirst[idx]
			local last = first + spanCount[idx] - 1
			if zInside and centreX >= boundsMinX and centreX <= boundsMaxX then
				for s = first, last do
					if spanOk[s] then
						local top = spanHi[s]
						local ceiling = if s < last then spanLo[s + 1] else boundsMaxY
						if top >= boundsMinY and top <= boundsMaxY and ceiling - top >= capHeight then
							local blocked = false
							for k = 1, offsetCount do
								local ni, nj = i + offDi[k], j + offDj[k]
								if ni >= 0 and ni < nx and nj >= 0 and nj < nz then
									local nidx = nj * nx + ni + 1
									local limit = top + stepUp + offAllow[k]
									local headTop = top + capHeight
									local nfirst = spanFirst[nidx]
									for s2 = nfirst, nfirst + spanCount[nidx] - 1 do
										if spanHi[s2] > limit and spanLo[s2] < headTop then
											blocked = true
											break
										end
									end
									if blocked then
										break
									end
								end
							end
							-- Only obstructions above STEP_UP erode. Nothing erodes away from a drop-off.
							if blocked then
								eroded += 1
							else
								cellTotal += 1
								colOf[cellTotal] = idx
								cellX[cellTotal] = centreX
								cellZ[cellTotal] = centreZ
								cellH[cellTotal] = top
								cellCeil[cellTotal] = ceiling
							end
						end
					end
				end
			end
			colCount[idx] = cellTotal + 1 - colFirst[idx]
		end
	end

	return {
		gridSize = gridSize,
		originX = originX,
		originZ = originZ,
		nx = nx,
		nz = nz,
		colFirst = colFirst,
		colCount = colCount,
		colOf = colOf,
		cellX = cellX,
		cellZ = cellZ,
		cellH = cellH,
		cellCeil = cellCeil,
		region = table.create(cellTotal, 0),
		counters = {
			boxes = #boxes,
			columns = total,
			spans = spanTotal,
			cells = cellTotal,
			reached = 0,
			linkTests = 0,
			eroded = eroded,
		},
	}
end

-- Iterative breadth-first fill. One array queue, two integer cursors, no recursion: Luau has a call-depth limit
-- and a long corridor exceeds it. Seeds are cell indices; region[c] = 1 marks a cell reached from any of them.
local function flood(grid: Grid, boxes: { Box }, index: Obb.Index, seeds: { number }, config: GridConfig)
	checkConfig(config)
	local stepUp = config.STEP_UP
	local capHeight = config.CAPSULE_HEIGHT
	local nx, nz = grid.nx, grid.nz
	local colFirst, colCount, colOf = grid.colFirst, grid.colCount, grid.colOf
	local cellX, cellZ, cellH, cellCeil = grid.cellX, grid.cellZ, grid.cellH, grid.cellCeil
	local region = grid.region
	local counters = grid.counters
	local cellTotal = #cellH
	local lowBody = stepUp + BODY_MARGIN
	local highBody = capHeight - BODY_MARGIN
	local segmentHits = Obb.segmentHits
	local queryIndex = Obb.queryIndex

	for c = 1, cellTotal do
		region[c] = 0
	end
	local reached = 0
	local linkTests = 0

	local queue: { number } = table.create(cellTotal, 0)
	local near: { number } = {}
	local head, tail = 1, 0
	for n = 1, #seeds do
		local s = seeds[n]
		if type(s) ~= "number" or s < 1 or s > cellTotal or s ~= floor(s) then
			error(`WalkGrid: seed {tostring(s)} is not a cell index in this grid`, 0)
		end
		if region[s] == 0 then
			region[s] = 1
			reached += 1
			tail += 1
			queue[tail] = s
		end
	end

	local stepI = { 1, -1, 0, 0 }
	local stepJ = { 0, 0, 1, -1 }
	while head <= tail do
		local c = queue[head]
		head += 1
		local col = colOf[c] - 1
		local ci = col % nx
		local cj = col // nx
		local hc, ceilC = cellH[c], cellCeil[c]
		local ax, az = cellX[c], cellZ[c]
		for dir = 1, 4 do
			local ni, nj = ci + stepI[dir], cj + stepJ[dir]
			if ni >= 0 and ni < nx and nj >= 0 and nj < nz then
				local nidx = nj * nx + ni + 1
				local first = colFirst[nidx]
				for n = first, first + colCount[nidx] - 1 do
					if region[n] == 0 then
						local hn = cellH[n]
						-- 1. height difference, 2. shared headroom, 3. exact segment at two body heights.
						if abs(hn - hc) <= stepUp then
							local top = max(hc, hn)
							if min(ceilC, cellCeil[n]) - top >= capHeight then
								linkTests += 1
								local bx, bz = cellX[n], cellZ[n]
								local found =
									queryIndex(index, min(ax, bx), min(az, bz), max(ax, bx), max(az, bz), near)
								local clear = true
								local yLow, yHigh = top + lowBody, top + highBody
								for q = 1, found do
									local box = boxes[near[q]]
									if
										segmentHits(box, ax, yLow, az, bx, yLow, bz, GEOM_EPSILON)
										or segmentHits(box, ax, yHigh, az, bx, yHigh, bz, GEOM_EPSILON)
									then
										clear = false
										break
									end
								end
								if clear then
									region[n] = 1
									reached += 1
									tail += 1
									queue[tail] = n
								end
							end
						end
					end
				end
			end
		end
	end
	counters.reached = reached
	counters.linkTests = linkTests
end

local function columnIndexOf(grid: Grid, x: number, z: number): number?
	local i = floor((x - grid.originX) / grid.gridSize)
	local j = floor((z - grid.originZ) / grid.gridSize)
	-- Positive comparisons so a NaN coordinate falls through to nil.
	if i >= 0 and i < grid.nx and j >= 0 and j < grid.nz then
		return j * grid.nx + i + 1
	end
	return nil
end

-- Pitfall 10: if no spawn finds a cell the BFS runs on an empty queue and reports 0 reached, and every spot then
-- fails with a misleading reason. An empty return here is the signal, and it must never be treated as "flood
-- everything". Cells at or below the point and no more than dropLimit below it, nearest (highest) first.
local function seedsAt(grid: Grid, point: Vec3, dropLimit: number): { number }
	local out: { number } = {}
	local idx = columnIndexOf(grid, point.x, point.z)
	if idx == nil then
		return out
	end
	local first = grid.colFirst[idx]
	for c = first + grid.colCount[idx] - 1, first, -1 do
		local h = grid.cellH[c]
		if h <= point.y and point.y - h <= dropLimit then
			out[#out + 1] = c
		end
	end
	return out
end

-- Appends the index of every cell in every column whose centre lies within `radius` horizontally into `out`
-- (from index 1) and returns the count. Allocates nothing per call.
local function cellsNear(grid: Grid, x: number, z: number, radius: number, out: { number }): number
	local size = grid.gridSize
	local i0 = max(0, floor((x - radius - grid.originX) / size))
	local i1 = min(grid.nx - 1, floor((x + radius - grid.originX) / size))
	local j0 = max(0, floor((z - radius - grid.originZ) / size))
	local j1 = min(grid.nz - 1, floor((z + radius - grid.originZ) / size))
	local limit = radius * radius
	local count = 0
	for j = j0, j1 do
		local dz = grid.originZ + (j + 0.5) * size - z
		for i = i0, i1 do
			local dx = grid.originX + (i + 0.5) * size - x
			if dx * dx + dz * dz <= limit then
				local idx = j * grid.nx + i + 1
				local first = grid.colFirst[idx]
				for c = first, first + grid.colCount[idx] - 1 do
					count += 1
					out[count] = c
				end
			end
		end
	end
	return count
end

return {
	columnCountFor = columnCountFor,
	build = build,
	flood = flood,
	seedsAt = seedsAt,
	columnIndexOf = columnIndexOf,
	cellsNear = cellsNear,
}
