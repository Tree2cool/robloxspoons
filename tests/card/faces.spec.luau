--!strict
-- CARD-19 / D-24 gate: shape and glyph carry all identity, colour is decorative. Greyscale survives.
--
-- Two machine layers (UI-SPEC "Greyscale must survive"):
--   1. the identity-key data is injective across all 50 faces, and
--   2. each key resolves to a DISTINCT DRAWN ASSET (glyph codepoint, or sprite rect), read from the
--      renderer's own table. Layer 1 alone is not enough: a renderer that drew one silhouette for two
--      pip ids would pass it. The hardest pair to tell apart at 16 px is spade versus club.
-- Tint is deliberately not in the key, so "strip the tint and keys stay distinct" would be a tautology
-- and is not asserted; case 8 instead proves flipping every tint changes nothing.
-- This proves distinct ASSETS, not distinguishable PIXELS: that half is MANUAL-CHECKS M-14 / M-16.
--
-- Mutations are injected broken COPIES of Faces.TABLES (the tests/engine/valve.spec convention). The
-- real tables are frozen, so mutating them would throw and would leak between cases; deepCopy exists
-- for that reason.
local CardPool = require("../../src/shared/Config/CardPool")
local Card = require("../../src/shared/Config/Card")
local Faces = require("../../src/shared/Card/Faces")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

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

local function tablesCopy(): Faces.AuditTables
	return deepCopy(Faces.TABLES)
end

local function hasProblem(problems: { string }, prefix: string): boolean
	for _, p in problems do
		if string.sub(p, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function describe(problems: { string }): string
	return table.concat(problems, " | ")
end

return function(t: Test.Runner)
	t.test("the rank ladder is frozen, 12 long, duplicate-free, and never uses 6", function()
		t.truthy(table.isfrozen(Faces.RANK_LADDER), "RANK_LADDER is not frozen")
		t.equal(#Faces.RANK_LADDER, Faces.MAX_RANKS)
		t.throws(function()
			table.insert(Faces.RANK_LADDER :: { string }, "X")
		end)
		t.equal(#Faces.RANK_LADDER, 12, "an insert changed the length")
		local seen: { [string]: boolean } = {}
		for _, g in Faces.RANK_LADDER do
			t.falsy(seen[g], `duplicate glyph {g}`)
			seen[g] = true
			t.truthy(g ~= "6", "6 must never be used: the 13th rank is unreachable because max ranks is 12")
		end
		t.equal(table.concat(Faces.RANK_LADDER, " "), "A K Q J 10 7 4 2 5 3 9 8")
	end)

	t.test("a rank integer maps to the same glyph regardless of round size (D-22)", function()
		local pairsVisited = 0
		for ranks = 5, 12 do
			for r = 1, ranks do
				t.equal(Faces.glyphOf(r), Faces.RANK_LADDER[r], `rank {r} changed glyph in a {ranks}-rank round`)
				pairsVisited += 1
			end
		end
		t.equal(pairsVisited, 68, "non-vacuity: sum(5..12) pairs")
	end)

	t.test("all 50 faces have a distinct identity key and a distinct drawn asset (D-24)", function()
		local problems, visited = Faces.audit(Faces.TABLES)
		t.deepEqual(problems, {})
		t.equal(visited, 50, "the audit must visit 12 * 4 + 2 faces")
		local sprite = tablesCopy()
		sprite.pipSource = "sprite"
		local p2, v2 = Faces.audit(sprite)
		t.deepEqual(p2, {}, "audit is not green under pipSource = sprite")
		t.equal(v2, 50)
		-- Independent of audit: every face's key is distinct, built through the public constructors.
		local keys: { [string]: boolean } = {}
		local n = 0
		for r = 1, 12 do
			for c = 1, 4 do
				local face = Faces.faceOf(r, c)
				t.falsy(keys[face.key], `duplicate key {face.key}`)
				keys[face.key] = true
				n += 1
			end
		end
		for _, mode in Faces.JOKER_MODES do
			local face = Faces.faceOf(Faces.JOKER_RANK, 1, mode)
			t.falsy(keys[face.key], `duplicate key {face.key}`)
			keys[face.key] = true
			n += 1
		end
		t.equal(n, 50, "non-vacuity: faces built")
	end)

	t.test("MUTATION: collapsing two pip silhouettes turns the greyscale gate red", function()
		local bad = tablesCopy()
		bad.pip.club.silhouette = "spade"
		local problems, visited = Faces.audit(bad)
		t.truthy(hasProblem(problems, "duplicate silhouette:"), describe(problems))
		t.truthy(hasProblem(problems, "duplicate identity key:"), describe(problems))
		t.equal(visited, 50)
		local clean = Faces.audit(tablesCopy())
		t.deepEqual(clean, {}, "clean control beside the mutation is not clean")
	end)

	t.test("MUTATION: pointing two pip ids at the same drawn asset turns the gate red", function()
		-- Every silhouette stays distinct: only the asset the renderer draws collides.
		local sameGlyph = tablesCopy()
		sameGlyph.pip.diamond.glyph = sameGlyph.pip.heart.glyph
		local problems = Faces.audit(sameGlyph)
		t.truthy(hasProblem(problems, "duplicate drawn asset:"), describe(problems))
		t.falsy(hasProblem(problems, "duplicate silhouette:"), "silhouettes were meant to stay distinct")
		sameGlyph.pipSource = "sprite"
		t.deepEqual(Faces.audit(sameGlyph), {}, "sprites still differ, so sprite source must be clean")

		-- The mirror: identical sprite rects, distinct glyphs.
		local sameSprite = tablesCopy()
		sameSprite.pip.club.sprite = deepCopy(sameSprite.pip.spade.sprite)
		t.deepEqual(Faces.audit(sameSprite), {}, "glyphs differ, so glyph source must be clean")
		sameSprite.pipSource = "sprite"
		local p2 = Faces.audit(sameSprite)
		t.truthy(hasProblem(p2, "duplicate drawn asset:"), describe(p2))
	end)

	t.test("the joker map is exhaustive in both directions, and a third mode fails until mapped", function()
		t.equal(#Faces.JOKER_MODES, 2)
		t.truthy(table.isfrozen(Faces.JOKER_MODES) and table.isfrozen(Faces.JOKER_BAND), "joker tables not frozen")
		t.throws(function()
			table.insert(Faces.JOKER_MODES :: { string }, "Chaos")
		end)
		t.equal(#Faces.JOKER_MODES, 2, "an insert changed the length")
		local clean = Faces.audit(Faces.TABLES)
		t.falsy(hasProblem(clean, "unmapped joker mode:"), describe(clean))

		local third = tablesCopy()
		table.insert(third.jokerModes, "Chaos")
		local problems = Faces.audit(third)
		t.deepEqual(problems, { "unmapped joker mode: Chaos" })
		t.throws(function()
			Faces.jokerFaceOf("Chaos")
		end, "unmapped joker mode")

		local wild = Faces.jokerFaceOf("Wild")
		local block = Faces.jokerFaceOf("Blocker")
		t.truthy(wild.band ~= nil and block.band ~= nil, "joker faces carry a band")
		if wild.band ~= nil and block.band ~= nil then
			t.truthy(wild.band.text ~= block.band.text, "joker modes share text")
			t.truthy(wild.band.shape ~= block.band.shape, "joker modes share shape")
		end
	end)

	t.test("MUTATION: two joker modes sharing a band shape turns the gate red", function()
		local shape = tablesCopy()
		shape.jokerBand.Blocker.shape = "star"
		local p1 = Faces.audit(shape)
		t.truthy(hasProblem(p1, "duplicate joker band:"), describe(p1))
		local text = tablesCopy()
		text.jokerBand.Blocker.text = "WILD"
		local p2 = Faces.audit(text)
		t.truthy(hasProblem(p2, "duplicate joker band:"), describe(p2))
		t.deepEqual(Faces.audit(tablesCopy()), {}, "clean control is not clean")
	end)

	t.test("colour is not part of any identity key", function()
		local before: { string } = {}
		for r = 1, 12 do
			for c = 1, 4 do
				table.insert(before, Faces.keyOf(r, c))
			end
		end
		local flipped = tablesCopy()
		local flips = 0
		for _, pip in flipped.pip do
			pip.isRedByDefault = not pip.isRedByDefault
			flips += 1
		end
		t.equal(flips, 4, "non-vacuity: pips flipped")
		t.deepEqual(Faces.audit(flipped), {}, "flipping tint broke the audit")
		-- Rebuild keys from the flipped tables by the same (glyph, silhouette) rule the audit uses.
		local compared = 0
		for r = 1, 12 do
			for c = 1, 4 do
				local suit = flipped.suitOfCopy[c]
				local key = `{flipped.ladder[r]}/{flipped.pip[suit].silhouette}`
				t.equal(key, before[compared + 1], "a tint flip changed a key")
				compared += 1
			end
		end
		t.equal(compared, 48, "non-vacuity: natural faces compared")
	end)

	t.test("drift: JOKER_RANK matches the engine, and the shipped JOKER_MODE is a mapped mode", function()
		t.equal(
			Faces.JOKER_RANK,
			Types.JOKER_RANK,
			"a pure shared module cannot require the engine across the mount boundary (guard R6); this spec is the drift test"
		)
		local found = false
		for _, mode in Faces.JOKER_MODES do
			if mode == CardPool.JOKER_MODE then
				found = true
			end
		end
		t.truthy(found, `CardPool.JOKER_MODE {CardPool.JOKER_MODE} has no face`)
	end)

	t.test("every joker explainer string fits the status strip", function()
		local n = 0
		for _, mode in Faces.JOKER_MODES do
			local s = Faces.JOKER_EXPLAINER[mode]
			t.truthy(s ~= nil and #s > 0, `no explainer for {mode}`)
			t.truthy(#s <= Card.STRIP_MAX_CHARS, `{mode} explainer is {#s} chars`)
			n += 1
		end
		t.equal(n, 2, "non-vacuity: explainers checked")
	end)
end
