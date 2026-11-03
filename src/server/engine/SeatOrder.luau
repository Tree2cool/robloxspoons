--!strict
-- Seat order and dealer for the next round (CARD-05, CARD-06). PURE ZONE: no Roblox API, no clock,
-- no state, and no randomness at all after round 1.
--
-- THE DEALER IS THE HEAD OF THE SEAT ORDER, ALWAYS -- there is no separate dealer rule.
-- CARD-05 ("the previous round's first finder, falling through to the highest-placed finisher
-- actually seated") and CARD-06 ("finishers in find order, then the empty-handed seeker, then
-- everyone else") collapse into a single ranking, because the hider does not sit at the card table
-- and therefore the highest-placed SEATED finisher IS the head of the seat order (research 8.1).
-- `dealerOf` exists so that no caller writes `order[1]` inline and nobody can later add a second
-- dealer rule: two rules implemented separately will eventually disagree.
--
-- THE LOCKED TOTAL ORDER. The buckets are concatenated in this sequence; inside a bucket the stated
-- key decides; the final tiebreak everywhere is `playerId` ascending (`playerId` is the Roblox
-- UserId, so it is a stable total order and never ties):
--   1. finishers                        -- position in previousFindOrder
--   2. non-finishers seated last round  -- their index in previousSeatOrder, ascending
--   3. the previous hider               -- single entry
--   4. joiners (in no previous list)    -- index in roster, i.e. join order
--
-- Zero finishers is NOT a special case: bucket 1 is simply empty and the head falls through to
-- bucket 2, which is reachable in every round that ends at the cap -- exactly the rounds the pacing
-- simulator hunts. Two or more empty-handed seekers is NOT a special case either: bucket 2 is a LIST
-- with a defined key, never "the" non-finisher (research Pitfall 5). Round 1 is this same function
-- with every previous list empty, so everyone lands in bucket 4 and the result is a seeded shuffle.
--
-- Deliberate duplication: `PlayerId` is declared here instead of imported from the shared engine
-- types, so this module has no imports at all. That is what lets it be written in the same wave as
-- the module that defines those types; src/server/core/Admission.luau carries the same kind of
-- duplication, documented the same way, for the same class of reason. Two lines are cheaper than a
-- cross-plan dependency.
export type PlayerId = number

export type SeatOrderInput = {
	round: number, -- 1-based; round 1 takes the seeded-shuffle path
	roster: { PlayerId }, -- players present NOW, in join order: the source of truth for "still here"
	hiderId: PlayerId?, -- this round's hider, excluded from the result: the hider does not play cards
	previousFindOrder: { PlayerId }, -- last round's completions in find order; MAY name departed players
	previousSeatOrder: { PlayerId }, -- last round's seat order; supplies the bucket-2 key
	previousHider: PlayerId?, -- last round's hider
	rng: any?, -- an Rng; REQUIRED when round == 1, never touched otherwise
}

local BUCKET_FINISHER = 1
local BUCKET_SEATED_NON_FINISHER = 2
local BUCKET_PREVIOUS_HIDER = 3
local BUCKET_JOINER = 4

type Ranked = { id: PlayerId, bucket: number, key: number }

-- Inputs arrive from the match lifecycle, which builds them from live player records: they are
-- validated, not trusted. A malformed entry is IGNORED rather than fatal, because one bad roster
-- entry must never take down a round (T-2-07).
local function isPlayerId(v: any): boolean
	if type(v) ~= "number" then
		return false
	end
	local n = v :: number
	-- n == n rejects NaN; the infinity comparisons reject both infinities; n % 1 == 0 rejects fractions.
	return n == n and n ~= math.huge and n ~= -math.huge and n % 1 == 0
end

local function listOf(v: any): { any }
	if type(v) ~= "table" then
		return {} -- a missing or malformed list behaves as an empty one
	end
	return v :: { any }
end

-- First occurrence wins, so a duplicated entry cannot hand one player two slots. The scan is a
-- numeric loop on purpose: generalised iteration would also yield any non-array keys, whose values
-- would then be compared against numeric keys inside the sort.
local function firstIndexes(list: { any }): { [PlayerId]: number }
	local out: { [PlayerId]: number } = {}
	for i = 1, #list do
		local v = list[i]
		if isPlayerId(v) and out[v :: PlayerId] == nil then
			out[v :: PlayerId] = i
		end
	end
	return out
end

-- The live roster is the source of truth for "still in the server". Every other list is filtered
-- against it BEFORE bucketing, never after: an entry in previousFindOrder naming a player who has
-- left must not occupy a bucket slot, or `order[1]` is a player who is not here and the dealer does
-- not exist (research 8.2 row 5).
local function eligibleSeekers(input: SeatOrderInput): { PlayerId }
	local hider: any = input.hiderId
	local hasHider = isPlayerId(hider)
	local roster = listOf(input.roster)
	local seen: { [PlayerId]: boolean } = {}
	local out: { PlayerId } = {}
	for i = 1, #roster do
		local v = roster[i]
		if isPlayerId(v) then
			local id = v :: PlayerId
			-- The hider does not play cards (02-CONTEXT amendment A3), and the card table has 9 seat
			-- anchors against a 10-player cap, so the hider is removed from every bucket at once.
			if (not hasHider or id ~= hider) and not seen[id] then
				seen[id] = true
				table.insert(out, id)
			end
		end
	end
	return out
end

-- Fisher-Yates driven by the INJECTED Rng. The global random generator is unseedable shared state,
-- so a round-1 order drawn from it could never be replayed, which would break every seeded trial of
-- the pacing simulator (T-2-08).
local function shuffled(ids: { PlayerId }, rng: any): { PlayerId }
	local out = table.clone(ids)
	for i = #out, 2, -1 do
		local j = rng:nextInt(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local function nextSeatOrder(input: SeatOrderInput): { PlayerId }
	local eligible = eligibleSeekers(input)
	local round: any = input.round
	-- A round number that is not a usable integer falls to the deterministic path: that path cannot
	-- error, so a malformed round is ranked rather than fatal.
	local isFirstRound = isPlayerId(round) and (round :: number) <= 1

	local order: { PlayerId }
	if isFirstRound then
		local rng: any = input.rng
		if rng == nil then
			-- Loud on purpose. A silent fallback to the global generator would make round 1
			-- unreproducible and break every seeded simulator trial.
			error("SeatOrder: round 1 requires an rng")
		end
		order = shuffled(eligible, rng)
	else
		-- No randomness on this path: `rng` is never read, so a caller that omits it for round 2 and
		-- later is correct rather than lucky.
		local findIndex = firstIndexes(listOf(input.previousFindOrder))
		local seatIndex = firstIndexes(listOf(input.previousSeatOrder))
		local previousHider: any = input.previousHider
		local hadPreviousHider = isPlayerId(previousHider)

		local ranked: { Ranked } = {}
		for rosterIndex, id in eligible do
			local bucket: number, key: number
			if findIndex[id] ~= nil then
				bucket, key = BUCKET_FINISHER, findIndex[id]
			elseif seatIndex[id] ~= nil then
				bucket, key = BUCKET_SEATED_NON_FINISHER, seatIndex[id]
			elseif hadPreviousHider and id == previousHider then
				bucket, key = BUCKET_PREVIOUS_HIDER, 0
			else
				bucket, key = BUCKET_JOINER, rosterIndex
			end
			table.insert(ranked, { id = id, bucket = bucket, key = key })
		end

		table.sort(ranked, function(a: Ranked, b: Ranked): boolean
			if a.bucket ~= b.bucket then
				return a.bucket < b.bucket
			end
			if a.key ~= b.key then
				return a.key < b.key
			end
			-- UserIds are unique, so this final tiebreak makes the comparator a total order and the
			-- sort deterministic. Within one bucket the keys are distinct list indexes, so it is
			-- belt and braces rather than a reachable branch.
			return a.id < b.id
		end)

		order = {}
		for _, r in ranked do
			table.insert(order, r.id)
		end
	end

	-- The only other error case. An empty order drawn from a non-empty roster is a bucketing bug,
	-- and a nil dealer is a crash one layer up (research 8.2 row 4), so it fails here, where the
	-- cause is still visible.
	if #order == 0 and #eligible > 0 then
		error("SeatOrder: produced an empty order from a non-empty roster")
	end
	return order
end

-- `order[1]`, or nil when there are no eligible seekers at all. The single reader of the dealer.
local function dealerOf(order: { PlayerId }): PlayerId?
	return order[1]
end

return {
	nextSeatOrder = nextSeatOrder,
	dealerOf = dealerOf,
}
