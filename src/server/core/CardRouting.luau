--!strict
-- Who sees what at the live card table (CARD-13, CLAUDE.md rule 3), written down as DATA.
--
--   1. PURE ZONE. No Roblox API, no clock, no yields, no roster. This file holds no state at all;
--      it is tables plus total functions.
--   2. The privacy decision is DATA. AUDIENCE and PRIVATE_KINDS are frozen, for the same reason
--      Manifest.PHASES is: a Luau type is erased at runtime, so freezing is what actually stops a
--      later module widening an audience. Guard R4 confines the Roblox send calls to NetServer, so
--      "is anything private broadcast?" is answerable by enumerating this table.
--   3. Defence in depth. assertPublic throws, so even if a later edit routes a Sync through
--      toSeated the failure is loud at the first attempt rather than a silent leak. makePublisher
--      assembles the three Publisher methods around it, so the guard a spec drives is the guard
--      that ships; NetServer supplies only effect closures.
--   4. ValveForcedPass never crosses as itself (D-18). It fires in about 8% of rounds at a full
--      roster, so this is an ordinary path. `lap` and `to` are dropped: `lap` is trajectory
--      bookkeeping and the Passed the engine emits beside the marker already carries `to`. The table
--      sees an ordinary pass; only the affected player is told why. Accepted consequence: the
--      downstream player receives a card with no explanation and nothing marks it as forced.
--   5. Completed.fifth never crosses. The four retired faces are public by design (they turn face
--      up at the seat); the fifth card stays in the finisher's hand, so its face stays private.
--   6. Copy assignment lives here, not in src/shared (D-37). Guard R5 bans the engine's rank table
--      identifier from src/shared and src/client; this file is under src/server, so it may name it.
--   7. DEPTHS ARE SERVER-SUPPLIED (CARD-13), NEVER DERIVED CLIENT-SIDE. Reconstructing them from the
--      event stream needs the complete stream from RoundStart, and one gateway reject or resync would
--      silently desync the counters with nothing to detect it. The `Depths` kind is public ("seated")
--      and carries counts only; CardTable builds it from the live engine state after each apply.
--   8. ROUND END IS ITS OWN PUBLIC KIND, NO PAYLOAD. The client restores its controls only on the local
--      seat's Completed, its SeatRemoved or the next RoundStart, and CardService.endRound removes no
--      seat. Without `RoundEnd` the server releases the avatar hold while the client still has the
--      touch controls hidden (UX-02 / D-29). Reusing SeatRemoved was rejected: the engine's RemoveCause
--      is Completed | Disconnected | Benched, none of which means "the round ended", and adding one
--      touches src/server/engine/. It carries an empty table; there is nothing to leak.
--   9. No hash, ever, in anything client-bound (Types.luau guarantee 6).
local Types = require("../engine/Types")

export type Publisher = {
	toPlayer: (userId: number, kind: string, payload: unknown) -> (),
	toSeated: (kind: string, payload: unknown) -> (),
	toAll: (kind: string, payload: unknown) -> (),
}

export type Audience = "owner" | "seated"

export type Effects = {
	fireToPlayer: (userId: number, kind: string, payload: unknown) -> (),
	fireToMany: (userIds: { number }, kind: string, payload: unknown) -> (),
	fireToAll: (kind: string, payload: unknown) -> (),
	seatedUserIds: () -> { number },
}

export type FaceRecord = { cardId: number, rank: number, copy: number }
export type Notice =
	{ code: "ForcedPass", cardId: number }
	| { code: "Strike", strikes: number, owes: "Pass" | "Draw", cardId: number? }
	| { code: "Benched" }
export type PublicEvent =
	{ kind: "Drew", seat: number, cardId: number }
	| { kind: "Passed", seat: number, to: number, cardId: number }
	| { kind: "Completed", seat: number, rank: number, faces: { FaceRecord } }
	| {
		kind: "SeatRemoved",
		seat: number,
		cause: "Completed" | "Disconnected" | "Benched",
		routedTo: number?,
		cards: number,
	}
-- CARD-13's "only the pile depths of other seats", as a wire shape. `depths[seat]` is the number of
-- cards waiting in that seat's left pile (0 for a removed seat). COUNTS ONLY: no key but `depths`, no
-- value but a non-negative integer. The privacy gate walks this payload by key name and by value type.
export type DepthsPayload = { depths: { number } }
export type PrivateNotice = { seat: number, notice: Notice }

local KINDS = { "RoundStart", "Sync", "Notice", "Table", "Stall", "Depths", "RoundEnd" }
table.freeze(KINDS)

local AUDIENCE: { [string]: Audience } = {
	RoundStart = "seated",
	Sync = "owner",
	Notice = "owner",
	Table = "seated",
	Stall = "seated",
	Depths = "seated",
	RoundEnd = "seated",
}
table.freeze(AUDIENCE)

local PRIVATE_KINDS: { [string]: true } = { Sync = true, Notice = true }
table.freeze(PRIVATE_KINDS)

local function audienceOf(kind: string): Audience
	local audience: string? = AUDIENCE[kind]
	if audience == nil then
		error(`CardRouting.audienceOf: unknown message kind {tostring(kind)}`)
	end
	return audience :: Audience
end

local function assertPublic(kind: string)
	if audienceOf(kind) ~= "seated" or PRIVATE_KINDS[kind] then
		error(`CardRouting.assertPublic: {kind} is private and must not be broadcast`)
	end
end

local function makePublisher(effects: Effects): Publisher
	return {
		toPlayer = function(userId: number, kind: string, payload: unknown)
			effects.fireToPlayer(userId, kind, payload)
		end,
		toSeated = function(kind: string, payload: unknown)
			assertPublic(kind)
			local ids = effects.seatedUserIds()
			if #ids == 0 then
				return
			end
			effects.fireToMany(ids, kind, payload)
		end,
		toAll = function(kind: string, payload: unknown)
			assertPublic(kind)
			effects.fireToAll(kind, payload)
		end,
	}
end

-- copy is 1..4 per natural rank, numbered in ascending card-id order; jokers get 1. The rank table is
-- fixed for the whole round, so this is computed once at the deal.
local function assignCopies(rankOf: { number }, ranks: number): { number }
	local copyOf: { number } = {}
	local seen = table.create(ranks, 0)
	for id = 1, #rankOf do
		local r = rankOf[id]
		if r == Types.JOKER_RANK then
			copyOf[id] = 1
		else
			if r < 1 or r > ranks then
				error(`CardRouting.assignCopies: card {id} has rank {r} outside 1..{ranks}`)
			end
			seen[r] += 1
			copyOf[id] = seen[r]
		end
	end
	for r = 1, ranks do
		if seen[r] ~= 4 then
			error(`CardRouting.assignCopies: rank {r} has {seen[r]} copies, expected exactly 4`)
		end
	end
	return copyOf
end

local function split(events: { Types.Event }, copyOf: { number }): ({ PublicEvent }, { PrivateNotice })
	local publicList: { PublicEvent } = {}
	local notices: { PrivateNotice } = {}
	for _, event in events do
		if event.kind == "Drew" then
			table.insert(publicList, { kind = "Drew", seat = event.seat, cardId = event.cardId })
		elseif event.kind == "Passed" then
			table.insert(publicList, { kind = "Passed", seat = event.seat, to = event.to, cardId = event.cardId })
		elseif event.kind == "Completed" then
			-- `fifth` is deliberately not read: it stays private to the finisher.
			local faces: { FaceRecord } = {}
			for _, cardId in event.retired do
				table.insert(faces, { cardId = cardId, rank = event.rank, copy = copyOf[cardId] })
			end
			table.insert(publicList, { kind = "Completed", seat = event.seat, rank = event.rank, faces = faces })
		elseif event.kind == "SeatRemoved" then
			table.insert(publicList, {
				kind = "SeatRemoved",
				seat = event.seat,
				cause = event.cause,
				routedTo = event.routedTo,
				cards = event.cards,
			})
		elseif event.kind == "ValveForcedPass" then
			-- Stripped from the public batch entirely; `lap` and `to` never cross.
			table.insert(notices, { seat = event.seat, notice = { code = "ForcedPass", cardId = event.cardId } })
		else
			error(`CardRouting.split: unrecognised event kind {tostring((event :: any).kind)}`)
		end
	end
	return publicList, notices
end

-- One Engine.apply event list out to a Publisher: the public batch to the seated table as a single
-- ordered Table message, each private notice to the seat it concerns. `userIdOfSeat` is the roster
-- lookup (the caller owns the roster). A notice goes ONLY to toPlayer, and this is the single place
-- a notice's recipient is decided.
local function publish(
	publisher: Publisher,
	events: { Types.Event },
	copyOf: { number },
	userIdOfSeat: (seat: number) -> number
)
	local publicList, notices = split(events, copyOf)
	if #publicList > 0 then
		publisher.toSeated("Table", publicList)
	end
	for _, n in notices do
		publisher.toPlayer(userIdOfSeat(n.seat), "Notice", n.notice)
	end
end

return {
	KINDS = KINDS,
	AUDIENCE = AUDIENCE,
	PRIVATE_KINDS = PRIVATE_KINDS,
	audienceOf = audienceOf,
	assertPublic = assertPublic,
	makePublisher = makePublisher,
	assignCopies = assignCopies,
	split = split,
	publish = publish,
}
