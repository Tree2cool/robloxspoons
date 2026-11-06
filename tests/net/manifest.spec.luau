--!strict
-- FOUND-04 + D-20. The manifest is the only list of things a client may ask the server to do, and its
-- `phases` field is the only place a round-phase name is ever written down per intent. A Luau type does
-- not exist at runtime, so this spec is what actually stops a later phase inventing a competing name.
-- Every rejection asserts the exact code, never a bare failure.
local Manifest = require("../../src/shared/Net/Manifest")
local Test = require("../harness/Test")

local NAN: number = 0 / 0
local INF: number = math.huge

-- The subset rule, written once. Returns a description of every way `phases` is not acceptable, empty
-- when it is acceptable. The negative cases below drive this same function with bad input, so the rule
-- is proven to catch what it claims to catch rather than merely to pass the real manifest.
-- (`{ any }` because Luau arrays are invariant: a { RoundPhase } is not a { string }, and a bad name is
-- exactly the input this must accept in order to reject it.)
local function phaseProblems(phases: { any }): { string }
	local problems: { string } = {}
	if #phases == 0 then
		table.insert(problems, "empty")
	end
	local valid: { [string]: boolean } = {}
	for _, name in Manifest.PHASES do
		valid[name] = true
	end
	for _, name in phases do
		if not valid[name] then
			table.insert(problems, `unknown phase: {name}`)
		end
	end
	return problems
end

return function(t: Test.Runner)
	t.test("PHASES is exactly Lobby, Hide, Round, Podium (D-20), in order, as a runtime constant", function()
		t.equal(#Manifest.PHASES, 4, "must be exactly 4 phases")
		t.deepEqual(Manifest.PHASES, { "Lobby", "Hide", "Round", "Podium" })
		t.equal(Manifest.PHASES[1], "Lobby")
		t.equal(Manifest.PHASES[2], "Hide")
		t.equal(Manifest.PHASES[3], "Round")
		t.equal(Manifest.PHASES[4], "Podium")
	end)

	t.test("PHASES is frozen so no module can append a competing name at runtime", function()
		t.truthy(table.isfrozen(Manifest.PHASES), "PHASES must be frozen")
		t.throws(function()
			table.insert(Manifest.PHASES :: any, "Scramble")
		end)
		t.equal(#Manifest.PHASES, 4, "an insert attempt must not have changed PHASES")
	end)

	t.test("every intent's phases list is non-empty and a subset of PHASES", function()
		local seen = 0
		for name, intent in Manifest.intents do
			seen += 1
			t.deepEqual(phaseProblems(intent.phases), {}, `intent {name} declares an unacceptable phase list`)
		end
		t.truthy(seen > 0, "the subset check ran over zero intents, which proves nothing")
	end)

	t.test("the subset rule catches a rejected or invented phase name (negative control)", function()
		-- "Scramble" is the name the planner originally proposed and the owner rejected in D-20.
		t.deepEqual(phaseProblems({ "Scramble" }), { "unknown phase: Scramble" })
		t.deepEqual(phaseProblems({ "Round", "Play" }), { "unknown phase: Play" })
		t.deepEqual(phaseProblems({ "Hunt" }), { "unknown phase: Hunt" })
		-- Case matters: these are strings, and a near-miss is still a different name.
		t.deepEqual(phaseProblems({ "round" }), { "unknown phase: round" })
		t.deepEqual(phaseProblems({ "Lobby", "Scramble", "Podium", "Cards" }), {
			"unknown phase: Scramble",
			"unknown phase: Cards",
		})
		-- An intent that is allowed in no phase is a bug too.
		t.deepEqual(phaseProblems({}), { "empty" })
		-- And a clean list reports nothing, so the rule is not simply rejecting everything.
		t.deepEqual(phaseProblems({ "Lobby", "Hide", "Round", "Podium" }), {})
		t.deepEqual(phaseProblems({ "Round" }), {})
	end)

	t.test("Manifest.intents has exactly Ping, Draw and Pass (Phase 4 added the two card intents)", function()
		local keys: { string } = {}
		for name in Manifest.intents do
			table.insert(keys, name)
		end
		table.sort(keys)
		t.deepEqual(keys, { "Draw", "Pass", "Ping" })
	end)

	t.test("every intent has a callable validate", function()
		for name, intent in Manifest.intents do
			t.equal(type(intent.validate), "function", `intent {name}.validate`)
		end
	end)

	t.test("Ping is allowed in every phase", function()
		t.deepEqual(Manifest.intents.Ping.phases, { "Lobby", "Hide", "Round", "Podium" })
	end)

	t.test("Ping accepts a finite integer nonce and returns it", function()
		local validate = Manifest.intents.Ping.validate
		local ok, clean = validate({ nonce = 0 })
		t.equal(ok, true, "nonce 0")
		t.deepEqual(clean, { nonce = 0 })
		local ok2, clean2 = validate({ nonce = 12345 })
		t.equal(ok2, true, "nonce 12345")
		t.deepEqual(clean2, { nonce = 12345 })
		t.equal((validate({ nonce = 2 ^ 31 })), true, "upper bound is inclusive")
	end)

	t.test("Ping: {} is MissingKey", function()
		local ok, code = Manifest.intents.Ping.validate({})
		t.equal(ok, false)
		t.equal(code, "MissingKey")
	end)

	t.test("Ping: a NaN nonce reaches the finite check and is NotFinite, not UnknownKey or OutOfRange", function()
		-- This is the whole reason Ping has a nonce: manual check M-03 fires exactly this payload at the
		-- live server, and it must reach `isFinite` rather than bounce off the envelope.
		local ok, code = Manifest.intents.Ping.validate({ nonce = NAN })
		t.equal(ok, false)
		t.equal(code, "NotFinite")
		local ok2, code2 = Manifest.intents.Ping.validate({ nonce = INF })
		t.equal(ok2, false)
		t.equal(code2, "NotFinite")
		local ok3, code3 = Manifest.intents.Ping.validate({ nonce = -INF })
		t.equal(ok3, false)
		t.equal(code3, "NotFinite")
	end)

	t.test("Ping: an extra key is UnknownKey", function()
		local ok, code = Manifest.intents.Ping.validate({ nonce = 0, x = 1 })
		t.equal(ok, false)
		t.equal(code, "UnknownKey")
	end)

	t.test("Ping: other bad nonces are rejected with their own distinct codes", function()
		local validate = Manifest.intents.Ping.validate
		local cases: { { label: string, payload: unknown, code: string } } = {
			{ label = "fraction", payload = { nonce = 1.5 }, code = "NotInteger" },
			{ label = "negative", payload = { nonce = -1 }, code = "OutOfRange" },
			{ label = "above max", payload = { nonce = 2 ^ 31 + 1 }, code = "OutOfRange" },
			{ label = "string nonce", payload = { nonce = "7" }, code = "WrongType" },
			{ label = "nil payload", payload = nil, code = "NotTable" },
			{ label = "number payload", payload = 7, code = "NotTable" },
			{ label = "function nonce", payload = { nonce = function() end }, code = "ForbiddenType" },
		}
		for _, c in cases do
			local ok, code = validate(c.payload)
			t.equal(ok, false, `{c.label}: should be rejected`)
			t.equal(code, c.code, `{c.label}: wrong rejection code`)
		end
	end)

	t.test("isKnown is true for Ping and false for everything else", function()
		t.equal(Manifest.isKnown("Ping"), true)
		t.equal(Manifest.isKnown("Nope"), false)
		t.equal(Manifest.isKnown(""), false)
		t.equal(Manifest.isKnown(42), false)
		t.equal(Manifest.isKnown(nil), false)
		t.equal(Manifest.isKnown(true), false)
		t.equal(Manifest.isKnown({}), false)
		t.equal(Manifest.isKnown(NAN), false)
		t.equal(Manifest.isKnown(string.rep("x", 200)), false)
		t.equal(Manifest.isKnown("ping"), false, "names are case-sensitive")
		t.equal(Manifest.isKnown("Ping "), false, "no trimming")
	end)

	t.test("MAX_NAME_LENGTH is 64 and a name past it is not known", function()
		t.equal(Manifest.MAX_NAME_LENGTH, 64)
		t.equal(Manifest.isKnown(string.rep("a", 64)), false)
		t.equal(Manifest.isKnown(string.rep("a", 65)), false)
	end)

	t.test("isKnown rejects by type and length BEFORE any lookup in intents", function()
		-- Count real table lookups by installing an __index on the intents table for the duration of this
		-- case. Garbage names must cost zero lookups; a plausible unknown name must cost one.
		local lookups = 0
		local intents = Manifest.intents
		setmetatable(intents :: any, {
			__index = function(_, _key)
				lookups += 1
				return nil
			end,
		})
		local ok, err = pcall(function()
			Manifest.isKnown(nil)
			Manifest.isKnown(42)
			Manifest.isKnown({})
			Manifest.isKnown(true)
			Manifest.isKnown("")
			Manifest.isKnown(string.rep("x", 65))
			Manifest.isKnown(string.rep("x", 200))
			t.equal(lookups, 0, "garbage names must not touch the intents table")
			Manifest.isKnown("Nope")
			t.equal(lookups, 1, "a plausible unknown name should cost exactly one lookup")
			t.equal(Manifest.isKnown("Ping"), true, "a known name is still found")
		end)
		setmetatable(intents :: any, nil)
		if not ok then
			error(err, 0)
		end
	end)
end
