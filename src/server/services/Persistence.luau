--!strict
-- Persistence adapter (FOUND-07, Phase 1 seam only): gathers the facts, asks the pure
-- PersistenceMode for a decision, and returns an in-memory store when Mock is selected.
--
-- SCOPE FENCE: there is no real DataStore work here, and ProfileStore is not vendored in Phase 1
-- (it arrives with the first phase that saves data, Phase 7). When the module is absent this reports
-- "NotReady" and selects Mock. The Mock store has the same method names as the real one will have
-- (StartSessionAsync, Reconcile, EndSession) so Phase 7 swaps the implementation, not the call sites.
--
-- The mechanism of isolation is a separate Roblox experience (D-13). The IsStudio refusal below is a
-- secondary tripwire behind it.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PersistenceMode = require("../core/PersistenceMode")
local Environments = require(ReplicatedStorage.Shared.Config.Environments)

export type Profile = {
	Data: { [string]: any },
	Reconcile: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
}

export type Store = {
	StartSessionAsync: (self: Store, profileKey: string) -> Profile?,
}

export type Selection = {
	mode: "Mock", -- the only mode that can be returned in Phase 1; Refuse and Real both error
	store: Store,
}

local Persistence = {}

local function copyTemplate(template: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {}
	for k, v in template do
		out[k] = if type(v) == "table" then copyTemplate(v) else v
	end
	return out
end

-- In-memory only. Nothing here is ever written anywhere, so a Mock session can never overwrite a
-- real profile: the failure mode this seam exists to prevent.
function Persistence.newMockStore(template: { [string]: any }?): Store
	local live: { [string]: boolean } = {}
	local store: Store
	store = {
		StartSessionAsync = function(_self: Store, profileKey: string): Profile?
			if live[profileKey] then
				return nil -- a second session on the same key is refused, as the real store will
			end
			live[profileKey] = true
			local profile: Profile
			profile = {
				Data = if template then copyTemplate(template) else {},
				Reconcile = function(_p: Profile) end,
				EndSession = function(_p: Profile)
					live[profileKey] = nil
				end,
			}
			return profile
		end,
	}
	return store
end

-- ProfileStore is not vendored yet. If it is ever present, read its DataStoreState; anything we
-- cannot positively read is "NotReady", which selects Mock.
local function readDataStoreState(): string
	local module = ServerScriptService:FindFirstChild("ProfileStore", true)
	if module == nil or not module:IsA("ModuleScript") then
		return "NotReady"
	end
	local ok, loaded = pcall(require, module)
	if not ok or type(loaded) ~= "table" then
		return "NotReady"
	end
	local state = (loaded :: any).DataStoreState
	if type(state) ~= "string" then
		return "NotReady"
	end
	return state
end

function Persistence.select(template: { [string]: any }?): Selection
	local mode = PersistenceMode.decide({
		dataStoreState = readDataStoreState(),
		isStudio = RunService:IsStudio(),
		gameId = game.GameId,
		productionUniverseId = Environments.PRODUCTION_UNIVERSE_ID,
	})

	if mode == "Refuse" then
		-- Loud and early: a Studio session aimed at production must not boot, let alone write.
		error(
			`Refusing real persistence: this is a Studio session and game.GameId matches the production universe id {Environments.PRODUCTION_UNIVERSE_ID}. Run against the dev experience instead; see MANUAL-CHECKS.md M-04.`
		)
	end

	if mode == "Real" then
		-- Reachable only if ProfileStore is vendored and reports Access. Real stores are Phase 7;
		-- failing here is correct, and falling back to defaults would risk overwriting a real profile.
		error("Real persistence is not implemented until Phase 7; refusing to continue rather than guess.")
	end

	return { mode = "Mock", store = Persistence.newMockStore(template) }
end

return Persistence
