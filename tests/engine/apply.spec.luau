--!strict
-- `Engine.newRound` and `Engine.apply` (plan 02-07). House style from tests/net/validate.spec.luau
-- and tests/core/gateway.spec.luau: every rejection asserts its OWN locked code, never merely that
-- something was refused. Phase 1 verification found a gateway that rejected everything and passed a
-- suite which only checked "rejected".
--
-- Every state in this file is built by the REAL `Engine.newRound`, with one deliberate exception:
-- case 11 uses `tests/harness/Livelock`, whose whole purpose is a hand-verified cycle. This is the
-- first plan in the phase where the entire stack exists, so the point of the file is to test it
-- ASSEMBLED rather than to re-test the primitives behind hand-built fixtures.
local fs = require("@lune/fs")

local Engine = require("../../src/server/engine/Engine")
local Invariants = require("../../src/server/engine/Invariants")
local Livelock = require("../harness/Livelock")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

local ENGINE_PATH = "src/server/engine/Engine.luau"

-- `jokerMode` is always passed as a LITERAL at a call site and never iterated out of a table:
-- Luau widens a singleton-string literal table to `{ string }` and the widened element no longer
-- satisfies `JokerMode` (the same note sits in tests/engine/invariants.spec.luau and
-- tests/engine/removal.spec.luau). Hence `configFor(..., mode)` taking a typed parameter.
local function configFor(seatCount: number, k: number, j: number, mode: Types.JokerMode): Types.EngineConfig
	return { ranks = seatCount + k, jokers = j, jokerMode = mode, antiLivelockValve = true }
end

local function playerIdsFor(seatCount: number): { Types.PlayerId }
	local ids: { Types.PlayerId } = {}
	for s = 1, seatCount do
		ids[s] = 100 + s
	end
	return ids
end

-- The round every rejection case starts from: 3 seats, ranks = 4, no jokers, circulation = 4.
-- Seat 1 holds {1,2,3,4} with the deck {13,14,15,16} in its inbox, seat 2 holds {5,6,7,8} and seat
-- 3 holds {9,10,11,12}, both with empty inboxes. The seed is hardcoded so that seat 1's FIRST draw
-- does not complete -- the positive draw case below asserts exactly one event, which is what pins
-- it, so a seed change cannot silently turn these cases into completion cases.
local REJECT_SEED = 11

local function rejectRound(): Types.State
	return Engine.newRound(configFor(3, 1, 0, "Wild"), playerIdsFor(3), Rng.new(REJECT_SEED))
end

-- Narrowing accessors. `Types.Event` is a tagged union, so `.cardId` is not a field of every
-- variant; these keep the narrowing local instead of sprinkling asserts through the cases.
local function kindsOf(events: { Types.Event }): { string }
	local out: { string } = {}
	for _, event in events do
		table.insert(out, event.kind)
	end
	return out
end

local function drewCard(event: Types.Event): Types.CardId?
	if event.kind == "Drew" then
		return event.cardId
	end
	return nil
end

local function passedBy(event: Types.Event): (Types.SeatId?, Types.CardId?)
	if event.kind == "Passed" then
		return event.to, event.cardId
	end
	return nil, nil
end

-- A GREEDY HOARDER, deterministic and mode-agnostic: keep the largest rank group, pass a card from
-- the smallest, lowest card id as the tiebreak. It is NOT a model of a player -- research section
-- 15 keeps the reaction-time and policy models out of `src/server/engine/` and plan 02-09 owns the
-- real bot. It is here only because a completion has to be reached by SOME reproducible sequence of
-- legal intents, and this is the shortest one that reaches four of a kind.
local function greedyCard(state: Types.State, seatId: Types.SeatId): Types.CardId
	local hand = state.seats[seatId].hand
	local counts: { [Types.Rank]: number } = {}
	for _, id in hand do
		local rank = state.rankOf[id]
		counts[rank] = (counts[rank] or 0) + 1
	end
	local best = hand[1]
	local bestKey = counts[state.rankOf[best]] * 1000 + best
	for _, id in hand do
		local key = counts[state.rankOf[id]] * 1000 + id
		if key < bestKey then
			best, bestKey = id, key
		end
	end
	return best
end

-- Walks the ring applying greedy intents until one apply produces a `Completed` event, and returns
-- that `ApplyResult` with the action index. `trace` collects the accepted intents so the identical
-- sequence can be replayed against a differently configured twin.
local function playUntilCompletion(
	state: Types.State,
	maxActions: number,
	trace: { Types.Intent }?
): (Types.ApplyResult?, number)
	local cursor = state.head
	for action = 1, maxActions do
		local seat = state.seats[cursor]
		local intent: Types.Intent
		if #seat.hand == Types.HAND_SIZE then
			if #seat.inbox == 0 then
				cursor = seat.next
				continue
			end
			intent = { kind = "Draw", seat = cursor }
		else
			intent = { kind = "Pass", seat = cursor, cardId = greedyCard(state, cursor) }
		end
		local result = Engine.apply(state, intent)
		if not result.ok then
			return nil, action
		end
		if trace ~= nil then
			table.insert(trace, intent)
		end
		local completed = false
		for _, event in result.events do
			if event.kind == "Completed" then
				completed = true
			end
		end
		local actor = state.seats[cursor]
		if not actor.live then
			cursor = state.head
		elseif #actor.hand == Types.HAND_SIZE then
			cursor = actor.next
		end
		if completed then
			return result, action
		end
	end
	return nil, maxActions
end

-- Everything on `State` except `valve.rng`, which is a table of CLOSURES: two independently
-- constructed generators are never equal by value, so a whole-state deepEqual would fail for a
-- reason that has nothing to do with reproducibility.
local function snapshot(state: Types.State)
	return {
		config = state.config,
		seatCount = state.seatCount,
		totalCards = state.totalCards,
		rankOf = state.rankOf,
		seats = state.seats,
		liveCount = state.liveCount,
		head = state.head,
		retired = state.retired,
		terminal = state.terminal,
		counters = state.counters,
	}
end

return function(t: Test.Runner)
	-- 1 ------------------------------------------------------------------------------------------
	t.test("newRound deals 9 seats of 4 with the whole circulating supply in the dealer's inbox", function()
		local state = Engine.newRound(configFor(9, 2, 1, "Wild"), playerIdsFor(9), Rng.new(7))
		t.equal(state.liveCount, 9, "every dealt seat is live")
		t.equal(state.seatCount, 9, "seatCount is the dealt roster")
		t.equal(state.totalCards, 4 * 11 + 1, "totalCards is 4 * ranks + jokers")
		for s = 1, 9 do
			t.equal(#state.seats[s].hand, Types.HAND_SIZE, `seat {s} holds a resting hand`)
		end
		t.equal(#state.seats[1].inbox, 9, "the dealer's inbox IS the deck: 4 * (11 - 9) + 1 = 9 cards")
		for s = 2, 9 do
			t.equal(#state.seats[s].inbox, 0, `seat {s}'s inbox is empty at the deal (research 3.8)`)
		end
		local ok, why = Invariants.check(state)
		t.truthy(ok, `a freshly dealt round reported {tostring(why)}`)
		t.equal(Invariants.circulation(state), 9, "circulation is 4k + j at the deal")
	end)

	-- 2 ------------------------------------------------------------------------------------------
	t.test("newRound lays the cards out per the LOCKED deal layout", function()
		local state = Engine.newRound(configFor(3, 1, 0, "Wild"), playerIdsFor(3), Rng.new(11))
		t.deepEqual(state.seats[1].hand, { 1, 2, 3, 4 }, "seat 1 holds ids 1..4")
		t.deepEqual(state.seats[2].hand, { 5, 6, 7, 8 }, "seat 2 holds ids 5..8")
		t.deepEqual(state.seats[3].hand, { 9, 10, 11, 12 }, "seat 3 holds ids 9..12")
		t.deepEqual(state.seats[1].inbox, { 13, 14, 15, 16 }, "the rest sit in the dealer's inbox ASCENDING")
	end)

	-- 3 ------------------------------------------------------------------------------------------
	t.test("newRound initialises the valve cold and the counters by scanning", function()
		local state = Engine.newRound(configFor(4, 1, 2, "Wild"), playerIdsFor(4), Rng.new(3))
		t.equal(state.valve.actionsSinceProgress, 0, "actionsSinceProgress starts at 0")
		t.equal(state.valve.armed, false, "a fresh round is not armed")
		t.equal(state.valve.firings, 0, "firings starts at 0")
		t.equal(state.valve.seenCount, 0, "the seen window starts empty")
		t.equal(state.valve.seenResets, 0, "seenResets starts at 0")
		t.equal(state.valve.observations, 0, "observations starts at 0")
		t.equal(state.counters.completions, 0, "completions starts at 0")
		t.equal(state.counters.churnRemovals, 0, "churnRemovals starts at 0")
		t.equal(state.counters.jokersInPlay, 2, "every joker is in play at the deal")
		t.deepEqual(state.counters.cnt, { 0, 0, 0, 0, 5 }, "every one of the 5 ranks is intact at the deal")
		for rank = 1, 5 do
			t.equal(state.counters.rankInPlay[rank], 4, `rank {rank} has all four copies in play`)
		end
	end)

	-- 4 ------------------------------------------------------------------------------------------
	t.test("newRound refuses a dead pool and an empty seat list", function()
		t.throws(function()
			Engine.newRound(configFor(5, 0, 0, "Wild"), playerIdsFor(5), Rng.new(1))
		end, "DeadPool")
		t.throws(function()
			Engine.newRound(configFor(0, 2, 1, "Wild"), {}, Rng.new(1))
		end, "at least one seated seeker")
	end)

	-- 5 ------------------------------------------------------------------------------------------
	t.test("newRound is reproducible from its seed alone", function()
		local a = Engine.newRound(configFor(6, 2, 1, "Blocker"), playerIdsFor(6), Rng.new(99))
		local b = Engine.newRound(configFor(6, 2, 1, "Blocker"), playerIdsFor(6), Rng.new(99))
		t.deepEqual(snapshot(a), snapshot(b), "the same config, seat list and seed deal the same round")
	end)

	-- THE SEVEN REJECT CODES -----------------------------------------------------------------------
	-- Research 11.3 says "each of the six Reject codes". It UNDERCOUNTS: section 9 lists seven and
	-- all seven are reachable, each with its own row below. Recorded here because plan 02-08's fuzz
	-- suite must assert coverage of SEVEN codes at a minimum observation count each, not six -- a
	-- code nobody can reach would otherwise ship as an untested branch.
	--
	-- Every row asserts all four of: ok == false, the exact code, an EMPTY event list, and an
	-- unchanged canonical state hash. A rejection that mutates state is worse than one that errors,
	-- and the hash is what makes "unchanged" checkable rather than assumed.
	--
	-- It also asserts the valve did not move. That is NOT covered by the hash: `Invariants.hash`
	-- deliberately excludes `valve` (it must, or no state could ever repeat and the valve could
	-- never fire), so a valve entry point called on a rejection would leave the hash identical and
	-- slip through. The locked valve call rule is "neither on a rejection", and this is the only
	-- place it can be checked on all seven codes.
	local function rejects(name: string, setup: (Types.State) -> Types.Intent, expected: Types.Reject)
		t.test(name, function()
			local state = rejectRound()
			local intent = setup(state)
			local before = Invariants.hash(state)
			local observations = state.valve.observations
			local lap = state.valve.actionsSinceProgress
			local result = Engine.apply(state, intent)
			t.equal(result.ok, false, `{name}: the intent must be refused`)
			t.equal(result.reject, expected, `{name}: the reject code`)
			t.equal(typeof(result.events), "table", `{name}: events is an empty table, never nil`)
			t.equal(#result.events, 0, `{name}: a rejection returns no events`)
			t.equal(Invariants.hash(state), before, `{name}: a rejection must leave the state byte-identical`)
			t.equal(state.valve.observations, observations, `{name}: no valve entry point runs on a rejection`)
			t.equal(state.valve.actionsSinceProgress, lap, `{name}: a rejection is not an action`)
		end)
	end

	-- 6 ------------------------------------------------------------------------------------------
	rejects("Draw naming seat 0 is UnknownSeat", function()
		return { kind = "Draw", seat = 0 }
	end, "UnknownSeat")

	-- 7 ------------------------------------------------------------------------------------------
	rejects("Pass naming seatCount + 1 is UnknownSeat", function(state)
		return { kind = "Pass", seat = state.seatCount + 1, cardId = 1 }
	end, "UnknownSeat")

	-- 8 ------------------------------------------------------------------------------------------
	rejects("Draw at a seat removed a moment ago is SeatNotLive", function(state)
		local gone = Engine.apply(state, { kind = "Remove", seat = 2, cause = "Benched" })
		t.truthy(gone.ok, "the setup removal must succeed")
		return { kind = "Draw", seat = 2 }
	end, "SeatNotLive")

	-- 9 ------------------------------------------------------------------------------------------
	rejects("Pass of card id 0 is UnknownCard", function()
		return { kind = "Pass", seat = 1, cardId = 0 }
	end, "UnknownCard")

	-- 10 -----------------------------------------------------------------------------------------
	rejects("Pass of card id totalCards + 1 is UnknownCard", function(state)
		return { kind = "Pass", seat = 1, cardId = state.totalCards + 1 }
	end, "UnknownCard")

	-- 11 -----------------------------------------------------------------------------------------
	rejects("Pass at a hand of 4 is HandNotFive", function()
		return { kind = "Pass", seat = 1, cardId = 1 }
	end, "HandNotFive")

	-- 12 -----------------------------------------------------------------------------------------
	rejects("Pass of a card held by another seat is NotYourCard", function(state)
		local drew = Engine.apply(state, { kind = "Draw", seat = 1 })
		t.truthy(drew.ok, "the setup draw must succeed")
		return { kind = "Pass", seat = 1, cardId = 5 }
	end, "NotYourCard")

	-- 13 -----------------------------------------------------------------------------------------
	rejects("Draw at a hand of 5 is HandNotFour", function(state)
		local drew = Engine.apply(state, { kind = "Draw", seat = 1 })
		t.truthy(drew.ok, "the setup draw must succeed")
		return { kind = "Draw", seat = 1 }
	end, "HandNotFour")

	-- 14 -----------------------------------------------------------------------------------------
	rejects("Draw at a hand of 4 with an empty inbox is InboxEmpty", function()
		return { kind = "Draw", seat = 2 }
	end, "InboxEmpty")

	-- 15 -----------------------------------------------------------------------------------------
	rejects("NotYourCard also covers a card sitting in the actor's OWN inbox", function(state)
		-- Research 7.6: in the live round this is the card that was auto-passed a moment before the
		-- intent arrived. A predicate that only checked "not in SOME hand" by scanning hands would
		-- answer UnknownCard or crash here; a predicate that scanned every container would accept it.
		local drew = Engine.apply(state, { kind = "Draw", seat = 1 })
		t.truthy(drew.ok, "the setup draw must succeed")
		t.equal(state.seats[1].inbox[1], 14, "the setup must leave a card in the actor's own inbox")
		return { kind = "Pass", seat = 1, cardId = 14 }
	end, "NotYourCard")

	-- 16 -----------------------------------------------------------------------------------------
	rejects("UnknownCard is checked BEFORE HandNotFive", function(state)
		-- Illegal on both counts: seat 1 holds 4 cards AND card id 99 names no card. The locked
		-- precedence says UnknownCard. Without this row two correct-looking implementations would
		-- disagree and no test would say which one is right.
		t.equal(#state.seats[1].hand, Types.HAND_SIZE, "the seat must be at a resting hand")
		return { kind = "Pass", seat = 1, cardId = 99 }
	end, "UnknownCard")

	-- 17 -----------------------------------------------------------------------------------------
	t.test("a legal draw at exactly 4 is accepted and the hand becomes 5", function()
		local state = rejectRound()
		local front = state.seats[1].inbox[1]
		t.equal(front, 13, "the dealer's inbox front is the lowest deck id")
		local result = Engine.apply(state, { kind = "Draw", seat = 1 })
		t.truthy(result.ok, "a draw at a resting hand with a stocked inbox is legal (CARD-01)")
		t.equal(result.reject, nil, "an accepted intent carries no reject code")
		t.deepEqual(kindsOf(result.events), { "Drew" }, "a non-completing draw emits exactly one event")
		t.equal(drewCard(result.events[1]), front, "the drawn card is the PRE-draw inbox front (FIFO)")
		t.equal(#state.seats[1].hand, Types.MAX_HAND, "the hand is now 5: the pile has locked")
		t.deepEqual(state.seats[1].inbox, { 14, 15, 16 }, "the front was popped, the rest kept their order")
		local ok, why = Invariants.check(state)
		t.truthy(ok, `the state after a legal draw reported {tostring(why)}`)
	end)

	-- 18 -----------------------------------------------------------------------------------------
	t.test("a legal pass at exactly 5 lands at the tail of the resolved successor's inbox", function()
		local state = rejectRound()
		local drew = Engine.apply(state, { kind = "Draw", seat = 1 })
		local card = drewCard(drew.events[1])
		t.equal(card, 13, "the setup draw must take the deck front")
		local result = Engine.apply(state, { kind = "Pass", seat = 1, cardId = 13 })
		t.truthy(result.ok, "a pass at a locked hand is legal (CARD-03)")
		t.deepEqual(kindsOf(result.events), { "Passed" }, "a pass emits exactly one event")
		local to, passed = passedBy(result.events[1])
		t.equal(to, 2, "the target is the resolved live successor, never a client-supplied seat")
		t.equal(passed, 13, "the event names the card the intent named")
		local inbox = state.seats[2].inbox
		t.equal(inbox[#inbox], 13, "the card is the LAST element of the successor's inbox (FIFO tail)")
		t.equal(#state.seats[1].hand, Types.HAND_SIZE, "the passer is back to a resting hand")
		local ok, why = Invariants.check(state)
		t.truthy(ok, `the state after a legal pass reported {tostring(why)}`)
	end)

	-- 19 -----------------------------------------------------------------------------------------
	t.test("a completing draw emits Drew, Completed, SeatRemoved in that order, from ONE apply", function()
		-- CARD-07. SEED 1 IS HARDCODED: the greedy sequence above reaches a completion on action 17
		-- of a 3-seat, ranks = 4, jokerless round, and hardcoding it makes the case deterministic
		-- from here on rather than dependent on a search that could start finding a different round.
		local state = Engine.newRound(configFor(3, 1, 0, "Wild"), playerIdsFor(3), Rng.new(1))
		local result, action = playUntilCompletion(state, 200, nil)
		t.truthy(result, `the greedy sequence must reach a completion; it stopped at action {action}`)
		t.equal(action, 17, "the hardcoded seed completes on action 17")
		assert(result ~= nil, "narrowing: the assertion above already failed if it is nil")
		t.deepEqual(
			kindsOf(result.events),
			{ "Drew", "Completed", "SeatRemoved" },
			"the LOCKED event order, all three from one apply"
		)
		local completed = result.events[2]
		assert(completed.kind == "Completed", "narrowing: the deepEqual above already pinned the kind")
		t.equal(#completed.retired, 4, "exactly four cards are retired")
		t.equal(completed.rank, state.rankOf[completed.retired[1]], "the retired cards carry the completing rank")
		t.equal(
			table.find(state.retired, completed.retired[1]) ~= nil,
			true,
			"the retired cards moved to state.retired"
		)
		local removed = result.events[3]
		assert(removed.kind == "SeatRemoved", "narrowing: the deepEqual above already pinned the kind")
		t.equal(removed.cause, "Completed", "the removal's cause is Completed")
		t.equal(removed.seat, completed.seat, "the seat removed is the seat that completed")
		-- The removal is in the SAME apply as the draw, so there is no window in which a completed
		-- seat is still a legal pass target (CARD-07: "immediately removes that player").
		t.equal(state.seats[completed.seat].live, false, "the seat is already gone when apply returns")
		t.equal(state.liveCount, 2, "the ring shrank by exactly one")
		t.equal(state.counters.completions, 1, "the completion was counted")
		t.equal(state.counters.churnRemovals, 0, "a completion is NOT churn")
		local ok, why = Invariants.check(state)
		t.truthy(ok, `the state after the completion chain reported {tostring(why)}`)
	end)

	-- 20 -----------------------------------------------------------------------------------------
	t.test("the IDENTICAL scripted sequence completes in Wild and does not in Blocker", function()
		-- CARD-12 at the apply level: both variants available behind an `EngineConfig` VALUE from
		-- the start, selected in the same process. SEED 5 IS HARDCODED. Both modes deal the same
		-- permutation on it, which is asserted rather than assumed: `Pool.deal`'s rejection
		-- predicate is STRICTER in Wild, so a seed where Wild accepts on its first attempt gives
		-- Blocker the same first attempt -- but a seed where it does not would silently compare two
		-- different rounds and the case would prove nothing.
		local wild = Engine.newRound(configFor(3, 1, 1, "Wild"), playerIdsFor(3), Rng.new(5))
		local blocker = Engine.newRound(configFor(3, 1, 1, "Blocker"), playerIdsFor(3), Rng.new(5))
		t.deepEqual(wild.rankOf, blocker.rankOf, "the two modes must start from the IDENTICAL deal")
		t.equal(Invariants.hash(wild), Invariants.hash(blocker), "and from the identical card layout")

		local trace: { Types.Intent } = {}
		local wildResult, wildAction = playUntilCompletion(wild, 200, trace)
		t.truthy(wildResult, `Wild must complete; it stopped at action {wildAction}`)
		t.equal(wildAction, 13, "the hardcoded seed completes on action 13 in Wild")
		assert(wildResult ~= nil, "narrowing")
		local wildCompleted = wildResult.events[2]
		assert(wildCompleted.kind == "Completed", "Wild's second event must be the completion")
		local jokersRetired = 0
		for _, id in wildCompleted.retired do
			if wild.rankOf[id] == Types.JOKER_RANK then
				jokersRetired += 1
			end
		end
		t.truthy(jokersRetired >= 1, "the completing set must SPEND a joker, or Blocker would complete too")

		-- Replay the recorded intents, in order, against the Blocker twin.
		local blockerEvents: { string } = {}
		for index, intent in trace do
			local replay = Engine.apply(blocker, intent)
			t.truthy(replay.ok, `Blocker rejected intent {index} with {tostring(replay.reject)}`)
			if index == #trace then
				blockerEvents = kindsOf(replay.events)
			end
		end
		t.deepEqual(
			kindsOf(wildResult.events),
			{ "Drew", "Completed", "SeatRemoved" },
			"Wild: a joker completes the set"
		)
		t.deepEqual(
			blockerEvents,
			{ "Drew" },
			"Blocker: the same hand is just a draw, because a joker completes nothing"
		)
		t.equal(wild.counters.completions, 1, "Wild counted a completion")
		t.equal(blocker.counters.completions, 0, "Blocker counted none")
		t.equal(blocker.liveCount, 3, "Blocker's ring is untouched")
		local ok, why = Invariants.check(blocker)
		t.truthy(ok, `the Blocker twin reported {tostring(why)}`)
	end)

	-- 21 -----------------------------------------------------------------------------------------
	t.test("a Remove intent routes identically for every cause an intent may carry", function()
		-- CARD-08 and CLAUDE.md rule 8: ONE generic operation. The two causes below are the two an
		-- intent may carry; `Completed` is covered by the next case, because it is the ENGINE's own
		-- cause and not a caller's.
		local function routeWith(cause: Types.RemoveCause): (string, { Types.CardId }, number)
			local state = rejectRound()
			local result = Engine.apply(state, { kind = "Remove", seat = 2, cause = cause })
			t.truthy(result.ok, `Remove with cause {cause} must be accepted`)
			t.deepEqual(kindsOf(result.events), { "SeatRemoved" }, `cause {cause} emits exactly one event`)
			local event = result.events[1]
			assert(event.kind == "SeatRemoved", "narrowing")
			t.equal(event.cause, cause, "the event echoes the cause the intent carried")
			t.equal(event.seat, 2, "the event names the removed seat")
			t.equal(event.routedTo, 3, "the cards route to the live successor")
			t.equal(event.cards, 4, "all four of the departing seat's resting cards routed")
			t.equal(state.seats[2].live, false, "the seat is gone")
			local ok, why = Invariants.check(state)
			t.truthy(ok, `the state after a {cause} removal reported {tostring(why)}`)
			return Invariants.hash(state), table.clone(state.seats[3].inbox), state.counters.churnRemovals
		end

		local disconnectedHash, disconnectedInbox, disconnectedChurn = routeWith("Disconnected")
		local benchedHash, benchedInbox, benchedChurn = routeWith("Benched")
		t.deepEqual(disconnectedInbox, { 5, 6, 7, 8 }, "the departing hand routes ascending to the successor's tail")
		t.deepEqual(benchedInbox, disconnectedInbox, "the two causes route to the same place, in the same order")
		t.equal(benchedHash, disconnectedHash, "and leave canonically identical states")
		t.equal(disconnectedChurn, 1, "a disconnect is churn")
		t.equal(benchedChurn, 1, "so is an AFK bench")
	end)

	-- 22 -----------------------------------------------------------------------------------------
	t.test("a Remove intent may not carry the engine's own Completed cause", function()
		-- See the note in Engine.luau. `Completed` is net zero on circulation ONLY because the
		-- completion path retires four cards before removing the seat; an intent carrying it would
		-- skip the retirement, route four cards into the successor's inbox with nothing leaving
		-- play, and desynchronise card accounting for the rest of the round (threat T-2-35). That is
		-- a caller wiring bug, so it is a loud error and deliberately NOT an eighth reject code --
		-- there are exactly seven, and a reject is a legal answer to an illegal request.
		local state = rejectRound()
		local before = Invariants.hash(state)
		t.throws(function()
			Engine.apply(state, { kind = "Remove", seat = 2, cause = "Completed" })
		end, 'may not carry the "Completed" cause')
		t.equal(Invariants.hash(state), before, "the refused removal moved nothing")
		t.equal(state.seats[2].live, true, "the seat is still live")
		t.equal(state.valve.observations, 0, "and no valve entry point ran")
	end)

	-- 23 -----------------------------------------------------------------------------------------
	t.test("a departed seat rejects its own intents while a pass TARGETING it lands downstream", function()
		-- Research 7.6, both ends in one case. The actor end is rejected; the target end is not a
		-- rejection at all, because `Ring.pass` resolves the successor at EXECUTION time.
		local state = rejectRound()
		local gone = Engine.apply(state, { kind = "Remove", seat = 2, cause = "Disconnected" })
		t.truthy(gone.ok, "the setup removal must succeed")

		local actor = Engine.apply(state, { kind = "Draw", seat = 2 })
		t.equal(actor.ok, false, "the departed ACTOR's intent is refused")
		t.equal(actor.reject, "SeatNotLive", "and the reason names the departure")

		local drew = Engine.apply(state, { kind = "Draw", seat = 1 })
		t.truthy(drew.ok, "seat 1 can still draw")
		local card = drewCard(drew.events[1])
		assert(card ~= nil, "narrowing: the draw must have produced a Drew event")
		local result = Engine.apply(state, { kind = "Pass", seat = 1, cardId = card })
		t.truthy(result.ok, "a pass whose intended neighbour left is NOT a rejection")
		local to, passed = passedBy(result.events[1])
		t.equal(to, 3, "the card lands in the DEPARTED seat's successor")
		t.equal(passed, card, "and it is the card the intent named")
		local inbox = state.seats[3].inbox
		t.equal(inbox[#inbox], card, "at the tail, behind the four cards seat 2 routed there")
		t.deepEqual(inbox, { 5, 6, 7, 8, card }, "the exact resulting inbox")
		local ok, why = Invariants.check(state)
		t.truthy(ok, `the state after a downstream pass reported {tostring(why)}`)
	end)

	-- 24 -----------------------------------------------------------------------------------------
	t.test("newRound is clean, correct and reproducible across the whole pool grid", function()
		local function gridFor(mode: Types.JokerMode)
			for seatCount = 2, 9 do
				for k = 1, 2 do
					for j = 0, 2 do
						local label = `seats={seatCount} k={k} j={j} mode={mode}`
						local ids = playerIdsFor(seatCount)
						local a = Engine.newRound(
							configFor(seatCount, k, j, mode),
							ids,
							Rng.new(seatCount * 100 + k * 10 + j)
						)
						local ok, why = Invariants.check(a)
						t.truthy(ok, `{label}: a freshly dealt round reported {tostring(why)}`)
						t.equal(why, nil, `{label}: check must return (true, nil)`)
						t.equal(Invariants.circulation(a), 4 * k + j, `{label}: circulation is 4k + j`)
						t.equal(a.liveCount, seatCount, `{label}: every seat is live`)
						for s = 1, seatCount do
							t.equal(#a.seats[s].hand, Types.HAND_SIZE, `{label}: seat {s} holds 4`)
							if s > 1 then
								t.equal(#a.seats[s].inbox, 0, `{label}: only the dealer's inbox is stocked`)
							end
						end
						t.equal(#a.seats[1].inbox, 4 * k + j, `{label}: the dealer's inbox IS the deck`)
						local b = Engine.newRound(
							configFor(seatCount, k, j, mode),
							ids,
							Rng.new(seatCount * 100 + k * 10 + j)
						)
						t.deepEqual(snapshot(a), snapshot(b), `{label}: the same seed deals the same round`)
					end
				end
			end
		end
		gridFor("Wild")
		gridFor("Blocker")
	end)

	-- 25 -----------------------------------------------------------------------------------------
	t.test("a forced pass from the valve is a normal pass plus a marker, end to end", function()
		-- CARD-11 wired. This drives `tests/harness/Livelock`'s hand-verified cycle through the REAL
		-- `Engine.apply`, never through the fixture's own `Livelock` mutator, because a fixture only
		-- ever driven by its private mutator proves nothing about the shipped engine.
		--
		-- What is claimed, and it is the measured claim and no more: the valve eliminated OBSERVED
		-- stalls for the selected pool. At k=2,j=2 its measured stall rate with the valve ON is
		-- 0.025%, not zero (02-CONTEXT.md amendment A7-CORRECTION), so "the engine cannot stall" is
		-- false and must never be written down.
		local VALVE_SEED = 1
		local LIMIT = 2000
		local INJECT_AFTER = 49 -- an odd action, so the seat that just drew is holding five

		local state = Livelock.build({ antiLivelockValve = true, valveSeed = VALVE_SEED })
		local fx = Livelock.newDriver(state)
		local hashes: { string } = {}
		local accepted = 0
		local firedAt: number? = nil
		local firedHandSize: number? = nil
		local completedAt: number? = nil
		local injectedReject: Types.Reject? = nil

		for action = 1, LIMIT do
			if action == INJECT_AFTER + 1 then
				-- A rejection must not move the valve. The canonical hash cannot catch this on its
				-- own: `Invariants.hash` excludes `valve` by design, so a valve entry point called
				-- on a rejection leaves the hash identical. That the firing below still lands on its
				-- expected action is the other half of the proof -- the injection did not perturb
				-- the trajectory at all.
				local before = Invariants.hash(state)
				local observations = state.valve.observations
				local refused = Engine.apply(state, { kind = "Draw", seat = fx.cursor })
				injectedReject = refused.reject
				t.equal(refused.ok, false, "the injected intent must be refused")
				t.equal(#refused.events, 0, "a rejection returns no events")
				t.equal(Invariants.hash(state), before, "a rejection moved a card")
				t.equal(state.valve.observations, observations, "a rejection moved the valve's observation count")
			end

			local intent = Livelock.nextIntent(fx)
			local result = Engine.apply(state, intent)
			t.truthy(result.ok, `action {action} was refused with {tostring(result.reject)}`)
			accepted += 1

			local kinds = kindsOf(result.events)
			for _, event in result.events do
				local drawn = drewCard(event)
				if drawn ~= nil then
					fx.lastDrawn = drawn
				end
				if event.kind == "Completed" then
					completedAt = action
				end
			end
			if #kinds == 3 and kinds[2] == "ValveForcedPass" then
				t.equal(firedAt, nil, "the case asserts the FIRST firing; it must be seen only once here")
				firedAt = action
				t.deepEqual(kinds, { "Drew", "ValveForcedPass", "Passed" }, "the LOCKED firing event order")
				local marker, passed = result.events[2], result.events[3]
				assert(marker.kind == "ValveForcedPass" and passed.kind == "Passed", "narrowing")
				t.equal(marker.cardId, passed.cardId, "the marker and the pass name the SAME card")
				t.equal(marker.to, passed.to, "and the same resolved target")
				t.equal(marker.seat, intent.seat, "the forced seat is the seat that drew")
				t.equal(
					marker.lap,
					action,
					"lap is actionsSinceProgress at the firing, which has never been reset here"
				)
				t.equal(
					table.find(state.seats[marker.to].inbox, marker.cardId) ~= nil,
					true,
					"a forced pass is a REAL pass: the card is in the successor's inbox"
				)
				firedHandSize = #state.seats[marker.seat].hand
			end

			local ok, why = Invariants.check(state)
			t.truthy(ok, `action {action} left the state reporting {tostring(why)}`)
			hashes[action] = Invariants.hash(state)
			if completedAt ~= nil then
				break
			end
		end

		t.equal(injectedReject, "HandNotFour", "the injected intent's own code")
		t.equal(firedAt, 113, "the valve's FIRST firing on this fixture, through the real apply")
		t.equal(
			firedHandSize,
			Types.HAND_SIZE,
			"the forced seat is back to a resting hand, exactly as after a real pass"
		)
		t.equal(state.valve.firings, 1, "exactly one firing was needed")
		t.equal(hashes[17], hashes[33], "the cycle was intact while the valve was unarmed")
		t.equal(hashes[33], hashes[49], "and still intact at action 49")
		-- The table that provably never completes DID complete, one action after the forced pass.
		t.equal(completedAt, 114, "the round escaped into a completion on the action after the firing")
		t.truthy(hashes[#hashes] ~= hashes[17], "the round left the cycle: the final state is not a cycle state")
		t.equal(
			state.valve.observations,
			accepted,
			"exactly one valve entry point ran per ACCEPTED apply, and none per rejection"
		)
		t.equal(accepted, 114, "114 accepted applies; the injected rejection is not one of them")
	end)

	-- 26 -----------------------------------------------------------------------------------------
	t.test("MUTATION: with antiLivelockValve = false the identical fixture never escapes", function()
		-- One half of case 25 fails if the valve is not wired; THIS half fails if the fixture is not
		-- really a cycle. Without it, "the valve rescued the round" is unfalsifiable: a round that
		-- would have escaped on its own looks exactly the same.
		local LIMIT = 2000
		local state = Livelock.build({ antiLivelockValve = false, valveSeed = 1 })
		local fx = Livelock.newDriver(state)
		local hashes: { string } = {}
		local forced, completions, fourOfAKind = 0, 0, 0

		for action = 1, LIMIT do
			local intent = Livelock.nextIntent(fx)
			local result = Engine.apply(state, intent)
			t.truthy(result.ok, `action {action} was refused with {tostring(result.reject)}`)
			for _, event in result.events do
				local drawn = drewCard(event)
				if drawn ~= nil then
					fx.lastDrawn = drawn
				end
				if event.kind == "ValveForcedPass" then
					forced += 1
				end
				if event.kind == "Completed" then
					completions += 1
				end
			end
			-- Completion-freedom SCANNED, not read off `counters.completions`: a counter assertion
			-- alone would also pass if the engine simply stopped detecting completions.
			for _, seat in state.seats do
				if seat.live then
					local counts: { [Types.Rank]: number } = {}
					for _, id in seat.hand do
						local rank = state.rankOf[id]
						counts[rank] = (counts[rank] or 0) + 1
						if counts[rank] >= 4 then
							fourOfAKind += 1
						end
					end
				end
			end
			local ok, why = Invariants.check(state)
			t.truthy(ok, `action {action} left the state reporting {tostring(why)}`)
			hashes[action] = Invariants.hash(state)
		end

		t.equal(forced, 0, "a disabled valve fired")
		t.equal(completions, 0, "the fixture is not completion-free")
		t.equal(fourOfAKind, 0, "a live hand held four of a rank, so the fixture is not completion-free")
		t.equal(state.valve.firings, 0, "the valve's own counter must agree")
		t.truthy(state.valve.armed, "the valve DID arm: the cost gate is the only thing the flag bypasses")
		t.equal(hashes[17], hashes[33], "the observation-point hash recurs")
		t.equal(hashes[33], hashes[49], "and keeps recurring")
		t.equal(hashes[LIMIT], hashes[16], "still cycling after 2,000 actions with the valve off")
		t.equal(state.valve.observations, LIMIT, "every action was observed")
	end)

	-- 27 -----------------------------------------------------------------------------------------
	t.test("apply never yields and hands control to nobody", function()
		-- Plan 02-03's R3 guard already fails the whole gate chain on any of these inside a pure
		-- zone. This case exists so a developer running only `--filter engine` still sees it, and so
		-- the reason is recorded next to the code it protects (CLAUDE.md rules 5 and 6). The needles
		-- are built by concatenation so this assertion is not its own counterexample.
		local source = fs.readFile(ENGINE_PATH)
		local needles = { "corou" .. "tine", "o" .. "s.", "ta" .. "sk.", ":Wa" .. "it(", "call" .. "back" }
		for _, needle in needles do
			t.equal(
				string.find(source, needle, 1, true),
				nil,
				`{ENGINE_PATH} contains "{needle}": apply must be synchronous and must return its events`
			)
		end
		t.truthy(
			string.find(source, "function apply(state: Types.State, intent: Types.Intent)", 1, true) ~= nil,
			"apply must take exactly two parameters: a state and an intent, with no handler function"
		)
	end)
end
