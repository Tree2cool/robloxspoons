--!strict
-- The live card table's server shell (CARD-02, CARD-13, CARD-14, CARD-16, CARD-17, CARD-19). It turns a
-- client intent into an `Engine.apply` call and the returned events into exactly the right message for
-- exactly the right audience.
--
--   1. PURE ZONE. No Roblox API, no clock read (`nowDeci` is injected), no yields anywhere. The file is
--      a FOUND-05 guarded root twice over: by the `CardTable` entry in `guardedNamePrefixes` (CLAUDE.md
--      rule 1 names it explicitly, which is why the filename is worth keeping) and by its location,
--      since every file in a pure zone is an R2/R3 root. `zones.luau`'s prefix list is not extended.
--   2. RULE 6: NOTHING IS PUBLISHED INSIDE A MUTATION. `apply` returns its events precisely so the
--      caller can publish afterwards; a yield mid-mutation lets two handlers interleave. There is no
--      callback into `apply` and no nesting of one `apply` inside another's handling. Beyond that, the
--      ORDER is the contract: every command is applied and its bookkeeping (`idle:sync`,
--      `stall:noteApply`, `stall:noteProgress`) completed BEFORE the first byte of any of them is
--      published. A publisher that yields at its first call therefore cannot let a second intent run
--      against bookkeeping that is still pending. `tick` does this at SWEEP granularity: it drains both
--      command sources, applies and bookkeeps every command, and only then publishes the collected
--      batches.
--   3. RULE 7: THE SEAT COMES FROM THE ROSTER, NEVER THE PAYLOAD. The gateway handed us a `userId`
--      derived from the Player the platform supplied, and `Ring.pass` resolves `next` inside `apply`.
--   4. RULE 8: ONE GENERIC REMOVAL. Bench, disconnect and the engine's own completion all go through
--      `Remove` / the completion path; a removed seat's cards route to the successor and are never
--      destroyed -- deleting them can make the remaining ranks unsolvable and deadlock the round.
--      `ShellRemoveCause` is narrowed because `apply` throws on "Completed", which the engine owns.
--   5. THE SHELL REIMPLEMENTS NO RULE. Legality, completion, the valve and seat removal are the
--      engine's. If the shell ever needs to inspect a hand to decide something that is a design error;
--      D-35 is the precedent: the hand-4 expiry is strike-only partly so no hand-inspection logic lands
--      out here. The one exception is the auto-pass PICK, which is IdleClock.pickUniform's.
--   6. CARD-13: `Sync` and `Notice` go through `toPlayer` and nothing else. `CardRouting.AUDIENCE` is
--      the table, `assertPublic` the backstop, guard R4 confines the Roblox call. A client never
--      receives another seat's hand contents in any form.
--   7. D-12 AT THE WIRE LEVEL: every Draw/Pass attempt is answered with the same `Sync` shape, accepted
--      or rejected. `result.reject` goes to telemetry only, as a counter name.
--   8. SEAT POSES ARE PUBLISHED, DELIBERATELY AND NARROWLY. The 3D seat stacks and travelling cards
--      are drawn at the seat anchors, and the map contract puts `CardTable/Seats/Seat1..Seat9` under
--      the map's `Data` folder, which is never cloned into Workspace. A client cannot learn a seat pose
--      from the replicated tree, and it needs one. Why this is not a rule 3 violation: rule 3 protects
--      spoon positions, hands, piles and the default-spot pool. A seat pose is public by construction
--      (an avatar is visibly sitting there and the camera is locked to the table); SpoonDefaultSpot,
--      DecoyAnchor, SeekerSpawn and HiderSpawn stay in `secretNames` and are not touched. The
--      narrowness is structural: `SeatSpec` is a four-field struct, so there is no map node in scope,
--      and `start` builds the payload FIELD BY FIELD rather than copying the incoming struct, so an
--      extra key a careless caller added cannot ride along. cardtable.spec asserts the key set exactly.
--   9. `debugState` IS A TEST SEAM. It hands the spec the engine state so it can hash it. It is never
--      called in production and never published.
local Engine = require("../engine/Engine")
local Pool = require("../engine/Pool")
local Types = require("../engine/Types")
local CardRouting = require("./CardRouting")
local IdleClock = require("./IdleClock")
local StallDetector = require("./StallDetector")

-- The shell's OWN removal cause. Narrowed on purpose: Engine.apply throws on "Completed", which it
-- owns. A type error here is cheaper than a thrown round.
export type ShellRemoveCause = "Disconnected" | "Benched"

export type Vec3 = { x: number, y: number, z: number }
-- EXACTLY these three fields and no others. Plan 04-14's CardService builds one of these per seat from
-- `mapSpec.cardTable.seats`; it must construct the struct field by field and must NEVER pass a map node
-- or a table it did not build.
export type SeatSpec = { playerId: Types.PlayerId, position: Vec3, look: Vec3 }

export type Deps = {
	publisher: CardRouting.Publisher,
	nowDeci: () -> number,
	rng: any, -- an Rng from src/server/engine/Rng.luau; seeded by the adapter
	-- Values, never config modules (guard R6). The adapter reads CardPool / Config.Card.
	extraRanks: number, -- CardPool.EXTRA_RANKS
	jokers: number, -- CardPool.JOKERS
	jokerMode: Types.JokerMode, -- CardPool.JOKER_MODE
	-- INJECTED AS OBJECTS, not as numbers: they arrive already carrying their converted numbers (plan
	-- 04-14 builds them), which keeps this file free of the seconds-to-deciseconds question, and gives
	-- the spec a handle on the very objects the shell uses.
	idle: IdleClock.IdleClock,
	stall: StallDetector.StallDetector,
	-- Two-clock rule: the core never reads a wall clock and never feeds a published value back. The
	-- adapter turns a remaining-deci count into a Unix deadline with GetServerTimeNow; DISPLAY ONLY.
	unixDeadlineFor: (remainingDeci: number) -> number,
	-- Phase 5 owns the hunt. Phase 4's implementation logs, releases the avatar and restores controls.
	onCompleted: (seat: Types.SeatId, playerId: Types.PlayerId, rank: Types.Rank) -> (),
	onSeatRemoved: (seat: Types.SeatId, playerId: Types.PlayerId, cause: Types.RemoveCause) -> (),
	onTelemetry: (name: string, data: { [string]: number }) -> (),
}

export type CardTable = {
	-- `seats` is ALREADY IN SEAT ORDER: index 1 is the dealer (CARD-05). Builds the round, assigns
	-- copies once, publishes RoundStart to the seated and one private Sync per seat.
	start: (self: CardTable, seats: { SeatSpec }) -> (),
	-- The gateway's dispatch target. `payload` is the CLEAN copy Gateway produced.
	onIntent: (self: CardTable, userId: number, intentName: string, payload: unknown) -> (),
	-- A gateway-level rejection never reached this file, so the client's seq was never acked. The raw
	-- payload is the client's own, UNVALIDATED: only a `seq` that is a finite integer in the manifest's
	-- range is read from it, and only to raise this user's ack so the Sync resolves the rejected entry
	-- cumulatively (WR-04). `push` is the caller's throttle verdict: false records the ack but sends
	-- nothing, so a rejection flood is not amplified into outbound Syncs.
	onGatewayReject: (
		self: CardTable,
		userId: number,
		intentName: unknown,
		code: string,
		rawPayload: unknown,
		push: boolean
	) -> (),
	-- The 10 Hz sweep. Drains IdleClock and StallDetector commands, applies and bookkeeps each OUTSIDE
	-- any other apply, then publishes (rule 6).
	tick: (self: CardTable) -> (),
	-- A leaver. Routes through the ONE generic removal with cause "Disconnected" (rule 8).
	removePlayer: (self: CardTable, userId: number) -> (),
	seatOf: (self: CardTable, userId: number) -> Types.SeatId?,
	isLive: (self: CardTable) -> boolean,
	-- Test seam only: the engine state, so cardtable.spec can hash it. Never called in production.
	debugState: (self: CardTable) -> Types.State,
}

-- What a seat's owner receives, and ONLY its owner (toPlayer). `seat` is 0 for a user who has no seat
-- (a stray tap, or a player already removed): the shape is identical so a pending queue still resolves.
export type SyncPayload = {
	ackSeq: number,
	seat: number,
	hand: { CardRouting.FaceRecord },
	inbox: number,
	downstream: number,
	idleDeadlineUnix: number?,
}

export type RoundStartSeat = { seat: number, playerId: number, position: Vec3, look: Vec3 }
export type RoundStartPayload = { seats: { RoundStartSeat }, jokerMode: Types.JokerMode, ranks: number }

type Step = () -> ()

-- One sweep's working set. `pending` is what goes on the wire, in order; `after` is the Phase 5 sinks,
-- fired once everything is published so a throwing sink cannot swallow a message a client awaits.
type Ctx = { now: number, pending: { Step }, after: { Step } }

type ApplyOpts = {
	-- true only for a player's own Draw/Pass: an auto-pass is not a real action, so it must not reset
	-- strikes (D-17).
	realAction: boolean,
	-- the player's own seq, echoed as ackSeq; nil for a server-originated command.
	ackSeq: number?,
	-- whether the actor gets a Sync. A removed seat does not: the player is gone or already told.
	syncActor: boolean,
}

local function new(deps: Deps): CardTable
	local state: Types.State? = nil
	local copyOf: { number } = {}
	-- userId -> seat, only while the seat is live. The generic removal deletes the entry.
	local rosterSeat: { [number]: Types.SeatId } = {}
	-- Last ackSeq each user sent, so a server-originated Sync carries the last known value.
	local lastAck: { [number]: number } = {}
	-- Per-seat signature of what its owner was last shown, so a Sync goes only to seats that changed.
	local lastSig: { [Types.SeatId]: string } = {}

	local function roundState(): Types.State
		if state == nil then
			error("CardTable: the round has not been started", 0)
		end
		return state
	end

	local function contained(fn: () -> ()): (boolean, unknown)
		local caught: unknown = nil
		local ok = xpcall(fn, function(e: unknown): ()
			caught = e
		end)
		return ok, caught
	end

	-- Telemetry carries counters only; a name may carry a kind or code. onTelemetry itself is guarded:
	-- a throwing sink must not become a second failure inside the failure handler.
	local function report(name: string, data: { [string]: number })
		contained(function()
			deps.onTelemetry(name, data)
		end)
	end

	local function userIdOfSeat(seat: Types.SeatId): number
		return roundState().seats[seat].playerId
	end

	local function viewOf(st: Types.State): IdleClock.View
		local view: IdleClock.View = {}
		for id, seat in st.seats do
			view[id] = { live = seat.live, handSize = #seat.hand, inboxSize = #seat.inbox }
		end
		return view
	end

	local function downstreamOf(st: Types.State, seatId: Types.SeatId): number
		local seat = st.seats[seatId]
		if not seat.live then
			return 0
		end
		local nextSeat = st.seats[seat.next]
		return if nextSeat ~= nil then #nextSeat.inbox else 0
	end

	-- CARD-13: the pile depth of every seat, as COUNTS ONLY (never a card id or a rank). Built at apply
	-- time, from the live state, so a later command in the same sweep cannot change what this batch says.
	local function depthsPayload(st: Types.State): CardRouting.DepthsPayload
		local depths: { number } = {}
		for id = 1, st.seatCount do
			local seat = st.seats[id]
			depths[id] = if seat ~= nil and seat.live then #seat.inbox else 0
		end
		return { depths = depths }
	end

	-- What the seat's owner was last shown. Hand ORDER is part of it (arrival order is displayed).
	local function signatureOf(st: Types.State, seatId: Types.SeatId): string
		local seat = st.seats[seatId]
		return `{table.concat(seat.hand, ",")}|{#seat.inbox}|{downstreamOf(st, seatId)}`
	end

	local function syncFor(seatId: Types.SeatId, ackSeq: number, now: number): SyncPayload
		local st = roundState()
		local seat = st.seats[seatId]
		local hand: { CardRouting.FaceRecord } = {}
		for _, cardId in seat.hand do
			table.insert(hand, { cardId = cardId, rank = st.rankOf[cardId], copy = copyOf[cardId] })
		end
		local payload: SyncPayload = {
			ackSeq = ackSeq,
			seat = seatId,
			hand = hand,
			inbox = #seat.inbox,
			downstream = downstreamOf(st, seatId),
			idleDeadlineUnix = nil,
		}
		local deadline = deps.idle:deadlineDeci(seatId)
		if deadline ~= nil then
			payload.idleDeadlineUnix = deps.unixDeadlineFor(math.max(0, deadline - now))
		end
		lastSig[seatId] = signatureOf(st, seatId)
		return payload
	end

	-- A Sync for a user who owns no live seat. Same shape, seat 0.
	local function seatlessSync(ackSeq: number): SyncPayload
		return { ackSeq = ackSeq, seat = 0, hand = {}, inbox = 0, downstream = 0, idleDeadlineUnix = nil }
	end

	local function queueSync(ctx: Ctx, userId: number, payload: SyncPayload)
		table.insert(ctx.pending, function()
			deps.publisher.toPlayer(userId, "Sync", payload)
		end)
	end

	local function queueNotice(ctx: Ctx, userId: number, notice: CardRouting.Notice)
		table.insert(ctx.pending, function()
			deps.publisher.toPlayer(userId, "Notice", notice)
		end)
	end

	local function hasProgress(events: { Types.Event }): boolean
		for _, event in events do
			if event.kind == "Completed" or event.kind == "SeatRemoved" then
				return true
			end
		end
		return false
	end

	-- THE ONE apply -> bookkeep -> queue path. Everything is queued, nothing is published: the caller
	-- publishes after every command of the sweep is done (rule 6).
	local function runApply(ctx: Ctx, intent: Types.Intent, opts: ApplyOpts): Types.ApplyResult
		local st = roundState()
		local seatId = intent.seat
		local actorUserId = if st.seats[seatId] ~= nil then st.seats[seatId].playerId else 0

		-- Synchronous, nothing else between the call and its return.
		local result = Engine.apply(st, intent)

		-- Bookkeeping, complete before anything is queued for publication. A failure here is contained
		-- so the already-applied batch is still published rather than dropped.
		local bookOk = contained(function()
			deps.idle:sync(viewOf(st), ctx.now, if result.ok and opts.realAction then seatId else nil)
			if result.ok then
				if st.liveCount >= 1 then
					deps.stall:noteApply(st.liveCount, ctx.now)
				end
				if hasProgress(result.events) then
					deps.stall:noteProgress(ctx.now)
				end
			end
		end)
		if not bookOk then
			report("bookkeeping_failed", { seat = seatId })
		end

		-- result.reject is NEVER published (D-12). It is a counter name for telemetry only.
		if not result.ok then
			report(`reject_{tostring(result.reject)}`, { seat = seatId })
		end

		-- The generic removal's roster effect. A removed seat's player no longer owns a seat.
		for _, event in result.events do
			if event.kind == "SeatRemoved" then
				rosterSeat[st.seats[event.seat].playerId] = nil
			end
		end

		-- 6. Publish order: the actor's Sync first, always; then the Table batch and its private
		-- notices through the ONE routing function; then a Sync to every other seat that changed.
		local ack = if opts.ackSeq ~= nil then opts.ackSeq else (lastAck[actorUserId] or 0)
		if opts.syncActor and actorUserId ~= 0 then
			queueSync(ctx, actorUserId, syncFor(seatId, ack, ctx.now))
		end
		local events = result.events
		if #events > 0 then
			table.insert(ctx.pending, function()
				CardRouting.publish(deps.publisher, events, copyOf, userIdOfSeat)
			end)
			local depths = depthsPayload(st)
			table.insert(ctx.pending, function()
				deps.publisher.toSeated("Depths", depths)
			end)
		end
		for id, seat in st.seats do
			if seat.live and id ~= seatId and lastSig[id] ~= signatureOf(st, id) then
				queueSync(ctx, seat.playerId, syncFor(id, lastAck[seat.playerId] or 0, ctx.now))
			end
		end

		-- 7. Sinks fire after publishing.
		for _, event in events do
			if event.kind == "Completed" then
				local seat, rank = event.seat, event.rank
				local playerId = st.seats[seat].playerId
				table.insert(ctx.after, function()
					local ok = contained(function()
						deps.onCompleted(seat, playerId, rank)
					end)
					if not ok then
						report("sink_failed_onCompleted", { seat = seat })
					end
				end)
			elseif event.kind == "SeatRemoved" then
				local seat = event.seat
				local cause: Types.RemoveCause = event.cause
				local playerId = st.seats[seat].playerId
				table.insert(ctx.after, function()
					local ok = contained(function()
						deps.onSeatRemoved(seat, playerId, cause)
					end)
					if not ok then
						report("sink_failed_onSeatRemoved", { seat = seat })
					end
				end)
			end
		end
		return result
	end

	-- Publishes the collected steps in order, each contained so one failing publish cannot drop the
	-- rest, then fires the sinks. Called with NO apply on the stack.
	local function flush(ctx: Ctx)
		for _, step in ctx.pending do
			local ok = contained(step)
			if not ok then
				report("publish_failed", {})
			end
		end
		for _, step in ctx.after do
			step()
		end
	end

	local function newCtx(): Ctx
		return { now = deps.nowDeci(), pending = {}, after = {} }
	end

	local function ackOf(userId: number, payload: unknown): number
		if type(payload) == "table" then
			local seq = (payload :: { [string]: unknown }).seq
			if type(seq) == "number" and seq == seq and seq >= 0 and seq % 1 == 0 then
				lastAck[userId] = seq
			end
		end
		return lastAck[userId] or 0
	end

	-- The manifest's bound on `seq` (Validate.integer max). Duplicated rather than required: this is a
	-- pure zone and a gateway-rejected payload was never validated.
	local MAX_SEQ = 2 ^ 31

	-- The `seq` of an UNVALIDATED client payload, or nil. Reads one key; trusts nothing else in it.
	local function rawSeqOf(payload: unknown): number?
		if type(payload) == "table" then
			local seq = (payload :: { [string]: unknown }).seq
			if type(seq) == "number" and seq == seq and seq >= 0 and seq <= MAX_SEQ and seq % 1 == 0 then
				return seq
			end
		end
		return nil
	end

	local function cardIdOf(payload: unknown): number?
		if type(payload) == "table" then
			local cardId = (payload :: { [string]: unknown }).cardId
			if type(cardId) == "number" then
				return cardId
			end
		end
		return nil
	end

	local shell: CardTable = {
		start = function(_self: CardTable, seats: { SeatSpec })
			local seatPlayerIds: { Types.PlayerId } = {}
			for i, spec in seats do
				seatPlayerIds[i] = spec.playerId
			end
			-- poolConfig takes PLAYERS IN THE ROUND, and `seats` is seated seekers: the hider does not
			-- play cards (amendment A3). The `+ 1` is exactly the off-by-one Pool.luau's header warns
			-- about; poolConfig is the only place the subtraction is written.
			local config = Pool.poolConfig(#seats + 1, deps.extraRanks, deps.jokers, deps.jokerMode)
			local st = Engine.newRound(config, seatPlayerIds, deps.rng)
			state = st
			copyOf = CardRouting.assignCopies(st.rankOf, config.ranks)
			table.clear(rosterSeat)
			table.clear(lastAck)
			table.clear(lastSig)
			local entries: { RoundStartSeat } = {}
			for i, spec in seats do
				rosterSeat[spec.playerId] = i
				-- FIELD BY FIELD from the incoming pose, never a copy of `spec`.
				entries[i] = {
					seat = i,
					playerId = spec.playerId,
					position = { x = spec.position.x, y = spec.position.y, z = spec.position.z },
					look = { x = spec.look.x, y = spec.look.y, z = spec.look.z },
				}
			end
			local rankCount = config.ranks
			local payload: RoundStartPayload = { seats = entries, jokerMode = config.jokerMode, ranks = rankCount }

			local ctx = newCtx()
			deps.idle:sync(viewOf(st), ctx.now, nil)
			-- D-20: anchor the stall detector's no-progress window to THIS round's clock. Its own anchor
			-- starts at 0 while the production clock is uptime-based, so without this the 45 s minimum-time
			-- gate is dead until the first Completed/SeatRemoved of the round (WR-02).
			deps.stall:noteProgress(ctx.now)
			table.insert(ctx.pending, function()
				deps.publisher.toSeated("RoundStart", payload)
			end)
			local depths = depthsPayload(st)
			table.insert(ctx.pending, function()
				deps.publisher.toSeated("Depths", depths)
			end)
			for i = 1, #seats do
				queueSync(ctx, seats[i].playerId, syncFor(i, 0, ctx.now))
			end
			flush(ctx)
		end,

		onIntent = function(_self: CardTable, userId: number, intentName: string, payload: unknown)
			local ctx = newCtx()
			local ack = ackOf(userId, payload)
			local answered = false
			local ok = contained(function()
				-- 1. The seat comes from the roster. Never from the payload (rule 7).
				local seat = rosterSeat[userId]
				if seat == nil then
					answered = true
					queueSync(ctx, userId, seatlessSync(ack))
					return
				end
				-- 2. The engine intent.
				local intent: Types.Intent
				if intentName == "Draw" then
					intent = { kind = "Draw", seat = seat }
				elseif intentName == "Pass" then
					-- A missing card id becomes 0, which the engine refuses as UnknownCard.
					intent = { kind = "Pass", seat = seat, cardId = cardIdOf(payload) or 0 }
				else
					answered = true
					report("unknown_intent", { seat = seat })
					queueSync(ctx, userId, syncFor(seat, ack, ctx.now))
					return
				end
				answered = true
				runApply(ctx, intent, { realAction = true, ackSeq = ack, syncActor = true })
			end)
			if not ok then
				report("intent_failed", {})
				if not answered then
					queueSync(ctx, userId, seatlessSync(ack))
				end
			end
			flush(ctx)
		end,

		onGatewayReject = function(
			_self: CardTable,
			userId: number,
			_intentName: unknown,
			_code: string,
			rawPayload: unknown,
			push: boolean
		)
			local seat = rosterSeat[userId]
			-- The rejected seq is never acked by the engine path, so the Sync below would sit BELOW it and
			-- the client's fold would keep the card gone until the 1.0 s watchdog. Acking it here is what
			-- makes this push reconcile. Raise-only: a lower hint must never lower the ack, because the
			-- client ignores a Sync whose ack is below what it already holds.
			local hint = rawSeqOf(rawPayload)
			if seat ~= nil and hint ~= nil and hint > (lastAck[userId] or 0) then
				lastAck[userId] = hint
			end
			if not push then
				return
			end
			local ctx = newCtx()
			local ack = lastAck[userId] or 0
			if seat ~= nil then
				queueSync(ctx, userId, syncFor(seat, ack, ctx.now))
			else
				queueSync(ctx, userId, seatlessSync(ack))
			end
			flush(ctx)
		end,

		tick = function(_self: CardTable)
			if state == nil then
				return
			end
			local ctx = newCtx()
			-- 1. Drain both sources into ONE ordered list.
			local commands: { { source: string, command: any } } = {}
			local idleOk = contained(function()
				for _, command in deps.idle:tick(ctx.now) do
					table.insert(commands, { source = "idle", command = command })
				end
			end)
			if not idleOk then
				report("idle_tick_failed", {})
			end
			local stallOk = contained(function()
				for _, command in deps.stall:tick(ctx.now) do
					table.insert(commands, { source = "stall", command = command })
				end
			end)
			if not stallOk then
				report("stall_tick_failed", {})
			end

			-- 2. Apply and bookkeep EVERY command. Nothing is published yet. Each command is contained
			-- on its own: one malformed or throwing command must not abort the rest of the sweep.
			local autoSeat: number? = nil
			local autoCard: number? = nil
			for _, entry in commands do
				local command = entry.command
				local kind = if type(command) == "table" then tostring(command.kind) else tostring(command)
				local sawAuto = false
				local ok = contained(function()
					local st = roundState()
					if kind == "StallCue" and entry.source == "stall" then
						table.insert(ctx.pending, function()
							deps.publisher.toSeated("Stall", { active = true })
						end)
					elseif kind == "StallClear" and entry.source == "stall" then
						table.insert(ctx.pending, function()
							deps.publisher.toSeated("Stall", { active = false })
						end)
					elseif entry.source == "idle" and (kind == "AutoPass" or kind == "Strike" or kind == "Bench") then
						local seatId = command.seat
						if type(seatId) ~= "number" or st.seats[seatId] == nil then
							error(`{kind} names no seat`, 0)
						end
						if kind == "AutoPass" then
							local cardId = IdleClock.pickUniform(st.seats[seatId].hand, deps.rng)
							local result = runApply(
								ctx,
								{ kind = "Pass", seat = seatId, cardId = cardId },
								{ realAction = false, ackSeq = nil, syncActor = true }
							)
							sawAuto = true
							autoSeat = seatId
							autoCard = if result.ok then cardId else nil
						elseif kind == "Strike" then
							local notice: CardRouting.Notice = {
								code = "Strike",
								strikes = command.strikes,
								owes = command.owes,
								cardId = if autoSeat == seatId then autoCard else nil,
							}
							local struckUserId = st.seats[seatId].playerId
							queueNotice(ctx, struckUserId, notice)
							-- IdleClock re-armed this seat's window, but a Draw-owed strike applies nothing, so
							-- no Sync carries the fresh deadline and the client would count down to a stale one
							-- (WR-01). A Pass-owed strike already queued one via its AutoPass.
							if autoSeat ~= seatId and st.seats[seatId].live then
								queueSync(ctx, struckUserId, syncFor(seatId, lastAck[struckUserId] or 0, ctx.now))
							end
						else
							-- The ONE generic removal (rule 8), with the shell's own narrowed cause.
							local cause: ShellRemoveCause = "Benched"
							runApply(
								ctx,
								{ kind = "Remove", seat = seatId, cause = cause },
								{ realAction = false, ackSeq = nil, syncActor = false }
							)
							queueNotice(ctx, st.seats[seatId].playerId, { code = "Benched" })
						end
					else
						error(`unknown command {kind}`, 0)
					end
				end)
				if not ok then
					report(`command_failed_{kind}`, {})
				end
				if not sawAuto then
					autoSeat = nil
					autoCard = nil
				end
			end

			-- 3. Publish what was collected. A command that threw has simply not contributed; the
			-- batches collected before and after it are STILL published, because a dropped batch leaves
			-- every client's pending queue unresolved, which is worse than the failure itself.
			flush(ctx)
		end,

		removePlayer = function(_self: CardTable, userId: number)
			local seat = rosterSeat[userId]
			if seat == nil then
				return
			end
			local ctx = newCtx()
			local ok = contained(function()
				local cause: ShellRemoveCause = "Disconnected"
				runApply(
					ctx,
					{ kind = "Remove", seat = seat, cause = cause },
					{ realAction = false, ackSeq = nil, syncActor = false }
				)
			end)
			if not ok then
				report("remove_failed", { seat = seat })
			end
			flush(ctx)
		end,

		seatOf = function(_self: CardTable, userId: number): Types.SeatId?
			return rosterSeat[userId]
		end,

		isLive = function(_self: CardTable): boolean
			return state ~= nil and state.liveCount > 0
		end,

		debugState = function(_self: CardTable): Types.State
			return roundState()
		end,
	}
	return shell
end

return { new = new }
