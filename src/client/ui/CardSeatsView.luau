--!strict
-- (File name: the plan called this CardTableView, but check-guards treats every file whose name starts with
-- "CardTable" as a FOUND-05 guarded root, and a client renderer must not be one -- Phase 7 plugs deck-skin
-- data in here. So it is CardSeatsView; the exported type is still TableView.)
-- THE TABLE AS A PLACE: one low stack of face-down cards at each seat, and face-down cards that visibly
-- hop from seat to seat as the public Passed events arrive (CARD-13, D-19, D-27).
--
--  1. D-19, THE REASON THE HOPS EXIST. The start-up ramp is real and measured: about 8.3 s at a full table
--     against a 4.6 s median time to first completion at three players. Cards visibly travelling the ring
--     make that wait read as the deal arriving instead of as nothing happening, they need no text, and they
--     teach a new player which way the chain flows.
--  2. D-27: A PLACE, NOT A WALLPAPER. You watch stacks grow, see cards travel and see someone stand up and
--     run. Making the table a backdrop was rejected explicitly, because that turns the card phase back into
--     the menu transition the Core Value forbids.
--  3. CARD-13: NO NUMERAL AND NO FACE OVER ANOTHER SEAT, EVER. Another seat is a stack HEIGHT and nothing
--     else; this file creates no text object at all, and a spec asserts it. A public Passed carries a
--     cardId and no rank, so there is nothing to draw face-up and nothing may be inferred. The exact count
--     lives only on the local player's own two panels (CardPiles): your left-pile depth is your most
--     actionable number, and nine floating numbers on a phone is clutter.
--  4. NO DEALER MARKER ANYWHERE. The dealer's left pile IS the remaining deck, so their stack is the
--     tallest object on the table by construction. The role is true by geometry, not by a flag someone has
--     to keep in sync with the engine.
--  5. WHERE THE NUMBERS COME FROM. Heights come from the server's Depths message (counts only, built from
--     the engine state), never from counting events here: a gateway reject or a resync would silently
--     desync a client-side counter with nothing to detect it. Seat poses come from RoundStart, because the
--     map's Seats folder is under Data, which is never cloned into Workspace.
--  6. THIS IS CLIENT-LOCAL COSMETIC GEOMETRY BUILT FROM PUBLIC FACTS. Nothing here is replicated and
--     nothing hidden is read (CLAUDE.md rule 3).
--  7. EVERY PART COMES FROM ONE HELPER, and the helper sets Anchored, CanCollide = false, CanQuery = false
--     and CanTouch = false. Phase 5's line-of-sight raycast is coming and RaycastParams.RespectCanCollide
--     defaults to false, the opposite of this project's collision model, so a cosmetic card that stayed
--     queryable would block a sightline and make a spoon unfindable. One creation site makes "every part"
--     checkable by counting, and tests/card/flourish_surface.spec.luau does.
--  8. THE HOP POOL IS PRE-ALLOCATED at TABLE_HOP_CONCURRENT_CAP and reused. Over the cap a hop is skipped
--     and only the stack height updates: a dropped cosmetic is better than a frame-rate collapse during the
--     ramp (about 20 actions a second table-wide at peak).
--  9. NOTHING HERE IS VERIFIED ON A DEVICE. Whether one extra card is a visible step at the reference
--     viewport, whether the arc reads as a pass and whether the stacks sit on the real table are M-12 and
--     M-17.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Card = require(ReplicatedStorage.Shared.Config.Card)
local CardTheme = require("./CardTheme")

export type Vec3 = { x: number, y: number, z: number }
export type SeatPose = { seat: number, playerId: number, position: Vec3, look: Vec3 }

export type TableView = {
	setSeats: (self: TableView, seats: { SeatPose }) -> (),
	setDepths: (self: TableView, depths: { number }) -> (),
	-- One face-down card hops anchor to anchor along a shallow arc. Driven by PUBLIC Passed events only.
	hop: (self: TableView, fromSeat: number, toSeat: number) -> (),
	seatPosition: (self: TableView, seat: number) -> Vector3?,
	-- The centroid of every seat anchor: where a completion flourish slides to.
	centre: (self: TableView) -> Vector3?,
	destroy: (self: TableView) -> (),
}

local CARD = Card.TABLE_CARD_STUDS
local TWEEN = Card.TWEEN
local HALF = 2

local UP = Vector3.new(0, 1, 0)

-- The ONE part-creation site in this file (header point 7).
local function newPart(parent: Instance, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = CardTheme.COLOR.CARD_BACK
	part.Material = Enum.Material.SmoothPlastic
	part.Size = Vector3.new(CARD.WIDTH, CARD.THICKNESS, CARD.LENGTH)
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function vectorOf(v: Vec3): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

-- In front of the seat, toward the table: the stack is not under the avatar.
local function anchorOf(pose: SeatPose): Vector3
	local position = vectorOf(pose.position)
	local look = vectorOf(pose.look)
	if look.Magnitude > 0 then
		return position + look.Unit * Card.SEAT_STACK_OFFSET_STUDS
	end
	return position
end

type Hopper = { part: Part, busy: boolean, tweens: { Tween } }

local CardTableView = {}

function CardTableView.new(parent: Instance): TableView
	local folder = Instance.new("Folder")
	folder.Name = "SpoonsCardTable"

	local anchors: { [number]: Vector3? } = {}
	local stacks: { [number]: Part } = {}
	local heights: { [number]: number } = {}
	local pool: { Hopper } = {}
	local destroyed = false

	for i = 1, Card.TABLE_HOP_CONCURRENT_CAP do
		table.insert(pool, { part = newPart(folder, `Hop{i}`), busy = false, tweens = {} })
	end
	folder.Parent = parent

	local function topOf(seat: number): Vector3
		return (anchors[seat] :: Vector3) + UP * (heights[seat] or 0)
	end

	local function clearSeats()
		for _, part in stacks do
			part:Destroy()
		end
		table.clear(stacks)
		table.clear(anchors)
		table.clear(heights)
	end

	local function release(hopper: Hopper)
		hopper.busy = false
		hopper.part.Transparency = 1
		table.clear(hopper.tweens)
	end

	local view: TableView
	view = {
		setSeats = function(_self: TableView, seats: { SeatPose })
			clearSeats()
			for _, pose in seats do
				anchors[pose.seat] = anchorOf(pose)
				stacks[pose.seat] = newPart(folder, `Seat{pose.seat}`)
				heights[pose.seat] = 0
			end
		end,
		setDepths = function(_self: TableView, depths: { number })
			for seat, part in stacks do
				local count = depths[seat] or 0
				-- Strictly monotone in the count until the cap, which only stops the stack growing off
				-- the table. No numeral, ever (header point 3).
				local height = Card.SEAT_STACK_STUDS_PER_CARD * math.min(math.max(count, 0), Card.SEAT_STACK_CAP)
				heights[seat] = height
				if height <= 0 then
					part.Transparency = 1
				else
					part.Transparency = 0
					part.Size = Vector3.new(CARD.WIDTH, height, CARD.LENGTH)
					part.Position = (anchors[seat] :: Vector3) + UP * (height / HALF)
				end
			end
		end,
		hop = function(_self: TableView, fromSeat: number, toSeat: number)
			if destroyed or anchors[fromSeat] == nil or anchors[toSeat] == nil then
				return
			end
			local free: Hopper? = nil
			for _, hopper in pool do
				if not hopper.busy then
					free = hopper
					break
				end
			end
			-- Over the cap: skip the cosmetic (header point 8). The height still updates via setDepths.
			if free == nil then
				return
			end
			local hopper = free :: Hopper
			hopper.busy = true
			local from, to = topOf(fromSeat), topOf(toSeat)
			local apex = (from + to) / HALF + UP * Card.HOP_PEAK_STUDS
			hopper.part.Position = from
			hopper.part.Transparency = 0
			local halfTime = TWEEN.HOP / HALF
			local rise = TweenService:Create(
				hopper.part,
				TweenInfo.new(halfTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = apex }
			)
			local fall = TweenService:Create(
				hopper.part,
				TweenInfo.new(halfTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = to }
			)
			hopper.tweens = { rise, fall }
			rise.Completed:Once(function()
				if destroyed then
					return
				end
				fall:Play()
			end)
			fall.Completed:Once(function()
				if not destroyed then
					release(hopper)
				end
			end)
			rise:Play()
		end,
		seatPosition = function(_self: TableView, seat: number): Vector3?
			return anchors[seat]
		end,
		centre = function(_self: TableView): Vector3?
			local sum = Vector3.zero
			local n = 0
			for _, anchor in anchors do
				if anchor ~= nil then
					sum += anchor
					n += 1
				end
			end
			if n == 0 then
				return nil
			end
			return sum / n
		end,
		destroy = function(_self: TableView)
			if destroyed then
				return
			end
			destroyed = true
			for _, hopper in pool do
				for _, tween in hopper.tweens do
					tween:Cancel()
				end
			end
			folder:Destroy()
		end,
	}
	return view
end

return CardTableView
