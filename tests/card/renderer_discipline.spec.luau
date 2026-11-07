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
		t.truthy(#files >= 2, `non-vacuity: scanned {#files} files`)
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
		t.truthy(#files >= 2, `non-vacuity: scanned {#files} files`)
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
		t.truthy(#files >= 2, `non-vacuity: scanned {#files} files`)
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
		t.truthy(#files >= 2, `non-vacuity: scanned {#files} files`)
		local total = 0
		for _, path in files do
			local n = hitsIn(fs.readFile(path))
			total += n
			t.equal(n, 0, `forbidden identifier in {path}`)
		end
		print(`  renderer_discipline[4]: {#files} files, {#needles} identifiers, {total} hits`)
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
end
