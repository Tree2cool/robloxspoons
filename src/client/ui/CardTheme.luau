--!strict
-- The single home for every literal colour, font and line weight in the client card HUD.
--
--  1. WHY A FILE OF ITS OWN. src/shared/Card is a pure zone and may not name Color3 or Font, and Phase 7's
--     deck skins need exactly one file to reskin. tests/card/renderer_discipline.spec.luau asserts that no
--     other file under src/client/ui contains a colour or font constructor.
--  2. FONT: BUILDER SANS ONLY, NO FALLBACK. The old Gotham enum members were removed from the platform and
--     now map to Montserrat, so a "Gotham fallback" would silently change the typeface and invalidate
--     every glyph-width figure in the UI-SPEC (the strip's 34-character cap rests on them). Builder Sans
--     being unavailable is a BLOCKER to raise with the owner (M-16), never a substitution to make.
--  3. THE ACCENT HAS EXACTLY FIVE USES AND THE LIST IS CLOSED. Each has a redundant non-colour carrier,
--     so meaning never rests on colour alone (D-24):
--       selection    the selected-card outline        also carried by the lift
--       drawRing     the drawable left-pile ring      also carried by the Draw label
--       drainBar     the AFK drain-bar fill           also carried by the countdown text
--       afkPulse     the fan outline pulse at hand 5  also carried by the countdown text
--       selfCallout  the self out-callout underline   also carried by the words
--     The forced-pass and stall cues use NEUTRAL_CUE on purpose: they are not the accent.
--  4. TIMINGS ARE NOT HERE. Tween durations and pulse rates live in Config.Card, so each kind of constant
--     has exactly one home: colour, font and line weight here, time there, geometry in Layout.
--  5. NO DESTRUCTIVE COLOUR. This phase has no destructive action: D-02 and D-03 removed every
--     confirmation and D-12 removed every error message, so an error red would have nothing to mark. It is
--     deliberately absent rather than defined and unused.
--  6. NOTHING IN THIS FILE IS INVENTED. Every value is quoted from the UI-SPEC "Typography" and "Color".
--     PLATE_OPACITY is the spec's 0.15 plate transparency stated as its complement, so the number does
--     not coincide with a Config.Card timing the discipline scan looks for.

local colorTable = {
	-- dominant 60%, drawn at 0.15 transparency (see PLATE_OPACITY)
	PLATE = Color3.fromRGB(20, 24, 36),
	CARD_FACE = Color3.fromRGB(244, 240, 230),
	CARD_STROKE = Color3.fromRGB(24, 24, 30),
	CARD_BACK = Color3.fromRGB(52, 64, 110),
	CARD_BACK_PATTERN = Color3.fromRGB(120, 136, 190),
	PILE_PANEL = Color3.fromRGB(38, 45, 66),
	ACCENT = Color3.fromRGB(255, 176, 32),
	SUIT_RED = Color3.fromRGB(200, 45, 40),
	SUIT_BLACK = Color3.fromRGB(24, 24, 30),
	TEXT_ON_DARK = Color3.fromRGB(240, 243, 250),
	TEXT_ON_CREAM = Color3.fromRGB(24, 24, 30),
	-- forced pass and stall: deliberately NOT the accent
	NEUTRAL_CUE = Color3.fromRGB(240, 243, 250),
}

local fontTable = {
	REGULAR = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular),
	BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
}

local textSizeTable = { LABEL = 16, BODY = 20, HEADING = 28 }

local strokeTable = { CARD = 2, SELECTED = 3, JOKER = 4, PULSE_MIN = 1, PULSE_MAX = 3 }

local accentUseList: { string } = { "selection", "drawRing", "drainBar", "afkPulse", "selfCallout" }

return table.freeze({
	FONT = table.freeze(fontTable),
	TEXT_SIZE = table.freeze(textSizeTable),
	COLOR = table.freeze(colorTable),
	ACCENT_USES = table.freeze(accentUseList),
	STROKE = table.freeze(strokeTable),
	CORNER_RADIUS = 8,
	PLATE_OPACITY = 0.85,
})
