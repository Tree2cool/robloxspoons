--!strict
-- SCORE-06: round end fires exactly once, and a callback from an earlier round can never affect a later
-- one. Every case uses the injected FakeScheduler (never real time) and asserts the REASON and the round
-- ID that ended, not just how many times onEnded ran: a stale callback that is inert for the wrong reason
-- looks identical to one the round-ID token correctly rejected.
local FakeScheduler = require("../harness/FakeScheduler")
local RoundLifecycle = require("../../src/server/core/RoundLifecycle")
local Test = require("../harness/Test")

type Ended = { id: number, reason: RoundLifecycle.Reason }

-- Wraps a scheduler so a test can see WHICH backstops actually ran. Without this, "round 2 survived" cannot
-- be told apart from "the stale callback never ran".
type Instrumented = {
	scheduler: RoundLifecycle.Scheduler,
	fired: { number }, -- registration indices of backstops that ran, in order
}

local function instrument(inner: FakeScheduler.FakeScheduler): Instrumented
	local fired: { number } = {}
	local registered = 0
	return {
		fired = fired,
		scheduler = {
			nowDeci = inner.nowDeci,
			delay = function(seconds: number, fn: () -> ()): () -> ()
				registered += 1
				local index = registered
				return inner.delay(seconds, function()
					table.insert(fired, index)
					fn()
				end)
			end,
		},
	}
end

local function setup(options: FakeScheduler.Options?)
	local sched = FakeScheduler.new(options)
	local inst = instrument(sched)
	local ended: { Ended } = {}
	local rl = RoundLifecycle.new({
		scheduler = inst.scheduler,
		onEnded = function(id: number, reason: RoundLifecycle.Reason)
			table.insert(ended, { id = id, reason = reason })
		end,
	})
	return sched, rl, ended, inst.fired
end

-- A lifecycle on a bare FakeScheduler (no instrumentation) for the same-tick cases, where the test needs to
-- register its own delay callbacks around begin() to control arrival order.
local function bare()
	local sched = FakeScheduler.new()
	local ended: { Ended } = {}
	local rl = RoundLifecycle.new({
		scheduler = sched,
		onEnded = function(id: number, reason: RoundLifecycle.Reason)
			table.insert(ended, { id = id, reason = reason })
		end,
	})
	return sched, rl, ended
end

-- A claim handler as Phase 4 will write it: ask isOpen first, only then end on the last spoon.
local function claim(rl: RoundLifecycle.Lifecycle, roundId: number, isLastSpoon: boolean): boolean
	if not rl:isOpen(roundId) then
		return false
	end
	if isLastSpoon then
		rl:endRound(roundId, "AllSpoonsClaimed")
	end
	return true
end

-- The research scenario, verbatim. `cancelIsNoop` flips between a platform cancel that works and one that
-- does nothing, so the same behaviour is proven with and without cancellation doing any of the work.
local function staleBackstopScenario(t: Test.Runner, cancelIsNoop: boolean)
	local sched, rl, ended, fired = setup({ cancelIsNoop = cancelIsNoop })

	local r1 = rl:begin(300)
	t.equal(sched.pending(), 1, "r1 registered one backstop")
	t.equal(rl:endRound(r1, "AllSpoonsClaimed"), true)
	-- This is the line that says which mode we are really in: a working cancel removes the backstop, a
	-- no-op cancel leaves it queued.
	t.equal(sched.pending(), if cancelIsNoop then 1 else 0, "pending backstops after r1 ended early")

	sched.advance(10)
	local r2 = rl:begin(300)
	t.equal(sched.pending(), if cancelIsNoop then 2 else 1, "pending backstops after r2 began")

	sched.advance(290) -- t = 300: r1's original deadline, where its stale backstop fires if it still exists
	t.equal(sched.nowDeci(), 3000)
	-- Proof of mode: the stale callback really ran with a no-op cancel and never ran with a working one.
	t.deepEqual(fired, if cancelIsNoop then { 1 } else {}, "which backstops have run at t=300")
	t.equal(sched.pending(), 1, "only r2's backstop remains")
	t.deepEqual(ended, { { id = r1, reason = "AllSpoonsClaimed" } }, "r1 ended once, by the last claim")
	t.equal(rl:activeRound(), r2)
	t.equal(rl:isOpen(r2), true, "r2 must still be open after r1's stale backstop")
	t.equal(rl:endCount(), 1)

	sched.advance(10) -- t = 310: r2's own deadline
	t.deepEqual(fired, if cancelIsNoop then { 1, 2 } else { 2 })
	t.deepEqual(ended, {
		{ id = r1, reason = "AllSpoonsClaimed" },
		{ id = r2, reason = "Timeout" },
	}, "r2 ended once, by its own timeout")
	t.equal(rl:endRound(r2, "Timeout"), false, "a further end of r2 is rejected")
	t.equal(rl:endCount(), 2)
	t.equal(#ended, 2)
end

return function(t: Test.Runner)
	t.test("begin returns strictly increasing round ids", function()
		local _, rl = setup()
		local r1 = rl:begin(300)
		rl:endRound(r1, "Aborted")
		local r2 = rl:begin(300)
		rl:endRound(r2, "Aborted")
		local r3 = rl:begin(300)
		t.truthy(r2 > r1, "r2 > r1")
		t.truthy(r3 > r2, "r3 > r2")
	end)

	t.test("begin computes an integer-decisecond absolute deadline from the injected clock", function()
		local sched, rl = setup()
		sched.advance(5)
		local r1 = rl:begin(300)
		local deadline = rl:deadlineDeci(r1)
		t.equal(deadline, 3050, "50 deci now + 3000 deci")
		t.equal(math.floor(deadline :: number), deadline, "deadline is an integer")
		t.equal(rl:deadlineDeci(r1 + 1), nil, "an unknown round has no deadline")
	end)

	t.test("begin rejects a duration that would leave a round with no usable deadline", function()
		local _, rl = setup()
		t.throws(function()
			rl:begin(0)
		end, "duration")
		t.throws(function()
			rl:begin(-5)
		end, "duration")
		t.throws(function()
			rl:begin(0 / 0)
		end, "duration")
		t.throws(function()
			rl:begin(math.huge)
		end, "duration")
		t.throws(function()
			rl:begin(0.05) -- positive, but floors to zero deciseconds: born already expired
		end, "duration")
		t.throws(function()
			rl:begin(("300" :: any) :: number)
		end, "duration")
		t.equal(rl:activeRound(), nil, "no rejected begin may leave a round behind")
	end)

	t.test("begin while the previous round is still live is an error, not a silent overwrite", function()
		local _, rl, ended = setup()
		local r1 = rl:begin(300)
		t.throws(function()
			rl:begin(300)
		end, "still active")
		t.equal(rl:activeRound(), r1, "r1 is untouched by the rejected begin")
		t.equal(#ended, 0, "the rejected begin ended nothing")
	end)

	t.test("endRound returns true once, then false, and reports the id and reason it ended with", function()
		local _, rl, ended = setup()
		local r1 = rl:begin(300)
		t.equal(rl:endRound(r1, "AllSpoonsClaimed"), true)
		t.equal(rl:endRound(r1, "AllSpoonsClaimed"), false)
		t.equal(rl:endRound(r1, "Timeout"), false, "a different reason does not get a second end either")
		t.deepEqual(ended, { { id = r1, reason = "AllSpoonsClaimed" } })
		t.equal(rl:endCount(), 1)
	end)

	t.test("endRound called 100 times fires onEnded exactly once", function()
		local _, rl, ended = setup()
		local r1 = rl:begin(300)
		local trues = 0
		for _ = 1, 100 do
			if rl:endRound(r1, "AllSpoonsClaimed") then
				trues += 1
			end
		end
		t.equal(trues, 1, "exactly one call reported it did the ending")
		t.deepEqual(ended, { { id = r1, reason = "AllSpoonsClaimed" } }, "one event, the first reason, the right round")
		t.equal(rl:endCount(), 1)
	end)

	t.test("endRound with an id that is not the active round returns false and fires nothing", function()
		local _, rl, ended = setup()
		t.equal(rl:endRound(1, "Aborted"), false, "nothing has begun yet")
		local r1 = rl:begin(300)
		t.equal(rl:endRound(r1 + 1, "Aborted"), false, "an id from the future")
		t.equal(rl:endRound(0, "Aborted"), false)
		t.equal(rl:activeRound(), r1, "the active round is unaffected")
		t.equal(rl:isOpen(r1), true)
		t.equal(#ended, 0)
		rl:endRound(r1, "Aborted")
		local r2 = rl:begin(300)
		t.equal(rl:endRound(r1, "Aborted"), false, "an old round id cannot end the current round")
		t.equal(rl:isOpen(r2), true, "r2 survived an attempt to end it under r1's id")
		t.deepEqual(ended, { { id = r1, reason = "Aborted" } })
	end)

	t.test("onEnded receives the reason it was ended with, for each reason", function()
		local reasons: { RoundLifecycle.Reason } = { "AllSpoonsClaimed", "Timeout", "Aborted" }
		for _, reason: RoundLifecycle.Reason in reasons do
			local _, rl, ended = setup()
			local r = rl:begin(300)
			rl:endRound(r, reason)
			t.deepEqual(ended, { { id = r, reason = reason } }, `reason {reason}`)
		end
	end)

	t.test("stale backstop from round 1 cannot end round 2 (cancel works)", function()
		staleBackstopScenario(t, false)
	end)

	t.test("stale backstop from round 1 cannot end round 2 (cancel is a no-op, so the token alone does it)", function()
		staleBackstopScenario(t, true)
	end)

	t.test("a stale backstop firing with no round active is inert", function()
		local sched, rl, ended, fired = setup({ cancelIsNoop = true })
		local r1 = rl:begin(300)
		rl:endRound(r1, "Aborted")
		sched.advance(300) -- r1's backstop runs now; no round is active
		t.deepEqual(fired, { 1 }, "the stale backstop did run")
		t.deepEqual(ended, { { id = r1, reason = "Aborted" } }, "and added no second end")
		t.equal(rl:activeRound(), nil)
		t.equal(rl:endCount(), 1)
	end)

	t.test("the backstop ends its own round with reason Timeout at the deadline", function()
		local sched, rl, ended, fired = setup()
		local r1 = rl:begin(30)
		sched.advance(29)
		t.equal(#ended, 0, "not before the deadline")
		sched.advance(1)
		t.deepEqual(fired, { 1 })
		t.deepEqual(ended, { { id = r1, reason = "Timeout" } })
		t.equal(rl:isOpen(r1), false)
		t.equal(rl:activeRound(), nil, "an ended round is no longer active")
	end)

	t.test("a last claim before the deadline ends the round and the later timer adds nothing", function()
		local sched, rl, ended = setup({ cancelIsNoop = true })
		local r1 = rl:begin(2) -- deadline at 20 deci
		sched.advance(1.5)
		t.equal(sched.nowDeci(), 15)
		t.equal(claim(rl, r1, true), true)
		sched.advance(1) -- t = 25: the (uncancelled) backstop fires
		t.deepEqual(ended, { { id = r1, reason = "AllSpoonsClaimed" } }, "the claim won, the timer was inert")
		t.equal(rl:endCount(), 1)
	end)

	t.test("deadline is exclusive: a claim exactly on the deadline decisecond is rejected", function()
		local sched, rl, ended = setup()
		local r1 = rl:begin(2) -- deadline at 20 deci
		t.equal(rl:deadlineDeci(r1), 20)
		sched.advance(1.9)
		t.equal(sched.nowDeci(), 19, "one decisecond before the deadline")
		t.equal(claim(rl, r1, false), true, "one decisecond earlier is accepted")
		t.equal(#ended, 0)
		sched.advance(0.1)
		-- The backstop fired at tick 20 and routed to a Timeout end. The claim is rejected at 20.
		t.equal(sched.nowDeci(), 20, "exactly on the deadline decisecond")
		t.equal(claim(rl, r1, true), false, "a claim on the deadline decisecond is outside the round")
		t.deepEqual(ended, { { id = r1, reason = "Timeout" } }, "ended by timeout, never by the rejected claim")
	end)

	t.test("isOpen at the deadline rejects and routes to a Timeout end exactly once", function()
		local sched, rl, ended = bare()
		local r1 = 0
		-- Registered before begin, so on the deadline tick this runs BEFORE r1's backstop (ties break by
		-- registration order). isOpen must therefore be what discovers the deadline, not the timer.
		sched.delay(2, function()
			t.equal(rl:isOpen(r1), false, "closed at the deadline decisecond")
			t.equal(rl:isOpen(r1), false, "still closed on a second ask")
			t.equal(rl:isOpen(r1), false, "and a third")
			t.deepEqual(ended, { { id = r1, reason = "Timeout" } }, "isOpen itself did the ending, before the timer")
		end)
		r1 = rl:begin(2)
		t.equal(sched.pending(), 2)
		sched.advance(2)
		t.deepEqual(ended, { { id = r1, reason = "Timeout" } }, "one Timeout end for r1, no more")
		t.equal(rl:endCount(), 1)
	end)

	t.test("tie, claim processed before the timer: the claim is outside the round, one Timeout end", function()
		local sched, rl, ended = bare()
		local r1 = 0
		local accepted: boolean? = nil
		sched.delay(2, function() -- registered first: arrives before the timer on the same tick
			accepted = claim(rl, r1, true)
		end)
		r1 = rl:begin(2)
		sched.advance(2)
		t.equal(sched.nowDeci(), 20)
		t.equal(accepted, false, "the last claim lands on the deadline decisecond and is rejected")
		t.deepEqual(ended, { { id = r1, reason = "Timeout" } }, "exactly one end, and it is the timeout")
		t.equal(rl:endCount(), 1)
	end)

	t.test("tie, timer processed before the claim: the claim is outside the round, one Timeout end", function()
		local sched, rl, ended = bare()
		local r1 = rl:begin(2)
		local accepted: boolean? = nil
		sched.delay(2, function() -- registered second: arrives after the timer on the same tick
			accepted = claim(rl, r1, true)
		end)
		sched.advance(2)
		t.equal(sched.nowDeci(), 20)
		t.equal(accepted, false, "the last claim arrives after the timer already ended the round")
		t.deepEqual(ended, { { id = r1, reason = "Timeout" } }, "exactly one end, and it is the timeout")
		t.equal(rl:endCount(), 1)
	end)

	t.test("primitive tie, endRound before the timer: first trigger wins, the timer is inert", function()
		local sched, rl, ended = bare()
		local r1 = 0
		sched.delay(2, function()
			rl:endRound(r1, "AllSpoonsClaimed")
		end)
		r1 = rl:begin(2)
		sched.advance(2)
		t.equal(rl:endRound(r1, "Timeout"), false, "the second trigger reports it did nothing")
		t.deepEqual(ended, { { id = r1, reason = "AllSpoonsClaimed" } }, "the first arrival decided the reason")
		t.equal(rl:endCount(), 1)
	end)

	t.test("primitive tie, timer before endRound: first trigger wins, the claim end returns false", function()
		local sched, rl, ended = bare()
		local r1 = rl:begin(2)
		local second: boolean? = nil
		sched.delay(2, function()
			second = rl:endRound(r1, "AllSpoonsClaimed")
		end)
		sched.advance(2)
		t.equal(second, false, "the claim end arrived second and reports it did nothing")
		t.deepEqual(ended, { { id = r1, reason = "Timeout" } }, "the first arrival decided the reason")
		t.equal(rl:endCount(), 1)
	end)

	t.test("state is ended BEFORE onEnded runs, so a re-entrant onEnded cannot end the round twice", function()
		local sched = FakeScheduler.new()
		local ended: { Ended } = {}
		local observedOpen: boolean? = nil
		local observedActive: number? = -1
		local reentrant: boolean? = nil
		local rl: RoundLifecycle.Lifecycle
		rl = RoundLifecycle.new({
			scheduler = sched,
			onEnded = function(id: number, reason: RoundLifecycle.Reason)
				table.insert(ended, { id = id, reason = reason })
				observedOpen = rl:isOpen(id)
				observedActive = rl:activeRound()
				reentrant = rl:endRound(id, "Aborted") -- a handler that tries to end it again
			end,
		})
		local r1 = rl:begin(300)
		t.equal(rl:endRound(r1, "AllSpoonsClaimed"), true)
		t.equal(observedOpen, false, "inside onEnded the round already reads as ended")
		t.equal(observedActive, nil)
		t.equal(reentrant, false, "a re-entrant end is rejected")
		t.deepEqual(ended, { { id = r1, reason = "AllSpoonsClaimed" } })
	end)

	t.test("onEnded may begin the next round, and that round is unaffected by the one that just ended", function()
		local sched = FakeScheduler.new({ cancelIsNoop = true })
		local ended: { Ended } = {}
		local nextId = 0
		local rl: RoundLifecycle.Lifecycle
		rl = RoundLifecycle.new({
			scheduler = sched,
			onEnded = function(id: number, reason: RoundLifecycle.Reason)
				table.insert(ended, { id = id, reason = reason })
				if nextId == 0 then
					nextId = rl:begin(300)
				end
			end,
		})
		local r1 = rl:begin(300)
		rl:endRound(r1, "AllSpoonsClaimed")
		t.truthy(nextId > r1, "the next round was begun from inside onEnded")
		t.equal(rl:activeRound(), nextId)
		sched.advance(299)
		t.equal(rl:isOpen(nextId), true, "nextId is open one second before its own deadline")
		t.equal(#ended, 1)
		-- t = 300: both backstops are due on the same tick. r1's stale one was registered first so it runs
		-- first and must be inert; nextId's own backstop then times its round out.
		sched.advance(1)
		t.deepEqual(ended, {
			{ id = r1, reason = "AllSpoonsClaimed" },
			{ id = nextId, reason = "Timeout" },
		}, "nextId ended by its OWN timeout, and r1's stale callback added nothing")
	end)
end
