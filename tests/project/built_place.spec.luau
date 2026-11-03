--!strict
-- FOUND-01 / FOUND-03: build the real place, then re-resolve its requires under Roblox rules. Build-then-check
-- runs as part of the normal suite, not as a step someone remembers.
--
-- Every failure-expecting case asserts a distinctive substring of the diagnostic (the REASON), never only a
-- non-zero exit: a checker that failed for the wrong reason would otherwise pass these.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Test = require("../harness/Test")

local PLACE = "build/spoons.rbxl"
local SCRATCH = "build/built-place-spec"
local CHECK = "scripts/ci/check-built-place.luau"

local function check(path: string): process.ExecResult
	return process.exec("lune", { "run", CHECK, path })
end

-- Loads the real built place, lets `mutate` damage it, writes it under SCRATCH and returns the checker result.
local function checkMutated(name: string, mutate: (game: any) -> ()): process.ExecResult
	fs.writeDir(SCRATCH)
	local game: any = roblox.deserializePlace(fs.readFile(PLACE))
	mutate(game)
	local out = `{SCRATCH}/{name}.rbxl`
	fs.writeFile(out, roblox.serializePlace(game))
	return check(out)
end

local function find(game: any, dotted: string): any
	local cur = game
	for part in string.gmatch(dotted, "[^.]+") do
		cur = cur:FindFirstChild(part)
		assert(cur ~= nil, `test setup: {dotted} not found at {part}`)
	end
	return cur
end

return function(t: Test.Runner)
	t.test("FOUND-01 the project assembles", function()
		fs.writeDir("build")
		local r = process.exec("rojo", { "build", "default.project.json", "-o", PLACE })
		t.equal(r.code, 0, r.stdout .. r.stderr)
		t.truthy(fs.isFile(PLACE), "rojo reported success but wrote no place file")
	end)

	t.test("FOUND-03 every pure-zone require re-resolves under Roblox rules", function()
		local r = check(PLACE)
		t.equal(r.code, 0, r.stdout .. r.stderr)
		t.contains(r.stdout, "check-built-place: ok (")
		local count = tonumber(string.match(r.stdout, "ok %((%d+) requires"))
		t.truthy(count ~= nil and count > 0, "the check must report a positive require count")
	end)

	t.test("the checker fails loudly on a missing file", function()
		local r = check("build/does-not-exist.rbxl")
		t.equal(r.code, 1)
		t.contains(r.stdout, "check-built-place: cannot read")
	end)

	t.test("the checker fails loudly on a place with no code (committed empty fixture)", function()
		local r = check("tests/project/fixtures/empty.rbxl")
		t.equal(r.code, 1, "a vacuous check must not read as green")
		t.contains(r.stdout, "ServerScriptService.Server is missing from the built place")
		t.contains(r.stdout, "no literal requires were found")
		t.falsy(string.find(r.stdout, "check-built-place: ok", 1, true) ~= nil, "must not print ok")
	end)

	t.test("a require of a module that does not exist is UNRESOLVED", function()
		local r = checkMutated("unresolved", function(game)
			find(game, "ServerScriptService.Server.core.MapValidator").Source ..= '\nlocal _x = require("./Nope")\n'
		end)
		t.equal(r.code, 1)
		t.contains(r.stdout, 'ServerScriptService.Server.core.MapValidator "./Nope" -> UNRESOLVED under Roblox rules')
		t.contains(r.stdout, "no child named Nope")
	end)

	t.test("a require that reaches a non-ModuleScript is rejected", function()
		local r = checkMutated("notmodule", function(game)
			find(game, "ServerScriptService.Server.core.MapValidator").Source ..= '\nlocal _x = require("../core")\n'
		end)
		t.equal(r.code, 1)
		t.contains(r.stdout, "target is a Folder, not a ModuleScript")
	end)

	t.test("@game requires are banned inside a pure zone", function()
		local r = checkMutated("atgame", function(game)
			find(game, "ServerScriptService.Server.engine.SpikeA").Source ..= '\nlocal _x = require("@game/ServerScriptService/Server/core/MapContract")\n'
		end)
		t.equal(r.code, 1)
		t.contains(r.stdout, "@game requires are banned inside a pure zone")
	end)

	t.test("alias requires are banned in shipped code", function()
		local r = checkMutated("alias", function(game)
			find(game, "ServerScriptService.Server.services.MapLoader").Source ..= '\nlocal _x = require("@lune/fs")\n'
		end)
		t.equal(r.code, 1)
		t.contains(r.stdout, 'MapLoader "@lune/fs" -> alias requires are banned in shipped code')
	end)

	t.test("a require that Roblox resolves but the filesystem does not is a MISMATCH", function()
		local r = checkMutated("mismatch", function(game)
			-- Roblox reaches services.Bucket (moved there); the filesystem has no src/server/services/Bucket.luau.
			find(game, "ServerScriptService.Server.core.Bucket").Parent =
				find(game, "ServerScriptService.Server.services")
			find(game, "ServerScriptService.Server.services.NetServer").Source ..= '\nlocal _x = require("./Bucket")\n'
		end)
		t.equal(r.code, 1)
		t.contains(r.stdout, "FILESYSTEM MISMATCH")
		t.contains(r.stdout, "the filesystem resolver finds no file at src/server/services/Bucket.luau")
	end)

	t.test("a script smuggled under the gray-box map is rejected (T-1-06)", function()
		local r = checkMutated("smuggled", function(game)
			local evil = roblox.Instance.new("Script")
			evil.Name = "Evil"
			evil.Parent = find(game, "ServerStorage.Maps.GrayBox.Geometry")
		end)
		t.equal(r.code, 1)
		t.contains(r.stdout, "ServerStorage.Maps.GrayBox contains a Script: ServerStorage.Maps.GrayBox.Geometry.Evil")
	end)

	t.test("a missing gray-box mount is rejected", function()
		local r = checkMutated("nomap", function(game)
			find(game, "ServerStorage.Maps.GrayBox").Parent = nil
		end)
		t.equal(r.code, 1)
		t.contains(r.stdout, "ServerStorage.Maps.GrayBox is missing from the built place")
	end)
end
