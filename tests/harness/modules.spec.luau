--!strict
-- Specs for the harness's own building blocks. Each case builds an INNER runner and drives it by hand,
-- so a failure here is a failure of Test/FakeClock/FakeScheduler, not of the inner scenario.
local FakeClock = require("./FakeClock")
local FakeScheduler = require("./FakeScheduler")
local Test = require("./Test")

local function failureOf(fn: () -> ()): string?
	local ok, err = pcall(fn :: () -> any)
	if ok then
		return nil
	end
	return tostring(err)
end

return function(t: Test.Runner)
	t.test("Test.new records tests and todos without running them", function()
		local inner = Test.new()
		local ran = false
		inner.test("a", function()
			ran = true
		end)
		inner.todo("later")
		t.equal(#inner.cases, 1)
		t.equal(inner.cases[1].name, "a")
		t.deepEqual(inner.todos, { "later" })
		t.falsy(ran, "registering a case must not run it")
		t.equal(inner.seed, 1, "default seed is 1")
		t.equal(Test.new({ seed = 77 }).seed, 77)
	end)

	t.test("equal passes on equal values and reports both values on mismatch", function()
		local inner = Test.new()
		t.equal(
			failureOf(function()
				inner.equal(1, 1)
			end),
			nil
		)
		local msg = failureOf(function()
			inner.equal(1, 2)
		end)
		t.truthy(msg, "equal(1, 2) must fail")
		t.contains(msg :: string, "expected 2, got 1")
		local withMsg = failureOf(function()
			inner.equal("a", "b", "custom")
		end)
		t.contains(withMsg :: string, "custom")
	end)

	t.test("throws passes only when the function errors with the substring", function()
		local inner = Test.new()
		t.equal(
			failureOf(function()
				inner.throws(function()
					error("kaboom happened")
				end, "kaboom")
			end),
			nil
		)
		t.truthy(failureOf(function()
			inner.throws(function() end)
		end))
		t.truthy(failureOf(function()
			inner.throws(function()
				error("other")
			end, "kaboom")
		end))
	end)

	t.test("deepEqual walks tables, rejects extra and missing keys, and caps depth", function()
		local inner = Test.new()
		t.equal(
			failureOf(function()
				inner.deepEqual({ a = { 1, 2 }, b = "x" }, { a = { 1, 2 }, b = "x" })
			end),
			nil
		)
		t.truthy(failureOf(function()
			inner.deepEqual({ a = 1 }, { a = 1, b = 2 })
		end))
		t.truthy(failureOf(function()
			inner.deepEqual({ a = 1, b = 2 }, { a = 1 })
		end))
		local deepA: any = {}
		local deepB: any = {}
		local cursorA, cursorB = deepA, deepB
		for _ = 1, 12 do
			cursorA.n = {}
			cursorB.n = {}
			cursorA, cursorB = cursorA.n, cursorB.n
		end
		t.contains(
			failureOf(function()
				inner.deepEqual(deepA, deepB)
			end) :: string,
			"depth cap"
		)
	end)

	t.test("contains is a plain find, not a pattern match", function()
		local inner = Test.new()
		t.equal(
			failureOf(function()
				inner.contains("a.b", ".")
			end),
			nil
		)
		t.truthy(failureOf(function()
			inner.contains("abc", ".")
		end))
	end)

	t.test("fuzz without an injected driver registers a case that fails loudly", function()
		local inner = Test.new()
		inner.fuzz("prop", {
			gen = function(_rng, _i)
				return 1
			end,
			check = function(_v) end,
		})
		t.equal(#inner.cases, 1, "fuzz registers exactly one case")
		local msg = failureOf(inner.cases[1].fn)
		t.truthy(msg, "a missing driver must fail, never skip")
		t.contains(msg :: string, "fuzz driver not installed")
	end)

	t.test("fuzz with an injected driver passes the name, opts and seed through", function()
		local seen: { any } = {}
		local inner = Test.new({
			seed = 9,
			fuzzDriver = function(name, opts, seed)
				seen = { name, opts, seed }
			end,
		})
		local opts: Test.FuzzOpts = {
			gen = function(_rng, _i)
				return 1
			end,
			check = function(_v) end,
		}
		inner.fuzz("prop", opts)
		inner.cases[1].fn()
		t.equal(seen[1], "prop")
		t.equal(seen[2], opts)
		t.equal(seen[3], 9)
	end)

	t.test("FakeClock starts at zero and advances", function()
		local c = FakeClock.new()
		t.equal(c.now(), 0)
		c.advance(2.5)
		t.equal(c.now(), 2.5)
		c.advance(0.5)
		t.equal(c.now(), 3)
	end)

	t.test("FakeScheduler fires due delays in due-time order, exactly once each", function()
		local s = FakeScheduler.new()
		local fired: { string } = {}
		s.delay(5, function()
			table.insert(fired, "five")
		end)
		s.delay(1, function()
			table.insert(fired, "one")
		end)
		s.delay(1, function()
			table.insert(fired, "one-b")
		end)
		s.delay(20, function()
			table.insert(fired, "twenty")
		end)
		t.equal(s.nowDeci(), 0)
		t.equal(s.pending(), 4)
		s.advance(10)
		t.deepEqual(fired, { "one", "one-b", "five" })
		t.equal(s.nowDeci(), 100, "time is stored in integer deciseconds")
		t.equal(s.pending(), 1)
		s.advance(10)
		t.deepEqual(fired, { "one", "one-b", "five", "twenty" })
		s.advance(100)
		t.equal(#fired, 4, "nothing fires twice")
	end)

	t.test("FakeScheduler cancel prevents a callback unless cancelIsNoop is set", function()
		local working = FakeScheduler.new()
		local ranWorking = false
		local cancel = working.delay(1, function()
			ranWorking = true
		end)
		cancel()
		working.advance(5)
		t.falsy(ranWorking, "a working cancel stops the callback")
		t.equal(working.pending(), 0)

		local broken = FakeScheduler.new({ cancelIsNoop = true })
		local ranBroken = false
		local noop = broken.delay(1, function()
			ranBroken = true
		end)
		noop()
		broken.advance(5)
		t.truthy(ranBroken, "with cancelIsNoop the stale callback still fires")
	end)

	t.test("FakeScheduler callbacks that schedule more work cannot re-fire themselves", function()
		local s = FakeScheduler.new()
		local count = 0
		local function tick()
			count += 1
			if count < 3 then
				s.delay(1, tick)
			end
		end
		s.delay(1, tick)
		s.advance(1)
		t.equal(count, 1, "a callback scheduled for later does not fire inside the same instant")
		s.advance(5)
		t.equal(count, 3)
		t.equal(s.pending(), 0)
	end)
end
