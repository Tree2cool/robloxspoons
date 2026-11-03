--!strict
-- NetServer (FOUND-04): the single Roblox entry point for client input. One envelope RemoteEvent, one
-- server-side connection, everything routed through the pure Gateway. Deliberately thin: all behaviour
-- and every test live in core/Gateway.
--
-- The actor is the Player the platform hands us. A seat, a target or a hand index is never read out of the
-- payload and a client-supplied user id is never trusted (CLAUDE.md rule 7).
--
-- Not used on purpose: request/response remotes (no gateway path), unreliable remotes for gameplay (they
-- can drop), reliance on handler completion order, buffering of rejected traffic (the bucket drops it).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bucket = require("../core/Bucket")
local Gateway = require("../core/Gateway")
-- Shared modules are fetched by absolute DataModel path: src/server and src/shared are separate Rojo
-- mounts, so a relative require would resolve on disk and fail in Studio (guard rule R6).
local Manifest = require(ReplicatedStorage.Shared.Net.Manifest)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)

export type Deps = {
	getPhase: () -> Gateway.RoundPhase,
	dispatch: (userId: number, intent: string, payload: unknown) -> (),
	onReject: (userId: number, intent: unknown, code: Gateway.Code) -> (),
	onError: (userId: number, intent: string, err: unknown) -> (),
}

export type NetServer = {
	gateway: Gateway.Gateway,
	remote: RemoteEvent,
	destroy: (self: NetServer) -> (),
}

local NetServer = {}

function NetServer.start(deps: Deps): NetServer
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Intent"

	local bucket = Bucket.new({
		clock = {
			now = function(): number
				return os.clock()
			end,
		},
	})

	local gateway = Gateway.new({
		manifest = Manifest,
		bucket = bucket,
		rateFor = RateLimits.forIntent,
		getPhase = deps.getPhase,
		dispatch = deps.dispatch,
		onReject = deps.onReject,
		onError = deps.onError,
	})

	-- Connect BEFORE parenting. Messages that arrive while no handler is connected sit in a bounded queue
	-- and are then dropped with an error, so the connection has to exist before clients can see the remote.
	local connection = remote.OnServerEvent:Connect(function(player: Player, intentName: unknown, payload: unknown)
		gateway:handle(player.UserId, intentName, payload)
	end)

	-- Frees per-player bucket state; without this it leaks for the life of the server.
	local leaving = Players.PlayerRemoving:Connect(function(player: Player)
		gateway:forget(player.UserId)
	end)

	remote.Parent = ReplicatedStorage

	local server: NetServer
	server = {
		gateway = gateway,
		remote = remote,
		destroy = function(_self: NetServer)
			connection:Disconnect()
			leaving:Disconnect()
			remote:Destroy()
		end,
	}
	return server
end

return NetServer
