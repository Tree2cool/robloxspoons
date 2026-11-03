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

-- The cells the pool search runs over: k = ranks - seatCount in {1, 2} (amendment A4 makes k >= 1
-- mandatory), j in {0, 1, 2}, both joker modes, at the small, middle and maximum table sizes.
local SEAT_COUNTS = { 2, 5, 9 }
local KS = { 1, 2 }
local JS = { 0, 1, 2 }
-- The modes are passed as literals rather than iterated out of a table: Luau widens a
-- singleton-string literal table to { string }, and the widened element type then no longer
-- satisfies JokerMode at the call site.
local function eachCell(visit: (seatCount: number, k: number, j: number, mode: Types.JokerMode) -> ())
	for _, seatCount in SEAT_COUNTS do
		for _, k in KS do
			for _, j in JS do
				visit(seatCount, k, j, "Wild")
				visit(seatCount, k, j, "Blocker")
			end
		end
	end
end

return function(t: Test.Runner)
	-- Every case asserts the violation NAME, never a bare boolean: a check that rejects everything
	-- is as useless as one that rejects nothing, so each mutation is paired with a clean assertion.
	local function expectClean(state: Types.State, label: string?)
		local ok, why = Invariants.check(state)
		t.equal(why, nil, `a well-formed state reported a violation ({tostring(label)})`)
		t.equal(ok, true, `a well-formed state did not report ok ({tostring(label)})`)
	end

	local function expectViolation(state: Types.State, name: string, label: string?)
		local ok, why = Invariants.check(state)
		t.equal(why, name, `wrong violation name ({tostring(label)})`)
		t.equal(ok, false, `check reported ok alongside violation {tostring(why)}`)
	end

	-- 1 ----------------------------------------------------------------------------------------
	t.test("clean state passes every invariant", function()
		eachCell(function(seatCount, k, j, mode)
			expectClean(makeState(seatCount + k, j, mode, seatCount), `m={seatCount} k={k} j={j} {mode}`)
		end)
	end)

	-- 2 ----------------------------------------------------------------------------------------
	t.test("circulation equals 4*(ranks-seats)+jokers at the deal", function()
		-- CARD-04: the circulating supply is a constant of the pool, not an accident of play, so
		-- "the deck never runs dry" is the standing assertion circulation >= 1.
		eachCell(function(seatCount, k, j, mode)
			local state = makeState(seatCount + k, j, mode, seatCount)
			local label = `m={seatCount} k={k} j={j} {mode}`
			t.equal(Invariants.circulation(state), 4 * k + j, label)
			t.equal(Invariants.expectedCirculation(state), 4 * k + j, label)
		end)
		-- Research 4.1: a non-completing removal is the ONLY operation that moves circulation, and
		-- it always moves it by exactly +4 (Rule 8's "churn makes the table looser, never tighter").
		local churned = makeState(11, 1, "Wild", 9)
		t.equal(Invariants.expectedCirculation(churned), 9)
		churned.counters.churnRemovals = 1
		t.equal(Invariants.expectedCirculation(churned), 13)
	end)

	-- 3 ----------------------------------------------------------------------------------------
	t.test("a dropped card on pass fails the circulation check", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		table.remove(state.seats[1].inbox) -- a pass that lost the card; counters NOT touched
		expectViolation(state, "circulation")
	end)

	-- 4 ----------------------------------------------------------------------------------------
	t.test("a duplicated card on draw fails the circulation check", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		table.insert(state.seats[3].hand, state.seats[4].hand[1]) -- a draw that copied instead of moving
		expectViolation(state, "circulation")
	end)

	-- 5 ----------------------------------------------------------------------------------------
	t.test("an extra retired ID fails the partition count", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		-- This mutation leaves circulation untouched, which is exactly why partition-count has to
		-- exist as a separate check rather than being folded into the circulation identity.
		table.insert(state.retired, state.totalCards + 1)
		expectViolation(state, "partition-count")
	end)

	-- 6 ----------------------------------------------------------------------------------------
	t.test("a swapped card fails the partition identity", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		-- Card X replaced by a second copy of card Y. The bucket SIZES are unchanged, so every
		-- counter stays consistent after the repair below -- this is the exact bug counters cannot
		-- see (research 4.2), and it is why the identity scan exists at all.
		state.seats[1].hand[1] = state.seats[2].hand[1]
		recount(state)
		expectViolation(state, "partition-identity")
	end)

	-- 7 ----------------------------------------------------------------------------------------
	t.test("a 6-card hand fails the hand-size check", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		table.insert(state.seats[2].hand, state.seats[2].hand[1])
		table.insert(state.seats[2].hand, state.seats[2].hand[2])
		expectViolation(state, "hand-size")
	end)

	-- 8 ----------------------------------------------------------------------------------------
	t.test("a broken ring link fails the ring-links check", function()
		local dead = makeState(7, 1, "Wild", 5)
		expectClean(dead)
		-- Seat 5 leaves without being unlinked, so seat 4's `next` and seat 1's `prev` now point at
		-- a dead seat. This is the shape a seat removal takes when it forgets to relink.
		dead.seats[5].live = false
		dead.liveCount = 4
		expectViolation(dead, "ring-links")

		local absent = makeState(7, 1, "Wild", 5)
		expectClean(absent)
		absent.seats[1].next = 99 -- a seat index that does not exist at all
		expectViolation(absent, "ring-links")
	end)

	-- 9 ----------------------------------------------------------------------------------------
	t.test("desynced rank counters fail counters-rankInPlay", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		-- The Pitfall 4 proof: the two sides of this check are genuinely independent, so they CAN
		-- disagree. Nothing in any container moved; only the counter did.
		state.counters.rankInPlay[1] -= 1
		expectViolation(state, "counters-rankInPlay")
	end)

	-- 10 ---------------------------------------------------------------------------------------
	t.test("desynced histogram alone fails counters-histogram", function()
		local state = makeState(11, 1, "Wild", 9)
		expectClean(state)
		-- rankInPlay and jokersInPlay are left correct, so check 7 passes and check 8 is the one
		-- that has to catch this. Without this row, check 8 would never have been watched failing.
		state.counters.cnt[5] -= 1
		expectViolation(state, "counters-histogram")
	end)

	-- 11 ---------------------------------------------------------------------------------------
	t.test("a dead multiset is reported unsatisfiable", function()
		-- This case must REACH violation 9, so the state has to be clean on violations 1 through 8
		-- first. The naive mutation (delete cards from play) drops circulation and `check` returns
		-- "circulation" -- violation 4 precedes violation 9 -- so it never reaches `unsatisfiable`
		-- at all. The violation list is NOT reordered to fix that; a conservation-clean fixture is
		-- built instead, from the identity that falls straight out of expectedCirculation:
		--
		--   circulation == expectedCirculation  iff
		--   #retired + #terminal == 4 * (seatCount - liveCount - churnRemovals)
		--
		-- i.e. four cards out of play per completed (non-churn) removal, and no more.
		--
		-- A retirement of ONE card from each of four ranks is not reachable by legal play -- a real
		-- completion retires four of ONE rank -- which is precisely why research 3.1 finds
		-- structural unsatisfiability unreachable while Rule 8 holds. The fixture is allowed to
		-- build it because `check` must detect a dead multiset wherever it arises; the claim that
		-- play cannot produce one is asserted empirically by plan 02-06's destroy mutation and plan
		-- 02-08's fuzz run, not by making this predicate unreachable.
		local state = makeDeadMultiset("Wild", false)
		t.equal(
			#state.retired + #state.terminal,
			4 * (state.seatCount - state.liveCount - state.counters.churnRemovals)
		)
		t.equal(
			Invariants.circulation(state),
			Invariants.expectedCirculation(state),
			"fixture is not conservation-clean"
		)
		expectViolation(state, "unsatisfiable")
		t.equal(Invariants.satisfiable(state), false)

		local blocked = makeDeadMultiset("Blocker", false)
		expectViolation(blocked, "unsatisfiable")

		-- One joker into play raises both circulation and expectedCirculation by 1, so the fixture
		-- stays clean. The mode asymmetry is CARD-10 against CARD-12 at the predicate level.
		local wild = makeDeadMultiset("Wild", true)
		t.equal(Invariants.circulation(wild), Invariants.expectedCirculation(wild))
		t.equal(Invariants.satisfiable(wild), true, "a wild joker must revive a 3-copy rank")
		expectClean(wild)
		t.equal(Invariants.satisfiable(makeDeadMultiset("Blocker", true)), false, "a blocker joker must not")
		expectViolation(makeDeadMultiset("Blocker", true), "unsatisfiable")
	end)

	-- 12 ---------------------------------------------------------------------------------------
	t.test("satisfiability is an O(1) histogram read, not a scan", function()
		local state = makeState(11, 1, "Wild", 9)
		local sum = 0
		for _, bucket in state.counters.cnt do
			sum += bucket
		end
		t.equal(sum, state.config.ranks, "cnt must partition the ranks")
		t.deepEqual(state.counters.cnt, { 0, 0, 0, 0, 11 }) -- every rank intact at the deal

		-- All four copies of rank 1 leave play together, as a real completion retires them.
		for _ = 1, 4 do
			table.insert(state.retired, table.remove(state.seats[1].hand, 1) :: Types.CardId)
		end
		recount(state)
		t.deepEqual(state.counters.cnt, { 1, 0, 0, 0, 10 }) -- exactly one rank shifted bucket
		local shifted = 0
		for _, bucket in state.counters.cnt do
			shifted += bucket
		end
		t.equal(shifted, state.config.ranks)
		t.equal(Invariants.satisfiable(state), true, "ten intact ranks remain")
	end)

	-- 13 ---------------------------------------------------------------------------------------
	t.test("the canonical hash sees an inbox reorder and ignores a hand reorder", function()
		local a = makeState(11, 1, "Wild", 9)
		local b = makeState(11, 1, "Wild", 9)
		t.equal(Invariants.hash(a), Invariants.hash(b), "two structurally equal states must hash equal")

		a.seats[2].hand[1], a.seats[2].hand[2] = a.seats[2].hand[2], a.seats[2].hand[1]
		t.equal(Invariants.hash(a), Invariants.hash(b), "a hand is a multiset: a reorder must hash equal")

		a.seats[1].inbox[1], a.seats[1].inbox[2] = a.seats[1].inbox[2], a.seats[1].inbox[1]
		-- The inbox order determines every future draw, so a hash that could not see this would
		-- silently disable both the simulator's cycle detection (research 11.4) and the fuzz
		-- suite's "state unchanged after a rejection" assertion.
		t.truthy(Invariants.hash(a) ~= Invariants.hash(b), "an inbox reorder must change the hash")

		local c = makeState(11, 1, "Wild", 9)
		table.insert(c.seats[1].hand, table.remove(c.seats[1].inbox, 1) :: Types.CardId)
		t.truthy(Invariants.hash(c) ~= Invariants.hash(b), "a draw must change the hash")
	end)

	-- 14 ---------------------------------------------------------------------------------------
	t.test("the canonical hash ignores counters, the valve record and rankOf", function()
		-- Plan 02-13's load-bearing precondition: the valve fires when a whole-table state repeats,
		-- so anything monotonic inside the hash would make every state unique, the valve would
		-- never fire, and amendment A7's mechanism would be silently vacuous -- the exact defect
		-- class Phase 1 verification found twice.
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

	-- 15 ---------------------------------------------------------------------------------------
	t.test("the liveness tripwire is subsumed by hand-size, which locks the order", function()
		-- `liveness` (violation 3) cannot be reached once `hand-size` (violation 1) has passed:
		-- with every live hand at 4 or 5, circulation >= 1 forces some seat to hold 5 (it can pass)
		-- or to hold 4 with a non-empty inbox (it can draw). That is research 3.1 Claim 3, and this
		-- row is what makes the claim falsifiable rather than asserted.
		local state = makeState(3, 0, "Wild", 2)
		expectClean(state)
		table.remove(state.seats[1].hand) -- the dealer is left holding three cards

		-- The liveness CONDITION genuinely holds here: circulation is 3 and no live seat has a
		-- legal action...
		t.equal(Invariants.circulation(state), 3)
		local playable = 0
		for _, seat in state.seats do
			if seat.live and (#seat.hand == 5 or (#seat.hand == 4 and #seat.inbox >= 1)) then
				playable += 1
			end
		end
		t.equal(playable, 0, "the fixture must have no legal action, or it proves nothing")

		-- ...and `check` still reports hand-size, because the order is locked. If this row ever
		-- reports "liveness", somebody reordered the violation list.
		expectViolation(state, "hand-size")
	end)
end
