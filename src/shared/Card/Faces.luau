--!strict
-- The card face vocabulary (CARD-19, D-21, D-22, D-23, D-24).
-- PURE ZONE: no Roblox API, no clock, no yields. Every table below is frozen so a later module cannot
-- widen a vocabulary at runtime (the `Manifest.PHASES` precedent: a Luau type is erased at runtime, so
-- freezing is what actually stops the drift).
--
-- D-21 / D-22. The engine has no suits: a rank is an integer and ranks = seated seekers + 3, so a round
-- uses between 5 and 12 ranks, four copies each, plus one joker. RANK_LADDER maps engine rank r to a
-- real playing-card glyph and is ORDERED BY VISUAL DISTINCTNESS, so a 3-player round (5 ranks) gets the
-- five most dissimilar glyphs and the confusable 5/3/9/8 group enters last. The mapping does not depend
-- on round size, so a given integer never changes glyph mid-round or between rounds. The numeral six is
-- never used: a 13th rank would be needed to reach it and the maximum is 12.
--
-- D-24. SHAPE AND GLYPH carry all identity; COLOUR IS DECORATIVE. The identity key is
-- (rankGlyph, silhouette) and `isRedByDefault` is never read by `keyOf` or by `audit`. Red versus black
-- must never be the only difference between two cards. Phase 7 deck skins inherit this rule.
--
-- D-23. The joker states its CURRENT rule on its face, driven by the live JOKER_MODE flag. There is no
-- branch on a mode name anywhere in this file: the band is table-driven, and `audit` reports an
-- unmapped mode, so a third mode fails the build until it is given a band.
--
-- This module never sees how a `copy` was assigned. That is server-side (plan 04-05, the card routing
-- module), because guard R5 bans the identifier that derives it from every file under src/shared and
-- src/client, in code or in a string literal (D-37 as corrected). It receives a copy in 1..4 and draws it.

export type Suit = "spade" | "heart" | "club" | "diamond"
export type JokerMode = "Wild" | "Blocker"

-- (Codepoints are built with utf8.char: the pure selene config rejects the \u escape.)
-- The DRAWN asset for a suit. Exactly one of `glyph` / `sprite` is used at render time, chosen once by
-- PIP_SOURCE; both are declared so the greyscale gate can assert distinctness of whichever the renderer
-- actually draws.
export type Pip = {
	suit: Suit,
	silhouette: string,
	glyph: string,
	sprite: { x: number, y: number, w: number, h: number },
	isRedByDefault: boolean, -- DECORATIVE ONLY. Never part of an identity key.
}

export type Band = { text: string, shape: string }

export type Face = {
	isJoker: boolean,
	rankGlyph: string, -- "" for a joker
	pip: Pip?,
	band: Band?,
	key: string,
}

export type AuditTables = {
	ladder: { string },
	suitOfCopy: { string },
	pip: { [string]: Pip },
	jokerModes: { string },
	jokerBand: { [string]: Band },
	pipSource: string,
}

local MAX_RANKS = 12 -- ranks = seated seekers + 3, seats 2..9 live -> 5..12
local COPIES = 4

-- "glyph" | "sprite". THE ONLY literal: `PIP_SOURCE` in the return and `TABLES.pipSource` both read
-- this, because two literals is how the renderer and the greyscale gate come to disagree about which
-- asset is actually drawn -- a gate that cannot fire. `faces.spec` asserts the two stay equal.
local PIP_SOURCE: string = "glyph"

local RANK_LADDER: { string } = table.freeze({ "A", "K", "Q", "J", "10", "7", "4", "2", "5", "3", "9", "8" })
local SUIT_OF_COPY: { string } = table.freeze({ "spade", "heart", "club", "diamond" })

local function makePip(suit: Suit, glyph: string, index: number, red: boolean): Pip
	return table.freeze({
		suit = suit,
		silhouette = suit :: string,
		glyph = glyph,
		sprite = table.freeze({ x = (index - 1) * 64, y = 0, w = 64, h = 64 }),
		isRedByDefault = red,
	})
end

local PIP: { [string]: Pip } = table.freeze({
	spade = makePip("spade", utf8.char(0x2660), 1, false),
	heart = makePip("heart", utf8.char(0x2665), 2, true),
	club = makePip("club", utf8.char(0x2663), 3, false),
	diamond = makePip("diamond", utf8.char(0x2666), 4, true),
})

local JOKER_MODES: { string } = table.freeze({ "Wild", "Blocker" })
-- Both modes differ in text AND shape, so the joker pair survives greyscale.
local JOKER_BAND: { [string]: Band } = table.freeze({
	Wild = table.freeze({ text = "WILD", shape = "star" }),
	Blocker = table.freeze({ text = "BLOCK", shape = "star-barred" }),
})
-- Strip copy; Config.Card.STRIP_MAX_CHARS = 34.
local JOKER_EXPLAINER: { [string]: string } = table.freeze({
	Wild = "Joker: counts as any rank.",
	Blocker = "Joker: completes no set.",
})

local TABLES: AuditTables = table.freeze({
	ladder = RANK_LADDER,
	suitOfCopy = SUIT_OF_COPY,
	pip = PIP,
	jokerModes = JOKER_MODES,
	jokerBand = JOKER_BAND,
	pipSource = PIP_SOURCE,
})

local function naturalKey(rankGlyph: string, silhouette: string): string
	return `{rankGlyph}/{silhouette}`
end

local function jokerKey(band: Band): string
	return `JOKER/{band.text}`
end

local function glyphOf(rank: number): string
	local glyph = RANK_LADDER[rank]
	if glyph == nil or rank % 1 ~= 0 then
		error(`Faces.glyphOf: rank {tostring(rank)} is outside 1..{MAX_RANKS}`, 0)
	end
	return glyph
end

local function suitOf(copy: number): Suit
	local name = SUIT_OF_COPY[copy]
	if name == nil or copy % 1 ~= 0 then
		error(`Faces.suitOf: copy {tostring(copy)} is outside 1..{COPIES}`, 0)
	end
	return PIP[name].suit
end

local function jokerFaceOf(mode: string): Face
	local band = JOKER_BAND[mode]
	if band == nil then
		error(`Faces.jokerFaceOf: unmapped joker mode: {tostring(mode)}`, 0)
	end
	return table.freeze({ isJoker = true, rankGlyph = "", pip = nil, band = band, key = jokerKey(band) })
end

local function keyOf(rank: number, copy: number): string
	return naturalKey(glyphOf(rank), PIP[suitOf(copy)].silhouette)
end

-- Rank 0 is the joker and needs the live mode, which is why a third argument exists; `copy` is ignored
-- there. A joker asked for without a mode errors by name rather than guessing a rule.
local function faceOf(rank: number, copy: number, mode: string?): Face
	if rank == 0 then
		if mode == nil then
			error("Faces.faceOf: a joker needs the live joker mode", 0)
		end
		return jokerFaceOf(mode)
	end
	local pip = PIP[suitOf(copy)]
	local rankGlyph = glyphOf(rank)
	return table.freeze({
		isJoker = false,
		rankGlyph = rankGlyph,
		pip = pip,
		band = nil,
		key = naturalKey(rankGlyph, pip.silhouette),
	})
end

-- The drawn asset a suit resolves to under `pipSource`: the codepoint, or the four sprite numbers.
local function drawnAsset(pip: Pip, pipSource: string): string
	if pipSource == "sprite" then
		local s = pip.sprite
		return `{s.x},{s.y},{s.w},{s.h}`
	end
	return pip.glyph
end

-- Walks the tables it is GIVEN, never the module-level ones, so a spec can inject a collapsed copy.
-- Returns the problems and the number of faces visited, so a vacuous audit can be detected.
local function audit(tables: AuditTables): ({ string }, number)
	local problems: { string } = {}
	local visited = 0

	if #tables.ladder < MAX_RANKS then
		table.insert(problems, `short ladder: {#tables.ladder} of {MAX_RANKS}`)
	end
	local glyphSeen: { [string]: boolean } = {}
	for _, glyph in tables.ladder do
		if glyphSeen[glyph] then
			table.insert(problems, `duplicate rank glyph: {glyph}`)
		end
		glyphSeen[glyph] = true
	end

	local silhouetteSeen: { [string]: string } = {}
	local assetSeen: { [string]: string } = {}
	for copy = 1, COPIES do
		local suit = tables.suitOfCopy[copy]
		if suit == nil then
			table.insert(problems, `unmapped copy: {copy}`)
		else
			local pip = tables.pip[suit]
			if pip == nil then
				table.insert(problems, `unmapped suit: {suit}`)
			else
				if silhouetteSeen[pip.silhouette] ~= nil then
					table.insert(problems, `duplicate silhouette: {pip.silhouette}`)
				end
				silhouetteSeen[pip.silhouette] = suit
				local asset = drawnAsset(pip, tables.pipSource)
				if assetSeen[asset] ~= nil then
					table.insert(problems, `duplicate drawn asset: {asset}`)
				end
				assetSeen[asset] = suit
			end
		end
	end

	local keySeen: { [string]: boolean } = {}
	local function visit(key: string)
		visited += 1
		if keySeen[key] then
			table.insert(problems, `duplicate identity key: {key}`)
		end
		keySeen[key] = true
	end

	for _, rankGlyph in tables.ladder do
		for copy = 1, #tables.suitOfCopy do
			local suit = tables.suitOfCopy[copy]
			local pip = tables.pip[suit]
			-- Colour is deliberately absent: only the glyph and the silhouette identify a card.
			visit(naturalKey(rankGlyph, if pip ~= nil then pip.silhouette else `?{suit}`))
		end
	end

	local textSeen: { [string]: boolean } = {}
	local shapeSeen: { [string]: boolean } = {}
	for _, mode in tables.jokerModes do
		local band = tables.jokerBand[mode]
		if band == nil then
			table.insert(problems, `unmapped joker mode: {mode}`)
			visited += 1
		else
			if textSeen[band.text] or shapeSeen[band.shape] then
				table.insert(problems, `duplicate joker band: {mode}`)
			end
			textSeen[band.text] = true
			shapeSeen[band.shape] = true
			visit(jokerKey(band))
		end
	end

	return problems, visited
end

return table.freeze({
	MAX_RANKS = MAX_RANKS,
	JOKER_RANK = 0, -- mirrors the engine's Types.JOKER_RANK; tests/card/faces.spec is the drift test
	-- M-16 flips the single PIP_SOURCE local above to "sprite" if the glyphs fail at 16 px on a phone;
	-- `audit` must stay green under either value. Hearts and spades are never built from rotated Frames.
	PIP_SOURCE = PIP_SOURCE,
	RANK_LADDER = RANK_LADDER,
	SUIT_OF_COPY = SUIT_OF_COPY,
	PIP = PIP,
	JOKER_MODES = JOKER_MODES,
	JOKER_BAND = JOKER_BAND,
	JOKER_EXPLAINER = JOKER_EXPLAINER,
	TABLES = TABLES,
	glyphOf = glyphOf,
	suitOf = suitOf,
	faceOf = faceOf,
	jokerFaceOf = jokerFaceOf,
	keyOf = keyOf,
	audit = audit,
})
