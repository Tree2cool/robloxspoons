--!strict
-- Shared lexing helpers for the CI scripts: comment stripping and literal-require extraction. check-guards
-- (filesystem view) and check-built-place (built-artefact view) MUST use the same logic, otherwise they could
-- disagree about which requires exist and the cross-check between them would prove nothing.

export type Req = { target: string, line: number }

local function lineAt(text: string, pos: number): number
	local line = 1
	local from = 1
	while true do
		local nl = string.find(text, "\n", from, true)
		if nl == nil or nl >= pos then
			return line
		end
		line += 1
		from = nl + 1
	end
end

-- Find `word` as a whole identifier (not part of a longer name).
local function findWord(text: string, word: string, init: number): (number?, number?)
	local from = init
	while true do
		local a, b = string.find(text, word, from, true)
		if a == nil or b == nil then
			return nil, nil
		end
		local before = if a > 1 then string.sub(text, a - 1, a - 1) else ""
		local after = string.sub(text, b + 1, b + 1)
		if string.match(before, "[%w_]") == nil and string.match(after, "[%w_]") == nil then
			return a, b
		end
		from = b + 1
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Comment stripping. String literals are walked (so a `--` inside a string is not a comment) and KEPT: leaving a
-- string in can only add a loud false positive. Newlines inside block comments are preserved so line numbers hold.
-- ---------------------------------------------------------------------------------------------------------------

local function stripComments(src: string): string
	local out: { string } = {}
	local n = #src
	local i = 1
	while i <= n do
		local c = string.sub(src, i, i)
		if c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == c or d == "\n" then
					break
				else
					j += 1
				end
			end
			table.insert(out, string.sub(src, i, math.min(j, n)))
			i = j + 1
		elseif c == "`" then
			local j = i + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == "`" then
					break
				else
					j += 1
				end
			end
			table.insert(out, string.sub(src, i, math.min(j, n)))
			i = j + 1
		elseif c == "[" then
			local eq = string.match(src, "^%[(=*)%[", i)
			if eq ~= nil then
				local close = "]" .. eq .. "]"
				local _, e = string.find(src, close, i, true)
				local stop = e or n
				table.insert(out, string.sub(src, i, stop))
				i = stop + 1
			else
				table.insert(out, c)
				i += 1
			end
		elseif c == "-" and string.sub(src, i + 1, i + 1) == "-" then
			local eq = string.match(src, "^%-%-%[(=*)%[", i)
			if eq ~= nil then
				local close = "]" .. eq .. "]"
				local _, e = string.find(src, close, i, true)
				local stop = e or n
				local _, newlines = string.gsub(string.sub(src, i, stop), "\n", "")
				table.insert(out, " " .. string.rep("\n", newlines))
				i = stop + 1
			else
				local nl = string.find(src, "\n", i, true)
				table.insert(out, " ")
				i = nl or n + 1
			end
		else
			table.insert(out, c)
			i += 1
		end
	end
	return table.concat(out)
end

-- Every `require` identifier in stripped text is either followed by a literal-string call, or it is not.
-- Returns the literal requires, and the line numbers of every other use of the word.
local function extractRequires(text: string): ({ Req }, { number })
	local literals: { Req } = {}
	local nonLiteral: { number } = {}
	local from = 1
	while true do
		local a, b = findWord(text, "require", from)
		if a == nil or b == nil then
			break
		end
		local target = string.match(text, '^%s*%(%s*"([^"]+)"%s*%)', b + 1)
		if target == nil then
			target = string.match(text, "^%s*%(%s*'([^']+)'%s*%)", b + 1)
		end
		-- A preceding `.` or `:` means it is a member named require, not the global: treat it as non-literal too.
		local before = if a > 1 then string.sub(text, a - 1, a - 1) else ""
		if target ~= nil and before ~= "." and before ~= ":" then
			table.insert(literals, { target = target, line = lineAt(text, a) })
		else
			table.insert(nonLiteral, lineAt(text, a))
		end
		from = b + 1
	end
	return literals, nonLiteral
end

return {
	lineAt = lineAt,
	findWord = findWord,
	stripComments = stripComments,
	extractRequires = extractRequires,
}
