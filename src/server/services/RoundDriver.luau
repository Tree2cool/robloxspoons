--!strict
-- Roblox adapter for the pure RoundLifecycle (SCORE-06). Deliberately thin: it only binds the real clock and
-- the real scheduler, then hands them to the core. All round logic and every test live in core/RoundLifecycle.
--
-- Two clocks, never mixed in one calculation:
--   * os.clock()          the scheduling and scoring clock. Sub-microsecond, unaffected by system clock
--                         adjustments, arbitrary baseline - which is fine because only DIFFERENCES matter
--                         (research verification row V-30). It is what the core sees as nowDeci().
--   * GetServerTimeNow()  Unix seconds, smoothed and monotonic: what a client countdown needs. It is used
--                         ONLY to publish a deadline outward and is never fed back into the core.
-- Their equivalence on a live server is untested (assumption A12), hence the strict separation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RoundLifecycle = require("../core/RoundLifecycle")
-- Shared config is fetched by absolute DataModel path, not a relative require: src/server and src/shared are
-- separate Rojo mounts, so a relative path would cross a mount boundary (check-guards rule R6).
local Config = require(ReplicatedStorage.Shared.Config.Round)

local RoundDriver = {}

export type Driver = {
	lifecycle: RoundLifecycle.Lifecycle,
	-- Starts a round at the configured cap and returns its id.
	beginRound: () -> number,
	-- Unix-seconds deadline for a client countdown, fixed when the round began. nil for any other round id.
	deadlineUnix: (roundId: number) -> number?,
}

local function makeScheduler(): RoundLifecycle.Scheduler
	return {
		nowDeci = function(): number
			return math.floor(os.clock() * Config.DECISECONDS_PER_SECOND)
		end,
		delay = function(seconds: number, fn: () -> ()): () -> ()
			local thread = task.delay(seconds, fn)
			return function()
				task.cancel(thread)
			end
		end,
	}
end

function RoundDriver.new(onEnded: (roundId: number, reason: RoundLifecycle.Reason) -> ()): Driver
	local scheduler = makeScheduler()
	local lifecycle = RoundLifecycle.new({ scheduler = scheduler, onEnded = onEnded })

	local publishedRoundId: number? = nil
	local publishedUnix = 0

	local function beginRound(): number
		local roundId = lifecycle:begin(Config.ROUND_CAP_SECONDS)
		local deadlineDeci = lifecycle:deadlineDeci(roundId) :: number
		local remainingSeconds = (deadlineDeci - scheduler.nowDeci()) / Config.DECISECONDS_PER_SECOND
		publishedRoundId = roundId
		publishedUnix = Workspace:GetServerTimeNow() + remainingSeconds
		return roundId
	end

	local function deadlineUnix(roundId: number): number?
		if roundId == publishedRoundId then
			return publishedUnix
		end
		return nil
	end

	return {
		lifecycle = lifecycle,
		beginRound = beginRound,
		deadlineUnix = deadlineUnix,
	}
end

return RoundDriver
