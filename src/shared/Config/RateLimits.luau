--!strict
-- Rate-limit shape and starting numbers for the single gateway (FOUND-04).
-- LOW CONFIDENCE: these values are starting points to be tuned in playtest (research V-34).
-- They are parameters everywhere, never inlined, so tuning is a one-file change.
export type Spec = { burst: number, refillPerSecond: number }

local RateLimits = {}

RateLimits.default = { burst = 4, refillPerSecond = 4 } :: Spec

RateLimits.byIntent = {
	Ping = { burst = 2, refillPerSecond = 1 },
} :: { [string]: Spec }

function RateLimits.forIntent(name: string): Spec
	return RateLimits.byIntent[name] or RateLimits.default
end

return RateLimits
