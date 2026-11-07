--!strict
-- Client boot entry point. Phase 4 boots the card client here: ClientNet.resolve() runs FIRST, because
-- WaitForChild is a yield point and a gameplay message arriving at an unresolved remote is dropped
-- (Pitfall 11). Then the card client subscribes to the card remote, and the Ping stays so the live
-- end-to-end path for the Studio checks M-02 and M-03 still exists.
local ClientNet = require("./net/ClientNet")
local CardClient = require("./ui/CardClient")

ClientNet.resolve()

local client = CardClient.new()
client:start()

ClientNet.send("Ping", { nonce = 1 })
print("[Spoons] client boot: Ping sent")
