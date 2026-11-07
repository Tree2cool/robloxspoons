--!strict
-- CARD-02 / CARD-14 / CARD-15 gate for src/shared/Card/Prediction.luau.
--
-- A FakeLink drives the reducer through virtual time against a stub server holding a tiny authoritative
-- hand model. Latency is modelled as 0.2 s and 0.3 s, not 150 ms: FakeScheduler floors to deciseconds, so
-- 0.15 s would be 1 deci and 0.3 s is the honest upper end of the CARD-14 band. The stub answers EVERY
-- intent with a Sync carrying ackSeq = seq whether it accepted or rejected it, so the message SHAPE is the
-- same at the wire level too (the server half of D-12).
--
-- Mutations are injected broken REDUCERS (wrappers around the real one) driven through the SAME scenario
-- helper as the clean case they break, with the real reducer passing in the same case. Prediction.luau is
-- never edited by this file.
local Card = require("../../src/shared/Config/Card")
local FakeScheduler = require("../harness/FakeScheduler")
local Prediction = require("../../src/shared/Card/Prediction")
local Test = require("../harness/Test")

type Reducer = Prediction.Reducer
type Change = Prediction.Change
type Emit = Prediction.Emit
type Auth = Prediction.Auth
type Wrap = (Reducer) -> Reducer

local TIMEOUT_DECI = math.floor(Card.PENDING_TIMEOUT_SECONDS * 10 + 0.5)

-- Every reject code the stack can produce for a card intent: wave 1 measured the validation vocabulary,
-- and the engine/shell codes are the D-12 list. None of them may reach the reducer or change its output.
local REJECT_CODES = {
	"UnknownKey",
	"MissingKey",
	"NotFinite",
	"WrongType",
	"NotInteger",
	"OutOfRange",
	"NotTable",
	"ForbiddenType",
	"RateLimited",
	"NotYourCard",
	"HandNotFour",
	"HandNotFive",
	"InboxEmpty",
	"SeatNotLive",
	"UnknownCard",
	"UnknownSeat",
}

type Server = {
	hand: { number },
	inbox: { number },
	downstream: number,
	handled: number,
	fresh: number,
	lastCode: string?,
}

type Rig = {
	r: Reducer,
	sched: FakeScheduler.FakeScheduler,
	server: Server,
	sends: number,
	emitted: { Emit },
	log: { Change },
	syncs: number,
	reject: { [number]: string },
	lost: { [number]: boolean },
	lastAuth: Auth,
	now: () -> number,
	tap: (id: number?) -> Emit?,
	draw: () -> Emit?,
	advance: (deci: number) -> (),
	forcedPass: (id: number) -> (),
	serverHandle: (emit: Emit) -> boolean,
	snapshot: () -> Auth,
	handIds: () -> { number },
}

local function faceOf(id: number): Prediction.FaceRecord
	return { cardId = id, rank = (id % 5) + 1, copy = (id % 4) + 1 }
end

local function idsOf(display: Prediction.Display): { any }
	local ids: { any } = {}
	for _, c in display.hand do
		table.insert(ids, if c.cardId == nil then "ph" else c.cardId)
	end
	return ids
end

local function newRig(wrap: Wrap?, latencySec: number, hand: { number }, inbox: { number }): Rig
	local sched = FakeScheduler.new()
	local real = Prediction.new(TIMEOUT_DECI)
	local r: Reducer = if wrap ~= nil then wrap(real) else real
	local server: Server = {
		hand = table.clone(hand),
		inbox = table.clone(inbox),
		downstream = 0,
		handled = 0,
		fresh = 100,
		lastCode = nil,
	}
	local reject: { [number]: string } = {}
	local lost: { [number]: boolean } = {}

	local function snapshot(): Auth
		local faces: { Prediction.FaceRecord } = {}
		for _, id in server.hand do
			table.insert(faces, faceOf(id))
		end
		return { ackSeq = server.handled, seat = 1, hand = faces, inbox = #server.inbox, downstream = server.downstream }
	end

	-- Returns true when the stub accepted the intent. A rejected intent still counts as handled (acked).
	local function serverHandle(emit: Emit): boolean
		local seq = emit.payload.seq
		local accepted = false
		local code = reject[seq]
		if code ~= nil then
			server.lastCode = code
		elseif emit.name == "Pass" then
			local idx = table.find(server.hand, emit.payload.cardId)
			if #server.hand == 5 and idx ~= nil then
				table.remove(server.hand, idx)
				server.downstream += 1
				server.fresh += 1
				table.insert(server.inbox, server.fresh) -- someone else passed to me
				accepted = true
			else
				server.lastCode = "HandNotFive"
			end
		else
			if #server.hand == 4 and #server.inbox >= 1 then
				table.insert(server.hand, table.remove(server.inbox, 1) :: number)
				accepted = true
			else
				server.lastCode = "HandNotFour"
			end
		end
		server.handled = math.max(server.handled, seq)
		return accepted
	end

	local rig: Rig
	local function deliver(snap: Auth)
		rig.syncs += 1
		rig.lastAuth = snap
		for _, c in r:onSync(snap) do
			table.insert(rig.log, c)
		end
	end

	local function send(emit: Emit)
		rig.sends += 1
		table.insert(rig.emitted, emit)
		local seq = emit.payload.seq
		if rig.lost[seq] then
			return -- a message genuinely lost, or a gateway-level reject that never reaches the card core
		end
		sched.delay(latencySec, function()
			serverHandle(emit)
			local snap = snapshot()
			sched.delay(latencySec, function()
				deliver(snap)
			end)
		end)
	end

	rig = {
		r = r,
		sched = sched,
		server = server,
		sends = 0,
		emitted = {},
		log = {},
		syncs = 0,
		reject = reject,
		lost = lost,
		lastAuth = snapshot(),
		now = function()
			return sched.nowDeci()
		end,
		tap = function(id: number?): Emit?
			local emit = r:tapSlot(id, sched.nowDeci())
			if emit ~= nil then
				send(emit)
			end
			return emit
		end,
		draw = function(): Emit?
			local emit = r:tapLeftPile(sched.nowDeci())
			if emit ~= nil then
				send(emit)
			end
			return emit
		end,
		advance = function(deci: number)
			for _ = 1, deci do
				sched.advance(0.1)
				for _, c in r:tickWatchdog(sched.nowDeci()) do
					table.insert(rig.log, c)
				end
			end
		end,
		forcedPass = function(id: number)
			local idx = table.find(server.hand, id)
			if #server.hand == 5 and idx ~= nil then
				table.remove(server.hand, idx)
				server.downstream += 1
				local snap = snapshot()
				sched.delay(latencySec, function()
					deliver(snap)
				end)
			end
		end,
		serverHandle = serverHandle,
		snapshot = snapshot,
		handIds = function(): { number }
			return table.clone(server.hand)
		end,
	}
	r:onSync(snapshot()) -- the round-start Sync; not logged
	rig.lastAuth = snapshot()
	return rig
end

local function count(changes: { Change }, kind: string): number
	local n = 0
	for _, c in changes do
		if c.kind == kind then
			n += 1
		end
	end
	return n
end

local function encode(changes: { Change }): string
	local parts: { string } = {}
	for _, c in changes do
		local keys: { string } = {}
		for k, v in c :: any do
			table.insert(keys, `{k}={tostring(v)}`)
		end
		table.sort(keys)
		table.insert(parts, table.concat(keys, ","))
	end
	return table.concat(parts, ";")
end

local function sortedKeys(tbl: { [any]: any }): string
	local keys: { string } = {}
	for k in tbl do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function sameIds(a: { any }, b: { any }): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local HAND5 = { 1, 2, 3, 4, 5 }
local INBOX3 = { 10, 11, 12 }

return function(t: Test.Runner)
	-- Scenarios shared between a clean case and the mutation that must break it. ----------------------

	local function scenSingleTap(wrap: Wrap?): number
		local rig = newRig(wrap, 0.2, HAND5, INBOX3)
		local e1 = rig.tap(3)
		t.equal(e1, nil, "a single tap emitted an intent")
		t.equal(rig.r:selectedCardId(), 3, "a single tap must select")
		t.equal(#rig.r:display().hand, 5, "a single tap changed the display hand")
		t.equal(rig.sends, 0, "send count after one tap")
		local e2 = rig.tap(1)
		t.equal(e2, nil, "moving the selection emitted an intent")
		t.equal(rig.r:selectedCardId(), 1, "selection did not follow the tap")
		t.equal(rig.sends, 0, "send count after two different taps")
		return 2
	end

	local function scenCommit(wrap: Wrap?): number
		local rig = newRig(wrap, 0.2, HAND5, INBOX3)
		rig.tap(3)
		local before = rig.r:display()
		local emit = rig.tap(3)
		t.truthy(emit ~= nil, "the second tap on the same card did not commit")
		local e = emit :: Emit
		t.equal(e.name, "Pass", "emit name")
		t.equal(sortedKeys(e.payload), "cardId,seq", "payload key set (rule 7: no seat, no target, no index)")
		t.equal(e.payload.cardId, 3, "payload cardId")
		t.equal(rig.r:selectedCardId(), nil, "selection not cleared by the commit")
		local after = rig.r:display()
		t.equal(#before.hand, 5, "hand before commit")
		t.deepEqual(idsOf(after), { 1, 2, 4, 5 }, "display must change in the SAME call as the commit (D-10)")
		t.equal(after.downstream, before.downstream + 1, "downstream not predicted")
		t.equal(rig.now(), 0, "no virtual time may have passed")
		t.equal(rig.sends, 1, "exactly one send")
		return 1
	end

	local function scenPlaceholder(wrap: Wrap?): number
		local rig = newRig(wrap, 0.2, { 1, 2, 3, 4 }, { 10, 11 })
		local d = rig.draw()
		t.truthy(d ~= nil, "draw at (4, 2) did not emit")
		local disp = rig.r:display()
		t.equal(#disp.hand, 5, "placeholder not appended in the same call")
		t.equal(disp.hand[5].cardId, nil, "the placeholder must have no id")
		t.equal(disp.inbox, 1, "inbox not predicted down")
		local e = rig.tap(nil)
		t.equal(e, nil, "a Pass naming a placeholder was emitted")
		t.equal(rig.r:selectedCardId(), nil, "a placeholder became selectable")
		t.equal(rig.sends, 1, "only the Draw may have been sent")
		rig.advance(4)
		t.equal(count(rig.log, "Flipped"), 1, "the Sync must flip the placeholder")
		t.equal(rig.log[1].kind, "Flipped", "first change")
		t.equal((rig.log[1] :: any).cardId, 10, "flipped card id")
		t.equal(rig.tap(10), nil, "first tap on the flipped card selects")
		t.truthy(rig.tap(10) ~= nil, "the flipped card must now be passable")
		t.equal(rig.sends, 2, "Draw + Pass")
		return 1
	end

	local function scenHappy(wrap: Wrap?): number
		local runs = 0
		for _, latency in { 0.2, 0.3 } do
			local rig = newRig(wrap, latency, HAND5, INBOX3)
			rig.tap(3)
			rig.tap(3)
			t.deepEqual(idsOf(rig.r:display()), { 1, 2, 4, 5 }, "immediate display")
			rig.advance(math.floor(latency * 20 + 0.5))
			t.equal(rig.syncs, 1, "the Sync did not land (non-vacuity)")
			t.equal(count(rig.log, "Returned"), 0, `a happy pass produced a Returned at {latency}s`)
			t.equal(rig.r:pendingCount(), 0, `pending not resolved at {latency}s`)
			local d = rig.r:display()
			t.deepEqual(idsOf(d), rig.handIds(), "display must equal auth once pending is empty")
			t.equal(d.inbox, #rig.server.inbox, "inbox")
			t.equal(d.downstream, rig.server.downstream, "downstream")
			runs += 1
		end
		return runs
	end

	local function scenWatchdog(wrap: Wrap?): number
		local lostRig = newRig(wrap, 0.2, HAND5, INBOX3)
		lostRig.lost[1] = true
		lostRig.tap(3)
		lostRig.tap(3)
		lostRig.advance(TIMEOUT_DECI)
		t.equal(lostRig.r:pendingCount(), 1, "the watchdog fired AT the timeout, it must fire after it")
		t.equal(count(lostRig.log, "Returned"), 0, "premature Returned")
		t.equal(#lostRig.r:display().hand, 4, "card should still be predicted away at the boundary")
		lostRig.advance(1)
		t.equal(count(lostRig.log, "Returned"), 1, "the watchdog did not roll the lost message back")
		t.equal((lostRig.log[1] :: any).cardId, 3, "returned card")
		t.equal(lostRig.r:pendingCount(), 0, "pending not dropped")
		t.deepEqual(idsOf(lostRig.r:display()), HAND5, "hand not restored")
		lostRig.advance(100)
		t.equal(#lostRig.log, 1, "the watchdog must fire exactly once")

		local timelyRig = newRig(wrap, 0.2, HAND5, INBOX3)
		timelyRig.tap(3)
		timelyRig.tap(3)
		timelyRig.advance(TIMEOUT_DECI * 4)
		t.equal(timelyRig.syncs, 1, "the timely Sync did not land (non-vacuity)")
		t.equal(count(timelyRig.log, "Returned"), 0, "the watchdog fired although the Sync arrived in time")
		return 2
	end

	-- Cases ------------------------------------------------------------------------------------------

	t.test("virtual time advances one deci per step (the rig's own premise)", function()
		local rig = newRig(nil, 0.2, HAND5, INBOX3)
		rig.advance(3)
		t.equal(rig.now(), 3, "advance(0.1) must be exactly one decisecond")
	end)

	t.test("CARD-15: a single tap emits NOTHING and only selects", function()
		t.equal(scenSingleTap(nil), 2)
	end)

	t.test("CARD-02 / D-01: a second tap on the SAME card commits exactly one Pass", function()
		t.equal(scenCommit(nil), 1)
	end)

	t.test("D-04: tapping another card moves the selection, tapping off clears it, and neither sends", function()
		local rig = newRig(nil, 0.2, HAND5, INBOX3)
		rig.tap(2)
		rig.tap(4)
		t.equal(rig.r:selectedCardId(), 4, "selection did not move")
		rig.r:tapRightPile(rig.now())
		t.equal(rig.r:selectedCardId(), 4, "the right-pile sink must keep the selection (D-06)")
		t.truthy(rig.r:sinkHintUntilDeci() ~= nil, "the sink must set the hint deadline")
		t.equal(rig.r:sinkHintUntilDeci(), math.floor(Card.TWEEN.SINK_HINT * 10 + 0.5), "hint deadline")
		rig.r:tapOff()
		t.equal(rig.r:selectedCardId(), nil, "tap off the hand did not clear")
		t.equal(rig.sends, 0, "none of these may send")
		t.equal(#rig.r:display().hand, 5, "display hand")
	end)

	t.test("F6: at hand 4 the slots are inert and no Pass is ever emitted", function()
		-- A commit here would fly a card out and back on a GUARANTEED HandNotFive, which D-12 forbids a
		-- legitimate player from experiencing.
		local rig = newRig(nil, 0.2, { 1, 2, 3, 4 }, INBOX3)
		local taps = 0
		for _, id in { 1, 2, 3, 4 } do
			t.equal(rig.tap(id), nil, "emit at hand 4")
			t.equal(rig.tap(id), nil, "second emit at hand 4")
			taps += 1
		end
		t.equal(taps, 4, "every card must have been tapped")
		t.equal(rig.r:selectedCardId(), nil, "selection at hand 4")
		t.equal(rig.sends, 0, "send count at hand 4")
		t.deepEqual(idsOf(rig.r:display()), { 1, 2, 3, 4 }, "display changed at hand 4")
	end)

	t.test("D-07: a draw is instant and only legal at hand 4 with a non-empty inbox", function()
		local rig = newRig(nil, 0.2, { 1, 2, 3, 4 }, { 10, 11 })
		local e = rig.draw()
		t.truthy(e ~= nil, "no draw at (4, 2)")
		t.equal(sortedKeys((e :: Emit).payload), "seq", "Draw payload key set")
		t.equal((e :: Emit).name, "Draw")
		t.equal(rig.r:display().inbox, 1, "inbox")
		t.equal(rig.r:display().hand[5].cardId, nil, "placeholder")
		t.equal(#rig.r:display().hand, 5)
		local empty = newRig(nil, 0.2, { 1, 2, 3, 4 }, {})
		t.equal(empty.draw(), nil, "draw at (4, 0)")
		local full = newRig(nil, 0.2, HAND5, INBOX3)
		t.equal(full.draw(), nil, "draw at hand 5")
		t.equal(empty.sends + full.sends, 0, "no send from the illegal draws")
	end)

	t.test("a placeholder cannot be passed (information-limited, not a gate)", function()
		t.equal(scenPlaceholder(nil), 1)
	end)

	t.test("CARD-14 at 150 ms and at 300 ms: the happy pass converges with no visible residue", function()
		t.equal(scenHappy(nil), 2)
	end)

	t.test("CARD-14: a rejection returns the card visibly, and a correction is indistinguishable from it", function()
		local want = "cardId=3,kind=Returned"
		local seen = 0
		for _, code in REJECT_CODES do
			local rig = newRig(nil, 0.2, HAND5, INBOX3)
			rig.reject[1] = code
			rig.tap(3)
			rig.tap(3)
			rig.advance(4)
			t.equal(rig.server.lastCode, code, "the stub did not record the code it rejected with")
			t.equal(#rig.log, 1, `exactly one change for {code}`)
			t.equal(encode(rig.log), want, `change list for {code}`)
			t.equal(sortedKeys(rig.log[1] :: any), "cardId,kind", "no key other than kind and cardId (D-12)")
			t.deepEqual(idsOf(rig.r:display()), HAND5, "hand back to 5")
			t.equal(rig.r:display().downstream, 0, "downstream back down")
			seen += 1
		end
		t.equal(seen, #REJECT_CODES, "every code exercised")
		t.equal(seen, 16, "non-vacuity: the code list shrank")

		-- The server ACCEPTS but reports a different hand: a correction.
		local rig = newRig(nil, 0.2, HAND5, INBOX3)
		rig.tap(3)
		rig.tap(3)
		local corrected: Auth = {
			ackSeq = 1,
			seat = 1,
			hand = { faceOf(5), faceOf(4), faceOf(3), faceOf(2), faceOf(1) },
			inbox = 7,
			downstream = 0,
		}
		local changes = rig.r:onSync(corrected)
		t.equal(encode(changes), want, "a correction must be byte-identical to a rejection")

		-- A gateway-level reject never reaches the card core: only the watchdog resolves it.
		local lostRig = newRig(nil, 0.2, HAND5, INBOX3)
		lostRig.lost[1] = true
		lostRig.tap(3)
		lostRig.tap(3)
		lostRig.advance(TIMEOUT_DECI + 1)
		t.equal(encode(lostRig.log), want, "a rate-limit / lost message must be byte-identical too")
	end)

	t.test("two rapid passes with one rejected: the cumulative ack resolves both orderings", function()
		-- Hand 5 allows Pass, Draw, Pass in flight before any Sync: Pass(a) then Draw then Pass(b).
		local function run(rejectSeq: number): (Rig, { Change })
			local rig = newRig(nil, 0.2, HAND5, INBOX3)
			rig.reject[rejectSeq] = "NotYourCard"
			local emits: { Emit } = {}
			rig.tap(1)
			table.insert(emits, rig.tap(1) :: Emit)
			table.insert(emits, rig.draw() :: Emit)
			rig.tap(5)
			table.insert(emits, rig.tap(5) :: Emit)
			t.equal(#emits, 3, "three intents in flight")
			t.equal(rig.r:pendingCount(), 3, "pending before any Sync")
			-- One cumulative Sync covering all three, delivered once.
			for _, e in emits do
				rig.serverHandle(e)
			end
			local changes = rig.r:onSync(rig.snapshot())
			return rig, changes
		end

		local rigA, changesA = run(1) -- first Pass rejected, Draw naturally rejected at hand 5, second accepted
		t.equal(rigA.r:pendingCount(), 0, "A: pending not resolved by the single cumulative ack")
		t.equal(count(changesA, "Returned"), 1, "A: exactly one Returned")
		t.equal(encode({ changesA[1] }), "cardId=1,kind=Returned", "A: the rejected card returns")
		t.deepEqual(idsOf(rigA.r:display()), rigA.handIds(), "A: display == auth")
		for _, c in changesA do
			t.falsy(c.kind == "Returned" and (c :: any).cardId == 5, "A: the accepted card must not return")
		end

		local rigB, changesB = run(3) -- first Pass accepted, Draw accepted, second Pass rejected
		t.equal(rigB.r:pendingCount(), 0, "B: pending not resolved")
		t.equal(count(changesB, "Returned"), 1, "B: exactly one Returned")
		t.equal(encode({ changesB[1] }), "cardId=5,kind=Returned", "B: the rejected card returns")
		t.equal(count(changesB, "Flipped"), 1, "B: the accepted draw flips its placeholder")
		t.deepEqual(idsOf(rigB.r:display()), rigB.handIds(), "B: display == auth")
		for _, c in changesB do
			t.falsy(c.kind == "Returned" and (c :: any).cardId == 1, "B: the accepted card must not return")
		end
	end)

	t.test("a stale or out-of-order Sync is ignored by ackSeq monotonicity", function()
		local rig = newRig(nil, 0.2, HAND5, INBOX3)
		local fresh: Auth =
			{ ackSeq = 5, seat = 1, hand = { faceOf(1), faceOf(2), faceOf(3), faceOf(4) }, inbox = 2, downstream = 3 }
		rig.r:onSync(fresh)
		local before = rig.r:display()
		local stale: Auth = {
			ackSeq = 3,
			seat = 1,
			hand = { faceOf(9), faceOf(8), faceOf(7), faceOf(6), faceOf(5) },
			inbox = 9,
			downstream = 0,
		}
		local changes = rig.r:onSync(stale)
		t.deepEqual(changes, {}, "a stale Sync returned changes")
		t.deepEqual(rig.r:display(), before, "a stale Sync changed the display")
		t.deepEqual(idsOf(rig.r:display()), { 1, 2, 3, 4 }, "hand after the stale Sync")
	end)

	t.test("a valve forced pass: Notice plus Sync becomes Removed, not Returned, and does not touch pending", function()
		-- `Returned` means "the server did not accept what I did"; `Removed` means "the server did
		-- something to me". Confusing them would show a return animation for a card that genuinely left.
		local a = newRig(nil, 0.2, HAND5, INBOX3)
		a.tap(2) -- selected, not yet sent
		local ownBatch: { any } = {
			{ kind = "Drew", seat = 1, cardId = 10 },
			{ kind = "Passed", seat = 1, to = 2, cardId = 2 },
		}
		t.deepEqual(a.r:onTable(ownBatch, { 2, 3, 4 }), {}, "own-seat events must not change the hand")
		t.deepEqual(a.r:depths(), { 2, 3, 4 }, "depths")
		t.deepEqual(idsOf(a.r:display()), HAND5, "the hand comes only from Sync")
		t.deepEqual(a.r:onNotice({ code = "ForcedPass", cardId = 2 }), {}, "a notice returns no change")
		t.equal(a.r:selectedCardId(), nil, "the selection must clear when the notice names it")
		a.forcedPass(2)
		a.advance(2)
		t.equal(count(a.log, "Removed"), 1, "the forced card must be Removed")
		t.equal(count(a.log, "Returned"), 0, "a forced card must never be Returned")
		t.equal((a.log[1] :: any).cardId, 2, "removed card")

		-- A Pass of mine is in flight when the valve takes another card. The in-flight Pass is now
		-- guaranteed to be rejected (hand 4), so its card returns at once and the entry stays pending
		-- until the server's ack.
		local b = newRig(nil, 0.2, HAND5, INBOX3)
		b.tap(4)
		b.tap(4)
		t.equal(b.r:pendingCount(), 1, "my Pass is pending")
		b.forcedPass(2)
		b.advance(2)
		t.equal(b.r:pendingCount(), 1, "a server-initiated Sync must not touch my pending entry")
		t.equal(count(b.log, "Removed"), 1, "forced card is Removed")
		t.equal(count(b.log, "Returned"), 1, "only my doomed Pass returns")
		local removed: { Change } = {}
		local returned: { Change } = {}
		for _, c in b.log do
			table.insert(if c.kind == "Removed" then removed else returned, c)
		end
		t.equal(encode(removed), "cardId=2,kind=Removed", "forced card change")
		t.equal(encode(returned), "cardId=4,kind=Returned", "my doomed Pass returns, the forced card does not")
		t.equal(#b.r:display().hand, 4, "the display hand must stay at 4")
		b.advance(2)
		t.equal(b.r:pendingCount(), 0, "the ack resolves my entry")
		t.deepEqual(idsOf(b.r:display()), b.handIds(), "converged")
	end)

	t.test("the watchdog rolls a lost message back after the timeout, exactly once", function()
		t.equal(scenWatchdog(nil), 2)
	end)

	t.test("NaN and negative times error by name instead of disabling the watchdog", function()
		local rig = newRig(nil, 0.2, HAND5, INBOX3)
		t.throws(function()
			rig.r:tapSlot(1, 0 / 0)
		end, "nowDeci must be a finite non-negative number")
		t.throws(function()
			rig.r:tickWatchdog(math.huge)
		end, "nowDeci must be a finite non-negative number")
		t.throws(function()
			rig.r:onSync({ ackSeq = 0 / 0, seat = 1, hand = {}, inbox = 0, downstream = 0 })
		end, "ackSeq must be finite")
		t.throws(function()
			Prediction.new(0 / 0)
		end, "pendingTimeoutDeci")
	end)

	-- Fuzz ---------------------------------------------------------------------------------------------

	local FUZZ_ITERATIONS = 30
	local fuzzStats = { steps = 0, emits = 0, returned = 0, removed = 0, lost = 0, forced = 0, seconds = 0.0 }

	t.fuzz("convergence under random latency, reject masks and forced-pass injection", {
		iterations = FUZZ_ITERATIONS,
		gen = function(rng, i)
			local actions: { { kind: number, pick: number, adv: number } } = {}
			for _ = 1, 20 do
				table.insert(actions, { kind = rng:nextInt(1, 8), pick = rng:nextInt(1, 6), adv = rng:nextInt(1, 4) })
			end
			local lostChoice = ({ 0, 0, 0, 1, 2, 4, 8 })[rng:nextInt(1, 7)]
			return {
				latency = ({ 0.2, 0.3 })[rng:nextInt(1, 2)],
				rejectMask = rng:nextInt(0, 255),
				lostMask = lostChoice,
				forcedAt = if rng:nextInt(0, 1) == 1 then rng:nextInt(1, 20) else 0,
				startHand = rng:nextInt(4, 5),
				actions = actions,
				last = i == FUZZ_ITERATIONS,
			}
		end,
		check = function(v)
			local started = os.clock()
			local hand = { 1, 2, 3, 4, 5 }
			if v.startHand == 4 then
				table.remove(hand, 5)
			end
			local rig = newRig(nil, v.latency, hand, { 10, 11, 12 })
			for seq = 1, 64 do
				if bit32.band(v.rejectMask, bit32.lshift(1, (seq - 1) % 8)) ~= 0 then
					rig.reject[seq] = "HandNotFive"
				end
				if bit32.band(v.lostMask, bit32.lshift(1, (seq - 1) % 4)) ~= 0 then
					rig.lost[seq] = true
				end
			end

			local function invariants(label: string)
				local d = rig.r:display()
				local n = #d.hand
				assert(n == 4 or n == 5, `{label}: display hand is {n}`)
				assert(d.inbox >= 0, `{label}: inbox {d.inbox}`)
				assert(d.downstream >= 0, `{label}: downstream {d.downstream}`)
				if rig.r:pendingCount() == 0 then
					local ids: { any } = {}
					for _, f in rig.lastAuth.hand do
						table.insert(ids, f.cardId)
					end
					assert(sameIds(idsOf(d), ids), `{label}: display != auth with pending empty`)
					assert(d.inbox == rig.lastAuth.inbox, `{label}: inbox != auth`)
					assert(d.downstream == rig.lastAuth.downstream, `{label}: downstream != auth`)
				end
				fuzzStats.steps += 1
			end

			local function tapChecked(id: number?)
				local before = idsOf(rig.r:display())
				local emit = rig.tap(id)
				if emit ~= nil then
					fuzzStats.emits += 1
					local keys = sortedKeys(emit.payload)
					assert(keys == "seq" or keys == "cardId,seq", `emitted keys {keys}`)
					if emit.name == "Pass" then
						assert(emit.payload.cardId ~= nil, "Pass without a cardId")
						assert(
							table.find(before, emit.payload.cardId) ~= nil,
							"Pass named a card not in the display hand"
						)
					end
				end
			end

			for step, a in v.actions do
				local d = rig.r:display()
				local pickCard: number? = nil
				if a.pick <= #d.hand then
					pickCard = d.hand[a.pick].cardId
				end
				if a.kind == 1 then
					tapChecked(pickCard)
				elseif a.kind == 2 or a.kind == 3 then
					tapChecked(pickCard)
					tapChecked(pickCard)
				elseif a.kind == 4 then
					local before = idsOf(rig.r:display())
					local emit = rig.draw()
					if emit ~= nil then
						fuzzStats.emits += 1
						assert(sortedKeys(emit.payload) == "seq", "Draw payload keys")
						assert(#before == 4, "Draw emitted away from hand 4")
					end
				elseif a.kind == 5 then
					rig.r:tapOff()
				elseif a.kind == 6 then
					rig.r:tapRightPile(rig.now())
				elseif a.kind == 7 then
					tapChecked(999) -- a stray id the display has never held
				else
					rig.advance(a.adv)
				end
				if step == v.forcedAt then
					local target = rig.server.hand[1 + (a.pick % #rig.server.hand)]
					rig.forcedPass(target)
					fuzzStats.forced += 1
				end
				invariants(`step {step}`)
				rig.advance(a.adv) -- every step also lets time pass so Syncs interleave with later taps
				invariants(`step {step} after advance`)
			end

			-- Drain: every Sync lands and the watchdog resolves anything that never will.
			rig.advance(TIMEOUT_DECI + 10)
			invariants("drain")
			assert(rig.r:pendingCount() == 0, `pending {rig.r:pendingCount()} after the drain`)
			assert(sameIds(idsOf(rig.r:display()), rig.handIds()), "display did not converge to the server hand")
			for _, e in rig.emitted do
				if rig.lost[e.payload.seq] then
					fuzzStats.lost += 1
				end
			end
			fuzzStats.returned += count(rig.log, "Returned")
			fuzzStats.removed += count(rig.log, "Removed")

			fuzzStats.seconds += os.clock() - started
			if v.last then
				print(
					`prediction fuzz: iterations={FUZZ_ITERATIONS} steps={fuzzStats.steps} emits={fuzzStats.emits} returned={fuzzStats.returned} removed={fuzzStats.removed} lostSends={fuzzStats.lost} forced={fuzzStats.forced} elapsed={string.format(
						"%.3f",
						fuzzStats.seconds
					)}s`
				)
				assert(fuzzStats.emits > 0, "non-vacuity: the fuzz emitted nothing")
				assert(fuzzStats.returned > 0, "non-vacuity: the fuzz never exercised a rollback")
				assert(fuzzStats.forced > 0, "non-vacuity: no forced pass was injected")
				assert(fuzzStats.lost > 0, "non-vacuity: no sent message was lost")
				assert(fuzzStats.seconds < 0.3, `fuzz took {fuzzStats.seconds}s, budget 0.3s`)
			end
		end,
	})

	-- Mutations ------------------------------------------------------------------------------------------

	-- A tapSlot that commits on the FIRST tap (commits on the first tap): CARD-15's mutation.
	local function firstTapCommits(real: Reducer): Reducer
		local m = table.clone(real)
		m.tapSlot = function(_self: Reducer, cardId: number?, nowDeci: number): Emit?
			real:tapSlot(cardId, nowDeci)
			return real:tapSlot(cardId, nowDeci)
		end
		return m
	end

	local function payloadNamesTarget(real: Reducer): Reducer
		local m = table.clone(real)
		m.tapSlot = function(_self: Reducer, cardId: number?, nowDeci: number): Emit?
			local emit = real:tapSlot(cardId, nowDeci)
			if emit ~= nil then
				emit.payload.to = 2
				emit.payload.index = 3
			end
			return emit
		end
		return m
	end

	local function passableNilPlaceholder(real: Reducer): Reducer
		local m = table.clone(real)
		m.tapSlot = function(_self: Reducer, cardId: number?, nowDeci: number): Emit?
			if cardId == nil then
				for _, c in real:display().hand do
					if c.cardId == nil then
						return { name = "Pass", payload = { seq = 99, cardId = 0 } }
					end
				end
			end
			return real:tapSlot(cardId, nowDeci)
		end
		return m
	end

	local function syncDropsNothing(real: Reducer): Reducer
		local m = table.clone(real)
		m.onSync = function(_self: Reducer, auth: Auth): { Change }
			local stale = table.clone(auth)
			stale.ackSeq = 0 -- the cumulative ack never reaches the pending list
			return real:onSync(stale)
		end
		return m
	end

	local function watchdogNeverFires(real: Reducer): Reducer
		local m = table.clone(real)
		m.tickWatchdog = function(_self: Reducer, _nowDeci: number): { Change }
			return {}
		end
		return m
	end

	t.test("MUTATION: five broken reducers each turn their gate red", function()
		local exercised = 0
		local function expectRed(label: string, scenario: (Wrap?) -> number, mutant: Wrap)
			local cleanOk, cleanErr = pcall(scenario :: (Wrap?) -> any, nil)
			t.truthy(cleanOk, `{label}: the clean control must pass: {tostring(cleanErr)}`)
			local ok, err = pcall(scenario :: (Wrap?) -> any, mutant)
			t.falsy(ok, `{label}: the broken reducer was NOT caught`)
			print(`MUTATION: {label} -> red: {tostring(err)}`)
			exercised += 1
		end
		expectRed("onSync does not drop acked pending", scenHappy, syncDropsNothing)
		expectRed("watchdog never fires", scenWatchdog, watchdogNeverFires)
		expectRed("tapSlot commits on the first tap (firstTapCommits)", scenSingleTap, firstTapCommits)
		expectRed("payload carries a to key and a hand index", scenCommit, payloadNamesTarget)
		expectRed("a Pass naming a nil-id placeholder is allowed", scenPlaceholder, passableNilPlaceholder)
		t.equal(exercised, 5, "mutations exercised")
	end)
end
