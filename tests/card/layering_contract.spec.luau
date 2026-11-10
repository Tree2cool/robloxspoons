--!strict
-- THE CONTRACT AROUND THE LAYERING ROUTE (Phase 04.1, Wave 0, plan 04.1-01).
--
-- WHAT THIS FILE PROVES: that the route is one of two legal values; that it has at most one read site in `src/`;
-- that choosing route `"Depth"` cannot silently drop the M-23 lighting-independence obligation; that the Studio
-- probe names every route the decision doc names; and that the shared card geometry never reads the route.
--
-- WHAT IT CANNOT PROVE, AND NOTHING IN THIS REPOSITORY CAN: whether the layering is actually right. That is a
-- photograph of two `AlwaysOnTop` SurfaceGuis on different Parts, it needs Studio, and it is **MANUAL-CHECKS
-- M-18**, which is unsigned. `Card.HAND.LAYERING_ROUTE` is PROVISIONAL until it is signed. Do not read a green
-- run here as evidence about draw order.
--
-- THE READ-SITE BUDGET IS A RATCHET, NOT A CEILING NOBODY TIGHTENS. Case 3 counts read sites OUTSIDE the file
-- that defines the constant -- the definition is not a read -- and asserts `<= 1`. At this wave that count is 0,
-- because the carrier does not exist yet. **PLAN 06 BUILDS THE CARRIER AND MUST RAISE THIS TO `== 1`.** If you
-- are reading this after plan 06 and the assertion still says `<=`, that is the bug.
--
-- CASE 5's TRUE TARGET DOES NOT EXIST YET. `src/shared/Card/Projection.luau` arrives in plan 02; this case
-- asserts over whatever is in `src/shared/Card/` today (6 files) so that the rule is in place before the file it
-- is aimed at, rather than being written by the same plan that could violate it.
--
-- SCAN DISCIPLINE. Every source scan here runs through `lex.stripComments`, so **it scans CODE and never
-- COMMENTS** -- string literals are KEPT. Both halves matter: the config header must be free to NAME
-- `AlwaysOnTop` in order to explain the spike, while the probe's route labels live in `print` strings and are
-- deliberately counted (a route named only in a comment is a route nobody will photograph). The shell-callable
-- twin of this scanner is `scripts/dev/scan.luau`.
--
-- WHY THE M-23 GATE NEVER CHECKS THE BOX. This spec is PERMANENT, so it must tolerate a SIGNED row. It asserts
-- the row EXISTS and is BLOCKING; it must NEVER assert that the row is still unticked. The moment the owner does
-- the thing the row exists to ask for, an unticked-only assertion would turn the suite red and the phase could
-- not close. **A gate that punishes the correct action is worse than no gate.** "Nothing device-dependent was
-- ticked by a machine" is a one-time authoring check (plan 04.1-01's own verify step and its summary), not a
-- standing test. Case 2's no-defect twin runs the predicate against a TICKED copy and requires it to PASS.
local Card = require("../../src/shared/Config/Card")
local Test = require("../harness/Test")
local fs = require("@lune/fs")
local lex = require("../../scripts/ci/lex")

local MANUAL = "MANUAL-CHECKS.md"
local CONFIG = "src/shared/Config/Card.luau"
local PROBE = "scripts/dev/spike-layering.luau"
local DECISION = ".planning/phases/04.1-first-person-cards/04.1-LAYERING-DECISION.md"
local GEOMETRY_DIR = "src/shared/Card"
local SRC_DIR = "src"
local ROUTE_LABELS = { "Route A", "Route B", "Route C" }

-- ---------------------------------------------------------------------------------------------------------------
-- The predicates under test. Each is a pure function of text, so every case can drive it on synthetic input as
-- well as on the real tree -- which is the only way a negative control is possible.
-- ---------------------------------------------------------------------------------------------------------------

local function isLegalRoute(route: any): boolean
	return route == "AlwaysOnTop" or route == "Depth"
end

-- Route "Depth" restores depth testing and with it scene lighting, so it is the only route that needs the
-- lighting-independence row. One function, named, so the obligation is a value and not an `if` buried in a case.
local function requiresLightingRow(route: string): boolean
	return route == "Depth"
end

-- The text of the `## M-23 ...` section, up to the next `##` heading or the end of the file.
local function m23Section(manualText: string): string?
	local text = "\n" .. manualText .. "\n## END\n"
	local from = string.find(text, "\n## M%-23")
	if from == nil then
		return nil
	end
	local stop = string.find(text, "\n## ", from + 1)
	return string.sub(text, from + 1, if stop ~= nil then stop - 1 else #text)
end

-- The parse-critical sign-off line, matched for EXISTENCE and nothing else: `- [ ]` and `- [x]` both match, on
-- purpose (see the header).
local function m23SignOffLine(section: string): string?
	return string.match("\n" .. section, "\n(%- %[[ x]%] M%-23 signed off:[^\n]*)")
end

local function m23BlockingLine(section: string): string?
	return string.match(section, "%*%*Blocking:[^\n]*")
end

export type Verdict = { ok: boolean, why: string, row: string }

local function checkLightingObligation(route: string, manualText: string): Verdict
	local section = m23Section(manualText)
	if section == nil then
		return { ok = false, why = "the M-23 section is missing from MANUAL-CHECKS.md entirely", row = "" }
	end
	local row = m23SignOffLine(section)
	if row == nil then
		return { ok = false, why = "the `- [ ] M-23 signed off:` line is missing from the M-23 section", row = "" }
	end
	if requiresLightingRow(route) then
		local blocking = m23BlockingLine(section)
		if blocking == nil or string.find(blocking, "yes", 1, true) == nil then
			return {
				ok = false,
				why = `route Depth needs M-23 to be BLOCKING; its Blocking line reads: {tostring(blocking)}`,
				row = row,
			}
		end
		return { ok = true, why = "route Depth: the M-23 row exists and is blocking", row = row }
	end
	if string.find(section, "NOT APPLICABLE", 1, true) == nil then
		return {
			ok = false,
			why = "route AlwaysOnTop needs M-23 to say NOT APPLICABLE for this route, and it does not",
			row = row,
		}
	end
	return { ok = true, why = "route AlwaysOnTop: the M-23 row exists and says NOT APPLICABLE", row = row }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------------------------------------------

local function luauFilesUnder(dir: string, found: { string })
	local names = fs.readDir(dir)
	table.sort(names)
	for _, name in names do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			luauFilesUnder(path, found)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(found, path)
		end
	end
end

-- Whole-token, case-sensitive, comments stripped. `LAYERING_ROUTES` must not satisfy a scan for `LAYERING_ROUTE`.
local function countTokenInText(text: string, token: string): number
	local code = lex.stripComments(text)
	local n, from = 0, 1
	while true do
		local a, b = lex.findWord(code, token, from)
		if a == nil or b == nil then
			return n
		end
		n += 1
		from = b + 1
	end
end

local function countTokenInFile(path: string, token: string): number
	return countTokenInText(fs.readFile(path), token)
end

return function(t: Test.Runner)
	t.test("[1] LAYERING_ROUTE is exactly one of the two legal values (clean control)", function()
		local route = Card.HAND.LAYERING_ROUTE
		print(`  shipped route: "{tostring(route)}" (PROVISIONAL until M-18 is signed)`)
		t.equal(typeof(route), "string", "the route must be a string")
		t.truthy(isLegalRoute(route), `illegal LAYERING_ROUTE "{tostring(route)}"`)
		-- Negative control: the same predicate on values that are nearly right. Case matters, abbreviations do
		-- not count, and nil is not a default.
		local rejected = 0
		for _, bad in { "Alwaysontop", "alwaysontop", "A", "", "depth", "AlwaysOnTop ", "Depth\n" } do
			t.falsy(isLegalRoute(bad), `negative control: "{bad}" must be rejected`)
			rejected += 1
		end
		t.falsy(isLegalRoute(nil), "negative control: nil must be rejected")
		t.falsy(isLegalRoute(true), "negative control: a boolean must be rejected")
		print(`  negative control: {rejected + 2} near-miss values rejected`)
		t.equal(rejected, 7, "non-vacuity: every near-miss was driven")
	end)

	t.test("[2] route Depth cannot silently drop the M-23 lighting row (the one that matters)", function()
		local manual = fs.readFile(MANUAL)
		local route = Card.HAND.LAYERING_ROUTE

		-- Clean control: the real file, the real route.
		local live = checkLightingObligation(route, manual)
		print(`  live route "{route}": {live.why}`)
		print(`  matched row: {live.row}`)
		t.truthy(live.ok, `the real tree fails its own M-23 obligation: {live.why}`)
		-- Non-vacuity: the matched text is real text and is the right row.
		t.truthy(#live.row > 0, "non-vacuity: the matched row text is empty")
		t.contains(live.row, "M-23", "non-vacuity: the matched row is not the M-23 row")

		-- No-defect twin A: force the route to Depth. The row is present, so this must PASS.
		local forced = checkLightingObligation("Depth", manual)
		print(`  forced "Depth" against the real file: ok={forced.ok} -- {forced.why}`)
		t.truthy(forced.ok, `forcing route Depth must PASS while the M-23 row exists: {forced.why}`)

		-- No-defect twin B: the row TICKED. This is the whole reason the gate matches `[ x]` and never `[ ]`:
		-- the moment the owner signs M-23, an unticked-only assertion would turn this suite red.
		local ticked =
			string.gsub(manual, "%- %[ %] M%-23 signed off:", "- [x] M-23 signed off: alejandrog_m 2026-12-01")
		t.truthy(string.find(ticked, "- [x] M-23 signed off:", 1, true) ~= nil, "the ticked copy was not built")
		local tickedVerdict = checkLightingObligation("Depth", ticked)
		print(`  route "Depth" with M-23 TICKED: ok={tickedVerdict.ok} -- {tickedVerdict.why}`)
		t.truthy(tickedVerdict.ok, "a SIGNED M-23 row must still PASS: a gate that punishes the correct action")
		local tickedA = checkLightingObligation("AlwaysOnTop", ticked)
		t.truthy(tickedA.ok, "a SIGNED M-23 row must still PASS under route AlwaysOnTop too")

		-- Negative control 1: the row line deleted, route Depth. MUST FAIL.
		local noRow = string.gsub(manual, "%- %[[ x]%] M%-23 signed off:[^\n]*", "(row deleted by the test)")
		t.truthy(m23SignOffLine(m23Section(noRow) :: string) == nil, "the row-deleted copy still has a row")
		local deleted = checkLightingObligation("Depth", noRow)
		print(`  NEGATIVE CONTROL, M-23 row deleted, route "Depth": ok={deleted.ok} -- {deleted.why}`)
		t.falsy(deleted.ok, "deleting the M-23 row under route Depth MUST fail; the gate cannot fire")

		-- Negative control 2: the whole section deleted, route Depth. MUST FAIL.
		local section = m23Section(manual) :: string
		local noSection = string.gsub(manual, "## M%-23.*", "", 1)
		t.truthy(m23Section(noSection) == nil, "the section-deleted copy still has an M-23 section")
		t.falsy(checkLightingObligation("Depth", noSection).ok, "a missing M-23 section under Depth MUST fail")

		-- Negative control 3: the row present but no longer blocking, route Depth. MUST FAIL.
		local notBlocking = string.gsub(manual, "%*%*Blocking: yes, if and only if", "**Blocking: no, never for", 1)
		t.truthy(notBlocking ~= manual, "the not-blocking copy was not built")
		local unblocked = checkLightingObligation("Depth", notBlocking)
		print(`  NEGATIVE CONTROL, M-23 no longer blocking, route "Depth": ok={unblocked.ok}`)
		t.falsy(unblocked.ok, "an M-23 row that is not blocking MUST fail under route Depth")

		-- Negative control 4: route AlwaysOnTop with the NOT APPLICABLE statement gone. MUST FAIL.
		local noNa = string.gsub(manual, "NOT APPLICABLE", "unclear", 1)
		while string.find(noNa, "NOT APPLICABLE", 1, true) ~= nil do
			noNa = string.gsub(noNa, "NOT APPLICABLE", "unclear", 1)
		end
		t.falsy(
			checkLightingObligation("AlwaysOnTop", noNa).ok,
			"route AlwaysOnTop with no NOT APPLICABLE statement MUST fail"
		)
		print(`  section scanned: {#section} chars; 4 negative controls fired`)
		t.truthy(#section > 800, `non-vacuity: the M-23 section is only {#section} chars -- is it really there?`)
	end)

	t.test("[3] LAYERING_ROUTE has at most one read site in src/ (ratchet; plan 06 raises it to == 1)", function()
		local files: { string } = {}
		luauFilesUnder(SRC_DIR, files)
		t.truthy(#files >= 40, `non-vacuity: only {#files} files under {SRC_DIR}`)

		local definitionHits = countTokenInFile(CONFIG, "LAYERING_ROUTE")
		local readSites = 0
		local readFiles: { string } = {}
		local total = 0
		for _, path in files do
			local n = countTokenInFile(path, "LAYERING_ROUTE")
			total += n
			if n > 0 and path ~= CONFIG then
				readSites += n
				table.insert(readFiles, `{path} x{n}`)
			end
		end
		print(`  {#files} files scanned (comments stripped, strings kept)`)
		print(`  definition site {CONFIG}: {definitionHits}`)
		print(
			`  READ sites outside the definition: {readSites} [{table.concat(readFiles, ", ")}] (total in src/: {total})`
		)
		-- Non-vacuity: the scanner finds the one occurrence that definitely exists. Without this the budget would
		-- pass just as happily against a scanner that matched nothing at all.
		t.equal(definitionHits, 1, "the config must define LAYERING_ROUTE exactly once")
		t.truthy(readSites <= 1, `LAYERING_ROUTE is read in {readSites} places; the budget is 1`)

		-- Negative control: the same scanner over synthetic text with two real hits must report 2, and must not
		-- be fooled by a longer identifier.
		t.equal(countTokenInText("local a = C.LAYERING_ROUTE\nlocal b = C.LAYERING_ROUTE\n", "LAYERING_ROUTE"), 2)
		t.equal(countTokenInText("local a = C.LAYERING_ROUTES\n", "LAYERING_ROUTE"), 0)
		t.equal(countTokenInText("-- LAYERING_ROUTE in a comment\nlocal a = 1\n", "LAYERING_ROUTE"), 0)
		t.equal(countTokenInText('local a = "LAYERING_ROUTE"\n', "LAYERING_ROUTE"), 1)
	end)

	t.test("[4] the probe names every route the decision doc names", function()
		local probeCode = lex.stripComments(fs.readFile(PROBE))
		local decisionText = fs.readFile(DECISION)
		t.truthy(#probeCode > 2000, `non-vacuity: the probe stripped to {#probeCode} chars`)
		t.truthy(#decisionText > 2000, `non-vacuity: the decision doc is {#decisionText} chars`)

		local function mentions(text: string, labels: { string }): number
			local found = 0
			for _, label in labels do
				if string.find(text, label, 1, true) ~= nil then
					found += 1
				end
			end
			return found
		end

		for _, label in ROUTE_LABELS do
			-- The probe is scanned COMMENT-STRIPPED on purpose: these labels live in its `print` lines, so the
			-- assertion is about what the operator is TOLD to look at, not about what the header says.
			t.truthy(string.find(probeCode, label, 1, true) ~= nil, `the probe never prints "{label}"`)
			t.truthy(string.find(decisionText, label, 1, true) ~= nil, `the decision doc never names "{label}"`)
		end
		-- Both legal route values must appear in the probe's code, or one of them is unphotographable.
		t.truthy(string.find(probeCode, "AlwaysOnTop", 1, true) ~= nil, "the probe never mentions AlwaysOnTop")
		t.truthy(string.find(probeCode, "Depth", 1, true) ~= nil, "the probe never mentions Depth")
		-- Five cards, not three: a probe of three centred cards can pass while the rolled end pair fails.
		t.truthy(string.find(probeCode, "HAND_SIZE = 5", 1, true) ~= nil, "the probe must build five cards a route")
		print(
			`  probe mentions {mentions(probeCode, ROUTE_LABELS)}/3 route labels in CODE, doc {mentions(
				decisionText,
				ROUTE_LABELS
			)}/3`
		)

		-- Negative control: the same predicate over a probe that forgot route C must see only 2.
		t.equal(mentions('print("Route A") print("Route B")', ROUTE_LABELS), 2, "negative control: a missing route")
		t.equal(mentions("-- Route A Route B Route C", ROUTE_LABELS), 3, "control: the predicate is a plain find")
	end)

	t.test("[5] the shared card geometry never reads the route", function()
		local files: { string } = {}
		luauFilesUnder(GEOMETRY_DIR, files)
		-- Projection.luau arrives in plan 02; this asserts over whatever is here today, so the rule predates the
		-- file it is aimed at.
		t.truthy(#files >= 5, `non-vacuity: only {#files} files under {GEOMETRY_DIR}`)
		local forbidden = { "LAYERING_ROUTE", "AlwaysOnTop", "ZOffset" }
		local total = 0
		for _, path in files do
			for _, token in forbidden do
				local n = countTokenInFile(path, token)
				total += n
				t.equal(n, 0, `{path} reads "{token}": the geometry must not know which route is live`)
			end
		end
		print(`  {#files} files under {GEOMETRY_DIR} x {#forbidden} tokens, {total} hits`)

		-- Negative control: the scanner fires on each token when it really is in code, and not when it is in a
		-- comment -- which is why the config header may explain `AlwaysOnTop` while this case forbids it here.
		t.equal(countTokenInText("gui.AlwaysOnTop = true\n", "AlwaysOnTop"), 1)
		t.equal(countTokenInText("gui.ZOffset = slot\n", "ZOffset"), 1)
		t.equal(countTokenInText("local r = Card.HAND.LAYERING_ROUTE\n", "LAYERING_ROUTE"), 1)
		t.equal(countTokenInText("-- AlwaysOnTop is the Wave 0 question\n", "AlwaysOnTop"), 0)
	end)
end
