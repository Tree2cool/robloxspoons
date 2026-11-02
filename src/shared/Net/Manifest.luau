--!strict
-- The intent registry for the single typed gateway (FOUND-04). One line per intent: later phases add
-- theirs here and nowhere else. PURE ZONE: requires only the sibling ./Validate.
local Validate = require("./Validate")

-- D-20: the round phase vocabulary. A type alone is not enough: types are erased at runtime and
-- `phases` is a plain array of strings, so nothing would stop a later manifest entry listing a name the
-- owner rejected. PHASES below is the runtime constant the manifest spec asserts against, which is how
-- D-20 actually stops later phases inventing competing names. Rejected alternatives live in CONTEXT.md.
--
-- `Round` is the single phase in which the card scramble and the hunt happen concurrently: one 5:00 cap
-- covers both and a finisher leaves the table while others are still passing, so they overlap rather
-- than follow each other. Say `RoundPhase.Round` when meaning this state, not the whole match cycle.
export type RoundPhase = "Lobby" | "Hide" | "Round" | "Podium"

local PHASES: { RoundPhase } = { "Lobby", "Hide", "Round", "Podium" }
table.freeze(PHASES)

export type Intent = {
	phases: { RoundPhase },
	validate: Validate.Validator,
}

local MAX_NAME_LENGTH = 64

local intents: { [string]: Intent } = {
	Ping = {
		phases = PHASES,
		-- `nonce` is NOT decoration. FOUND-04 and phase success criterion 4 both name NaN, and the only
		-- live (Studio) proof of NaN rejection is manual check M-03. With an empty schema, a NaN field
		-- would be bounced as an UnknownKey and never reach `isFinite`, so M-03 would prove the envelope
		-- and nothing about NaN. One required finite integer field makes the live path genuinely
		-- exercise the finite check. It is required, not optional, so `{}` is a MissingKey.
		validate = Validate.exactKeys({ nonce = Validate.integer({ min = 0, max = 2 ^ 31 }) }),
	},
}

-- Type and length come before the lookup (research check-order item 1): a name we have never heard of
-- must cost no lookup and allocate no per-name state.
local function isKnown(name: unknown): boolean
	if type(name) ~= "string" then
		return false
	end
	if #name == 0 or #name > MAX_NAME_LENGTH then
		return false
	end
	return intents[name] ~= nil
end

return {
	intents = intents,
	isKnown = isKnown,
	MAX_NAME_LENGTH = MAX_NAME_LENGTH,
	PHASES = PHASES,
}
