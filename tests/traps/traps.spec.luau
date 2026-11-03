--!strict
-- Executable proof of the exit-code traps behind D-01 ("every check hard-fails"). Each case invokes the REAL
-- CLI and asserts BOTH the exit code AND the diagnostic text. A bare "exits 1" is exactly what a working gate
-- and a gate broken for an unrelated reason have in common, so the reason is always asserted too.
--
--   TRAP 1: .luaurc must set lintErrors true or luau-lsp lint findings exit 0
--   TRAP 2: --formatter plain always exits 0, even with errors
--   TRAP 3: luau-lsp never downloads Roblox definitions; --definitions and --platform are load-bearing
--   TRAP 4: a failed or unparseable sourcemap load does NOT fail `luau-lsp analyze` (found by executing 01-01)
--
-- Fixtures sit under tests/traps/fixtures/** (invisible to stylua, selene and the default test sweep).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Test = require("../harness/Test")

local DEFS = "--definitions=tools/types/globalTypes.None.d.luau"
local SCRATCH = "build/01-04"

-- Run luau-lsp analyze with the DEFAULT formatter unless the case under test is the --formatter one.
local function analyze(args: { string }): process.ExecResult
	local argv = { "analyze" }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("luau-lsp", argv)
end

local function out(r: process.ExecResult): string
	return r.stdout .. r.stderr
end

local function countPlain(haystack: string, needle: string): number
	local count = 0
	local from = 1
	while true do
		local s, e = string.find(haystack, needle, from, true)
		if s == nil then
			return count
		end
		count += 1
		from = (e :: number) + 1
	end
end

-- The banned flag in any spelling a gate file could use.
local function usesPlainFormatter(text: string): boolean
	return string.find(text, "%-%-formatter[%s=]+plain") ~= nil
end

local function listFiles(dir: string): { string }
	local files: { string } = {}
	if fs.isDir(dir) then
		for _, name in fs.readDir(dir) do
			local path = `{dir}/{name}`
			if fs.isFile(path) then
				table.insert(files, path)
			end
		end
	end
	return files
end

return function(t: Test.Runner)
	t.test("TRAP 1: lintErrors true makes a lint-only finding exit non-zero", function()
		local r = analyze({ "--platform", "standard", "tests/traps/fixtures/lint-only/Lint.luau" })
		t.falsy(r.ok, "lint finding must hard-fail: " .. out(r))
		t.equal(r.code, 1)
		t.contains(out(r), "LocalUnused")
		t.falsy(string.find(out(r), "TypeError", 1, true), "fixture must be lint-only, no type error: " .. out(r))
	end)

	t.test("TRAP 1 counter-case: lintErrors false lets the same file pass", function()
		-- Luau walks UP from the analysed file and the nearest .luaurc wins, so the fixture's own .luaurc overrides
		-- the repo-root one. (--base-luaurc would lose to the root file, which is why it is not used here.)
		local r = analyze({ "--platform", "standard", "tests/traps/fixtures/lint-only-disabled/Lint.luau" })
		t.truthy(r.ok, "proves `lintErrors: true` in .luaurc is what hard-fails the gate: " .. out(r))
		t.equal(r.code, 0)
		-- The lint is still REPORTED, so the exit code differs only because of lintErrors, not because the lint is off.
		t.contains(out(r), "LocalUnused")
		-- And the nested config really was the one consulted.
		-- Normalise separators: Windows luau-lsp prints "lint-only-disabled\\.luaurc".
		t.contains((out(r):gsub("\\", "/")), "lint-only-disabled/.luaurc")
		t.equal(
			fs.readFile("tests/traps/fixtures/lint-only/Lint.luau"),
			fs.readFile("tests/traps/fixtures/lint-only-disabled/Lint.luau"),
			"the two fixtures must be byte-identical; only the .luaurc may differ"
		)
	end)

	t.test("TRAP 1: the committed .luaurc sets lintErrors and typeErrors true", function()
		local cfg = serde.decode("json", fs.readFile(".luaurc"))
		t.equal(cfg.lintErrors, true)
		t.equal(cfg.typeErrors, true)
	end)

	t.test("TRAP 2: the default formatter exits non-zero on a type error", function()
		local r = analyze({ "--platform", "standard", "tests/traps/fixtures/type-error/TypeError.luau" })
		t.falsy(r.ok, "type error must hard-fail: " .. out(r))
		t.equal(r.code, 1)
		t.contains(out(r), "TypeError: Expected this to be 'number', but got 'string'")
	end)

	t.test("TRAP 2: --formatter plain exits ZERO on the same type error", function()
		local r = analyze({
			"--platform",
			"standard",
			"--formatter",
			"plain",
			"tests/traps/fixtures/type-error/TypeError.luau",
		})
		t.truthy(r.ok, "this is why --formatter plain is banned from every gate: " .. out(r))
		t.equal(r.code, 0)
		-- The error IS printed (as a warning, `(W0)`), which is what makes the exit code so deceptive.
		t.contains(out(r), "(W0) TypeError")
	end)

	t.test("TRAP 2: no gate file uses --formatter plain", function()
		-- The detector must be proven able to match, or an empty scan reads as green.
		t.truthy(usesPlainFormatter("luau-lsp analyze --formatter plain src"))
		t.truthy(usesPlainFormatter("luau-lsp analyze --formatter=plain src"))
		t.falsy(usesPlainFormatter("luau-lsp analyze --platform standard src"))

		local gateFiles = { ".github/workflows/ci.yml", "scripts/verify.luau", ".githooks/pre-commit" }
		for _, f in listFiles(".github/workflows") do
			table.insert(gateFiles, f)
		end
		for _, f in listFiles(".githooks") do
			table.insert(gateFiles, f)
		end
		-- Gate files land in later plans (01-10, 01-11); whatever exists at any point in time must be clean.
		for _, path in gateFiles do
			if fs.isFile(path) then
				t.falsy(usesPlainFormatter(fs.readFile(path)), path .. " must not use --formatter plain")
			end
		end
	end)

	t.test("TRAP 3: with vendored definitions, a bogus Roblox member is an error", function()
		local r = analyze({ "--platform", "roblox", DEFS, "tests/traps/fixtures/roblox-member/Member.luau" })
		t.falsy(r.ok, "member checking requires the vendored definitions: " .. out(r))
		t.equal(r.code, 1)
		t.contains(out(r), "Key 'ThisMemberDoesNotExist' not found in external type 'Part'")
	end)

	t.test("TRAP 3: without definitions, the verdict changes and the member is never checked", function()
		local r = analyze({ "--platform", "roblox", "tests/traps/fixtures/roblox-member/Member.luau" })
		-- Divergence from research: for a file that touches `Instance`, the run does not pass silently, it fails for
		-- a DIFFERENT reason (the global itself is unknown) and prints the explicit no-download warning.
		t.falsy(r.ok, out(r))
		t.contains(out(r), "does not download definitions files")
		t.contains(out(r), "Unknown global 'Instance'")
		t.falsy(
			string.find(out(r), "ThisMemberDoesNotExist", 1, true),
			"without --definitions the member is unchecked: " .. out(r)
		)
	end)

	t.test("TRAP 3: omitting --platform standard accepts a Roblox type in a pure zone", function()
		local r = analyze({
			DEFS,
			"--base-luaurc",
			".luaurc",
			"tests/purity/fixtures/engine-roblox-type/src/server/engine/BadType.luau",
		})
		t.truthy(r.ok, "default platform is roblox, so `Instance` resolves: " .. out(r))
		t.equal(r.code, 0)
		t.falsy(string.find(out(r), "Unknown type", 1, true), out(r))

		-- Same file, same config, only --platform standard added: the verdict flips.
		local strict = analyze({
			"--platform",
			"standard",
			"--base-luaurc",
			".luaurc",
			"tests/purity/fixtures/engine-roblox-type/src/server/engine/BadType.luau",
		})
		t.falsy(strict.ok, "the purity run MUST pass --platform standard: " .. out(strict))
		t.contains(out(strict), "Unknown type 'Instance'")
	end)

	t.test("TRAP 3: the vendored definitions file is present and pinned", function()
		t.equal(#fs.readFile("tools/types/globalTypes.None.d.luau"), 677555)
	end)

	t.test("TRAP 4: a MISSING sourcemap prints an [ERROR] yet still exits 0", function()
		fs.writeDir(SCRATCH)
		local r = analyze({
			"--platform",
			"roblox",
			"--sourcemap",
			`{SCRATCH}/does-not-exist.json`,
			DEFS,
			"tests/purity/fixtures/engine-clean/src/server/engine/Good.luau",
		})
		t.truthy(r.ok, "this is the trap: the check degrades and still reports green: " .. out(r))
		t.equal(r.code, 0)
		t.contains(out(r), "[ERROR] Failed to load")
		t.contains(out(r), "for workspace 'CLI'")
		t.equal(countPlain(out(r), "[ERROR]"), 1)
	end)

	t.test("TRAP 4: an UNPARSEABLE sourcemap exits 0 and prints NO [ERROR] line", function()
		fs.writeDir(SCRATCH)
		fs.writeFile(`{SCRATCH}/malformed.json`, "{ this is not json\n")
		local r = analyze({
			"--platform",
			"roblox",
			"--sourcemap",
			`{SCRATCH}/malformed.json`,
			DEFS,
			"tests/purity/fixtures/engine-clean/src/server/engine/Good.luau",
		})
		t.truthy(r.ok, out(r))
		t.equal(r.code, 0)
		-- Divergence: this failure mode is NOT marked [ERROR]. A gate that only counts [ERROR] lines misses it.
		t.contains(out(r), "Sourcemap parsing failed, sourcemap is not loaded")
		t.equal(countPlain(out(r), "[ERROR]"), 0, "an [ERROR]-only detector would read this as healthy")
	end)

	t.test("TRAP 4 control: a valid sourcemap loads with no [ERROR] and no parse failure", function()
		fs.writeDir(SCRATCH)
		fs.writeFile(`{SCRATCH}/valid.json`, '{"name":"game","className":"DataModel","children":[]}\n')
		local r = analyze({
			"--platform",
			"roblox",
			"--sourcemap",
			`{SCRATCH}/valid.json`,
			DEFS,
			"tests/purity/fixtures/engine-clean/src/server/engine/Good.luau",
		})
		t.truthy(r.ok, out(r))
		t.equal(countPlain(out(r), "[ERROR]"), 0, out(r))
		t.falsy(string.find(out(r), "Sourcemap parsing failed", 1, true), out(r))
		t.falsy(string.find(out(r), "Failed to load", 1, true), out(r))
	end)

	t.test("CI gate: stylua --check rejects badly formatted Luau", function()
		-- A real file at a path NEITHER .styluaignore NOR selene's exclude covers, so a pass here
		-- cannot be an ignore rule rather than a clean file. stdin was tried first (01-04) but does
		-- not deliver under Lune on Windows: the tool receives nothing and exits 0, which reads as
		-- a passing gate. Found by the 01-11 fresh-clone rehearsal on a real Windows machine.
		local dir = "tests/traps/cigate"
		local path = dir .. "/Bad.luau"
		fs.writeDir(dir)
		local ran, err = pcall(function()
			fs.writeFile(path, "local x    =1\nreturn x\n")
			local r = process.exec("stylua", { "--check", path })
			t.falsy(r.ok, "stylua --check must reject this: " .. out(r))
			t.equal(r.code, 1)
			-- Control: same tool, same mode, well-formatted input passes, so the rejection is about formatting.
			fs.writeFile(path, "local x = 1\nreturn x\n")
			local good = process.exec("stylua", { "--check", path })
			t.truthy(good.ok, out(good))
		end)
		fs.removeDir(dir)
		if not ran then
			error(err, 0)
		end
	end)

	t.test("CI gate: selene with the Roblox std rejects an undefined global", function()
		-- Same reasoning as the stylua case: a real file outside every exclude, not stdin.
		local dir = "tests/traps/cigate"
		local path = dir .. "/Bad.luau"
		fs.writeDir(dir)
		local ran, err = pcall(function()
			fs.writeFile(path, "--!strict\nlocal y = someGlobalThatDoesNotExist\nreturn y\n")
			local r = process.exec("selene", { path })
			t.falsy(r.ok, "selene must reject this: " .. out(r))
			t.equal(r.code, 1)
			t.contains(out(r), "undefined_variable")
			t.contains(out(r), "someGlobalThatDoesNotExist")
			-- Control: clean input passes AND the Roblox std is genuinely active (`game` is known here,
			-- unlike in a pure zone under selene.pure.toml).
			fs.writeFile(path, '--!strict\nlocal p = game:GetService("Players")\nreturn p\n')
			local good = process.exec("selene", { path })
			t.truthy(good.ok, "the roblox std must accept `game`: " .. out(good))
		end)
		fs.removeDir(dir)
		if not ran then
			error(err, 0)
		end
	end)
end
