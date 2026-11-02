--!strict
-- Registration + assertion API consumed by every spec (FOUND-03). Requires nothing: the fuzz driver is
-- injected through Options.fuzzDriver, so this file can never hold a dangling require.
-- This file is the sole owner of FuzzOpts and FuzzDriver; Fuzz.luau imports them from here.

export type Case = { name: string, fn: () -> () }

export type FuzzOpts = {
	seed: number?,
	iterations: number?,
	gen: (rng: any, i: number) -> any,
	check: (value: any) -> (),
}
export type FuzzDriver = (name: string, opts: FuzzOpts, seed: number) -> ()

export type Options = { seed: number?, fuzzDriver: FuzzDriver? }

export type Runner = {
	cases: { Case },
	todos: { string },
	seed: number,
	test: (name: string, fn: () -> ()) -> (),
	todo: (name: string) -> (),
	equal: (actual: any, expected: any, message: string?) -> (),
	deepEqual: (actual: any, expected: any, message: string?) -> (),
	truthy: (value: any, message: string?) -> (),
	falsy: (value: any, message: string?) -> (),
	contains: (haystack: string, needle: string, message: string?) -> (),
	throws: (fn: () -> (), needle: string?) -> (),
	fuzz: (name: string, opts: FuzzOpts) -> (),
}

local DEEP_EQUAL_DEPTH_CAP = 8

local function show(value: any, depth: number?): string
	local d = depth or 0
	if type(value) == "string" then
		return string.format("%q", value)
	end
	if type(value) ~= "table" then
		return tostring(value)
	end
	if d >= 3 then
		return "{...}"
	end
	local parts: { string } = {}
	for k, v in value do
		table.insert(parts, `[{tostring(k)}] = {show(v, d + 1)}`)
	end
	table.sort(parts)
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function fail(message: string?, detail: string): never
	if message ~= nil and message ~= "" then
		error(`{message} ({detail})`, 0)
	end
	error(detail, 0)
end

local function deepEq(a: any, b: any, depth: number): boolean
	if a == b then
		return true
	end
	if a ~= a and b ~= b then
		return true -- NaN equals NaN for comparison purposes
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	if depth >= DEEP_EQUAL_DEPTH_CAP then
		error(`deepEqual depth cap ({DEEP_EQUAL_DEPTH_CAP}) exceeded`, 0)
	end
	for k, v in a do
		if not deepEq(v, b[k], depth + 1) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function new(options: Options?): Runner
	local seed: number = 1
	local driver: FuzzDriver? = nil
	if options ~= nil then
		if options.seed ~= nil then
			seed = options.seed
		end
		driver = options.fuzzDriver
	end

	local cases: { Case } = {}
	local todos: { string } = {}

	local function test(name: string, fn: () -> ())
		table.insert(cases, { name = name, fn = fn })
	end

	local function todo(name: string)
		table.insert(todos, name)
	end

	local function equal(actual: any, expected: any, message: string?)
		if actual ~= expected then
			fail(message, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
		end
	end

	local function deepEqual(actual: any, expected: any, message: string?)
		if not deepEq(actual, expected, 0) then
			fail(message, string.format("expected %s, got %s", show(expected), show(actual)))
		end
	end

	local function truthy(value: any, message: string?)
		if not value then
			fail(message, `expected a truthy value, got {show(value)}`)
		end
	end

	local function falsy(value: any, message: string?)
		if value then
			fail(message, `expected a falsy value, got {show(value)}`)
		end
	end

	local function contains(haystack: string, needle: string, message: string?)
		if string.find(haystack, needle, 1, true) == nil then
			fail(message, string.format("expected %s to contain %s", show(haystack), show(needle)))
		end
	end

	local function throws(fn: () -> (), needle: string?)
		local ok, err = pcall(fn :: () -> any)
		if ok then
			error("expected function to throw, but it returned normally", 0)
		end
		if needle ~= nil and string.find(tostring(err), needle, 1, true) == nil then
			error(string.format("expected error containing %s, got %s", show(needle), show(tostring(err))), 0)
		end
	end

	local function fuzz(name: string, opts: FuzzOpts)
		local installed = driver
		if installed == nil then
			-- Loud on purpose: a dropped wiring in tests/run.luau must break the suite, not skip fuzzing.
			test(name, function()
				error("fuzz driver not installed", 0)
			end)
			return
		end
		test(name, function()
			installed(name, opts, seed)
		end)
	end

	return {
		cases = cases,
		todos = todos,
		seed = seed,
		test = test,
		todo = todo,
		equal = equal,
		deepEqual = deepEqual,
		truthy = truthy,
		falsy = falsy,
		contains = contains,
		throws = throws,
		fuzz = fuzz,
	}
end

return { new = new }
