--!strict
-- FOUND-04 / threats T-1-01, T-1-25, T-1-26. Every rejection case asserts the EXACT code, never just
-- "it was rejected": a validator that rejected everything would otherwise pass this whole file.
local Test = require("../harness/Test")
local Validate = require("../../src/shared/Net/Validate")

local NAN: number = 0 / 0
local INF: number = math.huge
local NEG_INF: number = -math.huge

local function nested(depth: number): { [string]: any }
	-- depth 1 is `{}`; depth n is a table whose only value is a depth n-1 table.
	local root: { [string]: any } = {}
	local cursor = root
	for _ = 2, depth do
		local child: { [string]: any } = {}
		cursor.a = child
		cursor = child
	end
	return root
end

local function flat(count: number): { [string]: any }
	local out: { [string]: any } = {}
	for i = 1, count do
		out[`k{i}`] = i
	end
	return out
end

local function schemaOfKeys(count: number): { [string]: Validate.Validator }
	local out: { [string]: Validate.Validator } = {}
	for i = 1, count do
		out[`k{i}`] = Validate.integer({})
	end
	return out
end

type Vector = {
	label: string,
	validator: Validate.Validator,
	value: unknown,
	ok: boolean,
	-- when ok == false this is the required rejection code; when ok == true it is unused
	code: string?,
}

return function(t: Test.Runner)
	local function expectReject(validator: Validate.Validator, value: unknown, code: string, label: string)
		local ok, result = validator(value)
		t.equal(ok, false, `{label}: should be rejected`)
		t.equal(result, code, `{label}: wrong rejection code`)
	end

	local function expectAccept(validator: Validate.Validator, value: unknown, label: string): unknown
		local ok, result = validator(value)
		t.equal(ok, true, `{label}: should be accepted (got code {tostring(result)})`)
		return result
	end

	t.test("isFinite is true for ordinary and very large finite numbers", function()
		for _, v in { 0, -1.5, 1.5, 2 ^ 53, -(2 ^ 53), 1e308, -1e308 } do
			t.equal(Validate.isFinite(v), true, `isFinite({v})`)
		end
	end)

	t.test("isFinite is false for NaN, +inf and -inf", function()
		t.equal(Validate.isFinite(NAN), false, "NaN")
		t.equal(Validate.isFinite(INF), false, "+inf")
		t.equal(Validate.isFinite(NEG_INF), false, "-inf")
	end)

	t.test("isFinite is false for every non-number because the type check runs first", function()
		t.equal(Validate.isFinite("1"), false, "string")
		t.equal(Validate.isFinite(nil), false, "nil")
		t.equal(Validate.isFinite({}), false, "table")
		t.equal(Validate.isFinite(true), false, "boolean")
		t.equal(Validate.isFinite(function() end), false, "function")
	end)

	t.test("number: NaN is NotFinite and never OutOfRange, even with a range that would 'pass' it", function()
		-- NaN fails every comparison, so `value < min or value > max` lets it through. The required code
		-- NotFinite proves the finite check ran BEFORE any range comparison.
		expectReject(Validate.number({ min = 0, max = 10 }), NAN, "NotFinite", "NaN in [0,10]")
		expectReject(Validate.number({ min = -5, max = 5 }), NAN, "NotFinite", "NaN in [-5,5]")
		expectReject(Validate.number({}), NAN, "NotFinite", "NaN, no range")
	end)

	t.test("number: +inf and -inf are NotFinite, not OutOfRange", function()
		-- inf would fail a range check with OutOfRange; the required code NotFinite proves ordering.
		expectReject(Validate.number({ min = 0, max = 10 }), INF, "NotFinite", "+inf")
		expectReject(Validate.number({ min = 0, max = 10 }), NEG_INF, "NotFinite", "-inf")
		expectReject(Validate.number({}), INF, "NotFinite", "+inf no range")
		expectReject(Validate.number({}), NEG_INF, "NotFinite", "-inf no range")
	end)

	t.test("number: range is inclusive and out-of-range is OutOfRange", function()
		local v = Validate.number({ min = 0, max = 10 })
		t.equal(expectAccept(v, 0, "lower bound"), 0)
		t.equal(expectAccept(v, 10, "upper bound"), 10)
		t.equal(expectAccept(v, 5.5, "fraction is fine for number"), 5.5)
		expectReject(v, -0.001, "OutOfRange", "just below")
		expectReject(v, 10.001, "OutOfRange", "just above")
		expectReject(v, 1e308, "OutOfRange", "huge but finite")
		t.equal(expectAccept(Validate.number({}), 1e308, "no range accepts huge finite"), 1e308)
	end)

	t.test("number: wrong types are WrongType", function()
		local v = Validate.number({ min = 0, max = 10 })
		expectReject(v, "5", "WrongType", "numeric string")
		expectReject(v, nil, "WrongType", "nil")
		expectReject(v, true, "WrongType", "boolean")
		expectReject(v, {}, "WrongType", "table")
	end)

	t.test("integer: a fraction is NotInteger and is never truncated", function()
		local v = Validate.integer({ min = 0, max = 10 })
		expectReject(v, 1.5, "NotInteger", "1.5")
		expectReject(v, -1.5, "NotInteger", "-1.5")
		expectReject(v, 0.0000001, "NotInteger", "tiny fraction")
		-- integer check precedes range: an out-of-range fraction reports the integer problem.
		expectReject(v, 11.5, "NotInteger", "out-of-range fraction")
	end)

	t.test("integer: NaN, +inf, -inf are NotFinite (the finite check precedes the integer check)", function()
		-- inf % 1 is NaN and NaN % 1 == 0 is false, so a validator that skipped the finite check would
		-- report NotInteger. Requiring NotFinite proves ordering.
		local v = Validate.integer({ min = 0, max = 10 })
		expectReject(v, NAN, "NotFinite", "NaN")
		expectReject(v, INF, "NotFinite", "+inf")
		expectReject(v, NEG_INF, "NotFinite", "-inf")
		expectReject(Validate.integer({}), NAN, "NotFinite", "NaN no range")
		expectReject(Validate.integer({}), INF, "NotFinite", "+inf no range")
	end)

	t.test("integer: 1e308 is finite and 'whole' but outside the exact-integer range, so NotInteger", function()
		-- 1e308 % 1 == 0, so a bare modulo test accepts it. It must be rejected with or without a range.
		expectReject(Validate.integer({ min = 0, max = 10 }), 1e308, "NotInteger", "1e308 with range")
		expectReject(Validate.integer({}), 1e308, "NotInteger", "1e308 without range")
		expectReject(Validate.integer({}), -1e308, "NotInteger", "-1e308 without range")
		expectReject(Validate.integer({}), 2 ^ 53 + 2, "NotInteger", "first non-exact even integer")
		t.equal(expectAccept(Validate.integer({}), 2 ^ 53, "2^53 is still exact"), 2 ^ 53)
	end)

	t.test("integer: accepts whole numbers in range, rejects out of range with OutOfRange", function()
		local v = Validate.integer({ min = 0, max = 10 })
		t.equal(expectAccept(v, 0, "lower"), 0)
		t.equal(expectAccept(v, 10, "upper"), 10)
		t.equal(expectAccept(v, 7, "inside"), 7)
		expectReject(v, -1, "OutOfRange", "below")
		expectReject(v, 11, "OutOfRange", "above")
		expectReject(v, "7", "WrongType", "string")
		expectReject(v, nil, "WrongType", "nil")
	end)

	t.test("string: length cap yields TooLong and the boundary is inclusive", function()
		local v = Validate.string({ maxLen = 8 })
		t.equal(expectAccept(v, "ok", "short"), "ok")
		t.equal(expectAccept(v, "12345678", "exactly maxLen"), "12345678")
		t.equal(expectAccept(v, "", "empty"), "")
		expectReject(v, "123456789", "TooLong", "9 chars")
		expectReject(v, string.rep("x", 1000), "TooLong", "1000 chars")
		expectReject(v, 5, "WrongType", "number")
		expectReject(v, nil, "WrongType", "nil")
		expectReject(v, {}, "WrongType", "table")
	end)

	t.test("literal: accepts only the exact value, with distinct codes for type and value", function()
		local v = Validate.literal("Ping")
		t.equal(expectAccept(v, "Ping", "match"), "Ping")
		expectReject(v, "Pong", "NotLiteral", "same type different value")
		expectReject(v, 1, "WrongType", "different type")
		expectReject(v, nil, "WrongType", "nil")
		expectReject(Validate.literal(3), NAN, "NotFinite", "NaN against a numeric literal")
	end)

	t.test("exactKeys: accepts the exact shape and returns a clean copy", function()
		local v = Validate.exactKeys({ nonce = Validate.integer({ min = 0, max = 100 }) })
		local input = { nonce = 5 }
		local clean = expectAccept(v, input, "exact shape")
		t.deepEqual(clean, { nonce = 5 })
		t.truthy(clean ~= input, "must return a fresh table, not the caller's")
	end)

	t.test("exactKeys: a missing key is MissingKey, an extra key is UnknownKey, in both directions", function()
		local v = Validate.exactKeys({ a = Validate.integer({}), b = Validate.integer({}) })
		expectReject(v, {}, "MissingKey", "empty")
		expectReject(v, { a = 1 }, "MissingKey", "b missing")
		expectReject(v, { b = 1 }, "MissingKey", "a missing")
		expectReject(v, { a = 1, b = 2, extra = 3 }, "UnknownKey", "one extra")
		expectReject(v, { a = 1, b = 2, [1] = 9 }, "UnknownKey", "numeric extra key")
		-- Unknown AND missing in the same message: the documented order reports the missing key first.
		expectReject(v, { a = 1, zzz = 1 }, "MissingKey", "missing wins over unknown")
	end)

	t.test("exactKeys: a non-table is NotTable", function()
		local v = Validate.exactKeys({})
		expectReject(v, "x", "NotTable", "string")
		expectReject(v, 5, "NotTable", "number")
		expectReject(v, nil, "NotTable", "nil")
		expectReject(v, true, "NotTable", "boolean")
		expectReject(v, NAN, "NotTable", "NaN as a whole payload")
		t.equal(expectAccept(v, {}, "empty schema accepts empty table") ~= nil, true)
	end)

	t.test("exactKeys: a field failure surfaces the field's own code", function()
		local v = Validate.exactKeys({ nonce = Validate.integer({ min = 0, max = 100 }) })
		expectReject(v, { nonce = NAN }, "NotFinite", "NaN field")
		expectReject(v, { nonce = INF }, "NotFinite", "inf field")
		expectReject(v, { nonce = 1.5 }, "NotInteger", "fractional field")
		expectReject(v, { nonce = 101 }, "OutOfRange", "out of range field")
		expectReject(v, { nonce = "1" }, "WrongType", "string field")
	end)

	t.test("exactKeys: nesting beyond maxDepth (default 4) is TooDeep", function()
		-- Depth is counted on the value, so these are rejected before the schema is consulted: an
		-- over-deep message costs bounded CPU and never reaches UnknownKey.
		local v = Validate.exactKeys({})
		expectReject(v, nested(6), "TooDeep", "6 deep")
		expectReject(v, nested(5), "TooDeep", "5 deep")
		local cyclic: { [string]: any } = {}
		cyclic.self = cyclic
		expectReject(v, cyclic, "TooDeep", "cycle must terminate")
	end)

	t.test("exactKeys: nesting exactly at maxDepth is allowed and maxDepth is configurable", function()
		local fourDeep = Validate.exactKeys({
			a = Validate.exactKeys({
				a = Validate.exactKeys({
					a = Validate.exactKeys({}),
				}),
			}),
		})
		expectAccept(fourDeep, nested(4), "4 deep")
		expectReject(Validate.exactKeys({}, { maxDepth = 2 }), nested(3), "TooDeep", "custom maxDepth 2")
		expectAccept(Validate.exactKeys({ a = Validate.exactKeys({}) }, { maxDepth = 2 }), nested(2), "2 deep, max 2")
	end)

	t.test("exactKeys: more than maxEntries (default 32) is TooLarge, counted across nesting", function()
		expectReject(Validate.exactKeys({}), flat(64), "TooLarge", "64 entries, empty schema")
		expectReject(Validate.exactKeys(schemaOfKeys(33)), flat(33), "TooLarge", "33 entries")
		expectAccept(Validate.exactKeys(schemaOfKeys(32)), flat(32), "exactly 32")
		-- 3 + 3 + 3 = 9 total entries: over a limit of 8 only if the count spans the nesting.
		local spread: { [string]: any } = { x = flat(3), y = flat(3), z = flat(3) }
		expectReject(Validate.exactKeys({}, { maxEntries = 8 }), spread, "TooLarge", "entries counted across nesting")
	end)

	t.test("ForbiddenType: values outside nil/boolean/number/string/table are rejected as such", function()
		local forbidden: { [string]: unknown } = {
			["function"] = function() end,
			thread = coroutine.create(function() end),
			buffer = buffer.create(4),
		}
		for label, value in forbidden do
			expectReject(Validate.number({}), value, "ForbiddenType", `number <- {label}`)
			expectReject(Validate.integer({}), value, "ForbiddenType", `integer <- {label}`)
			expectReject(Validate.string({ maxLen = 4 }), value, "ForbiddenType", `string <- {label}`)
			expectReject(Validate.literal("x"), value, "ForbiddenType", `literal <- {label}`)
			expectReject(Validate.exactKeys({}), value, "ForbiddenType", `exactKeys <- {label}`)
		end
	end)

	t.test(
		"ForbiddenType: a forbidden value anywhere inside a payload is ForbiddenType, ahead of UnknownKey",
		function()
			local fn = function() end
			local v = Validate.exactKeys({ nonce = Validate.integer({}) })
			expectReject(v, { nonce = fn }, "ForbiddenType", "forbidden field value")
			expectReject(v, { nonce = 0, extra = fn }, "ForbiddenType", "forbidden value under an unknown key")
			expectReject(v, { nonce = 0, extra = { deeper = fn } }, "ForbiddenType", "forbidden value nested")
			expectReject(v, { nonce = 0, [fn :: any] = 1 }, "ForbiddenType", "forbidden KEY")
		end
	)

	t.test("validators never throw, whatever they are fed, and always return (boolean, value)", function()
		local hostile = setmetatable({}, {
			__index = function()
				error("hostile __index")
			end,
			__len = function()
				error("hostile __len")
			end,
			__iter = function()
				error("hostile __iter")
			end,
			__eq = function()
				error("hostile __eq")
			end,
		})
		local cyclic: { [string]: any } = {}
		cyclic.self = cyclic
		local garbage: { unknown } = {
			NAN,
			INF,
			NEG_INF,
			0,
			-1.5,
			"",
			string.rep("x", 1000),
			true,
			{},
			nested(6),
			flat(64),
			hostile,
			cyclic,
			function() end,
			coroutine.create(function() end),
			buffer.create(1),
		}
		local validators: { Validate.Validator } = {
			Validate.number({ min = 0, max = 10 }),
			Validate.integer({ min = 0, max = 10 }),
			Validate.string({ maxLen = 8 }),
			Validate.literal("x"),
			Validate.exactKeys({ nonce = Validate.integer({}) }),
		}
		for vi, validator in validators do
			for gi, value in garbage do
				local survived, ok, result = pcall(validator :: (unknown) -> (boolean, unknown), value)
				t.equal(survived, true, `validator {vi} threw on garbage value {gi}: {tostring(ok)}`)
				t.equal(type(ok), "boolean", `validator {vi} garbage {gi}: first result must be a boolean`)
				if ok == false then
					t.equal(type(result), "string", `validator {vi} garbage {gi}: rejection must carry a string code`)
				end
			end
		end
	end)

	t.test("a table that carries a metatable is accepted as plain data and the copy is stripped of it", function()
		local v = Validate.exactKeys({ nonce = Validate.integer({}) })
		local withMeta = setmetatable({ nonce = 3 }, { __index = { smuggled = true } })
		local clean = expectAccept(v, withMeta, "metatable table")
		t.equal(getmetatable(clean :: any), nil, "clean copy must have no metatable")
		t.deepEqual(clean, { nonce = 3 })
	end)

	t.test("table-driven vectors: each input maps to the one exact verdict", function()
		local anyNumber = Validate.number({})
		local vectors: { Vector } = {
			{ label = "NaN", validator = anyNumber, value = NAN, ok = false, code = "NotFinite" },
			{ label = "+inf", validator = anyNumber, value = INF, ok = false, code = "NotFinite" },
			{ label = "-inf", validator = anyNumber, value = NEG_INF, ok = false, code = "NotFinite" },
			{
				label = "1.5 as integer",
				validator = Validate.integer({}),
				value = 1.5,
				ok = false,
				code = "NotInteger",
			},
			{
				label = "-1.5 as integer",
				validator = Validate.integer({}),
				value = -1.5,
				ok = false,
				code = "NotInteger",
			},
			{ label = "2^53", validator = Validate.integer({}), value = 2 ^ 53, ok = true },
			{
				label = "1e308 as integer",
				validator = Validate.integer({}),
				value = 1e308,
				ok = false,
				code = "NotInteger",
			},
			{ label = "empty string", validator = Validate.string({ maxLen = 8 }), value = "", ok = true },
			{
				label = "1000-char string",
				validator = Validate.string({ maxLen = 8 }),
				value = string.rep("a", 1000),
				ok = false,
				code = "TooLong",
			},
			{
				label = "empty table",
				validator = Validate.exactKeys({ a = anyNumber }),
				value = {},
				ok = false,
				code = "MissingKey",
			},
			{
				label = "extra key",
				validator = Validate.exactKeys({ a = anyNumber, b = anyNumber }),
				value = { a = 1, b = 2, extra = 3 },
				ok = false,
				code = "UnknownKey",
			},
			{ label = "6-deep", validator = Validate.exactKeys({}), value = nested(6), ok = false, code = "TooDeep" },
			{
				label = "64 entries",
				validator = Validate.exactKeys({}),
				value = flat(64),
				ok = false,
				code = "TooLarge",
			},
		}
		t.equal(#vectors, 13, "vector table was edited without updating the count")
		for _, vec in vectors do
			local ok, result = vec.validator(vec.value)
			t.equal(ok, vec.ok, `{vec.label}: verdict`)
			if not vec.ok then
				t.equal(result, vec.code, `{vec.label}: code`)
			end
		end
	end)

	t.fuzz("number never accepts a non-finite value, whatever range it is given", {
		iterations = 500,
		gen = function(rng: any, _i: number): any
			local pool: { number } = { NAN, INF, NEG_INF }
			return { value = pool[rng:nextInt(1, 3)], min = rng:nextInt(-100, 0), max = rng:nextInt(0, 100) }
		end,
		check = function(sample: any)
			local ok, code = Validate.number({ min = sample.min, max = sample.max })(sample.value)
			t.equal(ok, false, "a non-finite value was accepted")
			t.equal(code, "NotFinite", "non-finite value rejected for the wrong reason")
		end,
	})
end
