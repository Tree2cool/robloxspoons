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

return {
	build = build,
	successorOf = successorOf,
	pass = pass,
	draw = draw,
}
