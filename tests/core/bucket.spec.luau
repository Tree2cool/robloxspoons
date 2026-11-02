--!strict
-- FOUND-04 / threats T-1-02 and T-1-28. Time is driven by the harness FakeClock, never by sleeping:
-- refill is proven by advancing the injected clock. Rejections are asserted by their observable effect
-- (the verdict plus the rejection tally), and the clock-abuse cases additionally prove the bucket's state
-- was left untouched by checking how many tokens are available afterwards.
local Bucket = require("../../src/server/core/Bucket")
local FakeClock = require("../harness/FakeClock")
local RateLimits = require("../../src/shared/Config/RateLimits")
local Test = require("../harness/Test")

local NAN: number = 0 / 0
local INF: number = math.huge

local SPEC: Bucket.Spec = { burst = 3, refillPerSecond = 1 }

return function(t: Test.Runner)
	-- Take up to `attempts` times at the current instant and return how many were granted.
	local function granted(
		store: Bucket.Store,
		userId: number,
		intent: string,
		spec: Bucket.Spec,
		attempts: number
	): number
		local n = 0
		for _ = 1, attempts do
			if store:take(userId, intent, spec) then
				n += 1
			end
		end
		return n
	end

	t.test("a burst of 3 is allowed at t=0 and the 4th is rejected", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		t.equal(store:take(1, "Ping", SPEC), true, "take 1")
		t.equal(store:take(1, "Ping", SPEC), true, "take 2")
		t.equal(store:take(1, "Ping", SPEC), true, "take 3")
		t.equal(store:take(1, "Ping", SPEC), false, "take 4 must be dropped")
		t.equal(store:rejections(), 1, "exactly one rejection so far")
	end)

	t.test("refill over time: nothing at t+0.5, one token at t+1, three at t+3 (FakeClock, no sleeping)", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		t.equal(granted(store, 1, "Ping", SPEC, 3), 3, "burst")
		t.equal(store:take(1, "Ping", SPEC), false, "empty at t=0")

		clock.advance(0.5)
		t.equal(store:take(1, "Ping", SPEC), false, "half a token is not a token")
		clock.advance(0.5)
		t.equal(store:take(1, "Ping", SPEC), true, "one full second buys exactly one token")
		t.equal(store:take(1, "Ping", SPEC), false, "and only one")

		clock.advance(3)
		t.equal(granted(store, 1, "Ping", SPEC, 10), 3, "three seconds buy three tokens")
	end)

	t.test("the cap holds: after a long idle only burst tokens are available, never more", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		t.equal(granted(store, 1, "Ping", SPEC, 3), 3)
		clock.advance(10)
		t.equal(granted(store, 1, "Ping", SPEC, 10), 3, "10s idle must cap at burst (3), not 10")
		clock.advance(1e6)
		t.equal(granted(store, 1, "Ping", SPEC, 10), 3, "a huge idle must still cap at burst")
	end)

	t.test("tokens never go below zero: a flood of rejected takes costs nothing", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		t.equal(granted(store, 1, "Ping", SPEC, 3), 3)
		t.equal(granted(store, 1, "Ping", SPEC, 100), 0, "100 more are all dropped")
		t.equal(store:rejections(), 100, "every drop is tallied")
		-- If rejected takes had driven the balance negative, one second of refill would not be enough.
		clock.advance(1)
		t.equal(store:take(1, "Ping", SPEC), true, "one second after a flood still buys one token")
		t.equal(store:take(1, "Ping", SPEC), false)
	end)

	t.test("a new bucket starts full: the first take at a late clock reading still has the whole burst", function()
		local clock = FakeClock.new()
		clock.advance(500)
		local store = Bucket.new({ clock = clock })
		t.equal(granted(store, 1, "Ping", SPEC, 10), 3)
	end)

	t.test("users are isolated: A exhausting their bucket does not touch B", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		t.equal(granted(store, 1, "Ping", SPEC, 10), 3, "A drains")
		t.equal(granted(store, 2, "Ping", SPEC, 10), 3, "B is untouched and has a full burst")
		t.equal(store:take(1, "Ping", SPEC), false, "A is still empty")
		t.equal(store:count(), 2, "two users tracked")
	end)

	t.test("the same user has independent buckets per intent", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		t.equal(granted(store, 1, "Ping", SPEC, 10), 3)
		t.equal(store:take(1, "Ping", SPEC), false, "Ping is empty")
		t.equal(granted(store, 1, "Other", SPEC, 10), 3, "a different intent has its own full bucket")
		t.equal(store:count(), 1, "still one user")
	end)

	t.test("forget frees every bucket for that user and a take after it behaves like a fresh user", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		granted(store, 1, "Ping", SPEC, 10)
		granted(store, 1, "Other", SPEC, 10)
		granted(store, 2, "Ping", SPEC, 1)
		t.equal(store:count(), 2)

		store:forget(1)
		t.equal(store:count(), 1, "user 1's state is freed")
		t.equal(granted(store, 1, "Ping", SPEC, 10), 3, "Ping is a fresh full bucket")
		t.equal(granted(store, 1, "Other", SPEC, 10), 3, "Other is a fresh full bucket")
		t.equal(granted(store, 2, "Ping", SPEC, 10), 2, "user 2 was not forgotten: 1 of 3 already used")

		store:forget(999) -- never seen: a no-op, never an error
		store:forget(1)
		store:forget(2)
		t.equal(store:count(), 0, "everyone forgotten")
	end)

	t.test("the rejection tally is monotonic and a grant does not move it", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		t.equal(store:rejections(), 0)
		granted(store, 1, "Ping", SPEC, 3)
		t.equal(store:rejections(), 0, "grants are not rejections")
		local last = store:rejections()
		for _ = 1, 20 do
			store:take(1, "Ping", SPEC)
			t.truthy(store:rejections() >= last, "tally went backwards")
			last = store:rejections()
		end
		t.equal(last, 20)
		store:forget(1)
		t.equal(store:rejections(), 20, "forget must not reset the tally")
	end)

	t.test("a clock that goes backwards grants nothing and leaves last unchanged", function()
		local clock = FakeClock.new()
		clock.advance(5)
		local store = Bucket.new({ clock = clock })
		t.equal(granted(store, 1, "Ping", SPEC, 3), 3, "drain at t=5")
		t.equal(store:rejections(), 0)

		clock.advance(-3) -- t = 2, earlier than last = 5
		t.equal(store:take(1, "Ping", SPEC), false, "backwards clock must not grant")
		t.equal(store:rejections(), 1, "and is tallied")

		-- If `last` had been overwritten with 2, t=6 would look like 4 seconds of refill and grant 3.
		-- Left at 5 it is 1 second of refill: exactly one token.
		clock.advance(4) -- t = 6
		t.equal(granted(store, 1, "Ping", SPEC, 10), 1, "refill is measured from the original last, so exactly 1 token")
	end)

	t.test("a backwards clock is refused even when tokens ARE available", function()
		-- The drained-bucket case above cannot tell "refused because the clock went backwards" from
		-- "refused because the bucket was empty". Here two tokens remain, so only the clock rule can
		-- be what rejects the take.
		local clock = FakeClock.new()
		clock.advance(5)
		local store = Bucket.new({ clock = clock })
		t.equal(store:take(1, "Ping", SPEC), true, "t=5, 2 tokens remain")

		clock.advance(-0.5) -- t = 4.5
		t.equal(store:take(1, "Ping", SPEC), false, "must be refused despite 2 tokens being available")
		t.equal(store:rejections(), 1, "and tallied as a rejection")

		clock.advance(0.5) -- back to t = 5: the same two tokens are still there, none were burned
		t.equal(granted(store, 1, "Ping", SPEC, 10), 2, "the refused take cost nothing")
	end)

	t.test(
		"last is tracked per pair: a new pair read at an earlier instant than another pair's last still works",
		function()
			local current = 10
			local store = Bucket.new({
				clock = {
					now = function()
						return current
					end,
				},
			})
			t.equal(store:take(1, "Ping", SPEC), true, "t=10 establishes last")
			current = 1
			-- A different, brand new pair read while the clock is behind another pair's reading is legal:
			-- it has no `last` to be behind. It must simply work like any new bucket.
			t.equal(store:take(2, "Ping", SPEC), true, "new user, valid positive reading")
		end
	)

	t.test("a non-finite or negative clock reading grants nothing and does not poison the bucket", function()
		local current = 0
		local store = Bucket.new({
			clock = {
				now = function()
					return current
				end,
			},
		})
		t.equal(granted(store, 1, "Ping", SPEC, 3), 3, "drain at t=0")
		local before = store:rejections()

		local bad: { { label: string, value: number } } = {
			{ label = "NaN", value = NAN },
			{ label = "+inf", value = INF },
			{ label = "-inf", value = -INF },
			{ label = "negative", value = -1 },
		}
		for _, reading in bad do
			current = reading.value
			t.equal(store:take(1, "Ping", SPEC), false, `{reading.label}: must not grant to a drained bucket`)
			t.equal(store:take(99, "Ping", SPEC), false, `{reading.label}: must not grant to a never-seen user`)
		end
		t.equal(store:rejections(), before + 8, "all 8 bad-clock takes are tallied")
		t.equal(store:count(), 1, "a bad reading must not allocate state for the never-seen user")

		-- +inf would have produced an infinite refill had it been accepted and stored. State untouched
		-- means t=0 -> t=1 is a normal 1-token refill.
		current = 1
		t.equal(granted(store, 1, "Ping", SPEC, 10), 1, "after the abuse, exactly one second of refill")
	end)

	t.test("a malformed spec or user id grants nothing and never throws", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		local badSpecs: { Bucket.Spec } = {
			{ burst = NAN, refillPerSecond = 1 },
			{ burst = INF, refillPerSecond = 1 },
			{ burst = 3, refillPerSecond = NAN },
			{ burst = 3, refillPerSecond = INF },
			{ burst = -1, refillPerSecond = 1 },
			{ burst = 3, refillPerSecond = -1 },
		}
		for i, spec in badSpecs do
			local ok, verdict = pcall(function()
				return store:take(1, "Ping", spec)
			end)
			t.equal(ok, true, `bad spec {i} must not throw`)
			t.equal(verdict, false, `bad spec {i} must not grant`)
		end
		local ok, verdict = pcall(function()
			return store:take(NAN, "Ping", SPEC)
		end)
		t.equal(ok, true, "a NaN user id must not throw (NaN is not a legal table key)")
		t.equal(verdict, false, "a NaN user id must not grant")
		t.equal(store:count(), 0, "none of that allocated state")
	end)

	t.test("it drops rather than queues: a long flood leaves state at one entry per user and intent", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		for _ = 1, 5000 do
			store:take(1, "Ping", SPEC)
		end
		t.equal(store:count(), 1)
		t.equal(store:rejections(), 4997, "5000 takes, 3 granted, the rest dropped")
	end)

	t.test("RateLimits: every spec is finite with at least one burst token and positive refill", function()
		local specs: { Bucket.Spec } = { RateLimits.default }
		for name in RateLimits.byIntent do
			table.insert(specs, RateLimits.forIntent(name))
		end
		t.truthy(#specs >= 2, "default plus at least Ping")
		for i, spec in specs do
			t.truthy(spec.burst == spec.burst and spec.burst >= 1 and spec.burst < INF, `spec {i} burst`)
			t.truthy(
				spec.refillPerSecond == spec.refillPerSecond and spec.refillPerSecond > 0 and spec.refillPerSecond < INF,
				`spec {i} refill`
			)
		end
	end)

	t.test("RateLimits.forIntent: Ping has its own entry and an unknown name falls back to default", function()
		t.deepEqual(RateLimits.forIntent("Ping"), { burst = 2, refillPerSecond = 1 })
		t.equal(RateLimits.forIntent("NoSuchIntent"), RateLimits.default, "unknown names use default")
		t.deepEqual(RateLimits.default, { burst = 4, refillPerSecond = 4 })
	end)

	t.test("the real Ping limit works end to end with the bucket", function()
		local clock = FakeClock.new()
		local store = Bucket.new({ clock = clock })
		local spec = RateLimits.forIntent("Ping")
		t.equal(granted(store, 1, "Ping", spec, 10), 2, "Ping burst is 2")
		clock.advance(1)
		t.equal(granted(store, 1, "Ping", spec, 10), 1, "and refills at 1 per second")
	end)

	t.fuzz("grants never exceed burst + refill * elapsed, for any sequence of takes and waits", {
		iterations = 200,
		gen = function(rng: any, _i: number): any
			local ops: { number } = {}
			for _ = 1, 60 do
				-- Quarter-second steps keep the float arithmetic exact. 0 means "take now".
				table.insert(ops, rng:nextInt(0, 8) / 4)
			end
			return ops
		end,
		check = function(ops: any)
			local clock = FakeClock.new()
			local store = Bucket.new({ clock = clock })
			local total = 0
			local elapsed = 0
			for _, step in ops do
				clock.advance(step)
				elapsed += step
				if store:take(1, "Ping", SPEC) then
					total += 1
				end
			end
			local allowance = SPEC.burst + SPEC.refillPerSecond * elapsed
			t.truthy(total <= allowance, `granted {total} but only {allowance} were ever available`)
		end,
	})
end
