--!strict
-- sweep: the staged Gate G1 sweep CLI (CARD-11, CARD-12).
--
--   lune run scripts/sim/sweep.luau -- [--stage search|confirm|mechanism|triage|both] [--rounds N]
--                                      [--out DIR] [--pool k,j,mode,autoPassSeconds]
--                                      [--seeds LIST] [--cap N] [--n N]
--
-- THIS FILE ADDS NO SIMULATION LOGIC. Every number comes from `Simulator.runCell` / `runRound` and
-- every mechanism verdict from `Simulator.evaluateMechanisms`; a second copy of either would let
-- the sweep and the CI subset disagree about what passing means. There is no bot policy, no
-- reaction-time model and no card rule in here.
--
-- WHAT EACH STAGE IS, AND WHICH ONE PRODUCES A VERDICT.
--   search     the 1,000-round grid that LOCATES the passing region. It is a search, not a gate.
--              A bare `--stage search` run prints `SEARCH ONLY - NOT A VERDICT`, writes no
--              selection block, and is NOT judged by the mechanism checks: the search grid
--              contains no valve-disabled twin and no auto-pass probe by construction, so running
--              those checks over it would report three failures about a stage that never claimed
--              to prove any of them.
--   mechanism  the valve-disabled twins (the proof the valve is load-bearing) and the auto-pass
--              probe. This is the ONLY place in the phase where the twin stall RATE, the firing
--              rate of a thin pool and the firing COUNT behind `VALVE_MIN_FIRINGS` are measured:
--              plan 02-09's CI subset carries a DETERMINISTIC fixture proof instead, because at
--              500 rounds each of those statistics is noise rather than a bar.
--   confirm    the locked 10,000-rounds-per-cell bar, applied to the configuration that ships.
--   triage     re-runs named seeds at a raised action cap to separate a cap artefact from a true
--              residual livelock. It writes ONLY `02-triage.json`.
--   both       search, then mechanism, then confirm, in ONE process against ONE in-memory table.
--
-- `both` IS THE ONLY INVOCATION THAT PRODUCES A VERDICT, and that is a property of the evidence
-- set rather than a convention. `evaluateMechanisms` is a check on a SET of cells and only a
-- `both` run emits every kind of cell it reads. A bare `mechanism` or `confirm` run is therefore a
-- labelled diagnostic SUB-STAGE whose construction failures are named in advance:
--   bare `mechanism`  fails `valve-twin-missing` and `valve-not-load-bearing` -- it emits no gated
--                     cell at all, so `matched` is empty and both bars fire. (At a small
--                     `--rounds` it also fails `valve-never-fired`; at the real 1,000-round probe
--                     it does not, because the measured firing rate puts ~145 firings in that one
--                     cell against `VALVE_MIN_FIRINGS = 20`. Plan 02-10's table predicted ~5
--                     firings from the prototype's rate and was wrong by 30x.)
--   bare `confirm`    fails `autopass-probe-missing` -- the probe is the mechanism stage's output.
-- Do not resolve a sub-stage's construction failure by weakening a bar or by skipping it when its
-- evidence is absent. The absent evidence IS the failure, and a run that wants a clean exit should
-- be a `both` run.
--
-- THE BARS, AND WHY THEY ARE NOT THE MODULE CONSTANTS. `Simulator.evaluateBars` is UNCHANGED and
-- is still called for every Pacing cell -- its verdict is recorded on every cell as
-- `lockedVerdict` / `lockedFailures`, so the locked-constant view is in the artefact and nothing is
-- hidden. But two of its five bars are not satisfiable by any pool this engine has: the measured
-- valve-ON residual is 0.05-0.10% against a ZERO bar, and the measured firing rate is 1.1-35.6%
-- against a 1% bar (02-09-SUMMARY, "THE FINDING"). 02-CONTEXT amendment A8 is the owner's
-- resolution: re-derive both from the measured curve and print the measurement. So the SELECTION
-- bars in this file are A8's, each one derived from a number in the table below, and the report
-- prints both views side by side.
--
-- THE MEASURED CURVE THE SELECTION BARS ARE DERIVED FROM. N=10, Pacing, churn=false, valve ON,
-- 1,000 rounds per cell, `valveFiringRate` = the fraction of rounds the engine had to rescue
-- (which equals the valve-OFF stall rate to three decimals at every pool measured, so every
-- firing is a real rescue):
--
--   k | j=1 Wild | j=1 Blocker | j=2 Wild | j=2 Blocker | occupancy | medianFirst (Blocker)
--   1 |   0.266  |    0.356    |  0.210   |    0.340    |   0.63    |  15.4s
--   2 |   0.107  |    0.150    |  0.076   |    0.154    |   0.79    |  14.2s
--   3 |   0.068  |    0.091    |  0.043   |    0.080    |   0.83    |  16.0s
--   4 |   0.033  |    0.048    |  0.021   |    0.036    |   0.84    |  17.8s
--   6 |   0.026  |    0.028    |  0.011   |    0.030    |   0.86    |  21.2s
--
-- The curve is smooth and monotone in k and has NO elbow, so the bar is a judgement and is written
-- here as the two MEASURED bounds that pin it rather than as a round number picked for comfort:
--   LOWER BOUND 0.060. The smallest worst-case rate anywhere in the searched grid is k=6 at 0.030
--     (worst over both joker modes and j in {1,2}). "Pass with margin" is half the bar, so a bar
--     below 2 x 0.030 = 0.060 makes the margin rule structurally incapable of being satisfied by
--     any pool the sweep searches -- the same defect class this phase has now found a dozen times.
--   UPPER BOUND 0.076. The quietest pool in amendment A4's original k in {1,2} grid is k=2,j=2
--     Wild at 0.076. The bar must stay below it, or a pool the engine rescues in one round in
--     thirteen passes and the firing rate stops discriminating -- which is the whole reason A7 made
--     it a first-class metric.
-- VALVE_RATE_MAX_SWEEP = 0.07 is the round value inside [0.060, 0.076). It is NOT a design target:
-- that no pool in the searched grid gets the rescue rate below ~2% is itself the finding, and the
-- report prints a bar-sensitivity table so plan 02-11 can see which pool every candidate bar would
-- have selected.
--
-- WHAT IS AND IS NOT CLAIMED. The honest claim this file's report makes is "zero observed stalls
-- for the selected pool at the confirmed round count", with the measured residual printed rather
-- than rounded away. Nothing here claims the engine cannot stall.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Pool = require("../../src/server/engine/Pool")
local Round = require("../../src/shared/Config/Round")
local Simulator = require("./Simulator")
local Types = require("../../src/server/engine/Types")

-- ---------------------------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------------------------

local DEFAULT_OUT = ".planning/phases/02-card-engine-and-pacing-simulator"
local REPORT_NAME = "02-G1-REPORT.md"
local DATA_NAME = "02-sweep-data.json"
local TRIAGE_NAME = "02-triage.json"

-- Research measured 144,000 rounds across 18 pools x 8 N with 0 stalls at this depth, so 1,000 is
-- a sound SEARCH depth. The locked 10,000 is applied by the confirm stage, to the pool that ships.
local SEARCH_ROUNDS = 1000
-- Not shortenable. This is the only measurement of the twin stall rate in the phase.
local MECHANISM_ROUNDS = 4000
local PROBE_ROUNDS = 1000
-- 02-CONTEXT: "10,000 rounds per (N, pool config), and the bar is ZERO stalls".
local CONFIRM_ROUNDS = 10000

-- Amendment A8 resolution 3: the grid extends past k=2. The planned grid stopped at k=2, which
-- carries a measured 12% intrinsic stall rate -- it would never have searched where the good pools
-- are. k=0 is kept because amendment A5 requires the dead pool to be REPORTED, not skipped.
-- k=8 is deliberately absent: A8 measured k=8 at 1.75% against k=6's 1.00%, non-monotone and
-- inside the noise of a 400-round cell, so it buys no information for 1/6th more search cost.
local SEARCH_K = { 0, 1, 2, 3, 4, 6 }
local SEARCH_J = { 0, 1, 2 }
local SEARCH_N = { 3, 6, 10 }
local CONFIRM_N = { 3, 4, 5, 6, 7, 8, 9, 10 }
local JOKER_MODES: { Types.JokerMode } = { "Wild", "Blocker" }
local CHURN_VARIANTS = { false, true }

-- Task 1, question 2, as answered: SEARCH the list and default to the largest FINITE value that
-- clears with margin. `math.huge` disables the mechanic entirely and is the pure-greedy comparison
-- the report must show; it is never selectable, because a product cannot ship "no AFK deadline".
local AUTO_PASS_CANDIDATES = { 1.5, 3.0, 5.0, 8.0, math.huge }
-- The probe's deadline. Measured `autoPassRate` 1.45% of actions here against the
-- `AUTO_PASS_PROBE_MIN_RATE` bar of 0.5%, a 2.9x margin. At the shipped deadline the rate is 0.000
-- in 6,000 rounds, which is why the auto-pass needs a PROBE rather than a bar on the gated cells.
local PROBE_DEADLINE = 1.0

-- Amendment A4: at k = 0 the Blocker variant stalls up to 97.4% while Wild stalls 0%, so the joker
-- flag would be a cliff rather than a flag and CARD-12's "both variants behind a flag" would be
-- false. Measured here: k=0,j=1 Blocker stalls 100.0% against Wild's 14.7%.
local K_FLOOR = 1
-- Task 1, question 1, as answered: j >= 1, with j = 0 measured and reported as a comparison.
-- PROJECT.md's Key Decisions table records "Jokers as wilds, gated on a solvability simulator",
-- CLAUDE.md states PROJECT.md wins and that its decisions are not re-opened, so the existence of
-- jokers is a decided design property and the simulator's job for j is to CLEAR the chosen count
-- as safe rather than to minimise it. CONTEXT's literal "then fewest jokers" tiebreak returns
-- j = 0 and deletes them; that departure is recorded in the report and in 02-10-SUMMARY.
local J_FLOOR = 1

-- The pool the auto-pass probe and the default triage run use. It is 02-09's provisional reference
-- pool, NOT a selection: the probe measures the auto-pass mechanism, which is pool-independent, and
-- naming the pool here keeps a bare `--stage mechanism` run reproducible without a search.
local REFERENCE_K = 2
local REFERENCE_J = 1
local REFERENCE_MODE: Types.JokerMode = "Wild"

-- THE SELECTION BARS (amendment A8). See the header for the derivation of each.
-- A8 resolution 2: an explicit residual ceiling, ~0.5%. Five times the measured valve-ON residual
-- (0.05-0.10% at N >= 9, 02-09; 0.010% measured here at k=6 over 10,000 rounds) and twenty times
-- below the 10.6% a valve regression produces. The MEASURED residual is printed in the report.
local STALL_RATE_MAX = 0.005
-- A8 resolution 1, pinned by the two measured bounds in the header.
local VALVE_RATE_MAX_SWEEP = 0.07
-- The bar-sensitivity ladder printed in the report, so the choice above is auditable against the
-- pool each alternative bar would have selected.
local VALVE_RATE_LADDER = { 0.40, 0.20, 0.15, 0.10, 0.07, 0.05, 0.04, 0.03, 0.02, 0.01 }

-- Margin. A selection with no margin is a knife edge that gets quietly relaxed later, so the walk
-- demands margin first and falls back to a bare pass with `marginal = true` and the bars named.
local MARGIN_STALL_RATE = STALL_RATE_MAX / 2
local MARGIN_VALVE_RATE = VALVE_RATE_MAX_SWEEP / 2
local MARGIN_MEDIAN_FIRST = 0.8 * Simulator.MEDIAN_FIRST_MAX_SECONDS
local MARGIN_P95_FIRST = 0.8 * Simulator.P95_FIRST_MAX_SECONDS
local MARGIN_OCCUPANCY = 1.1 * Simulator.OCCUPANCY_MIN

local TRIAGE_CAP_MULTIPLE = 10
local BASE_SEED = 21000
local SEED_BLOCK = 100000

-- ---------------------------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------------------------

type Stage = "search" | "mechanism" | "confirm" | "triage" | "both"

type PoolSpec = {
	k: number,
	j: number,
	jokerMode: Types.JokerMode,
	autoPassSeconds: number,
}

type Options = {
	stage: Stage,
	rounds: number?,
	out: string,
	pool: PoolSpec?,
	seeds: { number },
	cap: number?,
	n: number,
}

type Record = {
	stage: string,
	role: Simulator.CellRole,
	simMode: Simulator.SimMode,
	rounds: number,
	n: number,
	k: number,
	j: number,
	jokerMode: Types.JokerMode,
	churn: boolean,
	-- ABSENT when the deadline is disabled. JSON has no Infinity, so an infinite deadline is
	-- carried by `autoPassLabel` alone rather than by a sentinel number that would read as a value.
	autoPassSeconds: number?,
	autoPassLabel: string,
	antiLivelockValve: boolean,
	ranks: number,
	circulation: number,
	outcomes: Simulator.OutcomeCounts,
	stallRate: number,
	clearedFraction: number,
	firstCompletionSamples: number,
	medianFirst: number?,
	p95First: number?,
	medianAll: number?,
	p95All: number?,
	rampMean: number?,
	occupancyMean: number,
	autoPassRate: number,
	actions: number,
	passes: number,
	autoPasses: number,
	deadChaseInstants: number,
	dealAttemptMean: number,
	dealAttemptMax: number,
	valveFiringRate: number,
	valveFiringsMean: number,
	valveFiringsTotal: number,
	armedRate: number,
	valveSeenResetsTotal: number,
	hitActionCapSeeds: { number },
	failingSeeds: { number },
	-- The A8 selection bars.
	barsEvaluated: boolean,
	verdict: boolean,
	failures: { string },
	marginFailures: { string },
	-- `Simulator.evaluateBars`, unchanged, recorded so the locked-constant view is in the artefact.
	lockedVerdict: boolean,
	lockedFailures: { string },
	seconds: number,
}

type Candidate = {
	k: number,
	j: number,
	autoPassLabel: string,
	autoPassSeconds: number?,
	cells: number,
	passed: boolean,
	marginPassed: boolean,
	failures: { string },
	marginShortfalls: { string },
	rejectedBy: string?,
	worstStallRate: number,
	worstValveFiringRate: number,
	worstMedianFirst: number,
	worstP95First: number,
	worstOccupancy: number,
}

type Selection = {
	k: number,
	j: number,
	jokerModeDefault: Types.JokerMode,
	jokerModesCleared: { string },
	autoPassSeconds: number,
	marginal: boolean,
	marginalReasons: { string },
	rule: { string },
	departures: { string },
	candidates: { Candidate },
}

-- ---------------------------------------------------------------------------------------------
-- Argument parsing. An unknown argument must not look green (tests/run.luau's rule).
-- ---------------------------------------------------------------------------------------------

local HELP = table.concat({
	"usage: lune run scripts/sim/sweep.luau -- [--stage search|mechanism|confirm|triage|both]",
	"                                         [--rounds N] [--out DIR]",
	"                                         [--pool k,j,Wild|Blocker,autoPassSeconds]",
	"                                         [--seeds 1,2,3] [--cap N] [--n N]",
	"",
	"  --stage   defaults to `both` (search, then mechanism, then confirm, in ONE process against",
	"            ONE in-memory table). `both` is the only invocation that produces a VERDICT: the",
	"            mechanism checks read a SET of cells and only `both` emits every kind they read.",
	"            A bare `mechanism` run fails `valve-twin-missing` and `valve-not-load-bearing` BY",
	"            CONSTRUCTION (it emits no gated cell). A bare `confirm` run fails",
	"            `autopass-probe-missing` BY CONSTRUCTION (the probe is the mechanism stage's",
	"            output). Both are legitimate diagnostic SUB-STAGES; their non-zero exit is",
	"            information about the stage's scope and not a regression.",
	"            A bare `search` run is labelled SEARCH ONLY, writes no selection and is not judged",
	"            by the mechanism checks at all.",
	`  --rounds  per-cell round count override (defaults: search {SEARCH_ROUNDS}, mechanism {MECHANISM_ROUNDS}, confirm {CONFIRM_ROUNDS})`,
	`  --out     output directory (default {DEFAULT_OUT})`,
	"  --pool    confirm/triage only: the configuration to confirm or triage",
	"  --seeds   triage only: comma-separated seeds to re-run at a raised action cap",
	"  --cap     triage only: the raised action cap (default ten times SOLVABILITY_ACTION_CAP)",
	"  --n       triage only: the roster size the seeds came from (default 10)",
}, "\n")

local function fail(message: string): never
	print(message)
	process.exit(1)
	-- `process.exit` does not return, but the typechecker cannot know that.
	return error(message)
end

local function parsePool(raw: string): PoolSpec
	local parts: { string } = string.split(raw, ",")
	if #parts ~= 4 then
		fail(`unusable --pool value: {raw} (want k,j,Wild|Blocker,autoPassSeconds)`)
	end
	local k = tonumber(parts[1])
	local j = tonumber(parts[2])
	local mode = parts[3]
	local autoPass = if parts[4] == "inf" then math.huge else tonumber(parts[4])
	if k == nil or j == nil or autoPass == nil or (mode ~= "Wild" and mode ~= "Blocker") then
		fail(`unusable --pool value: {raw} (want k,j,Wild|Blocker,autoPassSeconds)`)
	end
	return {
		k = k :: number,
		j = j :: number,
		jokerMode = mode :: Types.JokerMode,
		autoPassSeconds = autoPass :: number,
	}
end

local function parseArgs(argv: { string }): Options
	local opts: Options = {
		stage = "both",
		rounds = nil,
		out = DEFAULT_OUT,
		pool = nil,
		seeds = {},
		cap = nil,
		n = 10,
	}
	local sawSeeds, sawCap, sawN = false, false, false
	local i = 1
	while i <= #argv do
		local a = argv[i]
		if a == "--" then
			-- Lune 0.11.1 does not consume the separator; tolerate it (tests/run.luau does the same).
			i += 1
		elseif a == "--help" or a == "-h" then
			print(HELP)
			process.exit(0)
			i += 1
		elseif a == "--stage" then
			local v = argv[i + 1]
			if v ~= "search" and v ~= "mechanism" and v ~= "confirm" and v ~= "triage" and v ~= "both" then
				fail(`unusable --stage value: {tostring(v)}`)
			end
			opts.stage = v :: Stage
			i += 2
		elseif a == "--rounds" then
			local v = tonumber(argv[i + 1])
			if v == nil or v < 1 or v % 1 ~= 0 then
				fail(`unusable --rounds value: {tostring(argv[i + 1])}`)
			end
			opts.rounds = v
			i += 2
		elseif a == "--out" then
			local v = argv[i + 1]
			if v == nil or v == "" then
				fail("unusable --out value: (empty)")
			end
			opts.out = v
			i += 2
		elseif a == "--pool" then
			local v = argv[i + 1]
			if v == nil then
				fail("unusable --pool value: (missing)")
			end
			opts.pool = parsePool(v)
			i += 2
		elseif a == "--seeds" then
			local v = argv[i + 1]
			if v == nil then
				fail("unusable --seeds value: (missing)")
			end
			for _, part in string.split(v, ",") do
				local seed = tonumber(part)
				if seed == nil then
					fail(`unusable --seeds value: {v}`)
				end
				table.insert(opts.seeds, seed :: number)
			end
			sawSeeds = true
			i += 2
		elseif a == "--cap" then
			local v = tonumber(argv[i + 1])
			if v == nil or v < 1 then
				fail(`unusable --cap value: {tostring(argv[i + 1])}`)
			end
			opts.cap = v
			sawCap = true
			i += 2
		elseif a == "--n" then
			local v = tonumber(argv[i + 1])
			if v == nil then
				fail(`unusable --n value: {tostring(argv[i + 1])}`)
			else
				-- An explicit `else` rather than a fall-through: Luau does not treat a call to a
				-- `never`-returning function as terminating control flow, so the refinement only
				-- survives inside the branch. `Pool.poolConfig` range-checks 3..10 after this.
				opts.n = v
			end
			sawN = true
			i += 2
		else
			-- A typo must not look green. Same rule as tests/run.luau.
			fail(`unknown argument: {a}`)
		end
	end

	-- A flag that is silently ignored is the same defect as a flag that is misspelled: the run does
	-- something other than what was asked and exits 0. So a triage-only flag outside triage is loud.
	if opts.stage ~= "triage" and (sawSeeds or sawCap or sawN) then
		fail(`--seeds, --cap and --n are triage-only flags; got them with --stage {opts.stage}`)
	end
	if opts.stage == "triage" and #opts.seeds == 0 then
		fail("--stage triage needs --seeds")
	end
	return opts
end

-- ---------------------------------------------------------------------------------------------
-- The A8 selection bars. `Simulator.evaluateBars` is UNCHANGED and is called alongside these; the
-- failure NAMES are deliberately the same vocabulary, so a reader comparing the two views is
-- comparing thresholds and not translating words.
-- ---------------------------------------------------------------------------------------------

local function sweepBars(record: Record, margin: boolean): (boolean, { string })
	local failures: { string } = {}
	local stallMax = if margin then MARGIN_STALL_RATE else STALL_RATE_MAX
	local valveMax = if margin then MARGIN_VALVE_RATE else VALVE_RATE_MAX_SWEEP
	local medianMax = if margin then MARGIN_MEDIAN_FIRST else Simulator.MEDIAN_FIRST_MAX_SECONDS
	local p95Max = if margin then MARGIN_P95_FIRST else Simulator.P95_FIRST_MAX_SECONDS
	local occupancyMin = if margin then MARGIN_OCCUPANCY else Simulator.OCCUPANCY_MIN

	-- Same ordering rule as `Simulator.evaluateBars`: the absence of completions is its own named
	-- failure and it returns BEFORE any median is touched, because `nil > 45` errors and defaulting
	-- the nil to 0 makes a dead table pass the pacing bar with a perfect score.
	if record.firstCompletionSamples == 0 then
		return false, { "no-completions" }
	end
	if record.stallRate > stallMax then
		table.insert(failures, "stalls")
	end
	-- The stalls bar from the other side, derived independently so a broken outcome accounting is
	-- caught rather than averaged away.
	if record.clearedFraction < 1 - stallMax then
		table.insert(failures, "cleared-fraction")
	end
	local medianFirst = record.medianFirst
	if medianFirst ~= nil and medianFirst > medianMax then
		table.insert(failures, "median-first")
	end
	local p95First = record.p95First
	if p95First ~= nil and p95First > p95Max then
		table.insert(failures, "p95-first")
	end
	if record.occupancyMean < occupancyMin then
		table.insert(failures, "occupancy")
	end
	if record.valveFiringRate > valveMax then
		table.insert(failures, "valve-rate")
	end
	return #failures == 0, failures
end

-- ---------------------------------------------------------------------------------------------
-- Running a cell
-- ---------------------------------------------------------------------------------------------

local cells: { Simulator.CellResult } = {}
local records: { Record } = {}
local cellIndex = 0
-- A per-STAGE counter as well as the global one, so a `both` run's progress line reads
-- `[confirm 7/36]` rather than `[confirm 1087/36]`.
local stageCellIndex = 0
local startClock = os.clock()

local function labelFor(autoPassSeconds: number): string
	return if autoPassSeconds == math.huge then "inf" else string.format("%.1f", autoPassSeconds)
end

type CellSpec = {
	stage: string,
	role: Simulator.CellRole,
	n: number,
	k: number,
	j: number,
	jokerMode: Types.JokerMode,
	churn: boolean,
	autoPassSeconds: number,
	simMode: Simulator.SimMode,
	valve: boolean,
	rounds: number,
}

local function runOneCell(spec: CellSpec, total: number): Record
	cellIndex += 1
	stageCellIndex += 1
	local config = Pool.poolConfig(spec.n, spec.k, spec.j, spec.jokerMode)
	config.antiLivelockValve = spec.valve

	local t0 = os.clock()
	local cell = Simulator.runCell({
		n = spec.n,
		config = config,
		seed = BASE_SEED + cellIndex * SEED_BLOCK,
		mode = spec.simMode,
		autoPassSeconds = spec.autoPassSeconds,
		churn = spec.churn,
		-- `identityCheck = false` is counters-only: plan 02-08's fuzz suite is where the full
		-- partition scan earns its cost, and research 11.1 measured it at nearly half the throughput.
		sabotage = "None",
		identityCheck = false,
	}, spec.rounds, spec.role)
	local seconds = os.clock() - t0

	local eligible = cell.rounds - cell.outcomes.DeadPool - cell.outcomes.RosterShortfall
	local record: Record = {
		stage = spec.stage,
		role = cell.role,
		simMode = spec.simMode,
		rounds = cell.rounds,
		n = spec.n,
		k = cell.k,
		j = cell.j,
		jokerMode = cell.jokerMode,
		churn = spec.churn,
		autoPassSeconds = if spec.autoPassSeconds == math.huge then nil else spec.autoPassSeconds,
		autoPassLabel = labelFor(spec.autoPassSeconds),
		antiLivelockValve = spec.valve,
		ranks = config.ranks,
		circulation = 4 * cell.k + cell.j,
		outcomes = cell.outcomes,
		stallRate = cell.stallRate,
		clearedFraction = if eligible > 0 then cell.outcomes.Cleared / eligible else 0,
		firstCompletionSamples = cell.firstCompletionSamples,
		medianFirst = cell.medianFirst,
		p95First = cell.p95First,
		medianAll = cell.medianAll,
		p95All = cell.p95All,
		rampMean = cell.rampMean,
		occupancyMean = cell.occupancyMean,
		autoPassRate = cell.autoPassRate,
		actions = cell.actions,
		passes = cell.passes,
		autoPasses = cell.autoPasses,
		deadChaseInstants = cell.deadChaseInstants,
		dealAttemptMean = cell.dealAttemptMean,
		dealAttemptMax = cell.dealAttemptMax,
		valveFiringRate = cell.valveFiringRate,
		valveFiringsMean = cell.valveFiringsMean,
		valveFiringsTotal = cell.valveFiringsTotal,
		armedRate = cell.armedRate,
		valveSeenResetsTotal = cell.valveSeenResetsTotal,
		hitActionCapSeeds = cell.capArtifactCandidates,
		failingSeeds = cell.failingSeeds,
		barsEvaluated = false,
		verdict = false,
		failures = {},
		marginFailures = {},
		lockedVerdict = false,
		lockedFailures = {},
		seconds = seconds,
	}

	-- 02-09: do NOT run the pacing bars over a Solvability cell. `now` never advances there, so
	-- every time is nil by construction and both checkers would report `"no-completions"` about a
	-- mode that has no clock. The twins are evidence about the valve, not candidates for selection.
	if spec.simMode == "Pacing" then
		record.barsEvaluated = true
		local verdict, failures = sweepBars(record, false)
		record.verdict = verdict
		record.failures = failures
		local _, marginFailures = sweepBars(record, true)
		record.marginFailures = marginFailures
		local lockedVerdict, lockedFailures = Simulator.evaluateBars(cell)
		record.lockedVerdict = lockedVerdict
		record.lockedFailures = lockedFailures
	else
		record.failures = { "solvability-cell-pacing-bars-not-applicable" }
		record.lockedFailures = { "solvability-cell-pacing-bars-not-applicable" }
	end

	table.insert(cells, cell)
	table.insert(records, record)

	-- A 20-to-40-minute silent run is indistinguishable from a hang (threat T-2-50).
	print(
		string.format(
			"[%s %d/%d] N=%d k=%d j=%d %s churn=%s ap=%s valve=%s %s %d rounds | cleared=%d stall=%.4f fire=%.4f occ=%.3f | %.2fs cell, %.1fs elapsed",
			spec.stage,
			stageCellIndex,
			total,
			spec.n,
			spec.k,
			spec.j,
			spec.jokerMode,
			tostring(spec.churn),
			record.autoPassLabel,
			tostring(spec.valve),
			spec.simMode,
			cell.rounds,
			cell.outcomes.Cleared,
			cell.stallRate,
			cell.valveFiringRate,
			cell.occupancyMean,
			seconds,
			os.clock() - startClock
		)
	)
	return record
end

-- ---------------------------------------------------------------------------------------------
-- Stage: search
-- ---------------------------------------------------------------------------------------------

local function searchCellCount(): number
	return #SEARCH_K * #SEARCH_J * #AUTO_PASS_CANDIDATES * #SEARCH_N * #JOKER_MODES * #CHURN_VARIANTS
end

local function runSearch(rounds: number)
	stageCellIndex = 0
	local total = searchCellCount()
	print(`-- stage search: {total} cells x {rounds} rounds (a SEARCH, not a gate)`)
	for _, k in SEARCH_K do
		for _, j in SEARCH_J do
			for _, autoPass in AUTO_PASS_CANDIDATES do
				for _, n in SEARCH_N do
					for _, mode: Types.JokerMode in JOKER_MODES do
						for _, churn in CHURN_VARIANTS do
							-- `role = "diagnostic"`: the search is not the gate, so its cells are
							-- deliberately OUTSIDE `evaluateMechanisms`'s evidence set. A thin-pool
							-- search cell carries enough firings to satisfy `valve-never-fired` on
							-- its own, and the twin match is pool-keyed, so admitting 1,080 search
							-- cells as `gated` would make the twin bar a claim about every pool
							-- searched rather than about the pool that ships.
							runOneCell({
								stage = "search",
								role = "diagnostic",
								n = n,
								k = k,
								j = j,
								jokerMode = mode,
								churn = churn,
								autoPassSeconds = autoPass,
								simMode = "Pacing",
								valve = true,
								rounds = rounds,
							}, total)
						end
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Stage: mechanism -- the valve-disabled twins and the auto-pass probe
-- ---------------------------------------------------------------------------------------------

local function runMechanism(twinRounds: number, probeRounds: number)
	stageCellIndex = 0
	local pools: { { number } } = {}
	for _, k in SEARCH_K do
		if k >= K_FLOOR then
			for _, j in SEARCH_J do
				table.insert(pools, { k, j })
			end
		end
	end
	local total = #pools + 1
	print(`-- stage mechanism: {#pools} valve-disabled twins x {twinRounds} rounds + 1 auto-pass probe`)
	for _, pair in pools do
		runOneCell({
			stage = "mechanism",
			role = "mechanism",
			n = 10,
			k = pair[1],
			j = pair[2],
			jokerMode = "Wild",
			churn = false,
			autoPassSeconds = math.huge,
			simMode = "Solvability",
			-- The twin. Pure greedy with no rescue and no deadline: the known worst case, and the
			-- proof the valve is load-bearing rather than decorative.
			valve = false,
			rounds = twinRounds,
		}, total)
	end
	-- The probe's role is NOT cosmetic: `autopass-probe-missing` fires when no cell carries exactly
	-- this role, so a probe emitted as "mechanism" would fail that bar on every run and the failure
	-- would look like a missing probe rather than a mislabelled one.
	runOneCell({
		stage = "mechanism",
		role = "autopass-probe",
		n = 10,
		k = REFERENCE_K,
		j = REFERENCE_J,
		jokerMode = REFERENCE_MODE,
		churn = false,
		autoPassSeconds = PROBE_DEADLINE,
		simMode = "Pacing",
		valve = true,
		rounds = probeRounds,
	}, total)
end

-- ---------------------------------------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------------------------------------

local function worstOf(group: { Record }): (number, number, number, number, number)
	local stall, valve, median, p95, occupancy = 0, 0, 0, 0, 1
	for _, r in group do
		stall = math.max(stall, r.stallRate)
		valve = math.max(valve, r.valveFiringRate)
		median = math.max(median, r.medianFirst or math.huge)
		p95 = math.max(p95, r.p95First or math.huge)
		occupancy = math.min(occupancy, r.occupancyMean)
	end
	return stall, valve, median, p95, occupancy
end

local function uniqueSorted(values: { string }): { string }
	local seen: { [string]: true } = {}
	local out: { string } = {}
	for _, v in values do
		if not seen[v] then
			seen[v] = true
			table.insert(out, v)
		end
	end
	table.sort(out)
	return out
end

-- Builds one candidate per (pool, auto-pass deadline) over the search grid, with its named bar
-- failures. A selection rule whose rejections are invisible cannot be audited (threat T-2-49), so
-- EVERY candidate considered is emitted, including the ones the k and j floors reject.
local function buildCandidates(): { Candidate }
	local groups: { [string]: { Record } } = {}
	local order: { string } = {}
	for _, r in records do
		if r.stage ~= "search" then
			continue
		end
		local key = `{r.k}|{r.j}|{r.autoPassLabel}`
		if groups[key] == nil then
			groups[key] = {}
			table.insert(order, key)
		end
		table.insert(groups[key], r)
	end

	local candidates: { Candidate } = {}
	for _, key in order do
		local group = groups[key]
		local first = group[1]
		local stall, valve, median, p95, occupancy = worstOf(group)
		local failures: { string } = {}
		local shortfalls: { string } = {}
		local passed, marginPassed = true, true
		for _, r in group do
			if not r.verdict then
				passed = false
				for _, f in r.failures do
					table.insert(failures, f)
				end
			end
			if #r.marginFailures > 0 then
				marginPassed = false
				for _, f in r.marginFailures do
					table.insert(shortfalls, f)
				end
			end
		end
		local rejectedBy: string? = nil
		if first.k < K_FLOOR then
			rejectedBy = "k-floor"
		elseif first.j < J_FLOOR then
			rejectedBy = "j-floor"
		elseif first.autoPassSeconds == nil then
			-- `math.huge` is the pure-greedy comparison, never a product value.
			rejectedBy = "auto-pass-disabled"
		elseif not passed then
			rejectedBy = "bars"
		elseif not marginPassed then
			rejectedBy = nil
		end
		table.insert(candidates, {
			k = first.k,
			j = first.j,
			autoPassLabel = first.autoPassLabel,
			autoPassSeconds = first.autoPassSeconds,
			cells = #group,
			passed = passed,
			marginPassed = marginPassed and passed,
			failures = uniqueSorted(failures),
			marginShortfalls = uniqueSorted(shortfalls),
			rejectedBy = rejectedBy,
			worstStallRate = stall,
			worstValveFiringRate = valve,
			worstMedianFirst = median,
			worstP95First = p95,
			worstOccupancy = occupancy,
		})
	end
	return candidates
end

-- The six-step selection rule, with the ONE correction this phase's measurements forced.
--
-- The plan's rule applies "margin" only to the auto-pass walk and picks the pool by "smallest that
-- passes". On the measured curve successive k differ by a factor of 1.6 to 1.9, so the smallest
-- pool that passes a bar ALWAYS sits within a factor of two of it -- which is exactly the margin
-- threshold. Written that way the rule is structurally incapable of producing a non-marginal
-- selection for any bar value: it would report `marginal = true` on every run, at every bar, and
-- the flag would carry no information. So margin is applied at the POOL level too: the walk looks
-- for the smallest pool that clears WITH margin and only then descends to a bare pass. This is the
-- plan's own margin-and-fallback doctrine extended one axis; the descending fallback and the
-- `marginal` flag are unchanged, and both passes emit their rejections.
local function select_(candidates: { Candidate }): Selection?
	local eligible: { Candidate } = {}
	for _, c in candidates do
		if c.k >= K_FLOOR and c.j >= J_FLOOR and c.autoPassSeconds ~= nil then
			table.insert(eligible, c)
		end
	end
	-- Deterministic order: fewest extra ranks, then fewest jokers (subject to the floor), then the
	-- LARGEST finite deadline (step 6's descending walk), then the lower worst-case valve firing
	-- rate.
	--
	-- THE FIRING-RATE KEY SORTS LAST, AND THAT ORDER IS LOAD-BEARING. Placed before the deadline it
	-- reorders the deadline walk by measurement noise: at two rounds per cell it selected a 3.0s
	-- deadline over 8.0s purely because that cell's firing rate happened to be lower, which is not
	-- a tie-break, it is the walk being overridden. Placed last the key is INERT in this grid --
	-- (k, j, deadline) names exactly one candidate, so no two candidates are ever equal on the
	-- first three keys. It is written anyway, so a future grid carrying two cells per candidate
	-- breaks the tie by measurement rather than by table order, and it is recorded as unreachable
	-- rather than presented as a rule that fires.
	table.sort(eligible, function(a, b)
		if a.k ~= b.k then
			return a.k < b.k
		end
		if a.j ~= b.j then
			return a.j < b.j
		end
		if a.autoPassSeconds ~= b.autoPassSeconds then
			return (a.autoPassSeconds :: number) > (b.autoPassSeconds :: number)
		end
		return a.worstValveFiringRate < b.worstValveFiringRate
	end)

	local rule = {
		`1. k >= {K_FLOOR} (amendment A4: at k = 0 the Blocker variant is a cliff, not a flag)`,
		`2. j >= {J_FLOOR} (PROJECT.md's Key Decisions: jokers exist; the sweep CLEARS j, it does not minimise it)`,
		"3. every bar passes in BOTH joker modes and BOTH churn variants, at every N searched (OQ-D)",
		`4. reject any pool whose valveFiringRate exceeds {VALVE_RATE_MAX_SWEEP} (amendment A8, re-derived from the measured curve)`,
		"5. smallest passing pool: fewest extra ranks k first, then fewest jokers j; ties on the lower valve firing rate",
		"6. auto-pass deadline: the largest FINITE candidate that clears, WITH MARGIN where any pool can",
	}
	local departures = {
		"CONTEXT's literal 'then fewest jokers' tiebreak returns j = 0 and deletes the jokers. PROJECT.md's"
			.. " Key Decisions table records them as a design property and CLAUDE.md says PROJECT.md wins, so the"
			.. " search floor is j >= 1 and j = 0 is measured and reported as a comparison (report section 6).",
		`Amendment A8 replaced the ZERO stall bar with an explicit residual ceiling of {STALL_RATE_MAX}`
			.. ` and the 1% valve-rate bar with {VALVE_RATE_MAX_SWEEP}; Simulator.evaluateBars is unchanged and its`
			.. " verdict is recorded on every cell as lockedVerdict/lockedFailures.",
		"Margin is applied at the POOL level as well as to the auto-pass walk. Applied only to the walk, the"
			.. " 'smallest passing pool' rule reports marginal = true at every bar value by construction, because"
			.. " successive k on the measured curve differ by less than the factor of two margin demands.",
	}

	for _, wantMargin in { true, false } do
		for _, c in eligible do
			local ok = if wantMargin then c.marginPassed else c.passed
			if ok then
				return {
					k = c.k,
					j = c.j,
					-- Both variants clear every bar, which is what makes CARD-12's flag a flag.
					-- PROJECT.md records wilds as the design intent, so Wild is the default.
					jokerModeDefault = "Wild",
					jokerModesCleared = { "Wild", "Blocker" },
					autoPassSeconds = c.autoPassSeconds :: number,
					marginal = not wantMargin,
					marginalReasons = if wantMargin then {} else c.marginShortfalls,
					rule = rule,
					departures = departures,
					candidates = candidates,
				}
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------
-- Stage: confirm -- the locked bar, applied to the configuration that ships
-- ---------------------------------------------------------------------------------------------

local function runConfirm(pool: PoolSpec, rounds: number): boolean
	stageCellIndex = 0
	local total = #CONFIRM_N * #JOKER_MODES * #CHURN_VARIANTS + #JOKER_MODES * #CHURN_VARIANTS
	print(
		`-- stage confirm: k={pool.k} j={pool.j} ap={labelFor(pool.autoPassSeconds)} | {#CONFIRM_N * #JOKER_MODES * #CHURN_VARIANTS} gated cells x {rounds} rounds + 4 valve-disabled twins`
	)
	local allPass = true
	for _, n in CONFIRM_N do
		for _, mode: Types.JokerMode in JOKER_MODES do
			for _, churn in CHURN_VARIANTS do
				local r = runOneCell({
					stage = "confirm",
					role = "gated",
					n = n,
					k = pool.k,
					j = pool.j,
					jokerMode = mode,
					churn = churn,
					autoPassSeconds = pool.autoPassSeconds,
					simMode = "Pacing",
					valve = true,
					rounds = rounds,
				}, total)
				if not r.verdict then
					allPass = false
				end
			end
		end
	end
	-- The twins sit at N = 10 ONLY, which is why `valve-twin-missing` matches at the POOL level and
	-- not per gated cell: the twin's job is to show the valve is load-bearing at a POOL, and a twin
	-- per N would triple this stage to prove something that is not a property of the roster size.
	for _, mode: Types.JokerMode in JOKER_MODES do
		for _, churn in CHURN_VARIANTS do
			runOneCell({
				stage = "confirm",
				role = "mechanism",
				n = 10,
				k = pool.k,
				j = pool.j,
				jokerMode = mode,
				churn = churn,
				autoPassSeconds = math.huge,
				simMode = "Solvability",
				valve = false,
				rounds = rounds,
			}, total)
		end
	end
	return allPass
end

-- ---------------------------------------------------------------------------------------------
-- Stage: triage -- a cap artefact or a true residual livelock?
-- ---------------------------------------------------------------------------------------------

type TriageRow = {
	seed: number,
	k: number,
	j: number,
	jokerMode: Types.JokerMode,
	n: number,
	classification: string,
	outcome: Simulator.Outcome,
	violation: string?,
	valveSeenResets: number,
	actions: number,
	cap: number,
}

local function runTriage(opts: Options): { TriageRow }
	local pool = opts.pool
		or {
			k = REFERENCE_K,
			j = REFERENCE_J,
			jokerMode = REFERENCE_MODE,
			autoPassSeconds = 5.0,
		}
	local cap = opts.cap or TRIAGE_CAP_MULTIPLE * Simulator.SOLVABILITY_ACTION_CAP
	print(
		`-- stage triage: {#opts.seeds} seed(s) at N={opts.n} k={pool.k} j={pool.j} {pool.jokerMode}, action cap {cap}`
	)
	local rows: { TriageRow } = {}
	for _, seed in opts.seeds do
		local config = Pool.poolConfig(opts.n, pool.k, pool.j, pool.jokerMode)
		local r = Simulator.runRound({
			n = opts.n,
			config = config,
			seed = seed,
			mode = "Pacing",
			autoPassSeconds = pool.autoPassSeconds,
			churn = false,
			sabotage = "None",
			identityCheck = false,
			actionCap = cap,
		})
		-- EXACTLY one of two strings, never an unlabelled failure: which of the two it is decides
		-- whether the report's headline claim is "zero stalls" or "zero stalls for the selected
		-- pool". `violation` is carried beside it because a round that ended on the 300s TIME cap
		-- cannot be rescued by a raised ACTION cap, and a reader has to be able to see that.
		local classification = if r.outcome == "Cleared" then "CapArtifact" else "ResidualLivelock"
		print(
			string.format(
				"  seed %d -> %s (%s%s, %d actions, seenResets %d)",
				seed,
				classification,
				r.outcome,
				if r.violation ~= nil then `/{r.violation}` else "",
				r.actions,
				r.valveSeenResets
			)
		)
		table.insert(rows, {
			seed = seed,
			k = pool.k,
			j = pool.j,
			jokerMode = pool.jokerMode,
			n = opts.n,
			classification = classification,
			outcome = r.outcome,
			violation = r.violation,
			valveSeenResets = r.valveSeenResets,
			actions = r.actions,
			cap = cap,
		})
	end
	return rows
end

-- ---------------------------------------------------------------------------------------------
-- Report rendering -- from the SAME in-memory table the JSON is written from, so the two cannot
-- drift.
-- ---------------------------------------------------------------------------------------------

local function f4(x: number?): string
	return if x == nil then "-" else string.format("%.4f", x)
end
local function f3(x: number?): string
	return if x == nil then "-" else string.format("%.3f", x)
end
local function f1(x: number?): string
	return if x == nil then "-" else string.format("%.1f", x)
end
local function pct(x: number): string
	return string.format("%.3f%%", x * 100)
end
local function names(list: { string }): string
	return if #list == 0 then "-" else table.concat(list, ",")
end

local function byStage(stage: string, role: string?): { Record }
	local out: { Record } = {}
	for _, r in records do
		if r.stage == stage and (role == nil or r.role == role) then
			table.insert(out, r)
		end
	end
	return out
end

local function renderReport(
	opts: Options,
	stages: { string },
	selection: Selection?,
	mechanismPass: boolean?,
	mechanismFailures: { string },
	roundsPerCell: { [string]: number },
	gatedPass: boolean?,
	baseCommand: string
): string
	local L: { string } = {}
	local function line(s: string)
		table.insert(L, s)
	end

	line("# Phase 2 Gate G1 Report")
	line("")
	line(`Generated {os.date("!%Y-%m-%dT%H:%M:%SZ")} by \`scripts/sim/sweep.luau\`.`)
	line("")

	-- 1 ------------------------------------------------------------------------------------
	line("## 1. Verdict")
	line("")
	if selection == nil then
		if stages[1] == "search" and #stages == 1 then
			line("**SEARCH ONLY - NOT A VERDICT.** This run executed the search grid alone. It located")
			line("the passing region and made NO selection; no selection block was written to")
			line("`02-sweep-data.json`, and **the mechanism checks were not evaluated** because the")
			line("search grid contains no valve-disabled twin and no auto-pass probe by construction.")
			line("A verdict needs `--stage both`.")
		else
			line("**SUB-STAGE - NOT A VERDICT.** This run executed only part of the evidence set, so no")
			line("selection was made. See the sub-stage table below for the bars this stage fails by")
			line("construction. A verdict needs `--stage both`.")
		end
	else
		local sel = selection
		line(
			`**Selected pool: k = {sel.k} extra ranks, j = {sel.j} joker(s), auto-pass deadline {string.format(
				"%.1f",
				sel.autoPassSeconds
			)}s.**`
		)
		line(`Joker mode is a FLAG, not a selection: {table.concat(sel.jokerModesCleared, " and ")} both clear every`)
		line(`bar at every N, and \`{sel.jokerModeDefault}\` is the default PROJECT.md records.`)
		line("")
		line(`Marginal: **{tostring(sel.marginal)}**{if sel.marginal then ` ({names(sel.marginalReasons)})` else ""}`)
		line("")
		local gated = byStage("confirm", "gated")
		if #gated > 0 then
			local stall, valve, median, p95, occupancy = worstOf(gated)
			line("| bar | measured worst case over the confirmed cells | bar | with margin |")
			line("|---|---|---|---|")
			line(`| stalls | {pct(stall)} | <= {pct(STALL_RATE_MAX)} | <= {pct(MARGIN_STALL_RATE)} |`)
			line(`| cleared fraction | see section 3 | = 1 - the stall ceiling | |`)
			line(`| median first | {f1(median)}s | <= 45s | <= {f1(MARGIN_MEDIAN_FIRST)}s |`)
			line(`| p95 first | {f1(p95)}s | <= 120s | <= {f1(MARGIN_P95_FIRST)}s |`)
			line(`| occupancy | {f3(occupancy)} | >= {f3(Simulator.OCCUPANCY_MIN)} | >= {f3(MARGIN_OCCUPANCY)} |`)
			line(`| valve firing rate | {pct(valve)} | <= {pct(VALVE_RATE_MAX_SWEEP)} | <= {pct(MARGIN_VALVE_RATE)} |`)
			line("")
			local pass = gatedPass == true and mechanismPass == true
			line(
				`**G1: {if pass then "PASSES" else "DOES NOT PASS"}** on this evidence - `
					.. `**zero observed stalls for the selected pool at {roundsPerCell.confirm or 0} rounds per cell**, `
					.. `measured residual {pct(stall)} against a {pct(STALL_RATE_MAX)} ceiling. `
					.. "That is the claim, in its honest form: a measured property of a SELECTED configuration, "
					.. "never an unconditional property of the engine. The measured residual is printed above "
					.. "rather than rounded away, and section 4b says whether it was a cap artefact or a real one."
			)
			if mechanismPass == false then
				line("")
				line(`Mechanism checks FAILED: \`{names(mechanismFailures)}\`.`)
			end
		end
	end
	line("")
	line("| stage | rounds per cell |")
	line("|---|---|")
	for _, key in { "search", "mechanism", "probe", "confirm" } do
		local v = roundsPerCell[key]
		if v ~= nil then
			line(`| {key} | {v} |`)
		end
	end
	line("")
	line("The search stage ran at its own round count and is a **search, not a gate**. The locked")
	line("10,000-rounds-per-cell bar is applied by the confirm stage, to the configuration that ships.")
	line("")

	-- 2 ------------------------------------------------------------------------------------
	line("## 2. The five bars")
	line("")
	line("| # | bar | threshold | where it comes from |")
	line("|---|---|---|---|")
	line(
		`| 1 | stalls | stall rate <= {pct(STALL_RATE_MAX)} | amendment A8 resolution 2: an explicit residual ceiling, five times the measured 0.05-0.10% valve-ON residual and twenty times below the 10.6% a valve regression produces. The locked bar was ZERO; no pool this engine has reaches it |`
	)
	line(
		"| 2 | cleared fraction | every eligible round cleared, to within the same ceiling | the stalls bar from the other side, derived independently |"
	)
	line(`| 3 | pacing | median time to first completion <= 45s and p95 <= 120s | 02-CONTEXT amendment A2 |`)
	line(
		`| 4 | occupancy | mean occupancy >= {f3(Simulator.OCCUPANCY_MIN)} | amendment A2 and research 3.7: without it the rule picks k=0,j=1, one card circulating among nine seats |`
	)
	line(
		`| 5 | valve firing rate | <= {pct(VALVE_RATE_MAX_SWEEP)} of rounds | amendment A8 resolution 1, re-derived from the measured curve. See the bar-sensitivity ladder in section 4b |`
	)
	line("")
	line("`Simulator.evaluateBars` is UNCHANGED and is evaluated for every Pacing cell alongside")
	line("these; its verdict rides on each cell in `02-sweep-data.json` as `lockedVerdict` and")
	line("`lockedFailures`, so the locked-constant view is in the artefact and can be read directly.")
	line("")

	-- 3 ------------------------------------------------------------------------------------
	line("## 3. Confirmation stage")
	line("")
	local gated = byStage("confirm", "gated")
	if #gated == 0 then
		line("Not run in this invocation.")
	else
		line(
			"| N | mode | churn | stall | medFirst | p95First | medAll | p95All | occupancy | ramp | autoPass | dealAttempt mean/max | Cleared/Unsat/Livelock/Cap/Shortfall/Dead | bars | locked bars |"
		)
		line("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
		for _, r in gated do
			local o = r.outcomes
			line(
				`| {r.n} | {r.jokerMode} | {tostring(r.churn)} | {f4(r.stallRate)} | {f1(r.medianFirst)} | {f1(
					r.p95First
				)} | `
					.. `{f1(r.medianAll)} | {f1(r.p95All)} | {f3(r.occupancyMean)} | {f1(r.rampMean)} | {f4(
						r.autoPassRate
					)} | `
					.. `{f1(r.dealAttemptMean)}/{r.dealAttemptMax} | {o.Cleared}/{o.Unsatisfiable}/{o.Livelock}/{o.CapReached}/{o.RosterShortfall}/{o.DeadPool} | `
					.. `{if r.verdict then "pass" else names(r.failures)} | {if r.lockedVerdict
						then "pass"
						else names(r.lockedFailures)} |`
			)
		end
	end
	line("")

	-- 4 ------------------------------------------------------------------------------------
	line("## 4. Known worst case: pure greedy with the valve disabled")
	line("")
	line("These cells run `antiLivelockValve = false` with the auto-pass deadline disabled")
	line("(`math.huge`): pure greedy, no rescue, no deadline. They are **the known worst case** and")
	line("**the proof the valve is load-bearing**. A valve-off stall is a 1,300-1,900 action")
	line("non-progressing tail against a healthy round's ~313 actions.")
	line("")
	local twins: { Record } = {}
	for _, r in records do
		if not r.antiLivelockValve then
			table.insert(twins, r)
		end
	end
	if #twins == 0 then
		line("No valve-disabled cell in this invocation.")
	else
		line("| stage | N | k | j | mode | churn | rounds | stall (valve OFF) | Livelock | CapReached |")
		line("|---|---|---|---|---|---|---|---|---|---|")
		for _, r in twins do
			line(
				`| {r.stage} | {r.n} | {r.k} | {r.j} | {r.jokerMode} | {tostring(r.churn)} | {r.rounds} | `
					.. `{f4(r.stallRate)} | {r.outcomes.Livelock} | {r.outcomes.CapReached} |`
			)
		end
	end
	line("")
	line("**Comparison to the figures these bars were originally written against.** 02-CONTEXT")
	line("amendment A7-CORRECTION tabulated a prototype at 0.275% / 0.250% / 21.6% valve-off stalls")
	line("for k=1,j=1 / k=2,j=1 / k=2,j=2. The real engine does not reproduce them: amendment A8")
	line("records 9.6-10.6% at k=2,j=1, a factor of 40, traced to amendment A3 (the prototype seated")
	line("10 players; the real game seats 9 seekers because the hider does not play cards, so the")
	line("endgame is one rank deeper and 33 of 53 stalls occur at `liveCount == 2`). The table above")
	line("is the measurement that supersedes the prototype's. A second prototype claim also fails to")
	line("reproduce: k=2,j=2 was its bad pool, and measured it is indistinguishable from k=2,j=1.")
	line("")

	-- 4b -----------------------------------------------------------------------------------
	line("## 4b. The valve")
	line("")
	local valveRows = byStage("confirm", "gated")
	if #valveRows == 0 then
		valveRows = byStage("search")
	end
	if #valveRows > 0 then
		line(
			"| stage | N | k | j | mode | churn | firing rate | firings/round | armed rate | seenResets | hit the action cap |"
		)
		line("|---|---|---|---|---|---|---|---|---|---|---|")
		local shown = 0
		for _, r in valveRows do
			if shown >= 48 then
				break
			end
			shown += 1
			line(
				`| {r.stage} | {r.n} | {r.k} | {r.j} | {r.jokerMode} | {tostring(r.churn)} | {f4(r.valveFiringRate)} | `
					.. `{f3(r.valveFiringsMean)} | {f4(r.armedRate)} | {r.valveSeenResetsTotal} | {#r.hitActionCapSeeds} |`
			)
		end
		line("")
	end
	line("`seenResets` is in THIS section because `VALVE_SEEN_CAP` clears the whole observation")
	line("window on overflow: a non-zero count means the valve was **blind** for part of those rounds")
	line("rather than merely quiet, and without it a `ResidualLivelock` row cannot say whether the")
	line("valve failed to break the cycle or never saw it.")
	line("")
	line("**Bar-sensitivity ladder.** The firing-rate bar is a judgement on a smooth monotone curve,")
	line("so here is the pool every candidate bar would have selected, measured from this run's own")
	line("search grid. The selected bar is marked.")
	line("")
	local candidates: { Candidate } = if selection ~= nil then selection.candidates else {}
	if #candidates == 0 then
		line("No search grid in this invocation, so no ladder.")
	else
		line("| candidate bar | smallest pool whose worst cell clears it | worst firing rate there |")
		line("|---|---|---|")
		for _, bar in VALVE_RATE_LADDER do
			local bestK, bestJ, bestRate = nil :: number?, nil :: number?, 0
			for _, c in candidates do
				if c.k < K_FLOOR or c.j < J_FLOOR or c.autoPassSeconds == nil then
					continue
				end
				if c.worstValveFiringRate <= bar then
					if bestK == nil or c.k < bestK or (c.k == bestK and c.j < (bestJ :: number)) then
						bestK, bestJ, bestRate = c.k, c.j, c.worstValveFiringRate
					end
				end
			end
			local marker = if bar == VALVE_RATE_MAX_SWEEP then " **<- selected bar**" else ""
			if bestK == nil then
				line(`| {pct(bar)} | none in the searched grid | - |{marker}`)
			else
				line(`| {pct(bar)} | k={bestK}, j={bestJ} | {pct(bestRate)} |{marker}`)
			end
		end
	end
	line("")
	line("### Triage")
	line("")
	local triagePath = `{opts.out}/{TRIAGE_NAME}`
	if fs.isFile(triagePath) then
		local ok, decoded = pcall(function()
			return serde.decode("json", fs.readFile(triagePath))
		end)
		if ok and typeof(decoded) == "table" and decoded.triaged ~= nil then
			line("| seed | N | k | j | mode | classification | outcome | violation | actions | seenResets | cap |")
			line("|---|---|---|---|---|---|---|---|---|---|---|")
			for _, row in decoded.triaged do
				line(
					`| {row.seed} | {row.n} | {row.k} | {row.j} | {row.jokerMode} | **{row.classification}** | `
						.. `{row.outcome} | {tostring(row.violation)} | {row.actions} | {row.valveSeenResets} | {row.cap} |`
				)
			end
		else
			line(`TRIAGE PENDING - \`{triagePath}\` exists but could not be read as triage rows`)
		end
	else
		line("TRIAGE PENDING - run --stage triage and fold the rows in here")
	end
	line("")
	line("Which of `CapArtifact` and `ResidualLivelock` the residual turns out to be decides whether")
	line('the honest claim is "zero stalls" or "zero stalls for the selected pool". 02-09 measured')
	line("`valveSeenResetsTotal = 0` and `hitActionCap = false` across 6,000 gated rounds - every")
	line("gated stall there was a 300s `time-cap` round, which a raised ACTION cap cannot rescue.")
	line("")

	-- 5 ------------------------------------------------------------------------------------
	line("## 5. Stall rate versus auto-pass timeout")
	line("")
	line("**Margin evidence, not what the gate rests on.** Amendment A7 moved the zero-stall result")
	line("onto the engine's valve, so the auto-pass is a secondary mitigation and its deadline is a")
	line("product choice (CARD-16 benches a player after repeated strikes, so a short deadline would")
	line("be striking ordinary players several times a round).")
	line("")
	local apKeys: { string } = {}
	local apGroups: { [string]: { Record } } = {}
	for _, r in byStage("search") do
		if apGroups[r.autoPassLabel] == nil then
			apGroups[r.autoPassLabel] = {}
			table.insert(apKeys, r.autoPassLabel)
		end
		table.insert(apGroups[r.autoPassLabel], r)
	end
	if #apKeys == 0 then
		line("No search grid in this invocation, so no curve.")
	else
		line("| deadline | cells | worst stall | worst firing rate | total auto-passes | auto-pass rate |")
		line("|---|---|---|---|---|---|")
		for _, key in apKeys do
			local group = apGroups[key]
			local stall, valve = worstOf(group)
			local autoPasses, actions = 0, 0
			for _, r in group do
				autoPasses += r.autoPasses
				actions += r.actions
			end
			line(
				`| {key} | {#group} | {f4(stall)} | {f4(valve)} | {autoPasses} | {f4(
					if actions > 0 then autoPasses / actions else 0
				)} |`
			)
		end
	end
	line("")
	local probes = byStage("mechanism", "autopass-probe")
	if #probes > 0 then
		local p = probes[1]
		line(
			`**Auto-pass probe** at a {p.autoPassLabel}s deadline, N={p.n}, k={p.k}, j={p.j} {p.jokerMode}, {p.rounds} rounds: `
				.. `\`autoPassRate = {f4(p.autoPassRate)}\` ({p.autoPasses} auto-passes over {p.actions} actions), against the `
				.. `\`AUTO_PASS_PROBE_MIN_RATE\` bar of {f4(Simulator.AUTO_PASS_PROBE_MIN_RATE)}. The probe exists because at a `
				.. "realistic shipped deadline the auto-pass correctly fires almost never, so its mechanism check has to be "
				.. "a probe rather than a bar on the gated cells."
		)
	else
		line("No auto-pass probe cell in this invocation.")
	end
	line("")

	-- 6 ------------------------------------------------------------------------------------
	line("## 6. Documented negative results")
	line("")
	line("`k = 0` and `j = 0` are swept and REPORTED, never skipped (amendment A5). A dead pool")
	line("excluded by a silent skip is a dead pool nobody can see in the artefact.")
	line("")
	local negatives: { Record } = {}
	for _, r in byStage("search") do
		if (r.k == 0 or r.j == 0) and r.n == 10 and not r.churn and r.autoPassLabel == "5.0" then
			table.insert(negatives, r)
		end
	end
	if #negatives == 0 then
		line("No search grid in this invocation.")
	else
		line("(N=10, churn=false, 5.0s deadline - one slice; every cell is in `02-sweep-data.json`.)")
		line("")
		line("| k | j | mode | circulation | stall | occupancy | DeadPool | Unsat | Livelock | Cap | bars |")
		line("|---|---|---|---|---|---|---|---|---|---|---|")
		for _, r in negatives do
			local o = r.outcomes
			line(
				`| {r.k} | {r.j} | {r.jokerMode} | {r.circulation} | {f4(r.stallRate)} | {f3(r.occupancyMean)} | `
					.. `{o.DeadPool} | {o.Unsatisfiable} | {o.Livelock} | {o.CapReached} | {names(r.failures)} |`
			)
		end
	end
	line("")
	line("The `k=0, j=0` rows are the **dead pool**: circulation `4k + j = 0`, so no card can move")
	line("and `Simulator.runRound` returns `DeadPool` with zero actions. The wild/blocker **cliff**")
	line("at `k = 0` is amendment A4's reason for the `k >= 1` floor: with one card circulating, a")
	line("Blocker joker cannot complete anything, so the joker flag becomes a cliff rather than a")
	line('flag and CARD-12\'s "both variants behind a flag" would be false. `j = 0` is the comparison')
	line("CONTEXT's literal tiebreak would have selected; it is measured here and NOT selected,")
	line("because PROJECT.md records the jokers as a design property.")
	line("")

	-- 7 ------------------------------------------------------------------------------------
	line("## 7. Occupancy")
	line("")
	line(`This is the table that justifies amendment A2's third bar (mean occupancy >= {f3(Simulator.OCCUPANCY_MIN)}).`)
	line("")
	local occRows: { Record } = {}
	for _, r in byStage("search") do
		if r.n == 10 and not r.churn and r.autoPassLabel == "5.0" and r.jokerMode == "Wild" then
			table.insert(occRows, r)
		end
	end
	if #occRows == 0 then
		line("No search grid in this invocation.")
	else
		line("(N=10, Wild, churn=false, 5.0s deadline.)")
		line("")
		line("| k | j | circulation | occupancy | passes the occupancy bar |")
		line("|---|---|---|---|---|")
		for _, r in occRows do
			line(
				`| {r.k} | {r.j} | {r.circulation} | {f3(r.occupancyMean)} | {tostring(
					r.occupancyMean >= Simulator.OCCUPANCY_MIN
				)} |`
			)
		end
	end
	line("")
	line("The dead-table cell sits in this table next to the selection on purpose: `k=0, j=1`")
	line("measures ~0.17 occupancy at ten players and would pass every other bar while being barely")
	line("a game.")
	line("")

	-- 8 ------------------------------------------------------------------------------------
	line("## 8. Carried debt")
	line("")
	line("Verbatim from `02-VALIDATION.md`'s Manual-Only Verifications table:")
	line("")
	line("| Behavior | Requirement | Why Manual | Test Instructions |")
	line("|----------|-------------|------------|-------------------|")
	line(
		"| Whether a bot's reaction-time distribution represents real humans (V-35) | CARD-11 | Unverifiable without real playtests; carried as debt since project init | Calibrate in Phase 4/6 against live sessions |"
	)
	line(
		"| Whether humans deviate from pure greed often enough for the pacing half of G1 to mean anything (A4) | CARD-11 | Same class as V-35, and newly surfaced by this phase's research | Measure deviation rate at the first real playtest |"
	)
	line("")
	line("**Scope note, verbatim.** G1's **solvability** half is a theorem and needs no playtest - it")
	line("does not depend on the bot model at all. Its **pacing** half measures the bot, not the game,")
	line("until the two rows above are closed. Do not let a green pacing number read as a verified")
	line("claim about real players.")
	line("")
	line("**Amendment A7 retired the old load-bearing assumption.** The zero-stall result no longer")
	line("depends on how often humans deviate from pure greed, because the engine's valve deviates")
	line("for them. What remains unverified is therefore the **pacing** model, not the solvability")
	line("claim - and amendment A8 made that valve far MORE load-bearing than A7 claimed: it rescues")
	line("roughly one round in ten at a full roster at the tight pools, not one in four hundred.")
	line("")

	-- 9 ------------------------------------------------------------------------------------
	line("## 9. Reproduction")
	line("")
	line("```")
	line(baseCommand)
	line("```")
	line("")
	line(`- base seed: {BASE_SEED}, one block of {SEED_BLOCK} per cell (cell i runs seeds base + i*block + 1..rounds)`)
	line(`- stages run: {table.concat(stages, ", ")}`)
	line(`- out: {opts.out}`)
	line(`- round cap: {Round.ROUND_CAP_SECONDS}s; Solvability action cap: {Simulator.SOLVABILITY_ACTION_CAP}`)
	line(`- lune: {_VERSION}`)
	line("- every non-cleared round's seed is carried in `02-sweep-data.json` as `failingSeeds`")
	line("  (capped at the first 20 per cell) and `hitActionCapSeeds`, so any row here can be replayed.")
	line("")
	if selection ~= nil then
		line("### The selection rule as implemented")
		line("")
		for _, s in selection.rule do
			line(`{s}`)
		end
		line("")
		line("Departures from CONTEXT's literal rule, recorded rather than hidden:")
		line("")
		for _, s in selection.departures do
			line(`- {s}`)
		end
		line("")
		line("### Every candidate considered, with its named rejections")
		line("")
		line(
			"| k | j | deadline | cells | passed | with margin | rejected by | named failures | margin shortfalls | worst stall | worst firing rate | worst medFirst | worst p95 | worst occupancy |"
		)
		line("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
		for _, c in selection.candidates do
			line(
				`| {c.k} | {c.j} | {c.autoPassLabel} | {c.cells} | {tostring(c.passed)} | {tostring(c.marginPassed)} | `
					.. `{c.rejectedBy or "-"} | {names(c.failures)} | {names(c.marginShortfalls)} | {f4(
						c.worstStallRate
					)} | `
					.. `{f4(c.worstValveFiringRate)} | {f1(c.worstMedianFirst)} | {f1(c.worstP95First)} | {f3(
						c.worstOccupancy
					)} |`
			)
		end
		line("")
	end
	return table.concat(L, "\n") .. "\n"
end

-- ---------------------------------------------------------------------------------------------
-- main
-- ---------------------------------------------------------------------------------------------

local function ensureDir(path: string)
	if not fs.isDir(path) then
		fs.writeDir(path)
	end
end

local function main()
	local argv: { string } = {}
	for _, a in process.args do
		table.insert(argv, a)
	end
	local opts = parseArgs(argv)
	local baseCommand = `lune run scripts/sim/sweep.luau -- {table.concat(argv, " ")}`
	ensureDir(opts.out)

	-- TRIAGE WRITES ONLY `02-triage.json`, AND RETURNS BEFORE ANY OTHER WRITE EXISTS. Every other
	-- stage renders the report and the cell table from its own in-memory table, so a triage run
	-- sharing that path would rewrite both from a table containing nothing but a handful of re-run
	-- seeds - destroying the verdict, the selection block and every cell row immediately before plan
	-- 02-14 commits them. There is no code path from here to either file.
	if opts.stage == "triage" then
		local rows = runTriage(opts)
		local payload = {
			meta = {
				generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
				cap = opts.cap or TRIAGE_CAP_MULTIPLE * Simulator.SOLVABILITY_ACTION_CAP,
				baseCommand = baseCommand,
			},
			triaged = rows,
		}
		fs.writeFile(`{opts.out}/{TRIAGE_NAME}`, serde.encode("json", payload, true))
		print(`sweep: triage wrote {opts.out}/{TRIAGE_NAME} ({#rows} seed(s)); nothing else was written`)
		return
	end

	local stages: { string } = if opts.stage == "both" then { "search", "mechanism", "confirm" } else { opts.stage }
	local roundsPerCell: { [string]: number } = {}

	if opts.stage == "search" then
		print("SEARCH ONLY - NOT A VERDICT: this stage locates the passing region; it makes no selection")
		print("and the mechanism checks are NOT evaluated over it (it contains no twin and no probe).")
	elseif opts.stage == "mechanism" or opts.stage == "confirm" then
		print(`SUB-STAGE - NOT A VERDICT: a bare \`{opts.stage}\` run emits only part of the evidence set.`)
		if opts.stage == "mechanism" then
			print("It fails `valve-twin-missing` and `valve-not-load-bearing` BY CONSTRUCTION, because it")
			print("emits no gated cell for a twin to match. The non-zero exit is the stage's scope, not a")
			print("regression. Use `--stage both` for a verdict.")
		else
			print("It fails `autopass-probe-missing` BY CONSTRUCTION, because the probe cell is the")
			print("mechanism stage's output. The non-zero exit is the stage's scope, not a regression.")
			print("Use `--stage both` for a verdict.")
		end
	end

	local selection: Selection? = nil
	local gatedPass: boolean? = nil

	for _, stage in stages do
		if stage == "search" then
			local rounds = opts.rounds or SEARCH_ROUNDS
			roundsPerCell.search = rounds
			runSearch(rounds)
		elseif stage == "mechanism" then
			local twinRounds = opts.rounds or MECHANISM_ROUNDS
			local probeRounds = opts.rounds or PROBE_ROUNDS
			roundsPerCell.mechanism = twinRounds
			roundsPerCell.probe = probeRounds
			runMechanism(twinRounds, probeRounds)
		elseif stage == "confirm" then
			local pool = opts.pool
			if pool == nil then
				-- `both`: the selection is made here, between the search and the confirmation, from
				-- the search grid in memory. A bare `confirm` needs `--pool`.
				local candidates = buildCandidates()
				if #candidates == 0 then
					fail("sweep: --stage confirm needs either a search grid in the same run or --pool")
				end
				selection = select_(candidates)
				if selection == nil then
					print("sweep: FAILED - no configuration clears the bars, even accepting a bare pass.")
					print("       Every candidate and its named rejections are in the report's section 9.")
					-- The report is still written, because a failure nobody can read is worse than one
					-- that exits non-zero.
					local report = renderReport(opts, stages, nil, nil, {}, roundsPerCell, false, baseCommand)
					fs.writeFile(`{opts.out}/{REPORT_NAME}`, report)
					fs.writeFile(
						`{opts.out}/{DATA_NAME}`,
						serde.encode("json", {
							meta = {
								generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
								stage = opts.stage,
								roundsPerCell = roundsPerCell,
								lune = _VERSION,
								baseSeed = BASE_SEED,
								baseCommand = baseCommand,
								selectionFailed = true,
							},
							candidates = candidates,
							cells = records,
						}, true)
					)
					fail("sweep: no passing configuration")
				end
				local sel = selection :: Selection
				pool = {
					k = sel.k,
					j = sel.j,
					jokerMode = sel.jokerModeDefault,
					autoPassSeconds = sel.autoPassSeconds,
				}
				print(`-- selection: k={sel.k} j={sel.j} ap={sel.autoPassSeconds} marginal={tostring(sel.marginal)}`)
			end
			if pool == nil then
				fail("sweep: --stage confirm needs --pool when it is not preceded by a search")
			end
			local rounds = opts.rounds or CONFIRM_ROUNDS
			roundsPerCell.confirm = rounds
			gatedPass = runConfirm(pool :: PoolSpec, rounds)
			if selection == nil then
				-- A forced `--pool` run still emits a selection block, so the artefact always says
				-- which configuration the numbers belong to.
				selection = {
					k = (pool :: PoolSpec).k,
					j = (pool :: PoolSpec).j,
					jokerModeDefault = (pool :: PoolSpec).jokerMode,
					jokerModesCleared = { "Wild", "Blocker" },
					autoPassSeconds = (pool :: PoolSpec).autoPassSeconds,
					marginal = false,
					marginalReasons = {},
					rule = { "forced by --pool; no search ran in this invocation" },
					departures = {},
					candidates = {},
				}
			end
		end
	end

	-- The mechanism checks are evaluated for every run that EMITS the evidence cells - `both`,
	-- `mechanism` and `confirm` - and NOT for a bare `search`, which contains no twin and no probe
	-- by construction. This is a scoping rule, not an off switch: any run that produces a selection
	-- is held to them, and the result is ANDed into the exit code below.
	local mechanismPass: boolean? = nil
	local mechanismFailures: { string } = {}
	if opts.stage ~= "search" then
		-- BOTH EVIDENCE BOOLEANS FALSE. The sweep claims no deterministic fixture proof and is held
		-- to the statistical thresholds, which are calibrated to ITS round count. Passing `true`
		-- here would borrow the CI subset's fixture proof to excuse a sweep that never fired.
		local pass, failures = Simulator.evaluateMechanisms(cells, {
			deterministicFiringProven = false,
			deterministicTwinProven = false,
		})
		mechanismPass = pass
		mechanismFailures = failures
		print(`-- mechanism checks: {if pass then "pass" else `FAIL ({table.concat(failures, ",")})`}`)
	else
		print("-- mechanism checks: NOT EVALUATED (search stage carries no twin and no probe)")
	end

	local report =
		renderReport(opts, stages, selection, mechanismPass, mechanismFailures, roundsPerCell, gatedPass, baseCommand)
	fs.writeFile(`{opts.out}/{REPORT_NAME}`, report)

	local payload: { [string]: any } = {
		meta = {
			generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			stage = opts.stage,
			stages = stages,
			-- A MAP KEYED BY STAGE, not a scalar: a `both` run uses three different round counts in
			-- one table and one in-memory table can only be written once, so a scalar would have to
			-- be either wrong or the last stage's value. Every cell also carries its own `rounds`,
			-- which is the authority; this map is the convenience.
			roundsPerCell = roundsPerCell,
			lune = _VERSION,
			baseSeed = BASE_SEED,
			baseCommand = baseCommand,
			searchCellCount = searchCellCount(),
			mechanismPass = mechanismPass,
			mechanismFailures = mechanismFailures,
			gatedPass = gatedPass,
			stallRateMax = STALL_RATE_MAX,
			valveFiringRateMax = VALVE_RATE_MAX_SWEEP,
		},
		cells = records,
	}
	-- A bare search run writes NO selection block. The banner is what stops a search-only run being
	-- read as a passing gate, and an absent key is a stronger statement than a null one.
	if selection ~= nil and opts.stage ~= "search" then
		payload.selection = selection
	end
	fs.writeFile(`{opts.out}/{DATA_NAME}`, serde.encode("json", payload, true))

	print(string.format(
		"sweep: %d cells, %d rounds, %.1fs -> %s/%s and %s/%s",
		#records,
		(function(): number
			local total = 0
			for _, r in records do
				total += r.rounds
			end
			return total
		end)(),
		os.clock() - startClock,
		opts.out,
		REPORT_NAME,
		opts.out,
		DATA_NAME
	))

	-- BOTH failures are reported, not just the first. A dead pool forced with `--pool` fails the
	-- bars AND the mechanism checks, and a run that printed only the mechanism line would hide the
	-- reason the configuration cannot be selected behind a sub-stage scoping failure.
	local problems: { string } = {}
	if gatedPass == false then
		local barFailures: { string } = {}
		for _, r in byStage("confirm", "gated") do
			for _, f in r.failures do
				table.insert(barFailures, f)
			end
		end
		table.insert(
			problems,
			`the confirmation stage found no passing configuration (bars: {names(uniqueSorted(barFailures))})`
		)
	end
	if mechanismPass == false then
		table.insert(problems, `mechanism checks: {table.concat(mechanismFailures, ",")}`)
	end
	if #problems > 0 then
		fail(`sweep: FAILED - {table.concat(problems, "; ")}`)
	end
end

main()
