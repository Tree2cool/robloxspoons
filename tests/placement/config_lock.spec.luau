--!strict
-- Spec lock for the owner-confirmed placement constants (D-13, D-18). The pattern is
-- tests/engine/spec_lock.spec.luau: the shipped config module is loaded by relative path (tests are outside
-- R6's shipped dirs) and its values and invariants are asserted, so a later edit cannot move a number
-- without a test saying what that number was protecting.
--
-- Every invariant here has a positive case AND a negative control. A comparison nobody has watched
-- discriminate is not evidence, so each control re-evaluates the same expression at a value that must make
-- it fail. Later plans (03-05, 03-08) extend this file with the PlacementConfig type lock, the arity lock
-- and the MapLoader source assertion; the cases are independent so they can be appended.
local Placement = require("../../src/shared/Config/Placement")
local Test = require("../harness/Test")

-- Research's two measured per-spot requirements against the committed graybox (03-RESEARCH.md, "The
-- Number Ladder"): the effective range each spot needs, in studs, at the shipped EYE_HEIGHT.
local CRATE_TOP_NEEDS = 4.06
local SHELF_EDGE_NEEDS = 6.54

return function(t: Test.Runner)
	t.test("the ten shipped placement values are exactly the owner-confirmed set (D-18)", function()
		t.equal(Placement.GRID_SIZE, 1.0)
		t.equal(Placement.STEP_UP, 1.0)
		t.equal(Placement.MAX_SLOPE_DEGREES, 30)
		t.equal(Placement.CAPSULE_RADIUS, 1.5)
		t.equal(Placement.CAPSULE_HEIGHT, 7.0)
		t.equal(Placement.REACH_HEIGHT, 2.5)
		t.equal(Placement.EYE_HEIGHT, 4.0)
		t.equal(Placement.SPOT_CLEARANCE, 0.25)
		t.equal(Placement.PICKUP_RANGE, 7.0)
		t.equal(Placement.PICKUP_MARGIN, 1.5)
		local count = 0
		for _ in Placement do
			count += 1
		end
		t.equal(count, 10, "an eleventh constant must be decided, not slipped in")
	end)

	t.test("effective range is 5.5 and every authored graybox spot sits at least 1 stud clear of a flip", function()
		local E = Placement.PICKUP_RANGE - Placement.PICKUP_MARGIN
		t.equal(E, 5.5)
		-- Pitfall 7: at PICKUP_RANGE 8.0 the effective range is 6.5 and the shelf-edge slack is 0.04, a
		-- verdict decided by float32 rounding. The 1.0-stud clearance on both sides is what 7.0 buys.
		-- Computed from E, never from the literal 5.5, so an edit to either constant moves E and fires.
		t.truthy(math.abs(E - CRATE_TOP_NEEDS) > 1.0, `crate-top slack {math.abs(E - CRATE_TOP_NEEDS)} <= 1.0`)
		t.truthy(math.abs(SHELF_EDGE_NEEDS - E) > 1.0, `shelf-edge slack {math.abs(SHELF_EDGE_NEEDS - E)} <= 1.0`)
	end)

	t.test("the knife-edge guard fires at PICKUP_RANGE 8.0 (negative control)", function()
		local E8 = 8.0 - Placement.PICKUP_MARGIN
		t.truthy(
			math.abs(SHELF_EDGE_NEEDS - E8) < 1.0,
			`at range 8.0 the shelf-edge slack is {math.abs(SHELF_EDGE_NEEDS - E8)}, expected under 1.0`
		)
	end)

	t.test("STEP_UP covers a legal slope at the shipped resolution (the ramp coupling)", function()
		-- The graybox Ramp is atan(6.5 / 14) = 24.9047 degrees. Measured minimum STEP_UP for it is exactly
		-- GRID_SIZE * tan(24.9047 deg): 0.464 at g = 1. At g = 4 with STEP_UP 1.0 the ramp disconnects and
		-- survivors fall to 11-12.
		local needed = Placement.GRID_SIZE * math.tan(math.rad(Placement.MAX_SLOPE_DEGREES))
		t.truthy(Placement.STEP_UP >= needed, `STEP_UP {Placement.STEP_UP} < GRID_SIZE * tan(slope) = {needed}`)
	end)

	t.test("the step-up coupling fails at a coarser grid (negative control)", function()
		local neededAt4 = 4 * math.tan(math.rad(30))
		t.truthy(Placement.STEP_UP < neededAt4, `STEP_UP {Placement.STEP_UP} would cover {neededAt4}`)
	end)

	t.test("PICKUP_MARGIN covers the grid half-diagonal", function()
		local halfDiagonal = Placement.GRID_SIZE * math.sqrt(2) / 2
		t.truthy(
			Placement.PICKUP_MARGIN >= Placement.GRID_SIZE * math.sqrt(2) / 2,
			`PICKUP_MARGIN {Placement.PICKUP_MARGIN} < half-diagonal {halfDiagonal}`
		)
	end)

	t.test("the margin coupling fails at a coarser grid (negative control)", function()
		local halfDiagonalAt4 = 4 * math.sqrt(2) / 2
		t.truthy(Placement.PICKUP_MARGIN < halfDiagonalAt4, `at g = 4 the half-diagonal is {halfDiagonalAt4}`)
	end)

	t.test("CAPSULE_HEIGHT > EYE_HEIGHT >= REACH_HEIGHT", function()
		-- An eye at or above the capsule height is incoherent, so that comparison is strict. A reach point
		-- above the eye is incoherent too, but a reach point EQUAL to the eye is the degenerate
		-- single-height configuration whose measured consequence (crate-top needs 8.75, map falls to 15
		-- survivors) is the whole reason EYE_HEIGHT is a separate constant, so it must stay expressible,
		-- and plan 03-06 case 7 bakes it as a negative control. Do not tighten this to a strict
		-- comparison. At the shipped values the strict form would also pass (4.0 vs 2.5), which is exactly
		-- why this is written down: the next reader will not otherwise see why the non-strict form matters.
		t.truthy(Placement.CAPSULE_HEIGHT > Placement.EYE_HEIGHT, "eye must sit below the capsule top")
		t.truthy(Placement.EYE_HEIGHT >= Placement.REACH_HEIGHT, "eye must not sit below reach")
	end)

	t.test("the clearance cliff exists: 0.5 would cull every authored spot", function()
		-- The authoring convention is anchor y = surface + 0.5. Measured, at SPOT_CLEARANCE 0.25 / 0.40 /
		-- 0.49 all 18 authored spots pass (the v1 measurement; the convention is unchanged at 21); at 0.50,
		-- 0.6 and 1.0 ZERO pass, because a <= comparison against a spot sitting exactly 0.5 above its
		-- surface culls all of them. Do not round this value up. Plan 03-06 adds the executable half of
		-- this cliff (a real bake at clearance 0.5); this case is the arithmetic guard that stops a
		-- careless edit before it reaches that bake.
		t.truthy(Placement.SPOT_CLEARANCE < 0.5, `SPOT_CLEARANCE {Placement.SPOT_CLEARANCE} is on the cliff`)
		t.truthy(Placement.SPOT_CLEARANCE <= 0.45, `SPOT_CLEARANCE {Placement.SPOT_CLEARANCE} leaves no headroom`)
	end)

	t.test("every value is a finite positive number", function()
		for key, v in Placement do
			local n: any = v
			t.truthy(type(n) == "number" and n == n and n > 0 and n < math.huge, `{key} = {tostring(n)}`)
		end
	end)
end
