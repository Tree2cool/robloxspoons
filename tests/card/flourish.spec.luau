--!strict
-- CARD-17 gate: the fixed-duration flourish driver (D-30, D-32, checker FLAG F8). Time moves only through
-- the FakeScheduler, so nothing here uses a real clock. Mutations are INJECTED broken dependencies (the
-- valve.spec convention), each beside a clean control seen to pass in the same case.
--
-- What this proves: the duration contract, the cut-off, the periodic scan and the injection. What it
-- cannot prove: that the starting gun FEELS like one (MANUAL-CHECKS M-17) or that audio asset ids resolve
-- (M-16). A synchronous infinite loop inside `play` cannot be stopped in Luau and is not tested.
local fs = require("@lune/fs")

local Card = require("../../src/shared/Config/Card")
local Flourish = require("../../src/shared/Card/Flourish")
local FakeScheduler = require("../harness/FakeScheduler")
local Test = require("../harness/Test")

local DURATION = 1.5
local SCAN = 0.25

type Violation = { message: string, deci: number }
type Rig = {
	driver: Flourish.Driver,
	fake: FakeScheduler.FakeScheduler,
	sched: Flourish.Scheduler,
	calls: { string },
	violations: { Violation },
	scanDecis: { number },
	cancelled: { any },
	spawned: { any },
	setOffenders: (list: { string }) -> (),
	setEscaped: (list: { string }) -> (),
	destroyRootCount: () -> number,
	firstViolationDeci: () -> number?,
}
type RigOptions = {
	registry: { [string]: Flourish.Entry }?,
	dropDelaysOf: number?, -- an injected defect: a delay of exactly this many seconds is never registered
}

local mutationsRed = 0

local function newRig(options: RigOptions): Rig
	local fake = FakeScheduler.new()
	local calls: { string } = {}
	local violations: { Violation } = {}
	local scanDecis: { number } = {}
	local cancelled: { any } = {}
	local spawned: { any } = {}
	local offenders: { string } = {}
	local escaped: { string } = {}

	local sched: Flourish.Scheduler = {
		nowDeci = fake.nowDeci,
		delay = function(seconds: number, fn: () -> ()): () -> ()
			if options.dropDelaysOf ~= nil and seconds == options.dropDelaysOf then
				return function() end
			end
			return fake.delay(seconds, fn)
		end,
		spawn = function(fn: () -> ()): any
			local co = coroutine.create(fn)
			table.insert(spawned, co)
			coroutine.resume(co)
			return co
		end,
		cancel = function(thread: any)
			table.insert(cancelled, thread)
			if coroutine.status(thread) == "suspended" then
				coroutine.close(thread)
			end
		end,
	}

	local surface: Flourish.Surface = {
		createRoot = function(_kind: Flourish.Kind): any
			table.insert(calls, "createRoot")
			return { name = "root" }
		end,
		destroyRoot = function(_root: any)
			table.insert(calls, "destroyRoot")
		end,
		scan = function(_root: any): { string }
			table.insert(calls, "scan")
			table.insert(scanDecis, fake.nowDeci())
			return table.clone(offenders)
		end,
		destroyOffenders = function(_root: any): number
			table.insert(calls, "destroyOffenders")
			local n = #offenders
			table.clear(offenders)
			return n
		end,
		snapshot = function(): any
			table.insert(calls, "snapshot")
			return { token = 1 }
		end,
		diff = function(_snapshot: any): { string }
			table.insert(calls, "diff")
			return table.clone(escaped)
		end,
		destroyEscaped = function(_snapshot: any): number
			table.insert(calls, "destroyEscaped")
			return #escaped
		end,
	}

	local driver = Flourish.new({
		surface = surface,
		scheduler = sched,
		durationSeconds = DURATION,
		scanIntervalSeconds = SCAN,
		registry = options.registry or {},
		onViolation = function(message: string)
			table.insert(violations, { message = message, deci = fake.nowDeci() })
		end,
	})

	return {
		driver = driver,
		fake = fake,
		sched = sched,
		calls = calls,
		violations = violations,
		scanDecis = scanDecis,
		cancelled = cancelled,
		spawned = spawned,
		setOffenders = function(list: { string })
			offenders = list
		end,
		setEscaped = function(list: { string })
			escaped = list
		end,
		destroyRootCount = function(): number
			local n = 0
			for _, c in calls do
				if c == "destroyRoot" then
					n += 1
				end
			end
			return n
		end,
		firstViolationDeci = function(): number?
			local first = violations[1]
			return if first ~= nil then first.deci else nil
		end,
	}
end

-- A flourish that schedules its own 5 s delay and returns at once.
local function longEntry(rig: { sched: Flourish.Scheduler }): Flourish.Entry
	return {
		kind = "Completion",
		play = function(_ctx: Flourish.FlourishContext)
			rig.sched.delay(5, function() end)
		end,
	}
end

-- A flourish that yields for 5 s through the injected scheduler and never returns before the cut-off.
local function yieldingEntry(sched: Flourish.Scheduler, kind: Flourish.Kind): Flourish.Entry
	return {
		kind = kind,
		play = function(_ctx: Flourish.FlourishContext)
			local co = coroutine.running()
			sched.delay(5, function()
				if coroutine.status(co) == "suspended" then
					coroutine.resume(co)
				end
			end)
			coroutine.yield()
		end,
	}
end

-- Builds a rig whose registry holds `make(sched)` for BOTH kinds. The registry needs the scheduler and the
-- scheduler needs the registry, so the entry closes over a late-bound reference.
local function rigWith(
	make: (sched: Flourish.Scheduler, kind: Flourish.Kind) -> Flourish.Entry,
	dropDelaysOf: number?
): Rig
	local late: { sched: Flourish.Scheduler? } = { sched = nil }
	local proxy: Flourish.Scheduler = {
		nowDeci = function()
			return (late.sched :: Flourish.Scheduler).nowDeci()
		end,
		delay = function(seconds: number, fn: () -> ()): () -> ()
			return (late.sched :: Flourish.Scheduler).delay(seconds, fn)
		end,
		spawn = function(fn: () -> ()): any
			return (late.sched :: Flourish.Scheduler).spawn(fn)
		end,
		cancel = function(thread: any)
			(late.sched :: Flourish.Scheduler).cancel(thread)
		end,
	}
	local rig = newRig({
		registry = { Deal = make(proxy, "Deal"), Completion = make(proxy, "Completion") },
		dropDelaysOf = dropDelaysOf,
	})
	late.sched = rig.sched
	return rig
end

local function cutoffLandsAt15(rig: Rig): boolean
	rig.driver:play("Completion", 1, true, { 7 })
	rig.fake.advance(1.4)
	if rig.destroyRootCount() ~= 0 or rig.driver:activeCount() ~= 1 then
		return false
	end
	rig.fake.advance(0.1)
	return rig.destroyRootCount() == 1 and rig.driver:activeCount() == 0
end

return function(t: Test.Runner)
	t.test("(a) a flourish that asks for 5 s is torn down at 1.5 s", function()
		local rig = rigWith(function(sched, kind)
			return { kind = kind, play = longEntry({ sched = sched }).play }
		end)
		rig.driver:play("Completion", 1, true, { 7 })
		rig.fake.advance(1.4)
		t.equal(rig.driver:activeCount(), 1, "gone before 1.4 s: an off-by-one early")
		t.equal(rig.destroyRootCount(), 0, "destroyed before the cut-off")
		rig.fake.advance(0.1)
		t.equal(rig.destroyRootCount(), 1, "not destroyed at exactly 1.5 s: an off-by-one late")
		t.equal(rig.driver:activeCount(), 0)
		rig.fake.advance(4.5)
		t.equal(rig.destroyRootCount(), 1, "destroyed more than once")
	end)

	t.test("(b) a flourish that YIELDS for 5 s is cancelled at 1.5 s and does not delay the driver", function()
		local rig = rigWith(yieldingEntry)
		local inputRan = false
		rig.fake.delay(0.4, function()
			inputRan = true
		end)
		rig.driver:play("Completion", 1, true, { 7 })
		t.equal(#rig.spawned, 1, "non-vacuity: the flourish was spawned")
		t.equal(coroutine.status(rig.spawned[1]), "suspended", "non-vacuity: the flourish is yielding")
		rig.fake.advance(1.4)
		t.equal(rig.destroyRootCount(), 0, "torn down early")
		t.truthy(inputRan, "D-30: a yielding flourish blocked the scheduler")
		rig.fake.advance(0.1)
		t.equal(rig.destroyRootCount(), 1, "teardown did not land at 1.5 s")
		t.equal(rig.cancelled[1], rig.spawned[1], "scheduler.cancel was not called on the flight's thread")
		t.equal(coroutine.status(rig.spawned[1]), "dead", "the yielding thread was not stopped")
		rig.fake.advance(4)
		t.equal(rig.destroyRootCount(), 1)
	end)

	t.test("(c) the default Plain flourishes finish strictly before the cut-off, with margin", function()
		local completion = Flourish.totalOf(Flourish.DEFAULTS.Completion)
		local deal = Flourish.totalOf(Flourish.DEFAULTS.Deal)
		t.equal(completion, 1.2)
		t.equal(deal, 0.6)
		t.truthy(completion < Card.FLOURISH_DURATION_SECONDS, "Completion races its own teardown")
		t.truthy(deal < Card.FLOURISH_DURATION_SECONDS)
		-- 0.2 s is more than one frame at 60 Hz (0.0167 s), so a late frame cannot make it race the cut-off.
		t.truthy(Card.FLOURISH_DURATION_SECONDS - completion >= 0.2 - 1e-9, "margin under 0.2 s")
		t.truthy(table.isfrozen(Flourish.DEFAULTS) and table.isfrozen(Flourish.DEFAULTS.Completion))
		t.throws(function()
			Flourish.totalOf({ mystery = 1 })
		end, "unrecognised definition shape")
		t.throws(function()
			Flourish.totalOf({ steps = { { name = "x", seconds = -1 } } })
		end, "positive numeric seconds")
		t.throws(function()
			Flourish.totalOf(5)
		end, "not a table")
	end)

	t.test("(d) input handlers fire during the flourish, all before teardown (D-30)", function()
		local rig = rigWith(yieldingEntry)
		rig.driver:play("Completion", 1, true, { 7 })
		local inputs = 0
		for _, at in { 0.2, 0.7, 1.4 } do
			rig.fake.delay(at, function()
				inputs += 1
				table.insert(rig.calls, "input")
			end)
		end
		rig.fake.advance(2)
		t.equal(inputs, 3, "non-vacuity: observed input count")
		local lastInput, destroyAt = 0, 0
		for i, c in rig.calls do
			if c == "input" then
				lastInput = i
			elseif c == "destroyRoot" then
				destroyAt = i
			end
		end
		t.truthy(destroyAt > 0 and lastInput < destroyAt, "an input fired after the flourish was destroyed")
	end)

	t.test("(e) the scan catches an input-taking object, and the diff catches an instance outside the root", function()
		local rig = rigWith(yieldingEntry)
		rig.setOffenders({ "Active GuiObject: FakeOverlay" })
		rig.setEscaped({ "escaped: Workspace.Stray" })
		rig.driver:play("Completion", 1, true, { 7 })
		rig.fake.advance(1.5)
		local sawScan, sawDiff = false, false
		for _, v in rig.violations do
			if string.find(v.message, "FakeOverlay", 1, true) then
				sawScan = true
			end
			if string.find(v.message, "Workspace.Stray", 1, true) then
				sawDiff = true
			end
		end
		t.truthy(sawScan, "scan finding not reported")
		t.truthy(sawDiff, "diff finding not reported")
		t.truthy(table.find(rig.calls, "destroyEscaped") ~= nil, "destroyEscaped not called")
		t.truthy(table.find(rig.calls, "destroyOffenders") ~= nil, "offenders not destroyed")
		t.equal(rig.destroyRootCount(), 1, "a violation must not be fatal")
		t.equal(rig.driver:activeCount(), 0)
	end)

	t.test(
		"F8: the scan runs PERIODICALLY during the flight (an undetected mid-flight Active object silently breaks D-30's instant control return, which protects a finisher's score)",
		function()
			-- clean control
			local rig = rigWith(yieldingEntry)
			rig.driver:play("Completion", 1, true, { 7 })
			rig.fake.delay(0.5, function()
				rig.setOffenders({ "Active GuiObject: MidFlightOverlay" })
			end)
			rig.fake.advance(1.5)
			local first = rig.firstViolationDeci()
			t.truthy(first ~= nil and first <= 7, `violation detected at deci {tostring(first)}, not by 0.75 s`)
			t.truthy((first :: number) < 15, "detected only at the cut-off")
			local periodic = 0
			for _, d in rig.scanDecis do
				if d < 15 then
					periodic += 1
				end
			end
			print(`F8 scans per flight (before the cut-off, deci-floored interval): {periodic}`)
			t.truthy(periodic >= math.floor(DURATION / SCAN), `only {periodic} scans in the flight`)
			t.truthy(table.find(rig.calls, "destroyOffenders") ~= nil)

			-- MUTATION: no periodic scan (the interval delay is never registered). The object is only found at
			-- the cut-off, i.e. after the input was already sunk for a full second.
			local broken = rigWith(yieldingEntry, SCAN)
			broken.driver:play("Completion", 1, true, { 7 })
			broken.fake.delay(0.5, function()
				broken.setOffenders({ "Active GuiObject: MidFlightOverlay" })
			end)
			broken.fake.advance(1.5)
			local brokenFirst = broken.firstViolationDeci()
			t.truthy(
				brokenFirst == nil or brokenFirst > 7,
				"MUTATION: no periodic scan still detected early (vacuous gate)"
			)
			mutationsRed += 1

			-- And the config route to the same bug is refused outright.
			t.throws(function()
				Flourish.new({
					surface = {} :: any,
					scheduler = rig.sched,
					durationSeconds = DURATION,
					scanIntervalSeconds = DURATION,
					registry = {},
					onViolation = function() end,
				})
			end, "scanIntervalSeconds must be below durationSeconds")
		end
	)

	t.test("F8: the Deal kind is ScreenGui-constrained and its DisplayOrder is below the hand", function()
		t.equal(Flourish.ROOT_SURFACE.Deal, "ScreenGui")
		t.equal(Flourish.ROOT_SURFACE.Completion, "Workspace")
		t.truthy(table.isfrozen(Flourish.ROOT_SURFACE), "ROOT_SURFACE not frozen")
		t.truthy(Flourish.DISPLAY_ORDER < Card.HAND_DISPLAY_ORDER, "F8: flourish DisplayOrder is not below the hand's")
		local kinds: { string } = {}
		local rig = newRig({})
		local entry: Flourish.Entry = { kind = "Deal", play = function() end }
		local recording = Flourish.new({
			surface = {
				createRoot = function(kind: Flourish.Kind): any
					table.insert(kinds, kind)
					return {}
				end,
				destroyRoot = function() end,
				scan = function(): { string }
					return {}
				end,
				destroyOffenders = function(): number
					return 0
				end,
				snapshot = function(): any
					return {}
				end,
				diff = function(): { string }
					return {}
				end,
				destroyEscaped = function(): number
					return 0
				end,
			},
			scheduler = rig.sched,
			durationSeconds = DURATION,
			scanIntervalSeconds = SCAN,
			registry = { Deal = entry },
			onViolation = function() end,
		})
		recording:play("Deal", 1, false, {})
		t.deepEqual(kinds, { "Deal" }, "createRoot must receive the kind so the Surface can honour the constraint")
	end)

	t.test("the call order is createRoot, snapshot, arm teardown, arm scan, THEN spawn", function()
		local atPlay: { pending: number, log: { string } }? = nil
		local rig: Rig
		rig = rigWith(function(_sched, kind)
			return {
				kind = kind,
				play = function()
					atPlay = { pending = rig.fake.pending(), log = table.clone(rig.calls) }
				end,
			}
		end)
		rig.driver:play("Completion", 1, true, { 7 })
		local seen = atPlay :: { pending: number, log: { string } }
		t.truthy(seen ~= nil, "non-vacuity: play ran")
		t.truthy(seen.pending >= 2, `only {seen.pending} timers armed when play was entered`)
		t.deepEqual(seen.log, { "createRoot", "snapshot" })
	end)

	t.test("(f) MUTATION: the cut-off removed, and the cut-off armed AFTER play", function()
		-- cut-off removed: the delay of exactly DURATION seconds is never registered.
		local real = rigWith(function(sched, kind)
			return { kind = kind, play = longEntry({ sched = sched }).play }
		end)
		t.truthy(cutoffLandsAt15(real), "clean control: the real driver must land at 1.5 s")
		local removed = rigWith(function(sched, kind)
			return { kind = kind, play = longEntry({ sched = sched }).play }
		end, DURATION)
		t.falsy(cutoffLandsAt15(removed), "MUTATION: cut-off removed still landed (vacuous gate)")
		mutationsRed += 1

		-- cut-off armed AFTER play: a driver that runs play inline and arms the teardown afterwards. A
		-- yielding flourish then blocks the arming for as long as it likes.
		local armedAfter = rigWith(yieldingEntry)
		local entry = yieldingEntry(armedAfter.sched, "Completion")
		local ctx: Flourish.FlourishContext =
			{ root = {}, kind = "Completion", seat = 1, isLocalSeat = true, durationSeconds = DURATION, faces = {} }
		local mutantTornDown = false
		local runner = coroutine.create(function()
			entry.play(ctx) -- play first ...
			armedAfter.fake.delay(DURATION, function() -- ... teardown armed afterwards
				mutantTornDown = true
			end)
		end)
		coroutine.resume(runner)
		armedAfter.fake.advance(1.5)
		t.falsy(mutantTornDown, "MUTATION: cut-off armed after play still landed (vacuous gate)")
		mutationsRed += 1
		-- The real driver, given the identical yielding flourish, lands.
		local realYield = rigWith(yieldingEntry)
		t.truthy(cutoffLandsAt15(realYield), "clean control: real driver with a yielding flourish")

		t.equal(mutationsRed, 3, "expected 3 mutations exercised (F8 no-scan + these 2)")
	end)

	t.test("an unknown kind or a missing registry entry is reported and does NOT throw", function()
		-- A missing cosmetic must never break a completion: a completion is the moment a score depends on.
		local rig = newRig({})
		rig.driver:play("Dance" :: any, 1, true, {})
		rig.driver:play("Deal", 1, true, {})
		t.equal(#rig.violations, 2)
		t.contains(rig.violations[1].message, "Dance")
		t.contains(rig.violations[2].message, "Deal")
		t.equal(rig.driver:activeCount(), 0)
		t.equal(#rig.calls, 0, "nothing should be created for a flourish that cannot run")
	end)

	t.test("a flourish that throws is reported, not fatal, and still torn down at 1.5 s", function()
		local rig = rigWith(function(_sched, kind)
			return {
				kind = kind,
				play = function()
					error("boom")
				end,
			}
		end)
		rig.driver:play("Completion", 1, true, { 7 })
		t.truthy(#rig.violations >= 1 and string.find(rig.violations[1].message, "boom", 1, true) ~= nil)
		rig.fake.advance(1.5)
		t.equal(rig.destroyRootCount(), 1)
		t.equal(rig.driver:activeCount(), 0)
	end)

	t.test("cancelAll tears every live flight down exactly once", function()
		local rig = rigWith(yieldingEntry)
		rig.driver:play("Completion", 1, true, { 7 })
		rig.driver:play("Deal", 2, false, {})
		t.equal(rig.driver:activeCount(), 2)
		rig.driver:cancelAll()
		t.equal(rig.driver:activeCount(), 0)
		t.equal(rig.destroyRootCount(), 2)
		rig.fake.advance(6)
		t.equal(rig.destroyRootCount(), 2, "a stale timer tore a flight down twice")
	end)

	t.test("the constructor refuses a nonsensical duration or scan interval", function()
		local function build(duration: number, interval: number)
			local rig = newRig({})
			Flourish.new({
				surface = {} :: any,
				scheduler = rig.sched,
				durationSeconds = duration,
				scanIntervalSeconds = interval,
				registry = {},
				onViolation = function() end,
			})
		end
		t.throws(function()
			build(0, 0.25)
		end, "durationSeconds must be finite and positive")
		t.throws(function()
			build(-1, 0.25)
		end, "durationSeconds must be finite and positive")
		t.throws(function()
			build(math.huge, 0.25)
		end, "durationSeconds must be finite and positive")
		t.throws(function()
			build(0 / 0, 0.25)
		end, "durationSeconds must be finite and positive")
		t.throws(function()
			build(1.5, 0)
		end, "scanIntervalSeconds must be finite and positive")
		t.throws(function()
			build(1.5, math.huge)
		end, "scanIntervalSeconds must be finite and positive")
		t.throws(function()
			build(1.5, 1.5)
		end, "scanIntervalSeconds must be below durationSeconds")
		t.throws(function()
			build(1.5, 2)
		end, "scanIntervalSeconds must be below durationSeconds")
	end)

	t.test(
		"rule 1 spec-lock: the driver requires nothing but the config, and takes its registry by injection",
		function()
			-- FOUND-05's guarded prefixes name only the server gameplay modules, so this is the check that the
			-- driver has no require path to cosmetics or shop code.
			local source = fs.readFile("src/shared/Card/Flourish.luau")
			local requires = 0
			for target in string.gmatch(source, 'require%("([^"]*)"%)') do
				requires += 1
				t.equal(target, "../Config/Card", `Flourish requires {target}`)
			end
			t.equal(requires, 1, "non-vacuity: requires examined")
			local lowered = string.lower(source)
			t.falsy(
				string.find(lowered, 'require%("[^"]*shop') ~= nil
					or string.find(lowered, 'require%("[^"]*cosmetic') ~= nil,
				"Flourish requires a shop or cosmetics module"
			)
			t.truthy(
				string.find(source, "registry: { [string]: Entry }", 1, true) ~= nil,
				"registry is no longer injected"
			)
			t.truthy(Card.FLOURISH_DURATION_SECONDS == DURATION and Card.FLOURISH_SCAN_INTERVAL_SECONDS == SCAN)
		end
	)
end
