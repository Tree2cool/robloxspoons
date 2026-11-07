--!strict
-- THE SURFACE BEHIND THE PURE FLOURISH DRIVER, and the two default flourishes (CARD-17, CARD-18 seam; D-30,
-- D-32, D-33; checker FLAG F8). src/shared/Card/Flourish.luau owns the logic; this file owns the Instances.
--
--  1. THE DRIVER OWNS THE DURATION, THE CUT-OFF AND THE PERIODIC SCAN. This file creates, scans and destroys,
--     and adds NO TIMER OF ITS OWN: a second timer is a second duration, and D-32 makes an unequal duration a
--     pay-to-win defect. The only scheduling calls below are the Scheduler's own three, one each, and the
--     driver is the only caller of them.
--  2. F8, RESOLVED. The UI root is a Folder inside a DEDICATED ScreenGui whose DisplayOrder is
--     Config.Card.FLOURISH_DISPLAY_ORDER, strictly below the hand's (checked again at runtime), so an Active
--     object a flourish creates cannot sit over the hand and sink a tap. The ScreenGui persists for the
--     session; only the Folder is destroyed per flight.
--  3. THE SCAN LOOKS FOR FIVE KINDS, NOT ONE: an Active GuiObject, an Interactable button, a ClickDetector, a
--     ProximityPrompt and a TextBox. Each is a way to take input without being an Active frame, and F8's
--     point is that an input sink mid-flight silently breaks D-30's instant control return, which is what
--     protects a finisher's score (find order drives SCORE-01..03). destroyOffenders destroys exactly what
--     scan reports, so a finding stops sinking input NOW rather than at the cut-off.
--     DEVIATION FROM THE PLAN'S WORDING, recorded: the plan says to flag every GuiObject whose Interactable
--     is true. Interactable defaults to true on every GuiObject, so that rule would flag every plain Frame
--     and destroy the default flourishes' own cards on the first scan. Interactable is therefore tested on
--     GuiButton only, where it is what decides whether a click lands. Whether a plain Frame with
--     Interactable = true and Active = false sinks input is a Roblox behaviour not verified here (M-17).
--  4. TWO RECORDED LIMITS. A synchronous infinite loop inside `play` cannot be stopped in Luau, and "every
--     parent a flourish could reach" cannot be enumerated, so snapshot/diff is a SCAN, not a proof. The
--     defences are the driver's timer, its periodic scan and code review of any registered flourish.
--     The snapshot watches ONLY the dedicated containers this file owns (the flourish ScreenGui, the
--     flourish Folder in Workspace, the card ScreenGui). Watching Workspace itself would let destroyEscaped
--     delete a respawning character, so that is deliberately not done.
--  5. PHASE 4 SHIPS ONLY THE DEFAULTS, and the registry reaches the driver as an ARGUMENT. What is lint
--     enforced is the other side: src/shared/Card/Flourish.luau is a guarded root by pure-zone location and
--     takes the registry as an argument, so no gameplay or decision module can reach a skin. THIS file is the
--     renderer and is deliberately NOT a guarded root, because Phase 7 needs it to import deck-skin data
--     (CARD-18, D-38 withdrawn). Nothing here claims otherwise.
--  6. EVERY 3D PART COMES FROM ONE HELPER that sets Anchored, CanCollide = false, CanQuery = false and
--     CanTouch = false: RaycastParams.RespectCanCollide defaults to false, so a queryable cosmetic would
--     block Phase 5's line-of-sight raycast. tests/card/flourish_surface.spec.luau counts the sites.
--  7. THE DEFAULTS EXECUTE Flourish.DEFAULTS' keyframe data and add nothing to it: Completion 0.3 + 0.5 + 0.4
--     = 1.2 s inside the 1.5 s cut-off, Deal settled by 0.6 s. The Deal kind is played at RoundStart for the
--     LOCAL seat only (CardClient); Completion is played for every seat that completes.
--  8. NOTHING HERE IS VERIFIED ON A DEVICE. Whether the faces flip legibly, the slide reads, the deal feels
--     like a deal, and whether the sting lands with it, are M-17 and M-12.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Card = require(ReplicatedStorage.Shared.Config.Card)
local Round = require(ReplicatedStorage.Shared.Config.Round)
local Faces = require(ReplicatedStorage.Shared.Card.Faces)
local Flourish = require(ReplicatedStorage.Shared.Card.Flourish)
local CardHud = require("./CardHud")
local CardTheme = require("./CardTheme")

-- What the default flourishes need to know about the table. Supplied by CardClient from public facts only.
export type DealGeometry = {
	-- Pixel centres relative to the safe-area origin (where the flourish ScreenGui starts).
	from: Vector2,
	to: { Vector2 },
	size: Vector2,
}
export type Stage = {
	seatPosition: (seat: number) -> Vector3?,
	centre: () -> Vector3?,
	deal: () -> DealGeometry?,
}

local CARD = Card.TABLE_CARD_STUDS
local HALF = 2

-- A session-long container. Created on first use, never per flight.
local flourishGui: ScreenGui? = nil

local function ensureGui(hud: CardHud.Hud): ScreenGui
	local existing = flourishGui
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local gui = CardHud.newGui("CardFlourish", Card.FLOURISH_DISPLAY_ORDER)
	-- F8: strictly below the hand. Checked on the live objects, not only on the two config numbers.
	if gui.DisplayOrder >= hud:gui().DisplayOrder then
		gui:Destroy()
		error("CardFlourish: the flourish ScreenGui must sit strictly below the hand's DisplayOrder")
	end
	CardHud.mount(gui)
	flourishGui = gui
	return gui
end

-- Which kind of input sink an instance is, or nil. ONE predicate, shared by scan and destroyOffenders, so
-- what is reported is exactly what is destroyed (header point 3).
local function offenderKind(inst: Instance): string?
	if inst:IsA("TextBox") then
		return "TextBox"
	end
	if inst:IsA("ClickDetector") then
		return "ClickDetector"
	end
	if inst:IsA("ProximityPrompt") then
		return "ProximityPrompt"
	end
	if inst:IsA("GuiButton") and (inst :: GuiButton).Interactable then
		return "Interactable"
	end
	if inst:IsA("GuiObject") and (inst :: GuiObject).Active then
		return "Active"
	end
	return nil
end

local function offendersUnder(root: Instance): { { inst: Instance, kind: string } }
	local found: { { inst: Instance, kind: string } } = {}
	for _, descendant in root:GetDescendants() do
		local kind = offenderKind(descendant)
		if kind ~= nil then
			table.insert(found, { inst = descendant, kind = kind })
		end
	end
	return found
end

type Snapshot = { [Instance]: { [Instance]: boolean } }

local CardFlourish = {}

function CardFlourish.makeSurface(hud: CardHud.Hud, workspaceRoot: Instance): Flourish.Surface
	-- Every root currently alive, so a second flight's root is never mistaken for an escape from the first.
	local liveRoots: { [Instance]: boolean } = {}

	local function watched(): { Instance }
		local parents: { Instance } = { workspaceRoot, ensureGui(hud) }
		local cardGui = hud:gui()
		if cardGui.Parent ~= nil then
			table.insert(parents, cardGui)
		end
		return parents
	end

	local function escapedSince(snapshot: Snapshot): { Instance }
		local escaped: { Instance } = {}
		for parent, before in snapshot do
			if parent.Parent ~= nil then
				for _, child in parent:GetChildren() do
					if not before[child] and not liveRoots[child] then
						table.insert(escaped, child)
					end
				end
			end
		end
		return escaped
	end

	local surface: Flourish.Surface
	surface = {
		createRoot = function(kind: Flourish.Kind): Flourish.Root
			local folder = Instance.new("Folder")
			folder.Name = `Flourish{kind}`
			local where = (Flourish.ROOT_SURFACE :: any)[kind]
			if where == "ScreenGui" then
				folder.Parent = ensureGui(hud)
			else
				folder.Parent = workspaceRoot
			end
			liveRoots[folder] = true
			return folder
		end,
		destroyRoot = function(root: Flourish.Root)
			liveRoots[root :: Instance] = nil
			(root :: Instance):Destroy()
		end,
		scan = function(root: Flourish.Root): { string }
			local descriptions: { string } = {}
			for _, offender in offendersUnder(root :: Instance) do
				table.insert(descriptions, `{offender.kind}:{offender.inst.ClassName}:{offender.inst:GetFullName()}`)
			end
			return descriptions
		end,
		destroyOffenders = function(root: Flourish.Root): number
			local found = offendersUnder(root :: Instance)
			for _, offender in found do
				offender.inst:Destroy()
			end
			return #found
		end,
		snapshot = function(): any
			local snapshot: Snapshot = {}
			for _, parent in watched() do
				local children: { [Instance]: boolean } = {}
				for _, child in parent:GetChildren() do
					children[child] = true
				end
				snapshot[parent] = children
			end
			return snapshot
		end,
		diff = function(snapshot: any): { string }
			local descriptions: { string } = {}
			for _, child in escapedSince(snapshot :: Snapshot) do
				table.insert(descriptions, `{child.ClassName}:{child:GetFullName()}`)
			end
			return descriptions
		end,
		destroyEscaped = function(snapshot: any): number
			local escaped = escapedSince(snapshot :: Snapshot)
			for _, child in escaped do
				child:Destroy()
			end
			return #escaped
		end,
	}
	return surface
end

local function cancelThread(thread: thread)
	task.cancel(thread)
end

-- The Scheduler the pure driver is built on, over task.delay / task.spawn / task.cancel, exactly as
-- RoundDriver builds its own so that `cancel` really cancels. These three calls are the only scheduling in
-- this file (header point 1).
local function makeScheduler(): Flourish.Scheduler
	return {
		nowDeci = function(): number
			-- Display only; the driver never reads it.
			return math.floor(time() * Round.DECISECONDS_PER_SECOND)
		end,
		delay = function(seconds: number, fn: () -> ()): () -> ()
			local fired = false
			local thread = task.delay(seconds, function()
				fired = true
				fn()
			end)
			return function()
				-- A callback cancelling its own timer from inside itself would abort its own teardown.
				if not fired then
					cancelThread(thread)
				end
			end
		end,
		spawn = function(fn: () -> ()): Flourish.Thread
			return task.spawn(fn)
		end,
		cancel = function(thread: Flourish.Thread)
			cancelThread(thread :: thread)
		end,
	}
end

-- The ONE 3D part-creation site in this file (header point 6).
local function newCardPart(parent: Instance, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = CardTheme.COLOR.CARD_BACK
	part.Material = Enum.Material.SmoothPlastic
	part.Size = Vector3.new(CARD.WIDTH, CARD.THICKNESS, CARD.LENGTH)
	part.Parent = parent
	return part
end

local function stepSeconds(): { [string]: number }
	local seconds: { [string]: number } = {}
	for _, step in Flourish.DEFAULTS.Completion.steps do
		seconds[step.name] = step.seconds
	end
	return seconds
end

local function playAll(tweens: { Tween })
	for _, tween in tweens do
		tween:Play()
	end
	if #tweens > 0 then
		tweens[#tweens].Completed:Wait()
	end
end

-- The face drawn on a flipped card. Public rank only; the copy index just picks the pip.
local function faceTextOf(rank: number, copy: number): (string, Color3)
	local ok, face = pcall(Faces.faceOf, rank, copy, nil)
	if not ok then
		return "", CardTheme.COLOR.TEXT_ON_CREAM
	end
	local pip = (face :: Faces.Face).pip
	local text = (face :: Faces.Face).rankGlyph
	local color = CardTheme.COLOR.SUIT_BLACK
	if pip ~= nil then
		text ..= pip.glyph
		if pip.isRedByDefault then
			color = CardTheme.COLOR.SUIT_RED
		end
	end
	return text, color
end

type FaceCard = { part: Part, label: TextLabel, text: string }

local function completionFlourish(stage: Stage): Flourish.Entry
	return {
		kind = "Completion",
		play = function(ctx: Flourish.FlourishContext)
			local origin = stage.seatPosition(ctx.seat)
			local count = #ctx.faces
			if origin == nil or count == 0 then
				return
			end
			local seconds = stepSeconds()
			local flip, hold, slide = seconds.flip, seconds.hold, seconds.slide
			local cards: { FaceCard } = {}
			for i, rank in ctx.faces do
				local part = newCardPart(ctx.root, `Face{i}`)
				local offset = (i - (count + 1) / HALF) * Card.FLOURISH_FAN_SPACING_STUDS
				part.Position = origin + Vector3.new(offset, CARD.THICKNESS, 0)
				local gui = Instance.new("SurfaceGui")
				gui.Face = Enum.NormalId.Top
				gui.LightInfluence = 0
				local label = Instance.new("TextLabel")
				label.Active = false
				label.BackgroundTransparency = 1
				label.BorderSizePixel = 0
				label.Size = UDim2.fromScale(1, 1)
				label.FontFace = CardTheme.FONT.BOLD
				label.TextScaled = true
				label.Text = ""
				local text, color = faceTextOf(rank, i)
				label.TextColor3 = color
				label.Parent = gui
				gui.Parent = part
				-- Held face-down (empty text) until the flip reaches its midpoint.
				table.insert(cards, { part = part, label = label, text = text })
			end

			-- Flip: narrow to nothing, swap to the face, widen again. Two halves of `flip`.
			local narrow: { Tween } = {}
			local widen: { Tween } = {}
			local halfFlip = TweenInfo.new(flip / HALF, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			for _, card in cards do
				table.insert(
					narrow,
					TweenService:Create(card.part, halfFlip, { Size = Vector3.new(0, CARD.THICKNESS, CARD.LENGTH) })
				)
				table.insert(
					widen,
					TweenService:Create(
						card.part,
						halfFlip,
						{ Size = Vector3.new(CARD.WIDTH, CARD.THICKNESS, CARD.LENGTH) }
					)
				)
			end
			playAll(narrow)
			for _, card in cards do
				card.part.Color = CardTheme.COLOR.CARD_FACE
				card.label.Text = card.text
			end
			playAll(widen)

			task.wait(hold)

			-- Slide to the table centre and fade.
			local target = stage.centre() or origin
			local away: { Tween } = {}
			local slideInfo = TweenInfo.new(slide, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			for _, card in cards do
				table.insert(away, TweenService:Create(card.part, slideInfo, { Position = target, Transparency = 1 }))
				table.insert(away, TweenService:Create(card.label, slideInfo, { TextTransparency = 1 }))
			end
			playAll(away)
		end,
	}
end

local function dealFlourish(stage: Stage): Flourish.Entry
	return {
		kind = "Deal",
		play = function(ctx: Flourish.FlourishContext)
			local geometry = stage.deal()
			if geometry == nil or #geometry.to == 0 then
				return
			end
			local def = Flourish.DEFAULTS.Deal
			-- Each card flies for whatever is left of settleBySeconds after the last card has started, so the
			-- whole deal is settled by exactly settleBySeconds.
			local flight = def.settleBySeconds - (def.cards - 1) * def.staggerSeconds
			local info = TweenInfo.new(flight, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tweens: { Tween } = {}
			for i = 1, def.cards do
				local back = Instance.new("Frame")
				back.Name = `Deal{i}`
				back.Active = false
				back.BorderSizePixel = 0
				back.BackgroundColor3 = CardTheme.COLOR.CARD_BACK
				back.AnchorPoint = Vector2.new(0.5, 0.5)
				back.Size = UDim2.fromOffset(geometry.size.X, geometry.size.Y)
				back.Position = UDim2.fromOffset(geometry.from.X, geometry.from.Y)
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, CardTheme.CORNER_RADIUS)
				corner.Parent = back
				back.Parent = ctx.root
				local slot = geometry.to[((i - 1) % #geometry.to) + 1]
				local tween = TweenService:Create(back, info, { Position = UDim2.fromOffset(slot.X, slot.Y) })
				table.insert(tweens, tween)
				tween:Play()
				if i < def.cards then
					task.wait(def.staggerSeconds)
				end
			end
			if #tweens > 0 then
				tweens[#tweens].Completed:Wait()
			end
		end,
	}
end

function CardFlourish.defaults(stage: Stage): { [string]: Flourish.Entry }
	return {
		Completion = completionFlourish(stage),
		Deal = dealFlourish(stage),
	}
end

-- The single call CardClient makes. The duration, the scan interval and the registry are the only inputs the
-- driver gets, and the duration is the one config number: no flourish can bring its own (D-32).
function CardFlourish.makeDriver(hud: CardHud.Hud, workspaceRoot: Instance, stage: Stage): Flourish.Driver
	return Flourish.new({
		surface = CardFlourish.makeSurface(hud, workspaceRoot),
		scheduler = makeScheduler(),
		durationSeconds = Card.FLOURISH_DURATION_SECONDS,
		scanIntervalSeconds = Card.FLOURISH_SCAN_INTERVAL_SECONDS,
		registry = CardFlourish.defaults(stage),
		onViolation = function(message: string)
			warn("CardFlourish", message)
		end,
	})
end

return CardFlourish
