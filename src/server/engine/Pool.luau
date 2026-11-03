--!strict
-- The pool and the deal (CARD-04, CARD-09): build the card multiset, shuffle it so a card id is a
-- deck POSITION rather than a rank, and reject any deal that hands a seat an opening hand which is
-- already complete or completable by a wild it holds.
--
-- 1. PURE ZONE. No Roblox API, no clock, no yields (CLAUDE.md rules 2, 5 and 6). Every random draw
--    arrives through the injected `Rng`; `math` + `bit32` only.
-- 2. CARD IDS ARE SHUFFLED DECK POSITIONS. The returned table IS `State.rankOf`: index = card id,
--    value = rank. Because the permutation is redrawn every round, the id -> rank mapping is
--    re-randomised every round, so an id that ever leaks to a client carries NO rank information
--    (CLAUDE.md rule 3, research Pitfall 6, threat T-2-16). Allocating ids in deck-build order
--    would instead fix `id 7 => rank 2` for the whole match, and closing the whole class costs
--    nothing here, so it is closed rather than left to the one surface that leaks first.
-- 3. THERE IS NO DECK TOP-UP, RE-DEAL OR DRY-DECK PATH, AND THERE MUST NEVER BE ONE. Research 4.1
--    proves circulation is exactly constant under draw, pass and completion and only ever grows
--    (+4 per non-completing removal), so CARD-04's "the deck never runs dry" is simply
--    `circulationOf >= 1` forever -- checked once, before the round starts. A top-up path would be
--    dead code hiding a conservation bug (research 14).
-- 4. REJECTION SAMPLING ONLY, WITH A LOUD CEILING. Research 10 measured 1.00-1.34 attempts (max 4
--    over ~14,000 deals), so `Types.MAX_DEAL_ATTEMPTS = 64` is ~50 standard deviations out and
--    reaching it means a broken predicate, not bad luck (threats T-2-17, T-2-18). `deal` therefore
--    errors there instead of "repairing" a bad permutation, because a repair would bias the deal
--    distribution for the tightest tables -- which are exactly the 3-player rounds.
-- 5. `Rng` IS A FAIRNESS PRNG FOR PLAY, NOT A SECURITY PRIMITIVE (threat T-2-20, accepted). It is
--    seeded xorshift32 and fully predictable from its seed. Never reuse it for a token, a session
--    id, a match code or anything an adversary profits from guessing.
-- 6. `EngineConfig.antiLivelockValve` (amendment A7) is IGNORED here. It is consumed by
--    `Engine.apply` and `Valve`; the pool neither reads nor validates it beyond carrying it.
local Rng = require("./Rng")
local Types = require("./Types")

local JOKER_RANK = Types.JOKER_RANK
local HAND_SIZE = Types.HAND_SIZE
local MAX_JOKERS = Types.MAX_JOKERS
local MAX_DEAL_ATTEMPTS = Types.MAX_DEAL_ATTEMPTS

-- Copies of every natural rank in the pool. Numerically equal to HAND_SIZE and conceptually not:
-- one is how many cards make a set, the other is how many a resting hand holds.
local COPIES_PER_RANK = 4

-- Deliberately duplicated from `src/shared/Config/Limits.luau` rather than required: an engine ->
-- shared require is a cross-mount edge and guard rule R6 fails it. These bound `poolConfig`'s
-- PLAYER COUNT argument only. Nothing in this module ever looks up a seat bound: `seatCount`
-- always arrives as a parameter, and `src/server/core/Admission.luau` stays the only predicate
-- allowed to say that a match may start.
local MIN_PLAYERS_IN_ROUND = 3
local MAX_PLAYERS_IN_ROUND = 10

export type Shuffler = Rng.Rng

-- `4 * (ranks - seatCount) + jokers`, which is `4k + j` exactly (amendment A5). This one line is
-- the whole of CARD-04: it is computable before any card moves, so "the deck never runs dry"
-- becomes arithmetic rather than a claim about the trajectory.
local function circulationOf(config: Types.EngineConfig, seatCount: number): number
	return COPIES_PER_RANK * (config.ranks - seatCount) + config.jokers
end

-- The ONLY place amendment A3's arithmetic is written. `n` is PLAYERS IN THE ROUND; the hider does
-- not play cards, so `seatCount = n - 1` (seated seekers) and `ranks = seatCount + k`. Research
-- flagged this ambiguity as shifting the chosen configuration by a full notch (OQ-B), so the
-- subtraction lives here once: the specs, the simulator and the sweep all build their configs
-- through this call, which makes an off-by-one against A3 a single-site bug instead of a per-caller
-- one. Nothing else in the phase may compute `n - 1` inline.
local function poolConfig(n: number, k: number, j: number, mode: Types.JokerMode): (Types.EngineConfig, number)
	if n % 1 ~= 0 or n < MIN_PLAYERS_IN_ROUND or n > MAX_PLAYERS_IN_ROUND then
		error(
			`Pool.poolConfig: players in round must be an integer in {MIN_PLAYERS_IN_ROUND}..{MAX_PLAYERS_IN_ROUND}, got {tostring(
				n
			)}`
		)
	end
	local seatCount = n - 1
	local config: Types.EngineConfig = {
		ranks = seatCount + k,
		jokers = j,
		jokerMode = mode,
		-- The shipped position (amendment A7). A config built by hand could forget it; one built
		-- here cannot, which is why specs build theirs here.
		antiLivelockValve = true,
	}
	return config, seatCount
end

local function isCount(value: number): boolean
	return value == value and value ~= math.huge and value % 1 == 0 and value >= 0
end

-- Returns `(ok, reason)`; `reason` is nil when ok and otherwise one of exactly FOUR locked strings.
-- Tests assert the string itself, never merely that something was refused, so never reword one.
-- The order is load-bearing: `ranks < seatCount` is reported as RanksBelowSeats even though it also
-- drives circulation negative, because the thin-pool diagnosis is the useful one.
local function validate(config: Types.EngineConfig, seatCount: number): (boolean, string?)
	-- "BadConfig": not a pool at all. Fractional or negative counts, no seated seeker, or a joker
	-- mode outside the two the engine implements.
	if not isCount(config.ranks) or not isCount(config.jokers) or not isCount(seatCount) then
		return false, "BadConfig"
	end
	if seatCount < 1 then
		return false, "BadConfig"
	end
	if config.jokerMode ~= "Wild" and config.jokerMode ~= "Blocker" then
		return false, "BadConfig"
	end
	-- "RanksBelowSeats": research 3.1 Claim 2. The round needs `seatCount - 1` completions and each
	-- completion damages exactly one rank, so `ranks >= seatCount` is what keeps a fully intact rank
	-- available for the last required completion. Below that the theorem does not hold at all.
	if config.ranks < seatCount then
		return false, "RanksBelowSeats"
	end
	-- "TooManyJokers": research 3.3 proves the completing rank is unique and the all-joker set is
	-- unreachable only for `j <= 2`. At `j >= 3` both proofs reopen, so the engine refuses the pool
	-- rather than silently invalidating its own uniqueness assertion downstream.
	if config.jokers > MAX_JOKERS then
		return false, "TooManyJokers"
	end
	-- "DeadPool": at `k = 0, j = 0` every seat holds exactly 4, no inbox is ever non-empty, no draw
	-- is ever legal, and four of a kind is checked only on draw -- a PROVABLE instant deadlock,
	-- measured at 100% stall for every N from 3 to 10 (research 3.1 corollary, amendment A5). It
	-- gets a name so the sweep reports it as a category; it must never be a silent skip.
	if circulationOf(config, seatCount) < 1 then
		return false, "DeadPool"
	end
	return true, nil
end

-- A permutation of the card multiset: COPIES_PER_RANK of each rank 1..ranks, then `jokers` copies
-- of JOKER_RANK. The result IS `rankOf` (see header note 2).
local function shuffledRanks(config: Types.EngineConfig, rng: Shuffler): { Types.Rank }
	local cards: { Types.Rank } = {}
	for rank = 1, config.ranks do
		for _ = 1, COPIES_PER_RANK do
			table.insert(cards, rank)
		end
	end
	for _ = 1, config.jokers do
		table.insert(cards, JOKER_RANK)
	end

	-- Fisher-Yates, ASCENDING: position `i` draws its occupant from the un-fixed tail `[i, n]`.
	-- The direction is not cosmetic. A stub `rng` whose `nextInt` always returns `lo` yields the
	-- IDENTITY permutation under this reading, which is what makes the 64-attempt test in
	-- pool.spec.luau fire; under the other reading it yields a rotation and that test would pass
	-- for the wrong reason. `Rng.nextInt` is inclusive on both ends, so `[i, n]` is the full tail.
	local n = #cards
	for i = 1, n - 1 do
		local j = rng:nextInt(i, n)
		cards[i], cards[j] = cards[j], cards[i]
	end
	return cards
end

-- True when this 4-card opening hand must be re-dealt (CARD-09).
-- The two reasons are checked as SEPARATE conditions on purpose: research 10 warns that a predicate
-- which only looks for four naturals passes the obvious test and silently ships exactly the bug
-- CARD-09 exists to prevent.
local function openingHandIsBad(rankOf: { Types.Rank }, handIds: { Types.CardId }, mode: Types.JokerMode): boolean
	local naturals: { [number]: number } = {}
	local jokersHeld = 0
	for _, id in handIds do
		local rank = rankOf[id]
		if rank == JOKER_RANK then
			jokersHeld += 1
		else
			naturals[rank] = (naturals[rank] or 0) + 1
		end
	end

	-- Condition 1: already a complete natural set. Bad in BOTH joker modes.
	for _, copies in naturals do
		if copies >= COPIES_PER_RANK then
			return true
		end
	end

	-- Condition 2, Wild mode only: completable by a wild the hand already holds. `a >= 1` naturals
	-- of one rank with `a + jokersHeld >= 4` covers 3+1 and 2+2, and research 3.3 proves those are
	-- the only wild completions reachable at `j <= 2`. In Blocker mode a joker can never complete a
	-- set, so 3 naturals + 1 joker is a LEGAL opening hand there and an illegal one here: that
	-- asymmetry is the CARD-10 / CARD-12 divergence showing up at the deal.
	if mode == "Wild" and jokersHeld > 0 then
		for _, copies in naturals do
			if copies >= 1 and copies + jokersHeld >= COPIES_PER_RANK then
				return true
			end
		end
	end

	return false
end

-- Rejection-sampled deal. Returns the accepted permutation and the attempt count (>= 1).
--
-- THE LOCKED DEAL LAYOUT, which every later plan assumes:
--   * totalCards T = 4 * ranks + jokers
--   * seat `s` (1-based) is dealt card ids `(s - 1) * 4 + 1` through `s * 4`
--   * the dealer is seat 1 and its inbox holds ids `seatCount * 4 + 1` through `T`, ascending
--   * so at the deal every circulating card sits in the dealer's inbox and every other inbox is
--     empty (research 3.8), and the start-up ramp advances one seat per draw+pass pair
--   * the deal is random because `rankOf` is a fresh shuffle, NOT because the id assignment moves
--
-- `attempts` is RETURNED rather than logged because the corpus assertion in pool.spec.luau has to
-- see it: without a visible counter the rejection loop is unfalsifiable -- a predicate that never
-- fires is indistinguishable from a correct one.
local function deal(config: Types.EngineConfig, seatCount: number, rng: Shuffler): ({ Types.Rank }, number)
	local ok, reason = validate(config, seatCount)
	if not ok then
		-- A round must never start on an invalid pool, so this is an error and not a return value.
		error(
			`Pool.deal: invalid pool {tostring(reason)} (ranks={config.ranks}, jokers={config.jokers}, seats={seatCount})`
		)
	end

	for attempt = 1, MAX_DEAL_ATTEMPTS do
		local rankOf = shuffledRanks(config, rng)
		local bad = false
		for s = 1, seatCount do
			local handIds: { Types.CardId } = {}
			for slot = 1, HAND_SIZE do
				table.insert(handIds, (s - 1) * HAND_SIZE + slot)
			end
			if openingHandIsBad(rankOf, handIds, config.jokerMode) then
				bad = true
				break
			end
		end
		if not bad then
			return rankOf, attempt
		end
	end

	error(
		`Pool.deal: no legal deal in {MAX_DEAL_ATTEMPTS} attempts (ranks={config.ranks}, jokers={config.jokers}, seats={seatCount})`
	)
end

return {
	poolConfig = poolConfig,
	validate = validate,
	circulationOf = circulationOf,
	shuffledRanks = shuffledRanks,
	openingHandIsBad = openingHandIsBad,
	deal = deal,
}
