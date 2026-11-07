--!strict
-- UX-02 / D-29 gate (plan 04-19, wire gap 2): a round that ends WITHOUT removing the local seat must
-- tell the client, or the server releases the avatar while the phone keeps its movement controls hidden.
--
-- CardService and CardClient name Roblox services, so LUNE CANNOT LOAD THEM. What can be reached is the
-- comment-stripped source (lex.stripComments, the tokeniser the other source gates use), so this gate is
-- a scan, and says so. That the controls really come back on a phone is M-11.
--
-- Every gate here has a clean control, a non-vacuity count, mutants that are the REAL source text edited
-- in memory, and a no-defect TWIN (the identity edit) that must read green so no mutant can be red for
-- harness reasons. A mutation on the files on disk is recorded in the plan summary.
local CardRouting = require("../../src/server/core/CardRouting")
local Test = require("../harness/Test")
local fs = require("@lune/fs")
local lex = require("../../scripts/ci/lex")

local SERVICE_PATH = "src/server/services/CardService.luau"
local CLIENT_PATH = "src/client/ui/CardClient.luau"

-- The head of the handler. NOT "teardown()\n round = nil": onRoundStart opens with those same two lines, so
-- an edit keyed on them lands in the wrong function and the mutant is never what it claims to be.
local ENDER = "local function onRoundEnd(_payload: any)\n\t\tendRoundView()"
local VIEW_HEAD = "local function endRoundView()\n\t\tteardown()"

local function countOf(text: string, needle: string): number
	local n = 0
	local from = 1
	while true do
		local a, b = string.find(text, needle, from, true)
		if a == nil then
			return n
		end
		n += 1
		from = (b :: number) + 1
	end
end

-- The text between two markers (the first occurrence of each), or "" when either is missing.
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

-- Server half. Returns the problems with CardService's endRound.
local function serviceProblems(raw: string): ({ string }, number)
	local text = lex.stripComments(raw)
	local problems: { string } = {}
	local body = slice(text, "local function endRound", "local function onIntent")
	if body == "" then
		return { "endRound body not found" }, 0
	end
	-- Two publish sites, each pinned to its own body: endRound's (checked below) and abortStart's, the
	-- rollback of a failed start that had already announced the round (WR-03, gated in service_wiring).
	if countOf(body, '"RoundEnd"') ~= 1 then
		table.insert(problems, `RoundEnd named {countOf(body, '"RoundEnd"')} times in endRound, expected 1`)
	end
	local abortBody = slice(text, "local function abortStart", "local function startRound")
	if countOf(abortBody, '"RoundEnd"') ~= 1 or countOf(text, '"RoundEnd"') ~= 2 then
		table.insert(
			problems,
			`RoundEnd named {countOf(text, '"RoundEnd"')} times in CardService, expected 2 (endRound, abortStart)`
		)
	end
	local send = string.find(body, 'toSeated("RoundEnd", {})', 1, true)
	if send == nil then
		table.insert(problems, 'endRound does not publish toSeated("RoundEnd", {})')
	else
		-- toSeated reads the seated list, so the clear must come AFTER the send; the avatar release
		-- comes before it, so a restored client is never ahead of a still-held avatar.
		local clear = string.find(body, "table.clear(seated)", 1, true)
		if clear == nil or send > clear then
			table.insert(problems, "RoundEnd is published after table.clear(seated): it would reach nobody")
		end
		local released = string.find(body, "seatHold:releaseAll()", 1, true)
		if released == nil or send < released then
			table.insert(problems, "RoundEnd is published before the avatar hold is released")
		end
		local guard = string.find(body, "if cardTable ~= nil then", 1, true)
		if guard == nil or guard > send then
			table.insert(problems, "RoundEnd is not guarded on a live round")
		end
	end
	if
		string.find(text, 'toPlayer%(%a+, "RoundEnd"') ~= nil
		or string.find(text, 'toAll("RoundEnd"', 1, true) ~= nil
	then
		table.insert(problems, "RoundEnd goes by a method other than toSeated")
	end
	return problems, #body
end

-- Client half. The handler must be registered and must tear down.
local function clientProblems(raw: string): ({ string }, number)
	local text = lex.stripComments(raw)
	local problems: { string } = {}
	local body = slice(text, "local function onRoundEnd", "local function onNotice")
	if body == "" then
		return { "onRoundEnd body not found" }, 0
	end
	if countOf(text, "RoundEnd = onRoundEnd") ~= 1 then
		table.insert(problems, "RoundEnd is not registered in the handler table exactly once")
	end
	if string.find(body, "endRoundView()", 1, true) == nil then
		table.insert(problems, "onRoundEnd does not call endRoundView() (controls would stay hidden)")
	end
	-- endRoundView is where the controls actually come back: it must call teardown() and drop the place.
	local view = slice(text, "local function endRoundView", "local function ")
	if string.find(view, "teardown()", 1, true) == nil then
		table.insert(problems, "endRoundView does not call teardown() (controls would stay hidden)")
	end
	if string.find(view, "destroyPlace()", 1, true) == nil then
		table.insert(problems, "endRoundView does not call destroyPlace()")
	end
	if string.find(body, "round = nil", 1, true) == nil then
		table.insert(problems, "onRoundEnd does not drop the round")
	end
	return problems, #body
end

return function(t: Test.Runner)
	local serviceRaw = fs.readFile(SERVICE_PATH)
	local clientRaw = fs.readFile(CLIENT_PATH)

	t.test("RoundEnd is a public, payload-free kind in the routing table", function()
		local present = 0
		for _, kind in CardRouting.KINDS do
			if kind == "RoundEnd" then
				present += 1
			end
		end
		t.equal(present, 1, "RoundEnd is in KINDS exactly once")
		t.equal(CardRouting.audienceOf("RoundEnd"), "seated")
		t.equal(CardRouting.PRIVATE_KINDS["RoundEnd"], nil, "not a private kind")
		CardRouting.assertPublic("RoundEnd")
		-- It really fires once through the shipped assembly, to the whole seated list, with no payload.
		local sent: { { target: string, payload: unknown } } = {}
		local pub = CardRouting.makePublisher({
			fireToPlayer = function() end,
			fireToMany = function(ids, _kind, payload)
				table.insert(sent, { target = table.concat(ids, ","), payload = payload })
			end,
			fireToAll = function() end,
			seatedUserIds = function()
				return { 1, 2, 3 }
			end,
		})
		pub.toSeated("RoundEnd", {})
		t.equal(#sent, 1)
		t.equal(sent[1].target, "1,2,3")
		t.deepEqual(sent[1].payload, {}, "an empty table: nothing to leak")
	end)

	t.test("CardService.endRound publishes RoundEnd to the seated, in the right place", function()
		local problems, size = serviceProblems(serviceRaw)
		t.deepEqual(problems, {}, "clean path")
		t.truthy(size > 400, `non-vacuity: endRound body only {size} chars`)
		print(`round_end case 2: endRound body {size} chars, 0 problems`)
	end)

	t.test("CardClient handles RoundEnd by tearing down and restoring controls", function()
		local problems, size = clientProblems(clientRaw)
		t.deepEqual(problems, {}, "clean path")
		t.truthy(size > 100, `non-vacuity: onRoundEnd body only {size} chars`)
		print(`round_end case 3: onRoundEnd body {size} chars, 0 problems`)
	end)

	t.test("MUTATION: each way of losing the round-end signal turns a gate red", function()
		-- No-defect twin: the identity edit through the very same mutation plumbing.
		local twinService = replaceOnce(serviceRaw, 'toSeated("RoundEnd", {})', 'toSeated("RoundEnd", {})')
		local twinClient = replaceOnce(replaceOnce(clientRaw, ENDER, ENDER), VIEW_HEAD, VIEW_HEAD)
		t.deepEqual((serviceProblems(twinService)), {}, "the no-defect service twin must be green")
		t.deepEqual((clientProblems(twinClient)), {}, "the no-defect client twin must be green")

		local mutants: { { name: string, problems: { string } } } = {
			{
				name = "service: publish deleted",
				problems = (serviceProblems(replaceOnce(serviceRaw, 'toSeated("RoundEnd", {})', "(nil)"))),
			},
			{
				name = "service: published through toAll",
				problems = (serviceProblems(
					replaceOnce(serviceRaw, 'toSeated("RoundEnd", {})', 'toAll("RoundEnd", {})')
				)),
			},
			{
				name = "service: seated cleared before the send",
				problems = (
					serviceProblems(replaceOnce(
						serviceRaw,
						-- keyed on endRound's own call (two tabs); abortStart's sits one level deeper
						"\n\t\tseatHold:releaseAll()",
						"\n\t\tseatHold:releaseAll()\n\t\ttable.clear(seated)"
					))
				),
			},
			{
				name = "service: released only after the send",
				problems = (serviceProblems(replaceOnce(serviceRaw, "\n\t\tseatHold:releaseAll()", "\n\t\t(nil)"))),
			},
			{
				name = "client: handler not registered",
				problems = (clientProblems(replaceOnce(clientRaw, "RoundEnd = onRoundEnd", "RoundEndX = onRoundEnd"))),
			},
			{
				name = "client: endRoundView does not restore the controls",
				problems = (clientProblems(replaceOnce(clientRaw, VIEW_HEAD, "local function endRoundView()"))),
			},
			{
				name = "client: handler does not tear down",
				problems = (clientProblems(replaceOnce(clientRaw, ENDER, "local function onRoundEnd(_payload: any)"))),
			},
		}
		for _, m in mutants do
			t.truthy(#m.problems > 0, `{m.name} must turn the gate red`)
			print(`  round_end mutation ({m.name}): {#m.problems} problem(s), e.g. {m.problems[1]}`)
		end
		t.equal(#mutants, 7, "mutation count")
	end)
end
