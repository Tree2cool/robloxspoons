# Deferred items — Phase 2

Out-of-scope discoveries logged rather than fixed. Each one was found while executing a plan in this
phase and is NOT caused by that plan's changes.

## From plan 02-09 (the bot simulator and its CI subset), 2026-11-03

### D-02-09-1 — `grep -rq 'DestroyRemovedCards\|destroy' src/` can never fail

Plan 02-09's task-2 acceptance criteria require that grep to exit 1. It exits 0 against
**pre-existing** code and always would have:

- `src/server/services/PlayerGate.luau:22,64` and `src/server/services/NetServer.luau:31,75` declare
  lifecycle `destroy` methods — correct, unrelated to cards.
- `src/server/engine/Types.luau:86`, `src/server/engine/Invariants.luau:133` and
  `src/server/engine/Ring.luau:27,28,29,183` carry the prose "never destroyed" / "destroying the
  cards would break Rule 8", which is the *statement* of Rule 8.

NOT fixed: nothing here is a defect, and renaming shipped lifecycle methods or deleting the prose
that records Rule 8 to satisfy a grep would be strictly worse. The criterion's intent is asserted the
meaningful way instead — `grep -rq 'DestroyRemovedCards' src/` **fails** — and the sabotage path
exists only in `scripts/sim/Simulator.luau`.

**Action for whoever owns VALIDATION.md / the plan set:** reword the criterion to name the sabotage
symbol rather than the English word.

### D-02-09-2 — `--filter engine` now picks up one non-engine case by label

`tests/run.luau` matches the filter against the whole label (`path::case name`), and
`tests/sim/subset.spec.luau` has a case called "MUTATION: a deliberately broken **engine** is
reported as a FAILURE". So `--filter engine` reports `140 passed ... 3.06s` where 02-08 recorded
`139 ... 2.32s`. The extra case and ~0.7s are that collision, not an engine regression.

NOT fixed: renaming the case would make its name worse, and narrowing the filter semantics is a
change to the shared runner that no plan in this phase owns. Anyone comparing `--filter engine`
numbers across plans should use `--filter tests/engine/` instead.

### D-02-09-3 — the suite is at 23.4-24.5s against CONTEXT's locked "~20s"

Recorded in 02-08-SUMMARY as already unreachable at 17.9s, and now measured at
`493 passed, 0 failed, 3 todo in 23.41-24.45s` with `scripts/verify.luau` at 26.1s. Nothing was
trimmed to fit a wall clock. NOT fixed here: it is an owner decision at plan 02-12's checkpoint.

### D-02-09-4 — Gate G1's zero-stall bar and the ~1% valve firing-rate bar are both unmet at every pool measured

The full measurement, its cause (amendment A3's completion target, i.e. research OQ-B's off-by-one)
and the k-sweep that rules out a pool change are in `02-09-SUMMARY.md` under "THE FINDING" and in the
header of `tests/sim/subset.spec.luau`. NOT fixed here: `evaluateBars` is untouched, neither bar was
relaxed, `Types.VALVE_ARM_ACTIONS_PER_SEAT` was not changed, and the pool was not moved to make the
gate green. It is an owner decision at plan 02-12's checkpoint, informed by plan 02-10's sweep.
