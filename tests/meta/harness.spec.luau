--!strict
-- Meta-test: proves the runner CAN fail. Without it "tests pass in CI" could be vacuous. Each case spawns the
-- real runner as a child process against a fixture directory and inspects the real exit code.
local process = require("@lune/process")

local Test = require("../harness/Test")

local function runner(args: { string }): process.ExecResult
	-- The literal "--" is part of every documented invocation; Lune 0.11.1 passes it through to the script.
	local argv = { "run", "tests/run.luau", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("lune", argv)
end

return function(t: Test.Runner)
	t.test("runner exits non-zero when a spec fails", function()
		local r = runner({ "--root", "tests/meta/fixtures/failing" })
		t.falsy(r.ok, "runner must report failure")
		t.equal(r.code, 1)
		t.contains(r.stdout .. r.stderr, "deliberate failure")
	end)

	t.test("runner exits zero when a spec passes", function()
		local r = runner({ "--root", "tests/meta/fixtures/passing" })
		t.truthy(r.ok, r.stdout .. r.stderr)
		t.equal(r.code, 0)
		t.contains(r.stdout, "1 passed, 0 failed, 0 todo")
	end)

	t.test("runner exits non-zero when no specs are discovered", function()
		local r = runner({ "--root", "tests/meta/fixtures/empty" })
		t.falsy(r.ok, "an empty run must not look green")
		t.equal(r.code, 1)
		-- Asserting the REASON matters: this case once passed because of an unrelated argument-parse error.
		t.contains(r.stdout .. r.stderr, "no spec files discovered")
	end)

	t.test("runner exits non-zero when a spec registers zero cases and zero todos", function()
		local r = runner({ "--root", "tests/meta/fixtures/zero-cases" })
		t.falsy(r.ok, "a spec that registers nothing must not read green")
		t.equal(r.code, 1)
		t.contains(r.stdout .. r.stderr, "no cases registered")
	end)

	t.test("runner exits non-zero when --filter matches nothing", function()
		local r = runner({ "--root", "tests/meta/fixtures/passing", "--filter", "zzz-matches-nothing" })
		t.falsy(r.ok, "a mistyped filter must not read green")
		t.equal(r.code, 1)
		t.contains(r.stdout .. r.stderr, "matched no cases")
	end)

	t.test("runner --filter runs only the matching cases", function()
		local r = runner({ "--root", "tests/meta/fixtures/passing", "--filter", "supposed to pass" })
		t.truthy(r.ok, r.stdout .. r.stderr)
		t.contains(r.stdout, "1 passed")
	end)

	t.test("runner rejects an unknown argument instead of ignoring it", function()
		local r = runner({ "--nonsense" })
		t.falsy(r.ok)
		t.contains(r.stdout .. r.stderr, "unknown argument: --nonsense")
	end)

	t.test("runner also accepts the invocation form without the -- separator", function()
		local r = process.exec("lune", { "run", "tests/run.luau", "--root", "tests/meta/fixtures/passing" })
		t.truthy(r.ok, r.stdout .. r.stderr)
		t.contains(r.stdout, "1 passed")
	end)

	t.test("fixtures are excluded from the normal sweep", function()
		-- Sweep tests/meta (which contains fixtures/failing) filtered to the fixture's own case name. If the
		-- sweep wrongly entered fixtures, that case would run and fail with "deliberate failure"; when the
		-- exclusion works, nothing matches and the run reports "matched no cases".
		local r = runner({ "--root", "tests/meta", "--filter", "supposed to fail" })
		local out = r.stdout .. r.stderr
		t.contains(out, "matched no cases")
		t.falsy(string.find(out, "deliberate failure", 1, true), "fixture must not run")
	end)
end
