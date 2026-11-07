--!strict
-- UX-01 / UX-03 gate: the UI-SPEC geometry is arithmetic, so it is asserted, not eyeballed.
--
-- WHAT THIS PROVES: the numbers (48 physical px floor, inset containment, TableRegion fraction, lift
-- clearance, hit-strip independence, strip width).
-- WHAT IT CANNOT PROVE: thumb reach, physical size on glass, camera projection of the 3D table into
-- tableRegion, notch behaviour, the strip at PreferredTextSize = Largest. Those are MANUAL-CHECKS M-12
-- (and M-11). UX-01 and UX-03 are NOT closed by this file.
--
-- Mutations are injected broken COPIES of Layout.DESIGN (the DESIGN table is frozen), not source edits.
local Card = require("../../src/shared/Config/Card")
local Layout = require("../../src/shared/Card/Layout")
local Test = require("../harness/Test")

type Viewport = Layout.Viewport

-- Real device insets are observation M-12; these are the contract's REFERENCE values.
local VIEWPORTS: { { name: string, v: Viewport } } = {
	{
		name = "phone notched",
		v = { width = 844, height = 390, insets = { top = 0, bottom = 21, left = 47, right = 0 } },
	},
	{ name = "phone small", v = { width = 640, height = 360, insets = { top = 36, bottom = 0, left = 0, right = 0 } } },
	{
		name = "phone large",
		v = { width = 932, height = 430, insets = { top = 0, bottom = 21, left = 50, right = 0 } },
	},
	{ name = "desktop", v = { width = 1920, height = 1080, insets = { top = 36, bottom = 0, left = 0, right = 0 } } },
}
local HANDS = { 4, 5 }
local NO_INSETS = { top = 0, bottom = 0, left = 0, right = 0 }

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out: { [any]: any } = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

local function withDesign(overrides: { [string]: number }): Layout.Design
	local copy: any = deepCopy(Layout.DESIGN)
	for k, v in overrides do
		copy[k] = v
	end
	return copy
end

local function hasPrefix(problems: { string }, prefix: string): string?
	for _, p in problems do
		if string.sub(p, 1, #prefix) == prefix then
			return p
		end
	end
	return nil
end

local function count(problems: { string }, prefix: string): number
	local n = 0
	for _, p in problems do
		if string.sub(p, 1, #prefix) == prefix then
			n += 1
		end
	end
	return n
end

local function near(a: number, b: number, tol: number): boolean
	return math.abs(a - b) <= tol
end

-- Runs `design` against every viewport/hand pair; returns (pairs red for prefix, pairs run, first message).
local function redAt(design: Layout.Design, prefix: string, viewports: { Viewport }): (number, number, string)
	local red, ran, first = 0, 0, ""
	for _, v in viewports do
		for _, h in HANDS do
			local problems = Layout.problems(v, h, design)
			ran += 1
			local hit = hasPrefix(problems, prefix)
			if hit then
				red += 1
				if first == "" then
					first = hit
				end
			end
		end
	end
	return red, ran, first
end

local function allViewports(): { Viewport }
	local out: { Viewport } = {}
	for _, e in VIEWPORTS do
		table.insert(out, e.v)
	end
	return out
end

return function(t: Test.Runner)
	t.test("every viewport solves cleanly at hand 4 and hand 5 (clean control)", function()
		local pairsRun, totalChecks = 0, 0
		for _, e in VIEWPORTS do
			for _, h in HANDS do
				local problems, checks = Layout.problems(e.v, h)
				t.deepEqual(problems, {}, `{e.name} hand {h}: {table.concat(problems, " | ")}`)
				t.truthy(checks >= 15, `{e.name} hand {h}: only {checks} checks`)
				pairsRun += 1
				totalChecks += checks
			end
		end
		t.equal(pairsRun, 8, "non-vacuity: viewport x hand-size pairs")
		print(`layout: {pairsRun} pairs, {totalChecks} checks performed`)
	end)

	t.test("the measured TableRegion fraction is printed for every viewport and is at least 58 percent", function()
		for _, e in VIEWPORTS do
			local s = Layout.solve(e.v, 5)
			print(
				`layout: {e.name} scale {s.scale} safe {s.safe.w}x{s.safe.h} tableRegionFraction {s.tableRegionFraction}`
			)
			t.truthy(s.tableRegionFraction >= 0.58, `{e.name} fraction {s.tableRegionFraction}`)
		end
		local a = Layout.solve({ width = 750, height = 369, insets = NO_INSETS }, 5)
		t.truthy(near(a.scale, 0.987, 0.001), `750x369 scale {a.scale}`)
		t.truthy(near(a.handZone.h, 142, 0.5), `750x369 handZone {a.handZone.h}`)
		t.truthy(near(a.tableRegionFraction, 0.615, 0.001), `750x369 fraction {a.tableRegionFraction}`)
		local b = Layout.solve({ width = 1920, height = 1080, insets = NO_INSETS }, 5)
		t.equal(b.scale, 1.5)
		t.truthy(near(b.handZone.h, 216, 1e-9), `1920x1080 handZone {b.handZone.h}`)
		t.truthy(near(b.tableRegionFraction, 0.8, 1e-9), `1920x1080 fraction {b.tableRegionFraction}`)
		-- The stated-down bound: 1 - 144/350 = 0.58857..., so 0.58 holds and 0.589 would not.
		t.truthy(1 - 144 / 350 > 0.588 and 1 - 144 / 350 < 0.589, "58.857 percent")
	end)

	t.test("the scale rule is exactly clamp(min(w/760, h/350), 0.85, 1.5)", function()
		local cases = {
			{ 1520, 1000, 1.5 }, -- both above ceiling
			{ 380, 700, 0.85 }, -- width-limited below floor
			{ 1520, 290, 0.85 }, -- height-limited below floor
			{ 760, 350, 1.0 }, -- exact boundary
			{ 950, 1000, 950 / 760 }, -- width-limited, in range
			{ 2000, 385, 385 / 350 }, -- height-limited, in range
			{ 100, 100, 0.85 }, -- both below floor
		}
		for _, c in cases do
			t.truthy(
				near(Layout.scaleFor(c[1], c[2]), c[3], 1e-12),
				`scaleFor({c[1]},{c[2]}) = {Layout.scaleFor(c[1], c[2])}`
			)
		end
		t.equal(#cases, 7, "non-vacuity: scale cases")
	end)

	t.test("every interactive rect is at least 48 physical px on every viewport, including at the floor", function()
		local interactive = 0
		for _, e in VIEWPORTS do
			for _, h in HANDS do
				local s = Layout.solve(e.v, h)
				local n = 0
				for _, el in s.elements do
					if el.interactive then
						n += 1
						t.truthy(
							el.rect.w >= 48 - 1e-9 and el.rect.h >= 48 - 1e-9,
							`{e.name} {el.name} {el.rect.w}x{el.rect.h}`
						)
					end
				end
				t.equal(n, h + 2, `{e.name} hand {h}: slots plus both piles`)
				interactive += n
			end
		end
		t.equal(interactive, 4 * (4 + 2) + 4 * (5 + 2), "non-vacuity: interactive rects")
		-- A viewport contrived to clamp to exactly the 0.85 floor.
		local floorView: Viewport = { width = 600, height = 300, insets = NO_INSETS }
		local s = Layout.solve(floorView, 5)
		t.equal(s.scale, 0.85)
		t.truthy(near(s.slots[1].hit.w, 51, 1e-9), `hit strip at the floor is {s.slots[1].hit.w}, expected 51`)
		print(`layout: interactive rects checked {interactive}; floor hit strip {s.slots[1].hit.w} physical px`)
	end)

	t.test("no rect lies outside the safe rect, and handZone and tableRegion partition the safe height", function()
		local rects = 0
		for _, e in VIEWPORTS do
			for _, h in HANDS do
				local s = Layout.solve(e.v, h)
				for _, el in s.elements do
					t.truthy(Layout.inside(el.rect, s.safe), `{e.name} {el.name} outside safe`)
					rects += 1
				end
				t.truthy(
					Layout.separation(s.handZone, s.tableRegion) >= -1e-9,
					`{e.name} handZone overlaps tableRegion`
				)
				t.truthy(near(s.handZone.h + s.tableRegion.h, s.safe.h, 1e-9), `{e.name} heights do not partition`)
			end
		end
		t.truthy(rects >= 8 * 8, `non-vacuity: {rects} rects`)
	end)

	t.test("a lifted card is 4 design px clear of the strip at every viewport", function()
		local slotsChecked = 0
		for _, e in VIEWPORTS do
			for _, h in HANDS do
				local s = Layout.solve(e.v, h)
				for _, slot in s.slots do
					t.truthy(
						slot.lifted.y >= s.strip.y + s.strip.h + 4 * s.scale - 1e-9,
						`{e.name} slot {slot.index} clearance`
					)
					t.truthy(Layout.separation(slot.lifted, s.strip) > 0, `{e.name} slot {slot.index} intersects strip`)
					slotsChecked += 1
				end
			end
		end
		t.equal(slotsChecked, 36, "non-vacuity: slots checked")
	end)

	t.test("hit strips are independent of the lift and of z-order (F7) and never intersect", function()
		local pairsChecked = 0
		for _, e in VIEWPORTS do
			for _, h in HANDS do
				-- The solver takes no selection argument: the API shape is part of the assertion.
				local a = Layout.solve(e.v, h)
				local b = Layout.solve(e.v, h)
				for i = 1, h do
					t.deepEqual(a.slots[i].hit, b.slots[i].hit, `{e.name} slot {i} hit differs between solves`)
					t.equal(a.slots[i].hit.w, (if i == h then 72 else 60) * a.scale, `{e.name} slot {i} hit width`)
					t.truthy(near(a.slots[i].hit.h, 108 * a.scale, 1e-9), `{e.name} slot {i} hit height`)
					for j = i + 1, h do
						t.truthy(
							Layout.separation(a.slots[i].hit, a.slots[j].hit) >= -1e-9,
							`{e.name} hit {i} intersects {j}`
						)
						pairsChecked += 1
					end
				end
			end
		end
		t.equal(pairsChecked, 4 * (6 + 10), "non-vacuity: hit pairs")
	end)

	t.test("the strip fits 34 characters at the 12 px proxy (F4) and touches neither pile", function()
		local narrowest = math.huge
		for _, e in VIEWPORTS do
			local s = Layout.solve(e.v, 5)
			local need = Card.STRIP_MAX_CHARS * 12 * s.scale
			local ratio = s.strip.w / need
			print(`layout: {e.name} strip headroom {ratio}`)
			t.truthy(s.strip.w >= need, `{e.name} strip {s.strip.w} < {need}`)
			narrowest = math.min(narrowest, ratio)
			t.truthy(Layout.separation(s.strip, s.leftPile) >= 0, `{e.name} strip meets leftPile`)
			t.truthy(Layout.separation(s.strip, s.rightPile) >= 0, `{e.name} strip meets rightPile`)
		end
		t.truthy(narrowest >= 1.5, `narrowest headroom {narrowest}`)
		-- Design-side bound only. The rendered width at PreferredTextSize = Largest is M-12.
	end)

	t.test(
		"MUTATION: eight broken designs each turn the gate red, with the clean design passing beside them",
		function()
			local all = allViewports()
			local mutations = 0
			local function red(name: string, design: Layout.Design, prefix: string, views: { Viewport }?)
				local n, ran, first = redAt(design, prefix, views or all)
				local cleanN, cleanRan = redAt(Layout.DESIGN, prefix, views or all)
				print(`MUTATION {name}: red at {n}/{ran} pairs on "{prefix}": {first}`)
				t.truthy(n > 0, `MUTATION {name} did not turn "{prefix}" red`)
				t.equal(cleanN, 0, `clean control has "{prefix}" problems`)
				t.truthy(cleanRan == ran and ran > 0, "non-vacuity: clean control ran the same pairs")
			end

			-- 1. STEP 60 -> 44: the step relation, plus the hit strips now overlap one another.
			red("STEP=44", withDesign({ STEP = 44 }), "step below touch floor:")
			red("STEP=44 (hit overlap)", withDesign({ STEP = 44 }), "hit overlap:")
			mutations += 1
			-- 2. scale floor 0.85 -> 0.7: the relation fires everywhere; a tiny phone shows it physically.
			local tiny: Viewport = { width = 500, height = 250, insets = NO_INSETS }
			red("SCALE_MIN=0.7", withDesign({ SCALE_MIN = 0.7 }), "step below touch floor:")
			red("SCALE_MIN=0.7 (physical)", withDesign({ SCALE_MIN = 0.7 }), "below touch floor:", { tiny })
			mutations += 1
			-- 3. hit strip shrunk by the 12 px overlap: 60 -> 48 design px falls under 48 physical below scale 1.
			red("HIT_W=48", withDesign({ HIT_W = 48 }), "below touch floor:")
			mutations += 1
			-- 4. HandZone grows: the table becomes wallpaper.
			red("HANDZONE_H=170", withDesign({ HANDZONE_H = 170 }), "table region too small:")
			mutations += 1
			-- 5. CHECKER FLAG F1, live in the spec: lift 20 touches the strip and makes the hit rect 112.
			red("LIFT=20 (F1)", withDesign({ LIFT = 20 }), "lift overlaps strip:")
			red("LIFT=20 (F1, hit height)", withDesign({ LIFT = 20 }), "hit height:")
			mutations += 1
			-- 6. CHECKER FLAG F2: at 12 the accent outline spills onto the neighbour's rank glyph.
			red("INDEX_INSET_X=12 (F2)", withDesign({ INDEX_INSET_X = 12 }), "index inset:")
			mutations += 1

			-- 7. A solver that ignores the insets entirely. This ONLY proves the insets are read at all.
			local ignoring, ranIgnoring = 0, 0
			for _, e in VIEWPORTS do
				local real = Layout.solve(e.v, 5)
				local naive = Layout.solve({ width = e.v.width, height = e.v.height, insets = NO_INSETS }, 5)
				local outside = 0
				for _, el in naive.elements do
					if not Layout.inside(el.rect, real.safe) then
						outside += 1
					end
				end
				local cleanOutside = 0
				for _, el in real.elements do
					if not Layout.inside(el.rect, real.safe) then
						cleanOutside += 1
					end
				end
				t.equal(cleanOutside, 0, `{e.name} real solver has elements outside`)
				if outside > 0 then
					ignoring += 1
				end
				ranIgnoring += 1
			end
			print(`MUTATION insets-ignored: red at {ignoring}/{ranIgnoring} viewports (all four have non-zero insets)`)
			t.equal(ignoring, 4, "insets-ignoring solver must put something outside the safe rect on every viewport")
			mutations += 1

			-- 8. ONE real element under the inset. PILE_MARGIN is the only value positioning an interactive
			-- element relative to the safe-rect EDGE, so a negative value is exactly "extends under the inset".
			local pileMut = withDesign({ PILE_MARGIN = -12 })
			red("PILE_MARGIN=-12", pileMut, "outside safe rect: leftPile")
			red("PILE_MARGIN=-12 (right)", pileMut, "outside safe rect: rightPile")
			local fanMut = withDesign({ HANDZONE_H = 144, FAN_BOTTOM_MARGIN = -16 })
			red("FAN_BOTTOM_MARGIN=-16", fanMut, "outside safe rect: slot1")
			red("FAN_BOTTOM_MARGIN=-16 (fan)", fanMut, "outside safe rect: fan")
			-- The message names the offender and ONLY the offender: no pile is blamed for a fan slot and
			-- no slot for a pile.
			for _, e in VIEWPORTS do
				local p = Layout.problems(e.v, 5, pileMut)
				t.equal(count(p, "outside safe rect: slot"), 0, `{e.name}: pile mutant blamed a slot`)
				t.equal(count(p, "outside safe rect: fan"), 0, `{e.name}: pile mutant blamed the fan`)
				local f = Layout.problems(e.v, 5, fanMut)
				t.equal(count(f, "outside safe rect: leftPile"), 0, `{e.name}: fan mutant blamed leftPile`)
				t.equal(count(f, "outside safe rect: rightPile"), 0, `{e.name}: fan mutant blamed rightPile`)
			end
			mutations += 1

			t.equal(mutations, 8, "assert 8 mutation rows exercised")
		end
	)

	t.test("solve errors by name on an impossible input", function()
		local ok: Viewport = VIEWPORTS[1].v
		t.throws(function()
			Layout.solve(ok, 3)
		end, "outside 4..5")
		t.throws(function()
			Layout.solve(ok, 6)
		end, "outside 4..5")
		t.throws(function()
			Layout.solve({ width = 100, height = 100, insets = { top = 60, bottom = 40, left = 0, right = 0 } }, 4)
		end, "no safe area")
		t.throws(function()
			Layout.solve({ width = 0, height = 300, insets = NO_INSETS }, 4)
		end, "no safe area")
	end)

	t.test("the ScreenInsets choice is CoreUISafeInsets and is carried as a string", function()
		-- A pure zone may not name an Enum; plan 04-16 maps this string to the real enum.
		t.equal(Layout.SCREEN_INSETS, "CoreUISafeInsets")
		t.equal(type(Layout.SCREEN_INSETS), "string")
	end)
end
