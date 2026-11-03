--!strict
-- The single typed gateway (FOUND-04). PURE ZONE: no Roblox API, no yields (CLAUDE.md rule 6).
-- The server derives the actor from the RemoteEvent's player argument; the client never names a
-- seat, a target or a hand index (CLAUDE.md rule 7), so `userId` arrives from the adapter and is
-- never read out of the payload.
--
-- Check order, cheapest first, nothing may be reordered:
--   1. known intent   (type + length + lookup; allocates nothing)
--   2. phase gate     (O(1); allocates nothing)
--   3. token bucket   (charged BEFORE validation, so malformed payloads cost the attacker tokens)
--   4. validate       (the Validate vocabulary; the clean copy it returns is what the handler gets)
--   5. dispatch       (inside xpcall: a throwing handler never escapes handle)
--
-- Rejection codes: UnknownIntent, WrongPhase, RateLimited, HandlerError come from here. A validation
-- rejection surfaces the validator's own code (MissingKey, NotFinite, UnknownKey, NotInteger,
-- OutOfRange, WrongType, ForbiddenType, ...) so a caller and a test can tell WHY it was refused.
export type Code = string

-- D-20 vocabulary, duplicated here DELIBERATELY. `Manifest` lives in `src/shared/Net` and this
-- file lives in `src/server/core`: a relative require between them is a cross-mount require and
-- guard rule R6 fails it. The duplication is made safe by a drift test that asserts
-- `Gateway.PHASES` deep-equals `Manifest.PHASES`. Do not replace the type with `string`.
export type RoundPhase = "Lobby" | "Hide" | "Round" | "Podium"

export type Intent = { phases: { RoundPhase }, validate: (value: unknown) -> (boolean, unknown) }

export type Deps = {
	manifest: { intents: { [string]: Intent }, isKnown: (name: unknown) -> boolean },
	bucket: {
		take: (self: any, userId: number, intent: string, spec: any) -> boolean,
		forget: (self: any, userId: number) -> (),
	},
	rateFor: (intent: string) -> any,
	getPhase: () -> RoundPhase,
	dispatch: (userId: number, intent: string, payload: unknown) -> (),
	onReject: (userId: number, intent: unknown, code: Code) -> (),
	onError: (userId: number, intent: string, err: unknown) -> (),
}

export type Gateway = {
	handle: (self: Gateway, userId: number, intentName: unknown, payload: unknown) -> (boolean, Code),
	forget: (self: Gateway, userId: number) -> (),
}

local PHASES = { "Lobby", "Hide", "Round", "Podium" } :: { RoundPhase }
table.freeze(PHASES)

local function new(deps: Deps): Gateway
	local function reject(userId: number, intentName: unknown, code: Code): (boolean, Code)
		deps.onReject(userId, intentName, code)
		return false, code
	end

	local gateway: Gateway = {
		handle = function(_self: Gateway, userId: number, intentName: unknown, payload: unknown): (boolean, Code)
			-- 1. known intent
			if not deps.manifest.isKnown(intentName) then
				return reject(userId, intentName, "UnknownIntent")
			end
			local name = intentName :: string
			local intent = deps.manifest.intents[name]

			-- 2. phase gate
			local phase = deps.getPhase()
			local inPhase = false
			for _, allowed in intent.phases do
				if allowed == phase then
					inPhase = true
					break
				end
			end
			if not inPhase then
				return reject(userId, name, "WrongPhase")
			end

			-- 3. token bucket (charged before validation)
			if not deps.bucket:take(userId, name, deps.rateFor(name)) then
				return reject(userId, name, "RateLimited")
			end

			-- 4. payload validation
			local ok, clean = intent.validate(payload)
			if not ok then
				return reject(userId, name, if type(clean) == "string" then clean else "Malformed")
			end

			-- 5. dispatch the CLEAN copy, contained
			local caught: unknown = nil
			local success = xpcall(function(): ()
				deps.dispatch(userId, name, clean)
			end, function(e: unknown): ()
				caught = e
			end)
			if not success then
				deps.onError(userId, name, caught)
				return reject(userId, name, "HandlerError")
			end
			return true, "Ok"
		end,

		forget = function(_self: Gateway, userId: number)
			deps.bucket:forget(userId)
		end,
	}
	return gateway
end

return { new = new, PHASES = PHASES }
