--!strict
-- The status strip: one line of text that carries every hint, countdown, strike warning and cue, plus the
-- AFK drain bar beneath it. It composes no string of its own: every word comes from Hints, and the only
-- string literals here are instance class and property names.
--
--  1. PRECEDENCE, STATED ONCE: countdown beats transient message beats hint. A countdown is a live
--     deadline the player can still act on; a message is history; a hint is the standing instruction.
--  2. ONE LINE AT ANY ACCESSIBILITY TEXT SIZE (D-36, checker FLAG F4). The platform's preferred-text-size
--     setting scales text even when automatic scaling is off, so the label carries a UITextSizeConstraint
--     capped at the body size. THE ACCEPTED COST, stated plainly: a player who chose the largest text gets
--     smaller text here than they asked for, in the exact place strike warnings appear. That was chosen
--     over wrapping, which forces a third re-derivation of the HandZone budget (the strip height is what
--     keeps the lifted card 4 px clear), and over truncation, which would cut the clause saying what is
--     about to happen. The longest strip string is 34 characters, hard against the cap, so there is no
--     headroom to spend. Whether it really holds one line at the largest setting is M-12, not proven here.
--  3. THE STRIP NEVER TAKES INPUT. Nothing in it is Active.
--  4. THE DRAIN BAR SHOWS ONLY WITH A COUNTDOWN (D-16): nothing for the first 6 s of the 8 s window, then
--     the countdown and the bar. The caller says when; the strip decides nothing else. The fraction is the
--     remaining seconds over the warn threshold in Config.Card.
--  5. HAND-4 AFK DECISION (the UI-SPEC "Minor" flag, resolved): at hand 4 the AFK cue pulses NOTHING. The
--     countdown text and the drain bar already carry it redundantly, and the left-pile ring keeps its one
--     meaning, "you can draw". One ring with two meanings is a cue that teaches nothing, so the pile
--     renderer is told nothing about the AFK state.
--  6. The parent is the Hud's handZone frame, which lays out in design units; every rect here is the
--     solved physical rect converted relative to that zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardConfig = require(ReplicatedStorage.Shared.Config.Card)
local Hints = require(ReplicatedStorage.Shared.Card.Hints)
local Layout = require(ReplicatedStorage.Shared.Card.Layout)
local CardTheme = require("./CardTheme")

export type Strip = {
	setHint: (self: Strip, state: Hints.State, kind: Hints.InputKind) -> (),
	-- A transient message that overrides the hint for `seconds`, then reverts. Used for the strike
	-- lines, the private forced-pass cue, the stall cue and the right-pile sink hint.
	setMessage: (self: Strip, text: string, seconds: number) -> (),
	-- D-16: nothing for the first 6 s of the 8 s window, then the countdown and the drain bar. The
	-- strip is told the remaining seconds and the warn threshold, and decides nothing else.
	setCountdown: (self: Strip, owes: "Pass" | "Draw", secondsLeft: number?) -> (),
	clearCountdown: (self: Strip) -> (),
	relayout: (self: Strip, solution: Layout.Solution) -> (),
	destroy: (self: Strip) -> (),
}

local CardStrip = {}

function CardStrip.new(parent: Frame, solution: Layout.Solution): Strip
	local label = Instance.new("TextLabel")
	label.Name = "Strip"
	label.Active = false
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = CardTheme.FONT.BOLD
	label.TextSize = CardTheme.TEXT_SIZE.BODY
	label.TextColor3 = CardTheme.COLOR.TEXT_ON_DARK
	label.TextScaled = false
	label.RichText = false
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = ""

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = CardTheme.TEXT_SIZE.BODY
	constraint.Parent = label

	local track = Instance.new("Frame")
	track.Name = "DrainTrack"
	track.Active = false
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Visible = false

	local fill = Instance.new("Frame")
	fill.Name = "DrainFill"
	fill.Active = false
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = CardTheme.COLOR.ACCENT
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = track

	local hintText = ""
	local messageText: string? = nil
	local messageThread: thread? = nil
	local countdownText: string? = nil
	local destroyed = false

	local function render()
		if destroyed then
			return
		end
		label.Text = countdownText or messageText or hintText
		track.Visible = countdownText ~= nil
	end

	local function cancelMessage()
		if messageThread then
			task.cancel(messageThread)
			messageThread = nil
		end
		messageText = nil
	end

	local function place(s: Layout.Solution)
		local zone = s.handZone
		local textH = s.strip.h - s.drain.h
		label.Position =
			UDim2.fromOffset(math.round((s.strip.x - zone.x) / s.scale), math.round((s.strip.y - zone.y) / s.scale))
		label.Size = UDim2.fromOffset(math.round(s.strip.w / s.scale), math.round(textH / s.scale))
		track.Position =
			UDim2.fromOffset(math.round((s.drain.x - zone.x) / s.scale), math.round((s.drain.y - zone.y) / s.scale))
		track.Size = UDim2.fromOffset(math.round(s.drain.w / s.scale), math.round(s.drain.h / s.scale))
	end

	local strip: Strip
	strip = {
		setHint = function(_self: Strip, state: Hints.State, kind: Hints.InputKind)
			hintText = Hints.HINT[state][kind]
			render()
		end,
		setMessage = function(_self: Strip, text: string, seconds: number)
			cancelMessage()
			messageText = text
			messageThread = task.delay(seconds, function()
				messageThread = nil
				messageText = nil
				render()
			end)
			render()
		end,
		setCountdown = function(_self: Strip, owes: "Pass" | "Draw", secondsLeft: number?)
			if secondsLeft == nil then
				countdownText = nil
			else
				countdownText = Hints.MESSAGES.countdown(owes, secondsLeft)
				fill.Size = UDim2.fromScale(math.clamp(secondsLeft / CardConfig.AFK_WARN_SECONDS, 0, 1), 1)
			end
			render()
		end,
		clearCountdown = function(_self: Strip)
			countdownText = nil
			render()
		end,
		relayout = function(_self: Strip, s: Layout.Solution)
			place(s)
		end,
		destroy = function(_self: Strip)
			if destroyed then
				return
			end
			cancelMessage()
			destroyed = true
			label:Destroy()
			track:Destroy()
		end,
	}

	place(solution)
	label.Parent = parent
	track.Parent = parent
	return strip
end

return CardStrip
