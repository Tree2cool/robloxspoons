---
phase: 01-foundations-contracts-and-spec-lock
plan: 06
subsystem: round-lifecycle
tags: [luau, fsm, round-id-token, deterministic-time, tdd, spec-lock]

requires:
  - phase: 01-01
    provides: pinned toolchain, .luaurc, Rojo project, selene.pure.toml
  - phase: 01-02
    provides: Lune test runner, FakeScheduler (cancelIsNoop), t.todo counting
provides:
  - "RoundLifecycle: pure round FSM with round-ID tokens, absolute integer-decisecond exclusive deadline, idempotent endRound"
  - "RoundDriver: thin Roblox adapter binding os.clock and task.delay/task.cancel; publishes deadline via GetServerTimeNow only"
  - "Config.Round: ROUND_CAP_SECONDS 300, HIDE_CAP_SECONDS 90, DECISECONDS_PER_SECOND 10"
  - "Three visible spec-lock todos: CARD-09, CARD-10, CARD-12"
affects: [phase-02, phase-04, phase-05, 01-10, 01-11]

tech-stack:
  added: []
  patterns:
    - "Handlers ask isOpen(roundId) first; isOpen turns an expired round into one Timeout end"
    - "Backstop closures capture the round id; staleness is decided by id comparison, never by trusting cancel"
    - "Instrumented scheduler wrapper records which backstops actually ran, so 'inert' is distinguishable from 'never fired'"

key-files:
  created:
    - src/server/core/RoundLifecycle.luau
    - src/server/services/RoundDriver.luau
    - src/shared/Config/Round.luau
    - tests/core/round.spec.luau
    - tests/engine/spec_lock.spec.luau
  modified: []

key-decisions:
  - "Deadline is exclusive: nowDeci() >= endsAtDeci closes the round; a claim on the deadline decisecond is rejected"
  - "begin() while the previous round has not ended is an error, not a silent overwrite or an implicit Aborted"
  - "endRound is the idempotent primitive and does NOT check the deadline; the deadline check lives in isOpen, which every handler must call first"
  - "Spec-lock items use t.todo, deliberately (see Deviations)"

requirements-completed: []
requirements-contributed: [SCORE-06]

duration: ~1 session
completed: 2026-11-02
---

# Phase 1 Plan 06: RoundLifecycle, RoundDriver and Spec-Lock Todos Summary

**A pure, yield-free round FSM where round end fires exactly once, a stale round-1 backstop provably cannot end round 2 (shown with a working cancel and with a no-op cancel), and the deadline is exclusive; plus a thin os.clock/task.delay adapter and exactly three visible spec-lock todos.**

REQUIREMENTS.md checkboxes were not touched (orchestrator owns that). STATE.md and ROADMAP.md were not touched.

## Tasks and commits

| Gate | Commit | Message |
|------|--------|---------|
| RED (task 1) | `169f751` | `test(01-06): add failing RoundLifecycle spec for SCORE-06` |
| GREEN (task 1) | `fd36fce` | `feat(01-06): implement RoundLifecycle with round-ID tokens and idempotent end` |
| Task 2 | `2fe8869` | `feat(01-06): add RoundDriver adapter binding os.clock and task.delay` |
| Task 3 | `42dbf44` | `test(01-06): record CARD-09, CARD-10, CARD-12 spec-lock decisions as visible todos` |

No REFACTOR commit: nothing worth changing after GREEN (stylua formatting was applied before the GREEN commit).

## Exported signature (Phases 4 and 5 consume this)

`src/server/core/RoundLifecycle.luau`, verbatim:

```lua
export type Reason = "AllSpoonsClaimed" | "Timeout" | "Aborted"
export type Scheduler = {
	nowDeci: () -> number,
	delay: (seconds: number, fn: () -> ()) -> () -> (),
}
export type Deps = {
	scheduler: Scheduler,
	onEnded: (roundId: number, reason: Reason) -> (),
}
export type Lifecycle = {
	begin: (self: Lifecycle, durationSeconds: number) -> number,
	isOpen: (self: Lifecycle, roundId: number) -> boolean,
	endRound: (self: Lifecycle, roundId: number, reason: Reason) -> boolean,
	deadlineDeci: (self: Lifecycle, roundId: number) -> number?,
	activeRound: (self: Lifecycle) -> number?,
	endCount: (self: Lifecycle) -> number,
}
-- return { new = new }   where new(deps: Deps): Lifecycle
```

Reason enum: `AllSpoonsClaimed | Timeout | Aborted`. Methods are called with `:`.

Behaviour contract worth knowing before consuming it:

- `endRound` checks only "is this the current round, and not already ended". It does **not** check the deadline. A claim handler must call `isOpen(roundId)` first (the `claim` helper in the spec shows the intended shape). Skipping `isOpen` and calling `endRound(id, "AllSpoonsClaimed")` directly on the deadline tick will succeed if the timer has not run yet.
- `isOpen` at or after the deadline calls `endRound(id, "Timeout")` itself and returns false, so `onEnded` can fire from inside `isOpen`.
- `onEnded` runs after the round is marked ended and the backstop cancelled. A re-entrant `endRound` from inside `onEnded` returns false; `begin` from inside `onEnded` is allowed (tested).
- `begin` errors on a non-number, NaN, infinite or sub-decisecond duration, and errors if the previous round has not ended.
- `activeRound()` is nil once the current round has ended. `deadlineDeci(id)` answers for the most recently begun round only.

`RoundDriver.new(onEnded)` returns `{ lifecycle, beginRound() -> roundId, deadlineUnix(roundId) -> number? }`.

## Exclusive deadline

Owner default, applied without asking: `scheduler.nowDeci() >= endsAtDeci` closes the round. A claim arriving exactly on the deadline decisecond is outside the round. Tested: tick 19 accepts, tick 20 rejects, and the end is a `Timeout` end, never `AllSpoonsClaimed`.

## Verbatim test output

Round specs after GREEN:

```
$ lune run tests/run.luau -- --filter round
ok   tests/core/round.spec.luau::begin returns strictly increasing round ids
ok   tests/core/round.spec.luau::begin computes an integer-decisecond absolute deadline from the injected clock
ok   tests/core/round.spec.luau::begin rejects a duration that would leave a round with no usable deadline
ok   tests/core/round.spec.luau::begin while the previous round is still live is an error, not a silent overwrite
ok   tests/core/round.spec.luau::endRound returns true once, then false, and reports the id and reason it ended with
ok   tests/core/round.spec.luau::endRound called 100 times fires onEnded exactly once
ok   tests/core/round.spec.luau::endRound with an id that is not the active round returns false and fires nothing
ok   tests/core/round.spec.luau::onEnded receives the reason it was ended with, for each reason
ok   tests/core/round.spec.luau::stale backstop from round 1 cannot end round 2 (cancel works)
ok   tests/core/round.spec.luau::stale backstop from round 1 cannot end round 2 (cancel is a no-op, so the token alone does it)
ok   tests/core/round.spec.luau::a stale backstop firing with no round active is inert
ok   tests/core/round.spec.luau::the backstop ends its own round with reason Timeout at the deadline
ok   tests/core/round.spec.luau::a last claim before the deadline ends the round and the later timer adds nothing
ok   tests/core/round.spec.luau::deadline is exclusive: a claim exactly on the deadline decisecond is rejected
ok   tests/core/round.spec.luau::isOpen at the deadline rejects and routes to a Timeout end exactly once
ok   tests/core/round.spec.luau::tie, claim processed before the timer: the claim is outside the round, one Timeout end
ok   tests/core/round.spec.luau::tie, timer processed before the claim: the claim is outside the round, one Timeout end
ok   tests/core/round.spec.luau::primitive tie, endRound before the timer: first trigger wins, the timer is inert
ok   tests/core/round.spec.luau::primitive tie, timer before endRound: first trigger wins, the claim end returns false
ok   tests/core/round.spec.luau::state is ended BEFORE onEnded runs, so a re-entrant onEnded cannot end the round twice
ok   tests/core/round.spec.luau::onEnded may begin the next round, and that round is unaffected by the one that just ended
21 passed, 0 failed, 0 todo in 0.03s
```

Full suite, final state, with the three todos printed by the runner:

```
todo tests/engine/spec_lock.spec.luau::CARD-09 deal-time four of a kind: re-shuffle so no seat starts complete, including hands completable by a wild
todo tests/engine/spec_lock.spec.luau::CARD-10 joker completion: spend naturals first, so the four cards that leave are the natural ranks before any wild
todo tests/engine/spec_lock.spec.luau::CARD-12 fallback: if Gate G1 fails, jokers ship as blockers instead of wilds, both variants behind a flag from the start
...
58 passed, 0 failed, 3 todo in 0.36s        (exit 0)
```

Before this plan the suite was 37 passed, 0 todo (01-02 summary); now 58 passed (+21) and exactly 3 todo.

### TDD RED evidence (commit `169f751`)

```
$ lune run tests/run.luau -- --filter round
FAIL tests/core/round.spec.luau::<load>
     runtime error: error requiring module "../../src/server/core/RoundLifecycle": could not resolve child component "core"
0 passed, 1 failed, 0 todo in 0.03s        (exit 1)
```

This RED is a load failure (the module did not exist), not a stub-based per-case failure. It proves the spec could not pass without the implementation. The per-case teeth are shown by the mutation checks below, which is the stronger evidence for these tests.

### Mutation checks (each applied to a copy of the implementation, then restored; final file byte-identical to the committed one)

| Mutation | Result |
|---|---|
| A: remove the round-id comparison from `endRound` and the backstop guard | 3 FAIL: `endRound with an id that is not the active round...`, `stale backstop ... (cancel is a no-op ...)`, `onEnded may begin the next round...`. The cancel-works variant stays green, which is exactly why the no-op variant exists. No-op failure message: `r1 ended once, by the last claim (expected { {id=1, AllSpoonsClaimed} }, got { {id=1, AllSpoonsClaimed}, {id=1, Timeout} })`, i.e. the stale callback really did end round 2 under round 1's id. |
| B: `>=` changed to `>` (inclusive deadline) | 2 FAIL: `isOpen at the deadline...`, `tie, claim processed before the timer...` |
| C: ended flag set after `onEnded` instead of before | 2 FAIL: `state is ended BEFORE onEnded runs...`, `onEnded may begin the next round...` |
| D: `cancel()` never called | 1 FAIL: `stale backstop ... (cancel works)` (the pending-count assertion) |
| E: remove only the backstop-local `if currentId ~= roundId` guard | **0 FAIL, 21 pass** |

**Mutation E is a finding, not a pass.** The backstop-local id guard the plan prescribes is redundant: `endRound` already rejects any id that is not the current round, so the token comparison happens there too. I kept the backstop-local guard as defence in depth (the plan asks for it), but no test can distinguish it from `endRound`'s own check, and none should pretend to. The real protection is the id comparison in `endRound`, which mutation A proves is load-bearing.

## Why each test asserts the reason, not only the count

Per the wave-2 lesson, "round ended once" is never asserted by count alone:

- The stale scenario wraps the scheduler to record **which backstops ran**. With `cancelIsNoop = true` it asserts `fired == {1}` at t=300 (the stale callback demonstrably ran) and `pending` counts of 1 then 2 (cancel really did nothing); with a working cancel it asserts `fired == {}` and `pending` 0 then 1. So a pass in the no-op mode cannot be explained by cancellation, and a pass in cancel mode cannot be mistaken for the token working.
- Every `onEnded` assertion is `deepEqual(ended, { { id = rN, reason = "..." } })`, naming the round and the reason (Timeout vs AllSpoonsClaimed vs Aborted).
- Tie cases register a test callback on the deadline tick **before** or **after** `begin`, so ties break by registration order and the two arrival orders are real, not simulated by call order in the test body.

## Spec-lock todos (CARD-09, CARD-10, CARD-12)

Exactly three `t.todo` entries, printed on every run (see output above). Acceptance checks run: `grep -c 't.todo'` = 3; no `SCORE-06` or `FOUND-08` in the file; no `t.test` in the file; the runner summary reports `3 todo`.

### Deliberate deviation from ROADMAP.md

ROADMAP.md Phase 1 says the spec-lock defaults are "each written as a test". They are written as `t.todo` entries instead. **This is a deliberate deviation, not satisfaction of the ROADMAP wording.** A todo can never fail, so it is strictly weaker than what the ROADMAP promises. It is still the correct Phase 1 form: there is no card engine until Phase 2, so there is nothing to assert against, and a fake passing test would be worse than a visible todo. The todos keep the resolved defaults visible on every run so Phase 2 converts them rather than rediscovering the decisions.

Also deliberate: the SCORE-06 deadline tie rule and the FOUND-08 player cap are **not** todos here. Both are covered by executing tests in this phase (`tests/core/round.spec.luau`, and `tests/core/admission.spec.luau` from plan 01-08), so a todo would restate a passing check and inflate the open count. No fourth todo was added; no genuinely unresolved fourth item was found.

### Proposed Phase 2 exit criterion (for the next planner)

The `spec_lock` todo count must reach **0** before Phase 2 closes: each of CARD-09, CARD-10 and CARD-12 is converted into a real test against the engine, and the runner summary reads `0 todo`. STATE.md flags CARD-09 and CARD-10 as BLOCKING.

## Gate commands (all run, exit codes observed)

```
stylua --check src tests                                              exit 0
selene src tests                                                      0 errors / 0 warnings / 0 parse errors
selene --config selene.pure.toml src/server/core                      0 errors / 0 warnings / 0 parse errors
luau-lsp analyze --platform standard --base-luaurc .luaurc src/server/core     exit 0
luau-lsp analyze --platform standard --base-luaurc .luaurc tests/core          exit 0 (after fix, Divergence 2)
luau-lsp analyze --platform standard --base-luaurc .luaurc tests/engine        exit 0
mkdir -p build/01-06 && rojo sourcemap default.project.json --include-non-scripts -o build/01-06/sourcemap.json
                                                                      Created sourcemap at build/01-06/sourcemap.json
luau-lsp analyze --platform roblox --sourcemap build/01-06/sourcemap.json
  --definitions=tools/types/globalTypes.None.d.luau --base-luaurc .luaurc
  src/server/services src/server/core src/shared                      exit 0, 0 lines matching "error"
purity grep over non-comment lines of RoundLifecycle.luau             no match for game|workspace|script|task|os|tick|wait|warn|Instance
```

The sourcemap-backed run was **not** trusted on exit 0 alone: a scratch copy of `RoundDriver` with a mistyped shared require produced `TypeError: Unknown require: game/ReplicatedStorage/Shared/Config/Rnd`, so the sourcemap really resolves and the clean pass is real. The scratch file was deleted.

## Deviations from Plan

### Not run / not verifiable here

**1. `lune run scripts/ci/check-guards.luau` was NOT run.** `scripts/` does not exist in this worktree (the guard script belongs to a sibling wave-3 plan, 01-03/01-04). Task 2's acceptance criterion `lune run scripts/ci/check-guards.luau exits 0` is therefore unverified. I substituted explicit greps for the rules it would enforce on this file (no `OnServerEvent|FireClient|FireAllClients|RemoteFunction`, no relative cross-mount require, no literal `300`, the required `os.clock`/`task.delay`/`task.cancel`/`GetServerTimeNow`/`ROUND_CAP_SECONDS` present), all of which pass. Plan 01-10's whole-tree run is the authoritative check of rule R4/R6 on `RoundDriver`.

### Divergences found by executing

**2. [Divergence] luau-lsp mis-infers a loop variable over a literal-union array.** `for _, reason in reasons do` where `reasons: { RoundLifecycle.Reason }` typed `reason` as `string | string | string` and failed at the `endRound(r, reason)` call. Fixed by annotating the loop variable (`for _, reason: RoundLifecycle.Reason in reasons do`). No check was loosened.

**3. [Divergence] The plan's research example calls `sched:advance(...)`; the real FakeScheduler fields are plain functions.** Use `sched.advance(...)`, `sched.delay(...)`, `sched.nowDeci()`, `sched.pending()` (dot, no self), per the 01-02 summary.

**4. [Divergence] Acceptance criterion `grep -q 'deadline exclusive' tests/engine/spec_lock.spec.luau` conflicts with the "no SCORE-06 todo" rule.** The three prescribed todo strings do not contain "deadline exclusive", and a todo for it is explicitly forbidden. I satisfied the grep with a header comment pointing at where the tie rule is actually tested, avoiding the strings `t.test`, `SCORE-06` and `FOUND-08` that other criteria forbid. The comment is not a todo and does not change the count.

### Design choices (not in the plan, flagged for review)

- `begin` errors when the previous round has not ended. The plan was silent. Silently overwriting would orphan a live round's backstop and onEnded; an implicit `Aborted` would fire `onEnded` from inside `begin`. A loud error is the smallest-surprise option. A caller that wants to abort first calls `endRound(id, "Aborted")`.
- `begin` also rejects a duration that floors to zero deciseconds (born already expired), beyond the plan's "non-finite, non-positive, non-numeric".
- The backstop is scheduled with the caller's `durationSeconds`, not `durationDeci / 10`, so it uses the same `floor(x * 10)` truncation as FakeScheduler. A real `task.delay` could fire fractionally before the `os.clock`-derived deadline decisecond; the effect is an at-most-fraction-of-a-decisecond-early Timeout. Not addressed; noted for Phase 4/5 if sub-decisecond fairness ever matters.
- `RoundDriver` takes the deci-per-second factor from `Config.Round.DECISECONDS_PER_SECOND` rather than the literal `10` shown in the plan, so it holds no timing numbers.

### Rule 1-3 auto-fixes

None beyond item 2 above.

## Known Stubs

None. `RoundDriver` is intentionally not unit-tested (adapter, nothing to test under Lune); its live behaviour is exercised in Phase 4 and is not claimed as verified here. `RoundDriver` is also not yet wired into any boot code (plan 01-10 owns wiring).

## Threat Flags

None new. Register status: T-1-04 and T-1-29 mitigated and mutation-verified (A, and the 100-call case); T-1-30 mitigated (mutation B); T-1-32 mitigated (mutation C, no yields in core, purity grep); T-1-31 mitigated by construction (core takes time only from the injected scheduler; `GetServerTimeNow` appears only in `RoundDriver` and only outward) but the adapter half is static-checked only, not executed.

## Self-Check: PASSED

- Files exist: `src/server/core/RoundLifecycle.luau`, `src/server/services/RoundDriver.luau`, `src/shared/Config/Round.luau`, `tests/core/round.spec.luau`, `tests/engine/spec_lock.spec.luau`.
- Commits `169f751`, `fd36fce`, `2fe8869`, `42dbf44` present in `git log`.
- RED commit precedes GREEN commit; a `test(...)` then `feat(...)` sequence exists for the TDD feature.
- `git status --short` clean before this SUMMARY was added; `build/` is gitignored.
