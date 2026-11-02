--!strict
-- Spec lock for the card-engine decisions resolved in ROADMAP.md Phase 1. CARD-09 and CARD-10 are the two
-- BLOCKING ones; CARD-12 is the fallback if Gate G1 fails.
--
-- These are todos rather than assertions, on purpose: no engine exists until Phase 2, so there is nothing to assert
-- against, and a fake passing test would be worse than a visible todo. The harness counts them separately,
-- prints them on every run and never fails on them. Phase 2 converts each into a real test, and the todo
-- count in the runner summary must reach 0 before Phase 2 closes.
--
-- Exactly three, no padding. Defaults that are already covered by an executing test elsewhere are NOT
-- restated here (a todo restating a passing check would inflate the open-question count). The
-- deadline exclusive tie rule is covered in tests/core/round.spec.luau, and the player cap in
-- tests/core/admission.spec.luau.
local Test = require("../harness/Test")

return function(t: Test.Runner)
	t.todo(
		"CARD-09 deal-time four of a kind: re-shuffle so no seat starts complete, including hands completable by a wild"
	)
	t.todo(
		"CARD-10 joker completion: spend naturals first, so the four cards that leave are the natural ranks before any wild"
	)
	t.todo(
		"CARD-12 fallback: if Gate G1 fails, jokers ship as blockers instead of wilds, both variants behind a flag from the start"
	)
end
