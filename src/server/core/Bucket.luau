--!strict
-- Token bucket for the gateway. PURE ZONE: no Roblox API, no yields (CLAUDE.md rule 6).
-- Drops, never queues: a client firing above the Roblox throttle has its excess DELAYED by the
-- platform, not dropped, so a flood becomes a server-side backlog unless the server drops it
-- (research Pitfall 9).
--
-- The clock is injected and measured in seconds. Anything the clock reports that is not a finite,
-- non-negative number, or that is earlier than the bucket's last reading, is a rejection that leaves
-- the bucket untouched: an unchecked clock is a free-token exploit (T-1-28), because an infinite
-- elapsed time refills to the cap.
export type Spec = { burst: number, refillPerSecond: number }
export type Store = {
	take: (self: Store, userId: number, intent: string, spec: Spec) -> boolean,
	forget: (self: Store, userId: number) -> (),
	rejections: (self: Store) -> number,
	count: (self: Store) -> number,
}
export type Deps = { clock: { now: () -> number } }

type Entry = { tokens: number, last: number }

-- NaN is the only number that is not equal to itself; the two infinities are excluded explicitly.
local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function specIsUsable(spec: Spec): boolean
	return isFinite(spec.burst) and isFinite(spec.refillPerSecond) and spec.burst >= 0 and spec.refillPerSecond >= 0
end

local function new(deps: Deps): Store
	local clock = deps.clock
	local state: { [number]: { [string]: Entry } } = {}
	local users = 0
	local rejected = 0

	local function reject(): boolean
		rejected += 1
		return false
	end

	local store: Store = {
		take = function(_self: Store, userId: number, intent: string, spec: Spec): boolean
			-- A NaN user id is not a legal table key (assigning it raises), so it is refused up front.
			if not isFinite(userId) or not specIsUsable(spec) then
				return reject()
			end
			local now = clock.now()
			if not isFinite(now) or now < 0 then
				return reject()
			end

			local perUser = state[userId]
			local existing: Entry? = nil
			if perUser ~= nil then
				existing = perUser[intent]
			end

			local entry: Entry
			if existing == nil then
				-- A bad clock never gets this far, so it never allocates state for a stranger.
				local bucketsForUser: { [string]: Entry }
				if perUser == nil then
					bucketsForUser = {}
					state[userId] = bucketsForUser
					users += 1
				else
					bucketsForUser = perUser
				end
				entry = { tokens = spec.burst, last = now }
				bucketsForUser[intent] = entry
			elseif now < existing.last then
				return reject()
			else
				entry = existing
				entry.tokens = math.min(spec.burst, entry.tokens + (now - entry.last) * spec.refillPerSecond)
				entry.last = now
			end

			if entry.tokens >= 1 then
				entry.tokens -= 1
				return true
			end
			return reject()
		end,

		forget = function(_self: Store, userId: number)
			if state[userId] ~= nil then
				state[userId] = nil
				users -= 1
			end
		end,

		rejections = function(_self: Store): number
			return rejected
		end,

		count = function(_self: Store): number
			return users
		end,
	}
	return store
end

return { new = new }
