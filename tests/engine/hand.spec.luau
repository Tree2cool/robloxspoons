--!strict
-- CARD-01 / CARD-07 / CARD-10 / CARD-12 at the hand level. Every row asserts the exact `retired` ID
-- list, not merely the counts: naturals-first is a claim about WHICH four cards leave. Every
-- rejection asserts its own message, and the uniqueness theorem is proven by enumeration and then
-- falsified, so neither can be vacuous.
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
-- rank so the ascending-ID ordering inside each group is observable rather than accidental.
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
		-- 02-VALIDATION.md's falsifiability row, verbatim: "3 naturals + 2 jokers must retire
		-- exactly 3 naturals + 1 joker and keep a joker as the 5th".
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
		name = "3 naturals + 1 joker + 1 other natural, Wild",
		spec = { 5, 3, 0, 3, 3 },
		mode = "Wild",
		rank = 3,
		naturals = 3,
		jokers = 1,
		retired = { 2, 4, 5, 3 },
		fifth = 1,
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

-- The three shapes that complete only because a joker stands in for a natural. CARD-12 says each
-- must be dead in Blocker mode.
local JOKER_COMPLETING: { { Types.Rank } } = {
	{ 0, 3, 3, 3, 0 }, -- 3 naturals + 2 jokers
	{ 5, 3, 0, 3, 3 }, -- 3 naturals + 1 joker + 1 other
	{ 0, 3, 5, 0, 3 }, -- 2 naturals + 2 jokers + 1 other
}

local NON_COMPLETING: { { label: string, spec: { Types.Rank } } } = {
	{ label = "2 + 2 of two ranks + 1 joker", spec = { 1, 1, 2, 2, 0 } },
	{ label = "3 + 1 + 1 of three ranks", spec = { 1, 2, 1, 3, 1 } },
	{ label = "2 + 2 + 1 of three ranks", spec = { 1, 2, 1, 2, 3 } },
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
			t.equal(c.naturalsUsed + c.jokersUsed, 4, `{row.name}: a set is four cards`)
			t.deepEqual(c.retired, row.retired, `{row.name}: wrong retired IDs (naturals first, each group ascending)`)
			t.equal(c.fifth, row.fifth, `{row.name}: wrong fifth`)
		end
	end)

	t.test("a hand that does not complete returns nil, in both modes", function()
		for _, case in NON_COMPLETING do
			local rankOf, hand = handOf(case.spec)
			-- The two modes are passed as LITERALS rather than iterated out of a table: Luau widens
			-- a singleton-string literal table to `{ string }`, and the widened element no longer
			-- satisfies `JokerMode` at the call site (plan 02-01 hit the same TypeError).
			t.equal(Hand.detectCompletion(rankOf, hand, "Wild"), nil, `{case.label} must not complete in Wild`)
			t.equal(Hand.detectCompletion(rankOf, hand, "Blocker"), nil, `{case.label} must not complete in Blocker`)
		end
	end)

	t.test("a joker can never complete a set in Blocker mode", function()
		-- Asserted as a PAIR inside one case, so the asymmetry is a single failure rather than two
		-- independent ones that could drift apart.
		for _, spec in JOKER_COMPLETING do
			local rankOf, hand = handOf(spec)
			local wild = Hand.detectCompletion(rankOf, hand, "Wild")
			t.truthy(wild, `Wild: this shape must complete`)
			t.equal((wild :: Hand.Completion).jokersUsed >= 1, true, "Wild: this shape must spend a joker")
			t.equal(Hand.detectCompletion(rankOf, hand, "Blocker"), nil, "Blocker: a joker must not complete a set")
			t.deepEqual(Hand.qualifyingRanks(rankOf, hand, "Blocker"), {}, "Blocker: no rank qualifies")
		end
	end)

	t.test("the same EngineConfig value selects the mode, in one process", function()
		-- A module-level mode constant could not satisfy this case: both branches run here, back to
		-- back, inside one process, selected only by the value passed in.
		local config: Types.EngineConfig = { ranks = 4, jokers = 2, jokerMode = "Wild", antiLivelockValve = true }
		local rankOf, hand = handOf({ 0, 3, 3, 3, 0 })

		local asWild = Hand.detectCompletion(rankOf, hand, config.jokerMode)
		local flipped: Types.EngineConfig =
			{ ranks = config.ranks, jokers = config.jokers, jokerMode = "Blocker", antiLivelockValve = true }
		local asBlocker = Hand.detectCompletion(rankOf, hand, flipped.jokerMode)

		t.truthy(asWild, "the Wild config value must complete this hand")
		t.equal(asBlocker, nil, "the Blocker config value must not complete the same hand")
		t.equal(asWild ~= asBlocker, true, "the two config values must not produce the same result")
	end)

	t.test("the completing rank is unique for every reachable 5-card hand at j <= 2 (exhaustive)", function()
		-- ranks = 3, jokers = 2, so T = 14 and there are exactly C(14,5) = 2002 five-card hands.
		-- Enumerating ALL of them is the proof of research 3.3's uniqueness claim; nothing here
		-- assumes an arbitrary pick is safe.
		local rankOf: { Types.Rank } = { 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, Types.JOKER_RANK, Types.JOKER_RANK }
		local T = #rankOf
		t.equal(T, 4 * 3 + Types.MAX_JOKERS, "the enumeration deck must be 4 * ranks + jokers")

		local subsetsChecked = 0
		local wildCompletions = 0
		local blockerCompletions = 0
		for a = 1, T - 4 do
			for b = a + 1, T - 3 do
				for c = b + 1, T - 2 do
					for d = c + 1, T - 1 do
						for e = d + 1, T do
							local hand = { a, b, c, d, e }
							subsetsChecked += 1
							local wild = Hand.qualifyingRanks(rankOf, hand, "Wild")
							local blocker = Hand.qualifyingRanks(rankOf, hand, "Blocker")
							t.equal(#wild <= 1, true, `Wild: hand {table.concat(hand, ",")} satisfied {#wild} ranks`)
							t.equal(
								#blocker <= 1,
								true,
								`Blocker: hand {table.concat(hand, ",")} satisfied {#blocker} ranks`
							)
							if #wild == 1 then
								wildCompletions += 1
								-- Uniqueness is what makes this call safe: the tripwire cannot fire.
								local got = Hand.detectCompletion(rankOf, hand, "Wild")
								t.truthy(got, "a qualifying rank must yield a Completion")
								t.equal(
									(got :: Hand.Completion).rank,
									wild[1],
									"the Completion must use the qualifying rank"
								)
							end
							if #blocker == 1 then
								blockerCompletions += 1
							end
						end
					end
				end
			end
		end

		-- Without these the loop bounds could be wrong and the theorem check would be vacuous --
		-- the exact failure mode Phase 1 verification found twice. The three expected counts were
		-- derived combinatorially, independently of this code: C(14,5) = 2002; the Blocker hands are
		-- "all four of one rank plus any other card" = 3 * 10 = 30; the Wild hands are
		-- 30 + (a=3, j=1) 3*4*8*2 = 192 + (a=3, j=2) 3*4 = 12 + (a=2, j=2, +1 other) 3*6*8 = 144.
		t.equal(subsetsChecked, 2002, "the enumeration must visit every 5-card subset of the 14-card deck")
		t.truthy(wildCompletions >= 1, "an enumeration that saw no completion at all proves nothing")
		t.equal(wildCompletions, 378, "Wild completions over all 2002 hands")
		t.equal(blockerCompletions, 30, "Blocker completions over all 2002 hands")
	end)

	t.test("the uniqueness tripwire can fire (j = 3 falsification)", function()
		-- Two ranks can only qualify at once if the hand holds THREE jokers, so build exactly that:
		-- one natural of rank 1, one of rank 2, three jokers. Both then satisfy `a >= 1 and a + 3 >= 4`.
		-- This hand is unreachable in the shipped build because `Pool.validate` rejects `jokers > 2`
		-- as `TooManyJokers`, and that is precisely why the tripwire must be proven to fire here:
		-- otherwise a future `j >= 3` pool would silently pick an arbitrary rank, and the mutation
		-- that turned the tripwire into a tiebreak would never turn this suite red.
		local rankOf, hand = handOf({ 1, 2, Types.JOKER_RANK, Types.JOKER_RANK, Types.JOKER_RANK })
		local qual = Hand.qualifyingRanks(rankOf, hand, "Wild")
		t.equal(#qual, 2, "at j = 3 both ranks must qualify")
		t.deepEqual(qual, { 1, 2 }, "qualifyingRanks must report both, ascending")
		t.throws(function()
			Hand.detectCompletion(rankOf, hand, "Wild")
		end, "completing rank is not unique")
		-- Blocker is immune: jokers contribute nothing, so no rank reaches four.
		t.equal(Hand.detectCompletion(rankOf, hand, "Blocker"), nil, "Blocker: three jokers complete nothing")
	end)

	t.test("a hand of the wrong size is a loud caller bug", function()
		-- Research 5: completion is checked ONLY on draw, so `#hand` is 5 at every legitimate call.
		-- Any other size means the caller broke CARD-01's hand-size invariant; swallowing it as nil
		-- would hide a real defect and surface later as card loss.
		local fourRankOf, fourHand = handOf({ 3, 3, 3, 3 })
		t.throws(function()
			Hand.detectCompletion(fourRankOf, fourHand, "Wild")
		end, "hand must hold 5")

		local sixRankOf, sixHand = handOf({ 3, 3, 3, 3, Types.JOKER_RANK, Types.JOKER_RANK })
		t.throws(function()
			Hand.detectCompletion(sixRankOf, sixHand, "Blocker")
		end, "hand must hold 5")
	end)

	t.test("retirement is deterministic across repeated calls", function()
		-- CONTEXT requires a failing simulator trial to paste straight into a unit test, which is
		-- only true if the same inputs always retire the same four cards in the same order.
		local rankOf, hand = handOf({ 0, 3, 3, 3, 0 })
		local first: { Types.CardId }? = nil
		for i = 1, 5 do
			local got = Hand.detectCompletion(rankOf, hand, "Wild")
			t.truthy(got, `call {i}: expected a completion`)
			local retired = (got :: Hand.Completion).retired
			if first == nil then
				first = retired
			else
				t.deepEqual(retired, first, `call {i}: retired set diverged from call 1`)
			end
		end
		t.deepEqual(first, { 2, 3, 4, 1 }, "the retired set must be the naturals ascending then the lowest joker")
	end)

	t.test("groupsOf never keys the joker rank", function()
		-- A groupsOf that counted jokers as rank 0 would make plan 02-09's greedy bot treat "rank 0"
		-- as a collectable rank and chase a set that cannot exist (research Pitfall 2).
		local rankOf, hand = handOf({ 0, 3, 3, 5, 0 })
		local counts, jokerCount = Hand.groupsOf(rankOf, hand)
		t.equal(counts[Types.JOKER_RANK], nil, "JOKER_RANK must never be a key of naturalCounts")
		t.equal(jokerCount, 2, "the joker count is returned separately")
		t.equal(counts[3], 2, "two naturals of rank 3")
		t.equal(counts[5], 1, "one natural of rank 5")
		local keys = 0
		for _ in counts do
			keys += 1
		end
		t.equal(keys, 2, "only the natural ranks present are keyed")
	end)
end
