--!strict
-- D-20 gate. The detector is keyed on accepted actions without progress and CANNOT be fed a valve
-- event. Evidence the keying matters: Phase 2 replayed 15 residual stalled seeds, every one ran
-- 2,431-4,429 actions without clearing, and 3 of the 15 had the valve armed with ZERO firings.
--
-- Mutations are injected broken DEPENDENCIES driven through the same scenario helper as the real
-- detector (convention tests/engine/valve.spec.luau). StallDetector.luau is never edited.
local Card = require("../../src/shared/Config/Card")
local StallDetector = require("../../src/server/core/StallDetector")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

local NAN: number = 0 / 0

local function deci(seconds: number): number
	return math.floor(seconds * 10 + 1e-9)
end

local PER_SEAT = Card.STALL_ACTIONS_PER_SEAT
local MIN_DECI = deci(Card.STALL_MIN_SECONDS)
local REPEAT_DECI = deci(Card.STALL_REPEAT_SECONDS)

type Detectorish = {
	noteApply: (any, number, number) -> (),
	noteProgress: (any, number) -> (),
	tick: (any, number) -> { any },
}

type Telemetry = { name: string, data: { [string]: number } }

local function build(sink: { Telemetry }?): StallDetector.StallDetector
	return StallDetector.new({
		actionsPerSeat = PER_SEAT,
		minDeci = MIN_DECI,
		cueDeci = deci(Card.STALL_CUE_SECONDS),
		repeatDeci = REPEAT_DECI,
		onTelemetry = function(name: string, data: { [string]: number })
			if sink ~= nil then
				table.insert(sink, { name = name, data = data })
			end
		end,
	})
end

type StuckOpts = { actions: number, liveSeats: number, deciPerAction: number, valveFirings: number }
type StuckResult = { cues: number, cueTimes: { number }, clears: number }

-- Drives a stuck table: `actions` accepted actions, no progress. `valveFirings` exists only to make
-- the scenario's name honest. The real detector has no way to receive it; a valve-keyed variant
-- receives it through `noteValve`, if it has one.
local function runStuck(d: Detectorish, opts: StuckOpts): StuckResult
	for _ = 1, opts.valveFirings do
		local feed = (d :: any).noteValve
		if feed ~= nil then
			feed(d)
		end
	end
	local result: StuckResult = { cues = 0, cueTimes = {}, clears = 0 }
	for i = 1, opts.actions do
		local now = math.floor(i * opts.deciPerAction)
		d:noteApply(opts.liveSeats, now)
		for _, command in d:tick(now) do
			if command.kind == "StallCue" then
				result.cues += 1
				table.insert(result.cueTimes, now)
			else
				result.clears += 1
			end
		end
	end
	return result
end

return function(t: Test.Runner)
	t.test("the action threshold is twice the engine's valve arming, asserted not hard-coded", function()
		t.equal(PER_SEAT, 2 * Types.VALVE_ARM_ACTIONS_PER_SEAT, "STALL_ACTIONS_PER_SEAT vs Types")
		t.equal(MIN_DECI, 450, "45 s")
	end)

	t.test("a healthy round never raises the cue, with a margin that discriminates", function()
		local d = build()
		-- A healthy 9-seat round is ~380 accepted actions table-wide. Completions (progress events,
		-- each removing a seat, 9 -> 3) are spread through it. The gaps below are an APPROXIMATION of
		-- measured pacing, not a measurement; the final gap is deliberately the longest and runs at
		-- the smallest table, where the threshold (96 * 3) is lowest -- the worst case for the margin.
		local gaps = { 40, 35, 55, 48, 62, 70, 70 }
		local seats = 9
		local now = 0
		local total = 0
		local progressEvents = 0
		local maxSince = 0
		local worstRatio = 0 -- max of actionsSinceProgress / (96 * liveSeats)
		local worstThreshold = 0
		local cues = 0
		for index, gap in gaps do
			for _ = 1, gap do
				now += 5 -- 0.5 s per action
				total += 1
				d:noteApply(seats, now)
				local since = d:actionsSinceProgress()
				if since > maxSince then
					maxSince = since
				end
				local ratio = since / (PER_SEAT * seats)
				if ratio > worstRatio then
					worstRatio = ratio
					worstThreshold = PER_SEAT * seats
				end
				for _, c in d:tick(now) do
					if c.kind == "StallCue" then
						cues += 1
					end
				end
			end
			if index < #gaps then
				d:noteProgress(now)
				progressEvents += 1
				seats -= 1
			end
		end
		t.equal(cues, 0, "a healthy round raised the cue")
		t.falsy(d:isActive(), "a healthy round left the detector active")
		-- Non-vacuity: the script drove actions and progress, and the counter is live.
		t.equal(total, 380, "the healthy script did not drive 380 actions")
		t.truthy(progressEvents >= 6, "no progress events fired")
		t.truthy(d:actionsSinceProgress() > 0, "the detector saw nothing")
		-- Discriminating assertion: the peak is far from the threshold, and the ratio is printed.
		local margin = 1 / worstRatio
		print(
			`[stall] healthy control: max actionsSinceProgress = {maxSince}, worst ratio to 96 x liveSeats = `
				.. `{string.format("%.3f", worstRatio)} ({maxSince} / {worstThreshold}), margin = {string.format(
					"%.1f",
					margin
				)}x, `
				.. `progress events = {progressEvents}, actions = {total}`
		)
		t.truthy(margin >= 2, `margin {margin}x is inside 2x: FINDING, report it, do not adjust the threshold`)
	end)

	t.test("a stuck table raises the cue even with ZERO valve firings (D-20)", function()
		local telemetry: { Telemetry } = {}
		local d = build(telemetry)
		-- valveFirings = 0 is explicit; the detector has no way to receive a valve event.
		local r = runStuck(d, { actions = 3000, liveSeats = 9, deciPerAction = 1, valveFirings = 0 })
		t.truthy(r.cues >= 1, "a stuck table with a silent valve raised no cue")
		t.equal(#telemetry >= 1, true, "no arming telemetry")
		local armed = telemetry[1]
		t.equal(armed.name, "stall_armed", "first telemetry")
		t.truthy(armed.data.actions >= PER_SEAT * 9, "armed before the action condition")
		t.truthy(armed.data.deci >= MIN_DECI, "armed before the wall-time condition")
		t.truthy(r.cues >= 3, `expected repeats over 3000 deci, got {r.cues}`)
		for i = 2, #r.cueTimes do
			t.equal(r.cueTimes[i] - r.cueTimes[i - 1], REPEAT_DECI, `repeat spacing at cue {i}`)
		end
		print(`[stall] stuck scenario: {r.cues} cues, first at deci {r.cueTimes[1]}`)
	end)

	t.test("MUTATION: a valve-keyed detector is silent in exactly the rounds that need it", function()
		-- 3 of 15 replayed stalls had the valve armed and firing zero times. A cue keyed off valve
		-- events never arms on them.
		local valveSeen = 0
		local valveKeyed = {
			noteValve = function(_self: any)
				valveSeen += 1
			end,
			noteApply = function(_self: any, _seats: number, _now: number) end,
			noteProgress = function(_self: any, _now: number) end,
			tick = function(_self: any, _now: number): { any }
				if valveSeen > 0 then
					return { { kind = "StallCue" } }
				end
				return {}
			end,
		}
		local scenario: StuckOpts = { actions = 3000, liveSeats = 9, deciPerAction = 1, valveFirings = 0 }
		local broken = runStuck(valveKeyed, scenario)
		local real = runStuck(build(), scenario)
		print(`[stall] MUTATION valve-keyed cues = {broken.cues}; real detector cues = {real.cues}`)
		t.equal(broken.cues, 0, "the valve-keyed variant should be silent with zero valve firings")
		t.truthy(real.cues >= 1, "the real detector must fire on the same scenario")
		-- Fixture validity: the broken variant is a working detector when its own signal is present.
		local fed = runStuck(valveKeyed, { actions = 10, liveSeats = 9, deciPerAction = 1, valveFirings = 1 })
		t.truthy(fed.cues >= 1, "the valve-keyed variant never fires even when fed, so the mutation proves nothing")
	end)

	t.test("neither condition alone arms the cue", function()
		-- (a) action count met, wall time not.
		local a = build()
		local ra = runStuck(a, { actions = 3000, liveSeats = 9, deciPerAction = 400 / 3000, valveFirings = 0 })
		t.equal(ra.cues, 0, "armed on the action count alone")
		t.equal(#a:tick(449), 0, "armed one deci before the wall-time condition")
		t.equal(#a:tick(450), 1, "did not arm the moment both conditions held")
		-- (b) wall time met, action count not.
		local b = build()
		local rb = runStuck(b, { actions = 20, liveSeats = 9, deciPerAction = 300, valveFirings = 0 })
		t.equal(rb.cues, 0, "armed on wall time alone")
		-- (c) both met.
		local c = runStuck(build(), { actions = 3000, liveSeats = 9, deciPerAction = 1, valveFirings = 0 })
		t.truthy(c.cues >= 1, "both conditions met but no cue")
	end)

	t.test("progress clears the window and emits StallClear exactly once", function()
		local d = build()
		runStuck(d, { actions = 1000, liveSeats = 9, deciPerAction = 1, valveFirings = 0 })
		t.truthy(d:isActive(), "fixture did not arm")
		d:noteProgress(1001)
		local first = d:tick(1001)
		t.equal(#first, 1, "StallClear count on the next tick")
		t.equal(first[1].kind, "StallClear", "kind")
		t.equal(#d:tick(1002), 0, "StallClear repeated")
		t.falsy(d:isActive(), "still active after progress")
		t.equal(d:actionsSinceProgress(), 0, "counter not reset")
	end)

	t.test("telemetry fires on arming and on clearing, with the counters", function()
		local telemetry: { Telemetry } = {}
		local d = build(telemetry)
		runStuck(d, { actions = 3000, liveSeats = 9, deciPerAction = 1, valveFirings = 0 })
		d:noteProgress(3001)
		d:tick(3001)
		t.equal(#telemetry, 2, "telemetry event count (armed repeats must not re-emit)")
		t.equal(telemetry[1].name, "stall_armed", "first event")
		t.equal(telemetry[2].name, "stall_cleared", "second event")
		t.equal(telemetry[1].data.liveSeats, 9, "liveSeats")
		t.truthy(telemetry[1].data.actions >= 864 and telemetry[1].data.deci >= 450, "armed counters")
		t.equal(telemetry[2].data.actions, 3000, "cleared actions")
		t.equal(telemetry[2].data.deci, 3001, "cleared deci")
	end)

	t.test("the threshold follows the table as seats are removed", function()
		local d = build()
		for i = 1, 300 do
			d:noteApply(9, i * 2)
		end
		t.equal(#d:tick(600), 0, "300 actions at 9 seats is below 96 x 9 and must not arm")
		d:noteApply(3, 602) -- 301 actions, now 3 live seats: threshold 288
		t.equal(#d:tick(602), 1, "threshold did not follow the live-seat count")
	end)

	t.test("non-finite or nonsensical input errors by name", function()
		local d = build()
		t.throws(function()
			d:noteApply(9, NAN)
		end, "nowDeci must be a finite non-negative integer")
		t.throws(function()
			d:noteApply(0, 5)
		end, "liveSeats must be a finite integer >= 1")
		t.throws(function()
			d:noteApply(2.5, 5)
		end, "liveSeats must be a finite integer >= 1")
		t.throws(function()
			d:noteApply(9, -1)
		end, "nowDeci must be a finite non-negative integer")
		t.throws(function()
			d:tick(1.5)
		end, "StallDetector.tick")
	end)
end
