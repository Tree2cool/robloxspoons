--!strict
local Invariants = require("../../src/server/engine/Invariants")
local Ring = require("../../src/server/engine/Ring")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

-- Counters derived by SCANNING the live containers, exactly as plan 02-01's spec does it and as
-- `Invariants.check` recomputes them. Deliberately a second copy rather than a shared fixture
-- module: a divergence between the two copies shows up as a failing assertion, not as silence.
local function recount(state: Types.State)
	local rankInPlay: { number } = {}
	for r = 1, state.config.ranks do
		rankInPlay[r] = 0
	end
	local jokersInPlay = 0
	for _, seat in state.seats do
		if seat.live then
			for _, ids in { seat.hand, seat.inbox } do
				for _, id in ids do
					local rank = state.rankOf[id]
					if rank == Types.JOKER_RANK then
						jokersInPlay += 1
					else
						rankInPlay[rank] += 1
					end
				end
			end
		end
	end
	local cnt: { number } = { 0, 0, 0, 0, 0 }
	for r = 1, state.config.ranks do
		local bucket = rankInPlay[r] + 1
		cnt[bucket] = (cnt[bucket] or 0) + 1
	end
	state.counters.rankInPlay = rankInPlay
	state.counters.jokersInPlay = jokersInPlay
	state.counters.cnt = cnt
end

-- Builds the ring with `Ring.build` (the function under test) and then lays the known 02-01 deal
-- over it: seat `s` holds IDs (s-1)*4+1 .. s*4 and the dealer's inbox holds the rest ascending,
-- because the dealer's inbox IS the deck.
local function makeRing(seatCount: number, ranks: number, jokers: number, mode: Types.JokerMode): Types.State
	local totalCards = 4 * ranks + jokers
	local rankOf: { Types.Rank } = {}
	for rank = 1, ranks do
		for _ = 1, 4 do
			table.insert(rankOf, rank)
		end
	end
	for _ = 1, jokers do
		table.insert(rankOf, Types.JOKER_RANK)
	end
	local playerIds: { Types.PlayerId } = {}
	for s = 1, seatCount do
		playerIds[s] = 100 + s
	end
	local state: Types.State = {
		config = { ranks = ranks, jokers = jokers, jokerMode = mode, antiLivelockValve = true },
		seatCount = seatCount,
		totalCards = totalCards,
		rankOf = rankOf,
		seats = {},
		liveCount = 0,
		head = 0,
		retired = {},
		terminal = {},
		counters = { rankInPlay = {}, jokersInPlay = 0, cnt = {}, completions = 0, churnRemovals = 0 },
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
	Ring.build(state, playerIds)
	for s = 1, seatCount do
		for id = (s - 1) * 4 + 1, s * 4 do
			table.insert(state.seats[s].hand, id)
		end
	end
	for id = seatCount * 4 + 1, totalCards do
		table.insert(state.seats[1].inbox, id)
	end
	recount(state)
	return state
end

return function(t: Test.Runner)
	local function expectClean(state: Types.State, label: string)
		local ok, why = Invariants.check(state)
		t.equal(why, nil, `a well-formed state reported a violation ({label})`)
		t.equal(ok, true, `a well-formed state did not report ok ({label})`)
	end

	-- 1 ----------------------------------------------------------------------------------------
	t.test("build wires a circular ring over indices", function()
		for _, seatCount in { 1, 2, 3, 9 } do
			local state = makeRing(seatCount, seatCount + 2, 1, "Wild")
			t.equal(state.head, 1, `head at m={seatCount}`)
			t.equal(state.liveCount, seatCount, `liveCount at m={seatCount}`)
			for s = 1, seatCount do
				local seat = state.seats[s]
				t.equal(seat.id, s, `seat id at m={seatCount}`)
				t.equal(seat.live, true, `seat liveness at m={seatCount}`)
				t.equal(seat.next, (s % seatCount) + 1, `next of seat {s} at m={seatCount}`)
				t.equal(seat.prev, ((s - 2) % seatCount) + 1, `prev of seat {s} at m={seatCount}`)
				-- next/prev are INDICES, not references: that is what makes the canonical hash and a
				-- deep-equal trivial and leaves no GC cycle (research 6).
				t.equal(type(seat.next), "number", "next must be an index")
			end
			-- The wrap, stated as the two assertions CARD-04 depends on.
			t.equal(state.seats[seatCount].next, 1, `the last seat's next is the dealer at m={seatCount}`)
			t.equal(state.seats[1].prev, seatCount, `the dealer's prev is the last seat at m={seatCount}`)
			expectClean(state, `build m={seatCount}`)
		end
	end)

	-- 2 ----------------------------------------------------------------------------------------
	t.test("a pass lands at the TAIL of next's inbox", function()
		-- Asserting membership would let a LIFO pile pass, so every inbox here is compared as an
		-- exact array with deepEqual.
		local state = makeRing(5, 7, 0, "Wild")
		t.deepEqual(state.seats[1].inbox, { 21, 22, 23, 24, 25, 26, 27, 28 }, "the dealer's inbox IS the deck")
		local first = state.seats[5].hand[1]
		local second = state.seats[5].hand[2]
		t.equal(Ring.pass(state, 5, first), 1, "pass returns the resolved target")
		t.equal(Ring.pass(state, 5, second), 1, "pass returns the resolved target")
		t.deepEqual(
			state.seats[1].inbox,
			{ 21, 22, 23, 24, 25, 26, 27, 28, first, second },
			"two passes must arrive at the tail, in order"
		)
		t.deepEqual(state.seats[5].hand, { 19, 20 }, "the passed cards left the hand")
	end)

	-- 3 ----------------------------------------------------------------------------------------
	t.test("a draw pops the FRONT of your own inbox", function()
		local state = makeRing(5, 7, 0, "Wild")
		local front = state.seats[1].inbox[1]
		local drawn = Ring.draw(state, 1)
		t.equal(drawn, front, "draw must pop the front: the inbox is FIFO in and FIFO out")
		t.deepEqual(state.seats[1].inbox, { 22, 23, 24, 25, 26, 27, 28 }, "the remainder is the old tail")
		t.deepEqual(state.seats[1].hand, { 1, 2, 3, 4, front }, "the drawn card is appended to the hand")
	end)

	-- 4 ----------------------------------------------------------------------------------------
	t.test("the last seat's pass lands beneath the dealer's deck", function()
		-- CARD-04. The point of this case is that NO CODE made it happen: seat m's `next` is the
		-- dealer, so "beneath the deck" is just "append to next's inbox tail".
		local state = makeRing(9, 11, 1, "Wild")
		local deck = table.clone(state.seats[1].inbox)
		t.deepEqual(
			deck,
			{ 37, 38, 39, 40, 41, 42, 43, 44, 45 },
			"the deal puts the whole circulating supply in the deck"
		)
		local card = state.seats[9].hand[1]
		t.equal(Ring.pass(state, 9, card), 1, "the last seat passes to the dealer")
		local inbox = state.seats[1].inbox
		t.equal(inbox[#inbox], card, "the passed card is at the tail, beneath the deck")
		local ahead = table.clone(inbox)
		table.remove(ahead)
		t.deepEqual(ahead, deck, "the deck's own cards are still ahead of it, in FIFO order")
	end)

	-- 5 ----------------------------------------------------------------------------------------
	t.test("the whole mechanic works at m = 2", function()
		-- Research 6: this is the case that proves there is no hidden last-seat branch, because the
		-- dealer is simultaneously the only `prev` and the only `next`. m = 2 is N = 3, the minimum
		-- roster, so it is a shipping configuration and not a curiosity.
		local state = makeRing(2, 4, 0, "Wild")
		t.deepEqual(state.seats[1].inbox, { 9, 10, 11, 12, 13, 14, 15, 16 }, "the deck")
		local before = Invariants.circulation(state)
		local drawn = Ring.draw(state, 1)
		t.equal(Ring.pass(state, 1, drawn), 2, "the dealer passes to seat 2")
		expectClean(state, "m=2 after the dealer's draw and pass")
		local back = Ring.draw(state, 2)
		t.equal(back, drawn, "seat 2 draws the card the dealer passed")
		t.equal(Ring.pass(state, 2, back), 1, "seat 2 passes back to the dealer, its only next")
		expectClean(state, "m=2 after the round trip")
		t.equal(Invariants.circulation(state), before, "a pass and a draw are both net zero")
		local inbox = state.seats[1].inbox
		t.equal(inbox[#inbox], back, "the card came back beneath the dealer's deck")
	end)

	-- 6 ----------------------------------------------------------------------------------------
	t.test("the whole mechanic works at m = 1", function()
		-- Research 7.2: a 1-seat ring is a legitimate playable state, not an error case. `next` and
		-- `prev` are self, so a pass appends to your own inbox and a draw pops your own inbox.
		local state = makeRing(1, 3, 0, "Wild")
		t.equal(state.seats[1].next, 1, "next is self")
		t.equal(state.seats[1].prev, 1, "prev is self")
		expectClean(state, "m=1 at the deal")
		local drawn = Ring.draw(state, 1)
		expectClean(state, "m=1 after a draw")
		t.equal(Ring.pass(state, 1, drawn), 1, "a pass at m = 1 targets yourself")
		local inbox = state.seats[1].inbox
		t.equal(inbox[#inbox], drawn, "the card went to the tail of your own inbox")
		expectClean(state, "m=1 after a pass")
	end)

	-- 7 ----------------------------------------------------------------------------------------
	t.test("the target is resolved at execution time", function()
		-- CARD-03's actual wording is "the server resolving which seat that is at execution time",
		-- and this is the case that distinguishes it from a cached target: seat 5's neighbour left
		-- between the intent and the execution, so the card lands in the DEPARTED seat's successor,
		-- with no rejection and no special handling (research 6, 7.6). The client never names the
		-- target (CLAUDE.md rule 7) and `pass` has no target parameter to name it with.
		local state = makeRing(9, 11, 1, "Wild")
		t.equal(state.seats[5].next, 6, "seat 5's neighbour at the deal")
		Ring.removeSeat(state, 6, "Disconnected")
		t.equal(Ring.successorOf(state, 5), 7, "seat 5's successor after the departure")
		t.equal(Ring.successorOf(state, 6), nil, "a removed seat has no successor to steer toward")
		local card = state.seats[5].hand[1]
		local target = Ring.pass(state, 5, card)
		t.equal(target, 7, "the pass landed in the departed seat's successor")
		local inbox = state.seats[7].inbox
		t.equal(inbox[#inbox], card, "at the tail, behind the cards seat 6 routed there")
		t.equal(#inbox, 5, "seat 6's four routed cards are still ahead of it")
	end)

	-- 8 ----------------------------------------------------------------------------------------
	t.test("circulation is unchanged by every pass and every draw", function()
		-- Research 4.1 and CARD-04's "the deck never runs dry": `Invariants.check` must be clean and
		-- circulation must not move after EVERY single operation, not merely at the end.
		local state = makeRing(9, 11, 1, "Wild")
		local expected = Invariants.circulation(state)
		t.equal(expected, 9, "circulation is 4k + j at the deal")
		local operations = 0
		local cursor = 1
		local guard = 0
		while operations < 200 do
			guard += 1
			t.truthy(guard < 4000, "the walk failed to find a legal action; the ring is corrupt")
			local seat = state.seats[cursor]
			if #seat.hand == Types.HAND_SIZE and #seat.inbox >= 1 then
				Ring.draw(state, cursor)
				operations += 1
				expectClean(state, `after draw {operations}`)
				t.equal(Invariants.circulation(state), expected, "a draw moved circulation")
				Ring.pass(state, cursor, seat.hand[1])
				operations += 1
				expectClean(state, `after pass {operations}`)
				t.equal(Invariants.circulation(state), expected, "a pass moved circulation")
			end
			t.truthy(Invariants.circulation(state) >= 1, "the deck ran dry")
			cursor = state.seats[cursor].next
		end
		t.equal(operations, 200, "200 alternating operations")
	end)
end
