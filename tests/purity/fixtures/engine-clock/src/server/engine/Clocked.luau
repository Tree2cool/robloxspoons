--!strict
-- MUTATION FIXTURE (not shipped code). A pure-zone module that reads a real clock, which
-- CLAUDE.md rule 5 forbids (the server is the only clock, in integer deciseconds supplied from
-- outside) and which selene.pure.toml accepts with 0 errors.
-- scripts/ci/check-guards.luau R3 must reject it.
local function stamp(): number
	return os.clock()
end

local function wall(): number
	return os.time()
end

return { stamp = stamp, wall = wall }
