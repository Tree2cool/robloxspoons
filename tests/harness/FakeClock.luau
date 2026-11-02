--!strict
-- Injected wall clock for tests. Seconds, starts at 0, moves only when told to. No yields.
export type FakeClock = { now: () -> number, advance: (seconds: number) -> () }

local function new(): FakeClock
	local t = 0
	return {
		now = function()
			return t
		end,
		advance = function(seconds: number)
			t += seconds
		end,
	}
end

return { new = new }
