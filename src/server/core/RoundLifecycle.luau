--!strict
-- Round FSM (SCORE-06). PURE ZONE: no Roblox API, no yields (CLAUDE.md rules 2, 6).
-- The server is the only clock and all times are integer deciseconds (CLAUDE.md rule 5).
--
-- Guarantees:
--   * onEnded fires exactly once per round, however many times endRound is called.
--   * A backstop callback registered by an earlier round can never end a later one. Two independent guards:
--     the backstop is cancelled when its round ends, AND it carries its round id and no-ops on mismatch.
--     The token guard works even when cancel does nothing.
--   * The deadline is EXCLUSIVE: a claim arriving on the deadline decisecond is outside the round.
--     Handlers must ask isOpen(roundId) before acting; isOpen routes an expired round to a Timeout end.
--   * State is marked ended BEFORE onEnded is invoked, so a re-entrant handler sees a closed round.
export type Reason = "AllSpoonsClaimed" | "Timeout" | "Aborted"
export type Scheduler = {
	nowDeci: () -> number,
	delay: (seconds: number, fn: () -> ()) -> () -> (),
}
export type Deps = {
	scheduler: Scheduler,
	onEnded: (roundId: number, reason: Reason) -> (),
}
export type Lifecycle = {
	begin: (self: Lifecycle, durationSeconds: number) -> number,
	isOpen: (self: Lifecycle, roundId: number) -> boolean,
	endRound: (self: Lifecycle, roundId: number, reason: Reason) -> boolean,
	deadlineDeci: (self: Lifecycle, roundId: number) -> number?,
	activeRound: (self: Lifecycle) -> number?,
	endCount: (self: Lifecycle) -> number,
}

local DECISECONDS_PER_SECOND = 10

local function new(deps: Deps): Lifecycle
	local scheduler = deps.scheduler
	local onEnded = deps.onEnded

	local nextRoundId = 0
	local currentId: number? = nil -- the most recently begun round; older ids are stale by definition
	local currentEndsAtDeci = 0
	local currentEnded = false
	local cancelBackstop: (() -> ())? = nil
	local endedEvents = 0

	local function endRound(roundId: number, reason: Reason): boolean
		if roundId ~= currentId or currentEnded then
			return false
		end
		-- Mutate first. Everything from here to the publish below is synchronous: no yields.
		currentEnded = true
		local cancel = cancelBackstop
		cancelBackstop = nil
		if cancel ~= nil then
			cancel()
		end
		endedEvents += 1
		onEnded(roundId, reason)
		return true
	end

	local function begin(_self: Lifecycle, durationSeconds: number): number
		if type(durationSeconds) ~= "number" or durationSeconds ~= durationSeconds or durationSeconds == math.huge then
			error(`RoundLifecycle.begin: invalid duration {tostring(durationSeconds)} (must be a finite number)`, 2)
		end
		local durationDeci = math.floor(durationSeconds * DECISECONDS_PER_SECOND)
		if durationDeci < 1 then
			error(
				`RoundLifecycle.begin: invalid duration {tostring(durationSeconds)} (must be at least one decisecond)`,
				2
			)
		end
		if currentId ~= nil and not currentEnded then
			error(`RoundLifecycle.begin: round {currentId} is still active; end it before beginning another`, 2)
		end

		nextRoundId += 1
		local roundId = nextRoundId
		currentId = roundId
		currentEndsAtDeci = scheduler.nowDeci() + durationDeci
		currentEnded = false
		-- The closure captures roundId. Whatever the platform cancel does, a stale firing is rejected by the
		-- id comparison below, so this must keep working with cancel as a no-op.
		cancelBackstop = scheduler.delay(durationSeconds, function()
			if currentId ~= roundId then
				return
			end
			endRound(roundId, "Timeout")
		end)
		return roundId
	end

	local function isOpen(_self: Lifecycle, roundId: number): boolean
		if roundId ~= currentId or currentEnded then
			return false
		end
		if scheduler.nowDeci() >= currentEndsAtDeci then
			endRound(roundId, "Timeout")
			return false
		end
		return true
	end

	return {
		begin = begin,
		isOpen = isOpen,
		endRound = function(_self: Lifecycle, roundId: number, reason: Reason): boolean
			return endRound(roundId, reason)
		end,
		deadlineDeci = function(_self: Lifecycle, roundId: number): number?
			if roundId == currentId then
				return currentEndsAtDeci
			end
			return nil
		end,
		activeRound = function(_self: Lifecycle): number?
			if currentEnded then
				return nil
			end
			return currentId
		end,
		endCount = function(_self: Lifecycle): number
			return endedEvents
		end,
	}
end

return { new = new }
