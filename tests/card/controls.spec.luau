--!strict
-- UX-02 / D-29 / D-30 gate for src/shared/Card/Controls: effect ORDER and IDEMPOTENCE against a
-- recording fake, plus an src-wide scan for four forbidden identifiers.
-- This proves the state machine only. Whether hide/restore works on a device under either input
-- system is M-11 (human-gated); UX-02 is not claimed met here.
local Controls = require("../../src/shared/Card/Controls")
local Test = require("../harness/Test")
local fs = require("@lune/fs")

type Ctor = (effects: Controls.Effects) -> Controls.Controls

local function recorder(): (Controls.Effects, { string })
	local log: { string } = {}
	local effects: Controls.Effects = {
		setTouchControls = function(enabled: boolean)
			table.insert(log, `setTouchControls:{enabled}`)
		end,
		bindSink = function()
			table.insert(log, "bindSink")
		end,
		unbindSink = function()
			table.insert(log, "unbindSink")
		end,
		destroyOverlay = function()
			table.insert(log, "destroyOverlay")
		end,
		startFlourish = function()
			table.insert(log, "startFlourish")
		end,
	}
	return effects, log
end

local function indexOf(log: { string }, name: string): number
	for i, v in log do
		if v == name then
			return i
		end
	end
	return -1
end

local function join(log: { string }): string
	return table.concat(log, ",")
end

-- The two order assertions (cases 3 and 5), shared so a mutant is judged by the same check.
local function orderProblems(ctor: Ctor): { string }
	local problems: { string } = {}
	do
		local fx, log = recorder()
		local c = ctor(fx)
		c:hide()
		c:restore()
		if join(log) ~= "setTouchControls:false,bindSink,unbindSink,setTouchControls:true" then
			table.insert(problems, `restore order: {join(log)}`)
		end
	end
	do
		local fx, log = recorder()
		local c = ctor(fx)
		c:hide()
		c:onLocalCompleted()
		local flourish = indexOf(log, "startFlourish")
		local reenabled = indexOf(log, "setTouchControls:true")
		if
			join(log)
			~= "setTouchControls:false,bindSink,destroyOverlay,unbindSink,setTouchControls:true,startFlourish"
		then
			table.insert(problems, `completed order: {join(log)}`)
		end
		if not (flourish > reenabled and reenabled > 0) then
			table.insert(problems, `D-30: flourish at {flourish} not after controls restored at {reenabled}`)
		end
	end
	return problems
end

-- The scan. Needles are spelled plainly because this file lives under tests/, which it does not scan.
-- If it is ever moved into src/, build them from concatenated fragments the way check-guards.luau does
-- for its own rule names, or the scan will trip on itself.
local NEEDLES = { "GetControls", "PlayerModule", "ControlModule", "ModalEnabled" }

local function scanText(text: string): { string }
	local hits: { string } = {}
	for _, needle in NEEDLES do
		local from = 1
		while true do
			local s, e = string.find(text, needle, from, true)
			if not s then
				break
			end
			table.insert(hits, needle)
			from = (e :: number) + 1
		end
	end
	return hits
end

local function walk(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			walk(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

return function(t: Test.Runner)
	t.test("hide performs setTouchControls(false) then bindSink, in that order", function()
		local fx, log = recorder()
		local c = Controls.new(fx)
		c:hide()
		t.deepEqual(log, { "setTouchControls:false", "bindSink" })
		t.equal(c:isHidden(), true)
	end)

	t.test("hide is idempotent", function()
		local fx, log = recorder()
		local c = Controls.new(fx)
		c:hide()
		c:hide()
		c:hide()
		t.equal(#log, 2)
	end)

	t.test("restore unbinds the sink BEFORE re-enabling controls", function()
		local fx, log = recorder()
		local c = Controls.new(fx)
		c:hide()
		c:restore()
		t.deepEqual(log, { "setTouchControls:false", "bindSink", "unbindSink", "setTouchControls:true" })
		t.equal(c:isHidden(), false)
	end)

	t.test("restore is idempotent and safe to call twice, and safe before any hide", function()
		local fx, log = recorder()
		local c = Controls.new(fx)
		c:hide()
		c:restore()
		local after = #log
		c:restore()
		t.equal(#log, after, "second restore added effects")
		local fx2, log2 = recorder()
		local fresh = Controls.new(fx2)
		fresh:restore()
		t.equal(#log2, 0, "restore before hide must do nothing")
	end)

	t.test("D-30: onLocalCompleted destroys the overlay, restores controls, and starts the flourish LAST", function()
		local fx, log = recorder()
		local c = Controls.new(fx)
		c:hide()
		c:onLocalCompleted()
		t.deepEqual(log, {
			"setTouchControls:false",
			"bindSink",
			"destroyOverlay",
			"unbindSink",
			"setTouchControls:true",
			"startFlourish",
		})
		t.truthy(
			indexOf(log, "startFlourish") > indexOf(log, "setTouchControls:true"),
			"D-30: the flourish must start after controls return, or a held finisher loses SCORE-01..03 find-order points"
		)
	end)

	t.test("MUTATION: three broken orderings each turn the gate red", function()
		t.deepEqual(orderProblems(Controls.new), {}, "clean control: the real module must be green")

		local function broken(kind: string): Ctor
			return function(fx: Controls.Effects): Controls.Controls
				local real = Controls.new(fx)
				local self: Controls.Controls
				self = {
					hide = function(_)
						real:hide()
					end,
					restore = function(_)
						if kind == "reenable-first" then
							-- Controls return while the sink is still bound.
							if real:isHidden() then
								fx.setTouchControls(true)
								real:restore()
							end
							return
						end
						real:restore()
					end,
					onLocalCompleted = function(_)
						if kind == "never-restores" then
							fx.destroyOverlay()
							fx.startFlourish()
						elseif kind == "flourish-first" then
							fx.destroyOverlay()
							fx.startFlourish()
							real:restore()
						else
							real:onLocalCompleted()
						end
					end,
					isHidden = function(_)
						return real:isHidden()
					end,
				}
				return self
			end
		end

		local mutations = 0
		for _, kind in { "never-restores", "flourish-first", "reenable-first" } do
			local problems = orderProblems(broken(kind))
			print(`controls: mutation {kind} -> {table.concat(problems, " | ")}`)
			t.truthy(#problems > 0, `{kind} stayed green`)
			mutations += 1
		end
		t.equal(mutations, 3)
	end)

	t.test("no file under src/ names GetControls, PlayerModule, ControlModule or ModalEnabled", function()
		local files: { string } = {}
		walk("src", files)
		local total = 0
		for _, path in files do
			local hits = scanText(fs.readFile(path))
			for _, needle in hits do
				total += 1
				t.truthy(false, `{path} names {needle}`)
			end
		end
		print(`controls: forbidden-identifier scan walked {#files} files, {total} hits`)
		t.truthy(#files >= 20, `non-vacuity: only {#files} files scanned`)
		t.equal(total, 0)

		-- negative control: the same scanner over an in-memory string must report exactly one hit,
		-- otherwise a broken walker or needle would pass this case for the wrong reason.
		t.equal(#scanText("local c = pm:GetControls()"), 1, "negative control: scanner must fire once")
		t.equal(#scanText("nothing to see here"), 0)
	end)
end
