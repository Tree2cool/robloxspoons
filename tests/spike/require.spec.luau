--!strict
-- Lune half of the require-style spike (V-4). The Roblox half is the built-place re-resolution in plan
-- 01-10; the Studio half is MANUAL-CHECKS M-02.
local SpikeA = require("../../src/server/engine/SpikeA")

local Test = require("../harness/Test")

return function(t: Test.Runner)
	t.test("FOUND-03 relative string requires resolve under Lune", function()
		t.equal(SpikeA.value, 42)
	end)
end
