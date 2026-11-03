--!strict
-- The simulator's BOT POLICY: the deterministic greedy choice, and the uniform draw the AFK
-- auto-pass models. Two pure functions of a state and a seat.
--
-- WHY THIS IS IN `scripts/sim/` AND NOT IN `src/server/engine/` (research section 15). A bot policy
-- and a reaction-time model are unvalidated models of a human being. Putting them in the pure zone
-- would make them part of the engine's CONTRACT, so a later measurement that said "players do not
-- actually play like this" would be a change to shipped logic instead of a change to a simulation.
-- The engine's anti-livelock valve is the opposite case and correctly lives in the engine: it
-- consults no policy and assumes nothing about how anybody plays.
--
-- `scripts/sim/` is NOT a pure zone -- selene's Roblox std, stylua and the standard-platform
-- typecheck all cover it, and `--!strict` on line 1 is mandatory under guard rule R1 -- but there
-- is no `Rng` exception here: every random draw arrives through the injected `Rng`, and the
-- standard library's own global generator appears nowhere -- not even by name in a comment, which
-- an acceptance grep in plan 02-09 asserts. A process-global generator is not a function of a seed,
-- and a failing sweep trial has to replay from its seed alone.
local Hand = require("../../src/server/engine/Hand")
local Rng = require("../../src/server/engine/Rng")
local Types = require("../../src/server/engine/Types")

local JOKER_RANK = Types.JOKER_RANK

-- THE LOCKED GREEDY POLICY (02-CONTEXT.md, research section 3.6). Keep the rank you hold most of;
-- pass from the SMALLEST group; break ties by card id ASCENDING.
--
-- Ties by card id are deterministic AND are not the lever. Research 3.6 measured that randomising
-- the tie-break only takes the pure-greedy stall rate from 44.7% to 26.3%, because the cycle is
-- created by the "never pass from your largest group" rule and not by the order within a tie. So
-- the tie rule is free to be the reproducible one, and a later executor must not "improve" it in
-- the belief that it is the livelock lever -- it is not, and changing it would silently change what
-- Gate G1 measured.
--
-- NO HIDDEN-INFORMATION AWARENESS, AND THAT IS DELIBERATE (research Pitfall 2). After a joker
-- completion a natural rank can sit at one copy in play and can never complete again. A greedy
-- agent holding two of that rank keeps them forever -- and so would a human, who has no way to know
-- the rank is DEAD. A bot that avoided dead ranks would be modelling a player who cannot exist, so
-- the dead-rank CHASE is exposed as a METRIC by `Simulator` (`deadChaseInstants`) rather than fixed
-- here. Research measured both variants at 0% stalls at noise 0.05, so informedness is not
-- load-bearing for the verdict either way; this comment is here so nobody "improves" the bot later
-- and quietly changes what G1 measured.
--
-- The one place the bot must know about `jokerMode`:
--
-- * Wild -- a joker counts as any rank, so it is the most valuable card in the hand. Rank the
--   NATURAL groups by size ascending and pass the lowest-id card of the smallest, and never pass a
--   joker while any natural group exists. At `jokers <= 2` a five-card hand holds at least three
--   naturals, so a natural group ALWAYS exists and a joker is never passed in Wild. That is stated
--   as a tripwire below rather than as an unreachable fallback branch.
-- * Blocker -- a joker can never complete a set (CARD-12), so it is dead weight and the greedy
--   choice is to pass it FIRST, lowest id first, before any natural.
--
-- Research 3.5 is the reason `k >= 1` is mandatory (amendment A4) and it shows up right here: in
-- Blocker mode at `k = 0` the jokers ARE the entire circulating supply, every circulating card is
-- a card that can never complete anything, and the cell stalls in up to 97.4% of rounds at N=10.
-- The bot is not wrong there; the pool is.
local function greedyPass(state: Types.State, seatId: Types.SeatId): Types.CardId
	local seat = state.seats[seatId]
	if seat == nil then
		error(`Bots.greedyPass: no seat {seatId}`, 0)
	end
	local hand = seat.hand
	if #hand == 0 then
		error(`Bots.greedyPass: seat {seatId} holds no cards`, 0)
	end
	local rankOf = state.rankOf
	local naturalCounts, jokerCount = Hand.groupsOf(rankOf, hand)

	if state.config.jokerMode == "Blocker" and jokerCount > 0 then
		local lowestJoker: Types.CardId? = nil
		for _, id in hand do
			if rankOf[id] == JOKER_RANK and (lowestJoker == nil or id < lowestJoker) then
				lowestJoker = id
			end
		end
		if lowestJoker ~= nil then
			return lowestJoker
		end
	end

	-- Smallest NATURAL group, ties by ascending card id. Scanning the cards rather than the groups
	-- makes the tie rule one comparison instead of two nested ones: a card in a smaller group wins,
	-- and within the same group size the lower id wins.
	local bestId: Types.CardId? = nil
	local bestSize = math.huge
	for _, id in hand do
		local rank = rankOf[id]
		if rank == JOKER_RANK then
			continue
		end
		local size = naturalCounts[rank]
		if size < bestSize or (size == bestSize and bestId ~= nil and id < bestId) then
			bestSize = size
			bestId = id
		end
	end
	if bestId == nil then
		-- A TRIPWIRE, NOT A FALLBACK. Research 3.3: at `jokers <= 2` a five-card hand holds at
		-- least three naturals, so an all-joker hand is unreachable. Returning a joker here would
		-- silently paper over a `jokers >= 3` pool or a corrupt `rankOf`, and the sweep would then
		-- be measuring a policy nobody specified.
		error(`Bots.greedyPass: seat {seatId} holds only jokers, which is unreachable at jokers <= 2`, 0)
	end
	return bestId
end

-- THE AUTO-PASS CHOICE. Uniform over the hand, drawn off the injected `Rng` against the hand's card
-- ids SORTED ASCENDING, so the index-to-card mapping depends on the hand's CONTENTS and not on the
-- order the cards happen to sit in a container. Without the sort a failing sweep seed would not
-- replay once an unrelated change shifted container order.
--
-- 1. THIS MUST STAY `uniform-random-from-hand`, the value plan 02-11 records in
--    `src/shared/Config/CardPool.luau` as `AUTO_PASS_SELECTION`. The deviation that breaks a
--    livelock comes from the auto-pass choosing a card the player would NOT have chosen. If Phase 4
--    ships the helpful-looking "auto-pass your worst card", that IS the player's own greedy choice,
--    the deviation is exactly ZERO, and every number this simulator produces about auto-pass
--    transfers nothing to the shipped game.
-- 2. DEVIATION IS A CLIFF, NOT A GRADIENT, AND THE CLIFF IS CLOSE TO ZERO. Measured at N=10, k=2,
--    j=1 over 4,000 rounds per cell: 0.25% stalls at 0% deviation, 0.20% at 0.001%, 0.05% at 0.01%
--    and 0% from 0.03% upward. Research sampled only 0% and 2%, so it never saw where the edge
--    actually is; 2% was never the threshold.
-- 3. AUTO-PASS IS NO LONGER WHAT MAKES GATE G1 PASS -- the engine's valve is (amendment A7). A
--    livelocked greedy table is not idle: every seat is drawing and passing on schedule, so an
--    auto-pass that fires on inaction fires exactly as often as the reaction-time tail crosses the
--    deadline and no more (2.86% of actions at 1.0s, 0.21% at 1.5s, ~0 at 5s). This function is
--    still the shipped mechanic's model and its rate is reported as margin evidence, which is why
--    it keeps its own metric.
local function randomPass(state: Types.State, seatId: Types.SeatId, rng: Rng.Rng): Types.CardId
	local seat = state.seats[seatId]
	if seat == nil then
		error(`Bots.randomPass: no seat {seatId}`, 0)
	end
	local ids = table.clone(seat.hand)
	if #ids == 0 then
		error(`Bots.randomPass: seat {seatId} holds no cards`, 0)
	end
	table.sort(ids)
	return ids[rng:nextInt(1, #ids)]
end

return {
	greedyPass = greedyPass,
	randomPass = randomPass,
}
