--!strict
-- Review-fix gates for CardService (WR-03: startRound is atomic).
--
-- CardService names game:GetService, so LUNE CANNOT LOAD IT. What can be reached is the comment-stripped
-- source (lex.stripComments, the tokeniser the other source gates use), so this gate is a scan, and says
-- so. That a failed start really leaves a retryable service in a live server is manual check M-17.
--
-- Shape follows round_end.spec: a clean control on the real source, a non-vacuity size, a no-defect TWIN
-- (the identity edit through the same plumbing) that must read green, and mutants that are the REAL
-- source text edited in memory, each of which must be seen by the SAME problems function.
local Test = require("../harness/Test")
local fs = require("@lune/fs")
local lex = require("../../scripts/ci/lex")

local SERVICE_PATH = "src/server/services/CardService.luau"

local function slice(text: string, from: string, to: string): string
	local a = string.find(text, from, 1, true)
	if a == nil then
		return ""
	end
	local b = string.find(text, to, a + #from, true)
	if b == nil then
		return ""
	end
	return string.sub(text, a, b - 1)
end

local function replaceOnce(text: string, old: string, new: string): string
	local a, b = string.find(text, old, 1, true)
	assert(a ~= nil, `replaceOnce: {old} not found`)
	return string.sub(text, 1, a - 1) .. new .. string.sub(text, (b :: number) + 1)
end

local function at(body: string, needle: string, from: number?): number?
	return (string.find(body, needle, from or 1, true))
end

-- WR-03. Returns (problems, startRound body size, abortStart body size).
local function atomicProblems(raw: string): ({ string }, number, number)
	local text = lex.stripComments(raw)
	local problems: { string } = {}
	local start = slice(text, "local function startRound", "local function endRound")
	local abort = slice(text, "local function abortStart", "local function startRound")
	if start == "" or abort == "" then
		return { "startRound or abortStart body not found" }, #start, #abort
	end

	-- Every fallible step sits INSIDE the pcall, so a throw cannot escape with state half built.
	local opened = at(start, "local started = pcall(function()")
	if opened == nil then
		table.insert(problems, "startRound has no pcall around its fallible work")
	else
		for _, step in
			{ "cardTable = table_", "holdAvatar(", 'setPhase("Round")', "table_:start(specs)", "Heartbeat:Connect(" }
		do
			local where = at(start, step)
			if where == nil or where < opened then
				table.insert(problems, `{step} is outside the pcall`)
			end
		end
	end

	-- The failure branch rolls back and reports failure.
	local failed = at(start, "if not started then")
	local aborted = at(start, "abortStart(announced)")
	local returned = at(start, "return false", (failed or 1))
	if failed == nil or aborted == nil or aborted < failed then
		table.insert(problems, "a failed start does not call abortStart")
	end
	if failed ~= nil and (returned == nil or aborted == nil or returned < aborted) then
		table.insert(problems, "a failed start does not return false after abortStart")
	end

	-- The rollback restores EVERY piece of state the start touched.
	for _, restore in
		{
			"stopSweep()",
			"seatHold:releaseAll()",
			"table.clear(seated)",
			"cardTable = nil",
			'setPhase("Lobby")',
		}
	do
		if at(abort, restore) == nil then
			table.insert(problems, `abortStart does not restore: {restore}`)
		end
	end
	-- Clients are told only if the round was announced, and only after that is known.
	local told = at(abort, 'toSeated("RoundEnd", {})')
	local guard = at(abort, "if announced then")
	if told == nil or guard == nil or guard > told then
		table.insert(problems, "abortStart does not send RoundEnd under `if announced`")
	end
	local clear = at(abort, "table.clear(seated)")
	if told ~= nil and clear ~= nil and clear < told then
		table.insert(problems, "abortStart clears the audience before RoundEnd is sent")
	end
	return problems, #start, #abort
end

return function(t: Test.Runner)
	local raw = fs.readFile(SERVICE_PATH)

	t.test("WR-03: startRound is atomic, and abortStart restores every piece of state", function()
		local problems, startSize, abortSize = atomicProblems(raw)
		t.deepEqual(problems, {}, "clean path")
		t.truthy(startSize > 1500 and abortSize > 300, `non-vacuity: bodies {startSize}/{abortSize} chars`)
		print(`service_wiring WR-03: startRound {startSize} chars, abortStart {abortSize} chars, 0 problems`)
	end)

	t.test("WR-03 MUTATION: each way of leaving a wedged service turns the gate red", function()
		local twin = replaceOnce(raw, "cardTable = nil", "cardTable = nil")
		t.deepEqual((atomicProblems(twin)), {}, "the no-defect twin must be green")

		local mutants: { { name: string, edited: string } } = {
			{
				name = "no pcall around the start",
				edited = replaceOnce(raw, "local started = pcall(function()", "local started = true\n\t\t(function()"),
			},
			{ name = "failure branch never taken", edited = replaceOnce(raw, "if not started then", "if false then") },
			{
				name = "rollback forgets cardTable",
				edited = replaceOnce(
					raw,
					"\t\ttable.clear(seated)\n\t\tcardTable = nil\n\t\tpcall",
					"\t\ttable.clear(seated)\n\t\tpcall"
				),
			},
			{
				name = "rollback forgets the holds",
				edited = replaceOnce(
					raw,
					"\t\tpcall(function()\n\t\t\tseatHold:releaseAll()\n\t\tend)\n\t\tif announced",
					"\t\tif announced"
				),
			},
			{
				name = "rollback forgets the audience",
				edited = replaceOnce(
					raw,
					"\t\ttable.clear(seated)\n\t\tcardTable = nil\n\t\tpcall",
					"\t\tcardTable = nil\n\t\tpcall"
				),
			},
			{
				name = "rollback forgets the phase",
				edited = replaceOnce(
					raw,
					'deps.setPhase("Lobby")\n\t\tend)\n\t\tdeps.onTelemetry("start_round_failed"',
					'local _ = 0\n\t\tend)\n\t\tdeps.onTelemetry("start_round_failed"'
				),
			},
			{
				name = "rollback ignores a half-announced round",
				edited = replaceOnce(raw, "if announced then", "if false then"),
			},
		}
		local seen = 0
		for _, mutant in mutants do
			local problems = atomicProblems(mutant.edited)
			t.truthy(#problems >= 1, `mutant "{mutant.name}" was not seen`)
			if #problems >= 1 then
				seen += 1
			end
		end
		t.equal(seen, #mutants, "every mutant seen")
		print(`service_wiring WR-03: {seen}/{#mutants} mutants seen, twin green`)
	end)
end
