--!strict
local Invariants = require("../../src/server/engine/Invariants")
local Ring = require("../../src/server/engine/Ring")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

-- Counters derived by SCANNING the live containers, exactly as plan 02-01's spec does it. A second
-- copy of the fixture rather than a shared module, on purpose: a divergence between this copy and
-- ring.spec's shows up as a failing assertion rather than as silence.
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

-- Seat `s` holds IDs (s-1)*4+1 .. s*4 and the dealer's inbox holds the rest ascending, because the
-- dealer's inbox IS the deck. The ring itself is wired by `Ring.build`.
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

-- Moves `count` cards off the front of the deck into `seatId`'s inbox, the way upstream passing
-- would have delivered them. Conservation-preserving: nothing is created and nothing is dropped.
local function deliver(state: Types.State, seatId: Types.SeatId, count: number)
	local deck = state.seats[1].inbox
	for _ = 1, count do
		local id = deck[1]
		table.remove(deck, 1)
		table.insert(state.seats[seatId].inbox, id)
	end
	recount(state)
end

-- The CALLER's half of a completion (`Engine.apply`, plan 02-07): the four of a kind leaves the
-- hand for `state.retired` BEFORE `removeSeat` is called. `removeSeat` never retires anything --
-- that is exactly why the cause cannot fork the routing.
local function retireFour(state: Types.State, seatId: Types.SeatId, ids: { Types.CardId })
	local hand = state.seats[seatId].hand
	for _, id in ids do
		for i, held in hand do
			if held == id then
				table.remove(hand, i)
				break
			end
		end
		table.insert(state.retired, id)
	end
	state.counters.completions += 1
	recount(state)
end

-- Seat 3 holding all four copies of rank 3 (IDs 9..12) plus a fifth card, with one more card
-- waiting in its inbox: the state `Engine.apply` is in at the instant a completion is detected on
-- a draw.
local function completionReady(): Types.State
	local state = makeRing(5, 7, 0, "Wild")
	deliver(state, 3, 2)
	Ring.draw(state, 3)
	recount(state)
	return state
end

-- The deterministic Rule 8 fixture research 3.4 recommends: a conservation-clean state in which
-- EXACTLY ONE rank is still fully intact and all four of its copies sit in seat 1's hand and inbox.
-- Every other rank has been partly retired, so no other rank can ever be completed, and seat 2's
-- own cards cannot rescue the round. Jokers are absent, so `satisfiable` in Wild mode is exactly
-- "some rank still has all four copies in play".
--   ranks 1..6, no jokers, T = 24. seatCount 4, liveCount 2, churnRemovals 0, so plan 02-01's
--   identity #retired + #terminal == 4 * (seatCount - liveCount - churnRemovals) gives 8 retired,
--   which is why the STARTING state is conservation-clean and the mutation below is the only change.
local function makeOneIntactRank(): Types.State
	local state = makeRing(4, 6, 0, "Wild")
	for _, seatId in { 3, 4 } do
		local dead = state.seats[seatId]
		dead.hand = {}
		dead.inbox = {}
		dead.live = false
		dead.next = seatId
		dead.prev = seatId
	end
	state.liveCount = 2
	state.head = 1
	state.seats[1].next, state.seats[1].prev = 2, 2
	state.seats[2].next, state.seats[2].prev = 1, 1
	state.counters.completions = 2
	state.retired = { 5, 6, 9, 10, 13, 14, 17, 21 }
	state.seats[1].hand = { 1, 2, 7, 8 } -- rank 1 x2, rank 2 x2
	state.seats[1].inbox = { 3, 4, 11, 12 } -- rank 1 x2, rank 3 x2
	state.seats[2].hand = { 15, 16, 18, 19 } -- rank 4 x2, rank 5 x2
	state.seats[2].inbox = { 20, 22, 23, 24 } -- rank 5 x1, rank 6 x3
	recount(state)
	return state
end

return function(t: Test.Runner)
	local function expectClean(state: Types.State, label: string)
		local ok, why = Invariants.check(state)
		t.equal(why, nil, `a well-formed state reported a violation ({label})`)
		t.equal(ok, true, `a well-formed state did not report ok ({label})`)
	end

	-- 9 ----------------------------------------------------------------------------------------
	t.test("all three causes route identically", function()
		-- CLAUDE.md rule 8: ONE generic operation for completion, disconnect and AFK. The three
		-- states are made byte-identical at the moment of the call -- including the caller-side
		-- retirement, which is the caller's work in every cause -- so the only thing that can differ
		-- afterwards is what `removeSeat` itself did. If a future edit forks the routing by cause,
		-- this is the case that fails, and the disconnect path is the one nobody exercises by hand.
		-- The causes are passed as LITERALS at the call site rather than iterated out of a table:
		-- Luau widens a singleton-string literal table to `{ string }`, and the widened element no
		-- longer satisfies `RemoveCause` at the call site (the same real TypeError plan 02-01's
		-- spec documents for `JokerMode`).
		local function routeWith(cause: Types.RemoveCause): ({ Types.CardId }, string, number)
			local state = completionReady()
			retireFour(state, 3, { 9, 10, 11, 12 })
			local routedTo, moved = Ring.removeSeat(state, 3, cause)
			t.equal(routedTo, 4, `the successor of seat 3 ({cause})`)
			t.equal(moved, 2, `cards routed ({cause})`)
			return table.clone(state.seats[4].inbox), Invariants.hash(state), state.counters.churnRemovals
		end
		local completedInbox, completedHash, completedChurn = routeWith("Completed")
		local disconnectedInbox, disconnectedHash, disconnectedChurn = routeWith("Disconnected")
		local benchedInbox, benchedHash, benchedChurn = routeWith("Benched")
		t.deepEqual(completedInbox, { 21, 22 }, "the successor's inbox gained the fifth card and the left pile")
		t.deepEqual(disconnectedInbox, completedInbox, "Disconnected routed differently from Completed")
		t.deepEqual(benchedInbox, completedInbox, "Benched routed differently from Completed")
		t.equal(disconnectedHash, completedHash, "Disconnected left a different table from Completed")
		t.equal(benchedHash, completedHash, "Benched left a different table from Completed")
		-- The ONE thing the cause is allowed to change.
		t.deepEqual(
			{ completedChurn, disconnectedChurn, benchedChurn },
			{ 0, 1, 1 },
			"only churnRemovals may differ by cause"
		)
	end)

	-- 10 ---------------------------------------------------------------------------------------
	t.test("the dump order is hand-first then inbox in FIFO order", function()
		-- The OQ-G lock (research 7.4). This is a replay-determinism assertion: a different order is
		-- a different draw order for the successor, and therefore a different round.
		local state = makeRing(5, 7, 0, "Wild")
		deliver(state, 3, 2)
		-- A hand is a multiset, so its storage order is arbitrary. Permuting it here is what proves
		-- the ascending sort does something rather than inheriting the fixture's order.
		state.seats[3].hand = { 12, 9, 11, 10 }
		t.deepEqual(state.seats[3].inbox, { 21, 22 }, "the departing inbox, in FIFO order")
		expectClean(state, "before the removal")
		local routedTo, moved = Ring.removeSeat(state, 3, "Disconnected")
		t.equal(routedTo, 4, "the successor")
		t.equal(moved, 6, "four from the hand and two from the inbox")
		t.deepEqual(state.seats[4].inbox, { 9, 10, 11, 12, 21, 22 }, "hand ascending, THEN inbox in FIFO order")
		t.deepEqual(state.seats[3].hand, {}, "the departing hand is emptied, not left aliased")
		t.deepEqual(state.seats[3].inbox, {}, "the departing inbox is emptied, not left aliased")
		expectClean(state, "after the removal")
	end)

	-- 11 ---------------------------------------------------------------------------------------
	t.test("ring shrinks to 2", function()
		-- Research 7.1: `seats[A.prev].next = A.next` and `seats[A.next].prev = A.prev` both reduce
		-- to `B.next = B; B.prev = B` when A.next == A.prev == B. m = 2 is N = 3, the minimum
		-- roster, so this is a shipping configuration.
		local state = makeRing(5, 7, 0, "Wild")
		for _, seatId in { 3, 4, 5 } do
			Ring.removeSeat(state, seatId, "Disconnected")
			expectClean(state, `after removing seat {seatId}`)
		end
		t.equal(state.liveCount, 2, "two seats left")
		t.equal(state.seats[1].next, 2, "the dealer's next")
		t.equal(state.seats[1].prev, 2, "the dealer's prev is the same seat as its next at m = 2")
		t.equal(state.seats[2].next, 1, "seat 2's next")
		t.equal(state.seats[2].prev, 1, "seat 2's prev")
		-- ...and it is playable both ways round, not merely well-formed.
		local down = Ring.draw(state, 1)
		t.equal(Ring.pass(state, 1, down), 2, "the dealer passes to seat 2")
		expectClean(state, "m=2 after a pass")
		local back = Ring.draw(state, 2)
		t.equal(back, down, "seat 2 drew the card the dealer passed")
		t.equal(Ring.pass(state, 2, back), 1, "seat 2 passes back to the dealer")
		local inbox = state.seats[1].inbox
		t.equal(inbox[#inbox], back, "the card landed at the tail of the dealer's deck")
		expectClean(state, "m=2 after the round trip")
	end)

	-- 12 ---------------------------------------------------------------------------------------
	t.test("ring shrinks to 1", function()
		-- Research 7.2: a 1-seat ring is PLAYABLE, not merely non-crashing. The sole remaining seat
		-- is the empty-handed seeker, and PROJECT.md awards a four-of-a-kind bonus with zero find
		-- points to a seeker who completes but finds no spoon, so this is a shipping state. Do not
		-- "fix" it with an early return.
		local state = makeRing(5, 7, 0, "Wild")
		for _, seatId in { 3, 4, 5, 2 } do
			Ring.removeSeat(state, seatId, "Disconnected")
			expectClean(state, `after removing seat {seatId}`)
		end
		t.equal(state.liveCount, 1, "one seat left")
		t.equal(state.head, 1, "head is the survivor")
		t.equal(state.seats[1].next, 1, "next is self")
		t.equal(state.seats[1].prev, 1, "prev is self")
		local drawn = Ring.draw(state, 1)
		expectClean(state, "m=1 after a draw")
		t.equal(Ring.pass(state, 1, drawn), 1, "a pass at m = 1 targets yourself")
		local inbox = state.seats[1].inbox
		t.equal(inbox[#inbox], drawn, "the card went to the tail of your own inbox")
		expectClean(state, "m=1 after a pass")
	end)

	-- 13 ---------------------------------------------------------------------------------------
	t.test("the ring empties and nothing is destroyed", function()
		-- Research 7.3, where Rule 8 collides with itself: the fifth card and the left pile must go
		-- to "the successor", and the sole remaining seat has none. Routing to self would resurrect
		-- a dead seat and destroying the cards would break Rule 8, so they move to `state.terminal`,
		-- which the partition identity counts. That is what keeps "never destroyed" literally
		-- assertable instead of merely promised.
		local state = makeRing(5, 7, 0, "Wild")
		for _, seatId in { 3, 4, 5, 2 } do
			Ring.removeSeat(state, seatId, "Disconnected")
		end
		expectClean(state, "the sole seat before it completes")
		Ring.draw(state, 1) -- hand of five: {1, 2, 3, 4, 21}
		retireFour(state, 1, { 1, 2, 3, 4 })
		local held = table.clone(state.seats[1].hand)
		for _, id in state.seats[1].inbox do
			table.insert(held, id)
		end
		local routedTo, moved = Ring.removeSeat(state, 1, "Completed")
		t.equal(routedTo, nil, "there is no successor, so nothing was routed to a seat")
		t.equal(moved, #held, "every card the seat held moved")
		t.equal(state.liveCount, 0, "the ring is empty")
		t.equal(state.head, 0, "head is the ring-emptied sentinel")
		t.deepEqual(state.terminal, held, "terminal holds exactly the cards the seat held")
		t.equal(#state.retired + #state.terminal, state.totalCards, "every card is still accounted for")
		-- At liveCount == 0 the partition identity is the only live proof left, and it is the one
		-- that matters: every one of the T card IDs appears exactly once, in some bucket.
		expectClean(state, "the emptied ring")
	end)

	-- 14 ---------------------------------------------------------------------------------------
	t.test("removing the dealer is not a special case", function()
		-- Research 7.5. This looks like it should be special -- the dealer holds the deck -- and
		-- CLAUDE.md's "the wrap needs no special case" is only true if it is not.
		local state = makeRing(5, 7, 0, "Wild")
		local deck = table.clone(state.seats[1].inbox)
		local routedTo, moved = Ring.removeSeat(state, 1, "Disconnected")
		t.equal(routedTo, 2, "the deck's new holder")
		t.equal(moved, 12, "four from the dealer's hand and eight from the deck")
		t.deepEqual(state.seats[2].inbox, { 1, 2, 3, 4, 21, 22, 23, 24, 25, 26, 27, 28 }, "hand first, then the deck")
		local tail = table.clone(state.seats[2].inbox)
		for _ = 1, 4 do
			table.remove(tail, 1)
		end
		t.deepEqual(tail, deck, "the deck arrived intact and in order")
		t.equal(state.head, 2, "head moved to the successor and never pointed at a dead seat")
		expectClean(state, "after removing the dealer")
		-- Seat 2 is now the de-facto deck holder, so a full wrap still works: the pass out of the
		-- last seat lands beneath seat 2's pile with no code knowing it is a deck.
		local cursor = 2
		for _ = 1, 4 do
			local drawn = Ring.draw(state, cursor)
			local target = Ring.pass(state, cursor, drawn)
			t.equal(target, state.seats[cursor].next, "the pass resolved next at call time")
			local inbox = state.seats[target].inbox
			t.equal(inbox[#inbox], drawn, "the card landed at the tail")
			expectClean(state, `wrap step from seat {cursor}`)
			cursor = target
		end
		t.equal(cursor, 2, "the wrap came back round to the deck holder")
	end)

	-- 15 ---------------------------------------------------------------------------------------
	t.test("a churn removal raises circulation by exactly 4", function()
		-- Research 4.1: a non-completing removal is the ONLY operation that moves circulation, and
		-- it always moves it by exactly +4 -- the formal statement of "churn makes the table looser,
		-- never tighter". Both a resting hand of 4 and a locked hand of 5 must give +4.
		local resting = makeRing(5, 7, 0, "Wild")
		local before = Invariants.circulation(resting)
		Ring.removeSeat(resting, 3, "Disconnected")
		t.equal(Invariants.circulation(resting), before + 4, "a departing hand of 4")
		t.equal(resting.counters.churnRemovals, 1, "the churn was counted")
		expectClean(resting, "after a churn removal at a hand of 4")

		local locked = makeRing(5, 7, 0, "Wild")
		deliver(locked, 3, 1)
		Ring.draw(locked, 3) -- seat 3 is now holding five
		local lockedBefore = Invariants.circulation(locked)
		t.equal(#locked.seats[3].hand, 5, "the fixture must hold five, or it proves nothing")
		Ring.removeSeat(locked, 3, "Benched")
		t.equal(Invariants.circulation(locked), lockedBefore + 4, "a departing hand of 5")
		expectClean(locked, "after a churn removal at a hand of 5")
	end)

	-- 16 ---------------------------------------------------------------------------------------
	t.test("a completion removal leaves circulation unchanged", function()
		local state = completionReady()
		local before = Invariants.circulation(state)
		local expectedBefore = Invariants.expectedCirculation(state)
		-- The retirement and the removal are two halves of ONE apply. Measured across the pair,
		-- a completion is net zero (research 4.1); the state in between -- a hand of one -- is
		-- transient and is never handed to `check`.
		retireFour(state, 3, { 9, 10, 11, 12 })
		Ring.removeSeat(state, 3, "Completed")
		t.equal(Invariants.circulation(state), before, "a completion is net zero")
		t.equal(Invariants.expectedCirculation(state), expectedBefore, "churn did not move")
		t.equal(state.counters.churnRemovals, 0, "a completion is not churn")
		expectClean(state, "after a completion removal")
	end)

	-- 17 ---------------------------------------------------------------------------------------
	t.test("MUTATION: destroying a removed seat's cards breaks conservation and kills the multiset", function()
		-- The Rule 8 tripwire proof, built the deterministic way research 3.4 recommends rather than
		-- statistically. Measured there: across 12,800 rounds the destroy variant fired the
		-- satisfiability tripwire in 2.9-5.7% of rounds while the honest variant fired it in 0.0%.
		-- That is why a crafted fixture is paired with the statistical version in plan 02-09's
		-- simulator: 3-6% is too rare to be a reliable unit test, and 0% is indistinguishable from a
		-- predicate that cannot fire at all.
		local routed: { Types.CardId } = { 1, 2, 7, 8, 3, 4, 11, 12 } -- hand ascending, then inbox FIFO

		-- The honest path: Rule 8 is obeyed, so the round stays solvable.
		local honest = makeOneIntactRank()
		expectClean(honest, "the crafted fixture before the removal")
		t.equal(Invariants.satisfiable(honest), true, "the fixture must start solvable")
		t.equal(honest.counters.cnt[5], 1, "exactly one rank is still fully intact")
		local routedTo, moved = Ring.removeSeat(honest, 1, "Disconnected")
		t.equal(routedTo, 2, "the successor")
		t.equal(moved, #routed, "every held card was routed")
		t.deepEqual(honest.seats[2].inbox, { 20, 22, 23, 24, 1, 2, 7, 8, 3, 4, 11, 12 }, "routed to the tail")
		t.equal(Invariants.satisfiable(honest), true, "routing the cards keeps the round solvable")
		expectClean(honest, "after the honest removal")

		-- The destruction Rule 8 forbids, performed from the TEST side: no shipped code path can do
		-- this, which is the whole point of there being no `destroyCards` parameter on `removeSeat`.
		local destroyed = makeOneIntactRank()
		Ring.removeSeat(destroyed, 1, "Disconnected")
		local inbox = destroyed.seats[2].inbox
		local gone: { [Types.CardId]: true } = {}
		for _, id in routed do
			gone[id] = true
		end
		local kept: { Types.CardId } = {}
		for _, id in inbox do
			if not gone[id] then
				table.insert(kept, id)
			end
		end
		destroyed.seats[2].inbox = kept
		recount(destroyed) -- the counters follow the cards into the void, so `satisfiable` can see it
		t.deepEqual(destroyed.seats[2].inbox, { 20, 22, 23, 24 }, "the routed cards were destroyed")

		-- The multiset died: no rank has four copies left in play and there is no joker to stand in,
		-- so no seat can ever reach four of a kind. Asserted through the PREDICATE, directly.
		t.equal(Invariants.satisfiable(destroyed), false, "destroying a removed seat's cards kills the multiset")
		t.equal(destroyed.counters.cnt[5], 0, "no rank is fully intact any more")

		-- ...and `check` reports `circulation`, NOT the satisfiability violation. `check` returns the
		-- FIRST violation in a locked order: `circulation` is violation 4 and the satisfiability
		-- tripwire is violation 9. Destroying cards drops `Invariants.circulation` while
		-- `expectedCirculation` is unchanged, so the conservation break is reported and violation 9
		-- is never reached. Both facts are worth asserting -- the cards vanished AND the multiset
		-- died. Reordering the violation list so violation 9 comes out here is forbidden: it would
		-- make every genuine conservation bug surface as a stall statistic in the simulator instead
		-- of as an error, inverting the whole design of `Invariants.check`. Plan 02-09's simulator
		-- classifies that stall category from `satisfiable()` for exactly the same reason.
		local ok, why = Invariants.check(destroyed)
		t.equal(why, "circulation", "a vanished card is a conservation bug and must be reported as one")
		t.equal(ok, false, "check reported ok on a state with eight destroyed cards")
		t.equal(Invariants.circulation(destroyed), 4, "circulation fell by the eight destroyed cards")
		t.equal(Invariants.expectedCirculation(destroyed), 12, "...while the expected side did not move")
	end)

	-- 18 ---------------------------------------------------------------------------------------
	t.test("a double removal is a loud error", function()
		-- Silently returning would leave `liveCount` and the ring disagreeing, and nothing else in
		-- the phase would notice until a fuzz run days later.
		local state = makeRing(5, 7, 0, "Wild")
		Ring.removeSeat(state, 3, "Disconnected")
		t.throws(function()
			Ring.removeSeat(state, 3, "Disconnected")
		end, "not live")
		t.throws(function()
			Ring.removeSeat(state, 99, "Benched")
		end, "no seat")
		expectClean(state, "after the rejected double removal")
	end)
end
