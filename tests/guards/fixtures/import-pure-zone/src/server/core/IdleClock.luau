--!strict
-- `IdleClock` matches NO entry in guardedNamePrefixes. It is a guarded root purely because
-- src/server/core is a pure zone (check-guards.luau:341), which is the fact this fixture exists to
-- pin. If someone later "hardens" the prefix list, this case keeps passing and says nothing new --
-- which is correct: the coverage it asserts does not depend on the list.
local Cosmetics = require("./CosmeticsBridge")
return { Cosmetics = Cosmetics }
