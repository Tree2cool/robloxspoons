--!strict
-- CARD-13 / CARD-19 routing gate (plan 04-05). The privacy decision is data in CardRouting; this file
-- enumerates it and drives the SHIPPED makePublisher / publish / split / assignCopies.
--
-- Every gate here has a clean control, a non-vacuity count, and a mutation expressed as an injected
-- broken dependency (the convention of tests/engine/valve.spec.luau), run through the SAME checking
-- helper as the clean path so the helper is proven able to fire.
local CardPool = require("../../src/shared/Config/CardPool")
local CardRouting = require("../../src/server/core/CardRouting")
local Engine = require("../../src/server/engine/Engine")
local Pool = require("../../src/server/engine/Pool")
local RecordingPublisher = require("../harness/RecordingPublisher")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

type Event = Types.Event

-- A deal for N players in the round, with a non-trivial seed (Rng's header documents small-seed weakness).
local function deal(n: number, seed: number): (Types.State, Types.EngineConfig)
	local config, seats = Pool.poolConfig(n, CardPool.EXTRA_RANKS, CardPool.JOKERS, CardPool.JOKER_MODE :: "Wild")
	local ids: { number } = {}
	for i = 1, seats do
		ids[i] = 9000 + i
	end
	return Engine.newRound(config, ids, Rng.new(seed)), config
end

-- Does the copy table give every natural rank exactly {1,2,3,4} and every joker 1? Returns the number
-- of ids checked, or -1 on a violation.
local function permutationIds(rankOf: { number }, copyOf: { number }, ranks: number): number
	local per: { { number } } = {}
	for r = 1, ranks do
		per[r] = {}
	end
	for id = 1, #rankOf do
		local copy = copyOf[id]
		if copy == nil then
			return -1
		end
		local r = rankOf[id]
		if r == Types.JOKER_RANK then
			if copy ~= 1 then
				return -1
			end
		else
			table.insert(per[r], copy)
		end
	end
	for r = 1, ranks do
		table.sort(per[r])
		local p = per[r]
		if #p ~= 4 or p[1] ~= 1 or p[2] ~= 2 or p[3] ~= 3 or p[4] ~= 4 then
			return -1
		end
	end
	return #rankOf
end

-- Calls that put a PRIVATE kind anywhere but toPlayer.
local function privateLeaks(rec: RecordingPublisher.RecordingPublisher): number
	local n = 0
	for _, c in rec.calls() do
		if CardRouting.PRIVATE_KINDS[c.kind] and c.method ~= "toPlayer" then
			n += 1
		end
	end
	return n
end

local function hasKey(tbl: any, key: string): boolean
	for k in tbl do
		if k == key then
			return true
		end
	end
	return false
end

-- The engine's exact valve emission order (Engine.luau): marker, then the Passed it explains.
local function valveEvents(): { Event }
	return {
		{ kind = "Drew", seat = 1, cardId = 5 },
		{ kind = "ValveForcedPass", seat = 2, cardId = 9, to = 3, lap = 512 },
		{ kind = "Passed", seat = 2, to = 3, cardId = 9 },
	}
end

local function userOf(seat: number): number
	return 100 + seat
end

return function(t: Test.Runner)
	t.test("KINDS, AUDIENCE and PRIVATE_KINDS are frozen and agree with each other", function()
		local seen = 0
		for _, kind in CardRouting.KINDS do
			seen += 1
			t.truthy(CardRouting.AUDIENCE[kind] ~= nil, `{kind} must have an audience`)
			if CardRouting.PRIVATE_KINDS[kind] then
				t.equal(CardRouting.AUDIENCE[kind], "owner", `{kind} is private so its audience is owner`)
			else
				t.equal(CardRouting.AUDIENCE[kind], "seated", `{kind} is public so its audience is seated`)
			end
		end
		t.equal(seen, 5, "non-vacuity: all five kinds exercised")
		local known: { [string]: boolean } = {}
		for _, kind in CardRouting.KINDS do
			known[kind] = true
		end
		for kind in CardRouting.AUDIENCE do
			t.truthy(known[kind], `AUDIENCE entry {kind} is not in KINDS`)
		end
		for kind in CardRouting.PRIVATE_KINDS do
			t.truthy(known[kind], `PRIVATE_KINDS entry {kind} is not in KINDS`)
		end
		t.truthy(table.isfrozen(CardRouting.KINDS), "KINDS frozen")
		t.truthy(table.isfrozen(CardRouting.AUDIENCE), "AUDIENCE frozen")
		t.truthy(table.isfrozen(CardRouting.PRIVATE_KINDS), "PRIVATE_KINDS frozen")
		local before = #CardRouting.KINDS
		t.falsy(
			pcall(function()
				table.insert(CardRouting.KINDS :: any, "Extra")
			end),
			"inserting into KINDS must throw"
		)
		t.equal(#CardRouting.KINDS, before, "KINDS length unchanged")
	end)

	t.test(
		"assertPublic throws for every private kind, passes for every public one, and throws on an unknown kind",
		function()
			local exercised = 0
			for _, kind in CardRouting.KINDS do
				exercised += 1
				if CardRouting.PRIVATE_KINDS[kind] then
					t.throws(function()
						CardRouting.assertPublic(kind)
					end, kind)
				else
					CardRouting.assertPublic(kind)
				end
			end
			t.equal(exercised, 5, "non-vacuity: five kinds exercised")
			t.throws(function()
				CardRouting.assertPublic("Nope")
			end, "Nope")
			t.throws(function()
				CardRouting.audienceOf("Nope")
			end, "Nope")
		end
	)

	t.test("makePublisher is the shipped assembly, and its broadcast methods guard before they fire", function()
		local fired = 0
		local effects: CardRouting.Effects = {
			fireToPlayer = function()
				fired += 1
			end,
			fireToMany = function()
				fired += 1
			end,
			fireToAll = function()
				fired += 1
			end,
			seatedUserIds = function()
				return { 1, 2, 3 }
			end,
		}
		local pub = CardRouting.makePublisher(effects)
		local attempted = 0
		for _, kind in CardRouting.KINDS do
			local isPrivate = CardRouting.PRIVATE_KINDS[kind] == true
			for _, method in { "toSeated", "toAll" } do
				attempted += 1
				fired = 0
				local ok = pcall(function()
					if method == "toSeated" then
						pub.toSeated(kind, {})
					else
						pub.toAll(kind, {})
					end
				end)
				t.equal(ok, not isPrivate, `{method}({kind}) throws exactly for private kinds`)
				if isPrivate then
					t.equal(fired, 0, `nothing may fire when {method}({kind}) throws`)
				else
					t.equal(fired, 1, `{method}({kind}) fires once`)
				end
			end
			attempted += 1
			fired = 0
			pub.toPlayer(7, kind, {})
			t.equal(fired, 1, `toPlayer({kind}) fires without a guard`)
		end
		t.equal(attempted, 15, "non-vacuity: 5 kinds x 3 methods")
		-- empty seated list is a no-op, not an error
		local empty = CardRouting.makePublisher({
			fireToPlayer = effects.fireToPlayer,
			fireToMany = effects.fireToMany,
			fireToAll = effects.fireToAll,
			seatedUserIds = function()
				return {}
			end,
		})
		fired = 0
		empty.toSeated("Table", {})
		t.equal(fired, 0, "empty seated list fires nothing and does not throw")
	end)

	t.test("MUTATION: a guard that does not throw lets a Sync reach a broadcast", function()
		local function wouldLeak(guard: (string) -> ()): boolean
			local ok = pcall(guard, "Sync")
			return ok
		end
		t.falsy(wouldLeak(CardRouting.assertPublic), "the real guard must refuse Sync")
		t.truthy(wouldLeak(function() end), "a no-op guard must be detected as a leak")
		-- the same mutation through the real assembly: a publisher built over a no-guard toSeated
		local rec = RecordingPublisher.new()
		local noGuard: CardRouting.Publisher = {
			toPlayer = rec.toPlayer,
			toSeated = rec.toSeated, -- MUTANT: no assertPublic
			toAll = rec.toAll,
		}
		noGuard.toSeated("Sync", {})
		t.equal(privateLeaks(rec), 1, "the leak counter sees a Sync broadcast")
	end)

	t.test("MUTATION: a Publisher fake that routes Sync via a broadcast turns the privacy gate red", function()
		-- Gate: publish a notice-bearing batch and count private kinds that left via a non-toPlayer method.
		local function run(leak: boolean): (number, number)
			local rec = RecordingPublisher.new({ leak = leak })
			CardRouting.publish(rec, valveEvents(), {}, userOf)
			-- a Sync as the shell would send it: private, to its owner
			rec.toPlayer(userOf(2), "Sync", { hand = { 9 } })
			return privateLeaks(rec), #rec.callsOfKind("Notice") + #rec.callsOfKind("Sync")
		end
		local cleanLeaks, cleanCalls = run(false)
		t.equal(cleanLeaks, 0, "clean control: no private kind is broadcast")
		t.equal(cleanCalls, 2, "non-vacuity: one Notice and one Sync were actually routed")
		local mutLeaks, mutCalls = run(true)
		t.equal(mutCalls, 2, "mutant routed the same two private calls")
		t.equal(mutLeaks, 2, "MUTANT: both private calls escape as broadcasts, so the gate fires (2)")
		print(`    [mutation] leak publisher: privateLeaks clean={cleanLeaks} mutant={mutLeaks}`)
	end)

	t.test("split strips ValveForcedPass and leaves the ordinary Passed the engine emits beside it", function()
		local publicList, notices = CardRouting.split(valveEvents(), {})
		t.equal(#publicList, 2, "Drew and Passed only")
		t.equal(publicList[1].kind, "Drew")
		t.equal(publicList[2].kind, "Passed")
		for _, e in publicList do
			t.falsy((e :: any).kind == "ValveForcedPass", "no public ValveForcedPass")
			t.falsy(hasKey(e, "lap"), "no lap key on any public entry")
		end
		t.deepEqual(notices, { { seat = 2, notice = { code = "ForcedPass", cardId = 9 } } })
	end)

	t.test("MUTATION: a router that passes ValveForcedPass through turns the gate red", function()
		-- Gate: returns the number of defects found in a public list.
		local function defects(publicList: { any }): number
			local n = 0
			for _, e in publicList do
				if e.kind == "ValveForcedPass" or hasKey(e, "lap") then
					n += 1
				end
			end
			return n
		end
		local function splitLeaky(events: { Event }, _copyOf: { number }): ({ any }, { any })
			local list: { any } = {}
			for _, e in events do
				table.insert(list, e)
			end
			return list, {}
		end
		local cleanList = CardRouting.split(valveEvents(), {})
		t.equal(defects(cleanList), 0, "clean control")
		local leakyList = splitLeaky(valveEvents(), {})
		t.equal(#leakyList, 3, "non-vacuity: the mutant forwarded all three events")
		t.equal(defects(leakyList), 1, "MUTANT: the ValveForcedPass is detected")
		print(`    [mutation] leaky split: defects clean={defects(cleanList)} mutant={defects(leakyList)}`)
	end)

	t.test("publish sends the ForcedPass notice to the affected player only, never to the table", function()
		-- Gate: who received a Notice. Returns the list of userIds.
		local function noticeRecipients(rec: RecordingPublisher.RecordingPublisher): { number }
			local out: { number } = {}
			for _, c in rec.callsOfKind("Notice") do
				if c.method == "toPlayer" and c.userId ~= nil then
					table.insert(out, c.userId)
				else
					table.insert(out, -1) -- a broadcast notice
				end
			end
			return out
		end
		local function runWith(resolver: (number) -> number): RecordingPublisher.RecordingPublisher
			local rec = RecordingPublisher.new()
			CardRouting.publish(rec, valveEvents(), {}, resolver)
			return rec
		end
		local rec = runWith(userOf)
		t.deepEqual(noticeRecipients(rec), { userOf(2) }, "clean: notice goes to seat 2's player only")
		t.equal(#rec.callsOfKind("Table"), 1, "one Table batch")
		t.equal(#rec.callsTo(userOf(3)), 1, "the downstream player sees only the Table batch, no Notice")
		t.equal(#rec.callsTo(userOf(2)), 2, "the affected player sees the batch and the Notice")
		for _, c in rec.callsOfKind("Table") do
			for _, e in c.payload do
				t.falsy(e.kind == "ForcedPass" or e.kind == "ValveForcedPass", "no valve marker in the public batch")
			end
		end

		-- MUTATION: notice sent to the wrong player. An injected noticeTarget = "successor" resolver
		-- (the seat's `to`). The publisher's leak option cannot see this: a wrong-target Notice is not a
		-- broadcast, so it needs its own mutant and its own gate (recipient identity).
		local successorOf: { [number]: number } = { [2] = 3 }
		local mutantResolver = function(seat: number): number
			return userOf(successorOf[seat] or seat)
		end
		local mut = runWith(mutantResolver)
		local recipients = noticeRecipients(mut)
		t.equal(#recipients, 1, "non-vacuity: the mutant still sent exactly one Notice")
		t.deepEqual(recipients, { userOf(3) }, "MUTANT: Notice lands on the successor")
		t.truthy(recipients[1] ~= userOf(2), "so the recipient gate (== affected player) would fire")
		print(`    [mutation] noticeTarget=successor: recipient clean={userOf(2)} mutant={recipients[1]}`)
		-- and the leak option is blind to it, which is exactly why the row is separate
		t.equal(privateLeaks(mut), 0, "the broadcast-leak gate does NOT see a wrong-target Notice")
	end)

	t.test("MUTATION: a Table payload that gains a rank for a non-retired card turns the rank gate red", function()
		local state, config = deal(6, 1000003 * 3 + 7)
		local copyOf = CardRouting.assignCopies(state.rankOf, config.ranks)
		local events: { Event } = {
			{ kind = "Drew", seat = 1, cardId = 4 },
			{ kind = "Passed", seat = 1, to = 2, cardId = 4 },
			{ kind = "Completed", seat = 2, rank = state.rankOf[10], retired = { 10, 11, 12, 13 }, fifth = 14 },
		}
		-- Gate: count entries that carry a rank outside Completed.
		local function rankLeaks(rec: RecordingPublisher.RecordingPublisher): (number, number)
			local leaks, inspected = 0, 0
			for _, c in rec.callsOfKind("Table") do
				for _, e in c.payload do
					inspected += 1
					if e.kind ~= "Completed" and hasKey(e, "rank") then
						leaks += 1
					end
				end
			end
			return leaks, inspected
		end
		local clean = RecordingPublisher.new()
		CardRouting.publish(clean, events, copyOf, userOf)
		local cleanLeaks, cleanInspected = rankLeaks(clean)
		t.equal(cleanInspected, 3, "non-vacuity: three public entries inspected")
		t.equal(cleanLeaks, 0, "clean control")

		-- MUTANT: a publisher wrapper that decorates every card-bearing entry with its rank.
		local mutant = RecordingPublisher.new()
		local decorating: CardRouting.Publisher = {
			toPlayer = mutant.toPlayer,
			toAll = mutant.toAll,
			toSeated = function(kind: string, payload: unknown)
				if kind == "Table" then
					for _, e in payload :: { any } do
						if e.cardId ~= nil then
							e.rank = state.rankOf[e.cardId]
						end
					end
				end
				mutant.toSeated(kind, payload)
			end,
		}
		CardRouting.publish(decorating, events, copyOf, userOf)
		local mutLeaks, mutInspected = rankLeaks(mutant)
		t.equal(mutInspected, 3, "mutant inspected the same entries")
		t.equal(mutLeaks, 2, "MUTANT: Drew and Passed now leak a rank")
		print(`    [mutation] rank decoration: rankLeaks clean={cleanLeaks} mutant={mutLeaks}`)
	end)

	t.test("split publishes the four retired faces and never the fifth card", function()
		local copyOf: { number } = {}
		for id = 1, 40 do
			copyOf[id] = (id % 4) + 1
		end
		local publicList = CardRouting.split(
			{ { kind = "Completed", seat = 1, rank = 7, retired = { 4, 11, 19, 27 }, fifth = 33 } },
			copyOf
		)
		t.equal(#publicList, 1)
		local entry = publicList[1] :: any
		t.equal(entry.kind, "Completed")
		t.equal(#entry.faces, 4)
		for i, face in entry.faces do
			t.equal(face.rank, 7, "face rank")
			t.equal(face.copy, copyOf[face.cardId], "face copy comes from the table")
			t.truthy(face.cardId ~= 33, `face {i} must not be the fifth card`)
		end
		t.falsy(hasKey(entry, "fifth"), "no fifth key on the public entry")
		t.falsy(hasKey(entry, "retired"), "no engine retired key leaked through")
	end)

	t.test("split errors by name on an unrecognised event kind", function()
		-- The exhaustiveness guarantee: a future engine event must be routed explicitly.
		t.throws(function()
			CardRouting.split({ { kind = "Teleported" } :: any }, {})
		end, "Teleported")
	end)

	t.test("assignCopies gives every natural rank a permutation of 1..4 across real deals", function()
		local start = os.clock()
		local idsSeen, expected, deals = 0, 0, 0
		local seedsPerN = 25
		for n = 3, 10 do
			for i = 1, seedsPerN do
				local state, config = deal(n, 1000003 * i + 7)
				local copyOf = CardRouting.assignCopies(state.rankOf, config.ranks)
				local checked = permutationIds(state.rankOf, copyOf, config.ranks)
				t.equal(checked, state.totalCards, `deal n={n} seed#{i} is a permutation`)
				idsSeen += checked
				expected += state.totalCards
				deals += 1
				t.deepEqual(CardRouting.assignCopies(state.rankOf, config.ranks), copyOf, "deterministic")
			end
		end
		local elapsed = os.clock() - start
		t.truthy(idsSeen > 0, "idsSeen == 0 would prove nothing: the loop did not run")
		t.equal(idsSeen, expected, "every id of every deal was checked")
		t.equal(deals, 200, "8 values of n x 25 seeds")
		print(`    [measure] assignCopies case: {deals} deals, {idsSeen} ids, {string.format("%.3f", elapsed)} s`)
		t.truthy(elapsed <= 0.25, `case 8 exceeded its 0.25 s allocation: {elapsed}`)
	end)

	t.test("MUTATION: skipping the ascending visit or reusing a copy index turns the permutation gate red", function()
		local state, config = deal(8, 1000003 * 5 + 7)
		local real = CardRouting.assignCopies(state.rankOf, config.ranks)
		t.equal(permutationIds(state.rankOf, real, config.ranks), state.totalCards, "clean control")

		-- MUTANT A: every id gets copy 1 (a reused index).
		local reused: { number } = {}
		for id = 1, #state.rankOf do
			reused[id] = 1
		end
		t.equal(permutationIds(state.rankOf, reused, config.ranks), -1, "MUTANT A: reused index is detected")

		-- MUTANT B: descending visit. Still a valid permutation, but DIFFERENT, so the ascending order
		-- is load-bearing and not incidental.
		local desc: { number } = {}
		local seen = table.create(config.ranks, 0)
		for id = #state.rankOf, 1, -1 do
			local r = state.rankOf[id]
			if r == Types.JOKER_RANK then
				desc[id] = 1
			else
				seen[r] += 1
				desc[id] = seen[r]
			end
		end
		t.equal(permutationIds(state.rankOf, desc, config.ranks), state.totalCards, "descending is still a permutation")
		local differing = 0
		for id = 1, #real do
			if real[id] ~= desc[id] then
				differing += 1
			end
		end
		t.truthy(differing > 0, "MUTANT B: descending visit differs from the ascending assignment")
		print(`    [mutation] copy assignment: reused index rejected, descending differs on {differing}/{#real} ids`)
	end)

	t.test("assignCopies errors when a rank does not have exactly four copies", function()
		-- Three copies of rank 1 and four of rank 2: a silent copy = 5 has no suit and renders blank.
		t.throws(function()
			CardRouting.assignCopies({ 1, 1, 1, 2, 2, 2, 2 }, 2)
		end, "rank 1")
	end)
end
