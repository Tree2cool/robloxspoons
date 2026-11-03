--!strict
-- check-built-place: re-resolves every literal require in the BUILT place under Roblox's rules.
--
--   lune run scripts/ci/check-built-place.luau build/spoons.rbxl [--verbose]
--
-- Lune resolving a require proves nothing about Roblox resolving it. This reads the real artefact `rojo build`
-- produced and walks the DataModel the way Roblox's require-by-string does:
--   ./x    starts at script.Parent        ../x   starts at script.Parent, then steps to its parent
--   @self/ starts at the script itself    @game/ starts at the DataModel
--   each further component is a child; `..` is a parent; the target must exist AND be a ModuleScript.
-- Custom .luaurc aliases are undocumented for the Roblox runtime, so any other `@alias/` is a failure.
--
-- Every resolution is cross-checked against the filesystem resolver (the file Lune would load), which must map
-- back to the same DataModel instance. This is the automated half of FOUND-03; the other half is manual M-02.
--
-- Exit 0 and `check-built-place: ok (<n> requires in <m> modules)`, or one line per failure and exit 1. Zero
-- requires found is a failure: it would mean the walk is looking in the wrong place and the check is vacuous.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local lex = require("./lex")
local zones = require("./zones")

type Inst = roblox.Instance
type Mount = { path: { string }, dm: { string } }

local SCRIPT_CLASSES: { [string]: boolean } = { ModuleScript = true, Script = true, LocalScript = true }

local function split(s: string, sep: string): { string }
	local out: { string } = {}
	for part in string.gmatch(s, "[^" .. sep .. "]+") do
		table.insert(out, part)
	end
	return out
end

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

local function isPrefix(prefix: { string }, list: { string }): boolean
	if #prefix > #list then
		return false
	end
	for i, v in prefix do
		if list[i] ~= v then
			return false
		end
	end
	return true
end

local function sameList(a: { string }, b: { string }): boolean
	return #a == #b and isPrefix(a, b)
end

-- ----------------------------------------------------------------------------------------------------------
-- Mounts, from the same default.project.json Rojo built the place from
-- ----------------------------------------------------------------------------------------------------------

local function collectMounts(node: any, names: { string }, out: { Mount })
	if type(node) ~= "table" then
		return
	end
	local pathValue = (node :: { [string]: any })["$path"]
	if type(pathValue) == "string" then
		table.insert(out, { path = split(string.gsub(pathValue, "/+$", ""), "/"), dm = table.clone(names) })
	end
	for key, child in node :: { [string]: any } do
		if type(key) == "string" and string.sub(key, 1, 1) ~= "$" and type(child) == "table" then
			local nextNames = table.clone(names)
			table.insert(nextNames, key)
			collectMounts(child, nextNames, out)
		end
	end
end

local function loadMounts(): { Mount }
	local project = serde.decode("json", fs.readFile("default.project.json")) :: any
	local mounts: { Mount } = {}
	collectMounts(project.tree, {}, mounts)
	-- Only code mounts: the .rbxm map mount is a file, not a directory of scripts.
	local code: { Mount } = {}
	for _, m in mounts do
		if not string.find(table.concat(m.path, "/"), "%.rbxm$") then
			table.insert(code, m)
		end
	end
	return code
end

-- ----------------------------------------------------------------------------------------------------------
-- DataModel helpers
-- ----------------------------------------------------------------------------------------------------------

local function dmPathOf(inst: Inst): { string }
	local names: { string } = {}
	local cur: Inst? = inst
	while cur ~= nil and cur.ClassName ~= "DataModel" do
		table.insert(names, 1, cur.Name)
		cur = cur.Parent
	end
	return names
end

local function dmLookup(game: Inst, names: { string }): Inst?
	local cur: Inst? = game
	for _, name in names do
		if cur == nil then
			return nil
		end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

-- Roblox resolution. Returns the instance or nil plus the reason it could not be reached.
local function resolveRoblox(game: Inst, script: Inst, target: string): (Inst?, string?)
	local rest: string
	local cur: Inst?
	if startsWith(target, "@self/") then
		cur = script
		rest = string.sub(target, 7)
	elseif startsWith(target, "@game/") then
		cur = game
		rest = string.sub(target, 7)
	elseif startsWith(target, "./") or startsWith(target, "../") then
		cur = script.Parent
		rest = target
	else
		return nil, "unsupported require form (aliases and bare names are undocumented for the Roblox runtime)"
	end
	for _, part in split(rest, "/") do
		if cur == nil then
			return nil, "walk left the DataModel"
		end
		if part == "." then
			continue
		elseif part == ".." then
			-- Lune types Parent as non-nil, but a DataModel root has none.
			local parent: Inst? = cur.Parent :: Inst?
			if parent == nil then
				return nil, "`..` stepped above the DataModel root"
			end
			cur = parent
		else
			local nextInst = cur:FindFirstChild(part)
			if nextInst == nil then
				return nil, `no child named {part} under {table.concat(dmPathOf(cur), ".")}`
			end
			cur = nextInst
		end
	end
	if cur == nil then
		return nil, "walk left the DataModel"
	end
	if cur.ClassName ~= "ModuleScript" then
		return nil, `target is a {cur.ClassName}, not a ModuleScript`
	end
	return cur, nil
end

-- ----------------------------------------------------------------------------------------------------------
-- Filesystem twin: the file Lune would load for the same require from the same module
-- ----------------------------------------------------------------------------------------------------------

local FILE_SUFFIXES = { ".luau", ".server.luau", ".client.luau", ".lua" }

-- Maps a DataModel path to the on-disk file backing it. Returns (file, isInit) or nil.
local function diskFileOf(mounts: { Mount }, dm: { string }): (string?, boolean)
	for _, m in mounts do
		if isPrefix(m.dm, dm) then
			local parts = table.clone(m.path)
			for i = #m.dm + 1, #dm do
				table.insert(parts, dm[i])
			end
			local base = table.concat(parts, "/")
			for _, suffix in FILE_SUFFIXES do
				if fs.isFile(base .. suffix) then
					return base .. suffix, false
				end
				if fs.isFile(base .. "/init" .. suffix) then
					return base .. "/init" .. suffix, true
				end
			end
		end
	end
	return nil, false
end

-- Maps a disk file back to a DataModel path through the mounts.
local function dmOfDiskFile(mounts: { Mount }, file: string): { string }?
	local parts = split(file, "/")
	local last = parts[#parts] or ""
	local isInit = string.match(last, "^init%.") ~= nil
	if isInit then
		table.remove(parts)
	else
		parts[#parts] = (string.gsub(string.gsub(last, "%.luau$", ""), "%.lua$", "")) :: string
		for _, suffix in { ".server", ".client" } do
			if string.sub(parts[#parts], -#suffix) == suffix then
				parts[#parts] = string.sub(parts[#parts], 1, -#suffix - 1)
			end
		end
	end
	for _, m in mounts do
		if isPrefix(m.path, parts) then
			local dm = table.clone(m.dm)
			for i = #m.path + 1, #parts do
				table.insert(dm, parts[i])
			end
			return dm
		end
	end
	return nil
end

-- Returns the DataModel path the filesystem resolver reaches, or nil plus a reason.
local function resolveDisk(
	mounts: { Mount },
	srcFile: string,
	srcIsInit: boolean,
	target: string
): ({ string }?, string?)
	local dir = split(srcFile, "/")
	table.remove(dir) -- the file name
	local rest = target
	if startsWith(target, "@self/") then
		rest = string.sub(target, 7)
	elseif srcIsInit then
		-- An init module IS its directory, so `./` starts one level up (Luau require-by-string rule).
		table.remove(dir)
	end
	for _, part in split(rest, "/") do
		if part == "." then
			continue
		elseif part == ".." then
			if #dir == 0 then
				return nil, "filesystem walk left the repository"
			end
			table.remove(dir)
		else
			table.insert(dir, part)
		end
	end
	local base = table.concat(dir, "/")
	for _, candidate in { base .. ".luau", base .. "/init.luau" } do
		if fs.isFile(candidate) then
			local dm = dmOfDiskFile(mounts, candidate)
			if dm == nil then
				return nil, `{candidate} exists on disk but is not under any Rojo mount`
			end
			return dm, nil
		end
	end
	return nil, `the filesystem resolver finds no file at {base}.luau or {base}/init.luau`
end

-- ----------------------------------------------------------------------------------------------------------

local function main()
	local verbose = false
	local args: { string } = {}
	for _, a in process.args do
		if a == "--verbose" then
			verbose = true
		elseif a ~= "--" then
			table.insert(args, a)
		end
	end
	local path = args[1]
	if path == nil or #args ~= 1 then
		print("usage: lune run scripts/ci/check-built-place.luau <built-place.rbxl> [--verbose]")
		process.exit(1)
		return
	end

	local readOk, contents = pcall(fs.readFile, path)
	if not readOk then
		print(`check-built-place: cannot read {path}`)
		process.exit(1)
		return
	end
	local parseOk, parsed = pcall(roblox.deserializePlace, contents :: string)
	if not parseOk then
		print(`check-built-place: cannot parse {path} as a place: {string.match(tostring(parsed), "^[^\n]*")}`)
		process.exit(1)
		return
	end
	local game = parsed :: Inst

	local mounts = loadMounts()
	local failures: { string } = {}
	local function fail(message: string)
		table.insert(failures, message)
	end

	-- Pure zones, as DataModel paths. Zone directories are mapped through the same mounts as scripts.
	local zoneDms: { { string } } = {}
	for _, zone in zones.pureZones do
		local zoneParts = split(zone, "/")
		for _, m in mounts do
			if isPrefix(m.path, zoneParts) then
				local dm = table.clone(m.dm)
				for i = #m.path + 1, #zoneParts do
					table.insert(dm, zoneParts[i])
				end
				table.insert(zoneDms, dm)
			end
		end
	end
	local function inPureZone(dm: { string }): boolean
		for _, z in zoneDms do
			if isPrefix(z, dm) then
				return true
			end
		end
		return false
	end

	local requireCount = 0
	local moduleCount = 0

	for _, mount in mounts do
		local root = dmLookup(game, mount.dm)
		if root == nil then
			fail(
				`{table.concat(mount.dm, ".")} is missing from the built place (expected mount of {table.concat(
					mount.path,
					"/"
				)})`
			)
			continue
		end
		local nodes: { Inst } = { root }
		for _, d in root:GetDescendants() do
			table.insert(nodes, d)
		end
		for _, script in nodes do
			if SCRIPT_CLASSES[script.ClassName] ~= true then
				continue
			end
			moduleCount += 1
			local scriptDm = dmPathOf(script)
			local scriptName = table.concat(scriptDm, ".")
			local source = (script :: any).Source
			if type(source) ~= "string" then
				fail(`{scriptName}: Source is not readable from the built place`)
				continue
			end
			local pure = inPureZone(scriptDm)
			local diskFile, diskIsInit = diskFileOf(mounts, scriptDm)
			local literals = lex.extractRequires(lex.stripComments(source))
			for _, req in literals do
				requireCount += 1
				local target = req.target
				if string.sub(target, 1, 1) == "@" and not startsWith(target, "@self/") then
					if startsWith(target, "@game/") and pure then
						fail(`{scriptName} "{target}" -> @game requires are banned inside a pure zone`)
						continue
					elseif not startsWith(target, "@game/") then
						fail(`{scriptName} "{target}" -> alias requires are banned in shipped code`)
						continue
					end
				end
				local resolved, reason = resolveRoblox(game, script, target)
				if resolved == nil then
					fail(`{scriptName} "{target}" -> UNRESOLVED under Roblox rules: {reason}`)
					continue
				end
				local resolvedDm = dmPathOf(resolved)
				if verbose then
					print(`{scriptName} "{target}" -> {table.concat(resolvedDm, ".")}`)
				end
				if startsWith(target, "@game/") then
					continue -- absolute DataModel paths have no filesystem twin
				end
				if diskFile == nil then
					fail(`{scriptName} "{target}" -> built script has no backing file on disk`)
					continue
				end
				local diskDm, diskReason = resolveDisk(mounts, diskFile, diskIsInit, target)
				if diskDm == nil then
					fail(`{scriptName} "{target}" -> FILESYSTEM MISMATCH: {diskReason}`)
				elseif not sameList(diskDm, resolvedDm) then
					fail(
						`{scriptName} "{target}" -> FILESYSTEM MISMATCH: Roblox reaches {table.concat(resolvedDm, ".")} but the filesystem reaches {table.concat(
							diskDm,
							"."
						)}`
					)
				end
			end
		end
	end

	-- FOUND-01 shape check on the artefact: the gray-box map is mounted and carries no code anywhere.
	local grayBox = dmLookup(game, { "ServerStorage", "Maps", "GrayBox" })
	if grayBox == nil then
		fail("ServerStorage.Maps.GrayBox is missing from the built place")
	else
		for _, d in grayBox:GetDescendants() do
			if SCRIPT_CLASSES[d.ClassName] == true then
				fail(`ServerStorage.Maps.GrayBox contains a {d.ClassName}: {table.concat(dmPathOf(d), ".")}`)
			end
		end
	end

	if requireCount == 0 then
		fail("no literal requires were found in any mounted module: the check would be vacuous")
	end

	if #failures > 0 then
		for _, line in failures do
			print(line)
		end
		print(`check-built-place: FAILED with {#failures} problem(s)`)
		process.exit(1)
		return
	end
	print(`check-built-place: ok ({requireCount} requires in {moduleCount} modules)`)
end

main()
