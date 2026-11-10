--!strict
-- PHASE 04.1 WAVE 0 SPIKE -- THE LAYERING PROBE. This settles MANUAL-CHECKS **M-18**, and nothing else does.
--
-- PASTE THE WHOLE FILE INTO THE STUDIO COMMAND BAR. It is not a Lune script and it is not mounted by Rojo
-- (`default.project.json` mounts neither `workspace` content nor `StarterGui`), so nothing cleans it up for you:
-- the last thing it prints is the cleanup snippet. The M-14 probe in MANUAL-CHECKS.md is the house precedent for
-- this shape, including the "delete it afterwards" note and the `GREYSCALE`-style flag at the top.
--
-- THE QUESTION. `SurfaceGui.AlwaysOnTop = true` is documented only as "always renders on top of 3D content";
-- `ZOffset` only as layering "in relation to others **on the same face**". Neither sentence covers two
-- `AlwaysOnTop` SurfaceGuis on DIFFERENT Parts (verification debt U3). The full taxonomy, each route's cost and
-- the decision rule are in `.planning/phases/04.1-first-person-cards/04.1-LAYERING-DECISION.md`. Read it; this
-- script does not re-derive the question, it photographs the answer.
--
-- WHY FIVE CARDS PER ROUTE AND NOT THREE. Slot roll is `(s - (n+1)/2) * ROLL_STEP_DEG`, so in a five-card hand
-- the ends sit at -8 and +8 degrees and dip `R(1 - cos 8 deg)` below the middle. **Three centred cards can pass
-- while the rolled end pair fails**, which would be a spike that approved the exact defect it existed to find.
--
-- WHAT THIS PROBE DOES NOT DO. It judges LAYERING, not legibility: it draws its own minimal face rather than
-- calling `CardFace`, so a later change to the face art cannot alter this photograph, and no CardFace defect can
-- be mistaken for a layering defect. Legibility at the rendered size is M-14. Colours and the font here are
-- deliberately NOT `CardTheme`'s, for the same reason. **Every GEOMETRY number is read from `Card.HAND` /
-- `Card.CAMERA` and none is hard-coded**, so what you photograph is the shipped geometry.
--
-- WHERE IT BUILDS. High above the map (`BASE_Y`), so the ONLY thing that can occlude a card is the probe's own
-- deliberate slab. A probe that built in the lobby would confuse "route B is depth-tested" with "the lobby table
-- is in the way".
--
-- ANONYMITY. Every part comes from ONE helper that sets `Anchored`, `CanCollide = false`, `CanQuery = false`,
-- `CanTouch = false` and `CastShadow = false`, and every CARD part is `Transparency = 1` and named `"CardSlot"`
-- with no attributes -- the shipped carrier's anonymity (D-45, CLAUDE.md rule 3), demonstrated rather than
-- shortcut. A probe that taught the pattern it is meant to forbid would be worse than no probe. The occluder is
-- the one part that is not a card, so it is the one part that is opaque and the one part with another name.
--
-- Roblox globals arrive through `getfenv()` on purpose: this file is committed, so it is linted, formatted and
-- TYPE-CHECKED by `scripts/verify.luau` like everything else, and the headless checker has no `game` or
-- `Instance`. Reading them through one named table is what lets the gate cover the rest of the file instead of
-- excluding it.

-- Which route's camera pose to sit at. Run the probe once per value and photograph each.
--   "A" | "B" | "C" -- the camera sits at the REAL pose, centred on that route's hand. **These are the shots
--                      the verdict is based on.**
--   "ALL"           -- pulled back so all three fit in one frame. An OVERVIEW ONLY: it is NOT the real pose,
--                      so the cards are smaller and farther than they ship. Never judge the rule from it.
local VIEW: string = "A"

local env: any = getfenv()
assert(
	env.game ~= nil and env.Instance ~= nil,
	"spike-layering: this is a STUDIO script -- paste it into the Studio command bar, not `lune run`"
)
local rbxRequire: (any) -> any = env.require
local game, Instance, Enum = env.game, env.Instance, env.Enum
local Vector3, Vector2, CFrame, Color3, UDim2 = env.Vector3, env.Vector2, env.CFrame, env.Color3, env.UDim2

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Card = rbxRequire(ReplicatedStorage.Shared.Config.Card)
local HAND = Card.HAND
local CAMERA = Card.CAMERA

local PROBE_NAME = "SpikeLayering"
local HAND_SIZE = 5
local GROUP_SPAN_STUDS = 12 -- camera-local X between route groups; wider than one hand (4 * STEP) plus margin
local BASE_Y = 400 -- far above any map geometry, so the only occluder is the probe's own slab
local ROUTES = { "A", "B", "C" }

-- Phase 4's design card, DERIVED and not retyped: CARD_STUDS is exactly 72 x 92 over 40, and deriving it here
-- is what makes "this probe hard-codes no geometry number" true rather than nearly true.
local DESIGN_PER_STUD = 1 / HAND.STUDS_PER_DESIGN_UNIT
local DESIGN_W = HAND.CARD_STUDS.WIDTH * DESIGN_PER_STUD
local DESIGN_H = HAND.CARD_STUDS.HEIGHT * DESIGN_PER_STUD

-- Not CardTheme's palette, and deliberately so (see the header): a layering probe must not be able to fail
-- because a colour token moved.
local FACE = Color3.fromRGB(240, 240, 240)
local INK = Color3.fromRGB(24, 24, 28)
local EDGE = Color3.fromRGB(200, 40, 40)
local SLAB = Color3.fromRGB(40, 120, 200)

-- ---------------------------------------------------------------------------------------------------------------
-- Derived geometry. The arc radius is DERIVED and never stored in config: a second constant is how two numbers
-- come to disagree (Config/Card.luau header point 9).
-- ---------------------------------------------------------------------------------------------------------------

local ROLL_STEP_RAD = math.rad(HAND.ROLL_STEP_DEG)
local ARC_R = HAND.STEP_STUDS / (2 * math.sin(ROLL_STEP_RAD / 2))

-- Slot `s` of `n`, in CAMERA-LOCAL space. The composition order is stated rather than implied, because plan 02's
-- pure `Projection` module is the authority on it and the two must agree:
--   translate to the slot centre on the arc  ->  roll about the view axis  ->  lean about the card's own X.
-- Lean is NEGATIVE about X so the card's top goes toward -Z, i.e. AWAY from an eye that looks down -Z.
local function slotCFrameLocal(s: number, n: number): any
	local roll = (s - (n + 1) / 2) * ROLL_STEP_RAD
	local pivotY = HAND.OFFSET_STUDS.Y - ARC_R
	local centre = Vector3.new(
		HAND.OFFSET_STUDS.X + ARC_R * math.sin(roll),
		pivotY + ARC_R * math.cos(roll),
		-- toward the camera (camera looks down -Z, so +Z is nearer the eye)
		HAND.OFFSET_STUDS.Z + (s - 1) * HAND.DEPTH_STEP_STUDS
	)
	return CFrame.new(centre) * CFrame.Angles(0, 0, -roll) * CFrame.Angles(-math.rad(HAND.LEAN_DEG), 0, 0)
end

-- ---------------------------------------------------------------------------------------------------------------
-- The one part helper. Card defaults are the shipped carrier's; the occluder is the only caller that overrides.
-- ---------------------------------------------------------------------------------------------------------------

local function makePart(parent: any, size: any, cf: any, name: string, transparency: number, colour: any): any
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = transparency
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeCardPart(parent: any, cf: any): any
	return makePart(
		parent,
		Vector3.new(HAND.CARD_STUDS.WIDTH, HAND.CARD_STUDS.HEIGHT, HAND.CARD_STUDS.THICKNESS),
		cf,
		-- the shipped carrier's name for EVERY card, with no attributes: a replicated carrier would reveal
		-- "someone has a card here", which a public count already says, and never a rank
		"CardSlot",
		1,
		FACE
	)
end

-- ---------------------------------------------------------------------------------------------------------------
-- The minimal self-labelling face: a border, a big slot numeral, and a corner index in the exposed strip.
-- The corner index is the point of the whole spike -- under a right neighbour it is ALL a player can see, so if
-- layering is wrong it is the thing drawn by the wrong card.
-- ---------------------------------------------------------------------------------------------------------------

local function drawFace(container: any, slot: number, scale: number)
	local scaler = Instance.new("UIScale")
	scaler.Scale = scale
	scaler.Parent = container

	local root = Instance.new("Frame")
	root.Name = "Face"
	root.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
	root.BackgroundColor3 = FACE
	root.BorderSizePixel = 0
	root.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = EDGE -- a LOUD edge: the rule is about whose edge covers whose
	stroke.Parent = root

	local big = Instance.new("TextLabel")
	big.Name = "SlotNumeral"
	big.Size = UDim2.fromScale(1, 1)
	big.BackgroundTransparency = 1
	big.Font = Enum.Font.GothamBold
	big.TextSize = 44
	big.TextColor3 = INK
	big.Text = tostring(slot)
	big.Parent = root

	-- 16 design units in from the left is Phase 4's index inset, and it is GREATER than the 12-unit overlap,
	-- which is exactly why the index stays visible under a right neighbour. Drawn at 4,4 inside a 14x20 box.
	local index = Instance.new("TextLabel")
	index.Name = "CornerIndex"
	index.Position = UDim2.fromOffset(4, 4)
	index.Size = UDim2.fromOffset(14, 20)
	index.BackgroundTransparency = 1
	index.Font = Enum.Font.GothamBold
	index.TextSize = 18
	index.TextColor3 = INK
	index.Text = tostring(slot)
	index.Parent = root
end

-- ---------------------------------------------------------------------------------------------------------------
-- Where the SurfaceGuis live. THE SHIPPED ARRANGEMENT IS PlayerGui + Adornee, and the probe uses it, because
-- draw order is the very thing in question and it could depend on where the LayerCollector lives.
-- ---------------------------------------------------------------------------------------------------------------

local guiHost, hostNote
-- RUN THIS *INSIDE* A RUNNING SESSION. PRESS PLAY FIRST, THEN PASTE.
-- Pasting in edit mode and pressing Play afterwards does not work, and fails in a way that looks like the
-- probe is broken: the cards are built in Workspace and DO survive into Play, but this script also sets a
-- SCRIPTABLE CAMERA, and starting a session hands the camera back to the default player scripts. So the
-- cards sit at y=400 while the player stands on the baseplate, and the screen is empty. (Measured
-- 2026-11-10: the owner hit exactly this, and the Output carried no probe prints at all, because the prints
-- happened in the edit-mode session that Play replaced.)
local localPlayer = Players.LocalPlayer
if localPlayer ~= nil then
	guiHost = localPlayer:FindFirstChildOfClass("PlayerGui")
	hostNote = "PlayerGui -- the shipped arrangement, and you are already in a running session"
end
if guiHost == nil then
	guiHost = StarterGui
	hostNote = "StarterGui -- NOT a running session. PRESS PLAY (F5): StarterGui is cloned into PlayerGui, "
		.. "which is the shipped arrangement. Judge nothing from edit mode."
end

local function clearPrevious()
	local old = Workspace:FindFirstChild(PROBE_NAME)
	while old ~= nil do
		old:Destroy()
		old = Workspace:FindFirstChild(PROBE_NAME)
	end
	for _, child in guiHost:GetChildren() do
		if child.Name == PROBE_NAME then
			child:Destroy()
		end
	end
end

local function makeSurface(adornee: any, alwaysOnTop: boolean, zOffset: number?): any
	local gui = Instance.new("SurfaceGui")
	gui.Name = PROBE_NAME
	gui.Adornee = adornee
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40 * HAND.CANVAS_SCALE
	gui.Active = false -- cards never take input; hit testing is the 2D button layer (D-47)
	gui.ResetOnSpawn = false -- UI check F14
	-- Set under BOTH routes. Documented (SurfaceGui.md, re-verified 2026-11-10): "setting it to 0 means that the
	-- lighting has no effect". Under route A it is already treated as 0, so this removes a DIFFERENCE between the
	-- routes; under route B it is the whole mitigation for the 4.5:1 luma floor. `Brightness` is left at its
	-- default 1, which is the other half of that mitigation (M-23 step 2).
	gui.LightInfluence = 0
	gui.AlwaysOnTop = alwaysOnTop
	if zOffset ~= nil then
		gui.ZOffset = zOffset
	end
	gui.Parent = guiHost
	return gui
end

-- ---------------------------------------------------------------------------------------------------------------
-- The three routes
-- ---------------------------------------------------------------------------------------------------------------

-- Route A: AlwaysOnTop = true, ZOffset = slot. The spec as written.
-- Route B: AlwaysOnTop = false, no ZOffset, the DEPTH_STEP_STUDS step doing the work.
local function buildPartPerCard(folder: any, baseCF: any, alwaysOnTop: boolean, useZOffset: boolean)
	for slot = 1, HAND_SIZE do
		local part = makeCardPart(folder, baseCF * slotCFrameLocal(slot, HAND_SIZE))
		local gui = makeSurface(part, alwaysOnTop, if useZOffset then slot else nil)
		drawFace(gui, slot, HAND.CANVAS_SCALE)
	end
end

-- Route C: ONE SurfaceGui, five Frames, ZIndex = slot, rectangles only.
-- Drawn DELIBERATELY WITHOUT SHEAR, so the operator can SEE the approximation error. Vanilla Roblox GuiObjects
-- have no shear and no skew, so a perspective quad -- which lean + roll produce -- is not drawable as a rotated
-- rectangle. The rectangles below are rotated by the slot roll and squashed by cos(LEAN), which is the best a
-- GuiObject can do and is NOT the proven corners. That is route C's real cost: either these approximations, whose
-- corners are not the projected corners (the precise failure D-47 exists to prevent), or new image assets.
local function buildRouteC(folder: any, baseCF: any)
	local planeW = HAND.CARD_STUDS.WIDTH + (HAND_SIZE - 1) * HAND.STEP_STUDS
	local planeH = HAND.CARD_STUDS.HEIGHT + 2 * ARC_R * (1 - math.cos((HAND_SIZE - 1) / 2 * ROLL_STEP_RAD))
	local plane = makePart(
		folder,
		Vector3.new(planeW, planeH, HAND.CARD_STUDS.THICKNESS),
		baseCF * CFrame.new(HAND.OFFSET_STUDS.X, HAND.OFFSET_STUDS.Y, HAND.OFFSET_STUDS.Z),
		"CardSlot",
		1,
		FACE
	)
	-- Route C ships ONE AlwaysOnTop surface, so ZOffset is irrelevant and ZIndex does the layering.
	local gui = makeSurface(plane, true, nil)
	-- SizingMode is PixelsPerStud, so CanvasSize is not the knob: ONE UIScale at the collector maps design
	-- units to canvas pixels, exactly as the shipped carrier does per card. Everything below is design units.
	local scaler = Instance.new("UIScale")
	scaler.Scale = HAND.CANVAS_SCALE
	scaler.Parent = gui
	local units = DESIGN_PER_STUD
	for slot = 1, HAND_SIZE do
		local holder = Instance.new("Frame")
		holder.Name = `RouteCCard{slot}`
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.BackgroundTransparency = 1
		holder.ZIndex = slot
		holder.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H * math.cos(math.rad(HAND.LEAN_DEG)))
		local roll = (slot - (HAND_SIZE + 1) / 2) * HAND.ROLL_STEP_DEG
		holder.Rotation = -roll
		holder.Position = UDim2.fromOffset(
			planeW * units / 2 + (slot - (HAND_SIZE + 1) / 2) * HAND.STEP_STUDS * units,
			planeH * units / 2 - (ARC_R * (math.cos(math.rad(roll)) - 1)) * units
		)
		holder.Parent = gui
		drawFace(holder, slot, 1)
		-- The approximation, named where a reader of the tree will see it.
		local note = Instance.new("StringValue")
		note.Name = "NoShearAvailable"
		note.Value = "a rotated+squashed rectangle, NOT the projected quad"
		note.Parent = holder
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------------------------------

clearPrevious()

local folder = Instance.new("Folder")
folder.Name = PROBE_NAME
folder.Parent = Workspace

local baseCameraCF = CFrame.new(Vector3.new(0, BASE_Y, 0)) * CFrame.Angles(math.rad(CAMERA.PITCH_DEGREES), 0, 0)
local groupX: { [string]: number } = {}
for i, route in ROUTES do
	groupX[route] = (i - (#ROUTES + 1) / 2) * GROUP_SPAN_STUDS
end

for _, route in ROUTES do
	local groupCF = baseCameraCF * CFrame.new(groupX[route], 0, 0)
	if route == "A" then
		buildPartPerCard(folder, groupCF, true, true)
	elseif route == "B" then
		buildPartPerCard(folder, groupCF, false, false)
		-- The occluder, placed between the eye and the fan at HALF the hand's distance so it covers the middle of
		-- the fan and leaves the ends visible. Route B restores depth testing, so the hand can be clipped by
		-- table geometry and by the avatar: that cost belongs in the SAME photograph, not in a later surprise.
		-- This is the only part here that is opaque and the only one not named "CardSlot" -- it is not a card.
		makePart(
			folder,
			Vector3.new(HAND.CARD_STUDS.WIDTH, HAND.CARD_STUDS.HEIGHT, 0.3),
			groupCF * CFrame.new(HAND.OFFSET_STUDS.X, HAND.OFFSET_STUDS.Y, HAND.OFFSET_STUDS.Z / 2),
			"SpikeOccluder",
			0,
			SLAB
		)
	else
		buildRouteC(folder, groupCF)
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Camera, then the words. The pose is the REAL one: same FOV, same pitch, same hand distance; only the eye's
-- sideways position changes, so the group under judgement is centred.
-- ---------------------------------------------------------------------------------------------------------------

local camera = Workspace.CurrentCamera
local savedType, savedFov = camera.CameraType, camera.FieldOfView
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical -- VERIFIED default, set anyway: the 48 px proof needs it
camera.FieldOfView = CAMERA.FOV_DEGREES
if VIEW == "ALL" then
	camera.CFrame = baseCameraCF * CFrame.new(0, 0, GROUP_SPAN_STUDS * 1.6)
else
	local x = groupX[VIEW]
	assert(x ~= nil, `spike-layering: VIEW must be "A", "B", "C" or "ALL", got "{tostring(VIEW)}"`)
	camera.CFrame = baseCameraCF * CFrame.new(x, 0, 0)
end

print("================================================================================")
print("PHASE 04.1 WAVE 0 LAYERING SPIKE -- this is MANUAL-CHECKS M-18 and nothing else is")
print("================================================================================")
print(`  SurfaceGui host : {hostNote}`)
print(`  VIEW            : {VIEW}{if VIEW == "ALL" then "  <-- OVERVIEW ONLY, NOT the real pose" else ""}`)
print(`  config says     : Card.HAND.LAYERING_ROUTE = "{HAND.LAYERING_ROUTE}"  (PROVISIONAL until M-18 is signed)`)
print(
	string.format(
		"  geometry        : %d cards/route, card %.2f x %.2f studs, step %.2f, roll +-%.0f deg, lean %.0f deg,",
		HAND_SIZE,
		HAND.CARD_STUDS.WIDTH,
		HAND.CARD_STUDS.HEIGHT,
		HAND.STEP_STUDS,
		(HAND_SIZE - 1) / 2 * HAND.ROLL_STEP_DEG,
		HAND.LEAN_DEG
	)
)
print(
	string.format(
		"                    depth step %.2f, offset (%.1f, %.1f, %.1f), derived arc R = %.2f studs, end dip %.3f",
		HAND.DEPTH_STEP_STUDS,
		HAND.OFFSET_STUDS.X,
		HAND.OFFSET_STUDS.Y,
		HAND.OFFSET_STUDS.Z,
		ARC_R,
		ARC_R * (1 - math.cos((HAND_SIZE - 1) / 2 * ROLL_STEP_RAD))
	)
)
print(string.format("  camera          : FOV %d deg VERTICAL, pitch %d deg", CAMERA.FOV_DEGREES, CAMERA.PITCH_DEGREES))
print("")
print("THE DECISION RULE, which is one sentence and is all you have to answer:")
print("")
print("    With five overlapping cards whose only difference is slot index, does the RIGHT-HAND card's")
print("    edge cover the LEFT-HAND card's, at EVERY adjacent pair, from the seated camera?")
print("")
print("  Check all FOUR adjacent pairs -- 1/2, 2/3, 3/4 and 4/5. The end pair is the one that fails:")
print("  three centred cards can pass while slots 4 and 5 do not, which is why there are five here.")
print("  The red border and the corner index are what to look at. Under a right neighbour the index is ALL")
print("  a player can see, so if layering is wrong it is drawn by the wrong card.")
print("")
print("  Route A  AlwaysOnTop = true, ZOffset = slot        -- the spec as written")
print("  Route B  AlwaysOnTop = false, depth step does it   -- ALSO record whether the blue slab occludes any")
print("           card. It MAY: that is route B's named cost, not a bug in this probe. Answer it explicitly.")
print("  Route C  one SurfaceGui, five Frames, ZIndex       -- drawn WITHOUT SHEAR on purpose. Roblox GuiObjects")
print("           have no shear, so these rotated+squashed rectangles are the approximation route C would ship,")
print("           and their corners are NOT the projected corners. Route C is a BLOCKER to raise, not a flip.")
print("")
print("  For route A also record whether ANY card is occluded. It must not be -- that is one of A's two reasons")
print("  for existing (nothing here is near the map: the probe builds at y = " .. tostring(BASE_Y) .. ").")
print("")
print('  Then: ship A / ship B (set LAYERING_ROUTE = "Depth", M-23 goes LIVE) / STOP and raise route C.')
print("  If B is chosen AND a card is occluded, that is a BLOCKER: the remedy moves HAND.OFFSET_STUDS, which is")
print("  a Projection input, so the 48 px proof must be re-run. See 04.1-LAYERING-DECISION.md.")
print("")
print("AFTERWARDS, paste this -- Rojo mounts none of it and will not clean it up:")
print(`    workspace:FindFirstChild("{PROBE_NAME}"):Destroy()`)
print(
	`    for _, g in game.Players.LocalPlayer.PlayerGui:GetChildren() do if g.Name == "{PROBE_NAME}" then g:Destroy() end end`
)
print(`    workspace.CurrentCamera.CameraType = Enum.CameraType.{savedType.Name}`)
print(string.format("    workspace.CurrentCamera.FieldOfView = %g", savedFov))
print(`  (in edit mode the guis are under StarterGui, not PlayerGui -- delete them there instead)`)
print("  Record the verdict in BOTH MANUAL-CHECKS.md M-18 and 04.1-LAYERING-DECISION.md, with the photographs.")
