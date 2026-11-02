--!strict
-- Persistence mode selection (FOUND-07). PURE ZONE: no Roblox API - the adapter reads
-- DataStoreState, IsStudio and GameId and passes them in, so the decision is unit-testable.
--
-- Isolation is a platform fact (a separate experience, D-13). The IsStudio check below is
-- SECONDARY defence in depth, never the mechanism.
--
-- FAIL CLOSED: Real is returned in exactly one situation (state is exactly "Access" and the Studio
-- tripwire did not fire). Anything unrecognised, missing or malformed selects Mock, because "unknown"
-- is not "proven safe". Mock never touches a real store, so it cannot overwrite a real profile.
export type State = "NotReady" | "NoInternet" | "NoAccess" | "Access"
export type Mode = "Real" | "Mock" | "Refuse"
export type Input = {
	dataStoreState: string,
	isStudio: boolean,
	gameId: number,
	productionUniverseId: number,
}

local function decide(input: Input): Mode
	-- 1. Refuse FIRST so it wins over Mock. A Studio session aimed at the production universe is a
	--    configuration error and must fail loudly rather than quietly degrade. productionUniverseId
	--    of 0 is the un-filled placeholder (owner gate M-04) and never matches a real GameId, so it
	--    cannot refuse an unrelated session.
	if input.isStudio == true and input.productionUniverseId ~= 0 and input.gameId == input.productionUniverseId then
		return "Refuse"
	end

	-- 2. Mock unless access is proven. Exact string match: "access", "" and nil all fall here.
	if input.dataStoreState ~= "Access" then
		return "Mock"
	end

	-- 3. Real.
	return "Real"
end

return {
	decide = decide,
}
