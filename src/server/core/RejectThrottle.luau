--!strict
-- Per-user log throttle for gateway rejections. PURE ZONE: no Roblox API, no clock read, no yields.
-- Time is a parameter in integer deciseconds (CLAUDE.md rule 5).
--
-- D-22 DECISION RECORD. `01-CONTEXT.md` D-22, reviewed in Phase 4: the gateway's check order is KEPT.
-- A wrong-phase rejection charges no token. The log is throttled instead.
--
-- The order is `isKnown -> phase gate -> bucket -> validate -> dispatch` (Gateway.luau:56-98).
-- Charging a token on a wrong-phase message would cost a bucket lookup/refill and would allocate a
-- per-user per-intent entry on first use, buys an attacker nothing (the message is dropped either
-- way), and spends real tokens for honest players at phase edges: a `Pass` landing just after the
-- round ends is a `WrongPhase`. It would also reorder a documented "nothing may be reordered" chain
-- and rewrite its spec-lock tests.
--
-- THE ACTUAL EXPOSURE WAS NEVER THE TOKEN COST. `Main.server.luau` warned ONCE PER REJECTION, so a
-- WrongPhase flood was a log-spam and CPU vector throttled only by the platform's per-client request
-- ceiling. That is what this file removes.
--
-- THE TRADE-OFF, STATED PLAINLY: suppressed individual lines mean a real diagnostic can be lost inside
-- a flood. The window summary and the per-user streak are the compensation, and Phase 8 may act on a
-- sustained streak. THIS PHASE DOES NOT KICK ANYBODY: `streakOf` is an accessor with no consumer yet,
-- and that is deliberate. Do not delete it and do not act on it before Phase 8.
--
-- THE KEY IS THE USER, NEVER (user, code). `code` is accepted so the caller can include it in the line
-- it logs; it takes no part in any throttling decision. A per-code throttle lets a flood of mixed
-- rejection codes walk straight through (the observed codes are UnknownKey, MissingKey, NotFinite,
-- WrongType, NotInteger, OutOfRange, NotTable, ForbiddenType, WrongPhase, ...). The spec holds a
-- mutation for exactly that "improvement".
--
-- CARD-14 consequence: a gateway-level rejection never reaches the card core, so its `seq` is never
-- acked. Whatever `note` returns, the caller still pushes a Sync so the client's pending entry
-- resolves; this module only decides what gets LOGGED.
export type Decision = {
	log: boolean, -- write the individual warn line
	summary: number?, -- non-nil when a window just closed with this many suppressed rejections
	streak: number, -- consecutive windows in which this user was rejected at least once
}

export type Deps = { logPerWindow: number, windowDeci: number }

export type RejectThrottle = {
	note: (self: RejectThrottle, userId: number, code: string, nowDeci: number) -> Decision,
	streakOf: (self: RejectThrottle, userId: number) -> number,
	forget: (self: RejectThrottle, userId: number) -> (),
}

type Entry = {
	windowStartDeci: number,
	countInWindow: number,
	loggedInWindow: number,
	streak: number,
}

-- NaN is the only number that is not equal to itself; the two infinities are excluded explicitly.
local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function new(deps: Deps): RejectThrottle
	local entries: { [number]: Entry } = {}

	local throttle: RejectThrottle = {
		note = function(_self: RejectThrottle, userId: number, _code: string, nowDeci: number): Decision
			if type(userId) ~= "number" or not isFinite(userId) then
				error(`RejectThrottle.note: userId must be a finite number, got {tostring(userId)}`)
			end
			if type(nowDeci) ~= "number" or not isFinite(nowDeci) or nowDeci < 0 or nowDeci % 1 ~= 0 then
				error(`RejectThrottle.note: nowDeci must be a finite non-negative integer, got {tostring(nowDeci)}`)
			end

			local entry = entries[userId]
			local summary: number? = nil
			if entry == nil then
				entry = {
					windowStartDeci = nowDeci,
					countInWindow = 0,
					loggedInWindow = 0,
					streak = 1,
				}
				entries[userId] = entry
			else
				local elapsed = nowDeci - entry.windowStartDeci
				if elapsed >= deps.windowDeci then
					local suppressed = entry.countInWindow - entry.loggedInWindow
					if suppressed > 0 then
						summary = suppressed
					end
					-- Windows are aligned to the first one. The closing window always held at least one
					-- rejection (a window only opens on a rejection), so the streak continues only when the
					-- very next window is the one now opening; any fully quiet window in between resets it.
					local windowsAdvanced = elapsed // deps.windowDeci
					if windowsAdvanced == 1 then
						entry.streak += 1
					else
						entry.streak = 1
					end
					entry.windowStartDeci += windowsAdvanced * deps.windowDeci
					entry.countInWindow = 0
					entry.loggedInWindow = 0
				end
			end

			entry.countInWindow += 1
			local shouldLog = entry.loggedInWindow < deps.logPerWindow
			if shouldLog then
				entry.loggedInWindow += 1
			end
			return { log = shouldLog, summary = summary, streak = entry.streak }
		end,

		streakOf = function(_self: RejectThrottle, userId: number): number
			local entry = entries[userId]
			if entry == nil then
				return 0
			end
			return entry.streak
		end,

		forget = function(_self: RejectThrottle, userId: number)
			if type(userId) == "number" and isFinite(userId) then
				entries[userId] = nil
			end
		end,
	}
	return throttle
end

return { new = new }
