--!strict
-- ONE SPECIFIC, VERIFIED, COMPLETION-FREE CYCLE, plus the intent generator that drives it.
-- Two seats, ranks = 3, no jokers, circulation = 4 * (3 - 2) + 0 = 4. Under `nextIntent` the
-- actions alternate Draw, Pass, Draw, Pass; the cycle is 16 ACTIONS long (8 draw observations) and
-- the observation-point hash first recurs at action 17. No seat ever reaches four of a kind: seat 1
-- rests on ranks 1,1,2,2 and seat 2 on 3,3,1,1, and every card that circulates is rank 2 or 3.
-- Those two numbers are stated here so an edit that breaks the cycle fails against an expectation
-- rather than silently becoming a non-cycle.
--
-- Harness module, not a spec, so `tests/run.luau` does not discover it -- but stylua, selene and
-- the typecheck all cover it.
local Invariants = require("../../src/server/engine/Invariants")
local Types = require("../../src/server/engine/Types")
local Valve = require("../../src/server/engine/Valve")

-- The driver's whole mutable record. EXPORTED: plans 02-07, 02-09 and 02-11 all construct one.
export type Driver = { state: Types.State, cursor: Types.SeatId, lastDrawn: Types.CardId? }

-- Card ids are deck positions, so this layout is a permutation like any dealt round would produce:
-- rank 1 = {1,2,7,8}, rank 2 = {3,4,9,10}, rank 3 = {5,6,11,12} -- four copies of each.
local RANK_OF: { Types.Rank } = { 1, 1, 2, 2, 3, 3, 1, 1, 2, 2, 3, 3 }
local RANKS = 3

local function build(opts: { antiLivelockValve: boolean, valveSeed: number? }): Types.State
	local seats: { Types.Seat } = {
		{ id = 1, playerId = 101, live = true, hand = { 1, 2, 3, 4 }, inbox = { 9, 10 }, next = 2, prev = 2 },
		{ id = 2, playerId = 102, live = true, hand = { 5, 6, 7, 8 }, inbox = { 11, 12 }, next = 1, prev = 1 },
	}
	-- Counters are SCANNED off the containers, never asserted from the layout above.
	local rankInPlay: { number } = table.create(RANKS, 0)
	for _, seat in seats do
		for _, ids in { seat.hand, seat.inbox } do
			for _, id in ids do
				rankInPlay[RANK_OF[id]] += 1
			end
		end
	end
	local cnt: { number } = table.create(5, 0)
	for rank = 1, RANKS do
		cnt[rankInPlay[rank] + 1] += 1
	end
	local state: Types.State = {
		config = { ranks = RANKS, jokers = 0, jokerMode = "Wild", antiLivelockValve = opts.antiLivelockValve },
		seatCount = 2,
		totalCards = 12,
		rankOf = table.clone(RANK_OF),
		seats = seats,
		liveCount = 2,
		head = 1,
		retired = {},
		terminal = {},
		counters = { rankInPlay = rankInPlay, jokersInPlay = 0, cnt = cnt, completions = 0, churnRemovals = 0 },
		valve = Valve.new(opts.valveSeed or 1),
	}
	-- A fixture that is not a legal state would make every consumer's conclusion worthless.
	local ok, why = Invariants.check(state)
	if not ok then
		error(`Livelock.build produced an illegal state: {tostring(why)}`, 0)
	end
	return state
end

local function newDriver(state: Types.State): Driver
	return { state = state, cursor = 1, lastDrawn = nil }
end

-- The policy is "pass the card you just drew". It is NOT a model of a player: it is the simplest
-- provably non-progressing policy, chosen because a cycle has to be a fact rather than a
-- probability. `lastDrawn` is set by the CONSUMER from the Drew event after a successful draw, so
-- the driver never reads the state's private containers and works identically whether the consumer
-- applies intents through `Engine.apply` or through `applyWithoutEngine`.
local function nextIntent(fx: Driver): Types.Intent
	local seat = fx.state.seats[fx.cursor]
	if #seat.hand == Types.HAND_SIZE then
		return { kind = "Draw", seat = fx.cursor }
	end
	local cardId = fx.lastDrawn
	if cardId == nil then
		error("Livelock.nextIntent: the consumer must set fx.lastDrawn from the Drew event", 0)
	end
	local intent: Types.Intent = { kind = "Pass", seat = fx.cursor, cardId = cardId }
	fx.cursor = seat.next
	return intent
end

-- Performs a Draw or a Pass directly on the containers and returns the drawn card id for a Draw.
-- It exists ONLY because this plan runs in wave 3, where `Engine` does not yet exist, so
-- `valve.spec` has no other way to move a card. It performs no legality check, no completion
-- detection and no counter maintenance.
--
-- Consumers in later waves (plans 02-07, 02-09 and 02-11) must drive this fixture through
-- `Engine.apply` and must NOT use this function: a fixture only ever driven by its own private
-- mutator proves nothing about the shipped engine.
local function applyWithoutEngine(state: Types.State, intent: Types.Intent): Types.CardId?
	if intent.kind == "Draw" then
		local seat = state.seats[intent.seat]
		local id = table.remove(seat.inbox, 1)
		if id == nil then
			error(`Livelock.applyWithoutEngine: seat {intent.seat} drew from an empty inbox`, 0)
		end
		table.insert(seat.hand, id)
		return id
	elseif intent.kind == "Pass" then
		local seat = state.seats[intent.seat]
		local at = table.find(seat.hand, intent.cardId)
		if at == nil then
			error(`Livelock.applyWithoutEngine: seat {intent.seat} does not hold card {intent.cardId}`, 0)
		end
		table.remove(seat.hand, at)
		table.insert(state.seats[seat.next].inbox, intent.cardId)
		return nil
	end
	error(`Livelock.applyWithoutEngine: unsupported intent kind {intent.kind}`, 0)
end

return {
	build = build,
	newDriver = newDriver,
	nextIntent = nextIntent,
	applyWithoutEngine = applyWithoutEngine,
}
