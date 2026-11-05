---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: planning
stopped_at: Phase 4 context gathered (04-CONTEXT.md); ready to plan Phase 4 or 5
last_updated: "2026-11-05T00:52:19.294Z"
last_activity: 2026-11-05
progress:
  total_phases: 8
  completed_phases: 3
  total_plans: 37
  completed_plans: 37
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-02)

**Core value:** The two-stage race has to feel great: the frantic card scramble must flow into the spoon hunt so that getting four of a kind feels like a starting gun, not a menu transition.
**Current focus:** Phase 4 — Live Card Table (Phases 1, 2 and 3 complete; context gathered, not yet planned)

## Current Position

Phase: 4 (Live Card Table) — **context gathered, 0 plans**
Plan: 0 of TBD
Status: Ready to plan Phase 4 (or Phase 5 — the roadmap pairs them)
Last activity: 2026-11-05

Progress: [░░░░░░░░░░] 0% of Phase 4 — Phases 1, 2 and 3 complete (37/37 plans, Gates G1 and G2 passed)

**Phase 4 context:** `.planning/phases/04-live-card-table/04-CONTEXT.md` (33 decisions, all eight
gray areas discussed). Full Q&A audit trail in `04-DISCUSSION-LOG.md`.

**Gate G1: PASSED** on the evidence in `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md`.
Selected and shipped in `src/shared/Config/CardPool.luau`: `k = 3` extra ranks, `j = 1` joker,
`JOKER_MODE = "Wild"` with Blocker live behind the flag, `ANTI_LIVELOCK_VALVE = true`,
`AUTO_PASS_MAX_SECONDS = 8.0`, `AUTO_PASS_SELECTION = "uniform-random-from-hand"`.
**The claim in its honest form:** 320,000 gated rounds at the locked 10,000 per (N, pool config)
produced **37 stalled rounds — 0.012% aggregate, 0.070% worst cell — against a 0.500% residual
ceiling**. Zero was the locked bar; no pool this engine has reaches it, so the bar became an explicit
residual ceiling (amendment A8) with the measured residual printed rather than rounded away. It is a
measured property of the SELECTED configuration at the confirmed round count, never an unconditional
property of the engine.

**Phase 2's exit condition is met:** `509 passed, 0 failed, 0 todo`, and `scripts/verify.luau` 14/14.
The three spec-lock `t.todo` entries that fed G1 (CARD-09, CARD-10, CARD-12) are real asserting tests.

Phase 1 remains COMPLETE and verified at commit `70fd9ce` by gsd-verifier: 9 of its 10 requirements
COMPLETE, FOUND-08 PARTIAL.

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: - min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01 P01 | multi-session | 3 tasks | 16 files |
| Phase 01 P02 | 1 session | 3 tasks | 15 files |
| Phase 01 P09 | 1 session | 2 tasks | 5 files |
| Phase 01 P10 | 1 session | 3 tasks | 8 files |
| Phase 01 P11 | 35m | 3 tasks | 10 files |
| Phase 02 P12 | 35m | 2 tasks | 6 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Engine-first. Pure card engine and pacing simulator (Phase 2) precede all UI and networking; Gate G1 sits inside Phase 2.
- [Roadmap]: Parallel pairs are Phase 2 with Phase 3, and Phase 4 with Phase 5; they merge at Gate G3 (vertical slice) before breadth work.
- [Roadmap]: Map contract (MAP-01) lands in Phase 1, validator (MAP-02, MAP-03) in Phase 3 after placement rules; the five maps (Phase 7a) wait on Gate G2.
- [Roadmap]: Anti-ESP is designed into Phase 5 on auto-filled data spoons, before the hide UI exists (Phase 6).
- [Roadmap]: Lint guards FOUND-05 and FOUND-06 are Phase 1 so no-pay-to-win and engine purity hold for the whole project.
- [Roadmap]: Engine lives in `server/engine/`, tested headless (Lune or `luau` CLI), not Jest-Lua (research Contradiction 1, follows ARCHITECTURE).
- [Roadmap]: Phase 7 holds two independent tracks (maps 7a, cosmetics/shop 7b); the planner may split it without changing requirement mapping.
- [Roadmap]: CARD-18, SCORE-09, MATCH-04, MATCH-05 sit in Phase 7 because they need cosmetic content; Phase 4 and Phase 6 build the hooks and baseline.
- [Phase 1 01-01]: D-16 corrected - tools installed by direct release-archive download (api.github.com 403); rokit.toml remains version source of truth for CI
- [Phase 1 01-01]: D-21 - roblox.yml must be generated outside the container (selene rustls cannot trust egress proxy CA); owner-generated, committed 4f011f1
- [Phase 1 01-01]: Fourth exit-code trap - luau-lsp exits 0 when sourcemap fails to load; sourcemap load must be asserted in every gate chain (01-10, 01-11)
- [Phase 1 01-02]: Test.luau owns FuzzOpts/FuzzDriver and requires nothing; fuzz driver injected, absence fails loudly
- [Phase 1 01-02]: Lune 0.11.1 passes '--' through to scripts and rejects .luau in require strings; runner handles both; failure-expecting meta cases must assert the reason
- [01-09] Gateway phase gate runs before the token bucket; validator codes pass through; rate limits (4/4, Ping 2/1) provisional LOW confidence
- [01-11] luau-lsp gated via scripts/ci/analyze.luau (exit 0 and no Failed to load / Sourcemap parsing failed / TypeError); hook uses stylua --respect-ignores

**Phase 2 — Gate G1 and the engine's locked contracts.** Every item below is locked by a test; a later
phase that contradicts one fails the suite rather than a review.

- [Gate G1 / 02-12]: **PASSED.** Jokers ship as **wilds**, with blockers live behind `JOKER_MODE` rather
  than held as a contingency — Wild and Blocker each clear all five bars at every N. Evidence:
  `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md`. Measured residual 37 stalled rounds in 320,000 gated
  (0.012% aggregate, 0.070% worst cell) against a 0.500% ceiling; median first completion 16.2s (bar 45s),
  p95 23.7s (bar 120s), occupancy 0.825 (bar 0.600), worst valve firing rate 8.240% (bar 20.000%).

- [02-11] The six shipped `src/shared/Config/CardPool.luau` values: `EXTRA_RANKS = 3`, `JOKERS = 1`,
  `JOKER_MODE = "Wild"`, `ANTI_LIVELOCK_VALVE = true`, `AUTO_PASS_MAX_SECONDS = 8.0`,
  `AUTO_PASS_SELECTION = "uniform-random-from-hand"`. `ranks = seatCount + 3` with `seatCount` = seated
  seekers = (players in round) − 1 (amendment A3; `Pool.poolConfig` is the only site that writes that
  subtraction). Circulation `= 4k + j = 13`.

- [02-11, owner] **`k = 3` over the bar's own `k = 6` is a GAMEPLAY decision, not a measurement.** Every
  candidate `k = 2..6` clears all five bars and the firing-rate curve is smooth and monotone with no
  elbow, so the bar CHOOSES rather than discovers (7% selects k=6, 20% selects k=3, 40% selects k=2).
  `k = 3` is the tightest pool reaching a clean zero stall rate on the search grid; it gives up ~2s of
  starting-gun speed against k=2 while cutting forced passes by about a third, and avoids k=6's ~45%
  slower start (median first 20.9s against 16.2s). The sweep was then **re-run** at that operating point,
  so the shipped pool is also the confirmed one.

- [02-13 / amendment A7] **The engine's anti-livelock valve, with its firing and choice rules locked.**
  Fires **immediately after a non-completing `Draw`, on the drawing seat**, when the whole-table state
  repeats with no completion since the previous repeat; it then forces one pass chosen **from naturals
  only** (falling back to the lowest card id in an all-joker hand). Its generator is DERIVED from the
  round's seed, never constant. `VALVE_SEEN_CAP` clears the whole observation window on overflow, so a
  non-zero `seenResets` means the valve was blind rather than merely quiet. These are 02-13's own choices
  held constant so the reference numbers stay comparable — they are not restatements of A7's wording.
  The valve must stay ON in the shipped game: at the selected pool the valve-DISABLED twins stall at
  3.58–8.31%, matching the firing rate, so every firing is a real rescue.

- [02-02] **The locked four-bucket seat order**, and `dealer == seatOrder[1]` always, because the hider is
  not seated so the highest-placed SEATED finisher IS the head of the order. Buckets: finishers by find
  order, then non-finishers by previous seat index, then the previous hider, then joiners by join order,
  with userId ascending as the final tiebreak. Zero finishers is NOT a special case (bucket 1 is simply
  empty); two or more empty-handed seekers is NOT a special case (bucket 2 is a list with a key, never an
  index into "the" non-finisher). Round 1 is the same function with every previous list empty and an
  INJECTED Rng — a missing rng is a loud error, never a fallback to the global generator.

- [02-06] **The locked removal dump order and the terminal bucket.** A departing seat's cards go
  **hand ascending, then inbox in FIFO order**, appended to the successor's inbox tail (research OQ-G).
  The sole-seat case routes to `state.terminal` (`head = 0`, `liveCount = 0`) rather than down a nil path,
  which is what keeps Non-Negotiable Rule 8's "never destroyed" literally assertable by the partition
  identity. `removeSeat` decrements `rankInPlay`/`jokersInPlay`/`cnt` **only** in the no-successor branch:
  routing a card to an inbox does not take it out of play.

- [02-07] **The locked reject precedence, event order and valve call rule.** Exactly seven reject codes,
  first match wins, with `UnknownCard` before `HandNotFive` and `HandNotFour` before `InboxEmpty` both
  mutation-proven in both directions. A rejection asserts four things — the code, an empty event list, an
  unchanged canonical hash, and an **unmoved valve** (the fourth is not implied by the third, because
  `Invariants.hash` excludes `valve` by design). The valve is wired INSIDE `apply` where no caller can
  forget it: exactly one entry point per successful apply and none on a rejection. Locked event order
  includes the valve's three-event form `Drew -> ValveForcedPass -> Passed`. A `Remove` intent may NOT
  carry the `Completed` cause — that is a caller-bug error, not an eighth reject code.

- [02-03 / amendment A6] **`coroutine` and `os.` are banned in the pure zones** by `check-guards` R3, which
  is what finally makes Non-Negotiable Rules 5 and 6 enforced rather than merely stated. `coroutine` is a
  whole-identifier ban; `os.` is a needle on the dotted namespace, so a pure-zone file may not contain the
  substring `os.` even inside a string literal. **No suppression mechanism was added** — a rule a developer
  can switch off in the file it governs is not a rule.

- [02-01] **The locked violation ORDER of `Invariants.check`**, nine names: `hand-size`, `ring-links`,
  `liveness`, `circulation`, `partition-count`, `partition-identity`, `counters-rankInPlay`,
  `counters-histogram`, `unsatisfiable`. **Do not reorder it.** `circulation` (4) precedes `unsatisfiable`
  (9) deliberately: a card that vanished is a conservation bug and must be reported as one. Reordering
  would make conservation bugs surface as stall statistics, which is the single most expensive way for
  this engine to be wrong. It is locked three ways — by `Types.Violation`, by a comment in both files, and
  by a test.

### Notes that would otherwise be lost

- **`src/server/engine/SeatOrder.luau` has no consumer inside Phase 2** beyond its own corpus, **by
  design**. Its first caller is **Phase 6's match lifecycle** (`nextSeatOrder` / `dealerOf`, with the
  locked four-bucket order above). It is not dead code and a later cleanup pass must not delete it.

- **The simulator's clock is float seconds; the shipped clock is integer deciseconds** (Non-Negotiable
  Rule 5 — the server is the only clock, scoring granularity 100ms). Round at the boundary when Phase 4
  carries any simulator-derived timing across.

- **`ValveForcedPass` fires in roughly 8% of rounds at the shipped pool** (3.59–8.24% per cell at N=10, up
  to 15.8% at tighter pools). A card leaves a player's hand that they did not choose, so **Phase 4 needs a
  real affordance for it**, not an edge-case path. The firing rate is a FEEL cost, not only a safety
  statistic — which is why it was traded against pacing rather than minimised.

- **The start-up ramp is real:** ~8.3s at N=10 against a 4.6s median time-to-first-completion at N=3. Far
  seats need a "waiting for cards" affordance.

### Pending Todos

From Phase 1 verification (`01-VERIFICATION.md`), each cheap now and expensive later:

**CLOSED 2026-11-04 (Phase 2, plan 02-08):** the carried Phase 1 fuzz todo — the fuzz harness had never
run beyond toy-scale properties at a 200-iteration count. Closed with a number: `tests/engine/fuzz.spec.luau` runs one
stateful case whose iteration is a whole round, and it measured **194,567 actions** (170,332 accepted,
24,235 rejected) across 500 rounds at every seat count from 2 to 9, with the full four-bucket partition
identity checked after every single action — 1.95x ROADMAP criterion 1's 100,000-action bar. The remaining
rows below (Phases 5, 6 and 7) are untouched and still open.

| For | Item |
|-----|------|
| **Phase 5** | `R4`'s `netOwners` guard covers only `Remote*` members. `ProximityPrompt.Triggered`, `ClickDetector.MouseClick`, `Tool.Activated` and `Humanoid.Touched` are unguarded client-to-server paths that bypass the gateway entirely. Phase 5's spoon-pickup affordance is exactly where the first one appears. One-line fix to the guard. |
| **Phase 5** | **`RaycastParams.RespectCanCollide` defaults to `false`** — the opposite of Phase 3's D-03, which treats only `CanCollide = true` parts as solid. Phase 5's line-of-sight raycast MUST set it to `true`, or CI and the live game will disagree about what blocks sight and a spot the validator passed can hide a spoon in play. Found by 03-RESEARCH while re-checking V-18 against primary docs (the one Roblox doc host reachable that run). One-line fix, invisible until it bites. |
| **Phase 6** | Wire `PlayerGate.canStart`. It has zero callers today, which is why FOUND-08 is PARTIAL. `Admission.luau` forbids anything else deciding a match may start, and that invariant is currently unenforceable because there are no call sites to inspect. |
| **Phase 7 (before authoring any cosmetics module)** | `FOUND-05` is a **filename deny-list** and the verifier confirmed it can be made vacuous by naming alone: `Scoring.luau` importing `Wardrobe.luau` leaves `check-guards` green. This is inside the guard's declared threat model (accident and drift), not outside it, but the no-pay-to-win rule is Non-Negotiable Rule 1. Require cosmetics/shop code under `cosmetics/` and `shop/` directories (path-segment matching already supports it), or invert R2 to an import allow-list. |
| **Phase 7 (start, and before any real DataStore write)** | Re-run M-04 check 2. FOUND-07's enforcing control is a Creator Hub toggle **outside the repo**; Phase 1 proved empirically it can be wrong while all 14 gates are green, and nothing in the repo can detect it being flipped back. Also close M-04 check 3 before the first real write. |

### Phase 3 execution findings (recorded as they are measured, not at phase close)

- **At the shipped `GRID_SIZE = 1.0` the slope-allowance erosion is INERT for the graybox ramp**
  (plan 03-04, measured). Research called slope-allowance erosion "the non-obvious part" of the
  walkable-grid pattern, but the plan's own test for it **could not detect its removal**: the
  mutation produced no FAIL line at all, because at g=1 with `CAPSULE_RADIUS 1.5` the erosion
  window reaches only one cell, so the rise it sees is 0.466 and the allowance never binds. The
  executor added a discriminating pair at `GRID_SIZE 0.5` (step 0.5 connects, step 0.2
  disconnects) which DOES go red under the mutation, and kept the plan's original pair labelled
  non-discriminating. **The machinery is correct and tested, but it is not load-bearing at the
  configuration that ships** — so do not cite it as a reason the ramp connects. Carry into
  03-10's debt section.
- **ACCEPTED DEPARTURE (orchestrator, wave 3): the two shelf corpus rows report `Unreachable`,
  not `OutOfReach`.** The locked corpus said `OutOfReach`; plan 03-05 measured `Unreachable` and
  asked for confirmation rather than adjusting the expectation. **Accepted, because the measured
  VALUE is unchanged** — nearest spawn-connected cell 6.538 against research's 6.54 — and only the
  label moved. The shelf top carries its own standable cells 2.12 away, inside `E = 5.5` but region
  0, so `OutOfReach`'s condition ("a cell within `PICKUP_RANGE` but none within `E`") is false while
  `Unreachable`'s ("a cell within `E` but none spawn-connected") is true. Research used "REACH" as a
  **coarse bucket spanning both reasons**, because D-12's six-reason taxonomy was decided after
  research ran (research gave five illustrative names and contradicted itself in the same
  paragraph). Corroborated independently: the implementation also reproduces research's ladder at a
  second operating point — at `PICKUP_RANGE 8.5` the shelf edge passes and the shelf centre is
  `NoSight`. **Consequence: the shelf is never `OutOfReach` below `E = 6.54`.** A flat-room row at
  (4, 8.7, 4) now produces `OutOfReach` for the coverage case.
- **"A comment that names the thing a grep forbids" has now bitten FOUR times in this phase**, and
  it is worth treating as a known failure mode rather than four coincidences: (1) the plan snippet
  whose comment spelled `MapValidator.validate(` and so broke its own call-site sweep; (2) plan
  03-02's `grep -c 'require'` floor contradicted by the header prose the same task mandated; (3)
  plan 03-05's own criterion forbade spelling `Config/Placement` in a comment, and 03-05 then did
  exactly that at `SpoonPlacement.luau:46`, which 03-08 found when the raw-source sweep failed on
  correct code; (4) 03-08's own sweep needed comment-stripping to be meaningful at all. **Rule for
  later phases: a grep-based gate over raw source is only sound if nothing in the file is allowed
  to describe what the gate searches for. Prefer `lex.stripComments` for any such gate.**
- **Line numbers quoted in a plan go stale exactly like counts do.** The plan (and the plan-checker)
  named two `validate(` call sites in `tests/maps/graybox.spec.luau` at lines 110 and 229; by wave 5
  there were **three**, at 175, 253 and 314, because waves 1-4 had edited the file. All three were
  injected. Later plans should locate call sites by pattern at execution time, never by line number.
- **`MAP_NO_SIGHT`'s overhang half-width flips to `OutOfReach` at about 3.45, where the plan's
  derivation said 3.62** (plan 03-08, measured). The fixture is unaffected at `w = 3` with ~0.45
  slack, but the derivation is slightly optimistic and should not be re-used as an exact figure.
- **A baseline captured at planning time can go stale before the wave that asserts it runs.** Plan
  03-05's "guarded roots = 20 before" was measured during planning; waves 1-2 added roots, so the
  real transition was 22 -> 23. The +1 delta still evidences the new root. Later plans asserting a
  repo-wide count should derive it at execution time, not quote a planning-time figure.
- **"Corridor width 3 erodes to nothing" holds only when the faces sit on lattice centre lines**
  (plan 03-04). A width-3 gap otherwise spans three centres. The maze fixture aligns deliberately
  and documents it; the authoring rule `width >= 2 * capsuleRadius + gridSize` is **sufficient,
  not exact**. Plan 03-07's maze oracle depends on this.
- **CI suite timing, tracked per wave:** Phase 1 baseline 15.94s -> Phase 2 close ~25-26s
  (owner-accepted departure) -> wave 1 **26.7s** -> wave 2 **29.6s**. Five waves remain and D-09's
  bake cap is additional. This needs an explicit owner decision before phase close rather than a
  silent second overshoot.
- **Orchestrator error, recorded for honesty:** the wave-2 executor was handed a fabricated full
  commit hash (short `51f76b8` was known; the remaining characters were invented). The agent
  detected the mismatch, verified HEAD was the correct commit and proceeded safely. Later waves
  use `git rev-parse HEAD` output verbatim.

### Blockers/Concerns

- **RESOLVED (Phase 2):** the former card-engine blocking entry is gone. CARD-09 (deal-time four-of-a-kind)
  and CARD-10 (which four cards leave on a joker completion) are no longer defaults awaiting a decision —
  they are asserting tests in `tests/engine/spec_lock.spec.luau`, and the runner's todo count is 0.

**Carried debt from Gate G1** (verbatim from `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md` section 8,
inherited explicitly so the next phase does not have to infer it):

- **V-35 STANDS.** Whether a bot's reaction-time distribution represents real humans is unverifiable
  without real playtests; carried since project init. Calibrate in Phase 4/6 against live sessions.

- **A4 STANDS.** Whether humans deviate from pure greed often enough is the same class as V-35 and was
  newly surfaced by this phase's research. Measure the deviation rate at the first real playtest.

- **Scope note on what those two actually limit.** G1's **solvability** half is a theorem and needs no
  playtest — it does not depend on the bot model at all. Its **pacing** half measures the bot, not the
  game, until the two rows above close. Do not let a green pacing number read as a verified claim about
  real players.

- **RETIRED by amendment A7: the deviation-rate assumption.** The zero-stall result no longer depends on
  how often humans deviate from pure greed, because the engine's valve deviates for them. What remains
  unverified is therefore the pacing model, not the solvability claim.

- **RETIRED by plan 02-03: the engine's half of verification debt V-15.** The pure-zone R3 guard now bans
  `coroutine` and `os.`, so Non-Negotiable Rules 5 and 6 are enforced in the engine rather than stated.
  V-15's non-engine half is unaffected.

- **The valve-on residual is NEITHER a `CapArtifact` NOR an unexplained `ResidualLivelock`, and it was
  measured rather than assumed.** `capArtifactCandidates` is empty in all 1,132 cells of the run across
  1,501,000 simulated rounds, and `hitActionCap` is false in every confirm row, so `02-triage.json` is
  absent by measurement rather than omission. Every stalled round this engine produces is a 300s
  `time-cap` round, which a raised ACTION cap cannot rescue. That is exactly why the recorded claim is
  scoped to the selected pool and the 37/320,000 residual is printed rather than rounded to zero.

- **Accepted departure from a locked decision (owner, 2026-11-04):** 02-CONTEXT locked "Phase 1's CI is
  ~20s and that should stay true". The suite now runs ~25–26s (Phase 1 baseline 15.94s + plan 02-09's
  measured 8.0s simulator subset + 02-08's fuzz suite and the new engine specs). **The owner accepts the
  overshoot.** Nothing was trimmed to hide it: the 500-round statistical floor, every mutation case and
  every bar are intact. Recorded as a measured, approved departure rather than a silent one.

- Verification debt: every Roblox platform claim in research is unverified (doc hosts DNS-blocked). Each phase's research step starts by re-checking SUMMARY.md Verification Debt rows for that phase. Add the blocked hosts to the environment's allowed domains.
- Owner decisions CONFIRMED during initialization: hider-score denominator = fixed 300 s (OQ 7); mid-round leaver = finish the round then end on current totals, no win credit (OQ 8); free/earned cosmetic baseline = free defaults plus an achievement-unlocked set (OQ 11); player cap = 10 (OQ 17).
- Owner decisions still open: match tiebreak (OQ 5, default: higher best-round then earlier four-of-a-kind placement), VIP route (OQ 14, Phase 7b), Game Pass versus Developer Product switch point (OQ 15, Phase 7b), rejoin policy confirmation (OQ 18, derived default in MATCH-08), cold-start and bot-fill decision (OQ 13, Phase 8 on telemetry).
- **Phase 3 Open Question 1 RESOLVED (owner, 2026-11-04): STRICT.** "After exclusions" was
  undefined and MAP-02, ROADMAP criterion 3 and Phase 1's 18-spot rationale could not all hold.
  Every authored default spot must pass; one issue per failing spot; any failure fails the build.
  **Consequence: the graybox is regenerated inside Phase 3** (D-17), because the confirmed
  constants leave exactly 16 of 18 surviving with zero spare, and `Spot08` is genuinely
  unfindable (line of sight blocked from every floor position within 12.36 studs).
- **OQ 12 RESOLVED (Phase 3 discuss, 2026-11-04):** avatar normalisation scope is a **canonical
  reference avatar** — one fixed capsule for every validity test, biased toward rejecting (short reach,
  tall headroom). The rule function takes no avatar argument, so HIDE-07's scale-invariance is true by
  construction rather than sampled. Recorded as D-10/D-11 in
  `.planning/phases/03-placement-rules-map-pipeline-and-validator/03-CONTEXT.md`.
- Cold start below the 3-player minimum is an existential risk that code alone cannot fix; bot-fill decision is deferred to Phase 8 on telemetry.
- First true 9 to 10 player human playtest needs a published place (human gate); Studio multi-client is capped.

### Phase 2 verification findings carried into Phase 4 (do not rediscover)

- **The valve has an unstated DETECTION LIMIT.** It fires only on an **exact** whole-table state
  repeat. A stuck trajectory that never exactly repeats is invisible to it even when armed and not
  blinded. Phase 2 verification replayed 15 of the 37 residual stalled seeds: all reproduced, every
  one reached a first completion (6.8-24.4s) and then ran **2,431-4,429 actions without clearing**
  against a healthy cell mean of ~380, with `valveSeenResets = 0` throughout — and **3 of the 15
  had `valveArmed = true` and zero firings**. So a stuck round can present with **no
  `ValveForcedPass` at all**: a "this round is going nowhere" affordance must NOT be keyed off valve
  events. This narrows the valve's claim; it does not weaken the measured result.

- **The triage question is formally open, and this sweep cannot close it.**
  `capArtifactCandidates`/`hitActionCap` track the 100,000-**action** cap, while the gated cells are
  Pacing cells ending on the 300-**second** clock at ~379 actions per round — so "no action-cap
  rounds" was structurally guaranteed for those 1,113 cells rather than discovered. The conclusion
  drawn from it is still correct and conservative (300s is the shipped round cap, so raising an
  action cap was never an option), but **whether the residual rounds are cycling or merely slow is
  unanswered**, because cycle detection is disabled for every valve-ON cell by design.

- **The fuzz suite's `k` grid is {1,2} and never covers the shipped `k = 3`.** Its 194,567-action
  conservation result is therefore not a claim about the shipped pool. Worth widening when Phase 4
  touches it.

- **CI regresses N = 3, 6, 10 only, while every observed residual stall was at N >= 7** (worst cell
  N = 9). The CI subset cannot see the regime the residual lives in.

- **A8's "firing rate equals valve-off stall rate to three decimals" does not hold to three
  decimals** (Blocker/churn 4.77% vs 5.33%; Wild/no-churn 5.86% vs 6.21%), and "every firing is a
  real rescue" is an inference from the correlation, not a per-firing measurement. The correlation
  is strong and the conclusion stands; the precision claim was overstated.

- **Phase 6 note on SeatOrder:** its 28-case corpus uses hand-built inputs, so the residual risk is
  the **construction** of `SeatOrderInput` from live records — hider identity, filtering departed
  finishers. Re-verify that when Phase 6 wires it, not the ranking itself.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-11-05
Stopped at: **Phase 4 context gathered.** All eight gray areas discussed; 33 decisions recorded.
Phase 3 remains complete (11/11 plans, Gate G2 PASSED by the owner in Studio).
Resume file: `.planning/phases/04-live-card-table/04-CONTEXT.md`

**Final measured state:** 657 tests passed / 0 failed / 0 todo; `verify.luau` 14/14 exit 0;
`validate-map` ok (21 spots, 9 seats); `ISSUE_CODES` 23; MANUAL-CHECKS 8 signed, 2 unsigned.

**Next:** `/gsd-plan-phase 4`. Phase 5 (Hunt, Anti-ESP, Claim and Scoring) is equally available —
the roadmap pairs 4 and 5 and they merge at Gate G3, the vertical slice. Phase 5 depends on Phase 3
and is now unblocked; Phase 4 depends on Phase 2. Phase 7a is also unblocked by Gate G2 but waits
on Gate G3 per the roadmap.

**New human gate raised by Phase 4's context (D-28):** landscape must be locked as the supported
orientation in the place settings, which is a Creator Dashboard step. It is recorded in
`04-CONTEXT.md` and belongs in `MANUAL-CHECKS.md` / `NEEDS_HUMAN.md` when Phase 4 is planned.

**Two items Phase 4's context carries as planner-level rather than owner-level:** D-22 of
`01-CONTEXT.md` (the gateway's phase-gate-before-token-bucket order, flagged in Phase 1 for revisit
in Phase 4 or Phase 8) and the rate limits for the new `Draw` / `Pass` intents (the current default
burst 4 / refill 4 per second predates any card traffic; V-34 marks the numbers LOW confidence).

**Carried into Phase 4/5/6 — do not rediscover:**
- **`RaycastParams.RespectCanCollide` defaults to `false`**, the opposite of D-03. Phase 5's
  line-of-sight raycast must set it `true` or CI and the live game will disagree about what blocks
  sight. This is the highest-value single fact this phase produced for a later one.
- **M-09 is the open human gate under V-19**, the phase's one genuinely soft claim: per-axis avatar
  scale limits, the R15 default `HipHeight` and any camera-height formula were never found in
  primary docs. Until signed, D-11's bias toward rejecting is the mitigation, not a verification.
  Needs a full-roster playtest; pair it with M-07.
- **Phase 5 must consume the same `EYE_HEIGHT` and `PICKUP_RANGE`** from
  `src/shared/Config/Placement.luau`, measured from the same root point. A separate `EYE_HEIGHT` is
  load-bearing: sharing one height culls the crate-top spots and drops the map below MAP-03.
- **CI timing will need revisiting in Phase 4**, which adds the most test weight of any remaining
  phase. Accepted at 29.9 s here as a second approved departure.
- **The process finding worth more than any fix:** nine assertions structurally incapable of firing
  were found in Phase 3 alone — three by the plan-checker across three passes, six by executors.
  Phase 2 found ~22. The pattern recurs even when everyone is actively looking for it, so budget
  for mutation-testing every gate rather than treating it as optional.
