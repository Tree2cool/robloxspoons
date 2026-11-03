--!strict
local Invariants = require("../../src/server/engine/Invariants")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

-- Counters derived by SCANNING the containers, which is how Engine will maintain them and how
-- `Invariants.check` recomputes them. Live seats only: `rankInPlay` means "in play".
local function recount(state: Types.State)
	local rankInPlay: { number } = {}
	for r = 1, state.config.ranks do
		rankInPlay[r] = 0
	end
	local jokersInPlay = 0
	local function countCard(id: Types.CardId)
		local rank = state.rankOf[id]
		if rank == Types.JOKER_RANK then
			jokersInPlay += 1
		else
			rankInPlay[rank] += 1
		end
	end
	for _, seat in state.seats do
		if seat.live then
			for _, id in seat.hand do
				countCard(id)
			end
			for _, id in seat.inbox do
				countCard(id)
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

-- A fixture, not a second engine: it lays cards out the way `Engine.newRound` will, but with a
-- KNOWN layout (no shuffle) so that any mutation below is pin-pointable.
local function makeState(ranks: number, jokers: number, mode: Types.JokerMode, seatCount: number): Types.State
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
	local seats: { Types.Seat } = {}
	for s = 1, seatCount do
		local hand: { Types.CardId } = {}
		for id = (s - 1) * 4 + 1, s * 4 do
			table.insert(hand, id)
		end
		table.insert(seats, {
			id = s,
			playerId = 100 + s,
			live = true,
			hand = hand,
			inbox = {},
			next = if s == seatCount then 1 else s + 1,
			prev = if s == 1 then seatCount else s - 1,
		})
	end
	for id = seatCount * 4 + 1, totalCards do
		table.insert(seats[1].inbox, id) -- the dealer's inbox IS the deck
	end
	local state: Types.State = {
		config = { ranks = ranks, jokers = jokers, jokerMode = mode, antiLivelockValve = true },
		seatCount = seatCount,
		totalCards = totalCards,
		rankOf = rankOf,
		seats = seats,
		liveCount = seatCount,
		head = 1,
		retired = {},
		terminal = {},
		counters = { rankInPlay = {}, jokersInPlay = 0, cnt = {}, completions = 0, churnRemovals = 0 },
		-- Nothing here exercises the valve (that is plan 02-13); the field exists so the fixture is
		-- a real State and check/hash are called on the shape they will actually see.
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
	recount(state)
	return state
end

-- Conservation-clean yet structurally dead: see the "dead multiset" case for why it is built this
-- way rather than by deleting cards.
local function makeDeadMultiset(mode: Types.JokerMode, withJoker: boolean): Types.State
	local state = makeState(4, if withJoker then 1 else 0, mode, 3)
	state.seats[3].hand = {}
	state.seats[3].inbox = {}
	state.seats[3].live = false
	state.liveCount = 2
	state.seats[1].next, state.seats[1].prev = 2, 2
	state.seats[2].next, state.seats[2].prev = 1, 1
	state.counters.completions = 1
	state.retired = { 1, 5, 9, 13 } -- one copy of EACH rank: every rank left at 3 copies in play
	state.seats[1].hand = { 2, 3, 4, 6 }
	state.seats[2].hand = { 7, 8, 10, 11 }
	state.seats[1].inbox = { 12, 14 }
	state.seats[2].inbox = { 15, 16 }
	if withJoker then
		table.insert(state.seats[1].inbox, 17)
	end
	recount(state)
	return state
end

return function(t: Test.Runner)
	-- Every case asserts the violation NAME, never a bare boolean: a check that rejects everything
	-- is as useless as one that rejects nothing, so each mutation is paired with a clean assertion.
	local function expectClean(state: Types.State)
		local ok, why = Invariants.check(state)
		t.equal(why, nil, "a well-formed state reported a violation")
		t.equal(ok, true, "a well-formed state did not report ok")
	end

	local function expectViolation(state: Types.State, name: string)
		local ok, why = Invariants.check(state)
		t.equal(why, name, "wrong violation name")
		t.equal(ok, false, `check reported ok alongside violation {tostring(why)}`)
	end

	t.test("circulation and expectedCirculation agree at the deal, and churn adds exactly 4", function()
		local state = makeState(11, 1, "Wild", 9) -- k = 2, j = 1 at nine seated seekers
		t.equal(Invariants.circulation(state), 9)
		t.equal(Invariants.expectedCirculation(state), 9)
		state.counters.churnRemovals = 1 -- one Disconnected removal
		t.equal(Invariants.expectedCirculation(state), 13)
	end)

	t.test("a well-formed state passes every invariant", function()
		expectClean(makeState(11, 1, "Wild", 9))
	end)

	t.test("a dropped card fails the circulation check", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		table.remove(state.seats[1].inbox)
		expectViolation(state, "circulation")
	end)

	t.test("a swapped card fails the partition identity", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		state.seats[1].hand[1] = state.seats[2].hand[1]
		recount(state)
		expectViolation(state, "partition-identity")
	end)

	t.test("an extra retired id fails the partition count", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		table.insert(state.retired, state.totalCards + 1)
		expectViolation(state, "partition-count")
	end)

	t.test("a six-card hand fails the hand-size check", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		table.insert(state.seats[2].hand, state.seats[2].hand[1])
		table.insert(state.seats[2].hand, state.seats[2].hand[2])
		expectViolation(state, "hand-size")
	end)

	t.test("desynced rank counters fail counters-rankInPlay", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		state.counters.rankInPlay[1] -= 1
		expectViolation(state, "counters-rankInPlay")
	end)

	t.test("a dead multiset is unsatisfiable, and a wild joker revives it", function()
		local state = makeDeadMultiset("Wild", false)
		t.equal(Invariants.satisfiable(state), false)
		t.equal(Invariants.satisfiable(makeDeadMultiset("Wild", true)), true)
	end)

	t.test("the canonical hash sees a pass and nothing else", function()
		local a = makeState(11, 1, "Wild", 9)
		local b = makeState(11, 1, "Wild", 9)
		t.equal(Invariants.hash(a), Invariants.hash(b))
		local moved = table.remove(a.seats[1].hand) :: Types.CardId
		table.insert(a.seats[2].inbox, moved)
		t.truthy(Invariants.hash(a) ~= Invariants.hash(b), "a pass did not change the hash")
	end)

	t.test("the canonical hash ignores counters, the valve record and rankOf", function()
		local state = makeState(11, 1, "Wild", 9)
		local before = Invariants.hash(state)
		state.counters.completions += 1
		t.equal(Invariants.hash(state), before, "counters.completions changed the hash")
		state.valve.actionsSinceProgress += 1
		t.equal(Invariants.hash(state), before, "valve.actionsSinceProgress changed the hash")
		state.valve.firings += 1
		t.equal(Invariants.hash(state), before, "valve.firings changed the hash")
		state.rankOf[1], state.rankOf[5] = state.rankOf[5], state.rankOf[1]
		t.equal(Invariants.hash(state), before, "a rankOf permutation changed the hash")
	end)
end
