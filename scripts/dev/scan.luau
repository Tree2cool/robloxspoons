--!strict
-- THIS TOOL SCANS CODE AND NEVER COMMENTS. Any gate that calls it MUST say which it scans, because the two
-- answers differ and a guard whose header says "raw text" while it scans stripped text has already shipped here
-- once and survived review.
--
-- WHY IT EXISTS. Several gates in this project must assert that a token does NOT appear in a file, while the same
-- file's mandated header is required to NAME that token in order to explain why it is forbidden. A raw `grep`
-- cannot tell those two apart, so those gates are unexecutable as shell commands. The repo already solves this
-- inside Luau specs with `scripts/ci/lex.stripComments`; this makes the same stripping available to a shell
-- verify step. (It has to be a committed file, not a piped script: `lune run -` can require a built-in alias but
-- NOT a relative path like `../ci/lex`. Measured, 04.1-ENV-NOTES.md.)
--
--   lune run scripts/dev/scan.luau code         <file>... <needle>...    fail if ANY needle is in the files' code
--   lune run scripts/dev/scan.luau code-dir     <dir>...  <needle>...    same, recursively over *.luau
--   lune run scripts/dev/scan.luau count      <n> <file>... <needle>...  fail unless the total is exactly n
--   lune run scripts/dev/scan.luau count-dir  <n> <dir>...  <needle>...  same, recursively
--   lune run scripts/dev/scan.luau requires-not <file>... <module>...    fail if a file requires the module
--
-- RULES, AND THEY ARE THE POINT OF THE TOOL:
--
--  1. EVERY MODE STRIPS COMMENTS FIRST, through `scripts/ci/lex.stripComments`, so header prose never trips a
--     gate. STRING LITERALS ARE KEPT, deliberately and for the same reason check-guards R5 keeps them: a
--     forbidden identifier inside a string is still in the shipped artefact. A gate that needs strings gone too
--     is a Luau spec's job (`renderer_discipline.spec`'s `stripCode`), not this tool's.
--  2. A needle that is a BARE IDENTIFIER (only `[%w_]`) matches WHOLE TOKENS ONLY, via `lex.findWord`: `Head`
--     does not match `Header` and `PLATE` does not match `Plate`. Any other needle (`Color3.`, `TWEEN.SEND`,
--     `:release(`, `mode == "Wild"`) is matched as a plain substring. **Matching is CASE-SENSITIVE in both
--     cases.** This repo's recurring defect is a gate that cannot fire: a check for `player.Character` silently
--     matched `player.CharacterAdded`, so the mutant passed and the gate proved nothing.
--  3. IT PRINTS WHAT IT SCANNED -- the file count, every file with a hit, and the total -- so a path that
--     silently matched nothing is visible as a zero rather than as a pass. Scanning NO file is an error, never a
--     pass: a gate over an empty set is the most expensive kind of green.
--  4. IT EXITS NON-ZERO WITH A NAMED MESSAGE giving the file, the needle and the LINE. A gate whose failure does
--     not say what failed costs more than it saves.
--  5. `count`/`count-dir` PRINT THE PER-FILE BREAKDOWN BEFORE ASSERTING, so the ratchets later plans rely on
--     (`LAYERING_ROUTE` exactly 1, per-frame connections exactly 2) report their evidence rather than a verdict.
--
-- ARGUMENT SPLITTING, stated because it is a deviation from this tool's first spec. Paths and needles are told
-- apart BY THE FILESYSTEM: leading arguments that exist on disk (as a directory for the `-dir` modes, as a file
-- otherwise) are paths, and everything after the first argument that does not is a needle. So
-- `code-dir src scripts DiagonalFieldOfView` scans BOTH trees for one needle, which is what the command reads
-- like. Once a needle has been seen, a later argument that IS an existing path is an error by name rather than a
-- silently-eaten needle -- that ambiguity is the one way this convention could hide a mistake, so it is refused.
local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local lex = require("../ci/lex")

local USAGE = table.concat({
	"usage:",
	"  scan.luau code         <file>... <needle>...",
	"  scan.luau code-dir     <dir>...  <needle>...",
	"  scan.luau count      <n> <file>... <needle>...",
	"  scan.luau count-dir  <n> <dir>...  <needle>...",
	"  scan.luau requires-not <file>... <module>...",
}, "\n")

type Hit = { file: string, needle: string, line: number }

local function die(message: string): never
	stdio.ewrite(`scan: {message}\n`)
	process.exit(1)
	-- process.exit does not return; the error keeps the type checker honest about that.
	error("unreachable")
end

local function isBareIdentifier(needle: string): boolean
	return needle ~= "" and string.match(needle, "^[%w_]+$") ~= nil
end

-- Every occurrence of `needle` in `text`, as line numbers. Whole-token for bare identifiers, plain substring
-- otherwise; case-sensitive either way (rule 2).
local function occurrences(text: string, needle: string): { number }
	local lines: { number } = {}
	local from = 1
	if isBareIdentifier(needle) then
		while true do
			local a, b = lex.findWord(text, needle, from)
			if a == nil or b == nil then
				return lines
			end
			table.insert(lines, lex.lineAt(text, a))
			from = b + 1
		end
	end
	while true do
		local a, b = string.find(text, needle, from, true)
		if a == nil or b == nil then
			return lines
		end
		table.insert(lines, lex.lineAt(text, a))
		from = b + 1
	end
end

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

-- Splits `args` into paths and needles by the filesystem (see the header's ARGUMENT SPLITTING note).
local function splitPathsAndNeedles(args: { string }, wantDir: boolean): ({ string }, { string })
	local function exists(path: string): boolean
		return if wantDir then fs.isDir(path) else fs.isFile(path)
	end
	local paths: { string } = {}
	local needles: { string } = {}
	for _, arg in args do
		if #needles == 0 and exists(arg) then
			table.insert(paths, arg)
		else
			if exists(arg) then
				die(
					`ambiguous argument "{arg}": it is an existing {if wantDir then "directory" else "file"} but it `
						.. `follows the needle "{needles[1]}". Put every path before every needle.`
				)
			end
			table.insert(needles, arg)
		end
	end
	return paths, needles
end

local function collectFiles(args: { string }, wantDir: boolean): ({ string }, { string })
	local paths, needles = splitPathsAndNeedles(args, wantDir)
	if #paths == 0 then
		die(`no existing {if wantDir then "directory" else "file"} among the arguments\n{USAGE}`)
	end
	if #needles == 0 then
		die(`no needles given; a scan for nothing is not a gate\n{USAGE}`)
	end
	local files: { string } = {}
	if wantDir then
		for _, dir in paths do
			luauFilesUnder(dir, files)
		end
	else
		files = paths
	end
	if #files == 0 then
		die(`scanned 0 files under {table.concat(paths, ", ")}: a gate over an empty set is not a pass`)
	end
	return files, needles
end

-- The shared body of code / code-dir / count / count-dir. Prints what it scanned (rule 3) and returns the hits.
local function scanForNeedles(files: { string }, needles: { string }, label: string): { Hit }
	local hits: { Hit } = {}
	local perFile: { string } = {}
	for _, file in files do
		local code = lex.stripComments(fs.readFile(file))
		local inThisFile = 0
		for _, needle in needles do
			for _, line in occurrences(code, needle) do
				table.insert(hits, { file = file, needle = needle, line = line })
				inThisFile += 1
			end
		end
		if inThisFile > 0 then
			table.insert(perFile, `    {file}: {inThisFile}`)
		end
	end
	print(`scan[{label}]: {#files} files, {#needles} needles ({table.concat(needles, " ")}), {#hits} hits in code`)
	print("  (comments stripped; string literals KEPT -- see this file's header)")
	if #perFile == 0 then
		print("    (no file had a hit)")
	else
		for _, line in perFile do
			print(line)
		end
	end
	return hits
end

local function reportHitsAndDie(hits: { Hit }, why: string): never
	for _, hit in hits do
		stdio.ewrite(`scan: {hit.file}:{hit.line}: forbidden "{hit.needle}" in code\n`)
	end
	return die(why)
end

local function runCode(args: { string }, wantDir: boolean)
	local files, needles = collectFiles(args, wantDir)
	local hits = scanForNeedles(files, needles, if wantDir then "code-dir" else "code")
	if #hits > 0 then
		reportHitsAndDie(hits, `{#hits} forbidden occurrence(s) in code; see the lines above`)
	end
	print(`scan: ok -- 0 occurrences of {#needles} needle(s) in {#files} file(s)`)
end

local function runCount(args: { string }, wantDir: boolean)
	local expectedRaw = table.remove(args, 1)
	local expected = if expectedRaw ~= nil then tonumber(expectedRaw) else nil
	if expected == nil or expected < 0 or expected % 1 ~= 0 then
		die(`count needs a non-negative integer first, got "{tostring(expectedRaw)}"\n{USAGE}`)
	end
	local files, needles = collectFiles(args, wantDir)
	local hits = scanForNeedles(files, needles, if wantDir then "count-dir" else "count")
	-- The breakdown is printed by scanForNeedles BEFORE this assertion, on purpose (rule 5): the evidence is
	-- useful whether the ratchet holds or not.
	for _, hit in hits do
		print(`    at {hit.file}:{hit.line} ("{hit.needle}")`)
	end
	if #hits ~= expected then
		die(`expected exactly {expected} occurrence(s), found {#hits} (listed above)`)
	end
	print(`scan: ok -- exactly {expected} occurrence(s), as required`)
end

-- A module name matches a require target when its path segments are a contiguous run of the target's, so
-- `Config/Card` matches `../../src/shared/Config/Card` and `Card` matches it too, while `Cardboard` matches
-- neither.
local function segments(path: string): { string }
	local out: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part ~= "." and part ~= ".." then
			table.insert(out, (string.gsub(part, "%.luau$", "")))
		end
	end
	return out
end

local function targetMatchesModule(target: string, module: string): boolean
	local t, m = segments(target), segments(module)
	if #m == 0 or #m > #t then
		return false
	end
	for start = 1, #t - #m + 1 do
		local all = true
		for i = 1, #m do
			if t[start + i - 1] ~= m[i] then
				all = false
				break
			end
		end
		if all then
			return true
		end
	end
	return false
end

local function runRequiresNot(args: { string })
	local files, modules = collectFiles(args, false)
	local hits: { Hit } = {}
	local totalRequires = 0
	for _, file in files do
		local code = lex.stripComments(fs.readFile(file))
		local literals, nonLiteral = lex.extractRequires(code)
		totalRequires += #literals
		for _, req in literals do
			for _, module in modules do
				if targetMatchesModule(req.target, module) then
					table.insert(hits, { file = file, needle = `require("{req.target}")`, line = req.line })
				end
			end
		end
		-- A require this tool cannot resolve is a violation, not a pass: it is the one construct that could be
		-- the forbidden module without saying so. check-guards R3 takes the same line.
		for _, line in nonLiteral do
			table.insert(hits, { file = file, needle = "a require with no literal string", line = line })
		end
	end
	print(`scan[requires-not]: {#files} files, {totalRequires} literal requires, {#modules} forbidden module(s)`)
	print(`  forbidden: {table.concat(modules, " ")}`)
	if #hits > 0 then
		reportHitsAndDie(hits, `{#hits} forbidden require(s); see the lines above`)
	end
	print(`scan: ok -- none of {#files} file(s) requires {table.concat(modules, " ")}`)
end

local function main(argv: { string })
	local args: { string } = {}
	for _, a in argv do
		if a ~= "--" then
			table.insert(args, a)
		end
	end
	local mode = table.remove(args, 1)
	if mode == nil then
		die(`no mode given\n{USAGE}`)
	elseif mode == "code" then
		runCode(args, false)
	elseif mode == "code-dir" then
		runCode(args, true)
	elseif mode == "count" then
		runCount(args, false)
	elseif mode == "count-dir" then
		runCount(args, true)
	elseif mode == "requires-not" then
		runRequiresNot(args)
	else
		die(`unknown mode "{mode}"\n{USAGE}`)
	end
end

main(process.args)
