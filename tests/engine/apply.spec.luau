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
local Engine = require("../../src/server/engine/Engine")
local Invariants = require("../../src/server/engine/Invariants")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

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
end
