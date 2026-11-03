--!strict
-- The one luau-lsp gate used by CI and by scripts/verify.luau.
--
--   lune run scripts/ci/analyze.luau <luau-lsp analyze arguments...>
--
-- WHY A WRAPPER. `luau-lsp analyze`'s exit code is NOT a reliable verdict (01-VALIDATION, "detector, settled"):
--   * a MISSING sourcemap exits 0 and prints `[ERROR] Failed to load sourcemap.json`
--   * a MALFORMED sourcemap exits 0 and prints `Sourcemap parsing failed` with NO `[ERROR]` line
--   * real type errors print `TypeError:` and NO `[ERROR]` line
--   * some genuine TypeErrors exit 0 (found in 01-10)
-- So the gate passes only if the exit code is 0 AND the output contains none of the three markers below.
-- `--formatter plain` is refused outright: it always exits 0, which defeats the exit code entirely.
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local MARKERS = { "Failed to load", "Sourcemap parsing failed", "TypeError" }

local function main(args: { string }): number
	local argv = { "analyze" }
	for _, a in args do
		if a == "--" then
			continue
		end
		if string.find(a, "formatter", 1, true) ~= nil then
			stdio.ewrite("analyze: refusing --formatter: `--formatter plain` always exits 0 and defeats the gate\n")
			return 1
		end
		table.insert(argv, a)
	end
	if #argv == 1 then
		stdio.ewrite("analyze: no arguments; refusing to run a gate that analyses nothing\n")
		return 1
	end
	local r = process.exec("luau-lsp", argv)
	local output = r.stdout .. r.stderr
	if output ~= "" then
		stdio.write(output)
		if string.sub(output, -1) ~= "\n" then
			stdio.write("\n")
		end
	end
	if r.code ~= 0 then
		stdio.ewrite(`analyze: FAILED: luau-lsp exited {r.code}\n`)
		return 1
	end
	for _, marker in MARKERS do
		if string.find(output, marker, 1, true) ~= nil then
			stdio.ewrite(`analyze: FAILED: exit code was 0 but the output contains "{marker}"\n`)
			return 1
		end
	end
	print("analyze: ok")
	return 0
end

local ok, result = pcall(main, process.args)
if not ok then
	stdio.ewrite(`analyze: internal error: {tostring(result)}\n`)
	process.exit(1)
end
process.exit(result :: number)
