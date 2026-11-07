--!strict
-- THE FAN, ITS HIT STRIPS AND THE CHANGE-LIST ANIMATOR (CARD-02, CARD-15, UX-01, D-01..D-04, D-11, D-12,
-- D-25). It APPLIES what the reducer says and decides nothing: `apply` takes the authoritative Display and
-- the Change list, and the Changes only choose HOW a card moves, never WHAT exists.
--
--  1. THE HIT MODEL IS THE WHOLE OF CARD-15. One invisible TextButton per slot, laid out from
--     Solution.slots[i].hit, independent of card z-order and of the lift. That is what makes D-01's second
--     tap land on the same strip, and what keeps every neighbouring strip above the 48 physical px floor.
--     The cards themselves are never Active (CardFace header point 6).
--  2. CREATED ONCE. The five strips and the backdrop are built in `new` and never recreated; `apply` shows,
--     hides and moves them. A tap can therefore never land on a button that is mid-destruction.
--  3. CHECKER FLAG F7, ACCEPTED: strips snap to the final layout at the instant the hand size changes
--     (relayout) while the card visuals tween for 0.12 s, so the two disagree by up to 30 px for that
--     window. The alternative is a tap landing on a slot that is about to move, and D-02 forbids adding a
--     delay to resolve it.
--  4. THE LIFTED-CARD OVERHANG, ACCEPTED: a lifted card is drawn 72 wide but hit-tested 60, so a tap on its
--     visible 12 px overhang selects the right-hand neighbour instead of sending. Widening the lifted hit
--     rect would drop that neighbour's strip to 40.8 physical px at the 0.85 scale floor, below the
--     project's own 48 px floor.
--  5. AT HAND 4 THE STRIPS STAY ACTIVE. They still call tapSlot; the REDUCER makes the tap inert (F6). If
--     they were hidden or inactive a tap would fall through to the backdrop and clear a selection.
--  6. A RETURNING CARD IS TAPPABLE FOR THE WHOLE FLIGHT. The strip is at the slot from the first frame; the
--     flight is cosmetic and gates nothing (D-02, D-11).
--  7. D-12: THERE IS NO ERROR PATH IN THIS FILE AND THERE MUST NOT BE ONE. A correction and a hard
--     rejection are the same `Returned`: no text, no sound, no colour flash. The renderer raises nothing and
--     names no guard; a hand/solution size mismatch degrades to the last slot rather than throwing.
--  8. ARRIVAL ORDER, NEVER RE-SORTED BY RANK (T-4-131). Entries follow Display.hand order exactly.
--  9. THE RENDERER DIFFS NOTHING FOR ITSELF (T-4-130). Cards are matched to the Display by cardId, and the
--     Change list is consulted only for how to move: Returned -> fly back from the right pile; Flipped ->
--     the face-down placeholder turns over; Removed -> leave. `Added` needs no hint because appearing is
--     the default. A Change naming a card this hand does not have is ignored. `apply` is idempotent: the
--     same inputs twice change nothing the second time.
-- 10. THE FORCED-PASS PAIR (04-09). A ValveForcedPass landing while my own Pass is in flight yields TWO
--     changes at once: a card leaves that I did not choose, and my own in-flight card returns. Rendered
--     together they would cross at the right pile, so the return is HELD for the length of the send and
--     then flies back: "that one left, then yours came back". The held card is already at its slot for
--     hit-testing. `Removed` with no cardId is a face-down placeholder leaving (a rolled-back Draw) and
--     flies back to the LEFT pile.
-- 11. The contract extras, recorded in the summary: setJokerMode (the live flag CardFace forwards to
--     Faces), and the hand/solution size contract: `relayout` must be called with the new Solution BEFORE
--     the `apply` that changes the hand size.
-- 12. WHAT THIS DOES NOT PROVE: that a tap feels immediate, that a single tap never sends on glass, and
--     that a return reads as a return rather than a teleport at 150-300 ms (M-13, M-17); target size and
--     thumb reach on glass (M-12); spade versus club at 16 px and greyscale (M-14). Not loadable in Lune.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardConfig = require(ReplicatedStorage.Shared.Config.Card)
local Hints = require(ReplicatedStorage.Shared.Card.Hints)
local Layout = require(ReplicatedStorage.Shared.Card.Layout)
local Prediction = require(ReplicatedStorage.Shared.Card.Prediction)
local CardFace = require("./CardFace")

export type Hand = {
	-- Called after every reducer transition. `display` is the authoritative picture and `changes` is
	-- what to animate; the renderer diffs nothing itself.
	apply: (self: Hand, display: Prediction.Display, changes: { Prediction.Change }, selectedCardId: number?) -> (),
	relayout: (self: Hand, solution: Layout.Solution) -> (),
	setInputKind: (self: Hand, kind: Hints.InputKind) -> (),
	-- The live joker flag from the round-start payload; forwarded to Faces, which errors by name if a
	-- joker is drawn without one.
	setJokerMode: (self: Hand, mode: string?) -> (),
	-- Plan 04-18: the keyboard and gamepad accelerators send without passing through a strip, so they tell
	-- the hand a card was sent by this player (otherwise its departure would render as a forced removal).
	markSent: (self: Hand, cardId: number) -> (),
	destroy: (self: Hand) -> (),
}

type Entry = {
	face: CardFace.CardFace,
	cardId: number?,
	slotIndex: number,
	alive: boolean,
}

local TWEEN = CardConfig.TWEEN
local MAX_HAND = 5 -- Types.MAX_HAND; Layout.solve only ever returns 4 or 5 slots
-- Above every card (CardFace uses 10..20): the strips are what take the tap.
local Z_BACKDROP = 0
local Z_STRIP = 50

local CardHand = {}

function CardHand.new(
	parent: Frame,
	solution: Layout.Solution,
	callbacks: {
		tapSlot: (cardId: number?) -> (),
		tapOff: () -> (),
	}
): Hand
	local sol = solution
	local entries: { Entry } = {}
	local leaving: { CardFace.CardFace } = {}
	local connections: { RBXScriptConnection } = {}
	local committed: { [number]: boolean } = {}
	local selectedNow: number? = nil
	local jokerMode: string? = nil
	local destroyed = false

	local function bind(signal: RBXScriptSignal, fn: (...any) -> ())
		table.insert(connections, signal:Connect(fn))
	end

	local function sink(button: TextButton)
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.Text = ""
		button.AutoButtonColor = false
		button.Active = true
		button.Selectable = false
	end

	-- The backdrop covers the whole Root (HandZone and TableRegion), below everything (D-04).
	local host: GuiObject = parent
	local above = parent.Parent
	if above ~= nil and above:IsA("GuiObject") then
		host = above :: GuiObject
	end
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	sink(backdrop)
	backdrop.ZIndex = Z_BACKDROP
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = host

	local strips: { TextButton } = {}
	local function onStrip(i: number)
		local entry = entries[i]
		local id = if entry ~= nil then entry.cardId else nil
		-- Remember that THIS player sent the card, so its departure is a send and not a forced removal.
		if id ~= nil and id == selectedNow and #entries == MAX_HAND then
			committed[id] = true
		end
		callbacks.tapSlot(id)
	end
	for i = 1, MAX_HAND do
		local button = Instance.new("TextButton")
		button.Name = `Slot{i}`
		sink(button)
		button.ZIndex = Z_STRIP
		button.Visible = false
		button.Parent = parent
		table.insert(strips, button)
		bind(button.Activated, function()
			onStrip(i)
		end)
	end
	bind(backdrop.Activated, function()
		callbacks.tapOff()
	end)

	local function slotAt(i: number): Layout.Slot
		return sol.slots[math.min(i, #sol.slots)]
	end

	-- Strips SNAP (F7); only card visuals tween.
	local function placeStrips()
		for i, button in strips do
			local slot = sol.slots[i]
			if slot == nil then
				button.Visible = false
			else
				local position, size = CardFace.zoneRect(slot.hit, sol)
				button.Position = position
				button.Size = size
				button.Visible = true
			end
		end
	end
	placeStrips()

	local function leftCentre(): Vector2
		return CardFace.pileArtCentre(sol.leftPile, sol)
	end
	local function rightCentre(): Vector2
		return CardFace.pileArtCentre(sol.rightPile, sol)
	end

	local function retire(face: CardFace.CardFace)
		local at = table.find(leaving, face)
		if at ~= nil then
			table.remove(leaving, at)
		end
		face:destroy()
	end

	-- A card leaves: to the right pile like a send, or a face-down placeholder back to the left pile.
	local function leave(entry: Entry, forced: boolean)
		entry.alive = false
		local face = entry.face
		face:setVisible(true)
		table.insert(leaving, face)
		if entry.cardId == nil then
			face:flyTo(leftCentre(), "Returning", function()
				retire(face)
			end)
		else
			face:flyTo(rightCentre(), if forced then "ForcedOut" else "InFlight", function()
				retire(face)
			end)
		end
	end

	local function newEntry(face: CardFace.CardFace, id: number?, index: number): Entry
		return { face = face, cardId = id, slotIndex = index, alive = true }
	end

	local function reveal(entry: Entry, dc: Prediction.DisplayCard)
		if dc.rank ~= nil then
			entry.face:setFace(dc.rank, dc.copy, jokerMode)
		end
	end

	local hand: Hand
	hand = {
		apply = function(_self: Hand, display: Prediction.Display, changes: { Prediction.Change }, selected: number?)
			if destroyed then
				return
			end
			selectedNow = selected

			-- How to move, per change kind. Anything naming a card we do not hold is simply never looked up.
			local returned: { [number]: boolean } = {}
			local flipped: { [number]: boolean } = {}
			local removedWithId = false
			for _, change in changes do
				if change.kind == "Returned" then
					returned[change.cardId] = true
				elseif change.kind == "Flipped" then
					flipped[change.cardId] = true
				elseif change.kind == "Removed" and change.cardId ~= nil then
					removedWithId = true
				end
			end
			-- The forced-pass pair (header point 10): hold the return for the length of the send.
			local holdReturn = if removedWithId then TWEEN.SEND else 0

			local byId: { [number]: Entry } = {}
			local blanks: { Entry } = {}
			for _, entry in entries do
				if entry.cardId ~= nil then
					byId[entry.cardId] = entry
				else
					table.insert(blanks, entry)
				end
			end
			local nextBlank = 1

			local nextEntries: { Entry } = {}
			for i, dc in display.hand do
				local slot = slotAt(i)
				local id = dc.cardId
				local entry: Entry? = nil
				if id ~= nil then
					entry = byId[id]
					if entry ~= nil then
						byId[id] = nil
					elseif flipped[id] and blanks[nextBlank] ~= nil then
						-- The face-down placeholder turns over and takes its identity.
						local blank = blanks[nextBlank]
						nextBlank += 1
						blank.cardId = id
						blank.face:flip()
						reveal(blank, dc)
						entry = blank
					else
						local face = CardFace.new(parent, sol)
						local fresh = newEntry(face, id, i)
						reveal(fresh, dc)
						face:moveToSlot(slot, false)
						if returned[id] then
							face:placeAt(rightCentre(), true)
							local target = CardFace.centreOf(slot.card, sol)
							if holdReturn > 0 then
								face:setVisible(false)
								-- Guarded by `alive` and `destroyed`, so there is nothing to cancel.
								task.delay(holdReturn, function()
									if fresh.alive and not destroyed then
										face:setVisible(true)
										face:flyTo(target, "Returning", nil)
									end
								end)
							else
								face:flyTo(target, "Returning", nil)
							end
						end
						entry = fresh
					end
				else
					entry = blanks[nextBlank]
					if entry ~= nil then
						nextBlank += 1
					else
						local face = CardFace.new(parent, sol)
						face:setFace(nil, nil, nil)
						face:moveToSlot(slot, false)
						face:placeAt(leftCentre(), false)
						face:flyTo(CardFace.centreOf(slot.card, sol), "Arriving", nil)
						entry = newEntry(face, nil, i)
					end
				end
				local settled = entry :: Entry
				if settled.slotIndex ~= i then
					settled.slotIndex = i
					settled.face:moveToSlot(slot, true)
				end
				table.insert(nextEntries, settled)
			end

			-- Anything not matched has left the hand.
			for _, entry in byId do
				leave(entry, not committed[entry.cardId :: number])
			end
			for k = nextBlank, #blanks do
				leave(blanks[k], false)
			end
			entries = nextEntries
			table.clear(committed)

			for _, entry in entries do
				local isSelected = entry.cardId ~= nil and entry.cardId == selected
				entry.face:setVisual(if isSelected then "Selected" else "Idle")
			end
		end,

		relayout = function(_self: Hand, solution2: Layout.Solution)
			local sameCount = #solution2.slots == #sol.slots
			sol = solution2
			placeStrips()
			for i, entry in entries do
				entry.face:setSolution(solution2)
				-- A viewport change snaps. A hand-size change is left to the apply that follows it, so the
				-- close-the-gap tween is not pre-empted.
				if sameCount then
					entry.face:moveToSlot(slotAt(i), false)
					entry.slotIndex = i
				end
			end
			for _, face in leaving do
				face:setSolution(solution2)
			end
		end,

		setInputKind = function(_self: Hand, kind: Hints.InputKind)
			for _, button in strips do
				button.Selectable = kind == "Gamepad"
			end
		end,

		setJokerMode = function(_self: Hand, mode: string?)
			jokerMode = mode
		end,

		markSent = function(_self: Hand, cardId: number)
			committed[cardId] = true
		end,

		destroy = function(_self: Hand)
			if destroyed then
				return
			end
			destroyed = true
			for _, c in connections do
				c:Disconnect()
			end
			table.clear(connections)
			for _, entry in entries do
				entry.alive = false
				entry.face:destroy()
			end
			for _, face in leaving do
				face:destroy()
			end
			table.clear(entries)
			table.clear(leaving)
			for _, button in strips do
				button:Destroy()
			end
			backdrop:Destroy()
		end,
	}
	return hand
end

return CardHand
