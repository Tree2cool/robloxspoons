--!strict
-- FOUND-04 + D-20. The manifest is the only list of things a client may ask the server to do, and its
-- `phases` field is the only place a round-phase name is ever written down per intent. A Luau type does
-- not exist at runtime, so this spec is what actually stops a later phase inventing a competing name.
-- Every rejection asserts the exact code, never a bare failure.
local Manifest = require("../../src/shared/Net/Manifest")
local Test = require("../harness/Test")
local Validate = require("../../src/shared/Net/Validate")

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

-- Rule 7, written once as data. `base` is a COMPLETE valid payload, so each case adds exactly one
-- defect: exactKeys reports MissingKey before UnknownKey, and a case that omitted a required key
-- while adding a forbidden one would assert the wrong code and prove nothing about rule 7.
local FORBIDDEN_KEYS = { "seat", "to", "target", "index", "hand", "slot", "userId" }
local BASES: { [string]: { [string]: any } } = {
	Draw = { seq = 1 },
	Pass = { seq = 1, cardId = 7 },
}

local function realValidators(): { [string]: Validate.Validator }
	return { Draw = Manifest.intents.Draw.validate, Pass = Manifest.intents.Pass.validate }
end

-- The forbidden-key checker. It takes its validators as a PARAMETER so a mutation is an injected broken
-- dependency, not a source edit. Returns how many cases ran and a sorted list of failures.
local function forbiddenKeyRun(validators: { [string]: Validate.Validator }): (number, { string })
	local seen = 0
	local failures: { string } = {}
	local names = { "Draw", "Pass" }
	for _, name in names do
		for _, key in FORBIDDEN_KEYS do
			local payload = table.clone(BASES[name])
			payload[key] = 1
			local ok, code = validators[name](payload)
			seen += 1
			if ok or code ~= "UnknownKey" then
				table.insert(failures, `{name}/{key}: expected UnknownKey, got {if ok then "true" else tostring(code)}`)
			end
		end
	end
	return seen, failures
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

	t.test("Draw and Pass accept their exact payload and return a clean copy", function()
		-- The clean control every hostile case below needs beside it.
		local seen = 0
		for name, base in BASES do
			local ok, clean = Manifest.intents[name].validate(base)
			t.equal(ok, true, `{name}: the exact payload must be accepted`)
			t.deepEqual(clean, base, `{name}: clean copy`)
			t.truthy(clean ~= base, `{name}: the result must be a copy, not the caller's table`)
			seen += 1
		end
		t.equal(seen, 2, "expected to drive exactly Draw and Pass")
	end)

	t.test("rule 7: no card intent accepts a seat, a pass target or a hand index", function()
		local seen, failures = forbiddenKeyRun(realValidators())
		t.equal(seen, 14, "2 intents x 7 forbidden keys must all have run")
		t.deepEqual(failures, {}, "a forbidden key was not rejected as UnknownKey")
		print(`rule 7 gate: {seen} cases ran, {#failures} failures`)
	end)

	t.test("rule 7 MUTATION: the gate goes red when the schema is loosened or the checker is blind", function()
		-- Mutations are injected as a broken dependency, never by editing the source. Each one is run
		-- through the SAME checker the real schemas pass through.

		-- exactKeys has no optional keys, so "loosening" cannot be expressed by adding a required field
		-- (that would fail the other cases with MissingKey). The faithful mutation is a validator that
		-- TOLERATES a key: it drops the key, then runs the real schema.
		local function tolerating(real: Validate.Validator, tolerated: { string }): Validate.Validator
			return function(value: unknown): (boolean, unknown)
				if type(value) ~= "table" then
					return real(value)
				end
				local copy = table.clone(value :: { [string]: unknown })
				for _, key in tolerated do
					copy[key] = nil
				end
				return real(copy)
			end
		end

		-- (a) Draw tolerates `seat`: exactly the one (Draw, seat) case must fail.
		local looseDraw = realValidators()
		looseDraw.Draw = tolerating(Manifest.intents.Draw.validate, { "seat" })
		local seenA, failuresA = forbiddenKeyRun(looseDraw)
		t.equal(seenA, 14, "mutation (a): all 14 cases must still run")
		t.deepEqual(failuresA, { "Draw/seat: expected UnknownKey, got true" })

		-- (b) Pass tolerates `index` and `target`: exactly those two cases fail.
		local loosePass = realValidators()
		loosePass.Pass = tolerating(Manifest.intents.Pass.validate, { "index", "target" })
		local seenB, failuresB = forbiddenKeyRun(loosePass)
		t.equal(seenB, 14, "mutation (b): all 14 cases must still run")
		t.deepEqual(failuresB, {
			"Pass/target: expected UnknownKey, got true",
			"Pass/index: expected UnknownKey, got true",
		})

		-- (c) A permissive validator that accepts anything: all 14 fail.
		local acceptAll: Validate.Validator = function(value: unknown): (boolean, unknown)
			return true, value
		end
		local seenC, failuresC = forbiddenKeyRun({ Draw = acceptAll, Pass = acceptAll })
		t.equal(seenC, 14, "mutation (c): all 14 cases must still run")
		t.equal(#failuresC, 14, "an accept-everything validator must fail every case")

		-- (d) A validator that rejects everything for the WRONG reason must not pass the gate either:
		-- it would if the checker only looked at `ok`.
		local rejectAll: Validate.Validator = function(_value: unknown): (boolean, unknown)
			return false, "MissingKey"
		end
		local seenD, failuresD = forbiddenKeyRun({ Draw = rejectAll, Pass = rejectAll })
		t.equal(seenD, 14, "mutation (d): all 14 cases must still run")
		t.equal(#failuresD, 14, "a wrong-code rejection must fail every case")
		print(`rule 7 mutations: (a) {#failuresA} (b) {#failuresB} (c) {#failuresC} (d) {#failuresD} red`)
	end)

	t.test("negative control: the forbidden-key checker can tell a tight schema from a loose one", function()
		local loose = Validate.exactKeys({
			seq = Validate.integer({ min = 0, max = 2 ^ 31 }),
			seat = Validate.integer({ min = 0, max = 4 }),
		})
		local looseOk = loose({ seq = 1, seat = 1 })
		t.equal(looseOk, true, "the loose schema must ACCEPT seat, or this control proves nothing")
		local tightOk, tightCode = Manifest.intents.Draw.validate({ seq = 1, seat = 1 })
		t.equal(tightOk, false, "the real Draw schema must reject seat")
		t.equal(tightCode, "UnknownKey")
	end)

	t.test("Draw and Pass reject NaN, infinity and a non-number seq", function()
		-- Establish what the field validator itself reports, then require the manifest to agree.
		local seqValidator = Validate.integer({ min = 0, max = 2 ^ 31 })
		local cases: { { label: string, seq: unknown, code: string } } = {
			{ label = "NaN", seq = NAN, code = "NotFinite" },
			{ label = "+inf", seq = INF, code = "NotFinite" },
			{ label = "-inf", seq = -INF, code = "NotFinite" },
			{ label = "string", seq = "1", code = "WrongType" },
			{ label = "fraction", seq = 1.5, code = "NotInteger" },
			{ label = "negative", seq = -1, code = "OutOfRange" },
		}
		local seen = 0
		for _, c in cases do
			local fieldOk, fieldCode = seqValidator(c.seq)
			t.equal(fieldOk, false, `{c.label}: Validate.integer must reject`)
			t.equal(fieldCode, c.code, `{c.label}: Validate.integer code`)
			for name, base in BASES do
				local payload = table.clone(base)
				payload.seq = c.seq
				local ok, code = Manifest.intents[name].validate(payload)
				t.equal(ok, false, `{name} {c.label}: should be rejected`)
				t.equal(code, c.code, `{name} {c.label}: wrong rejection code`)
				seen += 1
			end
		end
		t.equal(seen, 12, "6 defects x 2 intents must all have run")
	end)

	t.test("Pass rejects a cardId outside the sanity bound, and 49 is inside it", function()
		-- The 64 bound is a SANITY CAP, not a game rule. The real rule is the engine's UnknownCard /
		-- NotYourCard (plan 04-12); a cardId inside the cap that is not yours is still rejected there.
		local validate = Manifest.intents.Pass.validate
		local cases: { { cardId: number, ok: boolean, code: string? } } = {
			{ cardId = 0, ok = false, code = "OutOfRange" },
			{ cardId = 65, ok = false, code = "OutOfRange" },
			{ cardId = 49, ok = true },
			{ cardId = 1, ok = true },
			{ cardId = 64, ok = true },
		}
		for _, c in cases do
			local ok, result = validate({ seq = 1, cardId = c.cardId })
			t.equal(ok, c.ok, `cardId {c.cardId}`)
			if not c.ok then
				t.equal(result, c.code, `cardId {c.cardId}: code`)
			end
		end
		local nanOk, nanCode = validate({ seq = 1, cardId = NAN })
		t.equal(nanOk, false)
		t.equal(nanCode, "NotFinite")
	end)

	t.test("Draw and Pass reject a missing key, an extra key, a non-table and a forbidden type", function()
		local seen = 0
		for name, base in BASES do
			local validate = Manifest.intents[name].validate
			local extra = table.clone(base)
			extra.extra = 1
			local cases: { { label: string, payload: unknown, code: string } } = {
				{ label = "empty table", payload = {}, code = "MissingKey" },
				{ label = "extra key", payload = extra, code = "UnknownKey" },
				{ label = "string", payload = "nope", code = "NotTable" },
				{ label = "function", payload = print, code = "ForbiddenType" },
				{ label = "nil", payload = nil, code = "NotTable" },
			}
			for _, c in cases do
				local ok, code = validate(c.payload)
				t.equal(ok, false, `{name} {c.label}: should be rejected`)
				t.equal(code, c.code, `{name} {c.label}: wrong rejection code`)
				seen += 1
			end
		end
		t.equal(seen, 10, "5 defects x 2 intents must all have run")
	end)

	t.test("both card intents are Round-only", function()
		-- The gateway's phase gate runs BEFORE the token bucket (D-22, reviewed and kept in plan
		-- 04-07), so a wrong-phase card message costs no token. That is why plan 04-07 throttles the
		-- reject LOG instead of reordering the gate.
		for _, name in { "Draw", "Pass" } do
			local phases = Manifest.intents[name].phases
			t.deepEqual(phases, { "Round" }, `{name} must be Round-only`)
			for _, banned in { "Lobby", "Hide", "Podium" } do
				t.truthy(table.find(phases, banned :: any) == nil, `{name} must not allow {banned}`)
			end
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
