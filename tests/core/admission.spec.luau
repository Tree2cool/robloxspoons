--!strict
-- FOUND-08: the 10-player cap and 3-player minimum as an explicit boundary table.
-- Every refusal asserts its SPECIFIC reason code. "Refused" alone is not a test: a function that
-- refuses everything would pass it (wave 2 found two tests passing for exactly that reason).
local Admission = require("../../src/server/core/Admission")
local Limits = require("../../src/shared/Config/Limits")
local Test = require("../harness/Test")

type Row = { name: string, count: any, admit: boolean, reason: Admission.Reason }
type StartRow = { name: string, ready: any, expected: boolean }

local NAN = 0 / 0
local CAP = 10
local MIN = 3

return function(t: Test.Runner)
	t.test("Limits holds the configured cap and minimum", function()
		t.equal(Limits.MAX_PLAYERS, CAP)
		t.equal(Limits.MIN_PLAYERS_TO_START, MIN)
	end)

	-- decide(currentCount, cap): currentCount is the number of players ALREADY in the server.
	local decideRows: { Row } = {
		{ name = "empty server admits", count = 0, admit = true, reason = "Ok" },
		{ name = "1 present admits", count = 1, admit = true, reason = "Ok" },
		{ name = "2 present admits", count = 2, admit = true, reason = "Ok" },
		{ name = "3 present admits", count = 3, admit = true, reason = "Ok" },
		{ name = "9 present admits the 10th player", count = 9, admit = true, reason = "Ok" },
		{ name = "10 present refuses the 11th player", count = 10, admit = false, reason = "ServerFull" },
		{ name = "11 present refuses", count = 11, admit = false, reason = "ServerFull" },
		{ name = "1000 present refuses", count = 1000, admit = false, reason = "ServerFull" },
		{ name = "negative count is invalid, not full", count = -1, admit = false, reason = "InvalidInput" },
		{ name = "non-integer count is invalid, not floored", count = 1.5, admit = false, reason = "InvalidInput" },
		{ name = "non-integer count 9.5 is not floored to 9", count = 9.5, admit = false, reason = "InvalidInput" },
		{ name = "NaN count is invalid", count = NAN, admit = false, reason = "InvalidInput" },
		{ name = "+inf count is invalid, not full", count = math.huge, admit = false, reason = "InvalidInput" },
		{ name = "-inf count is invalid", count = -math.huge, admit = false, reason = "InvalidInput" },
		{ name = "nil count is invalid", count = nil, admit = false, reason = "InvalidInput" },
		{ name = "string count is not coerced", count = "5", admit = false, reason = "InvalidInput" },
		{ name = "boolean count is invalid", count = true, admit = false, reason = "InvalidInput" },
	}
	for _, row in decideRows do
		t.test("decide(cap 10): " .. row.name, function()
			local d = Admission.decide(row.count, CAP)
			t.equal(d.reason, row.reason, "reason code")
			t.equal(d.admit, row.admit, "admit flag")
		end)
	end

	-- A nonsensical cap never admits anyone, and says why.
	local capRows: { { name: string, cap: any } } = {
		{ name = "cap 0", cap = 0 },
		{ name = "cap -5", cap = -5 },
		{ name = "cap 1.5", cap = 1.5 },
		{ name = "cap NaN", cap = NAN },
		{ name = "cap +inf", cap = math.huge },
		{ name = "cap -inf", cap = -math.huge },
		{ name = "cap nil", cap = nil },
		{ name = "cap string", cap = "10" },
	}
	for _, row in capRows do
		t.test("decide: bad cap never admits (" .. row.name .. ")", function()
			local d = Admission.decide(0, row.cap)
			t.equal(d.reason, "InvalidInput", "reason code")
			t.equal(d.admit, false)
		end)
	end

	t.test("decide: cap 1 admits the first player and refuses the second", function()
		t.equal(Admission.decide(0, 1).reason, "Ok")
		t.equal(Admission.decide(1, 1).reason, "ServerFull")
	end)

	t.test("decide: both arguments bad still reports InvalidInput", function()
		t.equal(Admission.decide(NAN, NAN).reason, "InvalidInput")
	end)

	t.test("decide: the boundary is exactly the cap, for any cap", function()
		for cap = 1, 20 do
			t.equal(Admission.decide(cap - 1, cap).reason, "Ok", "count " .. (cap - 1) .. " cap " .. cap)
			t.equal(Admission.decide(cap, cap).reason, "ServerFull", "count " .. cap .. " cap " .. cap)
		end
	end)

	t.test("decide: results are fresh tables (a caller cannot poison later decisions)", function()
		local first = Admission.decide(0, CAP)
		local mutable: any = first
		mutable.admit = false
		mutable.reason = "ServerFull"
		local second = Admission.decide(0, CAP)
		t.equal(second.admit, true)
		t.equal(second.reason, "Ok")
	end)

	-- canStartMatch(readyCount, min): the only predicate that may start a match.
	local startRows: { StartRow } = {
		{ name = "0 ready cannot start", ready = 0, expected = false },
		{ name = "1 ready cannot start", ready = 1, expected = false },
		{ name = "2 ready cannot start (one short of the minimum)", ready = 2, expected = false },
		{ name = "3 ready starts (exactly the minimum)", ready = 3, expected = true },
		{ name = "4 ready starts", ready = 4, expected = true },
		{ name = "9 ready starts", ready = 9, expected = true },
		{ name = "10 ready starts", ready = 10, expected = true },
		{ name = "negative never starts", ready = -1, expected = false },
		{ name = "non-integer 2.5 never starts", ready = 2.5, expected = false },
		{ name = "non-integer 3.5 never starts (not floored to 3)", ready = 3.5, expected = false },
		{ name = "NaN never starts", ready = NAN, expected = false },
		{ name = "+inf never starts (inf >= 3 would be true if unvalidated)", ready = math.huge, expected = false },
		{ name = "-inf never starts", ready = -math.huge, expected = false },
		{ name = "nil never starts", ready = nil, expected = false },
		{ name = "string '3' never starts", ready = "3", expected = false },
	}
	for _, row in startRows do
		t.test("canStartMatch(min 3): " .. row.name, function()
			t.equal(Admission.canStartMatch(row.ready, MIN), row.expected)
		end)
	end

	local minRows: { { name: string, min: any } } = {
		{ name = "min 0 (would start an empty lobby)", min = 0 },
		{ name = "min -1", min = -1 },
		{ name = "min 2.5", min = 2.5 },
		{ name = "min NaN", min = NAN },
		{ name = "min +inf", min = math.huge },
		{ name = "min nil", min = nil },
	}
	for _, row in minRows do
		t.test("canStartMatch: bad minimum never starts (" .. row.name .. ")", function()
			t.equal(Admission.canStartMatch(5, row.min), false)
		end)
	end

	t.test("canStartMatch never errors on garbage input", function()
		local garbage: { any } = { NAN, math.huge, -math.huge, -1, 1.5, "x", true, {} }
		for i, g in garbage do
			t.equal(Admission.canStartMatch(g, MIN), false, "garbage ready #" .. i)
			t.equal(Admission.canStartMatch(5, g), false, "garbage min #" .. i)
		end
	end)

	-- spoons = N - 2 must hold at the BOTTOM, not only the top: 3 players = 1 hider, 2 seekers, 1 spoon.
	-- No spoon-count function exists in Phase 1, so the formula is applied locally; what is under test
	-- is that the configured minimum is exactly the smallest roster that yields at least one spoon.
	t.test("spoons = N - 2 at the 3-player minimum: 1 hider, 2 seekers, 1 spoon", function()
		local n = Limits.MIN_PLAYERS_TO_START
		local hiders = 1
		t.equal(n - hiders, 2, "seekers")
		t.equal(n - 2, 1, "spoons")
		t.equal(Admission.canStartMatch(n, Limits.MIN_PLAYERS_TO_START), true)
	end)

	t.test("spoons = N - 2 at the 10-player cap: 1 hider, 9 seekers, 8 spoons", function()
		local n = Limits.MAX_PLAYERS
		t.equal(n - 1, 9, "seekers")
		t.equal(n - 2, 8, "spoons")
		t.equal(Admission.decide(n - 1, Limits.MAX_PLAYERS).reason, "Ok", "the 10th player is admitted")
		t.equal(Admission.canStartMatch(n, Limits.MIN_PLAYERS_TO_START), true)
	end)

	t.test("the minimum is exactly the smallest roster with at least one spoon", function()
		for n = 0, Limits.MAX_PLAYERS do
			local hasASpoon = n - 2 >= 1
			t.equal(Admission.canStartMatch(n, Limits.MIN_PLAYERS_TO_START), hasASpoon, "N = " .. n)
		end
	end)

	t.test("every admitted roster size can start and keeps spoons = N - 2 >= 1", function()
		for n = Limits.MIN_PLAYERS_TO_START, Limits.MAX_PLAYERS do
			t.equal(Admission.canStartMatch(n, Limits.MIN_PLAYERS_TO_START), true, "N = " .. n)
			t.truthy(n - 2 >= 1, "N = " .. n)
		end
	end)

	-- Two ways to start a match is one too many: the module must export exactly these two functions.
	t.test("Admission exports exactly decide and canStartMatch", function()
		local keys: { string } = {}
		for k in Admission :: any do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		t.deepEqual(keys, { "canStartMatch", "decide" })
	end)
end
