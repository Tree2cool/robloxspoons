--!strict
-- Pure, synchronous, Roblox-API-free (FOUND-06). xorshift32 via bit32: no multiplies, so no
-- double-precision loss (Luau numbers are doubles; a 32-bit multiply silently goes wrong above 2^53).
-- Deterministic from a seed so fuzz failures are reproducible.
export type Rng = {
	nextUint: (self: Rng) -> number,
	nextNumber: (self: Rng) -> number,
	nextInt: (self: Rng, lo: number, hi: number) -> number,
}

local TWO_POW_32 = 4294967296
local ZERO_STATE_REPLACEMENT = 0x9E3779B9

-- Seed warm-up. xorshift32 seeded directly with a small integer produces a tiny first output, so
-- the first draw is not merely skewed, it is CONSTANT: before this, `Rng.new(s):nextInt(1, 9)`
-- returned 1 for every one of the seeds 1..1000. That matters because the shuffles and simulator
-- trials in this phase are seeded with small sequential counters, and Fisher-Yates spends its very
-- first draw on the last position -- so every round would have placed the same element in the same
-- seat. Running the recurrence a few times before any value is handed out fixes it: measured over
-- seeds 1..2000, the first `nextInt(1, 9)` goes from chi-square 13051.60 (counts 1820,180,0,...)
-- to 0.05 at three steps. The recurrence itself is unchanged, so the reference vectors in
-- rng.spec.luau still test the same xorshift32; they advance by exactly WARM_UP_STEPS.
local WARM_UP_STEPS = 3

local function new(seed: number): Rng
	-- bit32.bor truncates to an unsigned 32-bit integer; xorshift32 is stuck at 0, so replace a zero state.
	local state = bit32.bor(seed, 0)
	if state == 0 then
		state = ZERO_STATE_REPLACEMENT
	end

	local function step(): number
		local x = state
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
		state = x
		return x
	end

	for _ = 1, WARM_UP_STEPS do
		step()
	end

	local function nextUint(_self: Rng): number
		return step()
	end

	local function nextNumber(self: Rng): number
		return self:nextUint() / TWO_POW_32
	end

	local function nextInt(self: Rng, lo: number, hi: number): number
		local value = lo + math.floor(self:nextNumber() * (hi - lo + 1))
		if value > hi then
			return hi -- cannot happen for a [0, 1) draw, but the contract is "never above hi"
		end
		return value
	end

	return {
		nextUint = nextUint,
		nextNumber = nextNumber,
		nextInt = nextInt,
	}
end

return { new = new }
