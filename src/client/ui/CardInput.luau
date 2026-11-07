--!strict
-- The input layer: which hint set is showing (UX-04, D-09) and the keyboard and gamepad accelerators
-- (D-08). It owns no game decision. Every accelerator calls back into CardClient, which sends it to the
-- reducer; a number key twice sends only because the reducer treats a second tap on the selected card as
-- the send, exactly as a second pointer tap does.
--
--  1. D-09: HINTS FOLLOW THE LAST INPUT ACTUALLY USED, LIVE. The signal is
--     UserInputService.LastInputTypeChanged. UserInputService.PreferredInput exists and is newer, but it
--     reports the ANTICIPATED primary input, which is a different question from "what did the player just
--     touch", so it is not the signal here and is not read in code. A touchscreen laptop, a phone with a
--     paired mouse and a controller picked up mid round all depend on the distinction.
--  2. NIL FROM Hints.kindOf MEANS LEAVE THE HINTS ALONE. The same signal also fires for Focus,
--     Accelerometer, Gyro and TextInput, and swapping the hint set on a gyro reading would be a bug.
--  3. D-08: THE KEYBOARD AND THE GAMEPAD ARE ADDITIVE. The pointer path is the guaranteed one and nothing in
--     this file is the only way to do anything.
--  4. THE ACCELERATORS BIND ABOVE THE MOVEMENT SINK (CardControls.SINK_PRIORITY) so a number key is never
--     swallowed by it, and they return Sink only for an input they actually handled and Pass for anything
--     else, so nothing else in the game loses an input. Space, Enter and the pad's A button are both sunk
--     here and commit: a draw is legal only at hand 4 and a pass only at hand 5, and the REDUCER decides
--     which, not this file.
--  5. GAMEPAD IS [R-DISC] AND V-27 VERIFIED THE APIS EXIST, NOT THE DEVICE BEHAVIOUR. It is built from
--     context-action bindings rather than GuiService.SelectedObject, per the research recommendation.
--     RECORDED FALLBACK, a one-line data change in each of TWO places and nothing else: if the gamepad cell
--     of M-11 fails, map the pad input types to the Mouse kind in Hints.KIND_OF and empty GAMEPAD_STEPS and
--     GAMEPAD_COMMIT below. Both are data, which is why that is all it takes.
--  6. TEARDOWN: every binding made here is unbound in destroy and the connection is disconnected, so a
--     finisher's Space, Enter and A button are theirs again the instant the overlay goes (D-30).
--  7. NOT PROVEN HERE: that any of this behaves on a PC, a phone or a pad. M-11.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Hints = require(ReplicatedStorage.Shared.Card.Hints)
local CardControls = require("./CardControls")

export type Actions = {
	selectSlot: (index: number) -> (), -- 1..5
	commit: () -> (), -- Space, Enter or the pad's A button: pass at 5, draw at 4 (the reducer decides)
	moveSelection: (delta: number) -> (), -- the pad's shoulder buttons and D-pad left and right
}

export type Input = {
	kind: (self: Input) -> Hints.InputKind,
	onKindChanged: (self: Input, fn: (kind: Hints.InputKind) -> ()) -> (),
	destroy: (self: Input) -> (),
}

local ACTION_SLOT = "SpoonsSlot"
local ACTION_COMMIT = "SpoonsCommit"
local ACTION_STEP = "SpoonsStep"

-- Above the movement sink, so a key both bind is taken here first.
local PRIORITY = CardControls.SINK_PRIORITY + 1

local slotKeys: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.KeypadFive] = 5,
}
local SLOT_KEYS = table.freeze(slotKeys)

local commitKeyList: { Enum.KeyCode } = { Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter }
local COMMIT_KEYS = table.freeze(commitKeyList)

-- The two gamepad data tables of header point 5.
local gamepadSteps: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.ButtonL1] = -1,
	[Enum.KeyCode.ButtonR1] = 1,
	[Enum.KeyCode.DPadLeft] = -1,
	[Enum.KeyCode.DPadRight] = 1,
}
local GAMEPAD_STEPS = table.freeze(gamepadSteps)
local gamepadCommitList: { Enum.KeyCode } = { Enum.KeyCode.ButtonA }
local GAMEPAD_COMMIT = table.freeze(gamepadCommitList)

local function keysOf(map: { [Enum.KeyCode]: number }): { Enum.KeyCode }
	local out: { Enum.KeyCode } = {}
	for key in map do
		table.insert(out, key)
	end
	return out
end

-- Hints.kindOf narrowed through the frozen list. The standard-platform solver widens a literal-union
-- return through a frozen export, so the union is rebuilt from the list rather than asserted.
local function kindFromName(name: string): Hints.InputKind?
	local mapped = Hints.kindOf(name)
	if mapped == "Touch" then
		return "Touch"
	elseif mapped == "Mouse" then
		return "Mouse"
	elseif mapped == "Keyboard" then
		return "Keyboard"
	elseif mapped == "Gamepad" then
		return "Gamepad"
	end
	return nil
end

-- Only the seed. The live value is always the last LastInputTypeChanged that mapped to a kind.
local function seedKind(): Hints.InputKind
	local seeded: Hints.InputKind? = kindFromName(UserInputService:GetLastInputType().Name)
	if seeded ~= nil then
		return seeded
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Mouse"
end

local CardInput = {}

function CardInput.new(actions: Actions): Input
	local current: Hints.InputKind = seedKind()
	local listeners: { (kind: Hints.InputKind) -> () } = {}
	local destroyed = false

	local connection = UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local kind: Hints.InputKind? = kindFromName(inputType.Name)
		if kind == nil or kind == current then
			return
		end
		current = kind
		for _, fn in listeners do
			fn(kind)
		end
	end)

	local function onSlot(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		local index = SLOT_KEYS[input.KeyCode]
		if index == nil then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			actions.selectSlot(index)
		end
		return Enum.ContextActionResult.Sink
	end

	local function onCommit(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			actions.commit()
		end
		return Enum.ContextActionResult.Sink
	end

	local function onStep(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		local delta = GAMEPAD_STEPS[input.KeyCode]
		if delta == nil then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			actions.moveSelection(delta)
		end
		return Enum.ContextActionResult.Sink
	end

	-- createTouchButton is false throughout: no on-screen button is created by any of these.
	ContextActionService:BindActionAtPriority(ACTION_SLOT, onSlot, false, PRIORITY, table.unpack(keysOf(SLOT_KEYS)))
	local commitInputs: { Enum.KeyCode } = table.clone(COMMIT_KEYS)
	for _, key in GAMEPAD_COMMIT do
		table.insert(commitInputs, key)
	end
	ContextActionService:BindActionAtPriority(ACTION_COMMIT, onCommit, false, PRIORITY, table.unpack(commitInputs))
	if next(GAMEPAD_STEPS) ~= nil then
		ContextActionService:BindActionAtPriority(
			ACTION_STEP,
			onStep,
			false,
			PRIORITY,
			table.unpack(keysOf(GAMEPAD_STEPS))
		)
	end

	local input: Input
	input = {
		kind = function(_self: Input): Hints.InputKind
			return current
		end,
		onKindChanged = function(_self: Input, fn: (kind: Hints.InputKind) -> ())
			table.insert(listeners, fn)
		end,
		destroy = function(_self: Input)
			if destroyed then
				return
			end
			destroyed = true
			connection:Disconnect()
			table.clear(listeners)
			for _, name in { ACTION_SLOT, ACTION_COMMIT, ACTION_STEP } do
				ContextActionService:UnbindAction(name)
			end
		end,
	}
	return input
end

return CardInput
