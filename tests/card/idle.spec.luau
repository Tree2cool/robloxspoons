--!strict
-- CARD-16 gate: the AFK clock (D-13, D-14, D-15, D-17, D-35). Every mutation here is an INJECTED broken
-- dependency (the tests/engine/valve.spec.luau convention), never a source edit, and sits beside a clean
-- control that must be seen to pass in the same case. nowDeci is a plain integer: IdleClock never reads
-- a clock, so no FakeScheduler is needed (it floors to deciseconds anyway).
local IdleClock = require("../../src/server/core/IdleClock")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")

local DEPS: IdleClock.Deps = { autoPassDeci = 80, maxStrikes = 3 }

local function seatView(live: boolean, handSize: number, inboxSize: number): IdleClock.SeatView
	return { live = live, handSize = handSize, inboxSize = inboxSize }
end

local function oneSeat(handSize: number, inboxSize: number): IdleClock.View
	return { [1] = seatView(true, handSize, inboxSize) }
end

-- The surface the helpers drive, so a mutant can be a wrapper around the real clock.
type Clock = {
	sync: (self: any, view: IdleClock.View, nowDeci: number, playerActedSeat: number?) -> (),
	tick: (self: any, nowDeci: number) -> { any },
	strikesOf: (self: any, seat: number) -> number,
	deadlineDeci: (self: any, seat: number) -> number?,
}

-- D-35. A card-moving command is ANY command that is not a Strike or a Bench, or any command carrying a
-- cardId. Written as an open set deliberately: "kind ~= 'AutoDraw'" would only catch the one name we made
-- unrepresentable, which is a check that cannot fail.
local function noCardMoved(commands: { any }): { string }
	local problems: { string } = {}
	for index, cmd in commands do
		if cmd.kind ~= "Strike" and cmd.kind ~= "Bench" then
			table.insert(problems, `command {index} ({tostring(cmd.kind)}) is not a Strike or a Bench`)
		elseif cmd.cardId ~= nil then
			table.insert(problems, `command {index} ({tostring(cmd.kind)}) carries a cardId`)
		end
	end
	return problems
end

-- D-15 case table, driven through whatever predicate it is handed.
local LEGAL_CASES: { { handSize: number, inboxSize: number, expected: boolean } } = {
	{ handSize = 4, inboxSize = 0, expected = false },
	{ handSize = 4, inboxSize = 1, expected = true },
	{ handSize = 4, inboxSize = 13, expected = true },
	{ handSize = 5, inboxSize = 0, expected = true },
	{ handSize = 5, inboxSize = 3, expected = true },
	{ handSize = 3, inboxSize = 5, expected = false },
	{ handSize = 0, inboxSize = 0, expected = false },
}

local function predicateProblems(predicate: (IdleClock.SeatView) -> boolean): ({ string }, number)
	local problems: { string } = {}
	local rows = 0
	for _, row in LEGAL_CASES do
		rows += 1
		if predicate(seatView(true, row.handSize, row.inboxSize)) ~= row.expected then
			table.insert(problems, `({row.handSize},{row.inboxSize}) expected {tostring(row.expected)}`)
		end
		rows += 1
		if predicate(seatView(false, row.handSize, row.inboxSize)) ~= false then
			table.insert(problems, `dead ({row.handSize},{row.inboxSize}) expected false`)
		end
	end
	return problems, rows
end

-- D-15 at clock level: a (4, empty) seat ticked every 10 deci from 10 to 1000; returns commands seen.
local function idleRampCommands(clock: Clock): (number, number)
	clock:sync(oneSeat(4, 0), 0, nil)
	local ticks = 0
	local commands = 0
	for now = 10, 1000, 10 do
		ticks += 1
		commands += #clock:tick(now)
	end
	return ticks, commands
end

-- D-17: returns (strikes after a real action, strikes after a server-originated sync, re-armed deadline).
local function resetOutcome(clock: Clock): (number, number, number?)
	clock:sync(oneSeat(5, 1), 1000, nil)
	clock:tick(1080)
	clock:tick(1160)
	clock:sync(oneSeat(5, 1), 1170, 1)
	local afterReal = clock:strikesOf(1)
	local rearmed = clock:deadlineDeci(1)
	clock:tick(1250)
	clock:tick(1330)
	clock:sync(oneSeat(5, 1), 1340, nil)
	return afterReal, clock:strikesOf(1), rearmed
end

local function resetProblems(clock: Clock): { string }
	local problems: { string } = {}
	local afterReal, afterServer, rearmed = resetOutcome(clock)
	if afterReal ~= 0 then
		table.insert(problems, `a real action left strikes at {afterReal}`)
	end
	if rearmed ~= 1250 then
		table.insert(problems, `real action re-armed to {tostring(rearmed)}, expected 1250`)
	end
	if afterServer ~= 2 then
		table.insert(problems, `a server-originated sync changed strikes to {afterServer}, expected 2`)
	end
	return problems
end

-- D-14 distribution helper: 5000 draws over a 5-card hand; each card expected ~1000 (+-15%).
local HAND: { number } = { 11, 22, 33, 44, 55 }
local function uniformityProblems(pick: ({ number }, any) -> number): ({ string }, { [number]: number }, number)
	local rng = Rng.new(1000003)
	local counts: { [number]: number } = {}
	for _, card in HAND do
		counts[card] = 0
	end
	local total = 0
	for _ = 1, 5000 do
		local chosen = pick(HAND, rng)
		counts[chosen] = (counts[chosen] or 0) + 1
		total += 1
	end
	local problems: { string } = {}
	if total ~= 5000 then
		table.insert(problems, `only {total} draws`)
	end
	for _, card in HAND do
		-- A sampling tolerance, not a tuning target.
		if counts[card] < 850 or counts[card] > 1150 then
			table.insert(problems, `card {card} chosen {counts[card]} times`)
		end
	end
	return problems, counts, total
end

return function(t: Test.Runner)
	t.test("D-15: a seat at hand 4 with an EMPTY inbox never accrues idle time", function()
		local clock = IdleClock.new(DEPS)
		clock:sync(oneSeat(4, 0), 0, nil)
		t.equal(clock:deadlineDeci(1), nil, "no deadline may be armed")
		local ticks, commands = idleRampCommands(IdleClock.new(DEPS))
		t.equal(ticks, 100, "non-vacuity: ticks exercised")
		t.equal(commands, 0, "commands emitted for a seat with no legal action")
		print(`idle D-15 ramp: {ticks} ticks, {commands} commands`)
	end)

	t.test("D-15: the legal predicate is exactly (4 and inbox) or 5, and a dead seat is never legal", function()
		local problems, rows = predicateProblems(IdleClock.legal)
		t.deepEqual(problems, {}, "real predicate")
		t.equal(rows, 14, "non-vacuity: case count")
	end)

	t.test("a hand-5 seat expires at exactly +80 deci, not at +79 and not only at +81", function()
		local clock = IdleClock.new(DEPS)
		clock:sync(oneSeat(5, 0), 1000, nil)
		t.equal(clock:deadlineDeci(1), 1080)
		t.deepEqual(clock:tick(1079), {}, "fired one deci early")
		local commands = clock:tick(1080)
		t.equal(#commands, 2, "AutoPass then Strike")
		t.equal(commands[1].kind, "AutoPass")
		t.equal(commands[2].kind, "Strike")
		t.equal(commands[2].strikes, 1)
		t.equal(commands[2].owes, "Pass")
	end)

	t.test("D-35: a hand-4 expiry emits a Strike and NOTHING else, ever", function()
		local clock = IdleClock.new(DEPS)
		clock:sync(oneSeat(4, 2), 1000, nil)
		local observed = 0
		local first = clock:tick(1080)
		observed += #first
		t.deepEqual(noCardMoved(first), {})
		t.equal(#first, 1, "exactly one command")
		t.equal(first[1].kind, "Strike")
		t.equal(first[1].owes, "Draw")
		t.equal(clock:deadlineDeci(1), 1160, "re-armed to now + 80")
		local second = clock:tick(1160)
		observed += #second
		local third = clock:tick(1240)
		observed += #third
		t.deepEqual(noCardMoved(second), {})
		t.deepEqual(noCardMoved(third), {})
		t.equal(clock:strikesOf(1), 3)
		t.equal(third[#third].kind, "Bench", "third strike benches")
		t.equal(observed, 4, "non-vacuity: Strike, Strike, Strike, Bench")
	end)

	t.test("MUTATION: a clock that auto-draws at hand 4 is caught by the same helper", function()
		-- Four of a kind is checked ONLY on draw, so an auto-draw could hand an absent player a
		-- completion plus the kept placement bonus: the game would be paying someone for being away.
		-- AutoDraw is unrepresentable, so the mutants use kinds that ARE representable.
		local real = IdleClock.new(DEPS)
		real:sync(oneSeat(4, 2), 1000, nil)
		local mutant = {
			tick = function(_self: any, _nowDeci: number): { any }
				return {
					{ kind = "AutoPass", seat = 1 },
					{ kind = "Strike", seat = 1, strikes = 1, owes = "Draw" },
				}
			end,
		}
		local renamed = {
			tick = function(_self: any, _nowDeci: number): { any }
				return { { kind = "Draw", seat = 1 }, { kind = "Strike", seat = 1, strikes = 1, owes = "Draw" } }
			end,
		}
		local carrying = {
			tick = function(_self: any, _nowDeci: number): { any }
				return { { kind = "Strike", seat = 1, strikes = 1, owes = "Draw", cardId = 7 } }
			end,
		}
		t.truthy(#noCardMoved(mutant:tick(1080)) > 0, "AutoPass at hand 4 must be reported")
		t.truthy(#noCardMoved(renamed:tick(1080)) > 0, "a Draw command must be reported")
		t.truthy(#noCardMoved(carrying:tick(1080)) > 0, "a command carrying a cardId must be reported")
		t.deepEqual(noCardMoved(real:tick(1080)), {}, "the real clock must report nothing")
	end)

	t.test("D-17: any real player action resets the strike count; a server-originated one does not", function()
		local problems = resetProblems(IdleClock.new(DEPS))
		t.deepEqual(problems, {})
		local afterReal, afterServer = resetOutcome(IdleClock.new(DEPS))
		t.equal(afterReal, 0)
		t.equal(afterServer, 2, "non-vacuity: strikes were really built up to 2")
	end)

	t.test("a card arriving in an idle seat's inbox does not refresh its window", function()
		local clock = IdleClock.new(DEPS)
		clock:sync(oneSeat(5, 0), 1000, nil)
		clock:sync(oneSeat(5, 1), 1040, nil)
		t.equal(clock:deadlineDeci(1), 1080)
	end)

	t.test("becoming illegal pauses the clock and KEEPS the strike record", function()
		local clock = IdleClock.new(DEPS)
		clock:sync(oneSeat(5, 1), 1000, nil)
		clock:tick(1080)
		t.equal(clock:strikesOf(1), 1)
		clock:sync(oneSeat(4, 0), 1090, nil)
		t.equal(clock:deadlineDeci(1), nil)
		t.equal(clock:strikesOf(1), 1)
		clock:sync(oneSeat(4, 1), 1100, nil)
		t.equal(clock:deadlineDeci(1), 1180)
		t.equal(clock:strikesOf(1), 1)
	end)

	t.test("three strikes emits exactly one Bench, and a removed seat is forgotten", function()
		local clock = IdleClock.new(DEPS)
		clock:sync(oneSeat(5, 1), 1000, nil)
		local benches = 0
		local strikes = 0
		for _, now in { 1080, 1160, 1240 } do
			for _, cmd in clock:tick(now) do
				if cmd.kind == "Bench" then
					benches += 1
					t.equal(cmd.seat, 1)
				elseif cmd.kind == "Strike" then
					strikes += 1
				end
			end
		end
		-- The adapter applies Remove{Benched} and re-syncs the seat as not live.
		clock:sync({ [1] = seatView(false, 0, 0) }, 1241, nil)
		for now = 1250, 2000, 10 do
			for _, cmd in clock:tick(now) do
				if cmd.kind == "Bench" then
					benches += 1
				elseif cmd.kind == "Strike" then
					strikes += 1
				end
			end
		end
		t.equal(benches, 1)
		t.equal(strikes, 3, "no fourth strike after the bench")
		t.equal(clock:deadlineDeci(1), nil)
		t.equal(clock:strikesOf(1), 0)
		local other = IdleClock.new(DEPS)
		other:sync(oneSeat(5, 1), 1000, nil)
		other:tick(1080)
		other:forget(1)
		t.equal(other:deadlineDeci(1), nil)
		t.equal(other:strikesOf(1), 0)
	end)

	t.test("D-14: the auto-pass choice is uniform over the hand", function()
		local started = os.clock()
		local problems, counts, total = uniformityProblems(IdleClock.pickUniform)
		local elapsed = os.clock() - started
		t.deepEqual(problems, {})
		t.equal(total, 5000)
		for _, card in HAND do
			t.truthy(counts[card] > 0, `card {card} never chosen`)
		end
		t.truthy(elapsed < 0.2, `uniformity case took {elapsed}s`)
		print(
			`idle D-14 counts: {counts[11]},{counts[22]},{counts[33]},{counts[44]},{counts[55]} in {string.format(
				"%.4f",
				elapsed
			)}s`
		)
		t.throws(function()
			IdleClock.pickUniform({}, Rng.new(1000003))
		end, "empty hand")
	end)

	t.test("MUTATION: a greedy pick is detected by the uniformity assertion (D-14)", function()
		-- A greedy rule is the player's own choice, so it zeroes the deviation the Gate G1 sweep
		-- measured and invalidates every auto-pass number it produced.
		local function pickLowest(hand: { number }, _rng: any): number
			return math.min(table.unpack(hand))
		end
		local clean = uniformityProblems(IdleClock.pickUniform)
		local broken, counts = uniformityProblems(pickLowest)
		t.deepEqual(clean, {})
		t.truthy(#broken > 0, "greedy pick must be reported")
		t.equal(counts[11], 5000, "non-vacuity: the greedy mutant really always picks the lowest")
	end)

	t.test("MUTATION: 81-deci deadline, a too-wide predicate, a hand-4-only predicate", function()
		-- 81 deadline
		local real = IdleClock.new(DEPS)
		local late = IdleClock.new({ autoPassDeci = 81, maxStrikes = 3 })
		real:sync(oneSeat(5, 0), 1000, nil)
		late:sync(oneSeat(5, 0), 1000, nil)
		t.equal(#real:tick(1080), 2, "real clock fires at +80")
		t.equal(#late:tick(1080), 0, "the 81-deci mutant does not fire at +80")

		-- too-wide predicate (drops inboxSize >= 1)
		local function legalTooWide(seat: IdleClock.SeatView): boolean
			return seat.live and (seat.handSize == 4 or seat.handSize == 5)
		end
		local wideProblems = predicateProblems(legalTooWide)
		t.truthy(#wideProblems > 0, "too-wide predicate must fail the table")
		t.contains(table.concat(wideProblems, ";"), "(4,0)", "must fail the (4,0) row")
		-- and at clock level: the same defect injected as a view rewrite wakes the ramp seat
		local wideClock = IdleClock.new(DEPS)
		local wrapped: Clock = {
			sync = function(_self: any, view: IdleClock.View, nowDeci: number, acted: number?)
				local rewritten: IdleClock.View = {}
				for id, seat in view do
					rewritten[id] = seatView(seat.live, seat.handSize, if seat.handSize == 4 then 1 else seat.inboxSize)
				end
				wideClock:sync(rewritten, nowDeci, acted)
			end,
			tick = function(_self: any, nowDeci: number)
				return wideClock:tick(nowDeci)
			end,
			strikesOf = function(_self: any, seat: number)
				return wideClock:strikesOf(seat)
			end,
			deadlineDeci = function(_self: any, seat: number)
				return wideClock:deadlineDeci(seat)
			end,
		}
		local _, wideCommands = idleRampCommands(wrapped)
		local _, cleanCommands = idleRampCommands(IdleClock.new(DEPS))
		t.equal(cleanCommands, 0)
		t.truthy(wideCommands > 0, "the ramp mutant must strike the far seat")

		-- hand-4-only predicate
		local function legalHandFourOnly(seat: IdleClock.SeatView): boolean
			return seat.handSize == 4
		end
		local fourProblems = predicateProblems(legalHandFourOnly)
		t.truthy(#fourProblems > 0, "hand-4-only predicate must fail the table")
		t.contains(table.concat(fourProblems, ";"), "(5,3)", "must fail the (5,3) row")
		t.deepEqual((predicateProblems(IdleClock.legal)), {}, "clean control")
	end)

	t.test("MUTATION: a strike that does not reset on a real action", function()
		local real = IdleClock.new(DEPS)
		local inner = IdleClock.new(DEPS)
		local noReset: Clock = {
			sync = function(_self: any, view: IdleClock.View, nowDeci: number, _acted: number?)
				inner:sync(view, nowDeci, nil)
			end,
			tick = function(_self: any, nowDeci: number)
				return inner:tick(nowDeci)
			end,
			strikesOf = function(_self: any, seat: number)
				return inner:strikesOf(seat)
			end,
			deadlineDeci = function(_self: any, seat: number)
				return inner:deadlineDeci(seat)
			end,
		}
		t.deepEqual(resetProblems(real), {}, "clean control")
		t.truthy(#resetProblems(noReset) > 0, "a reset-less clock must be reported")
	end)

	t.test("non-finite or nonsensical input errors by name rather than arming a dead deadline", function()
		-- NaN fails every comparison, so a NaN deadline would make deadline <= nowDeci false forever and
		-- the clock would silently never fire.
		local clock = IdleClock.new(DEPS)
		t.throws(function()
			clock:sync(oneSeat(5, 1), 0 / 0, nil)
		end, "nowDeci")
		t.throws(function()
			clock:sync(oneSeat(5, 1), math.huge, nil)
		end, "nowDeci")
		t.throws(function()
			clock:sync(oneSeat(5, 1), 1.5, nil)
		end, "nowDeci")
		t.throws(function()
			clock:sync(oneSeat(-1, 1), 10, nil)
		end, "handSize")
		t.throws(function()
			clock:tick(0 / 0)
		end, "nowDeci")
		t.equal(clock:deadlineDeci(1), nil, "a rejected sync armed nothing")
	end)
end
