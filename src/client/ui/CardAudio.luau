--!strict
-- The card phase's sound: a completion sting, and quiet feedback for the local player's OWN draw and pass.
--
--  1. D-33'S SPLIT. A sting for every completion, the same for everyone, plus your own draw and pass sounds.
--     DELIBERATELY NOTHING for another seat's pass: nine players passing constantly is a cacophony, and the
--     public Passed events drive the table's hops, not sound. There is no method here that could play one.
--  2. A STARTING GUN THAT MAKES NO SOUND IS NOT A STARTING GUN. That is why the sting is the one sound the
--     owner must supply. Whether it reads as a starting gun, and whether any of it sounds right, is M-17.
--  3. AN EMPTY ASSET ID IS SILENT, NEVER AN ERROR. The phase has to run before the assets land (M-16), and
--     every id in Config.Card.AUDIO ships empty. So `makeSound` returns before it creates anything: no
--     Sound exists for an empty id, and the method that would have played it returns immediately. The
--     guard precedes the only constructor, which tests/card/flourish_surface.spec.luau asserts by offset.
--  4. OWN DRAW AND OWN PASS ARE PLAYED ON THE PREDICTED LOCAL ACTION (CardClient calls them from the same
--     place it sends), so they land with the motion rather than with the server's acknowledgement, and are
--     cut off at AUDIO.OWN_CAP_SECONDS so a long asset cannot smear into the next action.
--  5. ONE SOUND PER ID, CREATED ONCE, parented to a Folder under SoundService and reused. A Sound whose id
--     fails to load never errors here; it simply makes no noise.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Card = require(ReplicatedStorage.Shared.Config.Card)

export type Audio = {
	-- Completion; same for everyone; played once at the moment of completion.
	sting: (self: Audio) -> (),
	ownDraw: (self: Audio) -> (),
	ownPass: (self: Audio) -> (),
	destroy: (self: Audio) -> (),
}

local CardAudio = {}

function CardAudio.new(): Audio
	local ids = Card.AUDIO
	local folder = Instance.new("Folder")
	folder.Name = "SpoonsCardAudio"

	-- Returns nil, and creates nothing, for an empty id (header point 3).
	local function makeSound(name: string, assetId: string): Sound?
		if assetId == "" then
			return nil
		end
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = assetId
		sound.Volume = ids.VOLUME
		sound.Parent = folder
		return sound
	end

	local sting = makeSound("Sting", ids.STING)
	local draw = makeSound("Draw", ids.DRAW)
	local pass = makeSound("Pass", ids.PASS)
	if sting ~= nil or draw ~= nil or pass ~= nil then
		folder.Parent = SoundService
	end

	local function play(sound: Sound?, capped: boolean)
		if sound == nil then
			return
		end
		sound.TimePosition = 0
		sound:Play()
		if capped then
			task.delay(ids.OWN_CAP_SECONDS, function()
				sound:Stop()
			end)
		end
	end

	local audio: Audio
	audio = {
		sting = function(_self: Audio)
			play(sting, false)
		end,
		ownDraw = function(_self: Audio)
			play(draw, true)
		end,
		ownPass = function(_self: Audio)
			play(pass, true)
		end,
		destroy = function(_self: Audio)
			folder:Destroy()
		end,
	}
	return audio
end

return CardAudio
