--!strict
-- Round timing caps. PROJECT.md: "5:00 cap on the card/hunt phase plus <=90s hide phase, with
-- round end firing immediately on the last claim." The 300s figure is a CAP, not a duration.
return {
	ROUND_CAP_SECONDS = 300,
	HIDE_CAP_SECONDS = 90,
	DECISECONDS_PER_SECOND = 10,
}
