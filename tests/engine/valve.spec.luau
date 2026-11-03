--!strict
-- The valve is PROVEN to fire by a deterministic completion-free cycle, never by a statistic, and
-- the same fixture is shown never to escape with the valve disabled. That pairing is what makes
-- amendment A7's mechanism falsifiable rather than decorative.
--
-- THIS SPEC IS NOT THE WHOLE PROOF. It runs in wave 3, where `Engine.apply` does not exist yet, so
-- it drives the fixture with `Livelock.applyWithoutEngine` plus `Valve.afterAction` by hand. The
-- end-to-end proof through the real `Engine.apply` is plan 02-07's case 11.
local Invariants = require("../../src/server/engine/Invariants")
local Livelock = require("../harness/Livelock")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")
local Valve = require("../../src/server/engine/Valve")

-- The arm threshold on this fixture: VALVE_ARM_ACTIONS_PER_SEAT * liveCount = 48 * 2.
local ARM_AT = Types.VALVE_ARM_ACTIONS_PER_SEAT * 2
local CYCLE = 16 -- actions; 8 of them are draw observations
-- 96 + 16 + 1, and 112 is the wrong answer. The driver alternates Draw, Pass, Draw, Pass, so odd
-- actions are Draws. `armed` flips during action 96, which is a PASS, so `afterAction` returns on
-- `drewAtSeat == nil` and nothing is hashed there. The first armed observation is action 97, where
-- the window is empty and the call can only record. The cycle is 16 actions long, so the first
-- RECURRENCE is action 113. Measured: 113 for every one of the 200 valve seeds used by case 3.
local FIRST_FIRE = ARM_AT + CYCLE + 1

type Run = {
	state: Types.State,
	fx: Livelock.Driver,
	hashes: { string },
	forced: { Types.CardId },
	index: number,
	firstFire: number?,
	armedAt: number?,
	forcedNotHeld: number,
	forcedJokers: number,
	fourOfAKind: number,
	checkEach: boolean,
}

-- Takes the fixture's own options table rather than two positional booleans, so that the flag the
-- MUTATION case turns off is spelled out in the case that depends on it.
local function newRun(opts: { antiLivelockValve: boolean, valveSeed: number? }): Run
	local state = Livelock.build(opts)
	return {
		state = state,
		fx = Livelock.newDriver(state),
		hashes = {},
		forced = {},
		index = 0,
		firstFire = nil,
		armedAt = nil,
		forcedNotHeld = 0,
		forcedJokers = 0,
		fourOfAKind = 0,
		checkEach = false,
	}
end

-- One apply: the driver's intent, then the single valve observation that `Engine.apply` would make,
-- then -- inside the SAME apply -- the forced pass if the valve returned a card.
local function stepOnce(run: Run)
	local state = run.state
	local intent = Livelock.nextIntent(run.fx)
	local drawn = Livelock.applyWithoutEngine(state, intent)
	run.index += 1
	if intent.kind == "Draw" then
		run.fx.lastDrawn = drawn
		local forced = Valve.afterAction(state, intent.seat)
		if forced ~= nil then
			-- Captured BEFORE the pass, while the card is still in the hand it was chosen from.
			if table.find(state.seats[intent.seat].hand, forced) == nil then
				run.forcedNotHeld += 1
			end
			if state.rankOf[forced] == Types.JOKER_RANK then
				run.forcedJokers += 1
			end
			table.insert(run.forced, forced)
			if run.firstFire == nil then
				run.firstFire = run.index
			end
			-- THE LINE THE VALVE-ON HALF CANNOT PASS WITHOUT. `afterAction` only RETURNS a card id;
			-- nothing in this spec applies it. Without these three lines the trajectory never
			-- changes, the hash at action 2,000 still equals the hash at action 17, and case 4's
			-- second half fails against a valve that worked perfectly. Plan 02-07 case 11 needs no
			-- such line, because the real `Engine.apply` performs the forced pass itself -- so this
			-- hand-driving must not be copied into a plan that has the engine.
			Livelock.applyWithoutEngine(state, { kind = "Pass", seat = intent.seat, cardId = forced })
			run.fx.cursor = state.seats[intent.seat].next
			run.fx.lastDrawn = nil
		end
	else
		Valve.afterAction(state, nil)
	end
	if run.armedAt == nil and state.valve.armed then
		run.armedAt = run.index
	end
	run.hashes[run.index] = Invariants.hash(state)
	if run.checkEach then
		local ok, why = Invariants.check(state)
		if not ok then
			error(`Invariants.check reported {tostring(why)} at action {run.index}`, 0)
		end
		-- Completion-freedom, SCANNED rather than assumed. `applyWithoutEngine` performs no
		-- completion detection, so `counters.completions` can never move on this path and asserting
		-- that alone would be a check that cannot fail. This one can: permute the fixture's rank
		-- layout so a seat can collect four of a kind and it reports.
		for _, seat in state.seats do
			if not seat.live then
				continue
			end
			local perRank: { number } = table.create(state.config.ranks, 0)
			for _, id in seat.hand do
				local rank = state.rankOf[id]
				if rank ~= Types.JOKER_RANK then
					perRank[rank] += 1
					if perRank[rank] >= 4 then
						run.fourOfAKind += 1
					end
				end
			end
		end
	end
end

local function drive(run: Run, actions: number)
	for _ = 1, actions do
		stepOnce(run)
	end
end

return function(t: Test.Runner)
	-- 1 ----------------------------------------------------------------------------------------
	t.test("the valve is silent in the arm window", function()
		-- The cost-gate assertion. If the valve hashed from action 1 the CI subset's wall-time
		-- budget would be gone (plan 02-09 derives that budget; quoting a number here would go
		-- stale the first time it is re-measured).
		local run = newRun({ antiLivelockValve = true, valveSeed = 1 })
		drive(run, ARM_AT - 1)
		t.equal(run.state.valve.firings, 0, "the valve fired inside the arm window")
		t.equal(run.state.valve.armed, false, `armed before {ARM_AT} actions without progress`)
		t.equal(run.state.valve.seenCount, 0, "an unarmed valve hashed the state")
		t.equal(run.state.valve.observations, ARM_AT - 1, "one observation per action")
	end)

	-- 2 ----------------------------------------------------------------------------------------
	t.test("the valve arms and then fires on the repeated state", function()
		local run = newRun({ antiLivelockValve = true, valveSeed = 1 })
		drive(run, 256)
		t.equal(run.armedAt, ARM_AT, "the arm point moved; the arm constant or the driver changed")
		t.truthy(run.state.valve.firings >= 1, "the valve never fired on a verified cycle")
		t.equal(run.firstFire, FIRST_FIRE, `the first firing must land on action {FIRST_FIRE}`)
		t.equal(run.forcedNotHeld, 0, "the valve named a card the drawing seat was not holding")
	end)

	-- 3 ----------------------------------------------------------------------------------------
	t.test("the forced card is one the greedy policy would have kept", function()
		-- Deviation -- not merely "a pass happened" -- is the entire mechanism (research 3.6). A
		-- valve that always returned the same card would be a deterministic policy with exactly
		-- zero deviation. Measured: 5 distinct ids ({1,2,3,4,9}, the whole hand) over 200 seeds.
		local distinct: { [Types.CardId]: true } = {}
		local count = 0
		for seed = 1, 200 do
			local run = newRun({ antiLivelockValve = true, valveSeed = seed })
			drive(run, FIRST_FIRE)
			t.equal(run.firstFire, FIRST_FIRE, `seed {seed} did not fire on action {FIRST_FIRE}`)
			t.equal(run.forcedJokers, 0, `seed {seed} forced a joker out of the hand`)
			local card = run.forced[1]
			if distinct[card] == nil then
				distinct[card] = true
				count += 1
			end
		end
		t.truthy(count >= 3, `only {count} distinct forced cards over 200 firings`)
	end)

	-- 4 ----------------------------------------------------------------------------------------
	t.test("MUTATION: with the valve disabled, nothing escapes", function()
		-- The proof that the valve is load-bearing rather than decorative. A valve that could not
		-- fire, or a fixture that was not really a cycle, fails exactly one half of this case.
		local off = newRun({ antiLivelockValve = false, valveSeed = 1 })
		off.checkEach = true
		drive(off, 2000)
		t.equal(off.state.valve.firings, 0, "a disabled valve fired")
		t.equal(off.state.counters.completions, 0, "the fixture is not completion-free")
		t.equal(off.fourOfAKind, 0, "a seat reached four of a kind, so the fixture is not completion-free")
		t.equal(off.state.valve.observations, 2000, "one observation per action, valve off")
		-- A genuine 16-action cycle, asserted by equality of three hashes rather than by a timeout.
		t.equal(off.hashes[17], off.hashes[17 + CYCLE], "the state at action 33 left the cycle")
		t.equal(off.hashes[17], off.hashes[17 + 2 * CYCLE], "the state at action 49 left the cycle")
		t.equal(off.hashes[2000], off.hashes[2000 - CYCLE], "still cycling at action 2,000")

		local on = newRun({ antiLivelockValve = true, valveSeed = 1 })
		on.checkEach = true
		drive(on, 2000)
		t.truthy(on.state.valve.firings >= 1, "the valve never fired on the same 2,000 actions")
		t.truthy(on.hashes[2000] ~= on.hashes[17], "the trajectory never left the cycle")
		-- Stronger than the inequality above: the valve-on run visits states the valve-off run
		-- never reaches, so it left the cycle rather than merely landing on a different phase of
		-- it. Measured: 1,887 of 2,000.
		local offSeen: { [string]: true } = {}
		for index = 1, 2000 do
			offSeen[off.hashes[index]] = true
		end
		local novel = 0
		for index = 1, 2000 do
			if offSeen[on.hashes[index]] == nil then
				novel += 1
			end
		end
		t.truthy(novel >= 1, "every valve-on state was already on the valve-off cycle")
	end)

	-- 5 ----------------------------------------------------------------------------------------
	t.test("a repeat seen on a pass does not fire", function()
		-- The firing point is immediately after a non-completing draw, because that is the only
		-- instant at which a known seat provably has a legal pass. Firing elsewhere would be a
		-- different mechanism with no measurement behind it.
		local run = newRun({ antiLivelockValve = true, valveSeed = 1 })
		drive(run, FIRST_FIRE - 1)
		t.equal(run.firstFire, nil, "a firing landed before the first recurrence")
		local intent = Livelock.nextIntent(run.fx)
		if intent.kind ~= "Draw" then
			error(`action {FIRST_FIRE} must be a draw, not a {intent.kind}`, 0)
		end
		run.fx.lastDrawn = Livelock.applyWithoutEngine(run.state, intent)

		-- The recurrence, reported as a pass: no firing, and nothing recorded either.
		t.equal(Valve.afterAction(run.state, nil), nil, "a pass observation fired the valve")
		t.equal(run.state.valve.firings, 0, "firings moved on a pass observation")
		-- The SAME state, reported as the draw it actually was, DOES fire -- so the recurrence was
		-- real and the nil above is the firing rule, not a missing cycle.
		local forced = Valve.afterAction(run.state, intent.seat)
		t.truthy(forced ~= nil, "the recurrence did not fire even on the drawing seat")
		t.equal(run.state.valve.firings, 1, "the firing was not counted")
	end)

	-- 6 ----------------------------------------------------------------------------------------
	t.test("afterProgress restarts the window but not the arm", function()
		-- Research 11.4: a completion or a removal changes the state space, so a pre-progress hash
		-- recurring afterwards is not a cycle -- which is why the window must clear. The arm is a
		-- cost gate and not a soundness gate, which is why it must not: a round that has already
		-- paid 96 actions of no progress must not be handed a fresh arm period by one completion.
		local run = newRun({ antiLivelockValve = true, valveSeed = 1 })
		drive(run, ARM_AT + 1)
		local valve = run.state.valve
		t.equal(valve.armed, true, "the fixture did not arm")
		t.equal(valve.seenCount, 1, "only action 97, the first armed draw observation, was hashed")
		t.equal(run.firstFire, nil, "fired before the first recurrence")

		Valve.afterProgress(run.state)
		t.equal(valve.seenCount, 0, "afterProgress left the window populated")
		t.equal(valve.actionsSinceProgress, 0, "afterProgress left actionsSinceProgress standing")
		t.equal(valve.armed, true, "afterProgress un-armed a round that had already proven it needs watching")

		-- Both halves of what that means: the next armed observation can only record...
		drive(run, CYCLE + 1)
		t.equal(run.firstFire, nil, "the post-progress window was not empty")
		-- ...and the firing arrives one lap later, not one arm period later.
		drive(run, 1)
		local cost = (run.firstFire or 0) - (ARM_AT + 1)
		t.equal(cost, CYCLE + 2, "one 16-action lap plus the pass/draw parity")
		t.truthy(cost < ARM_AT, `re-firing cost {cost} actions; a fresh arm period would be {ARM_AT}`)
	end)

	-- 7 ----------------------------------------------------------------------------------------
	t.test("the valve is deterministic under its seed", function()
		-- CONTEXT requires a failing simulator trial to paste straight into a unit test, and a
		-- valve firing that did not replay would break that for every round the valve touched.
		local function forcedList(seed: number): string
			local run = newRun({ antiLivelockValve = true, valveSeed = seed })
			drive(run, 600)
			return table.concat(run.forced, ",")
		end
		local first = forcedList(11)
		t.truthy(#first > 0, "no firing happened, so the comparison proves nothing")
		t.equal(forcedList(11), first, "the same seed replayed to a different list of forced cards")
		-- Both halves: a broken generator wiring (a shared or ignored seed) passes the first.
		t.truthy(forcedList(1) ~= first, "a different seed produced the identical list of forced cards")
	end)

	-- 8 ----------------------------------------------------------------------------------------
	t.test("exactly one observation per action", function()
		-- Plan 02-08's fuzz suite compares this counter against its accepted-action count, so the
		-- valve cannot be skipped inside a conditional and read green.
		local run = newRun({ antiLivelockValve = true, valveSeed = 1 })
		local calls = 0
		for _ = 1, 7 do
			Valve.afterAction(run.state, nil)
			calls += 1
		end
		for _ = 1, 3 do
			Valve.afterProgress(run.state)
			calls += 1
		end
		Valve.afterAction(run.state, nil)
		calls += 1
		t.equal(run.state.valve.observations, calls, "afterProgress and afterAction must both count")
		drive(run, 5)
		t.equal(run.state.valve.observations, calls + 5, "a driven action skipped its observation")
	end)

	-- 9 ----------------------------------------------------------------------------------------
	t.test("the seen window is bounded", function()
		-- Asserted on a PRE-FILLED window rather than driven for real, and that is not a shortcut:
		-- this fixture's armed state space is the 8 observation points of its cycle, so 4,096
		-- DISTINCT armed observations are unreachable on it at any wall-time budget. The arithmetic
		-- is what matters -- an unbounded set in a 300-second round is a memory leak nobody would
		-- notice until a 10-player server.
		local run = newRun({ antiLivelockValve = true, valveSeed = 1 })
		run.state.valve.armed = true
		drive(run, 1) -- seat 1 now holds five cards, so afterAction's precondition holds
		local valve = run.state.valve
		valve.seen = {}
		for index = 1, Types.VALVE_SEEN_CAP do
			valve.seen[`filler{index}`] = true
		end
		valve.seenCount = Types.VALVE_SEEN_CAP
		t.equal(valve.seenResets, 0, "the window reset before the cap was reached")
		t.equal(Valve.afterAction(run.state, 1), nil, "a fresh hash fired the valve")
		t.truthy(valve.seenResets >= 1, "the cap did not restart the window")
		t.truthy(valve.seenCount <= Types.VALVE_SEEN_CAP, "the window grew past the cap")
		t.equal(valve.seenCount, 0, "the restarted window is empty")
	end)

	-- 10 ---------------------------------------------------------------------------------------
	t.test("a malformed call is a loud error", function()
		-- Silently returning nil would make a wiring bug in `Engine.apply` look like a mechanism
		-- that simply never fires, which is the failure mode this whole plan exists to prevent.
		local run = newRun({ antiLivelockValve = true, valveSeed = 1 })
		t.throws(function()
			Valve.afterAction(run.state, 1) -- seat 1 is resting on four cards
		end, "holds 4 cards")
		t.throws(function()
			Valve.afterAction(run.state, 99) -- no such seat
		end, "is not live")
		run.state.seats[2].live = false
		t.throws(function()
			Valve.afterAction(run.state, 2)
		end, "is not live")
		-- The clean call alongside the mutations: a guard that rejects everything is as useless as
		-- one that rejects nothing.
		local clean = newRun({ antiLivelockValve = true, valveSeed = 1 })
		drive(clean, 1)
		t.equal(Valve.afterAction(clean.state, 1), nil, "a well-formed call was rejected")
	end)

	-- 11 ---------------------------------------------------------------------------------------
	t.test("the choice rule skips jokers and falls back to the lowest card id", function()
		-- In Wild mode a joker is the most valuable card in the hand, and dumping it is a bigger
		-- disturbance than the mechanism needs. These two fixtures override `rankOf` directly and
		-- run no `check`: the valve reads only `rankOf` and the hand, so the counters a legal state
		-- would need are not consulted on this path.
		local distinct: { [Types.CardId]: true } = {}
		local count = 0
		for seed = 1, 60 do
			local run = newRun({ antiLivelockValve = true, valveSeed = seed })
			run.state.valve.armed = true
			drive(run, 1) -- seat 1 draws card 9 and holds {1,2,3,4,9}
			local state = run.state
			state.rankOf[9] = Types.JOKER_RANK
			local valve = state.valve
			valve.seen = { [Invariants.hash(state)] = true }
			valve.seenCount = 1
			local forced = Valve.afterAction(state, 1)
			t.truthy(forced ~= nil, `seed {seed} did not fire on a seeded recurrence`)
			t.truthy(forced ~= 9, `seed {seed} forced the joker out of the hand`)
			if forced ~= nil and distinct[forced] == nil then
				distinct[forced] = true
				count += 1
			end
		end
		t.truthy(count >= 2, `only {count} distinct naturals over 60 seeds`)

		-- The fallback: a hand with no natural at all. Unreachable at j <= 2, where a five-card
		-- hand holds at least three naturals, so this is the only thing that covers the branch.
		local run = newRun({ antiLivelockValve = true, valveSeed = 1 })
		run.state.valve.armed = true
		drive(run, 1)
		local state = run.state
		for _, id in state.seats[1].hand do
			state.rankOf[id] = Types.JOKER_RANK
		end
		state.valve.seen = { [Invariants.hash(state)] = true }
		state.valve.seenCount = 1
		t.equal(Valve.afterAction(state, 1), 1, "the all-joker fallback must name the lowest card id")
	end)
end
