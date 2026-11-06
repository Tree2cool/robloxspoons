--!strict
-- PURE ZONE: no Roblox API, no clock read, no imports. Arithmetic over two numbers.
--
-- WHY THIS IS A FUNCTION AND NOT AN EXPRESSION IN THE ADAPTER. CLAUDE.md rule 5 wants exactly one
-- conversion site, and `src/server/services/CardService.luau` is the right place to CALL it --
-- that is where the config values are read by absolute DataModel path (guard R6). But `CardService`
-- names `game:GetService`, so Lune cannot load it, which means an expression written inline there
-- is testable by nothing: a spec can only recompute the formula (and then the two can drift without
-- either failing) or grep for its text (and then a COMMENT satisfies the grep while the code does
-- something else -- the defect class that bit this project four times in Phase 3).
--
-- So the arithmetic lives here, where a spec can drive it, and the adapter remains the single
-- CALLER. One site, and a reachable gate. tests/card/config_lock.spec.luau drives this function
-- directly; tests/card/cardtable.spec.luau proves its result reaches IdleClock.
--
-- THE EPSILON AND THE FLOOR ARE BOTH LOAD-BEARING. `0.7 * 10` is 7.000000000000001 in IEEE double,
-- so a ceil or a round would produce 8 and exceed a ceiling the owner locked. Floor-with-epsilon
-- can never exceed `seconds * perSecond`, which is what D-13 requires of the CONFIGURED value.

local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function autoPassDeci(maxSeconds: number, decisPerSecond: number): number
	-- A NaN deadline can never be reached (NaN fails every comparison), so the AFK clock would
	-- silently never fire. Refuse by name instead.
	if not isFinite(maxSeconds) or maxSeconds <= 0 then
		error("CardTiming.autoPassDeci: maxSeconds must be finite and positive")
	end
	if not isFinite(decisPerSecond) or decisPerSecond <= 0 or decisPerSecond ~= math.floor(decisPerSecond) then
		error("CardTiming.autoPassDeci: decisPerSecond must be a finite positive integer")
	end
	return math.floor(maxSeconds * decisPerSecond + 1e-9)
end

return { autoPassDeci = autoPassDeci }
