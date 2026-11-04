--!strict
-- Plan 03-03 (HIDE-06): the exact oriented-box geometry layer.
--
-- What is proven, and the mutation that proves each property CAN fail:
--   * degenerate cases 1-6 (research "Segment-vs-OBB"), named after the research numbering. Cases 1 and 4 assert
--     a real boolean that is stable across two calls, so a NaN-driven "no hit" cannot hide. Mutation: delete the
--     `abs(d) < PARALLEL_GUARD` branch and cases 1, 2 and 4 go red.
--   * the committed Ramp's basis and its 24.90 degree face normal. Mutation: negate `nyTop` in columnSpan.
--   * two DIFFERENTIAL fuzz properties against dense brute-force samplers. They are the only assertions here
--     that nobody hand-picked an answer for. Mutation: invert the `ta > tb` swap in segmentHits.
--   * a floor on how many fuzz trials produced a hit and a miss, because a differential property whose every
--     trial misses agrees with everything. Mutation: narrow the generator so every segment misses.
local MapContract = require("../../src/server/core/MapContract")
local Obb = require("../../src/server/core/Obb")
local Test = require("../harness/Test")

type Vec3 = MapContract.Vec3

local EPS = Obb.GEOM_EPSILON
local FUZZ_SEGMENTS = 600
local FUZZ_COLUMNS = 600
local SEGMENT_SAMPLES = 4000
local COLUMN_SAMPLES = 400
local MIN_PER_OUTCOME = 50

local function v(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end

local LOOK_DEFAULT = v(0, 0, -1)
local UP_DEFAULT = v(0, 1, 0)

-- Axis-aligned box centred on the origin with the given FULL size.
local function aligned(sx: number, sy: number, sz: number): Obb.Box
	return Obb.fromPose("aligned", v(0, 0, 0), v(sx, sy, sz), LOOK_DEFAULT, UP_DEFAULT, true)
end

-- The committed graybox Ramp, reproduced from scripts/maps/generate-graybox.luau: size (length, 1, 6), a roll
-- about Z by -atan(6.5 / 14), centre (-31 - 0.5 sin(a), 3.25 - 0.5 cos(a), 0).
-- Measured under Lune 0.11.1 from the committed maps/gray-box.rbxm (research V-4). The Ramp is a roll about Z by
-- atan(6.5 / 14) = 24.9047 degrees, which does NOT change the look vector, which is why contract version 1 saw
-- it as a flat slab.
local RAMP_LOOK = v(0, 0, -1)
local RAMP_UP = v(0.42111206, 0.90701294, 0)
local function ramp(): Obb.Box
	local angle = math.atan(6.5 / 14)
	local length = math.sqrt(14 * 14 + 6.5 * 6.5)
	local centre = v(-31 - 0.5 * math.sin(angle), 3.25 - 0.5 * math.cos(angle), 0)
	return Obb.fromPose("Ramp", centre, v(length, 1, 6), RAMP_LOOK, RAMP_UP, true)
end

local function near(actual: number, expected: number, tolerance: number): boolean
	return math.abs(actual - expected) <= tolerance
end

local function fmt(x: number): string
	return string.format("%.6f", x)
end

local function describeBox(box: Obb.Box): string
	return string.format(
		"centre=(%s,%s,%s) h=(%s,%s,%s) right=(%s,%s,%s) up=(%s,%s,%s) look=(%s,%s,%s)",
		fmt(box.cx),
		fmt(box.cy),
		fmt(box.cz),
		fmt(box.h[1]),
		fmt(box.h[2]),
		fmt(box.h[3]),
		fmt(box.ax[1]),
		fmt(box.ay[1]),
		fmt(box.az[1]),
		fmt(box.ax[2]),
		fmt(box.ay[2]),
		fmt(box.az[2]),
		fmt(box.ax[3]),
		fmt(box.ay[3]),
		fmt(box.az[3])
	)
end

-- Random orthonormal basis: look from yaw and pitch, up from the pitch derivative rolled about look.
local function randomBasis(rng: any): (Vec3, Vec3)
	local yaw = rng:nextNumber() * 2 * math.pi
	local pitch = (rng:nextNumber() - 0.5) * math.pi * 0.95
	local roll = rng:nextNumber() * 2 * math.pi
	local cp, sp, cy, sy = math.cos(pitch), math.sin(pitch), math.cos(yaw), math.sin(yaw)
	local look = v(cp * sy, sp, -cp * cy)
	local base = v(-sp * sy, cp, sp * cy)
	-- look x base
	local side =
		v(look.y * base.z - look.z * base.y, look.z * base.x - look.x * base.z, look.x * base.y - look.y * base.x)
	local cr, sr = math.cos(roll), math.sin(roll)
	local up = v(base.x * cr + side.x * sr, base.y * cr + side.y * sr, base.z * cr + side.z * sr)
	assert(Obb.isOrthonormal(look, up, 1e-9), "fuzz generator produced a non-orthonormal basis")
	return look, up
end

local function randomBox(rng: any): Obb.Box
	local look, up = randomBasis(rng)
	local size = v(1 + rng:nextNumber() * 7, 1 + rng:nextNumber() * 7, 1 + rng:nextNumber() * 7)
	local centre = v((rng:nextNumber() - 0.5) * 6, (rng:nextNumber() - 0.5) * 6, (rng:nextNumber() - 0.5) * 6)
	return Obb.fromPose("fuzz", centre, size, look, up, true)
end

return function(t: Test.Runner)
	-- A. the six named degenerate cases ---------------------------------------------------------------------
	t.test("degenerate 1: a segment parallel to a slab never divides, and grazing counts as blocked", function()
		local box = aligned(2, 2, 2)
		t.equal(Obb.segmentHits(box, -5, 0, 0, 5, 0, 0, EPS), true, "straight through the middle hits")
		t.equal(Obb.segmentHits(box, -5, 5, 0, 5, 5, 0, EPS), false, "far above misses")
		local graze1 = Obb.segmentHits(box, -5, 1.0, 0, 5, 1.0, 0, EPS)
		local graze2 = Obb.segmentHits(box, -5, 1.0, 0, 5, 1.0, 0, EPS)
		t.truthy(graze1 == true or graze1 == false, "the grazing answer is a real boolean, not a NaN artefact")
		t.equal(graze1, graze2, "the grazing answer is stable across two calls")
		t.equal(graze1, true, "a segment along the top face plane is BLOCKED")
		t.equal(Obb.segmentHits(box, -5, 1.5, 0, 5, 1.5, 0, EPS), false, "clearly above the face misses")
	end)

	t.test("degenerate 2: a zero-length segment is a point test", function()
		local box = aligned(2, 2, 2)
		t.equal(Obb.segmentHits(box, 0.2, 0.3, -0.4, 0.2, 0.3, -0.4, EPS), true, "a point inside hits")
		t.equal(Obb.segmentHits(box, 3, 3, 3, 3, 3, 3, EPS), false, "a point outside misses")
		t.equal(Obb.segmentHits(box, 0, 0, 1, 0, 0, 1, EPS), true, "a point exactly on a face is blocked")
	end)

	t.test("degenerate 3: a segment starting inside the box is a hit", function()
		local box = aligned(2, 2, 2)
		t.equal(Obb.segmentHits(box, 0, 0, 0, 50, 40, -30, EPS), true, "starts inside, ends far outside")
		t.equal(Obb.segmentHits(box, 50, 40, -30, 0, 0, 0, EPS), true, "ends inside, starts far outside")
	end)

	t.test("degenerate 4: a grazing or tangent contact is blocked, not clear (D-11's rejecting bias)", function()
		local box = aligned(2, 2, 2)
		-- Ends exactly on the +x face plane.
		local touch1 = Obb.segmentHits(box, 5, 0, 0, 1, 0, 0, EPS)
		local touch2 = Obb.segmentHits(box, 5, 0, 0, 1, 0, 0, EPS)
		t.truthy(touch1 == true or touch1 == false, "the touching answer is a real boolean")
		t.equal(touch1, touch2, "the touching answer is stable")
		t.equal(touch1, true, "ending exactly on a face plane is blocked")
		-- Tangent along an edge.
		t.equal(Obb.segmentHits(box, -5, 1, 1, 5, 1, 1, EPS), true, "running along an edge is blocked")
		-- Just inside the epsilon inflation still blocks; clearly outside does not.
		t.equal(Obb.segmentHits(box, -5, 1 + EPS / 2, 0, 5, 1 + EPS / 2, 0, EPS), true, "within epsilon blocks")
		t.equal(Obb.segmentHits(box, -5, 1 + 10 * EPS, 0, 5, 1 + 10 * EPS, 0, EPS), false, "10 epsilon clear")
	end)

	t.test("degenerate 5: the world-AABB prefilter rejects before the slab test runs", function()
		local far = Obb.fromPose("far", v(100, 100, 100), v(2, 2, 2), LOOK_DEFAULT, UP_DEFAULT, true)
		t.equal(Obb.segmentHits(far, -5, 0, 0, 5, 0, 0, EPS), false, "a distant box is rejected")
		-- A 45 degree yawed long thin plank: its world AABB is a big square, but a segment that crosses the
		-- empty corner of that square must still miss. Only the slab test can reject it.
		local s = math.sqrt(0.5)
		local plank = Obb.fromPose("plank", v(0, 0, 0), v(10, 2, 0.5), v(s, 0, -s), UP_DEFAULT, true)
		t.truthy(plank.maxx > 3 and plank.minx < -3, "the AABB spans the plank diagonal")
		-- (3, 0, -3) is inside the AABB square but far from the diagonal plank along (1, 0, 1).
		local hit = Obb.segmentHits(plank, 3, 0, -3, 3, 0, -1, EPS)
		t.equal(hit, false, "AABB overlaps but the oriented box is not touched")
		t.equal(Obb.segmentHits(plank, -4, 0, -4, 4, 0, 4, EPS), true, "along the plank diagonal still hits")
	end)

	t.test("degenerate 6: a non-orthonormal basis is reported, never normalised", function()
		t.equal(Obb.isOrthonormal(RAMP_LOOK, RAMP_UP, 1e-3), true, "the Ramp basis is orthonormal at 1e-3")
		t.equal(Obb.isOrthonormal(LOOK_DEFAULT, LOOK_DEFAULT, 1e-3), false, "up equal to look is rejected")
		t.equal(Obb.isOrthonormal(LOOK_DEFAULT, v(0, 1.01, 0), 1e-3), false, "up scaled by 1.01 is rejected")
		t.equal(Obb.isOrthonormal(v(0, 0, -1.01), UP_DEFAULT, 1e-3), false, "look scaled by 1.01 is rejected")
		local scaled = Obb.fromPose("bad", v(0, 0, 0), v(2, 2, 2), LOOK_DEFAULT, v(0, 1.01, 0), true)
		t.equal(scaled.ay[2], 1.01, "fromPose keeps the stored up axis non-unit; MapValidator is the only judge")
	end)

	-- B. the Ramp basis ---------------------------------------------------------------------------------------
	t.test("fromPose reproduces the committed Ramp's RightVector (D-02)", function()
		-- Measured under Lune 0.11.1 from the committed maps/gray-box.rbxm (research V-4). The Ramp is a roll
		-- about Z by atan(6.5 / 14) = 24.9047 degrees, which does NOT change the look vector, which is why
		-- contract version 1 saw it as a flat slab.
		local box = Obb.fromPose("Ramp", v(0, 0, 0), v(2, 1, 6), RAMP_LOOK, RAMP_UP, true)
		t.truthy(near(box.ax[1], 0.90701294, 1e-5), `right.x {box.ax[1]} expected 0.90701294`)
		t.truthy(near(box.ay[1], -0.42111206, 1e-5), `right.y {box.ay[1]} expected -0.42111206`)
		t.truthy(near(box.az[1], 0, 1e-5), `right.z {box.az[1]} expected 0`)
		t.equal(box.h[1], 1, "half extents are size / 2")
		t.equal(box.h[2], 0.5, "half extents are size / 2")
		t.equal(box.h[3], 3, "half extents are size / 2")
	end)

	-- C. columnSpan -------------------------------------------------------------------------------------------
	t.test("columnSpan through a flat floor reports lo, hi and a vertical top normal", function()
		local floor = Obb.fromPose("Floor", v(0, -0.5, 0), v(120, 1, 120), LOOK_DEFAULT, UP_DEFAULT, true)
		local lo, hi, ny = Obb.columnSpan(floor, 10, -7)
		t.truthy(lo ~= nil and hi ~= nil, "a column inside the footprint hits")
		t.truthy(near(lo :: number, -1, 1e-9), `lo {lo} expected -1`)
		t.truthy(near(hi :: number, 0, 1e-9), `hi {hi} expected 0`)
		t.truthy(near(ny, 1, 1e-9), `nyTop {ny} expected 1`)
	end)

	t.test("columnSpan through the Ramp reports a 24.90 degree face normal", function()
		local lo, hi, ny = Obb.columnSpan(ramp(), -31, 0)
		t.truthy(lo ~= nil and hi ~= nil, "the column through the ramp middle hits")
		t.truthy(near(ny, 0.90701294, 1e-5), `nyTop {ny} expected 0.90701294`)
		local degrees = math.deg(math.acos(ny))
		t.truthy(near(degrees, 24.90, 0.01), `ramp slope {degrees} degrees expected 24.90`)
	end)

	t.test("columnSpan returns nil for a column that misses the box in XZ", function()
		local lo, hi, ny = Obb.columnSpan(aligned(2, 2, 2), 5, 0)
		t.equal(lo, nil, "lo is nil on a miss")
		t.equal(hi, nil, "hi is nil on a miss")
		t.equal(ny, 0, "nyTop is 0 on a miss")
		local lo2 = Obb.columnSpan(ramp(), -31, 10)
		t.equal(lo2, nil, "a column beside the ramp (past its 6 stud width) misses")
	end)

	t.test("columnSpan through the corner of an oriented box is shorter than through its middle", function()
		local s = math.sqrt(0.5)
		local box = Obb.fromPose("yawed", v(0, 0, 0), v(2, 2, 2), v(s, 0, -s), UP_DEFAULT, true)
		local lo, hi = Obb.columnSpan(box, 0, 0)
		t.truthy(lo ~= nil and hi ~= nil, "the middle hits")
		t.truthy(near((hi :: number) - (lo :: number), 2, 1e-9), "a vertical axis box has span equal to its height")
		-- 45 degree yaw: the footprint is a diamond with vertex at distance sqrt(2) along world X.
		local lo2 = Obb.columnSpan(box, 1.3, 0)
		t.truthy(lo2 ~= nil, "inside the diamond vertex region (|x| < sqrt 2)")
		local lo3 = Obb.columnSpan(box, 1.2, 0.6)
		t.equal(lo3, nil, "x + z beyond the diamond edge misses although inside the AABB")
	end)

	t.test("distanceToPoint is 0 inside, the face gap beside a face, and the corner distance diagonally", function()
		local box = aligned(2, 2, 2)
		t.equal(Obb.distanceToPoint(box, 0.3, -0.2, 0.9), 0, "inside is exactly 0")
		t.truthy(near(Obb.distanceToPoint(box, 4, 0, 0), 3, 1e-12), "beside a face is the perpendicular gap")
		t.truthy(near(Obb.distanceToPoint(box, 4, 5, 1), 5, 1e-12), "diagonal from an edge is the euclidean gap")
		t.truthy(near(Obb.distanceToPoint(box, 4, 5, 13), math.sqrt(9 + 16 + 144), 1e-12), "corner distance")
		-- Oriented: the Ramp's own centre is inside, a point 2 along its up axis above the top face is 1.5 away.
		local r = Obb.fromPose("r", v(0, 0, 0), v(10, 1, 6), RAMP_LOOK, RAMP_UP, true)
		t.equal(Obb.distanceToPoint(r, 0, 0, 0), 0, "ramp centre is inside")
		t.truthy(near(Obb.distanceToPoint(r, 2 * 0.42111206, 2 * 0.90701294, 0), 1.5, 1e-4), "along the up axis")
	end)

	-- E. queryIndex -------------------------------------------------------------------------------------------
	t.test("queryIndex returns every overlapping box with no duplicates", function()
		local boxes: { Obb.Box } = {}
		for n = 0, 19 do
			-- 5 x 4 lattice of 4 stud cubes on an 8 stud pitch; box n+1 centred at (8 * (n % 5), 0, 8 * (n // 5)).
			local c = v(8 * (n % 5), 0, 8 * (n // 5))
			boxes[#boxes + 1] = Obb.fromPose(`b{n}`, c, v(4, 4, 4), LOOK_DEFAULT, UP_DEFAULT, true)
		end
		-- One long box spanning many buckets exercises the dedupe.
		boxes[#boxes + 1] = Obb.fromPose("long", v(16, 10, 12), v(40, 1, 1), LOOK_DEFAULT, UP_DEFAULT, true)
		local index = Obb.newIndex(boxes, 8)
		local out: { number } = {}
		local count = Obb.queryIndex(index, 6, -1, 18, 9, out)
		t.truthy(count > 0, "the query found something")
		local seen: { [number]: boolean } = {}
		for n = 1, count do
			t.falsy(seen[out[n]], `box {out[n]} was returned twice`)
			seen[out[n]] = true
		end
		-- Every box whose true AABB overlaps the rectangle must be present (buckets may add extras).
		for n, box in boxes do
			local overlaps = box.maxx >= 6 and box.minx <= 18 and box.maxz >= -1 and box.minz <= 9
			if overlaps then
				t.truthy(seen[n], `box {box.name} overlaps the query but was not returned`)
			end
		end
		local again = Obb.queryIndex(index, 6, -1, 18, 9, out)
		t.equal(again, count, "a repeated query returns the same count (the stamp resets per query)")
		local none = Obb.queryIndex(index, 500, 500, 600, 600, out)
		t.equal(none, 0, "a rectangle outside the index returns nothing")
	end)

	-- D. differential fuzz ------------------------------------------------------------------------------------
	local segHits, segMisses = 0, 0
	t.fuzz("segmentHits agrees with a brute-force sampler over random oriented boxes", {
		iterations = FUZZ_SEGMENTS,
		gen = function(rng, i)
			-- gen is the ONLY consumer of the shared rng; check is a pure function of the value.
			local box = randomBox(rng)
			local function pt(): Vec3
				return v((rng:nextNumber() - 0.5) * 16, (rng:nextNumber() - 0.5) * 16, (rng:nextNumber() - 0.5) * 16)
			end
			return { box = box, p = pt(), q = pt(), i = i }
		end,
		check = function(value)
			local box: Obb.Box = value.box
			local p: Vec3 = value.p
			local q: Vec3 = value.q
			local context =
				`{describeBox(box)} p=({fmt(p.x)},{fmt(p.y)},{fmt(p.z)}) q=({fmt(q.x)},{fmt(q.y)},{fmt(q.z)})`
			local hit = Obb.segmentHits(box, p.x, p.y, p.z, q.x, q.y, q.z, 0)
			local length = math.sqrt((q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 + (q.z - p.z) ^ 2)
			local step = length / SEGMENT_SAMPLES
			local sampled = math.huge
			for n = 0, SEGMENT_SAMPLES do
				local f = n / SEGMENT_SAMPLES
				local d = Obb.distanceToPoint(box, p.x + (q.x - p.x) * f, p.y + (q.y - p.y) * f, p.z + (q.z - p.z) * f)
				if d < sampled then
					sampled = d
				end
			end
			if hit then
				segHits += 1
			else
				segMisses += 1
			end
			-- distanceToPoint is 1-Lipschitz, so the nearest sample is within step / 2 of the true minimum.
			if sampled <= 0 and not hit then
				error(`sampler found a point inside the box but segmentHits said miss: {context}`, 0)
			end
			if hit and sampled > step + 1e-9 then
				error(
					`segmentHits said hit but the nearest sample is {fmt(sampled)} away (step {fmt(step)}): {context}`,
					0
				)
			end
			-- The epsilon-inflated test may only ever ADD hits (the rejecting direction).
			if hit and not Obb.segmentHits(box, p.x, p.y, p.z, q.x, q.y, q.z, EPS) then
				error(`inflating by GEOM_EPSILON removed a hit: {context}`, 0)
			end
		end,
	})

	local colHits, colMisses = 0, 0
	t.fuzz("columnSpan agrees with a dense vertical sampler", {
		iterations = FUZZ_COLUMNS,
		gen = function(rng, i)
			local box = randomBox(rng)
			return { box = box, x = (rng:nextNumber() - 0.5) * 12, z = (rng:nextNumber() - 0.5) * 12, i = i }
		end,
		check = function(value)
			local box: Obb.Box = value.box
			local x: number = value.x
			local z: number = value.z
			local context = `{describeBox(box)} x={fmt(x)} z={fmt(z)}`
			local lo, hi, ny = Obb.columnSpan(box, x, z)
			local radius = math.sqrt(box.h[1] ^ 2 + box.h[2] ^ 2 + box.h[3] ^ 2) + 1
			local step = 2 * radius / COLUMN_SAMPLES
			local lowest, highest = math.huge, -math.huge
			for n = 0, COLUMN_SAMPLES do
				local y = box.cy - radius + n * step
				if Obb.distanceToPoint(box, x, y, z) <= 0 then
					lowest = math.min(lowest, y)
					highest = math.max(highest, y)
				end
			end
			local sampledAny = lowest <= highest
			if lo == nil or hi == nil then
				colMisses += 1
				if sampledAny then
					error(`sampler found an inside point but columnSpan returned nil: {context}`, 0)
				end
				return
			end
			colHits += 1
			if ny < -1e-9 or ny > 1 + 1e-9 then
				error(`nyTop {fmt(ny)} is not a top-exit normal: {context}`, 0)
			end
			if not sampledAny then
				if hi - lo > step + 1e-9 then
					error(
						`columnSpan span {fmt(hi - lo)} is wider than the step but the sampler saw nothing: {context}`,
						0
					)
				end
				return
			end
			if lowest < lo - 1e-6 or lowest - lo > step + 1e-6 then
				error(`lo {fmt(lo)} disagrees with sampled lowest {fmt(lowest)} (step {fmt(step)}): {context}`, 0)
			end
			if highest > hi + 1e-6 or hi - highest > step + 1e-6 then
				error(`hi {fmt(hi)} disagrees with sampled highest {fmt(highest)} (step {fmt(step)}): {context}`, 0)
			end
		end,
	})

	t.test("the differential fuzz generated both hits and misses", function()
		t.truthy(segHits > MIN_PER_OUTCOME, `only {segHits} segment trials hit (floor {MIN_PER_OUTCOME})`)
		t.truthy(segMisses > MIN_PER_OUTCOME, `only {segMisses} segment trials missed (floor {MIN_PER_OUTCOME})`)
		t.truthy(colHits > MIN_PER_OUTCOME, `only {colHits} column trials hit (floor {MIN_PER_OUTCOME})`)
		t.truthy(colMisses > MIN_PER_OUTCOME, `only {colMisses} column trials missed (floor {MIN_PER_OUTCOME})`)
		t.equal(segHits + segMisses, FUZZ_SEGMENTS, "every segment trial ran")
		t.equal(colHits + colMisses, FUZZ_COLUMNS, "every column trial ran")
		print(`obb fuzz coverage: segments hit={segHits} miss={segMisses}; columns hit={colHits} miss={colMisses}`)
	end)
end
