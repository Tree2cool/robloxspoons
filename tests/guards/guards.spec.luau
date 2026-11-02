--!strict
-- Drives every structural guard rule through the REAL CLI (scripts/ci/check-guards.luau) against a deliberately
-- broken fixture tree, and proves the clean tree passes. Each case asserts three things, because a bare exit code
-- cannot tell "failed for the right reason" from "failed for an unrelated reason" (the wave-2 lesson):
--   1. the exit code,
--   2. the EXACT set of rule ids that fired (so a fixture cannot pass by tripping some other rule),
--   3. distinguishing substrings of the diagnostic.
local process = require("@lune/process")

local Test = require("../harness/Test")

type Case = {
	root: string,
	ok: boolean,
	-- the exact set of rule ids expected in the output, sorted; empty for the clean fixture
	rules: { string },
	needles: { string },
}

local FIXTURES = "tests/guards/fixtures"

local CASES: { Case } = {
	{
		root = `{FIXTURES}/import-direct`,
		ok = false,
		rules = { "R2" },
		needles = { "Scoring -> CosmeticsBridge", "src/server/core/Scoring.luau:2" },
	},
	{
		root = `{FIXTURES}/import-transitive`,
		ok = false,
		rules = { "R2" },
		needles = { "CardTable -> Util -> ShopCatalog" },
	},
	{
		root = `{FIXTURES}/import-nonliteral`,
		ok = false,
		rules = { "R3" },
		needles = { "non-literal require", "src/server/core/Scoring.luau:2" },
	},
	{
		root = `{FIXTURES}/import-clean`,
		ok = true,
		rules = {},
		-- exact counts, so a guard that scanned nothing (or skipped the roots) cannot satisfy this case
		needles = { "check-guards: ok (2 files, 1 requires, 2 guarded roots)" },
	},
	{
		root = `{FIXTURES}/engine-suppressed`,
		ok = false,
		rules = { "R3b" },
		needles = { "selene: allow", "src/server/engine/Bad.luau:2" },
	},
	{
		root = `{FIXTURES}/strict-missing`,
		ok = false,
		rules = { "R1" },
		needles = {
			"src/server/services/NoHeader.luau:1",
			"src/server/services/WrongHeader.luau:1",
			"check-guards: 2 violation(s)",
		},
	},
	{
		root = `{FIXTURES}/net-hygiene`,
		ok = false,
		rules = { "R4" },
		needles = { "OnServerEvent may appear only in src/server/services/NetServer.luau", "Sneaky.luau:3" },
	},
	{
		root = `{FIXTURES}/secret-name`,
		ok = false,
		rules = { "R5" },
		needles = { "SpoonDefaultSpot", "src/client/Leak.luau:2" },
	},
	{
		root = `{FIXTURES}/cross-mount`,
		ok = false,
		rules = { "R6" },
		needles = { "cross-mount require", "resolves on disk but not in the DataModel", "src/server/engine/Bad.luau:2" },
	},
}

local function guard(args: { string }): process.ExecResult
	local argv = { "run", "scripts/ci/check-guards.luau" }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("lune", argv)
end

-- The distinct rule ids that appear at the start of an output line, sorted.
local function ruleIds(output: string): { string }
	local seen: { [string]: boolean } = {}
	local list: { string } = {}
	for line in string.gmatch(output, "[^\n]+") do
		local rule = string.match(line, "^(R%d+%a?) ")
		if rule ~= nil and not seen[rule] then
			seen[rule] = true
			table.insert(list, rule)
		end
	end
	table.sort(list)
	return list
end

return function(t: Test.Runner)
	for _, case in CASES do
		t.test(`guard fixture {case.root}`, function()
			local r = guard({ case.root })
			local output = r.stdout .. r.stderr
			t.equal(r.code, if case.ok then 0 else 1, output)
			t.deepEqual(ruleIds(output), case.rules, `wrong rule set fired:\n{output}`)
			for _, needle in case.needles do
				t.contains(output, needle)
			end
			if not case.ok then
				-- a failing run must also say how many violations it found
				t.contains(output, "violation(s)")
			end
		end)
	end

	t.test("guard passes on the real repository (zones.luau present, so R4-R6 are correctly scoped to src/)", function()
		local r = guard({ "." })
		local output = r.stdout .. r.stderr
		t.equal(r.code, 0, output)
		t.contains(output, "check-guards: ok")
		t.deepEqual(ruleIds(output), {}, output)
	end)

	t.test("--print-zones prints the pure zones space-separated and exits 0", function()
		local r = guard({ "--print-zones" })
		t.equal(r.code, 0, r.stdout .. r.stderr)
		t.equal(r.stdout, "src/server/engine src/server/core src/shared/Net\n")
	end)

	t.test("an unknown argument is rejected, not ignored", function()
		local r = guard({ "--no-such-flag" })
		t.equal(r.code, 1)
		t.contains(r.stdout .. r.stderr, "unknown argument: --no-such-flag")
	end)

	t.test("a root that is not a directory fails rather than reading green", function()
		local r = guard({ `{FIXTURES}/does-not-exist` })
		t.equal(r.code, 1)
		t.contains(r.stdout .. r.stderr, "is not a directory")
	end)

	t.test("a root with no .luau files fails rather than reading green", function()
		local r = guard({ "tests/meta/fixtures/empty" })
		t.equal(r.code, 1)
		t.contains(r.stdout .. r.stderr, "a scan of nothing must not look green")
	end)
end
