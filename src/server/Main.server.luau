--!strict
-- The one server boot entry point. Wiring only: no gameplay logic lives here.
--
-- Order matters, and each position has a reason:
--   1. Persistence first, so a misconfigured session dies before touching anything. Its Refuse error is
--      deliberately NOT caught (T-1-10).
--   2. PlayerGate, so the player cap is live before anyone can join.
--   3. RoundDriver, the round lifecycle. Phase 1 only logs the end of a round; scoring is Phase 5.
--   4. MapLoader, loading the one configured default map.
--   5. NetServer last: it is the only thing that accepts outside input, so it opens once the rest is up
--      (T-1-49).
local Gateway = require("./core/Gateway")
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
local _ = setPhase

-- An intent with no handler errors, so a manifest entry can never be silently unroutable.
local handlers: { [string]: (userId: number, payload: unknown) -> () } = {
	Ping = function(userId, payload)
		local nonce = (payload :: { nonce: number }).nonce
		print(`[Spoons] Ping from {userId} nonce={nonce}`)
	end,
}

NetServer.start({
	getPhase = getPhase,
	dispatch = function(userId, intent, payload)
		local handler = handlers[intent]
		if handler == nil then
			error(`no handler registered for intent {intent}`)
		end
		handler(userId, payload)
	end,
	onReject = function(userId, intent, code)
		warn(`[Spoons] rejected {tostring(intent)} from {userId}: {code}`)
	end,
	onError = function(userId, intent, err)
		warn(`[Spoons] handler error for {intent} from {userId}: {tostring(err)}`)
	end,
})

print(`[Spoons] server ready (round driver: {driver ~= nil})`)
