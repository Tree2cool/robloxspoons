---
phase: 02-card-engine-and-pacing-simulator
verified: 2026-11-04T00:00:00Z
status: human_needed
score: 16/16 must-haves verified
overrides_applied: 1
overrides:
  - must_have: "Gate G1: the bot pacing simulator reports zero stalls at every player count from 3 to 10 and acceptable time-to-first-completion, selecting the card pool and joker count"
    reason: >
      The literal "zero stalls" bar is not met and is not claimed. No pool this engine has reaches it.
      02-CONTEXT amendment A8 resolution 2 replaced it with an explicit 0.500% residual ceiling,
      owner-approved and dated, and ROADMAP.md itself now carries both the verbatim criterion and the
      departure. Verified independently from 02-sweep-data.json: 37 stalled rounds in 320,000 gated
      (0.0116% aggregate, 0.0700% worst cell). `Simulator.evaluateBars` is unchanged and its
      zero-stall verdict rides on every cell as `lockedVerdict` — it is FALSE in 20 of the 32 gated
      cells, so the unmet bar is visible in the artefact rather than erased.
    accepted_by: "owner (recorded in ROADMAP.md Phase 2, STATE.md, 02-12-SUMMARY.md task 1)"
    accepted_at: "2026-11-04"
human_verification:
  - test: "Decide whether the missing 02-14-SUMMARY.md is acceptable at phase close"
    expected: >
      Plan 02-14 produced the entire evidence base for Gate G1 (02-G1-REPORT.md, 02-sweep-data.json)
      and is ticked [x] in ROADMAP.md, but it is the only plan in the phase with no SUMMARY. The
      superseded first sweep (which selected k=6 and confirmed it at 10,000 rounds/cell) and the
      decision to change the valve-rate bar exist only in commit messages 88e4046, c4a6792, 0d76087.
    why_human: "A missing execution record is a process decision, not a code defect. Nothing is wrong in the code; the audit trail for the most load-bearing plan is thinner than for the other thirteen."
  - test: "Decide whether 02-G1-REPORT.md section 2's provenance for the valve-rate bar should be corrected"
    expected: >
      Section 2 attributes the 20% bar to "amendment A8 resolution 1, re-derived from the measured
      curve". scripts/sim/sweep.luau, which sets it, says the opposite in capitals: "IT IS NOW 0.20,
      AND THE REASON IS AN OWNER DECISION, NOT A MEASUREMENT ... a REGRESSION GUARD around a chosen
      operating point, not a discovery mechanism". The report's own section 4b is honest ("a
      judgement on a smooth monotone curve"); only section 2's table softens it.
    why_human: "The report is the artefact future phases cite. Whether to amend a committed gate report is an owner call."
  - test: "Decide whether CardPool.JOKER_MODE should be pinned to \"Wild\" by a test"
    expected: >
      Nothing in the 509-case suite can detect the shipped joker mode being flipped to Blocker. Both
      assertions that touch it (spec_lock case (a), subset case) accept either literal, and spec_lock
      case (d)'s config-vs-report diff searches the Verdict section, which names BOTH "Wild" and
      "Blocker" — so the mode half of that drift check cannot fail for either legal value. PROJECT.md
      records jokers-as-wilds as a design property.
    why_human: "Both modes clear every bar, so a flip is a design regression rather than a correctness one. Whether to lock the default is a design call."
  - test: "Register V-35 and A4 in MANUAL-CHECKS.md"
    expected: >
      02-VALIDATION.md declares two Manual-Only Verifications (V-35, the bot reaction-time
      distribution; A4, human deviation from pure greed). Neither appears in MANUAL-CHECKS.md, which
      NEEDS_HUMAN.md names as authoritative for human gates; `grep -n "V-35\|CARD-11" MANUAL-CHECKS.md`
      returns nothing. They are carried in STATE.md and 02-G1-REPORT.md section 8 only.
    why_human: "A Phase 4/6 executor reading the project's human-gate index will not see the calibration gate. Two table rows; cheap now."
deferred:
  - truth: "Whether a bot's reaction-time distribution represents real humans (V-35)"
    addressed_in: "Phase 4 / Phase 6"
    evidence: "02-VALIDATION.md Manual-Only: 'Calibrate in Phase 4/6 against live sessions'. ROADMAP Phase 4 research: 'Test on a real phone early'; Phase 8: tuning on real latency data."
  - truth: "Whether humans deviate from pure greed often enough for G1's pacing half to transfer (A4)"
    addressed_in: "Phase 4 / Phase 6"
    evidence: "02-VALIDATION.md Manual-Only: 'Measure deviation rate at the first real playtest'. Retired as a dependency of the SOLVABILITY claim by amendment A7 (the valve deviates instead of the player)."
  - truth: "CARD-05 / CARD-06 wired to a production consumer"
    addressed_in: "Phase 6"
    evidence: "ROADMAP Phase 6 requirements MATCH-01/02/03 (match lifecycle, hider rotation, seat order). STATE.md: 'src/server/engine/SeatOrder.luau has no consumer inside Phase 2 by design ... first caller is Phase 6's match lifecycle.'"
---

# Phase 2: Card Engine and Pacing Simulator — Verification Report

**Phase Goal:** A pure, headless, synchronous card-ring engine exists, is fuzz-proven, and a bot
simulator has decided the joker question before any UI is built
**Verified:** 2026-11-04
**Status:** human_needed — the goal is achieved; four items are owner decisions about the record, not defects
**Re-verification:** No — initial verification

---

## Verdict in one paragraph

**The phase goal is achieved and Gate G1 is genuinely passed, in its honest form.** The engine is
pure, synchronous, has no Roblox API path and no yield seam; the conservation claim is proven at
194,567 fuzzed actions across every table size 3–10 with the full four-bucket partition identity
checked after every single action; and the joker question is decided with both variants live. I
re-derived every headline number in the G1 report independently from `02-sweep-data.json` and all of
them check out exactly, including the 37/320,000 residual. I also replayed 15 of the 37 stalled
seeds through the real engine and they reproduce exactly. **Criterion 5's literal "zero stalls" bar
is not met, is not claimed, and the substitution is owner-approved and recorded in four
documents** — that is honest and sufficient, not an overreach. The findings below are real and
worth acting on, but none of them blocks Phase 2 from closing.

---

## Independent re-derivation of the G1 headline

Computed from `02-sweep-data.json` without reference to the report's prose:

| Claim in 02-G1-REPORT / STATE / CardPool | Re-derived from the data artefact | Agrees |
|---|---|---|
| 32 gated cells, 10,000 rounds each = 320,000 gated rounds | `role == "gated"` → 32 cells, 320,000 rounds, all `k=3 j=1 autoPass=8.0 valve=ON` | ✓ |
| 37 stalled rounds, 0.012% aggregate | 37 (`CapReached` summed over gated), 0.011563% | ✓ |
| worst cell 0.070% | max gated `stallRate` = 0.0007 | ✓ |
| median first completion 16.2s (bar 45s) | max gated `medianFirst` = 16.183s | ✓ |
| p95 first 23.7s (bar 120s) | max gated `p95First` = 23.686s | ✓ |
| minimum occupancy 0.825 (bar 0.600) | min gated `occupancyMean` = 0.82533 | ✓ |
| worst valve firing rate 8.240% (bar 20%, margin 10%) | max gated `valveFiringRate` = 0.0824 | ✓ |
| `marginal = false` | `selection.marginal = false` | ✓ |
| 1,132 cells / 1,501,000 simulated rounds | 1,132 cells, 1,501,000 rounds | ✓ |
| no round ended on the action cap; `seenResets` 0 everywhere | `hitActionCapSeeds` empty in all cells; `valveSeenResetsTotal` 0 | ✓ (see F3) |
| valve-off twins at the shipped pool stall 3.58–8.31% | confirm `role=mechanism`: 0.0621 / 0.0358 / 0.0831 / 0.0533 | ✓ |
| Blocker clears every bar at every N | 16 Blocker gated cells, `verdict=true` in all 16 | ✓ |
| zero-stall bar still evaluated and recorded | `lockedVerdict` FALSE in 20 of 32 gated cells | ✓ |
| `Unsatisfiable` outcomes | **0 across all 1,501,000 rounds in every cell** | ✓ |

Suite and gate chain, re-run here:

```
lune run tests/run.luau              -> 509 passed, 0 failed, 0 todo in 24.36s
lune run scripts/verify.luau         -> all 14 automated steps passed in 26.2s
lune run scripts/ci/check-guards.luau -> ok (85 files, 227 requires, 20 guarded roots), exit 0
--filter engine/fuzz                 -> 194,567 actions, 500 rounds, seatCounts 2..9 all covered
--filter purity                      -> 7 passed
```

---

## Goal Achievement

### Observable Truths — the five ROADMAP success criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Conservation invariant over 100k+ fuzzed actions at every table size 3–10, including leavers, idle seats and mid-pass departures | ✓ VERIFIED | `tests/engine/fuzz.spec.luau` measured here: **194,567 actions** (170,332 accepted, 24,235 rejected), `checksRun = 194,567` — `Invariants.check` ran once per action, asserted by `checksRun >= totalActions`. Seat counts 2..9 = players 3..10 (amendment A3), observed 63/66/71/64/63/54/56/63 rounds. Churn: 1,195 Disconnected + 1,194 Benched removals; ring-shrink milestones all hit (dealer 484, →2 437, →1 500, emptied 464); all seven reject codes ≥ 1,584 observations each. See F7/F8 for two coverage nits. |
| 2 | Draw only at exactly 4; a pass lands in the next LIVE seat's pile resolved at execution time; last seat's passes land beneath the dealer's deck so the deck never runs dry | ✓ VERIFIED | `Engine.apply` draw path returns `HandNotFour` at any size ≠ 4 (2,602 fuzz observations). `Ring.pass` has **no target parameter** and `Types.Intent`'s Pass variant has no `to`/`index` field, so the property is structural, not conventional (CLAUDE.md rule 7). `ring.spec::the target is resolved at execution time`; `apply.spec::a departed seat rejects its own intents while a pass TARGETING it lands downstream`. `Ring.luau` contains **no last-seat branch** — seat m's `next` *is* the dealer. "Never runs dry" reduces to `circulation = 4k + j = 13 >= 1`, derived independently by `Invariants.expectedCirculation` and compared against a container walk after every action. |
| 3 | Four of a kind on draw removes the seat immediately, the ring closes up, the removed seat's cards reach the successor and are never destroyed | ✓ VERIFIED | One completion check in the whole engine, on the draw path only. `apply.spec::a completing draw emits Drew, Completed, SeatRemoved in that order, from ONE apply`. `Ring.removeSeat` is one generic operation for all three causes; dump order locked (hand ascending, then inbox FIFO); the sole-seat case routes to `state.terminal` rather than a nil path, so "never destroyed" is literally assertable by the partition identity. `removal.spec::MUTATION: destroying a removed seat's cards breaks conservation and kills the multiset` — and `Invariants.satisfiable` is asserted **directly** there, because `circulation` precedes `unsatisfiable` in the locked violation order (a correction 02-VALIDATION records against its own earlier wording). No shipped path can destroy a card; the sabotage lives in `scripts/sim/Simulator.luau` only. |
| 4 | Dealer and next-round seat order computed correctly from the previous find order, including first-finder-is-the-hider and the random round-1 dealer | ✓ VERIFIED (computation) | `SeatOrder.nextSeatOrder` is one four-bucket total order with `dealerOf` as the single reader; 28 corpus cases including `the first finder is the hider`, `zero finishers last round`, `three empty-handed seekers, not one`, `the find order names a departed player`, `mass leave: no previous finisher is still in the server`, `round 1 is the same function with a seeded shuffle`, `round 1 without an rng errors rather than falling back`. **No production consumer until Phase 6** — see the CARD-05/06 judgement below. |
| 5 | **Gate G1:** zero stalls at every player count 3–10, acceptable time-to-first-completion, selecting the pool and joker count; jokers as wilds only if it passes, else blockers, both behind a flag from the start | ✓ PASSED (override) | **Literal form: NOT MET.** No pool reaches zero; the locked bar's own verdict (`lockedVerdict`) is false in 20 of 32 gated cells. **Amended form: MET.** 37/320,000 = 0.0116% against the 0.500% residual ceiling amendment A8 set, worst cell 0.0700%; median first 16.2s ≤ 45s; p95 23.7s ≤ 120s; occupancy 0.825 ≥ 0.600; valve firing 8.24% ≤ 20% (and ≤ the 10% margin bar); `marginal = false`; all five bars clear in **both** joker modes and **both** churn variants at **every** N from 3 to 10. Pool selected: `k = 3`, `j = 1`, 8.0s deadline, valve ON. Blocker is a **live flag**, not a contingency. |

**Score:** 5/5 criteria verified (criterion 5 against the owner-approved amended bar).

### Required Artefacts

| Artefact | Expected | Status | Details |
|---|---|---|---|
| `src/server/engine/Types.luau` | shared vocabulary, locked violation order | ✓ VERIFIED | 9-name `Violation` order locked three ways (type, comments in two files, a test) |
| `src/server/engine/Invariants.luau` | circulation, partition identity, satisfiability, canonical hash | ✓ VERIFIED | `hash` excludes `counters`/`valve`/`rankOf` — load-bearing for the valve, asserted by `invariants.spec` |
| `src/server/engine/Pool.luau` | poolConfig, shuffle, CARD-09 deal | ✓ VERIFIED | A3's `n − 1` written in exactly one place; `openingHandIsBad` checks both bad shapes separately plus the mode asymmetry; rejection counter returned so the predicate is falsifiable |
| `src/server/engine/Hand.luau` | completion detection, naturals-first, Wild/Blocker divergence | ✓ VERIFIED | one function, two branches; uniqueness proved exhaustively at j ≤ 2 **and** the tripwire shown to fire at j = 3 |
| `src/server/engine/Ring.luau` | pass/draw/wrap, one generic seat removal | ✓ VERIFIED | no last-seat branch, no 2-ring branch, no destroy path, no `target` parameter |
| `src/server/engine/Valve.luau` | anti-livelock valve | ✓ VERIFIED | returns a card id; the engine performs the pass; naturals-only uniform choice; arm gate is a cost gate; see the valve judgement below |
| `src/server/engine/Engine.luau` | `newRound` + the one mutation entry point | ✓ VERIFIED | `apply(state, intent)` — two parameters, no handler, no clock, events returned not broadcast; seven reject codes in locked precedence; valve wired inside where no caller can forget it |
| `src/server/engine/SeatOrder.luau` | one total order for dealer and seat order | ⚠️ VERIFIED, ORPHANED BY DESIGN | zero production callers (the one grep hit in `Simulator.luau` is a comment). Recorded as intentional in REQUIREMENTS.md status cells and in STATE.md's notes block |
| `src/shared/Config/CardPool.luau` | the six shipped G1 values | ✓ VERIFIED | `k=3, j=1, Wild, valve ON, 8.0s, uniform-random-from-hand`; diffed against the committed report by `spec_lock` (except the mode — see F5) |
| `scripts/sim/Simulator.luau` | two modes, six-outcome taxonomy, five bars, five mechanism checks | ✓ VERIFIED | drives the real `Engine.apply`; `evaluateBars` unchanged and recorded per cell as `lockedVerdict` |
| `scripts/sim/sweep.luau` | staged sweep CLI + report + data | ✓ VERIFIED | A8 bars applied as named overrides; `mechanismPass` ANDed into the exit code |
| `02-G1-REPORT.md` + `02-sweep-data.json` | the committed verdict and its data | ✓ VERIFIED | every headline number re-derived above; 37 failing seeds carried and replayable |
| `tests/harness/Livelock.luau` | deterministic valve fixture | ✓ VERIFIED | hand-verified 16-action completion-free cycle, legality-checked by `Invariants.check` at build, driven through the real `Engine.apply` by consumers |
| `02-14-SUMMARY.md` | execution record for the plan that produced the gate evidence | ✗ MISSING | see F1 |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Engine.apply` | `Valve.afterAction` / `afterProgress` | inline, inside the same synchronous apply | ✓ WIRED | exactly one entry point per successful apply, none on a rejection; `fuzz.spec` asserts `valve.observations == acceptedActions` exactly (170,332 == 170,332) and 0 observations on 24,235 rejections |
| `Valve` forced card | `Ring.pass` | card id only, successor resolved at execution time | ✓ WIRED | `ValveForcedPass` is followed by a real `Passed` for the same card and target, asserted per action in the fuzz |
| `Engine` completion | `Ring.removeSeat` | same apply, retirement first | ✓ WIRED | ordering is load-bearing (retire before route) and asserted |
| `CardPool` | gated sweep cells | `tests/sim/subset.spec.luau` equality on the cells case 1 already ran | ✓ WIRED | hardcoding `k` back into the construction path fails with `gated k is not CardPool.EXTRA_RANKS` |
| `CardPool` | `02-G1-REPORT.md` Verdict | `spec_lock` slices the Verdict section and diffs k, j, deadline, marginal | ⚠️ PARTIAL | the mode half of this diff cannot fail (F5) |
| `SeatOrder` | match lifecycle | — | ✗ NOT WIRED (by design, Phase 6) | |
| `src/server/engine/*` | `src/shared/*` | — | ✓ CORRECTLY ABSENT | guard R6 forbids the cross-mount require; `CardPool` values arrive as an `EngineConfig` value |
| gameplay modules | cosmetics/shop | — | ✓ CORRECTLY ABSENT | `check-guards` FOUND-05 green |

### Data-Flow Trace (Level 4)

| Artefact | Data | Source | Produces real data | Status |
|---|---|---|---|---|
| `02-G1-REPORT.md` tables | every number in sections 1, 3, 4, 4b, 6, 7 | rendered by `scripts/sim/sweep.luau` from the in-memory cell list, same objects serialised to `02-sweep-data.json` | yes — re-derived independently above, all agree | ✓ FLOWING |
| `CardPool.luau` | six constants | the sweep's `selection` block | yes — `selection.k=3, j=1, autoPassSeconds=8, marginal=false` | ✓ FLOWING |
| `subset.spec` gated cells | `k`, `j`, deadline, valve position | `require CardPool` | yes | ✓ FLOWING |
| `fuzz.spec` coverage report | 12 counters | accumulated from real `Engine.apply` results | yes — printed non-zero and floored | ✓ FLOWING |
| `MechanismEvidence` booleans | `deterministicFiringProven`, `deterministicTwinProven` | OBSERVED from the `Livelock` fixture driven through `Engine.apply`, never literals | yes — `subset.spec` asserts each equals the observation it came from | ✓ FLOWING |

### Behavioural Spot-Checks

| Behaviour | Command | Result | Status |
|---|---|---|---|
| Full suite green with zero todos (the phase exit condition) | `lune run tests/run.luau` | `509 passed, 0 failed, 0 todo in 24.36s` | ✓ PASS |
| 14-step gate chain | `lune run scripts/verify.luau` | `all 14 automated steps passed in 26.2s` | ✓ PASS |
| Pure-zone guards (rules 2, 5, 6) | `lune run scripts/ci/check-guards.luau` | `ok (85 files, 227 requires, 20 guarded roots)`, exit 0 | ✓ PASS |
| Fuzz load really runs | `--filter engine/fuzz` | 194,567 actions, 500 rounds, all 8 seat counts, all 7 reject codes | ✓ PASS |
| Headline numbers derivable from the artefact alone | Python re-derivation of `02-sweep-data.json` | 13 of 13 claims agree | ✓ PASS |
| **37 residual stalls reproduce from the committed seeds** | replayed 15 of 37 through `Simulator.runRound` with the shipped config | all 15 → `CapReached` / `time-cap`, identical classification | ✓ PASS (see F4 for what the replay also showed) |

### Requirements Coverage

| Req | Verdict | Evidence |
|---|---|---|
| **CARD-01** — hold 4, draw only at exactly 4 | **COMPLETE** | `HandNotFour` asserts its own code; `HandNotFour` before `InboxEmpty` mutation-proven in both directions; hand size is always 4 or 5 by the `hand-size` invariant, checked 194,567 times; there is no `locked` flag anywhere that could disagree with the hand it describes |
| **CARD-03** — passed card arrives in the next seat's left pile, server resolves which seat at execution time | **COMPLETE** | structural: no `target` parameter and no `to` field on the intent. `ring.spec` (8 cases) + `apply.spec::a departed seat rejects its own intents while a pass TARGETING it lands downstream` |
| **CARD-04** — last seat's passes land beneath the dealer's deck, deck never runs dry | **COMPLETE** | no last-seat branch exists; the dealer's inbox *is* the deck; `circulation = 4k + j` proved invariant under draw, pass and completion and derived two independent ways after every fuzz action. `pool.spec::circulation is 4k + j exactly`, `ring.spec::the last seat's pass lands beneath the dealer's deck` |
| **CARD-05** — dealer is the previous first finder, falling through to the highest-placed seated finisher; round 1 random | **COMPLETE** (integration deferred to Phase 6) | 28-case corpus incl. first-finder-is-hider, zero finishers, departed finisher, mass leave, seeded round 1, loud error on a missing rng. Zero production callers — judged below |
| **CARD-06** — seat order is finishers in find order, then the empty-handed seeker, then everyone else | **COMPLETE** (integration deferred to Phase 6) | same four-bucket ranking; bucket 2 is a LIST with a key, so "three empty-handed seekers" is not a special case; `userId` ascending total tiebreak |
| **CARD-07** — four of a kind detected on draw, immediately removes the player | **COMPLETE** | one completion check in the engine, draw path only, with an explicit prohibition on adding one to the pass path (a pass can only leave a subset of a hand that already had none). Removal happens inside the same apply, so a completed seat is never briefly a legal pass target. 274 completions observed in the fuzz, all three shapes (4 / 3+1j / 2+2j = 152 / 93 / 29) |
| **CARD-08** — removed seat's cards route to the successor and are never destroyed | **COMPLETE** | one generic `removeSeat` for completion, disconnect and AFK; cause forks nothing but the churn counter; locked dump order asserted as an exact array; `terminal` bucket for the sole-seat case; destroy mutation proves the tripwire fires (measured effect: 77% of churned rounds) |
| **CARD-09** — no opening hand already complete or completable by a held wild | **COMPLETE** | holds for every round the engine can CONSTRUCT, because `Engine.newRound` is the only way to build a state with cards. Both bad shapes checked as separate conditions (research warned a naturals-only predicate ships the exact bug); rejection counter asserted `> 0` over the corpus, so a vacuous predicate is distinguishable from a correct one; 64 attempts is a loud error, never a silent repair. Sweep-wide `dealAttemptMean` 1.01, max 3 |
| **CARD-10** — jokers act as wilds, naturals spent before jokers | **COMPLETE** | research 3.3's choice table asserted row by row; naturals-first shown optimal on both axes (cards stranded and jokers spent); retired set independent of hand array order and deterministic across calls; completing rank proved unique exhaustively at j ≤ 2 and the tripwire proved able to fire at j = 3 |
| **CARD-11** — headless pacing simulator proves the table stays solvable at every player count 3–10 and selects the pool and joker count | **COMPLETE, with the scope stated** | **Pool selected** (k=3, j=1, 8.0s, valve ON) and confirmed at 10,000 rounds/cell over 32 cells. **"Stays solvable" is met in the structural sense and only that sense:** `Invariants.satisfiable` is evaluated on every action in both simulator modes and reported **0 `Unsatisfiable` outcomes in all 1,501,000 simulated rounds**. That is a real theorem-grade result and it does not depend on the bot model. It is *not* the stronger reading "every round reaches four of a kind": 37 of 320,000 gated rounds did not. The phase's documents are careful about this distinction; it is restated here because "solvable" invites the stronger reading. The **pacing** half measures the bot until V-35 and A4 close |
| **CARD-12** — jokers revert to blockers that can never complete a set, if solvability cannot be proven | **COMPLETE, in a stronger form than written** | the conditional never triggered: Wild ships. Blocker is nevertheless a **live flag** — 16 Blocker gated cells, `verdict=true` in all 16, every bar cleared at every N — selected by an `EngineConfig` value, never a module constant, so both variants run in the same process. `apply.spec::the IDENTICAL scripted sequence completes in Wild and does not in Blocker` and `spec_lock` case (b) prove the unshipped branch is live code rather than an untested rewrite. One gap: nothing pins the shipped value (F5) |

**Orphaned requirements:** none. REQUIREMENTS.md maps exactly CARD-01, CARD-03..CARD-12 to Phase 2 and all eleven are claimed by plans in the phase.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|---|---|---|---|
| — | no TODO / FIXME / placeholder / stub in `src/server/engine/`, `src/shared/Config/CardPool.luau` or `scripts/sim/` | — | none |
| `tests/engine/spec_lock.spec.luau` | runner todo count is 0 and the registering string is absent even from comments, so `grep -rn` over `tests/` stays a usable guard | ℹ️ Info | the phase exit condition is met and self-guarding |
| `src/server/engine/Invariants.luau` | `liveness` (violation 3) is a deliberately unreachable subsumed tripwire | ℹ️ Info | disclosed in the file, and the order is locked by a test asserting a no-legal-action state reports `hand-size` instead — an unreachable check that is documented and ordered is not the defect class |

---

## Findings — what the summaries, the report or the documents claim that the code or data does not support

Ordered by how much they change a future reader's belief. **None of these blocks the phase.**

### F1 — `02-14-SUMMARY.md` does not exist, and it is the plan that produced the gate's entire evidence base

Every plan from 02-01 to 02-13 has a SUMMARY. Plan 02-14 — "run the search, mechanism, confirm and
triage stages; commit the G1 report and the sweep data" — is ticked `[x]` in ROADMAP.md and has four
commits (`5a121d4`, `88e4046`, `c4a6792`, `0d76087`, plus `92202cf`), but no SUMMARY and no "complete
the plan" commit. What is therefore recorded only in commit messages:

- The **first** full sweep selected and confirmed **k = 6, j = 1** at 10,000 rounds/cell (`88e4046`).
- The valve-rate bar was then changed from 0.07 to 0.20 (`c4a6792`) and the sweep re-run (`0d76087`),
  which is how the shipped pool became k = 3 *and* the confirmed one.
- The k = 6 run's data is not committed; `02-sweep-data.json` is the k = 3 re-run.

`CardPool.luau` and STATE.md both record the substance honestly. But the per-plan execution record
for the most load-bearing plan in the phase is missing, and the k=6 → k=3 history is one `git log`
away from being lost.

### F2 — the G1 report's provenance for the valve-rate bar is softer than the code that sets it

`02-G1-REPORT.md` section 2, bar 5: *"amendment A8 resolution 1, re-derived from the measured curve."*

`scripts/sim/sweep.luau`, the file that sets it:

> `VALVE_RATE_MAX_SWEEP` was 0.07 … which selected k=6. **IT IS NOW 0.20, AND THE REASON IS AN OWNER
> DECISION, NOT A MEASUREMENT.** … 0.20 is the candidate bar whose full selection rule (including the
> half-the-bar margin) yields k=3, j=1 at an 8.0s deadline with marginal = false. The bar is
> therefore a **REGRESSION GUARD** around a chosen operating point, not a discovery mechanism.

Both statements are in the repository; only one is in the artefact a future phase will cite. The
report's own section 4b *is* honest ("the firing-rate bar is a judgement on a smooth monotone
curve") and prints the full sensitivity ladder, and `CardPool.luau` is honest ("the bar CHOOSES
rather than discovers"). So this is an internal inconsistency in the report's attribution, not a
concealment — but it matters, because it means **one of G1's five bars was set after seeing the
answer, to admit the chosen pool.** The gate is still real: the other four bars (stalls,
cleared-fraction, pacing, occupancy) are independent of it and k = 3 clears all of them, and the
valve-rate bar continues to reject the k=1/k=2 neighbourhood. The honest sentence is "G1 passes on
four discovered bars plus one regression guard set at an owner-chosen operating point."

### F3 — the Triage section's conclusion rests on a check that cannot fire in the cells that produced the residual

The report concludes:

> `capArtifactCandidates` is **empty in all 1,132 cells of this run**, across 1,501,000 simulated
> rounds … So the residual is **not** a cap artefact.

`capArtifactCandidates` and `hitActionCap` track the **100,000-action** `SOLVABILITY_ACTION_CAP`. The
gated cells are Pacing cells, and a Pacing round terminates on the **300-second** clock: the
heaviest gated cell averages **379 actions per round**. A Pacing round cannot reach 100,000 actions
within 300 simulated seconds at a ~0.45s median reaction time — so `hitActionCap == false` was
structurally guaranteed for the 1,113 Pacing cells, not measured. The sentence "absent by measurement
rather than by omission" is therefore true of the 19 Solvability cells and near-tautological for the
rest.

The *conclusion* is still correct and conservative: the binding cap is 300s, which is the shipped
game's own round cap (`Round.ROUND_CAP_SECONDS`), so raising it is not an option and a 300s round is
a product stall either way. But the question the triage stage was built to answer — **were those 37
rounds cycling, or merely slow?** — is not answered by this run, and cannot be: `detectCycles` is
disabled for every valve-ON cell by design (correctly: with the valve on a repeated hash is not proof
of non-termination, and the detector would always win the race against the arm gate). This is the
same pattern the phase has been hunting all along; it is the twenty-second instance, and it sits in
the gate report rather than in a plan.

### F4 — what the residual actually is, from replaying it: in a fifth of the sample the valve armed, was not blind, and never fired

I replayed 15 of the 37 committed failing seeds through `Simulator.runRound` with the shipped config.
All 15 reproduce exactly (`CapReached` / `time-cap`). What the replay also shows:

| | observed across the 15 |
|---|---|
| reproduced exactly from the committed seed | 15 / 15 |
| round reached a **first completion** before sticking | **15 / 15**, at 6.8s – 24.4s |
| actions before the 300s cap | 2,431 – 4,429, against a healthy cell mean of ~380 |
| `valveSeenResets` (valve blind) | **0 in all 15** |
| valve firings | 0 – 4; **zero firings in 3 of 15**, all with `valveArmed = true` |

Two things follow that no document in the phase states:

1. **The residual is not "dead tables".** Every sampled residual round produced spoons and then
   stopped progressing for the remaining ~250–280 seconds — a non-progressing tail 6–11× a healthy
   round, which matches the report's own characterisation of a *valve-off* stall. In the shipped game
   that is a round in which most players never get four of a kind, at ~1 in 1,400 rounds at N = 9–10.
2. **The valve has a detection limit that is never written down.** `Valve.afterAction` fires only on
   an **exact** whole-table state repeat (`Invariants.hash`: head, per-seat liveness, sorted hand,
   FIFO inbox). In 3 of 15 sampled residual rounds the valve armed, the window never overflowed
   (`seenResets = 0`, so it was not blind in the sense A7/the report discuss), and it still never
   fired — the pathological trajectory simply never repeated a state exactly. The documents discuss
   firing rate and blindness-by-overflow at length; a trajectory that is stuck without exactly
   repeating is a third category and is unaddressed. **Phase 4 consequence:** a stuck round can
   present with *no* `ValveForcedPass` at all, so a "this round is going nowhere" affordance cannot
   be keyed off valve events.

This strengthens rather than weakens the narrow claim the phase makes. It is evidence *for* scoping
the claim to the selected configuration, and against anyone later upgrading it.

### F5 — nothing in the suite pins the shipped `JOKER_MODE`, and the one check that looks like it does cannot fail

The config-vs-report drift check (`spec_lock` case (d)) asserts k, j, the deadline and
`Marginal: **false**` against the report's Verdict section — all four genuinely fail on mutation. The
**mode** assertion is `string.find(verdict, CardPool.JOKER_MODE, 1, true) ~= nil`, and the Verdict
section reads *"Joker mode is a FLAG, not a selection: **Wild and Blocker** both clear every bar at
every N"*. It contains both literals, so the assertion passes for either value. The only other
assertions on the field (`spec_lock` case (a), `subset.spec` line 635) are `== "Wild" or ==
"Blocker"`.

So flipping `CardPool.JOKER_MODE` to `"Blocker"` passes all 509 cases, `verify.luau` 14/14, and the
drift check whose stated purpose is that *"the config must not drift from its evidence"*. Both modes
clear every bar, so this is a design-drift hole rather than a correctness one — but PROJECT.md's Key
Decisions record jokers-as-wilds as a design property, and this is the single G1 value no test can
defend. One line fixes it: `t.equal(CardPool.JOKER_MODE, "Wild", "PROJECT.md records jokers as
wilds; Blocker is the flag's other live position, not the default")`.

### F6 — `02-VALIDATION.md` still says "six reject codes"; the implementation and the fuzz correctly assert seven

The falsifiability table's Fuzz-load row reads *"a minimum observed count for every event kind and
all six reject codes"*. `Types.Reject` has seven and `fuzz.spec` asserts all seven with ≥ 10
observations each (`fuzz.spec` header note 4 explicitly says "SEVEN REJECT CODES, NOT SIX. Research
11.3 … undercounts"). Stale wording in the validation contract only; the code is right and stricter.

### F7 — the 100k fuzz reports its seat-count coverage but does not gate it

`fuzz.spec`'s header claims the run covers "every seat count from 2 to 9". The coverage block floors
the action count, every event kind, every removal cause, all four ring milestones, all seven reject
codes and the valve observation depth — but `seatCountsSeen` is only **printed**. Under the pinned
seed all eight counts appear (63–71 rounds each, confirmed by running it), so the claim is true
today; it is simply the one coverage claim in that file that cannot fail. Given the file's own
standard ("a suite that cannot prove it ran is theatre"), it is inconsistent. One `needs()` call.

### F8 — the conservation fuzz never runs the shipped pool

`fuzz.spec`'s generator draws `k = rng:nextInt(1, 2)`. The shipped pool is **k = 3**. Conservation is
pool-independent by construction (circulation is `4k + j` for any k), so the severity is genuinely
low — but "194,567 actions, no card ever lost" is not a statement about the configuration that
ships. Widening the generator to `nextInt(1, 3)` or 4 costs nothing.

### F9 — CI regresses only N = 3, 6, 10; all 37 residual stalls occurred at N = 7–10

`subset.spec` runs RUNG 2: `RUNG_PLAYER_COUNTS = {3, 6, 10}`, 12 gated cells. N = 4, 5, 7, 8, 9 are
covered only by the 24-minute manual sweep. Every stalled round in the gated run occurred at N ≥ 7,
and the worst cell (0.070%) is N = 9. The choice is documented and well argued (the subset's job is
regression, and `stalls` / `cleared-fraction` / `valve-rate` are explicitly `CI_UNRESOLVABLE` at 500
rounds, with `CI_RESIDUAL_STALL_MAX = 0.006` substituted). Carry it as a known coverage edge: an
engine change that regresses specifically at N = 9 would leave CI green.

### F10 — "valveFiringRate(ON) equals stallRate(OFF) to three decimals" does not hold against the final data

Amendment A8 claims this at every pool measured, and STATE.md repeats it as *"matching the firing
rate, so every firing is a real rescue."* Against the committed confirm cells:

| N=10 cell | firing rate (valve ON) | stall rate (valve OFF) |
|---|---|---|
| Wild, no churn | 5.86% | 6.21% |
| Wild, churn | 3.59% | 3.58% |
| Blocker, no churn | 8.24% | 8.31% |
| Blocker, churn | **4.77%** | **5.33%** |

Approximate agreement holds and the load-bearing conclusion (the valve is doing real work, ~500× the
residual) is fully supported. "To three decimals" is not true of this data, and "every firing is a
real rescue" is an inference from aggregate-rate equality, not a measurement — the two trajectories
diverge the moment the valve acts, so a per-firing claim is not available. `CardPool.luau`'s own
wording ("3.58% to 8.31% … roughly 500x the valve-on residual") is the accurate version.

*Also, a correction to the brief I was given:* the valve-off twins stall **3.58–8.31%** at N = 10,
not 6.2–8.3%; the churn variants are the low end.

### F11 — the two Manual-Only Verifications are not in the project's human-gate index

`02-VALIDATION.md` declares V-35 and A4 as Manual-Only. `NEEDS_HUMAN.md` states that
`MANUAL-CHECKS.md` is authoritative, and `grep -n "V-35\|A4\|reaction\|CARD-11" MANUAL-CHECKS.md`
returns nothing. Both are carried in STATE.md's Blockers section and in the G1 report's section 8, so
they are not lost — but a Phase 4/6 executor consulting the human-gate index will not see
"calibrate the bot reaction-time model against live sessions". Two table rows.

### F12 — the report's section 5 table does not support a comparison between auto-pass deadlines

"Stall rate versus auto-pass timeout" shows worst stall `1.0000` and worst firing rate `1.0000` at
every deadline including `inf`, because the aggregate spans the k = 0 dead pools. Only the
`total auto-passes` column (38,516 / 58 / 2 / 0 / 0) discriminates. The table is correctly labelled
"Margin evidence, not what the gate rests on", so it misleads nobody who reads the label, and the
auto-pass column is the half that carries the argument. Worth a per-pool slice next time.

---

## The three judgement calls I was asked for

### 1. Criterion 5 says "zero stalls". Is keeping it verbatim honest and sufficient, or does the phase claim a gate it did not meet?

**Honest and sufficient. It does not overreach.** I went looking for the overreach and could not find
it. Specifically:

- The criterion is kept **verbatim** in ROADMAP.md with the departure stated immediately beneath it,
  in the same section, including the sentence *"Criterion 5's literal 'zero stalls' bar was not met
  by any pool this engine has."*
- The measured residual is printed in **every** place the verdict appears — ROADMAP, STATE,
  REQUIREMENTS, PROJECT, `CardPool.luau`, the report — as a number (37 / 320,000), never rounded to
  zero and never softened to "effectively zero".
- The replaced bar is **still evaluated**. `Simulator.evaluateBars` was not touched; its zero-stall
  verdict rides on every cell as `lockedVerdict` / `lockedFailures`, and it is **false in 20 of the 32
  gated cells**. The unmet bar is readable straight out of the artefact, which is the opposite of a
  quietly relaxed gate.
- The amendment is dated, owner-attributed, and carries its own derivation (0.5% is 5× the measured
  valve-on residual and 20× below what a valve regression produces).
- 02-12's acceptance criteria include a grep that must **FAIL** for `guarantees zero|theorem about
  the engine` across all four planning documents. It does fail. The stronger claim was actively
  hunted, not merely avoided.

Two wording tightenings I would ask for, neither of which changes the verdict:

- ROADMAP's bold headline is **"Gate G1: PASSED"** sitting above the paragraph that says the literal
  bar was not met. A skimmer reads the bold line. **"Gate G1: PASSED against an amended bar (see
  below)"** costs five words and removes the only reading of these documents that could mislead.
- F2: the report should attribute the valve-rate bar the way the code attributes it.

### 2. The anti-livelock valve: sound? genuinely load-bearing? honestly bounded?

**Sound.** It is placed in the pure zone with a real argument (it consults no policy, assumes nothing
about how anyone plays, and chooses uniformly at random — it is a liveness mechanism of the same kind
as the hand-size rule, and the engine is the only place that can promise it runs). It imports no bot
model, takes no clock, yields nothing, returns a card id rather than performing the pass, and names
no target — so CLAUDE.md rules 6 and 7 survive it. It is wired *inside* `apply` where no caller can
forget it, with exactly one entry point per successful apply and none on a rejection, and that
depth is asserted per-action over 194,567 actions (`observations == acceptedActions`, plus 0
observations across 24,235 rejections). Its dependency on `Invariants.hash` excluding `counters` /
`valve` / `rankOf` is correctly identified as load-bearing — one monotonic field in the hash would
make the whole mechanism silently vacuous — and that exclusion is asserted in `invariants.spec`
rather than assumed here.

**Genuinely load-bearing, at the shipped pool and the shipped round count.** This is the part I
checked hardest, because "load-bearing" is the claim that carries the gate:

- Valve-disabled twins at **exactly the shipped pool, mode, churn setting and 10,000 rounds** stall
  at **3.58% – 8.31%**, against a 0.0116% valve-on aggregate: a ~500× effect, measured on matched
  cells rather than inferred.
- `evaluateMechanisms` ANDs a `valve-not-load-bearing` check into the verdict, and the "at least one
  matched twin" clause exists specifically because a `forall` over an empty twin set is vacuously
  true — i.e. the vacuity hole was found and closed, with a mutation case that hands it the empty set
  and expects it to fire.
- The deterministic half is a hand-verified 16-action completion-free cycle driven through the **real**
  `Engine.apply`, with its legality checked by `Invariants.check` at build, escaping at action 113 and
  provably never escaping with the valve disabled.

**Honestly bounded, with one gap.** A7's "zero-stall becomes a theorem about the engine" was retracted
by A7-CORRECTION the same day, and — importantly — the retraction *propagated into the code*:
`Valve.luau`, `Engine.luau`, `Simulator.luau` and `CardPool.luau` each state the narrow claim in their
headers, with explicit instructions not to restate the strong one, and a must-FAIL grep enforces it
across the planning documents. A8 then made the valve *more* load-bearing than A7 claimed (one round
in ten at a full roster, not one in four hundred) and traced the factor-of-40 discrepancy to a real
cause (amendment A3's seated-seeker off-by-one) rather than waving at it. That is the right handling.
The gap is **F4**: the valve detects only *exact* whole-table state repetition, and in 3 of the 15
residual rounds I replayed it armed, never went blind, and never fired, because the stuck trajectory
never exactly repeated. That limit is nowhere in A7, A7-CORRECTION, A8, the report or the module
header, and it is the honest mechanism of the residual.

### 3. CARD-05 and CARD-06 — Complete, or Partial?

**Complete is right, and the FOUND-08 precedent does not transfer.** The two cases differ in the kind
of thing the requirement asserts:

- **FOUND-08** ("the server refuses an 11th player" / `PlayerGate.canStart`) is a claim about
  *server behaviour*. It cannot be true without a caller, and `Admission.luau` forbids anything else
  deciding a match may start — so with zero call sites the invariant is literally unenforceable.
  Partial was correct there.
- **CARD-05/06** are claims about *what the dealer and the seat order are* — a computation. It is
  fully specified, implemented once as a single total order (so a second dealer rule cannot appear
  later and disagree), read only through `dealerOf` (so nobody writes `order[1]` inline), and locked
  by a 28-case corpus that covers all five previously-unspecified cases plus malformed-input
  robustness. Nothing about "the dealer is the previous round's first finder" becomes more true when
  a caller exists.

The executor's handling is also the right shape: the status cell keeps the still-true caveat ("first
consumer is Phase 6's match lifecycle") instead of deleting the information to tidy a table, and the
same fact is recorded **independently** in STATE.md's "Notes that would otherwise be lost" block —
which is where a Phase 6 planner will actually look, and which explicitly warns a cleanup pass not to
delete the module as dead code. Preserving the caveat in two places is strictly better than a
`Partial` cell that a reader has to interpret.

One strengthening, as a Phase 6 note rather than a status change: the corpus inputs are **hand-built**
`SeatOrderInput` records. The integration risk that remains is not the ranking but the *construction*
of that input from live player records — hider identity, roster filtering of departed finishers,
previous-round lists. Phase 6's plan should re-verify CARD-05/06 against real lifecycle data, and say
so.

---

## Gaps Summary

**No gap blocks Phase 2 from closing.** The goal is achieved: the engine exists, is pure and
synchronous, is fuzz-proven well past the stated bar, and the joker question is decided with both
variants live and tested. Gate G1 is genuinely passed in the form the documents claim — I re-derived
every headline number from the data artefact and replayed the residual from the committed seeds, and
both exercises confirm the record rather than contradicting it.

Ranked by what I would fix, and when:

**Before the phase is archived (records):**
- **F1** — write `02-14-SUMMARY.md`, or record somewhere durable that the first sweep selected and
  confirmed k = 6, that the valve-rate bar was then moved from 0.07 to 0.20 as an owner choice of
  operating point, and that the sweep was re-run so the shipped pool is the confirmed one. Today that
  history exists only in `git log`.
- **F2** — correct `02-G1-REPORT.md` section 2's provenance for bar 5 to match what
  `scripts/sim/sweep.luau` says about itself.
- ROADMAP's "Gate G1: PASSED" headline → "PASSED against an amended bar (see below)".

**Cheap now, annoying later (one-liners):**
- **F5** — pin `CardPool.JOKER_MODE` to `"Wild"`.
- **F7** — gate the fuzz's seat-count coverage instead of printing it.
- **F8** — widen the fuzz's `k` to include the shipped 3.
- **F6** — "six reject codes" → seven in `02-VALIDATION.md`.
- **F11** — add V-35 and A4 to `MANUAL-CHECKS.md`.

**Carry into Phase 4 as inherited knowledge (new, from F3/F4):**
- A stuck round can present with **no `ValveForcedPass` event at all**. The valve fires only on an
  exact whole-table state repeat; a pathological trajectory that never exactly repeats is invisible to
  it even while armed and un-blinded. A "this round is going nowhere" affordance cannot be keyed off
  valve events, and the ~1-in-1,400 residual at N = 9–10 is a round in which most players never get
  four of a kind — not a dead table, a stalled endgame after 1–3 spoons.
- The triage question "cycling or merely slow?" is formally open and this sweep cannot close it,
  because cycle detection is disabled for every valve-ON cell by design. The conservative conclusion
  the phase drew is the right one; the reasoning offered for it leans on a check that could not have
  come out differently.

**Known coverage edge (F9):** CI regresses N = 3, 6, 10 only, while every observed residual stall was
at N ≥ 7. The full sweep that covers the rest is a 24-minute manual run.

**Carried debt, unchanged and correctly scoped:** V-35 and A4 remain open until a real playtest.
G1's solvability half is a genuine theorem — `Invariants.satisfiable` is a multiset property, it is
evaluated on every action in both simulator modes, and it reported **0 `Unsatisfiable` outcomes across
1,501,000 simulated rounds**. G1's pacing half measures the bot, not the game. The scope note the
phase carries is accurate and should not be softened.

---

_Verified: 2026-11-04_
_Verifier: Claude (gsd-verifier)_
