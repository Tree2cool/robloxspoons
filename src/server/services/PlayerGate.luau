--!strict
-- PlayerGate (FOUND-08): the Roblox adapter in front of the pure Admission core.
--
-- Layering: (1) the place's Maximum Players setting on the Creator Dashboard is the hard cap
-- (Players.MaxPlayers is ReadOnly in script; MANUAL-CHECKS M-05); (2) this gate is defence in depth.
-- Reserved servers and teleports may not honour the place cap (assumption A7), which is precisely why
-- this check exists in code as well as in the place settings.
--
-- This module holds NO numeric limits. Both come from shared config, reached with an absolute service
-- path from `game`: a relative require from src/server into src/shared would resolve on disk and fail
-- in the DataModel (guard rule R6). Admission is inside the src/server mount, so it is relative.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Admission = require("../core/Admission")
local Limits = require(ReplicatedStorage.Shared.Config.Limits)

local FULL_MESSAGE = "This server is full. Please try joining again in a moment."
local UNAVAILABLE_MESSAGE = "This server could not accept you right now. Please try joining again."

export type PlayerGate = {
	destroy: (self: PlayerGate) -> (),
}

local PlayerGate = {}

-- Players already refused but not yet removed from the Players list. Kick is asynchronous, so a
-- refused player can still be counted by the next join; subtracting them stops one refusal from
-- turning into a second, wrongly refused legitimate player.
local function countAdmitted(refused: { [Player]: boolean }): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if not refused[player] then
			count += 1
		end
	end
	return count
end

function PlayerGate.new(): PlayerGate
	local refused: { [Player]: boolean } = {}

	local added = Players.PlayerAdded:Connect(function(player: Player)
		-- The joining player is already in the list, so the count BEFORE them is one less.
		local countBefore = countAdmitted(refused) - 1
		local decision = Admission.decide(countBefore, Limits.MAX_PLAYERS)
		if decision.admit then
			return
		end
		refused[player] = true
		if decision.reason == "ServerFull" then
			player:Kick(FULL_MESSAGE)
		else
			-- InvalidInput: the roster could not be trusted, so fail closed.
			player:Kick(UNAVAILABLE_MESSAGE)
		end
	end)

	local removing = Players.PlayerRemoving:Connect(function(player: Player)
		refused[player] = nil
	end)

	local self: PlayerGate = {
		destroy = function(_self: PlayerGate)
			added:Disconnect()
			removing:Disconnect()
		end,
	}
	return self
end

-- Nothing else in the codebase may decide that a match can start.
function PlayerGate.canStart(readyCount: number): boolean
	return Admission.canStartMatch(readyCount, Limits.MIN_PLAYERS_TO_START)
end

return PlayerGate
