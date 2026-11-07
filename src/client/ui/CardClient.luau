--!strict
-- THE ONE WIRING FILE. It owns the reducer, the HUD, the hand, the piles, the strip, the controls and the
-- input, and it is the only place they know about each other. Everything it does is plumbing: any `if` that
-- decides a game outcome belongs in src/shared/Card/. That sentence is this file's standard.
--
--  1. THE onCard HANDLER IS SYNCHRONOUS AND NEVER YIELDS (Pitfall 11). V-12 guarantees handler START order
--     only, so a yielding handler could be overtaken and the client would fold events out of order. The one
--     yield in this module's lifetime, resolving the remotes, happens in start, before anything is
--     connected.
--  2. THE HAND COMES ONLY FROM Sync (Pitfall 12). A public Drew for the local seat carries an id with no
--     face, so folding it into the hand would draw a blank card. The Table handler never touches the hand.
--  3. A HIDER NEVER GETS THE CARD OVERLAY. The UI is built only if the local player appears in
--     RoundStart.seats. The rotate prompt is the one exception and it is made in start, seated or not,
--     because a hider on a phone still needs it.
--  4. EXACTLY ONE PATH FROM AN INPUT TO A SENT INTENT, AND IT GOES THROUGH THE REDUCER. Pointer taps, the
--     keyboard and the gamepad all end in a reducer method, and the Emit it returns, if any, is the only
--     thing sent. That is what makes plan 04-09's CARD-15 assertion ("one tap alone never sends") describe
--     the shipped game and not a model of it. This is the only client file that sends a card intent.
--  5. D-30'S ORDER IS Controls.onLocalCompleted'S ORDER AND IS NOT RE-IMPLEMENTED HERE. The pure module
--     destroys the overlay, restores the controls and starts the flourish, in that order; this file only
--     supplies the callbacks.
--  6. nowDeci HERE IS A CLIENT-LOCAL DISPLAY CLOCK ONLY (rule 5). It accumulates the frame step, it is never
--     sent, never compared with a server value, and nothing a score depends on reads it. It exists to age
--     the reducer's pending entries for the watchdog. The countdown is the one place a server time is read,
--     and it only decides whether to show a number.
--  7. A FRESH REDUCER PER ROUND. ackSeq is not reset within a round, so reuse would carry a stale high-water
--     mark. Order matters twice more: relayout BEFORE the apply that changes the hand size, and the joker
--     mode set BEFORE the first apply that can contain a joker. Both are silent if missed.
--  8. D-12: A HARD REJECTION SAYS NOTHING. No reject code reaches this file and none is shown. A rejected
--     card simply returns, identically to a correction.
--  9. CONTAINED DISPATCH. Every handler runs inside xpcall and reports through warn, so a renderer error
--     does not kill the only handler the client has. A dead handler silently stops every later message, which
--     is worse than one visible error.
-- 10. THE JOKER EXPLAINER is a lookup keyed by the mode from RoundStart, with no branch on its value, so the
--     live JOKER_MODE flag is never made to lie to the player (D-23).
-- 11. KNOWN GAPS, recorded rather than papered over. (a) The Table payload carries no per-seat depth
--     snapshot, so the depth list handed to the reducer is whatever it already held (empty); plan 04-19's
--     stacks need a server-supplied depth field. (b) There is no round-end message among the five kinds, so
--     the overlay ends on the local seat's removal or the next RoundStart. (c) A keyboard or gamepad send
--     tells the hand through markSent, since it does not pass through a strip. (d) Nothing about feel,
--     controls or audio on a device is proven here: M-11, M-12, M-13, M-16.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Card = require(ReplicatedStorage.Shared.Config.Card)
local Round = require(ReplicatedStorage.Shared.Config.Round)
local Faces = require(ReplicatedStorage.Shared.Card.Faces)
local Hints = require(ReplicatedStorage.Shared.Card.Hints)
local Layout = require(ReplicatedStorage.Shared.Card.Layout)
local Prediction = require(ReplicatedStorage.Shared.Card.Prediction)
local ClientNet = require("../net/ClientNet")
local CardControls = require("./CardControls")
local CardHand = require("./CardHand")
local CardHud = require("./CardHud")
local CardInput = require("./CardInput")
local CardPiles = require("./CardPiles")
local CardStrip = require("./CardStrip")

export type Hooks = {
	-- Plan 04-19 parents into these. `payload` is the RoundStart table (seat poses and jokerMode).
	onRoundStart: ((payload: any, localSeat: number) -> ())?,
	onTable: ((events: { any }, depths: { number }, localSeat: number) -> ())?,
	-- Called by Controls.onLocalCompleted LAST, after the overlay is gone and the controls are back.
	startFlourish: ((completed: any) -> ())?,
}

export type CardClient = {
	start: (self: CardClient) -> (),
	destroy: (self: CardClient) -> (),
	setHooks: (self: CardClient, hooks: Hooks) -> (),
	hud: (self: CardClient) -> CardHud.Hud?,
}

type Ui = {
	hud: CardHud.Hud,
	hand: CardHand.Hand,
	piles: CardPiles.Piles,
	strip: CardStrip.Strip,
	input: CardInput.Input,
	handSize: number,
	kind: Hints.InputKind,
	explaining: boolean,
}

type RoundState = {
	reducer: Prediction.Reducer,
	localSeat: number,
	ui: Ui?,
	completed: any,
}

local HAND_FULL = 5
local SINK_STATE: Hints.State = "RightPileSink"
local HAND_OWES_DRAW = HAND_FULL - 1
local TWEEN = Card.TWEEN

local soundOf: { [string]: string } = { Draw = Card.AUDIO.DRAW, Pass = Card.AUDIO.PASS }

-- D-33. An empty asset id is silent by contract, not an error (M-16 supplies the ids).
local function playSound(assetId: string)
	if assetId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Volume = Card.AUDIO.VOLUME
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
end

-- One entry per notice code; an unknown code shows nothing rather than an invented line (D-12).
local noticeCopy: { [string]: (notice: any) -> string } = {
	ForcedPass = function(_notice: any): string
		return Hints.MESSAGES.forcedPass()
	end,
	Strike = function(notice: any): string
		return Hints.MESSAGES.strike(notice.strikes, notice.owes)
	end,
	Benched = function(_notice: any): string
		return Hints.MESSAGES.benched()
	end,
}

-- Display only: which hint row and which pile state the reducer's picture calls for.
local function hintStateOf(display: Prediction.Display, selected: number?): Hints.State
	if #display.hand == HAND_FULL then
		if selected ~= nil then
			return "Selected"
		end
		return "Hand5Idle"
	end
	if display.inbox >= 1 then
		return "Hand4CanDraw"
	end
	return "Hand4Empty"
end

local function leftStateOf(display: Prediction.Display): CardPiles.LeftState
	if #display.hand == HAND_FULL then
		return "Locked"
	end
	if display.inbox >= 1 then
		return "Drawable"
	end
	return "Empty"
end

local function jokerSelected(display: Prediction.Display, selected: number?): boolean
	if selected == nil then
		return false
	end
	for _, c in display.hand do
		if c.cardId == selected then
			return c.rank == Faces.JOKER_RANK
		end
	end
	return false
end

local function traceOf(e: unknown): string
	return debug.traceback(tostring(e), 2)
end

local CardClient = {}

function CardClient.new(): CardClient
	local conns: { RBXScriptConnection } = {}
	local rotate: CardHud.RotatePrompt? = nil
	local started = false
	local hooks: Hooks = {}
	local jokerMode: string? = nil
	local round: RoundState? = nil
	local clockSeconds = 0

	-- Header point 6.
	local function nowDeci(): number
		return math.floor(clockSeconds * Round.DECISECONDS_PER_SECOND)
	end

	local destroyUi: () -> ()
	local startFlourish: () -> ()
	local controls = CardControls.new(function()
		destroyUi()
	end, function()
		startFlourish()
	end)

	destroyUi = function()
		local r = round
		if r == nil or r.ui == nil then
			return
		end
		local ui = r.ui :: Ui
		r.ui = nil
		-- The hit surface goes first and in this frame: gone, not faded (D-30).
		ui.hud:destroy()
		ui.input:destroy()
		ui.hand:destroy()
		ui.piles:destroy()
		ui.strip:destroy()
	end

	startFlourish = function()
		local fn = hooks.startFlourish
		local r = round
		if fn ~= nil and r ~= nil then
			fn(r.completed)
		end
	end

	local function teardown()
		destroyUi()
		controls:restore()
	end

	local function relayoutAll(ui: Ui, solution: Layout.Solution)
		ui.hand:relayout(solution)
		ui.piles:relayout(solution)
		ui.strip:relayout(solution)
	end

	local function refreshCountdown()
		local r = round
		if r == nil or r.ui == nil then
			return
		end
		local ui = r.ui :: Ui
		local deadline = r.reducer:idleDeadlineUnix()
		if deadline == nil then
			ui.strip:clearCountdown()
			return
		end
		local secondsLeft = deadline - Workspace:GetServerTimeNow()
		if secondsLeft > Card.AFK_WARN_SECONDS then
			ui.strip:clearCountdown()
			return
		end
		local owes: "Pass" | "Draw" = if #r.reducer:display().hand == HAND_FULL then "Pass" else "Draw"
		ui.strip:setCountdown(owes, math.max(0, secondsLeft))
	end

	local function explainJoker(ui: Ui, display: Prediction.Display, selected: number?)
		local isJoker = jokerSelected(display, selected)
		if isJoker and not ui.explaining then
			ui.explaining = true
			local text = if jokerMode ~= nil then Faces.JOKER_EXPLAINER[jokerMode] else nil
			if text ~= nil then
				ui.strip:setMessage(text, TWEEN.NOTICE)
			end
		elseif not isJoker and ui.explaining then
			ui.explaining = false
			ui.strip:clearMessage()
		end
	end

	-- Every transition ends here: the reducer's own display goes to the renderer, which recomputes nothing.
	local function refresh(changes: { Prediction.Change })
		local r = round
		if r == nil or r.ui == nil then
			return
		end
		local ui = r.ui :: Ui
		local display = r.reducer:display()
		local size = #display.hand
		-- Header point 7: relayout BEFORE the apply that changes the hand size.
		if (size == HAND_FULL or size == HAND_OWES_DRAW) and size ~= ui.handSize then
			ui.handSize = size
			relayoutAll(ui, ui.hud:resolve(size))
		end
		local selected = r.reducer:selectedCardId()
		ui.hand:apply(display, changes, selected)
		ui.piles:setLeft(display.inbox, leftStateOf(display))
		ui.piles:setRight(display.downstream)
		ui.strip:setHint(hintStateOf(display, selected), ui.kind)
		explainJoker(ui, display, selected)
		refreshCountdown()
	end

	local function send(emit: Prediction.Emit)
		ClientNet.send(emit.name, emit.payload)
		playSound(soundOf[emit.name] or "")
	end

	local function onTapSlot(cardId: number?)
		local r = round
		if r == nil or r.ui == nil then
			return
		end
		local emit = r.reducer:tapSlot(cardId, nowDeci())
		local changes: { Prediction.Change } = {}
		if emit ~= nil then
			-- The reducer returns only the Emit, so the departure is supplied here (wiring contract 4).
			local sentId = emit.payload.cardId
			table.insert(changes, { kind = "Removed", cardId = sentId })
			local ui = r.ui :: Ui
			ui.hand:markSent(sentId)
			send(emit)
		end
		refresh(changes)
	end

	local function onTapOff()
		local r = round
		if r == nil then
			return
		end
		r.reducer:tapOff()
		refresh({})
	end

	local function onTapLeft()
		local r = round
		if r == nil or r.ui == nil then
			return
		end
		local emit = r.reducer:tapLeftPile(nowDeci())
		local changes: { Prediction.Change } = {}
		if emit ~= nil then
			table.insert(changes, { kind = "Added" })
			send(emit)
		end
		refresh(changes)
	end

	local function onTapRight()
		local r = round
		if r == nil or r.ui == nil then
			return
		end
		r.reducer:tapRightPile(nowDeci())
		local ui = r.ui :: Ui
		ui.strip:setMessage(Hints.HINT[SINK_STATE][ui.kind], TWEEN.SINK_HINT)
	end

	-- The accelerators. Each is a pointer tap by another route and ends in the same reducer method.
	local function selectSlot(index: number)
		local r = round
		if r == nil or r.ui == nil then
			return
		end
		local entry = r.reducer:display().hand[index]
		if entry ~= nil then
			onTapSlot(entry.cardId)
		end
	end

	local function commit()
		local r = round
		if r == nil or r.ui == nil then
			return
		end
		local selected = r.reducer:selectedCardId()
		if selected ~= nil then
			onTapSlot(selected) -- the second tap on the selected card is the send
		else
			onTapLeft() -- the reducer makes this inert unless the hand is at the draw size
		end
	end

	local function moveSelection(delta: number)
		local r = round
		if r == nil or r.ui == nil then
			return
		end
		local hand = r.reducer:display().hand
		local count = #hand
		if count == 0 then
			return
		end
		local selected = r.reducer:selectedCardId()
		local at: number? = nil
		if selected ~= nil then
			for i, c in hand do
				if c.cardId == selected then
					at = i
				end
			end
		end
		local target = if at == nil
			then (if delta > 0 then 1 else count)
			else math.clamp((at :: number) + delta, 1, count)
		-- Landing on the card already selected would be its second tap, which is the SEND. Moving the
		-- selection must never send, so that case is a no-op.
		if target == at then
			return
		end
		onTapSlot(hand[target].cardId)
	end

	local function buildUi(r: RoundState): Ui
		local hud = CardHud.new(HAND_OWES_DRAW)
		local ok, built = pcall(function(): Ui
			local solution = hud:resolve(HAND_OWES_DRAW)
			local zone = hud:handZone() -- wiring contract 1: all three parent here
			local hand = CardHand.new(zone, solution, { tapSlot = onTapSlot, tapOff = onTapOff })
			-- Wiring contract 3: before the first apply that can contain a joker.
			hand:setJokerMode(jokerMode)
			local piles = CardPiles.new(zone, solution, { tapLeft = onTapLeft, tapRight = onTapRight })
			local strip = CardStrip.new(zone, solution)
			local input = CardInput.new({ selectSlot = selectSlot, commit = commit, moveSelection = moveSelection })
			local ui: Ui = {
				hud = hud,
				hand = hand,
				piles = piles,
				strip = strip,
				input = input,
				handSize = HAND_OWES_DRAW,
				kind = input:kind(),
				explaining = false,
			}
			hand:setInputKind(ui.kind)
			input:onKindChanged(function(kind: Hints.InputKind)
				ui.kind = kind
				hand:setInputKind(kind)
				if round == r then
					refresh({})
				end
			end)
			hud:onViewportChanged(function()
				local current = hud:solution()
				if current ~= nil then
					relayoutAll(ui, current)
				end
			end)
			return ui
		end)
		if not ok then
			-- A half-built overlay would leave a hit-testing backdrop on screen with the controls untouched.
			hud:destroy()
			error(built, 0)
		end
		return built :: Ui
	end

	local function onRoundStart(payload: any)
		teardown()
		round = nil
		local localPlayer = Players.LocalPlayer
		if type(payload) ~= "table" or type(payload.seats) ~= "table" or localPlayer == nil then
			return
		end
		local seat: number? = nil
		for _, entry in payload.seats do
			if entry.playerId == localPlayer.UserId then
				seat = entry.seat
			end
		end
		-- A hider never gets the card overlay.
		if seat == nil then
			return
		end
		jokerMode = if type(payload.jokerMode) == "string" then payload.jokerMode else nil
		local timeoutDeci = math.round(Card.PENDING_TIMEOUT_SECONDS * Round.DECISECONDS_PER_SECOND)
		local r: RoundState = {
			reducer = Prediction.new(timeoutDeci),
			localSeat = seat :: number,
			ui = nil,
			completed = nil,
		}
		round = r
		r.ui = buildUi(r)
		controls:hide()
		refresh({})
		local fn = hooks.onRoundStart
		if fn ~= nil then
			fn(payload, r.localSeat)
		end
	end

	local function onSync(payload: any)
		local r = round
		if r == nil then
			return
		end
		refresh(r.reducer:onSync(payload))
	end

	local function onTable(events: any)
		local r = round
		if r == nil or type(events) ~= "table" then
			return
		end
		local depths = r.reducer:depths()
		r.reducer:onTable(events, depths)
		for _, event in events do
			if type(event) == "table" and event.seat == r.localSeat then
				if event.kind == "Completed" then
					r.completed = event
					controls:onLocalCompleted()
					playSound(Card.AUDIO.STING)
				elseif event.kind == "SeatRemoved" then
					teardown()
				end
			end
		end
		local fn = hooks.onTable
		if fn ~= nil then
			fn(events, depths, r.localSeat)
		end
	end

	local function onNotice(payload: any)
		local r = round
		if r == nil then
			return
		end
		refresh(r.reducer:onNotice(payload))
		local ui = r.ui
		local copy = if type(payload) == "table" then noticeCopy[payload.code] else nil
		if ui ~= nil and copy ~= nil then
			ui.strip:setMessage(copy(payload), TWEEN.NOTICE)
		end
	end

	local function onStall(payload: any)
		local r = round
		if r == nil or r.ui == nil or type(payload) ~= "table" then
			return
		end
		local ui = r.ui :: Ui
		if payload.active == true then
			ui.strip:setMessage(Hints.MESSAGES.stall(), Card.STALL_CUE_SECONDS)
		else
			ui.strip:clearMessage()
		end
	end

	local handlers: { [string]: (payload: any) -> () } = {
		RoundStart = onRoundStart,
		Sync = onSync,
		Table = onTable,
		Notice = onNotice,
		Stall = onStall,
	}

	local function contained(fn: () -> ())
		local failure = ""
		local ok = xpcall(fn, function(e: unknown): ()
			failure = traceOf(e)
		end)
		if not ok then
			warn("CardClient", failure)
		end
	end

	local function step(dt: number)
		clockSeconds += dt
		local r = round
		if r == nil then
			return
		end
		local changes = r.reducer:tickWatchdog(nowDeci())
		if #changes > 0 then
			refresh(changes)
		end
		refreshCountdown()
	end

	local client: CardClient
	client = {
		start = function(_self: CardClient)
			if started then
				return
			end
			started = true
			-- Idempotent. onCard errors by name if the remotes are not resolved yet.
			ClientNet.resolve()
			rotate = CardHud.newRotatePrompt()
			table.insert(
				conns,
				ClientNet.onCard(function(kind: string, payload: unknown)
					local handler = handlers[kind]
					if handler ~= nil then
						contained(function()
							handler(payload)
						end)
					end
				end)
			)
			table.insert(
				conns,
				RunService.RenderStepped:Connect(function(dt: number)
					contained(function()
						step(dt)
					end)
				end)
			)
		end,
		destroy = function(_self: CardClient)
			for _, c in conns do
				c:Disconnect()
			end
			table.clear(conns)
			teardown()
			round = nil
			if rotate ~= nil then
				rotate:destroy()
				rotate = nil
			end
			started = false
		end,
		setHooks = function(_self: CardClient, newHooks: Hooks)
			hooks = newHooks
		end,
		hud = function(_self: CardClient): CardHud.Hud?
			local r = round
			if r == nil or r.ui == nil then
				return nil
			end
			return (r.ui :: Ui).hud
		end,
	}
	return client
end

return CardClient
