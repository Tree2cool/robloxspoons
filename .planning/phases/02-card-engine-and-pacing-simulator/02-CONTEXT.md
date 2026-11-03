# Phase 2: Card Engine and Pacing Simulator - Context

**Gathered:** 2026-11-03
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous), 3 areas, all accepted as recommended

<domain>
## Phase Boundary

A pure, headless, synchronous card-ring engine plus a headless bot pacing simulator that
**decides Gate G1** — whether jokers ship as wilds (CARD-10) or as blockers (CARD-12) — before any
UI exists. The engine is the thing every later phase builds on: Phase 4 drives it over the network,
Phase 5 consumes its completion events.

In scope: CARD-01, CARD-03..CARD-12. The ring, passing, drawing, completion-on-draw, seat removal,
dealer and seat-order computation, the deal, the fuzz suite, the simulator, and the G1 decision.

Out of scope: anything with a Roblox API call, any UI, any network message. Non-Negotiable Rule 2
applies — `server/engine/` is lint-enforced pure and runs headless in CI.

</domain>

<decisions>
## Implementation Decisions

### Stall Definition and Pacing Targets

- A **stall** is either a structural deadlock — no seat can reach four-of-a-kind given the remaining
  card multiset — or a round that hits the 300s cap with zero completions. Detect impossibility
  directly rather than inferring it from slowness; a timeout-only definition cannot distinguish
  "slow" from "impossible", and the two have different fixes.
- Pacing target: **median time-to-first-completion <= 45s and p95 <= 120s at every N from 3 to 10.**
  Rationale from PROJECT.md's core value — the completion is the starting gun, so the hunt must get
  the bulk of the 300s. "Under the cap" was rejected as too weak to catch a snowball.
- **10,000 rounds per (N, pool config), and the bar is ZERO stalls, not a low stall rate.** One
  stalled round wastes five minutes for up to ten people, so a rate target would be accepting a
  known defect.
- Every trial is seeded from a recorded base seed, and **a failing trial prints the seed that
  reproduces it** so it can be pasted straight into a unit test. CI runs a fixed seed set; random
  sweeps are a separate manual run.

### Bot Model

- **Greedy passing:** keep the rank you hold most of, pass from the smallest group, ties broken by
  card id so runs are deterministic. This is both how a competent human plays and the adversarial
  case for solvability, because everyone converging is what strands a wild's real fourth card.
- **Gate on the all-greedy population.** A mixed greedy/random population is also run and reported,
  but it is the easier case and must not be what G1 passes on.
- **Reaction time is lognormal over roughly 250-900ms per action**, with a **zero-latency mode** for
  pure solvability runs. Pacing needs timing; solvability does not, and mixing them wastes runtime.
- **Churn is modelled:** a baseline run with a stable table and a variant with a random leaver per
  round. Seat removal is precisely where the engine can strand ranks (Non-Negotiable Rule 8), so a
  simulator that never removes a seat would miss the most dangerous case.

### Card Pool and the G1 Search

- Pool is **ranks = seatCount + k, four cards per rank**, searching **k in {0,1,2}** against
  **jokers in {0,1,2}**.
- The gate selects the **smallest pool that passes** — fewest extra ranks first, then fewest jokers.
  A larger pool is safer and flabbier; tightness is what makes the scramble tense.
- The wild-versus-blocker switch lives in a **pure `EngineConfig` value passed into the engine**,
  never a module-level constant, so both variants can run in the same process and both stay under
  test. CARD-12 is built from day one, not as a later fallback.
- **CI runs a fast subset** (500 rounds x N=3..10, fixed seeds) as a regression gate; the full 10k
  sweep is a manual/nightly script whose output is committed as a report. Phase 1's CI is ~20s and
  that should stay true.

### Claude's Discretion

- Engine module decomposition, type shapes, and the exact `apply`/event vocabulary, subject to
  Non-Negotiable Rules 2, 6 and 7.
- The lognormal parameters within the stated range, and the precise structural-deadlock predicate.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `tests/harness/Test.luau` — the test runner, and it **owns `FuzzOpts`/`FuzzDriver`**; the fuzz
  driver is injected and its absence fails loudly. Phase 2's 100k-action suite plugs in here.
- `tests/harness/FakeClock.luau` — time is injected, never slept. The simulator must take its clock
  the same way, or it cannot run 10,000 rounds quickly.
- `src/shared/Rng` (from 01-02) — the seeded generator the deal and the bot model need.
- `src/server/core/Admission.luau` — owns the 3..10 bounds the simulator sweeps.
- `tests/engine/spec_lock.spec.luau` — the three `t.todo` entries for CARD-09, CARD-10 and CARD-12.
  **Phase 2 must convert all three into real tests and drive the runner's todo count to 0.**

### Established Patterns

- Pure zones are `src/server/engine`, `src/server/core`, `src/shared/Net`, lint-enforced with an
  allow-list and typechecked on the standard (non-Roblox) platform. The engine goes in
  `src/server/engine/`.
- Tests assert the **reason**, not just the outcome; several Phase 1 defects were tests passing for
  the wrong reason. Every rejection asserts its own code.
- New gates are **mutation-proven** — broken deliberately to confirm they fail — before being
  trusted. Phase 1 verification found two checks that could not fail.

### Integration Points

- `scripts/verify.luau` and `.github/workflows/ci.yml` hold byte-identical run strings, asserted by
  a spec. Adding the simulator subset to CI means editing both.
- `src/server/core/RoundDriver` exists with `beginRound`/`deadlineUnix` currently uncovered and
  uncalled — Phase 2 or 4 is where it gets wired and tested.

</code_context>

<specifics>
## Specific Ideas

- The ring is a circular doubly-linked list; each seat has a `hand` and an `inbox` (its left pile,
  a FIFO deque). **The wrap needs no special case because the dealer's inbox IS the deck.** "The
  pile locks at 5" is just the rule *draw only when hand size is 4*. Four of a kind is checked
  **only on draw**, since passing can only leave a subset of a hand that already had none.
- Carried from Phase 1 verification, due this phase: the fuzz harness has only ever run toy
  properties at 200 iterations. Phase 2 is the first real load at 100k actions.

</specifics>

<deferred>
## Deferred Ideas

- AFK auto-pass (CARD-16) and the completion moment (CARD-17) are Phase 4 — they need a live table.
- Prediction and reconciliation (CARD-14) is Phase 4.
- The deal animation (CARD-18) is Phase 7, needing deck-skin content.

</deferred>
