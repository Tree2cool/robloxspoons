--!strict
-- Universe and place identifiers. Data stores are consistent per EXPERIENCE, so isolation means a
-- separate universe (D-13), not a separate place.
--
-- Filled in from MANUAL-CHECKS M-04 on 2026-11-03. The dev experience was created on the Creator
-- Hub and the place uploaded with "Save to Roblox As" (Studio's Publish As failed repeatedly with
-- a bare "Save failed"; creating the experience on the web first and uploading into it worked).
-- "Enable Studio Access to API Services" is ON for the dev experience.
--
-- PRODUCTION_UNIVERSE_ID is still 0 because no production experience exists yet. A zero here is
-- safe, not a gap: the Studio tripwire requires BOTH a Studio session AND a non-zero production id
-- equal to game.GameId, so a placeholder zero never refuses an unrelated session. Set it the moment
-- a production experience exists, or the tripwire protects nothing.
return {
	PRODUCTION_UNIVERSE_ID = 0,
	DEV_UNIVERSE_ID = 10774453248,
	DEV_PLACE_ID = 123236339661606,
}
