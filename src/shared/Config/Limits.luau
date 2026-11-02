--!strict
-- Roster limits. `Players.MaxPlayers` is ReadOnly in script and can only be set in the place's
-- settings on the Creator Dashboard, so the platform cap is a human step (MANUAL-CHECKS M-05) and
-- these values are the server-side defence in depth behind it.
return {
	MAX_PLAYERS = 10,
	MIN_PLAYERS_TO_START = 3,
}
