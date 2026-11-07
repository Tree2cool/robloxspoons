--!strict
-- The stall cue's own no-progress detector (D-20). PURE ZONE: no Roblox API, no yields, the clock is
-- a parameter in integer deciseconds (CLAUDE.md rules 5 and 6).
--
-- 1. PURE, with an injected clock. Every method takes `nowDeci`; nothing here reads time.
--
-- 2. D-20: INDEPENDENT OF THE VALVE, BY CONSTRUCTION. Phase 2 verification replayed 15 residual
--    stalled seeds. Every one ran 2,431-4,429 actions without clearing against a healthy mean of
--    about 380, and 3 of the 15 had the valve armed and firing ZERO times: the valve fires only on an
--    exact whole-table state repeat, and a stuck trajectory that never exactly repeats is invisible to
--    it. A cue keyed off ValveForcedPass would therefore be silent in exactly the rounds that need it.
--    So `noteApply` takes NO event parameter. There is nowhere a valve event could be fed in. A
--    convention would be forgotten; a missing parameter cannot be.
--
-- 3. BOTH CONDITIONS ARE REQUIRED. The cue arms when
--        actionsSinceProgress >= actionsPerSeat * liveSeatsAtLastApply
--    AND nowDeci - lastProgressDeci >= minDeci.
--    actionsPerSeat = 96 is twice the engine's VALVE_ARM_ACTIONS_PER_SEAT = 48 (the spec asserts the
--    relation against Types), so the cue is strictly later than the valve's arming. The wall-time
--    condition gates the small-table case, where an action count alone is reached too easily. The
--    numbers are Claude's discretion under D-20; Phase 8 may tune them on the telemetry emitted here.
--
-- 4. IT NEVER ENDS A ROUND. Round-end conditions belong to Phases 5 and 6 (D-20). This module raises a
--    cue and emits telemetry; it has no end-round path.
--
-- 5. Inputs are hardened with the isFinite idiom: liveSeats must be a finite integer >= 1 and nowDeci a
--    finite non-negative integer, or the call errors by name.
--
-- Telemetry carries counters only (`{ [string]: number }`): no card id, no hand, no hash.
export type Command = { kind: "StallCue" } | { kind: "StallClear" }

export type Deps = {
	actionsPerSeat: number,
	minDeci: number,
	cueDeci: number, -- carried for the client's display window; published by the caller, not acted on here
	repeatDeci: number,
	onTelemetry: (name: string, data: { [string]: number }) -> (),
}

export type StallDetector = {
	noteApply: (self: StallDetector, liveSeats: number, nowDeci: number) -> (),
	noteProgress: (self: StallDetector, nowDeci: number) -> (),
	tick: (self: StallDetector, nowDeci: number) -> { Command },
	isActive: (self: StallDetector) -> boolean,
	actionsSinceProgress: (self: StallDetector) -> number,
}

-- NaN is the only number that is not equal to itself; the two infinities are excluded explicitly.
local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function checkTime(who: string, nowDeci: number)
	if type(nowDeci) ~= "number" or not isFinite(nowDeci) or nowDeci < 0 or nowDeci % 1 ~= 0 then
		error(`StallDetector.{who}: nowDeci must be a finite non-negative integer, got {tostring(nowDeci)}`)
	end
end

local function new(deps: Deps): StallDetector
	local actions = 0
	local liveSeats = 1
	local lastProgressDeci = 0
	local active = false
	local lastCueDeci = 0
	local pendingClear = false

	local detector: StallDetector = {
		noteApply = function(_self: StallDetector, seats: number, nowDeci: number)
			checkTime("noteApply", nowDeci)
			if type(seats) ~= "number" or not isFinite(seats) or seats < 1 or seats % 1 ~= 0 then
				error(`StallDetector.noteApply: liveSeats must be a finite integer >= 1, got {tostring(seats)}`)
			end
			actions += 1
			liveSeats = seats
		end,

		noteProgress = function(_self: StallDetector, nowDeci: number)
			checkTime("noteProgress", nowDeci)
			if active then
				active = false
				pendingClear = true
				deps.onTelemetry("stall_cleared", { actions = actions, deci = nowDeci - lastProgressDeci })
			end
			actions = 0
			lastProgressDeci = nowDeci
		end,

		tick = function(_self: StallDetector, nowDeci: number): { Command }
			checkTime("tick", nowDeci)
			local out: { Command } = {}
			if pendingClear then
				pendingClear = false
				table.insert(out, { kind = "StallClear" })
			end
			if active then
				if nowDeci - lastCueDeci >= deps.repeatDeci then
					lastCueDeci = nowDeci
					table.insert(out, { kind = "StallCue" })
				end
			elseif
				actions > 0
				and actions >= deps.actionsPerSeat * liveSeats
				and nowDeci - lastProgressDeci >= deps.minDeci
			then
				active = true
				lastCueDeci = nowDeci
				deps.onTelemetry(
					"stall_armed",
					{ actions = actions, deci = nowDeci - lastProgressDeci, liveSeats = liveSeats }
				)
				table.insert(out, { kind = "StallCue" })
			end
			return out
		end,

		isActive = function(_self: StallDetector): boolean
			return active
		end,

		actionsSinceProgress = function(_self: StallDetector): number
			return actions
		end,
	}
	return detector
end

return { new = new }
