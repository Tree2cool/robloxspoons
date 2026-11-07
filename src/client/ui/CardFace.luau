--!strict
-- ONE CARD INSTANCE: the face, the back, the flip, and the six visual states (CARD-19, D-11, D-23, D-24).
-- The tree is built once in `new` and only mutated afterwards. Nothing here decides a rank, a suit, a band,
-- a colour, a font, a duration or a geometry number: they come from Faces, CardTheme, Config.Card and Layout.
--
--  1. NOTHING IS COMPUTED HERE. Every glyph, pip and band is read from Faces.faceOf, so a renderer cannot
--     invent a rank or a suit; tests/card/renderer_discipline.spec.luau scans for literals that try.
--  2. THE JOKER BAND IS TABLE-DRIVEN (D-23). CardPool.JOKER_MODE is a live flag and the same card means two
--     things depending on it, so the band text and shape are read from the Face that Faces returns. This
--     file never names a joker mode: the only mode-shaped input is the `mode` argument it forwards to Faces,
--     which errors by name for a joker asked for without one. A band shape Faces adds without a drawing
--     here errors by name too (SHAPE_HAS_BAR), rather than rendering a blank band.
--  3. COLOUR IS DECORATIVE (D-24). Only the tint reads Pip.isRedByDefault. Identity is the rank glyph plus
--     the pip silhouette. SELECTION IS THE LIFT AND THE STROKE THICKNESS, not the colour: the selected
--     stroke is the resting stroke plus (SELECTED - CARD) so it is also thicker on a joker, whose resting
--     stroke is already the heaviest.
--  4. PIPS: Faces.PIP_SOURCE decides, once. "glyph" draws pip.glyph in a TextLabel; "sprite" draws the
--     sheet cell through ImageRectOffset / ImageRectSize. Hearts and spades are never built from rotated
--     Frames. With no sprite asset id the sprite path draws a VISIBLE placeholder box, because a silently
--     invisible pip would read as a layout bug in every later check. The asset itself is M-16, and whether
--     spade and club survive 16 px in greyscale is M-14. Neither is closed by this file.
--  5. THE SIX STATES are a flat machine: Idle, Selected, Arriving, InFlight, Returning, ForcedOut. Idle and
--     Selected are resting states; Arriving and Returning are flights that END in the resting state the
--     caller last asked for (so selecting a card mid-return is honoured the instant it lands); InFlight and
--     ForcedOut are terminal and the caller destroys the card in onDone.
--  6. THE CARD IS NEVER ACTIVE. Hit testing is CardHand's strips, which is what makes a tap independent of
--     z-order and of the lift. A card that took input would re-couple the two.
--  7. flip() THEN setFace(): width 1 -> 0 -> 1 over TWEEN.FLIP, and the side shown changes at the midpoint
--     to whatever has been staged by then. Calling setFace after flip() inside the same frame is how the
--     face is revealed mid-turn rather than before it.
--  8. EXTRAS BEYOND THE PLAN'S CONTRACT, each recorded in the summary: setSolution (a viewport change),
--     placeAt (the origin of a flight), setVisible (hold a card back for a sequenced return), and an
--     optional `mode` on setFace (the live joker flag Faces needs). centreOf and zoneRect are exported so
--     CardHand and CardPiles share one rounding.
--  9. Coordinates are design units relative to the HandZone frame, which is where the Hud lays children
--     out; rounding happens here, as in the Hud, never in Layout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CardConfig = require(ReplicatedStorage.Shared.Config.Card)
local Faces = require(ReplicatedStorage.Shared.Card.Faces)
local Layout = require(ReplicatedStorage.Shared.Card.Layout)
local CardTheme = require("./CardTheme")

export type Visual = "Idle" | "Selected" | "Arriving" | "InFlight" | "Returning" | "ForcedOut"

export type CardFace = {
	-- nil, nil = face-down back. rank 0 is the joker and needs the live `mode`.
	setFace: (self: CardFace, rank: number?, copy: number?, mode: string?) -> (),
	setVisual: (self: CardFace, visual: Visual) -> (),
	moveToSlot: (self: CardFace, slot: Layout.Slot, animate: boolean) -> (),
	-- `target` is the card CENTRE in HandZone design units.
	flyTo: (self: CardFace, target: Vector2, visual: Visual, onDone: (() -> ())?) -> (),
	flip: (self: CardFace) -> (), -- width 1 -> 0 -> 1 over TWEEN.FLIP
	instance: (self: CardFace) -> Frame,
	destroy: (self: CardFace) -> (),
	setSolution: (self: CardFace, solution: Layout.Solution) -> (),
	-- Snap the centre to a point; `shrunk` starts the card at the in-flight size (leaving the right pile).
	placeAt: (self: CardFace, centre: Vector2, shrunk: boolean) -> (),
	setVisible: (self: CardFace, visible: boolean) -> (),
}

type PipView = { text: TextLabel, image: ImageLabel }
type Index = { group: Frame, rank: TextLabel, pip: PipView }

local D = Layout.DESIGN
local TWEEN = CardConfig.TWEEN

-- ZIndex among siblings in the HandZone: strips (CardHand) sit above all of these.
local Z_BASE = 10
local Z_SELECTED = 20
local SHRINK = 0.6 -- UI-SPEC "In flight": shrinking to 60 %
local CENTRE = 0.5
local SPRITE_SHEET = "" -- M-16: the owner-uploaded 4-cell sheet; empty draws the visible placeholder
local STAR = utf8.char(0x2605)
local JK = "JK"

-- Whether a band shape draws a diagonal bar through the star. Keyed by what Faces publishes.
local SHAPE_HAS_BAR: { [string]: boolean } = {}
SHAPE_HAS_BAR["star"] = false
SHAPE_HAS_BAR["star-barred"] = true

local CardFaceModule = {}

function CardFaceModule.centreOf(rect: Layout.Rect, s: Layout.Solution): Vector2
	local zone = s.handZone
	return Vector2.new(
		math.round((rect.x + rect.w / 2 - zone.x) / s.scale),
		math.round((rect.y + rect.h / 2 - zone.y) / s.scale)
	)
end

-- A physical rect as HandZone design-unit offsets, rounded.
function CardFaceModule.zoneRect(rect: Layout.Rect, s: Layout.Solution): (UDim2, UDim2)
	local zone = s.handZone
	return UDim2.fromOffset(math.round((rect.x - zone.x) / s.scale), math.round((rect.y - zone.y) / s.scale)),
		UDim2.fromOffset(math.round(rect.w / s.scale), math.round(rect.h / s.scale))
end

-- The pile art sits slightly below the panel's middle (the label takes the top). CardPiles lays the art
-- out with this and CardHand flies cards to and from the same point, so neither knows the other's geometry.
CardFaceModule.PILE_ART_Y = 0.55

function CardFaceModule.pileArtCentre(panel: Layout.Rect, s: Layout.Solution): Vector2
	local zone = s.handZone
	return Vector2.new(
		math.round((panel.x + panel.w / 2 - zone.x) / s.scale),
		math.round((panel.y + panel.h * CardFaceModule.PILE_ART_Y - zone.y) / s.scale)
	)
end

local function cardSize(s: Layout.Solution): Vector2
	local c = s.slots[1].card
	return Vector2.new(math.round(c.w / s.scale), math.round(c.h / s.scale))
end

local function plain(frame: GuiObject)
	frame.Active = false
	frame.BorderSizePixel = 0
end

local function newFrame(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	plain(f)
	f.BackgroundTransparency = 1
	f.Parent = parent
	return f
end

local function newLabel(parent: Instance, name: string, textSize: number, bold: boolean): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	plain(l)
	l.BackgroundTransparency = 1
	l.FontFace = if bold then CardTheme.FONT.BOLD else CardTheme.FONT.REGULAR
	l.TextSize = textSize
	l.TextScaled = false
	l.TextWrapped = false
	l.RichText = false
	l.TextColor3 = CardTheme.COLOR.TEXT_ON_CREAM
	l.Text = ""
	l.Parent = parent
	return l
end

local function stroke(parent: Instance, thickness: number, color: Color3): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = thickness
	s.Color = color
	s.Parent = parent
	return s
end

local function corner(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, CardTheme.CORNER_RADIUS)
	c.Parent = parent
end

-- Both the glyph label and the sprite cell exist; PIP_SOURCE shows exactly one.
local function newPip(parent: Instance, name: string, textSize: number): PipView
	local text = newLabel(parent, `{name}Glyph`, textSize, true)
	text.Size = UDim2.fromScale(1, 1)
	local image = Instance.new("ImageLabel")
	image.Name = `{name}Sprite`
	plain(image)
	image.Size = UDim2.fromScale(1, 1)
	image.Image = SPRITE_SHEET
	-- The placeholder: with no asset the cell is a visible box rather than nothing.
	if SPRITE_SHEET == "" then
		image.BackgroundTransparency = 0
		image.BackgroundColor3 = CardTheme.COLOR.CARD_BACK_PATTERN
	else
		image.BackgroundTransparency = 1
	end
	image.Visible = false
	image.Parent = parent
	text.Visible = false
	return { text = text, image = image }
end

local function showPip(view: PipView, pip: Faces.Pip?, tint: Color3)
	if pip == nil then
		view.text.Visible = false
		view.image.Visible = false
		return
	end
	if Faces.PIP_SOURCE == "sprite" then
		view.text.Visible = false
		view.image.Visible = true
		view.image.ImageRectOffset = Vector2.new(pip.sprite.x, pip.sprite.y)
		view.image.ImageRectSize = Vector2.new(pip.sprite.w, pip.sprite.h)
	else
		view.image.Visible = false
		view.text.Visible = true
		view.text.Text = pip.glyph
		view.text.TextColor3 = tint
	end
end

local function newIndex(parent: Instance, name: string): Index
	local group = newFrame(parent, name)
	group.Size = UDim2.fromScale(0.45, 0.48)
	local rank = newLabel(group, "Rank", CardTheme.TEXT_SIZE.BODY, true)
	rank.Size = UDim2.fromScale(1, 0.52)
	rank.TextXAlignment = Enum.TextXAlignment.Left
	local holder = newFrame(group, "PipHolder")
	holder.Position = UDim2.fromScale(0, 0.55)
	holder.Size = UDim2.fromScale(1, 0.42)
	local pip = newPip(holder, "IndexPip", CardTheme.TEXT_SIZE.LABEL)
	pip.text.TextXAlignment = Enum.TextXAlignment.Left
	return { group = group, rank = rank, pip = pip }
end

function CardFaceModule.new(parent: Frame, solution: Layout.Solution): CardFace
	local sol = solution
	local size = cardSize(sol)

	local root = Instance.new("Frame")
	root.Name = "Card"
	plain(root)
	root.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	root.BackgroundColor3 = CardTheme.COLOR.CARD_FACE
	root.BackgroundTransparency = 0
	root.ClipsDescendants = true
	root.Size = UDim2.fromOffset(size.X, size.Y)
	corner(root)
	local rim = stroke(root, CardTheme.STROKE.CARD, CardTheme.COLOR.CARD_STROKE)
	local scaler = Instance.new("UIScale")
	scaler.Scale = 1
	scaler.Parent = root

	-- Front: normal layer and joker layer share the corner index; only the normal layer mirrors it.
	local front = newFrame(root, "Front")
	front.Size = UDim2.fromScale(1, 1)
	local corner1 = newIndex(front, "Corner")
	corner1.group.Position = UDim2.fromOffset(D.INDEX_INSET_X, D.INDEX_INSET_Y)

	local normal = newFrame(front, "Normal")
	normal.Size = UDim2.fromScale(1, 1)
	local centreHolder = newFrame(normal, "CentreHolder")
	centreHolder.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	centreHolder.Position = UDim2.fromScale(CENTRE, CENTRE)
	centreHolder.Size = UDim2.fromScale(0.6, 0.45)
	local centrePip = newPip(centreHolder, "CentrePip", CardTheme.TEXT_SIZE.HEADING)
	local mirror = newIndex(normal, "Mirror")
	mirror.group.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	mirror.group.Rotation = 180
	-- Point reflection of the corner group through the card centre (group centre is 0.225 W, 0.24 H in).
	mirror.group.Position = UDim2.new(1 - 0.225, -D.INDEX_INSET_X, 1 - 0.24, -D.INDEX_INSET_Y)
	mirror.pip.text.TextXAlignment = Enum.TextXAlignment.Left

	local jokerLayer = newFrame(front, "Joker")
	jokerLayer.Size = UDim2.fromScale(1, 1)
	local innerBorder = newFrame(jokerLayer, "InnerBorder")
	innerBorder.Position = UDim2.fromScale(0.05, 0.04)
	innerBorder.Size = UDim2.fromScale(0.9, 0.92)
	stroke(innerBorder, CardTheme.STROKE.CARD, CardTheme.COLOR.CARD_STROKE)
	local centreStar = newLabel(jokerLayer, "Star", CardTheme.TEXT_SIZE.HEADING, true)
	centreStar.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	centreStar.Position = UDim2.fromScale(CENTRE, 0.33)
	centreStar.Size = UDim2.fromScale(0.6, 0.35)
	centreStar.Text = STAR
	local bar = newFrame(jokerLayer, "Bar")
	bar.AnchorPoint = Vector2.new(CENTRE, CENTRE)
	bar.Position = UDim2.fromScale(CENTRE, 0.33)
	bar.Size = UDim2.fromScale(0.07, 0.38)
	bar.Rotation = 45
	bar.BackgroundTransparency = 0
	bar.BackgroundColor3 = CardTheme.COLOR.TEXT_ON_CREAM
	bar.Visible = false
	local band = newFrame(jokerLayer, "Band")
	band.Position = UDim2.fromScale(0, 0.65)
	band.Size = UDim2.fromScale(1, 0.31)
	band.BackgroundTransparency = 0
	band.BackgroundColor3 = CardTheme.COLOR.CARD_STROKE
	local bandText = newLabel(band, "BandText", CardTheme.TEXT_SIZE.LABEL, true)
	bandText.Size = UDim2.fromScale(1, 1)
	bandText.TextColor3 = CardTheme.COLOR.TEXT_ON_DARK

	-- Back: drawn over the front while face-down.
	local back = newFrame(root, "Back")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundTransparency = 0
	back.BackgroundColor3 = CardTheme.COLOR.CARD_BACK
	corner(back)
	local pattern = newFrame(back, "Pattern")
	pattern.Position = UDim2.fromScale(0.09, 0.09)
	pattern.Size = UDim2.fromScale(0.82, 0.82)
	stroke(pattern, CardTheme.STROKE.CARD, CardTheme.COLOR.CARD_BACK_PATTERN)
	corner(pattern)

	local isJoker = false
	local staged = false -- a front face has been set
	local flipping = false
	local visual: Visual = "Idle"
	local rest: Visual = "Idle"
	local slotRef: Layout.Slot? = nil
	local motion: Tween? = nil
	local scaling: Tween? = nil
	local flipTween: Tween? = nil
	local destroyed = false

	local function showSide(up: boolean)
		front.Visible = up
		back.Visible = not up
	end
	showSide(false)
	jokerLayer.Visible = false

	local function flying(): boolean
		return visual == "Arriving" or visual == "Returning"
	end

	-- What the stroke and z-order look like for a state. Selection = thickness AND colour (and the lift).
	local function applyStyle(v: Visual)
		local base = if isJoker then CardTheme.STROKE.JOKER else CardTheme.STROKE.CARD
		if v == "Selected" then
			rim.Thickness = base + (CardTheme.STROKE.SELECTED - CardTheme.STROKE.CARD)
			rim.Color = CardTheme.COLOR.ACCENT
		elseif v == "ForcedOut" then
			rim.Thickness = base
			rim.Color = CardTheme.COLOR.NEUTRAL_CUE
		else
			rim.Thickness = base
			rim.Color = CardTheme.COLOR.CARD_STROKE
		end
		local slot = slotRef
		if v == "Idle" and slot ~= nil then
			root.ZIndex = Z_BASE + slot.index
		else
			root.ZIndex = Z_SELECTED
		end
	end

	local function stopMotion()
		if motion then
			motion:Cancel()
			motion = nil
		end
		if scaling then
			scaling:Cancel()
			scaling = nil
		end
	end

	local function glide(
		target: Vector2,
		seconds: number,
		style: Enum.EasingStyle,
		direction: Enum.EasingDirection,
		scaleTo: number,
		onDone: (() -> ())?
	)
		stopMotion()
		local info = TweenInfo.new(seconds, style, direction)
		local tween = TweenService:Create(root, info, { Position = UDim2.fromOffset(target.X, target.Y) })
		motion = tween
		scaling = TweenService:Create(scaler, info, { Scale = scaleTo })
		if scaling then
			scaling:Play()
		end
		if onDone ~= nil then
			tween.Completed:Once(function(state: Enum.PlaybackState)
				if state == Enum.PlaybackState.Completed and not destroyed then
					onDone()
				end
			end)
		end
		tween:Play()
	end

	local function restCentre(): Vector2?
		local slot = slotRef
		if slot == nil then
			return nil
		end
		return CardFaceModule.centreOf(if visual == "Selected" then slot.lifted else slot.card, sol)
	end

	local function snapTo(centre: Vector2)
		stopMotion()
		root.Position = UDim2.fromOffset(centre.X, centre.Y)
		scaler.Scale = 1
	end

	local face: CardFace
	face = {
		setFace = function(_self: CardFace, rank: number?, copy: number?, mode: string?)
			if rank == nil then
				staged = false
				isJoker = false
				jokerLayer.Visible = false
				normal.Visible = true
				if not flipping then
					showSide(false)
				end
				applyStyle(visual)
				return
			end
			if copy == nil and rank ~= Faces.JOKER_RANK then
				error("CardFace.setFace: a non-joker needs a copy")
			end
			local resolved = Faces.faceOf(rank, if copy == nil then 1 else copy, mode)
			isJoker = resolved.isJoker
			jokerLayer.Visible = isJoker
			normal.Visible = not isJoker
			if isJoker then
				local b = resolved.band
				if b == nil then
					error("CardFace.setFace: a joker face came back with no band")
				end
				local hasBar = SHAPE_HAS_BAR[b.shape]
				if hasBar == nil then
					error(`CardFace.setFace: no drawing for band shape {b.shape}`)
				end
				corner1.rank.Text = STAR
				corner1.rank.TextColor3 = CardTheme.COLOR.TEXT_ON_CREAM
				corner1.pip.image.Visible = false
				corner1.pip.text.Visible = true
				corner1.pip.text.Text = JK
				corner1.pip.text.TextColor3 = CardTheme.COLOR.TEXT_ON_CREAM
				bar.Visible = hasBar
				bandText.Text = b.text
			else
				local pip = resolved.pip
				local tint = if pip ~= nil and pip.isRedByDefault
					then CardTheme.COLOR.SUIT_RED
					else CardTheme.COLOR.SUIT_BLACK
				corner1.rank.Text = resolved.rankGlyph
				corner1.rank.TextColor3 = tint
				showPip(corner1.pip, pip, tint)
				mirror.rank.Text = resolved.rankGlyph
				mirror.rank.TextColor3 = tint
				showPip(mirror.pip, pip, tint)
				showPip(centrePip, pip, tint)
			end
			staged = true
			if not flipping then
				showSide(true)
			end
			applyStyle(visual)
		end,

		setVisual = function(_self: CardFace, v: Visual)
			if v == "Idle" or v == "Selected" then
				rest = v
				if flying() then
					applyStyle(v)
					return
				end
			end
			if v == visual then
				return
			end
			visual = v
			applyStyle(v)
			if v == "Idle" or v == "Selected" then
				local centre = restCentre()
				if centre ~= nil then
					glide(centre, TWEEN.SELECT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, nil)
				end
			end
		end,

		moveToSlot = function(_self: CardFace, slot: Layout.Slot, animate: boolean)
			slotRef = slot
			applyStyle(visual)
			if flying() then
				return
			end
			local centre = restCentre()
			if centre == nil then
				return
			end
			if animate then
				glide(centre, TWEEN.CLOSE_GAP, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, nil)
			else
				snapTo(centre)
			end
		end,

		flyTo = function(_self: CardFace, target: Vector2, v: Visual, onDone: (() -> ())?)
			visual = v
			applyStyle(v)
			local function landed()
				if v == "Arriving" or v == "Returning" then
					visual = rest
					applyStyle(visual)
					if rest == "Selected" then
						local centre = restCentre()
						if centre ~= nil then
							glide(centre, TWEEN.SELECT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, nil)
						end
					end
				end
				if onDone ~= nil then
					onDone()
				end
			end
			if v == "InFlight" or v == "ForcedOut" then
				glide(target, TWEEN.SEND, Enum.EasingStyle.Quad, Enum.EasingDirection.In, SHRINK, landed)
			elseif v == "Returning" then
				-- Deliberately slower and bouncier than the send (D-11): it must read as a return. It leaves
				-- the right pile at the size the send shrank it to (placeAt's `shrunk`) and grows as it lands.
				glide(target, TWEEN.RETURN, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 1, landed)
			elseif v == "Arriving" then
				glide(target, TWEEN.DRAW, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, landed)
			else
				glide(target, TWEEN.SELECT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, landed)
			end
		end,

		flip = function(_self: CardFace)
			if destroyed then
				return
			end
			if flipTween then
				flipTween:Cancel()
			end
			flipping = true
			local half = TWEEN.FLIP / 2
			local shut = TweenService:Create(
				root,
				TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.fromOffset(0, size.Y) }
			)
			flipTween = shut
			shut.Completed:Once(function(state: Enum.PlaybackState)
				if state ~= Enum.PlaybackState.Completed or destroyed then
					return
				end
				flipping = false
				showSide(staged)
				local open = TweenService:Create(
					root,
					TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(size.X, size.Y) }
				)
				flipTween = open
				open:Play()
			end)
			shut:Play()
		end,

		instance = function(_self: CardFace): Frame
			return root
		end,

		destroy = function(_self: CardFace)
			if destroyed then
				return
			end
			destroyed = true
			stopMotion()
			if flipTween then
				flipTween:Cancel()
			end
			root:Destroy()
		end,

		setSolution = function(_self: CardFace, s: Layout.Solution)
			sol = s
			size = cardSize(s)
			if not flipping then
				root.Size = UDim2.fromOffset(size.X, size.Y)
			end
		end,

		placeAt = function(_self: CardFace, centre: Vector2, shrunk: boolean)
			snapTo(centre)
			if shrunk then
				scaler.Scale = SHRINK
			end
		end,

		setVisible = function(_self: CardFace, visible: boolean)
			root.Visible = visible
		end,
	}

	root.Parent = parent
	return face
end

return CardFaceModule
