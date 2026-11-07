--!strict
-- The client's whole decision layer for the card hand (CARD-02, CARD-14, CARD-15): a pure reducer over
-- `auth + pending[]`. The renderer applies the Changes this returns and never recomputes state.
--
-- 1. PURE ZONE, no clock, no Roblox API, no Roblox types. `nowDeci` is a parameter on every call that
--    needs time. That is what lets CARD-14 be tested at simulated latency with nothing else present.
-- 2. D-10: PREDICT IMMEDIATELY. `display()` changes in the same call as a commit. Waiting for the ack
--    is a visible stall on every pass.
-- 3. D-02 / D-03 / CARD-15: ONE TAP ALONE NEVER EMITS AN INTENT, AND THERE IS NO DEBOUNCE. There is no
--    gate, no arming delay and no timestamp comparison in `tapSlot`. The accepted residual, recorded
--    verbatim: a fumbled fast double-tap on a single card WILL send that card. Do not add a debounce
--    without re-opening D-02; it was a deliberate trade ("Honestly remove the 0.5s, make it instant").
-- 4. D-12: NO `Change` VARIANT CARRIES A REASON, AND NONE MAY EVER BE ADDED. A correction, an engine
--    rejection, a shell rejection and a gateway rate limit are the same `Returned`. Reject codes are
--    server telemetry; naming the guard a prober tripped is a disclosure.
-- 5. RULE 7: the only emitted payload keys are `seq` and `cardId`. No seat, no target, no index. The
--    server resolves the seat from the Player, and Ring.pass resolves `next` at execution time.
-- 6. RULE 5: `seq` is a counter, not a clock. `sentAtDeci` is client-local, used only to age a pending
--    entry for the watchdog; it is never sent and never compared with a server value.
-- 7. THE HAND COMES ONLY FROM `Sync` (Pitfall 12): a public `Drew` for my own seat carries an id with no
--    face, so `onTable` never builds the hand.
-- 8. Cards are laid out in ARRIVAL ORDER and never re-sorted by rank: a re-sort on draw would move
--    slots under a thumb. An optional sort is a Phase 8 candidate.
-- 9. OPEN QUESTION 5, DECIDED: `tickWatchdog` rolls back LOCALLY and there is no `Resync` intent.
--    A gateway-level rejection (RateLimited, WrongPhase, a validation failure) never reaches the card
--    core, so its seq is never acked individually. The PRIMARY fix is a server push: the existing
--    `onReject` sink also sends that player a `Sync` carrying the current `ackSeq`, which resolves the
--    pending entry cumulatively. This watchdog is the BACKSTOP for a message genuinely lost. When a
--    pending entry is older than the timeout the reducer drops it and re-folds, emitting `Returned`
--    for a Pass and a `Removed` (with no id) for the placeholder of a Draw. The rejected alternatives
--    were a `Resync{seq}` intent (a new manifest row, a new bucket and a new client-driven path a
--    prober can poke, for a case where `auth` is already authoritative) and a no-op (a card visibly
--    gone forever, exactly the "visible glitch" criterion 2 forbids). Trade-off, stated plainly: if a
--    Sync was merely slow rather than lost, the card returns and may leave again when the Sync lands.
--    At 150-300 ms a 1.0 s timeout is roughly three round trips, so this is rare, and a brief double
--    motion is a far smaller defect than a card that never comes back. A dropped entry is gone from
--    `pending`, which is what stops the watchdog re-firing on it.
-- 10. `Returned` means "the server did not accept what I did"; `Removed` means "the server did
--    something to me" (AFK auto-pass, ValveForcedPass). Confusing them would animate a return for a
--    card that genuinely left.
-- 11. The fold SKIPS a predicted action that the server is certain to reject: a Pass unless the display
--    hand is 5, a Draw unless it is 4 and the inbox is non-empty. That keeps the display hand at 4 or 5
--    structurally, even when a server-initiated removal lands while my own Pass is still in flight.
--    The entry stays in `pending` until acked; only its visible effect is withheld.
-- 12. Every incoming number is checked finite and every failure errors by name. A NaN `sentAtDeci`
--    would make the watchdog's age comparison false forever and the backstop would silently never fire,
--    which is the defect class this project has found 31 times.
local Card = require("../Config/Card")

export type FaceRecord = { cardId: number, rank: number, copy: number }

export type Auth = {
	ackSeq: number,
	seat: number,
	hand: { FaceRecord },
	inbox: number,
	downstream: number,
	idleDeadlineUnix: number?,
}

export type Pending =
	{ seq: number, kind: "Draw", sentAtDeci: number }
	| { seq: number, kind: "Pass", cardId: number, sentAtDeci: number }

export type DisplayCard = { cardId: number?, rank: number?, copy: number? }
export type Display = { hand: { DisplayCard }, inbox: number, downstream: number }

-- No reason, code or message field on any variant, and there must never be one (header point 4).
-- `Removed` carries no id when it is the placeholder of a rolled-back Draw.
export type Change =
	{ kind: "Added", cardId: number? }
	| { kind: "Flipped", cardId: number }
	| { kind: "Returned", cardId: number }
	| { kind: "Removed", cardId: number? }

export type Emit = { name: "Draw" | "Pass", payload: { [string]: number } }

export type Reducer = {
	tapSlot: (self: Reducer, cardId: number?, nowDeci: number) -> Emit?,
	tapOff: (self: Reducer) -> (),
	tapLeftPile: (self: Reducer, nowDeci: number) -> Emit?,
	tapRightPile: (self: Reducer, nowDeci: number) -> (),
	onSync: (self: Reducer, auth: Auth) -> { Change },
	onTable: (self: Reducer, events: { any }, depths: { number }) -> { Change },
	onNotice: (self: Reducer, notice: any) -> { Change },
	tickWatchdog: (self: Reducer, nowDeci: number) -> { Change },
	display: (self: Reducer) -> Display,
	selectedCardId: (self: Reducer) -> number?,
	pendingCount: (self: Reducer) -> number,
	depths: (self: Reducer) -> { number },
	sinkHintUntilDeci: (self: Reducer) -> number?,
	idleDeadlineUnix: (self: Reducer) -> number?,
}

local HAND_SIZE = 5

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function checkNow(v: any, where: string)
	if not isFinite(v) or (v :: number) < 0 then
		error(`Prediction.{where}: nowDeci must be a finite non-negative number`)
	end
end

local function findId(hand: { DisplayCard }, cardId: number): number?
	for i, c in hand do
		if c.cardId == cardId then
			return i
		end
	end
	return nil
end

local function checkAuth(auth: any)
	if type(auth) ~= "table" then
		error("Prediction.onSync: auth must be a table")
	end
	if not isFinite(auth.ackSeq) then
		error("Prediction.onSync: ackSeq must be finite")
	end
	if not isFinite(auth.inbox) or not isFinite(auth.downstream) or not isFinite(auth.seat) then
		error("Prediction.onSync: seat, inbox and downstream must be finite")
	end
	if type(auth.hand) ~= "table" then
		error("Prediction.onSync: hand must be a table")
	end
	for _, f in auth.hand do
		if type(f) ~= "table" or not isFinite(f.cardId) or not isFinite(f.rank) or not isFinite(f.copy) then
			error("Prediction.onSync: every hand entry needs a finite cardId, rank and copy")
		end
	end
	if auth.idleDeadlineUnix ~= nil and not isFinite(auth.idleDeadlineUnix) then
		error("Prediction.onSync: idleDeadlineUnix must be finite")
	end
end

local function copyAuth(auth: Auth): Auth
	local hand: { FaceRecord } = {}
	for _, f in auth.hand do
		table.insert(hand, { cardId = f.cardId, rank = f.rank, copy = f.copy })
	end
	return {
		ackSeq = auth.ackSeq,
		seat = auth.seat,
		hand = hand,
		inbox = auth.inbox,
		downstream = auth.downstream,
		idleDeadlineUnix = auth.idleDeadlineUnix,
	}
end

-- display = fold(pending, auth), recomputed on every call and never cached. The second result is the
-- set of card ids this fold predicted away (so a diff can tell Returned from Added).
local function fold(auth: Auth, pending: { Pending }): (Display, { [number]: boolean })
	local hand: { DisplayCard } = {}
	for _, f in auth.hand do
		table.insert(hand, { cardId = f.cardId, rank = f.rank, copy = f.copy })
	end
	local inbox = auth.inbox
	local downstream = auth.downstream
	local away: { [number]: boolean } = {}
	for _, p in pending do
		if p.kind == "Pass" then
			local idx = if #hand == HAND_SIZE then findId(hand, p.cardId) else nil
			if idx ~= nil then
				table.remove(hand, idx)
				downstream += 1
				away[p.cardId] = true
			end
		else
			if #hand == HAND_SIZE - 1 and inbox >= 1 then
				inbox -= 1
				table.insert(hand, {})
			end
		end
	end
	return { hand = hand, inbox = inbox, downstream = downstream }, away
end

local function idSet(display: Display): { [number]: boolean }
	local set: { [number]: boolean } = {}
	for _, c in display.hand do
		if c.cardId ~= nil then
			set[c.cardId] = true
		end
	end
	return set
end

local function placeholders(display: Display): number
	local n = 0
	for _, c in display.hand do
		if c.cardId == nil then
			n += 1
		end
	end
	return n
end

-- Old display -> new display, as the list the renderer animates. `oldAway` is the set the OLD fold
-- predicted away.
local function diff(oldDisplay: Display, oldAway: { [number]: boolean }, newDisplay: Display): { Change }
	local oldIds = idSet(oldDisplay)
	local newIds = idSet(newDisplay)
	local changes: { Change } = {}
	local newcomers: { number } = {}
	for _, c in newDisplay.hand do
		local id = c.cardId
		if id ~= nil and not oldIds[id] then
			if oldAway[id] then
				table.insert(changes, { kind = "Returned", cardId = id })
			else
				table.insert(newcomers, id)
			end
		end
	end
	-- A placeholder has no id, so it can only be matched by count: the placeholders that stopped being
	-- placeholders are resolved first to newcomers (Flipped), the rest are Added.
	local resolved = math.max(0, placeholders(oldDisplay) - placeholders(newDisplay))
	local flipped = math.min(resolved, #newcomers)
	for i, id in newcomers do
		if i <= flipped then
			table.insert(changes, { kind = "Flipped", cardId = id })
		else
			table.insert(changes, { kind = "Added", cardId = id })
		end
	end
	for _ = 1, resolved - flipped do
		table.insert(changes, { kind = "Removed" })
	end
	for _, c in oldDisplay.hand do
		local id = c.cardId
		if id ~= nil and not newIds[id] then
			table.insert(changes, { kind = "Removed", cardId = id })
		end
	end
	return changes
end

local function new(pendingTimeoutDeci: number): Reducer
	if not isFinite(pendingTimeoutDeci) or pendingTimeoutDeci <= 0 then
		error("Prediction.new: pendingTimeoutDeci must be a finite positive number")
	end

	local auth: Auth = { ackSeq = 0, seat = 0, hand = {}, inbox = 0, downstream = 0 }
	local pending: { Pending } = {}
	local selected: number? = nil
	local nextSeq = 1
	local depthList: { number } = {}
	local sinkHintUntil: number? = nil

	local function sanitizeSelection()
		if selected ~= nil then
			local d = fold(auth, pending)
			if findId(d.hand, selected) == nil then
				selected = nil
			end
		end
	end

	local function rebuild(newAuth: Auth, keep: (Pending) -> boolean): { Change }
		local oldDisplay, oldAway = fold(auth, pending)
		auth = newAuth
		local kept: { Pending } = {}
		for _, p in pending do
			if keep(p) then
				table.insert(kept, p)
			end
		end
		pending = kept
		local newDisplay = fold(auth, pending)
		sanitizeSelection()
		return diff(oldDisplay, oldAway, newDisplay)
	end

	local self: Reducer
	self = {
		tapSlot = function(_self: Reducer, cardId: number?, nowDeci: number): Emit?
			checkNow(nowDeci, "tapSlot")
			local d = fold(auth, pending)
			if #d.hand ~= HAND_SIZE then
				return nil -- F6: at hand 4 the player owes a draw; a Pass would be a guaranteed rejection
			end
			if cardId == nil or findId(d.hand, cardId) == nil then
				return nil
			end
			if cardId ~= selected then
				selected = cardId -- D-04: selection follows the tap
				return nil
			end
			local seq = nextSeq
			nextSeq += 1
			table.insert(pending, { seq = seq, kind = "Pass", cardId = cardId, sentAtDeci = nowDeci })
			selected = nil
			return { name = "Pass", payload = { seq = seq, cardId = cardId } }
		end,

		tapOff = function(_self: Reducer)
			selected = nil
		end,

		tapLeftPile = function(_self: Reducer, nowDeci: number): Emit?
			checkNow(nowDeci, "tapLeftPile")
			local d = fold(auth, pending)
			if #d.hand ~= HAND_SIZE - 1 or d.inbox < 1 then
				return nil
			end
			local seq = nextSeq
			nextSeq += 1
			table.insert(pending, { seq = seq, kind = "Draw", sentAtDeci = nowDeci })
			return { name = "Draw", payload = { seq = seq } }
		end,

		tapRightPile = function(_self: Reducer, nowDeci: number)
			checkNow(nowDeci, "tapRightPile")
			-- D-06: an inert sink that KEEPS the selection and never emits.
			sinkHintUntil = nowDeci + math.floor(Card.TWEEN.SINK_HINT * 10 + 0.5)
		end,

		onSync = function(_self: Reducer, newAuth: Auth): { Change }
			checkAuth(newAuth)
			if newAuth.ackSeq < auth.ackSeq then
				return {} -- monotonicity: a stale Sync must not resurrect a resolved state
			end
			local copied = copyAuth(newAuth)
			-- Cumulative ack: anything at or below it that the new auth does not reflect was rejected.
			return rebuild(copied, function(p: Pending)
				return p.seq > copied.ackSeq
			end)
		end,

		onTable = function(_self: Reducer, events: { any }, newDepths: { number }): { Change }
			if type(events) ~= "table" or type(newDepths) ~= "table" then
				error("Prediction.onTable: events and depths must be tables")
			end
			local copied: { number } = {}
			for i, v in newDepths do
				if not isFinite(v) then
					error("Prediction.onTable: every depth must be finite")
				end
				copied[i] = v
			end
			depthList = copied
			return {} -- own-seat Drew and Passed are ignored: the hand comes only from Sync
		end,

		onNotice = function(_self: Reducer, notice: any): { Change }
			if type(notice) ~= "table" then
				error("Prediction.onNotice: notice must be a table")
			end
			if selected ~= nil and notice.cardId == selected then
				selected = nil
			end
			return {}
		end,

		tickWatchdog = function(_self: Reducer, nowDeci: number): { Change }
			checkNow(nowDeci, "tickWatchdog")
			local expired = false
			for _, p in pending do
				if nowDeci - p.sentAtDeci > pendingTimeoutDeci then
					expired = true
					break
				end
			end
			if not expired then
				return {}
			end
			return rebuild(auth, function(p: Pending)
				return nowDeci - p.sentAtDeci <= pendingTimeoutDeci
			end)
		end,

		display = function(_self: Reducer): Display
			local d = fold(auth, pending)
			return d
		end,

		selectedCardId = function(_self: Reducer): number?
			return selected
		end,

		pendingCount = function(_self: Reducer): number
			return #pending
		end,

		depths = function(_self: Reducer): { number }
			return table.clone(depthList)
		end,

		sinkHintUntilDeci = function(_self: Reducer): number?
			return sinkHintUntil
		end,

		idleDeadlineUnix = function(_self: Reducer): number?
			return auth.idleDeadlineUnix
		end,
	}
	return self
end

return { new = new }
