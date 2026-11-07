--!strict
-- Plan 04-12: CardTable against the REAL engine. The headline assertion is that driving the engine
-- through the shell reaches a byte-identical Invariants.hash to driving it directly -- the one check
-- that proves the shell reimplements no rule.
--
-- Every gate has a clean control, a non-vacuity count, and its mutation is an injected broken
-- dependency (a wrapper IdleClock, a wrapper publisher, a spec-local shell variant), run through the
-- SAME checking helper as the clean path so the helper is proven able to fire.
--
-- `coroutine` appears below: this file lives under tests/, which guard R3 does not scan, and the
-- coroutine is the TEST's -- src/server/core never names it.
local CardConfig = require("../../src/shared/Config/Card")
local CardPool = require("../../src/shared/Config/CardPool")
local CardRouting = require("../../src/server/core/CardRouting")
local CardTable = require("../../src/server/core/CardTable")
local CardTiming = require("../../src/server/core/CardTiming")
local Engine = require("../../src/server/engine/Engine")
local IdleClock = require("../../src/server/core/IdleClock")
local Invariants = require("../../src/server/engine/Invariants")
local Pool = require("../../src/server/engine/Pool")
local RecordingPublisher = require("../harness/RecordingPublisher")
local Rng = require("../../src/server/engine/Rng")
local Round = require("../../src/shared/Config/Round")
local StallDetector = require("../../src/server/core/StallDetector")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")
local Bots = require("../../scripts/sim/Bots")

type Rec = RecordingPublisher.RecordingPublisher
type Clock = { value: number }

local POSE: CardTable.Vec3 = { x = 0, y = 0, z = 0 }
local LOOK: CardTable.Vec3 = { x = 0, y = 0, z = -1 }

local function stallDetector(): StallDetector.StallDetector
	return StallDetector.new({
		actionsPerSeat = 96,
		minDeci = 450,
		cueDeci = 50,
		repeatDeci = 300,
		onTelemetry = function() end,
	})
end

type Fixture = {
	ct: CardTable.CardTable,
	rec: Rec,
	now: Clock,
	idle: IdleClock.IdleClock,
	stall: StallDetector.StallDetector,
	rng: any,
	users: { number },
	telemetry: { string },
	completed: { { seat: number, playerId: number, rank: number } },
	removed: { { seat: number, playerId: number, cause: Types.RemoveCause } },
	seqs: { [number]: number },
	publisher: CardRouting.Publisher,
	state: () -> Types.State,
}

type FixtureOptions = {
	seekers: number?, -- seated seekers; players in the round is this + 1
	seed: number?,
	idle: IdleClock.IdleClock?,
	stall: StallDetector.StallDetector?,
	publisher: CardRouting.Publisher?,
	maxStrikes: number?,
	autoPassDeci: number?,
	onCompleted: ((seat: number, playerId: number, rank: number) -> ())?,
	baseId: number?,
}

local function newFixture(o: FixtureOptions?): Fixture
	local opts: FixtureOptions = o or {}
	local seekers = opts.seekers or 3
	local baseId = opts.baseId or 100
	local users: { number } = {}
	for i = 1, seekers do
		users[i] = baseId + i
	end
	local rec = RecordingPublisher.new()
	local now: Clock = { value = 0 }
	local rng = Rng.new(opts.seed or 424242)
	local idle = opts.idle
		or IdleClock.new({ autoPassDeci = opts.autoPassDeci or 80, maxStrikes = opts.maxStrikes or 3 })
	local stall = opts.stall or stallDetector()
	local telemetry: { string } = {}
	local completed: { { seat: number, playerId: number, rank: number } } = {}
	local removed: { { seat: number, playerId: number, cause: Types.RemoveCause } } = {}
	local publisher: CardRouting.Publisher = opts.publisher or rec
	local ct = CardTable.new({
		publisher = publisher,
		nowDeci = function()
			return now.value
		end,
		rng = rng,
		extraRanks = CardPool.EXTRA_RANKS,
		jokers = CardPool.JOKERS,
		jokerMode = CardPool.JOKER_MODE :: "Wild",
		idle = idle,
		stall = stall,
		unixDeadlineFor = function(remaining: number)
			return 1000 + remaining / 10
		end,
		onCompleted = opts.onCompleted or function(seat, playerId, rank)
			table.insert(completed, { seat = seat, playerId = playerId, rank = rank })
		end,
		onSeatRemoved = function(seat, playerId, cause)
			table.insert(removed, { seat = seat, playerId = playerId, cause = cause })
		end,
		onTelemetry = function(name)
			table.insert(telemetry, name)
		end,
	})
	local specs: { CardTable.SeatSpec } = {}
	for _, id in users do
		table.insert(specs, { playerId = id, position = POSE, look = LOOK })
	end
	ct:start(specs)
	return {
		ct = ct,
		rec = rec,
		now = now,
		idle = idle,
		stall = stall,
		rng = rng,
		users = users,
		telemetry = telemetry,
		completed = completed,
		removed = removed,
		seqs = {},
		publisher = publisher,
		state = function()
			return ct:debugState()
		end,
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

-- hands + inboxes + retired + terminal. Rule 8's "never destroyed", asserted by conservation.
local function cardCount(st: Types.State): number
	local total = #st.retired + #st.terminal
	for _, seat in st.seats do
		total += #seat.hand + #seat.inbox
	end
	return total
end

local function conservationProblems(st: Types.State): { string }
	local problems: { string } = {}
	local counted = cardCount(st)
	if counted ~= st.totalCards then
		table.insert(problems, `card count {counted} ~= totalCards {st.totalCards}`)
	end
	local ok, why = Invariants.check(st)
	if not ok then
		table.insert(problems, `Invariants.check reports {tostring(why)}`)
	end
	return problems
end

-- Swap `cardId` into hand/inbox[index] of a seat. Every container is live, so counters are unaffected.
local function place(st: Types.State, seatId: number, where: "hand" | "inbox", index: number, cardId: number)
	local target = st.seats[seatId][where]
	local displaced = target[index]
	for _, seat in st.seats do
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

-- Seat 1 holds three of rank 1; the fourth is at the front of its inbox. Its next Draw completes.
local function arrangeCompletion(fx: Fixture): number
	local st = fx.state()
	local cards: { number } = {}
	for id, rank in st.rankOf do
		if rank == 1 then
			table.insert(cards, id)
		end
	end
	assert(#cards == 4, "rank 1 has four copies")
	place(st, 1, "hand", 1, cards[1])
	place(st, 1, "hand", 2, cards[2])
	place(st, 1, "hand", 3, cards[3])
	place(st, 1, "inbox", 1, cards[4])
	local ok, why = Invariants.check(st)
	assert(ok, `arrangement left the state reporting {tostring(why)}`)
	return 1
end

local function publicEvents(fx: Fixture): { any }
	local out: { any } = {}
	for _, call in fx.rec.callsOfKind("Table") do
		for _, event in call.payload do
			table.insert(out, event)
		end
	end
	return out
end

-- ------------------------------------------------------------------------------------------------
-- Case 1: equivalence with driving the engine directly.
-- ------------------------------------------------------------------------------------------------

local function policyIntent(st: Types.State, seatId: number, rng: any): Types.Intent?
	local seat = st.seats[seatId]
	if not seat.live then
		return nil
	end
	if #seat.hand == Types.MAX_HAND then
		return { kind = "Pass", seat = seatId, cardId = Bots.randomPass(st, seatId, rng) }
	elseif #seat.hand == Types.HAND_SIZE and #seat.inbox > 0 then
		return { kind = "Draw", seat = seatId }
	end
	return nil
end

-- Runs one round of the same scripted sequence through the shell and straight through Engine.apply.
-- Returns (shellHash, directHash, accepted, problems).
local function equivalenceRound(players: number, seed: number): (string, string, number, { string })
	local seekers = players - 1
	local fx = newFixture({ seekers = seekers, seed = seed })
	local config = Pool.poolConfig(players, CardPool.EXTRA_RANKS, CardPool.JOKERS, CardPool.JOKER_MODE :: "Wild")
	local direct = Engine.newRound(config, fx.users, Rng.new(seed))
	local policyRng = Rng.new(seed + 7919)
	local accepted = 0
	local problems: { string } = {}
	local st = fx.state()
	for step = 1, 450 do
		if accepted >= 420 then
			break
		end
		local progressed = false
		for seatId = 1, seekers do
			local intent = policyIntent(st, seatId, policyRng)
			if intent ~= nil then
				local userId = st.seats[seatId].playerId
				if intent.kind == "Draw" then
					draw(fx, userId)
				elseif intent.kind == "Pass" then
					pass(fx, userId, intent.cardId)
				end
				local result = Engine.apply(direct, intent)
				if result.ok then
					accepted += 1
					progressed = true
				end
			end
			-- An illegal intent now and then, so the rejection path is compared as well.
			if (step + seatId) % 11 == 0 and st.seats[seatId].live then
				draw(fx, st.seats[seatId].playerId)
				Engine.apply(direct, { kind = "Draw", seat = seatId })
			end
		end
		if not progressed then
			break
		end
	end
	local shellHash, directHash = Invariants.hash(st), Invariants.hash(direct)
	for _, p in conservationProblems(st) do
		table.insert(problems, `shell: {p}`)
	end
	for _, p in conservationProblems(direct) do
		table.insert(problems, `direct: {p}`)
	end
	return shellHash, directHash, accepted, problems
end

-- ------------------------------------------------------------------------------------------------
-- Case 6 rig: a yielding publisher, wrapper objects for idle and stall, and the shell variants.
-- ------------------------------------------------------------------------------------------------

type Counters = { syncs: number, noteApplies: number, expectedApplies: number }

type Rig = {
	fx: Fixture,
	counters: Counters,
	realIdle: IdleClock.IdleClock,
	realStall: StallDetector.StallDetector,
	yielding: boolean,
	-- Lune runs the main script itself in a coroutine, so isyieldable() is TRUE on the main thread; the
	-- gate must name the one thread allowed to yield.
	thread: thread?,
	onFirst: (() -> ())?,
}

local function newRig(maxStrikes: number, seekers: number, baseId: number): Rig
	local counters: Counters = { syncs = 0, noteApplies = 0, expectedApplies = 0 }
	local realIdle = IdleClock.new({ autoPassDeci = 80, maxStrikes = maxStrikes })
	local realStall = stallDetector()
	local idleWrapper: IdleClock.IdleClock = table.clone(realIdle)
	idleWrapper.sync = function(_self, view, nowDeci, acted)
		counters.syncs += 1
		realIdle:sync(view, nowDeci, acted)
	end
	idleWrapper.tick = function(_self, nowDeci)
		local commands = realIdle:tick(nowDeci)
		for _, command in commands do
			if command.kind == "AutoPass" or command.kind == "Bench" then
				counters.expectedApplies += 1
			end
		end
		return commands
	end
	local stallWrapper: StallDetector.StallDetector = table.clone(realStall)
	stallWrapper.noteApply = function(_self, liveSeats, nowDeci)
		counters.noteApplies += 1
		realStall:noteApply(liveSeats, nowDeci)
	end
	local rec = RecordingPublisher.new()
	local rig: Rig = {
		fx = nil :: any,
		counters = counters,
		realIdle = realIdle,
		realStall = realStall,
		yielding = false,
		thread = nil,
		onFirst = nil,
	}
	local function gate()
		local first = rig.onFirst
		if first ~= nil then
			rig.onFirst = nil
			first()
		end
		if rig.yielding and coroutine.running() == rig.thread then
			coroutine.yield()
		end
	end
	local publisher: CardRouting.Publisher = {
		toPlayer = function(userId: number, kind: string, payload: unknown)
			gate()
			rec.toPlayer(userId, kind, payload)
		end,
		toSeated = function(kind: string, payload: unknown)
			gate()
			rec.toSeated(kind, payload)
		end,
		toAll = function(kind: string, payload: unknown)
			gate()
			rec.toAll(kind, payload)
		end,
	}
	rig.fx = newFixture({
		seekers = seekers,
		idle = idleWrapper,
		stall = stallWrapper,
		publisher = publisher,
		baseId = baseId,
	})
	rig.fx.rec = rec
	return rig
end

type Snapshot = {
	hash: string,
	deadlines: { [number]: number },
	strikes: { [number]: number },
	actions: number,
}

local function snapshot(rig: Rig): Snapshot
	local st = rig.fx.state()
	local snap: Snapshot = { hash = Invariants.hash(st), deadlines = {}, strikes = {}, actions = 0 }
	for seatId = 1, #st.seats do
		local deadline = rig.realIdle:deadlineDeci(seatId)
		if deadline ~= nil then
			snap.deadlines[seatId] = deadline
		end
		snap.strikes[seatId] = rig.realIdle:strikesOf(seatId)
	end
	snap.actions = rig.realStall:actionsSinceProgress()
	return snap
end

local function viewOf(st: Types.State): IdleClock.View
	local view: IdleClock.View = {}
	for id, seat in st.seats do
		view[id] = { live = seat.live, handSize = #seat.hand, inboxSize = #seat.inbox }
	end
	return view
end

-- Spec-local shell variants. Each calls the same Engine, CardRouting, idle and stall as CardTable, in a
-- different ORDER. "good" is the specified order (a control proving the variant machinery is not itself
-- the difference); "early" publishes between apply and idle:sync.
local function miniIntent(rig: Rig, userId: number, cardId: number, mode: "good" | "early", now: number)
	local st = rig.fx.state()
	local seat = rig.fx.ct:seatOf(userId) :: number
	local result = Engine.apply(st, { kind = "Pass", seat = seat, cardId = cardId })
	local copyOf = CardRouting.assignCopies(st.rankOf, st.config.ranks)
	local function publishAll()
		rig.fx.publisher.toPlayer(userId, "Sync", { ackSeq = 0, seat = seat })
		CardRouting.publish(rig.fx.publisher, result.events, copyOf, function(s: number)
			return st.seats[s].playerId
		end)
	end
	if mode == "early" then
		publishAll()
	end
	rig.realIdle:sync(viewOf(st), now, if result.ok then seat else nil)
	rig.counters.syncs += 1
	if result.ok then
		rig.counters.noteApplies += 1
		rig.realStall:noteApply(st.liveCount, now)
	end
	if mode == "good" then
		publishAll()
	end
end

-- "collect" is the specified sweep; "perCommand" publishes each command's batch immediately.
local function miniTick(rig: Rig, mode: "collect" | "perCommand", now: number)
	local st = rig.fx.state()
	local copyOf = CardRouting.assignCopies(st.rankOf, st.config.ranks)
	local commands: { any } = rig.fx.idle:tick(now)
	local pending: { () -> () } = {}
	local function applyOne(intent: Types.Intent)
		local result = Engine.apply(st, intent)
		rig.realIdle:sync(viewOf(st), now, nil)
		rig.counters.syncs += 1
		if result.ok then
			rig.counters.noteApplies += 1
			rig.realStall:noteApply(st.liveCount, now)
		end
		for _, event in result.events do
			if event.kind == "SeatRemoved" or event.kind == "Completed" then
				rig.realStall:noteProgress(now)
				break
			end
		end
		table.insert(pending, function()
			CardRouting.publish(rig.fx.publisher, result.events, copyOf, function(s: number)
				return st.seats[s].playerId
			end)
		end)
	end
	for _, command in commands do
		if command.kind == "AutoPass" then
			local cardId = IdleClock.pickUniform(st.seats[command.seat].hand, rig.fx.rng)
			applyOne({ kind = "Pass", seat = command.seat, cardId = cardId })
		elseif command.kind == "Bench" then
			applyOne({ kind = "Remove", seat = command.seat, cause = "Benched" })
		end
		if mode == "perCommand" then
			for _, step in pending do
				step()
			end
			table.clear(pending)
		end
	end
	for _, step in pending do
		step()
	end
end

-- Runs `action` in a coroutine whose publisher yields on every call; at the FIRST publish `check` runs
-- (before the yield), then `between` drives the second intent on the main thread; the coroutine is then
-- resumed to the end.
local function driveYielding(rig: Rig, action: () -> (), check: () -> (), between: () -> ())
	rig.yielding = true
	rig.onFirst = check
	local co = coroutine.create(action)
	rig.thread = co
	local ok, err = coroutine.resume(co)
	assert(ok, tostring(err))
	assert(coroutine.status(co) == "suspended", "the action never reached a publish")
	between()
	local guard = 0
	while coroutine.status(co) ~= "dead" do
		guard += 1
		assert(guard < 200, "runaway coroutine")
		local resumed, why = coroutine.resume(co)
		assert(resumed, tostring(why))
	end
	rig.yielding = false
end

local function cardHandAt(rig: Rig, seat: number, index: number): number
	return rig.fx.state().seats[seat].hand[index]
end

-- Scenario A (intents): seat 2 and seat 1 both at hand 5, seat 2's inbox empty. Intent 1 is seat 2's
-- pass (disarms its clock); intent 2 is seat 1's pass INTO seat 2, which re-arms it.
local function setupIntentScenario(rig: Rig)
	local fx = rig.fx
	local u1, u2 = fx.users[1], fx.users[2]
	fx.now.value = 0
	draw(fx, u1)
	pass(fx, u1, cardHandAt(rig, 1, 5))
	draw(fx, u2)
	draw(fx, u1)
	local st = fx.state()
	assert(#st.seats[1].hand == 5 and #st.seats[2].hand == 5 and #st.seats[2].inbox == 0, "scenario A preconditions")
end

type Variant = "real" | "good" | "early"

local function intentOne(rig: Rig, variant: Variant, card: number)
	rig.fx.now.value = 500
	if variant == "real" then
		pass(rig.fx, rig.fx.users[2], card)
	else
		miniIntent(rig, rig.fx.users[2], card, variant, 500)
	end
end

local function intentTwo(rig: Rig, variant: Variant, card: number)
	rig.fx.now.value = 505
	if variant == "real" then
		pass(rig.fx, rig.fx.users[1], card)
	else
		miniIntent(rig, rig.fx.users[1], card, variant, 505)
	end
end

-- Returns (first-publish problems, interleaved snapshot, serial snapshot).
local function runIntentScenario(variant: Variant): ({ string }, Snapshot, Snapshot)
	local problems: { string } = {}

	local rig = newRig(3, 2, 200)
	setupIntentScenario(rig)
	local card1, card2 = cardHandAt(rig, 2, 1), cardHandAt(rig, 1, 1)
	local before = Invariants.hash(rig.fx.state())
	local syncs0, applies0 = rig.counters.syncs, rig.counters.noteApplies
	driveYielding(rig, function()
		intentOne(rig, variant, card1)
	end, function()
		-- The moment the first byte goes out: every state update for intent 1 is already complete.
		if Invariants.hash(rig.fx.state()) == before then
			table.insert(problems, "at the first publish the engine apply had not happened")
		end
		if rig.counters.syncs - syncs0 ~= 1 then
			table.insert(
				problems,
				`at the first publish idle:sync had run {rig.counters.syncs - syncs0} times, expected 1`
			)
		end
		if rig.counters.noteApplies - applies0 ~= 1 then
			table.insert(
				problems,
				`at the first publish stall:noteApply had run {rig.counters.noteApplies - applies0} times, expected 1`
			)
		end
	end, function()
		intentTwo(rig, variant, card2)
	end)
	local interleaved = snapshot(rig)
	assert(Invariants.check(rig.fx.state()), "interleaved run left the state invalid")

	local ref = newRig(3, 2, 200)
	setupIntentScenario(ref)
	intentOne(ref, "real", cardHandAt(ref, 2, 1))
	intentTwo(ref, "real", cardHandAt(ref, 1, 1))
	return problems, interleaved, snapshot(ref)
end

-- Scenario B (sweep): maxStrikes = 1 so one expiry yields AutoPass + Strike + Bench for seat 1 in a
-- single sweep. Seat 3 (upstream of seat 1) is at hand 5 and passes at the first publish.
local function setupSweepScenario(rig: Rig)
	local fx = rig.fx
	local u1, u2, u3 = fx.users[1], fx.users[2], fx.users[3]
	fx.now.value = 0
	draw(fx, u1)
	fx.now.value = 1
	pass(fx, u1, cardHandAt(rig, 1, 5))
	fx.now.value = 2
	draw(fx, u2)
	fx.now.value = 3
	pass(fx, u2, cardHandAt(rig, 2, 5))
	fx.now.value = 4
	draw(fx, u1)
	fx.now.value = 5
	draw(fx, u3)
	local st = fx.state()
	assert(#st.seats[1].hand == 5 and #st.seats[3].hand == 5, "scenario B preconditions")
	assert(rig.realIdle:deadlineDeci(1) == 84, `seat 1 deadline is {tostring(rig.realIdle:deadlineDeci(1))}`)
	assert(rig.realIdle:deadlineDeci(3) == 85, "seat 3 must outlive the sweep")
end

local function runSweepScenario(variant: "real" | "collect" | "perCommand"): ({ string }, Snapshot, Snapshot, number)
	local problems: { string } = {}
	local rig = newRig(1, 3, 300)
	setupSweepScenario(rig)
	local card = cardHandAt(rig, 3, 1)
	local applies0, expected0 = rig.counters.noteApplies, rig.counters.expectedApplies
	driveYielding(rig, function()
		rig.fx.now.value = 84
		if variant == "real" then
			rig.fx.ct:tick()
		else
			miniTick(rig, variant, 84)
		end
	end, function()
		local expected = rig.counters.expectedApplies - expected0
		local applied = rig.counters.noteApplies - applies0
		-- Structural, scenario-independent: at the first publish of a sweep EVERY command the sweep will
		-- apply has already been applied.
		if applied ~= expected then
			table.insert(problems, `first publish with {applied} of {expected} applies done`)
		end
	end, function()
		rig.fx.now.value = 86
		pass(rig.fx, rig.fx.users[3], card)
	end)
	local interleaved = snapshot(rig)
	assert(Invariants.check(rig.fx.state()), "interleaved sweep left the state invalid")

	local ref = newRig(1, 3, 300)
	setupSweepScenario(ref)
	local refCard = cardHandAt(ref, 3, 1)
	ref.fx.now.value = 84
	ref.fx.ct:tick()
	ref.fx.now.value = 86
	pass(ref.fx, ref.fx.users[3], refCard)
	return problems, interleaved, snapshot(ref), rig.counters.expectedApplies - expected0
end

-- ------------------------------------------------------------------------------------------------
-- Case 9: the RoundStart key set.
-- ------------------------------------------------------------------------------------------------

-- Hand-copied: the map Node type is an erased export type and exposes no field list at runtime. These are
-- its twelve fields minus `position` and `look`, which are legal inside a pose.
local BANNED_KEYS: { string } = {
	"name",
	"className",
	"attributes",
	"tags",
	"size",
	"up",
	"anchored",
	"canCollide",
	"shape",
	"children",
}
local BANNED: { [string]: true } = {}
for _, key in BANNED_KEYS do
	BANNED[key] = true
end

local function keysOf(node: any): { string }
	local keys: { string } = {}
	for k in node do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	return keys
end

-- Recursive whitelist walk. Every unexpected key is ONE problem naming the key and its path; an
-- unexpected key is not descended into (it is already reported). Returns (problems, nodes, seatEntries).
local function keySetProblems(root: any): ({ string }, number, number)
	local problems: { string } = {}
	local nodes = 0
	local seatEntries = 0
	local function exact(node: any, path: string, allowed: { string })
		nodes += 1
		if type(node) ~= "table" then
			table.insert(problems, `{path} is not a table`)
			return
		end
		local isAllowed: { [string]: true } = {}
		for _, key in allowed do
			isAllowed[key] = true
		end
		for _, key in keysOf(node) do
			if not isAllowed[key] then
				local tag = if BANNED[key] then " (a map-node field)" else ""
				table.insert(problems, `unexpected key {key} at {path}{tag}`)
			end
		end
		for _, key in allowed do
			if node[key] == nil then
				table.insert(problems, `missing key {key} at {path}`)
			end
		end
	end
	local function vec(node: any, path: string)
		exact(node, path, { "x", "y", "z" })
		if type(node) == "table" then
			for _, axis in { "x", "y", "z" } do
				local v = node[axis]
				if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
					table.insert(problems, `{path}.{axis} is not a finite number`)
				end
			end
		end
	end
	exact(root, "RoundStart", { "seats", "jokerMode", "ranks" })
	if type(root) == "table" and type(root.seats) == "table" then
		for index, entry in root.seats do
			seatEntries += 1
			local path = `RoundStart.seats[{index}]`
			exact(entry, path, { "seat", "playerId", "position", "look" })
			if type(entry) == "table" then
				vec(entry.position, `{path}.position`)
				vec(entry.look, `{path}.look`)
			end
		end
	end
	return problems, nodes, seatEntries
end

local function firstRoundStart(rec: Rec): any
	local calls = rec.callsOfKind("RoundStart")
	assert(#calls == 1, `expected one RoundStart, saw {#calls}`)
	assert(calls[1].method == "toSeated", "RoundStart must be toSeated")
	return calls[1].payload
end

local NODEISH = {
	playerId = 7,
	position = { x = 0, y = 0, z = 0 },
	look = { x = 0, y = 0, z = -1 },
	name = "Seat1",
	className = "Part",
	attributes = {},
	tags = {},
	size = { x = 1, y = 1, z = 1 },
	up = { x = 0, y = 1, z = 0 },
	anchored = true,
	canCollide = true,
	shape = "Block",
	children = {},
}

-- A careless `start`: forwards the incoming struct WHOLE instead of building the payload field by field.
local function startLeaky(rec: Rec, seats: { any })
	local entries: { any } = {}
	for i, spec in seats do
		local entry = table.clone(spec)
		entry.seat = i
		entries[i] = entry
	end
	rec.toSeated("RoundStart", { seats = entries, jokerMode = "Wild", ranks = #seats + CardPool.EXTRA_RANKS })
end

return function(t: Test.Runner)
	t.test("driving the engine through the shell reaches the same state as driving it directly", function()
		local seeds = { 11, 4242, 90210 }
		local cells = 0
		local lines: { string } = {}
		for _, players in { 3, 6, 10 } do
			local acceptedTotal = 0
			for _, seed in seeds do
				local shellHash, directHash, accepted, problems = equivalenceRound(players, seed)
				t.deepEqual(problems, {}, `N={players} seed={seed}`)
				t.equal(shellHash, directHash, `N={players} seed={seed}: state hash diverged`)
				t.truthy(accepted >= 20, `non-vacuity: N={players} seed={seed} accepted only {accepted}`)
				acceptedTotal += accepted
				cells += 1
			end
			table.insert(lines, `N={players}: {acceptedTotal} accepted actions over {#seeds} seeds`)
		end
		t.equal(cells, 9)
		print(`cardtable case 1: {table.concat(lines, "; ")}`)
	end)

	t.test(
		"the shipped conversion reaches IdleClock: expiry lands at autoPassDeci(8.0, 10) and not a tick earlier",
		function()
			local deci = CardTiming.autoPassDeci(CardPool.AUTO_PASS_MAX_SECONDS, Round.DECISECONDS_PER_SECOND)
			t.equal(deci, 80, "the shipped number")
			local function drained(autoPassDeci: number): ({ { any } }, Fixture)
				local real = IdleClock.new({ autoPassDeci = autoPassDeci, maxStrikes = CardConfig.MAX_STRIKES })
				local sweeps: { { any } } = {}
				local recording: IdleClock.IdleClock = table.clone(real)
				recording.tick = function(_self, nowDeci)
					local commands = real:tick(nowDeci)
					table.insert(sweeps, commands)
					return commands
				end
				local fx = newFixture({ seekers = 3, idle = recording })
				fx.now.value = 10
				draw(fx, fx.users[1]) -- seat 1 at hand 5; deadline armed at 10 + autoPassDeci
				fx.now.value = 10 + deci - 1
				fx.ct:tick()
				fx.now.value = 10 + deci
				fx.ct:tick()
				return sweeps, fx
			end
			local sweeps, fx = drained(deci)
			t.equal(#sweeps[1], 0, "no command one deci early")
			t.equal(#sweeps[2], 2, "AutoPass and Strike at armedAt + deci")
			t.equal(sweeps[2][1].kind, "AutoPass")
			t.equal(sweeps[2][2].kind, "Strike")
			t.equal(#fx.rec.callsOfKind("Notice"), 1, "the Strike notice reached the player")
			-- MUTATION: an IdleClock one deci longer does not fire where the real one does.
			local mutantSweeps = drained(deci + 1)
			t.equal(#mutantSweeps[2], 0, "the autoPassDeci + 1 mutant must not fire at armedAt + deci")
			print(
				`cardtable case 1b: autoPassDeci = {deci}; real sweeps {#sweeps[1]}/{#sweeps[2]} commands, mutant (+1) {#mutantSweeps[1]}/{#mutantSweeps[2]}`
			)
		end
	)

	t.test("the AFK path benches through Remove{Benched} and the cards reach the successor", function()
		local fx = newFixture({ seekers = 3 })
		local st = fx.state()
		local total0 = cardCount(st)
		local successor = st.seats[1].next
		local inboxBefore = #st.seats[successor].inbox
		t.truthy(fx.idle:deadlineDeci(1) ~= nil, "non-vacuity: the dealer's clock is armed")
		for _, at in { 80, 160, 240 } do
			fx.now.value = at
			fx.ct:tick()
		end
		local benched: { any } = {}
		for _, event in publicEvents(fx) do
			if event.kind == "SeatRemoved" and event.cause == "Benched" then
				table.insert(benched, event)
			end
		end
		t.equal(#benched, 1, "exactly one Benched removal")
		t.equal(benched[1].routedTo, successor)
		t.truthy(benched[1].cards > 0, "cards were routed")
		t.equal(
			#st.seats[successor].inbox,
			inboxBefore + benched[1].cards,
			"the successor's inbox grew by exactly that many"
		)
		t.equal(cardCount(st), total0, "total card count conserved")
		t.deepEqual(conservationProblems(st), {})
		t.equal(#fx.removed, 1)
		t.equal(fx.removed[1].cause, "Benched")
		t.equal(fx.ct:seatOf(fx.users[1]), nil, "the benched player no longer owns a seat")
		print(
			`cardtable case 2: benched seat 1 routed {benched[1].cards} cards to seat {successor}; count {total0} -> {cardCount(
				st
			)}`
		)
	end)

	t.test("MUTATION: a bench that destroys the cards is caught by the conservation assertion", function()
		-- Deleting a removed seat's cards can make the remaining ranks unsolvable and deadlock the round,
		-- which is why rule 8 exists. The variant drops the seat without calling Engine.apply.
		local real = newFixture({ seekers = 3 })
		real.ct:removePlayer(real.users[1])
		t.deepEqual(conservationProblems(real.state()), {}, "control: the real removal conserves")

		local broken = newFixture({ seekers = 3 })
		local st = broken.state()
		st.seats[1].hand = {}
		st.seats[1].inbox = {}
		local problems = conservationProblems(st)
		t.truthy(#problems > 0, "a card-destroying bench must fail the conservation helper")
		print(`  destroying bench: {#problems} problems, e.g. {problems[1]}`)
	end)

	t.test("the shell never issues Remove{cause = Completed}; the engine's completion path does", function()
		local fx = newFixture({ seekers = 3 })
		arrangeCompletion(fx)
		draw(fx, fx.users[1])
		local events = publicEvents(fx)
		local kinds: { string } = {}
		for _, event in events do
			table.insert(kinds, event.kind)
		end
		local completedAt, removedAt = table.find(kinds, "Completed"), table.find(kinds, "SeatRemoved")
		t.truthy(completedAt ~= nil and removedAt == (completedAt :: number) + 1, "Completed then SeatRemoved")
		t.equal(events[removedAt :: number].cause, "Completed")
		t.equal(#fx.completed, 1, "onCompleted fired exactly once")
		t.equal(fx.completed[1].seat, 1)
		t.equal(fx.completed[1].playerId, fx.users[1])
		t.equal(fx.completed[1].rank, 1)
		t.equal(#fx.removed, 1)
		t.equal(fx.removed[1].cause, "Completed")
		-- The engine refuses it directly. ShellRemoveCause excludes "Completed", so the shell issuing it
		-- is a type error as well; this is the runtime half.
		local fresh = newFixture({ seekers = 3 })
		t.throws(function()
			Engine.apply(fresh.state(), { kind = "Remove", seat = 1, cause = "Completed" })
		end, "Completed")
	end)

	t.test("MUTATION: one bad command does not abort the sweep, and the collected batches still publish", function()
		-- The mutation-table row "bench issues Remove with cause Completed" is unwritable as stated:
		-- ShellRemoveCause excludes it, so it is a type error rather than a test failure. The reachable
		-- property is containment. (Remove{Completed} skips the retirement, so its four hand cards would
		-- route into circulation and conservation would break -- which is why the engine throws on it and
		-- the shell's type excludes it.)
		local function run(withMalformed: boolean): (Fixture, number)
			local real = IdleClock.new({ autoPassDeci = 80, maxStrikes = 3 })
			local mutant: IdleClock.IdleClock = table.clone(real)
			mutant.tick = function(_self, _nowDeci)
				local commands: { any } = { { kind = "AutoPass", seat = 1 } }
				if withMalformed then
					table.insert(commands, { kind = "Explode", seat = 1 })
				end
				table.insert(commands, { kind = "Strike", seat = 2, strikes = 1, owes = "Draw" })
				return commands
			end
			local fx = newFixture({ seekers = 3, idle = mutant })
			draw(fx, fx.users[1]) -- seat 1 now holds five, so the AutoPass is legal
			fx.rec.reset()
			local before = cardCount(fx.state())
			fx.now.value = 100
			fx.ct:tick()
			return fx, before
		end
		for _, withMalformed in { false, true } do
			local fx, before = run(withMalformed)
			local label = if withMalformed then "malformed" else "control"
			local st = fx.state()
			t.equal(cardCount(st), before, `{label}: card count`)
			t.deepEqual(conservationProblems(st), {}, `{label}: invariants`)
			local passed = 0
			for _, event in publicEvents(fx) do
				if event.kind == "Passed" then
					passed += 1
				end
			end
			t.equal(passed, 1, `{label}: the AutoPass batch published`)
			local strikeNotices = 0
			for _, call in fx.rec.callsOfKind("Notice") do
				if call.payload.code == "Strike" and call.userId == fx.users[2] then
					strikeNotices += 1
				end
			end
			t.equal(strikeNotices, 1, `{label}: the following command still ran`)
			local contained = table.find(fx.telemetry, "command_failed_Explode") ~= nil
			t.equal(contained, withMalformed, `{label}: telemetry names the failed kind`)
			if withMalformed then
				print(
					`cardtable case 4b: malformed command contained; telemetry = {table.concat(fx.telemetry, ",")}; AutoPass batch and Strike notice still published; count {before} -> {cardCount(
						st
					)}`
				)
			end
		end
	end)

	t.test("a disconnect routes through the same generic removal with cause Disconnected", function()
		local fx = newFixture({ seekers = 3 })
		local st = fx.state()
		local total0 = cardCount(st)
		t.truthy(fx.idle:deadlineDeci(1) ~= nil, "non-vacuity: the clock was armed before the disconnect")
		fx.ct:removePlayer(fx.users[1])
		local removals: { any } = {}
		for _, event in publicEvents(fx) do
			if event.kind == "SeatRemoved" then
				table.insert(removals, event)
			end
		end
		t.equal(#removals, 1)
		t.equal(removals[1].cause, "Disconnected")
		t.equal(cardCount(st), total0)
		t.deepEqual(conservationProblems(st), {})
		t.equal(fx.ct:seatOf(fx.users[1]), nil)
		t.equal(fx.idle:deadlineDeci(1), nil, "the idle clock forgot the seat")
		t.equal(fx.idle:strikesOf(1), 0)
		fx.ct:removePlayer(fx.users[1]) -- idempotent
		t.equal(#fx.removed, 1)
	end)

	t.test("rule 6: a yielding publisher cannot interleave two intents mid-state", function()
		-- Intents. The control (miniIntent good) and the real shell both pass; publishing between apply
		-- and idle:sync fails both the structural first-publish check and the composite snapshot.
		local realProblems, realSnap, realRef = runIntentScenario("real")
		t.deepEqual(realProblems, {}, "real shell: first-publish bookkeeping")
		t.deepEqual(realSnap, realRef, "real shell: composite snapshot equals the serial run")
		local goodProblems, goodSnap, goodRef = runIntentScenario("good")
		t.deepEqual(goodProblems, {}, "control variant: first-publish bookkeeping")
		t.deepEqual(goodSnap, goodRef, "control variant: composite snapshot equals the serial run")
		t.truthy(next(realSnap.deadlines) ~= nil, "non-vacuity: the snapshot holds armed deadlines")

		local earlyProblems, earlySnap, earlyRef = runIntentScenario("early")
		t.truthy(#earlyProblems > 0, "MUTATION: publishing between apply and idle:sync must fail the structural check")
		local snapDiffers = false
		for _, seat in { 1, 2 } do
			if earlySnap.deadlines[seat] ~= earlyRef.deadlines[seat] then
				snapDiffers = true
			end
		end
		if earlySnap.hash ~= earlyRef.hash then
			snapDiffers = true
		end
		t.truthy(snapDiffers, "MUTATION: the composite snapshot must differ from the serial run")
		print(
			`cardtable case 6a: real deadlines {realSnap.deadlines[1]},{realSnap.deadlines[2]}; early-publish deadlines {earlySnap.deadlines[1]},{earlySnap.deadlines[2]} vs serial {earlyRef.deadlines[1]},{earlyRef.deadlines[2]}; structural: {earlyProblems[1]}`
		)

		-- Sweeps.
		local sProblems, sSnap, sRef, applies = runSweepScenario("real")
		t.equal(applies, 2, "non-vacuity: the sweep applies an AutoPass and a Bench")
		t.deepEqual(sProblems, {}, "real tick: every command applied before the first publish")
		t.deepEqual(sSnap, sRef, "real tick: composite snapshot equals the serial run")
		local cProblems, cSnap, cRef = runSweepScenario("collect")
		t.deepEqual(cProblems, {}, "control variant tick")
		t.deepEqual(cSnap, cRef, "control variant tick snapshot")
		-- MUTATION: a tick that publishes each command's batch immediately. Caught STRUCTURALLY.
		local pProblems, pSnap, pRef = runSweepScenario("perCommand")
		t.truthy(#pProblems > 0, "MUTATION: a tick that publishes per command must fail the structural check")
		-- RECORDED LIMIT: the plan expected the pass-into-the-benched-seat interleave to also separate the
		-- snapshots. It does not. The dumped cards keep their order whichever side of the bench the pass
		-- lands (hand sorted, then inbox, then the late card), and every deadline is armed at the sweep's
		-- own instant. A seat's own Draw as the interleave was tried while developing this and is equally invisible,
		-- because the deal's ascending ids make "drawn then sorted into the hand" and "still at the
		-- inbox front" produce the same routed order. So this mutant is detected STRUCTURALLY ONLY, which
		-- is what the first-publish applies-count assertion exists for.
		local sameAsSerial = pSnap.hash == pRef.hash and next(pSnap.deadlines) == next(pRef.deadlines)
		print(
			`cardtable case 6b: per-command tick structural: {pProblems[1]}; composite snapshot indistinguishable from serial: {tostring(
				sameAsSerial
			)}`
		)
	end)

	t.test("a throwing completion sink does not take the round down or swallow a message", function()
		local fx = newFixture({
			seekers = 3,
			onCompleted = function()
				error("sink exploded")
			end,
		})
		arrangeCompletion(fx)
		draw(fx, fx.users[1])
		local sawCompleted = false
		for _, event in publicEvents(fx) do
			if event.kind == "Completed" then
				sawCompleted = true
			end
		end
		t.truthy(sawCompleted, "the Table batch was still published")
		t.truthy(table.find(fx.telemetry, "sink_failed_onCompleted") ~= nil, "telemetry recorded the failure")
		t.deepEqual(conservationProblems(fx.state()), {})
		t.truthy(fx.ct:isLive(), "the round continues")
		draw(fx, fx.users[2]) -- another seat can still act without error
		t.equal(#fx.removed, 1, "onSeatRemoved still fired after the failing sink")
	end)

	t.test("the config is built through Pool.poolConfig and ranks follow amendment A3", function()
		-- Amendment A3's off-by-one: poolConfig takes PLAYERS IN THE ROUND and is the only place the
		-- subtraction is written.
		for n = 3, 10 do
			local fx = newFixture({ seekers = n - 1 })
			local st = fx.state()
			t.equal(st.config.ranks, (n - 1) + CardPool.EXTRA_RANKS, `N={n} ranks`)
			t.equal(st.seatCount, n - 1, `N={n} seatCount`)
		end
	end)

	t.test("the RoundStart payload carries EXACTLY the published key set and nothing from the map", function()
		local fx = newFixture({ seekers = 3 })
		local payload = firstRoundStart(fx.rec)
		local problems, nodes, seatEntries = keySetProblems(payload)
		t.deepEqual(problems, {}, "real start")
		t.truthy(nodes >= 1 + 3 * 3, `non-vacuity: only {nodes} nodes visited`)
		t.equal(seatEntries, 3, "seat entries checked")
		print(`cardtable case 9: {nodes} nodes visited, {seatEntries} seat entries, 0 problems`)

		-- MUTATION: a careless start forwards the struct whole.
		local mutations = 0
		local leakyRec = RecordingPublisher.new()
		startLeaky(leakyRec, { NODEISH })
		local leaky = keySetProblems(firstRoundStart(leakyRec))
		-- Every banned name is reported.
		local reportedNames: { [string]: true } = {}
		for _, problem in leaky do
			for _, key in BANNED_KEYS do
				if string.find(problem, `unexpected key {key} at `, 1, true) then
					reportedNames[key] = true
				end
			end
		end
		local distinct = 0
		for _ in reportedNames do
			distinct += 1
		end
		t.equal(distinct, #BANNED_KEYS, "every banned name is reported")
		t.equal(#leaky, #BANNED_KEYS, "reported-problem count: one per banned key")
		mutations += 1

		-- The REAL start fed the identical nodeish input reports zero.
		local nodeishRec = RecordingPublisher.new()
		local rig = newFixture({ seekers = 3 })
		local ct = CardTable.new({
			publisher = nodeishRec,
			nowDeci = function()
				return 0
			end,
			rng = Rng.new(5),
			extraRanks = CardPool.EXTRA_RANKS,
			jokers = CardPool.JOKERS,
			jokerMode = "Wild",
			idle = IdleClock.new({ autoPassDeci = 80, maxStrikes = 3 }),
			stall = stallDetector(),
			unixDeadlineFor = function(r)
				return r
			end,
			onCompleted = function() end,
			onSeatRemoved = function() end,
			onTelemetry = function() end,
		})
		local nodeishSeats: { any } = {}
		for i = 1, 3 do
			local spec = table.clone(NODEISH)
			spec.playerId = rig.users[i]
			nodeishSeats[i] = spec
		end
		ct:start(nodeishSeats)
		local realProblems = keySetProblems(firstRoundStart(nodeishRec))
		t.deepEqual(realProblems, {}, "real start fed the nodeish input must report zero problems")
		t.equal(mutations, 1)
		print(
			`  mutation (by-reference forward): {#leaky} problems reported ({#BANNED_KEYS} banned names x 1 seat); real start on identical input: {#realProblems}`
		)
	end)
end
