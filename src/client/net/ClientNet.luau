--!strict
-- ClientNet (FOUND-04): the client's only way to talk to the server. It sends INTENTS identified by name,
-- with stable ids inside the payload where one is needed. It never sends a seat index, a hand index or a
-- pass target: the server resolves those at execution time (CLAUDE.md rule 7).
--
-- Do not retry-spam. Above the platform's throttle the excess is DELAYED, not dropped, and the server's
-- token bucket will drop it anyway, so extra sends only build the client's own backlog.
--
-- Pitfall 11: WaitForChild is a YIELD POINT. Both remotes are resolved ONCE at boot (ClientNet.resolve),
-- before any handler is connected, so no gameplay message can arrive at an unresolved remote. V-12
-- guarantees handler START order only, so the receive handler stays synchronous and non-yielding or a
-- slow handler could be overtaken and events folded out of order. Messages that arrive with no connected
-- handler are queued in order up to a bounded limit, then dropped with an error.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientNet = {}

local remote: RemoteEvent? = nil
local cardRemote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote == nil then
		remote = ReplicatedStorage:WaitForChild("Intent") :: RemoteEvent
	end
	return remote :: RemoteEvent
end

-- Idempotent. Call once from Main.client before anything else; populates the same cache `send` uses.
function ClientNet.resolve()
	if remote == nil then
		remote = ReplicatedStorage:WaitForChild("Intent") :: RemoteEvent
	end
	if cardRemote == nil then
		cardRemote = ReplicatedStorage:WaitForChild("Card") :: RemoteEvent
	end
end

-- Errors by name if resolve has not run, rather than lazily yielding inside a Connect call.
function ClientNet.onCard(handler: (kind: string, payload: unknown) -> ()): RBXScriptConnection
	local card = cardRemote
	if card == nil then
		error("ClientNet.onCard called before ClientNet.resolve")
	end
	return card.OnClientEvent:Connect(function(kind: string, payload: unknown)
		-- SYNCHRONOUS: no lookup, no sleeping, no yield of any kind (Pitfall 11 / V-12).
		handler(kind, payload)
	end)
end

-- `Ping` requires `{ nonce = <integer> }`, so callers pass a real payload. The empty default exists for
-- intents that take none, not as a shortcut.
function ClientNet.send(intentName: string, payload: { [string]: any }?)
	getRemote():FireServer(intentName, payload or {})
end

return ClientNet
