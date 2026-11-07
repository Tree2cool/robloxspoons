--!strict
-- The card-phase layout as pure arithmetic (UX-01, UX-03, D-25, D-26, D-27, D-36). Every number comes
-- from the UI-SPEC "Layout and Screen Budget"; this file transcribes them and `problems` audits them.
--
--  1. PURE ZONE, AND THEREFORE NO ROBLOX TYPES. Rects are plain number tables and SCREEN_INSETS is a
--     string the renderer maps to the engine enum. That is what makes UX-01 and UX-03 headless
--     assertions rather than a Studio opinion, which is the whole reason this module exists.
--  2. COORDINATES: physical pixels, origin at the top-left of the FULLSCREEN area, because the insets
--     are relative to the rect covering all visible pixels. Design units are physical divided by scale.
--  3. THE INSETS CHOICE IS VERIFIED, NOT INFERRED (primary docs, last updated 2026-11-04):
--     CoreUISafeInsets is DeviceSafeInsets plus the Roblox core UI, and the docs recommend it for any
--     ScreenGui holding interactive or important elements. DeviceSafeInsets is the wrong choice: it
--     clears the camera notch but leaves UI under the Roblox top bar.
--  4. THE SCALE FLOOR OF 0.85 IS LOAD-BEARING. STEP >= 48 / 0.85 = 56.5 and 60 is the next 4-grid
--     value, so 60 * 0.85 = 51 physical px. Do not lower the floor without re-checking UX-01;
--     `problems` asserts the relation so lowering it fails the build.
--  5. CHECKER FLAGS F1, F2, F4, F7, RESOLVED. LIFT = 16 (at 20 the lifted top sits at 28 touching the
--     strip, and the hit rect would be 112 not 108). INDEX_INSET_X = 16 leaves 4 px over the 12 px
--     overlap. The strip spans the full safe width and strings are capped at STRIP_MAX_CHARS with a
--     12 px per-character proxy (F4's 11 was optimistic). Hit strips ignore z-order and the lift, so
--     a tap on a lifted card's 12 px overhang selects the neighbour: accepted, because widening it
--     would drop the neighbour's strip to 40.8 physical px at the floor.
--  6. TABLE_REGION_MIN_FRACTION exists because D-27 says the table is a place, not a wallpaper. The
--     true bound is 1 - 144/350 = 58.857%; the constant states it DOWN to 0.58, never up.
--  7. DERIVED VALUES ARE DERIVED. OVERLAP is CARD_W - STEP, the drain is the bottom of the strip, the
--     fan width follows handSize. A second constant is how two numbers disagree.
--
-- Nothing is rounded here: the renderer rounds. Rounding here would make the 48 px assertions disagree
-- with the rendered sizes. What this does NOT prove: physical size on glass, thumb reach, notch
-- behaviour, camera projection. Those are MANUAL-CHECKS M-11 / M-12.

local Card = require("../Config/Card")

export type Rect = { x: number, y: number, w: number, h: number }
export type Insets = { top: number, bottom: number, left: number, right: number }
export type Viewport = { width: number, height: number, insets: Insets }

export type Design = {
	REF_W: number,
	REF_H: number,
	SCALE_MIN: number,
	SCALE_MAX: number,
	HANDZONE_H: number,
	STRIP_H: number,
	STRIP_TEXT_H: number,
	DRAIN_H: number,
	STRIP_MARGIN: number,
	CARD_W: number,
	CARD_H: number,
	STEP: number,
	LIFT: number,
	INDEX_INSET_X: number,
	INDEX_INSET_Y: number,
	HIT_W: number,
	HIT_LAST_W: number,
	HIT_H: number,
	PILE_W: number,
	PILE_H: number,
	PILE_ART_W: number,
	PILE_ART_H: number,
	PILE_MARGIN: number,
	FAN_BOTTOM_MARGIN: number,
	MIN_FAN_PILE_GAP: number,
	CALLOUT_H: number,
	CALLOUT_GAP: number,
	TOUCH_FLOOR_PHYSICAL: number,
	TABLE_REGION_MIN_FRACTION: number,
	TABLE_REGION_HEIGHT_GUARANTEE: number,
	TABLE_PROJECTION_MARGIN: number,
	CHAR_WIDTH_PROXY: number,
}

export type Slot = { index: number, hit: Rect, card: Rect, lifted: Rect }
export type Named = { name: string, rect: Rect, interactive: boolean }
export type Solution = {
	scale: number,
	safe: Rect,
	designW: number,
	designH: number,
	tableRegion: Rect,
	tableRegionFraction: number,
	handZone: Rect,
	strip: Rect,
	drain: Rect,
	leftPile: Rect,
	rightPile: Rect,
	fan: Rect,
	slots: { Slot },
	calloutStack: { Rect },
	elements: { Named },
}

local EPS = 1e-9
local MIN_HAND = 4 -- Types.HAND_SIZE
local MAX_HAND = 5 -- Types.MAX_HAND

local DESIGN: Design = {
	REF_W = 760,
	REF_H = 350,
	SCALE_MIN = 0.85,
	SCALE_MAX = 1.5,
	HANDZONE_H = 144,
	STRIP_H = 28,
	STRIP_TEXT_H = 24,
	DRAIN_H = 4,
	STRIP_MARGIN = 8,
	CARD_W = 72,
	CARD_H = 92,
	STEP = 60,
	LIFT = 16,
	INDEX_INSET_X = 16, -- 16, not 12: checker FLAG F2
	INDEX_INSET_Y = 4,
	HIT_W = 60,
	HIT_LAST_W = 72,
	HIT_H = 108, -- CARD_H 92 + LIFT 16: checker FLAG F1
	PILE_W = 84,
	PILE_H = 96,
	PILE_ART_W = 52,
	PILE_ART_H = 68,
	PILE_MARGIN = 8,
	FAN_BOTTOM_MARGIN = 4,
	MIN_FAN_PILE_GAP = 24,
	CALLOUT_H = 32,
	CALLOUT_GAP = 4,
	TOUCH_FLOOR_PHYSICAL = 48,
	TABLE_REGION_MIN_FRACTION = 0.58,
	TABLE_REGION_HEIGHT_GUARANTEE = 300,
	TABLE_PROJECTION_MARGIN = 8,
	CHAR_WIDTH_PROXY = 12, -- bold 20 average; F4's 11 was optimistic
}
table.freeze(DESIGN)

local Layout = {}

-- A string, not an Enum: a pure zone names no Roblox type. The renderer maps it.
Layout.SCREEN_INSETS = "CoreUISafeInsets"
Layout.DESIGN = DESIGN

function Layout.OVERLAP(d: Design): number
	return d.CARD_W - d.STEP
end

function Layout.scaleFor(safeWidth: number, safeHeight: number, d: Design?): number
	local design = d or DESIGN
	local raw = math.min(safeWidth / design.REF_W, safeHeight / design.REF_H)
	return math.clamp(raw, design.SCALE_MIN, design.SCALE_MAX)
end

function Layout.safeRect(viewport: Viewport): Rect
	local i = viewport.insets
	local safe = {
		x = i.left,
		y = i.top,
		w = viewport.width - i.left - i.right,
		h = viewport.height - i.top - i.bottom,
	}
	if safe.w <= 0 or safe.h <= 0 then
		error(`Layout.solve: insets leave no safe area ({safe.w} x {safe.h})`)
	end
	return safe
end

function Layout.solve(viewport: Viewport, handSize: number, d: Design?): Solution
	local design = d or DESIGN
	if handSize < MIN_HAND or handSize > MAX_HAND or handSize ~= math.floor(handSize) then
		error(`Layout.solve: handSize {handSize} is outside {MIN_HAND}..{MAX_HAND}`)
	end
	local safe = Layout.safeRect(viewport)
	local scale = Layout.scaleFor(safe.w, safe.h, design)
	local designW = safe.w / scale
	local designH = safe.h / scale

	-- design units (origin = safe top-left) -> physical rect
	local function phys(dx: number, dy: number, dw: number, dh: number): Rect
		return { x = safe.x + dx * scale, y = safe.y + dy * scale, w = dw * scale, h = dh * scale }
	end

	local handTop = designH - design.HANDZONE_H
	local handZone = phys(0, handTop, designW, design.HANDZONE_H)
	local tableRegion = phys(0, 0, designW, handTop)
	local stripW = designW - 2 * design.STRIP_MARGIN
	local strip = phys(design.STRIP_MARGIN, handTop, stripW, design.STRIP_H)
	local drain = phys(design.STRIP_MARGIN, handTop + design.STRIP_H - design.DRAIN_H, stripW, design.DRAIN_H)
	local pileY = designH - design.PILE_MARGIN - design.PILE_H
	local leftPile = phys(design.PILE_MARGIN, pileY, design.PILE_W, design.PILE_H)
	local rightPile = phys(designW - design.PILE_MARGIN - design.PILE_W, pileY, design.PILE_W, design.PILE_H)

	local fanW = design.CARD_W + (handSize - 1) * design.STEP
	local fanX = (designW - fanW) / 2
	local fanY = designH - design.FAN_BOTTOM_MARGIN - design.CARD_H
	local fan = phys(fanX, fanY, fanW, design.CARD_H)

	local slots: { Slot } = {}
	for i = 1, handSize do
		local cx = fanX + (i - 1) * design.STEP
		local hitW = if i == handSize then design.HIT_LAST_W else design.HIT_W
		table.insert(slots, {
			index = i,
			card = phys(cx, fanY, design.CARD_W, design.CARD_H),
			lifted = phys(cx, fanY - design.LIFT, design.CARD_W, design.CARD_H),
			hit = phys(cx, fanY + design.CARD_H - design.HIT_H, hitW, design.HIT_H),
		})
	end

	-- Callouts are centred on the table region, as wide as a capped strip string, never wider than it.
	local calloutW = math.min(Card.STRIP_MAX_CHARS * design.CHAR_WIDTH_PROXY, designW - 2 * design.STRIP_MARGIN)
	local calloutStack: { Rect } = {}
	for k = 1, Card.MAX_CALLOUTS do
		local cy = (k - 1) * (design.CALLOUT_H + design.CALLOUT_GAP)
		table.insert(calloutStack, phys((designW - calloutW) / 2, cy, calloutW, design.CALLOUT_H))
	end

	local elements: { Named } = {}
	for _, slot in slots do
		table.insert(elements, { name = `slot{slot.index}`, rect = slot.hit, interactive = true })
	end
	table.insert(elements, { name = "leftPile", rect = leftPile, interactive = true })
	table.insert(elements, { name = "rightPile", rect = rightPile, interactive = true }) -- Active no-op sink (D-06)
	table.insert(elements, { name = "strip", rect = strip, interactive = false })
	table.insert(elements, { name = "drain", rect = drain, interactive = false })
	for k, rect in calloutStack do
		table.insert(elements, { name = `callout{k}`, rect = rect, interactive = false })
	end

	return {
		scale = scale,
		safe = safe,
		designW = designW,
		designH = designH,
		tableRegion = tableRegion,
		tableRegionFraction = tableRegion.h / safe.h,
		handZone = handZone,
		strip = strip,
		drain = drain,
		leftPile = leftPile,
		rightPile = rightPile,
		fan = fan,
		slots = slots,
		calloutStack = calloutStack,
		elements = elements,
	}
end

-- Signed separation: > 0 clear gap, 0 touching, < 0 overlapping.
function Layout.separation(a: Rect, b: Rect): number
	local sx = math.max(a.x - (b.x + b.w), b.x - (a.x + a.w))
	local sy = math.max(a.y - (b.y + b.h), b.y - (a.y + a.h))
	return math.max(sx, sy)
end

function Layout.inside(inner: Rect, outer: Rect): boolean
	return inner.x >= outer.x - EPS
		and inner.y >= outer.y - EPS
		and inner.x + inner.w <= outer.x + outer.w + EPS
		and inner.y + inner.h <= outer.y + outer.h + EPS
end

function Layout.problems(viewport: Viewport, handSize: number, d: Design?): ({ string }, number)
	local design = d or DESIGN
	local s = Layout.solve(viewport, handSize, design)
	local out: { string } = {}
	local checks = 0
	local function check(ok: boolean, message: string)
		checks += 1
		if not ok then
			table.insert(out, message)
		end
	end

	local floor = design.TOUCH_FLOOR_PHYSICAL
	for _, e in s.elements do
		if e.interactive then
			check(
				e.rect.w >= floor - EPS and e.rect.h >= floor - EPS,
				`below touch floor: {e.name} is {e.rect.w} x {e.rect.h} physical, floor {floor}`
			)
		end
		check(
			Layout.inside(e.rect, s.safe),
			`outside safe rect: {e.name} at {e.rect.x},{e.rect.y} {e.rect.w}x{e.rect.h}`
		)
	end
	-- Rects that are not in `elements` but must still be contained.
	for _, slot in s.slots do
		check(Layout.inside(slot.card, s.safe), `outside safe rect: slot{slot.index} card`)
		check(Layout.inside(slot.lifted, s.safe), `outside safe rect: slot{slot.index} lifted`)
	end
	check(Layout.inside(s.fan, s.safe), "outside safe rect: fan")

	if s.safe.h >= design.TABLE_REGION_HEIGHT_GUARANTEE then
		check(
			s.tableRegionFraction >= design.TABLE_REGION_MIN_FRACTION - EPS,
			`table region too small: {s.tableRegionFraction} < {design.TABLE_REGION_MIN_FRACTION}`
		)
	else
		-- Reported, never used to loosen the bound: the planner is told a real device fell short.
		check(false, `height below guarantee: safe height {s.safe.h} < {design.TABLE_REGION_HEIGHT_GUARANTEE}`)
	end

	for _, slot in s.slots do
		-- Touching counts: the spec requires the lifted card to CLEAR the strip, not to kiss it.
		local gap = Layout.separation(slot.lifted, s.strip)
		check(gap > EPS, `lift overlaps strip: slot{slot.index} lifted gap {gap}`)
	end
	for i = 1, #s.slots do
		for j = i + 1, #s.slots do
			check(Layout.separation(s.slots[i].hit, s.slots[j].hit) >= -EPS, `hit overlap: slot{i} and slot{j}`)
		end
	end

	local piles: { { name: string, rect: Rect } } = {
		{ name = "leftPile", rect = s.leftPile },
		{ name = "rightPile", rect = s.rightPile },
	}
	for _, entry in piles do
		local name, pile = entry.name, entry.rect
		local gap = Layout.separation(s.fan, pile)
		check(gap >= design.MIN_FAN_PILE_GAP * s.scale - EPS, `fan pile gap: fan to {name} is {gap}`)
		check(gap >= 0, `overlap: fan and {name}`)
		check(Layout.separation(s.strip, pile) >= 0, `overlap: strip and {name}`)
	end

	check(
		design.INDEX_INSET_X > Layout.OVERLAP(design),
		`index inset: {design.INDEX_INSET_X} <= overlap {Layout.OVERLAP(design)}`
	)
	check(
		design.STEP * design.SCALE_MIN >= floor - EPS,
		`step below touch floor: {design.STEP} x {design.SCALE_MIN} < {floor}`
	)
	check(
		s.strip.w >= Card.STRIP_MAX_CHARS * design.CHAR_WIDTH_PROXY * s.scale - EPS,
		`strip too narrow: {s.strip.w} physical`
	)
	check(design.HIT_H == design.CARD_H + design.LIFT, `hit height: {design.HIT_H} ~= {design.CARD_H} + {design.LIFT}`)

	return out, checks
end

return Layout
