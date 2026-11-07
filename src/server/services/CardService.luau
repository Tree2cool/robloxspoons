--!strict
-- Roblox adapter for the live card table (CARD-02, CARD-13, CARD-14, CARD-16). Deliberately thin: it
-- reads the clocks and the shared config, builds the two pure cores, and hands everything to
-- core/CardTable. Every behaviour lives in a pure core with its own tests, because every place this
-- phase is tempted to add logic to the Roblox-touching layer is a place a test can no longer reach it.
-- (This file names game:GetService, so Lune cannot load it. Specs reach it by comment-stripped source
-- scan and by testing the pure pieces it wires; that the wiring behaves in a live server is manual
-- check M-17.)
--
-- Two clocks, never mixed in one calculation (the RoundDriver.luau discipline, repeated because it is
-- easy to lose):
--   * os.clock()          the scheduling clock. Floored to integer deciseconds and handed to the pure
--                         cores as `nowDeci`. Monotonic within a server, meaningless across.
--   * GetServerTimeNow()  Unix seconds, smoothed and monotonic: what a client countdown needs. Used ONLY
--                         to publish a deadline outward (D-16) and NEVER fed back into a core.
--
-- THE ONE CALL SITE of the seconds-to-deciseconds conversion (CLAUDE.md rule 5) is AUTO_PASS_DECI below.
-- The ARITHMETIC lives in the pure core/CardTiming.luau, because this file cannot be loaded by Lune: an
-- inline expression here would be testable by nothing, and a text grep for it is satisfiable by a
-- comment. Arithmetic there, single call here; tests/card/deci_lock.spec.luau pins both.
--
-- Every config value is passed into the cores as a VALUE: a pure core cannot require shared config (R6).
-- The EngineConfig is built by Pool.poolConfig INSIDE CardTable, never by inline subtraction here.
-- The Rng is seeded from a mixed, non-sequential source (ASVS V6; see the seed comment below).
-- The 10 Hz sweep is ONE Heartbeat accumulator; there are no per-seat timers (rule 6: the pure tick
-- returns commands and the core applies them).
-- startRound / endRound are the RoundStub: Phase 6 replaces them. They exist so Phase 4 runs end to end
-- with Phases 5 and 6 absent.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CardRouting = require("../core/CardRouting")
local CardSeatHold = require("../core/CardSeatHold")
local CardTable = require("../core/CardTable")
local CardTiming = require("../core/CardTiming")
local Gateway = require("../core/Gateway")
local IdleClock = require("../core/IdleClock")
local RejectThrottle = require("../core/RejectThrottle")
local StallDetector = require("../core/StallDetector")
local Rng = require("../engine/Rng")
local Types = require("../engine/Types")
-- Shared config by absolute DataModel path: src/server and src/shared are separate Rojo mounts, so a
-- relative require would resolve on disk and fail in Studio (guard rule R6).
local CardConfig = require(ReplicatedStorage.Shared.Config.Card)
local CardPool = require(ReplicatedStorage.Shared.Config.CardPool)
local Round = require(ReplicatedStorage.Shared.Config.Round)

-- THE ONE CALL SITE OF THE CONVERSION. D-13: 8.0 s is the ceiling itself and the owner chose to sit
-- exactly at it, BECAUSE V-35 (whether the bot reaction-time model represents humans) is open. Do not
-- describe it as validated.
-- Honest consequence: nowDeci = floor(10 * clock), so an arming at real time c stores floor(10c) + D and
-- the deadline is first observable at elapsed (D - frac(10c)) / 10, which for D = 80 lies in [7.9, 8.0].
-- Flooring is ONE-SIDED-SHORT and can never lengthen the window; the 10 Hz sweep adds up to +0.1 s, so
-- the realised maximum is about 8.1 s against CARD-16's "must not exceed 8.0 s". Plan 04-20 puts that
-- gap to the owner; passing 7.9 here would close it and is NOT this plan's decision.
local AUTO_PASS_DECI = CardTiming.autoPassDeci(CardPool.AUTO_PASS_MAX_SECONDS, Round.DECISECONDS_PER_SECOND)
assert(
	AUTO_PASS_DECI <= CardPool.AUTO_PASS_MAX_SECONDS * Round.DECISECONDS_PER_SECOND,
	"AUTO_PASS_DECI exceeds the locked ceiling"
)

-- The one clock expression (same form as RoundDriver.makeScheduler, so the two agree by construction).
-- Main.server.luau reads it from here rather than writing os.clock() a second time.
local function nowDeci(): number
	return math.floor(os.clock() * Round.DECISECONDS_PER_SECOND)
end

-- Published outward only (D-16). Never fed back into a core.
local function unixDeadlineFor(remainingDeci: number): number
	return Workspace:GetServerTimeNow() + remainingDeci / Round.DECISECONDS_PER_SECOND
end

-- A round's deal must not be guessable. Rng.luau's header documents that xorshift32 seeded with a small
-- integer yields a constant first output, and the simulator seeds with small sequential counters. So
-- mix two unrelated sources; NEVER a round counter.
local function freshSeed(): number
	return bit32.bxor(math.floor(os.clock() * 1e6) % 2147483647, DateTime.now().UnixTimestampMillis % 2147483647)
end

export type SeatPose = { position: CardTable.Vec3, look: CardTable.Vec3 }

export type Deps = {
	publisher: CardRouting.Publisher, -- from NetServer.start
	setPhase: (phase: Gateway.RoundPhase) -> (),
	onCompleted: (seat: number, playerId: number, rank: number) -> (),
	onTelemetry: (name: string, data: { [string]: number }) -> (),
	-- Index = seat position, from MapLoader's MapSpec.cardTable.seats (plain data, never a map node).
	seatPoses: () -> { SeatPose },
}

export type CardService = {
	-- RoundStub (Phase 6's to replace). 3+ players: the first in join order hides, the rest are seated
	-- seekers in join order. Sets the phase to "Round" and starts the CardTable.
	startRound: (self: CardService) -> boolean,
	endRound: (self: CardService) -> (),
	onIntent: (self: CardService, userId: number, intentName: string, payload: unknown) -> (),
	onGatewayReject: (
		self: CardService,
		userId: number,
		intentName: unknown,
		code: string,
		rawPayload: unknown,
		push: boolean
	) -> (),
	removePlayer: (self: CardService, userId: number) -> (),
	seatedUserIds: (self: CardService) -> { number },
	destroy: (self: CardService) -> (),
}

-- Builds the two pure cores. They are handed to CardTable as OBJECTS (its Deps takes `idle` and
-- `stall`, not loose numbers). AUTO_PASS_DECI reaches the game through exactly one path: the constant
-- above -> IdleClock.new -> CardTable. deci_lock asserts that over comment-stripped source.
local function buildCores(
	onTelemetry: (name: string, data: { [string]: number }) -> ()
): (IdleClock.IdleClock, StallDetector.StallDetector)
	local idle = IdleClock.new({
		autoPassDeci = AUTO_PASS_DECI,
		maxStrikes = CardConfig.MAX_STRIKES,
	})
	local stall = StallDetector.new({
		actionsPerSeat = CardConfig.STALL_ACTIONS_PER_SEAT,
		minDeci = CardConfig.STALL_MIN_SECONDS * Round.DECISECONDS_PER_SECOND,
		cueDeci = CardConfig.STALL_CUE_SECONDS * Round.DECISECONDS_PER_SECOND,
		repeatDeci = CardConfig.STALL_REPEAT_SECONDS * Round.DECISECONDS_PER_SECOND,
		onTelemetry = onTelemetry,
	})
	return idle, stall
end

local CardService = {}

CardService.nowDeci = nowDeci

-- The reject throttle's values, read here so Main.server.luau need not fetch shared config.
function CardService.newRejectThrottle(): RejectThrottle.RejectThrottle
	return RejectThrottle.new({
		logPerWindow = CardConfig.REJECT_LOG_PER_WINDOW,
		windowDeci = CardConfig.REJECT_WINDOW_SECONDS * Round.DECISECONDS_PER_SECOND,
	})
end

-- Avatar seat hold (plan 04-15). THE SERVER-SIDE HALF OF UX-02, written as an ATTEMPT.
-- This is the only layer where holding a seated avatar is even possible: the client-side hiding (plan
-- 04-11) is ergonomics, since a client re-enables its own controls at will. WHETHER THIS LAYER HOLDS
-- ANYTHING IS UNPROVEN until manual check M-11 passes (assumption A2). The trust-boundary assumption is
-- that a cheat client controls its own input but not the server-set humanoid properties; M-11 cells
-- b-d exist to test exactly that. The movement-mode setting used below is documented to disable the
-- default control scripts, which is NOT the same as refusing a Humanoid:Move call or a client position
-- write, so cells c and d are the sharp ones.
--   Mechanism (A2, unverified): Player.Dev*MovementMode = Scriptable, a zeroed humanoid, a PivotTo.
--   Rejected: anchoring the root part (fights the physics solver; jitter and sliding); a Humanoid
--   physics state change (undocumented under the Input Action System migration); a real seated state
--   on the map seats (they are plain Parts, so converting them is a Phase 6 map-contract change).
--   RECORDED NEXT ATTEMPT if M-11 fails: a seated state on a converted seat Part (Phase 6, not a hot
--   fix), then a server-side position check that returns a wandering seated avatar to its anchor.
-- Release is the first thing in the Completed path (D-30): capability back, then control, before the
-- flourish. Every effect tolerates a missing Player, Character or Humanoid; a player can leave between
-- the decision and the effect.
--
-- Restore targets are captured from StarterPlayer ONCE at boot, not hard-coded: the place's own default
-- is the right thing to restore, and capturing it means a later Studio change to StarterPlayer is
-- honoured instead of silently overridden.
local StarterPlayer = game:GetService("StarterPlayer")
local RESTORE_COMPUTER_MODE = StarterPlayer.DevComputerMovementMode
local RESTORE_TOUCH_MODE = StarterPlayer.DevTouchMovementMode
local RESTORE_WALK_SPEED = StarterPlayer.CharacterWalkSpeed
local RESTORE_JUMP_HEIGHT = StarterPlayer.CharacterJumpHeight
local RESTORE_JUMP_POWER = StarterPlayer.CharacterJumpPower

local function humanoidOf(playerId: number): Humanoid?
	local player = Players:GetPlayerByUserId(playerId)
	local character = if player ~= nil then player.Character else nil
	if character == nil then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function makeSeatHold(onTelemetry: (name: string, data: { [string]: number }) -> ()): CardSeatHold.CardSeatHold
	return CardSeatHold.new({
		setMovementScriptable = function(playerId: number, scriptable: boolean)
			local player = Players:GetPlayerByUserId(playerId)
			if player == nil then
				return
			end
			-- Server only: these properties are documented as settable only from a server Script.
			if scriptable then
				player.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
				player.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable
			else
				player.DevComputerMovementMode = RESTORE_COMPUTER_MODE
				player.DevTouchMovementMode = RESTORE_TOUCH_MODE
			end
		end,
		freezeHumanoid = function(playerId: number, frozen: boolean)
			local humanoid = humanoidOf(playerId)
			if humanoid == nil then
				return
			end
			-- UseJumpPower decides which jump property applies; set both and let the unused one be inert.
			humanoid.WalkSpeed = if frozen then 0 else RESTORE_WALK_SPEED
			humanoid.JumpHeight = if frozen then 0 else RESTORE_JUMP_HEIGHT
			humanoid.JumpPower = if frozen then 0 else RESTORE_JUMP_POWER
		end,
		pivotTo = function(playerId: number, pose: CardSeatHold.Pose): boolean
			local player = Players:GetPlayerByUserId(playerId)
			local character = if player ~= nil then player.Character else nil
			if character == nil or character.PrimaryPart == nil then
				return false
			end
			local position = Vector3.new(pose.position.x, pose.position.y, pose.position.z)
			local look = Vector3.new(pose.look.x, pose.look.y, pose.look.z)
			character:PivotTo(
				if look.Magnitude > 0 then CFrame.lookAt(position, position + look) else CFrame.new(position)
			)
			return true
		end,
		onTelemetry = onTelemetry,
	})
end

function CardService.new(deps: Deps): CardService
	local seatHold = makeSeatHold(deps.onTelemetry)
	local connections: { RBXScriptConnection } = {}

	local function holdAvatar(playerId: number, pose: SeatPose)
		seatHold:hold(playerId, pose)
	end
	-- One generic release for completion, bench and disconnect (idempotent in the core).
	local function releaseAvatar(playerId: number)
		seatHold:release(playerId)
	end

	-- A respawn hands back a fresh humanoid; the core re-applies the freeze only for a held player.
	local function watchCharacter(player: Player)
		table.insert(
			connections,
			player.CharacterAdded:Connect(function()
				seatHold:onCharacterAdded(player.UserId)
			end)
		)
	end
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchCharacter))
	-- Drops the entry with no effect: there is no avatar left to restore.
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			seatHold:forget(player.UserId)
		end)
	)
	local cardTable: CardTable.CardTable? = nil
	local sweepConnection: RBXScriptConnection? = nil
	-- Player ids currently seated, in seat order. NetServer.toSeated reads this as its audience.
	local seated: { number } = {}

	local function unseat(playerId: number)
		local index = table.find(seated, playerId)
		if index ~= nil then
			table.remove(seated, index)
		end
	end

	local function stopSweep()
		if sweepConnection ~= nil then
			sweepConnection:Disconnect()
			sweepConnection = nil
		end
	end

	-- WR-03: everything startRound does once it has decided to start is ATOMIC. A throw between
	-- assigning `cardTable` and the sweep connecting used to leave `cardTable ~= nil` (every retry
	-- returned false), the avatars held in Scriptable mode and no sweep, so nothing could ever recover.
	-- Roll back to exactly the pre-call state: sweep off, holds released, audience empty, no table, Lobby.
	-- If the table had already announced the round, tell the clients it is over, or their place and
	-- hidden controls would leak (the same hazard endRound's RoundEnd exists for).
	local function abortStart(announced: boolean)
		stopSweep()
		pcall(function()
			seatHold:releaseAll()
		end)
		if announced then
			pcall(function()
				deps.publisher.toSeated("RoundEnd", {})
			end)
		end
		table.clear(seated)
		cardTable = nil
		pcall(function()
			deps.setPhase("Lobby")
		end)
		deps.onTelemetry("start_round_failed", {})
	end

	local function startRound(_self: CardService): boolean
		if cardTable ~= nil then
			return false
		end
		local players = Players:GetPlayers()
		if #players < 3 then
			return false
		end
		local poses = deps.seatPoses()
		-- Seekers only: the first player hides and plays no cards (amendment A3).
		if #poses < #players - 1 then
			return false
		end

		local announced = false
		local started = pcall(function()
			local idle, stall = buildCores(deps.onTelemetry)
			-- The config table widens its string literal to `string`; the engine takes the literal union.
			local jokerMode: Types.JokerMode = if CardPool.JOKER_MODE == "Blocker" then "Blocker" else "Wild"
			assert(CardPool.JOKER_MODE == jokerMode, "CardPool.JOKER_MODE is not a known joker mode")
			local table_ = CardTable.new({
				publisher = deps.publisher,
				nowDeci = nowDeci,
				rng = Rng.new(freshSeed()),
				extraRanks = CardPool.EXTRA_RANKS,
				jokers = CardPool.JOKERS,
				jokerMode = jokerMode,
				idle = idle,
				stall = stall,
				unixDeadlineFor = unixDeadlineFor,
				onCompleted = function(seat, playerId, rank)
					releaseAvatar(playerId)
					deps.onCompleted(seat, playerId, rank)
				end,
				onSeatRemoved = function(_seat, playerId, _cause)
					unseat(playerId)
					releaseAvatar(playerId)
				end,
				onTelemetry = deps.onTelemetry,
			})
			cardTable = table_

			-- Structs built field by field from plain pose data: no map node is ever in scope.
			local specs: { CardTable.SeatSpec } = {}
			table.clear(seated)
			for i = 2, #players do
				local pose = poses[i - 1]
				local spec: CardTable.SeatSpec = {
					playerId = players[i].UserId,
					position = { x = pose.position.x, y = pose.position.y, z = pose.position.z },
					look = { x = pose.look.x, y = pose.look.y, z = pose.look.z },
				}
				table.insert(specs, spec)
				table.insert(seated, spec.playerId)
				holdAvatar(spec.playerId, pose)
			end

			deps.setPhase("Round")
			table_:start(specs)
			announced = true

			-- ONE accumulator, subtract (do not reset) so the sweep does not drift. No per-seat timers.
			local interval = 1 / CardConfig.SWEEP_HZ
			local accumulator = 0
			sweepConnection = RunService.Heartbeat:Connect(function(dt: number)
				accumulator += dt
				if accumulator >= interval then
					accumulator -= interval
					table_:tick()
				end
			end)
		end)
		if not started then
			abortStart(announced)
			return false
		end
		return true
	end

	local function endRound(_self: CardService)
		stopSweep()
		for _, playerId in seated do
			releaseAvatar(playerId)
		end
		seatHold:releaseAll()
		-- UX-02 / D-29: the client restores its controls only on its own Completed, SeatRemoved or the next
		-- RoundStart, none of which an ended round sends. So tell every still-seated client, BEFORE `seated`
		-- is cleared (toSeated reads it). Contained: a failed publish must not stop the state reset.
		if cardTable ~= nil then
			local told = pcall(function()
				deps.publisher.toSeated("RoundEnd", {})
			end)
			if not told then
				deps.onTelemetry("round_end_publish_failed", {})
			end
		end
		table.clear(seated)
		cardTable = nil
		deps.setPhase("Lobby")
	end

	local function onIntent(_self: CardService, userId: number, intentName: string, payload: unknown)
		if cardTable ~= nil then
			cardTable:onIntent(userId, intentName, payload)
		end
	end

	local function onGatewayReject(
		_self: CardService,
		userId: number,
		intentName: unknown,
		code: string,
		rawPayload: unknown,
		push: boolean
	)
		if cardTable ~= nil then
			cardTable:onGatewayReject(userId, intentName, code, rawPayload, push)
		end
	end

	local function removePlayer(_self: CardService, userId: number)
		if cardTable ~= nil and cardTable:seatOf(userId) ~= nil then
			cardTable:removePlayer(userId)
		end
		unseat(userId)
		releaseAvatar(userId)
	end

	local function seatedUserIds(_self: CardService): { number }
		return table.clone(seated)
	end

	local function destroy(self: CardService)
		endRound(self)
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	return {
		startRound = startRound,
		endRound = endRound,
		onIntent = onIntent,
		onGatewayReject = onGatewayReject,
		removePlayer = removePlayer,
		seatedUserIds = seatedUserIds,
		destroy = destroy,
	}
end

return CardService
