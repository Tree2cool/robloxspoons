--!strict
-- FOUND-01 / FOUND-02 file-shape assertions: the committed configs are machine-checked, not eyeballed.
-- The Studio-sync half of FOUND-01 is a human check (MANUAL-CHECKS M-01); this proves the file shape only.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Environments = require("../../src/shared/Config/Environments")
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

	t.test("FOUND-07 every experience id is recorded, not a placeholder zero", function()
		-- A zero PRODUCTION_UNIVERSE_ID leaves the PersistenceMode Studio tripwire inert: it refuses
		-- only when game.GameId equals it, and no real experience has GameId 0. So a zero here is not
		-- a harmless placeholder, it is a disabled control. Same for the dev ids, which select the
		-- experience that is safe to write to.
		for _, field in { "PRODUCTION_UNIVERSE_ID", "DEV_UNIVERSE_ID", "DEV_PLACE_ID" } do
			local value = (Environments :: any)[field]
			t.equal(type(value), "number", `{field} must be a number`)
			t.truthy(value > 0, `{field} is still a placeholder zero, so its control is inert`)
			t.truthy(value % 1 == 0 and value < 2 ^ 53, `{field} must be an exact integer id`)
		end
	end)

	t.test("FOUND-07 production and dev are separate universes", function()
		-- D-13: data stores are per-experience, so isolation IS the universe split. If these ever
		-- matched, Studio sessions would share live player data and the tripwire would refuse every run.
		t.truthy(
			Environments.PRODUCTION_UNIVERSE_ID ~= Environments.DEV_UNIVERSE_ID,
			"dev and production must be different universes or there is no isolation"
		)
	end)

	t.test("FOUND-07 rojo serve is restricted to the dev place", function()
		-- servePlaceIds is what stops `rojo serve` syncing into the production place by accident.
		-- Asserting it EQUALS the dev place id, not merely that it exists, is what makes the pair
		-- impossible to desync: changing one file without the other fails here.
		t.equal(type(project.servePlaceIds), "table", "servePlaceIds must be present")
		t.equal(#project.servePlaceIds, 1)
		t.equal(project.servePlaceIds[1], Environments.DEV_PLACE_ID)
		for _, id in project.servePlaceIds do
			-- Against the production PLACE id, not the universe id. Those are separate id spaces,
			-- so the original form of this check could never fire however wrong the file got.
			t.truthy(id ~= Environments.PRODUCTION_PLACE_ID, "servePlaceIds must never name the production place")
		end
	end)

	t.test("vendored Roblox definitions are the pinned copy", function()
		-- Hash, not byte length. 01-01-SUMMARY called this file "sha256-pinned" while the only gate
		-- was its length, so any same-length substitution passed. The recorded hash is from the
		-- luau-lsp 1.70.1 tag; it matched the committed file when this check was tightened.
		local body = fs.readFile("tools/types/globalTypes.None.d.luau")
		t.equal(#body, 677555)
		t.equal(serde.hash("sha256", body), "9ad75109b8dc9197f6d1726208bfa0b12de47c3a43672a4fa43227f0cec609ee")
	end)
end
