--!strict
-- The anti-livelock safety valve (02-CONTEXT.md amendment A7 and its correction). It notices that
-- the whole table has returned to a state it has already been in, with no completion and no removal
-- since, and forces ONE uniformly random pass from the seat that just drew.
--
-- WHY THIS LIVES IN THE PURE ZONE, WHICH LOOKS WRONG AT FIRST. Research section 15 forbids the
-- reaction-time model and the greedy policy from `src/server/engine/`, because both are unvalidated
-- models of a human. This module is the opposite of a bot policy: it consults no policy, assumes
-- nothing about how anybody plays, and chooses uniformly at random. It is a liveness mechanism of
-- the same kind as the hand-size rule, and it belongs here because the engine is the only place
-- that can promise it runs at all. An executor who read section 15 alone would move this file.
--
-- WHAT IS AND IS NOT CLAIMED, measured at N=10 over 4,000 rounds per cell. At k=1,j=1 and k=2,j=1
-- the valve took the stall rate from 0.275% and 0.250% to zero observed stalls, while firing in
-- only about 0.25% of rounds, so it is invisible in healthy play. At k=2,j=2 it took 21.600% down
-- to 0.025% -- a residual, not zero -- while firing in 21.6% of rounds. So the honest claim is:
-- observed stalls were eliminated FOR A GOOD POOL, demonstrated rather than assumed, and the
-- firing rate is a better pool discriminator than the stall rate, because a configuration rescued
-- in one round in five is a bad configuration even when its stall rate looks fine. Do not restate
-- this as an unconditional property of the engine; the k=2,j=2 residual above falsifies that.
--
-- LOAD-BEARING PRECONDITION. `Invariants.hash` excludes `counters`, `valve` and `rankOf`. One
-- monotonically increasing field inside the hash would make every state unique, no state could
-- ever repeat, and this whole mechanism would be silently vacuous. Plan 02-01 case 13 asserts the
-- exclusion; this module depends on it and does not re-assert it.
--
-- NO YIELDS AND NO MUTATION OF CARD CONTAINERS (CLAUDE.md rules 6 and 7). Every function here is
-- synchronous and reports by returning. The valve does NOT perform the pass: it returns a card id
-- and `Engine.apply` executes the pass through the one container mutator, inside the same
-- synchronous apply. It names a card id and never a target seat or a hand index -- the successor is
-- resolved at execution time, exactly as for a player's pass.
local Invariants = require("./Invariants")
local Rng = require("./Rng")
local Types = require("./Types")

local JOKER_RANK = Types.JOKER_RANK
local MAX_HAND = Types.MAX_HAND

-- A fresh valve state. `seed` comes from `Engine.newRound` as a draw off the round's own generator,
-- so valve draws never perturb the deal and the deal never perturbs the valve, while both stay
-- functions of one seed.
local function new(seed: number): Types.ValveState
	return {
		rng = Rng.new(seed),
		actionsSinceProgress = 0,
		armed = false,
		seen = {},
		seenCount = 0,
		firings = 0,
		seenResets = 0,
		observations = 0,
	}
end

-- THE LOCKED CHOICE RULE. The drawing seat's card ids whose rank is not a joker, sorted ascending,
-- index `nextInt(1, #naturals)`. Sorted so the choice depends on the hand's CONTENTS and not on the
-- order the cards happen to sit in. If the hand holds no natural -- unreachable at j <= 2, where a
-- five-card hand holds at least three naturals -- fall back to the lowest card id in the hand.
--
-- WHY UNIFORMLY RANDOM, AND WHY NATURALS ONLY. The deviation IS the mechanism. Research 3.6
-- measured that the stall rate collapses as soon as a trace of passes are cards a greedy player
-- would not have chosen, and that randomising the greedy TIE-BREAK is not enough (44.7% to 26.3%),
-- because the cycle is created by "never pass from your largest group". A valve that passed the
-- "best" card to pass would be re-deriving the player's own greedy choice and the deviation would
-- be exactly zero. Naturals only, because in Wild mode a joker is the most valuable card in the
-- hand and dumping it is a bigger disturbance than the mechanism needs.
--
-- Both this rule and the firing point below are THIS PLAN'S CHOICES, held constant so the measured
-- numbers above stay comparable with the reference prototype that produced them. Neither amendment
-- A7 nor its correction states them. Plan 02-14 depends on that distinction: if its measured firing
-- rate diverges from the reference, the arm gate is only one of three candidate causes, the others
-- being this choice rule and the firing point.
local function chooseForcedCard(state: Types.State, seatId: Types.SeatId): Types.CardId
	local hand = state.seats[seatId].hand
	local naturals: { Types.CardId } = {}
	local lowest = hand[1]
	for _, id in hand do
		if state.rankOf[id] ~= JOKER_RANK then
			table.insert(naturals, id)
		end
		if id < lowest then
			lowest = id
		end
	end
	if #naturals == 0 then
		return lowest
	end
	table.sort(naturals)
	return naturals[state.valve.rng:nextInt(1, #naturals)]
end

-- Called by `Engine.apply` at the end of a successful apply that produced a Completed or a
-- SeatRemoved event. The state space changed, so the SEEN WINDOW restarts -- and `armed` is
-- deliberately left alone. The two halves are not the same kind of reason:
--
-- Clearing `seen` is SOUNDNESS. A completion or a removal changes the state space, so a hash
-- recorded before it can never legitimately recur afterwards; keeping it would make the valve fire
-- on a state that is not a cycle at all. Research 11.4 requires exactly this reset.
--
-- Un-arming would only be a COST choice, and here it is the wrong one. Arming already costs 48
-- actions per live seat with NO progress at all; a round that has paid that once has demonstrated
-- it needs watching, and re-arming from scratch after every completion would let the same cycle run
-- another full arm period. That is the identical argument `afterAction` makes for leaving `armed`
-- true after a FIRING -- the two sites must agree or this module contradicts itself. There is no
-- downside for healthy play, because a healthy round never arms in the first place (a 9-seat round
-- is about 250 actions against a 432-action threshold), so only a round that has already proven
-- pathological keeps hashing. It also makes plan 02-09's `valveArmed` metric mean "this round ever
-- armed" rather than "the valve happened to be armed when the last action landed".
local function afterProgress(state: Types.State)
	local valve = state.valve
	valve.observations += 1
	valve.actionsSinceProgress = 0
	valve.seen = {}
	valve.seenCount = 0
end

-- Called by `Engine.apply` at the end of every OTHER successful apply. `drewAtSeat` is the seat
-- that just drew -- so it now holds MAX_HAND cards and must pass next -- or nil when the action was
-- a pass. Returns the card id the engine must force that seat to pass, or nil for "do nothing".
--
-- Exactly one of `afterProgress` and `afterAction` is called per successful apply, and neither is
-- called on a rejection. Both bump `observations`, so plan 02-08's fuzz suite can assert
-- `observations == acceptedActions` -- the only way to catch the valve being accidentally skipped
-- inside a conditional and read green.
--
-- THE LOCKED FIRING RULE. It fires when all four hold: the configuration enables it;
-- `drewAtSeat ~= nil`, because immediately after a non-completing draw is the only instant at which
-- a known seat holds MAX_HAND and therefore provably has a legal pass, and it is about to pass
-- anyway, so the valve changes WHICH card leaves and not whether a pass happens; it is armed; and
-- the hash is already in the window.
local function afterAction(state: Types.State, drewAtSeat: Types.SeatId?): Types.CardId?
	local valve = state.valve

	-- A malformed call is a caller bug in `Engine.apply` and must be LOUD. Silently returning nil
	-- would make a wiring bug look like a mechanism that simply never fires, which is the failure
	-- mode this module exists to prevent.
	if drewAtSeat ~= nil then
		local drawer = state.seats[drewAtSeat]
		if drawer == nil or not drawer.live then
			error(`Valve.afterAction: seat {drewAtSeat} is not live`, 0)
		end
		if #drawer.hand ~= MAX_HAND then
			error(`Valve.afterAction: seat {drewAtSeat} holds {#drawer.hand} cards, not {MAX_HAND}`, 0)
		end
	end

	valve.observations += 1
	valve.actionsSinceProgress += 1
	-- THE ARM GATE IS A COST GATE AND NOTHING ELSE. Hashing on every draw costs roughly two
	-- microseconds per action: fine for a sweep, but it would blow the CI subset's wall-time budget
	-- (plan 02-09 derives that budget from measured throughput -- deliberately not quoted here,
	-- because a stale budget baked into a shipped comment is how a correct comment becomes a wrong
	-- one). A healthy 9-seat round is about 250 actions against 48 x 9 = 432, so it never arms. The
	-- only behavioural effect is that a cycle is detected at most one lap later than it could have
	-- been, because a cycle repeats forever until something breaks it.
	valve.armed = valve.armed or valve.actionsSinceProgress >= Types.VALVE_ARM_ACTIONS_PER_SEAT * state.liveCount

	-- Three cheap exits, and NO hashing in any of them -- that is the whole point of the arm gate.
	if not state.config.antiLivelockValve then
		return nil
	end
	if drewAtSeat == nil then
		return nil
	end
	if not valve.armed then
		return nil
	end

	local h = Invariants.hash(state)
	if valve.seen[h] == nil then
		valve.seen[h] = true
		valve.seenCount += 1
		if valve.seenCount > Types.VALVE_SEEN_CAP then
			-- Bound the window so a pathological round cannot grow memory without limit. A cycle
			-- shorter than the cap is still caught; passing it restarts the window and is counted.
			valve.seen = {}
			valve.seenCount = 0
			valve.seenResets += 1
		end
		return nil
	end

	-- The whole table has returned to a state it has already been in, with no completion and no
	-- removal in between, because `afterProgress` empties the window. Fire.
	valve.firings += 1
	-- The forced pass changes the trajectory, so the window restarts. `armed` stays true: this
	-- round has already shown it needs watching, and re-arming from scratch would let the same
	-- cycle run another full arm period.
	valve.seen = {}
	valve.seenCount = 0
	return chooseForcedCard(state, drewAtSeat)
end

return {
	new = new,
	afterProgress = afterProgress,
	afterAction = afterAction,
}
