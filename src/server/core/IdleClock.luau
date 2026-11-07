--!strict
-- The AFK clock (CARD-16; D-13, D-14, D-15, D-16, D-17, D-35). PURE ZONE: no Roblox API, no yields.
--
-- Guarantees:
--   1. PURE ZONE. No clock read, no yields, no randomness of its own. `nowDeci` is a parameter on every
--      call and every duration is an integer number of deciseconds (CLAUDE.md rules 5 and 6).
--   2. Strikes are shell bookkeeping, not engine state. The engine is pure and a strike is not a card
--      rule, so the record lives here, beside it.
--   3. D-15: the clock runs ONLY while the seat has a legal action (hand at 4 with a non-empty inbox, or
--      hand at 5). This is the thing most likely to be got wrong, and the failure is invisible: at
--      N = 10 the start-up ramp is ~8.3 s against a 4.6 s median time to first completion at N = 3, so a
--      clock that ran unconditionally would strike far seats for waiting on cards that have not reached
--      them. It looks like a tuning problem and is a correctness one. Exported as IdleClock.legal.
--   4. D-35: there is no auto-draw and no command that represents one. Four of a kind is checked only on
--      draw, so an auto-draw could pay an absent player a completion plus a kept placement bonus. At
--      hand 4 an expiry is a strike and NOTHING moves. Starvation self-corrects: three strikes benches the
--      seat through the generic removal path, which routes the hoarded inbox to the successor within
--      roughly 24 s at an 8.0 s deadline, and the engine's anti-livelock valve carries the table-level
--      stall job independently. (The Gate G1 sweep modelled the auto-pass at hand 5 only, so it is no
--      evidence for hand-4 behaviour.)
--   5. D-14 is locked. `pickUniform` is the only pick function. No greedy variant may ever be added: the
--      greedy choice is the player's own choice and zeroes the deviation the Gate G1 sweep measured.
--   6. Mutate, then build commands. `tick` increments strikes and re-arms BEFORE constructing the list,
--      then returns it. Nothing is published from here.
--   7. Every number arrives through Deps (guard R6). The one seconds-to-deciseconds conversion site is
--      the CardService adapter. D-13 sits the configured value at the 8.0 s ceiling.
--   8. D-17: any REAL action resets the strike count; a server-originated pass does not. Benching is a
--      command only; the adapter turns it into the one generic Remove with cause Benched (rule 8).
local Types = require("../engine/Types")

export type SeatView = { live: boolean, handSize: number, inboxSize: number }
export type View = { [Types.SeatId]: SeatView }

export type Owes = "Pass" | "Draw"

export type Command =
	{ kind: "AutoPass", seat: Types.SeatId }
	| { kind: "Strike", seat: Types.SeatId, strikes: number, owes: Owes }
	| { kind: "Bench", seat: Types.SeatId }

export type Deps = {
	autoPassDeci: number,
	maxStrikes: number,
}

export type IdleClock = {
	sync: (self: IdleClock, view: View, nowDeci: number, playerActedSeat: Types.SeatId?) -> (),
	tick: (self: IdleClock, nowDeci: number) -> { Command },
	forget: (self: IdleClock, seat: Types.SeatId) -> (),
	deadlineDeci: (self: IdleClock, seat: Types.SeatId) -> number?,
	strikesOf: (self: IdleClock, seat: Types.SeatId) -> number,
	owesOf: (self: IdleClock, seat: Types.SeatId) -> Owes?,
}

type Entry = { deadlineDeci: number?, strikes: number, owes: Owes? }

local FULL_HAND = 5
local DRAW_HAND = 4

-- NaN is the only number not equal to itself; the infinities are excluded explicitly. A NaN deadline
-- would make `deadline <= nowDeci` false forever and the clock would silently never fire.
local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function isCount(v: any): boolean
	return type(v) == "number" and isFinite(v) and v >= 0 and v == math.floor(v)
end

-- D-15, written once. A removed seat is never legal.
local function legal(seat: SeatView): boolean
	if not seat.live then
		return false
	end
	return (seat.handSize == DRAW_HAND and seat.inboxSize >= 1) or seat.handSize == FULL_HAND
end

-- D-14, LOCKED. Uniform over the hand; deliberately no sort, filter, score or dedupe, any of which would
-- reintroduce a preference.
local function pickUniform(hand: { Types.CardId }, rng: any): Types.CardId
	if #hand == 0 then
		error("IdleClock.pickUniform: empty hand", 0)
	end
	return hand[rng:nextInt(1, #hand)]
end

local function checkNow(nowDeci: number)
	if not isCount(nowDeci) then
		error("IdleClock: nowDeci must be a finite non-negative integer decisecond count", 0)
	end
end

local function new(deps: Deps): IdleClock
	if not isCount(deps.autoPassDeci) or deps.autoPassDeci < 1 then
		error("IdleClock: autoPassDeci must be a positive integer", 0)
	end
	if not isCount(deps.maxStrikes) or deps.maxStrikes < 1 then
		error("IdleClock: maxStrikes must be a positive integer", 0)
	end
	local window = deps.autoPassDeci
	local maxStrikes = deps.maxStrikes
	local entries: { [Types.SeatId]: Entry } = {}

	local function sortedSeats(): { Types.SeatId }
		local keys: { Types.SeatId } = {}
		for seatId in entries do
			table.insert(keys, seatId)
		end
		table.sort(keys)
		return keys
	end

	local clock: IdleClock = {
		sync = function(_self: IdleClock, view: View, nowDeci: number, playerActedSeat: Types.SeatId?)
			checkNow(nowDeci)
			for _, seat in view do
				if not isCount(seat.handSize) or not isCount(seat.inboxSize) then
					error("IdleClock: handSize and inboxSize must be non-negative integers", 0)
				end
			end
			-- Seats absent from the view are gone.
			for _, seatId in sortedSeats() do
				if view[seatId] == nil then
					entries[seatId] = nil
				end
			end
			for seatId, seat in view do
				if not seat.live then
					entries[seatId] = nil
				else
					local entry = entries[seatId]
					if entry == nil then
						entry = { deadlineDeci = nil, strikes = 0, owes = nil }
						entries[seatId] = entry
					end
					local acted = seatId == playerActedSeat
					if acted then
						entry.strikes = 0
					end
					if legal(seat) then
						local owesNow: Owes = if seat.handSize == FULL_HAND then "Pass" else "Draw"
						entry.owes = owesNow
						-- An armed deadline is left alone unless the seat itself acted: a card landing in
						-- someone's inbox must not refresh their window.
						if acted or entry.deadlineDeci == nil then
							entry.deadlineDeci = nowDeci + window
						end
					else
						entry.deadlineDeci = nil
						entry.owes = nil
					end
				end
			end
		end,

		tick = function(_self: IdleClock, nowDeci: number): { Command }
			checkNow(nowDeci)
			local commands: { Command } = {}
			for _, seatId in sortedSeats() do
				local entry = entries[seatId]
				local deadline = entry.deadlineDeci
				local owes = entry.owes
				if deadline ~= nil and owes ~= nil and deadline <= nowDeci then
					entry.strikes += 1
					entry.deadlineDeci = nowDeci + window
					local owed: Owes = "Draw"
					if owes == "Pass" then
						owed = "Pass"
						table.insert(commands, { kind = "AutoPass", seat = seatId })
					end
					local strike: Command = { kind = "Strike", seat = seatId, strikes = entry.strikes, owes = owed }
					table.insert(commands, strike)
					if entry.strikes >= maxStrikes then
						table.insert(commands, { kind = "Bench", seat = seatId })
					end
				end
			end
			return commands
		end,

		forget = function(_self: IdleClock, seat: Types.SeatId)
			entries[seat] = nil
		end,

		deadlineDeci = function(_self: IdleClock, seat: Types.SeatId): number?
			local entry = entries[seat]
			return if entry ~= nil then entry.deadlineDeci else nil
		end,

		strikesOf = function(_self: IdleClock, seat: Types.SeatId): number
			local entry = entries[seat]
			return if entry ~= nil then entry.strikes else 0
		end,

		owesOf = function(_self: IdleClock, seat: Types.SeatId): Owes?
			local entry = entries[seat]
			return if entry ~= nil then entry.owes else nil
		end,
	}
	return clock
end

return {
	new = new,
	legal = legal,
	pickUniform = pickUniform,
}
