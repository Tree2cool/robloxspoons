--!strict
-- FOUND-04 / threats T-1-01 T-1-02 T-1-03 T-1-27 T-1-40. Every rejection asserts its SPECIFIC code and that
-- nothing was dispatched: a gateway that rejected everything would pass a suite that only checked "rejected".
-- Time is the harness FakeClock; nothing sleeps. The manifest is test-local so no test intent ships.
-- (tests/ is not a Rojo mount, so requiring across src/server and src/shared here is legal.)
local Bucket = require("../../src/server/core/Bucket")
local FakeClock = require("../harness/FakeClock")
local Gateway = require("../../src/server/core/Gateway")
local Manifest = require("../../src/shared/Net/Manifest")
local RateLimits = require("../../src/shared/Config/RateLimits")
local Test = require("../harness/Test")
local Validate = require("../../src/shared/Net/Validate")

local NAN: number = 0 / 0

type Rejection = { userId: number, intent: unknown, code: string }
type Dispatched = { userId: number, intent: string, payload: unknown }

type Harness = {
	gateway: Gateway.Gateway,
	clock: FakeClock.FakeClock,
	bucket: Bucket.Store,
	dispatched: { Dispatched },
	rejections: { Rejection },
	errors: { unknown },
	setPhase: (phase: string) -> (),
	throwOnDispatch: boolean,
}

return function(t: Test.Runner)
	local function harness(): Harness
		local clock = FakeClock.new()
		local bucket = Bucket.new({ clock = clock })
		local phase: string = "Round"
		local h: Harness = {
			gateway = nil :: any,
			clock = clock,
			bucket = bucket,
			dispatched = {},
			rejections = {},
			errors = {},
			setPhase = function(p: string)
				phase = p
			end,
			throwOnDispatch = false,
		}
		local manifest = {
			intents = {
				Echo = {
					phases = { "Round" :: Gateway.RoundPhase },
					validate = Validate.exactKeys({ value = Validate.integer({ min = 0, max = 100 }) }),
				},
				Ready = {
					phases = { "Lobby" :: Gateway.RoundPhase },
					validate = Validate.exactKeys({}),
				},
			} :: { [string]: Gateway.Intent },
			isKnown = function(name: unknown): boolean
				if type(name) ~= "string" or #name == 0 or #name > 64 then
					return false
				end
				return (({ Echo = true, Ready = true }) :: { [string]: boolean })[name] == true
			end,
		}
		h.gateway = Gateway.new({
			manifest = manifest,
			bucket = bucket,
			rateFor = RateLimits.forIntent,
			getPhase = function(): Gateway.RoundPhase
				return phase :: any
			end,
			dispatch = function(userId: number, intent: string, payload: unknown)
				if h.throwOnDispatch then
					error("handler exploded")
				end
				table.insert(h.dispatched, { userId = userId, intent = intent, payload = payload })
			end,
			onReject = function(userId: number, intent: unknown, code: string)
				table.insert(h.rejections, { userId = userId, intent = intent, code = code })
			end,
			onError = function(_userId: number, _intent: string, err: unknown)
				table.insert(h.errors, err)
			end,
		})
		return h
	end

	local function expectRejected(h: Harness, userId: number, intent: unknown, payload: unknown, code: string)
		local before = #h.dispatched
		local ok, got = h.gateway:handle(userId, intent, payload)
		t.equal(ok, false, "must be rejected")
		t.equal(got, code, "wrong rejection code")
		t.equal(#h.dispatched, before, "a rejected message must never reach dispatch")
		local last = h.rejections[#h.rejections]
		t.equal(last.code, code, "onReject must report the same code")
	end

	t.test("a valid message is accepted, returns (true, Ok), and dispatches exactly once", function()
		local h = harness()
		local ok, code = h.gateway:handle(7, "Echo", { value = 5 })
		t.equal(ok, true)
		t.equal(code, "Ok")
		t.equal(#h.dispatched, 1)
		t.equal(h.dispatched[1].userId, 7)
		t.equal(h.dispatched[1].intent, "Echo")
		t.equal(#h.rejections, 0)
	end)

	t.test("the handler receives the CLEAN copy, not the raw payload", function()
		local h = harness()
		local raw = { value = 5 }
		h.gateway:handle(1, "Echo", raw)
		t.equal(#h.dispatched, 1)
		t.equal(rawequal(h.dispatched[1].payload, raw), false, "raw payload must not be handed over")
		t.deepEqual(h.dispatched[1].payload, { value = 5 })
	end)

	t.test("UnknownIntent: unknown name rejected before anything else", function()
		local h = harness()
		expectRejected(h, 1, "DrawCard", {}, "UnknownIntent")
	end)

	t.test("UnknownIntent: number, nil, empty and 200-char names", function()
		local h = harness()
		expectRejected(h, 1, 42, {}, "UnknownIntent")
		expectRejected(h, 1, nil, {}, "UnknownIntent")
		expectRejected(h, 1, "", {}, "UnknownIntent")
		expectRejected(h, 1, string.rep("a", 200), {}, "UnknownIntent")
		expectRejected(h, 1, { "Echo" }, {}, "UnknownIntent")
	end)

	t.test("unknown names allocate NO bucket state (100 attempts)", function()
		local h = harness()
		for i = 1, 100 do
			h.gateway:handle(i, "Nope" .. i, { value = 1 })
		end
		t.equal(h.bucket:count(), 0, "bucket.count() must stay 0")
		t.equal(h.bucket:rejections(), 0, "the bucket must not even have been consulted")
		t.equal(#h.rejections, 100)
		for _, r in h.rejections do
			t.equal(r.code, "UnknownIntent")
		end
		t.equal(#h.dispatched, 0)
	end)

	t.test("RateLimited: beyond the burst, then allowed again after one refill interval", function()
		local h = harness()
		for i = 1, 4 do
			local ok = h.gateway:handle(1, "Echo", { value = i })
			t.equal(ok, true, `attempt {i} within burst`)
		end
		expectRejected(h, 1, "Echo", { value = 1 }, "RateLimited")
		expectRejected(h, 1, "Echo", { value = 1 }, "RateLimited")
		t.equal(#h.dispatched, 4)
		h.clock.advance(0.25) -- refill 4/s: one token
		local ok, code = h.gateway:handle(1, "Echo", { value = 1 })
		t.equal(ok, true)
		t.equal(code, "Ok")
		t.equal(#h.dispatched, 5)
		expectRejected(h, 1, "Echo", { value = 1 }, "RateLimited")
	end)

	t.test("every attempt consumes a token: 5 malformed against burst 4 = 4 MissingKey then 1 RateLimited", function()
		local h = harness()
		for _ = 1, 5 do
			h.gateway:handle(1, "Echo", {})
		end
		local codes = {}
		for _, r in h.rejections do
			table.insert(codes, r.code)
		end
		t.deepEqual(codes, { "MissingKey", "MissingKey", "MissingKey", "MissingKey", "RateLimited" })
		t.equal(#h.dispatched, 0)
	end)

	t.test("a malformed flood cannot starve a different user", function()
		local h = harness()
		for _ = 1, 10 do
			h.gateway:handle(1, "Echo", {})
		end
		local ok = h.gateway:handle(2, "Echo", { value = 1 })
		t.equal(ok, true, "user 2 has its own bucket")
		t.equal(#h.dispatched, 1)
		t.equal(h.dispatched[1].userId, 2)
	end)

	t.test("two userIds do not share bucket state", function()
		local h = harness()
		for _ = 1, 4 do
			h.gateway:handle(1, "Echo", { value = 1 })
		end
		expectRejected(h, 1, "Echo", { value = 1 }, "RateLimited")
		local ok = h.gateway:handle(2, "Echo", { value = 1 })
		t.equal(ok, true)
		t.equal(h.bucket:count(), 2)
	end)

	t.test("forget frees a user's state and the next attempt behaves like a fresh user", function()
		local h = harness()
		for _ = 1, 4 do
			h.gateway:handle(1, "Echo", { value = 1 })
		end
		expectRejected(h, 1, "Echo", { value = 1 }, "RateLimited")
		t.equal(h.bucket:count(), 1)
		h.gateway:forget(1)
		t.equal(h.bucket:count(), 0, "forget must free per-player state")
		local ok, code = h.gateway:handle(1, "Echo", { value = 1 })
		t.equal(ok, true)
		t.equal(code, "Ok")
	end)

	t.test("WrongPhase: Echo in Lobby, Ready in Round, nothing dispatched", function()
		local h = harness()
		h.setPhase("Lobby")
		expectRejected(h, 1, "Echo", { value = 1 }, "WrongPhase")
		h.setPhase("Round")
		expectRejected(h, 1, "Ready", {}, "WrongPhase")
		h.setPhase("Lobby")
		local ok = h.gateway:handle(1, "Ready", {})
		t.equal(ok, true)
		t.equal(#h.dispatched, 1)
	end)

	t.test("WrongPhase is decided before the bucket: it neither charges a token nor allocates state", function()
		local h = harness()
		h.setPhase("Podium")
		for _ = 1, 10 do
			h.gateway:handle(1, "Echo", { value = 1 })
		end
		t.equal(h.bucket:count(), 0)
		for _, r in h.rejections do
			t.equal(r.code, "WrongPhase", "never RateLimited: phase precedes the bucket")
		end
		h.setPhase("Round")
		local ok = h.gateway:handle(1, "Echo", { value = 1 })
		t.equal(ok, true, "full burst still available")
	end)

	t.test("D-20 drift: Gateway.PHASES deep-equals Manifest.PHASES", function()
		t.deepEqual(Gateway.PHASES, Manifest.PHASES)
		t.equal(#Gateway.PHASES, 4)
		t.equal(table.isfrozen(Gateway.PHASES), true)
	end)

	t.test(
		"D-20 at runtime: a phase outside the vocabulary (Scramble) rejects every gated intent as WrongPhase",
		function()
			local h = harness()
			-- `:: any` is REQUIRED: getPhase is typed () -> RoundPhase, and RoundPhase must not be widened.
			h.setPhase("Scramble" :: any)
			expectRejected(h, 1, "Echo", { value = 1 }, "WrongPhase")
			expectRejected(h, 1, "Ready", {}, "WrongPhase")
			t.equal(#h.dispatched, 0)
			h.setPhase("round") -- case matters
			expectRejected(h, 1, "Echo", { value = 1 }, "WrongPhase")
			t.equal(#h.dispatched, 0)
		end
	)

	local ONE_MANY = string.rep("a", 500)
	local VECTORS: { { label: string, payload: unknown, code: string } } = {
		{ label = "valid", payload = { value = 1 }, code = "Ok" },
		{ label = "valid boundary 0", payload = { value = 0 }, code = "Ok" },
		{ label = "valid boundary 100", payload = { value = 100 }, code = "Ok" },
		{ label = "NaN", payload = { value = NAN }, code = "NotFinite" },
		{ label = "+inf", payload = { value = math.huge }, code = "NotFinite" },
		{ label = "-inf", payload = { value = -math.huge }, code = "NotFinite" },
		{ label = "1.5", payload = { value = 1.5 }, code = "NotInteger" },
		{ label = "-1", payload = { value = -1 }, code = "OutOfRange" },
		{ label = "101", payload = { value = 101 }, code = "OutOfRange" },
		{ label = "500-char string as value", payload = { value = ONE_MANY }, code = "WrongType" },
		{ label = "function as value", payload = { value = function() end }, code = "ForbiddenType" },
		{ label = "empty table", payload = {}, code = "MissingKey" },
		{ label = "extra key", payload = { value = 1, extra = 2 }, code = "UnknownKey" },
		{ label = "wrong key", payload = { wrong = 1 }, code = "MissingKey" },
		{ label = "string payload", payload = "not a table", code = "NotTable" },
		{ label = "500-char string payload", payload = ONE_MANY, code = "NotTable" },
		{ label = "number payload", payload = 42, code = "NotTable" },
		{ label = "nil payload", payload = nil, code = "NotTable" },
		{ label = "boolean payload", payload = true, code = "NotTable" },
	}

	t.test("vector table: each payload yields its specific code; dispatch count equals accepted count", function()
		local accepted = 0
		local totalDispatched = 0
		for _, v in VECTORS do
			local h = harness() -- fresh bucket per vector so the rate limit cannot mask the code
			local ok, code = h.gateway:handle(1, "Echo", v.payload)
			t.equal(code, v.code, `vector {v.label}`)
			t.equal(ok, v.code == "Ok", `vector {v.label} verdict`)
			if v.code == "Ok" then
				accepted += 1
				t.equal(#h.dispatched, 1, `vector {v.label} dispatch`)
			else
				t.equal(#h.dispatched, 0, `vector {v.label} must not dispatch`)
				t.equal(#h.rejections, 1, `vector {v.label} onReject once`)
			end
			totalDispatched += #h.dispatched
		end
		t.equal(accepted, 3)
		t.equal(totalDispatched, accepted)
	end)

	t.test(
		"a throwing handler is contained: HandlerError, onError called, next valid message still accepted",
		function()
			local h = harness()
			h.throwOnDispatch = true
			local ok, code = h.gateway:handle(1, "Echo", { value = 1 })
			t.equal(ok, false)
			t.equal(code, "HandlerError")
			t.equal(#h.errors, 1)
			t.contains(tostring(h.errors[1]), "handler exploded")
			t.equal(#h.dispatched, 0)
			h.throwOnDispatch = false
			local ok2, code2 = h.gateway:handle(1, "Echo", { value = 2 })
			t.equal(ok2, true)
			t.equal(code2, "Ok")
			t.equal(#h.dispatched, 1)
		end
	)

	t.test("a hostile payload (metatable that raises) is rejected without throwing out of handle", function()
		local h = harness()
		local hostile = setmetatable({}, {
			__index = function()
				error("boom")
			end,
			__len = function()
				error("boom")
			end,
		})
		local ok, code = h.gateway:handle(1, "Echo", hostile)
		t.equal(ok, false)
		t.equal(code, "MissingKey")
		t.equal(#h.dispatched, 0)
	end)

	t.test("a bad clock reading drops as RateLimited and never dispatches", function()
		local h = harness()
		h.clock.advance(-1)
		expectRejected(h, 1, "Echo", { value = 1 }, "RateLimited")
	end)

	t.test("the real Manifest: Ping accepted with a nonce, NaN nonce is NotFinite, bare Ping is MissingKey", function()
		local clock = FakeClock.new()
		local dispatched = 0
		local gw = Gateway.new({
			manifest = Manifest :: any,
			bucket = Bucket.new({ clock = clock }),
			rateFor = RateLimits.forIntent,
			getPhase = function(): Gateway.RoundPhase
				return "Lobby"
			end,
			dispatch = function()
				dispatched += 1
			end,
			onReject = function() end,
			onError = function() end,
		})
		local ok = gw:handle(1, "Ping", { nonce = 1 })
		t.equal(ok, true)
		local ok2, c2 = gw:handle(1, "Ping", { nonce = NAN })
		t.equal(ok2, false)
		t.equal(c2, "NotFinite")
		clock.advance(10)
		local ok3, c3 = gw:handle(1, "Ping", {})
		t.equal(ok3, false)
		t.equal(c3, "MissingKey")
		t.equal(dispatched, 1)
	end)
end
