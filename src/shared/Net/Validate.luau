--!strict
-- Validation vocabulary for the single typed gateway (FOUND-04).
-- PURE ZONE: no Roblox API. The standard library's finite predicate is deliberately NOT used - it is
-- absent from Selene 0.32.0's `luau` std - so the portable form below is this codebase's one source of
-- truth for finiteness.
--
-- Contract: a validator is a function `(value) -> (ok, result)`. On success `result` is a clean value
-- the caller may use; on rejection `result` is one of the Code strings below. A validator never throws
-- and never yields, whatever it is fed. Check order inside every validator is fixed:
--   forbidden type -> expected type -> finite -> integer -> range
-- so NaN can never reach a comparison that would let it through.
export type Code = string
export type Validator = (value: unknown) -> (boolean, unknown)

export type NumberOpts = { min: number?, max: number? }
export type StringOpts = { maxLen: number, minLen: number? }
export type KeysOpts = { maxDepth: number?, maxEntries: number? }

local DEFAULT_MAX_DEPTH = 4
local DEFAULT_MAX_ENTRIES = 32
-- Above 2^53 doubles skip integers, so "whole" no longer means "exactly this integer".
local MAX_EXACT_INTEGER = 2 ^ 53

-- Positive allow-list. Rejecting by what IS allowed is how "no Instances, functions or userdata ever"
-- is expressed without naming a single platform type.
local ALLOWED_TYPES: { [string]: boolean } = {
	["nil"] = true,
	boolean = true,
	number = true,
	string = true,
	table = true,
}

-- Threat T-1-01. `v == v` is the NaN test: NaN is a number that fails every comparison, so a range
-- check alone lets it through. The two infinities are rejected explicitly.
local function isFinite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isForbidden(value: unknown): boolean
	return not ALLOWED_TYPES[type(value)]
end

local function requireFinite(name: string, value: number?)
	if value ~= nil and not isFinite(value) then
		error(`Validate: {name} must be a finite number`, 2)
	end
end

local function number(opts: NumberOpts): Validator
	requireFinite("min", opts.min)
	requireFinite("max", opts.max)
	local min, max = opts.min, opts.max
	return function(value: unknown): (boolean, unknown)
		if isForbidden(value) then
			return false, "ForbiddenType"
		end
		if type(value) ~= "number" then
			return false, "WrongType"
		end
		if not isFinite(value) then
			return false, "NotFinite"
		end
		if (min ~= nil and value < min) or (max ~= nil and value > max) then
			return false, "OutOfRange"
		end
		return true, value
	end
end

local function integer(opts: NumberOpts): Validator
	requireFinite("min", opts.min)
	requireFinite("max", opts.max)
	local min, max = opts.min, opts.max
	return function(value: unknown): (boolean, unknown)
		if isForbidden(value) then
			return false, "ForbiddenType"
		end
		if type(value) ~= "number" then
			return false, "WrongType"
		end
		if not isFinite(value) then
			return false, "NotFinite"
		end
		-- Only after the finite check: inf % 1 is NaN. The magnitude cap rejects 1e308, which is finite
		-- and "whole" by modulo but is not an exactly representable integer.
		if value % 1 ~= 0 or value > MAX_EXACT_INTEGER or value < -MAX_EXACT_INTEGER then
			return false, "NotInteger"
		end
		if (min ~= nil and value < min) or (max ~= nil and value > max) then
			return false, "OutOfRange"
		end
		return true, value
	end
end

local function string_(opts: StringOpts): Validator
	local maxLen, minLen = opts.maxLen, opts.minLen
	requireFinite("maxLen", maxLen)
	requireFinite("minLen", minLen)
	return function(value: unknown): (boolean, unknown)
		if isForbidden(value) then
			return false, "ForbiddenType"
		end
		if type(value) ~= "string" then
			return false, "WrongType"
		end
		if #value > maxLen then
			return false, "TooLong"
		end
		if minLen ~= nil and #value < minLen then
			return false, "TooShort"
		end
		return true, value
	end
end

local function literal(expected: string | number | boolean): Validator
	if type(expected) == "number" then
		requireFinite("literal", expected)
	end
	return function(value: unknown): (boolean, unknown)
		if isForbidden(value) then
			return false, "ForbiddenType"
		end
		if type(value) ~= type(expected) then
			return false, "WrongType"
		end
		if type(value) == "number" and not isFinite(value) then
			return false, "NotFinite"
		end
		if value ~= expected then
			return false, "NotLiteral"
		end
		return true, value
	end
end

type Walk = { entries: number, maxDepth: number, maxEntries: number }

-- Bounded walk over the WHOLE value before any schema lookup, so one message buys bounded CPU
-- (T-1-25) and a forbidden value is reported as such wherever it hides (T-1-26). Uses `next`, which
-- is raw: it never triggers a metamethod, so a hostile metatable cannot run code or throw here.
local function inspect(node: { [unknown]: unknown }, depth: number, walk: Walk): Code?
	if depth > walk.maxDepth then
		return "TooDeep"
	end
	for key, child in next, node do
		walk.entries += 1
		if walk.entries > walk.maxEntries then
			return "TooLarge"
		end
		if isForbidden(key) or isForbidden(child) then
			return "ForbiddenType"
		end
		if type(child) == "table" then
			local code = inspect(child :: { [unknown]: unknown }, depth + 1, walk)
			if code ~= nil then
				return code
			end
		end
	end
	return nil
end

local function exactKeys(schema: { [string]: Validator }, opts: KeysOpts?): Validator
	local maxDepth = DEFAULT_MAX_DEPTH
	local maxEntries = DEFAULT_MAX_ENTRIES
	if opts ~= nil then
		maxDepth = opts.maxDepth or maxDepth
		maxEntries = opts.maxEntries or maxEntries
	end
	-- Fixed order so the same bad input always reports the same code.
	local names: { string } = {}
	for name in next, schema do
		table.insert(names, name)
	end
	table.sort(names)

	return function(value: unknown): (boolean, unknown)
		if isForbidden(value) then
			return false, "ForbiddenType"
		end
		if type(value) ~= "table" then
			return false, "NotTable"
		end
		local node = value :: { [unknown]: unknown }

		local code = inspect(node, 1, { entries = 0, maxDepth = maxDepth, maxEntries = maxEntries })
		if code ~= nil then
			return false, code
		end

		-- Both directions are required: the schema finds missing keys, the value finds unknown ones.
		for _, name in names do
			if rawget(node, name) == nil then
				return false, "MissingKey"
			end
		end
		for key in next, node do
			if type(key) ~= "string" or schema[key] == nil then
				return false, "UnknownKey"
			end
		end

		local clean: { [string]: unknown } = {}
		for _, name in names do
			local ok, result = schema[name](rawget(node, name))
			if not ok then
				return false, result
			end
			clean[name] = result
		end
		return true, clean
	end
end

return {
	isFinite = isFinite,
	number = number,
	integer = integer,
	string = string_,
	exactKeys = exactKeys,
	literal = literal,
}
