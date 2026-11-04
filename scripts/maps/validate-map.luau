--!strict
-- validate-map: the CI / dev CLI for the MAP-01 contract.
--
--   lune run scripts/maps/validate-map.luau maps/gray-box.rbxm
--
-- Reads the .rbxm, snapshots it into plain data and runs the same pure validator the server uses at runtime.
-- Prints one line per issue as `<CODE> <path> <message>` and exits 1 if there are any (or if the file cannot be
-- read or does not hold exactly one root); otherwise prints `validate-map: ok (<n> spots, <n> seats)` and exits 0.
--
-- The shipped placement numbers are injected here, because the pure validator may not require across the Rojo
-- mount boundary (R6); the runtime loader injects the same table through the DataModel path.
local process = require("@lune/process")

local MapValidator = require("../../src/server/core/MapValidator")
local Placement = require("../../src/shared/Config/Placement")
local Snapshot = require("./snapshot")

local function main()
	local args: { string } = {}
	for _, a in process.args do
		-- Lune 0.11.1 passes a literal "--" separator through (found in plan 01-02); tolerate it.
		if a ~= "--" then
			table.insert(args, a)
		end
	end
	local path = args[1]
	if path == nil or #args ~= 1 then
		print("usage: lune run scripts/maps/validate-map.luau <path-to.rbxm>")
		process.exit(1)
		return
	end

	local root, reason = Snapshot.loadFile(path)
	if root == nil then
		print(`validate-map: {reason or "unknown error"}`)
		process.exit(1)
		return
	end

	local issues, spec = MapValidator.validate(root, Placement)
	if #issues > 0 or spec == nil then
		for _, issue in issues do
			print(`{issue.code} {issue.path} {issue.message}`)
		end
		print(`validate-map: FAILED with {#issues} issue(s)`)
		process.exit(1)
		return
	end
	print(`validate-map: ok ({#spec.defaultSpots} spots, {#spec.cardTable.seats} seats)`)
end

main()
