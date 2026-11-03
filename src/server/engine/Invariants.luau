--!strict
-- The engine's two conserved quantities, the satisfiability predicate and the canonical state hash.
-- PURE ZONE: no Roblox API, no clock, no yields. `check` REPORTS, it never throws: the caller
-- decides whether a violation is fatal.
--
-- WHY THIS MODULE IS WRITTEN THE AWKWARD WAY. Research Pitfall 4: a conservation check whose two
-- sides are produced by the same helper is green forever, and Phase 1 verification found two checks
-- exactly like that. So `check` DERIVES ONE SIDE INDEPENDENTLY -- it walks the real seat containers
-- and recomputes hand contents, card identity, rank counts and the histogram, then compares the
-- result against `state.counters`. There is deliberately no cached `circulation` field on State to
-- compare with itself.
--
-- COST. Research 4.2 benchmarked the full identity scan at 343,502 actions/s against 595,017 for
-- counters only: 1.7x. At that price there is no tiering. `check` always does everything, and a
-- caller that cannot afford it calls `circulation` and `satisfiable` directly.
--
-- THE VIOLATION ORDER IS LOCKED (Types.Violation declares it). `circulation` precedes
-- `unsatisfiable` deliberately: a card that vanished is a conservation bug and must be reported as
-- one. If `unsatisfiable` came first, every genuine conservation bug would surface as a stall
-- statistic in the simulator instead of as an error. Never reorder this to make an assertion pass.
--
-- `liveness` (3) is a SUBSUMED TRIPWIRE and that is the theorem, not an oversight. Once `hand-size`
-- (1) has passed, every live hand holds 4 or 5 cards, so `circulation >= 1` forces some seat to hold
-- 5 (it can pass) or to hold 4 with a non-empty inbox (it can draw) -- research 3.1 Claim 3. It is
-- therefore unreachable in that position, and the spec locks the order by asserting that a state
-- with no legal action reports `hand-size` rather than `liveness`.
local Types = require("./Types")

local HAND_SIZE = Types.HAND_SIZE
local MAX_HAND = Types.MAX_HAND
local JOKER_RANK = Types.JOKER_RANK
local BUCKETS = 5 -- cnt[a + 1] for a in 0..4: how many ranks have exactly a copies in play

-- Sum over LIVE seats of inbox depth plus the transient fifth card. Research 4.1: draw, pass and
-- completion are all net zero, so this is a constant of the pool between churn removals.
local function circulation(state: Types.State): number
	if state.liveCount == 0 then
		return 0 -- the ring emptied (research 7.3): nothing circulates, by definition
	end
	local total = 0
	for _, seat in state.seats do
		if seat.live then
			total += #seat.inbox + (#seat.hand - HAND_SIZE)
		end
	end
	return total
end

-- The other side of the circulation identity, derived from the pool and the churn count alone.
-- Only a non-completing removal moves it, and always by exactly +4 (research 4.1).
-- CARD-04's "the deck never runs dry" is the assertion that this stays >= 1.
local function expectedCirculation(state: Types.State): number
	return 4 * (state.config.ranks - state.seatCount) + state.config.jokers + 4 * state.counters.churnRemovals
end

-- O(1) from the histogram, never a search (research 3.2).
local function satisfiable(state: Types.State): boolean
	if state.liveCount == 0 then
		return true -- the round is over; there is nothing left to satisfy
	end
	local counters = state.counters
	if state.config.jokerMode == "Blocker" then
		-- A joker cannot complete a set, so only a rank with all four copies still in play can.
		return (counters.cnt[BUCKETS] or 0) > 0
	end
	local lowest = math.max(1, 4 - counters.jokersInPlay)
	local total = 0
	for copies = lowest, 4 do
		total += counters.cnt[copies + 1] or 0
	end
	return total > 0
end

-- Canonical: head, then per seat in index order, liveness, the hand SORTED and the inbox in FIFO
-- order. The inbox order must matter (it determines every future draw) and the hand order must not
-- (a hand is a multiset), so a cycle of play hashes equal.
--
-- Hashes NOTHING else: not `counters`, not `valve`, not `rankOf`. Load-bearing twice over. Plan
-- 02-13's valve fires when a whole-table state REPEATS, decided from exactly this string, so one
-- monotonically increasing counter inside it would make every state unique, the valve would never
-- fire, and amendment A7's mechanism would be silently vacuous. The simulator's cycle detection
-- (research 11.4) and the fuzz suite's "state unchanged after a rejection" assertion are the other
-- two dependants. Separators are characters that cannot appear in a number.
local function hash(state: Types.State): string
	local parts: { string } = { tostring(state.head) }
	for index = 1, #state.seats do
		local seat = state.seats[index]
		local hand = table.clone(seat.hand)
		table.sort(hand)
		local live = if seat.live then "1" else "0"
		table.insert(parts, `{live}/{table.concat(hand, ",")}/{table.concat(seat.inbox, ",")}`)
	end
	return table.concat(parts, "|")
end

-- Returns (ok, firstViolationName) in the locked order declared by Types.Violation.
local function check(state: Types.State): (boolean, Types.Violation?)
	local seats = state.seats
	local liveCount = state.liveCount

	-- 1. hand-size. No `locked` flag exists: "the pile locks at 5" is just this range (research 5).
	for _, seat in seats do
		if seat.live and #seat.hand ~= HAND_SIZE and #seat.hand ~= MAX_HAND then
			return false, "hand-size"
		end
	end

	-- 2. ring-links. next/prev are indices, so a dead or absent target is a corrupt ring.
	local liveSeen = 0
	for _, seat in seats do
		if seat.live then
			liveSeen += 1
			local after, before = seats[seat.next], seats[seat.prev]
			if after == nil or not after.live or before == nil or not before.live then
				return false, "ring-links"
			end
		end
	end
	if liveSeen ~= liveCount then
		-- `liveCount` gates checks 3, 4 and 9, so a desync here would silently disable three
		-- invariants. The count of live seats is part of the ring's structure, not a free field.
		return false, "ring-links"
	end
	if liveCount >= 1 then
		local entry = seats[state.head]
		if entry == nil or not entry.live then
			return false, "ring-links"
		end
	end

	-- liveCount == 0 is the ring-emptied case (research 7.3). Circulation is 0 there by definition,
	-- so checks 3, 4 and 9 are skipped and the partition identity (6) is the only live proof that
	-- the terminal cards were ACCOUNTED FOR rather than destroyed -- which is Rule 8 itself.
	local circulating = circulation(state)

	-- 3. liveness. Subsumed by check 1 in this position; see the header.
	if circulating >= 1 and liveCount >= 1 then
		local playable = false
		for _, seat in seats do
			if seat.live and (#seat.hand == MAX_HAND or (#seat.hand == HAND_SIZE and #seat.inbox >= 1)) then
				playable = true
				break
			end
		end
		if not playable then
			return false, "liveness"
		end
	end

	-- 4. circulation. Two independently derived sides; this is half the point of the module.
	if liveCount >= 1 and circulating ~= expectedCirculation(state) then
		return false, "circulation"
	end

	-- 5. partition-count. Catches loss and duplication-by-addition, but not a swap: that is 6.
	-- Dead seats are scanned too: their containers must be empty, and if they are not, the cards
	-- they hold are still accounted for rather than vanished.
	local held = 0
	for _, seat in seats do
		held += #seat.hand + #seat.inbox
	end
	if held + #state.retired + #state.terminal ~= state.totalCards then
		return false, "partition-count"
	end

	-- 6. partition-identity. The scratch tally costs totalCards entries and is the only check that
	-- sees card X replaced by a second copy of card Y (research 4.2).
	local tally: { number } = table.create(state.totalCards, 0)
	local stray = false
	local function visit(ids: { Types.CardId })
		for _, id in ids do
			if id >= 1 and id <= state.totalCards and id % 1 == 0 then
				tally[id] += 1
			else
				stray = true
			end
		end
	end
	for _, seat in seats do
		visit(seat.hand)
		visit(seat.inbox)
	end
	visit(state.retired)
	visit(state.terminal)
	if stray then
		return false, "partition-identity"
	end
	for id = 1, state.totalCards do
		if tally[id] ~= 1 then
			return false, "partition-identity"
		end
	end

	-- 7. counters-rankInPlay. Recomputed by walking the live containers, never by re-reading the
	-- counters that are under test.
	local ranks = state.config.ranks
	local rankInPlay: { number } = table.create(ranks, 0)
	local jokersInPlay = 0
	for _, seat in seats do
		if not seat.live then
			continue
		end
		for _, ids in { seat.hand, seat.inbox } do
			for _, id in ids do
				local rank = state.rankOf[id]
				if rank == JOKER_RANK then
					jokersInPlay += 1
				elseif rank >= 1 and rank <= ranks and rank % 1 == 0 then
					rankInPlay[rank] += 1
				else
					return false, "counters-rankInPlay" -- rankOf itself is corrupt
				end
			end
		end
	end
	if jokersInPlay ~= state.counters.jokersInPlay then
		return false, "counters-rankInPlay"
	end
	local storedRanks = state.counters.rankInPlay
	for rank = 1, math.max(ranks, #storedRanks) do
		if (rankInPlay[rank] or 0) ~= (storedRanks[rank] or 0) then
			return false, "counters-rankInPlay"
		end
	end

	-- 8. counters-histogram, recomputed from the scanned rankInPlay so the two sides can disagree.
	local cnt: { number } = table.create(BUCKETS, 0)
	for rank = 1, ranks do
		local bucket = rankInPlay[rank] + 1
		cnt[bucket] = (cnt[bucket] or 0) + 1
	end
	local storedCnt = state.counters.cnt
	for bucket = 1, math.max(BUCKETS, #cnt, #storedCnt) do
		if (cnt[bucket] or 0) ~= (storedCnt[bucket] or 0) then
			return false, "counters-histogram"
		end
	end

	-- 9. unsatisfiable. Research 3.1 proves this is unreachable by legal play while Rule 8 holds, so
	-- it is a Rule 8 tripwire and not a condition. It must still detect a dead multiset wherever one
	-- arises, which is why the spec reaches it through a conservation-clean fixture.
	if liveCount >= 1 and not satisfiable(state) then
		return false, "unsatisfiable"
	end

	return true, nil
end

return {
	circulation = circulation,
	expectedCirculation = expectedCirculation,
	satisfiable = satisfiable,
	hash = hash,
	check = check,
}
