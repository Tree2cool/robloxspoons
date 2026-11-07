--!strict
-- Drift test for the one seconds-to-deciseconds conversion (CLAUDE.md rule 5, D-13, plan 04-14).
--
-- src/server/services/CardService.luau names game:GetService, so LUNE CANNOT LOAD IT. What a machine can
-- do is (a) scan its COMMENT-STRIPPED source and (b) drive the pure CardTiming.autoPassDeci directly.
--
-- What the first draft of this gate got wrong, which is the point of the whole file: its case 1 was a
-- RAW-text count of the conversion expression, which a comment satisfies while the real code does
-- something else (the comment-defeat class that bit this project four times in Phase 3), and its case 2
-- RECOMPUTED the formula inside the test, so test and shipped code could drift apart without either
-- failing. Both are replaced: every scan runs through lex.stripComments with a negative control, and the
-- value under test is the one CardTiming actually produces.
--
-- What this does NOT prove: that the constructed IdleClock really runs for 8 s in a live server. That is
-- manual check M-17 (a Studio three-player playtest).
local CardPool = require("../../src/shared/Config/CardPool")
local CardTiming = require("../../src/server/core/CardTiming")
local Card = require("../../src/shared/Config/Card")
local Round = require("../../src/shared/Config/Round")
local Test = require("../harness/Test")
local fs = require("@lune/fs")
local lex = require("../../scripts/ci/lex")

local SERVICE = "src/server/services/CardService.luau"
local CALL = "CardTiming.autoPassDeci("
local WHOLE_LINE =
	"local AUTO_PASS_DECI = CardTiming.autoPassDeci(CardPool.AUTO_PASS_MAX_SECONDS, Round.DECISECONDS_PER_SECOND)"

local function collapse(s: string): string
	return (string.gsub(s, "%s+", " "))
end

local function countOf(haystack: string, needle: string): number
	local n = 0
	local from = 1
	while true do
		local a, b = string.find(haystack, needle, from, true)
		if a == nil then
			return n
		end
		n += 1
		from = (b :: number) + 1
	end
end

-- Every .luau file under a directory, as relative paths.
local function walk(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			walk(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

-- The scanning function under test: occurrences of a marker in COMMENT-STRIPPED source.
local function strippedHits(raw: string, marker: string): number
	return countOf(lex.stripComments(raw), marker)
end

local function sourceFiles(): { string }
	local files: { string } = {}
	walk("src", files)
	return files
end

return function(t: Test.Runner)
	t.test("the call site is unique, is in CardService, and survives comment stripping", function()
		-- negative control: a comment must NOT satisfy the scan; code must.
		t.equal(strippedHits(`-- {CALL}1, 2)\nlocal x = 1\n`, CALL), 0, "negative control: marker in a comment only")
		t.equal(strippedHits(`--[[ {CALL}1, 2) ]]\nlocal x = 1\n`, CALL), 0, "negative control: block comment")
		t.equal(strippedHits(`local x = {CALL}1, 2)\n`, CALL), 1, "positive control: marker in code")

		local files = sourceFiles()
		t.truthy(#files >= 20, `non-vacuity: scanned {#files} files`)

		local callers: { string } = {}
		local arithmetic: { string } = {}
		local rawService = ""
		for _, path in files do
			local raw = fs.readFile(path)
			if path == SERVICE then
				rawService = raw
			end
			if strippedHits(raw, CALL) > 0 then
				table.insert(callers, path)
			end
			-- Used both by CardService's ceiling assert and nowhere else; counted per file below.
			if strippedHits(raw, "AUTO_PASS_MAX_SECONDS * Round.DECISECONDS_PER_SECOND") > 0 then
				table.insert(arithmetic, path)
			end
		end
		t.deepEqual(callers, { SERVICE }, "exactly one file calls CardTiming.autoPassDeci, and it is CardService")

		local stripped = lex.stripComments(rawService)
		print(`  deci_lock: scanned {#files} files; CardService stripped length {#stripped}`)
		t.equal(countOf(stripped, CALL), 1, "one call in CardService")
		t.equal(countOf(stripped, "local AUTO_PASS_DECI ="), 1, "one declaration")

		-- the WHOLE line, so autoPassDeci(7.5, 10) cannot pass.
		local sameLine: string? = nil
		for line in string.gmatch(stripped, "[^\n]+") do
			if string.find(line, "local AUTO_PASS_DECI =", 1, true) then
				sameLine = collapse(line)
			end
		end
		-- stylua may wrap the call over several lines; collapse the whole statement instead.
		local flat = collapse(stripped)
		t.truthy(string.find(flat, WHOLE_LINE, 1, true) ~= nil, "whole statement pinned (both arguments)")
		t.truthy(sameLine ~= nil, "declaration found (non-vacuity)")
		t.truthy(
			string.find(flat, "CardTiming.autoPassDeci(CardPool.AUTO_PASS_MAX_SECONDS,", 1, true) ~= nil,
			"argument 1"
		)
		t.truthy(string.find(flat, ", Round.DECISECONDS_PER_SECOND)", 1, true) ~= nil, "argument 2")
		-- negative control for the pin: a drifted argument must fail the same predicate.
		local drifted = collapse("local AUTO_PASS_DECI = CardTiming.autoPassDeci(7.5, 10)")
		t.falsy(string.find(drifted, WHOLE_LINE, 1, true) ~= nil, "negative control: autoPassDeci(7.5, 10) is rejected")

		-- no second arithmetic site: only CardService's ceiling assert may contain the product.
		t.deepEqual(arithmetic, { SERVICE }, "the product appears only in CardService's ceiling assert")
		t.equal(countOf(stripped, "AUTO_PASS_MAX_SECONDS * Round.DECISECONDS_PER_SECOND"), 1, "once, in the assert")

		-- where the value GOES: inside the IdleClock.new( call, exactly once, never a literal.
		t.equal(countOf(stripped, "autoPassDeci = AUTO_PASS_DECI"), 1, "AUTO_PASS_DECI is read exactly once")
		local at = string.find(stripped, "autoPassDeci = AUTO_PASS_DECI", 1, true) :: number
		local open = 0
		local from = 1
		while true do
			local a, b = string.find(stripped, "IdleClock.new(", from, true)
			if a == nil then
				break
			end
			if a < at then
				open = a
			end
			from = (b :: number) + 1
		end
		t.truthy(open > 0 and open < at, "IdleClock.new( precedes it")
		local close = string.find(stripped, "})", at, true)
		local nextCall = string.find(stripped, "IdleClock.new(", open + 1, true)
		t.truthy(
			close ~= nil and (nextCall == nil or (close :: number) < nextCall),
			"the next }) closes that same call"
		)

		for _, path in files do
			local text = lex.stripComments(fs.readFile(path))
			t.falsy(string.find(text, "autoPassDeci = %d") ~= nil, `no literal autoPassDeci in {path}`)
		end
		t.truthy(
			string.find("autoPassDeci = 80", "autoPassDeci = %d") ~= nil,
			"negative control: the literal pattern fires"
		)
	end)

	t.test("the SHIPPED conversion lands on 80 and can never exceed the ceiling", function()
		t.equal(
			CardTiming.autoPassDeci(CardPool.AUTO_PASS_MAX_SECONDS, Round.DECISECONDS_PER_SECOND),
			80,
			"the shipped conversion"
		)
		local function convertNaively(seconds: number, perSecond: number): number
			return math.ceil(seconds * perSecond)
		end
		local function withinCeiling(seconds: number, perSecond: number, convert: (number, number) -> number): boolean
			return convert(seconds, perSecond) <= seconds * perSecond + 1e-6
		end
		-- (0.7, 10) and (2.9, 10) are the plan's examples; both multiply to an exact integer in IEEE
		-- double, so a naive ceil does NOT trip them (measured). (0.07, 100) = 7.000000000000001 does.
		local inputs = { { 8.0, 10 }, { 0.7, 10 }, { 2.9, 10 }, { 0.07, 100 }, { 0.29, 100 } }
		local naiveViolations = 0
		for _, input in inputs do
			t.truthy(withinCeiling(input[1], input[2], CardTiming.autoPassDeci), `real stays within ceiling {input[1]}`)
			if not withinCeiling(input[1], input[2], convertNaively) then
				naiveViolations += 1
			end
		end
		t.truthy(naiveViolations >= 1, `non-vacuity: naive violates on {naiveViolations} input(s)`)
		t.equal(CardTiming.autoPassDeci(0.07, 100), 7, "real: 0.07 s at 100/s")
		t.equal(convertNaively(0.07, 100), 8, "naive: 0.07 s at 100/s overshoots")
		t.equal(CardTiming.autoPassDeci(0.7, 10), 7)
	end)

	t.test("the realised window is bounded by the sweep rate, and the bound is recorded", function()
		t.equal(Card.SWEEP_HZ, 10, "sweep rate")
		local deci = CardTiming.autoPassDeci(CardPool.AUTO_PASS_MAX_SECONDS, Round.DECISECONDS_PER_SECOND)
		local worst = (deci / 10) + (1 / Card.SWEEP_HZ)
		local best = (deci - 1) / 10
		print(`  deci_lock: realised window ({best}, {worst}] seconds`)
		t.truthy(worst <= 8.1 + 1e-9, `worst-case window {worst} <= 8.1`)
		t.truthy(math.abs(best - 7.9) < 1e-9, `earliest detection {best} == 7.9`)
		-- The locked ceiling binds the CONFIGURED value (exactly 8.0 s). The realised window is
		-- (7.9, 8.1] against CARD-16's "must not exceed 8.0 s": up to 0.1 s of overshoot from the sweep.
		-- Flooring is one-sided-short (an arming at real time c stores floor(10c) + D, so elapsed is
		-- (D - frac(10c))/10, never more than D/10); research assumption A5's "+-0.1 s on arming" should
		-- read "-0.1 s". Plan 04-20 puts the gap to the owner as a blocking decision; passing 7.9 would
		-- close it but is the owner's call, not this plan's.
	end)

	t.test("one clock expression: os.clock and GetServerTimeNow live in named files only", function()
		local files = sourceFiles()
		local osClock: { string } = {}
		local serverTime: { string } = {}
		for _, path in files do
			local raw = fs.readFile(path)
			if strippedHits(raw, "os.clock") > 0 then
				table.insert(osClock, path)
			end
			if strippedHits(raw, "GetServerTimeNow") > 0 then
				table.insert(serverTime, path)
			end
		end
		table.sort(osClock)
		table.sort(serverTime)
		print(`  deci_lock: os.clock in {table.concat(osClock, ", ")}`)
		print(`  deci_lock: GetServerTimeNow in {table.concat(serverTime, ", ")}`)
		t.deepEqual(osClock, {
			"src/server/services/CardService.luau",
			"src/server/services/NetServer.luau",
			"src/server/services/RoundDriver.luau",
		}, "os.clock files")
		-- Plan 04-18 added the client countdown, which is the one client read of server time: it only decides
		-- whether to SHOW a number (idleDeadlineUnix is already a server unix time), is never sent and nothing
		-- a score depends on reads it. The allowance names exactly that file, so a second client reader fails.
		t.deepEqual(serverTime, {
			"src/client/ui/CardClient.luau",
			"src/server/services/CardService.luau",
			"src/server/services/RoundDriver.luau",
		}, "GetServerTimeNow files")
		t.equal(strippedHits("-- os.clock\nlocal x = 1", "os.clock"), 0, "negative control: comment")
	end)
end
