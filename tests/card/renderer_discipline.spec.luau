--!strict
-- Discipline gate for src/client/ui (UX-01, UX-03, D-36; plan 04-16).
--
-- src/client/ui cannot be loaded by Lune: it names game:GetService. So this gates the DISCIPLINE rather
-- than the behaviour, by scanning source text in process. That is a weak kind of gate and it says so: it
-- proves the numbers come from Layout and the constants have one home, NOT that anything renders. Physical
-- target size, the notch, the Roblox top bar and the strip at the largest text setting are M-11 / M-12 /
-- M-15. UX-01, UX-02 and UX-03 are NOT closed by this file.
--
-- EVERY scan runs through lex.stripComments (cases 5 and 6 included: the first draft scanned raw text there,
-- which let a header comment satisfy the only machine link for UX-03's constant). Every case prints what it
-- scanned, has a non-vacuity assertion, a clean control and a negative control.
--
-- Rect arithmetic note: this plan asserts no rect clearance, so the touching-is-a-violation trap does not
-- arise here; the layout gate is tests/card/layout.spec.luau.
local Card = require("../../src/shared/Config/Card")
local Layout = require("../../src/shared/Card/Layout")
local Test = require("../harness/Test")
local fs = require("@lune/fs")
local lex = require("../../scripts/ci/lex")

local UI_DIR = "src/client/ui"
local THEME = "CardTheme.luau"

-- ---------------------------------------------------------------------------------------------------------------
-- The tokeniser and scanners under test
-- ---------------------------------------------------------------------------------------------------------------

-- Comments AND string/template literals gone: for scans where the content of a string must not count.
local function stripCode(raw: string): string
	local src = lex.stripComments(raw)
	local out: { string } = {}
	local i, n = 1, #src
	while i <= n do
		local c = string.sub(src, i, i)
		if c == '"' or c == "'" or c == "`" then
			local j = i + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == c then
					break
				else
					j += 1
				end
			end
			table.insert(out, '""')
			i = j + 1
		else
			table.insert(out, c)
			i += 1
		end
	end
	return table.concat(out)
end

local function countOf(text: string, needle: string): number
	local n, from = 0, 1
	while true do
		local a, b = string.find(text, needle, from, true)
		if not a then
			return n
		end
		n += 1
		from = (b :: number) + 1
	end
end

-- Standalone numeric literals equal to a needle. A token is a run of [%w_.] so `slot2` and `pos.X` are not
-- numbers; `decimalOnly` demands a decimal point (timings are written 0.15, a bare 2 is index arithmetic).
local function numberHits(code: string, needles: { number }, decimalOnly: boolean): { string }
	local hits: { string } = {}
	for token in string.gmatch(code, "[%w_%.]+") do
		local value = tonumber(token)
		if value ~= nil and (not decimalOnly or string.find(token, ".", 1, true) ~= nil) then
			for _, needle in needles do
				if value == needle then
					table.insert(hits, token)
					break
				end
			end
		end
	end
	return hits
end

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

local function uiFiles(): { string }
	local files: { string } = {}
	walk(UI_DIR, files)
	return files
end

local function baseName(path: string): string
	return string.match(path, "[^/]+$") :: string
end

local function numbersOf(source: any): { number }
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, v in source do
		if type(v) == "number" and not seen[v] then
			seen[v] = true
			table.insert(out, v)
		end
	end
	table.sort(out)
	return out
end

local function join(list: { any }): string
	local parts: { string } = {}
	for _, v in list do
		table.insert(parts, tostring(v))
	end
	return table.concat(parts, ",")
end

-- Case 5's predicate, a function so a mutant is judged by exactly the check the real file is.
local function insetProblems(code: string): { string }
	local problems: { string } = {}
	local count = countOf(code, "Enum.ScreenInsets.")
	if count ~= 1 then
		table.insert(problems, `Enum.ScreenInsets. appears {count} times, expected exactly 1`)
	end
	local member = string.match(code, "Enum%.ScreenInsets%.(%w+)")
	if member ~= Layout.SCREEN_INSETS then
		table.insert(problems, `enum member {tostring(member)} ~= Layout.SCREEN_INSETS {Layout.SCREEN_INSETS}`)
	end
	local assigns = 0
	for _ in string.gmatch(code, "%.ScreenInsets%s*=") do
		assigns += 1
	end
	if assigns ~= 1 then
		table.insert(problems, `.ScreenInsets is assigned {assigns} times, expected exactly 1`)
	end
	if countOf(code, "INSETS_BY_NAME[Layout.SCREEN_INSETS]") ~= 1 then
		table.insert(problems, "the assignment is not read through INSETS_BY_NAME[Layout.SCREEN_INSETS]")
	end
	if countOf(code, "IgnoreGuiInset") > 0 then
		table.insert(problems, "IgnoreGuiInset is set alongside the insets (applied twice)")
	end
	if countOf(code, "ResetOnSpawn = false") < 1 then
		table.insert(problems, "ResetOnSpawn = false is absent")
	end
	if countOf(code, "ResetOnSpawn = true") > 0 then
		table.insert(problems, "ResetOnSpawn = true")
	end
	return problems
end

-- Case 6's predicate. A string literal containing a space is prose; instance and property names have none.
local function stripProblems(code: string): { string }
	local problems: { string } = {}
	for _, required in { "TextScaled = false", "TextWrapped = false", "RichText = false", "UITextSizeConstraint" } do
		if countOf(code, required) < 1 then
			table.insert(problems, `missing: {required}`)
		end
	end
	for _, forbidden in { "TextScaled = true", "TextWrapped = true", "RichText = true" } do
		if countOf(code, forbidden) > 0 then
			table.insert(problems, `contradicts: {forbidden}`)
		end
	end
	local assigned = string.match(code, "MaxTextSize%s*=%s*([%w_%.]+)")
	if assigned ~= "CardTheme.TEXT_SIZE.BODY" then
		table.insert(problems, `MaxTextSize reads {tostring(assigned)}, expected CardTheme.TEXT_SIZE.BODY`)
	end
	for literal in string.gmatch(code, '"([^"\n]*)"') do
		if string.find(literal, " ", 1, true) then
			table.insert(problems, `string literal with a space (prose): "{literal}"`)
		end
	end
	if countOf(code, "Hints.HINT") < 1 or countOf(code, "Hints.MESSAGES") < 1 then
		table.insert(problems, "strip does not read Hints.HINT and Hints.MESSAGES")
	end
	return problems
end

local function replaceOnce(text: string, from: string, to: string): string
	local a, b = string.find(text, from, 1, true)
	if not a then
		error(`mutation target not found: {from}`)
	end
	return string.sub(text, 1, a - 1) .. to .. string.sub(text, (b :: number) + 1)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Plan 04-17 scanners: the card faces, the hit strips and the connection balance
-- ---------------------------------------------------------------------------------------------------------------

-- Every string literal's content, comments already stripped by the caller. Single-line only, like the rest.
local function literalsOf(code: string): { string }
	local out: { string } = {}
	local i, n = 1, #code
	while i <= n do
		local c = string.sub(code, i, i)
		if c == '"' or c == "'" or c == "`" then
			local j = i + 1
			while j <= n do
				local d = string.sub(code, j, j)
				if d == "\\" then
					j += 2
				elseif d == c then
					break
				else
					j += 1
				end
			end
			table.insert(out, string.sub(code, i + 1, j - 1))
			i = j + 1
		else
			i += 1
		end
	end
	return out
end

-- Case 7's predicate. Rank glyphs are matched EXACTLY (a bare "A" is a rank, "Active" is not); suit names and
-- band texts are matched anywhere inside a literal, since they are long enough not to collide.
local function faceLiteralProblems(code: string, glyphs: { string }, words: { string }): { string }
	local problems: { string } = {}
	for _, literal in literalsOf(code) do
		for _, glyph in glyphs do
			if literal == glyph then
				table.insert(problems, `rank glyph literal "{literal}"`)
			end
		end
		for _, word in words do
			if string.find(literal, word, 1, true) then
				table.insert(problems, `face word "{word}" in literal "{literal}"`)
			end
		end
	end
	return problems
end

-- Whole-word occurrences of a name in comment-stripped code: catches `== "Wild"`, `Wild =` and `.Wild` alike.
local function wordCount(code: string, word: string): number
	local n = 0
	for _ in string.gmatch(code, "%f[%w_]" .. word .. "%f[^%w_]") do
		n += 1
	end
	return n
end

local function modeBranchProblems(code: string, modes: { string }): { string }
	local problems: { string } = {}
	for _, mode in modes do
		local n = wordCount(code, mode)
		if n > 0 then
			table.insert(problems, `joker mode {mode} named {n} times`)
		end
	end
	return problems
end

-- The body of every function whose NAME contains `relayout` or `apply`, found by indentation (the project is
-- stylua-formatted with tabs, so a body ends at the first `end` at the same indent). A text approximation,
-- and it says so: the real guarantee is that a tap never lands on a button mid-destruction.
local function layoutPathBodies(code: string): { { name: string, lines: { string } } }
	local lines = string.split(code, "\n")
	local found: { { name: string, lines: { string } } } = {}
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local indent, name = string.match(line, "^(\t*)([%w_]+)%s*=%s*function%(")
		if name == nil then
			indent, name = string.match(line, "^(\t*)local function ([%w_]+)")
		end
		if name == nil then
			indent, name = string.match(line, "^(\t*)function [%w_%.:]-([%w_]+)%(")
		end
		local lower = if name ~= nil then string.lower(name) else ""
		if name ~= nil and (string.find(lower, "relayout", 1, true) or string.find(lower, "apply", 1, true)) then
			local body: { string } = {}
			local k = i + 1
			while k <= #lines and lines[k] ~= `{indent}end` and lines[k] ~= `{indent}end,` do
				table.insert(body, lines[k])
				k += 1
			end
			table.insert(found, { name = name, lines = body })
			i = k
		end
		i += 1
	end
	return found
end

local function constructorInLayoutPath(code: string): { string }
	local hits: { string } = {}
	for _, fn in layoutPathBodies(code) do
		for _, l in fn.lines do
			if string.find(l, "Instance.new", 1, true) then
				table.insert(hits, `{fn.name}: {l}`)
			end
		end
	end
	return hits
end

local function handProblems(code: string, maxButtons: number): { string }
	local problems: { string } = {}
	local buttons = countOf(code, 'Instance.new("TextButton")')
	if buttons < 1 or buttons > maxButtons then
		table.insert(problems, `TextButton constructors: {buttons}, expected 1..{maxButtons}`)
	end
	for _, hit in constructorInLayoutPath(code) do
		table.insert(problems, `constructor in a layout path: {hit}`)
	end
	return problems
end

local function connectBalance(code: string): (number, number)
	return countOf(code, ":Connect("), countOf(code, ":Disconnect(")
end

-- Case 11's predicate: the input surface. Strips and sinks must stay Active, the cards must never be, and
-- the hand has no error path or user-facing error wording (D-12).
local function surfaceProblems(hand: string, piles: string, face: string): { string }
	local problems: { string } = {}
	for _, required in { "AutoButtonColor = false", "Active = true", "BackgroundTransparency = 1", 'Text = ""' } do
		if countOf(hand, required) < 1 then
			table.insert(problems, `CardHand lacks: {required}`)
		end
	end
	if countOf(hand, "Active = false") > 0 then
		table.insert(problems, "CardHand deactivates something (a tap would fall through to the backdrop)")
	end
	for _, forbidden in { "error(", "assert(", "pcall(" } do
		if countOf(hand, forbidden) > 0 then
			table.insert(problems, `CardHand has an error path: {forbidden}`)
		end
	end
	for _, literal in literalsOf(hand) do
		local lower = string.lower(literal)
		for _, word in { "error", "invalid", "reject", "wrong", "failed", "illegal" } do
			if string.find(lower, word, 1, true) then
				table.insert(problems, `user-facing error wording in CardHand: "{literal}"`)
			end
		end
	end
	local sinks = countOf(piles, ".button.Active = true")
	if sinks < 2 then
		table.insert(problems, `CardPiles has {sinks} Active sinks, expected 2`)
	end
	if countOf(face, "Active = true") > 0 then
		table.insert(problems, "a card is Active (hit-testing belongs to the strips)")
	end
	return problems
end

-- ---------------------------------------------------------------------------------------------------------------
-- Plan 04-18 scanners: the client assembly
-- ---------------------------------------------------------------------------------------------------------------

local CLIENT_DIR = "src/client"
local MAIN = `{CLIENT_DIR}/Main.client.luau`
local CLIENT_NET = `{CLIENT_DIR}/net/ClientNet.luau`
local CARD_CLIENT = `{UI_DIR}/CardClient.luau`

local function offsetOf(text: string, needle: string): number?
	local a = string.find(text, needle, 1, true)
	return a
end

-- Case 12's predicate. Pitfall 11's defect is an ordering one: the remotes must be resolved before the card
-- client is built, because WaitForChild is a yield point and a message to an unresolved remote is dropped.
local function resolveOrderProblems(code: string): { string }
	local problems: { string } = {}
	local resolve = offsetOf(code, "ClientNet.resolve(")
	local build = offsetOf(code, "CardClient.new(")
	if resolve == nil then
		table.insert(problems, "ClientNet.resolve( is absent")
	end
	if build == nil then
		table.insert(problems, "CardClient.new( is absent")
	end
	if resolve ~= nil and build ~= nil and resolve > build then
		table.insert(problems, `ClientNet.resolve( at {resolve} is after CardClient.new( at {build}`)
	end
	return problems
end

-- Case 13's predicate: nothing that yields in the card message path.
local YIELD_NEEDLES = { "task.wait", "WaitForChild", ":Wait(" }
local function yieldHits(code: string): { string }
	local hits: { string } = {}
	for _, needle in YIELD_NEEDLES do
		for _ = 1, countOf(code, needle) do
			table.insert(hits, needle)
		end
	end
	return hits
end

-- Case 14's predicate. ":BindAction" does not match ":UnbindAction", so the two counts are independent.
local function bindCounts(code: string): (number, number)
	return countOf(code, ":BindAction"), countOf(code, ":UnbindAction(")
end

-- Case 15's predicates. `ClientNet.send(` is the call; the definition lives in ClientNet.luau and is excluded
-- by path. Intent names are read from string-literal first arguments only.
local function sendSites(code: string): number
	return countOf(code, "ClientNet.send(")
end

local function literalIntentNames(code: string): { string }
	local names: { string } = {}
	for name in string.gmatch(code, "ClientNet%.send%(%s*[\"']([%w_]+)[\"']") do
		table.insert(names, name)
	end
	return names
end

local function sendProblems(sources: { [string]: string }): { string }
	local problems: { string } = {}
	local siteFiles: { string } = {}
	for path, code in sources do
		if path ~= CLIENT_NET and sendSites(code) > 0 then
			table.insert(siteFiles, path)
		end
	end
	table.sort(siteFiles)
	if join(siteFiles) ~= join({ MAIN, CARD_CLIENT }) then
		table.insert(problems, `ClientNet.send( is called from {join(siteFiles)}, expected {MAIN},{CARD_CLIENT}`)
	end
	local cardSites = if sources[CARD_CLIENT] ~= nil then sendSites(sources[CARD_CLIENT]) else 0
	if cardSites ~= 1 then
		table.insert(problems, `CardClient has {cardSites} send sites, expected exactly 1`)
	end
	local mainNames = if sources[MAIN] ~= nil then literalIntentNames(sources[MAIN]) else {}
	if join(mainNames) ~= "Ping" then
		table.insert(problems, `Main.client sends {join(mainNames)}, expected only Ping`)
	end
	for path, code in sources do
		if path ~= MAIN and path ~= CLIENT_NET then
			for _, name in literalIntentNames(code) do
				if name == "Pass" or name == "Draw" then
					table.insert(problems, `{path} names the intent {name} as a literal`)
				end
			end
		end
	end
	return problems
end

local function clientSources(): { [string]: string }
	local files: { string } = {}
	walk(CLIENT_DIR, files)
	local sources: { [string]: string } = {}
	for _, path in files do
		sources[path] = lex.stripComments(fs.readFile(path))
	end
	return sources
end

return function(t: Test.Runner)
	t.test("no geometry number from Layout.DESIGN appears as a literal anywhere under src/client/ui", function()
		-- Whole numbers 0..4 are excluded: grid and index arithmetic (slot 1, a 2-up split, a 4-grid), not geometry.
		local needles: { number } = {}
		for _, v in numbersOf(Layout.DESIGN :: any) do
			if not (v <= 4 and v == math.floor(v)) then
				table.insert(needles, v)
			end
		end
		-- CardTheme is the one file that legitimately holds text sizes and a corner radius; those collide
		-- with geometry by coincidence (16 = LIFT, 28 = STRIP_H, 8 = STRIP_MARGIN, 0.85 = SCALE_MIN). The
		-- allowance is explicit and exact, and colour constructors' channel values are blanked first.
		local themeAllowed = { [8] = true, [16] = true, [28] = true, [0.85] = true }
		local themeNeedles: { number } = {}
		for _, v in needles do
			if not themeAllowed[v] then
				table.insert(themeNeedles, v)
			end
		end

		-- negative control: the scanner reports the two design numbers, and ignores a comment and a string
		t.equal(#numberHits(stripCode("UDim2.fromOffset(144, 92)"), needles, false), 2, "negative control: two hits")
		t.equal(
			#numberHits(stripCode('-- 144\nlocal s = "92"\nlocal slot144x = 1'), needles, false),
			0,
			"negative control: comment, string and identifier are not numbers"
		)

		local files = uiFiles()
		t.truthy(#files >= 8, `non-vacuity: scanned {#files} files, at least 8 expected`)
		print(`  renderer_discipline[1]: {#files} files, {#needles} needles: {join(needles)}`)
		local total = 0
		local sawTheme = false
		for _, path in files do
			local code = stripCode(fs.readFile(path))
			local use = needles
			if baseName(path) == THEME then
				sawTheme = true
				code = string.gsub(code, "Color3%.fromRGB%b()", "Color3.fromRGB()")
				use = themeNeedles
			end
			local hits = numberHits(code, use, false)
			total += #hits
			t.deepEqual(hits, {}, `geometry literal in {path}`)
		end
		t.truthy(sawTheme, "CardTheme was scanned under its explicit allowance (non-vacuity)")
		t.equal(total, 0)
	end)

	t.test("every Color3 and Font constructor under src/client/ui lives in CardTheme.luau", function()
		local needles = {
			"Color3.fromRGB",
			"Color3.new",
			"Color3.fromHSV",
			"Color3.fromHex",
			"Font.new",
			"Enum.Font.",
			"BrickColor",
		}
		local function hitsIn(code: string): number
			local n = 0
			for _, needle in needles do
				n += countOf(code, needle)
			end
			return n
		end
		-- negative control: a comment hides nothing it should not, and code is caught
		t.equal(hitsIn(lex.stripComments("-- Color3.fromRGB(1, 2, 3)\nlocal x = 1")), 0, "negative control: comment")
		t.equal(hitsIn(lex.stripComments("local c = Color3.fromRGB(1, 2, 3)")), 1, "negative control: code")

		local files = uiFiles()
		t.truthy(#files >= 8, `non-vacuity: scanned {#files} files, at least 8 expected`)
		local withHits: { string } = {}
		local report: { string } = {}
		local themeHits = 0
		for _, path in files do
			local n = hitsIn(lex.stripComments(fs.readFile(path)))
			table.insert(report, `{baseName(path)}={n}`)
			if n > 0 then
				table.insert(withHits, baseName(path))
			end
			if baseName(path) == THEME then
				themeHits = n
			end
		end
		print(`  renderer_discipline[2]: per-file hits {join(report)}`)
		t.truthy(themeHits > 0, "non-vacuity: CardTheme actually holds constructors")
		t.deepEqual(withHits, { THEME }, "the only file with a colour or font constructor is CardTheme")
	end)

	t.test("every tween duration and pulse rate comes from Config.Card", function()
		local source: { number } = {}
		for _, v in numbersOf(Card.TWEEN :: any) do
			table.insert(source, v)
		end
		for _, v in numbersOf(Card.PULSE_HZ :: any) do
			table.insert(source, v)
		end
		table.insert(source, Card.AFK_WARN_SECONDS)
		source = numbersOf(source)
		t.truthy(#source >= 10, `non-vacuity: {#source} timing values`)

		t.equal(#numberHits(stripCode("local d = 0.15"), source, true), 1, "negative control: a duration literal")
		t.equal(#numberHits(stripCode("-- 0.15\nlocal d = 5"), source, true), 0, "negative control: comment")

		local files = uiFiles()
		t.truthy(#files >= 8, `non-vacuity: scanned {#files} files, at least 8 expected`)
		print(`  renderer_discipline[3]: {#files} files, needles: {join(source)}`)
		for _, path in files do
			-- CardTheme is NOT exempt here: timings have exactly one home.
			t.deepEqual(numberHits(stripCode(fs.readFile(path)), source, true), {}, `timing literal in {path}`)
		end
	end)

	t.test("no renderer file names a forbidden identifier", function()
		local needles = {
			"rankOf",
			"GetControls",
			"PlayerModule",
			"ControlModule",
			"ModalEnabled",
			"FireServer",
			"OnClientEvent",
			"FireClient",
			"FireAllClients",
		}
		local function hitsIn(text: string): number
			local n = 0
			for _, needle in needles do
				n += countOf(text, needle)
			end
			return n
		end
		t.equal(hitsIn("local x = node.OnClientEvent"), 1, "negative control: fires on a planted identifier")
		-- RAW text, comments included: stricter than the guards, and it keeps headers honest.
		local files = uiFiles()
		t.truthy(#files >= 8, `non-vacuity: scanned {#files} files, at least 8 expected`)
		local total = 0
		for _, path in files do
			local n = hitsIn(fs.readFile(path))
			total += n
			t.equal(n, 0, `forbidden identifier in {path}`)
		end
		print(`  renderer_discipline[4]: {#files} files, {#needles} identifiers, {total} hits`)
	end)

	t.test("IN-05: the flourish scheduler reads no clock of its own", function()
		local path = `{UI_DIR}/CardFlourish.luau`
		local raw = fs.readFile(path)
		local function clockReads(text: string): number
			local code = lex.stripComments(text)
			return countOf(code, "time()") + countOf(code, "os.clock") + countOf(code, "tick()")
		end
		t.equal(clockReads("local x = time()"), 1, "negative control: fires on a planted time() read")
		t.equal(clockReads("-- time() in a comment\nlocal x = 1"), 0, "negative control: a comment does not count")
		local schedulerAt = string.find(raw, "local function makeScheduler", 1, true)
		t.truthy(schedulerAt ~= nil, "non-vacuity: makeScheduler was found in the scanned source")
		t.equal(clockReads(raw), 0, "CardFlourish reads a clock")
		t.equal(
			clockReads(
				replaceOnce(
					raw,
					"nowDeci = function(): number\n\t\t\treturn 0\n",
					"nowDeci = function(): number\n\t\t\treturn math.floor(time() * 10)\n"
				)
			),
			1,
			"MUTATION: time() back in nowDeci"
		)
		print(`  renderer_discipline[IN-05]: {#raw} chars scanned, 0 clock reads, mutant seen`)
	end)

	t.test("IN-06: the rotate prompt restores the orientation it overrode", function()
		local raw = fs.readFile(`{UI_DIR}/CardHud.luau`)
		-- Returns the problems with newRotatePrompt: capture before the set, restore inside destroy.
		local function orientationProblems(text: string): ({ string }, number)
			local code = lex.stripComments(text)
			local problems: { string } = {}
			local a = string.find(code, "function CardHud.newRotatePrompt", 1, true)
			if a == nil then
				return { "newRotatePrompt not found" }, 0
			end
			local body = string.sub(code, a)
			local capture = string.find(body, "local previousOrientation = pg.ScreenOrientation", 1, true)
			local set = string.find(body, "pg.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor", 1, true)
			if capture == nil or set == nil or capture > set then
				table.insert(problems, "the prior orientation is not captured before it is overridden")
			end
			local destroyAt = string.find(body, "destroy = function", 1, true)
			local restore = string.find(body, "pg.ScreenOrientation = previousOrientation", 1, true)
			if destroyAt == nil or restore == nil or restore < destroyAt then
				table.insert(problems, "destroy does not restore the captured orientation")
			end
			return problems, #body
		end
		local problems, size = orientationProblems(raw)
		t.deepEqual(problems, {}, "clean path")
		t.truthy(size > 500, `non-vacuity: newRotatePrompt scan covered {size} chars`)
		t.deepEqual((orientationProblems(replaceOnce(raw, "previousOrientation", "previousOrientation"))), {}, "twin")
		local noRestore =
			replaceOnce(raw, "pg.ScreenOrientation = previousOrientation", "local _ = previousOrientation")
		local neverCaptured =
			replaceOnce(raw, "local previousOrientation = pg.ScreenOrientation", "local previousOrientation = nil")
		local seenRestore = #(orientationProblems(noRestore))
		local seenCapture = #(orientationProblems(neverCaptured))
		t.truthy(seenRestore >= 1, "MUTATION: destroy stops restoring")
		t.truthy(seenCapture >= 1, "MUTATION: the prior value is never captured")
		print(`  renderer_discipline[IN-06]: {size} chars scanned, mutants seen {seenRestore}/{seenCapture}`)
	end)

	t.test("IN-01: a partial buildUi failure undoes every piece it built", function()
		local raw = fs.readFile(CARD_CLIENT)
		local function buildProblems(text: string): ({ string }, number)
			local code = lex.stripComments(text)
			local a = string.find(code, "local function buildUi", 1, true)
			local b = string.find(code, "local function onRoundStart", 1, true)
			if a == nil or b == nil or b < a then
				return { "buildUi body not found" }, 0
			end
			local body = string.sub(code, a, b - 1)
			local problems: { string } = {}
			for _, piece in { "hand", "piles", "strip", "input" } do
				local made = string.find(body, `local {piece} = Card`, 1, true)
				local undone = string.find(body, `{piece}:destroy()`, 1, true)
				if made == nil or undone == nil or undone < made then
					table.insert(problems, `{piece} is built but not registered for cleanup after it exists`)
				end
			end
			local failureAt = string.find(body, "if not ok then", 1, true)
			local loop = string.find(body, "for i = #cleanups, 1, -1 do", 1, true)
			local hudAt = string.find(body, "hud:destroy()", 1, true)
			if failureAt == nil or loop == nil or loop < failureAt then
				table.insert(problems, "the failure path does not unwind the cleanups newest first")
			elseif hudAt == nil or hudAt < loop then
				table.insert(problems, "the hud is destroyed before the pieces on top of it")
			end
			return problems, #body
		end
		local problems, size = buildProblems(raw)
		t.deepEqual(problems, {}, "clean path")
		t.truthy(size > 1200, `non-vacuity: buildUi scan covered {size} chars`)
		t.deepEqual((buildProblems(replaceOnce(raw, "pcall(cleanups[i])", "pcall(cleanups[i])"))), {}, "twin")
		local mutants: { { name: string, edited: string } } = {
			{
				name = "piles never registered (the leaked RenderStepped)",
				edited = replaceOnce(
					raw,
					"piles:destroy()\n\t\t\tend)\n\t\t\tlocal strip",
					"(nil)\n\t\t\tend)\n\t\t\tlocal strip"
				),
			},
			{
				name = "input never registered (the leaked bindings)",
				edited = replaceOnce(
					raw,
					"input:destroy()\n\t\t\tend)\n\t\t\tlocal ui",
					"(nil)\n\t\t\tend)\n\t\t\tlocal ui"
				),
			},
			{
				name = "failure path no longer unwinds",
				edited = replaceOnce(raw, "for i = #cleanups, 1, -1 do", "for i = 1, 0 do"),
			},
		}
		local seen = 0
		for _, mutant in mutants do
			local found = buildProblems(mutant.edited)
			t.truthy(#found >= 1, `mutant "{mutant.name}" was not seen`)
			if #found >= 1 then
				seen += 1
			end
		end
		t.equal(seen, #mutants, "every mutant seen")
		print(`  renderer_discipline[IN-01]: buildUi {size} chars, {seen}/{#mutants} mutants seen, twin green`)
	end)

	t.test("the ScreenInsets string in Layout maps to the enum member the HUD sets", function()
		-- negative control: a comment must not satisfy the scan, code must.
		local commentOnly = lex.stripComments("-- ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets\nlocal x = 1")
		local inCode = lex.stripComments("local m = { CoreUISafeInsets = Enum.ScreenInsets.CoreUISafeInsets }")
		t.equal(countOf(commentOnly, "Enum.ScreenInsets."), 0, "negative control: comment-only occurrence")
		t.equal(countOf(inCode, "Enum.ScreenInsets."), 1, "negative control: occurrence in code")

		t.equal(Layout.SCREEN_INSETS, "CoreUISafeInsets")
		t.truthy(Layout.SCREEN_INSETS ~= "None", "not None")
		t.truthy(Layout.SCREEN_INSETS ~= "DeviceSafeInsets", "not DeviceSafeInsets (clears the notch, not the top bar)")

		local raw = fs.readFile(`{UI_DIR}/CardHud.luau`)
		local code = lex.stripComments(raw)
		print(
			`  renderer_discipline[5]: CardHud raw {#raw} -> stripped {#code}, Enum.ScreenInsets. hits {countOf(
				code,
				"Enum.ScreenInsets."
			)}`
		)
		t.truthy(#code < #raw, "non-vacuity: stripping removed the header")
		t.deepEqual(insetProblems(code), {}, "CardHud sets the insets as specified")

		-- the predicate is not vacuous: each defect, injected into the real text, is reported
		local function reported(mutant: string, label: string)
			t.truthy(#insetProblems(mutant) > 0, `injected defect not caught: {label}`)
		end
		reported(
			replaceOnce(code, "Enum.ScreenInsets.CoreUISafeInsets", "Enum.ScreenInsets.DeviceSafeInsets"),
			"wrong member"
		)
		reported(code .. "\ngui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets", "second assignment")
		reported(code .. "\ngui.IgnoreGuiInset = true", "inset applied twice")
		reported(replaceOnce(code, "ResetOnSpawn = false", "ResetOnSpawn = true"), "respawn destroys the hand")
		reported(
			replaceOnce(code, "INSETS_BY_NAME[Layout.SCREEN_INSETS]", "INSETS_BY_NAME.CoreUISafeInsets"),
			"mapping unlinked"
		)
		-- and the comment attack: delete the real code, leave the member only in a comment
		local attacked = replaceOnce(code, "Enum.ScreenInsets.CoreUISafeInsets", "nil")
			.. "\n-- Enum.ScreenInsets.CoreUISafeInsets"
		reported(lex.stripComments(attacked), "comment attack")
	end)

	t.test("the strip label is configured for one line", function()
		-- WEAK, and said so: the real measurement is M-12 at the largest preferred text size. It is here
		-- because the absence of any required setting, or a contradicting second assignment, is a CERTAIN
		-- defect even though their presence is not a certain pass.
		local raw = fs.readFile(`{UI_DIR}/CardStrip.luau`)
		local code = lex.stripComments(raw)
		print(`  renderer_discipline[6]: CardStrip raw {#raw} -> stripped {#code}, problems {#stripProblems(code)}`)
		t.truthy(#code < #raw, "non-vacuity: stripping removed the header")
		t.deepEqual(stripProblems(code), {}, "CardStrip is configured for one line")

		-- clean control passed above; negative controls: comment-only mentions do not satisfy or contradict
		t.truthy(
			#stripProblems(
					lex.stripComments("-- TextScaled = false TextWrapped = false RichText = false UITextSizeConstraint")
				) > 0,
			"negative control: comment-only presence"
		)
		local commentedContradiction =
			replaceOnce(code, "TextScaled = false", "TextScaled = false -- TextScaled = true")
		t.deepEqual(
			stripProblems(lex.stripComments(commentedContradiction)),
			{},
			"a contradicting comment is not a contradiction"
		)

		local function reported(mutant: string, label: string)
			t.truthy(#stripProblems(mutant) > 0, `injected defect not caught: {label}`)
		end
		reported(replaceOnce(code, "TextScaled = false", "TextScaled = true"), "scaled text")
		reported(code .. "\nlabel.TextWrapped = true", "second assignment undoes the first")
		reported(code .. "\nlabel.RichText = true", "rich text")
		reported(replaceOnce(code, "TextWrapped = false", "TextSize = 1"), "wrap setting removed")
		reported(replaceOnce(code, "MaxTextSize = CardTheme.TEXT_SIZE.BODY", "MaxTextSize = 20"), "literal MaxTextSize")
		reported(code .. '\nlabel.Text = "Tap a card to pick it"', "prose composed in the strip")
	end)
	t.test("no rank glyph, suit name or joker band text appears as a literal outside Faces.luau", function()
		local Faces = require("../../src/shared/Card/Faces")
		local glyphs: { string } = {}
		for _, g in Faces.RANK_LADDER do
			table.insert(glyphs, g)
		end
		local words: { string } = {}
		for _, suit in Faces.SUIT_OF_COPY do
			table.insert(words, suit)
		end
		for _, mode in Faces.JOKER_MODES do
			table.insert(words, Faces.JOKER_BAND[mode].text)
		end
		t.equal(#glyphs, 12, "non-vacuity: the ladder is 12 glyphs")
		t.equal(#words, 6, "non-vacuity: four suits and two band texts")

		-- negative controls: each kind is caught, and a comment, an identifier and "Active" are not
		t.equal(#faceLiteralProblems('local g = "K"', glyphs, words), 1, "negative control: a rank glyph")
		t.equal(#faceLiteralProblems("local s = 'spade'", glyphs, words), 1, "negative control: a suit name")
		t.equal(#faceLiteralProblems('x.Text = "WILD"', glyphs, words), 1, "negative control: a band text")
		t.equal(
			#faceLiteralProblems(lex.stripComments('-- "K" "WILD"\nlocal Active = "Active"'), glyphs, words),
			0,
			"negative control: comment and the word Active"
		)

		local files = uiFiles()
		t.truthy(#files >= 8, `non-vacuity: scanned {#files} files, at least 8 expected`)
		local perFile: { string } = {}
		local sources: { [string]: string } = {}
		local literals = 0
		for _, path in files do
			local code = lex.stripComments(fs.readFile(path))
			sources[baseName(path)] = code
			literals += #literalsOf(code)
			table.insert(perFile, `{baseName(path)}={#literalsOf(code)}`)
			t.deepEqual(faceLiteralProblems(code, glyphs, words), {}, `face literal in {path}`)
		end
		print(`  renderer_discipline[7]: {#files} files, literals {literals} ({join(perFile)})`)
		print(`  renderer_discipline[7]: glyph needles {join(glyphs)}; word needles {join(words)}`)
		t.truthy(literals >= 30, `non-vacuity: {literals} string literals were actually examined`)

		-- twin: the same mutation function with an identity edit is clean, so a red mutant is not the harness
		local face = sources["CardFace.luau"]
		t.deepEqual(
			faceLiteralProblems(replaceOnce(face, "bandText.Text = b.text", "bandText.Text = b.text"), glyphs, words),
			{},
			"twin: an identity edit of the real CardFace is clean"
		)
		-- real-source mutations: the shipped CardFace is what is judged
		t.truthy(
			#faceLiteralProblems(
					replaceOnce(face, "bandText.Text = b.text", 'bandText.Text = "WILD"'),
					glyphs,
					words
				) > 0,
			"MUTATION: band text hard-coded in CardFace is caught"
		)
		t.truthy(
			#faceLiteralProblems(
					replaceOnce(face, "corner1.rank.Text = resolved.rankGlyph", 'corner1.rank.Text = "K"'),
					glyphs,
					words
				) > 0,
			"MUTATION: rank glyph hard-coded in CardFace is caught"
		)
		t.truthy(
			#faceLiteralProblems(
					replaceOnce(face, "bandText.Text = b.text", 'bandText.Text = "club"'),
					glyphs,
					words
				) > 0,
			"MUTATION: suit name hard-coded in CardFace is caught"
		)
	end)

	t.test("no file under src/client/ui branches on the joker mode", function()
		local Faces = require("../../src/shared/Card/Faces")
		local modes: { string } = {}
		for _, m in Faces.JOKER_MODES do
			table.insert(modes, m)
		end
		t.truthy(#modes >= 2, `non-vacuity: {#modes} joker modes ({join(modes)})`)
		t.equal(#modeBranchProblems('if mode == "Wild" then', modes), 1, "negative control: a mode comparison")
		t.equal(#modeBranchProblems("local t = { Blocker = 1 }", modes), 1, "negative control: a mode-keyed table")
		t.equal(#modeBranchProblems(lex.stripComments("-- Wild Blocker"), modes), 0, "negative control: comment")

		local files = uiFiles()
		t.truthy(#files >= 8, `non-vacuity: scanned {#files} files, at least 8 expected`)
		local sources: { [string]: string } = {}
		for _, path in files do
			local code = lex.stripComments(fs.readFile(path))
			sources[baseName(path)] = code
			t.deepEqual(modeBranchProblems(code, modes), {}, `joker mode named in {path}`)
		end
		print(`  renderer_discipline[8]: {#files} files, modes {join(modes)}, 0 hits`)

		local face = sources["CardFace.luau"]
		t.deepEqual(modeBranchProblems(replaceOnce(face, "local JK", "local JK"), modes), {}, "twin: identity edit")
		t.truthy(
			#modeBranchProblems(replaceOnce(face, "local JK", 'if mode == "Wild" then end\nlocal JK'), modes) > 0,
			"MUTATION: a Wild comparison in CardFace is caught"
		)
		t.truthy(
			#modeBranchProblems(
					replaceOnce(face, "local JK", "local _b = Faces.JOKER_BAND.Blocker\nlocal JK"),
					modes
				) > 0,
			"MUTATION: indexing the band by a mode name is caught"
		)
	end)

	t.test("the hit-strip buttons are created once, not per layout", function()
		-- A TEXT-LEVEL APPROXIMATION, and it says so: the real guarantee is that a tap can never land on a
		-- button mid-destruction. The certain-defect shape is a constructor inside the layout path.
		local maxHand = #Layout.solve(
			{ width = 1920, height = 1080, insets = { top = 0, bottom = 0, left = 0, right = 0 } },
			5
		).slots
		t.equal(maxHand, 5, "MAX_HAND derived from the real layout")
		local limit = maxHand + 1

		local hand = lex.stripComments(fs.readFile(`{UI_DIR}/CardHand.luau`))
		local bodies = layoutPathBodies(hand)
		local names: { string } = {}
		local lineTotal = 0
		for _, b in bodies do
			table.insert(names, `{b.name}({#b.lines})`)
			lineTotal += #b.lines
		end
		local buttons = countOf(hand, 'Instance.new("TextButton")')
		print(
			`  renderer_discipline[9]: CardHand TextButton constructors {buttons} (limit {limit}); layout-path bodies {join(
				names
			)}`
		)
		t.truthy(#bodies >= 2, `non-vacuity: found {#bodies} layout-path functions`)
		t.truthy(lineTotal >= 30, `non-vacuity: {lineTotal} body lines examined`)
		t.deepEqual(handProblems(hand, limit), {}, "CardHand constructs its buttons once")

		-- negative controls for the body finder and the predicate
		t.equal(
			#constructorInLayoutPath('\tapply = function(a)\n\t\tInstance.new("Frame")\n\tend,\n'),
			1,
			"negative control: constructor inside apply"
		)
		t.equal(
			#constructorInLayoutPath('\tlocal function build()\n\t\tInstance.new("Frame")\n\tend\n'),
			0,
			"negative control: constructor outside the layout path"
		)
		-- twin, then real-source mutations
		t.deepEqual(
			handProblems(replaceOnce(hand, "selectedNow = selected", "selectedNow = selected"), limit),
			{},
			"twin"
		)
		t.truthy(
			#handProblems(
					replaceOnce(
						hand,
						"selectedNow = selected",
						'selectedNow = selected\nlocal late = Instance.new("TextButton")'
					),
					limit
				) > 0,
			"MUTATION: a strip built inside apply is caught"
		)
		local inRelayout = replaceOnce(hand, "sol = solution2", 'sol = solution2\nlocal late = Instance.new("Frame")')
		t.truthy(#handProblems(inRelayout, limit) > 0, "MUTATION: a constructor inside relayout is caught")
		local many = hand
		for _ = 1, limit do
			many ..= '\nlocal extra = Instance.new("TextButton")'
		end
		t.truthy(#handProblems(many, limit) > 0, "MUTATION: more strips than slots plus the backdrop is caught")
	end)

	t.test("every connection in the renderer has a matching Disconnect", function()
		t.deepEqual(
			{ connectBalance("x:Connect(f) y:Connect(g) z:Disconnect()") },
			{ 2, 1 },
			"negative control: counts"
		)
		t.deepEqual({ connectBalance(lex.stripComments("-- a:Connect(f)")) }, { 0, 0 }, "negative control: comment")

		local files = uiFiles()
		t.truthy(#files >= 8, `non-vacuity: scanned {#files} files, at least 8 expected`)
		local report: { string } = {}
		local creators = 0
		local sources: { [string]: string } = {}
		for _, path in files do
			local code = lex.stripComments(fs.readFile(path))
			sources[baseName(path)] = code
			local connects, disconnects = connectBalance(code)
			table.insert(report, `{baseName(path)}={connects}/{disconnects}`)
			if connects > 0 then
				creators += 1
				t.truthy(disconnects >= connects, `{path}: {connects} Connect against {disconnects} Disconnect`)
			end
		end
		print(`  renderer_discipline[10]: Connect/Disconnect per file {join(report)}`)
		t.truthy(creators >= 3, `non-vacuity: {creators} files create connections (Hud, Hand, Piles expected)`)

		local function balanced(code: string): boolean
			local c, d = connectBalance(code)
			return c == 0 or d >= c
		end
		t.truthy(balanced(sources["CardPiles.luau"]), "twin: the real CardPiles is balanced")
		t.truthy(
			not balanced(replaceOnce(sources["CardPiles.luau"], "c:Disconnect()", "c:Destroy()")),
			"MUTATION: CardPiles.destroy no longer disconnects"
		)
		t.truthy(
			not balanced(replaceOnce(sources["CardHand.luau"], "c:Disconnect()", "c:Destroy()")),
			"MUTATION: CardHand.destroy no longer disconnects"
		)
		t.truthy(
			not balanced(sources["CardHud.luau"] .. "\ncam:GetPropertyChangedSignal('x'):Connect(f)"),
			"MUTATION: an extra render connection with no Disconnect"
		)
	end)

	t.test(
		"the input surface: strips and sinks stay Active, cards never are, and the hand has no error path",
		function()
			local hand = lex.stripComments(fs.readFile(`{UI_DIR}/CardHand.luau`))
			local piles = lex.stripComments(fs.readFile(`{UI_DIR}/CardPiles.luau`))
			local face = lex.stripComments(fs.readFile(`{UI_DIR}/CardFace.luau`))
			print(
				`  renderer_discipline[11]: CardHand Active = true x{countOf(hand, "Active = true")}, CardPiles sinks x{countOf(
					piles,
					".button.Active = true"
				)}, CardFace Active = true x{countOf(face, "Active = true")}`
			)
			t.truthy(
				countOf(hand, "Active = true") >= 1 and countOf(piles, ".button.Active = true") >= 2,
				"non-vacuity"
			)
			t.deepEqual(surfaceProblems(hand, piles, face), {}, "the shipped input surface")

			t.deepEqual(surfaceProblems(replaceOnce(hand, "Active = true", "Active = true"), piles, face), {}, "twin")
			local function reported(h: string, p: string, f: string, label: string)
				t.truthy(#surfaceProblems(h, p, f) > 0, `MUTATION not caught: {label}`)
			end
			reported(replaceOnce(hand, "Active = true", "Active = false"), piles, face, "strip made inactive")
			reported(hand .. '\nbutton.Text = "Invalid move"', piles, face, "a user-facing error string (D-12)")
			reported(hand .. '\nerror("nope")', piles, face, "an error path")
			reported(
				hand,
				replaceOnce(piles, "right.button.Active = true", "right.button.Visible = true"),
				face,
				"right sink lost"
			)
			reported(
				hand,
				replaceOnce(piles, "left.button.Active = true", "left.button.Visible = true"),
				face,
				"left sink lost"
			)
			reported(
				hand,
				piles,
				replaceOnce(face, "frame.Active = false", "frame.Active = true"),
				"a card takes input"
			)
			reported(
				replaceOnce(hand, "AutoButtonColor = false", "AutoButtonColor = true"),
				piles,
				face,
				"strip flashes"
			)
		end
	)

	t.test("ClientNet.resolve is called before any CardClient construction in Main.client", function()
		local main = lex.stripComments(fs.readFile(MAIN))
		local resolve = offsetOf(main, "ClientNet.resolve(")
		local build = offsetOf(main, "CardClient.new(")
		print(
			`  renderer_discipline[12]: Main.client offsets: ClientNet.resolve( = {resolve}, CardClient.new( = {build}`
		)
		t.truthy(resolve ~= nil and build ~= nil, "non-vacuity: both needles were found in the shipped Main.client")
		t.deepEqual(resolveOrderProblems(main), {}, "the shipped boot order")

		-- negative controls: a comment does not count, and the wrong order is reported
		t.truthy(
			#resolveOrderProblems(lex.stripComments("-- ClientNet.resolve()\nlocal c = CardClient.new()")) > 0,
			"negative control: a comment naming resolve satisfies nothing"
		)
		t.truthy(
			#resolveOrderProblems("local c = CardClient.new()\nClientNet.resolve()") > 0,
			"negative control: resolve after construction"
		)
		-- twin, then real-source mutations
		t.deepEqual(
			resolveOrderProblems(replaceOnce(main, "client:start()", "client:start()")),
			{},
			"twin: an identity edit of the real Main.client is clean"
		)
		local withoutResolve = replaceOnce(main, "ClientNet.resolve()", "local resolved = true")
		t.truthy(#resolveOrderProblems(withoutResolve) > 0, "MUTATION: resolve deleted from Main.client")
		local moved = withoutResolve .. "\nClientNet.resolve()"
		t.truthy(#resolveOrderProblems(moved) > 0, "MUTATION: resolve moved after the card client is built")
		local commentOnly = withoutResolve .. "\n-- ClientNet.resolve()"
		t.truthy(#resolveOrderProblems(lex.stripComments(commentOnly)) > 0, "MUTATION: resolve left only in a comment")
	end)

	t.test("no file under src/client names a yield inside the card message path", function()
		-- V-12 guarantees handler START order only, so a yielding handler can be overtaken and the client would
		-- fold events out of order. CardHud.new does call WaitForChild for the PlayerGui and may wait for a
		-- camera, but only on objects that already exist at that point, so neither yields in practice; that
		-- is not asserted here and the scan scope is CardClient, as planned.
		local code = lex.stripComments(fs.readFile(CARD_CLIENT))
		local hits = yieldHits(code)
		print(
			`  renderer_discipline[13]: CardClient stripped {#code} chars, yield needles {join(YIELD_NEEDLES)}, hits {#hits}`
		)
		t.truthy(#code > 2000, "non-vacuity: a real, non-empty CardClient was scanned")
		t.equal(countOf(code, "ClientNet.onCard("), 1, "non-vacuity: the handler under scan is the onCard one")
		t.deepEqual(hits, {}, "CardClient yields nowhere")

		t.equal(#yieldHits("task.wait(1) x:WaitForChild('a') y:Wait()"), 3, "negative control: all three kinds")
		t.equal(#yieldHits(lex.stripComments("-- task.wait(1)\nlocal x = 1")), 0, "negative control: comment")
		t.deepEqual(yieldHits(replaceOnce(code, "local started = false", "local started = false")), {}, "twin")
		t.truthy(
			#yieldHits(replaceOnce(code, "local started = false", "local started = false\ntask.wait(1)")) > 0,
			"MUTATION: task.wait in CardClient"
		)
		t.truthy(
			#yieldHits(replaceOnce(code, "local started = false", 'local started = false\ngame:WaitForChild("x")')) > 0,
			"MUTATION: WaitForChild in CardClient"
		)
		t.truthy(
			#yieldHits(replaceOnce(code, "local started = false", "local started = false\nlocal _ = x:Wait()")) > 0,
			"MUTATION: :Wait() in CardClient"
		)
	end)

	t.test("every BindAction has an UnbindAction, per file, and the counts are printed", function()
		local controls = lex.stripComments(fs.readFile(`{UI_DIR}/CardControls.luau`))
		local input = lex.stripComments(fs.readFile(`{UI_DIR}/CardInput.luau`))
		local cb, cu = bindCounts(controls)
		local ib, iu = bindCounts(input)
		print(`  renderer_discipline[14]: CardControls bind/unbind {cb}/{cu}, CardInput bind/unbind {ib}/{iu}`)
		t.truthy(cb >= 1 and ib >= 1, "non-vacuity: both files really bind something")
		t.truthy(cu >= cb, `CardControls: {cb} bind against {cu} unbind`)
		t.truthy(iu >= ib, `CardInput: {ib} bind against {iu} unbind`)

		-- negative controls for the counters
		t.deepEqual({ bindCounts(":BindAction(a) :BindActionAtPriority(b) :UnbindAction(a)") }, { 2, 1 }, "counts")
		t.deepEqual({ bindCounts(lex.stripComments("-- :BindAction(a)\nlocal x = 1")) }, { 0, 0 }, "comment")

		local function balanced(code: string): boolean
			local b, u = bindCounts(code)
			return u >= b
		end
		t.truthy(balanced(controls) and balanced(input), "twin: both real files are balanced")
		t.truthy(
			not balanced(replaceOnce(controls, ":UnbindAction(", ":Unbound(")),
			"MUTATION: CardControls no longer unbinds the sink"
		)
		t.truthy(
			not balanced(replaceOnce(input, ":UnbindAction(", ":Unbound(")),
			"MUTATION: CardInput no longer unbinds its accelerators"
		)
		t.truthy(
			not balanced(input .. "\nCAS:BindActionAtPriority('x', f, false, 1)"),
			"MUTATION: a second CardInput binding with no unbind"
		)
	end)

	t.test("the client never composes an intent payload outside the reducer", function()
		local sources = clientSources()
		local names: { string } = {}
		local hitList: { string } = {}
		for path, code in sources do
			table.insert(names, baseName(path))
			if path ~= CLIENT_NET and sendSites(code) > 0 then
				table.insert(hitList, `{baseName(path)}={sendSites(code)}`)
			end
		end
		table.sort(names)
		table.sort(hitList)
		print(`  renderer_discipline[15]: scanned {#names} client files ({join(names)})`)
		print(`  renderer_discipline[15]: ClientNet.send( hit list: {join(hitList)}`)
		t.truthy(#names >= 8, `non-vacuity: {#names} client files, at least 8 expected`)
		t.truthy(sources[CARD_CLIENT] ~= nil and sources[MAIN] ~= nil, "non-vacuity: both sending files were scanned")
		t.deepEqual(sendProblems(sources), {}, "exactly one card send path, and it is CardClient")

		-- negative controls
		t.equal(sendSites(lex.stripComments("-- ClientNet.send('Pass', {})")), 0, "negative control: comment")
		t.equal(sendSites("ClientNet.send('Pass', {})"), 1, "negative control: code")
		t.deepEqual(literalIntentNames('ClientNet.send("Draw", p) ClientNet.send(name, p)'), { "Draw" }, "names")

		local function with(path: string, code: string): { [string]: string }
			local copy = table.clone(sources)
			copy[path] = code
			return copy
		end
		local card = sources[CARD_CLIENT]
		t.deepEqual(
			sendProblems(with(CARD_CLIENT, replaceOnce(card, "local started = false", "local started = false"))),
			{},
			"twin: an identity edit of the real CardClient is clean"
		)
		local hand = `{UI_DIR}/CardHand.luau`
		t.truthy(
			#sendProblems(with(hand, sources[hand] .. '\nClientNet.send("Pass", { cardId = 1 })')) > 0,
			"MUTATION: a second send path in CardHand"
		)
		t.truthy(
			#sendProblems(with(CARD_CLIENT, card .. '\nClientNet.send("Draw", { seq = 1 })')) > 0,
			"MUTATION: a second send site inside CardClient"
		)
		t.truthy(
			#sendProblems(with(CARD_CLIENT, replaceOnce(card, "ClientNet.send(", "ClientNet.sent("))) > 0,
			"MUTATION: CardClient stops sending through ClientNet"
		)
		t.truthy(
			#sendProblems(with(MAIN, sources[MAIN] .. '\nClientNet.send("Pass", { cardId = 1 })')) > 0,
			"MUTATION: Main.client sends a card intent"
		)
	end)
end
