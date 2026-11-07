--!strict
-- Server-side seat hold for a seated seeker (UX-02, CARD-17; D-15, D-29, D-30). Bookkeeping over
-- injected effects: this file decides WHAT happens and in WHICH ORDER, and the service decides HOW.
--
--  1. PURE ZONE. Every effect is injected and no Roblox type is named; a Pose is plain numbers. That is
--     what makes the ordering and idempotence assertions runnable in Lune.
--  2. THIS IS THE LAYER WHERE ENFORCEMENT IS ATTEMPTED, and the client half is not even that. The
--     properties are set by the server, which is necessary, but whether they actually hold an avatar
--     against a determined client is UNPROVEN and is manual check M-11 (assumption A2). A cheat client
--     may re-enable its own controls and walk off to hunt before completing a set; find order drives
--     SCORE-01..03 and there are two fewer spoons than players, so that would be a direct exploit.
--     src/shared/Card/Controls.luau is ergonomics only.
--  3. D-30: release restores capability BEFORE control. Reversed, the finisher's first frames of input
--     hit a zero-speed humanoid, a visible stutter on the one action a score depends on.
--  4. Hold stops before it places. Otherwise the player could walk out of the chair in the gap.
--  5. Both operations are idempotent, because completion, bench, disconnect and round end can all fire
--     for the same player, sometimes in the same frame.
--  6. A respawn re-applies the freeze but NOT the movement mode: the movement mode is a property of the
--     Player and survives a respawn, while humanoid properties come back at their defaults.
--  7. `forget` fires no effect. There is no avatar to restore, and touching a departed Player is how a
--     service leaks a reference.
--  8. The mechanism (movement mode set to scriptable, zeroed humanoid, a pivot) is assumption A2 and is
--     unverified. The seam exists so it is swappable. Rejected: anchoring the root part (fights the
--     physics solver), a real seated state (needs the map seats converted, a Phase 6 map-contract
--     change, and is the recorded NEXT ATTEMPT), and a physics state change (undocumented under the
--     input-system migration). A second fallback after that: a server-side position check returning a
--     wandering seated avatar to its anchor. M-11 is where this is checked.
export type Vec3 = { x: number, y: number, z: number }
export type Pose = { position: Vec3, look: Vec3 }

-- `pivotTo` returns false when the player has no character yet, which is ordinary at round start: the
-- pose stays queued and is applied on the next character arrival.
export type Effects = {
	setMovementScriptable: (playerId: number, scriptable: boolean) -> (),
	freezeHumanoid: (playerId: number, frozen: boolean) -> (),
	pivotTo: (playerId: number, pose: Pose) -> boolean,
	onTelemetry: (name: string, data: { [string]: number }) -> (),
}

export type CardSeatHold = {
	hold: (self: CardSeatHold, playerId: number, pose: Pose) -> (),
	release: (self: CardSeatHold, playerId: number) -> (),
	onCharacterAdded: (self: CardSeatHold, playerId: number) -> (),
	forget: (self: CardSeatHold, playerId: number) -> (),
	releaseAll: (self: CardSeatHold) -> (),
	isHeld: (self: CardSeatHold, playerId: number) -> boolean,
	heldCount: (self: CardSeatHold) -> number,
}

local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function checkId(playerId: number, where: string)
	if type(playerId) ~= "number" or not isFinite(playerId) or playerId % 1 ~= 0 then
		error(`CardSeatHold.{where}: playerId must be a finite integer`, 3)
	end
end

local CardSeatHold = {}

function CardSeatHold.new(effects: Effects): CardSeatHold
	-- playerId -> the pose to (re)apply. Presence in this table IS "held".
	local held: { [number]: Pose } = {}
	local count = 0

	local function place(playerId: number, pose: Pose)
		if not effects.pivotTo(playerId, pose) then
			effects.onTelemetry("seat_hold_deferred", { playerId = playerId })
		end
	end

	local function release(_self: CardSeatHold, playerId: number)
		checkId(playerId, "release")
		if held[playerId] == nil then
			return
		end
		held[playerId] = nil
		count -= 1
		-- Capability first, then control (D-30).
		effects.freezeHumanoid(playerId, false)
		effects.setMovementScriptable(playerId, false)
	end

	local self: CardSeatHold
	self = {
		hold = function(_self: CardSeatHold, playerId: number, pose: Pose)
			checkId(playerId, "hold")
			if held[playerId] ~= nil then
				return
			end
			-- Copy the pose so a caller mutating its table later cannot move the queued pose.
			held[playerId] = {
				position = { x = pose.position.x, y = pose.position.y, z = pose.position.z },
				look = { x = pose.look.x, y = pose.look.y, z = pose.look.z },
			}
			count += 1
			effects.setMovementScriptable(playerId, true)
			effects.freezeHumanoid(playerId, true)
			place(playerId, held[playerId])
		end,
		release = release,
		onCharacterAdded = function(_self: CardSeatHold, playerId: number)
			checkId(playerId, "onCharacterAdded")
			local pose = held[playerId]
			if pose == nil then
				return
			end
			-- Deliberately NOT setMovementScriptable: it is a Player property and survives a respawn.
			effects.freezeHumanoid(playerId, true)
			place(playerId, pose)
		end,
		forget = function(_self: CardSeatHold, playerId: number)
			checkId(playerId, "forget")
			if held[playerId] ~= nil then
				held[playerId] = nil
				count -= 1
			end
		end,
		releaseAll = function(_self: CardSeatHold)
			local ids: { number } = {}
			for id in held do
				table.insert(ids, id)
			end
			table.sort(ids)
			for _, id in ids do
				release(self, id)
			end
		end,
		isHeld = function(_self: CardSeatHold, playerId: number): boolean
			return held[playerId] ~= nil
		end,
		heldCount = function(_self: CardSeatHold): number
			return count
		end,
	}
	return self
end

return CardSeatHold
