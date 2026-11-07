--!strict
-- The control-hiding seam (UX-02, D-29, D-30). A state machine over injected effects.
--
-- 1. PURE ZONE. Every effect is injected, which is the only reason UX-02's ordering can be a unit
--    test at all. Plan 04-18 supplies the Roblox backend.
-- 2. UX-02 / D-29: ONE seam, `hide` and `restore`, and no other API, so the mechanism can be swapped
--    without touching a caller. That matters because the mechanism sits on a removal path.
-- 3. THE LAYERS, AND WHY THEY ARE THE LAYERS. (a) the SERVER holds the avatar (plan 04-15), the only
--    security-relevant part; (b) the SERVER sets Dev*MovementMode = Scriptable, a server-only
--    property; (c) the CLIENT sets GuiService.TouchControlsEnabled = false to remove the thumbstick
--    graphics from under the left pile; (d) the CLIENT sinks movement keys with
--    ContextActionService:BindActionAtPriority returning Sink, so Space does not also jump. Nothing in
--    the default player scripts is mutated by any layer, so if a layer silently no-ops there is
--    nothing to restore and nothing left broken. The recorded fallback for a failing Input Action
--    System cell is "layer (a) alone plus (c) and (d)".
-- 4. THE LEGACY CONTROLS GETTER IS FORBIDDEN, and so is requiring the stock player-script module.
--    Neither appears in any official Roblox documentation and never has; a staff release post puts
--    the legacy endpoints on a removal path (default flips early 2027, legacy scripts removed
--    mid-2027), and the touch-modal property is deprecated in favour of TouchControlsEnabled. This
--    comment deliberately does not spell the identifiers: tests/card/controls.spec scans all of src/
--    for four of them, comments included.
-- 5. `restore` IS IDEMPOTENT AND UNBINDS BEFORE RE-ENABLING. Three community reports bear on this: a
--    key held during the disabled period not resuming until released (2024-04); a stuck jump button
--    and dead thumbstick after re-enabling on touch (2025-06); a frozen jump button after disabling
--    touch controls immediately following a jump (2024-01). None was re-tested here. All three bear
--    directly on D-30, and M-11 is where they are checked.
-- 6. D-30'S ORDER: destroy the overlay, restore controls, THEN start the flourish. Find order drives
--    SCORE-01..03, so a beat that holds a finisher still takes points off them; the flourish starts
--    last so it can never delay either step.
-- 7. THIS MODULE IS NOT SERVER-AUTHORITATIVE and must not be mistaken for the thing that keeps a seeker
--    at the table. A cheat client can re-enable its own controls; plan 04-15's server-side hold is the
--    only layer where holding the avatar is even possible. Client hiding is ergonomics.
--    UX-02 on device is NOT established by this module: it stays human-gated under M-11.

export type Effects = {
	setTouchControls: (enabled: boolean) -> (), -- 04-18: GuiService.TouchControlsEnabled
	bindSink: () -> (), -- 04-18: CAS BindActionAtPriority returning Sink
	unbindSink: () -> (), -- 04-18: CAS UnbindAction
	destroyOverlay: () -> (), -- 04-16: the hand ScreenGui, GONE not faded
	startFlourish: () -> (), -- 04-19: the driver's play()
}

export type Controls = {
	hide: (self: Controls) -> (),
	restore: (self: Controls) -> (),
	onLocalCompleted: (self: Controls) -> (),
	isHidden: (self: Controls) -> boolean,
}

local Controls = {}

function Controls.new(effects: Effects): Controls
	local hidden = false

	local self: Controls
	self = {
		hide = function(_: Controls)
			if hidden then
				return
			end
			hidden = true
			-- Graphics before the key sink, so a Space cannot jump in the gap.
			effects.setTouchControls(false)
			effects.bindSink()
		end,
		restore = function(_: Controls)
			if not hidden then
				return
			end
			hidden = false
			-- Unbind FIRST: a sink still bound when controls return would eat the finisher's first key.
			effects.unbindSink()
			effects.setTouchControls(true)
		end,
		onLocalCompleted = function(_: Controls)
			effects.destroyOverlay()
			self:restore()
			effects.startFlourish()
		end,
		isHidden = function(_: Controls): boolean
			return hidden
		end,
	}
	return self
end

return table.freeze(Controls)
