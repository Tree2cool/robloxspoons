--!strict
-- BOTH PILE PANELS (CARD-13, D-06, D-07, D-26). Built once, mutated afterwards. A panel shows a label, up
-- to three layers of card-back art, and the exact count numeral over it.
--
--  1. STATES ARE TEXT AND SHAPE, NEVER COLOUR ALONE (D-24). Drawable: the label `Draw`, full-opacity art and
--     a pulsing accent ring. Locked: the label `Locked`, art 60 percent transparent and NO ring. Empty: the
--     label `Draw`, a dashed-outline empty slot with no art, numeral `0`. The ring's single meaning is "you
--     can draw".
--  2. THIS FILE IS TOLD NOTHING ABOUT THE AFK STATE (plan 04-16's resolution of the UI-SPEC "Minor" flag).
--     At hand 4 the AFK cue pulses nothing, because the countdown text and drain bar already carry it and a
--     ring with two meanings teaches nothing. There is deliberately no argument through which it could.
--  3. THE PULSE IS AT OR BELOW 2 HZ and only a ring's stroke thickness moves, so there is no photosensitivity
--     risk and the full screen is never flashed (T-4-134). The rate is Config.Card.PULSE_HZ.DRAW_RING.
--  4. BOTH PANELS ARE ACTIVE NO-OP SINKS (D-04, D-06). A tap on either never reaches the backdrop, because
--     the backdrop CLEARS the selection and a fumbled tap must not deselect a card the player is about to
--     send. The left pile forwards its tap (it is the draw, D-07: instant and unguarded) and the REDUCER makes
--     it inert unless drawable; this file does not second-guess it. The right pile is a DESTINATION ONLY: it
--     sends nothing, and its callback only keeps the selection and pulses the strip hint.
--  5. COUNTS ARE EXACT ONLY FOR THE LOCAL PLAYER (CARD-13): the left count is my inbox depth and the right
--     count is the downstream seat's. Other seats get stack height on the 3D table and no numerals. There is
--     no dealer marker anywhere: the dealer's left pile IS the deck, so their stack is simply the tallest.
--  6. ONE RenderStepped CONNECTION drives the pulse and is disconnected in destroy. A leaked render connection
--     on a destroyed overlay is a per-round leak (T-4-133).
--  7. DASHED OUTLINE: a UIStroke cannot dash, so the empty slot's stroke carries a UIGradient whose
--     transparency alternates. That reads as dashes along the long edges only. Whether it reads as an empty
--     slot on glass is a visual check (M-14 family), not something this file proves.
--  8. leftCentre and rightCentre are the ART centres in HandZone design units (CardFace.pileArtCentre), so
--     CardHand can fly a card from and to them without either file knowing the other's geometry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardConfig = require(ReplicatedStorage.Shared.Config.Card)
local Layout = require(ReplicatedStorage.Shared.Card.Layout)
local CardFace = require("./CardFace")
local CardTheme = require("./CardTheme")

export type LeftState = "Drawable" | "Locked" | "Empty"

export type Piles = {
	setLeft: (self: Piles, count: number, state: "Drawable" | "Locked" | "Empty") -> (),
	setRight: (self: Piles, count: number) -> (),
	leftCentre: (self: Piles) -> Vector2, -- where a drawn card flies from
	rightCentre: (self: Piles) -> Vector2, -- where a passed card flies to
	relayout: (self: Piles, solution: Layout.Solution) -> (),
	destroy: (self: Piles) -> (),
}

type Panel = {
	button: TextButton,
	label: TextLabel,
	count: TextLabel,
	layers: { Frame },
	layerStrokes: { UIStroke },
	dashed: Frame,
}

local D = Layout.DESIGN
local MAX_LAYERS = 3
local LOCKED_FADE = 0.6 -- "art 60 % transparent"
local CENTRE = 0.5
local LABEL_DRAW = "Draw"
local LABEL_LOCKED = "Locked"
local LABEL_NEXT = "Next"
local DASHES = 4

local CardPiles = {}

local function dashedGradient(): UIGradient
	local points: { NumberSequenceKeypoint } = {}
	for k = 0, DASHES - 1 do
		local a = k / DASHES
		local mid = (k + CENTRE) / DASHES
		table.insert(points, NumberSequenceKeypoint.new(a, 0))
		table.insert(points, NumberSequenceKeypoint.new(mid - 0.001, 0))
		table.insert(points, NumberSequenceKeypoint.new(mid, 1))
		table.insert(points, NumberSequenceKeypoint.new(if k == DASHES - 1 then 1 else (k + 1) / DASHES - 0.001, 1))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new(points)
	return gradient
end

local function buildPanel(parent: Frame, name: string, labelText: string): Panel
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.Selectable = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = CardTheme.COLOR.PILE_PANEL
	button.BackgroundTransparency = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, CardTheme.CORNER_RADIUS)
	round.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Active = false
	label.BackgroundTransparency = 1
	label.FontFace = CardTheme.FONT.REGULAR
	label.TextSize = CardTheme.TEXT_SIZE.LABEL
	label.TextColor3 = CardTheme.COLOR.TEXT_ON_DARK
	label.TextScaled = false
	label.TextWrapped = false
	label.RichText = false
	label.Text = labelText
	label.Size = UDim2.fromScale(1, 0.22)
	label.Position = UDim2.fromScale(0, 0.03)
	label.Parent = button

	local layers: { Frame } = {}
	local layerStrokes: { UIStroke } = {}
	for i = 1, MAX_LAYERS do
		local layer = Instance.new("Frame")
		layer.Name = `Art{i}`
		layer.Active = false
		layer.BorderSizePixel = 0
		layer.AnchorPoint = Vector2.new(CENTRE, CENTRE)
		layer.Size = UDim2.fromOffset(D.PILE_ART_W, D.PILE_ART_H)
		layer.Position = UDim2.new(CENTRE, (i - 2) * 2, CardFace.PILE_ART_Y, (i - 2) * 2)
		layer.BackgroundColor3 = CardTheme.COLOR.CARD_BACK
		layer.Visible = false
		local layerRound = Instance.new("UICorner")
		layerRound.CornerRadius = UDim.new(0, CardTheme.CORNER_RADIUS)
		layerRound.Parent = layer
		local layerStroke = Instance.new("UIStroke")
		layerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		layerStroke.Thickness = CardTheme.STROKE.CARD
		layerStroke.Color = CardTheme.COLOR.CARD_BACK_PATTERN
		layerStroke.Parent = layer
		layer.Parent = button
		table.insert(layers, layer)
		table.insert(layerStrokes, layerStroke)
	end

	local dashed = Instance.new("Frame")
	dashed.Name = "EmptySlot"
	dashed.Active = false
	dashed.BorderSizePixel = 0
	dashed.BackgroundTransparency = 1
	dashed.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	dashed.Size = UDim2.fromOffset(D.PILE_ART_W, D.PILE_ART_H)
	dashed.Position = UDim2.fromScale(CENTRE, CardFace.PILE_ART_Y)
	dashed.Visible = false
	local dashedRound = Instance.new("UICorner")
	dashedRound.CornerRadius = UDim.new(0, CardTheme.CORNER_RADIUS)
	dashedRound.Parent = dashed
	local dashedStroke = Instance.new("UIStroke")
	dashedStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dashedStroke.Thickness = CardTheme.STROKE.CARD
	dashedStroke.Color = CardTheme.COLOR.TEXT_ON_DARK
	dashedStroke.Parent = dashed
	dashedGradient().Parent = dashedStroke
	dashed.Parent = button

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Active = false
	count.BackgroundTransparency = 1
	count.FontFace = CardTheme.FONT.BOLD
	count.TextSize = CardTheme.TEXT_SIZE.HEADING
	count.TextColor3 = CardTheme.COLOR.TEXT_ON_DARK
	count.TextStrokeColor3 = CardTheme.COLOR.CARD_STROKE
	count.TextStrokeTransparency = 0
	count.TextScaled = false
	count.TextWrapped = false
	count.RichText = false
	count.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	count.Position = UDim2.fromScale(CENTRE, CardFace.PILE_ART_Y)
	count.Size = UDim2.fromScale(1, 0.45)
	count.Text = "0"
	count.ZIndex = 2
	count.Parent = button

	button.Parent = parent
	return {
		button = button,
		label = label,
		count = count,
		layers = layers,
		layerStrokes = layerStrokes,
		dashed = dashed,
	}
end

function CardPiles.new(
	parent: Frame,
	solution: Layout.Solution,
	callbacks: {
		tapLeft: () -> (),
		tapRight: () -> (),
	}
): Piles
	local sol = solution
	local connections: { RBXScriptConnection } = {}
	local destroyed = false

	local function bind(signal: RBXScriptSignal, fn: (...any) -> ())
		table.insert(connections, signal:Connect(fn))
	end

	local left = buildPanel(parent, "LeftPile", LABEL_DRAW)
	local right = buildPanel(parent, "RightPile", LABEL_NEXT)
	-- Header point 4, one line per panel so each is separately checkable: neither tap reaches the backdrop.
	left.button.Active = true
	right.button.Active = true

	-- The accent ring: only on the drawable left pile, and only its thickness moves.
	local ring = Instance.new("UIStroke")
	ring.Name = "DrawRing"
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Color = CardTheme.COLOR.ACCENT
	ring.Thickness = CardTheme.STROKE.PULSE_MIN
	ring.Enabled = false
	ring.Parent = left.button

	-- Direction on the destination pile, drawn: a right-pointing triangle beside the art.
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Direction"
	arrow.Active = false
	arrow.BackgroundTransparency = 1
	arrow.FontFace = CardTheme.FONT.BOLD
	arrow.TextSize = CardTheme.TEXT_SIZE.LABEL
	arrow.TextColor3 = CardTheme.COLOR.TEXT_ON_DARK
	arrow.TextScaled = false
	arrow.Text = utf8.char(0x25B6)
	arrow.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	arrow.Position = UDim2.fromScale(0.9, CardFace.PILE_ART_Y)
	arrow.Size = UDim2.fromScale(0.22, 0.22)
	arrow.Parent = right.button

	local function place(s: Layout.Solution)
		local lp, ls = CardFace.zoneRect(s.leftPile, s)
		left.button.Position = lp
		left.button.Size = ls
		local rp, rs = CardFace.zoneRect(s.rightPile, s)
		right.button.Position = rp
		right.button.Size = rs
	end
	place(sol)

	local ringOn = false
	-- Accumulated frame time, not a clock read: the project has exactly one clock (tests/card/deci_lock).
	local elapsed = 0
	bind(RunService.RenderStepped, function(dt: number)
		elapsed += dt
		if not ringOn or destroyed then
			return
		end
		local phase = CENTRE + CENTRE * math.sin(elapsed * math.pi * 2 * CardConfig.PULSE_HZ.DRAW_RING)
		ring.Thickness = CardTheme.STROKE.PULSE_MIN + (CardTheme.STROKE.PULSE_MAX - CardTheme.STROKE.PULSE_MIN) * phase
	end)

	-- Both taps are forwarded; the reducer decides what, if anything, they do.
	bind(left.button.Activated, function()
		callbacks.tapLeft()
	end)
	bind(right.button.Activated, function()
		callbacks.tapRight()
	end)

	local function showLayers(panel: Panel, count: number, fade: number)
		local shown = math.min(math.max(count, 0), MAX_LAYERS)
		for i, layer in panel.layers do
			layer.Visible = i <= shown
			layer.BackgroundTransparency = fade
			panel.layerStrokes[i].Transparency = fade
		end
	end

	local piles: Piles
	piles = {
		setLeft = function(_self: Piles, count: number, state: LeftState)
			left.count.Text = tostring(count)
			if state == "Drawable" then
				left.label.Text = LABEL_DRAW
				left.label.FontFace = CardTheme.FONT.REGULAR
				showLayers(left, count, 0)
				left.dashed.Visible = false
				ringOn = true
				ring.Enabled = true
			elseif state == "Locked" then
				left.label.Text = LABEL_LOCKED
				left.label.FontFace = CardTheme.FONT.BOLD
				showLayers(left, count, LOCKED_FADE)
				left.dashed.Visible = false
				ringOn = false
				ring.Enabled = false
			else
				left.label.Text = LABEL_DRAW
				left.label.FontFace = CardTheme.FONT.REGULAR
				showLayers(left, 0, 0)
				left.dashed.Visible = true
				ringOn = false
				ring.Enabled = false
			end
		end,

		setRight = function(_self: Piles, count: number)
			right.count.Text = tostring(count)
			showLayers(right, count, 0)
		end,

		leftCentre = function(_self: Piles): Vector2
			return CardFace.pileArtCentre(sol.leftPile, sol)
		end,

		rightCentre = function(_self: Piles): Vector2
			return CardFace.pileArtCentre(sol.rightPile, sol)
		end,

		relayout = function(_self: Piles, s: Layout.Solution)
			sol = s
			place(s)
		end,

		destroy = function(_self: Piles)
			if destroyed then
				return
			end
			destroyed = true
			ringOn = false
			for _, c in connections do
				c:Disconnect()
			end
			table.clear(connections)
			left.button:Destroy()
			right.button:Destroy()
		end,
	}

	piles:setLeft(0, "Empty")
	piles:setRight(0)
	return piles
end

return CardPiles
