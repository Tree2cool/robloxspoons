--!strict
-- Exact oriented-box geometry for the placement rules (plan 03-03, HIDE-06).
--
-- PURE ZONE: plain data in, plain data out, no Roblox API, no clock, no yields (CLAUDE.md rules 2, 5, 6).
-- The world is oriented boxes only, so the slab method and a closest-point formula are sufficient; no general
-- convex collision code (SAT, GJK, polygon clipping) belongs here.
--
-- ACCEPTED LIMITATION (D-01): this is our model of collision, not Roblox's. Boxes are exact; meshes, CSG and
-- non-collidable parts are only as correct as the snapshot makes them. Phase 5 runs the real hunt in real
-- geometry and is where any divergence will first be observable. One implementation serves CI and runtime.
--
-- NAMING CONVENTION. check-guards R3 bans the substring "o" followed by "s" and a dot anywhere in a pure-zone
-- file, and the ban reaches INSIDE string literals (only comments are stripped). So point and vector locals are
-- p, q, a, b, pt, at, centre, origin, delta, axis, normal, corner. Never the three-letter words for a
-- position, a cosine or a line of sight; write the full word "position", and name a cosine `cosine` and a sine
-- `sine`. No message may end a sentence with a word that ends in that two-letter pair.
--
-- BASIS (D-02). axis[1] = right = look x up, axis[2] = up, axis[3] = look; h = size / 2. Verified against the
-- committed graybox Ramp: CFrame.Angles(0, 0, -atan(6.5 / 14)) gives look = (0, 0, -1) and
-- up = (0.42111206, 0.90701294, 0); look x up = (0.90701294, -0.42111206, 0), exactly the part's RightVector as
-- measured under Lune 0.11.1. acos(0.90701294) = 24.90 degrees, the true ramp angle. A roll about the look axis
-- is invisible without `up`, which is why the map contract went to v2.
--
-- EPSILON. GEOM_EPSILON is a LENGTH tolerance in studs, distinct from MapValidator's angular LOOK_EPSILON.
-- Acceptance comparisons shave it, rejection comparisons add it, so every borderline outcome falls on the
-- rejecting side (D-11). The 1e-12 guard on a direction component is a divide-by-zero guard, not a tolerance.
local MapContract = require("./MapContract")

type Vec3 = MapContract.Vec3

export type Box = {
	name: string,
	cx: number,
	cy: number,
	cz: number,
	ax: { number }, -- ax[k] = x component of axis k
	ay: { number }, -- ay[k] = y component of axis k
	az: { number }, -- az[k] = z component of axis k
	h: { number },
	minx: number,
	miny: number,
	minz: number,
	maxx: number,
	maxy: number,
	maxz: number,
	standable: boolean, -- true only for a block-shaped collidable Part (research assumption A4)
}

export type Index = {
	cellSize: number,
	minx: number,
	minz: number,
	nx: number,
	nz: number,
	buckets: { { number } }, -- bucket[j * nx + i + 1] = list of box indices overlapping that bucket
	boxes: { Box },
	stamp: { number }, -- stamp[boxIndex] == queryId marks a box already emitted by the current query
	queryId: number,
}

local GEOM_EPSILON = 1e-3
local PARALLEL_GUARD = 1e-12

local abs = math.abs
local sqrt = math.sqrt
local max = math.max
local min = math.min
local floor = math.floor

-- Deliberately does NOT normalise look or up. A non-orthonormal input is a contract violation that
-- MapValidator reports as MAP_NODE_BASIS_INVALID; silently repairing it here would hide a malformed map.
local function fromPose(name: string, centre: Vec3, size: Vec3, look: Vec3, up: Vec3, standable: boolean): Box
	local rx = look.y * up.z - look.z * up.y
	local ry = look.z * up.x - look.x * up.z
	local rz = look.x * up.y - look.y * up.x
	local ax = { rx, up.x, look.x }
	local ay = { ry, up.y, look.y }
	local az = { rz, up.z, look.z }
	local h = { size.x / 2, size.y / 2, size.z / 2 }
	local hx, hy, hz = 0, 0, 0
	for k = 1, 3 do
		hx += abs(ax[k]) * h[k]
		hy += abs(ay[k]) * h[k]
		hz += abs(az[k]) * h[k]
	end
	return {
		name = name,
		cx = centre.x,
		cy = centre.y,
		cz = centre.z,
		ax = ax,
		ay = ay,
		az = az,
		h = h,
		minx = centre.x - hx,
		miny = centre.y - hy,
		minz = centre.z - hz,
		maxx = centre.x + hx,
		maxy = centre.y + hy,
		maxz = centre.z + hz,
		standable = standable,
	}
end

local function isOrthonormal(look: Vec3, up: Vec3, epsilon: number): boolean
	local lookLen = sqrt(look.x * look.x + look.y * look.y + look.z * look.z)
	local upLen = sqrt(up.x * up.x + up.y * up.y + up.z * up.z)
	local dot = look.x * up.x + look.y * up.y + look.z * up.z
	return abs(lookLen - 1) <= epsilon and abs(upLen - 1) <= epsilon and abs(dot) <= epsilon
end

-- Closest-point formula in box-local axes. Exactly 0 when the point is inside.
local function distanceToPoint(box: Box, x: number, y: number, z: number): number
	local dx, dy, dz = x - box.cx, y - box.cy, z - box.cz
	local total = 0
	for k = 1, 3 do
		local projection = dx * box.ax[k] + dy * box.ay[k] + dz * box.az[k]
		local excess = abs(projection) - box.h[k]
		if excess > 0 then
			total += excess * excess
		end
	end
	return sqrt(total)
end

-- Kay-Kajiya slab test. inflate = GEOM_EPSILON makes grazing contact count as blocked. A segment that starts or
-- ends inside the box is a hit (t0 stays 0); that is safe for line of sight only because the Solid rule runs
-- earlier in the locked order (D-12), so the spot is proven outside every solid before a sight segment is cast.
-- A zero-length segment goes through the parallel branch on all three axes and is a point test.
local function segmentHits(
	box: Box,
	px: number,
	py: number,
	pz: number,
	qx: number,
	qy: number,
	qz: number,
	inflate: number
): boolean
	if max(px, qx) < box.minx - inflate or min(px, qx) > box.maxx + inflate then
		return false
	end
	if max(py, qy) < box.miny - inflate or min(py, qy) > box.maxy + inflate then
		return false
	end
	if max(pz, qz) < box.minz - inflate or min(pz, qz) > box.maxz + inflate then
		return false
	end
	local dx, dy, dz = qx - px, qy - py, qz - pz
	local ox, oy, oz = px - box.cx, py - box.cy, pz - box.cz
	local t0, t1 = 0, 1
	for k = 1, 3 do
		local o = ox * box.ax[k] + oy * box.ay[k] + oz * box.az[k]
		local d = dx * box.ax[k] + dy * box.ay[k] + dz * box.az[k]
		local h = box.h[k] + inflate
		if abs(d) < PARALLEL_GUARD then
			-- Dividing by zero yields inf, and 0 * inf = NaN, which compares false everywhere and would
			-- silently report no hit. Parallel to the slab: hit only if the origin is inside it.
			if abs(o) > h then
				return false
			end
		else
			local ta, tb = (-h - o) / d, (h - o) / d
			if ta > tb then
				ta, tb = tb, ta
			end
			if ta > t0 then
				t0 = ta
			end
			if tb < t1 then
				t1 = tb
			end
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

-- Vertical line (x, z) against one box. Returns lo, hi (world Y of entry and exit) and nyTop, the Y component of
-- the outward normal at the top exit. The normal comes from the exact face, so the ramp's 24.9047 degrees is
-- independent of grid resolution, and the ramp's high-end face (about 65 degrees off vertical) is correctly
-- rejected as a floor. Never compute slope from height differences between grid cells.
local function columnSpan(box: Box, x: number, z: number): (number?, number?, number)
	local tlo, thi, nyTop = -math.huge, math.huge, 0
	local dx, dz = x - box.cx, z - box.cz
	for k = 1, 3 do
		local a = dx * box.ax[k] + dz * box.az[k]
		local bb = box.ay[k]
		local h = box.h[k]
		if abs(bb) < 1e-9 then
			-- Axis is horizontal: the line is either always inside this slab or never.
			if abs(a) > h then
				return nil, nil, 0
			end
		else
			local t1, t2 = (-h - a) / bb, (h - a) / bb
			local tmin, tmax, sign
			if t1 < t2 then
				tmin, tmax, sign = t1, t2, 1
			else
				tmin, tmax, sign = t2, t1, -1
			end
			if tmin > tlo then
				tlo = tmin
			end
			if tmax < thi then
				thi = tmax
				nyTop = sign * bb -- outward normal Y at the TOP exit
			end
		end
	end
	if thi - tlo < 1e-6 then
		return nil, nil, 0
	end
	return box.cy + tlo, box.cy + thi, nyTop
end

local function newIndex(boxes: { Box }, cellSize: number): Index
	local count = #boxes
	local lowx, lowz, highx, highz = 0, 0, 0, 0
	if count > 0 then
		lowx, lowz, highx, highz = math.huge, math.huge, -math.huge, -math.huge
		for i = 1, count do
			local box = boxes[i]
			lowx = min(lowx, box.minx)
			lowz = min(lowz, box.minz)
			highx = max(highx, box.maxx)
			highz = max(highz, box.maxz)
		end
	end
	local nx = max(1, floor((highx - lowx) / cellSize) + 1)
	local nz = max(1, floor((highz - lowz) / cellSize) + 1)
	local buckets: { { number } } = table.create(nx * nz)
	for n = 1, nx * nz do
		buckets[n] = {}
	end
	for i = 1, count do
		local box = boxes[i]
		local i0 = floor((box.minx - lowx) / cellSize)
		local i1 = floor((box.maxx - lowx) / cellSize)
		local j0 = floor((box.minz - lowz) / cellSize)
		local j1 = floor((box.maxz - lowz) / cellSize)
		for j = j0, j1 do
			for c = i0, i1 do
				local list = buckets[j * nx + c + 1]
				list[#list + 1] = i
			end
		end
	end
	local stamp: { number } = table.create(count, 0)
	return {
		cellSize = cellSize,
		minx = lowx,
		minz = lowz,
		nx = nx,
		nz = nz,
		buckets = buckets,
		boxes = boxes,
		stamp = stamp,
		queryId = 0,
	}
end

-- Appends the deduplicated indices of boxes whose bucket range overlaps the rectangle into `out` and returns the
-- count. Bucket granularity means a returned box may sit in an overlapped bucket without touching the rectangle
-- itself; callers still run their exact test. Allocates nothing per query.
local function queryIndex(index: Index, minx: number, minz: number, maxx: number, maxz: number, out: { number }): number
	local size = index.cellSize
	local i0 = max(0, floor((minx - index.minx) / size))
	local i1 = min(index.nx - 1, floor((maxx - index.minx) / size))
	local j0 = max(0, floor((minz - index.minz) / size))
	local j1 = min(index.nz - 1, floor((maxz - index.minz) / size))
	index.queryId += 1
	local queryId = index.queryId
	local stamp = index.stamp
	local count = 0
	for j = j0, j1 do
		for i = i0, i1 do
			local list = index.buckets[j * index.nx + i + 1]
			for n = 1, #list do
				local boxIndex = list[n]
				if stamp[boxIndex] ~= queryId then
					stamp[boxIndex] = queryId
					count += 1
					out[count] = boxIndex
				end
			end
		end
	end
	return count
end

return {
	GEOM_EPSILON = GEOM_EPSILON,
	fromPose = fromPose,
	isOrthonormal = isOrthonormal,
	distanceToPoint = distanceToPoint,
	segmentHits = segmentHits,
	columnSpan = columnSpan,
	newIndex = newIndex,
	queryIndex = queryIndex,
}
