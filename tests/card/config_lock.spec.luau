--!strict
-- Spec lock for the Phase 4 values the owner locked (Gate G1 constants, D-13, D-14, D-20, D-32,
-- amendment A7). These assertions exist so a locked value cannot drift silently.
-- **If one fails, the fix is the source, never this file.**
--
-- tests/ is not a Rojo mount, so the cross-mount relative requires below are legal (guard R6 scans
-- shipped dirs only).
local Card = require("../../src/shared/Config/Card")
local CardPool = require("../../src/shared/Config/CardPool")
local CardTiming = require("../../src/server/core/CardTiming")
local Round = require("../../src/shared/Config/Round")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

-- A conversion with no floor and no epsilon. Rounding up is not hypothetical: `0.07 * 100` is
-- 7.0000000000000009 in IEEE double. (The plan's own example, `0.7 * 10`, is exactly 7.0 and does NOT
-- trip a ceil -- found when this gate's non-vacuity assertion fired on it; see the 04-01 SUMMARY.)
local function naive(seconds: number, perSecond: number): number
	return math.ceil(seconds * perSecond)
end

local function withinCeiling(seconds: number, perSecond: number, convert: (number, number) -> number): boolean
	-- The product is compared with a 1e-6 tolerance because the IEEE product of a decimal can sit a
	-- few ulp BELOW the true value (0.29 * 100 = 28.999999999999996) and the real conversion
	-- deliberately returns the true 29. A whole deci of overshoot (what ceil does) still fails.
	return convert(seconds, perSecond) <= seconds * perSecond + 1e-6
end

return function(t: Test.Runner)
	t.test("Gate G1 constants are at their locked positions", function()
		t.equal(CardPool.EXTRA_RANKS, 3, "G1 pool: EXTRA_RANKS (D-14)")
		t.equal(CardPool.JOKERS, 1, "G1 pool: JOKERS (D-14)")
		t.equal(CardPool.JOKER_MODE, "Wild", "G1 pool: JOKER_MODE (D-14)")
		t.equal(CardPool.ANTI_LIVELOCK_VALVE, true, "valve must stay on (amendment A7)")
		t.equal(CardPool.AUTO_PASS_MAX_SECONDS, 8.0, "auto-pass ceiling is a Gate G1 constraint (D-13)")
		t.equal(
			CardPool.AUTO_PASS_SELECTION,
			"uniform-random-from-hand",
			"selection rule is a Gate G1 constraint (D-13, A7-CORRECTION)"
		)
	end)

	t.test("the SHIPPED conversion lands on 80 and can never exceed the ceiling (D-13, rule 5)", function()
		-- The ceiling bounds the CONFIGURED value. The realised window is 7.9 s to 8.1 s: with
		-- nowDeci = floor(10 * clock) an arming at real time c stores floor(10c) + D, so the deadline
		-- is first observable at elapsed (D - frac(10c)) / 10, which for D = 80 lies in (7.9, 8.0].
		-- Flooring is ONE-SIDED and only ever SHORTENS the window; the 10 Hz sweep then adds up to
		-- +0.1 s of lateness, giving (7.9, 8.1]. (04-RESEARCH.md Integration 5, assumption A5.)
		local deci = CardTiming.autoPassDeci(CardPool.AUTO_PASS_MAX_SECONDS, Round.DECISECONDS_PER_SECOND)
		t.equal(deci, 80, "shipped auto-pass is 80 deciseconds")
		t.truthy(
			deci <= CardPool.AUTO_PASS_MAX_SECONDS * Round.DECISECONDS_PER_SECOND,
			"the converted value must never exceed the configured ceiling"
		)
	end)

	t.test("MUTATION: a naive conversion exceeds the ceiling where the real one cannot", function()
		local inputs: { { number } } =
			{ { 8.0, 10 }, { 0.7, 10 }, { 2.9, 10 }, { 0.07, 100 }, { 0.14, 100 }, { 0.29, 100 } }
		local naiveViolations = 0
		for _, input in inputs do
			t.truthy(
				withinCeiling(input[1], input[2], CardTiming.autoPassDeci),
				`real conversion exceeded the ceiling for ({input[1]}, {input[2]})`
			)
			if not withinCeiling(input[1], input[2], naive) then
				naiveViolations += 1
			end
		end
		print(`  inputs driven: {#inputs}, naive violations: {naiveViolations}`)
		t.equal(#inputs, 6, "non-vacuity: every input was driven")
		t.truthy(naiveViolations >= 1, "the mutation must violate the ceiling at least once or the gate is vacuous")
		t.equal(CardTiming.autoPassDeci(0.07, 100), 7)
		t.equal(naive(0.07, 100), 8, `naive(0.07, 100) must be 8; 0.07 * 100 = {string.format("%.17g", 0.07 * 100)}`)
		-- the epsilon: a bare floor undershoots where the product lands just BELOW an integer
		-- (0.29 * 100 = 28.999999999999996), which the ceiling predicate cannot see.
		local function bareFloor(seconds: number, perSecond: number): number
			return math.floor(seconds * perSecond)
		end
		t.equal(bareFloor(0.29, 100), 28, `0.29 * 100 = {string.format("%.17g", 0.29 * 100)}`)
		t.equal(CardTiming.autoPassDeci(0.29, 100), 29, "the epsilon rescues the undershoot")
		t.equal(CardTiming.autoPassDeci(0.7, 10), 7)
		-- bad input is refused by name
		local ok = pcall(CardTiming.autoPassDeci, 0 / 0, 10)
		t.falsy(ok, "NaN maxSeconds must error")
		ok = pcall(CardTiming.autoPassDeci, 8, 0)
		t.falsy(ok, "zero decisPerSecond must error")
		ok = pcall(CardTiming.autoPassDeci, 8, 2.5)
		t.falsy(ok, "non-integer decisPerSecond must error")
	end)

	t.test("Config.Card holds every Phase 4 tunable, and holds no Gate G1 constant", function()
		local expected: { { any } } = {
			{ "MAX_STRIKES", 3 },
			{ "AFK_WARN_SECONDS", 2.0 },
			{ "FLOURISH_DURATION_SECONDS", 1.5 },
			{ "PENDING_TIMEOUT_SECONDS", 1.0 },
			{ "STALL_ACTIONS_PER_SEAT", 96 },
			{ "STALL_MIN_SECONDS", 45.0 },
			{ "STRIP_MAX_CHARS", 34 },
			{ "CALLOUT_MAX_CHARS", 40 },
			{ "MAX_CALLOUTS", 2 },
			{ "STALL_CUE_SECONDS", 5.0 },
			{ "STALL_REPEAT_SECONDS", 30.0 },
			{ "SWEEP_HZ", 10 },
		}
		local seen = 0
		local card = Card :: any
		for _, pair in expected do
			t.equal(card[pair[1]], pair[2], `Config.Card.{pair[1]}`)
			seen += 1
		end
		print(`  config keys checked: {seen}`)
		t.truthy(seen >= 12, "the config lock ran over too few keys to prove anything")
		t.truthy(
			Card.FLOURISH_DISPLAY_ORDER < Card.HAND_DISPLAY_ORDER,
			"the flourish must never sit above the hand (checker FLAG F8)"
		)
		t.equal(typeof(Card.AUDIO.STING), "string")
		t.equal(typeof(Card.AUDIO.DRAW), "string")
		t.equal(typeof(Card.AUDIO.PASS), "string")
		t.equal((Card :: any).AUTO_PASS_MAX_SECONDS, nil, "Gate G1 constant duplicated into Config.Card")
		t.equal((Card :: any).AUTO_PASS_SELECTION, nil, "Gate G1 constant duplicated into Config.Card")
	end)

	t.test("STALL_ACTIONS_PER_SEAT is strictly above the engine's valve arming threshold (D-20)", function()
		t.truthy(
			Card.STALL_ACTIONS_PER_SEAT > Types.VALVE_ARM_ACTIONS_PER_SEAT,
			"the stall cue must be strictly later than the valve's arming"
		)
		t.equal(Card.STALL_ACTIONS_PER_SEAT, 2 * Types.VALVE_ARM_ACTIONS_PER_SEAT)
	end)
end
