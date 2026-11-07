--!strict
-- The fixed-duration flourish driver (CARD-17, CARD-18 seam; D-30, D-31, D-32, D-33; checker FLAG F8).
--
-- 1. PURE ZONE, and that is the point. Every platform-shaped thing arrives through `Surface` or
--    `Scheduler`, which is why the duration cap, the yield cancellation and the input-sink scan are
--    testable headless at all. This file names no engine type and creates no thread of its own.
-- 2. D-32: THE DRIVER OWNS THE DURATION, THE CONTENT NEVER DOES. PROJECT.md requires every deal animation
--    to share one fixed duration; an unequal one would be a pay-to-win defect, not a cosmetic bug. Phase 7
--    supplies content through the INJECTED registry and can supply a `play`, never a duration. The
--    registry is injected rather than required so this gameplay-adjacent module has no import path to
--    cosmetics or shop code (CLAUDE.md rule 1, FOUND-05).
-- 3. D-30: nothing here may delay input. `play` runs in its own spawned thread, the cut-off is armed
--    FIRST, and the Completed handler has already destroyed the overlay and restored controls before this
--    runs (plan 04-11's ordering). Find order drives SCORE-01..03, so a beat that holds the finisher
--    still takes points off them.
-- 4. Checker FLAG F8, resolved: a periodic scan during the flight (not only at return and cut-off), a
--    ScreenGui-constrained parent for the Deal kind, and DISPLAY_ORDER below the hand's. An input-taking
--    object created MID-FLIGHT could otherwise sink input for part of the window, silently breaking
--    point 3.
-- 5. KNOWN LIMITS, stated plainly. A synchronous infinite loop inside `play` CANNOT be stopped in Luau;
--    a protected call bounds neither time nor yields. The defences are this timer, the periodic scan and
--    code review of any registered content, not a runtime guarantee. And "every parent a flourish could
--    reach" cannot be enumerated, so snapshot/diff is a SCAN, not a proof.
-- 6. A broken or missing flourish never breaks a completion. Unknown kinds, throwing content and scan
--    findings go to `onViolation`; nothing throws out of `play`.
-- 7. Exactly-once teardown, with a per-flight record so a stale delayed callback from a finished flight
--    is inert (the RoundLifecycle idiom).
--
-- D-37: this file never sees how a card copy is assigned; `faces` carries PUBLIC ranks only.
-- D-33: audio is a completion sting plus draw/pass sounds, played by the Surface. An empty asset id is
-- silent by contract, not an error. Whether any of it FEELS right is MANUAL-CHECKS M-17 / M-16.

local Card = require("../Config/Card")

export type Kind = "Deal" | "Completion"
export type Root = any -- an opaque handle only the Surface understands

export type FlourishContext = {
	root: Root,
	kind: Kind,
	seat: number,
	isLocalSeat: boolean,
	durationSeconds: number,
	faces: { number }, -- PUBLIC ranks only, completion only; empty for Deal
}
export type Entry = { kind: Kind, play: (ctx: FlourishContext) -> () }

export type Surface = {
	createRoot: (kind: Kind) -> Root,
	destroyRoot: (root: Root) -> (),
	-- Every input-taking descendant under `root` (five kinds, not just Active), as descriptions.
	scan: (root: Root) -> { string },
	-- Destroys what `scan` would report; returns the count. Needed so a mid-flight finding stops sinking
	-- input immediately instead of at the cut-off.
	destroyOffenders: (root: Root) -> number,
	-- A pre-play census of every parent a flourish could plausibly reach.
	snapshot: () -> any,
	-- New instances outside `root` since the snapshot, as descriptions.
	diff: (snapshot: any) -> { string },
	destroyEscaped: (snapshot: any) -> number,
}
export type Thread = any
export type Scheduler = {
	nowDeci: () -> number,
	delay: (seconds: number, fn: () -> ()) -> () -> (), -- returns a cancel function
	spawn: (fn: () -> ()) -> Thread,
	cancel: (thread: Thread) -> (),
}
export type Deps = {
	surface: Surface,
	scheduler: Scheduler,
	durationSeconds: number, -- Card.FLOURISH_DURATION_SECONDS; the DRIVER's number
	scanIntervalSeconds: number, -- Card.FLOURISH_SCAN_INTERVAL_SECONDS; F8
	registry: { [string]: Entry }, -- INJECTED. Phase 7 supplies skin flourishes; Phase 4 the defaults
	onViolation: (message: string) -> (),
}

export type Driver = {
	play: (self: Driver, kind: Kind, seat: number, isLocalSeat: boolean, faces: { number }) -> (),
	cancelAll: (self: Driver) -> (),
	activeCount: (self: Driver) -> number,
}

type Flight = {
	id: number,
	kind: string,
	root: Root,
	snapshot: any,
	thread: Thread?,
	cancelTeardown: (() -> ())?,
	cancelScan: (() -> ())?,
	playReturned: boolean,
	tornDown: boolean,
}

local Flourish = {}

-- F8: Deal is UI and lives inside a ScreenGui with an explicit DisplayOrder BELOW the hand, so an input
-- taking object it creates cannot sit over the hand. Completion is 3D and lives under a Workspace folder.
-- Strings, because this is a pure zone; plan 04-19's Surface maps them.
Flourish.ROOT_SURFACE = table.freeze({ Deal = "ScreenGui", Completion = "Workspace" })
Flourish.DISPLAY_ORDER = Card.FLOURISH_DISPLAY_ORDER

-- The default "Plain" flourishes as KEYFRAME DATA: a pure zone cannot tween, and data lets the spec
-- assert the totals arithmetically. Plan 04-19's Surface executes them.
Flourish.DEFAULTS = table.freeze({
	Completion = table.freeze({
		steps = table.freeze({
			table.freeze({ name = "flip", seconds = 0.3 }),
			table.freeze({ name = "hold", seconds = 0.5 }),
			table.freeze({ name = "slide", seconds = 0.4 }),
		}),
	}),
	Deal = table.freeze({ staggerSeconds = 0.1, cards = 4, settleBySeconds = 0.6 }),
})

local function roundMs(x: number): number
	return math.floor(x * 1000 + 0.5) / 1000
end

function Flourish.totalOf(def: any): number
	if type(def) ~= "table" then
		error("Flourish.totalOf: definition is not a table")
	end
	local steps = def.steps
	if steps ~= nil then
		if type(steps) ~= "table" or #steps == 0 then
			error("Flourish.totalOf: steps must be a non-empty array")
		end
		local sum = 0
		for _, step in steps do
			if
				type(step) ~= "table"
				or type(step.seconds) ~= "number"
				or step.seconds ~= step.seconds
				or step.seconds <= 0
			then
				error("Flourish.totalOf: every step needs a positive numeric seconds")
			end
			sum += step.seconds
		end
		return roundMs(sum)
	end
	if def.staggerSeconds ~= nil and def.cards ~= nil and def.settleBySeconds ~= nil then
		local stagger, cards, settle = def.staggerSeconds, def.cards, def.settleBySeconds
		if type(stagger) ~= "number" or type(cards) ~= "number" or type(settle) ~= "number" then
			error("Flourish.totalOf: Deal fields must be numbers")
		end
		if cards < 1 or stagger < 0 or settle <= stagger * (cards - 1) then
			error("Flourish.totalOf: Deal settleBySeconds must exceed the last card's start time")
		end
		return roundMs(settle)
	end
	error("Flourish.totalOf: unrecognised definition shape")
end

local function positiveFinite(x: any): boolean
	return type(x) == "number" and x == x and x > 0 and x < math.huge
end

function Flourish.new(deps: Deps): Driver
	if not positiveFinite(deps.durationSeconds) then
		error("Flourish.new: durationSeconds must be finite and positive")
	end
	if not positiveFinite(deps.scanIntervalSeconds) then
		error("Flourish.new: scanIntervalSeconds must be finite and positive")
	end
	if deps.scanIntervalSeconds >= deps.durationSeconds then
		error("Flourish.new: scanIntervalSeconds must be below durationSeconds (F8: no periodic scan)")
	end

	local surface, scheduler = deps.surface, deps.scheduler
	local flights: { [number]: Flight } = {}
	local nextId = 0
	local count = 0

	-- A throwing reporter must not take the completion with it.
	local function report(message: string)
		pcall(deps.onViolation, message)
	end

	-- Runs `fn` protected; returns the error text, or nil on success. (Void functions return one value
	-- from pcall, which the stricter checker will not destructure into two.)
	local function attempt(fn: () -> ()): string?
		local result = table.pack(pcall(fn))
		if result[1] == false then
			return tostring(result[2])
		end
		return nil
	end

	local function scanNow(flight: Flight)
		local ok, found = pcall(surface.scan, flight.root)
		if not ok then
			report(`{flight.kind} scan threw: {tostring(found)}`)
			return
		end
		local list = found :: { string }
		if #list > 0 then
			for _, description in list do
				report(`{flight.kind} input-taking object: {description}`)
			end
			-- Destroy now, not at the cut-off: this is what restores input mid-flight.
			local destroyed, err = pcall(surface.destroyOffenders, flight.root)
			if not destroyed then
				report(`{flight.kind} destroyOffenders threw: {tostring(err)}`)
			end
		end
	end

	local function teardown(flight: Flight)
		if flight.tornDown then
			return
		end
		flight.tornDown = true
		if flight.cancelTeardown ~= nil then
			flight.cancelTeardown()
		end
		if flight.cancelScan ~= nil then
			flight.cancelScan()
		end
		if flight.thread ~= nil then
			local thread = flight.thread
			local err = attempt(function()
				scheduler.cancel(thread)
			end)
			if err ~= nil then
				report(`{flight.kind} cancel threw: {err}`)
			end
		end
		-- Surface calls are individually protected so one failure cannot skip destroyRoot.
		scanNow(flight)
		local okDiff, escaped = pcall(surface.diff, flight.snapshot)
		if okDiff then
			for _, description in escaped :: { string } do
				report(`{flight.kind} escaped its root: {description}`)
			end
		else
			report(`{flight.kind} diff threw: {tostring(escaped)}`)
		end
		local okEscape, errEscape = pcall(surface.destroyEscaped, flight.snapshot)
		if not okEscape then
			report(`{flight.kind} destroyEscaped threw: {tostring(errEscape)}`)
		end
		local errRoot = attempt(function()
			surface.destroyRoot(flight.root)
		end)
		if errRoot ~= nil then
			report(`{flight.kind} destroyRoot threw: {errRoot}`)
		end
		if flights[flight.id] == flight then
			flights[flight.id] = nil
			count -= 1
		end
	end

	local function armScan(flight: Flight)
		flight.cancelScan = scheduler.delay(deps.scanIntervalSeconds, function()
			if flight.tornDown or flights[flight.id] ~= flight then
				return
			end
			scanNow(flight)
			armScan(flight)
		end)
	end

	local driver = {} :: Driver

	function driver.play(_self: Driver, kind: Kind, seat: number, isLocalSeat: boolean, faces: { number })
		local surfaceKind = (Flourish.ROOT_SURFACE :: any)[kind]
		if surfaceKind == nil then
			report(`unknown flourish kind: {tostring(kind)}`)
			return
		end
		local entry = deps.registry[kind]
		if entry == nil then
			report(`no flourish registered for kind: {tostring(kind)}`)
			return
		end

		-- 1. root
		local okRoot, root = pcall(surface.createRoot, kind)
		if not okRoot then
			report(`{kind} createRoot threw: {tostring(root)}`)
			return
		end
		-- 2. snapshot
		local okSnap, snapshot = pcall(surface.snapshot)
		if not okSnap then
			report(`{kind} snapshot threw: {tostring(snapshot)}`)
			attempt(function()
				surface.destroyRoot(root)
			end)
			return
		end

		nextId += 1
		local flight: Flight = {
			id = nextId,
			kind = kind,
			root = root,
			snapshot = snapshot,
			thread = nil,
			cancelTeardown = nil,
			cancelScan = nil,
			playReturned = false,
			tornDown = false,
		}
		flights[flight.id] = flight
		count += 1

		-- 3. arm the teardown BEFORE play can run: nothing play does can delay its own cancellation.
		flight.cancelTeardown = scheduler.delay(deps.durationSeconds, function()
			if flights[flight.id] == flight then
				teardown(flight)
			end
		end)
		-- 4. arm the first periodic scan (it re-arms itself while the flight is live).
		armScan(flight)

		local ctx: FlourishContext = {
			root = root,
			kind = kind,
			seat = seat,
			isLocalSeat = isLocalSeat,
			durationSeconds = deps.durationSeconds,
			faces = faces,
		}
		-- 5. only now spawn play, in its own cancellable thread.
		flight.thread = scheduler.spawn(function()
			local err = attempt(function()
				entry.play(ctx)
			end)
			if err ~= nil then
				report(`{kind} flourish threw: {err}`)
			end
			-- 6. play returned: one scan now.
			flight.playReturned = true
			if not flight.tornDown then
				scanNow(flight)
			end
		end)
	end

	function driver.cancelAll(_self: Driver)
		local all: { Flight } = {}
		for _, flight in flights do
			table.insert(all, flight)
		end
		for _, flight in all do
			teardown(flight)
		end
	end

	function driver.activeCount(_self: Driver): number
		return count
	end

	return driver
end

return Flourish
