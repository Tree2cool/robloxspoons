--!strict
-- Completion detection for a single hand: grouping, which ranks could complete, and exactly which
-- four cards leave. PURE ZONE: no Roblox API, no clock, no yields. A pure function of a hand, a rank
-- map and a joker mode -- it knows nothing of seats, inboxes, the ring or events.
--
-- 1. FOUR OF A KIND IS CHECKED ONLY ON DRAW (CLAUDE.md, research 5). Passing can only leave a
--    SUBSET of a hand that already had no set, so a pass can never create one. That is a
--    correctness argument, not an optimisation: it is why `detectCompletion` needs no history and
--    why it never legitimately sees a 4-card hand. A call at any size other than MAX_HAND means the
--    caller broke CARD-01's hand-size invariant, so it errors rather than returning nil -- a silent
--    nil would surface four layers downstream as card loss.
--
-- 2. THE JOKER MODE ARRIVES AS A VALUE, in `EngineConfig.jokerMode` (02-CONTEXT.md, locked). There
--    is no module-level mode constant here and no build flag: Wild and Blocker are two branches of
--    ONE function, so both are runnable in the same process and the Gate G1 sweep can clear the
--    chosen pool in both positions. Research 3.5 measured why that matters -- at `k = 0` the switch
--    is a cliff from 0% to 97.4% stalled rounds at N=10, so a branch only ever exercised in one
--    shipped configuration is not a fallback, it is an untested rewrite. CARD-12 ships from day one.
--
-- 3. NATURALS-FIRST IS SOLVABILITY-OPTIMAL, not merely spec-locked (CARD-10, research 3.3). Of the
--    three completing shapes, 4 naturals strands 0 cards of the rank and spends 0 jokers, 3+1j
--    strands 1 and spends 1, and 2+2j strands 2 and spends 2. Taking the most naturals available is
--    therefore best on BOTH axes at once; there is no trade-off to tune.
--
-- 4. TOTAL CARDS STRANDED PER ROUND IS BOUNDED BY `jokers <= 2` (research 3.3). Every joker
--    completion consumes at least one joker, so at most MAX_JOKERS of them can ever occur in a
--    round and joker-induced dilution of the circulating pool is bounded by two cards.
--
-- 5. ORDERING IS PART OF THE CONTRACT. Within each group the lowest card IDs are taken, ascending,
--    so the retired set is a deterministic function of the hand alone. A failing simulator trial
--    must replay exactly from its seed; an arbitrary pick would let a replay diverge.
local Types = require("./Types")

local JOKER_RANK = Types.JOKER_RANK
local MAX_HAND = Types.MAX_HAND
-- Four of a kind is HAND_SIZE cards, and that is not a coincidence worth a second constant: a
-- resting hand is exactly one set in size, which is the whole content of "the pile locks at 5".
local SET_SIZE = Types.HAND_SIZE

export type Completion = {
	rank: Types.Rank, -- the NATURAL rank completed; never JOKER_RANK
	retired: { Types.CardId }, -- exactly 4 IDs: naturals first, then jokers, each group ascending
	fifth: Types.CardId, -- the card that stays in the hand and travels on with the seat's removal
	naturalsUsed: number, -- 2, 3 or 4
	jokersUsed: number, -- 0, 1 or 2; always SET_SIZE - naturalsUsed
}

-- Counts per NATURAL rank plus the joker count, for a hand of any size. `JOKER_RANK` is never a key
-- of the first return: a bot that saw "rank 0" in the count table would treat jokers as a
-- collectable rank and chase a rank that cannot be completed (research Pitfall 2).
local function groupsOf(rankOf: { Types.Rank }, hand: { Types.CardId }): ({ [Types.Rank]: number }, number)
	local naturalCounts: { [Types.Rank]: number } = {}
	local jokerCount = 0
	for _, id in hand do
		local rank = rankOf[id]
		if rank == nil then
			-- A card with no rank is a corrupt `rankOf` or a card from another round. Loud, because
			-- counting it as anything would make the completion silently wrong.
			error(`Hand.groupsOf: card {id} has no rank`)
		end
		if rank == JOKER_RANK then
			jokerCount += 1
		else
			naturalCounts[rank] = (naturalCounts[rank] or 0) + 1
		end
	end
	return naturalCounts, jokerCount
end

-- Shared by `qualifyingRanks` and `detectCompletion` so the two can never disagree about what
-- qualifies. Returned ascending, so the result is deterministic and a spec can deepEqual it.
local function ranksFrom(
	naturalCounts: { [Types.Rank]: number },
	jokerCount: number,
	mode: Types.JokerMode
): { Types.Rank }
	local out: { Types.Rank } = {}
	for rank, a in naturalCounts do
		if mode == "Blocker" then
			-- CARD-12: jokers contribute nothing, so only four naturals complete. Same function,
			-- different branch -- never a second module.
			if a == SET_SIZE then
				table.insert(out, rank)
			end
		else
			-- Wild. The `a >= 1` clause anchors the set in a natural, because the rank of an
			-- all-joker set is undefined. Research 3.3 proves an all-joker set is unreachable at
			-- `jokers <= 2` anyway -- a 5-card hand cannot hold three jokers -- so this clause is
			-- belt-and-braces today. It reopens the moment a pool sets `jokers >= 3`, which is also
			-- when the uniqueness tripwire below becomes reachable.
			if a >= 1 and a + jokerCount >= SET_SIZE then
				table.insert(out, rank)
			end
		end
	end
	table.sort(out)
	return out
end

-- Every natural rank this hand could complete under `mode`. Research 3.3: the length is 0 or 1 for
-- every reachable hand at `jokers <= 2`.
local function qualifyingRanks(rankOf: { Types.Rank }, hand: { Types.CardId }, mode: Types.JokerMode): { Types.Rank }
	local naturalCounts, jokerCount = groupsOf(rankOf, hand)
	return ranksFrom(naturalCounts, jokerCount, mode)
end

-- nil when the hand does not complete. Errors on a wrong-size hand and on an ambiguous completion.
local function detectCompletion(rankOf: { Types.Rank }, hand: { Types.CardId }, mode: Types.JokerMode): Completion?
	if #hand ~= MAX_HAND then
		error(`Hand.detectCompletion: hand must hold 5, got {#hand}`)
	end

	local naturalCounts, jokerCount = groupsOf(rankOf, hand)
	local qual = ranksFrom(naturalCounts, jokerCount, mode)
	if #qual == 0 then
		return nil
	end
	if #qual >= 2 then
		-- A TRIPWIRE, NOT A TIEBREAK. Research 3.3 proves no 5-card hand satisfies two ranks at
		-- `jokers <= 2`: 4+4 needs eight cards, 3+1j twice needs six, and 2+2j plus anything leaves
		-- the other rank at three or fewer. Picking an arbitrary rank here would silently paper over
		-- a `jokers >= 3` pool or a corrupt `rankOf`; the spec proves this branch can fire.
		local names: { string } = {}
		for _, rank in qual do
			table.insert(names, tostring(rank))
		end
		error(`Hand.detectCompletion: completing rank is not unique ({table.concat(names, ", ")})`)
	end

	local rank = qual[1]
	-- Research 3.3's choice table: take the most naturals available, which minimises both the cards
	-- of `rank` stranded and the jokers consumed.
	local naturalsUsed = math.min(naturalCounts[rank], SET_SIZE)
	local jokersUsed = SET_SIZE - naturalsUsed

	local naturalIds: { Types.CardId } = {}
	local jokerIds: { Types.CardId } = {}
	for _, id in hand do
		local r = rankOf[id]
		if r == rank then
			table.insert(naturalIds, id)
		elseif r == JOKER_RANK then
			table.insert(jokerIds, id)
		end
	end
	table.sort(naturalIds)
	table.sort(jokerIds)

	local retired: { Types.CardId } = {}
	local isRetired: { [Types.CardId]: true } = {}
	for i = 1, naturalsUsed do
		table.insert(retired, naturalIds[i])
		isRetired[naturalIds[i]] = true
	end
	for i = 1, jokersUsed do
		table.insert(retired, jokerIds[i])
		isRetired[jokerIds[i]] = true
	end

	local fifth: Types.CardId? = nil
	for _, id in hand do
		if not isRetired[id] then
			fifth = id
			break
		end
	end

	-- Cheap, and it catches an off-by-one in the ID selection at the one place it is still a local
	-- bug rather than a card-loss bug several layers downstream.
	if #retired ~= SET_SIZE then
		error(`Hand.detectCompletion: selected {#retired} cards, expected {SET_SIZE}`)
	end
	if fifth == nil then
		error("Hand.detectCompletion: no fifth card left after retirement")
	end

	return {
		rank = rank,
		retired = retired,
		fifth = fifth,
		naturalsUsed = naturalsUsed,
		jokersUsed = jokersUsed,
	}
end

return {
	groupsOf = groupsOf,
	qualifyingRanks = qualifyingRanks,
	detectCompletion = detectCompletion,
}
