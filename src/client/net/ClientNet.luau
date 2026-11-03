--!strict
-- ClientNet (FOUND-04): the client's only way to talk to the server. It sends INTENTS identified by name,
-- with stable ids inside the payload where one is needed. It never sends a seat index, a hand index or a
-- pass target: the server resolves those at execution time (CLAUDE.md rule 7).
--
-- Do not retry-spam. Above the platform's throttle the excess is DELAYED, not dropped, and the server's
-- token bucket will drop it anyway, so extra sends only build the client's own backlog.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientNet = {}

local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote == nil then
		remote = ReplicatedStorage:WaitForChild("Intent") :: RemoteEvent
	end
	return remote :: RemoteEvent
end

-- `Ping` requires `{ nonce = <integer> }`, so callers pass a real payload. The empty default exists for
-- intents that take none, not as a shortcut.
function ClientNet.send(intentName: string, payload: { [string]: any }?)
	getRemote():FireServer(intentName, payload or {})
end

return ClientNet
