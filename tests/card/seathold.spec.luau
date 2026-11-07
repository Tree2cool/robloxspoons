--!strict
-- UX-02 / CARD-17 / D-30 gate for core/CardSeatHold: effect ORDER, IDEMPOTENCE, respawn and leak
-- behaviour against a recording fake. This proves the bookkeeping only. Whether the Roblox properties
-- the service sets actually hold an avatar against a determined client is UNPROVEN until M-11.
local CardSeatHold = require("../../src/server/core/CardSeatHold")
local Test = require("../harness/Test")

type Hold = CardSeatHold.CardSeatHold
type Ctor = (fx: CardSeatHold.Effects) -> Hold

local POSE: CardSeatHold.Pose = { position = { x = 1, y = 2, z = 3 }, look = { x = 0, y = 0, z = -1 } }

-- pivotFails: the first N pivotTo calls return false (character not loaded yet).
local function recorder(pivotFails: number): (CardSeatHold.Effects, { string }, { string })
	local log: { string } = {}
	local telemetry: { string } = {}
	local fails = pivotFails
	local fx: CardSeatHold.Effects = {
		setMovementScriptable = function(p: number, on: boolean)
			table.insert(log, `scriptable:{p}:{on}`)
		end,
		freezeHumanoid = function(p: number, on: boolean)
			table.insert(log, `freeze:{p}:{on}`)
		end,
		pivotTo = function(p: number, pose: CardSeatHold.Pose): boolean
			table.insert(log, `pivot:{p}:{pose.position.x},{pose.position.y},{pose.position.z}`)
			if fails > 0 then
				fails -= 1
				return false
			end
			return true
		end,
		onTelemetry = function(name: string, data: { [string]: number })
			table.insert(telemetry, `{name}:{data.playerId}`)
		end,
	}
	return fx, log, telemetry
end

local function join(log: { string }): string
	return table.concat(log, ",")
end

local function indexOf(log: { string }, name: string): number
	for i, v in log do
		if v == name then
			return i
		end
	end
	return -1
end

local function countPrefix(log: { string }, prefix: string): number
	local n = 0
	for _, v in log do
		if string.sub(v, 1, #prefix) == prefix then
			n += 1
		end
	end
	return n
end

-- The order/idempotence/respawn checks, shared so a mutant is judged by the same code as the real
-- module. Returns the problems and how many checks ran (non-vacuity).
local function problemsOf(ctor: Ctor): ({ string }, number)
	local problems: { string } = {}
	local checks = 0
	local function check(ok: boolean, msg: string)
		checks += 1
		if not ok then
			table.insert(problems, msg)
		end
	end
	do -- case 1: hold order
		local fx, log = recorder(0)
		ctor(fx):hold(7, POSE)
		check(join(log) == "scriptable:7:true,freeze:7:true,pivot:7:1,2,3", `hold order: {join(log)}`)
	end
	do -- case 3: release order (D-30)
		local fx, log = recorder(0)
		local h = ctor(fx)
		h:hold(7, POSE)
		h:release(7)
		local a, b = indexOf(log, "freeze:7:false"), indexOf(log, "scriptable:7:false")
		check(a > 0 and b > 0 and a < b, `release order: {join(log)}`)
	end
	do -- case 4: release idempotence
		local fx, log = recorder(0)
		local h = ctor(fx)
		h:hold(7, POSE)
		h:release(7)
		local n = #log
		h:release(7)
		check(#log == n, `second release added {#log - n} entries`)
		local fx2, log2 = recorder(0)
		ctor(fx2):release(9)
		check(#log2 == 0, `release of a never-held player logged {join(log2)}`)
	end
	do -- case 5: respawn
		local fx, log = recorder(0)
		local h = ctor(fx)
		h:hold(7, POSE)
		local n = #log
		h:onCharacterAdded(7)
		local tail = table.concat(log, ",", n + 1)
		check(tail == "freeze:7:true,pivot:7:1,2,3", `respawn tail: {tail}`)
	end
	return problems, checks
end

return function(t: Test.Runner)
	t.test("hold stops the avatar before placing it", function()
		local fx, log = recorder(0)
		local h = CardSeatHold.new(fx)
		h:hold(7, POSE)
		t.deepEqual(log, { "scriptable:7:true", "freeze:7:true", "pivot:7:1,2,3" })
		t.truthy(h:isHeld(7))
	end)

	t.test("hold is idempotent", function()
		local fx, log = recorder(0)
		local h = CardSeatHold.new(fx)
		h:hold(7, POSE)
		h:hold(7, POSE)
		h:hold(7, { position = { x = 9, y = 9, z = 9 }, look = POSE.look })
		t.equal(#log, 3)
		t.equal(h:heldCount(), 1)
	end)

	t.test("release restores capability before control (D-30)", function()
		local fx, log = recorder(0)
		local h = CardSeatHold.new(fx)
		h:hold(7, POSE)
		h:release(7)
		t.deepEqual({ log[4], log[5] }, { "freeze:7:false", "scriptable:7:false" })
		t.truthy(
			indexOf(log, "freeze:7:false") < indexOf(log, "scriptable:7:false"),
			"D-30: control must return after capability, or the finisher's first input hits a zero-speed humanoid and loses find-order points"
		)
		t.equal(h:isHeld(7), false)
	end)

	t.test("release is idempotent and safe on a player who was never held", function()
		local fx, log = recorder(0)
		local h = CardSeatHold.new(fx)
		h:hold(7, POSE)
		h:release(7)
		local n = #log
		h:release(7)
		t.equal(#log, n)
		local fx2, log2 = recorder(0)
		CardSeatHold.new(fx2):release(7)
		t.equal(#log2, 0)
	end)

	t.test("a respawn while held re-freezes and re-pivots, and does NOT re-set the movement mode", function()
		local fx, log = recorder(0)
		local h = CardSeatHold.new(fx)
		h:hold(7, POSE)
		local n = #log
		h:onCharacterAdded(7)
		t.deepEqual({ table.unpack(log, n + 1) }, { "freeze:7:true", "pivot:7:1,2,3" })
		t.equal(countPrefix(log, "scriptable:"), 1, "movement mode set exactly once")
		-- A player who is not held appends nothing.
		local m = #log
		h:onCharacterAdded(99)
		t.equal(#log, m)
		h:release(7)
		local k = #log
		h:onCharacterAdded(7)
		t.equal(#log, k, "a released player's respawn appends nothing")
	end)

	t.test("a deferred pose is applied when the character arrives", function()
		local fx, log, telemetry = recorder(1)
		local h = CardSeatHold.new(fx)
		h:hold(7, POSE)
		t.equal(countPrefix(log, "scriptable:7:true"), 1, "movement mode applied before the character exists")
		t.equal(countPrefix(log, "freeze:7:true"), 1, "freeze applied before the character exists")
		t.deepEqual(telemetry, { "seat_hold_deferred:7" })
		h:onCharacterAdded(7)
		t.equal(log[#log], "pivot:7:1,2,3", "same pose applied on arrival")
		t.equal(#telemetry, 1, "second pivot succeeded, no further deferral")
	end)

	t.test("forget drops the entry and fires nothing", function()
		local fx, log = recorder(0)
		local h = CardSeatHold.new(fx)
		h:hold(7, POSE)
		local n = #log
		h:forget(7)
		t.equal(#log, n)
		t.equal(h:isHeld(7), false)
		t.equal(h:heldCount(), 0)
		h:release(7)
		t.equal(#log, n, "later release is a no-op")
		h:forget(7)
		t.equal(h:heldCount(), 0)
	end)

	t.test("releaseAll releases every held player in ascending id", function()
		local fx, log = recorder(0)
		local h = CardSeatHold.new(fx)
		h:hold(9, POSE)
		h:hold(3, POSE)
		h:hold(6, POSE)
		local n = #log
		h:releaseAll()
		local order: { string } = {}
		for i = n + 1, #log do
			if string.sub(log[i], 1, 7) == "freeze:" then
				table.insert(order, string.split(log[i], ":")[2])
			end
		end
		t.deepEqual(order, { "3", "6", "9" })
		t.equal(h:heldCount(), 0)
	end)

	t.test("a non-integer playerId errors by name", function()
		local fx = recorder(0)
		local h = CardSeatHold.new(fx)
		local ok, err = pcall(function()
			h:hold(0 / 0, POSE)
		end)
		t.equal(ok, false)
		t.truthy(string.find(tostring(err), "CardSeatHold.hold", 1, true) ~= nil, tostring(err))
	end)

	t.test("MUTATION: four broken holds each turn a gate red", function()
		local clean, cleanChecks = problemsOf(CardSeatHold.new)
		print(`seathold: clean control {#clean} problems over {cleanChecks} checks`)
		t.deepEqual(clean, {}, "clean control: the real module must be green")
		t.truthy(cleanChecks == 5, `non-vacuity: only {cleanChecks} checks ran`)

		-- Each mutant is a self-contained implementation of the same interface driven through the same
		-- injected effects; only the named defect differs from the real module.
		local function broken(kind: string): Ctor
			return function(fx: CardSeatHold.Effects): Hold
				local held: { [number]: boolean } = {}
				local function stand(p: number)
					fx.freezeHumanoid(p, false)
					fx.setMovementScriptable(p, false)
				end
				local mutant: Hold
				mutant = {
					hold = function(_, p, pose)
						if held[p] then
							return
						end
						held[p] = true
						if kind == "pivot-first" then
							fx.pivotTo(p, pose)
						end
						fx.setMovementScriptable(p, true)
						fx.freezeHumanoid(p, true)
						if kind ~= "pivot-first" then
							fx.pivotTo(p, pose)
						end
					end,
					release = function(_, p)
						if kind == "not-idempotent" then
							stand(p)
							held[p] = nil
							return
						end
						if not held[p] then
							return
						end
						held[p] = nil
						if kind == "control-first" then
							fx.setMovementScriptable(p, false)
							fx.freezeHumanoid(p, false)
						else
							stand(p)
						end
					end,
					onCharacterAdded = function(_, p)
						if not held[p] then
							return
						end
						-- no-refreeze: a respawn hands back a fresh humanoid at default speed, so skipping
						-- the freeze would leave a seated player free to walk away.
						if kind ~= "no-refreeze" then
							fx.freezeHumanoid(p, true)
						end
						fx.pivotTo(p, POSE)
					end,
					forget = function(_, p)
						held[p] = nil
					end,
					releaseAll = function(_) end,
					isHeld = function(_, p)
						return held[p] == true
					end,
					heldCount = function(_)
						return 0
					end,
				}
				return mutant
			end
		end

		-- the unmutated twin of the same harness must itself be green, or the mutants prove nothing
		local twinProblems = problemsOf(broken("none"))
		t.deepEqual(twinProblems, {}, "clean control: the mutant harness with no defect must be green")

		local mutations = 0
		for _, kind in { "pivot-first", "control-first", "not-idempotent", "no-refreeze" } do
			local problems = problemsOf(broken(kind))
			print(`seathold: mutation {kind} -> {table.concat(problems, " | ")}`)
			t.truthy(#problems > 0, `{kind} stayed green`)
			mutations += 1
		end
		t.equal(mutations, 4)
	end)
end
