--!strict
-- Property-test driver, injected into Test.new by tests/run.luau as `fuzzDriver`. It imports FuzzOpts from
-- Test.luau (the sole owner of the type); Test.luau never imports from here.
local Rng = require("../../src/server/engine/Rng")
local Test = require("./Test")

export type FuzzOpts = Test.FuzzOpts

local DEFAULT_ITERATIONS = 200

-- Matches Test.FuzzDriver exactly: (name, opts, seed) -> ()
local function driver(name: string, opts: FuzzOpts, seed: number)
	local effectiveSeed = opts.seed or seed
	local iterations = opts.iterations or DEFAULT_ITERATIONS
	local rng = Rng.new(effectiveSeed)
	for i = 1, iterations do
		local genOk, value = pcall(opts.gen :: (any, number) -> any, rng, i)
		if not genOk then
			error(
				string.format(
					"fuzz %q generator failed at iteration %d with seed %d: %s",
					name,
					i,
					effectiveSeed,
					tostring(value)
				),
				0
			)
		end
		local checkOk, err = pcall(opts.check :: (any) -> any, value)
		if not checkOk then
			error(
				string.format("fuzz %q failed at iteration %d with seed %d: %s", name, i, effectiveSeed, tostring(err)),
				0
			)
		end
	end
end

return { driver = driver }
