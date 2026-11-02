--!strict
-- The single test entrypoint (FOUND-03):
--   lune run tests/run.luau [-- --filter <substring>] [--root <dir>] [--seed <n>]
-- Discovers <root>/**/*.spec.luau, registers each spec's cases on a fresh runner, executes them in pcall and
-- exits non-zero on ANY of: a failing case, a spec that fails to load, a spec that registers nothing, a run
-- that discovers no specs, or a filter that matches nothing. Every one of those is a way for a suite to read
-- green while verifying nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")

local Test = require("./harness/Test")

local SPEC_SUFFIX = ".spec.luau"

-- Spec paths are discovered at runtime, so the require string is computed. luau-lsp can only resolve literal
-- require strings ("Unknown require: unsupported path"), so this one call is deliberately typed as dynamic.
-- Lune itself resolves it fine, which the harness meta-test and the full run prove.
local dynamicRequire: (string) -> any = require :: any

local function parseArgs(args: { string }): (string?, string, number)
	local filter: string? = nil
	local root = "tests"
	local seed = 1
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--" then
			-- Lune 0.11.1 does NOT consume the "--" separator: `lune run x -- --filter y` delivers "--" as
			-- args[1]. Tolerate it so both documented invocation forms work.
			i += 1
		elseif a == "--filter" then
			filter = args[i + 1]
			i += 2
		elseif a == "--root" then
			root = args[i + 1]
			i += 2
		elseif a == "--seed" then
			local n = tonumber(args[i + 1])
			if n == nil then
				print(`unusable --seed value: {tostring(args[i + 1])}`)
				process.exit(1)
			else
				seed = n
			end
			i += 2
		else
			print(`unknown argument: {a}`)
			process.exit(1)
		end
	end
	return filter, root, seed
end

local function discover(dir: string, includeFixtures: boolean, found: { string })
	local names = fs.readDir(dir)
	table.sort(names)
	for _, name in names do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			-- Fixtures are deliberately broken (guards, purity, traps, meta). They must never be swept into the
			-- normal run; they are only reachable by pointing --root at (or inside) a fixtures directory.
			if includeFixtures or name ~= "fixtures" then
				discover(path, includeFixtures, found)
			end
		elseif string.sub(name, -#SPEC_SUFFIX) == SPEC_SUFFIX then
			table.insert(found, path)
		end
	end
end

local filter, root, seed = parseArgs(process.args)
root = string.gsub(root, "/+$", "")

local rootInFixtures = string.find(root .. "/", "/fixtures/", 1, true) ~= nil
local specs: { string } = {}
discover(root, rootInFixtures, specs)

local started = os.clock()
local passed, failed, todoCount = 0, 0, 0

local function matches(label: string): boolean
	return filter == nil or string.find(label, filter, 1, true) ~= nil
end

local function fail(label: string, detail: string)
	failed += 1
	print(`FAIL {label}`)
	for line in string.gmatch(detail, "[^\n]+") do
		print(`     {line}`)
	end
end

local registeredAnything = false

for _, path in specs do
	-- Lune resolves require() relative to THIS file, so tests/engine/x.spec.luau becomes ./engine/x.spec.luau.
	local relative = string.match(path, "^tests/(.+)$")
	if relative == nil then
		fail(`{path}::<load>`, "spec paths must live under tests/")
		continue
	end

	local loadOk, specOrErr = pcall(function(): any
		-- Lune 0.11.1 rejects the file extension in a require string: strip ".luau".
		return dynamicRequire(`./{string.sub(relative, 1, -#".luau" - 1)}`)
	end)
	if not loadOk then
		fail(`{path}::<load>`, tostring(specOrErr))
		continue
	end
	if type(specOrErr) ~= "function" then
		fail(`{path}::<load>`, "spec module must return function(t)")
		continue
	end

	local runner = Test.new({ seed = seed })
	local regOk, regErr = pcall(specOrErr :: (Test.Runner) -> any, runner)
	if not regOk then
		fail(`{path}::<register>`, tostring(regErr))
		continue
	end

	-- A spec that loads but registers nothing is a failure: a typo in a spec body would otherwise silently
	-- disable a whole area while the suite stays green.
	if #runner.cases == 0 and #runner.todos == 0 then
		fail(`{path}::<no cases registered>`, "spec loaded but registered zero cases and zero todos")
		continue
	end
	registeredAnything = true

	for _, case in runner.cases do
		local label = `{path}::{case.name}`
		if matches(label) then
			local ok, err = pcall(case.fn :: () -> any)
			if ok then
				passed += 1
				print(`ok   {label}`)
			else
				fail(label, tostring(err))
			end
		end
	end
	for _, name in runner.todos do
		local label = `{path}::{name}`
		if matches(label) then
			todoCount += 1
			print(`todo {label}`)
		end
	end
end

local elapsed = os.clock() - started
print(string.format("%d passed, %d failed, %d todo in %.2fs", passed, failed, todoCount, elapsed))

if #specs == 0 then
	print(`FAIL no spec files discovered under {root}: an empty run must not look green`)
	process.exit(1)
end
if filter ~= nil and registeredAnything and passed + failed + todoCount == 0 then
	print(`FAIL filter {filter} matched no cases: a typo must not look green`)
	process.exit(1)
end
if failed > 0 then
	process.exit(1)
end
process.exit(0)
