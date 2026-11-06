--!strict
-- Recording Publisher fake. Every server-to-client publish is appended to a list a spec can inspect,
-- so an audience is asserted from what was actually called rather than from what the router claims.
-- No yields, no Roblox API.
export type Call = {
	method: "toPlayer" | "toSeated" | "toAll",
	userId: number?, -- nil for toSeated / toAll
	kind: string,
	payload: any,
}

-- `leak` is the INJECTED DEFECT (the FakeScheduler.cancelIsNoop idiom): with it set, every call made
-- through `toPlayer` is recorded as a `toAll` broadcast instead. It models a real regression -- a later
-- edit routing a private kind through the public method -- so a privacy gate that cannot see it is
-- proven unable to fire. The fake stays SILENT in leak mode: one that announced its own defect would
-- let a gate pass by reading the announcement instead of the routing.
export type Options = { leak: boolean? }

export type RecordingPublisher = {
	toPlayer: (userId: number, kind: string, payload: unknown) -> (),
	toSeated: (kind: string, payload: unknown) -> (),
	toAll: (kind: string, payload: unknown) -> (),
	-- inspection. calls() returns a COPY: a spec that captured it once and expected it to grow would
	-- be a silent vacuous pass, so re-call it after acting.
	calls: () -> { Call },
	-- toPlayer calls for that userId PLUS every broadcast: "what did this player see" is the question
	-- every CARD-13 assertion asks, and a broadcast is seen by everyone.
	callsTo: (userId: number) -> { Call },
	callsOfKind: (kind: string) -> { Call },
	reset: () -> (),
}

local function new(options: Options?): RecordingPublisher
	local leak = options ~= nil and options.leak == true
	local list: { Call } = {}

	return {
		toPlayer = function(userId: number, kind: string, payload: unknown)
			if leak then
				table.insert(list, { method = "toAll", userId = nil, kind = kind, payload = payload })
			else
				table.insert(list, { method = "toPlayer", userId = userId, kind = kind, payload = payload })
			end
		end,
		toSeated = function(kind: string, payload: unknown)
			table.insert(list, { method = "toSeated", userId = nil, kind = kind, payload = payload })
		end,
		toAll = function(kind: string, payload: unknown)
			table.insert(list, { method = "toAll", userId = nil, kind = kind, payload = payload })
		end,
		calls = function()
			return table.clone(list)
		end,
		callsTo = function(userId: number)
			local out: { Call } = {}
			for _, c in list do
				if c.method ~= "toPlayer" or c.userId == userId then
					table.insert(out, c)
				end
			end
			return out
		end,
		callsOfKind = function(kind: string)
			local out: { Call } = {}
			for _, c in list do
				if c.kind == kind then
					table.insert(out, c)
				end
			end
			return out
		end,
		reset = function()
			table.clear(list)
		end,
	}
end

return { new = new }
