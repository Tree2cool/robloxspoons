--!strict
-- `scripts/sim/Bots` (plan 02-09 task 1): the greedy policy and the auto-pass choice.
--
-- The cases pin the CHOICE RULE on exactly specified hands, which is why the states here are
-- hand-built rather than dealt: a dealt round cannot be made to hold "three of rank 5, one of
-- rank 2 and one of rank 7" on demand, and a case that asserted the rule on whatever the deal
-- produced would not be asserting the rule at all. The bots read `state.rankOf`,
-- `state.config.jokerMode` and ONE seat's hand and nothing else, so everything else in the state
-- is filled with legal-looking values.
local Bots = require("../../scripts/sim/Bots")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

local JOKER_RANK = Types.JOKER_RANK

local function stateWith(rankOf: { Types.Rank }, hand: { Types.CardId }, mode: Types.JokerMode): Types.State
	local ranks = 1
	local jokers = 0
	for _, rank in rankOf do
		if rank == JOKER_RANK then
			jokers += 1
		elseif rank > ranks then
			ranks = rank
		end
	end
	local rankInPlay: { number } = table.create(ranks, 0)
	local jokersInPlay = 0
	for _, id in hand do
		local rank = rankOf[id]
		if rank == JOKER_RANK then
			jokersInPlay += 1
		else
			rankInPlay[rank] += 1
		end
	end
	local cnt: { number } = table.create(5, 0)
	for rank = 1, ranks do
		cnt[rankInPlay[rank] + 1] += 1
	end
	local seats: { Types.Seat } = {
		{ id = 1, playerId = 101, live = true, hand = table.clone(hand), inbox = {}, next = 2, prev = 2 },
		{ id = 2, playerId = 102, live = true, hand = {}, inbox = {}, next = 1, prev = 1 },
	}
	return {
		config = { ranks = ranks, jokers = jokers, jokerMode = mode, antiLivelockValve = true },
		seatCount = 2,
		totalCards = #rankOf,
		rankOf = table.clone(rankOf),
		seats = seats,
		liveCount = 2,
		head = 1,
		retired = {},
		terminal = {},
		counters = {
			rankInPlay = rankInPlay,
			jokersInPlay = jokersInPlay,
			cnt = cnt,
			completions = 0,
			churnRemovals = 0,
		},
		valve = {
			rng = Rng.new(1),
			actionsSinceProgress = 0,
			armed = false,
			seen = {},
			seenCount = 0,
			firings = 0,
			seenResets = 0,
			observations = 0,
		},
	}
end

-- rankOf is a deck permutation, so these layouts are chosen so that the card IDS in each group are
-- NOT contiguous: a tie broken by "lowest card id" and a tie broken by "first in hand order" would
-- agree on a contiguous layout and the case would pass for the wrong reason.
-- ids:        1   2   3   4   5   6   7   8
local LAYOUT: { Types.Rank } = { 5, 7, 5, 2, 5, 2, 7, JOKER_RANK }

return function(t: Test.Runner)
	t.test("greedy Wild: three of rank 5, one of rank 2, one of rank 7 -> a size-1 group, lower card id", function()
		-- hand = {1,3,5} (rank 5) + {4} (rank 2) + {2} (rank 7). Two size-1 groups; card 2 < card 4.
		local state = stateWith(LAYOUT, { 1, 3, 5, 4, 2 }, "Wild")
		t.equal(Bots.greedyPass(state, 1), 2)
	end)

	t.test("greedy Wild: two of rank 5, two of rank 2, one of rank 7 -> the only size-1 group", function()
		-- hand = {1,3} (rank 5) + {4,6} (rank 2) + {7} (rank 7). Card 7 is the single size-1 group,
		-- and it is the HIGHEST id in the hand, so a bug that just passed the lowest id would fail.
		local state = stateWith(LAYOUT, { 1, 3, 4, 6, 7 }, "Wild")
		t.equal(Bots.greedyPass(state, 1), 7)
	end)

	t.test("greedy Wild: a joker is never passed while any natural group exists", function()
		-- hand = {1,3,5} (rank 5) + {4} (rank 2) + {8} (joker). The joker is card 8; the rank-2
		-- card is 4. Wild keeps the joker because it completes the rank-5 group.
		local state = stateWith(LAYOUT, { 1, 3, 5, 4, 8 }, "Wild")
		t.equal(Bots.greedyPass(state, 1), 4)
	end)

	t.test("greedy Blocker: the SAME hand passes the joker FIRST", function()
		-- In Blocker a joker can never complete a set, so it is dead weight and goes first. This is
		-- the CARD-12 divergence: one hand, one function, two answers.
		local state = stateWith(LAYOUT, { 1, 3, 5, 4, 8 }, "Blocker")
		t.equal(Bots.greedyPass(state, 1), 8)
	end)

	t.test("greedyPass is deterministic: two calls on the same state agree", function()
		local state = stateWith(LAYOUT, { 1, 3, 5, 4, 2 }, "Wild")
		local first = Bots.greedyPass(state, 1)
		local second = Bots.greedyPass(state, 1)
		t.equal(second, first)
		-- And a freshly built identical state agrees too, so the answer is a function of the hand
		-- and not of anything the first call left behind.
		t.equal(Bots.greedyPass(stateWith(LAYOUT, { 1, 3, 5, 4, 2 }, "Wild"), 1), first)
	end)

	t.test("randomPass is reproducible from a seed and covers the hand", function()
		local state = stateWith(LAYOUT, { 1, 3, 5, 4, 2 }, "Wild")
		t.equal(Bots.randomPass(state, 1, Rng.new(7)), Bots.randomPass(state, 1, Rng.new(7)))

		local rng = Rng.new(12345)
		local seen: { [Types.CardId]: true } = {}
		local distinct = 0
		for _ = 1, 200 do
			local id = Bots.randomPass(state, 1, rng)
			t.truthy(table.find({ 1, 3, 5, 4, 2 }, id) ~= nil, `randomPass returned {id}, not a card in the hand`)
			if seen[id] == nil then
				seen[id] = true
				distinct += 1
			end
		end
		-- 4 of 5 rather than 5 of 5: the bar must be about the choice being spread, not about a
		-- particular generator's 200-draw coverage. At uniform the chance of missing two of five
		-- cards in 200 draws is about 10^-19, so this cannot flake, and a stuck choice fails it.
		t.truthy(distinct >= 4, `randomPass returned only {distinct} distinct cards in 200 draws`)
	end)

	t.test("randomPass draws from the SORTED hand, so the index-to-card map is deterministic", function()
		-- Two states holding the same hand multiset in different ORDERS must make the same choice
		-- from the same seed. Without the sort, the mapping would depend on container order and a
		-- failing sweep seed would not replay.
		local a = stateWith(LAYOUT, { 1, 3, 5, 4, 2 }, "Wild")
		local b = stateWith(LAYOUT, { 2, 4, 5, 3, 1 }, "Wild")
		t.equal(Bots.randomPass(b, 1, Rng.new(99)), Bots.randomPass(a, 1, Rng.new(99)))
	end)
end
