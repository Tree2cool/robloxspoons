--!strict
-- The shipped placement constants. Confirmed by the owner on 2026-11-04 (D-16, D-18), chosen from the
-- measured ladder in
-- .planning/phases/03-placement-rules-map-pipeline-and-validator/03-RESEARCH.md ("The Number Ladder"),
-- which reports for every candidate value which graybox spots it accepts and which it culls. This is the
-- same discipline that selected k = 3 in CardPool.luau: the operating point was chosen with the trade-off
-- visible, then the measurement was re-run at it. These numbers are not open for tuning.
--
-- Nothing under src/ imports this module except MapLoader. Guard rule R6 fails a pure-zone file that
-- reaches across a Rojo mount boundary (tests/guards/fixtures/cross-mount/ proves it), so SpoonPlacement
-- and MapValidator RECEIVE the config as a parameter and never import it. The runtime wiring point is the
-- MapLoader service, which reads it through the DataModel path
-- loading ReplicatedStorage.Shared.Config.Placement, exactly as RoundDriver.luau:18 and
-- Persistence.luau:17 do. The CI CLI and the specs load it by relative path, because scripts and tests
-- are never mounted.
--
-- EYE_HEIGHT is separate from REACH_HEIGHT and that is load-bearing, not tidiness. With one shared height
-- the crate-top spot needs an effective range of 8.75 studs, is culled, and the reference map falls to 15
-- survivors, failing MAP-03. With a separate 4.0 eye height it needs 4.06. The measured need at eye
-- 2.5 / 3.0 / 3.5 / 4.0 is 8.75 / 6.82 / 4.95 / 4.06 studs. Phase 5's hunt must consume this same
-- EYE_HEIGHT and this same PICKUP_RANGE, measured from the same root point, or the shared name means
-- nothing: the server knows only the HumanoidRootPart position and adds these offsets to it.
--
-- PICKUP_RANGE 7.0 was chosen for clean separation, not to rescue a spot. At range 8.0 with margin 1.5 the
-- shelf-edge spot's verdict flips on a 0.04-stud difference, which is a coin toss decided by float32
-- rounding. At 7.0 every authored spot sits at least 1 stud clear of a flip (crate-top 1.44, shelf-edge
-- 1.04). Range 8.5 would buy a seventeenth survivor and was rejected: choosing a gameplay constant to make
-- map validation pass is D-15 running backwards.
--
-- The capsule is biased toward rejecting (D-11): short reach, tall headroom. A single capsule cannot be
-- conservative in both directions; for reach the safe choice is the shortest avatar, for headroom and
-- standability the tallest. This one is deliberately harder to satisfy than any real avatar, so a spot the
-- validator accepts is reachable for everyone. An unfindable spoon stalls a round; a culled spot costs
-- nothing while the map carries margin. CAPSULE_HEIGHT 7.0 means no walkable ceiling below 7 studs, and
-- corridors need width >= 2 * CAPSULE_RADIUS + GRID_SIZE (4.0 at these values); both are authoring rules
-- for the Phase 7a maps. CAPSULE_RADIUS and CAPSULE_HEIGHT change no graybox survivor count across
-- 0.5-2.5 and 5-8. The capsule is per place and never per player (D-10), so no purchase can change it.
--
-- Three invariants, each with its own test in tests/placement/config_lock.spec.luau (not comments, because
-- a comment cannot fail):
--   STEP_UP >= GRID_SIZE * tan(MAX_SLOPE_DEGREES). The graybox ramp is 24.9047 degrees (atan(6.5 / 14)),
--   and the measured minimum STEP_UP for it is exactly GRID_SIZE * tan(24.9047 deg): 0.232 at g=0.5, 0.464
--   at g=1, 0.929 at g=2. At GRID_SIZE 4 with STEP_UP 1.0 the ramp disconnects, the ledge spots go with
--   it, and survivors fall to 11-12.
--   PICKUP_MARGIN >= GRID_SIZE * sqrt(2) / 2. The grid-quantisation error is bounded by the cell
--   half-diagonal: 0.71 at g=1, 1.41 at g=2, 0.35 at g=0.5. The remaining ~0.8 of the 1.5 margin covers
--   controller jitter, imperfect footing and the lag between the real and the server-known root position
--   (V-23, LOW confidence, a Phase 5/8 measurement).
--   CAPSULE_HEIGHT > EYE_HEIGHT >= REACH_HEIGHT. Note the asymmetry, and keep it. An eye at or above the
--   capsule's own height is incoherent, so that comparison is strict. A reach point above the eye is
--   likewise incoherent, but a reach point EQUAL to the eye is the degenerate single-height configuration,
--   and that configuration is the entire justification for EYE_HEIGHT existing as a separate constant:
--   research measured that with one shared reach/eye height the crate-top spot needs an effective range of
--   8.75, is culled, and the reference map falls to 15 survivors. A strict > here would make the exact
--   configuration research measured inexpressible, so the negative control that proves EYE_HEIGHT is
--   load-bearing could not be written. Plan 03-06 case 7 bakes the graybox at EYE_HEIGHT = REACH_HEIGHT =
--   2.5 for precisely that purpose, and plan 03-05's assertConfig uses the same >= on the lower
--   comparison. Do not "tidy" it to >.
--
-- The clearance cliff. SPOT_CLEARANCE >= 0.5 culls all 18 authored graybox spots (v1; 21 after plan
-- 03-06), because the authoring convention puts every anchor exactly 0.5 above its surface. 0.25 is
-- deliberate headroom under a cliff edge, and the spec asserts the cliff exists so nobody rounds it up
-- later. The real driver is the spoon skin template's fixed bounding box (CLAUDE.md rule 4), which is
-- Phase 7b work and does not exist yet: 0.25 is a placeholder to be re-derived when that template lands
-- (research assumption A3).
--
-- MAX_SLOPE_DEGREES 30 is stricter than the live game, which is the safe direction. The platform defaults
-- are Humanoid.MaxSlopeAngle = 89 and StarterPlayer.CharacterMaxSlopeAngle = 89. If the place ever lowers
-- CharacterMaxSlopeAngle it must not go below this value, or the live game will refuse a slope the
-- validator accepted. That is an out-of-repo control with the same auditability problem as
-- Players.MaxPlayers (M-05) and the FOUND-07 persistence toggle, and it is recorded as M-08 in
-- MANUAL-CHECKS.md. The flood deliberately does not model jumping even though Humanoid.JumpHeight defaults
-- to 7.2 studs and a real player can therefore jump onto the 6.5 ledge and the 4.0 crates; not modelling
-- it is the rejecting direction.
--
-- What these numbers do not rest on. STEP_UP is a design choice: Roblox does not document a Humanoid's
-- auto-step height (assumption A1). The R15 default HipHeight, the head height and the per-axis avatar
-- scale limits were not found in primary docs (assumption A2, A6; V-19 is MEDIUM for the documented parts
-- and LOW for the limits). Both feed rejecting-biased choices, so being wrong costs map culls rather than
-- unfindable spoons, but the envelope is recorded as M-09 in MANUAL-CHECKS.md so it is at least auditable.
return {
	GRID_SIZE = 1.0,
	STEP_UP = 1.0,
	MAX_SLOPE_DEGREES = 30,
	CAPSULE_RADIUS = 1.5,
	CAPSULE_HEIGHT = 7.0,
	REACH_HEIGHT = 2.5,
	EYE_HEIGHT = 4.0,
	SPOT_CLEARANCE = 0.25,
	PICKUP_RANGE = 7.0,
	PICKUP_MARGIN = 1.5,
}
