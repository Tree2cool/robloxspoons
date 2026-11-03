---
phase: 02-card-engine-and-pacing-simulator
plan: 04
subsystem: engine
tags: [pool, deal, rejection-sampling, fisher-yates, card-ids, circulation, mutation-proof, CARD-09, CARD-04]

requires:
  - phase: 02-01
    provides: "src/server/engine/Types.luau — JOKER_RANK, HAND_SIZE, MAX_JOKERS, MAX_DEAL_ATTEMPTS, EngineConfig (incl. antiLivelockValve), Rank, CardId, JokerMode"
  - phase: 01-02
    provides: "tests/run.luau + Test.Runner + Fuzz.driver, and src/server/engine/Rng.luau (seeded xorshift32, warm-up fixed in wave 2)"
  - phase: 02-03
    provides: "check-guards R3 bans on `coroutine` and `os.` inside pure zones, including inside string literals"
provides:
  - "src/server/engine/Pool.luau — poolConfig, validate, circulationOf, shuffledRanks, openingHandIsBad, deal"
  - "poolConfig: the single site where amendment A3's `seatCount = n - 1` and `ranks = seatCount + k` are written; it also sets `antiLivelockValve = true`, so no caller hand-builds an EngineConfig"
  - "The four locked validate reasons — BadConfig, RanksBelowSeats, TooManyJokers, DeadPool — in a load-bearing order"
  - "circulationOf = 4 * (ranks - seatCount) + jokers = 4k + j, computable before any card moves (CARD-04, amendment A5)"
  - "The locked deal layout every later plan assumes: seat s holds ids (s-1)*4+1..s*4 and the dealer's inbox is ids seatCount*4+1..T"
  - "CARD-09 rejection-sampled deal with a visible attempt counter and a loud error at 64 attempts; no repair, re-deal or top-up path exists"
  - "tests/engine/pool.spec.luau — 12 cases, including the two that make the deal predicate falsifiable (forcing seed 14, corpus attempt counter)"
affects: [02-07, 02-08, 02-09, 02-10, 02-11]

tech-stack:
  added: []
  patterns:
    - "A derived quantity (seatCount, ranks) is computed in exactly ONE helper and every caller — specs, simulator, sweep — is routed through it, so an off-by-one against an amendment is a single-site bug"
    - "Prove the single-site rule by asserting the ABSENCE of the alternative: a hand-built EngineConfig must set `antiLivelockValve` under --!strict, so the spec reads its own source and asserts zero occurrences of that assignment"
    - "A rejection-sampling loop RETURNS its attempt count instead of logging it, because a counter nobody can read makes the loop unfalsifiable"
    - "Pair a corpus lower bound with a corpus UPPER bound: a predicate that rejects nearly everything is as broken as one that never fires"
    - "Lock the direction of an algorithm with a stub-driven test: a `nextInt` that always returns `lo` yields the identity permutation under ascending Fisher-Yates and a rotation under the other reading, so the direction cannot drift silently"

key-files:
  created:
    - src/server/engine/Pool.luau
    - tests/engine/pool.spec.luau
  modified: []

key-decisions:
  - "`shuffledRanks`/`deal` type their rng parameter as `Pool.Shuffler = Rng.Rng` rather than the plan's `rng: any`. The plan's key_links require `require(\"./Rng\")` from Pool, and a type-only use is the honest one — Pool never constructs a generator, it is always injected. Specs that need a degenerate generator cast a stub to `Pool.Shuffler`, which is what case 11 does"
  - "`validate` reports `RanksBelowSeats` BEFORE `DeadPool`, and the order is asserted. `ranks = 8` at 9 seats also drives circulation negative, so a DeadPool-first ordering would hide the thin-pool diagnosis behind a deadlock diagnosis. Mutation M8 proves the order is load-bearing"
  - "`BadConfig` additionally covers negative jokers and `seatCount = 0`; both are reachable from a Phase 6 caller and neither is a pool"
  - "The threat T-2-20 note (Rng is a fairness PRNG for play, never a security primitive) is worded to avoid the substring the plan's own purity grep bans — the acceptance criterion greps `os.|coroutine|game|Instance` case-sensitively, so the header says \"a fairness PRNG for play\""
  - "Header note 3 says \"no deck TOP-UP\" rather than \"no deck REFILL\": the acceptance criterion greps `-i refill`, which a comment promising never to write a refill path would itself trip. Caught and fixed before the GREEN commit"
  - "Joker modes are passed as LITERALS at every call site — never read out of a table, never returned from a helper. Both forms produced a real TypeError (`Expected '\"Blocker\" | \"Wild\"' but got 'string | string'`); this is the same widening wave 2 recorded in invariants.spec.luau, and it also bites a `(coin: number) -> Types.JokerMode` helper"
  - "Case 7 both hardcodes the forcing seed AND re-runs the 1..5000 search, asserting the search still agrees. A hardcoded-only case goes silently vacuous if the Rng stream ever changes; the search alone is not deterministic. Together, a stream change reports the NEW first forcing seed"

patterns-established:
  - "Pattern: the only-place rule, enforced by a source scan — the spec asserts that no case in it hand-builds the structure the helper owns"
  - "Pattern: two-sided corpus bounds on a rejection counter (> deals and < 4x deals)"
  - "Pattern: a stub generator whose constant output pins an algorithm's direction, asserted via the exact error text rather than a bare throw"

requirements-completed: [CARD-09, CARD-04]

duration: 13min
completed: 2026-11-03
---

# Phase 2 Plan 04: The Pool and the Deal Summary

**`Pool.luau` builds the card multiset, shuffles it so a card id is a re-randomised deck position rather than a rank, and rejection-samples the deal until no seat opens with a complete or wild-completable hand — with the predicate proven capable of firing by a hardcoded forcing seed and by a two-sided corpus counter, and all twelve gates mutation-proven.**

## Performance

- **Duration:** ~13 min (20:19Z to 20:32Z)
- **Tasks:** 2 of 2 (task 1 run as RED -> GREEN per house style)
- **Files created:** 2 (`src/server/engine/Pool.luau` 243 lines, `tests/engine/pool.spec.luau` 419 lines)
- **Commits:** 3 (plus this one)

## Accomplishments

### `poolConfig` — the only place amendment A3 is written

```luau
poolConfig: (n: number, k: number, j: number, mode: Types.JokerMode) -> (Types.EngineConfig, number)
```

`n` is PLAYERS IN THE ROUND. The hider plays no cards, so `seatCount = n - 1` (seated seekers) and
`ranks = seatCount + k`; `antiLivelockValve` is set `true`. It errors unless `n` is an integer in
`3..10` (`MIN_PLAYERS_IN_ROUND`/`MAX_PLAYERS_IN_ROUND` are duplicated locally on purpose — an
engine -> shared require is a cross-mount edge and guard rule R6 fails it, and nothing here ever
looks up a seat bound: `seatCount` always arrives as a parameter).

Case 0 asserts the arithmetic across `n` in 3..10 and `k` in 0..2, asserts `n = 2`, `n = 11` and
`n = 4.5` all error, and then asserts the single-site rule structurally: it reads its own source and
requires **zero** occurrences of `antiLivelockValve =`. A hand-built `EngineConfig` cannot omit that
field under `--!strict`, so zero occurrences proves every config in the spec came from `poolConfig`.
The needle is built by concatenation so the assertion is not its own counterexample.

### The four locked `validate` reasons

| Reason | Fires when | Why it is named rather than crashed or skipped |
|--------|-----------|------------------------------------------------|
| `"BadConfig"` | `ranks`/`jokers`/`seatCount` not a non-negative integer, `seatCount < 1`, or `jokerMode` outside `Wild`/`Blocker` | Not a pool at all; a Phase 6 caller can produce this |
| `"RanksBelowSeats"` | `ranks < seatCount` | Research 3.1 Claim 2: the round needs `seatCount - 1` completions, each damages one rank, so `ranks >= seatCount` keeps an intact rank for the last required completion |
| `"TooManyJokers"` | `jokers > Types.MAX_JOKERS` (2) | Research 3.3 proves the completing rank is unique and the all-joker set unreachable only at `j <= 2`; at `j >= 3` both proofs reopen |
| `"DeadPool"` | `circulationOf < 1` | `k=0, j=0` is a provable instant deadlock (100% stall for every N, research 3.1 corollary / A5). The sweep in 02-10 needs it as a CATEGORY, not a hang |

**The order is load-bearing and asserted:** `RanksBelowSeats` is reported before `DeadPool` because a
thin pool also drives circulation negative, and the thin-pool diagnosis is the useful one.

### CARD-04: circulation is a computation, not a claim

`circulationOf(config, seatCount) = 4 * (config.ranks - seatCount) + config.jokers`, i.e. `4k + j`
exactly (amendment A5). Asserted across `seatCount` in {2,5,9} x `k` in 0..3 x `j` in 0..2. There is
**no deck top-up, re-deal, dry-deck or refill path anywhere in the module**, which the acceptance
greps enforce; research 14 calls such a path dead code that hides a conservation bug.

### The locked deal layout (verbatim, as the later plans assume it)

- `totalCards` (T) `= 4 * ranks + jokers`
- seat `s` (1-based) is dealt card IDs `(s - 1) * 4 + 1` through `s * 4`
- the dealer is seat 1, and its inbox holds IDs `seatCount * 4 + 1` through `T`, in ascending order
- so at the deal every circulating card sits in the dealer's inbox and every other inbox is empty
  (research 3.8), and the start-up ramp advances one seat per draw+pass pair
- the deal is random because `rankOf` is a fresh shuffle, NOT because the ID assignment moves

Case 10 asserts `T - seatCount * 4 == circulationOf(config, seatCount)` across the grid, computing
the two sides independently (layout arithmetic versus `4k + j`) so they cannot agree by sharing a
helper.

### The shuffle, and why a card id carries no rank

Fisher-Yates is written **ascending**, drawing position `i`'s occupant from the un-fixed tail
`[i, n]`, over the injected `Rng` (never `math.random`, which is unseedable global state):

```luau
local n = #cards
for i = 1, n - 1 do
	local j = rng:nextInt(i, n)
	cards[i], cards[j] = cards[j], cards[i]
end
```

The returned table **is** `rankOf`: index = card id, value = rank. A card id is therefore a shuffled
deck POSITION, re-randomised every round, so an id that leaks to a client carries no rank
information (CLAUDE.md rule 3, research Pitfall 6, threat T-2-16). Case 5 fuzzes 300 iterations
asserting the exact multiset and — crucially — that at least two distinct permutations were observed,
because an unshuffled multiset satisfies every other assertion in that case.

### CARD-09, proven non-vacuous twice

`openingHandIsBad` checks the two reasons as **separate conditions**: four naturals of one rank (bad
in both modes), and, in Wild mode only, `a >= 1` naturals with `a + jokersHeld >= 4` (3+1 and 2+2 —
research 3.3 proves those are the only wild completions reachable at `j <= 2`). In Blocker mode
3 naturals + 1 joker and 2 naturals + 2 jokers are **legal** opening hands: that asymmetry is the
CARD-10 / CARD-12 divergence showing up at the deal, and case 6 asserts all of it row by row.

| Falsifier | Measurement |
|-----------|-------------|
| **Hardcoded forcing seed** (case 7) | At `seatCount = 2, k = 1, j = 2, Wild`, **seed 14** is the first seed in 1..5000 that needs **2 attempts**. The case asserts `attempts == 2`, asserts the accepted deal is still legal for both seats, then re-runs the 1..5000 search and asserts the first hit is still seed 14 — so a change to the Rng stream reports the new seed instead of going quietly vacuous. If nothing in 5000 seeds forces a rejection the case fails with "the deal predicate never fires: a vacuous predicate is indistinguishable from a correct one" |
| **Corpus counter** (case 8) | Seeds 1..400 at the same cell spend **438 attempts total, mean 1.095, max 4**. Asserted `> 400` (at least one rejection fired) and `< 1600` (it does not reject nearly everything) |

**On the plan's "expect ~536":** that figure came from research 10's tightest row, `N=3, j=2, R=2`
(mean 1.34), which is `k = 0`. This plan's cell is `k = 1`, i.e. `ranks = 3`, which is research's
`N=3, j=2, R=3` row at **mean 1.13**. Measured 1.095 against 1.13 is agreement, not a discrepancy —
no assertion was adjusted to fit observed output. For the record, measured means at other cells:
`n=3,k=2,j=2` 1.030; `n=6,k=1,j=1` 1.013; `n=10,k=2,j=1` 1.003, all consistent with research's
1.00-1.07 for `N >= 6`.

`deal` errors at `Types.MAX_DEAL_ATTEMPTS = 64` with
`"Pool.deal: no legal deal in 64 attempts (ranks=..., jokers=..., seats=...)"`. No repair path
exists: editing a bad deal would bias the distribution for the tightest tables, which are exactly
the 3-player rounds (threats T-2-17, T-2-18).

## Mutation Proofs

Twelve mutations, each applied to `Pool.luau` alone and reverted immediately; verbatim output of
`lune run tests/run.luau -- --filter engine/pool`. Clean baseline: **12 passed, 0 failed**.

```
=== M1 openingHandIsBad always returns false (the vacuous CARD-09 predicate)
    FAIL tests/engine/pool.spec.luau::openingHandIsBad sees all three bad shapes and the mode asymmetry
    FAIL tests/engine/pool.spec.luau::a crafted deck forces a rejection
    FAIL tests/engine/pool.spec.luau::the rejection counter is greater than zero over the corpus
    FAIL tests/engine/pool.spec.luau::64 attempts is a loud error, not a silent repair
    expected function to throw, but it returned normally
    8 passed, 4 failed, 0 todo in 0.21s

=== M2 drop the wild-completable half, keep only four-naturals
    FAIL tests/engine/pool.spec.luau::openingHandIsBad sees all three bad shapes and the mode asymmetry
    FAIL tests/engine/pool.spec.luau::a crafted deck forces a rejection
    10 passed, 2 failed, 0 todo in 0.24s

=== M3 mode-blind predicate: Blocker treated as Wild
    FAIL tests/engine/pool.spec.luau::openingHandIsBad sees all three bad shapes and the mode asymmetry
    11 passed, 1 failed, 0 todo in 0.24s

=== M4 shuffledRanks returns the multiset unshuffled
    FAIL tests/engine/pool.spec.luau::a crafted deck forces a rejection
    FAIL tests/engine/pool.spec.luau::the rejection counter is greater than zero over the corpus
    FAIL tests/engine/pool.spec.luau::no accepted deal gives any seat a complete or wild-completable opening hand
    9 passed, 3 failed, 0 todo in 0.23s

=== M5 Fisher-Yates written the other way round (i from n down, j from [1, i])
    FAIL tests/engine/pool.spec.luau::a crafted deck forces a rejection
    FAIL tests/engine/pool.spec.luau::64 attempts is a loud error, not a silent repair
    the stub must yield the identity permutation (expected { [10] = 3, [11] = 3, [12] = 3, [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 2, [6] = 2, [7] = 2, [8] = 2, [9] = 3 }, got { [10] = 3, [11] = 3, [12]
    10 passed, 2 failed, 0 todo in 0.24s

=== M6 poolConfig forgets amendment A3: seatCount = n
    FAIL tests/engine/pool.spec.luau::poolConfig writes amendment A3's arithmetic once
    FAIL tests/engine/pool.spec.luau::circulation is 4k + j exactly
    FAIL tests/engine/pool.spec.luau::an invalid pool is rejected by its own name
    FAIL tests/engine/pool.spec.luau::the dead pool k=0 j=0 is excluded by an assertion, not by a skip
    FAIL tests/engine/pool.spec.luau::k >= 1 is the mandatory floor, and k = 0 with j = 1 is legal arithmetic
    FAIL tests/engine/pool.spec.luau::the shuffle is a permutation of the multiset
    FAIL tests/engine/pool.spec.luau::a crafted deck forces a rejection
    FAIL tests/engine/pool.spec.luau::the rejection counter is greater than zero over the corpus
    FAIL tests/engine/pool.spec.luau::no accepted deal gives any seat a complete or wild-completable opening hand
    FAIL tests/engine/pool.spec.luau::every circulating card starts in the dealer's inbox
    FAIL tests/engine/pool.spec.luau::64 attempts is a loud error, not a silent repair
    1 passed, 11 failed, 0 todo in 0.22s

=== M7 circulationOf counts jokers twice
    FAIL tests/engine/pool.spec.luau::circulation is 4k + j exactly
    seats=2, k=0, j=1: circulation must be 4k + j (expected 1, got 2)
    FAIL tests/engine/pool.spec.luau::k >= 1 is the mandatory floor, and k = 0 with j = 1 is legal arithmetic
    FAIL tests/engine/pool.spec.luau::every circulating card starts in the dealer's inbox
    seats=2, k=1, j=1: the dealer's inbox must hold exactly the circulating supply (expected 6, got 5)
    9 passed, 3 failed, 0 todo in 0.21s

=== M8 validate reports DeadPool before RanksBelowSeats
    FAIL tests/engine/pool.spec.luau::an invalid pool is rejected by its own name
    11 passed, 1 failed, 0 todo in 0.21s

=== M9 drop the DeadPool check entirely
    FAIL tests/engine/pool.spec.luau::an invalid pool is rejected by its own name
    FAIL tests/engine/pool.spec.luau::the dead pool k=0 j=0 is excluded by an assertion, not by a skip
    seats=2: the dead pool must not validate (expected false, got true)
    10 passed, 2 failed, 0 todo in 0.23s

=== M10 a repair path: return the last permutation instead of erroring at the ceiling
    FAIL tests/engine/pool.spec.luau::64 attempts is a loud error, not a silent repair
    11 passed, 1 failed, 0 todo in 0.26s

=== M11 TooManyJokers threshold loosened to j > 3
    FAIL tests/engine/pool.spec.luau::an invalid pool is rejected by its own name
    11 passed, 1 failed, 0 todo in 0.20s

=== M12 poolConfig ships the valve off
    FAIL tests/engine/pool.spec.luau::poolConfig writes amendment A3's arithmetic once
    11 passed, 1 failed, 0 todo in 0.23s
```

**M1 is the one the plan exists for:** a predicate that always returns `false` is the exact shape of
the CARD-09 bug, and it is caught by four cases — including both falsifiers (7 and 8), which is the
point. **M5** is the direction lock: the plan warned that implementing the other Fisher-Yates reading
would make case 11 pass for the wrong reason, and the mutation shows case 11 failing on the identity
assertion when the direction flips.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The plan's own purity greps collide with two phrases the plan asks for**
- **Found during:** Task 1 acceptance checks
- **Issue:** The acceptance criteria require `grep -qiE 'refill|...'` and `grep -qE '...|game|...'` to
  FAIL on `Pool.luau`, while the plan's text asks the header to say "no deck-refill path" (T-2-17
  wording) and to record T-2-20 as "`Rng` is a game-fairness PRNG". Each phrase trips its own grep —
  even inside a comment, which is exactly how the pure-zone needle rules work.
- **Fix:** Header note 3 says "THERE IS NO DECK TOP-UP, RE-DEAL OR DRY-DECK PATH"; note 5 says
  "`Rng` IS A FAIRNESS PRNG FOR PLAY, NOT A SECURITY PRIMITIVE". Both meanings are intact.
- **Commit:** 06d884a

**2. [Rule 3 - Blocking] `Types.JokerMode` widens to `string` when read from a table OR returned from a helper**
- **Found during:** Task 2, `analyze` step
- **Issue:** `local MODES: { Types.JokerMode } = { "Wild", "Blocker" }` and then
  `pool(9, 0, 1, mode)` produced
  `TypeError: Expected this to be '"Blocker" | "Wild"' but got 'string | string'`. Annotating the
  elements (`"Wild" :: Types.JokerMode`) did not help, and neither did a
  `(coin: number) -> Types.JokerMode` helper — the widening survives both.
- **Fix:** Modes are passed as literals at every call site: case 4 calls a
  `(mode: Types.JokerMode)` local twice with `"Wild"` and `"Blocker"`, and case 9's fuzz generator
  branches on a coin flip with a literal in each branch. A declared PARAMETER of type `JokerMode`
  forwards fine; only the table-element and return-value positions widen. This is the same defect
  wave 2 recorded in `invariants.spec.luau`, now confirmed to cover the helper-return form too.
- **Commit:** 6a2d6dc

### Judgement Calls (not defects)

**`rng` is typed `Pool.Shuffler = Rng.Rng`, not `any`.** The plan's `<interfaces>` block writes
`rng: any` while its `key_links` block requires `require("./Rng")` from `Pool.luau`. Pool never
constructs a generator, so the only honest use of that require is the type. Real callers
(`Rng.new(seed)`) satisfy it unchanged; case 11's degenerate stub casts. No behaviour differs.

**Case 7 keeps the search as well as the hardcoded seed.** The plan says to search, then hardcode.
Hardcoding alone would go silently vacuous if the Rng stream changed; the search alone would not be
deterministic. Doing both means a stream change reports the new forcing seed by name.

## Verification

```
stylua --check src/server/engine/Pool.luau tests/engine/pool.spec.luau   FORMAT_OK
selene --config selene.pure.toml src/server/engine                        0 errors, 0 warnings
selene src scripts tests                                                  0 errors, 0 warnings
analyze --platform standard ... src/server/engine tests                   analyze: ok
check-guards                                                              ok (73 files, 158 requires, 19 guarded roots)
lune run tests/run.luau -- --filter engine/pool                           12 passed, 0 failed, 0 todo
```

Task 1 acceptance greps, all as specified: `head -1` is `--!strict`; `DeadPool`,
`RanksBelowSeats`, `TooManyJokers`, `MAX_DEAL_ATTEMPTS`, `local function poolConfig` and
`for i = 1, n - 1 do` all present; `descending`, `refill|reshuffleDeck|deckEmpty|exhaust`,
`math.random` and `os.|coroutine|game|Instance` all absent (exit 1). Task 2 acceptance greps:
`grep -c 'iterations ='` = 2 = `grep -c 't.fuzz('`; `vacuous predicate`,
`no legal deal in 64 attempts`, `"DeadPool"`, `Blocker` and `poolConfig` all present; the forcing
seed shows as `local forcing = { seed = 14, attempts = 2 } -- hardcoded: the first seed in 1..5000
needing a re-shuffle`.

### Whole-suite note (wave 3)

The plan forbids a whole-suite or `scripts/verify.luau` assertion from this plan precisely because it
runs beside 02-05, 02-06 and 02-13. Run anyway for the record: **420 passed, 9 failed, 3 todo**, and
**all 9 failures are `tests/engine/removal.spec.luau`** — plan 02-06's RED commit (`fbefea8`) landed
its failing removal rows before `Ring.removeSeat` exists, and `src/server/engine/Ring.luau` is
currently modified in the working tree by that sibling. `scripts/verify.luau` stops at the typecheck
step on the same file (`Key 'removeSeat' not found`). Nothing in either failure touches `Pool.luau`
or `pool.spec.luau`; those are sibling in-flight work and were deliberately not touched. The 14-step
gate run belongs to plan 02-07, which is alone in its wave.

## TDD Gate Compliance

The plan marks task 1 `tdd="true"` while listing only `Pool.luau` in its `<files>`. Executed in the
house order recorded in wave 1 and 2 (`test(... RED)` then `feat(... GREEN)`):

| Gate | Commit | What |
|------|--------|------|
| RED | `40ab3cb` | `test(02-04): failing pool behaviour rows before Pool exists (RED)` — task 1's `<behavior>` block, failing because `./Pool` does not resolve |
| GREEN | `06d884a` | `feat(02-04): Pool — validate, circulation, the shuffle and the CARD-09 deal predicate (GREEN)` — 5 passed, 0 failed |
| (task 2) | `6a2d6dc` | `test(02-04): the deal corpus ...` — the RED spec grown into the 12-case corpus |

No REFACTOR gate was needed. No test passed unexpectedly during RED: the load failed, which is the
designed signal.

## Known Stubs

None. `Pool.luau` has no placeholder, no TODO and no unwired path; every exported function is
exercised by the corpus.

## Threat Flags

None. The files introduce no network endpoint, no auth path, no file access and no schema at a trust
boundary beyond what `<threat_model>` already registers (T-2-16 through T-2-20, all mitigated or
explicitly accepted in the module header).

## For the Next Phase

- `Engine.newRound` (02-07) should call `Pool.deal(config, seatCount, rng)` and lay the result out
  exactly as the locked layout above: seat `s` gets ids `(s-1)*4+1..s*4`, the dealer's inbox gets
  `seatCount*4+1..T` ascending, every other inbox empty. `Invariants.expectedCirculation` already
  agrees with `Pool.circulationOf` by construction at `churnRemovals = 0`.
- The simulator (02-09) and the sweep (02-10) must build their configs through `Pool.poolConfig` and
  must never compute `n - 1` inline; case 0's source scan is what keeps that true for this spec, and
  a similar scan is cheap to add there.
- `k = 0, j = 0` is reportable as the `DeadPool` category rather than a hang, and `k = 0, j = 1`
  validates while being ruled out by amendment A4 on pacing grounds — the sweep should report it as a
  documented negative result, not skip it.
- `tests/engine/spec_lock.spec.luau`'s CARD-09 todo is now covered by real assertions here. It was
  left untouched: the todo list is one file shared with 02-05 and 02-06 in this wave, and retiring
  the three todos belongs to whichever plan owns that file (02-11 per the phase plan).

## Self-Check: PASSED

All three files exist on disk (`src/server/engine/Pool.luau`, `tests/engine/pool.spec.luau`,
`.planning/phases/02-card-engine-and-pacing-simulator/02-04-SUMMARY.md`) and all three task commits
are reachable in git (`40ab3cb`, `06d884a`, `6a2d6dc`).
