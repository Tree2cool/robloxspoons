--!strict
-- Universe and place identifiers. Data stores are consistent per EXPERIENCE, so isolation means a
-- separate universe (D-13), not a separate place. These are 0 until the owner completes the
-- Creator Hub gate (MANUAL-CHECKS M-04); plan 01-12 fills them in.
return {
	PRODUCTION_UNIVERSE_ID = 0,
	DEV_UNIVERSE_ID = 0,
	DEV_PLACE_ID = 0,
}
