--!strict
-- FOUND-01 / FOUND-02 file-shape assertions: the committed configs are machine-checked, not eyeballed.
-- The Studio-sync half of FOUND-01 is a human check (MANUAL-CHECKS M-01); this proves the file shape only.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Test = require("../harness/Test")

return function(t: Test.Runner)
	local project = serde.decode("json", fs.readFile("default.project.json"))
	local rokit = serde.decode("toml", fs.readFile("rokit.toml"))
	local luaurc = serde.decode("json", fs.readFile(".luaurc"))

	t.test("FOUND-01 Workspace ignores unknown instances", function()
		t.equal(project.tree.Workspace["$ignoreUnknownInstances"], true)
	end)

	t.test("FOUND-01 Rojo mounts code only", function()
		t.equal(project.tree.ServerScriptService.Server["$path"], "src/server")
		t.equal(project.tree.ReplicatedStorage.Shared["$path"], "src/shared")
		t.equal(project.tree.StarterPlayer.StarterPlayerScripts.Client["$path"], "src/client")
		t.falsy(project.tree.Workspace["$path"], "Workspace must never be a mount")
		t.falsy(project.tree.ServerStorage.Maps["$path"], "Maps must have no $path so Studio drafts survive")
	end)

	t.test("FOUND-01 spec files never sync", function()
		t.contains(table.concat(project.globIgnorePaths, ","), "*.spec.luau")
	end)

	t.test("FOUND-02 toolchain is pinned to exact versions", function()
		t.equal(rokit.tools.rojo, "rojo-rbx/rojo@7.7.1")
		t.equal(rokit.tools.stylua, "JohnnyMorganz/StyLua@2.6.0")
		t.equal(rokit.tools.selene, "Kampfkarren/selene@0.32.0")
		t.equal(rokit.tools["luau-lsp"], "JohnnyMorganz/luau-lsp@1.70.1")
		t.equal(rokit.tools.lune, "lune-org/lune@0.11.1")
		for alias, spec in rokit.tools do
			t.falsy(string.find(spec, "[%^~%*]"), `version range in {alias}`)
		end
	end)

	t.test("FOUND-02 lint and type errors hard-fail (exit-code trap 1)", function()
		t.equal(luaurc.languageMode, "strict")
		t.equal(luaurc.lintErrors, true)
		t.equal(luaurc.typeErrors, true)
	end)

	t.test("vendored Roblox definitions are the pinned copy", function()
		t.equal(#fs.readFile("tools/types/globalTypes.None.d.luau"), 677555)
	end)
end
