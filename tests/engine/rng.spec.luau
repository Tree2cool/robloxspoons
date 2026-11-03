--!strict
local Fuzz = require("../harness/Fuzz")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")

local function draw(seed: number, n: number): { number }
	local rng = Rng.new(seed)
	local out: { number } = {}
	for _ = 1, n do
		table.insert(out, rng:nextUint())
	end
	return out
end

return function(t: Test.Runner)
	t.test("nextUint matches an independently computed xorshift32 reference", function()
		-- Reference values computed outside Luau (Python, 64-bit ints masked to 32), so this catches a
		-- precision or truncation bug that a self-consistency check could not.
		-- Recomputed in Python after the seed warm-up landed (3 recurrence steps before the first
		-- value is handed out). The recurrence is unchanged, so this still tests the same xorshift32.
		t.deepEqual(draw(1, 5), { 307599695, 2398689233, 745495504, 632435482, 435756210 })
	end)

	t.test("the FIRST draw is uniform across small sequential seeds (warm-up regression)", function()
		-- The defect this guards: xorshift32 seeded directly with a small integer yields a tiny first
		-- output, so `Rng.new(s):nextInt(1, 9)` returned 1 for EVERY seed 1..1000 -- constant, not
		-- merely skewed. It reached here from Phase 1 and would have silently biased this phase's
		-- deals and every seeded simulator trial, because Fisher-Yates spends its first draw on the
		-- last position. Seeds are sequential counters in practice, which is exactly the worst case.
		local N = 2000
		local counts: { number } = {}
		for v = 1, 9 do
			counts[v] = 0
		end
		for seed = 1, N do
			local v = Rng.new(seed):nextInt(1, 9)
			counts[v] += 1
		end
		local expected = N / 9
		local chi = 0
		for v = 1, 9 do
			local d = counts[v] - expected
			chi += (d * d) / expected
		end
		-- 8 degrees of freedom: 20.09 is p=0.01. Unfixed this value is ~13051, so the bar is not
		-- delicate -- it separates "constant" from "uniform" by three orders of magnitude.
		t.truthy(chi < 20.09, `first-draw chi-square {chi} over {N} seeds; expected < 20.09`)
	end)

	t.test("same seed gives an identical sequence, run twice", function()
		t.deepEqual(draw(12345, 200), draw(12345, 200))
	end)

	t.test("different seeds diverge within 10 draws", function()
		local a, b = draw(1, 10), draw(2, 10)
		local differs = false
		for i = 1, 10 do
			if a[i] ~= b[i] then
				differs = true
			end
		end
		t.truthy(differs, "seeds 1 and 2 produced the same first 10 values")
	end)

	t.test("a zero seed is normalised and does not get stuck at zero", function()
		t.deepEqual(draw(0, 2), { 25405621, 3862129951 })
		t.truthy(draw(0, 50)[50] ~= 0)
	end)

	t.test("nextInt stays inside [lo, hi] inclusive, including lo == hi", function()
		local rng = Rng.new(7)
		for _ = 1, 5000 do
			local x = rng:nextInt(3, 9)
			t.truthy(x >= 3 and x <= 9 and x % 1 == 0, `nextInt(3, 9) returned {x}`)
		end
		for _ = 1, 100 do
			t.equal(rng:nextInt(4, 4), 4)
		end
	end)

	t.test("nextNumber is in [0, 1): never 1, never negative, never NaN", function()
		local rng = Rng.new(99)
		for _ = 1, 5000 do
			local x = rng:nextNumber()
			t.truthy(x == x, "NaN")
			t.truthy(x >= 0 and x < 1, `nextNumber returned {x}`)
		end
	end)

	t.test("10000 draws of nextInt(0, 1) produce both values", function()
		local rng = Rng.new(5)
		local seen = { [0] = 0, [1] = 0 }
		for _ = 1, 10000 do
			local x = rng:nextInt(0, 1)
			seen[x] += 1
		end
		t.truthy(seen[0] > 0 and seen[1] > 0, "generator is stuck on one value")
		t.truthy(seen[0] > 4000 and seen[1] > 4000, `badly skewed: {seen[0]} / {seen[1]}`)
	end)

	t.test("a failing fuzz property reports the iteration and the seed", function()
		local ok, err = pcall(function()
			Fuzz.driver("always-fails-at-3", {
				iterations = 10,
				gen = function(_rng, i)
					return i
				end,
				check = function(v)
					assert(v < 3, "boom")
				end,
			}, 4242)
		end)
		t.falsy(ok, "a failing property must raise")
		t.contains(tostring(err), "iteration 3")
		t.contains(tostring(err), "seed 4242")
		t.contains(tostring(err), "boom")
	end)

	t.test("fuzz opts.seed overrides the runner seed, and replays identically", function()
		local first: { number } = {}
		local second: { number } = {}
		local function record(into: { number }): Test.FuzzOpts
			return {
				seed = 77,
				iterations = 5,
				gen = function(rng, _i)
					return rng:nextUint()
				end,
				check = function(v)
					table.insert(into, v)
				end,
			}
		end
		Fuzz.driver("replay-a", record(first), 1)
		Fuzz.driver("replay-b", record(second), 999)
		t.equal(#first, 5)
		t.deepEqual(first, second)
	end)

	t.fuzz("nextInt always lands in range", {
		iterations = 2000,
		gen = function(rng, _i)
			return { lo = rng:nextInt(-50, 50), span = rng:nextInt(0, 99), draw = rng }
		end,
		check = function(v)
			local hi = v.lo + v.span
			local x = v.draw:nextInt(v.lo, hi)
			assert(x >= v.lo and x <= hi and x % 1 == 0, `out of range: {x}`)
		end,
	})
end
