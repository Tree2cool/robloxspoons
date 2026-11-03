--!strict
-- scripts/ci/analyze.luau is the single luau-lsp gate (final detector form, 01-VALIDATION). Every failure case
-- asserts the REASON substring, not only the exit code: a bare exit 1 cannot tell the right failure from an
-- unrelated one. The inputs are the same real-CLI fixtures plan 01-04 used for the exit-code traps.
local fs = require("@lune/fs")
local process = require("@lune/process")

local Test = require("../harness/Test")

local DEFS = "--definitions=tools/types/globalTypes.None.d.luau"
local SCRATCH = "build/ci-analyze"
local GOOD = "tests/purity/fixtures/engine-clean/src/server/engine/Good.luau"

local function gate(args: { string }): (process.ExecResult, string)
	local argv = { "run", "scripts/ci/analyze.luau" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv)
	return r, r.stdout .. r.stderr
end

return function(t: Test.Runner)
	t.test("analyze gate: a clean file passes with exit 0", function()
		local r, out = gate({ "--platform", "standard", "--base-luaurc", ".luaurc", GOOD })
		t.equal(r.code, 0, out)
		t.contains(out, "analyze: ok")
	end)

	t.test("analyze gate: a real TypeError fails, for the TypeError reason", function()
		local r, out = gate({ "--platform", "standard", "tests/traps/fixtures/type-error/TypeError.luau" })
		t.equal(r.code, 1, out)
		t.contains(out, "TypeError")
		t.contains(out, "analyze: FAILED")
	end)

	t.test("analyze gate: a lint-only finding fails on the exit code", function()
		local r, out = gate({ "--platform", "standard", "tests/traps/fixtures/lint-only/Lint.luau" })
		t.equal(r.code, 1, out)
		t.contains(out, "LocalUnused")
		t.contains(out, "luau-lsp exited 1")
	end)

	t.test("analyze gate: a MISSING sourcemap fails although luau-lsp exits 0", function()
		fs.writeDir(SCRATCH)
		local r, out = gate({ "--platform", "roblox", "--sourcemap", `{SCRATCH}/nope.json`, DEFS, GOOD })
		t.equal(r.code, 1, out)
		t.contains(out, 'output contains "Failed to load"')
	end)

	t.test("analyze gate: a MALFORMED sourcemap fails although luau-lsp exits 0 and prints no [ERROR]", function()
		fs.writeDir(SCRATCH)
		fs.writeFile(`{SCRATCH}/malformed.json`, "{ this is not json\n")
		local r, out = gate({ "--platform", "roblox", "--sourcemap", `{SCRATCH}/malformed.json`, DEFS, GOOD })
		t.equal(r.code, 1, out)
		t.contains(out, 'output contains "Sourcemap parsing failed"')
		t.falsy(
			string.find(out, "[ERROR]", 1, true),
			"this case has no [ERROR] line, so an [ERROR] counter would pass it"
		)
	end)

	t.test("analyze gate: a valid sourcemap passes", function()
		fs.writeDir(SCRATCH)
		fs.writeFile(`{SCRATCH}/valid.json`, '{"name":"game","className":"DataModel","children":[]}\n')
		local r, out = gate({ "--platform", "roblox", "--sourcemap", `{SCRATCH}/valid.json`, DEFS, GOOD })
		t.equal(r.code, 0, out)
		t.contains(out, "analyze: ok")
	end)

	t.test("analyze gate: --formatter is refused, in both spellings", function()
		local r1, out1 = gate({ "--formatter", "plain", GOOD })
		t.equal(r1.code, 1, out1)
		t.contains(out1, "refusing --formatter")
		local r2, out2 = gate({ "--formatter=plain", GOOD })
		t.equal(r2.code, 1, out2)
		t.contains(out2, "refusing --formatter")
	end)

	t.test("analyze gate: no paths means no gate, and is refused", function()
		local r, out = gate({})
		t.equal(r.code, 1, out)
		t.contains(out, "refusing to run a gate that analyses nothing")
	end)
end
