--!strict
-- RED. These rows are written before `src/server/engine/Pool.luau` exists, so the require below
-- fails the load and the suite goes red for the right reason. Plan 02-04 task 2 grows this file
-- into the full deal corpus (the crafted forcing seed and the rejection counter); what is here is
-- exactly task 1's <behavior> block, one assertion per claim.
local Pool = require("../../src/server/engine/Pool")
local Rng = require("../../src/server/engine/Rng")
local Types = require("../../src/server/engine/Types")
local Test = require("../harness/Test")

return function(t: Test.Runner)
	t.test("circulation is 4k + j", function()
		-- poolConfig(n, k, j, mode): seatCount = n - 1 (amendment A3), ranks = seatCount + k.
		local nine, seats9 = Pool.poolConfig(10, 2, 1, "Wild")
		t.equal(seats9, 9)
		t.equal(nine.ranks, 11)
		t.equal(Pool.circulationOf(nine, seats9), 9, "ranks=11, jokers=1, seats=9 circulates 4*2+1")
		local dead, seatsDead = Pool.poolConfig(10, 0, 0, "Wild")
		t.equal(Pool.circulationOf(dead, seatsDead), 0, "k=0, j=0 circulates nothing")
	end)

	t.test("an invalid pool is rejected by its own name", function()
		local dead = Pool.poolConfig(10, 0, 0, "Wild")
		local ok, reason = Pool.validate(dead, 9)
		t.equal(ok, false)
		t.equal(reason, "DeadPool")

		local thin = Pool.poolConfig(10, -1, 0, "Wild") -- ranks = 8 against 9 seats
		local thinOk, thinReason = Pool.validate(thin, 9)
		t.equal(thinOk, false)
		t.equal(thinReason, "RanksBelowSeats")

		local jokey = Pool.poolConfig(10, 2, 3, "Wild")
		local jokeyOk, jokeyReason = Pool.validate(jokey, 9)
		t.equal(jokeyOk, false)
		t.equal(jokeyReason, "TooManyJokers")

		local good = Pool.poolConfig(10, 2, 1, "Wild")
		local goodOk, goodReason = Pool.validate(good, 9)
		t.equal(goodOk, true)
		t.equal(goodReason, nil)
	end)

	t.test("the shuffle is a permutation of the multiset", function()
		local config = Pool.poolConfig(10, 2, 1, "Wild")
		for seed = 1, 20 do
			local rankOf = Pool.shuffledRanks(config, Rng.new(seed))
			t.equal(#rankOf, 4 * config.ranks + config.jokers, `seed {seed}: wrong deck size`)
			local counts: { [number]: number } = {}
			for _, rank in rankOf do
				counts[rank] = (counts[rank] or 0) + 1
			end
			t.equal(counts[Types.JOKER_RANK], config.jokers, `seed {seed}: joker count`)
			for rank = 1, config.ranks do
				t.equal(counts[rank], 4, `seed {seed}: rank {rank} copies`)
			end
		end
	end)

	t.test("openingHandIsBad sees the bad shapes and the mode asymmetry", function()
		local J = Types.JOKER_RANK
		local ids = { 1, 2, 3, 4 }
		t.equal(Pool.openingHandIsBad({ 2, 2, 2, 2 }, ids, "Wild"), true, "4 naturals, Wild")
		t.equal(Pool.openingHandIsBad({ 2, 2, 2, 2 }, ids, "Blocker"), true, "4 naturals, Blocker")
		t.equal(Pool.openingHandIsBad({ 2, 2, 2, J }, ids, "Wild"), true, "3 naturals + joker, Wild")
		t.equal(Pool.openingHandIsBad({ 2, 2, 2, J }, ids, "Blocker"), false, "3 naturals + joker, Blocker")
		t.equal(Pool.openingHandIsBad({ 2, 2, J, J }, ids, "Wild"), true, "2 naturals + 2 jokers, Wild")
		t.equal(Pool.openingHandIsBad({ 2, 2, 1, 1 }, ids, "Wild"), false, "2 + 2 of two ranks")
		t.equal(Pool.openingHandIsBad({ 2, 2, 2, 1 }, ids, "Wild"), false, "3 naturals + 1 unrelated")
	end)

	t.test("deal accepts only a permutation where no seat opens bad", function()
		local config, seatCount = Pool.poolConfig(3, 1, 2, "Wild")
		for seed = 1, 50 do
			local rankOf, attempts = Pool.deal(config, seatCount, Rng.new(seed))
			t.truthy(attempts >= 1, `seed {seed}: attempts must be at least 1`)
			for s = 1, seatCount do
				local handIds = { (s - 1) * 4 + 1, (s - 1) * 4 + 2, (s - 1) * 4 + 3, (s - 1) * 4 + 4 }
				t.equal(
					Pool.openingHandIsBad(rankOf, handIds, config.jokerMode),
					false,
					`seed {seed}: seat {s} opened with a complete or wild-completable hand`
				)
			end
		end
	end)
end
