--!strict
-- NetServer transport gate (plan 04-13).
--
-- NetServer.luau names game:GetService, so LUNE CANNOT LOAD IT. Two things are available and this spec does
-- both: (a) drive the SHIPPED CardRouting.makePublisher assembly with NetServer-shaped effects, and (b) scan
-- the comment-stripped NetServer source for the one claim (a) cannot reach, namely that NetServer really
-- builds its publisher through makePublisher and hand-rolls nothing.
--
-- An earlier draft rebuilt the three publisher methods in this spec and never loaded the real NetServer,
-- so deleting the guard from production left the suite green. That is why the assembly is pure and shipped
-- from CardRouting, and why case 6 exists.
local CardRouting = require("../../src/server/core/CardRouting")
local Test = require("../harness/Test")
local fs = require("@lune/fs")
local lex = require("../../scripts/ci/lex")

type Fired = { target: string, kind: string }

-- NetServer-shaped effects over a fake roster: same semantics as NetServer's four closures, with the
-- Roblox send replaced by a recorder. Missing players are skipped silently, exactly as in production.
local function newRig(roster: { [number]: boolean }, seated: { number })
	local fired: { Fired } = {}
	local effects: CardRouting.Effects = {
		fireToPlayer = function(userId, kind, _payload)
			if not roster[userId] then
				return
			end
			table.insert(fired, { target = tostring(userId), kind = kind })
		end,
		fireToMany = function(userIds, kind, _payload)
			for _, userId in userIds do
				if roster[userId] then
					table.insert(fired, { target = tostring(userId), kind = kind })
				end
			end
		end,
		fireToAll = function(kind, _payload)
			table.insert(fired, { target = "ALL", kind = kind })
		end,
		seatedUserIds = function()
			return seated
		end,
	}
	return fired, effects
end

-- The same assembly with NO guard: the mutant. It is local to the spec on purpose; its only job is to prove
-- the clean path discriminates.
local function unguarded(effects: CardRouting.Effects): CardRouting.Publisher
	return {
		toPlayer = function(userId, kind, payload)
			effects.fireToPlayer(userId, kind, payload)
		end,
		toSeated = function(kind, payload)
			local ids = effects.seatedUserIds()
			if #ids == 0 then
				return
			end
			effects.fireToMany(ids, kind, payload)
		end,
		toAll = function(kind, payload)
			effects.fireToAll(kind, payload)
		end,
	}
end

local function attempt(fn: () -> ()): boolean
	local ok = pcall(fn)
	return ok
end

local function countOf(text: string, needle: string): number
	local n = 0
	local from = 1
	while true do
		local a, b = string.find(text, needle, from, true)
		if a == nil then
			return n
		end
		n += 1
		from = (b :: number) + 1
	end
end

-- Slice the stripped source between consecutive effect markers (the stated fallback shape: robust to
-- formatting, no nesting-depth tracking). The last closure ends at the closing of the makePublisher call.
local MARKERS = { "fireToPlayer = function(", "fireToMany = function(", "fireToAll = function(", "seatedUserIds = " }

type Scan = {
	makePublisher: number,
	assertPublic: number,
	bodies: { [string]: string },
	wholeFireClient: number,
	wholeFireAll: number,
	seatedFromDeps: boolean,
}

local function scan(raw: string): Scan
	local text = lex.stripComments(raw)
	local starts: { number } = {}
	for i, marker in MARKERS do
		local a = string.find(text, marker, 1, true)
		starts[i] = a or -1
	end
	local bodies: { [string]: string } = {}
	for i, marker in MARKERS do
		local from = starts[i]
		if from < 0 then
			bodies[marker] = ""
		else
			local to = #text
			if i < #MARKERS then
				local nextStart = starts[i + 1]
				if nextStart > from then
					to = nextStart - 1
				end
			else
				local close = string.find(text, "})", from, true)
				to = close or #text
			end
			bodies[marker] = string.sub(text, from, to)
		end
	end
	return {
		makePublisher = countOf(text, "CardRouting.makePublisher("),
		assertPublic = countOf(text, "assertPublic"),
		bodies = bodies,
		wholeFireClient = countOf(text, ":FireClient("),
		wholeFireAll = countOf(text, ":FireAllClients("),
		seatedFromDeps = string.find(text, "seatedUserIds = deps.seatedUserIds", 1, true) ~= nil,
	}
end

return function(t: Test.Runner)
	t.test("the shipped assembly guards before it fires, over NetServer's own effect shapes", function()
		local attempts = 0
		local throwing = 0
		for _, kind in CardRouting.KINDS do
			local isPrivate = CardRouting.PRIVATE_KINDS[kind] == true
			for _, method in { "toSeated", "toAll" } do
				local fired, effects = newRig({ [1] = true, [2] = true }, { 1, 2 })
				local pub = CardRouting.makePublisher(effects)
				local ok = attempt(function()
					if method == "toSeated" then
						pub.toSeated(kind, {})
					else
						pub.toAll(kind, {})
					end
				end)
				attempts += 1
				if isPrivate then
					throwing += 1
					t.falsy(ok, `{method}({kind}) must throw`)
					t.equal(#fired, 0, `{method}({kind}) fired before/after throwing`)
				else
					t.truthy(ok, `{method}({kind}) must succeed`)
					t.truthy(#fired >= 1, `{method}({kind}) must fire`)
				end
			end
		end
		t.equal(#CardRouting.KINDS, 6, "6 kinds exercised")
		t.equal(attempts, 12)
		t.equal(throwing, 4, "Sync and Notice x toSeated/toAll")
		print(`netguard case 1: {#CardRouting.KINDS} kinds, {attempts} attempted calls, {throwing} refused`)
	end)

	t.test("MUTATION: a publisher assembled without the guard fires a Sync to everyone", function()
		-- Reachable ONLY because the assembly lives in CardRouting (pure, loadable). With it in NetServer no
		-- spec could load it and this row could not fire.
		local firedBad, effectsBad = newRig({ [1] = true }, { 1 })
		local bad = unguarded(effectsBad)
		bad.toAll("Sync", {})
		bad.toSeated("Notice", {})
		t.equal(#firedBad, 2, "mutant leaks both private kinds")

		local firedGood, effectsGood = newRig({ [1] = true }, { 1 })
		local good = CardRouting.makePublisher(effectsGood)
		t.falsy(attempt(function()
			good.toAll("Sync", {})
		end))
		t.falsy(attempt(function()
			good.toSeated("Notice", {})
		end))
		t.equal(#firedGood, 0, "real assembly fires nothing")
		-- clean control: a public kind passes through both.
		good.toAll("Table", {})
		t.equal(#firedGood, 1)
	end)

	t.test("fireToPlayer returns silently for a userId with no Player", function()
		local fired, effects = newRig({ [7] = true }, {})
		local pub = CardRouting.makePublisher(effects)
		pub.toPlayer(99, "Sync", {})
		t.equal(#fired, 0)
		pub.toPlayer(7, "Sync", {})
		t.equal(#fired, 1)
		t.equal(fired[1].target, "7")
	end)

	t.test("toSeated with an empty seated list is a no-op, not an error", function()
		local fired, effects = newRig({ [1] = true }, {})
		local pub = CardRouting.makePublisher(effects)
		pub.toSeated("Table", {})
		pub.toSeated("Stall", {})
		t.equal(#fired, 0)
	end)

	t.test("roster removal frees the entry", function()
		local roster: { [number]: boolean } = { [1] = true, [2] = true }
		local fired, effects = newRig(roster, { 1, 2, 3 })
		local pub = CardRouting.makePublisher(effects)
		roster[1] = nil
		pub.toPlayer(1, "Sync", {})
		t.equal(#fired, 0, "removed user is a silent no-op")
		pub.toPlayer(2, "Sync", {})
		t.equal(#fired, 1, "other user still fires")
		-- seated list names 1 (gone) and 3 (never present): both skipped, 2 fires, no error.
		pub.toSeated("Table", {})
		t.equal(#fired, 2)
		t.equal(fired[2].target, "2")
	end)

	t.test("NetServer calls makePublisher and does NOT hand-roll the three methods", function()
		local raw = fs.readFile("src/server/services/NetServer.luau")
		local s = scan(raw)
		local strippedLen = #lex.stripComments(raw)

		t.equal(s.makePublisher, 1, "CardRouting.makePublisher( exactly once")
		t.equal(s.assertPublic, 0, "assertPublic named nowhere in NetServer")

		-- Per closure body: the send call is bound to ITS closure, not merely to the file.
		local function body(marker: string): string
			return s.bodies[marker]
		end
		local plain = body("fireToPlayer = function(")
		local many = body("fireToMany = function(")
		local all = body("fireToAll = function(")
		local seated = body("seatedUserIds = ")
		t.truthy(#plain > 0 and #many > 0 and #all > 0 and #seated > 0, "all four bodies sliced (non-vacuity)")
		t.equal(countOf(plain, ":FireClient("), 1, "fireToPlayer FireClient")
		t.equal(countOf(plain, "FireAllClients"), 0, "fireToPlayer never broadcasts")
		t.equal(countOf(many, ":FireClient("), 1, "fireToMany FireClient")
		t.equal(countOf(many, "FireAllClients"), 0, "fireToMany never broadcasts")
		t.equal(countOf(all, ":FireAllClients("), 1, "fireToAll FireAllClients")
		t.equal(countOf(all, "FireClient"), 0, "fireToAll never targets one")
		t.equal(countOf(seated, "FireClient"), 0, "seatedUserIds sends nothing (FireClient)")
		t.equal(countOf(seated, "FireAllClients"), 0, "seatedUserIds sends nothing (FireAllClients)")
		-- whole-file cross-check catches a send outside every closure
		t.equal(s.wholeFireClient, 2, "whole-file FireClient")
		t.equal(s.wholeFireAll, 1, "whole-file FireAllClients")
		t.truthy(s.seatedFromDeps, "seated audience is the one CardService supplies")

		-- negative controls on the scanning function itself
		local commentOnly = "-- CardRouting.makePublisher( is mentioned here\nlocal x = 1\n"
		local inCode = "local p = CardRouting.makePublisher({\n})\n"
		t.equal(scan(commentOnly).makePublisher, 0, "negative control: comment-only yields 0 hits")
		t.equal(scan(inCode).makePublisher, 1, "negative control: code yields 1 hit")
		-- binding control: a fireToPlayer that broadcasts must be visible to the per-body check.
		local broadcasting = "x({\nfireToPlayer = function(a)\n\tr:FireAllClients(a)\nend,\n"
			.. "fireToMany = function(a)\n\tr:FireClient(a)\nend,\nfireToAll = function(a)\n\tr:FireAllClients(a)\nend,\n"
			.. "seatedUserIds = d.x,\n})\n"
		local bs = scan(broadcasting)
		t.equal(
			countOf(bs.bodies["fireToPlayer = function("], "FireAllClients"),
			1,
			"negative control: broadcasting fireToPlayer is caught"
		)
		-- the decisive point: totals alone are satisfied by a swap, bodies are not
		local swapped = "x({\nfireToPlayer = function(a)\n\tr:FireAllClients(a)\nend,\n"
			.. "fireToMany = function(a)\n\tr:FireClient(a)\n\tr:FireClient(a)\nend,\nfireToAll = function(a)\nend,\n"
			.. "seatedUserIds = d.x,\n})\n"
		local ss = scan(swapped)
		t.equal(ss.wholeFireAll, 1, "swap keeps whole-file FireAllClients at 1")
		t.equal(ss.wholeFireClient, 2, "swap keeps whole-file FireClient at 2")
		t.equal(
			countOf(ss.bodies["fireToPlayer = function("], "FireAllClients"),
			1,
			"yet the per-body check sees the broadcast"
		)

		print(
			`netguard case 6: stripped length {strippedLen}, makePublisher {s.makePublisher}, assertPublic {s.assertPublic}, `
				.. `FireClient {s.wholeFireClient}, FireAllClients {s.wholeFireAll}, bodies {#plain}/{#many}/{#all}/{#seated} chars`
		)
	end)

	-- NOT covered here, and where it is covered instead:
	--  * that fireToPlayer really reaches the right client is a one-line adapter proven by guard R4 plus the
	--    Studio multi-client observation folded into M-12 ("two real clients, one sees only its own hand");
	--  * that parenting after connecting avoids the dropped-message window is a Studio observation;
	--  * that cross-instance ordering holds in practice is V-12's documented guarantee, re-checked
	--    2026-11-05, not re-measured here.
	-- Body slicing shipped as the stated fallback shape: text between consecutive effect markers.
end
