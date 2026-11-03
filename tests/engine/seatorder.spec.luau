--!strict
-- CARD-05 / CARD-06: the seat order is ONE ranking and the dealer is its head.
--
-- The corpus is table-driven because `nextSeatOrder` is pure and takes no clock, which makes a
-- corpus exhaustive rather than representative (research 8.3). Every row carries a `why` naming the
-- rule it pins: a failure message that does not say WHICH rule was violated sends the next reader
-- back to the source. The five inputs research 8.2 flags as unspecified by CARD-05/CARD-06 are rows
-- 1-5 here, so none of them can be quietly re-decided later.
local Rng = require("../../src/server/engine/Rng")
local SeatOrder = require("../../src/server/engine/SeatOrder")
local Test = require("../harness/Test")

type Case = {
	name: string,
	why: string,
	input: SeatOrder.SeatOrderInput,
	expected: { number },
}

local NAN = 0 / 0

-- The five unspecified cases first (research 8.2, in table order), then the buckets they do not reach.
local CASES: { Case } = {
	{
		name = "the first finder is the hider",
		why = "CARD-05 falls through to the highest-placed finisher actually SEATED, and the hider is not seated",
		input = {
			round = 2,
			roster = { 3, 7, 9, 11 },
			hiderId = 7,
			previousFindOrder = { 7, 3, 9 },
			previousSeatOrder = { 7, 3, 9, 11 },
		},
		expected = { 3, 9, 11 },
	},
	{
		name = "zero finishers last round",
		why = "bucket 1 is empty, so the dealer is the head of 'everyone else' by previous seat index; this is reachable in any capped round",
		input = {
			round = 2,
			roster = { 5, 2, 8 },
			hiderId = 8,
			previousFindOrder = {},
			previousSeatOrder = { 2, 5, 8 },
		},
		expected = { 2, 5 },
	},
	{
		name = "three empty-handed seekers, not one",
		why = "CARD-06's 'the empty-handed seeker' is singular only in a clean round; bucket 2 is a list with a key, never an index into 'the' non-finisher",
		input = {
			round = 2,
			roster = { 1, 2, 3, 4, 5 },
			hiderId = 5,
			previousFindOrder = { 2 },
			previousSeatOrder = { 4, 1, 2, 3 },
		},
		expected = { 2, 4, 1, 3 },
	},
	{
		name = "the find order names a departed player",
		why = "the find order is filtered against the live roster BEFORE the head is taken, so a departed finisher never occupies a bucket slot",
		input = {
			round = 2,
			roster = { 1, 2, 3 },
			hiderId = 3,
			previousFindOrder = { 12 },
			previousSeatOrder = { 2, 1, 12 },
		},
		expected = { 2, 1 },
	},
	{
		name = "mass leave: no previous finisher is still in the server",
		why = "the function must still produce a dealer; a nil dealer is a crash one layer up, so everyone falls through to bucket 4 in join order",
		input = {
			round = 2,
			roster = { 20, 21, 22 },
			hiderId = 22,
			previousFindOrder = { 5, 6 },
			previousSeatOrder = { 5, 6, 7 },
			previousHider = 8,
		},
		expected = { 20, 21 },
	},
	{
		name = "the previous hider rejoins the table",
		why = "bucket 3: the previous hider sorts after every seated non-finisher, because he held no cards last round and has no previous seat index",
		input = {
			round = 2,
			roster = { 1, 2, 3, 4 },
			hiderId = 4,
			previousFindOrder = {},
			previousSeatOrder = { 2, 1 },
			previousHider = 3,
		},
		expected = { 2, 1, 3 },
	},
	{
		name = "the previous hider outranks a joiner who joined before him",
		why = "bucket 3 is a bucket of its own, ahead of bucket 4: the previous hider played last round, a joiner did not, so join order cannot put the joiner first",
		input = {
			round = 2,
			roster = { 9, 3, 1, 2, 4 },
			hiderId = 4,
			previousFindOrder = {},
			previousSeatOrder = { 2, 1 },
			previousHider = 3,
		},
		expected = { 2, 1, 3, 9 },
	},
	{
		name = "a joiner sorts after the previous hider, and joiners keep join order",
		why = "bucket 4 is keyed by roster index, which IS join order, so a joiner never outranks a player who was already at the table",
		input = {
			round = 2,
			roster = { 50, 10, 30, 7, 8 },
			hiderId = 7,
			previousFindOrder = {},
			previousSeatOrder = { 8 },
			previousHider = nil,
		},
		expected = { 8, 50, 10, 30 },
	},
	{
		name = "an all-joiner roster keeps join order, not userId order",
		why = "playerId ascending is the final TIEBREAK only; bucket 4's key is join order, so 99 before 11 is correct and sorting by userId would be wrong",
		input = {
			round = 2,
			roster = { 99, 11, 2 },
			previousFindOrder = {},
			previousSeatOrder = {},
			hiderId = 2,
		},
		expected = { 99, 11 },
	},
	{
		name = "a descending previous seat order is preserved",
		why = "within bucket 2 the previous seat index decides, so last round's position is preserved and playerId ascending never overrides it",
		input = {
			round = 2,
			roster = { 1, 9, 5 },
			hiderId = 5,
			previousFindOrder = {},
			previousSeatOrder = { 9, 1 },
		},
		expected = { 9, 1 },
	},
	{
		name = "finishers outrank a seated non-finisher who sat first",
		why = "the buckets are concatenated, not interleaved: a bucket-1 key of 3 still beats a bucket-2 key of 1",
		input = {
			round = 2,
			roster = { 1, 2, 3, 4 },
			hiderId = 4,
			previousFindOrder = { 9, 3, 2 },
			previousSeatOrder = { 1, 2, 3, 9 },
		},
		expected = { 3, 2, 1 },
	},
}

local function countEligible(case: Case): number
	local n = 0
	for _, id in case.input.roster do
		if case.input.hiderId == nil or id ~= case.input.hiderId then
			n += 1
		end
	end
	return n
end

return function(t: Test.Runner)
	for _, case in CASES do
		t.test(case.name, function()
			local order = SeatOrder.nextSeatOrder(case.input)
			t.deepEqual(order, case.expected, case.why)
			-- dealer == seatOrder[1], always: CARD-05 and CARD-06 are one function (research 8.1).
			t.equal(SeatOrder.dealerOf(order), case.expected[1], "the dealer is the head of the seat order")
		end)
	end

	-- Written as loops over CASES so that a row added later cannot forget any of these three.
	t.test("the hider never appears in the order, for every corpus row", function()
		for _, case in CASES do
			for _, id in SeatOrder.nextSeatOrder(case.input) do
				t.truthy(
					case.input.hiderId == nil or id ~= case.input.hiderId,
					`{case.name}: the hider does not play cards, so he is in no bucket`
				)
			end
		end
	end)

	t.test("no player appears twice, for every corpus row", function()
		for _, case in CASES do
			local seen: { [number]: boolean } = {}
			for _, id in SeatOrder.nextSeatOrder(case.input) do
				t.falsy(seen[id], `{case.name}: player {id} was seated twice`)
				seen[id] = true
			end
		end
	end)

	t.test("the order holds every eligible roster member, for every corpus row", function()
		-- The case that catches a bucketing bug which silently drops a player: the engine would then
		-- deal to fewer seats than there are seekers and nothing else in the phase would notice.
		for _, case in CASES do
			t.equal(
				#SeatOrder.nextSeatOrder(case.input),
				countEligible(case),
				`{case.name}: roster minus the hider must all be seated`
			)
		end
	end)

	local function roundOne(seed: number?, roster: { number }): { number }
		local input: any = {
			round = 1,
			roster = roster,
			hiderId = roster[1],
			previousFindOrder = {},
			previousSeatOrder = {},
		}
		if seed ~= nil then
			input.rng = Rng.new(seed)
		end
		return SeatOrder.nextSeatOrder(input)
	end

	t.test("round 1 is the same function with a seeded shuffle", function()
		local roster = { 1, 2, 3, 4 }
		local a = roundOne(99, roster)
		t.deepEqual(roundOne(99, roster), a, "the same seed must replay the identical order")
		-- Permutation of the roster minus the hider: length AND set membership, so a shuffle that
		-- dropped or invented a player fails here rather than in Phase 6.
		t.equal(#a, 3)
		local seen: { [number]: boolean } = {}
		for _, id in a do
			seen[id] = true
		end
		t.deepEqual(seen, { [2] = true, [3] = true, [4] = true })
	end)

	t.test("round 1 with a different seed gives a different order", function()
		-- Nine seekers, not three: with three there are only six permutations, so a collision between
		-- two fixed seeds is ordinary rather than evidence of a no-op shuffle. Two further seed pairs
		-- are asserted so this cannot pass on one lucky pair.
		local roster = { 70, 11, 22, 33, 44, 55, 66, 77, 88, 99 }
		local pairs2 = { { 99, 100 }, { 1, 2 }, { 12345, 999 } }
		for _, p in pairs2 do
			local a, b = roundOne(p[1], roster), roundOne(p[2], roster)
			local differs = false
			for i = 1, #a do
				if a[i] ~= b[i] then
					differs = true
				end
			end
			t.truthy(differs, `seeds {p[1]} and {p[2]} produced the identical order: the shuffle may be a no-op`)
		end
	end)

	t.test("round 1 without an rng errors rather than falling back", function()
		-- A silent fallback to the global random generator would make round 1 unreproducible and
		-- break every seeded trial of the pacing simulator.
		t.throws(function()
			roundOne(nil, { 1, 2, 3, 4 })
		end, "round 1 requires an rng")
	end)

	t.test("rounds after 1 use no randomness", function()
		-- No `rng` field at all. A function that reached for the rng on this path would crash here.
		local input: SeatOrder.SeatOrderInput = {
			round = 2,
			roster = { 4, 5, 6, 7 },
			hiderId = 7,
			previousFindOrder = { 6 },
			previousSeatOrder = { 5, 4, 6 },
		}
		local first = SeatOrder.nextSeatOrder(input)
		t.deepEqual(SeatOrder.nextSeatOrder(input), first, "rounds after 1 are a pure function of their input")
		t.deepEqual(first, { 6, 5, 4 })
	end)

	t.test("an unusable round number falls to the deterministic path instead of erroring", function()
		local bad: { any } = { NAN, 2.5, "2", nil, math.huge, true }
		for i, round in bad do
			local input: any = {
				round = round,
				roster = { 1, 2, 3 },
				hiderId = 3,
				previousFindOrder = {},
				previousSeatOrder = { 2, 1 },
			}
			t.deepEqual(SeatOrder.nextSeatOrder(input), { 2, 1 }, `unusable round #{i} must not need an rng`)
		end
		-- A nil in the list above would be a hole that iteration skips, so the missing round is its own case.
		local noRound: any = {
			roster = { 1, 2, 3 },
			hiderId = 3,
			previousFindOrder = {},
			previousSeatOrder = { 2, 1 },
		}
		t.deepEqual(SeatOrder.nextSeatOrder(noRound), { 2, 1 }, "a missing round must not need an rng either")
	end)

	t.test("a malformed roster entry is ignored, not fatal", function()
		-- T-2-07: one bad entry must never take down a round.
		local input: any = {
			round = 2,
			roster = { 1, "x", 2, 1.5, NAN, math.huge, true, 3 } :: { any },
			hiderId = 3,
			previousFindOrder = {},
			previousSeatOrder = {},
		}
		t.deepEqual(SeatOrder.nextSeatOrder(input), { 1, 2 }, "non-integer entries are skipped, the rest are seated")
	end)

	t.test("a duplicated roster entry seats that player once", function()
		local input: any = {
			round = 2,
			roster = { 1, 1, 2, 3 },
			hiderId = 3,
			previousFindOrder = {},
			previousSeatOrder = {},
		}
		t.deepEqual(SeatOrder.nextSeatOrder(input), { 1, 2 }, "seating one player twice would deal him two hands")
	end)

	t.test("a duplicated previous-list entry cannot hand one player two slots", function()
		local input: any = {
			round = 2,
			roster = { 1, 2, 3 },
			hiderId = 3,
			previousFindOrder = { 2, 2 },
			previousSeatOrder = { 1, 1, 2 },
		}
		t.deepEqual(SeatOrder.nextSeatOrder(input), { 2, 1 }, "first occurrence wins in every previous list")
	end)

	t.test("missing previous lists behave as empty ones", function()
		local input: any = { round = 2, roster = { 8, 9, 10 }, hiderId = 10 }
		t.deepEqual(SeatOrder.nextSeatOrder(input), { 8, 9 }, "a nil list must not crash a round")
		local garbage: any = {
			round = 2,
			roster = { 8, 9, 10 },
			hiderId = 10,
			previousFindOrder = "nonsense",
			previousSeatOrder = 7,
			previousHider = "nobody",
		}
		t.deepEqual(SeatOrder.nextSeatOrder(garbage), { 8, 9 }, "a non-table list must not crash a round either")
	end)

	t.test("a hider who is not in the roster removes nobody", function()
		local input: SeatOrder.SeatOrderInput = {
			round = 2,
			roster = { 1, 2, 3 },
			hiderId = 42,
			previousFindOrder = {},
			previousSeatOrder = { 3, 2, 1 },
		}
		t.deepEqual(SeatOrder.nextSeatOrder(input), { 3, 2, 1 }, "the hider is filtered by identity, not by position")
	end)

	t.test("no eligible seeker gives an empty order and a nil dealer, not an error", function()
		local input: SeatOrder.SeatOrderInput = {
			round = 2,
			roster = { 7 },
			hiderId = 7,
			previousFindOrder = {},
			previousSeatOrder = { 7 },
		}
		local order = SeatOrder.nextSeatOrder(input)
		t.deepEqual(order, {})
		t.equal(SeatOrder.dealerOf(order), nil, "an empty order has no dealer, and saying so is not a crash")
	end)

	t.test("dealerOf is the only way to read the dealer, and it reads the head", function()
		t.equal(SeatOrder.dealerOf({}), nil)
		t.equal(SeatOrder.dealerOf({ 4 }), 4)
		t.equal(SeatOrder.dealerOf({ 4, 5, 6 }), 4)
	end)

	t.test("each call returns a fresh order (a caller cannot poison later rounds)", function()
		local input: SeatOrder.SeatOrderInput = {
			round = 2,
			roster = { 1, 2, 3 },
			hiderId = 3,
			previousFindOrder = {},
			previousSeatOrder = { 2, 1 },
		}
		local first = SeatOrder.nextSeatOrder(input)
		first[1] = 999
		t.deepEqual(SeatOrder.nextSeatOrder(input), { 2, 1 })
	end)

	t.test("SeatOrder exports exactly nextSeatOrder and dealerOf", function()
		-- Two ways to compute a seat order is one too many: the dealer rule lives nowhere else.
		local keys: { string } = {}
		for k in SeatOrder :: any do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		t.deepEqual(keys, { "dealerOf", "nextSeatOrder" })
	end)
end
