--!strict
-- Require-style canary. Proves `./Sibling` resolves identically under Lune (filesystem) and the
-- Roblox runtime (DataModel), which is what lets the engine be tested headless (FOUND-03).
-- Only `./`, `../` and `@self/` string requires are legal in this directory.
local SpikeB = require("./SpikeB")

export type Spike = { value: number }

local SpikeA: Spike = { value = SpikeB.value }

return SpikeA
