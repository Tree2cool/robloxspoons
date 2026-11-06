--!strict
-- The `require` below is a FORBIDDEN import path ("shop" is in forbiddenSegments) and this case
-- expects the rule set to be exactly { "R4" } -- i.e. NO R2. That absence is the assertion: a file
-- under src/client/ui is deliberately not a FOUND-05 guarded root, because Phase 7 needs the card
-- UI to import deck-skin data (CARD-18). If this case ever reports { "R2", "R4" }, the renderer has
-- been made a guarded root and Phase 7 is broken.
local Shop = require("./ShopPanel")
local function connect(remote: any)
	return remote.OnClientEvent:Connect(function() end)
end
return { Shop = Shop, connect = connect }
