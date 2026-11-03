---
phase: 02-card-engine-and-pacing-simulator
plan: 02
subsystem: engine
tags: [seat-order, dealer, total-order, determinism, seeded-shuffle, input-validation]

requires:
  - phase: 01-02
    provides: "tests/run.luau harness, Test.Runner API (deepEqual/throws/truthy/falsy), the assert-the-reason rule"
  - phase: 01-03
    provides: "check-guards R1/R2/R3/R6 and selene.pure.toml, which define what the pure zone may contain"
  - phase: 02-03
    provides: "R3's coroutine and os. bans, under which this module was written"
  - phase: 01
    provides: "src/server/engine/Rng.luau — the injected seeded generator used by the round-1 shuffle"
provides:
  - "src/server/engine/SeatOrder.luau — nextSeatOrder(input) -> { PlayerId } and dealerOf(order) -> PlayerId?"
  - "The locked four-bucket total order for CARD-05 + CARD-06, implemented ONCE so the two rules cannot disagree"
  - "A 28-case corpus pinning all five inputs research 8.2 flags as unspecified, each row asserting its reason"
  - "The SeatOrderInput contract that Phase 6's match lifecycle and plan 02-09's simulator consume"
affects: [06, 02-09, 02-12]

tech-stack:
  added: []
  patterns:
    - "Two requirements that are provably the same ranking get ONE function; the second reader (dealerOf) is a named accessor, never an inline order[1]"
    - "Filter against the live roster BEFORE bucketing, so a departed player cannot occupy a bucket slot and become the head"
    - "Bucket keys are list indexes and the final tiebreak is userId ascending, which makes the comparator a total order with no reachable tie"
    - "A pure ranking module declares its own PlayerId alias rather than importing one, so it can be written in the same wave as the module that owns the shared vocabulary"

key-files:
  created:
    - src/server/engine/SeatOrder.luau
    - tests/engine/seatorder.spec.luau
    - .planning/phases/02-card-engine-and-pacing-simulator/deferred-items.md
  modified:
    - .planning/REQUIREMENTS.md

key-decisions:
  - "dealer == seatOrder[1] always: CARD-05 and CARD-06 are one ranking, because the hider is not seated and so the highest-placed SEATED finisher IS the head of the seat order"
  - "The four buckets are finishers by find order, non-finishers by previous seat index, the previous hider, joiners by join order, with userId ascending as the final tiebreak"
  - "Zero finishers is NOT a special case: bucket 1 is simply empty and the head falls through to bucket 2"
  - "Two or more empty-handed seekers is NOT a special case: bucket 2 is a list with a key, never an index into 'the' non-finisher"
  - "Round 1 is the same function with every previous list empty and an INJECTED Rng; a missing rng is a loud error, never a fallback to the global generator"
  - "An unusable round number (NaN, 2.5, nil, inf, a string) falls to the deterministic path, which cannot error, rather than to the path that demands an rng"
  - "Malformed list entries are ignored, not fatal; the only two errors are a missing round-1 rng and the provable-bug case of an empty order from a non-empty roster"
  - "The playerId tiebreak is unreachable by construction (bucket keys are distinct list indexes), so the corpus asserts THAT reason instead of faking a tie"
  - "CARD-05/CARD-06 recorded as Partial, following the FOUND-08 precedent: the rule is implemented and locked but has no consumer until Phase 6"

patterns-established:
  - "Mutation-prove a corpus, not just a guard: five deliberate breaks of the module, each expected to turn a NAMED row red. The one break that stayed green exposed a missing discriminating row"

requirements-completed: []
requirements-contributed: [CARD-05, CARD-06]

duration: ~1 session
completed: 2026-11-03
---

# Phase 2 Plan 02: Seat Order and Dealer Summary

**`SeatOrder.nextSeatOrder` is the single ranking that answers both CARD-05 and CARD-06 — a
four-bucket total order over the seated seekers whose head IS the dealer — and it returns a dealer
for every reachable input, including zero finishers, three empty-handed seekers, a find order full of
departed players and a mass leave, with no randomness at all after round 1.**

## Performance

- **Tasks:** 2 of 2
- **Files created:** 3; **modified:** 1
- **Seat-order corpus alone:** `28 passed, 0 failed, 0 todo in 0.16s`
- **Full suite after this plan:** `374 passed, 0 failed, 3 todo in 14.39s` (baseline at `168515e` was
  `336 passed, 0 failed, 3 todo`; +38 = this plan's 28 plus wave-sibling 02-01's 10)
- **`scripts/verify.luau`:** `verify: all 14 automated steps passed in 16.7s` — unchanged from baseline

## Task Commits

1. **RED — the six `<behavior>` rows before the module exists** — `26b34ec` (test)
2. **Task 1: `SeatOrder.luau`, one total order whose head is the dealer** — `923e5c2` (feat)
3. **Task 2: the 28-case corpus, each row asserting its reason** — `f443155` (test)
4. **Deferred finding: the `Rng` small-seed warm-up defect** — `a50b937` (docs)

## Why one function

CARD-05 names the dealer ("the previous round's first finder; if that player is hiding, the
highest-placed finisher actually seated"). CARD-06 names the seat order ("finishers in find order,
then the empty-handed seeker, then everyone else"). The hider does not play cards, so the
highest-placed **seated** finisher is by definition the first element of the seat order. Therefore:

> **`dealer == seatOrder[1]`, always.**

`dealerOf(order)` is the only reader of the dealer, which is why no caller ever writes `order[1]`
inline and nobody can later add a second dealer rule. Two rules implemented separately will
eventually disagree; this plan makes that disagreement structurally impossible.

## The locked total order (verbatim — Phase 6 implements against this)

Buckets are **concatenated**, not interleaved. Within a bucket the stated key decides. The final
tiebreak everywhere is `playerId` ascending (`playerId` is the Roblox `UserId`, a stable total order).

| # | bucket | key within the bucket |
|---|--------|----------------------|
| 1 | finishers | position in `previousFindOrder` |
| 2 | non-finishers who were seated last round | their index in `previousSeatOrder` ascending |
| 3 | the previous hider | single entry |
| 4 | joiners (in no previous list) | index in the filtered roster, i.e. join order |

Rules that make it total and crash-free:

1. **Filtered against the live `roster` BEFORE bucketing, never after.** A `previousFindOrder` entry
   naming a player who has left never occupies a bucket slot, so `order[1]` cannot be a player who is
   not in the server (T-2-06).
2. **`hiderId` is removed from every bucket at once.** The hider does not play cards (02-CONTEXT
   amendment A3) and the card table has 9 seat anchors against a 10-player cap.
3. **Zero finishers is not a special case** — bucket 1 is empty and the head falls through to bucket 2.
   Reachable in every round that ends at the cap, which is exactly what the pacing simulator hunts.
4. **Two or more empty-handed seekers is not a special case** — bucket 2 is a LIST with a key
   (research Pitfall 5). Nothing in the module indexes "the" non-finisher.
5. **Round 1 is the same function.** Every previous list is empty, so everyone is a joiner, and the
   result is a Fisher-Yates shuffle driven by the **injected** `Rng`. `round == 1` with no rng raises
   `SeatOrder: round 1 requires an rng`. Rounds after 1 never read `rng`.
6. **De-duplicated.** A player in both `previousFindOrder` and `previousSeatOrder` is seated once;
   bucket 1 wins. A duplicated roster entry is seated once.
7. **`dealerOf(order)`** returns `order[1]`, or `nil` for an empty order.

## The exact `SeatOrderInput` field list

```luau
export type PlayerId = number

export type SeatOrderInput = {
	round: number,                  -- 1-based; round 1 takes the seeded-shuffle path
	roster: { PlayerId },           -- players present NOW, in join order: the source of truth for "still here"
	hiderId: PlayerId?,             -- this round's hider, excluded from the result
	previousFindOrder: { PlayerId }, -- last round's completions in find order; MAY name departed players
	previousSeatOrder: { PlayerId }, -- last round's seat order; supplies the bucket-2 key
	previousHider: PlayerId?,       -- last round's hider
	rng: any?,                      -- an Rng; REQUIRED when round == 1, never touched otherwise
}

nextSeatOrder: (input: SeatOrderInput) -> { PlayerId }
dealerOf: (order: { PlayerId }) -> PlayerId?
```

`previousFindOrder`, `previousSeatOrder` and `previousHider` may be absent or malformed at runtime:
a non-table behaves as an empty list, and a non-integer entry is skipped. The module has **no
requires at all** (`grep -c 'require(' src/server/engine/SeatOrder.luau` → `0`), which is what let it
be written in the same wave as plan 02-01's `Types.luau`; `PlayerId` is declared locally and the
duplication is justified in the file header, exactly as `src/server/core/Admission.luau` does.

## Forward edge: no consumer inside Phase 2

`SeatOrder`'s consumer is the **Phase 6 match lifecycle**, which supplies `roster`, `hiderId` and the
previous round's lists; plan **02-09**'s simulator may also drive it to generate round-to-round seat
rotation. Inside Phase 2 nothing calls it except its own corpus, and that is correct for a pure
ranking function — it was deliberately not wired into anything to make it look used. Plan **02-12**
records this forward edge in STATE.md so the module is not an untracked orphan.

## The corpus, and what each row exists to stop

11 table-driven rows (`why` field on every one) plus 17 standalone cases. The five rows research 8.2
flags as unspecified by CARD-05/CARD-06 come first:

| Row | Input | Expected | The rule it pins |
|---|---|---|---|
| the first finder is the hider | find `{7,3,9}`, hider 7, roster `{3,7,9,11}` | `{3,9,11}` | CARD-05 falls through to the highest-placed **seated** finisher |
| **zero finishers** last round | find `{}`, prev seat `{2,5,8}` | `{2,5}` | bucket 1 empty, head comes from bucket 2 |
| three empty-handed seekers, not one | find `{2}`, prev seat `{4,1,2,3}` | `{2,4,1,3}` | bucket 2 is a list with a key |
| the find order names a departed player | find `{12}`, 12 absent from roster | `{2,1}` | filtered before the head is taken |
| mass leave | every previous name gone | `{20,21}` | still produces a dealer; a nil dealer is a crash one layer up |
| the previous hider rejoins | prev hider 3 | `{2,1,3}` | bucket 3 sorts after every seated non-finisher |
| the previous hider outranks an earlier joiner | roster `{9,3,1,2,4}` | `{2,1,3,9}` | bucket 3 is its own bucket, ahead of bucket 4 |
| an all-joiner roster keeps join order | roster `{99,11,2}` | `{99,11}` | userId is the TIEBREAK, not the key |
| a descending previous seat order is preserved | prev seat `{9,1}` | `{9,1}` | bucket 2's key is the previous index |
| finishers outrank an earlier-seated non-finisher | find `{9,3,2}`, prev seat `{1,2,3,9}` | `{3,2,1}` | buckets concatenate, they do not interleave |

Three of the standalone cases are **loops over `CASES`**, so a row added later cannot forget them:
the hider never appears, no player appears twice, and `#result` equals the roster minus the hider.
That last one is the case that catches a bucketing bug which silently drops a player — the engine
would otherwise deal to fewer seats than there are seekers and nothing else in the phase would
notice. The rest cover the round-1 shuffle (same seed replays; three seed pairs diverge; the result
is a permutation by length *and* set membership), the missing-rng error, "rounds after 1 use no
randomness" (called twice with no `rng` field at all), malformed rosters, duplicated entries, missing
previous lists, an unusable round number, a hider who is not in the roster, an empty order with a
`nil` dealer, order freshness, and that the module exports exactly `nextSeatOrder` and `dealerOf`.

## Mutation proof — the corpus was watched failing

Five deliberate breaks of `SeatOrder.luau`, each expected to turn a **named** row red:

| Mutation | Result |
|---|---|
| M1: rank departed finishers too (filter *after* bucketing) | 6 rows red, including "the find order names a departed player" |
| M2: sort by `playerId` only, ignoring bucket and key | 6 rows red, including "an all-joiner roster keeps join order" |
| M3: keep the hider in the buckets | 7 rows red, including the hider loop |
| M4: fall back to an unseeded order in round 1 | "round 1 without an rng errors rather than falling back" red |
| M5: treat the previous hider as a joiner (drop bucket 3) | **initially GREEN — a corpus gap** |

M5 is the finding. The original "previous hider rejoins" row used a roster in which the previous
hider happened to be the last joiner anyway, so bucket 3 and bucket 4 were indistinguishable. A new
row ("the previous hider outranks a joiner who joined before him", roster `{9,3,1,2,4}`) makes them
distinguishable, and M5 re-run now fails by name:

```
FAIL tests/engine/seatorder.spec.luau::the previous hider outranks a joiner who joined before him
```

Every mutation was reverted with `git checkout -- src/server/engine/SeatOrder.luau`; the final tree
differs from the mutated runs only in the added corpus row.

## The `playerId` tiebreak is unreachable, and that is the point

The plan asked for a corpus row "where bucket keys tie and ascending `playerId` decides". It is not
reachable through the public contract, and the reason is structural: every bucket key is a distinct
index into a list (find order, previous seat order, filtered roster) with first-occurrence-wins
de-duplication, and bucket 3 holds at most one player. So two players in the same bucket can never
share a key. Rather than fake a tie by reaching into the comparator, the corpus asserts the two
properties that would be wrong if the tiebreak were ever the primary key: an all-joiner roster keeps
join order (`{99,11}`, not `{11,99}`), and a descending previous seat order is preserved (`{9,1}`,
not `{1,9}`). The `playerId` clause stays in the comparator as belt and braces — it is what makes the
sort a total order rather than merely a stable one — and its header comment says so.

## Deferred finding: `Rng` returns a non-uniform FIRST draw for small seeds

While verifying "a different seed gives a different order", a 3-seeker roster gave the **identical**
permutation for seeds 99 and 100. The cause is in `Rng.luau`, not here: xorshift32 with no warm-up
returns a tiny first value from a small state.

```
seeds 1..1000 whose FIRST nextInt(1, 9) is 1:  1000 / 1000   (should be ~111)
same seeds, hashed before use:                  120 / 1000   (uniform)
second-draw histogram, seeds 1..1000:           1=119 2=112 3=112 4=112 5=112 6=110 7=106 8=111 9=106
```

Consequence for any Fisher-Yates shuffle, which spends its first draw on the last position: with a
small or sequential seed, `roster[1]` lands in the **last** seat every time. Logged as **D-02-01** in
`deferred-items.md` with the measurement, the suggested fix (warm up or hash the seed inside
`Rng.new`, then recompute `rng.spec.luau`'s externally computed reference vectors) and interim
guidance for consumers. It was **not** fixed here: `Rng.luau` is outside this plan's file list, it is
shared with the deck shuffle being written in the same wave, and patching around it inside
`SeatOrder` would have hidden the defect from the other consumers. The corpus works around it
honestly — the "different seed" case uses a 9-seeker roster and three seed pairs, with a comment
saying why three seekers is not enough evidence.

## Threat register dispositions discharged

| Threat ID | Disposition | Evidence |
|---|---|---|
| T-2-06 | mitigated | `previousFindOrder` is filtered against the live roster before bucketing; the departed-finisher row asserts it, and mutation M1 proves the row can fail |
| T-2-07 | mitigated | non-integer entries ignored; non-table and missing lists behave as empty; the only errors are the missing round-1 rng and the provable-bug empty order. Four standalone cases drive garbage input |
| T-2-08 | mitigated | the shuffle uses the injected `Rng` only; `grep -q 'math.random'` fails on the module, and M4 proves the error path can fail |
| T-2-09 | accepted | the seat order is public information in the shipped build |
| T-2-10 | accepted | no identity surface; the Phase 4 adapter binds `playerId` from the authenticated player |

## Gates after the final commit

```
head -1 src/server/engine/SeatOrder.luau                        --!strict
grep -c 'require(' src/server/engine/SeatOrder.luau             0
grep -E 'os\.|coroutine|game|Instance' .../SeatOrder.luau       no match (exit 1)
grep -q 'math.random' .../SeatOrder.luau                        no match (exit 1)
grep -c 'why =' tests/engine/seatorder.spec.luau                11
stylua --check src scripts tests                                EXIT=0
selene src scripts tests                   0 errors / 0 warnings / 0 parse errors
selene --config selene.pure.toml src/server/engine
                                           0 errors / 0 warnings / 0 parse errors
lune run scripts/ci/analyze.luau ... src/server/engine tests/engine/seatorder.spec.luau
                                           analyze: ok
lune run scripts/ci/check-guards.luau      ok (63 files, 129 requires, 14 guarded roots)
lune run tests/run.luau -- --filter engine/seatorder
                                           28 passed, 0 failed, 0 todo
lune run tests/run.luau                    374 passed, 0 failed, 3 todo in 14.39s
lune run scripts/verify.luau               verify: all 14 automated steps passed in 16.7s
```

No CI step was added: the corpus runs inside `tests/run.luau`, which `ci.yml` already invokes, so
there is no `run:`-string drift.

## Notes for later plans

- **Phase 6** owns the only production call site. It must pass `previousSeatOrder` from the value
  this function returned last round, and `previousFindOrder` in **find order**, not score order.
- The dealer is `SeatOrder.dealerOf(order)`. Writing `order[1]` at a call site re-creates the second
  dealer rule this plan exists to prevent.
- **Do not hand `Rng.new` a small sequential counter** until D-02-01 is fixed (see above).
- `SeatOrder` ranks only; it does not build the ring. Plan 02-01's `Types.luau` owns the seat
  vocabulary, and the ring builder consumes this order as its seat sequence.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 - Bug] The corpus could not detect a missing bucket 3**
- **Found during:** Task 2, while mutation-proving the corpus
- **Issue:** mutation M5 (treat the previous hider as a joiner) left all 27 cases green, because the
  only previous-hider row used a roster in which bucket 3 and bucket 4 produced the same output.
- **Fix:** added the row "the previous hider outranks a joiner who joined before him"
  (roster `{9,3,1,2,4}`, previous hider 3), which separates the buckets. M5 now fails by name.
- **Files modified:** `tests/engine/seatorder.spec.luau`
- **Commit:** `f443155`

**2. [Rule 1 - Bug] A mixed-type array literal failed the strict typecheck**
- **Found during:** Task 2 verification
- **Issue:** `roster = { 1, "x", 2, 1.5, NAN, math.huge, true, 3 }` inferred `{ number | string }`,
  so `luau-lsp` rejected `true` — the malformed-input case could not compile.
- **Fix:** annotated the literal `:: { any }`.
- **Files modified:** `tests/engine/seatorder.spec.luau`
- **Commit:** `f443155`

**3. [Rule 1 - Bug] A `nil` element in a test table was silently skipped**
- **Found during:** Task 2 verification
- **Issue:** the unusable-round loop listed `nil` among `{ NAN, 2.5, "2", nil, math.huge, true }`;
  that is a hole, so iteration never exercised a missing `round`.
- **Fix:** a missing `round` became its own explicit assertion with a comment saying why.
- **Files modified:** `tests/engine/seatorder.spec.luau`
- **Commit:** `f443155`

### Documented departures from the plan text

**4. Plan corpus row 8's "second case where bucket keys tie" was not written as a tie**
A key tie is unreachable through the public contract (see "The `playerId` tiebreak is unreachable"
above). Faking one would have required reaching into the comparator, which is not exported. The
corpus asserts the reason instead, in two rows that would both fail if `playerId` were ever the
primary key. The plan's own parenthetical already noted that a joiner tie "is impossible"; this is
the same argument extended to the other three buckets.

**5. The RED gate was taken with the spec file, which the plan assigns to task 2**
Task 1 carries `tdd="true"`, and the only way to have a failing test before the module exists is to
write the spec first. The six `<behavior>` rows from task 1 were committed as the RED gate
(`26b34ec`, failing on the missing module), the module as GREEN (`923e5c2`), and task 2 then grew the
same file into the full corpus (`f443155`). Both files are in the plan's `files_modified`, so nothing
outside the plan's scope was touched.

**6. `requirements mark-complete` was not used, and CARD-05/CARD-06 are recorded as Partial**
`gsd-sdk query requirements.mark-complete CARD-05 CARD-06` corrupted the markdown — it inserted a
newline inside the bold span, producing `- [x] **CARD-05\n**: ...` — and it did not update the
traceability table at all. The edit was reverted (`git checkout -- .planning/REQUIREMENTS.md`) and
made by hand. The status chosen is **Partial**, not Complete, following the `FOUND-08` precedent in
the same table: the rule is implemented and locked by a corpus, but it has no consumer until Phase 6,
so the requirement checkboxes stay unticked. **The SDK handler bug is outside this repository and was
not fixed here; the orchestrator should know not to trust it.**

**7. The full suite and `scripts/verify.luau` were run despite the plan forbidding it**
The plan says a wave-parallel plan must not assert on the whole suite. The orchestrator's brief
required confirming both against the baseline, so both were run after the wave sibling had landed its
commits, and both are green (`374 passed, 0 failed, 3 todo`; all 14 steps). Mid-run, the suite did
briefly show `FAIL tests/engine/invariants.spec.luau::<load>` from plan 02-01's half-written file —
which is exactly the failure mode the plan warned about, and nothing in it was touched.

## Self-Check: PASSED

- `src/server/engine/SeatOrder.luau` — FOUND; contains `local function nextSeatOrder`,
  `local function dealerOf`, `round 1 requires an rng`; `--!strict` on line 1; 0 requires; no
  `math.random`; no banned token
- `tests/engine/seatorder.spec.luau` — FOUND; 11 `why =` rows; contains `zero finishers`,
  `round 1 requires an rng`, `dealerOf`; 28 cases pass
- `.planning/phases/02-card-engine-and-pacing-simulator/deferred-items.md` — FOUND; contains D-02-01
- Commits `26b34ec`, `923e5c2`, `f443155`, `a50b937` — all FOUND in `git log`
