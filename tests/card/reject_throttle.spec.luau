--!strict
-- D-22 closure gate. The gateway order is untouched; the log is throttled at the sink instead.
-- Mutations are injected broken DEPENDENCIES driven through the same counting helper as the real
-- throttle (convention tests/engine/valve.spec.luau).
local Card = require("../../src/shared/Config/Card")
local RejectThrottle = require("../../src/server/core/RejectThrottle")
local Test = require("../harness/Test")

local NAN: number = 0 / 0

type Decision = RejectThrottle.Decision
type Throttleish = { note: (any, number, string, number) -> Decision }

local LOG_PER_WINDOW = 3
local WINDOW = 100

local function build(): RejectThrottle.RejectThrottle
	return RejectThrottle.new({ logPerWindow = LOG_PER_WINDOW, windowDeci = WINDOW })
end

-- Sends `codes` rejections for one user at one instant and returns how many were logged.
local function logged(th: Throttleish, userId: number, codes: { string }, nowDeci: number): (number, number)
	local n = 0
	for _, code in codes do
		if th:note(userId, code, nowDeci).log then
			n += 1
		end
	end
	return n, #codes
end

local function repeated(code: string, count: number): { string }
	local out = {}
	for _ = 1, count do
		table.insert(out, code)
	end
	return out
end

return function(t: Test.Runner)
	t.test("the shipped config values reach the throttle as the plan states", function()
		t.equal(Card.REJECT_LOG_PER_WINDOW, LOG_PER_WINDOW, "REJECT_LOG_PER_WINDOW")
		t.equal(math.floor(Card.REJECT_WINDOW_SECONDS * 10 + 1e-9), WINDOW, "10 s window is 100 deci")
	end)

	t.test("the first N rejections in a window log and the rest do not", function()
		local th = build()
		local decisions: { Decision } = {}
		for _ = 1, 10 do
			table.insert(decisions, th:note(1, "WrongPhase", 0))
		end
		t.equal(#decisions, 10, "decisions collected")
		local logs = 0
		for i, d in decisions do
			t.equal(d.log, i <= 3, `decision {i}`)
			if d.log then
				logs += 1
			end
		end
		t.equal(logs, 3, "logged lines")
	end)

	t.test("a closing window reports the suppressed count exactly once", function()
		local th = build()
		for _ = 1, 10 do
			th:note(1, "WrongPhase", 0)
		end
		t.equal(th:note(1, "WrongPhase", 100).summary, 7, "summary on the closing call")
		t.equal(th:note(1, "WrongPhase", 100).summary, nil, "summary repeated")
	end)

	t.test("a window with no suppression reports no summary", function()
		local th = build()
		th:note(1, "WrongPhase", 0)
		th:note(1, "WrongPhase", 0)
		t.equal(th:note(1, "WrongPhase", 150).summary, nil, "summary with nothing suppressed")
	end)

	t.test("the streak counts consecutive windows with rejections and resets on an empty one", function()
		local th = build()
		-- Intended behaviour: a window with no rejection at all is indistinguishable from an absent
		-- user, and both reset the streak to a fresh 1 on the next rejection.
		t.equal(th:note(1, "WrongPhase", 0).streak, 1, "window 1")
		t.equal(th:streakOf(1), 1, "streakOf window 1")
		t.equal(th:note(1, "WrongPhase", 100).streak, 2, "window 2")
		t.equal(th:note(1, "WrongPhase", 200).streak, 3, "window 3")
		t.equal(th:streakOf(1), 3, "streakOf window 3")
		t.equal(th:note(1, "WrongPhase", 600).streak, 1, "after three empty windows")
		t.equal(th:streakOf(1), 1, "streakOf after reset")
	end)

	t.test("users are independent and forget frees the entry", function()
		local th = build()
		for _ = 1, 3 do
			th:note(1, "WrongPhase", 0)
		end
		t.equal(th:note(2, "WrongPhase", 0).log, true, "user 2 consumed by user 1")
		t.equal(th:note(1, "WrongPhase", 0).log, false, "user 1 allowance exhausted")
		th:forget(1)
		t.equal(th:streakOf(1), 0, "streak after forget")
		t.equal(th:note(1, "WrongPhase", 0).log, true, "user 1 logs again after forget")
	end)

	t.test("MUTATION: an unthrottled sink logs every rejection", function()
		local noThrottle: Throttleish = {
			note = function(_self: any, _u: number, _c: string, _n: number): Decision
				return { log = true, streak = 0 }
			end,
		}
		local codes = repeated("WrongPhase", 10)
		local broken, total = logged(noThrottle, 1, codes, 0)
		local real = logged(build(), 1, codes, 0)
		print(`[throttle] MUTATION unthrottled logs {broken}/{total}; real throttle logs {real}/{total}`)
		t.equal(broken, 10, "the unthrottled variant should log 10 of 10")
		t.equal(real, 3, "the real throttle should log 3 of 10")
	end)

	t.test("MUTATION: throttling per code lets a mixed flood through", function()
		local seen: { [string]: number } = {}
		local perCode: Throttleish = {
			note = function(_self: any, userId: number, code: string, _n: number): Decision
				local key = `{userId}:{code}`
				local count = (seen[key] or 0) + 1
				seen[key] = count
				return { log = count <= LOG_PER_WINDOW, streak = 0 }
			end,
		}
		local codes = {
			"UnknownKey",
			"MissingKey",
			"NotFinite",
			"WrongType",
			"NotInteger",
			"OutOfRange",
			"NotTable",
			"ForbiddenType",
			"WrongPhase",
			"RateLimited",
		}
		local broken, total = logged(perCode, 1, codes, 0)
		local real = logged(build(), 1, codes, 0)
		print(`[throttle] MUTATION per-code logs {broken}/{total}; real throttle logs {real}/{total}`)
		t.equal(total, 10, "distinct codes driven")
		t.equal(broken, 10, "the per-code variant should log 10 of 10")
		t.equal(real, 3, "the real throttle should still log 3 of 10")
		-- Fixture validity: the per-code variant does throttle a repeated code.
		local same = logged(perCode, 2, repeated("WrongPhase", 10), 0)
		t.equal(same, 3, "the per-code variant never throttles, so the mutation proves nothing")
	end)

	t.test("non-finite input errors by name", function()
		local th = build()
		t.throws(function()
			th:note(1, "X", NAN)
		end, "nowDeci must be a finite non-negative integer")
		t.throws(function()
			th:note(1, "X", 1.5)
		end, "nowDeci must be a finite non-negative integer")
		t.throws(function()
			th:note(NAN, "X", 0)
		end, "userId must be a finite number")
		t.throws(function()
			th:note("1" :: any, "X", 0)
		end, "userId must be a finite number")
	end)
end
