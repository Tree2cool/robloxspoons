--!strict
-- Drift guard (T-1-45): scripts/verify.luau must run exactly the steps in .github/workflows/ci.yml, in the same order,
-- with the same commands. The check reads the real `--list` output and the real workflow file.
local fs = require("@lune/fs")
local process = require("@lune/process")

local Test = require("../harness/Test")

type Step = { name: string, run: string? }

-- Single-line `run:` values only; the one block-scalar step (Pure zone list) is compared by name.
local function parseWorkflow(text: string): { Step }
	local steps: { Step } = {}
	local current: Step? = nil
	for line in string.gmatch(text, "[^\n]+") do
		local name = string.match(line, "^      %- name: (.+)$")
		if name ~= nil then
			current = { name = name, run = nil }
			table.insert(steps, current :: Step)
		else
			local run = string.match(line, "^        run: (.+)$")
			if run ~= nil and current ~= nil and run ~= "|" then
				(current :: Step).run = run
			end
		end
	end
	return steps
end

local function parseList(output: string): { Step }
	local steps: { Step } = {}
	local current: Step? = nil
	for line in string.gmatch(output, "[^\n]+") do
		local name = string.match(line, "^%d+%. (.+)$")
		if name ~= nil then
			current = { name = name, run = nil }
			table.insert(steps, current :: Step)
		elseif current ~= nil then
			(current :: Step).run = string.match(line, "^   (.+)$")
		end
	end
	return steps
end

return function(t: Test.Runner)
	local ci = parseWorkflow(fs.readFile(".github/workflows/ci.yml"))
	local listed = process.exec("lune", { "run", "scripts/verify.luau", "--list" })
	t.equal(listed.code, 0, listed.stderr)
	local verify = parseList(listed.stdout)

	t.test("verify chain: both lists are non-trivial (a parser that finds nothing proves nothing)", function()
		t.truthy(#ci >= 14, `ci.yml steps parsed: {#ci}`)
		t.truthy(#verify >= 14, `verify steps parsed: {#verify}`)
	end)

	t.test("verify chain: same step names in the same order as ci.yml", function()
		t.equal(#verify, #ci, "step count differs between verify.luau and ci.yml")
		for i, step in ci do
			t.equal(verify[i].name, step.name, `step {i} differs`)
		end
	end)

	t.test("verify chain: every single-line ci.yml run command is identical in verify.luau", function()
		local compared = 0
		for i, step in ci do
			if step.run ~= nil then
				compared += 1
				t.equal(verify[i].run, step.run, `command of step '{step.name}' differs`)
			end
		end
		t.truthy(compared >= 12, `only {compared} commands compared`)
	end)

	t.test("verify chain: neither gate file contains a bypass flag", function()
		for _, path in { ".github/workflows/ci.yml", "scripts/verify.luau", ".githooks/pre-commit" } do
			local text = fs.readFile(path)
			t.falsy(string.find(text, "allow-warnings", 1, true), `{path} contains allow-warnings`)
			t.falsy(string.find(text, "continue-on-error", 1, true), `{path} contains continue-on-error`)
			t.falsy(string.find(text, "%-%-formatter[%s=]+plain") ~= nil, `{path} contains --formatter plain`)
		end
	end)

	t.test("ci.yml: SHA-pinned action, read-only token, every-push trigger, one inlined-zone consumer set", function()
		local text = fs.readFile(".github/workflows/ci.yml")
		t.contains(text, "CompeyDev/setup-rokit@1d9390883f7ebce19d48f5b8d006e11d387c92ab")
		t.contains(text, "version: v1.2.0")
		t.contains(text, "contents: read")
		t.contains(text, "  push:\n  pull_request:")
		t.falsy(string.find(text, "branches", 1, true), "push must not filter branches (D-02)")
		t.contains(text, 'test -n "$zones"')
		local _, consumers = string.gsub(text, "steps%.zones%.outputs%.list", "")
		t.equal(consumers, 2)
		local _, inlined = string.gsub(text, "print%-zones%)", "")
		t.equal(inlined, 1, "--print-zones must be captured once, never spliced inline elsewhere")
	end)

	t.test("pre-commit hook is fast checks only (D-03)", function()
		local text = fs.readFile(".githooks/pre-commit")
		t.contains(text, "stylua --check --respect-ignores")
		t.contains(text, "selene $files")
		t.falsy(string.find(text, "luau-lsp", 1, true), "typecheck belongs in CI")
		t.falsy(string.find(text, "tests/run.luau", 1, true), "tests belong in CI")
	end)
end
