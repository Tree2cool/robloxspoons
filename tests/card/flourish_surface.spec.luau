--!strict
-- The Roblox-side halves of plan 04-19: the flourish Surface, the audio, the seat stacks and the callout
-- (checker FLAG F8, D-30, D-32, D-33, CARD-13).
--
-- LUNE CANNOT LOAD ANY OF THESE MODULES: they name game:GetService and Instance.new. What is reachable is
-- (a) the comment-stripped SOURCE TEXT, scanned, and (b) one function, `offenderKind`, whose text is
-- extracted and EXECUTED over fake instances with luau.load, so the five-kind coverage F8 depends on is run
-- rather than merely grepped. That the Surface really destroys an input sink in a live place is M-17; that
-- the cards, stacks and sounds look and sound right is M-12 / M-16 / M-17. Nothing here claims otherwise.
--
-- Every gate has a clean control, a non-vacuity count, mutants that are the REAL source text edited in
-- memory, and a no-defect TWIN (the identity edit through the same plumbing) asserted green so no mutant is
-- red for harness reasons. The plan summary records the same mutations made on the files on disk.
local Card = require("../../src/shared/Config/Card")
local Flourish = require("../../src/shared/Card/Flourish")
local Test = require("../harness/Test")
local fs = require("@lune/fs")
local lex = require("../../scripts/ci/lex")
local luau = require("@lune/luau")

local FLOURISH_PATH = "src/client/ui/CardFlourish.luau"
local AUDIO_PATH = "src/client/ui/CardAudio.luau"
local SEATS_PATH = "src/client/ui/CardSeatsView.luau"
local CALLOUT_PATH = "src/client/ui/CardCallout.luau"
local CLIENT_PATH = "src/client/ui/CardClient.luau"

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

local function replaceOnce(text: string, old: string, new: string): string
	local a, b = string.find(text, old, 1, true)
	assert(a ~= nil, `replaceOnce: {old} not found`)
	return string.sub(text, 1, a - 1) .. new .. string.sub(text, (b :: number) + 1)
end

-- ---------------------------------------------------------------------------------------------------------
-- offenderKind, executed. A fake instance answers IsA from a class set and carries Active / Interactable.
-- ---------------------------------------------------------------------------------------------------------
type Fake = { classes: { [string]: boolean }, Active: boolean, Interactable: boolean, IsA: (Fake, string) -> boolean }

local function fake(classNames: { string }, active: boolean, interactable: boolean): Fake
	local classes: { [string]: boolean } = {}
	for _, name in classNames do
		classes[name] = true
	end
	return {
		classes = classes,
		Active = active,
		Interactable = interactable,
		IsA = function(self: Fake, class: string): boolean
			return self.classes[class] == true
		end,
	}
end

type Probe = { label: string, instance: Fake, expect: string? }

-- The five input-taking kinds, then the things that must NOT be reported. The plain Frame carries
-- Interactable = true (the engine default) on purpose: flagging it is the plan's literal wording and would
-- delete every card the default flourishes make.
local function probes(): { Probe }
	return {
		{ label = "TextBox", instance = fake({ "TextBox", "GuiObject" }, false, true), expect = "TextBox" },
		{ label = "ClickDetector", instance = fake({ "ClickDetector" }, false, true), expect = "ClickDetector" },
		{ label = "ProximityPrompt", instance = fake({ "ProximityPrompt" }, false, true), expect = "ProximityPrompt" },
		{ label = "Interactable", instance = fake({ "GuiButton", "GuiObject" }, false, true), expect = "Interactable" },
		{ label = "Active", instance = fake({ "GuiObject" }, true, true), expect = "Active" },
		{ label = "plain Frame", instance = fake({ "GuiObject" }, false, true), expect = nil },
		{ label = "plain Part", instance = fake({ "BasePart" }, false, false), expect = nil },
		{ label = "disabled button", instance = fake({ "GuiButton", "GuiObject" }, false, false), expect = nil },
	}
end

local function extractPredicate(raw: string): string
	local text = lex.stripComments(raw)
	local a = string.find(text, "local function offenderKind", 1, true)
	assert(a ~= nil, "offenderKind not found in CardFlourish")
	local b = string.find(text, "\nend\n", a, true)
	assert(b ~= nil, "offenderKind has no end")
	return string.sub(text, a, b + 4) .. "\nreturn offenderKind\n"
end

-- Returns (problems, probesRun, kindsDetected).
local function coverageProblems(raw: string): ({ string }, number, number)
	local chunk = luau.load(extractPredicate(raw))
	local predicate = chunk() :: (Fake) -> string?
	local problems: { string } = {}
	local run, detected = 0, 0
	for _, probe in probes() do
		run += 1
		local got = predicate(probe.instance)
		if got ~= probe.expect then
			table.insert(problems, `{probe.label}: expected {tostring(probe.expect)}, got {tostring(got)}`)
		elseif got ~= nil then
			detected += 1
		end
	end
	return problems, run, detected
end

-- ---------------------------------------------------------------------------------------------------------
-- Part-site counting (case 6).
-- ---------------------------------------------------------------------------------------------------------
local PART_PROPERTIES = { "CanCollide = false", "CanQuery = false", "CanTouch = false", "Anchored = true" }
local PART_REENABLED = { "CanCollide = true", "CanQuery = true", "CanTouch = true", "Anchored = false" }

-- Returns (problems, sites).
local function partProblems(raw: string): ({ string }, number)
	local text = lex.stripComments(raw)
	local sites = countOf(text, 'Instance.new("Part")')
	local problems: { string } = {}
	if sites < 1 then
		table.insert(problems, "no part-creation site found (the scan would be vacuous)")
	end
	for _, property in PART_PROPERTIES do
		local n = countOf(text, property)
		if n < sites then
			table.insert(problems, `{property} appears {n} times for {sites} part sites`)
		end
	end
	for _, property in PART_REENABLED do
		if countOf(text, property) > 0 then
			table.insert(problems, `{property} appears: a re-enabled property hides behind the counts`)
		end
	end
	return problems, sites
end

-- ---------------------------------------------------------------------------------------------------------
-- Audio guard offset (case 5).
-- ---------------------------------------------------------------------------------------------------------
-- Returns (problems, guardOffset, constructorOffset).
local function audioProblems(raw: string): ({ string }, number, number)
	local text = lex.stripComments(raw)
	local problems: { string } = {}
	local constructors = countOf(text, 'Instance.new("Sound")')
	if constructors > 1 then
		table.insert(problems, `{constructors} Sound constructors, expected at most one`)
	end
	local constructor = string.find(text, 'Instance.new("Sound")', 1, true) or -1
	local guard = string.find(text, '== ""', 1, true) or string.find(text, '~= ""', 1, true) or -1
	if constructor < 0 then
		table.insert(problems, "no Sound constructor found (the offset comparison would be vacuous)")
	elseif guard < 0 then
		table.insert(problems, "no empty-string guard found")
	elseif guard > constructor then
		table.insert(problems, `the empty-id guard (offset {guard}) comes AFTER the constructor (offset {constructor})`)
	end
	return problems, guard, constructor
end

return function(t: Test.Runner)
	local flourishRaw = fs.readFile(FLOURISH_PATH)
	local audioRaw = fs.readFile(AUDIO_PATH)
	local seatsRaw = fs.readFile(SEATS_PATH)
	local calloutRaw = fs.readFile(CALLOUT_PATH)
	local clientRaw = fs.readFile(CLIENT_PATH)
	local flourish = lex.stripComments(flourishRaw)

	t.test("the flourish ScreenGui's DisplayOrder is strictly below the hand's (F8, second half)", function()
		t.truthy(Card.FLOURISH_DISPLAY_ORDER < Card.HAND_DISPLAY_ORDER, "config: flourish below hand")
		-- Set from the config name through the one ScreenGui factory, and from no literal.
		t.equal(countOf(flourish, "CardHud.newGui("), 1, "one ScreenGui is created")
		t.truthy(
			string.find(flourish, 'CardHud.newGui("CardFlourish", Card.FLOURISH_DISPLAY_ORDER)', 1, true) ~= nil,
			"the flourish ScreenGui's DisplayOrder is Card.FLOURISH_DISPLAY_ORDER"
		)
		t.equal(string.find(flourish, "DisplayOrder%s*=%s*%d"), nil, "no DisplayOrder is set from a numeric literal")
		-- The runtime comparison against the live hand ScreenGui exists too.
		t.truthy(
			string.find(flourish, "gui.DisplayOrder >= hud:gui().DisplayOrder", 1, true) ~= nil,
			"the live comparison against the hand's ScreenGui is present"
		)
		-- Negative control: a literal would be caught.
		t.truthy(string.find("gui.DisplayOrder = 5", "DisplayOrder%s*=%s*%d") ~= nil, "negative control: literal")
	end)

	t.test("the Surface implements every member, and scan and destroyOffenders share ONE predicate", function()
		local members = {
			"createRoot",
			"destroyRoot",
			"scan",
			"destroyOffenders",
			"snapshot",
			"diff",
			"destroyEscaped",
		}
		for _, member in members do
			t.equal(countOf(flourish, `{member} = function`), 1, `Surface.{member} is defined exactly once`)
		end
		-- destroyOffenders is the half of F8 the driver's contract added: reporting without destroying leaves
		-- the sink in place until the cut-off.
		t.equal(countOf(flourish, "offendersUnder("), 3, "one definition, one call in scan, one in destroyOffenders")
	end)

	t.test("the scan looks for every input-taking kind, not only Active (executed, M-17 is the live check)", function()
		-- The certain defect shape is a scan that names only Active: the flourish gate would pass while the
		-- real hole stayed open. Here the real predicate text runs over fakes of all five kinds.
		local problems, run, detected = coverageProblems(flourishRaw)
		t.deepEqual(problems, {}, "clean path")
		t.equal(run, 8, "non-vacuity: probes run")
		t.equal(detected, 5, "non-vacuity: all five input-taking kinds detected")
		print(`flourish_surface case 3: {run} probes run, {detected} kinds detected, 0 problems`)

		for _, name in { "Active", "Interactable", "ClickDetector", "ProximityPrompt", "TextBox" } do
			t.truthy(string.find(flourish, name, 1, true) ~= nil, `the comment-stripped text names {name}`)
		end

		-- No-defect twin through the same plumbing.
		local twin = replaceOnce(flourishRaw, 'inst:IsA("TextBox")', 'inst:IsA("TextBox")')
		t.deepEqual((coverageProblems(twin)), {}, "the no-defect twin must be green")

		local mutations = 0
		local edits: { { name: string, old: string, new: string } } = {
			{ name = "TextBox dropped", old = 'inst:IsA("TextBox")', new = "false" },
			{ name = "ClickDetector dropped", old = 'inst:IsA("ClickDetector")', new = "false" },
			{ name = "ProximityPrompt dropped", old = 'inst:IsA("ProximityPrompt")', new = "false" },
			{ name = "Interactable dropped", old = "(inst :: GuiButton).Interactable", new = "false" },
			{ name = "Active dropped", old = "(inst :: GuiObject).Active", new = "false" },
			-- the plan's literal wording: every Interactable GuiObject, which flags a plain Frame
			{
				name = "Interactable on every GuiObject",
				old = 'inst:IsA("GuiButton") and (inst :: GuiButton).Interactable',
				new = 'inst:IsA("GuiObject") and (inst :: GuiObject).Interactable',
			},
		}
		for _, edit in edits do
			local problemsMutant = coverageProblems(replaceOnce(flourishRaw, edit.old, edit.new))
			t.truthy(#problemsMutant > 0, `{edit.name} must turn the coverage gate red`)
			mutations += 1
			print(`  flourish_surface mutation ({edit.name}): {problemsMutant[1]}`)
		end
		t.equal(mutations, 6, "mutation count")
	end)

	t.test("the surface adds no timer of its own (D-32)", function()
		t.equal(countOf(flourish, "task.delay("), 1, "exactly one task.delay (the Scheduler's)")
		t.equal(countOf(flourish, "task.cancel("), 1, "exactly one task.cancel (the Scheduler's)")
		t.equal(countOf(flourish, "task.spawn("), 1, "exactly one task.spawn (the Scheduler's)")
		-- The duration number is read once, where the driver is constructed.
		t.equal(countOf(flourish, "FLOURISH_DURATION_SECONDS"), 1, "the duration is read once, by the driver")
		-- Mutants: a second timer of any of the three kinds, and a second reading of the duration.
		local base = flourish
		t.equal(countOf(base .. "\ntask.delay(1, f)", "task.delay("), 2, "negative control: a second timer is counted")
		t.equal(countOf(base .. "\nCard.FLOURISH_DURATION_SECONDS", "FLOURISH_DURATION_SECONDS"), 2, "negative control")
	end)

	t.test(
		"the default flourishes finish strictly inside the cut-off, with margin the implementation must not eat",
		function()
			local completion = Flourish.totalOf(Flourish.DEFAULTS.Completion)
			local deal = Flourish.totalOf(Flourish.DEFAULTS.Deal)
			t.truthy(
				completion + 0.2 <= Card.FLOURISH_DURATION_SECONDS,
				`Completion {completion} s leaves < 0.2 s of margin`
			)
			t.truthy(deal + 0.2 <= Card.FLOURISH_DURATION_SECONDS, `Deal {deal} s leaves < 0.2 s of margin`)
			-- The implementation executes the DATA and adds no step: it reads each step's seconds by name and
			-- carries no timing literal of its own.
			for _, step in { "flip", "hold", "slide" } do
				t.truthy(
					string.find(flourish, `seconds.{step}`, 1, true) ~= nil,
					`the Completion flourish reads the {step} step from the data`
				)
			end
			t.truthy(string.find(flourish, "def.settleBySeconds", 1, true) ~= nil, "Deal reads settleBySeconds")
			t.truthy(string.find(flourish, "def.staggerSeconds", 1, true) ~= nil, "Deal reads staggerSeconds")
			print(
				`flourish_surface case 4: Completion {completion} s, Deal {deal} s against a {Card.FLOURISH_DURATION_SECONDS} s cut-off`
			)
		end
	)

	t.test("audio is silent with an empty id, by offset (D-33, M-16)", function()
		local problems, guard, constructor = audioProblems(audioRaw)
		t.deepEqual(problems, {}, "clean path")
		t.truthy(guard > 0 and constructor > 0, "non-vacuity: both offsets found")
		t.truthy(guard < constructor, `guard offset {guard} precedes constructor offset {constructor}`)
		t.equal(Card.AUDIO.STING, "", "STING ships empty pending M-16")
		t.equal(Card.AUDIO.DRAW, "", "DRAW ships empty pending M-16")
		t.equal(Card.AUDIO.PASS, "", "PASS ships empty pending M-16")
		-- Nothing in the file plays for another seat's pass.
		local stripped = lex.stripComments(audioRaw)
		for _, name in { "sting", "ownDraw", "ownPass", "destroy" } do
			t.equal(countOf(stripped, `{name} = function`), 1, `Audio.{name} is the only such method`)
		end

		-- negative control: the constructor first and the guard after must be reported
		local reversed = 'local s = Instance.new("Sound")\nif assetId == "" then return end\n'
		local reversedProblems, rGuard, rConstructor = audioProblems(reversed)
		t.truthy(#reversedProblems > 0, "negative control: a late guard is reported")
		print(`flourish_surface negative control: guard offset {rGuard} after constructor offset {rConstructor}`)
		-- a second constructor is reported too
		t.truthy(
			#(audioProblems(stripped .. '\nlocal b = Instance.new("Sound")')) > 0,
			"negative control: a second Sound"
		)
		-- twin and real-source mutation: delete the guard from the real text
		t.deepEqual(
			(audioProblems(replaceOnce(audioRaw, 'if assetId == "" then', 'if assetId == "" then'))),
			{},
			"twin"
		)
		local unguarded = audioProblems(replaceOnce(audioRaw, 'assetId == ""', "false"))
		t.truthy(#unguarded > 0, "deleting the guard from the real source turns the gate red")
		print(`flourish_surface case 5: guard offset {guard}, constructor offset {constructor}`)
	end)

	t.test("EVERY cosmetic part is non-collidable and non-queryable, not just one (Phase 5 raycast trap)", function()
		-- RaycastParams.RespectCanCollide defaults to FALSE, the opposite of this project's collision model, so
		-- a cosmetic that stayed queryable would be hit by Phase 5's line-of-sight raycast even with collisions
		-- off, and one missed part is one spoon that cannot be seen.
		local seatsProblems, seatsSites = partProblems(seatsRaw)
		local flourishProblems, flourishSites = partProblems(flourishRaw)
		t.deepEqual(seatsProblems, {}, "CardSeatsView")
		t.deepEqual(flourishProblems, {}, "CardFlourish")
		-- The preferred shape shipped: exactly one creation helper per file, so the counts are exact.
		t.equal(seatsSites, 1, "CardSeatsView has exactly one part-creation site")
		t.equal(flourishSites, 1, "CardFlourish has exactly one part-creation site")
		local seats = lex.stripComments(seatsRaw)
		t.truthy(countOf(seats, "newPart(") >= 3, "the stacks and the hop pool all go through the helper")
		t.truthy(countOf(flourish, "newCardPart(") >= 2, "the flourish cards go through the helper")
		print(`flourish_surface case 6: part sites CardSeatsView={seatsSites}, CardFlourish={flourishSites}`)

		-- negative control: two sites with one CanCollide = false is a shortfall
		local twoSites = 'Instance.new("Part")\nCanCollide = false\nCanQuery = false\nCanTouch = false\nAnchored = true\n'
			.. 'Instance.new("Part")\n'
		local shortfall = partProblems(twoSites)
		t.truthy(#shortfall >= 4, `negative control: two sites, one property set each -> {#shortfall} shortfalls`)
		t.truthy(#(partProblems("CanCollide = true\n")) > 0, "negative control: no site at all is reported")
		t.truthy(
			#(partProblems(seatsRaw .. "\npart.CanCollide = true")) > 0,
			"negative control: a re-enable is reported"
		)

		-- real-source mutations, one per property, plus the twin
		t.deepEqual((partProblems(replaceOnce(seatsRaw, "part.CanQuery = false", "part.CanQuery = false"))), {}, "twin")
		for _, property in PART_PROPERTIES do
			local mutated = replaceOnce(seatsRaw, `part.{property}`, "part.Name = part.Name")
			t.truthy(#(partProblems(mutated)) > 0, `dropping {property} from CardSeatsView must turn the gate red`)
			local mutatedFlourish = replaceOnce(flourishRaw, `part.{property}`, "part.Name = part.Name")
			t.truthy(
				#(partProblems(mutatedFlourish)) > 0,
				`dropping {property} from CardFlourish must turn the gate red`
			)
		end
		-- A second part created outside the helper is what the count exists to catch.
		local extraSite = seatsRaw .. '\nlocal extra = Instance.new("Part")\nextra.Anchored = true'
		t.truthy(#(partProblems(extraSite)) > 0, "a second creation site with only one property set is red")
	end)

	t.test(
		"other seats are a stack height and nothing else: no text, no dealer marker, strictly monotone (CARD-13)",
		function()
			-- Raw text, comments included: no text object is named anywhere in the file.
			t.equal(countOf(string.lower(seatsRaw), "textlabel"), 0, "CardSeatsView names no TextLabel")
			t.equal(countOf(string.lower(seatsRaw), "textbutton"), 0, "CardSeatsView names no TextButton")
			t.equal(countOf(string.lower(seatsRaw), "surfacegui"), 0, "CardSeatsView names no SurfaceGui")
			local seats = lex.stripComments(seatsRaw)
			t.equal(countOf(string.lower(seats), "dealer"), 0, "no dealer marker in code")
			t.truthy(
				string.find(
					seats,
					"Card.SEAT_STACK_STUDS_PER_CARD * math.min(math.max(count, 0), Card.SEAT_STACK_CAP)",
					1,
					true
				) ~= nil,
				"the stack height is the configured expression"
			)
			-- The expression, evaluated: strictly increasing through the cap, flat after it.
			local function height(count: number): number
				return Card.SEAT_STACK_STUDS_PER_CARD * math.min(math.max(count, 0), Card.SEAT_STACK_CAP)
			end
			local steps = 0
			for n = 1, Card.SEAT_STACK_CAP do
				t.truthy(height(n) > height(n - 1), `height must rise from {n - 1} to {n}`)
				steps += 1
			end
			t.equal(height(Card.SEAT_STACK_CAP + 5), height(Card.SEAT_STACK_CAP), "flat past the cap")
			t.equal(steps, Card.SEAT_STACK_CAP, "non-vacuity: every step up to the cap was checked")
			-- The hop pool is the configured cap, and an over-cap hop returns without touching anything.
			t.truthy(countOf(seats, "Card.TABLE_HOP_CONCURRENT_CAP") == 1, "the pool is sized from the config cap")
			t.truthy(
				string.find(seats, "if free == nil then\n\t\t\t\treturn", 1, true) ~= nil,
				"over the cap a hop is skipped"
			)
			-- Negative control: a text object would be caught.
			t.equal(
				countOf(string.lower(seatsRaw .. '\nInstance.new("TextLabel")'), "textlabel"),
				1,
				"negative control"
			)
		end
	)

	t.test("callouts are built once, newest on top, evict rather than queue, and take no input", function()
		local callout = lex.stripComments(calloutRaw)
		t.truthy(string.find(callout, "Card.MAX_CALLOUTS", 1, true) ~= nil, "the cap is the config value")
		t.truthy(string.find(callout, "Hints.CALLOUTS", 1, true) ~= nil, "the words come from Hints")
		-- Every GuiObject this file creates goes through `plain`, which sets Active = false.
		local sites = countOf(callout, 'Instance.new("Frame")') + countOf(callout, 'Instance.new("TextLabel")')
		local plainCalls = countOf(callout, "plain(") - 1 -- minus the definition
		t.equal(sites, 3, "non-vacuity: three GuiObjects per banner")
		t.equal(plainCalls, sites, "every GuiObject is made inert")
		t.equal(countOf(callout, "Active = false"), 1, "plain sets Active = false")
		t.equal(countOf(callout, "Active = true"), 0, "nothing sets Active = true")
		-- Eviction, not a queue: the oldest is hidden and re-used, and there is no queue structure.
		t.truthy(string.find(callout, "local oldest = active[#active]", 1, true) ~= nil, "the oldest is evicted")
		t.equal(countOf(string.lower(callout), "queue"), 0, "no queue in code")
		t.truthy(string.find(callout, "table.insert(active, 1, banner)", 1, true) ~= nil, "newest goes on top")
		-- Only the self callout carries the accent underline.
		t.truthy(string.find(callout, "banner.underline.Visible = isSelf", 1, true) ~= nil, "underline only for self")
		t.equal(Card.MAX_CALLOUTS, 2, "two stacked callouts")
	end)

	t.test("the client feeds the stacks the server's depths and the hops the public Passed events", function()
		local client = lex.stripComments(clientRaw)
		t.truthy(string.find(client, "Depths = onDepths", 1, true) ~= nil, "Depths is dispatched")
		t.truthy(string.find(client, ".view:setDepths(list)", 1, true) ~= nil, "the stacks take the depth list")
		t.truthy(string.find(client, 'event.kind == "Passed"', 1, true) ~= nil, "hops are driven by Passed")
		t.truthy(string.find(client, "place.view:hop(event.seat, event.to)", 1, true) ~= nil, "a hop is seat to seat")
		-- Own sounds only: no audio call sits on the Passed path.
		t.equal(countOf(client, "audio:ownPass()"), 1, "own pass sound is in send only")
		t.equal(countOf(client, "audio:sting()"), 1, "the sting is played once per Completed event")
		-- The Deal kind is played for the local seat only.
		t.truthy(
			string.find(client, 'place.driver:play("Deal", r.localSeat, true, {})', 1, true) ~= nil,
			"Deal: local seat"
		)
	end)
end
