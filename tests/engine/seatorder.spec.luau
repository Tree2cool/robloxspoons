--!strict
-- CARD-05 / CARD-06: the seat order is one ranking and the dealer is its head.
-- RED step: these are plan 02-02 task 1's six <behavior> rows, written before SeatOrder.luau exists.
local Rng = require("../../src/server/engine/Rng")
local SeatOrder = require("../../src/server/engine/SeatOrder")
local Test = require("../harness/Test")

return function(t: Test.Runner)
	t.test("the first finder is the hider, so the dealer is the highest-placed SEATED finisher", function()
		local order = SeatOrder.nextSeatOrder({
			round = 2,
			roster = { 3, 7, 9, 11 },
			hiderId = 7,
			previousFindOrder = { 7, 3, 9 },
			previousSeatOrder = { 7, 3, 9, 11 },
		})
		t.deepEqual(order, { 3, 9, 11 })
		t.equal(SeatOrder.dealerOf(order), 3)
	end)

	t.test("zero finishers: the dealer is the head of everyone else by previous seat index", function()
		local order = SeatOrder.nextSeatOrder({
			round = 2,
			roster = { 5, 2, 8 },
			hiderId = 8,
			previousFindOrder = {},
			previousSeatOrder = { 2, 5, 8 },
		})
		t.deepEqual(order, { 2, 5 })
	end)

	t.test("one finisher, then two non-finishers by previous seat index", function()
		local order = SeatOrder.nextSeatOrder({
			round = 2,
			roster = { 1, 4, 6, 9 },
			hiderId = 9,
			previousFindOrder = { 4 },
			previousSeatOrder = { 6, 1, 4 },
		})
		t.deepEqual(order, { 4, 6, 1 })
	end)

	t.test("a departed finisher is filtered BEFORE the head is taken, never after", function()
		local order = SeatOrder.nextSeatOrder({
			round = 2,
			roster = { 1, 2, 3 },
			hiderId = 3,
			previousFindOrder = { 12 },
			previousSeatOrder = { 2, 1, 12 },
		})
		t.deepEqual(order, { 2, 1 })
	end)

	t.test("round 1 is a seeded shuffle of the roster minus the hider", function()
		local function roundOne(seed: number)
			return SeatOrder.nextSeatOrder({
				round = 1,
				roster = { 1, 2, 3, 4 },
				hiderId = 2,
				previousFindOrder = {},
				previousSeatOrder = {},
				rng = Rng.new(seed),
			})
		end
		local a = roundOne(99)
		t.equal(#a, 3)
		t.deepEqual(roundOne(99), a)
		local seen: { [number]: boolean } = {}
		for _, id in a do
			seen[id] = true
		end
		t.deepEqual(seen, { [1] = true, [3] = true, [4] = true })
	end)

	t.test("a joiner sorts after all non-finishers and after the previous hider, by join order", function()
		local order = SeatOrder.nextSeatOrder({
			round = 2,
			roster = { 1, 2, 3, 4, 9 },
			hiderId = 4,
			previousFindOrder = {},
			previousSeatOrder = { 2, 1, 4 },
			previousHider = 3,
		})
		t.deepEqual(order, { 2, 1, 3, 9 })
	end)
end
