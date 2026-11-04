---
phase: 2
slug: card-engine-and-pacing-simulator
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-11-03
closed: 2026-11-04
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `02-RESEARCH.md` § Validation Architecture. Every row's falsifiability proof is
> mandatory, not advisory: Phase 1 verification found two checks that could not fail at all.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bespoke headless runner — `tests/run.luau` + `tests/harness/Test.luau` (FOUND-03). No Jest-Lua. |
| **Config file** | None; discovery is `tests/**/*.spec.luau`, `fixtures/` excluded unless `--root` points inside |
| **Quick run command** | `PATH=/root/.rokit/bin:$PATH lune run tests/run.luau -- --filter engine` |
| **Full suite command** | `PATH=/root/.rokit/bin:$PATH lune run tests/run.luau` |
| **Full gate chain** | `lune run scripts/verify.luau` — 14 steps, `run:` strings byte-identical to `ci.yml` |
| **Estimated runtime** | *estimated at phase start:* ~16s full suite, sub-second for `--filter engine`, +2–6s for the simulator subset. *Measured at phase end:* 25.18s full suite, 2.91s for `--filter engine`, 5.74–5.97s for `--filter sim/subset` |
| **Baseline at phase start** | 333 passed, 0 failed, **3 todo**, 15.94s |
| **Measured at phase end** | **509 passed, 0 failed, 0 todo, 25.18s** (`scripts/verify.luau` 14/14 in 27.2s). This is the baseline Phase 3 inherits; the 15.94s figure above is Phase 1's and is kept only so the delta is readable. The growth is the simulator: `--filter sim/subset` 5.83s and `--filter sim/sweep` 2.19s are 8.0s of it, and 02-09-SUMMARY records that CONTEXT's locked "~20s should stay true" was already unreachable before this phase. |

**PATH gotcha — applies to every task.** Rokit shims are not on the default PATH. Running
`lune run tests/run.luau` without `PATH=/root/.rokit/bin:$PATH` reports **67 spurious failures**.
Every plan task's automated verify must set PATH explicitly.

**Phase exit condition: the runner's todo count reaches 0. MET.** `tests/engine/spec_lock.spec.luau`
held three todo placeholders (CARD-09, CARD-10, CARD-12) that had to become real tests. A green run
with todos remaining is not a finished phase, and the pass count alone will not reveal it — so the
todo field was read explicitly: plan 02-11 converted all three and the runner now prints
**`509 passed, 0 failed, 0 todo`**. No spec anywhere registers a todo.

---

## Sampling Rate

- **After every task commit:** `lune run tests/run.luau -- --filter engine` (sub-second)
- **After every plan wave:** full suite — **and check the todo count, not just the pass count**
- **Before phase close:** `lune run scripts/verify.luau` green, todo count 0, sweep report regenerated
- **Max feedback latency:** ~16 seconds as estimated; **25.18s measured** for the full suite at phase end, 2.91s for the per-task `--filter engine` loop. See the sign-off below: the per-task loop is inside the line, the wave-level full suite is not

---

## Phase Requirements → Test Map

| Req | Behaviour | Type | Automated command | Cases | File |
|-----|-----------|------|-------------------|-------|------|
| CARD-01 | draw only at `hand == 4`; `HandNotFour` asserts its own code; hand size always 4 or 5 | unit + fuzz | `--filter engine/hand` | 10 | ✅ `tests/engine/hand.spec.luau` |
| CARD-03 | passed card lands in the `next` LIVE seat's inbox tail, resolved at apply time, including when the target was removed between intent and apply | unit | `--filter engine/ring` | 8 | ✅ `tests/engine/ring.spec.luau` |
| CARD-04 | last seat's pass appends beneath the dealer's deck; FIFO preserved; circulation never reaches 0 | unit + fuzz | `--filter engine/ring` | 8 | ✅ `tests/engine/ring.spec.luau` |
| CARD-05 | dealer = `seatOrder[1]`; first-finder-is-hider; no seated finisher; zero finishers; round-1 seeded random | unit corpus | `--filter engine/seatorder` | 28 | ✅ `tests/engine/seatorder.spec.luau` |
| CARD-06 | finishers → non-finishers (0, 1, ≥2) → previous hider → joiners → `userId` tiebreak | unit corpus | `--filter engine/seatorder` | 28 | ✅ `tests/engine/seatorder.spec.luau` |
| CARD-07 | completion detected **only** on draw; completing rank unique; seat removed in the same apply | unit + fuzz | `--filter engine/apply` and `--filter engine/hand` | 28 / 10 | ✅ `tests/engine/apply.spec.luau`, `tests/engine/hand.spec.luau` |
| CARD-08 | hand + inbox → successor in a locked order; ring→2, ring→1, ring emptied, dealer removed, mid-pass departure | unit + fuzz + **mutation** | `--filter engine/removal` | 10 | ✅ `tests/engine/removal.spec.luau` |
| CARD-09 | no opening hand complete or wild-completable (4, 3+1, 2+2); rejection counter **> 0** over the corpus | unit + corpus + **mutation** | `--filter engine/pool`; the locked decision in `--filter engine/spec_lock` | 12 / 3 | ✅ `tests/engine/pool.spec.luau`, `tests/engine/spec_lock.spec.luau` (replaced a todo) |
| CARD-10 | naturals spent before jokers; 5th-card identity; `j <= 2` asserted so all-joker is unreachable | unit | `--filter engine/hand`; the locked decision in `--filter engine/spec_lock` | 10 / 3 | ✅ `tests/engine/hand.spec.luau`, `tests/engine/spec_lock.spec.luau` (replaced a todo) |
| CARD-11 | simulator: zero stalls + pacing bars + **occupancy floor** at N=3..10; a failing trial prints its seed | integration | `--filter sim/subset` | 16 | ✅ `tests/sim/subset.spec.luau` |
| CARD-11 | the anti-livelock valve (amendment A7): it arms, it forces exactly one pass, and the round leaves the cycle | unit + fixture + **mutation** | `--filter engine/valve` | 11 | ✅ `tests/engine/valve.spec.luau`, `tests/harness/Livelock.luau` |
| CARD-12 | blocker mode runs in the same process via `EngineConfig`; chosen pool passes in **both** modes | unit + integration | `--filter sim/subset`; the locked decision in `--filter engine/spec_lock` | 16 / 3 | ✅ `tests/sim/subset.spec.luau`, `tests/engine/spec_lock.spec.luau` (replaced a todo) |
| Gate G1 | the shipped pool, joker count, mode, valve flag and auto-pass constraints are the ones the gate ran, and agree with the committed report | unit + integration | `--filter engine/spec_lock` and `--filter sim/subset` | 3 / 16 | ✅ `src/shared/Config/CardPool.luau` + both specs above |
| — | the full sweep CLI's staging, bars and selection rule | integration | `--filter sim/sweep` | 12 | ✅ `tests/sim/sweep.spec.luau` |
| Rules 5/6 | pure zones reject `coroutine.*` and `os.*` | guard + **mutation fixture** | `lune run scripts/ci/check-guards.luau`; the fixtures in `--filter purity` | 7 | ✅ `tests/purity/purity.spec.luau` + `tests/purity/fixtures/` |

---

## Every Check's Falsifiability Proof

**House standard.** A check is not trusted until it has been made to fail on purpose. Phase 1
verification found a length check behind a "sha256-pinned" claim and a namespace-confused comparison
that could never fire — both green, both worthless.

| Check | How it is proven capable of failing |
|-------|-------------------------------------|
| Circulation invariant | drop a card on pass; duplicate one on draw — each must fail the assertion |
| Partition identity | swap a card for a copy of another; counters stay consistent, the identity scan must fail |
| Satisfiability predicate | **destroy a removed seat's cards** (violate Rule 8) → `Invariants.satisfiable(state) == false` is asserted **directly**, plus a crafted one-action fixture that fires deterministically. The row previously said the destroy mutation makes `check` report `unsatisfiable`; it does not, because `circulation` precedes satisfiability in the locked violation order and is reported first, so the check is asserted on its own predicate instead of through `check`. Measured effect size is also far wider than the 2.9–5.7% research estimated: **77% of churned rounds** (02-09), because destroying a departing seat's routed bundle removes 4–13 cards from a circulation of 9 |
| CARD-09 deal check | crafted deck forcing a rejection, plus a corpus assertion that the rejection counter > 0. A vacuous predicate is otherwise indistinguishable from a correct one |
| CARD-10 naturals-first | 3 naturals + 2 jokers must retire exactly 3 naturals + 1 joker and keep a joker as the 5th |
| Fuzz load | assert `totalActions >= 100_000` **and** a minimum observed count for every event kind and all seven reject codes — otherwise a generator bug silently disables whole areas while green |
| Rejection codes | each illegal intent asserts its own code **and** that state is unchanged |
| New `coroutine`/`os.` guard | fixtures under `tests/purity/fixtures/` using each construct must make `check-guards` exit 1 with the matching R3 message |
| Simulator gate | run it against a deliberately broken engine (Rule 8 destroy variant) and against the `k=0,j=0` dead pool; both must be reported as failures, not passes. Realised as **seven mutation proofs** in `tests/sim/subset.spec.luau`, five of which cost zero simulated rounds: (1) the broken engine → `stalls, cleared-fraction, valve-rate`, (2) the dead pool → `no-completions`, (3) the valve-off fixture that never escapes, (4) no proof and no twin → all three valve bars including the empty-`forall` case, (5) a non-stalling twin → `valve-not-load-bearing` alone, (6) a quiet probe and a DELETED probe → `autopass-never-fired` then `autopass-probe-missing`, (7) a bad pool on its firing rate alone → `valve-rate` as the only failure at `stallRate = 0`. Plus the positive control: the satisfiable triple returns `true` with an EMPTY failure list, so the bars are not a gate nothing passes |
| The **five** mechanism checks — `valve-never-fired`, `valve-twin-missing`, `valve-not-load-bearing`, `autopass-probe-missing`, `autopass-never-fired` | Each has **a threshold OR a deterministic fixture proof, calibrated to the round count it is applied at**, and each flips the gate's `pass` boolean (`evaluateMechanisms`' result is ANDed into the verdict, never printed). The "or a deterministic fixture proof" half is not padding: CI satisfies **three of the five** through `MechanismEvidence`, whose two booleans are OBSERVED from `tests/harness/Livelock.luau` driven through the real `Engine.apply`, precisely because `VALVE_MIN_FIRINGS = 20` is calibrated for the sweep's 540,000 rounds and is noise at the subset's few thousand. A fact about one trajectory has no round count. Each of the five has a mutation case above reporting it by name |
| Gate G1's shipped configuration | `CardPool.luau` is diffed against the committed `02-G1-REPORT.md` Verdict by `--filter engine/spec_lock` (mutate either side → the case names the mismatch), and the gated cells are diffed against `CardPool` by `--filter sim/subset` (hardcode `k` back into the construction path → `gated k is not CardPool.EXTRA_RANKS`). `ANTI_LIVELOCK_VALVE` and `AUTO_PASS_SELECTION` are asserted in both specs, and flipping either fails both |
| CI subset wiring | `tests/ci/verify.spec.luau` already asserts byte-identical `run:` strings; running the subset inside `tests/run.luau` needs **no new CI step**, avoiding that drift risk entirely |

---

## Wave 0 Requirements

- [x] `tests/engine/pool.spec.luau` — deal, shuffle permutation, CARD-09 rejection + its mutation proof
- [x] `tests/engine/ring.spec.luau` — pass/draw, FIFO, m=2 and m=1 rings, dealer wrap (CARD-03, CARD-04)
- [x] `tests/engine/hand.spec.luau` — completion detection, rank uniqueness, naturals-first (CARD-01, CARD-07, CARD-10)
- [x] `tests/engine/removal.spec.luau` — all three causes, all six edge cases, Rule 8 destroy mutation (CARD-08)
- [x] `tests/engine/seatorder.spec.luau` — table-driven corpus including the five unspecified cases (CARD-05, CARD-06)
- [x] `tests/engine/invariants.spec.luau` — circulation + partition, each mutation-proven
- [x] `tests/engine/fuzz.spec.luau` — 100k-action run with action-count and per-kind coverage assertions
- [x] `tests/sim/subset.spec.luau` — 500 rounds × N=3,6,10 (rung 2, a full cross product), fixed seeds, both joker modes, churn variant
- [x] `scripts/sim/sweep.luau` — full 10k sweep plus a committed report (`02-G1-REPORT.md`, `02-sweep-data.json`)
- [x] `tests/purity/fixtures/engine-yield/`, `tests/purity/fixtures/engine-clock/` — guard mutation fixtures
- [x] **Rewrite** `tests/engine/spec_lock.spec.luau` — three todos become real tests, todo count 0
- [x] No framework install needed. `opts.iterations` **must be set explicitly**; the 200 default is ~2% of the intended load

**Added by the phase and not named in the original list** (amendment A7 created the valve after this
contract was written, and plans 02-07/02-10 split the assembled engine and the sweep CLI out):

- [x] `tests/engine/valve.spec.luau` — the anti-livelock valve: arming, exactly one forced pass, the seen-window cap (CARD-11)
- [x] `tests/harness/Livelock.luau` — the hand-verified, completion-free 16-action cycle, driven through the REAL `Engine.apply`; it is what makes the valve's proof deterministic instead of a statistic
- [x] `tests/engine/apply.spec.luau` — the assembled engine: every rejection code, the locked event order, the Wild/Blocker divergence (CARD-07)
- [x] `tests/sim/sweep.spec.luau` — the sweep CLI's staging, argument handling and selection rule, including a smoke test that fails in 2.4s rather than after 30 minutes

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Whether a bot's reaction-time distribution represents real humans (V-35) | CARD-11 | Unverifiable without real playtests; carried as debt since project init | Calibrate in Phase 4/6 against live sessions |
| Whether humans deviate from pure greed often enough for the pacing half of G1 to mean anything (A4) | CARD-11 | Same class as V-35, and newly surfaced by this phase's research | Measure deviation rate at the first real playtest |

**Scope note.** G1's **solvability** half is a theorem and needs no playtest — it does not depend on
the bot model at all. Its **pacing** half measures the bot, not the game, until the two rows above
are closed. Do not let a green pacing number read as a verified claim about real players.

---

## Validation Sign-Off

Ticked by plan 02-11 against the finished phase. Each box names the evidence rather than asserting
itself, because a checklist that cannot be checked is the same defect as a test that cannot fail.

- [x] All tasks have an `<automated>` verify or a Wave 0 dependency — every plan from 02-01 to 02-14 carries an `<automated>` block; 02-12's checkpoint is the only non-automated step and it is an owner sign-off, not a verification
- [x] Sampling continuity: no 3 consecutive tasks without an automated verify
- [x] Wave 0 covers every MISSING reference above — every ❌ in the map is now a ✅ naming a spec that exists, and the four artefacts the original list did not name are added above
- [x] No watch-mode flags
- [x] Every PATH-dependent command sets `PATH=/root/.rokit/bin:$PATH`
- [x] Feedback latency < 20s **for the per-task sampling loop**: `--filter engine` is 2.83s and every single-spec filter is under 0.5s. **The FULL suite is 25.18s and is over the line** — recorded rather than ticked silently. It was already unreachable before this phase (02-08-SUMMARY), the overshoot is the simulator (`sim/subset` 5.83s + `sim/sweep` 2.19s), and the wave-level loop is the one that pays it. Plan 02-12 takes the overshoot to the owner
- [x] Runner todo count is 0 — `509 passed, 0 failed, 0 todo in 25.18s`; no spec anywhere registers a todo
- [x] `nyquist_compliant: true` set in frontmatter
- [x] Every `--filter` command this document names has been RUN and exited 0 with at least one passing case. `tests/run.luau` exits 1 on a filter that matches nothing, so the five filters this document carried before plan 02-11 — in the CARD-03, CARD-07, CARD-09, CARD-10 and CARD-12 rows, each naming a spec file that was never created — were documented commands that FAILED: each printed `FAIL filter <name> matched no cases: a typo must not look green` and exited 1. They were reconciled in the direction of the REAL filenames (the layout was decided per requirement cluster during planning and is the right one; the map was written before the files existed), and no near-empty spec file was created to match the document. The five retired strings are recorded in `02-11-SUMMARY.md` rather than here, so that a `grep` of this file for a filter that matches nothing stays a usable guard

**Approval:** 2026-11-04 — signed off against the measured end-of-phase state: `509 passed, 0 failed,
**0 todo** in 25.18s`, `scripts/verify.luau` 14/14 in 27.2s, every documented `--filter` run and
green, the valve's five mechanism checks and the seven simulator mutation proofs in the
falsifiability table above, the satisfiability row corrected to what the check actually asserts, and
Gate G1's shipped configuration locked in `src/shared/Config/CardPool.luau` against the committed
`02-G1-REPORT.md`. The two Manual-Only rows remain open debt and are unchanged: G1's pacing half
still measures the bot, not real players.
