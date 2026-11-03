--!strict
-- THE 100,000-ACTION CONSERVATION FUZZ (plan 02-08). This file is the phase's load-bearing proof of
-- ROADMAP Phase 2 success criterion 1: across 100,000+ fuzzed actions at every seat count from 2 to
-- 9, with random pools, random churn, idle seats, mid-pass departures and deliberately illegal
-- intents, no card is ever lost, duplicated or swapped.
--
-- 1. ONE ITERATION IS ONE WHOLE ROUND (research 11.2). The driver in `tests/harness/Fuzz.luau` is
--    stateless -- it calls `gen(rng, i)` and then `check(value)` -- so a STATEFUL property has to
--    be folded into `check`: `gen` returns a round PLAN rather than a state, `check` builds the
--    round from that plan with `Engine.newRound` and drives it to the end, and the coverage totals
--    live in spec-level locals closed over by `check`.
--
-- 2. REPRODUCTION IS THE WHOLE POINT OF THE SEED DISCIPLINE, so both halves of it are stated here
--    as contracts. `plan` is a pure function of the base seed and the iteration index, because the
--    shared `rng` is touched ONLY by `gen`. The round is a pure function of `plan`, because every
--    draw inside `check` comes from `Rng.new(plan.roundSeed)` and never from the shared generator,
--    and because `check` only ever WRITES to the spec-level accumulators -- it never reads one to
--    decide what to do next. (That is why the illegal-intent cycle and the churn cause below are
--    derived from `plan.i` and a per-round counter instead of from a spec-level counter: a
--    cross-round counter would make round 412 depend on round 411 and the printed seed would stop
--    reproducing anything.) The driver's failure message names the base seed and the iteration;
--    every error raised here additionally names `plan.roundSeed`, so a failing trial pastes
--    straight into a unit test as `Engine.newRound(config, ids, Rng.new(roundSeed))`, which is what
--    02-CONTEXT.md requires of a failing trial.
--
-- 3. A SUITE THAT CANNOT PROVE IT RAN IS THEATRE (research 11.3, which names two specific
--    defects): a generator bug that shortens rounds, so the suite runs 2,000 actions instead of
--    100,000 and still reads green; and a generator that never emits a completion, a mid-pass
--    departure or an illegal intent, so whole branches sit untested behind a green tick. Both are
--    closed at the bottom of this file -- the action count, a floor for every event kind, every
--    removal cause, all four ring-shrink milestones and all SEVEN reject codes, plus a `checksRun`
--    counter proving `Invariants.check` really ran once per action. Phase 1 verification found two
--    checks in this project that could not fail at all and plan 02-07's mutation battery found a
--    third, so every floor here is mutation-proven rather than merely written.
--
-- 4. SEVEN REJECT CODES, NOT SIX. Research 11.3 says "each of the six Reject codes" and
--    undercounts; `Types.Reject` lists seven and plan 02-07 proved all seven reachable. Each is
--    constructed deliberately below with its EXPECTED code asserted, never merely "some rejection":
--    a catch-all branch that refused everything with one code passed a Phase 1 suite which only
--    checked "refused".
--
-- 5. A REJECTION ASSERTS THREE THINGS: the code, an EMPTY event list, and an unchanged canonical
--    `Invariants.hash` -- research 11.3 notes that a rejection which mutates is worse than one that
--    errors. The valve is tracked separately and could not be covered by the hash in any case,
--    because `Invariants.hash` excludes `valve` by design (plan 02-07, deviation 4).
--
-- 6. `Remove{cause = "Completed"}` IS NEVER GENERATED. It throws by design (plan 02-07, deviation
--    1): an externally supplied one skips the retirement and leaves circulation permanently +4 for
--    the rest of the round. `SeatRemoved{cause = "Completed"}` coverage comes from completing draws
--    instead, which is where research 11.3 wants it from anyway.
--
-- 7. THE VALVE IS OBSERVED, NOT FLOORED. `state.valve.observations` must equal the number of
--    accepted applies so far in the round after every accepted action, and must not move on a
--    rejection; that pair is what catches the valve being skipped inside a conditional and reading
--    green, and it is the mechanism Gate G1's zero-stall result rests on. The FIRING count is
--    RECORDED and reported rather than floored: under this suite's near-random play a table
--    deviates constantly, so a whole-table state repeat is legitimately rare and a firing floor
--    would flake. The firing PROOF lives in plan 02-13's deterministic cycle fixture and plan
--    02-07's end-to-end case. A floor this suite cannot meet honestly must not be quietly set to
--    zero either -- that is the `autoPassRate == 0` defect class the phase checker rejected once
--    already, and the length check Phase 1 verification found behind a "sha256-pinned" claim.
local Engine = require("../../src/server/engine/Engine")
local Fuzz = require("../harness/Fuzz")
local Invariants = require("../../src/server/engine/Invariants")
local Pool = require("../../src/server/engine/Pool")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

local HAND_SIZE = Types.HAND_SIZE
local MAX_HAND = Types.MAX_HAND
local JOKER_RANK = Types.JOKER_RANK

-- THE LOAD. 500 rounds at a measured mean of a few hundred actions each clears the 100,000-action
-- floor with margin for the short 2-seat rounds. The arithmetic is written down so that a future
-- edit to the round length (the churn rate, the termination rule or the action cap all move it) is
-- forced to re-derive the iteration count instead of discovering a silently 40,000-action suite:
--
--     actions = ITERATIONS x mean actions per round   must be >= 100_000
--     at 500 iterations that needs a mean of >= 200 actions per round
--
-- and the `totalActions` floor at the bottom is what turns "must be" into a failing test. Research
-- 11.1 measured the full identity scan at 343,502 actions/s, so this costs ~0.3s of scan time and
-- there is no reason to tier it.
local ITERATIONS = 500

-- A per-round cap, and an ERROR rather than a quiet break: a round of 2 to 9 seats cannot
-- legitimately need this many actions (the longest observed is two orders of magnitude below it),
-- so reaching it means a runaway driver loop, which would otherwise only ever show up as a slow
-- suite. Churn also bounds the sole-seat endgame at ~100 actions in expectation, so the cap is a
-- tripwire and not a budget.
local ACTION_CAP = 4000

-- The eight illegal constructions below cover the seven codes; `NotYourCard` has two shapes because
-- research 7.6 distinguishes them (a card held by another seat, and a card of the actor's own that
-- an auto-pass already moved into an inbox) and plan 02-07's mutation M3 is caught only by the
-- second.
local ILLEGAL_SHAPES = 8

-- Seat predicates for the pickers. Numeric rather than string tags so the hot scan compares
-- integers.
local WANT_DEAD = 1
local WANT_LIVE = 2
local WANT_LOCKED = 3 -- live, holding MAX_HAND: the only seat that may legally pass
local WANT_LOCKED_WITH_INBOX = 4 -- live, MAX_HAND, and something sitting in its own inbox
local WANT_RESTING = 5 -- live, holding HAND_SIZE
local WANT_RESTING_EMPTY_INBOX = 6 -- live, HAND_SIZE, empty inbox: the InboxEmpty situation

export type RoundPlan = {
	i: number,
	roundSeed: number,
	seatCount: number,
	k: number,
	jokers: number,
	jokerMode: Types.JokerMode,
	antiLivelockValve: boolean,
	churnChance: number,
	illegalChance: number,
}

-- One reusable buffer for the seat pickers. They are never nested, and a fresh table per pick would
-- allocate once per illegal intent and once per churn removal.
local scratch: { number } = {}

local function pickSeat(state: Types.State, rng: any, want: number): Types.SeatId?
	local found = 0
	for id = 1, #state.seats do
		local seat = state.seats[id]
		local hit: boolean
		if want == WANT_DEAD then
			hit = not seat.live
		elseif want == WANT_LIVE then
			hit = seat.live
		elseif want == WANT_LOCKED then
			hit = seat.live and #seat.hand == MAX_HAND
		elseif want == WANT_LOCKED_WITH_INBOX then
			hit = seat.live and #seat.hand == MAX_HAND and #seat.inbox >= 1
		elseif want == WANT_RESTING then
			hit = seat.live and #seat.hand == HAND_SIZE
		else
			hit = seat.live and #seat.hand == HAND_SIZE and #seat.inbox == 0
		end
		if hit then
			found += 1
			scratch[found] = id
		end
	end
	if found == 0 then
		return nil
	end
	return scratch[rng:nextInt(1, found)]
end

-- An in-range card id the seat does not hold. Starts from a random id and walks forward with
-- wraparound, so it is uniform-ish and terminates in at most MAX_HAND + 1 probes.
local function foreignCard(state: Types.State, seatId: Types.SeatId, rng: any): Types.CardId?
	local hand = state.seats[seatId].hand
	local start = rng:nextInt(1, state.totalCards)
	for offset = 0, state.totalCards - 1 do
		local id = (start + offset - 1) % state.totalCards + 1
		if table.find(hand, id) == nil then
			return id
		end
	end
	return nil
end

-- ONE deliberately illegal intent, built so the EXPECTED reject code is known in advance. Returns
-- `(nil, nil)` when the current state cannot express this shape (there is no dead seat yet, nobody
-- is holding five, ...); the caller then advances the cycle, so a shape is skipped rather than
-- weakened into "some rejection". Shape 1 needs nothing from the state, so the cycle can always
-- produce something while a seat is live.
local function buildIllegal(state: Types.State, rng: any, shape: number): (Types.Intent?, Types.Reject?)
	if shape == 1 then
		-- UnknownSeat: an index that names no seat at all. Below the ring and above it, alternating,
		-- because an implementation that bounds-checked only one end would pass on the other.
		local seatId = if rng:nextNumber() < 0.5 then 0 else state.seatCount + 1
		local intent: Types.Intent = { kind = "Draw", seat = seatId }
		return intent, "UnknownSeat"
	elseif shape == 2 then
		-- SeatNotLive: the actor end of a mid-pass departure (research 7.6). A seat that completed,
		-- disconnected or was benched may not act, and its own replayed intents must be refused.
		local seatId = pickSeat(state, rng, WANT_DEAD)
		if seatId == nil then
			return nil, nil
		end
		local intent: Types.Intent = { kind = "Draw", seat = seatId }
		return intent, "SeatNotLive"
	elseif shape == 3 then
		-- UnknownCard: an id outside 1..totalCards. Checked BEFORE the hand size, so this fires
		-- from a resting hand too -- plan 02-07's locked Pass precedence.
		local seatId = pickSeat(state, rng, WANT_LIVE)
		if seatId == nil then
			return nil, nil
		end
		local cardId = if rng:nextNumber() < 0.5 then 0 else state.totalCards + 1
		local intent: Types.Intent = { kind = "Pass", seat = seatId, cardId = cardId }
		return intent, "UnknownCard"
	elseif shape == 4 then
		-- HandNotFive: a pass from a RESTING hand, with a perfectly real card id the seat holds.
		-- Only the hand size is wrong, which is what distinguishes this from NotYourCard.
		local seatId = pickSeat(state, rng, WANT_RESTING)
		if seatId == nil then
			return nil, nil
		end
		local intent: Types.Intent = { kind = "Pass", seat = seatId, cardId = state.seats[seatId].hand[1] }
		return intent, "HandNotFive"
	elseif shape == 5 then
		-- NotYourCard, shape 1: a card in range, from a hand of five, that this seat does not hold.
		local seatId = pickSeat(state, rng, WANT_LOCKED)
		if seatId == nil then
			return nil, nil
		end
		local cardId = foreignCard(state, seatId, rng)
		if cardId == nil then
			return nil, nil
		end
		local intent: Types.Intent = { kind = "Pass", seat = seatId, cardId = cardId }
		return intent, "NotYourCard"
	elseif shape == 6 then
		-- NotYourCard, shape 2 (research 7.6): a card sitting in the actor's OWN inbox. It is in
		-- play, it is "the seat's", and it is still not passable -- plan 02-07's case 15, and the
		-- only thing that catches a predicate which scans the inbox as well as the hand (M3).
		local seatId = pickSeat(state, rng, WANT_LOCKED_WITH_INBOX)
		if seatId == nil then
			return nil, nil
		end
		local intent: Types.Intent = { kind = "Pass", seat = seatId, cardId = state.seats[seatId].inbox[1] }
		return intent, "NotYourCard"
	elseif shape == 7 then
		-- HandNotFour: a draw at five. CARD-01's "the pile locks at 5" is exactly this rejection and
		-- nothing else -- there is no `locked` flag anywhere to disagree with the hand.
		local seatId = pickSeat(state, rng, WANT_LOCKED)
		if seatId == nil then
			return nil, nil
		end
		local intent: Types.Intent = { kind = "Draw", seat = seatId }
		return intent, "HandNotFour"
	end
	-- InboxEmpty: a resting hand with nothing to draw. Checked AFTER HandNotFour, so the hand must
	-- be exactly four for this to be the answer (plan 02-07's case 17 and mutation M1).
	local seatId = pickSeat(state, rng, WANT_RESTING_EMPTY_INBOX)
	if seatId == nil then
		return nil, nil
	end
	local intent: Types.Intent = { kind = "Draw", seat = seatId }
	return intent, "InboxEmpty"
end

local function kindsOf(events: { Types.Event }): string
	local parts: { string } = {}
	for _, event in events do
		table.insert(parts, event.kind)
	end
	return table.concat(parts, ",")
end

return function(t: Test.Runner)
	-- SPEC-LEVEL COVERAGE TOTALS, closed over by `check`. WRITE-ONLY from inside a round: nothing
	-- here is ever read to decide what the driver does next, which is what keeps a round a pure
	-- function of its plan (see header note 2).
	local roundsPlayed = 0
	local totalActions = 0
	local acceptedActions = 0
	local rejectedActions = 0
	local checksRun = 0
	local longestRound = 0
	local shortestRound = math.huge
	local seatCountsSeen: { [number]: number } = {}

	local eventCounts: { [string]: number } = {
		Drew = 0,
		Passed = 0,
		Completed = 0,
		SeatRemoved = 0,
		ValveForcedPass = 0,
	}
	-- Keyed by `naturalsUsed`, derived from the Completed event's `retired` list rather than read
	-- off a field: `Types.Event` does not carry `naturalsUsed`, and deriving it from `rankOf` means
	-- the shape is counted from the cards that actually left play.
	local completionShapes: { [number]: number } = { [4] = 0, [3] = 0, [2] = 0 }
	local causeCounts: { [string]: number } = { Completed = 0, Disconnected = 0, Benched = 0 }
	local milestones: { [string]: number } = { dealerRemoved = 0, ringToTwo = 0, ringToOne = 0, ringEmptied = 0 }
	local rejectCounts: { [string]: number } = {
		UnknownSeat = 0,
		SeatNotLive = 0,
		UnknownCard = 0,
		NotYourCard = 0,
		HandNotFour = 0,
		HandNotFive = 0,
		InboxEmpty = 0,
	}

	local valveObservations = 0
	local valveFirings = 0
	local valveSeenResets = 0
	local armedRounds = 0
	-- The two valve defects this suite exists to catch, counted rather than raised on the spot. A
	-- per-action `error` would make the totals below structurally incapable of failing -- the exact
	-- un-failable-gate class this phase has now found six times -- so the per-action comparison
	-- feeds a counter and captures the FIRST offender's reproduction data, and the assertion at the
	-- bottom is the gate that can actually fail, with that reproduction text in its message.
	local valveDepthMismatches = 0
	local valveObservationsOnRejection = 0
	-- One captured reproduction EACH: the two defects have different causes (a skipped or doubled
	-- entry point against an entry point that runs on the refusal path), so sharing one slot would
	-- report the wrong round for whichever lost the race.
	local valveDepthRepro: string? = nil
	local valveLeakRepro: string? = nil

	local function coverageReport(): string
		local lines: { string } = {
			`totalActions       {totalActions}   (accepted {acceptedActions}, rejected {rejectedActions})`,
			`checksRun          {checksRun}`,
			`rounds             {roundsPlayed}   (longest {longestRound} actions, shortest {shortestRound})`,
			`events             Drew {eventCounts.Drew}   Passed {eventCounts.Passed}   Completed {eventCounts.Completed}   SeatRemoved {eventCounts.SeatRemoved}   ValveForcedPass {eventCounts.ValveForcedPass}`,
			`completion shapes  4 naturals {completionShapes[4]}   3+1j {completionShapes[3]}   2+2j {completionShapes[2]}`,
			`removal causes     Completed {causeCounts.Completed}   Disconnected {causeCounts.Disconnected}   Benched {causeCounts.Benched}`,
			`ring milestones    dealer removed {milestones.dealerRemoved}   ring to 2 {milestones.ringToTwo}   ring to 1 {milestones.ringToOne}   ring emptied {milestones.ringEmptied}`,
			`reject codes       UnknownSeat {rejectCounts.UnknownSeat}   SeatNotLive {rejectCounts.SeatNotLive}   UnknownCard {rejectCounts.UnknownCard}   NotYourCard {rejectCounts.NotYourCard}   HandNotFour {rejectCounts.HandNotFour}   HandNotFive {rejectCounts.HandNotFive}   InboxEmpty {rejectCounts.InboxEmpty}`,
			`valve              observations {valveObservations}   firings {valveFirings}   armed rounds {armedRounds}   seen resets {valveSeenResets}`,
			`valve defences     depth mismatches {valveDepthMismatches} ({tostring(valveDepthRepro)})   observations on a rejection {valveObservationsOnRejection} ({tostring(
				valveLeakRepro
			)})`,
		}
		local seats: { string } = {}
		for count = 2, 9 do
			table.insert(seats, `{count}:{seatCountsSeen[count] or 0}`)
		end
		table.insert(lines, `rounds by seatCount  {table.concat(seats, "  ")}`)
		return table.concat(lines, "\n  ")
	end

	local function gen(rng: any, i: number): RoundPlan
		local mode: Types.JokerMode = if rng:nextNumber() < 0.5 then "Wild" else "Blocker"
		return {
			i = i,
			-- The one number that reproduces the round. Everything `check` does is drawn from
			-- `Rng.new(roundSeed)`; nothing in `check` touches this shared `rng` again.
			roundSeed = rng:nextUint(),
			-- 2..9 SEATED SEEKERS, which is N = 3..10 players, because the hider does not play cards
			-- (02-CONTEXT.md amendment A3: seatCount = N - 1). The subtraction is never written
			-- inline here -- `Pool.poolConfig` takes PLAYERS and owns it.
			seatCount = rng:nextInt(2, 9),
			k = rng:nextInt(1, 2), -- k >= 1 is mandatory (amendment A4); k = 0 is plan 02-10's DeadPool
			jokers = rng:nextInt(0, 2),
			jokerMode = mode,
			antiLivelockValve = true, -- the shipped setting; asserted against what poolConfig builds
			churnChance = 0.01, -- per action: one live seat is Disconnected or Benched
			illegalChance = 0.12, -- per action: one deliberately illegal intent instead of a legal one
		}
	end

	local function check(value: any)
		local plan: RoundPlan = value
		local config, seatCount = Pool.poolConfig(plan.seatCount + 1, plan.k, plan.jokers, plan.jokerMode)
		local repro =
			`iteration {plan.i}, roundSeed {plan.roundSeed}, seatCount {plan.seatCount}, pool ranks={config.ranks} jokers={config.jokers} mode={config.jokerMode} k={plan.k}`

		if seatCount ~= plan.seatCount then
			error(
				`{repro}: Pool.poolConfig returned seatCount {seatCount} for {plan.seatCount + 1} players; amendment A3 is seatCount = N - 1 -- reproduce with Rng.new({plan.roundSeed})`
			)
		end
		if config.antiLivelockValve ~= plan.antiLivelockValve then
			error(
				`{repro}: Pool.poolConfig did not build the shipped valve position (amendment A7) -- reproduce with Rng.new({plan.roundSeed})`
			)
		end

		local playerIds: { Types.PlayerId } = {}
		for s = 1, plan.seatCount do
			playerIds[s] = 1000 + s
		end

		-- ONE generator for the whole round: the deal, the valve's derived seed and every driver
		-- decision below. That is what makes the round a pure function of `plan.roundSeed`.
		local rng = Rng.new(plan.roundSeed)
		local state = Engine.newRound(config, playerIds, rng)

		local appliesInRound = 0
		local acceptedInRound = 0
		local illegalInRound = 0
		local churnInRound = 0

		-- ONE action: apply it, account for it, and check the FULL partition identity afterwards.
		-- `expected` nil means "this intent is legal and must be accepted"; a code means "this
		-- intent is illegal and must be refused with exactly this code".
		local function act(intent: Types.Intent, expected: Types.Reject?)
			appliesInRound += 1
			if appliesInRound > ACTION_CAP then
				error(
					`{repro}: the round driver exceeded the {ACTION_CAP}-action cap with completions={state.counters.completions} liveCount={state.liveCount}; a 2..9 seat round cannot legitimately need that many actions -- reproduce with Rng.new({plan.roundSeed})`
				)
			end

			local observationsBefore = state.valve.observations
			local hashBefore = if expected ~= nil then Invariants.hash(state) else ""

			local result = Engine.apply(state, intent)
			totalActions += 1

			if expected ~= nil then
				rejectedActions += 1
				if result.ok ~= false then
					error(
						`{repro}: an illegal {intent.kind} was ACCEPTED, expected reject {expected} -- reproduce with Rng.new({plan.roundSeed})`
					)
				end
				if result.reject ~= expected then
					error(
						`{repro}: an illegal {intent.kind} was refused with {tostring(result.reject)}, expected {expected}; a code asserted only as "some rejection" would let one catch-all branch pass -- reproduce with Rng.new({plan.roundSeed})`
					)
				end
				if #result.events ~= 0 then
					error(
						`{repro}: a {expected} rejection returned {#result.events} events ({kindsOf(result.events)}), expected an empty list -- reproduce with Rng.new({plan.roundSeed})`
					)
				end
				if Invariants.hash(state) ~= hashBefore then
					error(
						`{repro}: a {expected} rejection MUTATED the state (research 11.3: worse than one that errors) -- reproduce with Rng.new({plan.roundSeed})`
					)
				end
				rejectCounts[expected] += 1
				if state.valve.observations ~= observationsBefore then
					valveObservationsOnRejection += 1
					if valveLeakRepro == nil then
						valveLeakRepro =
							`{repro}: the valve was observed on a {expected} rejection (observations {observationsBefore} -> {state.valve.observations}) at applies={appliesInRound}`
					end
				end
			else
				acceptedActions += 1
				acceptedInRound += 1
				if not result.ok then
					error(
						`{repro}: a legal {intent.kind} at seat {intent.seat} was refused with {tostring(result.reject)} -- reproduce with Rng.new({plan.roundSeed})`
					)
				end

				-- EXACTLY ONE VALVE ENTRY POINT PER ACCEPTED APPLY, none on a rejection (plan
				-- 02-07's locked valve call rule). Counted, not raised here; see the accumulator.
				if state.valve.observations ~= acceptedInRound then
					valveDepthMismatches += 1
					if valveDepthRepro == nil then
						valveDepthRepro =
							`{repro}: valve.observations is {state.valve.observations} after {acceptedInRound} accepted applies in the round, at applies={appliesInRound}`
					end
				end

				local events = result.events
				local removed = false
				for _, event in events do
					eventCounts[event.kind] += 1
					if event.kind == "Completed" then
						local naturals = 0
						for _, id in event.retired do
							if state.rankOf[id] ~= JOKER_RANK then
								naturals += 1
							end
						end
						completionShapes[naturals] = (completionShapes[naturals] or 0) + 1
					elseif event.kind == "SeatRemoved" then
						removed = true
						causeCounts[event.cause] = (causeCounts[event.cause] or 0) + 1
						if event.seat == 1 then
							milestones.dealerRemoved += 1
						end
					end
				end
				if removed then
					-- The ring-shrink milestones research 7 names as the cases a naive
					-- implementation breaks. Read from `liveCount` AFTER the removal.
					if state.liveCount == 2 then
						milestones.ringToTwo += 1
					elseif state.liveCount == 1 then
						milestones.ringToOne += 1
					elseif state.liveCount == 0 then
						milestones.ringEmptied += 1
					end
				end

				-- THE LOCKED EVENT ORDER, and with it the uniform rule that EVERY card movement in
				-- the engine carries exactly one Drew or Passed -- the forced pass included. A
				-- consumer that special-cased the ValveForcedPass marker would be a Phase 4 bug
				-- waiting to happen, so the marker is required to be FOLLOWED by a real Passed for
				-- the same card and the same target.
				local count = #events
				local formOk = false
				if intent.kind == "Draw" then
					if count == 1 then
						formOk = events[1].kind == "Drew"
					elseif count == 3 then
						local first, second, third = events[1], events[2], events[3]
						if first.kind == "Drew" and second.kind == "ValveForcedPass" and third.kind == "Passed" then
							formOk = true
							if second.cardId ~= third.cardId or second.to ~= third.to then
								error(
									`{repro}: ValveForcedPass names card {second.cardId} to seat {second.to} but the Passed that follows it moves card {third.cardId} to seat {third.to} -- reproduce with Rng.new({plan.roundSeed})`
								)
							end
						elseif first.kind == "Drew" and second.kind == "Completed" and third.kind == "SeatRemoved" then
							formOk = true
						end
					end
				elseif intent.kind == "Pass" then
					formOk = count == 1 and events[1].kind == "Passed"
				else
					formOk = count == 1 and events[1].kind == "SeatRemoved"
				end
				if not formOk then
					error(
						`{repro}: a legal {intent.kind} produced the event form "{kindsOf(events)}", which is not one of the locked forms -- reproduce with Rng.new({plan.roundSeed})`
					)
				end
			end

			-- THE FULL FOUR-BUCKET PARTITION IDENTITY, AFTER EVERY ACTION, ACCEPTED OR REJECTED, AND
			-- NEVER TIERED. Research 11.1: the identity scan is 1.7x the cost of the counters alone
			-- and 100k actions cost ~0.3s, so there is nothing to buy by checking every tenth state.
			-- `Engine.apply` deliberately does not call this (plan 02-07, note 5): the cost is this
			-- suite's to pay.
			local ok, why = Invariants.check(state)
			checksRun += 1
			if not ok then
				error(
					`{repro}: Invariants.check reported "{tostring(why)}" after a {intent.kind} at seat {intent.seat} (expected={tostring(
						expected
					)}, applies={appliesInRound}, liveCount={state.liveCount}, completions={state.counters.completions}) -- reproduce with Rng.new({plan.roundSeed})`
				)
			end
		end

		-- THE ROUND. It ends when the ring empties, or when every seat that can still win has won
		-- (seatCount - 1 completions: there are always two fewer spoons than players), or at the
		-- action cap, which errors.
		local target = plan.seatCount - 1
		while state.liveCount > 0 and state.counters.completions < target do
			if rng:nextNumber() < plan.illegalChance then
				-- Cycle the shapes so every code is attempted across the run, starting from an
				-- offset derived from the iteration index so the rotation is still a pure function
				-- of the plan. A shape the current state cannot express is SKIPPED, not weakened.
				local intent: Types.Intent? = nil
				local expected: Types.Reject? = nil
				for step = 0, ILLEGAL_SHAPES - 1 do
					local shape = (plan.i + illegalInRound + step) % ILLEGAL_SHAPES + 1
					intent, expected = buildIllegal(state, rng, shape)
					if intent ~= nil then
						break
					end
				end
				illegalInRound += 1
				if intent ~= nil and expected ~= nil then
					act(intent, expected)
				end
			else
				-- A uniformly chosen legal action among every live seat that has one. Draw at
				-- exactly four with something to draw; pass a uniformly chosen held card at five.
				local options = 0
				local optionSeat: { number } = {}
				local optionDraw: { boolean } = {}
				for id = 1, #state.seats do
					local seat = state.seats[id]
					if not seat.live then
						continue
					end
					if #seat.hand == MAX_HAND then
						options += 1
						optionSeat[options] = id
						optionDraw[options] = false
					elseif #seat.hand == HAND_SIZE and #seat.inbox >= 1 then
						options += 1
						optionSeat[options] = id
						optionDraw[options] = true
					end
				end
				if options == 0 then
					-- THE LIVENESS INVARIANT (research 5, Invariants check 3). With a card in
					-- circulation some live seat must hold five (it can pass) or hold four with a
					-- non-empty inbox (it can draw). No legal action with circulation left means
					-- the ring is corrupt, so this is an error and never a quiet break.
					local circulating = Invariants.circulation(state)
					if circulating >= 1 then
						error(
							`{repro}: no live seat has a legal action while circulation is {circulating} (liveCount={state.liveCount}, applies={appliesInRound}); the ring is corrupt -- reproduce with Rng.new({plan.roundSeed})`
						)
					end
					break
				end
				local pick = rng:nextInt(1, options)
				local seatId = optionSeat[pick]
				if optionDraw[pick] then
					local intent: Types.Intent = { kind = "Draw", seat = seatId }
					act(intent, nil)
				else
					local hand = state.seats[seatId].hand
					local intent: Types.Intent = { kind = "Pass", seat = seatId, cardId = hand[rng:nextInt(1, #hand)] }
					act(intent, nil)
				end
			end

			-- CHURN: a mid-pass departure, a disconnect or an AFK bench, all through the one generic
			-- removal (CLAUDE.md rule 8). The cause alternates so both accumulate, derived from the
			-- per-round counter so it stays reproducible. `Completed` is never generated here: it
			-- throws by design (header note 6).
			if state.liveCount > 0 and rng:nextNumber() < plan.churnChance then
				local seatId = pickSeat(state, rng, WANT_LIVE)
				if seatId ~= nil then
					local cause: Types.RemoveCause = if (plan.i + churnInRound) % 2 == 0
						then "Disconnected"
						else "Benched"
					churnInRound += 1
					local intent: Types.Intent = { kind = "Remove", seat = seatId, cause = cause }
					act(intent, nil)
				end
			end
		end

		roundsPlayed += 1
		seatCountsSeen[plan.seatCount] = (seatCountsSeen[plan.seatCount] or 0) + 1
		longestRound = math.max(longestRound, appliesInRound)
		shortestRound = math.min(shortestRound, appliesInRound)
		valveObservations += state.valve.observations
		valveFirings += state.valve.firings
		valveSeenResets += state.valve.seenResets
		if state.valve.armed then
			armedRounds += 1
		end

		-- THE COVERAGE GATE LIVES INSIDE THIS CASE, ON THE LAST ITERATION, AND NOT IN A SEPARATE
		-- `t.test`. `tests/run.luau` selects by substring, so a filter that picked a counter case
		-- without the fuzz case would read zero totals and fail falsely -- and, far worse, a filter
		-- that picked the fuzz case without the counter case would read green while asserting
		-- nothing about coverage at all. One case, one set of totals.
		if plan.i < ITERATIONS then
			return
		end

		print(`  fuzz coverage (plan 02-08):\n  {coverageReport()}`)
	end

	local fuzzOpts: Test.FuzzOpts = {
		seed = 20260203,
		iterations = 500,
		gen = gen,
		check = check,
	}
	-- `iterations` is a literal above so the load is visible at the call site, while `check` needs
	-- the same number to know which iteration is the last one. The two are tied together here rather
	-- than trusted to stay in step: if they ever diverged DOWNWARD the coverage block would never
	-- run at all and this file would assert nothing about its own coverage.
	if fuzzOpts.iterations ~= ITERATIONS then
		error(`fuzz.spec: opts.iterations ({tostring(fuzzOpts.iterations)}) must equal ITERATIONS ({ITERATIONS})`)
	end

	t.fuzz("500 whole rounds: the partition identity holds after every one of 100,000+ actions", fuzzOpts)

	t.test("the fuzz driver is installed", function()
		t.equal(type(Fuzz.driver), "function", "tests/harness/Fuzz must export driver")
		t.equal(type(Test.new), "function", "tests/harness/Test must export new")
		t.equal(type(t.fuzz), "function", "the runner must expose fuzz, or 125,000 actions become zero")
	end)
end
