---
phase: 2
slug: card-engine-and-pacing-simulator
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-11-03
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
| **Estimated runtime** | ~16s full suite, sub-second for `--filter engine`, +2–6s for the simulator subset |
| **Baseline at phase start** | 333 passed, 0 failed, **3 todo**, 15.94s |

**PATH gotcha — applies to every task.** Rokit shims are not on the default PATH. Running
`lune run tests/run.luau` without `PATH=/root/.rokit/bin:$PATH` reports **67 spurious failures**.
Every plan task's automated verify must set PATH explicitly.

**Phase exit condition: the runner's todo count reaches 0.** `tests/engine/spec_lock.spec.luau`
holds three `t.todo` entries (CARD-09, CARD-10, CARD-12) that must become real tests. A green run
with todos remaining is not a finished phase, and the pass count alone will not reveal it.

---

## Sampling Rate

- **After every task commit:** `lune run tests/run.luau -- --filter engine` (sub-second)
- **After every plan wave:** full suite — **and check the todo count, not just the pass count**
- **Before phase close:** `lune run scripts/verify.luau` green, todo count 0, sweep report regenerated
- **Max feedback latency:** ~16 seconds

---

## Phase Requirements → Test Map

| Req | Behaviour | Type | Automated command | File |
|-----|-----------|------|-------------------|------|
| CARD-01 | draw only at `hand == 4`; `HandNotFour` asserts its own code; hand size always 4 or 5 | unit + fuzz | `--filter engine/hand` | ❌ W0 |
| CARD-03 | passed card lands in the `next` LIVE seat's inbox tail, resolved at apply time, including when the target was removed between intent and apply | unit | `--filter engine/pass` | ❌ W0 |
| CARD-04 | last seat's pass appends beneath the dealer's deck; FIFO preserved; circulation never reaches 0 | unit + fuzz | `--filter engine/ring` | ❌ W0 |
| CARD-05 | dealer = `seatOrder[1]`; first-finder-is-hider; no seated finisher; zero finishers; round-1 seeded random | unit corpus | `--filter engine/seatorder` | ❌ W0 |
| CARD-06 | finishers → non-finishers (0, 1, ≥2) → previous hider → joiners → `userId` tiebreak | unit corpus | `--filter engine/seatorder` | ❌ W0 |
| CARD-07 | completion detected **only** on draw; completing rank unique; seat removed in the same apply | unit + fuzz | `--filter engine/complete` | ❌ W0 |
| CARD-08 | hand + inbox → successor in a locked order; ring→2, ring→1, ring emptied, dealer removed, mid-pass departure | unit + fuzz + **mutation** | `--filter engine/removal` | ❌ W0 |
| CARD-09 | no opening hand complete or wild-completable (4, 3+1, 2+2); rejection counter **> 0** over the corpus | unit + corpus + **mutation** | `--filter engine/deal` | ❌ W0 (replaces a todo) |
| CARD-10 | naturals spent before jokers; 5th-card identity; `j <= 2` asserted so all-joker is unreachable | unit | `--filter engine/joker` | ❌ W0 (replaces a todo) |
| CARD-11 | simulator: zero stalls + pacing bars + **occupancy floor** at N=3..10; a failing trial prints its seed | integration | `--filter sim/subset` | ❌ W0 |
| CARD-12 | blocker mode runs in the same process via `EngineConfig`; chosen pool passes in **both** modes | unit + integration | `--filter sim/blocker` | ❌ W0 (replaces a todo) |
| Rules 5/6 | pure zones reject `coroutine.*` and `os.*` | guard + **mutation fixture** | `lune run scripts/ci/check-guards.luau` | ❌ W0 |

---

## Every Check's Falsifiability Proof

**House standard.** A check is not trusted until it has been made to fail on purpose. Phase 1
verification found a length check behind a "sha256-pinned" claim and a namespace-confused comparison
that could never fire — both green, both worthless.

| Check | How it is proven capable of failing |
|-------|-------------------------------------|
| Circulation invariant | drop a card on pass; duplicate one on draw — each must fail the assertion |
| Partition identity | swap a card for a copy of another; counters stay consistent, the identity scan must fail |
| Satisfiability predicate | **destroy a removed seat's cards** (violate Rule 8) → fires in 2.9–5.7% of rounds, plus a crafted one-action fixture that fires deterministically |
| CARD-09 deal check | crafted deck forcing a rejection, plus a corpus assertion that the rejection counter > 0. A vacuous predicate is otherwise indistinguishable from a correct one |
| CARD-10 naturals-first | 3 naturals + 2 jokers must retire exactly 3 naturals + 1 joker and keep a joker as the 5th |
| Fuzz load | assert `totalActions >= 100_000` **and** a minimum observed count for every event kind and all six reject codes — otherwise a generator bug silently disables whole areas while green |
| Rejection codes | each illegal intent asserts its own code **and** that state is unchanged |
| New `coroutine`/`os.` guard | fixtures under `tests/purity/fixtures/` using each construct must make `check-guards` exit 1 with the matching R3 message |
| Simulator gate | run it against a deliberately broken engine (Rule 8 destroy variant) and against the `k=0,j=0` dead pool; both must be reported as failures, not passes |
| CI subset wiring | `tests/ci/verify.spec.luau` already asserts byte-identical `run:` strings; running the subset inside `tests/run.luau` needs **no new CI step**, avoiding that drift risk entirely |

---

## Wave 0 Requirements

- [ ] `tests/engine/pool.spec.luau` — deal, shuffle permutation, CARD-09 rejection + its mutation proof
- [ ] `tests/engine/ring.spec.luau` — pass/draw, FIFO, m=2 and m=1 rings, dealer wrap (CARD-03, CARD-04)
- [ ] `tests/engine/hand.spec.luau` — completion detection, rank uniqueness, naturals-first (CARD-01, CARD-07, CARD-10)
- [ ] `tests/engine/removal.spec.luau` — all three causes, all six edge cases, Rule 8 destroy mutation (CARD-08)
- [ ] `tests/engine/seatorder.spec.luau` — table-driven corpus including the five unspecified cases (CARD-05, CARD-06)
- [ ] `tests/engine/invariants.spec.luau` — circulation + partition, each mutation-proven
- [ ] `tests/engine/fuzz.spec.luau` — 100k-action run with action-count and per-kind coverage assertions
- [ ] `tests/sim/subset.spec.luau` — 500 rounds × N=3..10, fixed seeds, both joker modes, churn variant
- [ ] `scripts/sim/sweep.luau` — full 10k sweep plus a committed report
- [ ] `tests/purity/fixtures/engine-yield/`, `tests/purity/fixtures/engine-clock/` — guard mutation fixtures
- [ ] **Rewrite** `tests/engine/spec_lock.spec.luau` — three `t.todo` become real tests, todo count 0
- [ ] No framework install needed. `opts.iterations` **must be set explicitly**; the 200 default is ~2% of the intended load

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

- [ ] All tasks have an `<automated>` verify or a Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without an automated verify
- [ ] Wave 0 covers every MISSING reference above
- [ ] No watch-mode flags
- [ ] Every PATH-dependent command sets `PATH=/root/.rokit/bin:$PATH`
- [ ] Feedback latency < 20s
- [ ] Runner todo count is 0
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
