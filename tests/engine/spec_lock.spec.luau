--!strict
-- Spec lock for the card-engine decisions resolved in ROADMAP.md Phase 1. CARD-09 and CARD-10 are the two
-- BLOCKING ones; CARD-12 is the fallback if Gate G1 fails.
--
-- THE ENGINE NOW EXISTS, so these are real assertions. Plan 02-11 converted the three todo placeholders
-- into the three cases below, each asserting the DECISION as its todo worded it rather than merely that
-- some nearby code works. **This file must register zero todos** -- and the literal string the harness
-- registers them with must not appear even in a comment, because a `grep -rn` over `tests/` is the
-- automated guard that the count stays at zero. `02-VALIDATION.md` makes the runner's todo count reaching 0
-- the phase exit condition, and says plainly that a green run with todos remaining is not a finished phase
-- and that the pass count alone will not reveal it.
--
-- Exactly three, no padding, and each is deliberately narrow. The primitives already have their own files --
-- `pool.spec.luau` fuzzes the deal, `hand.spec.luau` covers completion detection, `apply.spec.luau` drives
-- the assembled engine -- so these cases assert the LOCKED DECISIONS and their preconditions, which is a
-- different job from testing the modules. Where a case needs the shipped configuration it reads
-- `src/shared/Config/CardPool.luau`, the module that records Gate G1's verdict, and CARD-12 reads the
-- committed report itself so the config and its evidence cannot drift apart.
local fs = require("@lune/fs")

local CardPool = require("../../src/shared/Config/CardPool")
local Engine = require("../../src/server/engine/Engine")
local Hand = require("../../src/server/engine/Hand")
local Pool = require("../../src/server/engine/Pool")
local Rng = require("../../src/server/engine/Rng")
local Test = require("../harness/Test")
local Types = require("../../src/server/engine/Types")

local JOKER_RANK = Types.JOKER_RANK
local HAND_SIZE = Types.HAND_SIZE

local REPORT_PATH = ".planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md"

-- `CardPool.JOKER_MODE` is a `string` to the type checker, so it is narrowed ONCE here. The narrowing cannot
-- hide a bad value: CARD-12 case (a) asserts the module's own field is one of exactly two literals, so a
-- third value fails loudly there instead of being silently played as Wild.
local SHIPPED_MODE: Types.JokerMode = if CardPool.JOKER_MODE == "Blocker" then "Blocker" else "Wild"

local function shippedConfig(seatCount: number): Types.EngineConfig
	return {
		ranks = seatCount + CardPool.EXTRA_RANKS,
		jokers = CardPool.JOKERS,
		jokerMode = SHIPPED_MODE,
		antiLivelockValve = CardPool.ANTI_LIVELOCK_VALVE,
	}
end

-- The LOCKED deal layout: seat `s` holds ids `(s-1)*4+1 .. s*4` (02-04-SUMMARY.md).
local function handIdsFor(seat: number): { Types.CardId }
	local ids: { Types.CardId } = {}
	for slot = 1, HAND_SIZE do
		table.insert(ids, (seat - 1) * HAND_SIZE + slot)
	end
	return ids
end

local function playerIdsFor(seatCount: number): { Types.PlayerId }
	local ids: { Types.PlayerId } = {}
	for s = 1, seatCount do
		ids[s] = 100 + s
	end
	return ids
end

-- A GREEDY HOARDER, deterministic: keep the largest rank group, pass from the smallest, lowest card id as
-- the tiebreak. Copied in spirit from apply.spec.luau and for the same reason -- a completion has to be
-- reached by SOME reproducible sequence of legal intents, and this is the shortest one. It is not a model of
-- a player; plan 02-09's `Bots` owns that.
local function greedyCard(state: Types.State, seatId: Types.SeatId): Types.CardId
	local hand = state.seats[seatId].hand
	local counts: { [Types.Rank]: number } = {}
	for _, id in hand do
		local rank = state.rankOf[id]
		counts[rank] = (counts[rank] or 0) + 1
	end
	local best = hand[1]
	local bestKey = counts[state.rankOf[best]] * 1000 + best
	for _, id in hand do
		local key = counts[state.rankOf[id]] * 1000 + id
		if key < bestKey then
			best, bestKey = id, key
		end
	end
	return best
end

return function(t: Test.Runner)
	-- 1 ------------------------------------------------------------------------------------------
	t.test(
		"CARD-09 deal-time four of a kind: re-shuffle so no seat starts complete, including hands completable by a wild",
		function()
			-- BOTH HALVES IN ONE CASE, because either alone is satisfied by a vacuous predicate. A deal
			-- predicate that always returns false passes the "no seat starts complete" half for every seed
			-- it is ever shown (research section 10: "a predicate that never fires is indistinguishable
			-- from a correct one"), and a counter that is merely greater than zero says nothing about
			-- whether the accepted deals are legal.
			--
			-- At the SHIPPED pool, not at a tight one. That matters for the sizing: the rejection rate here
			-- is about 0.7% of deals (28 rejections in the 4,000 below), against the ~10% that
			-- `pool.spec.luau`'s k=1, j=2 corpus sees, because a wider pool rarely deals anyone four of a
			-- kind. 500 seeds per seat count is what makes the counter non-vacuous at EVERY seat count
			-- rather than only in aggregate -- the thinnest, seatCount = 8, rejects exactly once.
			local CORPUS_SEEDS = 500
			local totalAttempts, totalDeals, worstAttempts = 0, 0, 0
			local rejectingSeatCounts = 0

			for seatCount = 2, 9 do
				local config = shippedConfig(seatCount)
				local attempts, rejections = 0, 0
				for seed = 1, CORPUS_SEEDS do
					local rankOf, used = Pool.deal(config, seatCount, Rng.new(seed))
					attempts += used
					worstAttempts = math.max(worstAttempts, used)
					if used > 1 then
						rejections += 1
					end
					-- The ACCEPTED deal must be legal for every seat. `openingHandIsBad` is the engine's own
					-- predicate, so this asserts the deal loop honoured it rather than re-deriving it: in
					-- Wild it covers 4 naturals, 3+1 and 2+2, which research 3.3 proves are the only
					-- reachable wild completions at `j <= 2`.
					for s = 1, seatCount do
						t.equal(
							Pool.openingHandIsBad(rankOf, handIdsFor(s), config.jokerMode),
							false,
							`seats={seatCount} seed={seed}: seat {s} started on a complete or wild-completable hand`
						)
					end
				end
				if rejections > 0 then
					rejectingSeatCounts += 1
				end
				totalAttempts += attempts
				totalDeals += CORPUS_SEEDS
			end

			-- THE REJECTION COUNTER, the half that makes the predicate falsifiable. `attempts > deals` can
			-- only happen when `openingHandIsBad` returned true at least once.
			t.truthy(
				totalAttempts > totalDeals,
				`{totalDeals} deals took {totalAttempts} attempts: not one rejection fired, so the CARD-09 `
					.. `predicate is vacuous and a seat could start complete without this case noticing`
			)
			-- Bounded on the OTHER side too: a predicate that rejects nearly everything is just as broken,
			-- and at the shipped pool the true surplus is ~0.7% rather than the 10% a tight pool shows.
			t.truthy(
				totalAttempts < totalDeals * 2,
				`{totalDeals} deals took {totalAttempts} attempts: the predicate rejects most deals, which is `
					.. `as broken as never rejecting`
			)
			t.truthy(worstAttempts >= 2, "no deal in the corpus needed a re-shuffle")
			t.truthy(
				worstAttempts <= Types.MAX_DEAL_ATTEMPTS,
				`worst case {worstAttempts} attempts exceeded the ceiling`
			)
			t.equal(
				rejectingSeatCounts,
				8,
				"every seat count from 2 to 9 must see at least one rejection in the corpus"
			)
			print(
				`    CARD-09: {totalDeals} deals at the shipped pool took {totalAttempts} attempts `
					.. `(surplus {totalAttempts - totalDeals}, worst {worstAttempts}), no seat ever started complete`
			)
		end
	)

	-- 2 ------------------------------------------------------------------------------------------
	t.test(
		"CARD-10 joker completion: spend naturals first, so the four cards that leave are the natural ranks before any wild",
		function()
			-- The hands are CRAFTED and the card ids are INTERLEAVED with the jokers on purpose: ids 1 and 3
			-- are jokers and 2, 4, 5 are the naturals, so "naturals first, then jokers, each group
			-- ascending" is a different list from "the hand in its own order". An implementation that
			-- retired the first four cards it saw would pass a non-interleaved fixture and fail this one.
			local threeNaturals: { Types.Rank } = { JOKER_RANK, 5, JOKER_RANK, 5, 5 }
			local hand: { Types.CardId } = { 1, 2, 3, 4, 5 }

			local wild = Hand.detectCompletion(threeNaturals, hand, "Wild")
			t.truthy(wild ~= nil, "3 naturals + 2 jokers must complete in Wild")
			assert(wild ~= nil, "narrowing")
			t.equal(wild.rank, 5, "the completing rank is the NATURAL rank, never the joker rank")
			-- The EXACT list, not the counts: the counts alone are satisfied by spending a joker in place
			-- of a natural, which is the choice CARD-10 exists to forbid.
			t.deepEqual(wild.retired, { 2, 4, 5, 1 }, "the three naturals ascending, THEN the lowest joker")
			t.equal(wild.naturalsUsed, 3, "all three naturals are spent")
			t.equal(wild.jokersUsed, 1, "exactly ONE joker is spent, not two")
			t.equal(wild.fifth, 3, "the fifth card is the joker that was NOT spent")
			t.equal(threeNaturals[wild.fifth], JOKER_RANK, "and it is a joker: the hand keeps a wild, not a natural")

			-- Four naturals + one joker: the joker is not touched at all. This is the half that proves
			-- "naturals FIRST" rather than merely "naturals are involved".
			local fourNaturals: { Types.Rank } = { 5, JOKER_RANK, 5, 5, 5 }
			local full = Hand.detectCompletion(fourNaturals, hand, "Wild")
			t.truthy(full ~= nil, "4 naturals + 1 joker must complete in Wild")
			assert(full ~= nil, "narrowing")
			t.deepEqual(full.retired, { 1, 3, 4, 5 }, "the four naturals leave and the joker stays")
			t.equal(full.naturalsUsed, 4, "four naturals are available, so four are spent")
			t.equal(full.jokersUsed, 0, "and NO joker is spent")
			t.equal(full.fifth, 2, "the joker is the fifth card")

			-- Research 3.3's choice table, asserted as the reason rather than quoted: of the completing
			-- shapes, 4 naturals strands 0 cards of the rank and spends 0 jokers, 3+1j strands 1 and spends
			-- 1, 2+2j strands 2 and spends 2. Taking the most naturals available is best on BOTH axes, so
			-- the rule is solvability-optimal and not merely spec-locked.
			t.truthy(
				full.jokersUsed < wild.jokersUsed,
				"the hand with more naturals must strand fewer jokers, or 'naturals first' is not what ran"
			)

			-- And the same five cards complete NOTHING in Blocker, which is where CARD-10 and CARD-12 meet:
			-- the rule only has content because a joker can stand in at all.
			t.equal(
				Hand.detectCompletion(threeNaturals, hand, "Blocker"),
				nil,
				"in Blocker a joker completes nothing, so 3 naturals + 2 jokers is just a 5-card hand"
			)
			print(
				`    CARD-10: retired {table.concat(wild.retired, ",")} keeping joker {wild.fifth} at 3+2j; `
					.. `retired {table.concat(full.retired, ",")} spending no joker at 4+1j`
			)
		end
	)

	-- 3 ------------------------------------------------------------------------------------------
	t.test(
		"CARD-12 fallback: if Gate G1 fails, jokers ship as blockers instead of wilds, both variants behind a flag from the start",
		function()
			-- (a) THE FLAG IS A FLAG. One of exactly two literals, asserted against the module that records
			-- the decision, so a typo or a third mode is a failure here rather than a `BadConfig` error
			-- somewhere in Phase 4.
			t.truthy(
				CardPool.JOKER_MODE == "Wild" or CardPool.JOKER_MODE == "Blocker",
				`CardPool.JOKER_MODE is "{CardPool.JOKER_MODE}", which is neither variant the engine implements`
			)

			-- (b) BOTH VARIANTS RUN IN THE SAME PROCESS, and the SHIPPED pool is where they are compared.
			-- Two rounds differing ONLY in `jokerMode`, the identical scripted sequence driven through
			-- each, and the event lists must differ -- which is what makes the unshipped variant live code
			-- rather than a branch nobody has ever executed (research 3.5: a flag exercised in one position
			-- only is an untested rewrite, not a fallback).
			--
			-- The seed is pinned because the two modes must DEAL IDENTICALLY for the comparison to be about
			-- the mode: `Pool.openingHandIsBad` is itself mode-dependent, so a seed whose Wild deal needs a
			-- re-shuffle and whose Blocker deal does not would compare two different tables. `rankOf` is
			-- asserted equal rather than assumed, so a change to Rng's stream reports THAT instead of
			-- silently comparing two different rounds.
			local SEED = 3
			local SEATS = 3
			local wildConfig = shippedConfig(SEATS)
			wildConfig.jokerMode = "Wild"
			local blockerConfig = shippedConfig(SEATS)
			blockerConfig.jokerMode = "Blocker"

			local wild = Engine.newRound(wildConfig, playerIdsFor(SEATS), Rng.new(SEED))
			local blocker = Engine.newRound(blockerConfig, playerIdsFor(SEATS), Rng.new(SEED))
			t.deepEqual(
				blocker.rankOf,
				wild.rankOf,
				`seed {SEED} no longer deals both modes identically, so this case would compare two different tables`
			)

			local trace: { Types.Intent } = {}
			local wildKinds: { string } = {}
			local jokersRetired = 0
			local cursor = wild.head
			local completedAt: number? = nil
			for action = 1, 200 do
				local seat = wild.seats[cursor]
				local intent: Types.Intent
				if #seat.hand == HAND_SIZE then
					if #seat.inbox == 0 then
						cursor = seat.next
						continue
					end
					intent = { kind = "Draw", seat = cursor }
				else
					intent = { kind = "Pass", seat = cursor, cardId = greedyCard(wild, cursor) }
				end
				local result = Engine.apply(wild, intent)
				t.truthy(result.ok, `Wild rejected a {intent.kind} at action {action} ({tostring(result.reject)})`)
				table.insert(trace, intent)
				for _, event in result.events do
					table.insert(wildKinds, event.kind)
					if event.kind == "Completed" then
						completedAt = action
						for _, id in event.retired do
							if wild.rankOf[id] == JOKER_RANK then
								jokersRetired += 1
							end
						end
					end
				end
				local actor = wild.seats[cursor]
				if not actor.live then
					cursor = wild.head
				elseif #actor.hand == HAND_SIZE then
					cursor = actor.next
				end
				if completedAt ~= nil then
					break
				end
			end

			t.equal(completedAt, 3, `seed {SEED} no longer completes on action 3; re-pin the seed and the trace`)
			-- Without a joker in the retired set the two modes would agree and the case would prove nothing:
			-- it is the WILD STANDING IN for a fourth natural that Blocker refuses.
			t.truthy(jokersRetired >= 1, "the completing set must SPEND a joker, or Blocker would complete too")

			local blockerKinds: { string } = {}
			for index, intent in trace do
				local replay = Engine.apply(blocker, intent)
				t.truthy(replay.ok, `Blocker rejected intent {index} with {tostring(replay.reject)}`)
				for _, event in replay.events do
					table.insert(blockerKinds, event.kind)
				end
			end

			t.deepEqual(wildKinds, { "Drew", "Passed", "Drew", "Completed", "SeatRemoved" }, "the Wild event list")
			t.deepEqual(
				blockerKinds,
				{ "Drew", "Passed", "Drew" },
				"the Blocker event list: the same hand is just a draw"
			)
			t.truthy(
				#wildKinds ~= #blockerKinds,
				"the identical sequence produced identical events in both modes, so one variant is dead code"
			)
			t.equal(blocker.counters.completions, 0, "Blocker counted no completion")
			t.equal(blocker.liveCount, SEATS, "Blocker's ring is untouched")
			t.equal(wild.counters.completions, 1, "Wild counted exactly one")
			print(
				`    CARD-12: Wild {table.concat(wildKinds, ",")} | Blocker {table.concat(blockerKinds, ",")} `
					.. `over the same {#trace} intents at k={CardPool.EXTRA_RANKS}, j={CardPool.JOKERS}`
			)

			-- (c) THE VERDICT'S PRECONDITIONS. The zero-stall measurement was taken with the valve ON and
			-- the auto-pass numbers were taken with a uniform-random selection rule, so a config that ships
			-- either differently is a config the report says nothing about. Neither is asserted anywhere
			-- else in this file's reach, and `AUTO_PASS_SELECTION` in particular is the one Phase 4 is most
			-- likely to "improve": an auto-pass that passes the player's worst card is the player's own
			-- greedy choice, so the deviation is exactly zero and the simulator transfers nothing.
			t.equal(CardPool.ANTI_LIVELOCK_VALVE, true, "G1's stall result is a measurement taken with the valve ON")
			t.equal(
				CardPool.AUTO_PASS_SELECTION,
				"uniform-random-from-hand",
				"the auto-pass selection rule is a constraint on Phase 4, not a tuning knob"
			)

			-- (d) THE CONFIG MUST NOT DRIFT FROM ITS EVIDENCE. The same drift class `tests/ci/verify.spec.luau`
			-- guards for the CI `run:` strings: a number in a module and a number in a committed report that
			-- nobody compares. The Verdict section is sliced out rather than searching the whole file,
			-- because the report also tabulates every REJECTED candidate -- "k = 4" appears in it dozens of
			-- times -- so a whole-file search would pass for a pool the gate refused.
			local report = fs.readFile(REPORT_PATH)
			local verdictStart = string.find(report, "## 1. Verdict", 1, true)
			t.truthy(verdictStart ~= nil, `{REPORT_PATH} has no "## 1. Verdict" section`)
			assert(verdictStart ~= nil, "narrowing")
			local nextSection = string.find(report, "\n## ", verdictStart + 1, true)
			local verdict = string.sub(report, verdictStart, if nextSection ~= nil then nextSection else #report)

			-- The SELECTION LINE, not the section, for the three numbers: the section also carries the bar
			-- table and the residual paragraph, and asserting against one line keeps a failure readable
			-- instead of dumping thirty lines of markdown.
			local selectionLine = string.match(verdict, "%*%*Selected pool:[^\n]*")
			t.truthy(selectionLine ~= nil, `{REPORT_PATH}'s Verdict has no "**Selected pool:" line`)
			assert(selectionLine ~= nil, "narrowing")

			t.contains(
				selectionLine,
				`k = {CardPool.EXTRA_RANKS} extra ranks`,
				`the report's Verdict does not select CardPool.EXTRA_RANKS = {CardPool.EXTRA_RANKS}`
			)
			t.contains(
				selectionLine,
				`j = {CardPool.JOKERS} joker`,
				`the report's Verdict does not select CardPool.JOKERS = {CardPool.JOKERS}`
			)
			t.contains(
				selectionLine,
				string.format("deadline %.1fs", CardPool.AUTO_PASS_MAX_SECONDS),
				"the report's Verdict does not name CardPool.AUTO_PASS_MAX_SECONDS as the selected deadline"
			)
			-- The mode is asserted against the whole section, because the report records it as a FLAG in the
			-- prose beneath the selection line rather than as part of the selected pool. `string.find` with
			-- a message rather than `t.contains`, so a failure prints the sentence and not the section.
			-- NOT a drift check, and it must not be mistaken for one. The Verdict section says "Wild and
			-- Blocker both clear every bar", so it contains BOTH literals and this find succeeds for
			-- either value -- it only proves the report discusses the mode at all. Phase 2 verification
			-- found that flipping the shipped mode to Blocker was caught solely by CARD-09's rejection
			-- COUNT (Blocker yields fewer wild-completable hands), which is incidental: it would vanish
			-- the moment that corpus changed. The deliberate pin is the assertion below it.
			t.truthy(
				string.find(verdict, CardPool.JOKER_MODE, 1, true) ~= nil,
				`the report's Verdict never mentions the shipped joker mode {CardPool.JOKER_MODE}`
			)

			-- THE PIN. PROJECT.md's Key Decisions table records jokers-as-wilds as a design property and
			-- CLAUDE.md forbids re-opening that row; Gate G1 then cleared BOTH modes at every roster size,
			-- so Blocker survives as a live flag rather than a contingency. That is exactly why the mode
			-- needs an explicit assertion: when both variants pass every bar, no measurement can tell you
			-- which one is meant to ship. This is the one G1 value the data cannot defend, so the decision
			-- defends it. Changing the shipped mode means changing PROJECT.md first, then this line.
			t.equal(
				CardPool.JOKER_MODE,
				"Wild",
				"the shipped joker mode must be Wild: PROJECT.md's Key Decisions table records "
					.. "jokers-as-wilds, and G1 cleared both modes, so nothing in the measured data "
					.. "distinguishes them. Flip PROJECT.md first if this is deliberate."
			)
			-- `marginal` is in the Verdict for a reason: plan 02-11 was instructed to HALT rather than choose
			-- a value if the report flagged the selection marginal without a stated reason. Locking the flag
			-- here means a future re-run that comes back marginal fails this case instead of quietly
			-- inheriting the old decision.
			t.truthy(
				string.find(verdict, "Marginal: **false**", 1, true) ~= nil,
				"the shipped pool must be selected from a NON-marginal verdict"
			)
			print(`    CARD-12: {REPORT_PATH} agrees with CardPool on k, j, the deadline, the mode and marginal=false`)
		end
	)
end
