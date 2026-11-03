--!strict
-- Client boot entry point. Sends one Ping so there is a live end-to-end path for the Studio checks
-- M-02 and M-03. No UI: that is Phase 4.
local ClientNet = require("./net/ClientNet")

ClientNet.send("Ping", { nonce = 1 })
print("[Spoons] client boot: Ping sent")
