--!strict
-- The card HUD's root: one ScreenGui, one scale frame, the zone frames every other UI module parents into,
-- the viewport re-solve, and the rotate prompt. It APPLIES Layout.solve and computes no geometry of its
-- own (T-4-115); the only arithmetic here is converting the solved physical rects into the design units the
-- scale frame lays children out in, and rounding, which Layout deliberately leaves to the renderer.
--
--  1. UX-03: THE INSETS ARE SET EXPLICITLY, ONCE, FROM THE PURE CONSTANT. Layout.SCREEN_INSETS is a string
--     because a pure zone names no engine enum; the table below is the one-line mapping and the only place
--     the enum member is spelled. The member is the one the documentation recommends for any ScreenGui
--     holding interactive or important elements (verified against primary docs, V-24). The device-only
--     member is the plausible wrong answer: it clears the camera notch but leaves UI under the Roblox top
--     bar. The assignment sits in one helper used by both ScreenGuis here, so there is one assignment.
--  2. IgnoreGuiInset IS DELIBERATELY NOT SET. Setting it as well as the insets is how the inset gets
--     applied twice and pushes everything inward on every device (T-4-120).
--  3. WHETHER THE INSETS ALONE SUFFICE, OR MANUAL INSET ARITHMETIC IS STILL NEEDED IN PRACTICE, IS A
--     REAL-DEVICE OBSERVATION (M-12), NOT A DOCS QUESTION. resolve builds the Viewport from the camera and
--     the engine's reported inset and trusts Layout; this container has no notched phone.
--  4. D-30: destroy removes the ScreenGui outright. It is the overlay-destroy effect of the controls state
--     machine. The restored thumbstick occupies the left pile's corner, so a transparent overlay would
--     still sink the first tap, and holding a finisher still costs them points. Gone, not faded.
--  5. THE RESPAWN FLAG IS FALSE. A respawn mid-round must not destroy the hand (T-4-121, M-11 row 3).
--  6. THE TREE IS BUILT COMPLETELY BEFORE PARENTING, as NetServer parents its remotes last: nothing
--     half-built is ever visible or hittable.
--  7. NO TWEEN AND NO DEBOUNCE ON A VIEWPORT CHANGE. A rotation or a window resize snaps; anything else is
--     a frame budget this phase has not measured.
--  8. THE ROTATE PROMPT (D-28) IS A FALLBACK, NOT THE MECHANISM. Landscape is locked in the place's
--     supported-orientation settings, a Creator Dashboard setting and therefore a human gate (M-15). It is
--     a SEPARATE ScreenGui because the hand is destroyed on completion and the prompt must survive that: a
--     player who rotates after completing still needs telling. It is driven by the orientation the device
--     reports, not by comparing viewport dimensions. Requesting the sensor-landscape member from script is
--     a second line of defence only: it is NOT verified that a script-side request overrides the dashboard
--     setting (N-3). It is the single place in the phase where text may wrap, because it shows in portrait
--     where the layout does not exist and no budget applies.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CardConfig = require(ReplicatedStorage.Shared.Config.Card)
local Hints = require(ReplicatedStorage.Shared.Card.Hints)
local Layout = require(ReplicatedStorage.Shared.Card.Layout)
local CardTheme = require("./CardTheme")

export type Hud = {
	-- Re-solves the layout and repositions every zone. Called on creation and on any
	-- Camera.ViewportSize change; `handSize` comes from the reducer's display.
	resolve: (self: Hud, handSize: number) -> Layout.Solution,
	solution: (self: Hud) -> Layout.Solution?,
	-- Zone frames every other UI module parents into. None of them is Active.
	tableRegion: (self: Hud) -> Frame,
	handZone: (self: Hud) -> Frame,
	-- The ScreenGui, for the flourish surface's DisplayOrder comparison (plan 04-19).
	gui: (self: Hud) -> ScreenGui,
	-- D-30: GONE, not faded.
	destroy: (self: Hud) -> (),
	onViewportChanged: (self: Hud, fn: () -> ()) -> (),
}

export type RotatePrompt = { destroy: (self: RotatePrompt) -> () }

-- A second, NON-interactive layer that is not the hand: it outlives the hand's destruction at the local
-- completion (D-30), which is what lets a who-went callout still show to the player who just went. Its
-- `region` is placed exactly where the hand's TableRegion is, so Layout's callout rects apply unchanged.
export type Overlay = {
	region: (self: Overlay) -> Frame,
	-- Re-solves from the live camera and positions the region; returns the solution for the callout rects.
	resolve: (self: Overlay, handSize: number) -> Layout.Solution,
	destroy: (self: Overlay) -> (),
}

-- The one mapping from the pure string to the engine enum (header point 1).
local INSETS_BY_NAME: { [string]: Enum.ScreenInsets } = {
	CoreUISafeInsets = Enum.ScreenInsets.CoreUISafeInsets,
}

local CardHud = {}

local function applyInsets(gui: ScreenGui)
	local insets = INSETS_BY_NAME[Layout.SCREEN_INSETS]
	if insets == nil then
		error(`CardHud: no engine enum mapped for Layout.SCREEN_INSETS = {Layout.SCREEN_INSETS}`)
	end
	gui.ScreenInsets = insets
end

local function playerGui(): PlayerGui
	local player = Players.LocalPlayer
	if player == nil then
		error("CardHud: no LocalPlayer (client only)")
	end
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

local function camera(): Camera
	while Workspace.CurrentCamera == nil do
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
	end
	return Workspace.CurrentCamera :: Camera
end

-- The only logic that is not Layout's: engine readings into the plain Viewport table (header point 3).
local function readViewport(cam: Camera): Layout.Viewport
	local topLeft, bottomRight = GuiService:GetGuiInset()
	return {
		width = cam.ViewportSize.X,
		height = cam.ViewportSize.Y,
		insets = { top = topLeft.Y, bottom = bottomRight.Y, left = topLeft.X, right = bottomRight.X },
	}
end

local function container(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Parent = parent
	return frame
end

-- An unparented ScreenGui with the explicit insets and no reset on spawn. Every ScreenGui this client
-- creates comes from here, so the insets are assigned in one place (UX-03).
function CardHud.newGui(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	applyInsets(gui)
	gui.DisplayOrder = displayOrder
	gui.ResetOnSpawn = false
	return gui
end

-- Parents a fully built gui to the local PlayerGui, last (header point 6).
function CardHud.mount(gui: ScreenGui)
	gui.Parent = playerGui()
end

function CardHud.newOverlay(name: string, displayOrder: number): Overlay
	local cam = camera()
	local gui = CardHud.newGui(name, displayOrder)
	local root = container("Root", gui)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	local region = container("TableRegion", root)
	local destroyed = false
	local overlay: Overlay
	overlay = {
		region = function(_self: Overlay): Frame
			return region
		end,
		resolve = function(_self: Overlay, handSize: number): Layout.Solution
			local s = Layout.solve(readViewport(cam), handSize)
			uiScale.Scale = s.scale
			root.Position = UDim2.fromOffset(0, 0)
			root.Size = UDim2.fromOffset(math.round(s.designW), math.round(s.designH))
			region.Position = UDim2.fromOffset(
				math.round((s.tableRegion.x - s.safe.x) / s.scale),
				math.round((s.tableRegion.y - s.safe.y) / s.scale)
			)
			region.Size = UDim2.fromOffset(math.round(s.tableRegion.w / s.scale), math.round(s.tableRegion.h / s.scale))
			return s
		end,
		destroy = function(_self: Overlay)
			if destroyed then
				return
			end
			destroyed = true
			gui:Destroy()
		end,
	}
	-- Last, per header point 6.
	CardHud.mount(gui)
	return overlay
end

function CardHud.new(handSize: number): Hud
	local cam = camera()

	local gui = Instance.new("ScreenGui")
	gui.Name = "CardHud"
	applyInsets(gui)
	gui.DisplayOrder = CardConfig.HAND_DISPLAY_ORDER
	gui.ResetOnSpawn = false

	local root = container("Root", gui)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root
	local tableRegion = container("TableRegion", root)
	local handZone = container("HandZone", root)
	-- A separate non-interactive child, so the plate can never sink a tap.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Active = false
	plate.BorderSizePixel = 0
	plate.BackgroundColor3 = CardTheme.COLOR.PLATE
	plate.BackgroundTransparency = 1 - CardTheme.PLATE_OPACITY
	plate.Size = UDim2.fromScale(1, 1)
	plate.Parent = handZone

	local latest: Layout.Solution? = nil
	local currentHand = handSize
	local subscribers: { () -> () } = {}
	local destroyed = false
	local viewportConnection: RBXScriptConnection? = nil

	local function place(frame: Frame, rect: Layout.Rect, s: Layout.Solution)
		frame.Position =
			UDim2.fromOffset(math.round((rect.x - s.safe.x) / s.scale), math.round((rect.y - s.safe.y) / s.scale))
		frame.Size = UDim2.fromOffset(math.round(rect.w / s.scale), math.round(rect.h / s.scale))
	end

	local hud: Hud
	hud = {
		resolve = function(_self: Hud, hand: number): Layout.Solution
			currentHand = hand
			local s = Layout.solve(readViewport(cam), hand)
			uiScale.Scale = s.scale
			root.Position = UDim2.fromOffset(0, 0)
			root.Size = UDim2.fromOffset(math.round(s.designW), math.round(s.designH))
			place(tableRegion, s.tableRegion, s)
			place(handZone, s.handZone, s)
			latest = s
			return s
		end,
		solution = function(_self: Hud): Layout.Solution?
			return latest
		end,
		tableRegion = function(_self: Hud): Frame
			return tableRegion
		end,
		handZone = function(_self: Hud): Frame
			return handZone
		end,
		gui = function(_self: Hud): ScreenGui
			return gui
		end,
		destroy = function(_self: Hud)
			if destroyed then
				return
			end
			destroyed = true
			if viewportConnection then
				viewportConnection:Disconnect()
			end
			table.clear(subscribers)
			gui:Destroy()
		end,
		onViewportChanged = function(_self: Hud, fn: () -> ())
			table.insert(subscribers, fn)
		end,
	}

	hud:resolve(handSize)
	-- The camera outlives the gui, so destroy disconnects this explicitly.
	viewportConnection = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if destroyed then
			return
		end
		hud:resolve(currentHand)
		for _, fn in subscribers do
			fn()
		end
	end)

	-- Last, per header point 6.
	gui.Parent = playerGui()
	return hud
end

function CardHud.newRotatePrompt(): RotatePrompt
	local pg = playerGui()
	-- Belt and braces only (header point 8). IN-06: the value is captured first and put back by destroy, so
	-- tearing the prompt down no longer leaves the whole PlayerGui locked to landscape.
	local previousOrientation = pg.ScreenOrientation
	pg.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

	local gui = Instance.new("ScreenGui")
	gui.Name = "CardRotatePrompt"
	applyInsets(gui)
	gui.DisplayOrder = CardConfig.HAND_DISPLAY_ORDER + 1
	gui.ResetOnSpawn = false

	local backing = Instance.new("Frame")
	backing.Name = "Backing"
	backing.Active = false
	backing.BorderSizePixel = 0
	backing.BackgroundColor3 = CardTheme.COLOR.PLATE
	backing.BackgroundTransparency = 0
	backing.Size = UDim2.fromScale(1, 1)
	backing.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "Prompt"
	label.Active = false
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = CardTheme.FONT.BOLD
	label.TextSize = CardTheme.TEXT_SIZE.HEADING
	label.TextColor3 = CardTheme.COLOR.TEXT_ON_DARK
	label.TextScaled = false
	label.TextWrapped = true
	label.Text = Hints.ROTATE_PROMPT
	label.Parent = backing

	local function refresh()
		gui.Enabled = pg.CurrentScreenOrientation == Enum.ScreenOrientation.Portrait
	end
	local connection = pg:GetPropertyChangedSignal("CurrentScreenOrientation"):Connect(refresh)
	refresh()
	gui.Parent = pg

	local prompt: RotatePrompt
	prompt = {
		destroy = function(_self: RotatePrompt)
			connection:Disconnect()
			gui:Destroy()
			pg.ScreenOrientation = previousOrientation
		end,
	}
	return prompt
end

return CardHud
