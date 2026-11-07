--!strict
-- THE WHO-WENT CALLOUT: a one-line banner over the table naming whoever just completed (D-31).
--
--  1. WHY IT EXISTS. The information is already public, and "someone is already out there" is the pressure
--     the whole design runs on: there are two fewer spoons than players, and a player who is head-down in
--     their hand on a phone would otherwise miss the diegetic event entirely.
--  2. WHAT IT IS NOT. Round placement and standings were rejected as out of boundary for this phase (they
--     belong to Phases 5 and 6). The words come only from Hints.CALLOUTS, which has no slot for either.
--  3. THE STACK RULE. Simultaneous callouts stack, NEWEST ON TOP, at most Config.Card.MAX_CALLOUTS; a third
--     EVICTS THE OLDEST. They never queue serially: a queue would show a stale name while someone else is
--     already out, and the freshest completion is the one a seeker most needs to know about.
--  4. BUILT ONCE. The banners are created at MAX_CALLOUTS in `new` and shown, hidden and re-texted, never
--     created per completion, because a completion can coincide with another.
--  5. NOTHING HERE TAKES INPUT. Active is false on every banner and every child, so a callout over the table
--     can never eat a tap meant for the hand.
--  6. ONLY THE SELF CALLOUT HAS AN ACCENT UNDERLINE (the fifth and last accent use in CardTheme). The words
--     carry the meaning; the underline is decoration, never the sole carrier (D-24).
--  7. CHECKER FLAG F5, ACCEPTED AND RECORDED. A two-deep stack is 68 design px (32 + 4 + 32), about 24% of
--     the table region at 640x360 and 33% at 844x390, inside the spec's ~40% ceiling. It does sit over the
--     far seats for its visible time. Accepted: the callout is D-31's pressure, and the far seats carry no
--     information a seeker must act on in that window.
--  8. THE TIMING IS ONE TWEEN PER PART: TWEEN.CALLOUT is the delay before the fade and TWEEN.CALLOUT_FADE
--     the fade itself, so there is no timer to cancel and a re-used banner just restarts. The look is M-12.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Card = require(ReplicatedStorage.Shared.Config.Card)
local Hints = require(ReplicatedStorage.Shared.Card.Hints)
local Layout = require(ReplicatedStorage.Shared.Card.Layout)
local CardTheme = require("./CardTheme")

export type Callout = {
	-- A nil name means the local player's own completion.
	show: (self: Callout, displayName: string?, isSelf: boolean) -> (),
	relayout: (self: Callout, solution: Layout.Solution) -> (),
	destroy: (self: Callout) -> (),
}

type Banner = {
	frame: Frame,
	label: TextLabel,
	underline: Frame,
	tweens: { Tween },
	token: number,
}

local TWEEN = Card.TWEEN

local function plain(frame: GuiObject)
	frame.Active = false
	frame.BorderSizePixel = 0
end

local CardCallout = {}

function CardCallout.new(parent: Frame, solution: Layout.Solution): Callout
	local banners: { Banner } = {}
	-- Newest first: active[1] is the top banner.
	local active: { Banner } = {}
	local current = solution
	local destroyed = false

	for i = 1, Card.MAX_CALLOUTS do
		local frame = Instance.new("Frame")
		frame.Name = `Callout{i}`
		plain(frame)
		frame.BackgroundColor3 = CardTheme.COLOR.PLATE
		frame.BackgroundTransparency = 1 - CardTheme.PLATE_OPACITY
		frame.Visible = false

		local label = Instance.new("TextLabel")
		label.Name = "Words"
		plain(label)
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = CardTheme.FONT.BOLD
		label.TextSize = CardTheme.TEXT_SIZE.BODY
		label.TextColor3 = CardTheme.COLOR.TEXT_ON_DARK
		label.TextScaled = false
		label.RichText = false
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Text = ""
		label.Parent = frame

		local underline = Instance.new("Frame")
		underline.Name = "SelfUnderline"
		plain(underline)
		underline.BackgroundColor3 = CardTheme.COLOR.ACCENT
		underline.AnchorPoint = Vector2.new(0, 1)
		underline.Position = UDim2.fromScale(0, 1)
		underline.Size = UDim2.new(1, 0, 0, CardTheme.STROKE.CARD)
		underline.Visible = false
		underline.Parent = frame

		frame.Parent = parent
		table.insert(banners, { frame = frame, label = label, underline = underline, tweens = {}, token = 0 })
	end

	local function place(banner: Banner, rect: Layout.Rect)
		local s = current
		banner.frame.Position = UDim2.fromOffset(
			math.round((rect.x - s.tableRegion.x) / s.scale),
			math.round((rect.y - s.tableRegion.y) / s.scale)
		)
		banner.frame.Size = UDim2.fromOffset(math.round(rect.w / s.scale), math.round(rect.h / s.scale))
	end

	local function layoutActive()
		for i, banner in active do
			local rect = current.calloutStack[i]
			if rect ~= nil then
				place(banner, rect)
			end
		end
	end

	local function stop(banner: Banner)
		for _, tween in banner.tweens do
			tween:Cancel()
		end
		table.clear(banner.tweens)
		banner.token += 1
	end

	local function hide(banner: Banner)
		stop(banner)
		banner.frame.Visible = false
		local at = table.find(active, banner)
		if at ~= nil then
			table.remove(active, at)
			layoutActive()
		end
	end

	local function pickBanner(): Banner
		if #active >= Card.MAX_CALLOUTS then
			-- The oldest is evicted, never queued behind (header point 3).
			local oldest = active[#active]
			hide(oldest)
			return oldest
		end
		for _, banner in banners do
			if table.find(active, banner) == nil then
				return banner
			end
		end
		error("CardCallout: no free banner")
	end

	local fadeInfo =
		TweenInfo.new(TWEEN.CALLOUT_FADE, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, TWEEN.CALLOUT)

	local callout: Callout
	callout = {
		show = function(_self: Callout, displayName: string?, isSelf: boolean)
			if destroyed then
				return
			end
			local banner = pickBanner()
			stop(banner)
			banner.label.Text = if isSelf or displayName == nil
				then Hints.CALLOUTS.selfOut()
				else Hints.CALLOUTS.other(displayName)
			banner.underline.Visible = isSelf
			banner.frame.BackgroundTransparency = 1 - CardTheme.PLATE_OPACITY
			banner.label.TextTransparency = 0
			banner.underline.BackgroundTransparency = 0
			banner.frame.Visible = true
			table.insert(active, 1, banner)
			layoutActive()

			local token = banner.token
			local fade = TweenService:Create(banner.frame, fadeInfo, { BackgroundTransparency = 1 })
			local fadeText = TweenService:Create(banner.label, fadeInfo, { TextTransparency = 1 })
			local fadeLine = TweenService:Create(banner.underline, fadeInfo, { BackgroundTransparency = 1 })
			banner.tweens = { fade, fadeText, fadeLine }
			fade.Completed:Once(function()
				if not destroyed and banner.token == token then
					hide(banner)
				end
			end)
			fade:Play()
			fadeText:Play()
			fadeLine:Play()
		end,
		relayout = function(_self: Callout, newSolution: Layout.Solution)
			current = newSolution
			layoutActive()
		end,
		destroy = function(_self: Callout)
			if destroyed then
				return
			end
			destroyed = true
			for _, banner in banners do
				stop(banner)
				banner.frame:Destroy()
			end
			table.clear(active)
		end,
	}
	return callout
end

return CardCallout
