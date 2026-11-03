--!strict
-- `Engine`: the round constructor and the ONE mutation entry point. PURE ZONE: no Roblox API, no
-- clock, no yields (CLAUDE.md rules 2, 5 and 6).
--
-- 1. `apply(state, intent)` IS SYNCHRONOUS AND TAKES EXACTLY TWO PARAMETERS. It accepts no handler
--    function, no sink, no observer list and no clock, and it RETURNS its events rather than
--    broadcasting them. The caller feeds the returned list into its own event stream AFTER apply
--    has returned, so there is no seam at which a handler could run in the middle of a mutation
--    (research section 9, property 1; CLAUDE.md rule 6). Plan 02-03's R3 guard makes the
--    yield-capable standard library a build failure inside this directory, but that ban is
--    belt-and-braces: the SHAPE above is what makes the no-yield property structural rather than
--    conventional, because there is nowhere for a handler to be passed in.
--
-- 2. TWO VALIDATION LAYERS, NEITHER REDUNDANT (research section 15 and Security Domain V5).
--    `src/shared/Net/Validate` owns payload SHAPE: it refuses a NaN, a missing field or a wrong
--    type, and it cannot know whether a hand holds a card. This module owns LEGALITY: it refuses an
--    illegal action with its own reject code, and it cannot know a payload was malformed. So
--    nothing here re-checks shape beyond what legality needs, and nothing here ASSUMES the shape
--    layer ran either -- an out-of-range seat index is `UnknownSeat`, not an error.
--
-- 3. EVERY REJECTION CARRIES ITS OWN CODE and leaves the state untouched. A boolean return would
--    make seven distinct bugs indistinguishable, and the house standard from Phase 1 is that the
--    test asserts the REASON: a gateway that refused everything once passed a suite which only
--    checked "refused". `tests/engine/apply.spec.luau` asserts the code, an empty event list and an
--    unchanged canonical state hash on every rejection.
--
-- 4. FOUR OF A KIND IS CHECKED ONLY ON THE DRAW PATH (CLAUDE.md, research section 5). Passing can
--    only leave a SUBSET of a hand that already had no set, so a pass can never create one. The
--    pass path therefore has no completion check and must never grow one.
--
-- 5. ONLY TWO PLACES TAKE A CARD OUT OF PLAY: the retirement below, and `Ring.removeSeat`'s
--    terminal branch, which that function owns. `removeSeat` also owns `churnRemovals`. This module
--    must therefore retire the four completed cards BEFORE calling `removeSeat(..., "Completed")`
--    and must never touch `rankInPlay` / `jokersInPlay` / `cnt` for a ROUTED card -- routing a card
--    into an inbox does not take it out of play (02-06-SUMMARY.md: do not double-count).
--
-- 6. `Remove` IS ONE INTENT WITH A CAUSE, not three operations (CLAUDE.md rule 8). Phase 4's AFK
--    bench, a disconnect and a completion all route through the same removal.
--
-- 7. AN INTENT NAMES A CARD, NEVER A TARGET AND NEVER A HAND INDEX (CLAUDE.md rule 7).
--    `Types.Intent`'s Pass variant has no `to`, no `target` and no `index` field, so a future wire
--    payload has nowhere to put one, and `Ring.pass` resolves the successor at execution time.
--
-- 8. `Invariants.check` IS NOT CALLED FROM `apply`, DELIBERATELY. The fuzz suite (plan 02-08) and
--    the simulator (plan 02-09) call it after every action, which is where the cost belongs;
--    research 11.1 measured the full identity scan at 1.7x the cost of the counters alone, and the
--    shipped hot path must not pay for a test-time assertion. `newRound` does call it once, because
--    a round that starts corrupt must not be playable and the deal is the cheapest place to catch a
--    layout mistake.
local Invariants = require("./Invariants")
local Pool = require("./Pool")
local Ring = require("./Ring")
local Types = require("./Types")
local Valve = require("./Valve")

local HAND_SIZE = Types.HAND_SIZE
local JOKER_RANK = Types.JOKER_RANK
local BUCKETS = 5 -- counters.cnt[a + 1] for a in 0..4

-- Builds a fully dealt round. `seatPlayerIds` is already IN SEAT ORDER -- index 1 is the dealer,
-- because `SeatOrder` (plan 02-02) put it there (CARD-05). Errors by name, through `Pool.deal`, on
-- an invalid pool.
local function newRound(config: Types.EngineConfig, seatPlayerIds: { Types.PlayerId }, rng: any): Types.State
	local seatCount = #seatPlayerIds
	if seatCount < 1 then
		-- Named separately from the pool diagnosis below: an empty seat list is a caller mistake in
		-- the round lifecycle, not a bad pool configuration, and the two are fixed in different files.
		error(`Engine.newRound: need at least one seated seeker, got {seatCount}`)
	end

	-- CARD-09 holds for every round the engine can CONSTRUCT, rather than for rounds somebody
	-- remembered to deal properly, because this is the only way to build a `State` with cards in it.
	-- `Pool.deal` already errors by name on an invalid pool (BadConfig / RanksBelowSeats /
	-- TooManyJokers / DeadPool), so there is no second validation here: one site, one set of reason
	-- strings. Its second return is the rejection-sampling attempt count, deliberately NOT captured:
	-- `State` must stay a pure description of the table, and plan 02-09's simulator reads the metric
	-- from `Pool.deal` directly.
	local rankOf = Pool.deal(config, seatCount, rng)
	local totalCards = 4 * config.ranks + config.jokers

	local state: Types.State = {
		config = config,
		seatCount = seatCount,
		totalCards = totalCards,
		rankOf = rankOf,
		seats = {},
		liveCount = 0,
		head = 0,
		retired = {},
		terminal = {},
		counters = {
			rankInPlay = {},
			jokersInPlay = 0,
			cnt = {},
			completions = 0,
			churnRemovals = 0,
		},
		-- The valve's generator is DERIVED from the deal's generator rather than shared with it, so
		-- a valve draw can never shift the deal and a re-deal can never shift the valve, while the
		-- whole round stays a function of one seed -- which is what lets a failing simulator trial be
		-- reproduced from its seed alone.
		valve = Valve.new(rng:nextUint()),
	}

	Ring.build(state, seatPlayerIds)

	-- THE LOCKED DEAL LAYOUT (02-04-SUMMARY.md). Seat `s` holds ids `(s-1)*4+1 .. s*4`; the dealer
	-- holds the remainder in its inbox, ascending. The deal is random because `rankOf` is a fresh
	-- shuffle, NOT because the id assignment moves.
	--
	-- The consequence worth stating: at the deal EVERY circulating card sits in the dealer's inbox
	-- and every other inbox is empty, so only the dealer can act and the start-up wave advances one
	-- seat per draw+pass pair (research 3.8). That measured +0.87s of median time-to-first-completion
	-- per added player is propagation, not card luck, and it is why Phase 4 needs a "waiting for
	-- cards" affordance for far seats during the first ~8 seconds at a full roster.
	for s = 1, seatCount do
		local hand = state.seats[s].hand
		for slot = 1, HAND_SIZE do
			table.insert(hand, (s - 1) * HAND_SIZE + slot)
		end
	end
	local deck = state.seats[1].inbox
	for id = seatCount * HAND_SIZE + 1, totalCards do
		table.insert(deck, id)
	end

	-- Counters DERIVED by scanning `rankOf`, never asserted from the layout. At the deal every card
	-- is in a live container, so the scan is over all ids -- and because it reads `rankOf` while
	-- `Invariants.check` recomputes the same quantities by walking the SEAT CONTAINERS, the two
	-- sides are independent and a layout mistake shows up as a violation instead of agreeing with
	-- itself (research Pitfall 4).
	local rankInPlay: { number } = table.create(config.ranks, 0)
	local jokersInPlay = 0
	for id = 1, totalCards do
		local rank = rankOf[id]
		if rank == JOKER_RANK then
			jokersInPlay += 1
		else
			rankInPlay[rank] += 1
		end
	end
	local cnt: { number } = table.create(BUCKETS, 0)
	for rank = 1, config.ranks do
		local bucket = rankInPlay[rank] + 1
		cnt[bucket] = (cnt[bucket] or 0) + 1
	end
	state.counters.rankInPlay = rankInPlay
	state.counters.jokersInPlay = jokersInPlay
	state.counters.cnt = cnt

	local ok, why = Invariants.check(state)
	if not ok then
		error(`Engine.newRound: the deal produced an illegal state ({tostring(why)})`)
	end
	return state
end

return {
	newRound = newRound,
}
