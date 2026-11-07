--!strict
-- UX-04 / D-09 / D-12 / D-35 / D-36 gate for src/shared/Card/Hints.
-- Mutations are injected broken COPIES of the audit input (the real tables are frozen), each asserted
-- red in the same case as a clean control.
local Card = require("../../src/shared/Config/Card")
local Faces = require("../../src/shared/Card/Faces")
local Hints = require("../../src/shared/Card/Hints")
local Layout = require("../../src/shared/Card/Layout")
local Test = require("../harness/Test")

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out: { [any]: any } = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

local function realInput(): Hints.AuditInput
	return {
		hint = deepCopy(Hints.HINT),
		states = Hints.STATES :: any,
		kinds = Hints.INPUT_KINDS :: any,
		messages = Hints.sampleMessages(Faces.JOKER_EXPLAINER),
		callouts = Hints.sampleCallouts(),
		maxChars = Card.STRIP_MAX_CHARS,
		calloutMaxChars = Card.CALLOUT_MAX_CHARS,
	}
end

local function hasProblem(problems: { string }, prefix: string): boolean
	for _, p in problems do
		if string.sub(p, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- Reference viewports, the same set as layout.spec (real device insets are M-12).
local VIEWPORTS: { { name: string, v: Layout.Viewport } } = {
	{
		name = "phone notched",
		v = { width = 844, height = 390, insets = { top = 0, bottom = 21, left = 47, right = 0 } },
	},
	{ name = "phone small", v = { width = 640, height = 360, insets = { top = 36, bottom = 0, left = 0, right = 0 } } },
	{
		name = "phone large",
		v = { width = 932, height = 430, insets = { top = 0, bottom = 21, left = 50, right = 0 } },
	},
	{ name = "desktop", v = { width = 1920, height = 1080, insets = { top = 36, bottom = 0, left = 0, right = 0 } } },
}

return function(t: Test.Runner)
	t.test("the hint table is complete and every string fits (clean control)", function()
		local problems, measured = Hints.audit(realInput())
		t.deepEqual(problems, {})
		print(`hints: audit measured {measured} strings`)
		t.truthy(measured >= 31, `non-vacuity: only {measured} strings measured`)
		t.equal(#Hints.STATES * #Hints.INPUT_KINDS, 20, "hint table is 5 x 4")
	end)

	t.test("every strip string is within STRIP_MAX_CHARS and within the solved strip width", function()
		local input = realInput()
		local strings: { string } = {}
		for _, state in Hints.STATES do
			for _, kind in Hints.INPUT_KINDS do
				table.insert(strings, (Hints.HINT :: any)[state][kind])
			end
		end
		for _, s in input.messages do
			table.insert(strings, s)
		end
		local worst = math.huge
		local longest = 0
		local longestS = ""
		local counted = 0
		for _, e in VIEWPORTS do
			local strip = Layout.solve(e.v, 5)
			for _, s in strings do
				t.truthy(#s <= Card.STRIP_MAX_CHARS, `{s} is {#s} chars`)
				local need = #s * Layout.DESIGN.CHAR_WIDTH_PROXY * strip.scale
				t.truthy(need <= strip.strip.w, `{s} needs {need} of {strip.strip.w} at {e.name}`)
				worst = math.min(worst, strip.strip.w / need)
				if #s > longest then
					longest = #s
					longestS = s
				end
				counted += 1
			end
		end
		print(`hints: worst-case strip headroom {worst}; longest {longest} chars: "{longestS}"; {counted} measurements`)
		t.truthy(worst >= 1.5, `worst headroom {worst}`)
		t.equal(counted, #strings * #VIEWPORTS, "non-vacuity: measurements")
		t.truthy(counted >= 4 * 31, "non-vacuity: enough strings")
	end)

	t.test(
		"MUTATION: a deleted cell, an over-long string, an exclamation mark and error copy each turn the audit red",
		function()
			local mutations = 0
			local function run(prefix: string, mutate: (i: Hints.AuditInput) -> ())
				local clean = Hints.audit(realInput())
				t.deepEqual(clean, {}, "clean control must be green")
				local broken = realInput()
				mutate(broken)
				local problems = Hints.audit(broken)
				print(`hints: mutation {prefix} -> {table.concat(problems, " | ")}`)
				t.truthy(hasProblem(problems, prefix), `expected {prefix}, got {table.concat(problems, " | ")}`)
				mutations += 1
			end
			run("missing cell:", function(i)
				i.hint.Selected.Gamepad = nil
			end)
			run("too long:", function(i)
				i.messages.waiting = string.rep("a", 40)
			end)
			run("stray exclamation:", function(i)
				i.messages.waiting = "Waiting for cards!"
			end)
			run("forbidden error copy:", function(i)
				i.messages.waiting = "Pass rejected"
			end)
			t.equal(mutations, 4)
		end
	)

	t.test("kindOf maps every pointer, key and pad type and ignores the rest", function()
		local cases: { { name: string, kind: string? } } = {
			{ name = "Touch", kind = "Touch" },
			{ name = "MouseButton1", kind = "Mouse" },
			{ name = "MouseButton2", kind = "Mouse" },
			{ name = "MouseButton3", kind = "Mouse" },
			{ name = "MouseWheel", kind = "Mouse" },
			{ name = "MouseMovement", kind = "Mouse" },
			{ name = "Keyboard", kind = "Keyboard" },
		}
		for i = 1, 8 do
			table.insert(cases, { name = `Gamepad{i}`, kind = "Gamepad" })
		end
		for _, name in { "Focus", "Accelerometer", "Gyro", "TextInput", "InputMethod", "None", "banana" } do
			table.insert(cases, { name = name, kind = nil })
		end
		local distinct: { [string]: boolean } = {}
		for _, c in cases do
			local got = Hints.kindOf(c.name)
			t.equal(got, c.kind, `kindOf({c.name})`)
			if got ~= nil then
				distinct[got] = true
			end
		end
		print(`hints: kindOf cases {#cases}`)
		t.truthy(#cases >= 22, `non-vacuity: {#cases} cases`)
		local n = 0
		for _ in distinct do
			n += 1
		end
		t.truthy(n >= 4, `negative control: only {n} distinct non-nil kinds`)
	end)

	t.test("the countdown and strike builders interpolate correctly and stay inside the cap", function()
		local generated = 0
		local owesList: { any } = { "Pass", "Draw" }
		for _, owes in owesList do
			for s = 0, 2 do
				local m = Hints.MESSAGES.countdown(owes, s)
				t.truthy(#m <= Card.STRIP_MAX_CHARS, m)
				t.equal(m, `{owes} a card: {s}`)
				generated += 1
			end
			for k = 1, 3 do
				local m = Hints.MESSAGES.strike(k, owes)
				t.truthy(#m <= Card.STRIP_MAX_CHARS, m)
				generated += 1
			end
		end
		t.falsy(string.find(Hints.MESSAGES.strike(1, "Draw"), "passed", 1, true), "D-35: hand 4 moved nothing")
		t.equal(Hints.MESSAGES.strike(2, "Pass"), Hints.MESSAGES.strike(2, "Draw"))
		t.equal(generated, 12, "non-vacuity: strings generated")
	end)

	t.test("the other-player callout truncates a long display name and stays within CALLOUT_MAX_CHARS", function()
		local long = Hints.CALLOUTS.other(string.rep("n", 30))
		t.truthy(#long <= Card.CALLOUT_MAX_CHARS, `{#long} chars`)
		t.equal(long, string.rep("n", Hints.NAME_BUDGET) .. " is out! Find a spoon!")
		t.equal(Hints.CALLOUTS.other("Bob"), "Bob is out! Find a spoon!")
	end)

	t.test("STATES, INPUT_KINDS and HINT are frozen", function()
		t.truthy(table.isfrozen(Hints.STATES) and table.isfrozen(Hints.INPUT_KINDS) and table.isfrozen(Hints.HINT))
		for name, tbl in { STATES = Hints.STATES, INPUT_KINDS = Hints.INPUT_KINDS } :: { [string]: any } do
			local before = #tbl
			t.throws(function()
				table.insert(tbl, "x")
			end)
			t.equal(#tbl, before, name)
		end
		t.truthy(table.isfrozen((Hints.HINT :: any).Selected), "rows frozen")
	end)
end
