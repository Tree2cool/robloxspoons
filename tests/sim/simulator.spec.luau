--!strict
-- `scripts/sim/Simulator` (plan 02-09 task 2): the two modes, the six-category taxonomy and the
-- metrics. These are the SIMULATOR's own behaviour cases. The G1 regression subset, the gate and
-- the gate's seven falsifiability mutations live in `tests/sim/subset.spec.luau` (task 3).
--
-- Every case here drives the REAL engine through `Simulator.runRound`, so a result about a case
-- here is a result about the shipped `Engine.apply` and the shipped `Valve`.
local Pool = require("../../src/server/engine/Pool")
local Simulator = require("../../scripts/sim/Simulator")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

-- The provisional reference pool (02-CONTEXT amendment A4 and plan 02-10's starting point).
local REF_K = 2
local REF_J = 1

local function opts(
	n: number,
	k: number,
	j: number,
	mode: Types.JokerMode,
	simMode: Simulator.SimMode,
	overrides: {
		valve: boolean?,
		autoPassSeconds: number?,
		churn: boolean?,
		churnLeavers: number?,
		sabotage: Simulator.Sabotage?,
		seed: number?,
		identityCheck: boolean?,
		actionCap: number?,
	}
): Simulator.SimOpts
	local config = Pool.poolConfig(n, k, j, mode)
	if overrides.valve ~= nil then
		config.antiLivelockValve = overrides.valve
	end
	return {
		n = n,
		config = config,
		seed = overrides.seed or 1,
		mode = simMode,
		autoPassSeconds = overrides.autoPassSeconds or 5.0,
		churn = overrides.churn or false,
		churnLeavers = overrides.churnLeavers,
		sabotage = overrides.sabotage or "None",
		identityCheck = overrides.identityCheck or false,
		actionCap = overrides.actionCap,
	}
end

-- Cases 3 and 4 both need the valve-OFF outcome of the same 80 seeds, and `tests/run.luau` runs
-- cases in registration order -- so a case reading another case's local would depend on that order.
-- One lazy shared scan makes the dependency explicit and halves the cost.
local SOLVABILITY_SEEDS = 80
local cachedValveOff: { [number]: string }? = nil

local function valveOffOutcomes(): { [number]: string }
	local cached = cachedValveOff
	if cached ~= nil then
		return cached
	end
	local out: { [number]: string } = {}
	for seed = 1, SOLVABILITY_SEEDS do
		out[seed] = Simulator.runRound(opts(10, 2, 2, "Wild", "Solvability", {
			valve = false,
			autoPassSeconds = math.huge,
			seed = seed,
		})).outcome
	end
	cachedValveOff = out
	return out
end

return function(t: Test.Runner)
	t.test("Pacing at the reference pool clears for the great majority of seeds, with a plausible TTFC", function()
		local cleared, total = 0, 40
		local lo, hi = math.huge, 0
		for seed = 1, total do
			local r = Simulator.runRound(opts(10, REF_K, REF_J, "Wild", "Pacing", { seed = seed }))
			if r.outcome == "Cleared" then
				cleared += 1
			end
			local first = r.firstCompletionSeconds
			t.truthy(first ~= nil, `seed {seed}: outcome {r.outcome} produced no first completion`)
			if first ~= nil then
				lo = math.min(lo, first)
				hi = math.max(hi, first)
			end
		end
		print(
			`    reference pool TTFC over {total} seeds: {string.format("%.2f", lo)}s .. {string.format("%.2f", hi)}s, cleared {cleared}/{total}`
		)
		t.equal(cleared, total, "every reference-pool round must clear")
		t.truthy(lo >= 3.0, `the fastest first completion was {lo}s, below the plausible floor of 3s`)
		t.truthy(hi <= 30.0, `the slowest first completion was {hi}s, above the plausible ceiling of 30s`)
	end)

	t.test("a k=0, j=0 pool is reported as DeadPool and does not error", function()
		local r = Simulator.runRound(opts(10, 0, 0, "Wild", "Pacing", {}))
		t.equal(r.outcome, "DeadPool")
		t.equal(r.actions, 0)
		t.equal(r.violation, "DeadPool")
		t.truthy(r.seed ~= nil, "a DeadPool result still carries its seed")
	end)

	t.test("Solvability with the valve OFF livelocks on some seeds and clears on others", function()
		-- k=2, j=2 is research's bad pool: 21.6% of rounds livelock under pure greed. Using it here
		-- rather than the reference pool is deliberate -- at k=2,j=1 the valve-off stall rate is
		-- 0.25%, so a case built on it would need ~2,000 seeds to see one Livelock and would be a
		-- coin flip at 80.
		local livelocked, cleared = 0, 0
		for _, outcome in valveOffOutcomes() do
			if outcome == "Livelock" then
				livelocked += 1
			elseif outcome == "Cleared" then
				cleared += 1
			end
		end
		print(`    valve OFF, k=2 j=2, {SOLVABILITY_SEEDS} seeds: {livelocked} Livelock, {cleared} Cleared`)
		t.truthy(livelocked >= 1, "pure greed must livelock on at least one seed at k=2, j=2")
		t.truthy(cleared >= 1, "pure greed must also clear on at least one seed")
		t.equal(livelocked + cleared, SOLVABILITY_SEEDS, "every round must land in one of the two categories")
	end)

	t.test("the valve rescues exactly the seeds that livelocked without it", function()
		local rescued, firings = 0, 0
		local checked = 0
		for seed, offOutcome in valveOffOutcomes() do
			if offOutcome ~= "Livelock" then
				continue
			end
			checked += 1
			local on = Simulator.runRound(opts(10, 2, 2, "Wild", "Solvability", {
				valve = true,
				autoPassSeconds = math.huge,
				seed = seed,
			}))
			t.equal(on.outcome, "Cleared", `seed {seed} livelocked without the valve and did not clear with it`)
			t.truthy(on.valveFirings >= 1, `seed {seed} cleared with the valve on but the valve never fired`)
			rescued += 1
			firings += on.valveFirings
		end
		print(`    rescued {rescued}/{checked} livelocked seeds, {firings} total firings`)
		t.truthy(checked >= 1, "the case asserts nothing unless at least one seed livelocked")
	end)

	t.test("a destroyed-card round is Unsatisfiable, classified from the PREDICATE", function()
		-- 30 rounds, not 120: the measured Unsatisfiable rate is 77% of churned sabotage rounds
		-- (subset.spec.luau carries the arithmetic), so the chance of seeing none in 30 is 0.23^30,
		-- about 1e-19, and a destroyed-card round is the most expensive round this simulator runs.
		local unsat, other = 0, {}
		for seed = 1, 30 do
			local r = Simulator.runRound(opts(10, REF_K, REF_J, "Wild", "Pacing", {
				churn = true,
				sabotage = "DestroyRemovedCards",
				seed = seed,
			}))
			if r.outcome == "Unsatisfiable" then
				unsat += 1
				-- The name proves the classification came from `Invariants.satisfiable`, not from
				-- `check`'s first-violation name: `check` reports `circulation` (violation 4) for a
				-- destroyed card and never reaches the satisfiability test (violation 9).
				t.equal(r.violation, "satisfiable-false")
			else
				other[r.outcome] = (other[r.outcome] or 0) + 1
			end
		end
		print(`    sabotage over 30 rounds: {unsat} Unsatisfiable; other outcomes:`)
		for name, count in other do
			print(`      {name} = {count}`)
		end
		t.truthy(unsat >= 1, "destroying routed cards must produce at least one Unsatisfiable round in 30")
	end)

	t.test("a roster shortfall is its own category, not CapReached", function()
		-- ONE leaver can never cause a shortfall and that is arithmetic, not luck:
		-- live = seatCount - completions - churn and remaining = seatCount - 1 - completions, so
		-- live < remaining is exactly churn > 1. Hence churnLeavers = 3.
		local shortfall, cap, cleared = 0, 0, 0
		for seed = 1, 60 do
			local r = Simulator.runRound(opts(10, REF_K, REF_J, "Wild", "Pacing", {
				churn = true,
				churnLeavers = 3,
				seed = seed,
			}))
			if r.outcome == "RosterShortfall" then
				shortfall += 1
			elseif r.outcome == "CapReached" then
				cap += 1
			elseif r.outcome == "Cleared" then
				cleared += 1
			end
		end
		print(`    3 leavers over 60 rounds: {shortfall} RosterShortfall, {cleared} Cleared, {cap} CapReached`)
		t.truthy(shortfall >= 1, "three leavers must drop the roster below the spoon count at least once in 60")
		t.equal(cap, 0, "a roster shortfall must never be reported as CapReached")
	end)

	t.test("one leaver can NEVER cause a shortfall, so the gated churn cells see none", function()
		local shortfall = 0
		for seed = 1, 60 do
			local r = Simulator.runRound(opts(10, REF_K, REF_J, "Wild", "Pacing", { churn = true, seed = seed }))
			if r.outcome == "RosterShortfall" then
				shortfall += 1
			end
		end
		t.equal(shortfall, 0, "with one leaver, live seats equal the remaining spoons and never fall below")
	end)

	t.test("a round is a pure function of its SimOpts, and always carries its seed", function()
		local o = opts(10, REF_K, REF_J, "Wild", "Pacing", { churn = true, seed = 4242 })
		local a = Simulator.runRound(o)
		local b = Simulator.runRound(o)
		t.deepEqual(b, a, "two runs of identical SimOpts must agree in every field")
		t.equal(a.seed, 4242)
		t.truthy(type(a.valveSeenResets) == "number", "valveSeenResets must reach RoundResult as a number")
	end)

	t.test("occupancy distinguishes a one-card table from a busy one", function()
		local thin = Simulator.runCell(opts(10, 0, 1, "Wild", "Pacing", {}), 40, "diagnostic")
		local busy = Simulator.runCell(opts(10, 2, 2, "Wild", "Pacing", {}), 40, "diagnostic")
		print(
			`    occupancy k=0 j=1: {string.format("%.3f", thin.occupancyMean)}; k=2 j=2: {string.format(
				"%.3f",
				busy.occupancyMean
			)}`
		)
		t.truthy(thin.occupancyMean < 0.60, `k=0, j=1 occupancy was {thin.occupancyMean}, not below the 0.60 bar`)
		t.truthy(busy.occupancyMean > 0.60, `k=2, j=2 occupancy was {busy.occupancyMean}, not above the 0.60 bar`)
	end)

	t.test("runCell aggregates the counts, the rates and the valve metrics", function()
		local cell = Simulator.runCell(opts(10, REF_K, REF_J, "Wild", "Pacing", {}), 50)
		t.equal(cell.rounds, 50)
		t.equal(cell.role, "gated")
		t.equal(cell.n, 10)
		t.equal(cell.k, REF_K)
		t.equal(cell.j, REF_J)
		t.equal(cell.jokerMode, "Wild")
		t.equal(cell.outcomes.Cleared, 50)
		t.equal(cell.stallRate, 0)
		t.equal(cell.firstCompletionSamples, 50)
		t.truthy(cell.medianFirst ~= nil and cell.p95First ~= nil, "a cell with completions carries both quantiles")
		t.truthy(cell.dealAttemptMean >= 1.0, "a deal always takes at least one attempt")
		t.truthy(cell.dealAttemptMax >= 1, "the deal-attempt maximum is observed, not derived")
		t.equal(cell.valveSeenResetsTotal, 0)
		t.equal(#cell.failingSeeds, 0)
	end)
end
