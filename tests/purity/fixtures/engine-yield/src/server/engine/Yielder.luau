--!strict
-- MUTATION FIXTURE (not shipped code). A pure-zone module that yields in the middle of a state
-- mutation, which CLAUDE.md rule 6 forbids and which selene.pure.toml accepts with 0 errors.
-- scripts/ci/check-guards.luau R3 must reject it. If this fixture ever passes the guard, rule 6 is
-- unenforced again.
local state = { value = 0 }

local function mutate(n: number)
	state.value += n
	coroutine.yield()
	state.value += n
end

local function resume(co: thread)
	coroutine.resume(co)
end

return { mutate = mutate, resume = resume }
