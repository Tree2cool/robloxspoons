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

local function new(seed: number): Rng
	-- bit32.bor truncates to an unsigned 32-bit integer; xorshift32 is stuck at 0, so replace a zero state.
	local state = bit32.bor(seed, 0)
	if state == 0 then
		state = ZERO_STATE_REPLACEMENT
	end

	local function nextUint(_self: Rng): number
		local x = state
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
		state = x
		return x
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
