--!strict
-- One local command that mirrors the whole CI chain (D-04, D-17).
--
--   lune run scripts/verify.luau            run every step in CI order; stop at the first failure
--   lune run scripts/verify.luau --list     print the chain without running it (diff it against ci.yml)
--
-- The `run` strings below are character-for-character the `run:` lines of .github/workflows/ci.yml, including the
-- `${{ steps.zones.outputs.list }}` placeholder, so the two cannot drift silently: tests/ci/verify.spec.luau
-- compares them. Steps stop at the FIRST failure on purpose; a wall of cascading errors hides the real one.
-- Never add a luau-lsp formatter override or a Selene warnings allowance: both turn a hard-fail gate into a pass.
--
-- The pure-zone list is captured with its status checked and asserted non-empty, then spliced in. An empty list
-- would silently drop the FOUND-06 layers while every step stayed green.
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local ZONES_PLACEHOLDER = "${{ steps.zones.outputs.list }}"

type Step = { name: string, run: string, kind: "shell" | "zones" }

local STEPS: { Step } = {
	{
		name = "Tool versions",
		kind = "shell",
		run = "rojo --version && stylua --version && selene --version && luau-lsp --version && lune --version",
	},
	{ name = "Lune typedefs", kind = "shell", run = "lune setup" },
	{ name = "Format", kind = "shell", run = "stylua --check src scripts tests" },
	{ name = "Lint (shipped code, Roblox std)", kind = "shell", run = "selene src scripts tests" },
	{
		name = "Pure zone list",
		kind = "zones",
		run = "lune run scripts/ci/check-guards.luau --print-zones",
	},
	{
		name = "Lint (pure zones, FOUND-06 allow-list)",
		kind = "shell",
		run = `selene --config selene.pure.toml {ZONES_PLACEHOLDER}`,
	},
	{
		name = "Sourcemap",
		kind = "shell",
		run = "rojo sourcemap default.project.json --include-non-scripts -o sourcemap.json",
	},
	{
		name = "Typecheck (roblox platform)",
		kind = "shell",
		run = 'lune run scripts/ci/analyze.luau --platform roblox --sourcemap sourcemap.json --definitions=tools/types/globalTypes.None.d.luau --base-luaurc .luaurc --ignore "**/fixtures/**" src',
	},
	{
		name = "Typecheck (standard platform, pure zones + tooling)",
		kind = "shell",
		run = `lune run scripts/ci/analyze.luau --platform standard --base-luaurc .luaurc --ignore "**/fixtures/**" {ZONES_PLACEHOLDER} scripts tests`,
	},
	{
		name = "Structural guards (FOUND-02 / FOUND-05 / FOUND-06 / R4 / R5)",
		kind = "shell",
		run = "lune run scripts/ci/check-guards.luau",
	},
	{
		name = "Map contract (MAP-01)",
		kind = "shell",
		run = "lune run scripts/maps/validate-map.luau maps/gray-box.rbxm",
	},
	{
		name = "Tests (unit, fuzz, guard fixtures, traps, map validator)",
		kind = "shell",
		run = "lune run tests/run.luau",
	},
	{
		name = "Build",
		kind = "shell",
		run = "mkdir -p build && rojo build default.project.json -o build/spoons.rbxl",
	},
	{
		name = "Built-place require check (FOUND-03)",
		kind = "shell",
		run = "lune run scripts/ci/check-built-place.luau build/spoons.rbxl",
	},
}

local function tokenize(segment: string): { string }
	local tokens: { string } = {}
	for token in string.gmatch(segment, "%S+") do
		local stripped = string.gsub(token, '^"(.*)"$', "%1")
		table.insert(tokens, stripped)
	end
	return tokens
end

local function splitAnd(command: string): { string }
	local segments: { string } = {}
	local from = 1
	while true do
		local s, e = string.find(command, "&&", from, true)
		if s == nil or e == nil then
			table.insert(segments, string.sub(command, from))
			return segments
		end
		table.insert(segments, string.sub(command, from, s - 1))
		from = e + 1
	end
end

local function fail(step: Step, shown: string, result: process.ExecResult?, why: string)
	stdio.ewrite(`\nFAILED: {step.name}\n  command: {shown}\n  reason:  {why}\n`)
	if result ~= nil then
		stdio.ewrite(`--- stdout ---\n{result.stdout}\n--- stderr ---\n{result.stderr}\n`)
	end
	stdio.ewrite("verify: stopped at the first failure (later steps were NOT run)\n")
	process.exit(1)
end

-- Runs one `&&`-joined command; returns the captured stdout of the last segment.
local function runCommand(step: Step, command: string): string
	local lastOut = ""
	for _, segment in splitAnd(command) do
		local tokens = tokenize(segment)
		local program = table.remove(tokens, 1)
		if program == nil then
			fail(step, command, nil, "empty command segment")
			return ""
		end
		if program == "mkdir" then
			-- `mkdir -p <dir>`: the one shell built-in the chain uses; rojo build does not create its output dir.
			local dir = tokens[#tokens]
			if dir == nil then
				fail(step, command, nil, "mkdir with no directory")
				return ""
			end
			fs.writeDir(dir)
			continue
		end
		local result = process.exec(program, tokens)
		if not result.ok then
			fail(step, command, result, `exit code {result.code}`)
		end
		lastOut = result.stdout
	end
	return lastOut
end

local function manualSection()
	local text = fs.readFile("MANUAL-CHECKS.md")
	local unsigned: { string } = {}
	local signed = 0
	local currentHeading: string? = nil
	for line in string.gmatch(text, "[^\n]+") do
		if string.match(line, "^## M%-%d%d") ~= nil then
			currentHeading = string.gsub(line, "^##%s*", "")
		elseif string.match(line, "^%- %[.%] M%-%d%d signed off") ~= nil and currentHeading ~= nil then
			if string.sub(line, 4, 4) == "x" then
				signed += 1
			else
				table.insert(unsigned, currentHeading)
			end
			currentHeading = nil
		end
	end
	print("")
	print("============================================================================")
	print("NOT VERIFIED HERE - needs a human with Studio (see MANUAL-CHECKS.md)")
	print("============================================================================")
	for _, heading in unsigned do
		print(`  [ ] {heading}`)
	end
	print(`  {signed} signed off, {#unsigned} unsigned.`)
	print("An unsigned manual check does not fail this script: it is a human gate, not a build error,")
	print("but Phase 1 is not closed until every box in MANUAL-CHECKS.md is ticked.")
end

local function main(args: { string })
	local listOnly = false
	for _, a in args do
		if a == "--list" then
			listOnly = true
		elseif a ~= "--" then
			stdio.ewrite(`verify: unknown argument: {a}\n`)
			process.exit(1)
		end
	end
	if listOnly then
		for i, step in STEPS do
			print(`{i}. {step.name}`)
			print(`   {step.run}`)
		end
		return
	end

	local zones = ""
	local started = os.clock()
	for i, step in STEPS do
		print(`-> [{i}/{#STEPS}] {step.name}`)
		local t0 = os.clock()
		if step.kind == "zones" then
			zones = string.gsub(runCommand(step, step.run), "%s+$", "")
			if zones == "" then
				fail(step, step.run, nil, "empty pure-zone list - the FOUND-06 gate would be vacuous")
			end
			print(`   pure zones: {zones}`)
		else
			local command = step.run
			local s, e = string.find(command, ZONES_PLACEHOLDER, 1, true)
			if s ~= nil and e ~= nil then
				if zones == "" then
					fail(step, step.run, nil, "step needs the pure-zone list but it was never captured")
				end
				command = string.sub(command, 1, s - 1) .. zones .. string.sub(command, e + 1)
			end
			runCommand(step, command)
		end
		print(string.format("   ok %s (%.1fs)", step.name, os.clock() - t0))
	end
	print(string.format("\nverify: all %d automated steps passed in %.1fs", #STEPS, os.clock() - started))
	manualSection()
end

main(process.args)
