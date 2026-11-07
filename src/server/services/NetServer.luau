--!strict
-- NetServer (FOUND-04): the single Roblox entry point for client input. One envelope RemoteEvent, one
-- server-side connection, everything routed through the pure Gateway. Deliberately thin: all behaviour
-- and every test live in core/Gateway.
--
-- The actor is the Player the platform hands us. A seat, a target or a hand index is never read out of the
-- payload and a client-supplied user id is never trusted (CLAUDE.md rule 7).
--
-- This file now owns TWO remotes: Intent (client to server) and Card (server to client, the card stream).
-- V-12 is verified: ordering is guaranteed per connection per direction, including across different
-- RemoteEvent instances, so a second remote costs no ordering guarantee. The Publisher lives here only
-- because guard R4 confines the server-to-client send calls to this file. Every decision about audience lives
-- in core/CardRouting and every test of it in tests/card/privacy.spec; this file supplies four one-line
-- effect closures and hands them to CardRouting.makePublisher, so it assembles and decides nothing.
--
-- Not used on purpose: request/response remotes (no gateway path), unreliable remotes for gameplay (they
-- can drop), reliance on handler completion order, buffering of rejected traffic (the bucket drops it).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bucket = require("../core/Bucket")
local CardRouting = require("../core/CardRouting")
local Gateway = require("../core/Gateway")
-- Shared modules are fetched by absolute DataModel path: src/server and src/shared are separate Rojo
-- mounts, so a relative require would resolve on disk and fail in Studio (guard rule R6).
local Manifest = require(ReplicatedStorage.Shared.Net.Manifest)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)

export type Deps = {
	getPhase: () -> Gateway.RoundPhase,
	dispatch: (userId: number, intent: string, payload: unknown) -> (),
	-- `rawPayload` is the client's UNVALIDATED payload for the message being rejected (nil when the
	-- rejection is not tied to one). Only a consumer that validates it itself may read it (WR-04).
	onReject: (userId: number, intent: unknown, code: Gateway.Code, rawPayload: unknown) -> (),
	onError: (userId: number, intent: string, err: unknown) -> (),
	-- Which userIds are currently seated, so toSeated has an audience. Supplied by CardService from the
	-- CardTable roster; an empty list means "no round" and toSeated is then a no-op, not an error.
	seatedUserIds: () -> { number },
}

export type NetServer = {
	gateway: Gateway.Gateway,
	remote: RemoteEvent,
	cardRemote: RemoteEvent,
	publisher: CardRouting.Publisher,
	destroy: (self: NetServer) -> (),
}

local NetServer = {}

function NetServer.start(deps: Deps): NetServer
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Intent"
	local cardRemote = Instance.new("RemoteEvent")
	cardRemote.Name = "Card"

	-- userId -> Player, so the pure routing layer can name a user and this file can find the Instance.
	local roster: { [number]: Player? } = {}
	for _, player in Players:GetPlayers() do
		roster[player.UserId] = player
	end
	local joining = Players.PlayerAdded:Connect(function(player: Player)
		roster[player.UserId] = player
	end)

	local bucket = Bucket.new({
		clock = {
			now = function(): number
				return os.clock()
			end,
		},
	})

	-- The payload of the message `gateway:handle` is currently working on. Gateway.onReject has no
	-- payload parameter and Gateway.luau is frozen, so it is carried here. It is set and cleared around
	-- the one synchronous handle call; the card dispatch path never yields.
	local inFlightPayload: unknown = nil

	local gateway = Gateway.new({
		manifest = Manifest,
		bucket = bucket,
		rateFor = RateLimits.forIntent,
		getPhase = deps.getPhase,
		dispatch = deps.dispatch,
		onReject = function(userId: number, intent: unknown, code: Gateway.Code)
			deps.onReject(userId, intent, code, inFlightPayload)
		end,
		onError = deps.onError,
	})

	-- Connect BEFORE parenting. Messages that arrive while no handler is connected sit in a bounded queue
	-- and are then dropped with an error, so the connection has to exist before clients can see the remote.
	local connection = remote.OnServerEvent:Connect(function(player: Player, intentName: unknown, payload: unknown)
		inFlightPayload = payload
		gateway:handle(player.UserId, intentName, payload)
		inFlightPayload = nil
	end)

	-- Frees per-player bucket state; without this it leaks for the life of the server.
	local leaving = Players.PlayerRemoving:Connect(function(player: Player)
		gateway:forget(player.UserId)
		roster[player.UserId] = nil
	end)

	local publisher = CardRouting.makePublisher({
		fireToPlayer = function(userId, kind, payload)
			local player = roster[userId]
			-- They left between the routing decision and the send. Ordinary, not an error.
			if player == nil then
				return
			end
			cardRemote:FireClient(player, kind, payload)
		end,
		fireToMany = function(userIds, kind, payload)
			for _, userId in userIds do
				local player = roster[userId]
				if player ~= nil then
					cardRemote:FireClient(player, kind, payload)
				end
			end
		end,
		fireToAll = function(kind, payload)
			cardRemote:FireAllClients(kind, payload)
		end,
		seatedUserIds = deps.seatedUserIds,
	})

	-- Parent only after every connection above exists.
	cardRemote.Parent = ReplicatedStorage
	remote.Parent = ReplicatedStorage

	local server: NetServer
	server = {
		gateway = gateway,
		remote = remote,
		cardRemote = cardRemote,
		publisher = publisher,
		destroy = function(_self: NetServer)
			connection:Disconnect()
			leaving:Disconnect()
			joining:Disconnect()
			remote:Destroy()
			cardRemote:Destroy()
		end,
	}
	return server
end

return NetServer
