--!strict
-- The ring: a circular doubly-linked list over a fixed seat array, plus the pass and draw
-- primitives (CARD-03, CARD-04). PURE ZONE: no Roblox API, no clock, no yields.
--
-- 1. THIS MODULE PERFORMS NO LEGALITY CHECKING, AND THAT IS THE DIVISION OF LABOUR.
--    `Engine.apply` (plan 02-07) validates an intent and returns the reject code -- UnknownSeat,
--    SeatNotLive, UnknownCard, NotYourCard, HandNotFour, HandNotFive, InboxEmpty -- and only then
--    calls these primitives. A second validation layer here would create two places that can
--    disagree about what is legal, and one of them would not be the one the tests assert. That
--    split is also what lets the spec test FIFO ordering, the dealer wrap and a 1-seat ring
--    directly, without routing every case through intent validation.
--    The `error` calls below are CALLER-BUG assertions, not reject codes: they fire only where the
--    alternative is silent corruption (removing a card that is not in the hand would quietly drop
--    the hand's last card instead). A caller that reaches one has skipped `Engine.apply`.
-- 2. NEXT/PREV ARE INDICES, NEVER REFERENCES (research 6). That is what makes the canonical state
--    hash and a deep-equal trivial, keeps a state serialisable, and leaves no GC cycle behind a
--    dead seat.
-- 3. THERE IS NO LAST-SEAT BRANCH ANYWHERE IN THIS FILE. Seat m's `next` IS the dealer, so CARD-04
--    ("the last seat's passes land beneath the dealer's deck") is already satisfied by "append to
--    the tail of next's inbox". The dealer's inbox IS the deck: it needs no separate field and no
--    deck-empty path. If you ever find yourself writing a branch for the last seat, the ring is
--    wrong, not the rule.
-- 4. RULE 6, NO YIELDS INSIDE A MUTATION. Every function here is synchronous, returns its result,
--    takes no callback and publishes nothing; `Engine.apply` collects the events. There is no point
--    at which a handler could run mid-mutation.
-- 5. NO CODE PATH IN THIS MODULE DESTROYS A CARD, and none may ever be added (CLAUDE.md rule 8).
--    There is no `destroyCards` parameter and no discard list. The ring-emptied case routes to
--    `state.terminal` instead, so "never destroyed" stays literally assertable by the partition
--    identity. The destroy mutation that proves the Rule 8 tripwire can fire is performed from the
--    TEST side (tests/engine/removal.spec.luau), precisely so that no shipped path can do it.
local Types = require("./Types")

-- Wires seats 1..#playerIds into a circular ring and deals NOTHING: `Pool` (02-04) and
-- `Engine.newRound` (02-07) own the cards. `head` is the dealer, which is seat 1 by construction
-- because `SeatOrder` has already put the dealer at the head of the seat order (CARD-05).
local function build(state: Types.State, playerIds: { Types.PlayerId })
	local n = #playerIds
	local seats: { Types.Seat } = {}
	for i = 1, n do
		seats[i] = {
			id = i,
			playerId = playerIds[i],
			live = true,
			hand = {},
			inbox = {},
			-- The wrap, and the only place it is ever expressed: seat n's next is 1 and seat 1's
			-- prev is n. At n == 1 both reduce to self, which is a playable ring (research 7.2).
			next = (i % n) + 1,
			prev = ((i - 2) % n) + 1,
		}
	end
	state.seats = seats
	state.head = if n > 0 then 1 else 0
	state.liveCount = n
end

-- The next LIVE seat after `seatId`. With correct unlinking `next` ALWAYS points at a live seat, so
-- this needs no skip loop. Do not add one: if a skip loop is ever needed the unlink is broken, and
-- `Invariants.check` reports that as `ring-links`. A skip loop here would hide the corruption and
-- leave `liveCount` quietly disagreeing with the ring for the rest of the round.
-- Returns nil only when `seatId` is the sole live seat and is itself being removed (its links have
-- been pointed at itself and its liveness cleared), or when `seatId` names no seat at all.
local function successorOf(state: Types.State, seatId: Types.SeatId): Types.SeatId?
	local seat = state.seats[seatId]
	if seat == nil then
		return nil
	end
	local after = state.seats[seat.next]
	if after == nil or not after.live then
		return nil
	end
	return seat.next
end

-- Removes `cardId` from the seat's hand and appends it to the TAIL of the next seat's inbox.
-- Returns the target so the caller can put it in the `Passed` event.
--
-- THE TARGET IS RESOLVED HERE, AT EXECUTION TIME, AND THERE IS NO TARGET PARAMETER (CLAUDE.md
-- rule 7). The client names a stable card id and nothing else, so a pass whose intended neighbour
-- left between intent and execution lands in the departed seat's successor with no special handling
-- (research 6, 7.6). If this function took a `target` argument, the client could eventually supply
-- one, and seat steering would become a wire-level capability.
--
-- Circulation is unchanged by a pass: hand surplus -1, inbox +1 (research 4.1).
local function pass(state: Types.State, seatId: Types.SeatId, cardId: Types.CardId): Types.SeatId
	local seat = state.seats[seatId]
	if seat == nil then
		error(`pass: no seat {seatId}`)
	end
	local index: number? = nil
	for i, id in seat.hand do
		if id == cardId then
			index = i
			break
		end
	end
	if index == nil then
		-- A caller bug, not a reject: `Engine.apply` answers NotYourCard before it gets here.
		error(`pass: card {cardId} is not in seat {seatId}'s hand`)
	end
	table.remove(seat.hand, index)
	local target = seat.next
	table.insert(state.seats[target].inbox, cardId)
	return target
end

-- Pops the FRONT of the seat's own inbox and appends it to the hand. The inbox is FIFO in and FIFO
-- out: `pass` writes the tail, `draw` reads index 1. Circulation is unchanged (inbox -1, hand
-- surplus +1).
--
-- `table.remove(_, 1)` is O(#inbox) and that is deliberate. #inbox is bounded by circulation, which
-- is 4*(ranks - seatCount) + jokers + 4*churnRemovals -- at most a few dozen cards at the shipped
-- pool and at the 10-player cap. Do not "optimise" this into a head-index deque: a head index is a
-- second source of truth about where the front is, and the canonical hash, the valve's cycle
-- detection and every exact-array assertion in the specs all read the inbox as a plain array whose
-- front is index 1.
local function draw(state: Types.State, seatId: Types.SeatId): Types.CardId
	local seat = state.seats[seatId]
	if seat == nil then
		error(`draw: no seat {seatId}`)
	end
	local cardId = table.remove(seat.inbox, 1)
	if cardId == nil then
		-- A caller bug, not a reject: `Engine.apply` answers InboxEmpty before it gets here.
		error(`draw: seat {seatId} has an empty inbox`)
	end
	table.insert(seat.hand, cardId)
	return cardId
end

-- ONE operation for every cause (CLAUDE.md rule 8): completion, disconnect and AFK. Returns
-- (routedTo, cardsRouted); `routedTo` is nil when the ring emptied and the cards went to
-- `state.terminal` instead.
--
-- THE CAUSE MUST NEVER FORK THE ROUTING. Only `Completed` differs, and only in what the CALLER did
-- first: `Engine.apply` has already moved the four retired cards out of the hand. Inside this
-- function the cause affects exactly one thing -- `churnRemovals` is incremented when the cause is
-- not `Completed`. If the causes forked the routing, Rule 8 would hold on one path and not another,
-- and the disconnect path is the one nobody exercises by hand.
--
-- DUMP ORDER IS LOCKED (research 7.4, OQ-G): the departing HAND first, in ASCENDING card id, then
-- the departing INBOX in FIFO order, all appended to the successor's inbox tail. That preserves the
-- global chain order, because the inbox cards arrived from upstream after the hand was assembled.
-- Either choice is defensible; leaving it implicit is not, because it fixes the successor's draw
-- order and therefore replay determinism. removal.spec asserts the exact resulting array.
--
-- A 1-SEAT RING IS PLAYABLE, not merely non-crashing (research 7.2). After the last relink
-- `next == prev == self`, so a pass appends to your own inbox and a draw pops your own inbox:
-- self-consistent, still live, invariants unchanged. The sole remaining seat is the empty-handed
-- seeker, and PROJECT.md awards a four-of-a-kind bonus with zero find points to a seeker who
-- completes but finds no spoon, so it is a shipping state. Do not "fix" it with an early return.
local function removeSeat(state: Types.State, seatId: Types.SeatId, cause: Types.RemoveCause): (Types.SeatId?, number)
	local seats = state.seats
	local seat = seats[seatId]
	if seat == nil then
		error(`removeSeat: no seat {seatId}`)
	end
	if not seat.live then
		-- A double removal is a caller bug. Returning quietly would leave the ring and `liveCount`
		-- disagreeing, which gates three of `Invariants.check`'s nine checks.
		error(`removeSeat: seat {seatId} is not live`)
	end

	local routedTo: Types.SeatId? = if state.liveCount > 1 then seat.next else nil

	-- The dumped list, in the locked order. Nothing is ever dropped here: a card leaves this list
	-- only by being appended to the successor's inbox or to `state.terminal`.
	local dumped: { Types.CardId } = table.clone(seat.hand)
	table.sort(dumped)
	for _, id in seat.inbox do
		table.insert(dumped, id)
	end
	seat.hand = {}
	seat.inbox = {}

	if routedTo ~= nil then
		local inbox = seats[routedTo].inbox
		for _, id in dumped do
			table.insert(inbox, id)
		end
	else
		-- Research 7.3: the sole live seat is leaving, so there is no successor. Routing to self
		-- would resurrect a dead seat and destroying the cards would break Rule 8, so they move to
		-- the terminal bucket that the partition identity counts. "Never destroyed" stays literally
		-- assertable, and the engine still has no nil-successor path anywhere else.
		for _, id in dumped do
			table.insert(state.terminal, id)
		end
		-- A card in `terminal` is ACCOUNTED FOR but out of play, so this is the one place the
		-- function owns a play counter. Routing a card to an inbox does not take it out of play, so
		-- the routed branch above touches no counter at all (note for plan 02-07: do not
		-- double-count; only retirement and this terminal move change what is in play).
		local counters = state.counters
		for _, id in dumped do
			local rank = state.rankOf[id]
			if rank == Types.JOKER_RANK then
				counters.jokersInPlay -= 1
			else
				local copies = counters.rankInPlay[rank]
				counters.cnt[copies + 1] = (counters.cnt[copies + 1] or 0) - 1
				counters.rankInPlay[rank] = copies - 1
				counters.cnt[copies] = (counters.cnt[copies] or 0) + 1
			end
		end
	end

	-- Unlink. Written exactly this way so that a 2-ring is NOT a special case (research 7.1): when
	-- `seat.next == seat.prev == B`, both assignments reduce to `B.next = B` and `B.prev = B`, which
	-- is correct. Do not add an `if liveCount == 2` branch -- that is the shape a naive
	-- implementation takes, and it is the one that breaks the minimum roster.
	seats[seat.prev].next = seat.next
	seats[seat.next].prev = seat.prev

	seat.live = false
	-- Point the dead seat at itself so a stale reference cannot walk back into the live ring, and so
	-- `successorOf` answers nil for it rather than naming a seat it no longer belongs to.
	seat.next = seatId
	seat.prev = seatId
	state.liveCount -= 1

	if state.head == seatId then
		-- `head = 0` is the ring-emptied sentinel `Invariants.check` already special-cases; head is
		-- never left pointing at a dead seat.
		state.head = routedTo or 0
	end

	if cause ~= "Completed" then
		-- Research 4.1: a non-completing removal adds exactly 4 to circulation, because the
		-- departing hand's four resting cards become inbox cards. That +4 is the formal statement of
		-- "churn makes the table looser, never tighter". A completion is net zero across the
		-- retirement and the removal together, so it must NOT be counted here.
		state.counters.churnRemovals += 1
	end

	return routedTo, #dumped
end

return {
	build = build,
	successorOf = successorOf,
	pass = pass,
	draw = draw,
	removeSeat = removeSeat,
}
