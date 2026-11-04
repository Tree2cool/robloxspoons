---
phase: 02-card-engine-and-pacing-simulator
plan: 12
subsystem: planning-memory
tags: [gate-g1, owner-sign-off, planning-memory, phase-boundary-constraint, open-questions, carried-debt, honest-claim]

requires:
  - phase: 02-11
    provides: "src/shared/Config/CardPool.luau — the six shipped values this plan copies into PROJECT.md's Key Decisions, CARD-16's requirement line and ROADMAP's Phase 4 note; and the 0-todo suite that is Phase 2's exit condition"
  - phase: 02-14
    provides: "02-G1-REPORT.md and 02-sweep-data.json — the committed verdict every recorded claim cites, re-run at the owner's chosen operating point so the shipped pool is the confirmed one"
  - phase: 02-10
    provides: "the owner's recorded pre-sweep answers (the j >= 1 floor and the auto-pass candidate list), confirmed still standing at this plan's checkpoint"
  - phase: 02-08
    provides: "the measured 194,567 fuzzed actions — the number that closes the carried Phase 1 fuzz todo"
  - phase: 02-02
    provides: "SeatOrder and its locked four-bucket order, recorded in STATE.md together with the fact that its first consumer is Phase 6"
provides:
  - "PROJECT.md: the jokers decision resolved and citing the report, plus three new Key Decisions rows (the engine's anti-livelock valve with its honest limit, the auto-pass deadline ceiling, the auto-pass SELECTION rule)"
  - "REQUIREMENTS.md: CARD-01 and CARD-03..CARD-12 ticked and Complete; CARD-16 carrying BOTH Gate G1 constraints"
  - "ROADMAP.md: the G1 verdict under Phase 2 with criterion 5's wording kept auditable above it; a Phase 4 note naming both auto-pass constraints, the ~8% ValveForcedPass rate, the deciseconds boundary and the start-up ramp"
  - "STATE.md: Phase 2 complete; the locked contracts from plans 02-01/02/03/06/07/13; SeatOrder's Phase 6 consumer; the closed fuzz todo; V-35 and A4 carried with two assumptions recorded as retired; the accepted CI-time departure"
  - "02-RESEARCH.md: all seven of section 12's open questions annotated RESOLVED against what resolved them"
affects: [03, 04, 06]

tech-stack:
  added: []
  patterns:
    - "A constraint that crosses a phase boundary is recorded in four independent places (the config module, the requirement line, the roadmap note for the consuming phase, and the Key Decisions table), because the half that looks like a free implementation choice is the half that gets 'improved'"
    - "A decided Key Decisions row has its status and evidence filled in while its rationale text stays byte-identical — the rationale is the record of why, and CLAUDE.md forbids re-opening it"
    - "A settled open question gets a RESOLVED annotation naming what resolved it and where, appended rather than replacing the question: an open question that was silently answered is one somebody re-opens"
    - "A requirement moving Partial -> Complete keeps the caveat that made it Partial when the caveat is still true (CARD-05/06 have no Phase 2 consumer by design), instead of deleting the information to make a table look tidier"
    - "The must-FAIL grep discipline applies to this plan's own prose: quoting the removed text verbatim in the note that records its removal trips the grep that proves it was removed"

key-files:
  created:
    - .planning/phases/02-card-engine-and-pacing-simulator/02-12-SUMMARY.md
  modified:
    - .planning/PROJECT.md
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md
    - .planning/STATE.md
    - .planning/phases/02-card-engine-and-pacing-simulator/02-RESEARCH.md

key-decisions:
  - "Gate G1 PASSED is recorded in all four planning documents as a measured property of the SELECTED configuration — 37 stalled rounds in 320,000 gated, 0.012% aggregate and 0.070% worst cell against a 0.500% ceiling — never as zero and never as a property of the engine"
  - "AUTO_PASS_SELECTION = uniform-random-from-hand is recorded as a CONSTRAINT ON PHASE 4 in four places, because a greedy selection rule makes the deviation the simulator measured exactly zero and transfers nothing to the shipped game"
  - "The owner accepted the ~25-26s suite against CONTEXT's locked ~20s; recorded in STATE.md as an approved, measured departure rather than left in a SUMMARY file"
  - "CARD-04/05/06 move from Partial to Complete, but CARD-05/06 keep their 'first consumer is Phase 6' caveat: the ranking is implemented and locked, and the unwired-consumer fact is carried rather than deleted"
  - "ROADMAP's Phase 1 progress row was corrected from a stale 8/12 In progress to 12/12 Complete while in the file (Rule 1)"

metrics:
  duration: ~35m
  completed: 2026-11-04
  tasks: 2
  files_created: 1
  files_modified: 5
---

# Phase 2 Plan 12: Record the Gate G1 Verdict Summary

**Gate G1's verdict now lives where the project actually reads it: the jokers decision in PROJECT.md
is resolved and cites the committed report, three new Key Decisions rows pin the engine's valve and
both halves of the auto-pass constraint, eleven CARD requirements are ticked, ROADMAP records the
verdict under Phase 2 with criterion 5's original wording kept auditable above it, STATE.md carries
the locked engine contracts and the V-35/A4 debt forward, and all seven of research §12's open
questions are annotated RESOLVED — with the measured residual printed everywhere rather than rounded
to zero.**

## Task 1 — the owner's checkpoint response, verbatim

The checkpoint was presented and answered before any planning document was edited. Recorded verbatim
as delivered:

> **YOUR TASK 1 CHECKPOINT IS ALREADY ANSWERED.** Your plan opens with a blocking owner checkpoint.
> The owner has already decided every point, so record the answers and proceed — do not stop and wait.
>
> - **(a) The joker floor `j >= 1`:** confirmed correct. Measured, Wild and Blocker BOTH clear every
>   bar at every roster size, so CARD-12 ships as a live flag with real tests rather than a
>   contingency. `j = 0` was swept and reported as a negative result.
> - **(b) The AFK deadline:** 8.0s, selected by the sweep.
> - **(c) The pool:** **k = 3**, chosen by the OWNER from the bar-sensitivity ladder, overriding the
>   bar's own k=6. Record the reasoning, not just the number: every candidate k=2..k=6 cleared all
>   five bars, the firing-rate curve is smooth with no elbow so the bar *chooses* rather than
>   discovers, and k=3 is the tightest pool reaching a clean zero stall rate — giving up ~2s of
>   starting-gun speed against k=2 while cutting forced passes by a third, and avoiding k=6's ~45%
>   slower start. The sweep was then **re-run** so the shipped pool is also the confirmed one.
> - **(c2) The CI-time overshoot:** the full suite is ~25–26s against CONTEXT's locked "~20s".
>   **The owner accepts the overshoot.** Nothing was trimmed to hide it: the 500-round floor, every
>   mutation case and every bar are intact. Record it as an accepted, measured departure from a
>   locked decision — not as a silent one.

Points (b2) and (d) were not contradicted and stand as the plan presented them: the valve ships
enabled and its claim is the narrow one ("zero observed stalls for the selected pool at the confirmed
round count", never "the engine cannot stall"); and G1's pacing half measures the bot, not the game,
while its solvability half is a theorem independent of the bot model.

**No change was requested**, so nothing was re-run and `src/shared/Config/CardPool.luau` was not
touched. The sweep, the report and the config module were already mutually consistent and remain so.

### The (c2) response, recorded explicitly

A locked-decision departure that reaches only a SUMMARY file was never actually approved, so this one
is recorded in **STATE.md's Blockers/Concerns section** as well as here:

> **Accepted departure from a locked decision (owner, 2026-11-04):** 02-CONTEXT locked "Phase 1's CI
> is ~20s and that should stay true". The suite now runs ~25–26s (Phase 1 baseline 15.94s + plan
> 02-09's measured 8.0s simulator subset + 02-08's fuzz suite and the new engine specs). **The owner
> accepts the overshoot.** Nothing was trimmed to hide it: the 500-round statistical floor, every
> mutation case and every bar are intact.

The measured number at this plan's close is **25.20s** for `tests/run.luau` (26.40s on the baseline
run before any edit) and **26.3s** for `scripts/verify.luau`. This also closes deferred item
**D-02-09-3**, which recorded the overshoot and named plan 02-12's checkpoint as its owner.

### Two things that were already done before this plan ran

Recorded so the next reader does not look for them as outstanding work:

1. **CARD-09/10/11/12 were already marked Complete** in REQUIREMENTS.md, checkboxes and traceability
   table both, by the orchestrator after plan 02-11 correctly left the file alone. This plan ticked
   the remaining seven (CARD-01, CARD-03..CARD-08) and enriched the CARD-11 and CARD-12 traceability
   rows with the verdict and the live-flag note.
2. **`02-G1-REPORT.md`'s triage section was already folded.** It reads "No round ended on the action
   cap; nothing to triage" with the measured basis. The report was not edited by this plan.

## Task 2 — the exact edits, document by document

### `.planning/PROJECT.md`

| Edit | What changed |
|---|---|
| The jokers bullet in the Card phase section | "This ships **only if** a headless bot simulator proves..." replaced with the decided outcome: `j = 1` Wild over `ranks = seatCount + 3` (circulation 13) with the valve enabled, the measured 37/320,000 residual against the 0.500% ceiling, median first completion 16.2s and p95 23.7s, the report path, and the fact that Blocker is a **live flag** rather than a dead fallback (which is also why `k >= 1` is mandatory) |
| Key Decisions row "Jokers as wilds, gated on a solvability simulator" | Outcome column `— Pending` -> **Wilds — Gate G1 PASSED** with the pool, the joker count, the mode, the measured residual and the report path. **The rationale column is byte-identical**: CLAUDE.md forbids re-opening a recorded decision, so a row's *status* and *evidence* may be filled in while its *reason* stays as written |
| Three new Key Decisions rows | (1) the engine's anti-livelock valve, with the honest limit **in the same row** — demonstrated for the selected pool at the confirmed round count, not universally, and k=2/j=2 carries a residual too; (2) the auto-pass deadline ceiling; (3) the auto-pass SELECTION rule, which gets its own row precisely because it is the half that looks like a free implementation choice |
| Footer | Last-updated line moved to 2026-11-04, naming plan 02-12 |

`grep -c 'Pending'` fell from **32 to 31** — exactly the one row that was resolved, and none of the
three added rows reintroduces the word.

### `.planning/REQUIREMENTS.md`

- **Checkboxes ticked:** CARD-01, CARD-03, CARD-04, CARD-05, CARD-06, CARD-07, CARD-08 (CARD-09
  through CARD-12 were already ticked). CARD-02 and CARD-13 onwards untouched.
- **Traceability table:** CARD-01, CARD-03, CARD-07, CARD-08 `Pending -> Complete`. CARD-04
  `Partial -> Complete` (the ring that realises the circulation identity landed in 02-06/02-07).
  CARD-05 and CARD-06 `Partial -> Complete` **keeping the caveat that made them Partial**, reworded to
  the still-true fact: the ranking is locked by corpus and **its first consumer is Phase 6's match
  lifecycle**. CARD-11 gained the verdict and the V-35/A4 scope note; CARD-12 gained the live-flag
  note.
- **CARD-16** now carries a bracketed Gate G1 constraint naming **both axes**: the deadline must not
  exceed `CardPool.AUTO_PASS_MAX_SECONDS` (8.0s), **and** the card it passes must be chosen by
  `CardPool.AUTO_PASS_SELECTION` = `uniform-random-from-hand`, with the reason each matters and the
  report cited. This is the outward edge of the G1 decision and research §3.6's named Phase 2 ->
  Phase 4 dependency.

### `.planning/ROADMAP.md`

- **Phase 2:** success criterion 5 is kept **verbatim**, with the verdict recorded immediately below
  it — the selected configuration, the five bars with their measured worst cases, and an explicit
  paragraph stating that criterion 5's literal "zero stalls" bar was **not** met by any pool this
  engine has and became an explicit residual ceiling (amendment A8, owner-approved). Keeping the
  original wording above the verdict is what makes a quietly relaxed gate visible (threat T-2-58).
- **Phase 4:** a new "Note on CARD-16" with both constraints as numbered items, plus three things
  that would otherwise have been lost in a summary file: `ValveForcedPass` fires in ~8% of rounds at
  a full roster (up to 15.8% at tighter pools) and needs a real affordance; the simulator's clock is
  float seconds while the shipped clock is integer deciseconds (Non-Negotiable Rule 5), so round at
  the boundary; and the start-up ramp is real at ~8.3s for N=10 against a 4.6s median
  time-to-first-completion at N=3, so far seats need a "waiting for cards" affordance.
- **Plan list:** all 14 checkboxes ticked. The "14 plans in 10 waves" count and the `02-13`/`02-14`
  lines were already correct and were not rewritten.
- **Progress table and phase list:** Phase 2 -> `14/14 | Complete (Gate G1 PASSED) | 2026-11-04` and
  its phase-list checkbox ticked. **Deviation (Rule 1):** Phase 1's row was a stale
  `8/12 | In progress` with a malformed extra trailing cell, contradicting STATE.md's "COMPLETE and
  verified"; corrected to `12/12 | Complete | 2026-11-03`.

### `.planning/STATE.md`

- **Frontmatter:** `completed_phases 1 -> 2`, `completed_plans 12 -> 26`, `stopped_at` -> Phase 2
  complete, `percent 46 -> 25`. The percent is now **phase** progress (2 of 8), not plan progress:
  26 of 26 *known* plans are complete but Phases 3-8 are still TBD, so a plan-ratio reading would
  have printed 100% for a milestone that is a quarter done.
- **Current Position:** Phase 2 complete, 14/14, Gate G1 PASSED with the selected configuration, the
  honest residual, and the `509 passed, 0 failed, 0 todo` exit-condition confirmation.
- **Accumulated Context > Decisions:** the G1 decision; the six `CardPool` values; the owner's
  k=3-over-k=6 reasoning; **plan 02-13's valve with its locked firing point (immediately after a
  non-completing `Draw`, on the drawing seat) and its naturals-only choice rule**; **plan 02-02's
  locked four-bucket seat order** with `dealer == seatOrder[1]` and the two non-special-cases;
  **plan 02-06's locked dump order** (hand ascending, then inbox FIFO) and the `terminal` bucket;
  **plan 02-07's locked reject precedence, event order and valve call rule**; **plan 02-03's
  pure-zone `coroutine`/`os.` ban**; and **plan 02-01's locked violation ORDER of `Invariants.check`**
  with the warning that reordering it would make conservation bugs surface as stall statistics.
- **A new "Notes that would otherwise be lost" block:** `SeatOrder.luau` has **no Phase 2 consumer by
  design** and its first caller is Phase 6's match lifecycle (`nextSeatOrder` / `dealerOf`) — without
  that line it is an untracked orphan a later cleanup pass could reasonably delete. Plus the
  deciseconds boundary, the ~8% `ValveForcedPass` rate and the start-up ramp.
- **Pending Todos:** the Phase 2 row is **gone**, replaced by a CLOSED note carrying the evidence as a
  number — **194,567 actions** (170,332 accepted, 24,235 rejected) across 500 rounds at every seat
  count from 2 to 9, 1.95x ROADMAP criterion 1's 100,000-action bar. The Phase 5, 6 and 7 rows are
  untouched.
- **Blockers/Concerns:** the stale card-engine blocking entry is **gone** (CARD-09 and CARD-10 are
  asserting tests now, not defaults) and replaced by a RESOLVED line. A "Carried debt from Gate G1"
  block was added: **V-35 stands**, **A4 stands**, the scope note on what they limit, **amendment A7
  RETIRED the deviation-rate assumption** (the zero-stall result no longer depends on how often humans
  deviate, because the engine's valve deviates for them), **plan 02-03 RETIRED the engine's half of
  V-15**, the residual's triage outcome, and the owner's accepted CI-time departure.

**The triage question the plan asked to carry forward, answered:** the k=2,j=2 valve-on residual is
**neither a `CapArtifact` nor an unexplained `ResidualLivelock`**. `capArtifactCandidates` is empty in
all 1,132 cells of the run across 1,501,000 simulated rounds and `hitActionCap` is false in every
confirm row, so `02-triage.json` is absent by measurement rather than omission. Every stalled round
this engine produces is a 300s `time-cap` round, which a raised ACTION cap cannot rescue — which is
exactly why the recorded claim is scoped to the selected pool and the 37/320,000 residual is printed
rather than rounded away.

### `.planning/phases/.../02-RESEARCH.md` — the seven RESOLVED annotations

Appended as a one-line blockquote after each question's body. **No question text, recommendation or
measured table was edited.**

| OQ | Question | RESOLVED by |
|---|---|---|
| **OQ-A** | The gate has no passing configuration | None of its three options as written — amendment **A7**'s engine valve took a fourth route, with option 2's auto-pass surviving as a secondary mitigation and amendment A8 replacing the literal zero bar with an owner-approved 0.500% residual ceiling. Evidence: the report's valve section and plan 02-13's deterministic fixture (escapes on action 113 through the real `apply`, provably never with the valve disabled) |
| **OQ-B** | `seatCount` ambiguity | Amendment **A3**: seated seekers, `ranks = (players − 1) + k`, implemented once in `Pool.poolConfig`. Measured, the off-by-one moved the valve-off stall rate by a factor of 40 |
| **OQ-C** | The selection rule deletes the jokers | **The owner's answer at plan 02-10's pre-sweep checkpoint**, recorded verbatim in `02-10-SUMMARY.md`: `j >= 1`, the sweep CLEARS `j` rather than minimising it, `j = 0` measured and reported as a comparison. Re-confirmed at this plan's sign-off |
| **OQ-D** | Must the pool pass in both joker modes? | **Yes**, enforced by step 3 of the sweep's selection rule and by the CI subset. The "available behind a flag" language stands rather than being dropped |
| **OQ-E** | Occupancy floor | Amendment **A2**, the 60% bar in `evaluateBars`. Load-bearing: without it the rule picks `k=0, j=1` at ~0.17 occupancy |
| **OQ-F** | Dealer with zero finishers, multiple empty-handed seekers | **Plan 02-02's locked four-bucket total order** and its corpus — neither is a special case |
| **OQ-G** | The departing seat's dump order | **Plan 02-06's locked "hand ascending, then inbox in FIFO order"**, locked by a test as the question required |

## Deviations from Plan

### Auto-fixed

**1. [Rule 1 - Bug] ROADMAP's Phase 1 progress row was stale and malformed**
- **Found during:** Task 2, while updating the Phase 2 row the plan asked for
- **Issue:** `| 1. Foundations, Contracts and Spec Lock | 8/12 | In progress | - | - |` — contradicts
  STATE.md's "Phase 1 COMPLETE and verified at commit `70fd9ce`", and carries a fifth table cell the
  four-column header does not have
- **Fix:** `| 12/12 | Complete | 2026-11-03 |`. In scope: this plan owns ROADMAP.md and was editing
  the adjacent row
- **Commit:** `736f658`

**2. [Rule 1 - Bug] This plan's own prose tripped two of its own must-FAIL greps**
- **Found during:** Task 2 verification
- **Issue:** The notes recording the *removal* of the Phase 2 fuzz todo and the stale card-engine
  blocker quoted the removed text verbatim, so `grep -q 'toy properties at 200 iterations'` and
  `grep -q 'BLOCKING for card engine'` both still exited 0 — the greps that are supposed to prove the
  rows are gone
- **Fix:** Both notes reworded to say the same thing without the literal substrings ("the fuzz harness
  had never run beyond toy-scale properties at a 200-iteration count"; "the former card-engine
  blocking entry is gone"). The honest-claim grep discipline applies to the record of a removal as
  much as to the removal
- **Commit:** `736f658`

**3. [Rule 1 - Bug] `gsd-sdk query state.record-metric` recomputed STATE.md's frontmatter wrongly and
reflowed its lists**
- **Found during:** the state-update step, after task 2's commit
- **Issue:** the handler does more than append a metric row. It recalculated the frontmatter to
  `completed_phases: 1` (Phase 2 **is** complete), `completed_plans: 25`, `percent: 96` — the
  plan-ratio reading that prints 96% for a milestone a quarter done — and inserted a blank line between
  every bullet in the Decisions, Blockers and Todos lists, flattening the structure this plan had just
  authored
- **Fix:** STATE.md restored to the hand-authored version the plan specifies, keeping the two things
  the handler got right: `status: planning` (more accurate than `executing` now) and its real
  timestamp, plus the metric row itself (`| Phase 02 P12 | 35m | 2 tasks | 6 files |`) added by hand.
  The remaining state handlers (`advance-plan`, `update-progress`, `record-session`, `add-decision`,
  `roadmap update-plan-progress`, `requirements mark-complete`) were **deliberately not run**: this
  plan owns the exact content of all four documents, `advance-plan` would increment a plan counter past
  the end of the phase, and `requirements mark-complete CARD-11 CARD-12` would flatten the evidence
  notes just written into those traceability rows. Every effect those handlers exist to produce is
  present, written by hand to the plan's specification

### Judgement calls recorded rather than silently taken

**CARD-04/05/06 move Partial -> Complete, but CARD-05 and CARD-06 keep their caveat.** The plan
directs that all eleven requirements this phase owns be marked Complete. Plan 02-02 had deliberately
recorded CARD-05/06 as **Partial** following the FOUND-08 precedent, because the ranking has no
consumer until Phase 6. Both readings are defensible; deleting the information is not. So the rows are
`Complete` as the plan directs, with the still-true fact preserved in the status cell — **first
consumer is Phase 6's match lifecycle** — and the same fact recorded independently in STATE.md's new
notes block, where a Phase 6 planner will actually look. CARD-04's caveat was simply spent: the ring
that realises the circulation identity landed in plans 02-06 and 02-07.

**`percent` reads phase progress, not plan progress.** See the STATE.md section above. 26 of 26 known
plans are done, but Phases 3-8 are TBD, so the plan ratio would have printed 100% for a milestone
that is a quarter complete.

## Nothing outstanding from this plan's own scope

No fix-attempt limit was reached, no architectural decision arose (Rule 4 never fired), no
authentication gate was hit, and no stub was introduced — this plan ships markdown with no runtime
surface (threat T-2-62, accepted). The threat register's four `mitigate` dispositions are all
satisfied: T-2-58 (criterion 5's wording kept above the verdict), T-2-59 (both constraints in four
places), T-2-59b (sign-off recorded before any document was edited), T-2-59c (seven RESOLVED
annotations), T-2-60 (every value copied from `02-11-SUMMARY.md` and `CardPool.luau`, with 02-11's
spec-lock case still asserting the config matches the report) and T-2-61 (V-35 and A4 in STATE.md).

## Verification

```
$ lune run tests/run.luau | tail -1
509 passed, 0 failed, 0 todo in 25.20s

$ lune run scripts/verify.luau | tail -3
verify: all 14 automated steps passed in 26.3s
  6 signed off, 0 unsigned.
```

**Phase 2's exit condition is the todo count, and it is 0.** A green run with todos remaining is not
a finished phase, and the pass count alone would not have revealed it.

All 14 of task 2's acceptance greps pass, including the four that must FAIL:

| Grep | Expected | Result |
|---|---|---|
| `02-G1-REPORT` in PROJECT.md | exit 0 | pass (5 occurrences) |
| `AUTO_PASS_MAX_SECONDS` / `AUTO_PASS_SELECTION` in REQUIREMENTS.md | exit 0 | pass (1 each, on the CARD-16 line) |
| `AUTO_PASS_MAX_SECONDS` / `AUTO_PASS_SELECTION` in ROADMAP.md | exit 0 | pass (2 each, under Phase 4) |
| `uniform-random-from-hand` in PROJECT.md | exit 0 | pass (a Key Decisions row, not only a code comment) |
| `CARD-11 \| Phase 2` shows `Complete` | exit 0 | pass |
| `14 plans` in ROADMAP.md, with `02-13` and `02-14` named | exit 0 | pass |
| `RESOLVED` count in 02-RESEARCH.md | `>= 7` | **7** |
| `SeatOrder` in STATE.md | exit 0 | pass |
| `V-35` in STATE.md | exit 0 | pass (2) |
| `Pending` count in PROJECT.md | `< 32` | **31** |
| `guarantees zero\|theorem about the engine` in all four | **exit 1** | pass |
| `toy properties at 200 iterations` in STATE.md | **exit 1** | pass |
| `BLOCKING for card engine` in STATE.md | **exit 1** | pass |
| criterion 5's original wording still present in ROADMAP.md | exit 0 | pass |

## Commits

| Commit | What |
|---|---|
| `736f658` | `docs(02-12): record the Gate G1 verdict in the planning documents` — all five documents |

Task 1 changed no file by design, so it has no commit: it presented the finished work and its response
is recorded here.

## Self-Check: PASSED

- `.planning/PROJECT.md` — FOUND
- `.planning/REQUIREMENTS.md` — FOUND
- `.planning/ROADMAP.md` — FOUND
- `.planning/STATE.md` — FOUND
- `.planning/phases/02-card-engine-and-pacing-simulator/02-RESEARCH.md` — FOUND
- `.planning/phases/02-card-engine-and-pacing-simulator/02-12-SUMMARY.md` — FOUND
- commit `736f658` — FOUND in `git log`
- `736f658` deletes no tracked file (`git diff --diff-filter=D HEAD~1 HEAD` is empty)
