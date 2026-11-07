--!strict
-- Every word the card HUD shows (UX-04, D-08, D-09, D-12, D-16..D-20, D-35, D-36).
--
-- 1. PURE ZONE, so input types are handled as NAMES. No Roblox API is named here; plan 04-18 maps the
--    real UserInputType to `kindOf` by its name.
-- 2. D-09: THE LAST INPUT ACTUALLY USED. Hints follow it and switch live, not the device type at join.
--    That covers a touchscreen laptop, a phone with a paired mouse, and a controller picked up mid
--    round. The newer PreferredInput API is the wrong source: it reports the ANTICIPATED primary input,
--    which is a different question. LastInputTypeChanged is the documented signal (V-27). An unmapped
--    name returns nil ("leave the hints alone") rather than a default, because that signal also fires
--    for Focus, Accelerometer, Gyro and TextInput, and swapping the hint set on a gyro reading would be
--    a bug rather than responsiveness.
-- 3. D-08: KEYBOARD AND GAMEPAD ARE ADDITIVE. Every state has a Touch and a Mouse string and those are
--    the guaranteed paths. V-27 fallback: if the gamepad check (M-11) fails, the Gamepad column
--    degrades to showing the Mouse set. That is why the table is data and the renderer never
--    hard-codes a column.
-- 4. CHECKER FLAG F4 AND D-36, RESOLVED IN COPY. Four UI-SPEC strings exceeded 34 characters and were
--    REWRITTEN, not truncated: the RightPileSink Touch and Mouse hints, strike(2), forcedPass and
--    stall (the Touch and Mouse pair counts as one UI-SPEC row). D-36 forbade truncation because a
--    cut-off consequence clause ("Strike 2 of 3. One more benches you." with the end gone) is worse
--    than no message. Budget: 34 characters against a strip of at least 634 design px at a 12 px bold
--    proxy, about 1.55x headroom before PreferredTextSize = Largest can overflow it. The rendered
--    check is M-12.
-- 5. D-12: THERE IS NO ERROR COPY AND THERE MUST NEVER BE ANY. A hard rejection (rate limited,
--    NotYourCard, HandNotFour, HandNotFive, InboxEmpty, SeatNotLive, UnknownCard, UnknownSeat) returns
--    the card silently, identically to a correction. A legitimate player never sees one, and a message
--    would hand a prober the name of the guard they tripped. Inventing error copy is a defect here.
--    `audit`'s "forbidden error copy:" check keeps that row empty.
-- 6. VOICE: exclamation marks appear ONLY in the starting-gun callouts. `audit` enforces it.
-- 7. D-35: the hand-4 strike line says nothing about a pass, because at hand 4 nothing moved.
-- 8. FORCED PASS (D-18) is private to the affected player and fires in roughly 1 round in 12. It can
--    land while the player's own Pass is in flight, which shows two changes at once: a card leaving
--    that they did not choose, and their own card returning. "Table stuck. We passed for you." reads
--    correctly for both. A rolled-back Draw placeholder leaves with no card id; the copy never names
--    a card for that reason.

export type InputKind = "Touch" | "Mouse" | "Keyboard" | "Gamepad"
export type State = "Hand5Idle" | "Selected" | "Hand4CanDraw" | "Hand4Empty" | "RightPileSink"

export type AuditInput = {
	hint: any,
	states: { string },
	kinds: { string },
	messages: any,
	callouts: any,
	maxChars: number,
	calloutMaxChars: number,
}

-- A type alone is not enough: it is erased at runtime, so freezing the runtime lists is what stops drift.
local INPUT_KINDS: { InputKind } = table.freeze({ "Touch", "Mouse", "Keyboard", "Gamepad" })
local STATES: { State } = table.freeze({ "Hand5Idle", "Selected", "Hand4CanDraw", "Hand4Empty", "RightPileSink" })

local function row(touch: string, mouse: string, keyboard: string, gamepad: string): { [InputKind]: string }
	return table.freeze({ Touch = touch, Mouse = mouse, Keyboard = keyboard, Gamepad = gamepad })
end

-- A literal nested table, not generated, so a missing cell is visible on the page as well as to `audit`.
local HINT: { [State]: { [InputKind]: string } } = table.freeze({
	Hand5Idle = row(
		"Tap a card to pick it",
		"Click a card to pick it",
		"Press 1-5 to pick a card",
		"Press LB or RB to pick a card"
	),
	Selected = row("Tap it again to pass", "Click it again to pass", "Press Space to pass", "Press A to pass"),
	Hand4CanDraw = row("Tap your pile to draw", "Click your pile to draw", "Press Space to draw", "Press A to draw"),
	Hand4Empty = row("Waiting for cards", "Waiting for cards", "Waiting for cards", "Waiting for cards"),
	RightPileSink = row(
		"Tap the lifted card to send",
		"Click the lifted card to send",
		"Press Space to pass",
		"Press A to pass"
	),
})

-- Exhaustive over the pointer, key and pad types; everything else is nil on purpose.
local KIND_OF: { [string]: InputKind } = table.freeze({
	Touch = "Touch",
	MouseButton1 = "Mouse",
	MouseButton2 = "Mouse",
	MouseButton3 = "Mouse",
	MouseWheel = "Mouse",
	MouseMovement = "Mouse",
	Keyboard = "Keyboard",
	Gamepad1 = "Gamepad",
	Gamepad2 = "Gamepad",
	Gamepad3 = "Gamepad",
	Gamepad4 = "Gamepad",
	Gamepad5 = "Gamepad",
	Gamepad6 = "Gamepad",
	Gamepad7 = "Gamepad",
	Gamepad8 = "Gamepad",
})

local NAME_BUDGET = 18

local function kindOf(userInputTypeName: string): InputKind?
	return KIND_OF[userInputTypeName]
end

local function whole(n: number): number
	return math.max(0, math.floor(n))
end

-- Functions, not literals, wherever a number is interpolated, so a call site cannot build a string by
-- concatenation and drift past the cap with nothing to catch it.
local MESSAGES = table.freeze({
	countdown = function(owes: "Pass" | "Draw", secondsLeft: number): string
		local verb = if owes == "Draw" then "Draw" else "Pass"
		return `{verb} a card: {whole(secondsLeft)}`
	end,
	strike = function(strikes: number, owes: "Pass" | "Draw"): string
		if strikes <= 1 then
			if owes == "Draw" then
				return "Idle at your pile. Strike 1 of 3."
			end
			return "Auto-passed a card. Strike 1 of 3."
		elseif strikes == 2 then
			return "Strike 2 of 3. One more benches."
		end
		return "You were benched for being idle."
	end,
	benched = function(): string
		return "You were benched for being idle."
	end,
	forcedPass = function(): string
		return "Table stuck. We passed for you."
	end,
	stall = function(): string
		return "Table is stuck. Try another card."
	end,
	waiting = function(): string
		return "Waiting for cards from your left"
	end,
})

local CALLOUTS = table.freeze({
	other = function(displayName: string): string
		return `{string.sub(displayName, 1, NAME_BUDGET)} is out! Find a spoon!`
	end,
	selfOut = function(): string
		return "You're out! Find a spoon!"
	end,
})

local ROTATE_PROMPT = "Rotate your device to landscape"

-- Flat samples of every dynamic builder, for `audit`. Tables are arguments to `audit`, so a mutation is
-- an injected copy of these and never a source edit.
local function sampleMessages(jokerExplainers: { [string]: string }?): { [string]: string }
	local out: { [string]: string } = {}
	local owesList: { "Pass" | "Draw" } = { "Pass", "Draw" }
	for _, owes in owesList do
		for s = 0, 2 do
			out[`countdown {owes} {s}`] = MESSAGES.countdown(owes, s)
		end
		for k = 1, 3 do
			out[`strike {k} {owes}`] = MESSAGES.strike(k, owes)
		end
	end
	out.benched = MESSAGES.benched()
	out.forcedPass = MESSAGES.forcedPass()
	out.stall = MESSAGES.stall()
	out.waiting = MESSAGES.waiting()
	out.rotate = ROTATE_PROMPT
	if jokerExplainers then
		for mode, text in jokerExplainers do
			out[`joker {mode}`] = text
		end
	end
	return out
end

local function sampleCallouts(): { [string]: string }
	return {
		selfOut = CALLOUTS.selfOut(),
		otherLongest = CALLOUTS.other(string.rep("x", NAME_BUDGET + 12)),
	}
end

local FORBIDDEN_WORDS = { "error", "invalid", "failed", "rejected", "not allowed" }

local function checkString(problems: { string }, label: string, s: any, maxChars: number, allowBang: boolean)
	if type(s) ~= "string" or #s == 0 then
		table.insert(problems, `empty string: {label}`)
		return
	end
	if #s > maxChars then
		table.insert(problems, `too long: {label} is {#s} > {maxChars}`)
	end
	if not allowBang and string.find(s, "!", 1, true) then
		table.insert(problems, `stray exclamation: {label}`)
	end
	local lower = string.lower(s)
	for _, w in FORBIDDEN_WORDS do
		if string.find(lower, w, 1, true) then
			table.insert(problems, `forbidden error copy: {label} contains "{w}"`)
		end
	end
end

local KNOWN_KINDS: { [string]: boolean } = { Touch = true, Mouse = true, Keyboard = true, Gamepad = true }
local KNOWN_STATES: { [string]: boolean } =
	{ Hand5Idle = true, Selected = true, Hand4CanDraw = true, Hand4Empty = true, RightPileSink = true }

-- Returns the problems and the number of strings measured, so a vacuous audit can be detected.
local function audit(t: AuditInput): ({ string }, number)
	local problems: { string } = {}
	local measured = 0
	for _, state in t.states do
		if not KNOWN_STATES[state] then
			table.insert(problems, `unmapped state: {state}`)
		end
	end
	for _, kind in t.kinds do
		if not KNOWN_KINDS[kind] then
			table.insert(problems, `unmapped kind: {kind}`)
		end
	end
	for _, state in t.states do
		local rowOf = t.hint[state]
		for _, kind in t.kinds do
			local s = if rowOf then rowOf[kind] else nil
			if s == nil then
				table.insert(problems, `missing cell: {state}/{kind}`)
			else
				measured += 1
				checkString(problems, `{state}/{kind}`, s, t.maxChars, false)
			end
		end
	end
	for name, s in t.messages do
		measured += 1
		checkString(problems, `message {name}`, s, t.maxChars, false)
	end
	for name, s in t.callouts do
		measured += 1
		checkString(problems, `callout {name}`, s, t.calloutMaxChars, true)
	end
	return problems, measured
end

return table.freeze({
	INPUT_KINDS = INPUT_KINDS,
	STATES = STATES,
	HINT = HINT,
	KIND_OF = KIND_OF,
	ROTATE_PROMPT = ROTATE_PROMPT,
	NAME_BUDGET = NAME_BUDGET,
	MESSAGES = MESSAGES,
	CALLOUTS = CALLOUTS,
	kindOf = kindOf,
	sampleMessages = sampleMessages,
	sampleCallouts = sampleCallouts,
	audit = audit,
})
