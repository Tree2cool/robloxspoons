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
end
