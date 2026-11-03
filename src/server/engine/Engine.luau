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
local Hand = require("./Hand")
local Invariants = require("./Invariants")
local Pool = require("./Pool")
local Ring = require("./Ring")
local Types = require("./Types")
local Valve = require("./Valve")

local HAND_SIZE = Types.HAND_SIZE
local MAX_HAND = Types.MAX_HAND
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

-- Every rejection returns through here, so there is exactly one shape for a refusal: a code, and an
-- EMPTY event list rather than nil, because a consumer that has to distinguish nil from empty will
-- eventually get it wrong. Nothing is mutated on this path -- no card moves, no counter moves and
-- no valve entry point runs.
local function rejected(code: Types.Reject): Types.ApplyResult
	return { ok = false, events = {}, reject = code }
end

-- The ONLY mutation entry point. Synchronous, two parameters, no handler function, no clock. The
-- events are RETURNED; the caller feeds them to its own stream after this function has returned.
--
-- VALIDATION RUNS IN THE LOCKED PRECEDENCE, first match wins, because the tests assert the exact
-- code and a different order is a different contract:
--   any     UnknownSeat  -> SeatNotLive
--   Draw    ...          -> HandNotFour -> InboxEmpty
--   Pass    ...          -> UnknownCard -> HandNotFive -> NotYourCard
--   Remove  ...          (no further checks; the cause comes from outside)
local function apply(state: Types.State, intent: Types.Intent): Types.ApplyResult
	local seat = state.seats[intent.seat]
	if seat == nil then
		-- A seat index that names no seat. NOT an error: this module does not assume the shape
		-- layer ran, and an out-of-range index is an illegal intent like any other.
		return rejected("UnknownSeat")
	end
	if not seat.live then
		-- Research 7.6, the actor end of a mid-pass departure: an intent whose actor left between
		-- intent and execution must be refused, never applied to a dead seat. This is also the
		-- engine's own answer to a replayed or forged intent for a removed seat.
		return rejected("SeatNotLive")
	end

	local events: { Types.Event } = {}

	if intent.kind == "Draw" then
		if #seat.hand ~= HAND_SIZE then
			-- CARD-01. "The pile locks at 5" is exactly this rule and nothing else; there is no
			-- `locked` flag on a seat that could disagree with the hand it describes.
			return rejected("HandNotFour")
		end
		if #seat.inbox == 0 then
			return rejected("InboxEmpty")
		end

		local cardId = Ring.draw(state, intent.seat)
		table.insert(events, { kind = "Drew", seat = intent.seat, cardId = cardId })

		-- THE ONLY completion check in the engine (CLAUDE.md, research section 5).
		local completion = Hand.detectCompletion(state.rankOf, seat.hand, state.config.jokerMode)
		if completion ~= nil then
			-- Retirement, which with `Ring.removeSeat`'s terminal branch is one of exactly two
			-- places a card leaves play. `removeSeat` owns that branch and `churnRemovals`; this
			-- block owns the retired four and `completions`, and neither touches the other's
			-- counters (02-06-SUMMARY.md: do not double-count).
			local counters = state.counters
			local isRetired: { [Types.CardId]: true } = {}
			for _, id in completion.retired do
				isRetired[id] = true
				table.insert(state.retired, id)
				local rank = state.rankOf[id]
				if rank == JOKER_RANK then
					counters.jokersInPlay -= 1
				else
					local copies = counters.rankInPlay[rank]
					counters.cnt[copies + 1] = (counters.cnt[copies + 1] or 0) - 1
					counters.rankInPlay[rank] = copies - 1
					counters.cnt[copies] = (counters.cnt[copies] or 0) + 1
				end
			end
			local kept: { Types.CardId } = {}
			for _, id in seat.hand do
				if not isRetired[id] then
					table.insert(kept, id)
				end
			end
			seat.hand = kept
			counters.completions += 1

			table.insert(events, {
				kind = "Completed",
				seat = intent.seat,
				rank = completion.rank,
				retired = completion.retired,
				fifth = completion.fifth,
			})

			-- THE REMOVAL HAPPENS INSIDE THE SAME APPLY AS THE DRAW. CARD-07's wording is "detected
			-- on draw and immediately removes that player"; splitting it across two applies would
			-- open a window in which a completed seat is still a legal pass target. The retirement
			-- above runs FIRST, because `removeSeat` routes whatever is still in the hand.
			local routedTo, cards = Ring.removeSeat(state, intent.seat, "Completed")
			table.insert(events, {
				kind = "SeatRemoved",
				seat = intent.seat,
				cause = "Completed",
				routedTo = routedTo,
				cards = cards,
			})
		end
	elseif intent.kind == "Pass" then
		if intent.cardId % 1 ~= 0 or intent.cardId < 1 or intent.cardId > state.totalCards then
			-- A card id outside `1..totalCards` names no card in this round. A fractional or NaN id
			-- names no card either, so the legality answer is the same one; the shape layer still
			-- owns refusing it as a malformed payload (research Security Domain V5).
			return rejected("UnknownCard")
		end
		if #seat.hand ~= MAX_HAND then
			return rejected("HandNotFive")
		end
		if table.find(seat.hand, intent.cardId) == nil then
			-- NotYourCard covers BOTH situations, and must: the card is held by a different seat,
			-- and the card is in play but sitting in an inbox rather than in any hand. Research 7.6:
			-- a card that was auto-passed a moment before the intent arrived is no longer in the
			-- actor's hand, and that is a rejection rather than a crash. ASVS V4: a seat can only
			-- ever act on cards it actually holds.
			return rejected("NotYourCard")
		end

		-- `Ring.pass` takes NO target and resolves the successor at execution time, so the client
		-- names a card and nothing else (CLAUDE.md rule 7).
		local to = Ring.pass(state, intent.seat, intent.cardId)
		table.insert(events, { kind = "Passed", seat = intent.seat, to = to, cardId = intent.cardId })

		-- NO COMPLETION CHECK HERE, AND NONE MAY BE ADDED. Passing can only leave a SUBSET of a
		-- hand that already had no set, so a pass can never create one. A "defensive" check here
		-- would not be defensive: it would double-fire completions on the forced pass below.
	else
		-- ONE intent with a cause, not three operations (CLAUDE.md rule 8). Phase 4's AFK bench and
		-- a disconnect both route through here, and so does nothing else: `removeSeat` is the single
		-- generic operation and the cause only decides whether this counts as churn.
		if intent.cause == "Completed" then
			-- A CALLER-BUG ERROR, NOT AN EIGHTH REJECT CODE (the house rule from `Ring`: `error`
			-- only where the alternative is silent corruption, and never where a reject code
			-- exists). `Completed` is the engine's OWN cause: it is net zero on circulation only
			-- because the completion path above retires four cards BEFORE removing the seat, and
			-- `removeSeat` deliberately leaves `churnRemovals` alone for it. An externally supplied
			-- `Remove{cause = "Completed"}` skips the retirement, so its four hand cards route into
			-- the successor's inbox with nothing taken out of play: circulation gains 4 while
			-- `expectedCirculation` does not, and `Invariants.check` reports `circulation`. One
			-- forged intent would desynchronise card accounting for the rest of the round (threat
			-- T-2-35), which is exactly the class of damage a reject code must not be used to
			-- describe -- a reject is a legal answer to an illegal request, and this is a wiring
			-- bug in the caller. Phase 4's adapter must bind the cause from the lifecycle event
			-- (disconnect or AFK strike-out) and can never obtain this one.
			error(
				`Engine.apply: a Remove intent may not carry the "Completed" cause; it belongs to the completion path, which retires the four cards first (seat {intent.seat})`
			)
		end
		local routedTo, cards = Ring.removeSeat(state, intent.seat, intent.cause)
		table.insert(events, {
			kind = "SeatRemoved",
			seat = intent.seat,
			cause = intent.cause,
			routedTo = routedTo,
			cards = cards,
		})
	end

	-- THE VALVE (plan 02-13, 02-CONTEXT.md amendment A7 and its correction). ONE block covering all
	-- three intent kinds, and the last thing a successful apply does. Four reasons it is shaped
	-- exactly like this:
	--
	-- * IT IS WIRED IN HERE RATHER THAN EXPOSED AS A TICK. If a caller had to run it, Phase 4 could
	--   forget, and the measured zero-stall result would stop applying to the shipped product.
	--   Breaking a livelock is a liveness property of the engine, like the hand-size rule -- not an
	--   optional service a caller opts into.
	-- * IT RUNS AFTER THE MUTATION AND INSIDE THE SAME SYNCHRONOUS APPLY. No yield point, no handler
	--   function, nothing broadcast (CLAUDE.md rule 6). `apply` still takes exactly two parameters.
	-- * A FORCED PASS IS A REAL PASS. `Ring.pass` resolves `next` at execution time, so the valve
	--   names a card and never a target (CLAUDE.md rule 7), and the seat drops back to a resting
	--   hand exactly as if the player had passed. `ValveForcedPass` comes BEFORE the `Passed` it
	--   explains, and the `Passed` is emitted as well rather than folded into the marker, so that
	--   EVERY card movement in the engine has exactly one `Drew` or `Passed` event -- a uniform rule
	--   Phase 4's adapter and plan 02-08's fuzz suite can both rely on, instead of a consumer having
	--   to know that one event kind is secretly also a pass. Phase 4 must read `ValveForcedPass` as
	--   "that pass was not the player's choice", the same contract as an AFK auto-pass.
	-- * A PASS CAN NEVER COMPLETE ANYONE, so the forced pass needs no completion check and cannot
	--   cascade.
	--
	-- Exactly one entry point runs per SUCCESSFUL apply and NEITHER runs on a rejection: a rejection
	-- must leave the state unchanged, and the valve's counters are part of the state. Plan 02-08
	-- asserts `state.valve.observations == acceptedActions`, which is what catches the valve being
	-- skipped inside a conditional and reading green.
	--
	-- What is claimed: the valve eliminated OBSERVED stalls for a good pool -- 0 of 4,000 rounds at
	-- k=1,j=1 and at k=2,j=1 -- and reduced but did not eliminate them at k=2,j=2 (21.600% to
	-- 0.025%). It is a demonstrated property of a selected configuration and never an unconditional
	-- property of the engine.
	local progressed = false
	for _, event in events do
		if event.kind == "Completed" or event.kind == "SeatRemoved" then
			progressed = true
			break
		end
	end
	if progressed then
		Valve.afterProgress(state)
	else
		-- `drewAtSeat` is the drawing seat on a non-completing draw and nil on a pass. Immediately
		-- after a non-completing draw is the only instant at which a known seat holds MAX_HAND and
		-- therefore provably has a legal pass, and it is about to pass anyway -- so the valve
		-- changes WHICH card leaves, never whether a pass happens.
		local drewAtSeat: Types.SeatId? = if intent.kind == "Draw" then intent.seat else nil
		local forced = Valve.afterAction(state, drewAtSeat)
		if forced ~= nil then
			local to = Ring.pass(state, intent.seat, forced)
			-- `lap` carries the firing's `actionsSinceProgress` so the metric is in the event stream
			-- and not only in a counter. NO state hash goes in an event: the hash encodes every
			-- hand and an event crosses the network boundary in Phase 4 (CLAUDE.md rule 3).
			table.insert(events, {
				kind = "ValveForcedPass",
				seat = intent.seat,
				cardId = forced,
				to = to,
				lap = state.valve.actionsSinceProgress,
			})
			table.insert(events, { kind = "Passed", seat = intent.seat, to = to, cardId = forced })
		end
	end

	return { ok = true, events = events }
end

return {
	newRound = newRound,
	apply = apply,
}
