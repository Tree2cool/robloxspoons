--!strict
-- CARD-13 privacy gate (plan 04-12). CardTable is driven against the REAL engine with a recording
-- publisher; every assertion reads what was actually called, never what the router claims.
--
-- Every gate here has a clean control, a non-vacuity count, and its mutation is an injected broken
-- publisher (the tests/engine/valve.spec.luau convention) driven through the SAME checking helper as the
-- clean path, so the helper is proven able to fire.
local CardRouting = require("../../src/server/core/CardRouting")
local CardTable = require("../../src/server/core/CardTable")
local IdleClock = require("../../src/server/core/IdleClock")
local Invariants = require("../../src/server/engine/Invariants")
local Livelock = require("../harness/Livelock")
local RecordingPublisher = require("../harness/RecordingPublisher")
local Rng = require("../../src/server/engine/Rng")
local StallDetector = require("../../src/server/core/StallDetector")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

type Rec = RecordingPublisher.RecordingPublisher
type Wrap = (base: Rec, state: () -> Types.State, seatOfUser: (number) -> number?) -> CardRouting.Publisher

type Options = {
	leak: boolean?,
	wrap: Wrap?,
	userIds: { number }?,
	seed: number?,
}

type Fixture = {
	ct: CardTable.CardTable,
	rec: Rec,
	state: () -> Types.State,
	users: { number },
	telemetry: { string },
	completed: { { seat: number, playerId: number, rank: number } },
	seqs: { [number]: number },
}

local POSE: CardTable.Vec3 = { x = 0, y = 0, z = 0 }

-- Three seated seekers: Pool.poolConfig(4, 3, 1, "Wild").
local function newFixture(opts: Options?): Fixture
	local o: Options = opts or {}
	local users = o.userIds or { 101, 102, 103 }
	local rec = RecordingPublisher.new({ leak = o.leak })
	local ct: CardTable.CardTable
	local publisher: CardRouting.Publisher = rec
	if o.wrap ~= nil then
		publisher = o.wrap(rec, function()
			return ct:debugState()
		end, function(userId: number)
			return ct:seatOf(userId)
		end)
	end
	local telemetry: { string } = {}
	local completed: { { seat: number, playerId: number, rank: number } } = {}
	ct = CardTable.new({
		publisher = publisher,
		nowDeci = function()
			return 0
		end,
		rng = Rng.new(o.seed or 424242),
		extraRanks = 3,
		jokers = 1,
		jokerMode = "Wild",
		idle = IdleClock.new({ autoPassDeci = 80, maxStrikes = 3 }),
		stall = StallDetector.new({
			actionsPerSeat = 96,
			minDeci = 450,
			cueDeci = 50,
			repeatDeci = 300,
			onTelemetry = function() end,
		}),
		unixDeadlineFor = function(remainingDeci: number)
			return 1000 + remainingDeci / 10
		end,
		onCompleted = function(seat, playerId, rank)
			table.insert(completed, { seat = seat, playerId = playerId, rank = rank })
		end,
		onSeatRemoved = function() end,
		onTelemetry = function(name)
			table.insert(telemetry, name)
		end,
	})
	local specs: { CardTable.SeatSpec } = {}
	for _, id in users do
		table.insert(specs, { playerId = id, position = POSE, look = { x = 0, y = 0, z = -1 } })
	end
	ct:start(specs)
	return {
		ct = ct,
		rec = rec,
		state = function()
			return ct:debugState()
		end,
		users = users,
		telemetry = telemetry,
		completed = completed,
		seqs = {},
	}
end

local function nextSeq(fx: Fixture, userId: number): number
	local n = (fx.seqs[userId] or 0) + 1
	fx.seqs[userId] = n
	return n
end

local function draw(fx: Fixture, userId: number)
	fx.ct:onIntent(userId, "Draw", { seq = nextSeq(fx, userId) })
end

local function pass(fx: Fixture, userId: number, cardId: number)
	fx.ct:onIntent(userId, "Pass", { seq = nextSeq(fx, userId), cardId = cardId })
end

-- The scripted deal: a draw and a pass per seat, repeated so cards reach every seat.
local function scriptedDeal(fx: Fixture, rounds: number)
	for _ = 1, rounds do
		for _, userId in fx.users do
			draw(fx, userId)
			local seat = fx.ct:seatOf(userId)
			if seat ~= nil then
				local hand = fx.state().seats[seat].hand
				pass(fx, userId, hand[#hand])
			end
		end
	end
end

-- CASE 1 helper. Every Sync is toPlayer, addressed to the seat it describes, and no OTHER player's
-- recorder holds that very payload. Returns (problems, syncCount).
local function syncProblems(fx: Fixture): ({ string }, number)
	local problems: { string } = {}
	local syncs = 0
	for _, call in fx.rec.calls() do
		if call.kind == "Sync" then
			syncs += 1
			if call.method ~= "toPlayer" then
				table.insert(problems, `a Sync went out via {call.method}`)
			else
				local owner = call.userId :: number
				if fx.ct:seatOf(owner) ~= nil and call.payload.seat ~= fx.ct:seatOf(owner) then
					table.insert(problems, `a Sync for seat {call.payload.seat} was sent to user {owner}`)
				end
				for _, other in fx.users do
					if other ~= owner then
						for _, seen in fx.rec.callsTo(other) do
							if seen.payload == call.payload then
								table.insert(problems, `user {other} also received user {owner}'s Sync payload`)
							end
						end
					end
				end
			end
		end
	end
	return problems, syncs
end

local BANNED_PUBLIC: { [string]: true } = { rank = true, copy = true, hand = true, inbox = true }

-- CASE 2 helper. Recursive, by KEY NAME. A `Completed` event may carry its own `rank` and its `faces`
-- list (each face has rank and copy): the four retired faces turn face up at the seat by design.
-- Returns (problems, nodesVisited, publicCalls).
local function publicWalkProblems(fx: Fixture): ({ string }, number, number)
	local problems: { string } = {}
	local visited = 0
	local publicCalls = 0
	local function walk(node: any, path: string, allowed: boolean)
		visited += 1
		if type(node) ~= "table" then
			return
		end
		local isCompleted = node.kind == "Completed"
		for key, value in node do
			local keyName = tostring(key)
			if BANNED_PUBLIC[keyName] and not allowed and not (isCompleted and keyName == "rank") then
				table.insert(problems, `{path}.{keyName} crossed to a public audience`)
			end
			walk(value, `{path}.{keyName}`, allowed or (isCompleted and keyName == "faces"))
		end
	end
	for index, call in fx.rec.calls() do
		if call.method == "toSeated" or call.method == "toAll" then
			publicCalls += 1
			walk(call.payload, `call{index}:{call.kind}`, false)
		end
	end
	return problems, visited, publicCalls
end

-- CASE 3 helper. Forced pass: exactly one ForcedPass Notice, to that seat's player only, the table's
-- Table batches never contain a ValveForcedPass, and no other player ever sees a Notice.
-- Returns (problems, noticeCount).
local function forcedPassProblems(fx: Fixture, forcedUser: number): ({ string }, number)
	local problems: { string } = {}
	local notices = fx.rec.callsOfKind("Notice")
	local forced = 0
	for _, call in notices do
		if call.payload.code == "ForcedPass" then
			forced += 1
			if call.method ~= "toPlayer" or call.userId ~= forcedUser then
				table.insert(problems, `ForcedPass notice went {call.method} to {tostring(call.userId)}`)
			end
		end
	end
	if forced ~= 1 then
		table.insert(problems, `expected exactly one ForcedPass notice, saw {forced}`)
	end
	for _, call in fx.rec.callsOfKind("Table") do
		for _, event in call.payload do
			if event.kind == "ValveForcedPass" then
				table.insert(problems, "a ValveForcedPass appeared in a public Table batch")
			end
		end
	end
	for _, other in fx.users do
		if other ~= forcedUser then
			for _, call in fx.rec.callsTo(other) do
				if call.kind == "Notice" then
					table.insert(problems, `user {other} received a Notice`)
				end
			end
		end
	end
	return problems, forced
end

-- The hijack: the valve fires only on an exact whole-table state repeat, which a dealt round never
-- produces on demand. The Livelock fixture is a verified completion-free cycle whose first valve firing
-- lands on action 113 (tests/engine/apply.spec.luau). Its fields are copied INTO the table's own state,
-- so every action still runs through CardTable:onIntent -> Engine.apply. CardTable keeps its own
-- `copyOf` (21 entries from the real deal), which covers the fixture's 12 card ids.
local FORCED_ACTION = 113

local function newForcedFixture(opts: Options?): (Fixture, number, number)
	local o: Options = opts or {}
	o.userIds = { 101, 102 }
	local fx = newFixture(o)
	local fixture = Livelock.build({ antiLivelockValve = true, valveSeed = 1 })
	local state = fx.state()
	state.config = fixture.config
	state.seatCount = fixture.seatCount
	state.totalCards = fixture.totalCards
	state.rankOf = fixture.rankOf
	state.seats = fixture.seats
	state.liveCount = fixture.liveCount
	state.head = fixture.head
	state.retired = fixture.retired
	state.terminal = fixture.terminal
	state.counters = fixture.counters
	state.valve = fixture.valve
	local driver = Livelock.newDriver(state)
	local firedAt = 0
	local forcedUser = 0
	for action = 1, FORCED_ACTION + 5 do
		local intent = Livelock.nextIntent(driver)
		local userId = state.seats[intent.seat].playerId
		if intent.kind == "Draw" then
			draw(fx, userId)
			local hand = state.seats[intent.seat].hand
			driver.lastDrawn = hand[#hand]
		elseif intent.kind == "Pass" then
			pass(fx, userId, intent.cardId)
		end
		if #fx.rec.callsOfKind("Notice") > 0 then
			firedAt = action
			forcedUser = userId
			break
		end
	end
	return fx, firedAt, forcedUser
end

local function keyList(t: any): string
	local keys: { string } = {}
	for k in t do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

-- Puts `cardId` at hand[index] / inbox[index] of a seat by swapping with wherever it currently is. Every
-- container is live, so the in-play counters are unaffected.
local function place(state: Types.State, seatId: number, where: "hand" | "inbox", index: number, cardId: number)
	local target = state.seats[seatId][where]
	local displaced = target[index]
	for _, seat in state.seats do
		for _, container in { seat.hand, seat.inbox } do
			local at = table.find(container, cardId)
			if at ~= nil then
				container[at] = displaced
				target[index] = cardId
				return
			end
		end
	end
	error("place: card not found")
end

-- A real completion at seat 1: three of rank r in hand plus the fourth at the front of the inbox.
-- Returns (rank, fifth card id, the four retired ids).
local function arrangeCompletion(fx: Fixture): (number, number, { number })
	local state = fx.state()
	local rankCards: { number } = {}
	for id, rank in state.rankOf do
		if rank == 1 then
			table.insert(rankCards, id)
		end
	end
	assert(#rankCards == 4, "rank 1 must have four copies")
	place(state, 1, "hand", 1, rankCards[1])
	place(state, 1, "hand", 2, rankCards[2])
	place(state, 1, "hand", 3, rankCards[3])
	place(state, 1, "inbox", 1, rankCards[4])
	local fifth = state.seats[1].hand[4]
	assert(state.rankOf[fifth] ~= 1, "the fifth must not be of the completed rank")
	local ok, why = Invariants.check(state)
	assert(ok, `arrangement left the state reporting {tostring(why)}`)
	return 1, fifth, rankCards
end

-- Mutant publishers (each wraps the recording fake; each is a broken dependency, not a source edit).
local function wrapSyncViaSeated(base: Rec): CardRouting.Publisher
	return {
		toPlayer = function(userId: number, kind: string, payload: unknown)
			if kind == "Sync" then
				base.toSeated("Sync", payload)
			else
				base.toPlayer(userId, kind, payload)
			end
		end,
		toSeated = base.toSeated,
		toAll = base.toAll,
	}
end

local function wrapForcedInPublicBatch(base: Rec): CardRouting.Publisher
	return {
		toPlayer = function(userId: number, kind: string, payload: unknown)
			local notice = payload :: any
			if kind == "Notice" and notice.code == "ForcedPass" then
				base.toSeated("Table", { { kind = "ValveForcedPass", cardId = notice.cardId } })
			end
			base.toPlayer(userId, kind, payload)
		end,
		toSeated = base.toSeated,
		toAll = base.toAll,
	}
end

local function wrapRankOnTable(base: Rec): CardRouting.Publisher
	return {
		toPlayer = base.toPlayer,
		toSeated = function(kind: string, payload: unknown)
			if kind == "Table" then
				local events = table.clone(payload :: any)
				for i, event in events do
					if event.kind == "Drew" then
						local leaked = table.clone(event)
						leaked.rank = 3
						events[i] = leaked
					end
				end
				base.toSeated(kind, events)
			else
				base.toSeated(kind, payload)
			end
		end,
		toAll = base.toAll,
	}
end

-- A broken seat -> userId resolver: the Notice goes to the player seated AFTER the affected one.
local function wrapNoticeToSuccessor(
	base: Rec,
	state: () -> Types.State,
	seatOfUser: (number) -> number?
): CardRouting.Publisher
	return {
		toPlayer = function(userId: number, kind: string, payload: unknown)
			if kind == "Notice" then
				local seat = seatOfUser(userId)
				if seat ~= nil then
					local st = state()
					base.toPlayer(st.seats[st.seats[seat].next].playerId, kind, payload)
					return
				end
			end
			base.toPlayer(userId, kind, payload)
		end,
		toSeated = base.toSeated,
		toAll = base.toAll,
	}
end

return function(t: Test.Runner)
	t.test("every Sync reaches exactly its owner and no other player sees it", function()
		local fx = newFixture()
		scriptedDeal(fx, 4)
		local problems, syncs = syncProblems(fx)
		t.deepEqual(problems, {}, "clean path")
		for _, userId in fx.users do
			local own = 0
			for _, call in fx.rec.calls() do
				if call.kind == "Sync" and call.userId == userId then
					own += 1
				end
			end
			t.truthy(own >= 3, `non-vacuity: user {userId} saw only {own} Syncs`)
		end
		print(`privacy case 1: {syncs} Syncs, {#fx.rec.calls()} calls total, 0 problems`)
	end)

	t.test("no payload sent via toSeated or toAll carries a rank for a card that is not a retired face", function()
		local fx = newFixture()
		scriptedDeal(fx, 4)
		local problems, visited, publicCalls = publicWalkProblems(fx)
		t.deepEqual(problems, {}, "clean path")
		t.truthy(visited >= 40, `non-vacuity: only {visited} payload nodes visited`)
		t.truthy(publicCalls >= 10, `non-vacuity: only {publicCalls} public calls`)
		print(`privacy case 2: {publicCalls} public calls, {visited} nodes walked, 0 problems`)
	end)

	t.test("a ValveForcedPass becomes a private Notice and the table sees an ordinary Passed", function()
		-- D-18 fires in roughly 1 round in 12 at a full roster, so this is an ordinary path and not an
		-- edge case. The valve is forced by the verified Livelock cycle, driven through onIntent.
		local fx, firedAt, forcedUser = newForcedFixture()
		t.equal(firedAt, FORCED_ACTION, "the valve's first firing on this fixture")
		local problems, forced = forcedPassProblems(fx, forcedUser)
		t.deepEqual(problems, {}, "clean path")
		t.equal(forced, 1)
		local tables = fx.rec.callsOfKind("Table")
		local last = tables[#tables].payload
		local kinds: { string } = {}
		for _, event in last do
			table.insert(kinds, event.kind)
		end
		t.deepEqual(kinds, { "Drew", "Passed" }, "the table sees an ordinary draw and pass")
		local other = if forcedUser == 101 then 102 else 101
		for _, call in fx.rec.callsTo(other) do
			t.truthy(call.kind ~= "Notice", "the other player saw a Notice")
		end
		print(`privacy case 3: valve fired at action {firedAt}; Notice to user {forcedUser} only`)
	end)

	t.test("a completion publishes the four retired faces to the table and the fifth card to nobody", function()
		local fx = newFixture()
		local rank, fifth, retired = arrangeCompletion(fx)
		draw(fx, 101)
		t.equal(#fx.completed, 1, "onCompleted fired once")
		t.equal(fx.completed[1].rank, rank)
		local completedEvent: any = nil
		for _, call in fx.rec.callsOfKind("Table") do
			for _, event in call.payload do
				if event.kind == "Completed" then
					completedEvent = event
				end
			end
		end
		t.truthy(completedEvent ~= nil, "a public Completed was published")
		t.equal(#completedEvent.faces, 4, "four retired faces")
		local copies: { number } = {}
		local faceIds: { number } = {}
		for _, face in completedEvent.faces do
			t.equal(face.rank, rank)
			table.insert(copies, face.copy)
			table.insert(faceIds, face.cardId)
		end
		table.sort(copies)
		table.sort(faceIds)
		table.sort(retired)
		t.deepEqual(copies, { 1, 2, 3, 4 }, "each face has its copy number")
		t.deepEqual(faceIds, retired, "the faces are the four retired cards")
		-- The fifth card id appears in NO public payload, as a cardId or under any key.
		local fifthSeen = 0
		local nodes = 0
		local function scan(node: any)
			nodes += 1
			if type(node) ~= "table" then
				return
			end
			for key, value in node do
				if key == "fifth" then
					fifthSeen += 1
				end
				if key == "cardId" and value == fifth then
					fifthSeen += 1
				end
				scan(value)
			end
		end
		for _, call in fx.rec.calls() do
			if call.method ~= "toPlayer" then
				scan(call.payload)
			end
		end
		t.truthy(nodes > 10, "non-vacuity: nodes scanned")
		t.equal(fifthSeen, 0, "the fifth card crossed to a public audience")
		-- The finisher's own final Sync is still private.
		local ownSyncs = 0
		for _, call in fx.rec.callsOfKind("Sync") do
			if call.userId == 101 then
				ownSyncs += 1
				t.equal(call.method, "toPlayer")
			end
		end
		t.truthy(ownSyncs >= 2, "the finisher received a Sync after the completion")
		print(
			`privacy case 4: Completed with {#completedEvent.faces} faces, fifth card {fifth} never public ({nodes} nodes)`
		)
	end)

	t.test("a rejected intent produces the same Sync message shape as an accepted one (D-12)", function()
		local fx = newFixture()
		-- seat 1 rests at hand 4: a Pass is refused with HandNotFive.
		fx.rec.reset()
		pass(fx, 101, fx.state().seats[1].hand[1])
		local rejected = fx.rec.callsOfKind("Sync")
		fx.rec.reset()
		draw(fx, 101)
		local accepted = fx.rec.callsOfKind("Sync")
		t.truthy(#rejected >= 1 and #accepted >= 1, "non-vacuity: both branches ran")
		t.equal(rejected[1].method, "toPlayer")
		t.equal(accepted[1].method, "toPlayer")
		t.equal(rejected[1].userId, 101)
		t.equal(keyList(rejected[1].payload), keyList(accepted[1].payload), "same key set")
		t.equal(rejected[1].payload.ackSeq, 1, "the rejected attempt is acked at its own seq")
		t.equal(accepted[1].payload.ackSeq, 2, "the accepted attempt is acked at its own seq")
		local telemetryHit = table.find(fx.telemetry, "reject_HandNotFive") ~= nil
		t.truthy(telemetryHit, "onTelemetry received the reject")
		-- No payload anywhere names a reject.
		local banned: { [string]: true } = { reject = true, code = true, reason = true, error = true }
		local leaks = 0
		local function scan(node: any)
			if type(node) ~= "table" then
				if type(node) == "string" and string.find(node, "HandNotFive") then
					leaks += 1
				end
				return
			end
			for key, value in node do
				if banned[tostring(key)] then
					leaks += 1
				end
				scan(value)
			end
		end
		for _, call in fx.rec.calls() do
			scan(call.payload)
		end
		t.equal(leaks, 0, "a reject code reached a client")
		print(`privacy case 5: rejected and accepted Sync keys = {keyList(rejected[1].payload)}`)
	end)

	t.test("MUTATION: five leaks each turn the gate red", function()
		local mutations = 0
		local function caseOneAndTwo(opts: Options): ({ string }, { string })
			local fx = newFixture(opts)
			scriptedDeal(fx, 4)
			local a = syncProblems(fx)
			local b = publicWalkProblems(fx)
			return a, b
		end

		-- clean control through the very same helpers
		local cleanA, cleanB = caseOneAndTwo({})
		t.deepEqual(cleanA, {}, "control: case 1 helper")
		t.deepEqual(cleanB, {}, "control: case 2 helper")

		-- 1. the publisher's own leak option (every toPlayer becomes a broadcast)
		local leakA = caseOneAndTwo({ leak = true })
		t.truthy(#leakA > 0, "leak = true must turn case 1 red")
		mutations += 1
		print(`  mutation 1 (leak = true): {#leakA} problems, e.g. {leakA[1]}`)

		-- 2. Sync routed via toSeated
		local viaSeated = caseOneAndTwo({ wrap = wrapSyncViaSeated })
		t.truthy(#viaSeated > 0, "Sync via toSeated must turn case 1 red")
		mutations += 1
		print(`  mutation 2 (Sync via toSeated): {#viaSeated} problems, e.g. {viaSeated[1]}`)

		-- 3. ValveForcedPass in the public batch
		local cleanFx, _, cleanUser = newForcedFixture()
		t.deepEqual((forcedPassProblems(cleanFx, cleanUser)), {}, "control: case 3 helper")
		local fx3, _, user3 = newForcedFixture({ wrap = wrapForcedInPublicBatch })
		local p3 = forcedPassProblems(fx3, user3)
		t.truthy(#p3 > 0, "a public ValveForcedPass must turn case 3 red")
		mutations += 1
		print(`  mutation 3 (ValveForcedPass public): {#p3} problems, e.g. {p3[1]}`)

		-- 4. a rank on a Table payload for a card that is not retired
		local _, rankLeak = caseOneAndTwo({ wrap = wrapRankOnTable })
		t.truthy(#rankLeak > 0, "a rank on a Table payload must turn case 2 red")
		mutations += 1
		print(`  mutation 4 (rank on Table): {#rankLeak} problems, e.g. {rankLeak[1]}`)

		-- 5. a Notice delivered to the WRONG player. Not a broadcast, so `leak` cannot see it: only an
		-- identity check on the recipient can.
		local fx5, _, user5 = newForcedFixture({ wrap = wrapNoticeToSuccessor })
		local p5 = forcedPassProblems(fx5, user5)
		t.truthy(#p5 > 0, "a Notice to the wrong player must turn case 3 red")
		local other = if user5 == 101 then 102 else 101
		local sawNotice = false
		for _, call in fx5.rec.callsTo(other) do
			if call.kind == "Notice" then
				sawNotice = true
			end
		end
		t.truthy(sawNotice, "callsTo(other) now contains the Notice it previously lacked")
		mutations += 1
		print(`  mutation 5 (Notice to wrong player): {#p5} problems, e.g. {p5[1]}`)

		t.equal(mutations, 5, "mutation count")
	end)

	t.test("a stray intent from a userId with no seat answers that player and touches no one else", function()
		local fx = newFixture()
		local before = Invariants.hash(fx.state())
		fx.rec.reset()
		fx.ct:onIntent(999, "Pass", { seq = 7, cardId = 3 })
		local calls = fx.rec.calls()
		t.equal(#calls, 1, "exactly one call")
		t.equal(calls[1].method, "toPlayer")
		t.equal(calls[1].userId, 999)
		t.equal(calls[1].kind, "Sync")
		t.equal(calls[1].payload.ackSeq, 7)
		t.equal(calls[1].payload.seat, 0)
		t.equal(Invariants.hash(fx.state()), before, "the engine state moved")
	end)
end
