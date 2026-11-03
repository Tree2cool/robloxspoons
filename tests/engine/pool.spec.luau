--!strict
-- CARD-09 and CARD-04 (plan 02-04). House style from tests/net/validate.spec.luau: every rejection
-- asserts its own locked reason string, never just "it was refused".
--
-- WHY THIS FILE IS SHAPED THE WAY IT IS. Research section 10 names the trap: a re-shuffle loop whose
-- completeness predicate ALWAYS RETURNS FALSE looks identical to a correct one -- same output,
-- always one attempt, suite green -- and ships exactly the bug CARD-09 exists to prevent. So two
-- cases here exist only to prove the predicate can fire: a hardcoded crafted seed that needs a
-- second attempt, and a corpus counter that must exceed the number of deals. Cases 7 and 8. Without
-- them case 9 is unfalsifiable.
local fs = require("@lune/fs")

local Pool = require("../../src/server/engine/Pool")
local Rng = require("../../src/server/engine/Rng")
local Types = require("../../src/server/engine/Types")
local Test = require("../harness/Test")

local SPEC_PATH = "tests/engine/pool.spec.luau"
local PERMUTATION_ITERATIONS = 300
local DEAL_ITERATIONS = 400
local CORPUS_SEEDS = 400
local SEARCH_SEEDS = 5000
-- The joker modes are always passed as LITERALS at the call site, never iterated out of a table and
-- never returned from a helper: Luau widens a singleton-string literal to `string` in both of those
-- positions, and the widened type then no longer satisfies JokerMode (the same note sits in
-- tests/engine/invariants.spec.luau).

-- Every config in this file is built here, which is the point of case 0: `poolConfig` is the only
-- place amendment A3's `seatCount = n - 1` is written, so `n` is PLAYERS IN THE ROUND and the hider
-- is already subtracted. `k` may be negative in this helper's callers purely to manufacture the
-- RanksBelowSeats pool; no shipped caller does that.
local function pool(seatCount: number, k: number, j: number, mode: Types.JokerMode): (Types.EngineConfig, number)
	local config, seats = Pool.poolConfig(seatCount + 1, k, j, mode)
	assert(seats == seatCount, "poolConfig disagreed with the requested seatCount")
	return config, seats
end

local function handIdsFor(seat: number): { Types.CardId }
	local ids: { Types.CardId } = {}
	for slot = 1, Types.HAND_SIZE do
		table.insert(ids, (seat - 1) * Types.HAND_SIZE + slot)
	end
	return ids
end

local function countOccurrences(haystack: string, needle: string): number
	local total = 0
	local from = 1
	while true do
		local found = string.find(haystack, needle, from, true)
		if found == nil then
			return total
		end
		total += 1
		from = found + 1
	end
end

return function(t: Test.Runner)
	-- 0 ------------------------------------------------------------------------------------------
	t.test("poolConfig writes amendment A3's arithmetic once", function()
		for n = 3, 10 do
			for k = 0, 2 do
				local config, seatCount = Pool.poolConfig(n, k, 1, "Wild")
				t.equal(seatCount, n - 1, `n={n}: seatCount is SEATED SEEKERS, the hider plays no cards (A3)`)
				t.equal(config.ranks, n - 1 + k, `n={n}, k={k}: ranks = seatCount + k`)
				t.equal(config.jokers, 1, `n={n}: jokers passes through`)
				t.equal(config.jokerMode, "Wild", `n={n}: jokerMode passes through`)
				t.equal(config.antiLivelockValve, true, `n={n}: poolConfig sets the shipped valve position (A7)`)
			end
		end
		-- Outside 3..10 is not a round at all (CLAUDE.md: 3-player minimum, 10-player cap).
		t.throws(function()
			Pool.poolConfig(2, 1, 1, "Wild")
		end, "players in round")
		t.throws(function()
			Pool.poolConfig(11, 1, 1, "Wild")
		end, "players in round")
		t.throws(function()
			Pool.poolConfig(4.5, 1, 1, "Wild")
		end, "players in round")

		-- Research OQ-B: this off-by-one shifts the chosen pool by a full notch, so it is not enough
		-- that poolConfig is right -- nothing else may compute n - 1 or build a config by hand. A
		-- hand-built EngineConfig must set `antiLivelockValve` or --!strict rejects it, so zero
		-- occurrences of that assignment in this file proves every case above went through
		-- poolConfig. The needle is concatenated so this assertion is not its own counterexample.
		local source = fs.readFile(SPEC_PATH)
		local needle = "antiLivelockValve" .. " ="
		t.equal(
			countOccurrences(source, needle),
			0,
			`{SPEC_PATH} hand-builds an EngineConfig; every config in this spec must come from Pool.poolConfig`
		)
	end)

	-- 1 ------------------------------------------------------------------------------------------
	t.test("circulation is 4k + j exactly", function()
		-- Amendment A5. This is what makes CARD-04 a computation rather than a claim: the circulating
		-- supply is known before any card moves, and research 4.1 shows draw, pass and completion
		-- are all net zero on it.
		for _, seatCount in { 2, 5, 9 } do
			for k = 0, 3 do
				for j = 0, 2 do
					local config, seats = pool(seatCount, k, j, "Wild")
					t.equal(
						Pool.circulationOf(config, seats),
						4 * k + j,
						`seats={seatCount}, k={k}, j={j}: circulation must be 4k + j`
					)
				end
			end
		end
	end)

	-- 2 ------------------------------------------------------------------------------------------
	t.test("an invalid pool is rejected by its own name", function()
		local function expectReason(config: Types.EngineConfig, seatCount: number, reason: string, label: string)
			local ok, got = Pool.validate(config, seatCount)
			t.equal(ok, false, `{label}: should be rejected`)
			t.equal(got, reason, `{label}: wrong rejection reason`)
		end

		local dead, deadSeats = pool(9, 0, 0, "Wild")
		expectReason(dead, deadSeats, "DeadPool", "k=0, j=0 at 9 seats")

		-- k = -1 manufactures ranks = 8 against 9 seats. Reported as RanksBelowSeats even though it
		-- also drives circulation negative: the thin-pool diagnosis is the useful one, and the order
		-- inside validate is what guarantees it.
		local thin, thinSeats = pool(9, -1, 0, "Wild")
		expectReason(thin, thinSeats, "RanksBelowSeats", "ranks=8 at 9 seats")

		local jokey, jokeySeats = pool(9, 2, 3, "Wild")
		expectReason(jokey, jokeySeats, "TooManyJokers", "j=3 reopens the research 3.3 proofs")

		-- BadConfig: a pool that is not a pool. Built through poolConfig and then deliberately
		-- corrupted, so the corruption is visible rather than smuggled in by a hand-built literal.
		local chaos, chaosSeats = pool(9, 2, 1, "Wild")
		chaos.jokerMode = "Chaos" :: any
		expectReason(chaos, chaosSeats, "BadConfig", "jokerMode=Chaos")

		local fractional, fractionalSeats = pool(9, 2, 1, "Wild")
		fractional.ranks = 11.5
		expectReason(fractional, fractionalSeats, "BadConfig", "fractional ranks")

		local negative, negativeSeats = pool(9, 2, 1, "Wild")
		negative.jokers = -1
		expectReason(negative, negativeSeats, "BadConfig", "negative jokers")

		local seatless = pool(9, 2, 1, "Wild")
		expectReason(seatless, 0, "BadConfig", "zero seated seekers")

		local good, goodSeats = pool(9, 2, 1, "Wild")
		local ok, reason = Pool.validate(good, goodSeats)
		t.equal(ok, true, "ranks=11, jokers=1 at 9 seats is the selected pool and must validate")
		t.equal(reason, nil, "an accepted pool reports no reason")
	end)

	-- 3 ------------------------------------------------------------------------------------------
	t.test("the dead pool k=0 j=0 is excluded by an assertion, not by a skip", function()
		-- Research 3.1's corollary: every seat holds exactly 4, no inbox is ever non-empty, no draw
		-- is ever legal, and four of a kind is only checked on draw. Measured at 100% stall for
		-- every N from 3 to 10. The cell gets a NAME so the sweep in plan 02-10 reports it as a
		-- category instead of hanging; a silent skip would read as a pass.
		for _, seatCount in { 2, 5, 9 } do
			local config, seats = pool(seatCount, 0, 0, "Wild")
			local ok, reason = Pool.validate(config, seats)
			t.equal(ok, false, `seats={seatCount}: the dead pool must not validate`)
			t.equal(reason, "DeadPool", `seats={seatCount}: must be named DeadPool`)
			t.equal(Pool.circulationOf(config, seats), 0, `seats={seatCount}: nothing circulates`)
			t.throws(function()
				Pool.deal(config, seats, Rng.new(1))
			end, "DeadPool")
		end
	end)

	-- 4 ------------------------------------------------------------------------------------------
	t.test("k >= 1 is the mandatory floor, and k = 0 with j = 1 is legal arithmetic", function()
		-- Amendment A4. `k = 0, j = 1` is one single card circulating among nine seats: it VALIDATES,
		-- because validate's job is arithmetic, and it is still not shippable. At k=0 the CARD-12
		-- blocker variant stalls ~97% at N=10 while the wild variant is fine, so "both variants
		-- behind a flag from the start" would be false there -- the flag would be a cliff. k=0 is
		-- retained only as a documented negative result; the search starts at k=1 (A2, A4).
		local function checkKZero(mode: Types.JokerMode)
			local config, seats = pool(9, 0, 1, mode)
			local ok, reason = Pool.validate(config, seats)
			t.equal(ok, true, `mode={mode}: k=0, j=1 is legal arithmetic (A4 rules it out on PACING, not validity)`)
			t.equal(reason, nil, `mode={mode}: no reason when ok`)
			t.equal(Pool.circulationOf(config, seats), 1, "k=0, j=1 circulates exactly one card among nine seats")
		end
		checkKZero("Wild")
		checkKZero("Blocker")
	end)

	-- 5 ------------------------------------------------------------------------------------------
	local seenPermutations: { [string]: true } = {}
	local distinctPermutations = 0
	t.fuzz("the shuffle is a permutation of the multiset", {
		iterations = PERMUTATION_ITERATIONS,
		gen = function(rng, i)
			local seatCount = rng:nextInt(2, 9)
			local config = pool(seatCount, rng:nextInt(1, 2), rng:nextInt(0, 2), "Wild")
			return { config = config, rankOf = Pool.shuffledRanks(config, rng), i = i }
		end,
		check = function(v)
			local config: Types.EngineConfig = v.config
			local rankOf: { Types.Rank } = v.rankOf
			assert(
				#rankOf == 4 * config.ranks + config.jokers,
				`deck size {#rankOf}, expected {4 * config.ranks + config.jokers}`
			)
			local counts: { [number]: number } = {}
			for _, rank in rankOf do
				counts[rank] = (counts[rank] or 0) + 1
			end
			assert(
				(counts[Types.JOKER_RANK] or 0) == config.jokers,
				`joker count {counts[Types.JOKER_RANK] or 0}, expected {config.jokers}`
			)
			for rank = 1, config.ranks do
				assert((counts[rank] or 0) == 4, `rank {rank} appears {counts[rank] or 0} times, expected 4`)
			end

			-- A shuffledRanks that returned the multiset UNSHUFFLED would satisfy every assertion
			-- above on every iteration, so the permutation itself has to be observed changing.
			local key = table.concat(rankOf, ",")
			if seenPermutations[key] == nil then
				seenPermutations[key] = true
				distinctPermutations += 1
			end
			if v.i == PERMUTATION_ITERATIONS then
				assert(
					distinctPermutations >= 2,
					`only {distinctPermutations} distinct permutation(s) over {PERMUTATION_ITERATIONS} iterations: the shuffle is not shuffling`
				)
			end
		end,
	})

	-- 6 ------------------------------------------------------------------------------------------
	t.test("openingHandIsBad sees all three bad shapes and the mode asymmetry", function()
		local J = Types.JOKER_RANK
		local ids = handIdsFor(1)
		local function expect(rankOf: { Types.Rank }, mode: Types.JokerMode, bad: boolean, label: string)
			t.equal(Pool.openingHandIsBad(rankOf, ids, mode), bad, `{label} ({mode})`)
		end

		-- Shape 1: already complete. Bad in BOTH modes.
		expect({ 2, 2, 2, 2 }, "Wild", true, "4 naturals of one rank")
		expect({ 2, 2, 2, 2 }, "Blocker", true, "4 naturals of one rank")

		-- Shape 2: 3 naturals + 1 joker. The CARD-10 / CARD-12 divergence at the deal: a wild
		-- completes it, a blocker never can. A predicate that ignored `mode` passes the Wild row and
		-- fails the Blocker one.
		expect({ 2, 2, 2, J }, "Wild", true, "3 naturals + 1 joker")
		expect({ 2, 2, 2, J }, "Blocker", false, "3 naturals + 1 joker is a LEGAL opening hand")

		-- Shape 3: 2 naturals + 2 jokers. Research 3.3: at j <= 2 these are the only wild
		-- completions reachable, and a predicate checking only `copies == 4` passes shape 1 while
		-- silently shipping shapes 2 and 3.
		expect({ 2, J, 2, J }, "Wild", true, "2 naturals + 2 jokers")
		expect({ 2, J, 2, J }, "Blocker", false, "2 naturals + 2 jokers is a LEGAL opening hand")

		-- Good hands, in both modes.
		expect({ 2, 2, 2, 5 }, "Wild", false, "3 naturals + 1 unrelated natural")
		expect({ 2, 2, 2, 5 }, "Blocker", false, "3 naturals + 1 unrelated natural")
		expect({ 2, 2, 5, 5 }, "Wild", false, "2 + 2 of two different ranks")
		expect({ 2, 2, 5, 5 }, "Blocker", false, "2 + 2 of two different ranks")
		-- Two jokers and two unrelated naturals: no rank reaches 4 even with both wilds.
		expect({ 2, 5, J, J }, "Wild", false, "1 + 1 naturals + 2 jokers")
	end)

	-- 7 ------------------------------------------------------------------------------------------
	t.test("a crafted deck forces a rejection", function()
		-- The research section 10 mutation proof, half one. At the tightest cell the engine will
		-- actually be asked to run (seatCount = 2, k = 1, j = 2, Wild) some seeds need a second
		-- shuffle. The seed below was found by the deterministic search at the bottom of this case
		-- and is hardcoded so the case no longer depends on a search; the search is then re-run and
		-- asserted to still agree, so a change to Rng's stream reports the NEW seed instead of
		-- quietly going vacuous.
		local forcing = { seed = 14, attempts = 2 } -- hardcoded: the first seed in 1..5000 needing a re-shuffle
		local config, seatCount = pool(2, 1, 2, "Wild")

		local rankOf, attempts = Pool.deal(config, seatCount, Rng.new(forcing.seed))
		t.equal(
			attempts,
			forcing.attempts,
			`seed {forcing.seed} no longer needs {forcing.attempts} attempts; re-run the search below and update the hardcoded seed`
		)
		t.truthy(attempts >= 2, `seed {forcing.seed} must force at least one rejection`)
		for s = 1, seatCount do
			t.equal(
				Pool.openingHandIsBad(rankOf, handIdsFor(s), config.jokerMode),
				false,
				`seed {forcing.seed}: the ACCEPTED deal must still be legal for seat {s}`
			)
		end

		local firstHit = -1
		for candidate = 1, SEARCH_SEEDS do
			local _, candidateAttempts = Pool.deal(config, seatCount, Rng.new(candidate))
			if candidateAttempts >= 2 then
				firstHit = candidate
				break
			end
		end
		t.truthy(
			firstHit ~= -1,
			`the deal predicate never fires: a vacuous predicate is indistinguishable from a correct one (searched {SEARCH_SEEDS} seeds at seats=2, k=1, j=2, Wild)`
		)
		t.equal(firstHit, forcing.seed, "the first forcing seed moved; update the hardcoded seed and its comment")
	end)

	-- 8 ------------------------------------------------------------------------------------------
	t.test("the rejection counter is greater than zero over the corpus", function()
		-- The research section 10 mutation proof, half two: the vacuity assertion. A predicate that
		-- never fires over hundreds of deals is broken, not lucky -- and one that rejects almost
		-- everything is just as broken, so the total is bounded on BOTH sides.
		local config, seatCount = pool(2, 1, 2, "Wild")
		local totalAttempts = 0
		local worst = 0
		for seed = 1, CORPUS_SEEDS do
			local _, attempts = Pool.deal(config, seatCount, Rng.new(seed))
			totalAttempts += attempts
			worst = math.max(worst, attempts)
		end
		t.truthy(
			totalAttempts > CORPUS_SEEDS,
			`{CORPUS_SEEDS} deals took {totalAttempts} attempts: not one rejection fired, so the CARD-09 predicate is vacuous`
		)
		t.truthy(
			totalAttempts < CORPUS_SEEDS * 4,
			`{CORPUS_SEEDS} deals took {totalAttempts} attempts: the predicate rejects nearly everything, which is equally broken`
		)
		-- Research section 10 measured mean 1.13 at ranks=3 (and 1.34 at the even tighter ranks=2),
		-- max 4 attempts over ~14,000 deals. Measured here: 438 attempts over 400 deals = 1.095.
		t.truthy(worst <= Types.MAX_DEAL_ATTEMPTS, `worst case {worst} attempts exceeded the ceiling`)
	end)

	-- 9 ------------------------------------------------------------------------------------------
	t.fuzz("no accepted deal gives any seat a complete or wild-completable opening hand", {
		iterations = DEAL_ITERATIONS,
		gen = function(rng, _i)
			local seatCount = rng:nextInt(2, 9)
			local k = rng:nextInt(1, 2)
			local j = rng:nextInt(0, 2)
			local wild = rng:nextInt(0, 1) == 0
			local config, seats
			if wild then
				config, seats = pool(seatCount, k, j, "Wild")
			else
				config, seats = pool(seatCount, k, j, "Blocker")
			end
			local rankOf, attempts = Pool.deal(config, seats, rng)
			return { config = config, seatCount = seats, rankOf = rankOf, attempts = attempts }
		end,
		check = function(v)
			local config: Types.EngineConfig = v.config
			assert(v.attempts >= 1, `attempt count {v.attempts} must be at least 1`)
			assert(v.attempts <= Types.MAX_DEAL_ATTEMPTS, `attempt count {v.attempts} exceeded the ceiling`)
			assert(#v.rankOf == 4 * config.ranks + config.jokers, "the accepted deal is the wrong size")
			for s = 1, v.seatCount do
				assert(
					not Pool.openingHandIsBad(v.rankOf, handIdsFor(s), config.jokerMode),
					`seats={v.seatCount}, ranks={config.ranks}, jokers={config.jokers}, mode={config.jokerMode}: seat {s} opened complete or wild-completable`
				)
			end
		end,
	})

	-- 10 -----------------------------------------------------------------------------------------
	t.test("every circulating card starts in the dealer's inbox", function()
		-- Research 3.8 plus the locked deal layout: seat s holds ids (s-1)*4+1 .. s*4, so everything
		-- above seatCount*4 is the dealer's inbox -- and that count must BE the circulation. The two
		-- halves are computed independently here (layout arithmetic versus 4k + j) so they cannot
		-- agree by sharing a helper.
		for _, seatCount in { 2, 5, 9 } do
			for k = 1, 2 do
				for j = 0, 2 do
					local config, seats = pool(seatCount, k, j, "Wild")
					local totalCards = 4 * config.ranks + config.jokers
					t.equal(
						totalCards - seats * Types.HAND_SIZE,
						Pool.circulationOf(config, seats),
						`seats={seatCount}, k={k}, j={j}: the dealer's inbox must hold exactly the circulating supply`
					)
				end
			end
		end
	end)

	-- 11 -----------------------------------------------------------------------------------------
	t.test("64 attempts is a loud error, not a silent repair", function()
		-- A stub whose nextInt always returns `lo` makes the ASCENDING Fisher-Yates in shuffledRanks
		-- the identity permutation, so seat 1 is dealt ids 1..4 = four copies of rank 1 on every
		-- attempt and the predicate can never be satisfied. The error text is asserted, not merely
		-- that it threw: research section 10 forbids a "repair" path because editing a bad deal would
		-- bias the deal distribution for the tightest tables, which are exactly the 3-player rounds.
		local stub: Pool.Shuffler = {
			nextUint = function(_self): number
				return 0
			end,
			nextNumber = function(_self): number
				return 0
			end,
			nextInt = function(_self, lo: number, _hi: number): number
				return lo
			end,
		} :: any

		local config, seatCount = pool(2, 1, 0, "Wild")
		t.equal(Pool.circulationOf(config, seatCount), 4, "the forcing config must itself be a valid pool")
		local identity = Pool.shuffledRanks(config, stub)
		t.deepEqual(identity, { 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3 }, "the stub must yield the identity permutation")
		t.throws(function()
			Pool.deal(config, seatCount, stub)
		end, "no legal deal in 64 attempts")
	end)
end
