--!strict
-- FOUND-06 (CLAUDE.md rule 2): the card engine references no Roblox API. Two layers enforce it and this
-- spec drives the REAL selene and luau-lsp binaries against fixtures to prove each layer can fail:
--   layer 1: selene --config selene.pure.toml (std = "luau" allow-list) rejects Roblox VALUE references
--   layer 2: luau-lsp --platform standard rejects Roblox TYPE references, which selene cannot see
-- Every failure case asserts the diagnostic text as well as the exit code, so a gate that exits non-zero
-- for an unrelated reason cannot pass for the wrong reason.
local fs = require("@lune/fs")
local process = require("@lune/process")

local Test = require("../harness/Test")

local ENGINE_VALUE = "tests/purity/fixtures/engine-roblox-value/src/server/engine"
local ENGINE_TYPE = "tests/purity/fixtures/engine-roblox-type/src/server/engine"
local ENGINE_CLEAN = "tests/purity/fixtures/engine-clean/src/server/engine"

-- Pure zones that must always be covered, whether or not scripts/ci/check-guards.luau has landed yet.
local ALWAYS_PURE = { "src/server/engine" }

local function selenePure(path: string): process.ExecResult
	return process.exec("selene", { "--config", "selene.pure.toml", path })
end

-- No --formatter flag anywhere in this file: the default formatter is the one that exits non-zero.
local function analyzeStandard(path: string): process.ExecResult
	return process.exec("luau-lsp", {
		"analyze",
		"--platform",
		"standard",
		"--base-luaurc",
		".luaurc",
		path,
	})
end

local function split(text: string): { string }
	local out: { string } = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(out, word)
	end
	return out
end

return function(t: Test.Runner)
	t.test("FOUND-06 layer 1: Roblox value reference fails the allow-list lint", function()
		local r = selenePure(ENGINE_VALUE)
		t.falsy(r.ok, "selene must reject `game` in a pure zone")
		t.equal(r.code, 1)
		t.contains(r.stdout .. r.stderr, "undefined_variable")
	end)

	t.test("FOUND-06 layer 2 is necessary: the linter accepts a type-only reference", function()
		local r = selenePure(ENGINE_TYPE)
		t.truthy(r.ok, "selene cannot see type annotations - this is why layer 2 exists: " .. r.stdout .. r.stderr)
		t.contains(r.stdout .. r.stderr, "0 errors")
	end)

	t.test("FOUND-06 layer 2: type-only Roblox reference fails the standard-platform typecheck", function()
		local r = analyzeStandard(ENGINE_TYPE .. "/BadType.luau")
		t.falsy(r.ok, "standard platform must not know the `Instance` type")
		t.equal(r.code, 1)
		t.contains(r.stdout .. r.stderr, "Unknown type 'Instance'")
	end)

	t.test("a clean engine file passes both layers", function()
		local lint = selenePure(ENGINE_CLEAN)
		t.truthy(lint.ok, lint.stdout .. lint.stderr)
		t.contains(lint.stdout .. lint.stderr, "0 errors")
		local types = analyzeStandard(ENGINE_CLEAN .. "/Good.luau")
		t.truthy(types.ok, types.stdout .. types.stderr)
		t.falsy(string.find(types.stdout .. types.stderr, "TypeError", 1, true), types.stdout .. types.stderr)
	end)

	t.test("the real pure zones pass the allow-list lint", function()
		local zones: { string } = {}
		for _, z in ALWAYS_PURE do
			table.insert(zones, z)
		end
		-- scripts/ci/check-guards.luau is owned by plan 01-03 and is the source of truth for the zone list once
		-- it lands. Until then the always-pure list above keeps this case from asserting nothing.
		if fs.isFile("scripts/ci/check-guards.luau") then
			local listed = process.exec("lune", { "run", "scripts/ci/check-guards.luau", "--print-zones" })
			t.truthy(listed.ok, listed.stderr)
			for _, z in split(listed.stdout) do
				table.insert(zones, z)
			end
		end
		local checked = 0
		for _, zone in zones do
			-- Zones created by later plans (src/server/core, src/shared/Net) may not exist yet.
			if fs.isDir(zone) then
				local r = selenePure(zone)
				t.truthy(r.ok, zone .. " must be clean under selene.pure.toml: " .. r.stdout .. r.stderr)
				t.contains(r.stdout .. r.stderr, "0 errors", zone)
				checked += 1
			end
		end
		t.truthy(checked >= 1, "at least src/server/engine must have been checked")
	end)
end
