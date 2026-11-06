--!strict
-- Rate-limit shape and starting numbers for the single gateway (FOUND-04).
-- LOW CONFIDENCE: these values are starting points to be tuned in playtest (research V-34).
-- The Phase 4 debt re-check found the documented platform ceiling (~500 requests/second/client, with
-- RemoteEvent excess delayed in order, not dropped); that did NOT close V-34, because the docs give no
-- gameplay-appropriate number.
-- They are parameters everywhere, never inlined, so tuning is a one-file change.
export type Spec = { burst: number, refillPerSecond: number }

local RateLimits = {}

RateLimits.default = { burst = 4, refillPerSecond = 4 } :: Spec

RateLimits.byIntent = {
	Ping = { burst = 2, refillPerSecond = 1 },
	-- LOW CONFIDENCE (V-34). `Bucket` is keyed per (userId, intent), so Draw and Pass get SEPARATE
	-- buckets and a pass flurry cannot starve a draw. These are starting values for Phase 8 tuning,
	-- not measured.
	--
	-- Sizing argument, recorded so Phase 8 tunes from a premise rather than a guess: a seat can
	-- only draw at hand 4 and only pass at hand 5, so legal actions strictly alternate. The peak
	-- measured table-wide rate is ~20 actions/second across 10 seats (~2/second/seat) during the
	-- start-up ramp. 6/second with a burst of 8 is comfortably above any human and ~60x below the
	-- platform ceiling. A rejection here is NOT free: it never reaches the card core, so the
	-- client's pending entry is only resolved by the age watchdog, which is a visible card return.
	-- Err generous.
	Draw = { burst = 8, refillPerSecond = 6 },
	Pass = { burst = 8, refillPerSecond = 6 },
} :: { [string]: Spec }

function RateLimits.forIntent(name: string): Spec
	return RateLimits.byIntent[name] or RateLimits.default
end

return RateLimits
