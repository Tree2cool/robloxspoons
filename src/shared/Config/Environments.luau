--!strict
-- Universe and place identifiers. Data stores are consistent per EXPERIENCE, so isolation means a
-- separate universe (D-13), not a separate place.
--
-- Filled in from MANUAL-CHECKS M-04 on 2026-11-03. Two experiences exist:
--
--   SPOONS [BETA]  production  GameId 10774453248  PlaceId 123236339661606
--   Spoons Dev     dev         GameId 10774461969  PlaceId 120922388251092
--
-- Both places were uploaded with "Save to Roblox As" (Studio's "Publish As" failed repeatedly with
-- a bare "Save failed"; creating the experience on the Creator Hub first and uploading into it
-- worked). "Enable Studio Access to API Services" is ON for Spoons Dev and OFF for SPOONS [BETA].
--
-- PRODUCTION_UNIVERSE_ID being non-zero is what makes the Studio tripwire live: PersistenceMode
-- returns Refuse when RunService:IsStudio() and game.GameId == PRODUCTION_UNIVERSE_ID. A zero here
-- would leave it inert, so never reset it to a placeholder.
return {
	PRODUCTION_UNIVERSE_ID = 10774453248,
	-- Recorded so `servePlaceIds` can be asserted against the production PLACE. Comparing a place
	-- id to a universe id is a namespace error: the two id spaces never collide, so such a check
	-- can never fire. Phase 1 verification caught exactly that mistake in project.spec.luau.
	PRODUCTION_PLACE_ID = 123236339661606,
	DEV_UNIVERSE_ID = 10774461969,
	DEV_PLACE_ID = 120922388251092,
}
