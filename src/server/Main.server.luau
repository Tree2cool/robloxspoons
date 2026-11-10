--!strict
-- The one server boot entry point. Wiring only: no gameplay logic lives here.
--
-- Order matters, and each position has a reason:
--   1. Persistence first, so a misconfigured session dies before touching anything. Its Refuse error is
--      deliberately NOT caught (T-1-10).
--   2. PlayerGate, so the player cap is live before anyone can join.
--   3. RoundDriver, the round lifecycle. Phase 1 only logs the end of a round; scoring is Phase 5.
--   4. MapLoader, loading the one configured default map.
--   5. CardService, after MapLoader because it needs the map's seat poses. It takes NetServer's
--      publisher, so it is assigned right after NetServer.start returns (see the build-order comment).
--   6. NetServer last: it is the only thing that accepts outside input, so it opens once the rest is up
--      (T-1-49).
local Players = game:GetService("Players")

local Gateway = require("./core/Gateway")
local CardService = require("./services/CardService")
local MapLoader = require("./services/MapLoader")
local NetServer = require("./services/NetServer")
local Persistence = require("./services/Persistence")
local PlayerGate = require("./services/PlayerGate")
local RoundDriver = require("./services/RoundDriver")

-- A configured default, NOT a per-map branch; Phase 7's MAP-04 rotation replaces this constant with a
-- rotation source.
local DEFAULT_MAP_ID = "GrayBox"

local selection = Persistence.select()
print(`[Spoons] persistence mode: {selection.mode}`)

PlayerGate.new()

local driver = RoundDriver.new(function(roundId, reason)
	print(`[Spoons] round {roundId} ended: {reason}`)
end)

local _, mapSpec = MapLoader.load(DEFAULT_MAP_ID)
print(`[Spoons] map loaded: {mapSpec.metadata.id}`)

-- One holder with a setter; the real phase machine is Phase 4/6 work.
local currentPhase: Gateway.RoundPhase = "Lobby"
local function getPhase(): Gateway.RoundPhase
	return currentPhase
end
local function setPhase(phase: Gateway.RoundPhase)
	currentPhase = phase
end

local cardService: CardService.CardService? = nil
local roundStarted = false

-- An intent with no handler errors, so a manifest entry can never be silently unroutable. Draw and Pass
-- both route to the card core.
local handlers: { [string]: (userId: number, payload: unknown) -> () } = {
	Ping = function(userId, payload)
		local nonce = (payload :: { nonce: number }).nonce
		print(`[Spoons] Ping from {userId} nonce={nonce}`)
	end,
	Draw = function(userId, payload)
		if cardService ~= nil then
			cardService:onIntent(userId, "Draw", payload)
		end
	end,
	Pass = function(userId, payload)
		if cardService ~= nil then
			cardService:onIntent(userId, "Pass", payload)
		end
	end,
}

-- Per-user reject log throttle (plan 04-07). Its clock is CardService.nowDeci: one clock expression in
-- the codebase, because two clock expressions is how two clocks disagree.
local rejectThrottle = CardService.newRejectThrottle()

-- Build order: NetServer first, with a seatedUserIds closure reading `cardService`, an upvalue assigned
-- below; then CardService with the publisher NetServer returns. A closure over an upvalue is clearer
-- than a two-phase constructor. The nil guard covers the window before assignment, which is real:
-- NetServer.start parents its remotes at the end of its own body.
local netServer = NetServer.start({
	getPhase = getPhase,
	dispatch = function(userId, intent, payload)
		local handler = handlers[intent]
		if handler == nil then
			error(`no handler registered for intent {intent}`)
		end
		handler(userId, payload)
	end,
	onReject = function(userId, intent, code, rawPayload)
		-- 01-CONTEXT.md D-22, reviewed in Phase 4 (see src/server/core/RejectThrottle.luau's header for
		-- the full record): the Gateway's check order is KEPT and a wrong-phase message charges no token.
		-- The real exposure was this warn firing once per rejection, which made a WrongPhase flood a
		-- log-spam and CPU vector. `streakOf` is reserved for Phase 8; this phase kicks nobody.
		local decision = rejectThrottle:note(userId, tostring(code), CardService.nowDeci())
		if decision.log then
			warn(`[Spoons] rejected {tostring(intent)} from {userId}: {code}`)
		end
		if decision.summary ~= nil then
			warn(`[Spoons] suppressed {decision.summary} further rejections from {userId} in the last window`)
		end
		-- CARD-14 resync: a gateway-level rejection never reaches the card core, so the client's seq was
		-- never acked. The card core acks the rejected seq (read from the raw payload) and pushes a Sync
		-- at that ack, which resolves the client's pending entry cumulatively. WR-04: the push is gated
		-- by the SAME per-user throttle as the log line, so a rate-limit flood is not amplified into
		-- one outbound Sync per message; a throttled rejection is resolved by the next Sync or, failing
		-- that, by plan 04-09's age watchdog, which stays the backstop.
		if cardService ~= nil then
			cardService:onGatewayReject(userId, intent, tostring(code), rawPayload, decision.log)
		end
	end,
	onError = function(userId, intent, err)
		warn(`[Spoons] handler error for {intent} from {userId}: {tostring(err)}`)
	end,
	seatedUserIds = function()
		if cardService ~= nil then
			return cardService:seatedUserIds()
		end
		return {}
	end,
})

cardService = CardService.new({
	publisher = netServer.publisher,
	setPhase = setPhase,
	-- Phase 4's completion sink. Phase 5 owns the hunt, the glint, the spoon claim and scoring; this
	-- stub exists so Phase 4 runs without it. CardService releases the avatar itself.
	onCompleted = function(seat, playerId, rank)
		print(`[Spoons] seat {seat} (player {playerId}) completed rank {rank}`)
	end,
	-- The DATA, not just the name. It was dropped until 2026-11-10, when `seat_hold_deferred` told us a
	-- hold had deferred but not WHOSE, and a Studio session went on guessing which of three players it
	-- meant. Every telemetry payload in this phase is a flat table of numbers, so this stays one line
	-- per event. Sorted, so two runs are diffable.
	onTelemetry = function(name, data)
		local parts: { string } = {}
		for key, value in data do
			table.insert(parts, `{key}={value}`)
		end
		table.sort(parts)
		print(`[Spoons] telemetry {name} {table.concat(parts, " ")}`)
	end,
	seatPoses = function()
		return mapSpec.cardTable.seats
	end,
})

-- RoundStub: Phase 6 replaces this trigger. Start one card round once the roster reaches three.
local function tryStartRound()
	if cardService ~= nil and #Players:GetPlayers() >= 3 and not roundStarted then
		roundStarted = cardService:startRound()
	end
end
Players.PlayerAdded:Connect(tryStartRound)
tryStartRound()

Players.PlayerRemoving:Connect(function(player: Player)
	rejectThrottle:forget(player.UserId)
	if cardService ~= nil then
		cardService:removePlayer(player.UserId)
	end
end)

print(`[Spoons] server ready (round driver: {driver ~= nil})`)
