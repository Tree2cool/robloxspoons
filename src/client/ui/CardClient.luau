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
-- 11. KNOWN GAPS, recorded rather than papered over. (a) CLOSED in 04-19: pile depths arrive as their own
--     public `Depths` message (counts only, built by the server), so the stacks never depend on counting
--     events client-side. (b) CLOSED in 04-19: a round that ends without removing the local seat now
--     sends the public `RoundEnd`, which tears the overlay down and restores the controls (UX-02 /
--     D-29); before it the controls stayed hidden until the next RoundStart. (c) A keyboard or gamepad send
--     tells the hand through markSent, since it does not pass through a strip. (d) Nothing about feel,
--     controls or audio on a device is proven here: M-11, M-12, M-13, M-16.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Card = require(ReplicatedStorage.Shared.Config.Card)
local Round = require(ReplicatedStorage.Shared.Config.Round)
local Faces = require(ReplicatedStorage.Shared.Card.Faces)
local Flourish = require(ReplicatedStorage.Shared.Card.Flourish)
local Hints = require(ReplicatedStorage.Shared.Card.Hints)
local Layout = require(ReplicatedStorage.Shared.Card.Layout)
local Prediction = require(ReplicatedStorage.Shared.Card.Prediction)
local ClientNet = require("../net/ClientNet")
local CardAudio = require("./CardAudio")
local CardCallout = require("./CardCallout")
local CardControls = require("./CardControls")
local CardFlourish = require("./CardFlourish")
local CardHand = require("./CardHand")
local CardHud = require("./CardHud")
local CardInput = require("./CardInput")
local CardPiles = require("./CardPiles")
local CardSeatsView = require("./CardSeatsView")
local CardStrip = require("./CardStrip")

export type Hooks = {
	-- Plan 04-19 parents into these. `payload` is the RoundStart table (seat poses and jokerMode).
	onRoundStart: ((payload: any, localSeat: number) -> ())?,
	onTable: ((events: { any }, depths: { number }, localSeat: number) -> ())?,
	-- Server-supplied pile depths (CARD-13): one count per seat, seat order, counts only.
	onDepths: ((depths: { number }, localSeat: number) -> ())?,
	-- The server ended the round (UX-02 / D-29). Fired after the overlay is gone and the controls are back.
	onRoundEnd: (() -> ())?,
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

-- The table as a place (plan 04-19). None of it is replicated or hidden data: every part is built here from
-- public RoundStart and Table facts, and it outlives the hand (D-30 destroys the hand at completion).
type Place = {
	view: CardSeatsView.TableView,
	overlay: CardHud.Overlay,
	callouts: CardCallout.Callout,
	container: Folder,
	driver: Flourish.Driver,
	playerOfSeat: { [number]: number },
}

type RoundState = {
	reducer: Prediction.Reducer,
	localSeat: number,
	ui: Ui?,
	completed: any,
	place: Place?,
}

local HAND_FULL = 5
local SINK_STATE: Hints.State = "RightPileSink"
local HAND_OWES_DRAW = HAND_FULL - 1
local TWEEN = Card.TWEEN

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
	-- Plan 04-19. Created once, silent for every empty asset id (D-33, M-16).
	local audio = CardAudio.new()

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

	-- The public ranks of a Completed event's four retired faces. Ranks only, never a card id or a copy.
	local function ranksOf(event: any): { number }
		local ranks: { number } = {}
		if type(event) == "table" and type(event.faces) == "table" then
			for _, face in event.faces do
				if type(face) == "table" and type(face.rank) == "number" then
					table.insert(ranks, face.rank)
				end
			end
		end
		return ranks
	end

	-- D-30: this runs LAST in Controls.onLocalCompleted, after the overlay is gone and the controls are
	-- back, so the flourish can never delay either. The Deal kind is the other one the driver is given:
	-- played at RoundStart for the LOCAL seat only.
	startFlourish = function()
		local r = round
		if r == nil then
			return
		end
		local place = r.place
		if place ~= nil and type(r.completed) == "table" then
			place.driver:play("Completion", r.localSeat, true, ranksOf(r.completed))
		end
		local fn = hooks.startFlourish
		if fn ~= nil then
			fn(r.completed)
		end
	end

	-- Everything 04-19 builds that is not the hand. Idempotent; called at round start, round end and destroy.
	local function destroyPlace()
		local r = round
		if r == nil or r.place == nil then
			return
		end
		local place = r.place :: Place
		r.place = nil
		-- cancelAll runs each flight's own teardown (scan, diff, destroyRoot) rather than orphaning it.
		place.driver:cancelAll()
		place.callouts:destroy()
		place.overlay:destroy()
		place.view:destroy()
		place.container:Destroy()
	end

	local function buildDealGeometry(hud: CardHud.Hud): CardFlourish.DealGeometry?
		local solution = hud:solution()
		if solution == nil then
			return nil
		end
		local safe = solution.safe
		local function centreOf(rect: Layout.Rect): Vector2
			return Vector2.new(rect.x + rect.w / 2 - safe.x, rect.y + rect.h / 2 - safe.y)
		end
		local targets: { Vector2 } = {}
		for _, slot in solution.slots do
			table.insert(targets, centreOf(slot.card))
		end
		local first = solution.slots[1].card
		return { from = centreOf(solution.leftPile), to = targets, size = Vector2.new(first.w, first.h) }
	end

	local function buildPlace(r: RoundState, payload: any, hud: CardHud.Hud): Place
		local view = CardSeatsView.new(Workspace)
		local poses: { CardSeatsView.SeatPose } = {}
		local playerOfSeat: { [number]: number } = {}
		for _, entry in payload.seats do
			playerOfSeat[entry.seat] = entry.playerId
			table.insert(
				poses,
				{ seat = entry.seat, playerId = entry.playerId, position = entry.position, look = entry.look }
			)
		end
		view:setSeats(poses)
		-- The flourish's Workspace container is ours alone: destroyEscaped may delete anything new in it, so it
		-- must never be Workspace itself (a respawning character would be deleted).
		local container = Instance.new("Folder")
		container.Name = "SpoonsFlourish"
		container.Parent = Workspace
		local overlay = CardHud.newOverlay("CardCallouts", Card.FLOURISH_DISPLAY_ORDER)
		local callouts = CardCallout.new(overlay:region(), overlay:resolve(HAND_OWES_DRAW))
		local stage: CardFlourish.Stage = {
			seatPosition = function(seat: number): Vector3?
				return view:seatPosition(seat)
			end,
			centre = function(): Vector3?
				return view:centre()
			end,
			deal = function(): CardFlourish.DealGeometry?
				return buildDealGeometry(hud)
			end,
		}
		hud:onViewportChanged(function()
			if r.place ~= nil then
				callouts:relayout(overlay:resolve(HAND_OWES_DRAW))
			end
		end)
		return {
			view = view,
			overlay = overlay,
			callouts = callouts,
			container = container,
			driver = CardFlourish.makeDriver(hud, container, stage),
			playerOfSeat = playerOfSeat,
		}
	end

	local function teardown()
		destroyUi()
		controls:restore()
	end

	-- A round is over for this client: the hand, the controls and the place all go (UX-02 / D-29).
	local function endRoundView()
		teardown()
		destroyPlace()
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
		-- D-33: own draw and own pass only, on the predicted local action. Nothing for another seat's pass.
		if emit.name == "Draw" then
			audio:ownDraw()
		else
			audio:ownPass()
		end
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
		-- IN-01: every piece is registered here the moment it exists, so a throw part-way through can undo
		-- exactly what was built (CardPiles holds a RenderStepped connection, CardInput three bound actions).
		local cleanups: { () -> () } = {}
		local ok, built = pcall(function(): Ui
			local solution = hud:resolve(HAND_OWES_DRAW)
			local zone = hud:handZone() -- wiring contract 1: all three parent here
			local hand = CardHand.new(zone, solution, { tapSlot = onTapSlot, tapOff = onTapOff })
			table.insert(cleanups, function()
				hand:destroy()
			end)
			-- Wiring contract 3: before the first apply that can contain a joker.
			hand:setJokerMode(jokerMode)
			local piles = CardPiles.new(zone, solution, { tapLeft = onTapLeft, tapRight = onTapRight })
			table.insert(cleanups, function()
				piles:destroy()
			end)
			local strip = CardStrip.new(zone, solution)
			table.insert(cleanups, function()
				strip:destroy()
			end)
			local input = CardInput.new({ selectSlot = selectSlot, commit = commit, moveSelection = moveSelection })
			table.insert(cleanups, function()
				input:destroy()
			end)
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
			-- Pieces are undone newest first, each contained so one failing destroy cannot strand the rest.
			for i = #cleanups, 1, -1 do
				pcall(cleanups[i])
			end
			hud:destroy()
			error(built, 0)
		end
		return built :: Ui
	end

	local function onRoundStart(payload: any)
		endRoundView()
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
			place = nil,
		}
		round = r
		r.ui = buildUi(r)
		controls:hide()
		refresh({})
		local ui = r.ui :: Ui
		-- Contained: a failure in the table cosmetics must not take the hand with it.
		local placeOk, placeErr = pcall(function()
			local place = buildPlace(r, payload, ui.hud)
			r.place = place
			place.driver:play("Deal", r.localSeat, true, {})
		end)
		if not placeOk then
			warn("CardClient", tostring(placeErr))
		end
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
			if type(event) == "table" then
				local place = r.place
				if event.kind == "Passed" and place ~= nil then
					-- A public Passed: the card is face-down, there is no rank to show and none is inferred.
					place.view:hop(event.seat, event.to)
				end
				local isLocal = event.seat == r.localSeat
				if event.kind == "Completed" then
					if isLocal then
						r.completed = event
						controls:onLocalCompleted()
					elseif place ~= nil then
						place.driver:play("Completion", event.seat, false, ranksOf(event))
					end
					-- D-33: the starting gun, the same for everyone, once, after the finisher has control.
					audio:sting()
					-- D-31: the table is told who went. The self callout survives the hand's destruction
					-- because it lives on its own overlay.
					if place ~= nil then
						if isLocal then
							place.callouts:show(nil, true)
						else
							local userId = place.playerOfSeat[event.seat]
							local player = if userId ~= nil then Players:GetPlayerByUserId(userId) else nil
							if player ~= nil then
								place.callouts:show(player.DisplayName, false)
							end
						end
					end
				elseif event.kind == "SeatRemoved" and isLocal then
					teardown()
				end
			end
		end
		local fn = hooks.onTable
		if fn ~= nil then
			fn(events, depths, r.localSeat)
		end
	end

	-- CARD-13: the server's pile depths. Validated as plain finite non-negative counts; anything else is
	-- ignored (D-12), never repaired, so a malformed message cannot put an invented number on a stack.
	local function onDepths(payload: any)
		local r = round
		if r == nil or type(payload) ~= "table" or type(payload.depths) ~= "table" then
			return
		end
		local list: { number } = {}
		for i = 1, #payload.depths do
			local v = payload.depths[i]
			if type(v) ~= "number" or v ~= v or v < 0 or v == math.huge then
				return
			end
			list[i] = v
		end
		r.reducer:onTable({}, list)
		if r.place ~= nil then
			(r.place :: Place).view:setDepths(list)
		end
		local fn = hooks.onDepths
		if fn ~= nil then
			fn(list, r.localSeat)
		end
	end

	-- UX-02 / D-29: the round ended without removing this seat (CardService.endRound removes none), so
	-- neither Completed nor SeatRemoved will ever come. Without this the server has released the avatar
	-- while the touch controls stay hidden and the key sink stays bound. teardown is idempotent, so a
	-- RoundEnd that follows this seat's own Completed does nothing twice.
	local function onRoundEnd(_payload: any)
		endRoundView()
		round = nil
		local fn = hooks.onRoundEnd
		if fn ~= nil then
			fn()
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
		Depths = onDepths,
		RoundEnd = onRoundEnd,
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
			endRoundView()
			round = nil
			audio:destroy()
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
