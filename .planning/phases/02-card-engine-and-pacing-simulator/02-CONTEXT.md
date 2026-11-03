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

### AMENDMENTS after research (2026-11-03) — these OVERRIDE the three areas above

Phase research ran ~230,000 simulated rounds and found that two decisions accepted earlier today do
not survive contact with the numbers. Both were re-decided by the owner. The superseded wording is
kept above deliberately, so the record shows what changed and why.

**A1. Gate G1 is gated on greedy bots PLUS the shipped AFK auto-pass mechanic (CARD-16), not on
pure greedy.** The zero-stall bar is unachievable against a purely greedy population: every
configuration livelocks at a non-zero rate, while a trace of deviation drives it to zero. Confirmed
in two independent implementations (the researcher's Luau spike and a separate Python check, which
agreed qualitatively while differing in magnitude):

| k | j | circulation = 4k+j | pure greedy stall | +2% deviation |
|---|---|--------------------|-------------------|---------------|
| 0 | 0 | 0  | 100%  | 100% |
| 0 | 1 | 1  | 1.0%  | 0.0% |
| 1 | 1 | 5  | 0.3%  | 0.0% |
| 2 | 1 | 9  | 0.3%  | 0.0% |
| 2 | 2 | 10 | 20.7% | 0.0% |

Auto-pass is chosen over a bare "assume humans deviate 2%" floor because it is a **real mechanic the
game already ships**, so the gate measures the actual product rather than an unverifiable claim
about human behaviour. The pure-greedy stall curve is still computed and reported as the known
worst case. Rationale for caring at all: a gate that cannot pass does not stay a gate — it gets
quietly relaxed by whoever is executing, and then nothing was gated.

**A2. Pool selection gains a third bar: a circulation/occupancy floor (~60% of seats able to act).**
The accepted rule — smallest pool that passes, fewest extra ranks then fewest jokers — selects
**k=0, j=1**, which is **one single card circulating among nine seats**. It passes both the stall
and the pacing bars while being barely a game. Time-to-first-completion provably cannot detect a
dead table; occupancy can, costs one counter, and selects k=2.

**A3. `seatCount` means SEATED SEEKERS, not match roster** (resolved from the design, not asked).
The hider does not play cards, and CLAUDE.md fixes the card table at 9 seat anchors against a
10-player cap. So `ranks = (players in round − 1) + k`. The research flagged this ambiguity as
shifting the chosen configuration by a full notch, so it is stated explicitly rather than left to
the executor.

**A4. k >= 1 is mandatory** (derived, not asked). At k=0 the CARD-12 blocker variant stalls ~97% at
N=10 while the wild variant is fine, so "both variants behind a flag from the start" would be false
at k=0 — the flag would be a cliff, not a flag. Combined with A2 this means the search starts at
k=1, and k=0 is retained only as a documented negative result.

**A5. Circulation is `4k + j` exactly**, which makes CARD-04's "the deck never runs dry" simply
`circulation >= 1`, and makes `k=0, j=0` a provable instant deadlock rather than an empirical one.

**A6. Rules 5 and 6 are enforced by nothing today.** Research ran a pure-zone fixture using
`coroutine.yield`, `coroutine.resume`, `os.clock` and `os.time` through `selene.pure.toml` and got
**0 errors** — `std = "luau"` permits all of them. No pure zone uses any of them today, so banning
them in `check-guards` R3 is zero-churn and makes Non-Negotiable Rules 5 and 6 actually enforced
instead of merely stated. This phase should do it.

**A7. (2026-11-03, owner) The engine gets an anti-livelock safety valve, and G1 no longer rests on an
assumption about how humans play.** This SUPERSEDES A1's mechanism, though not its reasoning.

Measured at N=10, k=2, j=1, 4,000 rounds per cell:

| deviation per pass | stall rate |
|--------------------|-----------|
| 0% (pure greedy)   | **0.25%** |
| 0.001%             | 0.20%     |
| 0.01%              | 0.05%     |
| 0.03%              | **0%**    |
| 0.1%               | 0%        |

The cliff is near **0.03%**, not the 2% research assumed — research only sampled 0% and 2%, so it
never saw where the edge actually is.

Why A1's auto-pass is not enough on its own: the firing rate is exactly the tail of the reaction-time
distribution past the deadline. At 1.0s that is 2.9%, at 1.5s 0.21%, at 3.0s 0.0003%. Only deadlines
around 1.0–1.5s clear the cliff, and **a 1.5-second pass deadline is not an AFK mechanic** — CARD-16
auto-passes an idle player *and benches them after repeated strikes*, so at that deadline it would be
striking ordinary players several times a round. At any deadline a real AFK feature would use, the
mechanism fires essentially never and the gate silently reduces to pure greedy, which livelocks.

**The valve:** the engine detects a repeated whole-table state with no completion since the previous
repeat, and forces one random pass. Zero-stall becomes a theorem about the engine instead of a claim
about players. It fires in roughly 0.25% of rounds and is invisible otherwise. The machinery already
exists in the plans — `Invariants.hash` and the simulator's cycle detection — so this largely moves
it from `scripts/sim/` into `src/server/engine/`.

**A7-CORRECTION (measured, same day).** A7 above claims zero-stall "becomes a theorem about the
engine". My own prototype of the valve falsifies that as an unconditional claim, so the weaker and
true version governs. Measured at N=10, 4,000 rounds per cell:

| pool | stall valve OFF | stall valve ON | rounds where valve fired | mean fires/round |
|------|-----------------|----------------|--------------------------|------------------|
| k=1, j=1 | 0.275% | **0.000%** | 0.28% | 0.004 |
| k=2, j=1 | 0.250% | **0.000%** | 0.25% | 0.005 |
| k=2, j=2 | 21.600% | 0.025% | **21.60%** | 0.415 |

1. **The valve works for good pools.** Both `j=1` configurations go to exactly 0 stalls in 4,000
   rounds while firing in only ~0.25% of them, so it is invisible in normal play.
2. **It is NOT an unconditional guarantee.** `k=2, j=2` with the valve ON still stalls 0.025%. That
   may be the prototype's 20,000-action cap binding rather than a true livelock, but the honest claim
   is "the valve eliminates observed stalls **for the selected pool**, demonstrated rather than
   assumed" — not "by construction, for every pool". The plans must not repeat the stronger claim.
3. **Valve firing rate is a much better pool discriminator than stall rate**, which is the real
   argument for making it a selection input. `k=2, j=2` is a bad pool that needs rescuing in 21.6% of
   rounds, yet its *stall* rate with the valve on (0.025%) would sail past a naive zero-stall bar.
   The firing rate screams. A hard bar of ~1% is proposed. Note also that `j=2` is dramatically worse
   than `j=1` at the same `k` — independent evidence for the "jokers present but few" reading.

**What this does to the gate.** G1's zero-stall bar is now carried by the valve rather than by player
behaviour, so the simulator's job changes: it must prove the valve FIRES when needed and that stalls are zero *with it enabled*, and it
must still report the pure-greedy and auto-pass curves as evidence about the margin. The valve's
firing rate becomes a first-class metric; a pool whose valve fires often is a bad pool even at zero
stalls.

**Auto-pass is retained as a real mechanic but demoted** from "the thing that makes G1 pass" to a
secondary mitigation, with its deadline free to take a realistic AFK value.

**AUTO_PASS_SELECTION must be recorded alongside the deadline.** Deviation comes from auto-pass
choosing a card the player would NOT have chosen. If Phase 4 ships the obvious "pass your worst card",
deviation is exactly zero and the simulator's result transfers nothing to the shipped game.

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
