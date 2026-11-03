--!strict
-- The headless bot simulator (CARD-11, CARD-12): two modes, a six-category outcome taxonomy, the
-- eight metrics, the four-plus-one per-cell G1 bars and the five mechanism (vacuity) checks.
--
-- IT DRIVES THE REAL ENGINE. Every card movement goes through `Engine.apply`, so a result about
-- this simulator is a result about the shipped game. There is no second copy of the card rules
-- here and there must never be one.
--
-- THE CLOCK, IN ONE PLACE BECAUSE IT IS THE THING MOST LIKELY TO BE MISREAD LATER. The simulator's
-- clock is FLOAT SECONDS, because that is what a lognormal reaction time is. The SHIPPED clock is
-- INTEGER DECISECONDS on the server (CLAUDE.md rule 5; scoring granularity 100ms). The two never
-- meet -- the engine takes no clock at all, and `Engine.apply` has no time parameter -- so a pacing
-- number from here is accurate to the MODEL and not to the shipped timebase, and any value handed
-- to Phase 4 must be rounded to deciseconds at that boundary.
--
-- VIRTUAL TIME IS A PLAIN NUMBER. `now` is advanced only by the Pacing scheduler. Nothing sleeps
-- and nothing reads a wall clock: research 11.1's throughput exists ONLY because nothing sleeps,
-- and CLAUDE.md rule 5 keeps the clock out of the engine entirely. `os.clock` is permitted in
-- `scripts/` and is not used anywhere in this file, not even for progress reporting, because a
-- second notion of time in a file about time is how the two get confused.
--
-- WHAT IS AND IS NOT CLAIMED. Amendment A7-CORRECTION: the valve eliminated OBSERVED stalls for a
-- GOOD POOL -- 0 of 4,000 rounds at k=1,j=1 and k=2,j=1 -- and reduced but did not eliminate them
-- at k=2,j=2 (21.600% to 0.025%, which may be the prototype's 20,000-action cap binding). Zero
-- stalls is a measured property of a SELECTED CONFIGURATION, never an unconditional property of the
-- engine, and nothing in this file or its output says otherwise.
--
-- WHY THE BOT POLICY AND THE REACTION-TIME MODEL ARE HERE AND NOT IN `src/server/engine/`
-- (research section 15). Both are unvalidated models of a human. In the engine they would become
-- part of its contract; here, a later measurement that says "players do not play like this" changes
-- a simulation rather than shipped logic.
local Bots = require("./Bots")
local Engine = require("../../src/server/engine/Engine")
local Invariants = require("../../src/server/engine/Invariants")
local Pool = require("../../src/server/engine/Pool")
local Rng = require("../../src/server/engine/Rng")
local Round = require("../../src/shared/Config/Round")
local Types = require("../../src/server/engine/Types")

local HAND_SIZE = Types.HAND_SIZE
local MAX_HAND = Types.MAX_HAND
local JOKER_RANK = Types.JOKER_RANK

-- ---------------------------------------------------------------------------------------------
-- Constants. Each one is either measured or derived; none is a round number picked for comfort.
-- ---------------------------------------------------------------------------------------------

-- Solvability backstop so a pathological round reports instead of hanging. `hitActionCap` is
-- recorded SEPARATELY from the time cap: it is what makes a cap artifact distinguishable from a
-- true residual livelock, and plan 02-14 re-runs every such round at ten times the cap. The
-- k=2,j=2 valve-on residual (0.025%, 1 round in 4,000) was produced under a 20,000-action cap and
-- may be the cap binding rather than a livelock the valve could not break -- which is exactly what
-- decides whether the honest claim is "zero stalls" or "zero stalls for the selected pool".
local SOLVABILITY_ACTION_CAP = 100_000

-- The reaction-time model (research 11.4, assumption A3; 02-CONTEXT's "roughly 250-900ms"):
-- lognormal with a 0.45s median and sigma 0.42 in log space, which puts ~90% of samples inside
-- [0.25, 0.90]. DO NOT CLAMP THE DISTRIBUTION -- the tail is load-bearing, because the AFK
-- auto-pass fires exactly when a sample crosses the deadline and clamping would delete the
-- mechanism this file measures.
local REACTION_MEDIAN_SECONDS = 0.45
local REACTION_SIGMA_LOG = 0.42

-- A disconnect is scheduled in ACTIONS, not seconds, so one rule serves both modes (Solvability has
-- no clock at all). The window is 20 actions per seated seeker -- 180 at a full roster against a
-- ~250-action healthy round (research 3.8) -- so a drawn leaver usually lands inside the round and
-- never lands at a point the simulator chose to make a particular outcome happen. A leaver whose
-- index falls past the end of the round simply never left, which is what a disconnect that did not
-- happen looks like.
local CHURN_ACTION_WINDOW_PER_SEAT = 20

-- The G1 bars (02-CONTEXT amendments A1, A2 and A7; research 3.7).
local MEDIAN_FIRST_MAX_SECONDS = 45
local P95_FIRST_MAX_SECONDS = 120
local OCCUPANCY_MIN = 0.60
-- Measured: good pools fire in 0.25-0.28% of rounds (4x margin below this bar) while k=2,j=2 fires
-- in 21.6% (20x above it). This is the bar that catches what a zero-stall bar cannot see --
-- k=2,j=2's valve-on stall rate is 0.025% and looks nearly fine, while a pool the engine has to
-- rescue in more than one round in five is simply the wrong pool.
local VALVE_RATE_MAX = 0.01

-- THE SWEEP'S CALIBRATION, AND ONLY THE SWEEP'S. Plan 02-10 runs 540,000 search rounds; at the
-- measured 0.005 firings/round that expects ~2,700 firings, a 135x margin over this constant.
-- Applied to a CI subset the SAME number is a coin flip: at the same mean, 4,000 gated rounds
-- expect 20.0 firings and the check would fail about 47% of runs, and 2,500 rounds expect 12.5 and
-- it would fail about 97%. A gate that fails for a reason unrelated to the thing it gates is a gate
-- that gets deleted by whoever is on call, so CI carries a DETERMINISTIC proof through
-- `MechanismEvidence` instead and never borrows this threshold. There is deliberately no
-- per-caller override: see `MechanismEvidence`.
local VALVE_MIN_FIRINGS = 20
-- Five times below the measured 0.25% valve-off stall rate, so the check keeps real margin while
-- still being a threshold rather than an exact-zero test.
local VALVE_PROOF_MIN_STALL_RATE = 0.0005
-- Measured ~2.86% of ACTIONS at a 1.0s deadline, so ~6x margin. The denominator matters: see
-- `autoPassRate` in `runCell`.
local AUTO_PASS_PROBE_MIN_RATE = 0.005

-- ---------------------------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------------------------

export type Outcome = "Cleared" | "Unsatisfiable" | "Livelock" | "CapReached" | "RosterShortfall" | "DeadPool"
export type SimMode = "Pacing" | "Solvability"
export type Sabotage = "None" | "DestroyRemovedCards"
export type CellRole = "gated" | "mechanism" | "autopass-probe" | "diagnostic"

export type SimOpts = {
	n: number, -- PLAYERS IN THE ROUND. The seat count comes from Pool.poolConfig, never from n - 1 here
	config: Types.EngineConfig, -- `antiLivelockValve = false` is the valve's mutation twin
	seed: number,
	mode: SimMode,
	autoPassSeconds: number, -- a realistic AFK deadline; math.huge disables the mechanic entirely
	churn: boolean, -- one random leaver per round
	-- HOW MANY leavers, defaulting to 1 when `churn` is true. This field is NOT decoration and it is
	-- not in plan 02-09's published interface, which carried `churn: boolean` alone. The arithmetic
	-- forced it: live = seatCount - completions - churnRemovals and remaining spoons =
	-- (seatCount - 1) - completions, so `live < remaining` reduces to `churnRemovals > 1` exactly.
	-- With one leaver the two are always EQUAL and `RosterShortfall` is structurally unreachable --
	-- so a shortfall case built on `churn = true` alone could never fail, and the category it is
	-- meant to prove separate from `CapReached` would never be exercised. The gated cells still use
	-- one leaver, which is the realistic rate and is why they see no shortfalls.
	churnLeavers: number?,
	sabotage: Sabotage, -- test-only Rule 8 violation; implemented HERE and never in src/
	identityCheck: boolean, -- full partition scan per action (fuzz-grade) vs counters-only (sweep-grade)
	actionCap: number?, -- Solvability backstop; defaults to SOLVABILITY_ACTION_CAP. Raised by triage
}

export type RoundResult = {
	outcome: Outcome,
	seed: number, -- the reproducing seed, ALWAYS present
	-- NIL IN SOLVABILITY MODE, BY CONSTRUCTION. That mode is zero-latency: `now` never advances, so
	-- a time from it would be 0 for every round, `medianFirst` would be 0 and every pacing bar would
	-- pass with a perfect score on a mode that has no clock. Returning nil instead makes
	-- `evaluateBars` fail `"no-completions"` on a Solvability cell, which is correct: the pacing bars
	-- are for Pacing cells. Plan 02-10 must not run `evaluateBars` over its Solvability cells.
	firstCompletionSeconds: number?,
	allSpoonsSeconds: number?,
	rampSeconds: number?, -- time until every seat has acted once; nil if a seat left before acting
	occupancyMean: number,
	actions: number,
	passes: number,
	autoPasses: number,
	valveFirings: number, -- state.valve.firings at the end of the round
	-- state.valve.armed at the end of the round. Plan 02-13's `afterProgress` clears the window but
	-- LEAVES `armed` true, so this reads as "this round ever armed" rather than "the valve happened
	-- to be armed when the last action landed".
	valveArmed: boolean,
	-- state.valve.seenResets: how many times VALVE_SEEN_CAP cleared the whole window. Non-zero means
	-- the valve was BLIND for part of the round, not merely quiet -- clearing the window discards
	-- exactly the evidence a longer-period cycle needs, so a trajectory whose period exceeds the cap
	-- is never detected. Plan 02-14's triage cannot honestly tell a blind valve from a working one
	-- without it, and that is the distinction the k=2,j=2 valve-on residual of 0.025% turns on.
	valveSeenResets: number,
	deadChaseInstants: number,
	dealAttempts: number,
	violation: string?, -- the classification reason, when one fired
	hitActionCap: boolean, -- true when the round ended on actionCap rather than on time or completions
}

export type OutcomeCounts = {
	Cleared: number,
	Unsatisfiable: number,
	Livelock: number,
	CapReached: number,
	RosterShortfall: number,
	DeadPool: number,
}

export type CellResult = {
	rounds: number,
	outcomes: OutcomeCounts,
	-- How many rounds contributed a time-to-first-completion. `medianFirst` and `p95First` are nil
	-- when this is 0, and `evaluateBars` fails `"no-completions"` rather than defaulting them:
	-- `nil > 45` is a runtime error and defaulting the nil to 0 makes a totally dead table PASS the
	-- pacing bar with a perfect score. Neither may happen.
	firstCompletionSamples: number,
	medianFirst: number?,
	p95First: number?,
	allSpoonsSamples: number,
	medianAll: number?,
	p95All: number?,
	rampMean: number?,
	occupancyMean: number,
	stallRate: number, -- (Unsatisfiable + Livelock + CapReached) / rounds; RosterShortfall and DeadPool EXCLUDED
	autoPassRate: number, -- auto-passes / total ACTIONS; see runCell for why not per round
	actions: number,
	passes: number,
	autoPasses: number,
	deadChaseInstants: number,
	dealAttemptMean: number,
	dealAttemptMax: number,
	valveFiringRate: number, -- fraction of ROUNDS with at least one firing
	valveFiringsMean: number,
	valveFiringsTotal: number,
	armedRate: number,
	valveSeenResetsTotal: number,
	capArtifactCandidates: { number }, -- seeds of rounds with hitActionCap == true; plan 02-14 triages them
	failingSeeds: { number }, -- non-Cleared, non-RosterShortfall seeds, capped at the first 20
	-- The pool, carried so `evaluateMechanisms` can match a gated cell to its twin on the POOL
	-- rather than re-deriving it from a label.
	config: Types.EngineConfig,
	n: number,
	k: number,
	j: number,
	jokerMode: Types.JokerMode,
	autoPassSeconds: number,
	-- Set by the caller, defaulting to "gated". `evaluateMechanisms` READS it, and plan 02-10 writes
	-- `role = "mechanism"` into its JSON, so it is a real field rather than a sweep-local
	-- annotation. A check that has to guess which cells are evidence and which are diagnostics is a
	-- check whose input set is undefined -- and an undefined input set is precisely how a vacuity
	-- check ends up satisfied by the one cell the gate exists to reject (a 400-round k=2,j=2
	-- diagnostic produces ~163 firings, which would satisfy `"valve-never-fired"` all by itself).
	role: CellRole,
}

-- How a 500-round CI subset and a 540,000-round sweep share one checker without either borrowing
-- the other's calibration. CI supplies a DETERMINISTIC proof (tests/harness/Livelock.luau driven
-- through the real Engine.apply); the sweep supplies neither boolean and is held to the statistical
-- thresholds, which are calibrated to its round count.
export type MechanismEvidence = {
	-- The fixture fired the valve and the trajectory left the cycle. OBSERVED, never a literal true.
	deterministicFiringProven: boolean,
	-- The SAME fixture with antiLivelockValve = false never escaped. OBSERVED, never a literal true.
	deterministicTwinProven: boolean,
	-- There is deliberately NO threshold-override field here. An earlier draft carried a numeric
	-- override; both callers left it nil, nothing forbade setting it to 0, and a per-caller override
	-- on a check whose whole purpose is to prevent a vacuous pass is an off switch wearing a
	-- parameter's clothes. VALVE_MIN_FIRINGS is a module constant scoped to the sweep, and a caller
	-- that needs a different calibration supplies a deterministic proof instead.
}

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

-- AMENDMENT A3'S ARITHMETIC LIVES IN EXACTLY ONE PLACE: `Pool.poolConfig`. `SimOpts` carries a full
-- `EngineConfig` so the valve-off twin is expressible, which means the simulator needs the SEAT
-- COUNT without re-deriving the config. Reading it back out of `poolConfig` and discarding the
-- throwaway config is deliberately uglier than typing `n - 1`: research OQ-B measured that
-- off-by-one as shifting the chosen configuration by a full notch, so no second site may compute
-- it. `poolConfig` also range-checks `n` against the 3..10 roster bounds, which is why an
-- out-of-range `n` errors here rather than producing a silently tiny round.
local function seatCountFor(n: number, mode: Types.JokerMode): number
	local _throwaway, seatCount = Pool.poolConfig(n, 0, 0, mode)
	return seatCount
end

local function playerIdsFor(seatCount: number): { Types.PlayerId }
	local ids: { Types.PlayerId } = {}
	for s = 1, seatCount do
		ids[s] = 100 + s
	end
	return ids
end

-- Box-Muller on two uniforms off the injected generator. One sample per call; the second normal is
-- discarded rather than cached, because caching it across calls would make a reaction time depend
-- on how many times the function had been called before and a failing seed would stop replaying.
local function reactionTime(rng: Rng.Rng): number
	local u1 = rng:nextNumber()
	local u2 = rng:nextNumber()
	if u1 <= 0 then
		-- `nextNumber` returns [0, 1); log(0) is -inf. Substituting the smallest representable step
		-- of the 32-bit generator keeps the tail finite without clamping the distribution.
		u1 = 1 / 4294967296
	end
	local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	return REACTION_MEDIAN_SECONDS * math.exp(REACTION_SIGMA_LOG * z)
end

local function quantile(sorted: { number }, fraction: number): number?
	local count = #sorted
	if count == 0 then
		return nil
	end
	local index = math.ceil(fraction * count)
	if index < 1 then
		index = 1
	end
	if index > count then
		index = count
	end
	return sorted[index]
end

local function median(sorted: { number }): number?
	local count = #sorted
	if count == 0 then
		return nil
	end
	if count % 2 == 1 then
		return sorted[(count + 1) // 2]
	end
	return (sorted[count // 2] + sorted[count // 2 + 1]) / 2
end

local function emptyCounts(): OutcomeCounts
	return {
		Cleared = 0,
		Unsatisfiable = 0,
		Livelock = 0,
		CapReached = 0,
		RosterShortfall = 0,
		DeadPool = 0,
	}
end

-- ---------------------------------------------------------------------------------------------
-- runRound
-- ---------------------------------------------------------------------------------------------

local function runRound(opts: SimOpts): RoundResult
	if opts.sabotage ~= "None" and opts.identityCheck then
		-- These two options contradict each other and the contradiction must be LOUD rather than
		-- producing a confusing engine error. Destroying a routed card IS a conservation violation,
		-- so `Invariants.check` correctly reports `circulation` on the very next action and the
		-- simulator correctly errors on any `check` violation. The sabotage path exists to prove the
		-- SATISFIABILITY tripwire can fire, which is read from the predicate.
		error("Simulator.runRound: sabotage and identityCheck contradict; a destroyed card IS a check violation", 0)
	end

	local seatCount = seatCountFor(opts.n, opts.config.jokerMode)
	-- `spoons = n - 2`, so required completions = `seatCount - 1` = `n - 2`, which leaves exactly one
	-- empty-handed seeker. That seeker is a shipping state, not a bug (research 7.2).
	local requiredCompletions = seatCount - 1

	local valid, reason = Pool.validate(opts.config, seatCount)
	if not valid then
		-- Research 3.1's corollary: k=0, j=0 is a PROVABLE instant deadlock (circulation = 4k + j =
		-- 0) and that cell must be excluded by an asserting RESULT, never by a silent skip and never
		-- by a crash. The reason string is carried through so the sweep can report the category.
		return {
			outcome = "DeadPool",
			seed = opts.seed,
			firstCompletionSeconds = nil,
			allSpoonsSeconds = nil,
			rampSeconds = nil,
			occupancyMean = 0,
			actions = 0,
			passes = 0,
			autoPasses = 0,
			valveFirings = 0,
			valveArmed = false,
			valveSeenResets = 0,
			deadChaseInstants = 0,
			dealAttempts = 0,
			violation = reason,
			hitActionCap = false,
		}
	end

	-- `Pool.deal`'s attempt count is the deal-attempt metric (research 10; 02-07-SUMMARY says to
	-- read it from `Pool.deal` and not from `State`, which deliberately does not carry it). The deal
	-- is a pure function of (config, seatCount, seed), so replaying it on a FRESH generator with the
	-- same seed observes exactly the attempt count `Engine.newRound` is about to pay. The
	-- alternative -- threading an out-parameter through `newRound` -- would change the engine's
	-- contract to serve a metric.
	local _rankOf, dealAttempts = Pool.deal(opts.config, seatCount, Rng.new(opts.seed))

	local dealRng = Rng.new(opts.seed)
	local state = Engine.newRound(opts.config, playerIdsFor(seatCount), dealRng)
	-- The simulator's own draws (reaction times, the auto-pass choice, the churn schedule) come off
	-- a generator DERIVED from the deal's, so a simulator draw can never shift the deal while the
	-- whole round stays a function of one seed.
	local simRng = Rng.new(dealRng:nextUint())

	local now = 0.0
	local actions, passes, autoPasses = 0, 0, 0
	local occupancySum, occupancySamples = 0.0, 0
	local deadChaseInstants = 0
	local firstCompletionSeconds: number? = nil
	local allSpoonsSeconds: number? = nil
	local rampSeconds: number? = nil
	local acted: { [Types.SeatId]: true } = {}
	local actedCount = 0
	local violation: string? = nil
	local actionCap = opts.actionCap or SOLVABILITY_ACTION_CAP

	-- EXACT CYCLE DETECTION, AND ONLY WHERE IT IS SOUND. A repeated (state hash, round-robin cursor)
	-- is a literal cycle in the state graph, so `Livelock` is reported WITH PROOF rather than on a
	-- timeout. It is sound only where the dynamics are deterministic, which is why this runs in
	-- strict round-robin Solvability mode and why Pacing relies on the 300s cap instead.
	--
	-- IT ALSO REQUIRES THE VALVE TO BE OFF, and that correction matters. With the valve ENABLED the
	-- dynamics are not deterministic -- the valve draws from its own generator and forces a pass --
	-- so a repeated hash is NOT a proof of non-termination: the engine is about to break it. Worse,
	-- the detector would always win the race: it fires at the FIRST repeat (action 17 in the
	-- Livelock fixture) while the valve's arm gate needs 48 actions per live seat (96 there, firing
	-- at 113). So running detection with the valve on would report `Livelock` for rounds the engine
	-- provably escapes, and the valve's whole measured effect would be invisible. With the valve on,
	-- Solvability terminates on the action cap and `hitActionCap` tells plan 02-14 which it was.
	local detectCycles = opts.mode == "Solvability" and not opts.config.antiLivelockValve
	local seen: { [string]: true } = {}

	local churnActions: { number } = {}
	if opts.churn then
		local leavers = opts.churnLeavers or 1
		for _ = 1, leavers do
			table.insert(churnActions, simRng:nextInt(1, CHURN_ACTION_WINDOW_PER_SEAT * seatCount))
		end
		table.sort(churnActions)
	end
	local churnIndex = 1

	local function finish(outcome: Outcome, hitCap: boolean): RoundResult
		return {
			outcome = outcome,
			seed = opts.seed,
			firstCompletionSeconds = firstCompletionSeconds,
			allSpoonsSeconds = allSpoonsSeconds,
			rampSeconds = rampSeconds,
			occupancyMean = if occupancySamples > 0 then occupancySum / occupancySamples else 0,
			actions = actions,
			passes = passes,
			autoPasses = autoPasses,
			valveFirings = state.valve.firings,
			valveArmed = state.valve.armed,
			valveSeenResets = state.valve.seenResets,
			deadChaseInstants = deadChaseInstants,
			dealAttempts = dealAttempts,
			violation = violation,
			hitActionCap = hitCap,
		}
	end

	local function canAct(seat: Types.Seat): boolean
		return seat.live and (#seat.hand == MAX_HAND or (#seat.hand == HAND_SIZE and #seat.inbox >= 1))
	end

	-- MEAN SEAT OCCUPANCY, SAMPLED AT EVERY ACTION INSTANT (research 3.7). Median
	-- time-to-first-completion provably cannot see a table where nobody has anything to do;
	-- occupancy can, and it costs one counter. Without this bar the selection rule picks k=0, j=1 --
	-- ONE single card circulating among nine seats, a 14% occupancy table at 10 players that passes
	-- every other bar while being barely a game.
	--
	-- The dead-rank chase (research Pitfall 2) is sampled in the same pass, behind an O(1) gate. A
	-- seat can only chase a rank it holds at least 2 of, so only ranks with 2 or 3 copies in play
	-- can be chased, and a rank is dead when `rankInPlay[r] + jokersInPlay < 4`. The histogram
	-- answers "is any such rank dead" in constant time, and at the deal the answer is always no
	-- (every rank starts with four copies in play), so the per-seat scan runs only after a
	-- completion has actually killed a rank.
	local function sampleInstant()
		local liveCount = state.liveCount
		if liveCount <= 0 then
			return
		end
		local busy = 0
		for _, seat in state.seats do
			if canAct(seat) then
				busy += 1
			end
		end
		occupancySum += busy / liveCount
		occupancySamples += 1

		local counters = state.counters
		local chaseable = 0
		for copies = 2, 3 - counters.jokersInPlay do
			chaseable += counters.cnt[copies + 1] or 0
		end
		if chaseable == 0 then
			return
		end
		for _, seat in state.seats do
			if not seat.live then
				continue
			end
			local held: { [Types.Rank]: number } = {}
			local chasing = false
			for _, id in seat.hand do
				local rank = state.rankOf[id]
				if rank == JOKER_RANK then
					continue
				end
				local count = (held[rank] or 0) + 1
				held[rank] = count
				if count >= 2 and counters.rankInPlay[rank] + counters.jokersInPlay < 4 then
					chasing = true
					break
				end
			end
			if chasing then
				deadChaseInstants += 1
			end
		end
	end

	-- `sabotage = "DestroyRemovedCards"`: the Rule 8 VIOLATION, implemented HERE and never in `src/`,
	-- so no shipped code path can destroy a card. The routed cards are the last `cards` entries of
	-- the successor's inbox (`Ring.removeSeat`'s locked dump order appends them to the tail), so
	-- deleting them and decrementing the in-play counters is exactly "a removed seat's cards were
	-- destroyed instead of routed". It exists to prove the satisfiability tripwire AND the gate
	-- itself can fail: research 3.4 measured it firing UNSATISFIABLE in 2.9-5.7% of churned rounds
	-- against 0.0% on the honest path.
	local function destroyRouted(routedTo: Types.SeatId, cards: number)
		local inbox = state.seats[routedTo].inbox
		local counters = state.counters
		for _ = 1, cards do
			local id = table.remove(inbox)
			if id == nil then
				break
			end
			local rank = state.rankOf[id]
			if rank == JOKER_RANK then
				counters.jokersInPlay -= 1
			else
				local copies = counters.rankInPlay[rank]
				counters.cnt[copies + 1] = (counters.cnt[copies + 1] or 0) - 1
				counters.rankInPlay[rank] = copies - 1
				counters.cnt[copies] = (counters.cnt[copies] or 0) + 1
			end
		end
	end

	-- Applies one intent and returns a TERMINAL outcome or nil. The caller has already sampled the
	-- instant and advanced `now`.
	-- Returns a finished `RoundResult` when the action ended the round, or nil to keep playing.
	-- It returns the RESULT rather than the outcome string because Luau's `~= nil` refinement widens
	-- an optional union of string singletons back to `string`, so `Outcome?` could not be handed to
	-- `finish` without a cast -- and a cast on the one value that decides a round's category is
	-- exactly where a cast should not be.
	local function execute(intent: Types.Intent, cursorAfter: Types.SeatId): RoundResult?
		local result = Engine.apply(state, intent)
		if not result.ok then
			-- The simulator only ever offers intents it has just checked are legal, so a rejection
			-- is a simulator bug and must be loud: averaged into a stall rate it would look like a
			-- pool problem.
			error(
				`Simulator: the engine rejected a {intent.kind} the simulator believed legal `
					.. `({tostring(result.reject)}, seat {intent.seat}, seed {opts.seed})`,
				0
			)
		end
		actions += 1
		if acted[intent.seat] == nil and intent.kind ~= "Remove" then
			acted[intent.seat] = true
			actedCount += 1
			if actedCount == seatCount and opts.mode == "Pacing" then
				rampSeconds = now
			end
		end

		local progressed = false
		for _, event in result.events do
			if event.kind == "Passed" then
				passes += 1
			elseif event.kind == "Completed" then
				progressed = true
				if firstCompletionSeconds == nil and opts.mode == "Pacing" then
					firstCompletionSeconds = now
				end
			elseif event.kind == "SeatRemoved" then
				progressed = true
				if opts.sabotage == "DestroyRemovedCards" and event.routedTo ~= nil and event.cards > 0 then
					destroyRouted(event.routedTo, event.cards)
				end
			end
		end

		if opts.identityCheck then
			local ok, why = Invariants.check(state)
			if not ok then
				-- A CONSERVATION BREAK IS AN ENGINE BUG, NOT A ROUND OUTCOME, and must not be
				-- averaged into a stall rate. `check`'s violation ORDER is locked and must never be
				-- reordered to make a name come out: that would make every genuine conservation bug
				-- surface as a stall statistic instead of an error.
				error(`Simulator: Invariants.check reported {tostring(why)} at action {actions}, seed {opts.seed}`, 0)
			end
		end

		-- 1. THE COMPLETION TARGET FIRST. `requiredCompletions = seatCount - 1 = n - 2` leaves exactly
		-- one empty-handed seeker. It is checked before the satisfiability predicate because a round
		-- that has claimed every spoon has nothing left to satisfy -- `Invariants.satisfiable` itself
		-- returns true at `liveCount == 0` for the same reason -- and the round ENDS here, so nothing
		-- can observe the residual multiset.
		if state.counters.completions >= requiredCompletions then
			if opts.mode == "Pacing" then
				allSpoonsSeconds = now
			end
			return finish("Cleared", false)
		end

		-- 2. `Unsatisfiable`, classified from the PREDICATE and never from `check`'s violation NAME.
		-- `check` returns the FIRST violation in a locked order: `circulation` is violation 4 while
		-- `unsatisfiable` is violation 9, so a state whose cards were destroyed reports
		-- `"circulation"` and `check` never reaches the satisfiability test. A simulator that waited
		-- for that name would classify every destroyed-card round as a conservation error and the
		-- sabotage proof would be testing the wrong thing.
		if state.liveCount >= 1 and not Invariants.satisfiable(state) then
			violation = "satisfiable-false"
			return finish("Unsatisfiable", false)
		end

		-- 3. `RosterShortfall` -- its OWN category, and NOT a stall (research Pitfall 8). Counting it
		-- would make the gate tighten the pool for a Phase 6 lifecycle reason that has nothing to do
		-- with cards. `liveCount == 0` with the target unmet falls out of the same inequality.
		local remainingSpoons = requiredCompletions - state.counters.completions
		if state.liveCount < remainingSpoons then
			violation = "roster-shortfall"
			return finish("RosterShortfall", false)
		end

		-- 4. `Livelock` -- a literal cycle in the state graph, with proof. The seen-set is cleared on
		-- every completion AND every removal, which is SOUNDNESS and not economy: both change the
		-- state space (a removal adds 4 to circulation), so a hash recorded before one can never
		-- legitimately recur afterwards and keeping it would fire on a state that is not a cycle at
		-- all. This is the same rule `Valve.afterProgress` follows, and the two must agree.
		if detectCycles then
			if progressed then
				seen = {}
			else
				local key = `{Invariants.hash(state)}@{cursorAfter}`
				if seen[key] ~= nil then
					violation = "state-cycle"
					return finish("Livelock", false)
				end
				seen[key] = true
			end
		end

		return nil
	end

	-- A disconnect, as one generic removal (CLAUDE.md rule 8). The victim is drawn uniformly from
	-- the LIVE seats, so a seat that already completed is never "disconnected".
	local function maybeChurn(): RoundResult?
		while churnIndex <= #churnActions and churnActions[churnIndex] <= actions + 1 do
			churnIndex += 1
			if state.liveCount < 1 then
				break
			end
			local liveIds: { Types.SeatId } = {}
			for _, seat in state.seats do
				if seat.live then
					table.insert(liveIds, seat.id)
				end
			end
			local victim = liveIds[simRng:nextInt(1, #liveIds)]
			sampleInstant()
			local terminal = execute({ kind = "Remove", seat = victim, cause = "Disconnected" }, 0)
			if terminal ~= nil then
				return terminal
			end
		end
		return nil
	end

	-- MODE: Solvability (zero-latency; the theorem re-check and the worst-case curve). Strict
	-- round-robin from the dealer in seat order; each seat takes its ONE legal action when its turn
	-- comes and is skipped when it has none. `greedyPass` always, `autoPassSeconds` ignored, `now`
	-- never advances. The cursor walks seat INDICES rather than `next` links, because a removed
	-- seat's links point at itself by design and a cursor sitting on one would have nowhere to go.
	if opts.mode == "Solvability" then
		local cursor = 1 -- the dealer (SeatOrder, plan 02-02)
		while true do
			local churned = maybeChurn()
			if churned ~= nil then
				return churned
			end
			if state.liveCount == 0 then
				-- The ring emptied without the target being met; the inequality in `execute` has
				-- already classified every path that gets here, so this is the churn-at-liveCount-1
				-- case only.
				violation = "ring-emptied"
				return finish("RosterShortfall", false)
			end
			if actions >= actionCap then
				return finish("CapReached", true)
			end

			local chosen: Types.SeatId? = nil
			for step = 0, seatCount - 1 do
				local candidate = ((cursor - 1 + step) % seatCount) + 1
				if canAct(state.seats[candidate]) then
					chosen = candidate
					break
				end
			end
			if chosen == nil then
				if Invariants.circulation(state) >= 1 then
					-- THE LIVENESS INVARIANT (research section 5). Once every live hand holds 4 or 5
					-- cards, circulation >= 1 forces some seat to hold 5 or to hold 4 with a
					-- non-empty inbox, so this is unreachable and means the ring is corrupt.
					error(`Simulator: no live seat can act while circulation >= 1 (seed {opts.seed})`, 0)
				end
				-- Circulation reached zero with seats still live. Unreachable on the honest path,
				-- where circulation is constant and >= 1: only the sabotage path can destroy a card.
				-- The table is frozen with the target unmet, which is a stall by any reading, so it
				-- is reported as one rather than as a success.
				violation = "circulation-zero"
				return finish("CapReached", false)
			end

			local seat = state.seats[chosen]
			local intent: Types.Intent = if #seat.hand == MAX_HAND
				then { kind = "Pass", seat = chosen, cardId = Bots.greedyPass(state, chosen) }
				else { kind = "Draw", seat = chosen }
			local nextCursor = (chosen % seatCount) + 1
			sampleInstant()
			local done = execute(intent, nextCursor)
			cursor = nextCursor
			if done ~= nil then
				return done
			end
		end
	end

	-- MODE: Pacing (the G1-gated population). An event-driven schedule with no sleep: a live seat
	-- with a legal action and no pending wake is scheduled at `now + reactionTime()`; a seat with no
	-- legal action is not scheduled and becomes schedulable the moment a pass lands in its inbox.
	--
	-- THE AFK AUTO-PASS (CARD-16, as modelled). When a seat holds MAX_HAND it must pass, so its
	-- reaction time `r` is drawn against the pass deadline: at `r <= autoPassSeconds` it passes its
	-- `greedyPass` choice at `now + r`; past the deadline the shipped mechanic fires and it passes a
	-- `randomPass` choice at `now + autoPassSeconds`, counting an auto-pass. A DRAW carries no
	-- deadline, because the deadline is about a locked pile.
	--
	-- THE MECHANISM THE GATE RESTS ON IS NOT THIS ONE. A livelocked greedy table is not idle --
	-- every seat is drawing and passing on schedule -- so an auto-pass that fires on inaction fires
	-- exactly as often as the reaction-time tail crosses the deadline and no more: measured 2.86% of
	-- actions at a 1.0s deadline, 1.67% at 1.1s, 0.21% at 1.5s, 0.019% at 2.0s, 0.0003% at 3.0s and
	-- ~0 at 5s and beyond. The deviation cliff is near 0.03% per pass, so only deadlines around
	-- 1.0-1.5s clear it -- and a 1.5-second pass deadline is NOT an AFK mechanic: CARD-16 auto-passes
	-- an idle player and benches them after repeated strikes, so at that deadline it would be
	-- striking ordinary players several times a round. At any deadline a real AFK feature would use,
	-- this mechanism fires essentially never. That is why amendment A7 moved the zero-stall job into
	-- the engine's valve and demoted auto-pass to a secondary mitigation whose deadline is now free
	-- to take a realistic product value. Its rate is still reported, as margin evidence.
	-- `autoPassSeconds = math.huge` disables it, which is one half of the pure-greedy worst case
	-- that must still be reported alongside the verdict (the other half is `antiLivelockValve =
	-- false`).
	local wakeAt: { [Types.SeatId]: number } = {}
	local wakeAuto: { [Types.SeatId]: boolean } = {}

	local function reschedule()
		for _, seat in state.seats do
			if not canAct(seat) then
				wakeAt[seat.id] = nil
				wakeAuto[seat.id] = nil
				continue
			end
			if wakeAt[seat.id] ~= nil then
				continue
			end
			local r = reactionTime(simRng)
			if #seat.hand == MAX_HAND and r > opts.autoPassSeconds then
				wakeAt[seat.id] = now + opts.autoPassSeconds
				wakeAuto[seat.id] = true
			else
				wakeAt[seat.id] = now + r
				wakeAuto[seat.id] = false
			end
		end
	end

	while true do
		local churned = maybeChurn()
		if churned ~= nil then
			return churned
		end
		if state.liveCount == 0 then
			violation = "ring-emptied"
			return finish("RosterShortfall", false)
		end
		if actions >= actionCap then
			return finish("CapReached", true)
		end
		reschedule()

		local chosen: Types.SeatId? = nil
		local soonest = math.huge
		for _, seat in state.seats do
			local at = wakeAt[seat.id]
			-- Ties by the lower seat id, so equal wake times (two auto-passes at the same deadline)
			-- resolve deterministically.
			if at ~= nil and at < soonest then
				soonest = at
				chosen = seat.id
			end
		end
		if chosen == nil then
			if Invariants.circulation(state) >= 1 then
				error(`Simulator: no live seat can act while circulation >= 1 (seed {opts.seed})`, 0)
			end
			violation = "circulation-zero"
			return finish("CapReached", false)
		end
		if soonest >= Round.ROUND_CAP_SECONDS then
			-- The 300s cap (PROJECT.md, `src/shared/Config/Round.luau`). Taken from the config rather
			-- than typed here. `CapReached` as defined also closes a gap in 02-CONTEXT's locked stall
			-- definition: "a round that hits the cap with ZERO completions" does not catch the
			-- realistic failure of 6 of 8 spoons claimed and then a livelock, and the multiset clause
			-- does not catch it either, because the multiset is still satisfiable. That refinement
			-- sits inside CONTEXT's "precise structural-deadlock predicate" discretion and is not a
			-- change to the locked definition.
			violation = "time-cap"
			return finish("CapReached", false)
		end

		now = soonest
		local seat = state.seats[chosen]
		local intent: Types.Intent
		if #seat.hand == MAX_HAND then
			local auto = wakeAuto[chosen] == true
			local cardId = if auto then Bots.randomPass(state, chosen, simRng) else Bots.greedyPass(state, chosen)
			if auto then
				autoPasses += 1
			end
			intent = { kind = "Pass", seat = chosen, cardId = cardId }
		else
			intent = { kind = "Draw", seat = chosen }
		end
		wakeAt[chosen] = nil
		wakeAuto[chosen] = nil
		sampleInstant()
		local done = execute(intent, 0)
		if done ~= nil then
			return done
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- runCell
-- ---------------------------------------------------------------------------------------------

local FAILING_SEED_CAP = 20

-- Runs `rounds` rounds at `seed = opts.seed + i` and aggregates. `role` defaults to "gated"; plan
-- 02-10 passes "mechanism" for its valve-off twins and "autopass-probe" for its probe.
local function runCell(opts: SimOpts, rounds: number, role: CellRole?): CellResult
	local seatCount = seatCountFor(opts.n, opts.config.jokerMode)
	local counts = emptyCounts()
	local firsts: { number } = {}
	local alls: { number } = {}
	local ramps: { number } = {}
	local occupancySum = 0.0
	local actions, passes, autoPasses = 0, 0, 0
	local deadChaseInstants = 0
	local dealAttemptSum, dealAttemptMax = 0, 0
	local valveFiringsTotal, valveFiringRounds, armedRounds, seenResetsTotal = 0, 0, 0, 0
	local capArtifactCandidates: { number } = {}
	local failingSeeds: { number } = {}

	for i = 1, rounds do
		local roundOpts = table.clone(opts)
		roundOpts.seed = opts.seed + i
		local r = runRound(roundOpts)
		counts[r.outcome] += 1
		if r.firstCompletionSeconds ~= nil then
			table.insert(firsts, r.firstCompletionSeconds)
		end
		if r.allSpoonsSeconds ~= nil then
			table.insert(alls, r.allSpoonsSeconds)
		end
		if r.rampSeconds ~= nil then
			table.insert(ramps, r.rampSeconds)
		end
		occupancySum += r.occupancyMean
		actions += r.actions
		passes += r.passes
		autoPasses += r.autoPasses
		deadChaseInstants += r.deadChaseInstants
		dealAttemptSum += r.dealAttempts
		if r.dealAttempts > dealAttemptMax then
			dealAttemptMax = r.dealAttempts
		end
		valveFiringsTotal += r.valveFirings
		if r.valveFirings >= 1 then
			valveFiringRounds += 1
		end
		if r.valveArmed then
			armedRounds += 1
		end
		seenResetsTotal += r.valveSeenResets
		if r.hitActionCap then
			table.insert(capArtifactCandidates, r.seed)
		end
		if r.outcome ~= "Cleared" and r.outcome ~= "RosterShortfall" and #failingSeeds < FAILING_SEED_CAP then
			-- Capped so a broken cell does not print a thousand lines, and the cap is stated rather
			-- than silent: `capArtifactCandidates` and the outcome counts carry the full picture.
			table.insert(failingSeeds, r.seed)
		end
	end

	table.sort(firsts)
	table.sort(alls)
	local rampMean: number? = nil
	if #ramps > 0 then
		local sum = 0.0
		for _, value in ramps do
			sum += value
		end
		rampMean = sum / #ramps
	end

	return {
		rounds = rounds,
		outcomes = counts,
		firstCompletionSamples = #firsts,
		medianFirst = median(firsts),
		p95First = quantile(firsts, 0.95),
		allSpoonsSamples = #alls,
		medianAll = median(alls),
		p95All = quantile(alls, 0.95),
		rampMean = rampMean,
		occupancyMean = if rounds > 0 then occupancySum / rounds else 0,
		-- `RosterShortfall` and `DeadPool` are EXCLUDED: the first is a Phase 6 lifecycle matter
		-- (research Pitfall 8) and the second is a configuration error, and counting either would
		-- tune the pool for a reason that has nothing to do with cards.
		stallRate = if rounds > 0 then (counts.Unsatisfiable + counts.Livelock + counts.CapReached) / rounds else 0,
		-- AUTO-PASSES DIVIDED BY TOTAL ACTIONS, NEVER BY ROUNDS. The measured 2.86% at a 1.0s
		-- deadline is a fraction of ACTIONS, so `AUTO_PASS_PROBE_MIN_RATE = 0.005` and its ~6x
		-- margin only mean anything against that denominator. A per-round denominator would inflate
		-- it by roughly the action count per round -- about 250 at a full roster -- and the probe bar
		-- would pass on a mechanism that fired twice.
		autoPassRate = if actions > 0 then autoPasses / actions else 0,
		actions = actions,
		passes = passes,
		autoPasses = autoPasses,
		deadChaseInstants = deadChaseInstants,
		dealAttemptMean = if rounds > 0 then dealAttemptSum / rounds else 0,
		dealAttemptMax = dealAttemptMax,
		valveFiringRate = if rounds > 0 then valveFiringRounds / rounds else 0,
		valveFiringsMean = if rounds > 0 then valveFiringsTotal / rounds else 0,
		valveFiringsTotal = valveFiringsTotal,
		armedRate = if rounds > 0 then armedRounds / rounds else 0,
		valveSeenResetsTotal = seenResetsTotal,
		capArtifactCandidates = capArtifactCandidates,
		failingSeeds = failingSeeds,
		config = opts.config,
		n = opts.n,
		k = opts.config.ranks - seatCount,
		j = opts.config.jokers,
		jokerMode = opts.config.jokerMode,
		autoPassSeconds = opts.autoPassSeconds,
		role = role or "gated",
	}
end

-- ---------------------------------------------------------------------------------------------
-- The gate
-- ---------------------------------------------------------------------------------------------

-- The per-cell G1 bars. Failures are NAMED STRINGS, never bare booleans, and NO BAR IS EVER
-- COMPUTED FROM A NIL.
local function evaluateBars(cell: CellResult): (boolean, { string })
	local failures: { string } = {}

	-- 0. A cell in which nothing ever completed has `medianFirst == nil`, and both obvious handlings
	-- are wrong: `nil > 45` is a runtime error, and defaulting the nil to 0 makes a totally dead
	-- table PASS the pacing bar with a perfect score. So the absence of completions is its own named
	-- failure, and it returns BEFORE any median is touched.
	if cell.firstCompletionSamples == 0 then
		return false, { "no-completions" }
	end

	-- 1. ZERO stalls, not a low rate: one stalled round wastes five minutes for up to ten people, so
	-- a rate target would be accepting a known defect.
	if cell.stallRate > 0 then
		table.insert(failures, "stalls")
	end

	-- 2. The stalls bar derived from the OTHER side. If `stallRate` is 0 then every eligible round
	-- cleared, so the two can only disagree if the outcome accounting is broken -- worth catching for
	-- the same reason `Invariants` derives one side of conservation independently.
	local eligible = cell.rounds - cell.outcomes.DeadPool - cell.outcomes.RosterShortfall
	if cell.outcomes.Cleared < eligible then
		table.insert(failures, "cleared-fraction")
	end

	local medianFirst = cell.medianFirst
	if medianFirst ~= nil and medianFirst > MEDIAN_FIRST_MAX_SECONDS then
		table.insert(failures, "median-first")
	end
	local p95First = cell.p95First
	if p95First ~= nil and p95First > P95_FIRST_MAX_SECONDS then
		table.insert(failures, "p95-first")
	end

	-- 4. Amendment A2 and research 3.7. Without this bar the selection rule picks k=0, j=1: one
	-- single card circulating among nine seats, a 14% occupancy table at 10 players that passes the
	-- other bars while being barely a game.
	if cell.occupancyMean < OCCUPANCY_MIN then
		table.insert(failures, "occupancy")
	end

	-- 5. A pool whose valve fires often is a bad pool EVEN AT ZERO STALLS.
	if cell.valveFiringRate > VALVE_RATE_MAX then
		table.insert(failures, "valve-rate")
	end

	return #failures == 0, failures
end

-- THE MECHANISM CHECKS -- the vacuity checks, as a property of a SET of cells plus an explicit
-- evidence record. The returned `pass` MUST be ANDed into the caller's verdict: these are NOT
-- informational, and NONE of them is an exact-zero test.
--
-- WHY `evidence` EXISTS. A threshold is only a threshold RELATIVE TO A ROUND COUNT (see
-- VALVE_MIN_FIRINGS). So the statistical thresholds belong to the SWEEP, CI proves the same facts
-- DETERMINISTICALLY, and the `evidence` record is where CI says which proof it is carrying. Each
-- valve bar below is an explicit either/or -- deterministic evidence OR a statistic -- and never a
-- statistic borrowed across two round counts.
--
-- WHY THE SHAPE IS THIS AND NOT SIMPLER. The first draft of this gate had an `autoPassRate == 0`
-- check that was both informational and an exact-zero test, so it could never fire at a finite
-- deadline over hundreds of thousands of rounds. That is the same defect class Phase 1 verification
-- found twice. A mechanism check must (a) have a threshold with margin OR a deterministic proof,
-- calibrated to the round count it is actually applied at, (b) flip the `pass` boolean, and (c) have
-- its own mutation case reported as a FAILURE naming the bar. All five bars here have all three.
local function evaluateMechanisms(cells: { CellResult }, evidence: MechanismEvidence): (boolean, { string })
	local failures: { string } = {}

	local gated: { CellResult } = {}
	local twins: { CellResult } = {}
	local probe: CellResult? = nil
	local firingsTotal = 0
	for _, cell in cells do
		if cell.role == "gated" then
			table.insert(gated, cell)
		end
		if cell.role == "autopass-probe" and probe == nil then
			probe = cell
		end
		if cell.config.antiLivelockValve then
			firingsTotal += cell.valveFiringsTotal
		else
			table.insert(twins, cell)
		end
	end

	-- A gate that passes because the mechanism never ran is passing on pure greedy. The threshold is
	-- not `== 0`, because at a 0.25% firing rate an exact-zero test cannot fire in any short run --
	-- the defect this replaces -- and it is not applied to CI, because at CI's round count it is
	-- noise rather than a bar.
	if not evidence.deterministicFiringProven and firingsTotal < VALVE_MIN_FIRINGS then
		table.insert(failures, "valve-never-fired")
	end

	-- THE MATCHING RULE IS SET-LEVEL AND POOL-KEYED, and `n` is deliberately NOT part of the match:
	-- the twin's job is to show the valve is load-bearing at a POOL, and the pool is (k, j,
	-- jokerMode). Read per gated cell instead, plan 02-10's confirm stage fails BY CONSTRUCTION --
	-- it emits 32 gated cells spanning N=3..10 against 4 twins, all of them at N=10 -- and since
	-- this result is ANDed into the sweep CLI's exit code, that reading makes a 20-to-40-minute run
	-- exit non-zero every time for a reason that is not a defect.
	local matched: { CellResult } = {}
	for _, twin in twins do
		for _, g in gated do
			if twin.k == g.k and twin.j == g.j and twin.jokerMode == g.jokerMode then
				table.insert(matched, twin)
				break
			end
		end
	end

	if not evidence.deterministicTwinProven then
		if #matched == 0 then
			table.insert(failures, "valve-twin-missing")
		end
		-- THE "AT LEAST ONE MATCHED TWIN" CLAUSE IS NOT DECORATION. Written as "every matched twin
		-- stalls" alone, a forall over an EMPTY set is TRUE, so a cell set with no twin at all would
		-- satisfy this bar vacuously -- which is exactly the set the missing-twin mutation case hands
		-- it and expects it to FIRE. `"valve-twin-missing"` would still fire there, but this bar
		-- would be satisfied in precisely the situation it exists to catch, and the two bars would
		-- no longer be independent.
		local loadBearing = #matched >= 1
		for _, twin in matched do
			if twin.stallRate < VALVE_PROOF_MIN_STALL_RATE then
				loadBearing = false
			end
		end
		if not loadBearing then
			table.insert(failures, "valve-not-load-bearing")
		end
	end

	-- A MISSING PROBE IS A FAILURE, NOT A SKIP. Without this bar `"autopass-never-fired"` is the one
	-- mechanism bar with no mutation case: the natural implementation is "find the probe cell; if it
	-- is nil, skip", that passes silently, and so deleting the probe cell deletes the check.
	if probe == nil then
		table.insert(failures, "autopass-probe-missing")
	elseif probe.autoPassRate < AUTO_PASS_PROBE_MIN_RATE then
		-- A PROBE and not a check on the gated cells: at a realistic AFK deadline the auto-pass
		-- correctly fires almost never, so requiring it to fire in the gated cells would be requiring
		-- the shipped product to be wrong.
		table.insert(failures, "autopass-never-fired")
	end

	return #failures == 0, failures
end

return {
	runRound = runRound,
	runCell = runCell,
	evaluateBars = evaluateBars,
	evaluateMechanisms = evaluateMechanisms,
	SOLVABILITY_ACTION_CAP = SOLVABILITY_ACTION_CAP,
	MEDIAN_FIRST_MAX_SECONDS = MEDIAN_FIRST_MAX_SECONDS,
	P95_FIRST_MAX_SECONDS = P95_FIRST_MAX_SECONDS,
	OCCUPANCY_MIN = OCCUPANCY_MIN,
	VALVE_RATE_MAX = VALVE_RATE_MAX,
	VALVE_MIN_FIRINGS = VALVE_MIN_FIRINGS,
	VALVE_PROOF_MIN_STALL_RATE = VALVE_PROOF_MIN_STALL_RATE,
	AUTO_PASS_PROBE_MIN_RATE = AUTO_PASS_PROBE_MIN_RATE,
}
