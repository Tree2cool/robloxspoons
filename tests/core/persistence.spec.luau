--!strict
-- FOUND-07 (code half): the persistence mode decision is pure, fail-closed, and ordered
-- Refuse > Mock > Real. The mode returned IS the reason code here, so each row asserts the exact mode:
-- an implementation that returned "Mock" for everything would fail every Real and Refuse row.
local PersistenceMode = require("../../src/server/core/PersistenceMode")
local Test = require("../harness/Test")

type Row = {
	name: string,
	state: string,
	isStudio: boolean,
	gameId: number,
	productionUniverseId: number,
	expected: PersistenceMode.Mode,
}

local PROD = 123
local DEV = 999

local function input(row: Row): PersistenceMode.Input
	return {
		dataStoreState = row.state,
		isStudio = row.isStudio,
		gameId = row.gameId,
		productionUniverseId = row.productionUniverseId,
	}
end

return function(t: Test.Runner)
	-- The seven behaviour rows from the plan, in order.
	local rows: { Row } = {
		{
			name = "live server on production with Access selects Real",
			state = "Access",
			isStudio = false,
			gameId = PROD,
			productionUniverseId = PROD,
			expected = "Real",
		},
		{
			name = "Studio tripwire: Studio on the production universe is Refused, not Real",
			state = "Access",
			isStudio = true,
			gameId = PROD,
			productionUniverseId = PROD,
			expected = "Refuse",
		},
		{
			name = "Studio on the dev universe with Access is allowed Real",
			state = "Access",
			isStudio = true,
			gameId = DEV,
			productionUniverseId = PROD,
			expected = "Real",
		},
		{
			name = "NotReady selects Mock",
			state = "NotReady",
			isStudio = false,
			gameId = PROD,
			productionUniverseId = PROD,
			expected = "Mock",
		},
		{
			name = "NoInternet selects Mock in Studio on dev",
			state = "NoInternet",
			isStudio = true,
			gameId = DEV,
			productionUniverseId = PROD,
			expected = "Mock",
		},
		{
			name = "NoAccess selects Mock on a live server",
			state = "NoAccess",
			isStudio = false,
			gameId = PROD,
			productionUniverseId = PROD,
			expected = "Mock",
		},
		{
			name = "precedence: Refuse beats Mock (Studio, production, NoAccess)",
			state = "NoAccess",
			isStudio = true,
			gameId = PROD,
			productionUniverseId = PROD,
			expected = "Refuse",
		},
		{
			name = "placeholder zero id never refuses an unrelated Studio session",
			state = "Access",
			isStudio = true,
			gameId = PROD,
			productionUniverseId = 0,
			expected = "Real",
		},
		{
			name = "unknown state string selects Mock, never Real",
			state = "SomethingNew",
			isStudio = false,
			gameId = PROD,
			productionUniverseId = PROD,
			expected = "Mock",
		},
	}
	for _, row in rows do
		t.test("decide: " .. row.name, function()
			t.equal(PersistenceMode.decide(input(row)), row.expected)
		end)
	end

	t.test("empty and wrong-case state strings select Mock (exact match on Access only)", function()
		for _, state in { "", "access", "ACCESS", "Access ", " Access", "Access\n" } do
			local mode = PersistenceMode.decide({
				dataStoreState = state,
				isStudio = false,
				gameId = DEV,
				productionUniverseId = PROD,
			})
			t.equal(mode, "Mock", "state '" .. state .. "'")
		end
	end)

	t.test("a nil or non-string state selects Mock, never errors", function()
		local garbage: { any } = { false, 0, {} }
		for i = 1, #garbage do
			local bad: any = {
				dataStoreState = garbage[i],
				isStudio = false,
				gameId = DEV,
				productionUniverseId = PROD,
			}
			t.equal(PersistenceMode.decide(bad), "Mock", "garbage state #" .. i)
		end
		local missing: any = { isStudio = false, gameId = DEV, productionUniverseId = PROD }
		t.equal(PersistenceMode.decide(missing), "Mock", "missing state")
	end)

	-- Exhaustive truth table: 5 states x isStudio x (production | other) x (real id | placeholder 0).
	-- The expected value is written as the three rules, independently of the implementation's layout.
	t.test("exhaustive table: Refuse > Mock > Real for every combination", function()
		local states = { "Access", "NotReady", "NoInternet", "NoAccess", "Bogus" }
		local studioFlags = { true, false }
		local gameIds = { PROD, DEV }
		local prodIds = { PROD, 0 }
		local count = 0
		for _, state in states do
			for _, studio in studioFlags do
				for _, gameId in gameIds do
					for _, prodId in prodIds do
						local expected: PersistenceMode.Mode
						if studio and prodId ~= 0 and gameId == prodId then
							expected = "Refuse"
						elseif state ~= "Access" then
							expected = "Mock"
						else
							expected = "Real"
						end
						local actual = PersistenceMode.decide({
							dataStoreState = state,
							isStudio = studio,
							gameId = gameId,
							productionUniverseId = prodId,
						})
						local label = string.format("state=%s studio=%s game=%d prod=%d", state, tostring(studio), gameId, prodId)
						t.equal(actual, expected, label)
						count += 1
					end
				end
			end
		end
		t.equal(count, 40)
	end)

	-- Real is only ever reachable with a proven Access state: nothing else may select it.
	t.test("Real is returned only when the state is exactly Access", function()
		for _, state in { "NotReady", "NoInternet", "NoAccess", "Bogus", "" } do
			for _, studio in { true, false } do
				for _, gameId in { PROD, DEV, 0 } do
					local mode = PersistenceMode.decide({
						dataStoreState = state,
						isStudio = studio,
						gameId = gameId,
						productionUniverseId = PROD,
					})
					t.truthy(mode ~= "Real", "state '" .. state .. "' must never select Real")
				end
			end
		end
	end)

	-- Secondary defence: the tripwire needs BOTH Studio and the production id. A live server on the
	-- production universe must not be refused (that would take the game offline).
	t.test("the tripwire is secondary: a live production server is never Refused", function()
		for _, state in { "Access", "NotReady", "NoInternet", "NoAccess", "Bogus" } do
			local mode = PersistenceMode.decide({
				dataStoreState = state,
				isStudio = false,
				gameId = PROD,
				productionUniverseId = PROD,
			})
			t.truthy(mode ~= "Refuse", "state '" .. state .. "' on a live server")
		end
	end)

	t.test("PersistenceMode exports exactly decide", function()
		local keys: { string } = {}
		for k in PersistenceMode :: any do
			table.insert(keys, tostring(k))
		end
		t.deepEqual(keys, { "decide" })
	end)
end
