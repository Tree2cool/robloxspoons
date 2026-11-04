--!strict
-- The sweep CLI's smoke test, so a broken sweep fails in CI in two seconds instead of after half
-- an hour (threat T-2-50). It drives the REAL `scripts/sim/sweep.luau` through `process.exec` at
-- one to three rounds per cell -- the house pattern from `tests/ci/analyze.spec.luau` and
-- `tests/maps/validator.spec.luau`.
--
-- EVERY INVOCATION PASSES `--out`, AND `run` REFUSES TO EXEC WITHOUT IT. `--out` defaults to the
-- phase's planning directory, which is where plan 02-14 commits the real `02-G1-REPORT.md`,
-- `02-sweep-data.json` and `02-triage.json`. A case that omitted the flag would overwrite a
-- committed verdict with a three-round table on every subsequent full-suite run -- silently, since
-- the case would still pass. The guard inside `run` is the half that cannot be forgotten; the
-- explicit flag in every argument list is the half a reader can see.
--
-- WHY THE SEARCH STAGE RUNS AT ONE ROUND AND NOT THREE. 02-CONTEXT amendment A8 extended the
-- search grid past k=2, which doubled it to 1,080 cells. At three rounds the one search invocation
-- alone costs ~2.6s and the whole spec misses its budget; at one round it is ~1.1s and every
-- assertion in cases 1-4d still holds, because each of them is about the SHAPE of the output (the
-- cell count, the dead-pool row, the banner, the report's sections) and none is about a rate.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Test = require("../harness/Test")

local SCRATCH = "build/sweep-spec"
-- Case 4c gets its own directory so its byte-identity assertion does not depend on which other
-- case ran first; `tests/run.luau` executes cases in registration order and a case that read
-- another case's output would depend on that order.
local TRIAGE_SCRATCH = "build/sweep-spec-triage"

local REPORT = "02-G1-REPORT.md"
local DATA = "02-sweep-data.json"
local TRIAGE = "02-triage.json"

-- The search grid's dimensions, written out again here ON PURPOSE. Asserting the cell COUNT is
-- what stops a loop-bound bug from silently shrinking the sweep -- the same failure mode plan
-- 02-08 caught with its action-count assertion -- and the assertion only has teeth if the expected
-- number is derived independently of the code under test.
local SEARCH_K = { 0, 1, 2, 3, 4, 6 }
local SEARCH_J = { 0, 1, 2 }
local SEARCH_AUTO_PASS = { 1.5, 3.0, 5.0, 8.0, math.huge }
local SEARCH_N = { 3, 6, 10 }
local JOKER_MODES = { "Wild", "Blocker" }
local CHURN_VARIANTS = { false, true }
local EXPECTED_SEARCH_CELLS = #SEARCH_K * #SEARCH_J * #SEARCH_AUTO_PASS * #SEARCH_N * #JOKER_MODES * #CHURN_VARIANTS

type Run = {
	code: number,
	out: string,
	report: string?,
	data: any,
}

local function run(args: { string }): Run
	local sawOut = false
	for _, a in args do
		if a == "--out" then
			sawOut = true
		end
	end
	if not sawOut then
		error("every sweep invocation in this spec must pass --out, or it writes into .planning/", 0)
	end
	local argv = { "run", "scripts/sim/sweep.luau", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv)
	local out = r.stdout .. r.stderr

	-- The output directory is whatever follows --out.
	local dir = SCRATCH
	for i, a in args do
		if a == "--out" then
			dir = args[i + 1]
		end
	end
	local report: string? = if fs.isFile(`{dir}/{REPORT}`) then fs.readFile(`{dir}/{REPORT}`) else nil
	local data: any = nil
	if fs.isFile(`{dir}/{DATA}`) then
		data = serde.decode("json", fs.readFile(`{dir}/{DATA}`))
	end
	return { code = r.code, out = out, report = report, data = data }
end

-- Lazy and memoised at spec scope: one process per stage shape, shared by every case that reads
-- it, so the spec pays for the 1,080-cell search grid exactly once.
local searchMemo: Run? = nil
local function searchRun(): Run
	if searchMemo == nil then
		searchMemo = run({ "--stage", "search", "--rounds", "1", "--out", SCRATCH })
	end
	return searchMemo :: Run
end

local mechanismMemo: Run? = nil
local function mechanismRun(): Run
	if mechanismMemo == nil then
		mechanismMemo = run({ "--stage", "mechanism", "--rounds", "3", "--out", SCRATCH })
	end
	return mechanismMemo :: Run
end

local confirmMemo: Run? = nil
local function confirmRun(): Run
	if confirmMemo == nil then
		confirmMemo = run({
			"--stage",
			"confirm",
			"--rounds",
			"3",
			"--pool",
			"2,1,Wild,5.0",
			"--out",
			SCRATCH,
		})
	end
	return confirmMemo :: Run
end

return function(t: Test.Runner)
	-- 1 -------------------------------------------------------------------------------------
	t.test("the search stage runs and writes both outputs", function()
		local r = searchRun()
		t.equal(r.code, 0, r.out)
		t.truthy(fs.isFile(`{SCRATCH}/{REPORT}`), "the report must exist")
		t.truthy(fs.isFile(`{SCRATCH}/{DATA}`), "the cell table must exist")
		t.truthy(r.data ~= nil, "the JSON must decode")
		-- A MAP KEYED BY STAGE, indexed by stage rather than asserted as a scalar: a `both` run
		-- carries three different round counts in one table, so a scalar would have to be either
		-- wrong or the last stage's value.
		t.equal(r.data.meta.roundsPerCell.search, 1, "meta.roundsPerCell is keyed by stage")
		t.equal(#r.data.cells, EXPECTED_SEARCH_CELLS, "the search grid's cell count")
		t.equal(r.data.meta.searchCellCount, EXPECTED_SEARCH_CELLS, "the CLI's own count of the grid")
	end)

	-- 2 -------------------------------------------------------------------------------------
	t.test("every cell carries a verdict and its named failures", function()
		local r = searchRun()
		local withFailures, withLockedFailures = 0, 0
		for i, cell in r.data.cells do
			t.equal(typeof(cell.verdict), "boolean", `cell {i} verdict`)
			t.equal(typeof(cell.failures), "table", `cell {i} failures`)
			t.equal(cell.verdict, #cell.failures == 0, `cell {i}: a verdict must agree with its failures`)
			-- THE LOCKED-CONSTANT VIEW RIDES ON EVERY CELL, and asserting its TYPE alone cannot
			-- detect its absence: both fields are initialised (`false` and `{}`) before the bars run,
			-- so a mutation that drops the two assignments leaves a boolean and a table in place and
			-- a type assertion passes. Mutation M11 did exactly that and was caught by nothing. So
			-- the assertion is the INVARIANT instead: a false locked verdict must name its reasons,
			-- and a dropped record is a false verdict with no reasons.
			t.equal(typeof(cell.lockedVerdict), "boolean", `cell {i} lockedVerdict`)
			t.equal(typeof(cell.lockedFailures), "table", `cell {i} lockedFailures`)
			t.equal(
				cell.lockedVerdict,
				#cell.lockedFailures == 0,
				`cell {i}: a locked verdict must agree with its locked failures`
			)
			-- And the two views are ORDERED, which is the other half of "evaluateBars is unchanged":
			-- every locked threshold is at least as strict as the A8 one it was re-derived into
			-- (zero stalls vs a 0.5% ceiling, 1% valve rate vs 7%, identical pacing and occupancy),
			-- so every sweep failure must also appear in the locked list. A sweep bar accidentally
			-- made STRICTER than the locked bar it replaced would break this.
			for _, f in cell.failures do
				local found = false
				for _, g in cell.lockedFailures do
					if f == g then
						found = true
					end
				end
				t.truthy(found, `cell {i}: sweep failure {f} is absent from the locked failures`)
			end
			if #cell.failures > 0 then
				withFailures += 1
			end
			if #cell.lockedFailures > 0 then
				withLockedFailures += 1
			end
		end
		t.truthy(withFailures > 0, "at least one cell must fail, or the report cannot represent a failure")
		t.truthy(withLockedFailures > 0, "at least one cell must carry a locked-bar failure")
	end)

	-- 3 -------------------------------------------------------------------------------------
	t.test("the dead pool is a reported cell, not a skipped one", function()
		local r = searchRun()
		local found = 0
		for _, cell in r.data.cells do
			if cell.k == 0 and cell.j == 0 then
				found += 1
				t.equal(
					cell.outcomes.DeadPool,
					cell.rounds,
					"every round of a k=0,j=0 cell must be classified DeadPool"
				)
				t.equal(cell.actions, 0, "a dead pool moves no card")
			end
		end
		-- Amendment A5: the dead pool is excluded by an ASSERTING result, never by a silent skip,
		-- and the sweep is exactly where a skip would be invisible.
		t.equal(
			found,
			#SEARCH_AUTO_PASS * #SEARCH_N * #JOKER_MODES * #CHURN_VARIANTS,
			"every k=0,j=0 cell of the grid is present"
		)
	end)

	-- 4 -------------------------------------------------------------------------------------
	t.test("the report names every bar, the valve and the carried debt", function()
		local r = searchRun()
		local report = r.report :: string
		t.contains(report, "occupancy")
		t.contains(report, "45s")
		t.contains(report, "120s")
		t.contains(report, "pure greedy")
		t.contains(report, "valve")
		t.contains(report, "V-35")
		t.contains(report, "solvability")
		-- The triage rows are an OUTPUT of the confirm stage that produced the report, so they
		-- cannot exist when it is rendered. Plan 02-14 replaces this placeholder; a placeholder the
		-- next step is told to replace is auditable, a triage run that rewrote the whole report
		-- would not be.
		t.contains(report, "TRIAGE PENDING")
		-- A report that overstated the valve would let the solvability half read as a theorem about
		-- the engine rather than a measurement of a selected pool, which 02-VALIDATION.md's scope
		-- note forbids for the pacing half and amendment A7-CORRECTION forbids for this one.
		t.falsy(string.find(report, "guarantees zero", 1, true), "the report must not claim a guarantee")
	end)

	-- 4d ------------------------------------------------------------------------------------
	t.test("a bare search run is labelled as not a verdict", function()
		local r = searchRun()
		t.equal(r.code, 0, r.out)
		t.contains(r.out, "SEARCH ONLY")
		t.contains(r.report :: string, "SEARCH ONLY")
		-- The search grid has no twin and no probe in it, so the mechanism bars must not be
		-- evaluated over it -- and the banner is what stops a search-only run being read as a
		-- passing gate.
		t.contains(r.out, "mechanism checks: NOT EVALUATED")
		t.equal(r.data.selection, nil, "a bare search run writes NO selection block")
	end)

	-- 4b ------------------------------------------------------------------------------------
	t.test("the mechanism stage emits valve-disabled twins and the auto-pass probe, under their own roles", function()
		local r = mechanismRun()
		local twins, probes = 0, 0
		for _, cell in r.data.cells do
			if cell.antiLivelockValve == false and cell.role == "mechanism" then
				twins += 1
			end
			if cell.autoPassSeconds == 1.0 and cell.role == "autopass-probe" then
				probes += 1
			end
		end
		t.truthy(twins >= 1, "at least one valve-disabled twin under role=mechanism")
		-- The probe's ROLE is asserted, not just its deadline: emitted as "mechanism" instead, plan
		-- 02-09's `autopass-probe-missing` bar would fail on every sweep run and the failure would
		-- look like a missing probe rather than a mislabelled one.
		t.equal(probes, 1, "exactly one cell carries role=autopass-probe at the 1.0s deadline")

		-- THE NON-ZERO EXIT IS THE POINT OF THIS CASE. It proves `evaluateMechanisms` is wired into
		-- the exit code rather than printed. A bare mechanism run emits no gated cell, so the twin
		-- match is empty and both twin bars fire BY CONSTRUCTION -- which is information about the
		-- stage's scope, not a regression, and the CLI says so itself.
		t.equal(r.code, 1, r.out)
		t.contains(r.out, "valve-not-load-bearing")
		t.contains(r.out, "valve-twin-missing")
		t.contains(r.out, "SUB-STAGE")
	end)

	-- 4c ------------------------------------------------------------------------------------
	t.test("the triage stage classifies a seed and clobbers nothing", function()
		-- A confirm run first, so there IS a report and a cell table in the directory for triage to
		-- be proven not to touch.
		local seeded = run({
			"--stage",
			"confirm",
			"--rounds",
			"1",
			"--pool",
			"2,1,Wild,5.0",
			"--out",
			TRIAGE_SCRATCH,
		})
		t.truthy(seeded.report ~= nil, "the confirm run must have written a report to triage against")
		local reportBefore = fs.readFile(`{TRIAGE_SCRATCH}/{REPORT}`)
		local dataBefore = fs.readFile(`{TRIAGE_SCRATCH}/{DATA}`)

		local r = run({
			"--stage",
			"triage",
			"--seeds",
			"1,2,3",
			"--cap",
			"200",
			"--out",
			TRIAGE_SCRATCH,
		})
		t.equal(r.code, 0, r.out)
		t.truthy(fs.isFile(`{TRIAGE_SCRATCH}/{TRIAGE}`), "02-triage.json must exist")
		local triage = serde.decode("json", fs.readFile(`{TRIAGE_SCRATCH}/{TRIAGE}`))
		t.equal(#triage.triaged, 3, "one row per seed")
		for _, row in triage.triaged do
			-- Never an unlabelled failure: which of the two it is decides whether the report's claim
			-- is "zero stalls" or "zero for the selected pool".
			t.truthy(
				row.classification == "CapArtifact" or row.classification == "ResidualLivelock",
				`unlabelled triage classification: {tostring(row.classification)}`
			)
			t.equal(typeof(row.seed), "number")
			t.equal(typeof(row.valveSeenResets), "number")
		end

		-- THIS IS THE HALF THAT PROTECTS THE VERDICT. If triage rendered the report from its own
		-- table it would replace the whole verdict with a three-seed table immediately before plan
		-- 02-14 commits it, and nothing else in the suite would notice.
		t.equal(fs.readFile(`{TRIAGE_SCRATCH}/{REPORT}`), reportBefore, "triage must not touch the report")
		t.equal(fs.readFile(`{TRIAGE_SCRATCH}/{DATA}`), dataBefore, "triage must not touch the cell table")
	end)

	-- 5 -------------------------------------------------------------------------------------
	t.test("the confirm stage honours --pool", function()
		local r = confirmRun()
		local gated, twins = 0, 0
		local seenN: { [number]: true } = {}
		for _, cell in r.data.cells do
			if cell.role == "gated" then
				gated += 1
				t.equal(cell.k, 2, "forced k")
				t.equal(cell.j, 1, "forced j")
				t.equal(cell.antiLivelockValve, true, "a gated cell runs the shipped valve position")
				seenN[cell.n] = true
			elseif cell.role == "mechanism" then
				twins += 1
				t.equal(cell.antiLivelockValve, false, "a twin runs with the valve off")
				t.equal(cell.n, 10, "the twins sit at N=10 only, which is why the twin match is pool-keyed")
			end
		end
		t.equal(gated, #JOKER_MODES * #CHURN_VARIANTS * 8, "8 roster sizes x 2 joker modes x 2 churn variants")
		t.equal(twins, 4, "4 valve-disabled twin cells at the selected pool")
		for n = 3, 10 do
			t.truthy(seenN[n], `the confirm stage must cover N={n}`)
		end
		-- The exit code AND the named failure, not just the shape: a bare confirm run emits no
		-- auto-pass probe, because the probe is the mechanism stage's output.
		t.equal(r.code, 1, r.out)
		t.contains(r.out, "autopass-probe-missing")
		t.contains(r.out, "SUB-STAGE")
	end)

	-- 6 -------------------------------------------------------------------------------------
	t.test("an unknown argument exits 1", function()
		-- `--stage search --rounds 1` is here even though the run must die before it reaches a cell.
		-- Without it, a mutation that makes an unknown argument IGNORED falls through to the default
		-- `--stage both` at the default round counts -- a half-hour run inside a two-second spec.
		-- Every guard case in this file is bounded for that reason: a guard's mutation proof must
		-- fail fast, not run the whole sweep.
		local r = run({ "--no-such-flag", "--stage", "search", "--rounds", "1", "--out", SCRATCH })
		t.equal(r.code, 1, r.out)
		t.contains(r.out, "unknown argument: --no-such-flag")
	end)

	-- 7 -------------------------------------------------------------------------------------
	t.test("the sweep exits non-zero when it cannot select", function()
		local r = run({
			"--stage",
			"confirm",
			"--rounds",
			"1",
			"--pool",
			"0,0,Wild,1.5",
			"--out",
			SCRATCH,
		})
		-- A sweep that cannot select must fail LOUDLY rather than writing an empty verdict, and the
		-- message must name the failure: the dead pool's gated cells report `no-completions`, which
		-- is a different thing from the sub-stage scoping failure that accompanies it.
		t.equal(r.code, 1, r.out)
		t.contains(r.out, "no passing configuration")
		t.contains(r.out, "no-completions")
	end)

	-- 8 -------------------------------------------------------------------------------------
	t.test("a triage-only flag outside triage is refused, not ignored", function()
		-- A flag that is silently ignored is the same defect as a flag that is misspelled: the run
		-- does something other than what was asked and exits 0.
		-- Bounded with `--rounds 1` for the same reason as the case above: dropping the guard must
		-- make this case fail in a second, not run the real search grid.
		local r = run({ "--stage", "search", "--seeds", "1,2", "--rounds", "1", "--out", SCRATCH })
		t.equal(r.code, 1, r.out)
		t.contains(r.out, "triage-only")
	end)

	-- 9 -------------------------------------------------------------------------------------
	t.test("the spec leaves no scratch output behind", function()
		for _, dir in { SCRATCH, TRIAGE_SCRATCH } do
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			t.falsy(fs.isDir(dir), `{dir} must be cleaned up`)
		end
	end)
end
