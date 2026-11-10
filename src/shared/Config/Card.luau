--!strict
-- Every Phase 4 (live card table) tunable, as a value. Read the header before changing one: several of
-- these look like feel knobs and are not.
--
-- 1. THIS FILE HOLDS SECONDS, NOT DECISECONDS. The float-seconds to integer-deciseconds conversion
--    (CLAUDE.md rule 5) is the pure function src/server/core/CardTiming.luau, and it has exactly ONE
--    caller in shipped code: plan 04-14's src/server/services/CardService.luau.
--    tests/card/config_lock.spec.luau drives the function directly and tests/card/cardtable.spec.luau
--    proves its result reaches IdleClock.
--
-- 2. FLOURISH_DURATION_SECONDS IS NOT A FEEL KNOB (D-32). PROJECT.md requires every deal animation to
--    have the same fixed duration so none confers an advantage; an unequal duration would be a
--    pay-to-win defect. The driver owns the duration, never the content.
--
-- 3. STALL_ACTIONS_PER_SEAT = 96 AND STALL_MIN_SECONDS = 45.0 ARE BOTH REQUIRED (D-20). 96 is twice the
--    engine's Types.VALVE_ARM_ACTIONS_PER_SEAT = 48, so the cue is strictly later than the valve's
--    arming. A healthy 9-seat round is ~380 actions table-wide (~42 per seat) against a threshold of
--    864, and the 15 replayed residual stalls ran 2,431-4,429 actions; the separation is the point.
--    The second condition gates the small-table case on wall time, where an action count alone is too
--    easily reached. The detector is keyed on accepted actions without progress and NEVER on
--    ValveForcedPass: 3 of those 15 stalls had the valve armed and firing zero times, so a valve-keyed
--    cue would be silent in exactly the rounds that need it.
--
-- 4. STRIP_MAX_CHARS = 34 IS THE PLANNER'S RESOLUTION OF CHECKER FLAG F4 PLUS D-36. The UI-SPEC's own
--    450 px strip limit was ~6 px short of its two 38-character strings at DEFAULT text size, and
--    GuiService.PreferredTextSize = Largest scales text even at TextScaled = false. Both halves are
--    applied: plan 04-08 widens the strip to the full safe width (>= 634 design px) AND every strip
--    string is capped at 34 characters, giving 634 / (34 * 12) = 1.55x headroom before overflow, with
--    a UITextSizeConstraint above that. Four UI-SPEC strings exceed 34 and are rewritten in plan 04-11
--    rather than truncated, because D-36 records that truncating the clause which says what is about
--    to happen is worse than no message.
--
-- 5. AUDIO IDS ARE OWNER-SUPPLIED AND AN EMPTY STRING MUST BE SILENT, NEVER AN ERROR (D-33, human
--    gate). The phase has to run before the assets land.
--
-- 6. AUTO_PASS_MAX_SECONDS AND AUTO_PASS_SELECTION ARE DELIBERATELY NOT HERE. They are Gate G1
--    constants and live only in CardPool.luau; a second copy is how a locked value drifts.
--
-- 7. LAYERING_ROUTE IS NOT A FEEL KNOB. It names the answer to Phase 04.1's Wave 0 spike -- how two
--    AlwaysOnTop SurfaceGuis on DIFFERENT Parts order against each other, which no primary Roblox doc
--    states. Its two legal values are "AlwaysOnTop" and "Depth". **The value shipped here is PROVISIONAL
--    until MANUAL-CHECKS M-18 is signed**, and the reasoning, the three routes and the one-sentence
--    decision rule live in .planning/phases/04.1-first-person-cards/04.1-LAYERING-DECISION.md -- read it
--    before touching this line. It has exactly ONE read site in src/ (the card carrier);
--    tests/card/layering_contract.spec.luau budgets that count and asserts that setting it to "Depth"
--    drags the M-23 lighting-independence row with it, so the route cannot change in silence.
--
-- 8. TWEEN.CARD_MOVE DELIBERATELY REPLACES THE PER-PATH DRAW/SEND/RETURN FOR THE 3D HAND (D-51 read
--    literally: a per-path duration is how a presentation change becomes a pacing change nobody intended).
--    One travel duration for draw, pass, return and deal. SELECT, FLIP and CLOSE_GAP are NOT travel and are
--    unchanged. DRAW 0.15 / SEND 0.18 / RETURN 0.25 stay in the file because the 2D path still owns the
--    piles until that path is gone; they are not for the hand.
--
-- 9. THE FAN'S ARC RADIUS IS DERIVED AND IS NEVER STORED HERE: R = STEP_STUDS / (2 * sin(ROLL_STEP_DEG / 2))
--    = 21.5 studs. A second constant is how two numbers come to disagree. A scan asserts that no
--    ARC_RADIUS / RADIUS_STUDS constant exists in this file.
--
-- 10. CAMERA.FOV_DEGREES IS THE **VERTICAL** ANGLE (VERIFIED: Camera.md, FieldOfView is the vertical FOV,
--    clamped 1..120, default 70; horizontal follows the aspect ratio). `DiagonalFieldOfView` must NEVER be
--    substituted: the diagonal property is measured against the fullscreen area that a notch can eat, which
--    is the opposite of what a 48 px touch guarantee needs. A scan asserts the identifier appears nowhere.
--
-- 11. EYE_RISE_STUDS AND PITCH_DEGREES ARE STARTING VALUES, tuned on the real map (M-12, Open Question 7).
--    The 48 px proof does not depend on either: it is driven by the projected card HEIGHT, which depends on
--    FOV, the viewport height and HAND.OFFSET_STUDS. Changing OFFSET_STUDS DOES re-open that proof.
--
-- This file requires nothing.
return {
	-- CARD-16 / D-17
	MAX_STRIKES = 3,
	-- D-16: nothing for the first 6 s of the 8 s window, then a countdown
	AFK_WARN_SECONDS = 2.0,
	-- CARD-14 watchdog: a gateway-level reject never reaches the card core, so an unacked pending
	-- entry older than this triggers a resync rather than leaving a phantom gap
	PENDING_TIMEOUT_SECONDS = 1.0,
	-- D-32: ONE duration for every flourish kind (see header point 2)
	FLOURISH_DURATION_SECONDS = 1.5,
	FLOURISH_SCAN_INTERVAL_SECONDS = 0.25,
	HAND_DISPLAY_ORDER = 10,
	FLOURISH_DISPLAY_ORDER = 5,
	-- D-20: the stall detector's own thresholds. BOTH must be met (see header point 3).
	STALL_ACTIONS_PER_SEAT = 96,
	STALL_MIN_SECONDS = 45.0,
	STALL_CUE_SECONDS = 5.0,
	STALL_REPEAT_SECONDS = 30.0,
	-- D-22 log throttle
	REJECT_LOG_PER_WINDOW = 3,
	REJECT_WINDOW_SECONDS = 10.0,
	SWEEP_HZ = 10,
	-- Checker FLAG F4 + D-36 (see header point 4)
	STRIP_MAX_CHARS = 34,
	CALLOUT_MAX_CHARS = 40,
	MAX_CALLOUTS = 2,
	TABLE_HOP_CONCURRENT_CAP = 16,
	SEAT_STACK_STUDS_PER_CARD = 0.25,
	SEAT_STACK_CAP = 16,
	-- Stud geometry for the 3D table cosmetics (CardSeatsView, CardFlourish). Starting values: the real
	-- tuning is on the real map (M-12). Named here so no client file carries a stud literal.
	TABLE_CARD_STUDS = { WIDTH = 1.4, LENGTH = 2.0, THICKNESS = 0.05 },
	SEAT_STACK_OFFSET_STUDS = 3.0,
	HOP_PEAK_STUDS = 1.0,
	FLOURISH_FAN_SPACING_STUDS = 1.6,
	-- Phase 04.1, the first-person hand. Design units convert at exactly 1/40 stud, so every Phase 4 face
	-- token stays valid: the 72 x 92 design card is 1.8 x 2.3 studs and the ratio is exactly 72:92.
	-- No literal from this table may be repeated in src/client (header point 7 of 04.1-UI-SPEC's carrier rule).
	HAND = {
		STUDS_PER_DESIGN_UNIT = 1 / 40,
		CARD_STUDS = { WIDTH = 1.8, HEIGHT = 2.3, THICKNESS = 0.05 },
		-- = 60 design units: the chord between neighbouring card centres, not an arc length
		STEP_STUDS = 1.5,
		-- = 16 design units, along the card's OWN up vector (so a rolled card lifts along its own axis)
		LIFT_STUDS = 0.4,
		-- slot s of n gets (s - (n + 1) / 2) * this, in degrees, about the view axis
		ROLL_STEP_DEG = 4,
		-- the top leans AWAY from the camera; the pivot is the card's centre
		LEAN_DEG = 12,
		-- slot s steps (s - 1) * this toward the camera. Under route "Depth" this is the layering mechanism;
		-- under "AlwaysOnTop" it is harmless. See header point 7.
		DEPTH_STEP_STUDS = 0.05,
		-- camera-local. Roblox looks down -Z, so Z is negative for "in front of the eye".
		OFFSET_STUDS = { X = 0, Y = -2.2, Z = -6.5 },
		-- SurfaceGui PixelsPerStud = 40 * this
		CANVAS_SCALE = 3,
		-- "AlwaysOnTop" | "Depth". WAVE 0 / M-18, PROVISIONAL. See header point 7 and
		-- .planning/phases/04.1-first-person-cards/04.1-LAYERING-DECISION.md
		LAYERING_ROUTE = "AlwaysOnTop",
		-- Phase 4's smallest rendered pip was 16 * 0.85 = 13.6 px; this is that floor rounded up to a whole
		-- pixel and may never be lower
		PIP_MIN_PX = 14,
		-- Phase 4's smallest rendered rank glyph
		GLYPH_MIN_PX = 17,
		-- the tighter assertion at the smallest supported viewport; the project floor itself is 48 (V-25)
		HIT_FLOOR_MARGIN_PX = 52,
	},
	CAMERA = {
		-- VERTICAL (verified, header point 10); never DiagonalFieldOfView
		FOV_DEGREES = 70,
		-- above seat.position, from CardTable.SeatSpec only; never from Head/PrimaryPart (D-42)
		EYE_RISE_STUDS = 2.5,
		PITCH_DEGREES = -18,
		-- below this FULLSCREEN height the 48 px floor is reported, not claimed (checker flag F10)
		MIN_FULL_HEIGHT = 360,
		ASPECT_MIN = 4 / 3,
		ASPECT_MAX = 21 / 9,
	},
	TWEEN = {
		SELECT = 0.08,
		SEND = 0.18,
		RETURN = 0.25,
		DRAW = 0.15,
		FLIP = 0.12,
		CLOSE_GAP = 0.12,
		HOP = 0.30,
		CALLOUT = 2.5,
		CALLOUT_FADE = 0.2,
		NOTICE = 3.0,
		FORCED_RING = 0.4,
		SINK_HINT = 2.0,
		-- Phase 04.1: the ONE travel duration for every card-travel path -- draw, pass, return, deal
		-- (D-51, header point 8). Deliberately equal to SEND so a later edit to one is visibly a decision
		-- about the other; tests/card/config_lock.spec.luau asserts the equality.
		CARD_MOVE = 0.18,
	},
	PULSE_HZ = { DRAW_RING = 1.5, AFK = 1.5, STALL = 0.8 },
	-- Owner-supplied asset ids (human gate, NEEDS_HUMAN). Empty string is silent (header point 5).
	AUDIO = { STING = "", DRAW = "", PASS = "", VOLUME = 0.3, OWN_CAP_SECONDS = 0.12 },
}
