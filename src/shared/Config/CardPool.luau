--!strict
-- The shipped card pool, decided by Gate G1 in Phase 2 and evidenced by
-- .planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md (section 1, the Verdict) and
-- its data artefact 02-sweep-data.json (`selection`). 320,000 gated rounds at 10,000 per cell.
--
-- ranks = seatCount + EXTRA_RANKS, four cards per rank, where seatCount is SEATED SEEKERS =
-- (players in the round) - 1. The hider does not play cards (amendment A3). `Pool.poolConfig` is the
-- only place that subtraction is written; nothing else may compute `n - 1` inline.
-- circulation = 4 * EXTRA_RANKS + JOKERS, and it is invariant under draw, pass and completion, so
-- "the deck never runs dry" (CARD-04) is just circulation >= 1.
--
-- These are inputs to an EngineConfig VALUE. The engine never requires this module: src/server ->
-- src/shared is a cross-mount require that resolves on disk and fails in the DataModel, and guard
-- rule R6 forbids it (the same constraint src/server/core/Admission.luau documents). The Phase 4
-- adapter and the simulator read from here and pass the values in.
--
-- WHY k = 3 AND NOT THE k = 6 THE BAR SELECTED. The number alone is not the decision. Every
-- candidate from k=2 to k=6 clears all five bars, and the firing-rate curve is smooth and monotone
-- with no elbow (02-G1-REPORT.md section 4b, the bar-sensitivity ladder), so the bar CHOOSES rather
-- than discovers: a 7% bar selects k=6, a 20% bar selects k=3, a 40% bar selects k=2. The owner set
-- the bar at the k=3 operating point and the sweep was then re-run at it, so the shipped pool is
-- also the CONFIRMED one. k=3 is the tightest pool whose search-grid cells show no stall at all; it
-- gives up ~2s of starting-gun speed against k=2 while cutting forced passes by about a third, and
-- avoids k=6's ~45% slower start (median first completion 20.9s against 16.2s). A valve firing is
-- NOT invisible -- a card leaves a hand the player did not choose -- so the firing rate is a FEEL
-- cost and not only a safety statistic, which is why it is traded against pacing rather than
-- minimised.
--
-- ANTI_LIVELOCK_VALVE must stay true in the shipped game. G1's stall result is a measured property
-- of this pool WITH the engine's valve enabled (02-CONTEXT.md amendment A7): at this very pool and
-- round count the valve-DISABLED twin cells stall at 3.58% to 8.31% (report section 4), which is the
-- evidence the valve is load-bearing, roughly 500x the valve-on residual.
-- The honest claim is a RESIDUAL, not a zero and never a theorem: with the valve on the confirm
-- stage observed 37 stalled rounds in 320,000 -- 0.012% aggregate, 0.070% in the worst cell --
-- against the 0.500% ceiling amendment A8 set. The locked bar was zero; no pool this engine has
-- reaches it. See 02-G1-REPORT.md sections "The valve" and the section 1 residual line.
--
-- AUTO_PASS_MAX_SECONDS and AUTO_PASS_SELECTION are CONSTRAINTS ON PHASE 4, not tuning knobs.
-- The deadline is a product value now that the valve carries the stall job (A7 demoted the auto-pass
-- to a secondary mitigation), and CARD-16 benches a player after repeated strikes, so a short
-- deadline would strike ordinary players several times a round. At 8.0s the auto-pass fires
-- essentially never and that is correct: the sweep recorded 0 auto-passes across its 8.0s cells,
-- 2 at 5.0s, 58 at 3.0s and 38,516 at 1.5s (report section 5), and the mechanism is kept falsifiable
-- by a dedicated 1.0s probe cell measuring 1.38% of actions rather than by a bar on shipped cells.
--
-- The SELECTION RULE is the load-bearing half: deviation comes from the auto-pass choosing a card
-- the player would NOT have chosen. If Phase 4 ships the helpful-looking "auto-pass your worst
-- card", that IS the player's own greedy choice, the deviation is exactly zero, and the simulator's
-- auto-pass numbers transfer nothing to the shipped game (A7-CORRECTION). The rule modelled
-- throughout the sweep is `Bots.randomPass`: a card drawn uniformly at random from the hand.
return {
	EXTRA_RANKS = 3,
	JOKERS = 1,
	JOKER_MODE = "Wild",
	ANTI_LIVELOCK_VALVE = true,
	AUTO_PASS_MAX_SECONDS = 8.0,
	AUTO_PASS_SELECTION = "uniform-random-from-hand",
}
