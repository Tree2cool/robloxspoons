--!strict
-- Structural guards (FOUND-05, FOUND-06 hygiene half, FOUND-02 strict-header half, FOUND-04 structural half).
--
--   lune run scripts/ci/check-guards.luau [root]        scan `root` (default "."); exit 1 on any violation
--   lune run scripts/ci/check-guards.luau --print-zones  print the pure zones space-separated; exit 1, empty stdout,
--                                                        if the list is empty (see printZones)
--
-- THREAT MODEL. This guard defends against accident and agent drift, not against an adversary with metatable
-- tricks. It is sound inside guarded zones because it forbids every construct it cannot statically resolve.
--
-- Rules (one violation per line: `<RULE_ID> <relative/path>:<line> <message>`):
--   R1  every .luau under scanDirs starts with `--!strict` on line 1                     (scanDirs)
--   R2  FOUND-05: no transitive literal-require path from a guarded root to a forbidden   (src/ roots)
--       module family (cosmetics, shop, ...). The message names the whole chain.
--   R3  inside pure zones, guarded roots and everything they require: no require that is not a
--       literal string, and no getfenv / setfenv / loadstring / rawget(_G / _G[ / coroutine / os.
--       (coroutine and os. are CLAUDE.md rules 6 and 5: no yields mid-mutation, server is the only clock)
--   R3b inside pure zones: no suppression comment (selene: allow, --# selene, --!nocheck, ...)
--   R4  Net hygiene: Remote entry points may appear only in their owner file             (shippedDirs)
--   R5  hidden-data vocabulary must not appear under src/client or src/shared            (shippedDirs)
--   R6  a require must resolve to the same module on disk and in the Roblox DataModel   (shippedDirs)
--
-- SCOPES ARE PER RULE, AND THAT IS DELIBERATE. R4, R5 and R6 scan `zones.shippedDirs` only. scripts/ci/zones.luau
-- names OnServerEvent and SpoonDefaultSpot as table keys, tests name them as expected-output needles, and tests/
-- and scripts/ legitimately require across Rojo mounts because they are never mounted. If one of those three rules
-- ever reports a violation in scripts/ or tests/, the scope is wrong, not the rule. Never shorten the name lists and
-- never add a per-file exception.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local lex = require("./lex")
local zones = require("./zones")

local netOwners: { [string]: string } = zones.netOwners

type Violation = { rule: string, file: string, line: number, msg: string }
type Req = lex.Req
local lineAt = lex.lineAt
local findWord = lex.findWord
local stripComments = lex.stripComments
local extractRequires = lex.extractRequires
type SourceFile = { rel: string, raw: string, text: string, requires: { Req } }
type Mount = { path: { string }, dm: { string } }
-- kind: "file" resolved on disk (path = root-relative file), "raw" not a filesystem path (path = the string as written),
-- "missing" a relative path that matches no file (path = the nominal path), "selfmisuse" `@self/` outside an init module
type Edge = { target: string, line: number, kind: string, path: string }

local SUPPRESSIONS = { "selene: allow", "--# selene", "--!nocheck", "--!nonstrict", "-- luau-lsp:", "--!native" }
-- `coroutine` and `os.` are banned in pure zones for CLAUDE.md rules 5 and 6, not for rule 2:
-- selene.pure.toml sets std = "luau", so coroutine.* and os.* are STANDARD Luau and pass the
-- allow-list lint with 0 errors (measured, 02-RESEARCH.md section 1). Without this ban an engine
-- module can yield mid-mutation and read a real clock while all 14 gates stay green.
-- `coroutine` is a findWord entry, so `coroutine.yield`, `.resume`, `.wrap` and `.create` are one
-- rule while an identifier such as `coroutines` or `myCoroutineHelper` is not a false hit.
local BANNED_CONSTRUCTS = { "getfenv", "setfenv", "loadstring", "coroutine" }

-- ---------------------------------------------------------------------------------------------------------------
-- Small string and path helpers
-- ---------------------------------------------------------------------------------------------------------------

local function split(s: string, sep: string): { string }
	local out: { string } = {}
	for part in string.gmatch(s, "[^" .. sep .. "]+") do
		table.insert(out, part)
	end
	return out
end

local function toSet(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, v in list do
		set[v] = true
	end
	return set
end

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

local function join(root: string, rel: string): string
	if root == "." then
		return rel
	end
	return root .. "/" .. rel
end

local function basenameOf(path: string): string
	local segs = split(path, "/")
	local last = segs[#segs] or path
	if (last == "init.luau" or last == "init.lua") and #segs > 1 then
		last = segs[#segs - 1]
	end
	last = string.gsub(last, "%.luau$", "")
	last = string.gsub(last, "%.lua$", "")
	return last
end

-- ---------------------------------------------------------------------------------------------------------------
-- Rojo mounts and DataModel paths
-- ---------------------------------------------------------------------------------------------------------------

local function collectMounts(node: any, names: { string }, out: { Mount })
	if type(node) ~= "table" then
		return
	end
	local pathValue = (node :: { [string]: any })["$path"]
	if type(pathValue) == "string" then
		local p = string.gsub(pathValue, "/+$", "")
		table.insert(out, { path = split(p, "/"), dm = table.clone(names) })
	end
	for key, child in node :: { [string]: any } do
		if type(key) == "string" and string.sub(key, 1, 1) ~= "$" and type(child) == "table" then
			local nextNames = table.clone(names)
			table.insert(nextNames, key)
			collectMounts(child, nextNames, out)
		end
	end
end

local function loadMounts(root: string): { Mount }
	local mounts: { Mount } = {}
	local projectPath = join(root, "default.project.json")
	if fs.isFile(projectPath) then
		local project = serde.decode("json", fs.readFile(projectPath)) :: any
		local tree = if type(project) == "table" then (project :: { [string]: any }).tree else nil
		if type(tree) == "table" then
			collectMounts(tree, {}, mounts)
		end
		if #mounts == 0 then
			error(`{projectPath} declares no $path mounts: cannot resolve the DataModel twin`)
		end
	else
		for _, m in zones.mounts do
			table.insert(mounts, { path = split(m.path, "/"), dm = split(m.datamodel, ".") })
		end
	end
	return mounts
end

local function isPrefix(prefix: { string }, full: { string }): boolean
	if #prefix > #full then
		return false
	end
	for i, seg in prefix do
		if full[i] ~= seg then
			return false
		end
	end
	return true
end

local function sameList(a: { string }, b: { string }): boolean
	return #a == #b and isPrefix(a, b)
end

-- DataModel path of a source file (as a list of instance names), plus the mount it lives in and whether it is an
-- init module (an init module IS its directory's instance).
local function dmOf(rel: string, mounts: { Mount }): ({ string }?, Mount?, boolean)
	local segs = split(rel, "/")
	for _, mount in mounts do
		if isPrefix(mount.path, segs) and #segs > #mount.path then
			local dm = table.clone(mount.dm)
			local isInit = false
			for i = #mount.path + 1, #segs do
				local part = segs[i]
				if i == #segs then
					part = string.gsub(part, "%.server%.luau?$", "")
					part = string.gsub(part, "%.client%.luau?$", "")
					part = string.gsub(part, "%.luau?$", "")
					if part == "init" then
						isInit = true
						break
					end
				end
				table.insert(dm, part)
			end
			return dm, mount, isInit
		end
	end
	return nil, nil, false
end

-- ---------------------------------------------------------------------------------------------------------------
-- Filesystem resolution
-- ---------------------------------------------------------------------------------------------------------------

local function isInitFile(rel: string): boolean
	local segs = split(rel, "/")
	local last = segs[#segs]
	return last == "init.luau" or last == "init.lua"
end

local function resolveRequire(root: string, sf: SourceFile, req: Req): Edge
	local target = req.target
	local baseSegs = split(sf.rel, "/")
	table.remove(baseSegs) -- drop the file name: base is its directory
	local rest: string

	if startsWith(target, "@self/") then
		if not isInitFile(sf.rel) then
			return { target = target, line = req.line, kind = "selfmisuse", path = target }
		end
		rest = string.sub(target, 7)
	elseif startsWith(target, "./") or startsWith(target, "../") then
		-- An init module is its directory, so `./` and `../` start from the directory's parent.
		if isInitFile(sf.rel) then
			table.remove(baseSegs)
		end
		rest = target
	else
		return { target = target, line = req.line, kind = "raw", path = target }
	end

	local segs = table.clone(baseSegs)
	for _, part in split(rest, "/") do
		if part == "." then
			continue
		elseif part == ".." then
			if #segs == 0 then
				return { target = target, line = req.line, kind = "missing", path = "<escapes root>" }
			end
			table.remove(segs)
		else
			table.insert(segs, part)
		end
	end
	local joined = table.concat(segs, "/")
	for _, suffix in { ".luau", ".lua", "/init.luau", "/init.lua" } do
		local candidate = joined .. suffix
		if fs.isFile(join(root, candidate)) then
			return { target = target, line = req.line, kind = "file", path = candidate }
		end
	end
	return { target = target, line = req.line, kind = "missing", path = joined }
end

-- ---------------------------------------------------------------------------------------------------------------
-- The scan
-- ---------------------------------------------------------------------------------------------------------------

local function collectFiles(root: string, rel: string, ignored: { [string]: boolean }?, out: { string })
	local dirPath = join(root, rel)
	if not fs.isDir(dirPath) then
		return
	end
	local names = fs.readDir(dirPath)
	table.sort(names)
	for _, name in names do
		local childRel = rel .. "/" .. name
		if ignored ~= nil and ignored[name] then
			continue
		end
		if fs.isDir(join(root, childRel)) then
			collectFiles(root, childRel, ignored, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, childRel)
		end
	end
end

local function underAny(rel: string, dirs: { string }): boolean
	for _, dir in dirs do
		if startsWith(rel, dir .. "/") then
			return true
		end
	end
	return false
end

local function check(root: string): number
	local violations: { Violation } = {}
	local function add(rule: string, file: string, line: number, msg: string)
		table.insert(violations, { rule = rule, file = file, line = line, msg = msg })
	end

	if not fs.isDir(root) then
		print(`check-guards: root {root} is not a directory`)
		return 1
	end

	-- 1. File walk. Ignored segments are honoured unless the root itself points inside one (fixture runs).
	local ignored = toSet(zones.ignoreSegments)
	local ignoreOn = true
	for _, seg in split(root, "/") do
		if ignored[seg] then
			ignoreOn = false
		end
	end
	local paths: { string } = {}
	for _, dir in zones.scanDirs do
		collectFiles(root, dir, if ignoreOn then ignored else nil, paths)
	end
	-- collectFiles prefixes "rel/" with a leading scanDir, so the entries are already root-relative.
	if #paths == 0 then
		-- A guard that scanned nothing must not read green.
		print(`check-guards: no .luau files found under {root}: a scan of nothing must not look green`)
		return 1
	end

	local files: { [string]: SourceFile } = {}
	local order: { string } = {}
	local requireCount = 0
	for _, rel in paths do
		local raw = fs.readFile(join(root, rel))
		local text = stripComments(raw)
		local requires = extractRequires(text)
		requireCount += #requires
		files[rel] = { rel = rel, raw = raw, text = text, requires = requires }
		table.insert(order, rel)
	end

	local function load(rel: string): SourceFile?
		local existing = files[rel]
		if existing ~= nil then
			return existing
		end
		if not fs.isFile(join(root, rel)) then
			return nil
		end
		local raw = fs.readFile(join(root, rel))
		local text = stripComments(raw)
		local requires = extractRequires(text)
		local sf: SourceFile = { rel = rel, raw = raw, text = text, requires = requires }
		files[rel] = sf
		return sf
	end

	-- R1: strict header on every authored file.
	for _, rel in order do
		local sf = files[rel]
		local firstLine = string.match(sf.raw, "^([^\n]*)") or ""
		firstLine = string.gsub(firstLine, "\r$", "")
		if firstLine ~= "--!strict" then
			add("R1", rel, 1, `first line must be exactly --!strict (found: {firstLine})`)
		end
	end

	-- Roots for R2/R3: guarded-name files under src/, then every file in a pure zone.
	local rootSet: { [string]: boolean } = {}
	local guardedFirst: { string } = {}
	local zoneRoots: { string } = {}
	for _, rel in order do
		if underAny(rel, zones.shippedDirs) then
			local base = string.match(rel, "([^/]+)$") or rel
			for _, prefix in zones.guardedNamePrefixes do
				if startsWith(base, prefix) then
					rootSet[rel] = true
					table.insert(guardedFirst, rel)
					break
				end
			end
		end
	end
	for _, rel in order do
		if underAny(rel, zones.pureZones) and not rootSet[rel] then
			rootSet[rel] = true
			table.insert(zoneRoots, rel)
		end
	end
	local roots: { string } = {}
	for _, rel in guardedFirst do
		table.insert(roots, rel)
	end
	for _, rel in zoneRoots do
		table.insert(roots, rel)
	end

	-- R3: non-resolvable constructs. Applied to roots and to every file the closure reaches, otherwise a helper
	-- module outside the zones could re-introduce indirection and make the closure unsound.
	local r3Done: { [string]: boolean } = {}
	local function checkR3(sf: SourceFile)
		if r3Done[sf.rel] then
			return
		end
		r3Done[sf.rel] = true
		local _, nonLiteral = extractRequires(sf.text)
		for _, line in nonLiteral do
			add("R3", sf.rel, line, "non-literal require: the require target is not a string literal")
		end
		for _, word in BANNED_CONSTRUCTS do
			local from = 1
			while true do
				local a, b = findWord(sf.text, word, from)
				if a == nil or b == nil then
					break
				end
				add("R3", sf.rel, lineAt(sf.text, a), `banned construct: {word}`)
				from = b + 1
			end
		end
		-- `os.` is a needle and NOT a findWord entry on purpose: the bare word `os` appears legitimately in
		-- prose and inside identifiers, while the dotted namespace access is unambiguous. Because sf.text keeps
		-- string literals, a pure-zone file may not contain the substring `os.` even inside a string. That
		-- over-strictness is intentional in a zone whose whole point is having no clock.
		for _, needle in { "rawget(_G", "rawget( _G", "_G[", "os." } do
			local from = 1
			while true do
				local a, b = string.find(sf.text, needle, from, true)
				if a == nil or b == nil then
					break
				end
				add("R3", sf.rel, lineAt(sf.text, a), `banned construct: {needle}`)
				from = b + 1
			end
		end
	end

	-- Resolve each src file's requires once; R6 and R2 both read them.
	local edgeCache: { [string]: { Edge } } = {}
	local function edgesOf(sf: SourceFile): { Edge }
		local cached = edgeCache[sf.rel]
		if cached ~= nil then
			return cached
		end
		local edges: { Edge } = {}
		for _, req in sf.requires do
			table.insert(edges, resolveRequire(root, sf, req))
		end
		edgeCache[sf.rel] = edges
		return edges
	end

	local forbidden: { string } = {}
	for _, seg in zones.forbiddenSegments do
		table.insert(forbidden, string.lower(seg))
	end
	local function forbiddenHit(path: string): string?
		for _, seg in split(string.lower(path), "/") do
			for _, bad in forbidden do
				if string.find(seg, bad, 1, true) ~= nil then
					return bad
				end
			end
		end
		return nil
	end

	-- R2 closure: depth-first, cycle-safe (visited set per root). The chain is rebuilt from basenames.
	local reported: { [string]: boolean } = {}
	local function walk(sf: SourceFile, chain: { string }, visited: { [string]: boolean })
		for _, edge in edgesOf(sf) do
			local hit = forbiddenHit(edge.path)
			if hit ~= nil then
				local key = `{sf.rel}:{edge.line}:{edge.path}`
				if not reported[key] then
					reported[key] = true
					local full = table.clone(chain)
					table.insert(full, basenameOf(edge.path))
					add(
						"R2",
						sf.rel,
						edge.line,
						`forbidden import: {table.concat(full, " -> ")} (path segment matches "{hit}")`
					)
				end
			elseif edge.kind == "file" and not visited[edge.path] then
				visited[edge.path] = true
				local nextFile = load(edge.path)
				if nextFile ~= nil then
					checkR3(nextFile)
					local nextChain = table.clone(chain)
					table.insert(nextChain, basenameOf(edge.path))
					walk(nextFile, nextChain, visited)
				end
			end
		end
	end

	for _, rel in roots do
		local sf = files[rel]
		checkR3(sf)
		local visited: { [string]: boolean } = { [rel] = true }
		walk(sf, { basenameOf(rel) }, visited)
	end

	-- R3b and the non-relative-require ban: pure zones only. Suppression detection reads the UNSTRIPPED text.
	for _, rel in order do
		if underAny(rel, zones.pureZones) then
			local sf = files[rel]
			for _, needle in SUPPRESSIONS do
				local from = 1
				while true do
					local a, b = string.find(sf.raw, needle, from, true)
					if a == nil or b == nil then
						break
					end
					add("R3b", rel, lineAt(sf.raw, a), `suppression comment in a pure zone: {needle}`)
					from = b + 1
				end
			end
			for _, edge in edgesOf(sf) do
				if edge.kind == "raw" or edge.kind == "selfmisuse" then
					add("R3", rel, edge.line, `non-relative require "{edge.target}" in a pure zone`)
				end
			end
		end
	end

	-- R4 / R5 / R6: shippedDirs only.
	local mounts = loadMounts(root)
	local secretClientDirs = { "src/client", "src/shared" }
	for _, rel in order do
		if not underAny(rel, zones.shippedDirs) then
			continue
		end
		local sf = files[rel]

		-- R4
		for name, owner in netOwners do
			if rel ~= owner then
				local from = 1
				while true do
					local a, b = findWord(sf.text, name, from)
					if a == nil or b == nil then
						break
					end
					add("R4", rel, lineAt(sf.text, a), `{name} may appear only in {owner}`)
					from = b + 1
				end
			end
		end

		-- R5
		if underAny(rel, secretClientDirs) then
			for _, name in zones.secretNames do
				local from = 1
				while true do
					local a, b = string.find(sf.text, name, from, true)
					if a == nil or b == nil then
						break
					end
					add(
						"R5",
						rel,
						lineAt(sf.text, a),
						`hidden-data name {name} must not appear in client or shared code`
					)
					from = b + 1
				end
			end
		end

		-- R6
		local fileDm, mount = dmOf(rel, mounts)
		if fileDm == nil or mount == nil then
			add("R6", rel, 1, "file is under src/ but not under any Rojo mount: it does not exist in the DataModel")
			continue
		end
		for _, edge in edgesOf(sf) do
			if edge.kind == "missing" then
				add("R6", rel, edge.line, `unresolvable require "{edge.target}" (no file at {edge.path})`)
			elseif edge.kind == "selfmisuse" then
				add("R6", rel, edge.line, `"{edge.target}" is only legal from an init module`)
			elseif edge.kind == "file" then
				local walkDm = table.clone(fileDm)
				if not startsWith(edge.target, "@self/") then
					-- A non-init module's `./` starts at its parent; an init module IS its directory instance, so its
					-- parent is also one step up. Both reduce to "drop the last name".
					table.remove(walkDm)
				end
				local rest = if startsWith(edge.target, "@self/") then string.sub(edge.target, 7) else edge.target
				local escaped = false
				for _, part in split(rest, "/") do
					if part == "." then
						continue
					elseif part == ".." then
						if #walkDm == 0 then
							escaped = true
							break
						end
						table.remove(walkDm)
					else
						table.insert(walkDm, part)
					end
				end
				local targetDm = dmOf(edge.path, mounts)
				local ok = not escaped and isPrefix(mount.dm, walkDm) and targetDm ~= nil and sameList(walkDm, targetDm)
				if not ok then
					local reached = if escaped then "<above DataModel root>" else table.concat(walkDm, ".")
					add(
						"R6",
						rel,
						edge.line,
						`cross-mount require "{edge.target}" resolves on disk but not in the DataModel (walk reached {reached})`
					)
				end
			end
		end
	end

	-- Output
	table.sort(violations, function(a: Violation, b: Violation): boolean
		if a.file ~= b.file then
			return a.file < b.file
		end
		if a.line ~= b.line then
			return a.line < b.line
		end
		return a.rule < b.rule
	end)
	for _, v in violations do
		print(`{v.rule} {v.file}:{v.line} {v.msg}`)
	end
	if #violations > 0 then
		print(`check-guards: {#violations} violation(s)`)
		return 1
	end
	print(`check-guards: ok ({#order} files, {requireCount} requires, {#roots} guarded roots)`)
	return 0
end

-- `--print-zones` feeds CI steps that splice the output into a command line (the FOUND-06 type and lint layers).
-- An empty list would splice to nothing, those steps would silently analyse only `scripts tests`, and the pure zones
-- would drop out of the gate while the step stayed green. An empty list is a configuration error: exit 1, empty stdout.
local function printZones(): number
	local list = zones.pureZones
	if #list == 0 then
		stdio.ewrite("check-guards: --print-zones: zones.pureZones is empty; refusing to print nothing and exit 0\n")
		return 1
	end
	for _, zone in list do
		if zone == "" or string.find(zone, "%s") ~= nil then
			stdio.ewrite(`check-guards: --print-zones: unusable zone entry {zone}\n`)
			return 1
		end
	end
	print(table.concat(list, " "))
	return 0
end

local function main(args: { string }): number
	local root: string? = nil
	local wantZones = false
	for _, a in args do
		if a == "--" then
			-- Lune 0.11.1 passes the `--` separator through to the script; tolerate it.
			continue
		elseif a == "--print-zones" then
			wantZones = true
		elseif string.sub(a, 1, 2) == "--" then
			print(`check-guards: unknown argument: {a}`)
			return 1
		elseif root == nil then
			root = a
		else
			print(`check-guards: unexpected extra argument: {a}`)
			return 1
		end
	end
	if wantZones then
		return printZones()
	end
	local scanRoot = string.gsub(root or ".", "(.)/+$", "%1")
	return check(scanRoot)
end

-- The whole body is wrapped: an internal error must exit non-zero, never fall through to exit 0.
local ok, result = pcall(main, process.args)
if not ok then
	print(`check-guards: internal error: {tostring(result)}`)
	process.exit(1)
elseif result ~= 0 then
	process.exit(1)
end
process.exit(0)
