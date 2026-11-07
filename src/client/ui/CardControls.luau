--!strict
-- The Roblox half of UX-02 (D-29, D-30). The DECISIONS and the ORDER live in the pure
-- src/shared/Card/Controls.luau, which is tested headlessly; this file is only the four effects it is
-- handed, and it adds no decision of its own.
--
--  1. THE LEGACY CONTROLS GETTER IS NEVER CALLED AND THE STOCK PLAYER-SCRIPT MODULE IS NEVER REQUIRED.
--     Neither appears in any official Roblox documentation and never has. A staff release post
--     (2026-06-11) says the legacy endpoints "may no longer exist"; the engine default moves to the Input
--     Action System in early 2027 and the legacy scripts are removed in mid-2027. This comment does not
--     spell the identifiers, because tests/card/controls.spec scans all of src/ for them, comments
--     included.
--  2. NOTHING IN THE DEFAULT PLAYER SCRIPTS IS MUTATED by either effect here. If a layer silently does
--     nothing under the Input Action System, there is nothing to restore and nothing left broken. That is
--     the whole reason the layers are these layers.
--  3. THE TOUCH-MODAL PROPERTY IS DEPRECATED in favour of GuiService.TouchControlsEnabled, so the former is
--     not used.
--  4. THIS IS ERGONOMICS, NOT A SECURITY LAYER (T-4-139). A modified client can re-enable its own controls.
--     Holding the avatar is plan 04-15's server-side job; this file only removes the thumbstick graphics
--     from under the left pile and is meant to keep Space from also jumping while a card is being passed.
--  5. RECORDED, NOT FIXED: three community reports describe re-enable problems. A key held during the
--     disabled period not resuming until released (2024-04). A stuck jump button and a dead thumbstick
--     after re-enabling on touch (2025-06). A frozen jump button after disabling touch controls right
--     after a jump (2024-01). None was re-tested here, and all three bear on D-30, because find order
--     drives SCORE-01..03 and a stuck control costs the finisher points. IF THE STUCK-TOUCH CASE
--     REPRODUCES IN M-11, the recorded fallback is to re-assert by setting TouchControlsEnabled false and
--     then true on the next frame. It is a fallback, not a first resort, and it is NOT implemented here
--     speculatively.
--  6. WHETHER ANY OF THIS WORKS ON A PC, A PHONE OR A GAMEPAD, UNDER EITHER INPUT SYSTEM SETTING, IS M-11,
--     THE PHASE'S HIGHEST-RISK ROW. UX-02 is not claimed met by this file.
--  7. THE SINK'S ACTION NAME, PRIORITY AND KEY LIST ARE EXPORTED, so the M-11 matrix and the input layer
--     (which binds ABOVE the sink so a number key is never swallowed) read one source.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controls = require(ReplicatedStorage.Shared.Card.Controls)

local SINK_ACTION = "SpoonsSinkMove"
local SINK_PRIORITY = Enum.ContextActionPriority.High.Value

local sinkKeyList: { Enum.KeyCode } = {
	Enum.KeyCode.Space,
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
}
local SINK_KEYS = table.freeze(sinkKeyList)

local function sinkHandler(_actionName: string, _state: Enum.UserInputState, _input: InputObject)
	return Enum.ContextActionResult.Sink
end

local CardControls = {}

CardControls.SINK_ACTION = SINK_ACTION
CardControls.SINK_PRIORITY = SINK_PRIORITY
CardControls.SINK_KEYS = SINK_KEYS

function CardControls.makeEffects(onDestroyOverlay: () -> (), onStartFlourish: () -> ()): Controls.Effects
	return {
		setTouchControls = function(enabled: boolean)
			GuiService.TouchControlsEnabled = enabled
		end,
		bindSink = function()
			-- The false is createTouchButton: no touch button is made, so the documented seven-button
			-- ceiling is irrelevant.
			ContextActionService:BindActionAtPriority(
				SINK_ACTION,
				sinkHandler,
				false,
				SINK_PRIORITY,
				table.unpack(SINK_KEYS)
			)
		end,
		unbindSink = function()
			ContextActionService:UnbindAction(SINK_ACTION)
		end,
		destroyOverlay = onDestroyOverlay,
		startFlourish = onStartFlourish,
	}
end

function CardControls.new(onDestroyOverlay: () -> (), onStartFlourish: () -> ()): Controls.Controls
	return Controls.new(CardControls.makeEffects(onDestroyOverlay, onStartFlourish))
end

return CardControls
