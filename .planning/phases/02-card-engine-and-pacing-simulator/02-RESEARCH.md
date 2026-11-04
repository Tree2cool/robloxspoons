# Phase 2: Card Engine and Pacing Simulator - Research

**Researched:** 2026-11-03
**Domain:** Combinatorial game-state design, property-based testing, headless simulation. **Not** Roblox API.
**Confidence:** HIGH on solvability and invariants (derived + measured in this session). MEDIUM on pacing (measured, but the bot model is unvalidated against humans — V-35). HIGH on tooling budget (measured).

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Stall Definition and Pacing Targets**

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

**Bot Model**

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

**Card Pool and the G1 Search**

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

### Deferred Ideas (OUT OF SCOPE)

- AFK auto-pass (CARD-16) and the completion moment (CARD-17) are Phase 4 — they need a live table.
- Prediction and reconciliation (CARD-14) is Phase 4.
- The deal animation (CARD-18) is Phase 7, needing deck-skin content.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CARD-01 | Player holds 4 cards and can draw from their left pile only when their hand size is exactly 4 | §5 Hand-size invariant `|hand| ∈ {4,5}`; the "pile locks at 5" rule needs no lock state. Rejection code `HandNotFour`. |
| CARD-03 | A passed card arrives in the next seat's left pile, server resolving which seat at execution time | §6 `next` resolved at apply time; §7 removal relinks before the next apply. Rule 7 intent vocabulary in §9. |
| CARD-04 | The last seat's passes land beneath the dealer's deck, so the deck never runs dry | §4 **Circulation invariant**: `4k + j` cards circulate forever, provably constant. "Beneath" = FIFO tail. No last-seat branch exists. |
| CARD-05 | Dealer is previous round's first finder; collision → highest-placed seated finisher; round 1 random | §8 Dealer = head of the seat order, so CARD-05 collapses into CARD-06. Four unspecified cases listed. |
| CARD-06 | Seat order = finishers in find order, then the empty-handed seeker, then everyone else | §8 total-order function; the "exactly one empty-handed seeker" assumption breaks under churn and partial rounds. |
| CARD-07 | Four of a kind detected on draw, removes the player immediately | §3 proof that the completing rank is always **unique** for j ≤ 2, so no tiebreak is needed. |
| CARD-08 | A removed seat's cards route to the successor's left pile, never destroyed | §4 + §7. **Mutation-proven in this session**: destroying them makes the multiset unsatisfiable in 2.9–5.7% of rounds (§3.4). |
| CARD-09 | No opening hand already complete or completable by a held wild | §10 rejection sampling: mean 1.0–1.34 attempts, max 4 in 400. Needs a *rejection-fired* assertion or the check is vacuous. |
| CARD-10 | Jokers act as wilds; naturals spent before jokers on completion | §3.3 naturals-first is **provably solvability-optimal** (minimises both jokers consumed and cards stranded). For j ≤ 2 the only wild completions are 3+1 and 2+2; all-joker sets are unreachable. |
| CARD-11 | Headless pacing simulator proves solvability 3–10 and selects pool + joker count | §2, §3, §11. Measured across ~230,000 rounds. Selection-rule conflict flagged in §12. |
| CARD-12 | Jokers revert to blockers if solvability cannot be proven | §3.5 blocker mode is **not safely interchangeable** at every pool: at k=0 it stalls up to 97.4% where wild mode stalls 0%. The flag must be safe in both positions. |
</phase_requirements>

---

## 1. Verification Debt Re-check (mandatory first action)

**Host reachability re-tested in this session** (`curl --max-time 6`, HTTP code shown):

| Host | Result |
|------|--------|
| `create.roblox.com` | `000` (DNS/connect failure) |
| `devforum.roblox.com` | `000` |
| `robloxapi.github.io` | `000` |

`[VERIFIED: direct curl, 2026-11-03]` **The verification debt STANDS. No Roblox platform claim is upgraded in this phase.** `madstudioroblox.github.io` and `jsdotlua.github.io` were not retested (neither is relevant to a phase with no Roblox API surface).

### V-15 — single-threaded atomicity of non-yielding handlers; replication scope

**The orchestrator's assessment is CORRECT, and incomplete in a way that is worth acting on now.**

Correct part: V-15 does not block Phase 2. The engine references no Roblox API (Rule 2, lint-enforced by `selene --config selene.pure.toml` + `luau-lsp --platform standard`, `[CITED: tests/purity/purity.spec.luau]`), so there is no handler, no `RemoteEvent`, no Instance and no replication in scope. `apply` is synchronous by construction and runs under Lune, a single-threaded interpreter with no preemption. V-15 becomes load-bearing in Phase 4, when real `OnServerEvent` handlers drive the engine and the question "can two handlers interleave inside one mutation?" has consequences.

The gap: **Rule 6 ("no yields inside state mutations") is currently enforced by nothing.** Verified in this session:

```
# a pure-zone fixture using coroutine.yield, coroutine.resume, os.clock and os.time
$ selene --config selene.pure.toml <fixture>
Results: 0 errors, 0 warnings, 0 parse errors
```

`[VERIFIED: ran selene 0.32.0 with the repo's own selene.pure.toml against a crafted fixture]`

`selene.pure.toml` sets `std = "luau"` `[CITED: selene.pure.toml]`, and `coroutine.*` and `os.*` are standard Luau — so an engine module can yield, and can read a real clock, while every one of Phase 1's 14 gates stays green. `src/server/engine`, `src/server/core` and `src/shared/Net` contain **no** `os.`, `coroutine`, `task.`, `:Wait()` or `spawn(` today `[VERIFIED: grep across all three pure zones]`, so the guard can be added with zero churn.

**Recommendation (cheap now, expensive later):** Phase 2 extends `scripts/ci/check-guards.luau` R3's `BANNED_CONSTRUCTS` for pure zones with `coroutine` and `os.` (both already have the machinery — see `BANNED_CONSTRUCTS` and the `rawget(_G` needle loop at `scripts/ci/check-guards.luau:380-397`). This makes Rules 5 and 6 structurally enforced, mutation-proven with a fixture under `tests/purity/fixtures/`, and **retires the engine's half of V-15 permanently** — the engine cannot yield, therefore handler interleaving cannot corrupt it, regardless of what the platform does.

### V-35 — does a simulated bot's reaction-time distribution represent humans?

**The CONTEXT's handling (a stated range plus a zero-latency mode) is sound but does not go far enough, because this session found that the gate's verdict is dominated by a *different* bot parameter than reaction time.**

What is unverifiable: reaction time, yes (needs P4/P6 playtests). What this session measured: reaction time barely matters to the verdict, and **the greedy-purity parameter matters totally** (§3.6). At perfectly deterministic greed the stall rate is 1–45% for every pool in the grid; at a 2% rate of "passed a random card instead of the greedy one" it is exactly 0% for every pool in the grid. Nothing in between was observed.

**What this means for how much of G1 can be trusted:**

| G1 half | Trust | Why |
|---------|-------|-----|
| **SOLVABILITY** | **HIGH — and it does not actually depend on the bot model at all.** | §3.1 proves by counting that the remaining-multiset predicate can never become unsatisfiable for any pool with `ranks ≥ seats`. The simulation confirms it (0 unsatisfiable events in ~230,000 rounds). This half is a theorem the simulator *re-checks*, not a question the simulator *answers*. |
| **PACING** | **LOW-MEDIUM, and it is measuring the bot, not the game.** | Measured medians are 4.9–13.3s against a 45s bar — a 4x margin that no plausible reaction-time error closes (the bar is only breached if human per-action time is ~4x the modelled 450ms median). But the *stall* number, which is the thing G1 gates on, is a step function of a bot behaviour no playtest has measured. |

V-35 is therefore **not upgraded**, and a second unverifiable parameter (greedy purity) is added to it. See §12 OQ-A for the consequence.

---

## 2. Summary

The phase's hard question — "can a shrinking circle become unsolvable?" — has an exact answer that does not need simulation, and this session derived and then empirically confirmed it. Two conserved quantities do all the work. **Circulation** (`Σ|inbox| + Σ(|hand|−4)`) equals `4k + j` and is *invariant across completions*, so the ring's liveness never degrades as it shrinks; it only grows when a seat leaves without completing. **Rank budget**: every completion destroys cards of exactly one natural rank plus jokers, so after `c` completions at least `R − c` ranks remain fully intact — and since the round needs only `m₀ − 1` completions out of `R ≥ m₀` ranks, a fully intact rank is always available. Structural unsatisfiability is therefore **unreachable** while Rule 8 holds, and the "no seat can ever reach four of a kind" predicate is best understood not as a gate criterion but as **the assertion that proves Rule 8 is being honoured** — deliberately violating Rule 8 in this session made it fire in 2.9–5.7% of rounds, which is the mutation proof the house standard requires.

What *does* fail is not impossibility but **greedy-hoarding livelock**: every seat holds a split pair, the circulating cards are ones nobody wants, and the state cycles forever. Under strictly deterministic greedy play this happens in 1–45% of rounds across every pool in the searched grid, in both wild and blocker mode. Inject a 2% chance that a seat passes a random card instead of its greedy choice and the stall rate is **exactly zero in all 256 configuration cells tested (76,800 rounds)**. The gate as literally specified — zero stalls on the all-greedy population — therefore has **no passing configuration**, and the fallback does not rescue it because blockers livelock too. This must be resolved before the gate is implemented, not discovered when it fails.

Two further findings change what the gate should select. First, the locked selection rule ("fewest extra ranks first, then fewest jokers") picks `k=0, j=1` — a pool whose entire circulating supply is **one card**, giving a seat something to do only 14% of the time at N=10 while passing both stated pacing bars comfortably. Time-to-first-completion cannot see a dead table; an occupancy metric can, and it is cheap to add. Second, `k=0, j=0` is a provable instant deadlock (zero circulation), and at `k=0` the wild/blocker flag is not a flag but a cliff: 0% stalls as wilds, up to 97.4% as blockers. A fallback that is only safe in one flag position is not a fallback.

**Primary recommendation:** Build the engine around the two conserved quantities as O(1) assertions checked after every single action, treat the multiset predicate as a Rule-8 tripwire rather than a gate criterion, and before implementing G1, resolve (a) the all-greedy livelock so the gate has a passing configuration, (b) the `seatCount` ambiguity in `ranks = seatCount + k`, and (c) whether the selection rule may legally return `j=0` and delete the jokers the design wants. Everything else in the phase is mechanical and the measured CI budget has room: full per-action identity checking runs at 343,000 actions/s, so the 100k-action fuzz suite costs ~0.3s and the locked 500×8 CI subset ~2.1s.

---

## 3. The Solvability Question (core intellectual content)

Notation, fixed for the rest of this document:

| Symbol | Meaning |
|--------|---------|
| `N` | players in the match (3..10) |
| `m₀` | seats at the card table at round start = `N − 1` (the hider is away) |
| `m` | live seats now |
| `spoons` | `N − 2`, so **required completions = `m₀ − 1` = `N − 2`**, leaving exactly one empty-handed seeker |
| `R` | distinct ranks in the pool, 4 cards each |
| `j` | jokers in the pool |
| `k` | `R − seatCount` (see §12 OQ-B: `seatCount` is ambiguous) |
| `n_r` | copies of rank `r` still in play |
| `J` | jokers still in play |
| `T` | `4R + j`, total cards ever in play |

### 3.1 Theorem: the remaining multiset can never become unsatisfiable

**Satisfiability predicate.** A seat can reach four of a kind iff some rank can still be assembled:

```
satisfiable  ⟺  ∃ r :  n_r ≥ 1  ∧  n_r + J ≥ 4          (wild mode)
satisfiable  ⟺  ∃ r :  n_r = 4                           (blocker mode)
```

**Claim 1 — every completion damages exactly one rank.** The four cards that leave are `a` naturals of a single rank `r` plus `b = 4 − a` jokers. No other rank loses a card. So `n_r` drops from 4 to `4 − a ∈ {0,1,2}` and `J` drops by `b`.

**Claim 2 — intact ranks outlast the demand.** All `R` ranks start intact (`n_r = 4`; nothing has left play at the deal, wherever the cards sit). By Claim 1, after `c` completions `#{r : n_r = 4} ≥ R − c`. The round demands `c ≤ m₀ − 1` completions. Any pool with `R ≥ m₀` therefore always has at least `R − (m₀ − 1) ≥ 1` fully intact rank available when the last required completion is due.

**Claim 3 — an intact rank is gatherable.** A seat's hand holds 4 cards plus one transient 5th, which is exactly the capacity needed to hold four of a rank. Cards travel forward around the ring one seat per pass. Liveness holds whenever circulation ≥ 1: a seat holding 5 can always pass, and a seat holding 4 with a non-empty inbox can always draw, so a legal action always exists. Under cooperative passing the four cards of an intact rank can therefore be routed to any chosen seat.

**Conclusion.** For any pool with `R ≥ m₀` and circulation ≥ 1, **`satisfiable` is an invariant, not a condition**. `[VERIFIED: derived here, then confirmed empirically — 0 unsatisfiable events in ~230,000 simulated rounds across 18 pool configurations × N=3..10, both joker modes, with and without churn]`

Corollary: `k = 0, j = 0` (under the "seatCount = seats" reading) gives circulation `= 0` and is a **provable instant deadlock** — every seat holds exactly 4, no inbox is ever non-empty, no draw is ever legal, and four-of-a-kind is only checked on draw. Measured: 100% stall at every N from 3 to 10 `[VERIFIED: spike, 4,000 rounds]`. That cell must be excluded from the sweep by an asserting test, never by a silent skip.

### 3.2 Predicate cost: O(1)

Keep a 5-entry histogram `cnt[0..4]` of how many ranks have exactly that many copies in play, plus `J`:

```
satisfiable  ⟺  Σ_{a = max(1, 4−J)}^{4} cnt[a] > 0
```

A completion touches one rank (one decrement and one increment in `cnt`) and `J`. Evaluation is a fixed 4-term sum. **O(1) update, O(1) query — not O(n), not a search.** The planner can assert it after every fuzzed action for free.

### 3.3 CARD-10: "spend naturals first" is provably the optimal rule

For `j ≤ 2`, a 5-card hand can hold at most 2 jokers, so the only possible wild completions are `3 naturals + 1 joker` and `2 naturals + 2 jokers`:

| Choice | Cards of `r` stranded | Jokers removed | Verdict |
|--------|----------------------|----------------|---------|
| 4 naturals | 0 | 0 | best; always taken when available |
| 3 naturals + 1 joker | 1 | 1 | naturals-first picks this |
| 2 naturals + 2 jokers | 2 | 2 | strictly worse on both axes |

Naturals-first **simultaneously minimises stranding and joker consumption**, so Phase 1's spec-lock decision is also the solvability-optimal one. Two further consequences:

- **The all-joker set is unreachable for `j ≤ 2`.** Open Question 2's "or all four are jokers?" sub-case cannot arise anywhere in the searched grid. The CARD-10 spec needs rules only for `a ∈ {2,3,4}`. If a future pool ever sets `j ≥ 3` this reopens — worth a comment in the config, and an assertion that `j ≤ 2`.
- **The completing rank is always unique.** No 5-card hand can satisfy two ranks at once for `j ≤ 2` (4+4 needs 8 cards; 3+1j and 3+1j needs 6; 2+2j and anything leaves the other at ≤ 3). So completion needs **no tiebreak**, and a test should assert uniqueness rather than assuming an arbitrary pick is safe.
- **Total stranded cards per round ≤ j ≤ 2.** Each joker completion consumes at least one joker, so at most 2 can ever occur. Joker-induced dilution of the circulating pool is bounded by 2 cards — negligible against circulation `4k + j` whenever `k ≥ 1`, and total when `k = 0, j = 2`.

### 3.4 Mutation proof: the predicate CAN fire, and fires exactly on a Rule 8 violation

The house standard requires every new check be deliberately broken to confirm it can fail. Run with the removed seat's cards **destroyed** instead of routed to the successor (the exact violation Rule 8 forbids), one churn leaver per round, 1,600 rounds per cell:

| k | j | Rule 8 honoured | UNSATISFIABLE fired | Round failed to clear all spoons |
|---|---|-----------------|---------------------|----------------------------------|
| 1 | 0 | yes | 0.0% | 0.0% |
| 1 | 2 | yes | 0.0% | 0.0% |
| 2 | 0 | yes | 0.0% | 0.0% |
| 2 | 2 | yes | 0.0% | 0.0% |
| 1 | 0 | **no (destroyed)** | **5.7%** | 0.0% |
| 1 | 2 | **no (destroyed)** | **2.9%** | 0.0% |
| 2 | 0 | **no (destroyed)** | **5.2%** | 0.0% |
| 2 | 2 | **no (destroyed)** | **3.2%** | 0.0% |

`[VERIFIED: spike run this session, 12,800 rounds]`

This is the test to write. Because the statistical version only fires in 3–6% of rounds, pair it with a **deterministic fixture**: construct a state where exactly one rank is still intact and all four of its copies sit in one seat's hand and inbox, remove that seat with destruction enabled, and assert `UNSATISFIABLE` fires on that single action. Then the check is proven capable of failing without needing hundreds of rounds.

Note also what the table says about churn itself: with Rule 8 honoured, **a random leaver every round caused zero failures** — churn is solvability-safe and pacing-safe, because (§4) a non-completing removal *increases* circulation by 4.

### 3.5 Where wild and blocker modes actually diverge: the k=0 cell

500 rounds per cell, noise 0.05, 300s cap:

| k | j | mode | N=3 | N=4 | N=5 | N=6 | N=7 | N=8 | N=9 | N=10 | medFirst | p95First |
|---|---|------|-----|-----|-----|-----|-----|-----|-----|------|----------|----------|
| 0 | 0 | wild | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | — | — |
| 0 | 1 | wild | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 11.4s | 48.3s |
| 0 | 2 | wild | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 0% | 5.4s | 24.5s |
| 0 | 0 | blocker | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | — | — |
| 0 | 1 | blocker | 2.8% | 10.2% | 17.8% | 39.8% | **64.0%** | **80.6%** | **93.4%** | **97.4%** | 101.1s | 253.5s |
| 0 | 2 | blocker | 0.4% | 1.2% | 2.2% | 9.2% | 16.4% | 35.2% | 53.0% | **73.8%** | 61.9s | 177.8s |

`[VERIFIED: spike, 8,000 rounds]`

At `k = 0` the jokers *are* the entire circulating supply. As wilds they are the most useful cards in the game; as blockers they are dead weight and nothing can ever be assembled. **Consequence for CARD-12: the wild/blocker switch is not a free flag.** If the gate selects a pool that only works with wilds, flipping the flag later ships a game that stalls 97% of rounds at 10 players. The selection rule must therefore read "the smallest pool that passes **in both joker modes**", or CARD-12 must be struck as a live fallback and demoted to a test-only variant. This is a material finding for the plan — it is exactly the kind of thing "both variants available behind a flag from the start" is supposed to guarantee and currently does not.

For `k ≥ 1` both modes pass: at noise 0.05, 1,000 rounds per (cell, N), 18 cells × 8 N = **144,000 rounds, 0 stalls, 0 unsatisfiable events**.

| mode | k | j | worst stall over N | medFirst | p95First | medAll | p95All |
|------|---|---|-------------------|----------|----------|--------|--------|
| wild | 1 | 0 | 0.00% | 7.7s | 19.4s | 13.9s | 35.2s |
| wild | 1 | 1 | 0.00% | 6.5s | 16.7s | 13.4s | 31.8s |
| wild | 1 | 2 | 0.00% | 4.9s | 14.4s | 13.4s | 29.9s |
| wild | 2 | 0 | 0.00% | 9.5s | 17.5s | 16.7s | 33.0s |
| wild | 2 | 2 | 0.00% | 6.3s | 15.4s | 17.0s | 33.4s |
| wild | 3 | 2 | 0.00% | 7.6s | 17.6s | 21.1s | 40.2s |
| blocker | 1 | 0 | 0.00% | 7.5s | 19.6s | 13.7s | 35.6s |
| blocker | 1 | 2 | 0.00% | 10.0s | 22.5s | 18.6s | 42.9s |
| blocker | 2 | 2 | 0.00% | 11.3s | 21.3s | 21.0s | 40.2s |
| blocker | 3 | 2 | 0.00% | 13.3s | 23.9s | 25.4s | 46.2s |

`[VERIFIED: spike, 144,000 rounds]` Read the two modes against each other: **adding jokers as wilds speeds the round up** (`k=1`: 7.7s → 4.9s as j goes 0 → 2) and **adding them as blockers slows it down** (7.5s → 10.0s). Wilds are strictly better for pacing and, per §3.1, carry no solvability cost. The design intent behind jokers is sound; the risk the project feared is not where it was expected to be.

### 3.6 The real failure mode: greedy-hoarding livelock, and its cliff

The structural question being closed means the stall question is entirely about the *passing policy*. Pure greedy — keep the largest group, pass from the smallest, ties by card id — livelocks: every seat ends up holding a split pair, the circulating cards belong to ranks nobody is collecting, and the whole state repeats.

Because pure greedy with a strict round-robin schedule is *fully deterministic*, a livelock is literally a cycle in the state graph, and it can be **detected exactly** by hashing the state (cursor + per-seat sorted hand + per-seat inbox in FIFO order) and watching for a repeat. No timeout needed. Measured under that regime, 60 rounds per cell:

| pool | N=3 | N=5 | N=7 | N=10 |
|------|-----|-----|-----|------|
| k=0 j=0 wild | 100% | 100% | 100% | 100% |
| k=1 j=0 wild | 18% | 42% | 32% | 55% |
| k=2 j=2 wild | 2% | 5% | 15% | 22% |
| k=1 j=0 blocker | 3% | 25% | 32% | 58% |

`[VERIFIED: spike, cycle detection, ~5,800 rounds]` Then the decisive experiment — stall rate against a single bot-model parameter, `noise` = P(this seat passes a uniformly random card instead of its greedy choice), under the lognormal schedule, 300 rounds per (cell, N), 32 cells:

| noise | random tie-break | worst stall rate over k∈{1,2}, j∈{0,2}, N=3..10 |
|-------|------------------|--------------------------------------------------|
| 0.00 | no | **44.7%** |
| 0.00 | yes | **26.3%** |
| **0.02** | no | **0.0%** |
| **0.02** | yes | **0.0%** |
| 0.05 | either | 0.0% |
| 0.10 | either | 0.0% |
| 0.25 | either | 0.0% |

`[VERIFIED: spike, 76,800 rounds; 0 stalls in every one of the 256 cells at noise ≥ 0.02]`

Three things follow, and they are the most consequential findings in this document.

1. **The gate as specified has no passing configuration.** "Gate on the all-greedy population" with zero stalls is unachievable at any `(k, j)` in the grid, in either joker mode. The fallback does not help — blockers livelock at a similar rate. A gate that cannot pass will be "fixed" under deadline pressure by whoever is executing, which is the worst possible time to redefine a safety criterion. Resolve it in the plan (§12 OQ-A).
2. **Randomising the tie-break is not the fix.** Random tie-breaks only cut 44.7% to 26.3%. The cycle is created by the strict "never pass from your largest group" rule, not by tie ordering. So CONTEXT's locked "ties broken by card id so runs are deterministic" is fine and should be kept; the parameter to add is target-abandonment, not tie noise.
3. **Pool size is a second-order lever here.** Going from k=1 to k=2 roughly halves the pure-greedy stall rate but never reaches zero. If the gate's purpose is to pick a pool, a criterion that is 20x more sensitive to the bot model than to the pool cannot do that job.

A real-game note that belongs in the plan rather than the gate: the live game already has a livelock breaker in **AFK auto-pass (CARD-16, Phase 4)**, which by definition passes a card the player did not greedily choose. If auto-pass is modelled, the all-greedy population self-heals. That is the honest way to argue the live game is safe, and it is a Phase 4 dependency the Phase 2 gate should name explicitly rather than assume.

### 3.7 The metric the stated pacing bars cannot see

Median time-to-first-completion is blind to a table where nobody has anything to do. **Circulation is `4k + j` and does not scale with seat count** (§4), so the fraction of seats holding a legal action falls as N grows. Measured: fraction of live seats with a legal action (hand of 5, or non-empty inbox), sampled at every action instant, noise 0.05, wild:

| k | j | circulation | N=3 | N=5 | N=7 | N=9 | N=10 |
|---|---|-------------|-----|-----|-----|-----|------|
| 0 | 1 | 1 | 50% | 30% | 21% | 16% | **14%** |
| 0 | 2 | 2 | 67% | 54% | 39% | 30% | 27% |
| 1 | 0 | 4 | 80% | 71% | 60% | 49% | 45% |
| 1 | 2 | 6 | 74% | 74% | 70% | 62% | 59% |
| 2 | 0 | 8 | 85% | 77% | 72% | 69% | 67% |
| 2 | 2 | 10 | 80% | 77% | 74% | 71% | **70%** |
| 3 | 2 | 14 | 84% | 78% | 76% | 74% | 74% |

`[VERIFIED: spike, 10,560 rounds]`

The locked selection rule — fewest extra ranks first, then fewest jokers — selects `k=0, j=1`: **circulation of one card**, a 14% occupancy table at 10 players, and it passes both stated bars (median 11.4s ≤ 45s, p95 48.3s ≤ 120s). Nine players would spend 86% of the card phase holding a locked hand watching a single token crawl round the ring. That directly contradicts PROJECT.md's "passing is real-time and simultaneous" and the core value of a "frantic card scramble".

**Recommendation:** add an occupancy floor to G1's pacing half — **≥ 60% mean occupancy at every N from 3 to 10** — which is cheap to compute (one counter per action instant) and selects `k = 2`. State it as a third bar alongside the median and p95 so the gate's selection rule has something to bite on. Note `k = 2` is also the cell where both joker modes are comfortably safe (§3.5), so one choice settles two risks.

### 3.8 Start-up ramp: time-to-first-completion is ramp-dominated

At the deal, all `4k + j` circulating cards sit in the dealer's inbox and every other inbox is empty, so only the dealer can act. The wave advances one seat per draw+pass pair, ≈ 2 × 450ms ≈ 0.9s per seat. Predicted and confirmed: medFirst rises almost perfectly linearly in N, **+0.87s per added player** at k=1,j=0 (3.5s at N=3 → 9.6s at N=10) and +0.77s/player at k=2 `[VERIFIED: derived, then matched against the measured pacing table]`.

So at 10 players roughly 8 of the ~9.6s median is propagation, not card luck. Implications: (a) the 45s bar has a 4x margin that is structurally safe, not luck; (b) a bigger pool does **not** fix a slow start, because the ramp is set by seat count; (c) Phase 4 needs a "waiting for cards" affordance for far seats during the first ~8 seconds or the UI will look broken on its first impression. Worth recording as a cross-phase note.

---

## 4. Conservation and the Invariant (how to assert it cheaply)

Two conserved quantities, both O(1) to maintain and both checkable after **every single action**.

### 4.1 Circulation (the strong form)

```
circulation  :=  Σ_seats |inbox|  +  Σ_seats (|hand| − 4)
```

Behaviour under every operation — derived, then confirmed by running it:

| Operation | Effect on circulation |
|-----------|----------------------|
| draw (inbox → hand) | 0 (inbox −1, hand surplus +1) |
| pass (hand → next.inbox) | 0 (hand surplus −1, inbox +1) |
| **completion** (4 retired, 5th + inbox → successor) | **0** |
| **churn removal** (hand + inbox → successor, nothing retired) | **+4** |

Therefore:

```
circulation  ==  4·(R − m₀) + j  +  4·(churn removals so far)
```

**This is the invariant to assert.** It is stronger and cheaper than "hands plus piles equals initial minus four per completion": it is exactly constant between removals, it accounts for the transient 5th card instead of special-casing it, and the fact that **completions do not change it** is the formal statement of why a shrinking circle stays live. It also makes two design truths falsifiable rather than asserted: CARD-04's "the deck never runs dry" is just `circulation ≥ 1` forever, and Rule 8's "churn makes the table looser, never tighter" is the `+4`.

### 4.2 Partition identity (catches what counters cannot)

Every card ID belongs to exactly one of four buckets:

```
hands  ⊎  inboxes  ⊎  retired (completed sets)  ⊎  terminal (held by the last seat when the ring empties)
       with  |hands| + |inboxes| + |retired| + |terminal|  ==  T  ==  4R + j
```

A counter-sum check catches loss and duplication-by-addition. It does **not** catch a swap bug that replaces card X with a second copy of Y. For that, scan all buckets into a scratch table and assert every ID appears exactly once. Measured cost: a full per-action identity scan runs at **343,502 actions/s** vs **595,017 actions/s** for counters alone — only 1.7x slower `[VERIFIED: benchmarked in Lune 0.11.1 this session]`. At that price, **run the full identity check after every action in the 100k fuzz suite** (≈0.3s) and keep counters-only for the big sweeps. No tiering gymnastics needed.

The `terminal` bucket exists because of a real edge case — see §7.3.

---

## 5. Hand-size and liveness invariants (CARD-01)

| Invariant | Statement | Why it is the right form |
|-----------|-----------|--------------------------|
| Hand size | `∀ live seat: |hand| ∈ {4, 5}` | "The pile locks at 5" needs **no lock flag**; it is just `draw requires |hand| == 4`. A boolean `locked` field would be a second source of truth that can disagree. |
| No silent hand growth | a seat's hand changes **only** by its own draw or its own pass | Seat removal routes to the successor's **inbox**, never a hand. This is what makes "four of a kind is checked only on draw" sound — assert it, don't assume it. |
| Liveness | `circulation ≥ 1 ⟹ some live seat has a legal action` | A seat at 5 can always pass; a seat at 4 with a non-empty inbox can always draw. If the fuzzer ever finds no legal action with circulation ≥ 1, the ring is corrupt. |
| Single writer | a seat's inbox is written only by its `prev` (pass) or by the removal operation | Two writers exist, so their **ordering** must be defined — see §7.4. |

---

## 6. Ring representation (CARD-03, CARD-04)

A circular doubly-linked list over a fixed seat array, `next`/`prev` as indices (not references) so a state hash and a deep-equal are trivial and no GC cycle exists.

- `next` is resolved **at apply time**, never carried in the intent (Rule 7). A pass whose target left between intent and execution lands in the departed seat's successor with no special handling.
- **No last-seat branch exists.** Seat `m`'s `next` is the dealer, so "passes land beneath the dealer's deck" is just "append to the dealer's inbox tail". The test that proves there is no hidden branch is to run the whole suite at `m = 2`, where the dealer is simultaneously the only `prev` and the only `next`.
- The dealer's inbox **is** the deck; it needs no separate field and no "deck empty" path.

---

## 7. Seat Removal (Rule 8) — one operation, and its edge cases

One function, `removeSeat(state, seatId, cause)` where `cause ∈ {Completed, Disconnected, Benched}`. Only `Completed` retires four cards; every cause routes the rest identically. The causes must not fork the routing, or Rule 8 holds in one path and not another.

### 7.1 Ring shrinking to 2

`A.next == A.prev == B`. Unlink must be written so that relinking a 2-ring is not a special case: `seats[A.prev].next = A.next` and `seats[A.next].prev = A.prev` both reduce to `B.next = B; B.prev = B`. Correct, but it is the case a naive implementation breaks. Required tests: a full round at `m₀ = 2` (which is N=3, the minimum roster, so it is a shipping configuration not a curiosity); removal of each of the two seats; and a pass in a 2-ring landing in the other seat's inbox tail.

### 7.2 Ring shrinking to 1

`next == prev == self`. **Passing appends to your own inbox and drawing pops your own inbox** — self-consistent, still live, and the invariants hold unchanged. The sole remaining seat is the empty-handed seeker and may legitimately keep playing: PROJECT.md awards a four-of-a-kind bonus with zero find points to a seeker who completes but finds no spoon (Phase 5 criterion 3). So a 1-seat ring must be playable, not merely non-crashing.

### 7.3 The sole seat completes — the ring empties

This is where Rule 8 collides with itself: the 5th card and the inbox must go to "the successor", and there is no successor. Routing them to `self` would resurrect a dead seat. **Specify it explicitly:** the ring becomes empty and those cards move to a `terminal` bucket that the partition identity (§4.2) counts. "Never destroyed" then stays literally assertable — no card ever vanishes, it is accounted for — and the engine has no nil-successor path. Test: complete with `m == 1` and assert (a) the ring is empty, (b) no error, (c) the partition still sums to `T`, (d) every card ID is still accounted for exactly once.

### 7.4 Ordering of the dumped cards

PROJECT.md says "the fifth card and the seat's left pile pass on" without fixing the order. It must be fixed, because it determines the successor's draw order and therefore replay determinism. **Recommended: the departing hand first, then the departing inbox in FIFO order**, which preserves the global chain order (inbox cards arrived from upstream after the hand was assembled). Either choice is defensible; what is not defensible is leaving it implicit. Lock it with a test asserting the exact resulting inbox sequence.

### 7.5 Removing the dealer

No special case: the deck is just the dealer's inbox, so it routes to the successor like any pile, and the successor becomes the de-facto deck holder. Worth an explicit test precisely because it *looks* like it should be special — CLAUDE.md's claim "the wrap needs no special case" is only true if this test passes.

### 7.6 Mid-pass departure, both ends

- Target leaves between intent and execution → `next` is re-resolved; the card lands downstream. No rejection.
- **Actor** leaves between intent and execution → the intent must be rejected with `SeatNotLive`, not applied to a dead seat.
- The named card is no longer in the actor's hand (auto-passed first) → rejected with `NotYourCard`.

### 7.7 Churn makes the table looser, and introduces a second failure class

Circulation gains 4 per churn removal (§4.1), so churn cannot tighten the ring. But spoons are fixed at round start (MATCH-10) while seats are not, so **if live seats drop below remaining spoons, some spoons can never be claimed** — each seat can claim at most one. That round rides to the 300s cap through no fault of the engine or the pool.

**This must be its own category in the stall taxonomy** (`RosterShortfall`), or the churn variant will report false G1 failures and the gate will be tuned against a Phase 6 lifecycle matter. Recommended taxonomy, mutually exclusive, recorded per round with the reproducing seed:

| Outcome | Meaning | Owner |
|---------|---------|-------|
| `Cleared` | all remaining spoons claimed before the cap | — |
| `Unsatisfiable` | §3.1 predicate fired | **engine bug (Rule 8 violation)** |
| `Livelock` | deterministic mode: state cycle detected | bot model / pool |
| `CapReached` | 300s cap, completions possible but not achieved | bot model / pool |
| `RosterShortfall` | live seats < remaining spoons | Phase 6 lifecycle, **not a stall** |
| `DeadPool` | circulation == 0 at the deal | pool config is invalid |

Note this also closes a gap in the locked stall definition. "A round that hits the 300s cap with **zero** completions" does not catch the realistic failure — 6 of 8 spoons claimed and then a livelock — and the multiset clause does not catch it either, because the multiset is still satisfiable (§3.1). `CapReached` as defined above catches it. This is a refinement inside "the precise structural-deadlock predicate", which CONTEXT.md assigns to Claude's discretion, not a change to the locked definition.

---

## 8. Dealer and Seat Order (CARD-05, CARD-06)

### 8.1 The two requirements collapse into one function

Seat order (CARD-06) ranks seekers: finishers in find order, then the empty-handed seeker, then everyone else. The dealer rule (CARD-05) picks the previous round's first finder, falling through to the highest-placed finisher *actually seated*. The hider is not seated, so the highest-placed seated finisher **is** the head of the seat order. Therefore:

> **`dealer == seatOrder[1]`, always.**

One pure function, `nextSeatOrder(previousFindOrder, roster, hiderId, rng) -> { playerId }`, and the dealer is its head. Two rules implemented once cannot disagree. Round 1 is the same function with an empty find order and a seeded shuffle.

### 8.2 Cases CARD-05 and CARD-06 do not currently specify

| Case | Reachable when | Recommended resolution |
|------|----------------|----------------------|
| First finder is the hider | normal rotation | Locked already: next highest-placed **seated** finisher = `seatOrder[1]`. Needs a test. |
| **Zero finishers last round** | exactly the stall case the simulator hunts, and any round that hits the cap early | There is no find order at all. `seatOrder[1]` becomes the head of "everyone else", which needs a defined order (below). Flag: the dealer rule is silent here. |
| **More than one empty-handed seeker** | any round ending at the cap, or any round with churn | CARD-06 says "the empty-handed seeker", singular — true only in a clean round where `N−2` of `N−1` seekers finish. Needs a total order over non-finishers. |
| No previous finisher is still in the server | mass leave between rounds | Must fall through to "everyone else" and still produce a dealer. A nil dealer is a crash. |
| Find order contains a player who has since left | normal churn | Filter against the live roster **before** taking the head, not after. |

**Recommended total order** (extends SUMMARY.md Open Question 6's default, which the ROADMAP marks as resolved in this phase): finishers by find order → non-finishers by previous seat index (stable, so last round's position is preserved) → previous hider → joiners by join order → final tiebreak `userId` ascending. Fully deterministic, no RNG after round 1, and it produces a dealer in every case above.

### 8.3 Testability note

`nextSeatOrder` is pure and takes no clock, so it is exhaustively testable: a table-driven corpus of (previous find order, roster delta, hider) → expected order. That corpus is the right home for all five rows above, each asserting the specific reason it is ordered that way, per the house standard.

---

## 9. Engine API shape (Claude's discretion, Rules 2/6/7)

Recommended shape, and the reasons that make it non-arbitrary:

```
-- EngineConfig is a VALUE, never a module constant (CONTEXT, locked)
type JokerMode = "Wild" | "Blocker"
type EngineConfig = { ranks: number, jokers: number, jokerMode: JokerMode, allowAllJokerSet: boolean }

type Intent =
    | { kind: "Draw", seat: SeatId }
    | { kind: "Pass", seat: SeatId, cardId: CardId }     -- card ID only; never a target, never a hand index (Rule 7)
    | { kind: "Remove", seat: SeatId, cause: RemoveCause }

type Reject = "SeatNotLive" | "NotYourCard" | "HandNotFour" | "HandNotFive" | "InboxEmpty" | "UnknownSeat" | "UnknownCard"

type Event =
    | { kind: "Drew", seat: SeatId, cardId: CardId }
    | { kind: "Passed", seat: SeatId, to: SeatId, cardId: CardId }
    | { kind: "Completed", seat: SeatId, rank: Rank, retired: { CardId }, fifth: CardId? }
    | { kind: "SeatRemoved", seat: SeatId, cause: RemoveCause, routedTo: SeatId?, cards: number }

apply(state, intent) -> (ok: boolean, events: { Event }, reject: Reject?)
```

Four properties worth calling out:

1. **Events are returned, never published from inside the mutation** (Rule 6). `apply` takes no callbacks. This is what makes the no-yield guarantee structural rather than a convention — there is no place a handler could run mid-mutation.
2. **Every rejection carries its own code**, matching the Phase 1 pattern (`Admission.Reason`, `Validate`'s codes) and the house standard that tests assert the reason. A boolean return would make six distinct bugs indistinguishable.
3. **Card IDs should be the shuffled deck positions, so the ID↔rank mapping is re-randomised every round.** Free to implement, and it means a card ID carries no rank information even if one leaks — defence in depth for Rule 3 and for Phase 4's CARD-13 (pile depths only).
4. **`Remove` is one intent with a cause**, not three operations (Rule 8). Phase 4's AFK bench and Phase 5's completion both route through it.

Module split (all under `src/server/engine/`, all pure): `Pool` (build + shuffle + deal with CARD-09 rejection), `Ring` (seats, next/prev, removal), `Hand` (grouping, completion detection, naturals-first selection), `Engine` (`apply`, events, invariant counters), `SeatOrder` (§8), `Invariants` (circulation + partition, exported so both the fuzz suite and the simulator assert the same thing).

---

## 10. CARD-09: the deal, and why rejection sampling needs a *rejection-fired* assertion

Rejection sampling (re-shuffle whole deals until no opening hand is complete or wild-completable) is unbiased and cheap. Measured attempts until a legal deal, 400 trials per cell:

| worst cell | mean attempts | max attempts seen |
|------------|---------------|-------------------|
| N=3, j=2, R=2 (tightest) | 1.34 | 4 |
| N=3, j=2, R=3 | 1.13 | 4 |
| N≥6, any j | 1.00–1.07 | 2–3 |

`[VERIFIED: spike, ~14,000 deals]` A hard bound of 64 attempts is ~50 standard deviations away; exceeding it should `error` loudly rather than silently fall back, and a biased "repair" path should not be written at all (it would change the deal distribution for the tightest tables, which are exactly the 3-player rounds).

**The mutation-proof problem:** a re-shuffle loop whose completeness predicate always returns false looks *identical* to a correct one — same output, always 1 attempt, suite green. Two assertions close it:

1. A **crafted deck** that forces a rejection (seed or construct a deal giving seat 1 four of a rank, and a second giving 3 naturals + a joker), asserting the attempt counter increments and the final deal is legal.
2. A **corpus assertion** that over the seeded CI deal corpus the rejection counter is **> 0** — a predicate that never fires over thousands of deals is broken, not lucky.

Also assert the wild-completable half separately from the complete half (`3 naturals + 1 joker` and `2 naturals + 2 jokers` each need their own case), since a predicate that only checks `n == 4` passes the obvious test and silently ships the bug CARD-09 exists to prevent.

---

## 11. Simulator and Fuzz Design, with measured budgets

### 11.1 Measured throughput (Lune 0.11.1, this machine, this session)

| Configuration | rounds/s | actions/s |
|---------------|----------|-----------|
| O(1) counter invariant per action | 1,904 | 595,017 |
| **Full identity scan per action** | 1,099 | 343,502 |

`[VERIFIED: benchmarked, N=10, k=2, j=2, wild]`

Derived budgets (apply a 2–3x pessimism factor for `--!strict` typed engine code with event allocation and intent validation, which the spike omits):

| Workload | Spike cost | With 3x pessimism | Verdict |
|----------|-----------|-------------------|---------|
| 100k-action fuzz, **full identity check every action** | 0.3s | ~0.9s | Comfortable. Do not tier it. |
| Locked CI subset: 500 rounds × N=3..10, counters | 2.1s | ~6.3s | Fits, but it is the budget risk. |
| Full sweep: 10k rounds × 8 N × 9 pools × 2 modes × 2 churn variants | ~25 min | ~75 min | Nightly/manual, as locked. |

Baseline to protect: the current suite is **333 passed, 0 failed, 3 todo in 15.94s** `[VERIFIED: ran tests/run.luau with the rokit bin on PATH]`, dominated by subprocess tool invocations in the guard/trap/purity specs. CONTEXT's "~20s should stay true" therefore has roughly 4–6s of headroom in the test step. **If the 500×8 subset lands above ~4s, sample N per commit (N ∈ {3, 6, 10}) and run all eight on the merge/full run** rather than cutting the round count — the locked 500 rounds is the statistical floor, whereas N coverage is the dimension that can be sampled without weakening the claim. Decide it on measurement, not in advance.

### 11.2 Plugging into the existing harness

`tests/harness/Test.luau` owns `FuzzOpts`/`FuzzDriver`; `Fuzz.driver` runs `opts.iterations` (default 200) of `gen(rng, i)` then `check(value)`, and its failure message already prints `name`, iteration and the effective seed `[CITED: tests/harness/Fuzz.luau]`. Mapping a **stateful** 100k-action property onto a stateless generator:

- **One iteration = one whole round.** `gen` returns a *plan*: `{ roundSeed = rng:nextUint(), n = ..., config = ..., script = ... }`. `check` builds the round from `roundSeed` and runs it, asserting invariants after **every** action.
- `Rng` has no fork; derive sub-seeds with `rng:nextUint()` (xorshift32 never returns 0 from a non-zero state, and `Rng.new` normalises 0 anyway) `[CITED: src/server/engine/Rng.luau]`.
- **`check` must put `roundSeed` in its error message.** The driver prints the base seed and iteration, which only reproduces the plan if the plan is a pure function of both — state that explicitly so a failure pastes straight into a unit test, as CONTEXT requires.
- 100k actions ≈ 400 iterations at ~250 actions/round, so `opts.iterations` must be set; the 200 default is not enough.

### 11.3 The fuzz suite must assert its own coverage, or it is theatre

Phase 1 verification found two checks that could not fail. A fuzz suite has two specific ways to look green while testing nothing, and both need explicit assertions:

1. **Action-count assertion.** A generator bug that shortens rounds leaves the suite green while running 2k actions instead of 100k. Assert `totalActions ≥ 100_000` at the end of the fuzz case.
2. **Per-kind coverage assertions.** A generator that never emits a completion, never removes a seat mid-pass, or never produces an illegal intent tests none of those paths — silently. Assert minimum observed counts for: `Drew`, `Passed`, `Completed`, natural completion, 3+1 joker completion, 2+2 joker completion, `SeatRemoved{Completed}`, `SeatRemoved{Disconnected}`, removal of the dealer, removal reducing the ring to 2, removal reducing it to 1, ring emptied, **and each of the six `Reject` codes**. A rejection code with zero observations is an untested branch.

Illegal intents must be generated deliberately (draw at 5, pass at 4, pass a card you do not hold, act on a removed seat, unknown card ID) and each must assert *its own code* **and that the state is byte-identical afterwards** — a rejection that mutates state is worse than one that errors.

### 11.4 Two simulator modes, as locked

| Mode | Schedule | Purpose | Stall detector |
|------|----------|---------|----------------|
| **Solvability** (zero-latency) | strict round-robin, greedy ties by card id — fully deterministic | re-check the §3.1 theorem; find cycles | **Exact state-hash cycle detection** — no timeout, and it terminates with proof. Hash = cursor + per-seat sorted hand + per-seat inbox in FIFO order; clear the set on each completion (the state space changes). |
| **Pacing** | event-driven, lognormal per-action | medians, p95, occupancy | 300s cap + taxonomy (§7.7) |

Lognormal parameters for the 250–900ms range (Claude's discretion): **median 0.45s, σ = 0.42 in log space**, which puts ~90% of samples inside [0.25, 0.90] (since `ln(900/450) = 0.693 = 1.645σ`). That is the parameterisation used for every measurement in this document, so the numbers here are directly comparable to what the implementation will produce. Sample via Box-Muller on `Rng.nextNumber`.

Cycle detection is only sound where the dynamics are deterministic — hence strict round-robin in solvability mode. Under the lognormal schedule a repeated state is not a proof of a cycle (the RNG has advanced), so the pacing mode must rely on the cap. Do not mix them.

### 11.5 Metrics the simulator should report (beyond the locked bars)

| Metric | Why |
|--------|-----|
| median / p95 time-to-first-completion, per N | locked bar |
| median / p95 time-to-**all**-spoons | the hunt's actual start budget; measured 13.4–25.4s median |
| **mean seat occupancy, per N** | §3.7 — the only metric that sees a dead table |
| **start-up ramp**: time until every seat has acted once | §3.8 — feeds Phase 4's "waiting for cards" affordance |
| outcome taxonomy counts + reproducing seed per non-`Cleared` round | §7.7 |
| **dead-rank chasing**: seat-instants holding ≥2 of a rank with `n_r + J < 4` | §13 pitfall 2 — a player invisibly chasing an impossible rank |
| stall rate **as a function of noise**, not a single number | §3.6 — a single number hides a cliff |
| deal rejection attempts: mean and max | §10 vacuity check |

---

## 12. Open Questions (must be resolved in the plan, not during execution)

**OQ-A — The gate has no passing configuration.** `[VERIFIED: 76,800 rounds]` "Gate on the all-greedy population" with zero stalls is unachievable at every `(k, j)` in the grid, in both joker modes, because pure deterministic greed livelocks at 1–45%. Options, in the order I would recommend them:

1. Define the gated population as greedy **with a stated imperfection floor** (e.g. 2% random-pass, which is 0% stalls everywhere) and require the pass to hold across the whole swept noise range `[ε, 0.25]` — reporting the curve, not a point. This keeps "gate on greedy", makes the unverifiable parameter explicit, and matches what humans demonstrably do.
2. Model **AFK auto-pass (CARD-16)** inside the simulator, so the all-greedy population self-heals through a mechanism the shipped game actually has. Strongest argument about the live game; creates a Phase 2 → Phase 4 dependency that must be named.
3. Keep pure greedy and accept a non-zero stall rate — contradicts the locked "ZERO stalls, not a low stall rate".

Whichever is chosen, it is a change to what G1 means and the owner should see it. It cannot be left for the executor to discover.

> **RESOLVED (plan 02-12).** By none of the three options as written: amendment **A7** took a fourth route — the ENGINE got an anti-livelock valve, so the gate no longer rests on an assumption about how people play. Option 2's auto-pass survives as a secondary mitigation with a realistic deadline. Amendment **A8** then replaced the literal zero-stall bar with an explicit 0.500% residual ceiling, owner-approved, with the measured residual printed. Evidence: `02-G1-REPORT.md` section 4b (the valve) and plan 02-13's deterministic livelock fixture, which escapes on action 113 through the real `apply` and provably never escapes with the valve disabled.

**OQ-B — `seatCount` in "ranks = seatCount + k" is ambiguous**, and it shifts the gate's answer by a whole notch. If `seatCount` = seats at the table (`N−1`), then circulation `= 4k + j` and `k=0,j=0` is a provable instant deadlock. If `seatCount` = players (`N`), then circulation `= 4(k+1) + j` and `k=0` is the viable floor. Recommended: **define it as live seats at round start**, state the pool in terms of circulation (`circulation = 4(R − m₀) + j ≥ 1`, and ≥ 8 for occupancy), and exclude the dead cell with an asserting test rather than a silent skip.

> **RESOLVED (plan 02-12).** By 02-CONTEXT amendment **A3**: `seatCount` means SEATED SEEKERS, so `ranks = (players in round − 1) + k` and circulation `= 4k + j`. Implemented in exactly one place, `Pool.poolConfig`; nothing else may compute `n - 1` inline. The dead `k=0, j=0` cell is swept and REPORTED as a negative result (amendment A5), never silently skipped. This off-by-one was not cosmetic: measured, it moved the valve-off stall rate by a factor of 40 (amendment A8).

**OQ-C — the selection rule, applied literally, deletes the jokers.** "Fewest extra ranks first, then fewest jokers" selects `j = 0` wherever `j = 0` passes, and it does (§3.5). That makes CARD-10's wild semantics dead code in the shipped game and removes the swings PROJECT.md's Key Decisions table says jokers exist to provide. Recommended framing: **the joker count is a design parameter (PROJECT wants swings → `j ≥ 1`), and the simulator's job is to *clear* the chosen `j` as safe, not to minimise it.** Owner decision — it conflicts with a locked rule, so I have not assumed it away.

> **RESOLVED (plan 02-12).** By the **owner's answer at plan 02-10's pre-sweep checkpoint**, recorded verbatim in `02-10-SUMMARY.md`: the recommended framing was taken — `j` searches `{1,2}` with a floor of `j >= 1`, the sweep CLEARS the chosen `j` rather than minimising it, and `j = 0` is measured and reported as a comparison (`02-G1-REPORT.md` section 6). PROJECT.md's Key Decisions table wins over the literal tiebreak, per CLAUDE.md. The owner re-confirmed the floor at plan 02-12's sign-off.

**OQ-D — must the chosen pool pass in BOTH joker modes?** `[VERIFIED: §3.5]` At `k=0` the flag is a cliff (0% vs 97.4%). If CARD-12 is a real fallback that can be flipped on a live game, the gate must test both positions at the selected pool and `k ≥ 1` is effectively mandatory. If it is only a test-time variant, say so and drop the "available behind a flag" language.

> **RESOLVED (plan 02-12).** **Yes — both modes, and the flag is real.** Enforced by step 3 of the sweep's selection rule (every bar must pass in BOTH joker modes and BOTH churn variants at every N searched) and by the CI subset, whose gated cells run both modes at 500 rounds per cell. Wild and Blocker each clear every bar at the selected pool, so the "available behind a flag" language stands rather than being dropped, and `k >= 1` is confirmed mandatory (amendment A4).

**OQ-E — occupancy floor.** Recommend ≥ 60% mean occupancy at every N as a third pacing bar (§3.7). Without it the gate can legally select a table that is idle 86% of the time at 10 players.

> **RESOLVED (plan 02-12).** Adopted as recommended by 02-CONTEXT amendment **A2**: mean occupancy `>= 0.600` is the third bar, implemented in `Simulator.evaluateBars`. It is load-bearing, not decorative — without it the selection rule picks `k=0, j=1`, one card circulating among nine seats at ~0.17 occupancy (`02-G1-REPORT.md` section 7). The selected pool measures 0.825.

**OQ-F — dealer when the previous round had zero finishers**, and the order among multiple empty-handed seekers (§8.2). Both are reachable in exactly the rounds the simulator is hunting, so they will show up during this phase.

> **RESOLVED (plan 02-12).** By **plan 02-02's locked four-bucket total order** and its corpus. Neither case is a special case: zero finishers means bucket 1 is simply empty and the head falls through to bucket 2, and two or more empty-handed seekers is handled because bucket 2 is a LIST with a key, never an index into "the" non-finisher. `dealer == seatOrder[1]` always, because the hider is not seated.

**OQ-G — order of a departing seat's hand vs inbox** when routed to the successor (§7.4). Affects replay determinism; must be locked by a test either way.

> **RESOLVED (plan 02-12).** By **plan 02-06's locked order: departing hand ascending, then departing inbox in FIFO order**, appended to the successor's inbox tail — locked by a test, as required. The sole-seat case routes to the `terminal` bucket rather than a nil path, which keeps Non-Negotiable Rule 8's "never destroyed" literally assertable by the partition identity.

---

## 13. Common Pitfalls

### Pitfall 1: treating the multiset predicate as the gate criterion
**What goes wrong:** the predicate is implemented, never fires in 10,000 rounds, and is read as "solvability proven". It never fires because §3.1 says it *cannot* fire while Rule 8 holds — it proves nothing about the stall the players will actually hit.
**How to avoid:** classify it as a **Rule 8 tripwire**, mutation-prove it with §3.4's destroy-variant and the crafted fixture, and gate stalls on the `Livelock`/`CapReached` categories instead.
**Warning sign:** a report whose only stall column is `Unsatisfiable: 0`.

### Pitfall 2: a bot (or a player) chasing a dead rank
**What goes wrong:** after a joker completion, a rank sits at `n_r = 1` and can never complete. A greedy agent holding 2 of it keeps them forever. A bot does this invisibly; so does a human, who has no way to know the rank is dead.
**How to avoid:** measure it (`deadChase` in §11.5). Do **not** "fix" the bot by giving it hidden-information awareness as the gated default — that models a player who cannot exist. Keep the naive bot as the gated population and report the informed variant separately. Measured: at noise 0.05 both variants stall 0%, so informedness is not load-bearing for the verdict `[VERIFIED: 19,200 rounds]`.

### Pitfall 3: `t.fuzz` silently running 200 iterations
**What goes wrong:** `Fuzz.luau`'s `DEFAULT_ITERATIONS = 200`. A 100k-action claim with a forgotten `iterations` runs ~2% of the intended load and reads green.
**How to avoid:** assert the total action count (§11.3). Carried Phase 1 todo: "the fuzz harness has only ever run toy properties at 200 iterations" — this is the phase where that stops being true, and the only way to prove it is an assertion on the count.

### Pitfall 4: a conservation check that cannot fail
**What goes wrong:** `inHands + inInbox + retired == total` where all three counters are updated by the same helper — a bug in the helper keeps the sum consistent and the check green forever.
**How to avoid:** derive one side **independently**: recompute `inHands` and `inInbox` by scanning the actual containers and compare against the counters, so the check has two sources that can disagree. Then mutation-prove it: drop a card on pass, duplicate a card on draw, and swap a card for a copy of another (the last one is why the identity scan exists, §4.2) — each must fail.

### Pitfall 5: taking "the empty-handed seeker" as singular
**What goes wrong:** `seatOrder` indexes "the" non-finisher and errors or silently mis-orders when a capped or churned round leaves three of them.
**How to avoid:** a total order over all non-finishers (§8.2), with a corpus case for 0, 1 and ≥2 of them.

### Pitfall 6: a deterministic card ID → rank mapping
**What goes wrong:** IDs allocated in deck-build order make `id 7 ⟹ rank 2` for the whole game. Any future surface that exposes an ID the client should not own leaks a rank, against Rule 3.
**How to avoid:** IDs are shuffled deck positions, re-randomised per round (§9, item 3). Free, and it closes the class rather than the instance.

### Pitfall 7: writing an engine that can yield
**What goes wrong:** `coroutine.yield` inside a mutation, or `os.clock()` as a time source. Verified in this session: the pure-zone lint permits both today (§1), so Rule 6 would be violated with all 14 gates green.
**How to avoid:** extend R3's banned constructs (§1), with a fixture proving the new guard fails.

### Pitfall 8: counting a roster shortfall as a stall
**What goes wrong:** the churn variant reports failures that are really "fewer seats than spoons", the gate tightens the pool to compensate, and the pool ends up flabby for a reason that has nothing to do with cards.
**How to avoid:** the §7.7 taxonomy, with `RosterShortfall` excluded from the stall rate and reported separately.

---

## 14. Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Seeded RNG | a new generator, `math.random` | `src/server/engine/Rng` | xorshift32 via `bit32`, already covered by 11 tests including a reference-vector check and a zero-seed normalisation case `[CITED: tests/engine/rng.spec.luau]`. `math.random` is global state and unseedable per-round. |
| Property-test driver | a bespoke loop | `Test.fuzz` + the injected `Fuzz.driver` | Already prints iteration + seed on failure, and its absence fails loudly by design `[CITED: tests/harness/Test.luau]`. A second driver would bypass that. |
| Simulated time | `os.clock`, `task.wait` | `FakeClock` / `FakeScheduler` pattern — inject the clock | Rule 5, and §11.1's throughput exists only because nothing sleeps. `FakeScheduler` also supports `cancelIsNoop` for testing stale callbacks `[CITED: tests/harness/FakeScheduler.luau]`. |
| Roster bounds 3..10 | new constants | `src/server/core/Admission` + `Config/Limits` | `Admission` is declared the only predicate allowed to say a match may start; a second bounds check is a second source of truth. |
| Round cap / deciseconds | a new timer | `Config/Round` (`ROUND_CAP_SECONDS = 300`, `DECISECONDS_PER_SECOND = 10`) and `RoundLifecycle` | Exactly-once round end with the stale-callback token guard is already built and tested. |
| A "pile locked" flag | boolean state per seat | the rule `|hand| == 4` | A second source of truth that can disagree with hand size. CLAUDE.md already states this. |
| A deck-exhaustion path | refill / reshuffle logic | the ring wrap | §4.1: circulation is invariant, so the deck provably never empties. A refill path would be dead code that silently hides a conservation bug. |

**Key insight:** every piece of infrastructure this phase needs already exists and is already mutation-proven. The new code is the engine's logic and its invariants — and the invariants are arithmetic, not machinery.

---

## 15. Architectural Responsibility Map

| Capability | Primary tier | Secondary tier | Rationale |
|------------|-------------|----------------|-----------|
| Card ring state, pass/draw/complete | **Pure engine** (`src/server/engine/`) | — | Rule 2; no Roblox API, runs headless. |
| Completion detection + naturals-first | Pure engine | — | Pure function of a hand + config. |
| Seat removal (all three causes) | Pure engine | API/server adapter triggers it | Rule 8 is one operation; the *cause* comes from outside, the *routing* must not. |
| Dealer + seat order | Pure engine (`SeatOrder`) | Match lifecycle (P6) supplies find order and roster | Pure ranking function; no clock, no Roblox types. |
| Conservation / satisfiability invariants | Pure engine (`Invariants`) | Fuzz suite and simulator both consume it | One implementation asserted from two places; two would drift. |
| Intent validation + rejection codes | Pure engine | Typed gateway (P1) validates *shape*, engine validates *legality* | Gateway cannot know whether a hand holds a card; engine cannot know a payload is NaN. Both layers are needed and neither duplicates the other. |
| Reaction-time model, bot policy | **Simulator** (`scripts/sim/` or `tests/sim/`) | — | Not shipped logic. Must not live in `engine/`. |
| Clock, scheduling, networking | **Server adapter** (P4) | — | Rules 5 and 6. The engine never sees a clock. |

---

## 16. Project Constraints (from CLAUDE.md)

| Rule | Binding effect on this phase |
|------|------------------------------|
| 1 — gameplay never imports cosmetics/shop | No engine module may be named `Scoring`/`CardTable`/`SpoonPlacement` and import a forbidden segment. Engine has no cosmetic surface, so this is free — but note the Phase 7 todo that R2 is a **filename** deny-list, so naming an engine module `CardTable.luau` makes it a guarded root. |
| 2 — engine references no Roblox API | `src/server/engine/`, lint-enforced two ways (selene allow-list for values, `luau-lsp --platform standard` for types). Both layers are already mutation-proven `[CITED: tests/purity/purity.spec.luau]`. |
| 3 — nothing hidden is a replicated Instance | Engine is data-only, so free. Reinforced by shuffled card IDs (§9). |
| 4 — no purchase affects outcome | No engine surface. |
| 5 — server is the only clock, integer deciseconds | Engine takes **no** clock at all. Currently unenforced in pure zones (§1) — add the guard. |
| 6 — no yields inside state mutations | `apply` returns events; no callbacks. Currently unenforced (§1) — add the guard. |
| 7 — client never names a pass target or hand index | `Intent` carries a stable card ID; `next` resolved at apply time (§9). |
| 8 — seat removal is one generic operation, cards never destroyed | One `removeSeat` with a cause; §3.4's destroy-variant is the mutation proof; §7.3 defines the no-successor case so "never destroyed" stays literally true. |
| `--!strict` everywhere, line 1 | R1 scans all of `src`, `scripts`, `tests`. |
| Pure zones add-only | `scripts/ci/zones.luau` says nothing is ever removed from the list; new engine files land inside the existing `src/server/engine` zone, no list change needed `[CITED: scripts/ci/zones.luau]`. |
| Commit atomically | Engine, fuzz suite and simulator are three separable commits. |

---

## 17. Environment Availability

| Dependency | Required by | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `lune` | headless engine tests, fuzz, simulator | ✓ | 0.11.1 (`/root/.rokit/bin/lune`) | — |
| `selene` | pure-zone lint (FOUND-06 layer 1, new R3 guard) | ✓ | 0.32.0 | — |
| `luau-lsp` | standard-platform typecheck (layer 2) | ✓ | 1.70.1 | — |
| `stylua`, `rojo` | format gate, build | ✓ | 2.6.0 / 7.7.1 | — |
| Roblox doc hosts | nothing in this phase | ✗ | — | Not needed: no Roblox API surface. Debt recorded (§1). |

`[VERIFIED: ran each tool this session; the full suite passes 333/333 with /root/.rokit/bin on PATH]`

**Note for every plan task:** the rokit shims are **not on the default PATH** in this container. `lune run tests/run.luau` without `PATH=/root/.rokit/bin:$PATH` reports **67 spurious failures** (every spec that shells out to selene/luau-lsp/rojo), which is a convincing-looking red suite with no real defect behind it. Any task that runs the suite must set PATH, and any task that reads a failure count must not trust one produced without it.

**Missing dependencies with no fallback:** none.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bespoke headless runner: `tests/run.luau` + `tests/harness/Test.luau` (FOUND-03). No Jest-Lua. |
| Config file | None; discovery is `tests/**/*.spec.luau`, `fixtures/` excluded unless `--root` points inside one |
| Quick run command | `PATH=/root/.rokit/bin:$PATH lune run tests/run.luau -- --filter engine` |
| Full suite command | `PATH=/root/.rokit/bin:$PATH lune run tests/run.luau` |
| Full gate chain | `lune run scripts/verify.luau` (14 steps; `run:` strings byte-identical to `.github/workflows/ci.yml`, asserted by `tests/ci/verify.spec.luau`) |
| Baseline | 333 passed, 0 failed, **3 todo**, 15.94s `[VERIFIED this session]` |
| Phase exit condition | **todo count reaches 0** — `tests/engine/spec_lock.spec.luau`'s three `t.todo` entries (CARD-09, CARD-10, CARD-12) become real tests |

### Phase Requirements → Test Map

| Req | Behaviour | Type | Automated command | File exists? |
|-----|-----------|------|-------------------|--------------|
| CARD-01 | draw only at `|hand| == 4`; `HandNotFour` rejection asserts its own code; `|hand| ∈ {4,5}` always | unit + fuzz invariant | `lune run tests/run.luau -- --filter engine/hand` | ❌ Wave 0 |
| CARD-03 | passed card lands in `next` live seat's inbox tail, `next` resolved at apply time, incl. target removed between intent and apply | unit | `--filter engine/pass` | ❌ Wave 0 |
| CARD-04 | last seat's pass appends beneath the dealer's deck; FIFO order preserved; circulation never reaches 0 | unit + fuzz invariant | `--filter engine/ring` | ❌ Wave 0 |
| CARD-05 | dealer = `seatOrder[1]`; first-finder-is-hider; no seated finisher; zero finishers; round-1 seeded random | unit corpus | `--filter engine/seatorder` | ❌ Wave 0 |
| CARD-06 | order = finishers → non-finishers (0, 1, ≥2) → prev hider → joiners → `userId` | unit corpus | `--filter engine/seatorder` | ❌ Wave 0 |
| CARD-07 | completion detected **only** on draw; completing rank unique; seat removed in the same apply | unit + fuzz | `--filter engine/complete` | ❌ Wave 0 |
| CARD-08 | hand + inbox → successor in the locked order; ring→2, ring→1, ring emptied, dealer removed, mid-pass departure; partition identity holds | unit + fuzz + **mutation** | `--filter engine/removal` | ❌ Wave 0 |
| CARD-09 | no opening hand complete or wild-completable (4, 3+1, 2+2); rejection counter **> 0** over the corpus; bounded retries | unit + corpus + **mutation** | `--filter engine/deal` | ❌ Wave 0 (replaces a `t.todo`) |
| CARD-10 | naturals spent before jokers; 5th card identity; `j ≤ 2` asserted so all-joker is unreachable | unit | `--filter engine/joker` | ❌ Wave 0 (replaces a `t.todo`) |
| CARD-11 | simulator: zero stalls + pacing bars + occupancy floor at N=3..10; failing trial prints its seed | integration (CI subset) | `--filter sim/subset` | ❌ Wave 0 |
| CARD-12 | blocker mode runs in the same process via `EngineConfig`; selected pool passes in **both** modes | unit + integration | `--filter sim/blocker` | ❌ Wave 0 (replaces a `t.todo`) |
| Rules 5/6 | pure zones reject `coroutine` and `os.` | guard + **mutation fixture** | `lune run scripts/ci/check-guards.luau` | ❌ Wave 0 |

### Every check's falsifiability proof (house standard)

| Check | How it is proven capable of failing |
|-------|-------------------------------------|
| Circulation invariant | drop a card on pass; duplicate on draw — each must fail the assertion |
| Partition identity | swap a card for a copy of another (counters stay consistent, identity scan must fail) |
| Satisfiability predicate | **destroy a removed seat's cards** → fires in 2.9–5.7% of rounds `[VERIFIED §3.4]`, plus a crafted one-action fixture that fires deterministically |
| CARD-09 deal check | crafted deck forcing a rejection; corpus assertion that the rejection counter > 0 |
| CARD-10 naturals-first | a hand of 3 naturals + 2 jokers must retire exactly 3 naturals + 1 joker and keep a joker as the 5th |
| Fuzz load | assert `totalActions ≥ 100_000` and a minimum observed count for every event kind and every one of the six reject codes |
| Rejection codes | each illegal intent asserts its own code **and** that state is unchanged |
| New `coroutine`/`os.` guard | a fixture under `tests/purity/fixtures/` using each construct must make `check-guards` exit 1 with the matching `R3` message |
| Simulator gate | run it against a deliberately broken engine (Rule 8 destroy variant) and against the `k=0,j=0` dead pool; both must be reported as failures, not as passes |
| CI subset wiring | `tests/ci/verify.spec.luau` already asserts byte-identical `run:` strings; if the subset runs inside `tests/run.luau`, **no new CI step is needed** and that drift risk is avoided entirely |

### Sampling Rate

- **Per task commit:** `lune run tests/run.luau -- --filter engine` (sub-second; no subprocess specs)
- **Per wave merge:** full suite (~16s + ~2–6s for the subset) — **and check the todo count, not just the pass count**
- **Phase gate:** `lune run scripts/verify.luau` green, todo count 0, and the committed full-sweep report regenerated

### Wave 0 Gaps

- [ ] `tests/engine/pool.spec.luau` — deal, shuffle permutation, CARD-09 rejection (incl. its mutation proof)
- [ ] `tests/engine/ring.spec.luau` — pass/draw, FIFO, m=2 and m=1 rings, dealer wrap (CARD-03, CARD-04)
- [ ] `tests/engine/hand.spec.luau` — completion detection, rank uniqueness, naturals-first (CARD-01, CARD-07, CARD-10)
- [ ] `tests/engine/removal.spec.luau` — all three causes, all six edge cases, Rule 8 destroy mutation (CARD-08)
- [ ] `tests/engine/seatorder.spec.luau` — table-driven corpus incl. the five unspecified cases (CARD-05, CARD-06)
- [ ] `tests/engine/invariants.spec.luau` — circulation + partition, each mutation-proven
- [ ] `tests/engine/fuzz.spec.luau` — 100k-action property run with action-count and per-kind coverage assertions
- [ ] `tests/sim/subset.spec.luau` — 500 rounds × N=3..10 fixed seeds, both joker modes, churn variant
- [ ] `scripts/sim/sweep.luau` — full 10k sweep + committed report
- [ ] `tests/purity/fixtures/engine-yield/`, `tests/purity/fixtures/engine-clock/` — guard mutation fixtures
- [ ] **Rewrite** `tests/engine/spec_lock.spec.luau`: three `t.todo` → real tests, todo count 0
- [ ] No framework install needed; `opts.iterations` must be set explicitly (default 200 is ~2% of the intended load)

---

## Security Domain

`security_enforcement` is absent from `.planning/config.json`, so treated as enabled. The engine has no network, storage or auth surface; the applicable controls are input legality and ownership.

| ASVS category | Applies | Standard control in this phase |
|---------------|---------|-------------------------------|
| V2 Authentication | no | no identity surface in the engine |
| V3 Session management | no | — |
| V4 Access control | **yes** | `Intent.seat` is **never** trusted from a payload: the Phase 4 adapter binds it from the authenticated player. The engine's own defence is `SeatNotLive` + `NotYourCard`, so a seat can only ever act on cards it holds. Assert that passing another seat's card ID is rejected with its own code. |
| V5 Input validation | **yes** | Two layers, neither redundant: `src/shared/Net/Validate` rejects malformed/NaN payload *shape* (Phase 1); the engine rejects illegal *legality* with its own codes (§9). An unknown card ID and an unknown seat ID must both be rejections, not errors. |
| V6 Cryptography | no | `Rng` is a game-fairness PRNG, not a security primitive. Worth a comment saying so, so nobody later uses it for a token. |

### Known threat patterns

| Pattern | STRIDE | Mitigation |
|---------|--------|------------|
| Client names a pass target or hand index to steer cards | Tampering | Rule 7: card IDs only, `next` resolved at apply time (§9) |
| Client infers hidden hands from card IDs | Information disclosure | IDs are shuffled deck positions, re-randomised per round (§9) |
| Client replays or forges an intent for a removed seat | Spoofing/Tampering | `SeatNotLive` with no state mutation; fuzz asserts state is unchanged on every rejection |
| Engine reads a real clock and becomes manipulable | Tampering | Rule 5; new pure-zone `os.` guard (§1) |
| Crafted intent sequence desynchronises card accounting | Tampering/DoS | Circulation + partition invariants asserted after every action, both mutation-proven |

---

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|-------|---------|---------------|
| A1 | A real `--!strict` engine with event allocation is within 3x of the spike's throughput | §11.1 | CI budget blows the ~20s promise; mitigation already stated (sample N per commit) |
| A2 | Required completions per round = `N − 2` = spoons, leaving exactly one empty-handed seeker | §3 | Every stall count is measured against the wrong target. Derived from PROJECT.md ("two fewer spoons than players") + CARD-06, not independently confirmed |
| A3 | `median 0.45s, σ 0.42` is a reasonable reading of "lognormal over roughly 250–900ms" | §11.4 | Pacing numbers shift; the 4x margin absorbs a lot. Unverifiable per V-35 |
| A4 | Humans deviate from pure greed at least ~2% of passes | §3.6, OQ-A | The gate's conclusion inverts. **This is the load-bearing assumption of the whole phase** and it is exactly V-35's unverifiable territory — flagged, not assumed away |
| A5 | Cooperative routing suffices for Claim 3's gatherability (no capacity obstruction) | §3.1 | The theorem weakens from "unreachable" to "not observed in 230,000 rounds". The empirical result stands either way |
| A6 | `k ≥ 1` is needed for the joker flag to be safe in both positions | §3.5, OQ-D | Only tested at k ∈ {0,1,2,3}; the k=0 cliff is measured, the k=1 safety is measured at 1,000 rounds/cell not 10,000 |
| A7 | A 60% occupancy floor is the right threshold | §3.7, OQ-E | A number I chose from the measured table, not from playtest data. The *metric* is the finding; the threshold is a proposal |

---

## Sources

### Primary (HIGH confidence)

- **Measurements taken in this session** using the repo's own pinned `lune` 0.11.1 and `selene` 0.32.0: ~230,000 simulated rounds across the solvability grid, noise sweep, k=0 probe, occupancy sweep, Rule-8 mutation run, deal-rejection sweep, and two throughput benchmarks. Scratch harness at `/tmp/claude-0/-home-user-robloxspoons/8171801a-ef05-5879-bdd8-bef36c22b07f/scratchpad/spike.luau` and `/tmp/claude-0/-home-user-robloxspoons/8171801a-ef05-5879-bdd8-bef36c22b07f/scratchpad/spike2.luau` (throwaway, not shipped).
- **Derivations in this session** (§3.1 counting theorem, §4.1 circulation algebra, §3.3 naturals-first optimality and rank uniqueness, §8.1 `dealer == seatOrder[1]`).
- Repo code read directly: `CLAUDE.md`, `tests/harness/Test.luau`, `tests/harness/Fuzz.luau`, `tests/harness/FakeClock.luau`, `tests/harness/FakeScheduler.luau`, `tests/run.luau`, `tests/engine/spec_lock.spec.luau`, `tests/engine/rng.spec.luau`, `tests/purity/purity.spec.luau`, `src/server/engine/Rng.luau`, `src/server/core/Admission.luau`, `src/server/core/RoundLifecycle.luau`, `src/server/services/RoundDriver.luau`, `src/shared/Config/*`, `scripts/ci/zones.luau`, `scripts/ci/check-guards.luau`, `scripts/ci/analyze.luau`, `scripts/verify.luau`, `selene.toml`, `selene.pure.toml`.
- Planning docs: `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `.planning/research/SUMMARY.md`, `02-CONTEXT.md`.

### Secondary (MEDIUM)

- Prior project research (`SUMMARY.md` Open Questions 1, 2, 3, 4, 6; Verification Debt V-15, V-35) — carried at its stated confidence, not upgraded.

### Tertiary / unavailable

- `create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io` — **unreachable, retested this session.** No external documentation was consulted for this phase, and none was needed: the phase has no Roblox API surface. No web search was performed; the questions were combinatorial and were answered by derivation plus measurement against the repo's own toolchain.

---

## Metadata

**Confidence breakdown:**

| Area | Level | Reason |
|------|-------|--------|
| Solvability / structural deadlock | **HIGH** | Proved by counting, then confirmed at 0/230,000 rounds, then mutation-proven to be capable of firing |
| Conservation invariants | **HIGH** | Derived algebraically, exercised every action in every run, no violation observed |
| Seat-removal edge cases | **HIGH** | Enumerated from the data structure; the ring-emptied case is a genuine gap in the current rules and is called out |
| Dealer / seat order | **MEDIUM-HIGH** | The collapse to one function is sound; five input cases are genuinely unspecified in CARD-05/06 and need a decision |
| Pacing numbers | **MEDIUM** | Measured at 144,000 rounds with a 4x margin on the bars, but the bot model is unvalidated (V-35) |
| **Stall rate / the G1 verdict** | **LOW-MEDIUM** | A step function of an unverifiable bot parameter. The *sensitivity* is HIGH confidence; the *verdict* is not |
| CI / throughput budget | **HIGH** | Benchmarked on this machine with the pinned toolchain |
| Roblox platform claims | **unchanged** | Verification debt stands (§1); no claim upgraded |

**Research date:** 2026-11-03
**Valid until:** 2027-01-02 (60 days — the domain is combinatorial and the toolchain is pinned; nothing here decays). Re-measure the throughput numbers if `lune` is bumped. The stall-rate conclusions should be re-examined the first time real human passing behaviour is observed (Phase 4/6), which is also when V-35 can finally be retired.
