--!strict
-- CARD-01 / CARD-07 / CARD-10 / CARD-12 at the hand level. Every row asserts the exact `retired` ID
-- list, not merely the counts: naturals-first is a claim about WHICH four cards leave.
local Hand = require("../../src/server/engine/Hand")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

-- Card ID `i` has rank `spec[i]`, so a case states its shape inline: `{ 0, 3, 3, 3, 0 }` is
-- "joker, three of rank 3, joker" and a failure message points at a shape, not at a fixture name.
local function handOf(spec: { Types.Rank }): ({ Types.Rank }, { Types.CardId })
	local rankOf: { Types.Rank } = {}
	local hand: { Types.CardId } = {}
	for i, rank in spec do
		rankOf[i] = rank
		hand[i] = i
	end
	return rankOf, hand
end

type Row = {
	name: string,
	spec: { Types.Rank },
	mode: Types.JokerMode,
	rank: Types.Rank,
	naturals: number,
	jokers: number,
	retired: { Types.CardId },
	fifth: Types.CardId,
}

-- Research 3.3's choice table, row by row. `spec` deliberately scatters the cards of the completing
-- rank so the ascending-ID ordering inside each group is observable.
local ROWS: { Row } = {
	{
		name = "4 naturals + 1 other natural, Wild",
		spec = { 5, 3, 3, 3, 3 },
		mode = "Wild",
		rank = 3,
		naturals = 4,
		jokers = 0,
		retired = { 2, 3, 4, 5 },
		fifth = 1,
	},
	{
		-- Naturals-first means a HELD joker is not spent when four naturals are available.
		name = "4 naturals + 1 joker, Wild: the joker is the fifth",
		spec = { 3, 0, 3, 3, 3 },
		mode = "Wild",
		rank = 3,
		naturals = 4,
		jokers = 0,
		retired = { 1, 3, 4, 5 },
		fifth = 2,
	},
	{
		-- 02-VALIDATION.md, verbatim: "3 naturals + 2 jokers must retire exactly 3 naturals + 1
		-- joker and keep a joker as the 5th".
		name = "3 naturals + 2 jokers, Wild",
		spec = { 0, 3, 3, 3, 0 },
		mode = "Wild",
		rank = 3,
		naturals = 3,
		jokers = 1,
		retired = { 2, 3, 4, 1 },
		fifth = 5,
	},
	{
		name = "2 naturals + 2 jokers + 1 other natural, Wild",
		spec = { 0, 3, 5, 0, 3 },
		mode = "Wild",
		rank = 3,
		naturals = 2,
		jokers = 2,
		retired = { 2, 5, 1, 4 },
		fifth = 3,
	},
	{
		name = "4 naturals + 1 joker, Blocker",
		spec = { 3, 0, 3, 3, 3 },
		mode = "Blocker",
		rank = 3,
		naturals = 4,
		jokers = 0,
		retired = { 1, 3, 4, 5 },
		fifth = 2,
	},
}

return function(t: Test.Runner)
	t.test("the retirement table from research 3.3, row by row", function()
		for _, row in ROWS do
			local rankOf, hand = handOf(row.spec)
			local got = Hand.detectCompletion(rankOf, hand, row.mode)
			t.truthy(got, `{row.name}: expected a completion`)
			local c = got :: Hand.Completion
			t.equal(c.rank, row.rank, `{row.name}: wrong completing rank`)
			t.equal(c.naturalsUsed, row.naturals, `{row.name}: wrong naturalsUsed`)
			t.equal(c.jokersUsed, row.jokers, `{row.name}: wrong jokersUsed`)
			t.deepEqual(c.retired, row.retired, `{row.name}: wrong retired IDs (naturals first, each group ascending)`)
			t.equal(c.fifth, row.fifth, `{row.name}: wrong fifth`)
		end
	end)

	t.test("a joker can never complete a set in Blocker mode", function()
		-- 3 naturals + 2 jokers completes in Wild and must not in Blocker.
		local rankOf, hand = handOf({ 0, 3, 3, 3, 0 })
		t.truthy(Hand.detectCompletion(rankOf, hand, "Wild"), "Wild: 3 naturals + 2 jokers must complete")
		t.equal(Hand.detectCompletion(rankOf, hand, "Blocker"), nil, "Blocker: a joker must not complete a set")
	end)

	t.test("a hand that does not complete returns nil", function()
		-- 2 + 2 of two ranks plus a joker: neither rank can reach 4.
		local rankOf, hand = handOf({ 1, 1, 2, 2, 0 })
		t.equal(Hand.detectCompletion(rankOf, hand, "Wild"), nil, "2+2+1j must not complete in Wild")
		t.equal(Hand.detectCompletion(rankOf, hand, "Blocker"), nil, "2+2+1j must not complete in Blocker")
	end)

	t.test("a hand of the wrong size is a loud caller bug", function()
		local rankOf, hand = handOf({ 3, 3, 3, 3 })
		t.throws(function()
			Hand.detectCompletion(rankOf, hand, "Wild")
		end, "hand must hold 5")
	end)
end
