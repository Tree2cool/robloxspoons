--!strict
-- Roster admission (FOUND-08). PURE ZONE: no Roblox API. The adapter supplies the live count and
-- the configured cap; this module makes the decision.
--
-- Exactly two functions are exported. `canStartMatch` is the ONLY predicate that may say a match can
-- begin: a second one would be a second way to start a match.
export type Reason = "Ok" | "ServerFull" | "InvalidInput"
export type Decision = { admit: boolean, reason: Reason }

-- Deliberate duplication of the finite-integer check in src/shared/Net/Validate.luau. Requiring it
-- from here would be a cross-mount require (src/server -> src/shared), which resolves on disk and
-- fails in the DataModel (guard rule R6). Four lines are cheaper than a dependency injection seam.
-- `type(v) == "number"` first so nil, strings and booleans are rejected rather than coerced.
local function isCount(v: any, minimum: number): boolean
	if type(v) ~= "number" then
		return false
	end
	local num = v :: number
	-- v == v rejects NaN; the inf comparisons reject both infinities; num % 1 == 0 rejects fractions.
	return v == v and v ~= math.huge and v ~= -math.huge and num % 1 == 0 and num >= minimum
end

-- `currentCount` is the number of players already present (before the joiner is counted).
local function decide(currentCount: number, cap: number): Decision
	if not isCount(currentCount, 0) or not isCount(cap, 1) then
		return { admit = false, reason = "InvalidInput" }
	end
	if currentCount < cap then
		return { admit = true, reason = "Ok" }
	end
	return { admit = false, reason = "ServerFull" }
end

-- Returns false rather than erroring on bad input: a bad input must never start a match.
local function canStartMatch(readyCount: number, min: number): boolean
	if not isCount(readyCount, 0) or not isCount(min, 1) then
		return false
	end
	return readyCount >= min
end

return {
	decide = decide,
	canStartMatch = canStartMatch,
}
