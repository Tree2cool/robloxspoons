---
phase: 02-card-engine-and-pacing-simulator
plan: 05
subsystem: engine
tags: [hand, completion, four-of-a-kind, naturals-first, joker-mode, uniqueness-theorem, mutation-proof]

requires:
  - phase: 02-01
    provides: "Types.luau — JOKER_RANK, HAND_SIZE, MAX_HAND, MAX_JOKERS, Rank, CardId, JokerMode, EngineConfig (incl. antiLivelockValve)"
  - phase: 01-02
    provides: "tests/run.luau + Test.Runner (assert-the-reason house rule, deepEqual, throws)"
  - phase: 01-03
    provides: "pure-zone enforcement (selene.pure.toml, luau-lsp --platform standard, check-guards R1/R3/R3b)"
provides:
  - "src/server/engine/Hand.luau — groupsOf, qualifyingRanks, detectCompletion and the exported Completion type"
  - "CARD-10 as executable law: naturals before jokers, with the exact retired ID list (naturals ascending, then jokers ascending) part of the contract"
  - "CARD-12 at the hand level: Wild and Blocker are two branches of ONE function selected by an EngineConfig VALUE; no module-level mode constant exists"
  - "CARD-07's prerequisite: the completing rank is unique over all 2002 five-card hands at j = 2, proven by enumeration and falsified at j = 3"
  - "tests/engine/hand.spec.luau — 10 cases, 7 mutation proofs"
affects: [02-07, 02-08, 02-09, 02-11, 02-12]

tech-stack:
  added: []
  patterns:
    - "A tripwire, not a tiebreak: where a theorem says a case is unreachable, error with the offending values instead of papering over it, then PROVE the branch can fire by constructing the out-of-spec configuration the theorem excludes (j = 3)"
    - "An exhaustive theorem check must assert its own coverage: subsetsChecked == 2002 plus the exact positive counts (378 Wild, 30 Blocker), all three derived combinatorially OFF-code, so a loop-bound bug cannot make the proof vacuous"
    - "A fixture that is accidentally sorted makes a sort untestable: the hand array order case runs three permutations of the same five cards so the ascending-ID selection is load-bearing rather than incidental"
    - "Mode literals are passed at the call site, never iterated out of a `{ JokerMode }` table: Luau widens a singleton-string literal table to `{ string }` and the element stops satisfying the union"

key-files:
  created:
    - src/server/engine/Hand.luau
    - tests/engine/hand.spec.luau
  modified: []

key-decisions:
  - "`groupsOf` errors on a card with no rank (`Hand.groupsOf: card {id} has no rank`) rather than letting `naturalCounts[nil]` raise an opaque index error. A corrupt `rankOf` or a card from another round is a caller bug of the same class as a wrong-size hand, so it gets the same loud treatment"
  - "`ranksFrom(naturalCounts, jokerCount, mode)` is a private helper shared by `qualifyingRanks` and `detectCompletion`, so the two can never disagree about what qualifies and `groupsOf` is walked once per detection rather than twice"
  - "`SET_SIZE = Types.HAND_SIZE` rather than a new constant 4. Four of a kind being the same size as a resting hand is not a coincidence to be hidden behind a second name — it IS the content of 'the pile locks at 5'"
  - "Added an 11th assertion family the plan did not ask for: a case running three permutations of the same five cards. `handOf` builds hands that are already ascending, so both `table.sort` calls could be deleted with every other row still green (mutation M6 confirms only this case catches it)"
  - "The exact enumeration counts (378 Wild, 30 Blocker) are asserted, not just `>= 1`. Both were derived combinatorially before the code ran: Blocker = 3 ranks * 10 remaining cards = 30; Wild = 30 + 3*4*8*2 (a=3, j=1) + 3*4 (a=3, j=2) + 3*6*8 (a=2, j=2, +1 other) = 378"

requirements-completed: [CARD-07, CARD-10, CARD-12]
requirements-contributed: [CARD-01]

duration: ~1 session
completed: 2026-11-03
---

# Phase 2 Plan 05: Hand — Completion Detection Summary

**Four-of-a-kind detection as a pure function of a 5-card hand, a rank map and a joker mode: naturals are spent before jokers (optimal on both stranding and joker consumption, not merely spec-locked), the retired four are a deterministic function of the hand's contents by ascending card ID, and the "no tiebreak needed" claim is proven over all 2002 five-card hands at `j = 2` and then made to fire at `j = 3`.**

## Performance

- **Tasks:** 2 of 2 (task 1 ran as a TDD RED/GREEN pair)
- **Files created:** 2; **modified:** 0
- **`hand.spec.luau` isolated:** `10 passed, 0 failed, 0 todo in 0.01s`
- **`--filter engine`:** `87 passed, 0 failed, 3 todo in 0.38s`
- **Full suite:** `429 passed, 0 failed, 3 todo in 15.28s` at the end of the wave (verified baseline at
  `0e3bbba` was 380; +10 from this plan, the rest from wave-3 siblings 02-04/02-06/02-13). The first
  post-plan run read `409 passed, 0 failed` before those siblings finished landing
- **`scripts/verify.luau`:** `verify: all 14 automated steps passed in 17.1s`
- **Purity layers:** `selene --config selene.pure.toml src/server/engine` → `0 errors`; `analyze --platform standard src/server/engine` → `ok`; `check-guards` → `ok (72 files, 153 requires, 19 guarded roots)`

## Task Commits

1. **Task 1 (RED): failing hand rows before `Hand` exists** — `996cdb0` (test)
2. **Task 1 (GREEN): `Hand` — grouping, qualifying ranks, naturals-first retirement** — `21929f6` (feat)
3. **Task 2: prove naturals-first, the uniqueness theorem and the Wild/Blocker asymmetry** — `99b2278` (test)
4. **Task 2 follow-up: make the ascending-ID sort load-bearing** — `febe3a8` (test)

No REFACTOR commit: the GREEN implementation needed no cleanup.

## The `Completion` type, verbatim

Plan 02-07 builds the `Completed` event from this (`Types.Event` already declares
`{ kind: "Completed", seat, rank, retired, fifth }`, so the three middle fields map straight across):

```luau
export type Completion = {
	rank: Types.Rank, -- the NATURAL rank completed; never JOKER_RANK
	retired: { Types.CardId }, -- exactly 4 IDs: naturals first, then jokers, each group ascending
	fifth: Types.CardId, -- the card that stays in the hand and travels on with the seat's removal
	naturalsUsed: number, -- 2, 3 or 4
	jokersUsed: number, -- 0, 1 or 2; always SET_SIZE - naturalsUsed
}
```

Exports: `groupsOf`, `qualifyingRanks`, `detectCompletion`. One `require`, of `./Types`.

## The exact retirement rule

For the single qualifying rank `r`:

1. `naturalsUsed = math.min(naturalCounts[r], 4)` — **take the most naturals available**. Research
   3.3: 4 naturals strands 0 cards of `r` and spends 0 jokers; 3+1j strands 1 and spends 1; 2+2j
   strands 2 and spends 2. Naturals-first is therefore optimal on both axes at once.
2. `jokersUsed = 4 - naturalsUsed` (0, 1 or 2).
3. `retired` = the `naturalsUsed` **lowest** card IDs of rank `r`, ascending, **followed by** the
   `jokersUsed` **lowest** joker IDs, ascending. The two groups are never interleaved.
4. `fifth` = the one hand card not in `retired` — found by scanning the hand in its own array order,
   so it is well defined for any hand permutation.
5. `#retired == 4` and `fifth ~= nil` are asserted before returning.

Consequences: a **held joker is not spent when four naturals are available** (row 2 of the table
below), and a 3+2j hand keeps a joker as its fifth (02-VALIDATION.md's falsifiability row).

Qualification, by mode — the same function, two branches, selected by `EngineConfig.jokerMode`:

- **Wild:** `naturalCounts[r] >= 1 and naturalCounts[r] + jokerCount >= 4`. The `>= 1` clause anchors
  the set in a natural because an all-joker set has no rank; it is belt-and-braces at `j <= 2`
  (a 5-card hand cannot hold 3 jokers) and reopens at `j >= 3`.
- **Blocker:** `naturalCounts[r] == 4`. Jokers contribute nothing. CARD-12.

## The retirement table as locked by the spec

| Shape | Mode | spec (card id → rank) | retired | fifth | naturals/jokers |
|-------|------|----------------------|---------|-------|-----------------|
| 4 naturals + 1 other natural | Wild | `{5,3,3,3,3}` | `{2,3,4,5}` | 1 | 4 / 0 |
| 4 naturals + 1 joker | Wild | `{3,0,3,3,3}` | `{1,3,4,5}` | 2 (**the joker**) | 4 / 0 |
| 3 naturals + 2 jokers | Wild | `{0,3,3,3,0}` | `{2,3,4,1}` | 5 (a joker) | 3 / 1 |
| 3 naturals + 1 joker + 1 other | Wild | `{5,3,0,3,3}` | `{2,4,5,3}` | 1 | 3 / 1 |
| 2 naturals + 2 jokers + 1 other | Wild | `{0,3,5,0,3}` | `{2,5,1,4}` | 3 | 2 / 2 |
| 4 naturals + 1 joker | Blocker | `{3,0,3,3,3}` | `{1,3,4,5}` | 2 | 4 / 0 |

Each row asserts `rank`, `naturalsUsed`, `jokersUsed`, `naturalsUsed + jokersUsed == 4`, the exact
`retired` list by `deepEqual` and `fifth`.

## The uniqueness theorem: observed counts

Deck `rankOf = {1,1,1,1, 2,2,2,2, 3,3,3,3, 0,0}` (ranks = 3, jokers = 2, T = 14), **all**
C(14,5) five-card subsets enumerated, both modes checked on every subset:

| Quantity | Observed | Derived off-code |
|----------|----------|------------------|
| `subsetsChecked` | **2002** | C(14,5) = 2002 |
| `wildCompletions` (`#qualifyingRanks == 1` in Wild) | **378** | 30 + 192 + 12 + 144 = 378 |
| `blockerCompletions` | **30** | 3 ranks × 10 remaining cards = 30 |
| hands satisfying **two** ranks, either mode | **0** | 0 — research 3.3's claim |

The Wild derivation in full: `a=4` → 3·C(4,4)·10 = 30; `a=3, j=1` → 3·C(4,3)·8·C(2,1) = 192;
`a=3, j=2` → 3·C(4,3) = 12; `a=2, j=2` plus one other natural → 3·C(4,2)·8 = 144. All three counts
were computed before the enumeration was run, so the spec compares the code against arithmetic rather
than against itself. Every one of the 378 Wild completions also round-trips through
`detectCompletion` and is asserted to use the qualifying rank — safe precisely because the tripwire
cannot fire here.

## Mutation proofs (verbatim output)

Seven mutations, each applied alone to the committed source, the spec run, then the file restored
with `git checkout --`. Every mutation turns the suite red, and each fails the case that owns the
claim.

**M1 — the uniqueness tripwire turned into a tiebreak** (`if #qual >= 2 then` → `if false then`):

```
FAIL tests/..._isolated/handonly.spec.luau::the uniqueness tripwire can fire (j = 3 falsification)
     expected function to throw, but it returned normally
9 passed, 1 failed, 0 todo in 0.01s
```

**M2 — jokers-first instead of naturals-first**
(`naturalsUsed = math.min(naturalCounts[rank], SET_SIZE)` → `math.max(SET_SIZE - jokerCount, 0)`):

```
FAIL tests/..._isolated/handonly.spec.luau::the retirement table from research 3.3, row by row
     4 naturals + 1 joker, Wild: the joker is the fifth: wrong naturalsUsed (expected 4, got 3)
FAIL tests/..._isolated/handonly.spec.luau::the retired set does not depend on the hand's array order
     hand order 1,2,3,4,5: retired must be the naturals ascending then the lowest joker (expected { [1] = 2, [2] = 3, [3] = 4, [4] = 1 }, got { [1] = 2, [2] = 3, [3] = 1, [4] = 5 })
FAIL tests/..._isolated/handonly.spec.luau::retirement is deterministic across repeated calls
     the retired set must be the naturals ascending then the lowest joker (expected { [1] = 2, [2] = 3, [3] = 4, [4] = 1 }, got { [1] = 2, [2] = 3, [3] = 1, [4] = 5 })
7 passed, 3 failed, 0 todo in 0.01s
```

**M3 — the wrong-size error turned into a silent `nil`**:

```
FAIL tests/..._isolated/handonly.spec.luau::a hand of the wrong size is a loud caller bug
     expected function to throw, but it returned normally
9 passed, 1 failed, 0 todo in 0.01s
```

**M4 — the Blocker branch made to behave like Wild** (`if a == SET_SIZE then` →
`if a >= 1 and a + jokerCount >= SET_SIZE then`):

```
FAIL tests/..._isolated/handonly.spec.luau::a joker can never complete a set in Blocker mode
FAIL tests/..._isolated/handonly.spec.luau::the same EngineConfig value selects the mode, in one process
FAIL tests/..._isolated/handonly.spec.luau::the completing rank is unique for every reachable 5-card hand at j <= 2 (exhaustive)
     Blocker completions over all 2002 hands (expected 30, got 378)
FAIL tests/..._isolated/handonly.spec.luau::the uniqueness tripwire can fire (j = 3 falsification)
     /home/user/robloxspoons/src/server/engine/Hand:127: Hand.detectCompletion: completing rank is not unique (1, 2)
6 passed, 4 failed, 0 todo in 0.01s
```

**M5 — `groupsOf` made to key the joker rank as a natural**:

```
FAIL tests/..._isolated/handonly.spec.luau::the retirement table from research 3.3, row by row
     /home/user/robloxspoons/src/server/engine/Hand:128: Hand.detectCompletion: completing rank is not unique (0, 3)
FAIL tests/..._isolated/handonly.spec.luau::a joker can never complete a set in Blocker mode
     /home/user/robloxspoons/src/server/engine/Hand:128: Hand.detectCompletion: completing rank is not unique (0, 3)
FAIL tests/..._isolated/handonly.spec.luau::the same EngineConfig value selects the mode, in one process
     /home/user/robloxspoons/src/server/engine/Hand:128: Hand.detectCompletion: completing rank is not unique (0, 3)
FAIL tests/..._isolated/handonly.spec.luau::the completing rank is unique for every reachable 5-card hand at j <= 2 (exhaustive)
     Wild: hand 1,2,3,13,14 satisfied 2 ranks (expected true, got false)
FAIL tests/..._isolated/handonly.spec.luau::the uniqueness tripwire can fire (j = 3 falsification)
FAIL tests/..._isolated/handonly.spec.luau::the retired set does not depend on the hand's array order
     /home/user/robloxspoons/src/server/engine/Hand:128: Hand.detectCompletion: completing rank is not unique (0, 3)
FAIL tests/..._isolated/handonly.spec.luau::retirement is deterministic across repeated calls
     /home/user/robloxspoons/src/server/engine/Hand:128: Hand.detectCompletion: completing rank is not unique (0, 3)
FAIL tests/..._isolated/handonly.spec.luau::groupsOf never keys the joker rank
     JOKER_RANK must never be a key of naturalCounts (expected nil, got 2)
2 passed, 8 failed, 0 todo in 0.01s
```

Note what M5 reveals: keying jokers as rank 0 does not merely mislead a bot, it makes the joker rank
*qualify*, so the uniqueness tripwire fires on an ordinary hand. The tripwire is load-bearing against
a real defect class, not only against a hypothetical `j >= 3` pool.

**M6 — both ascending-ID sorts deleted**:

```
FAIL tests/..._isolated/handonly.spec.luau::the retired set does not depend on the hand's array order
     hand order 4,1,5,3,2: retired must be the naturals ascending then the lowest joker (expected { [1] = 2, [2] = 3, [3] = 4, [4] = 1 }, got { [1] = 4, [2] = 3, [3] = 2, [4] = 1 })
9 passed, 1 failed, 0 todo in 0.01s
```

Exactly one case catches it — the one added as a deviation. Before that case existed this mutation
was **green**, which is why it was added.

**M7 — the enumeration's outer loop bound off by one** (`for a = 1, T - 4` → `T - 5`), the coverage
assertion proving the theorem check cannot go vacuous:

```
FAIL tests/..._isolated/handonly.spec.luau::the completing rank is unique for every reachable 5-card hand at j <= 2 (exhaustive)
     the enumeration must visit every 5-card subset of the 14-card deck (expected 2002, got 2001)
9 passed, 1 failed, 0 todo in 0.02s
```

The spec paths read `tests/..._isolated/handonly.spec.luau` because the mutation runs used a
throwaway `--root` directory (see "Wave-3 isolation" below); the case names and all assertion text
are verbatim.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical coverage] The ascending-ID sort was untestable**

- **Found during:** Task 2, while choosing mutations
- **Issue:** `handOf` returns `hand = {1, 2, ..., #spec}`, already ascending, and
  `detectCompletion` collects candidate IDs by walking the hand in array order. Both `table.sort`
  calls could therefore be deleted with all nine planned cases still green (mutation M6). A real
  hand is an array in *draw* order, so the determinism guarantee the plan spends two paragraphs on
  — and threat T-2-21's whole mitigation — was true of the fixture, not of the code.
- **Fix:** added a tenth case, "the retired set does not depend on the hand's array order", running
  three permutations of the same five cards (`{1,2,3,4,5}`, `{4,1,5,3,2}`, `{5,4,3,2,1}`) and
  asserting one identical `retired` list and `fifth`.
- **Files modified:** `tests/engine/hand.spec.luau`
- **Commit:** `febe3a8`

**2. [Rule 2 - Missing validation] `groupsOf` on a card with no rank**

- **Found during:** Task 1
- **Issue:** a card ID absent from `rankOf` would reach `naturalCounts[nil] = ...` and raise
  `table index is nil`, four frames from the actual cause, or — worse — be counted as a natural of
  rank `nil`.
- **Fix:** an explicit `error(\`Hand.groupsOf: card {id} has no rank\`)`, the same loud-caller-bug
  treatment the plan prescribes for a wrong-size hand.
- **Files modified:** `src/server/engine/Hand.luau`
- **Commit:** `21929f6`

**3. [Rule 3 - Blocking] A `{ JokerMode }` table does not typecheck at the call site**

- **Found during:** Task 2 verification
- **Issue:** `local MODES: { Types.JokerMode } = { "Wild", "Blocker" }` then
  `Hand.detectCompletion(rankOf, hand, mode)` fails `analyze` with
  `Expected '"Blocker" | "Wild"' but got 'string | string'`. Luau widens the singleton-string
  literal table's element type. Plan 02-01 hit the identical TypeError and solved it with a visitor.
- **Fix:** both modes are passed as **literals** at the call site in the non-completing case, and
  the `MODES` table was deleted. The commentary records why, so it is not reintroduced.
- **Files modified:** `tests/engine/hand.spec.luau`
- **Commit:** `99b2278`

### Transient, resolved by its owner (not logged as a defect)

Mid-wave, `scripts/verify.luau` stopped at its `analyze` step with
`tests/engine/pool.spec.luau(341,80): TypeError: Expected this to be '"Blocker" | "Wild"' but got
'string | string'` — the same widening defect as deviation 3, in **wave-3 sibling plan 02-04's
uncommitted working copy** (` M tests/engine/pool.spec.luau`, +379 lines, at the time). It was not in
any commit and not this plan's file, so it was left untouched and deliberately **not** written to the
shared `deferred-items.md`, which a concurrent sibling also owns. While it was outstanding, the rest
of the tree was shown clean by running `analyze` with that one file excluded:

```
analyze --platform standard --ignore "**/fixtures/**" --ignore "**/pool.spec.luau" \
        src/server/engine scripts tests   ->  analyze: ok
```

**02-04 has since committed its fix.** The final gate run from this working tree is
`verify: all 14 automated steps passed in 17.1s`, so nothing is outstanding. Nothing was deferred by
this plan.

Note for the verifier: while siblings were mid-edit, a single full-suite run read
`420 passed, 9 failed` and the next read `429 passed, 0 failed` with no commit in between — the
failures were a snapshot of other agents' half-written files, not flakiness in the suite. This plan's
10 rows were `ok` in every run.

## Wave-3 isolation note (method, for the verifier)

`tests/run.luau` loads **every** discovered spec before applying `--filter`, so during a parallel
wave a sibling's RED spec (a spec whose module does not exist yet) fails the run regardless of the
filter. To get a trustworthy exit code for this plan's own rows, each run used a throwaway
`tests/_wave3_isolated_05/handonly.spec.luau` that re-exports `../engine/hand.spec` and a
`--root tests/_wave3_isolated_05`. **The directory was deleted before the final commit** and never
entered a commit. Once siblings 02-04 and 02-06 landed their modules, the ordinary
`--filter engine` run went green (`87 passed, 0 failed, 3 todo`) and confirmed the same 10 rows.

## Threat Mitigations Implemented

| Threat ID | Mitigation as built |
|-----------|---------------------|
| T-2-21 | Retirement is a deterministic function of the hand's *contents*: lowest IDs within each group, naturals group before jokers group, proven invariant under three hand permutations (deviation 1) and across five repeated calls |
| T-2-22 | `detectCompletion` errors with the offending ranks instead of tiebreaking; the branch is proven reachable by the `j = 3` case and by mutation M5 |
| T-2-23 | Wrong-size hand is a loud `error` at 4 and at 6 cards, mutation-proven (M3) |
| T-2-24 | `jokerMode` is only ever a parameter. `grep -qE 'SHIP_WILDS\|local JOKER_MODE\|JOKERS_ARE'` exits 1; both branches run back to back in one process in case 4, and mutation M4 proves the Blocker branch is not dead code |
| T-2-25 | accepted — `Hand` sees card IDs and a rank map, holds no identity, emits nothing but its return value |

## For Plan 02-07 (`Engine.apply`), 02-09 (bot) and 02-11

- Call `detectCompletion` **only after a Draw**, and only with `#hand == 5`. It errors otherwise, by
  design — do not pre-check and swallow; a wrong size there is a hand-size invariant break.
- Map a `Completion` straight onto `Types.Event`'s `Completed`: `rank`, `retired`, `fifth` carry
  across unchanged. `naturalsUsed` / `jokersUsed` are metrics (jokers consumed per round is bounded
  by `MAX_JOKERS`), not event fields.
- `retired` cards leave play; `fifth` travels with the seat's removal (Rule 8: never destroyed).
- The greedy bot must call `Hand.groupsOf` rather than recounting — it already excludes `JOKER_RANK`
  from the count table, which is what stops a bot "collecting rank 0" (research Pitfall 2).
- A pool with `jokers >= 3` reopens two proofs at once (all-joker sets, rank uniqueness) and will now
  **error loudly** instead of mis-selecting a rank. `Pool.validate`'s `TooManyJokers` is the gate
  that keeps that unreachable; keep them in sync.

## Acceptance Criteria

| Criterion | Result |
|-----------|--------|
| `head -1 Hand.luau` is `--!strict` | `--!strict` |
| `grep -q 'completing rank is not unique' Hand.luau` | pass |
| `grep -q 'hand must hold 5' Hand.luau` | pass |
| `grep -c 'Blocker' Hand.luau` >= 1 | 2 |
| `grep -qE 'SHIP_WILDS\|local JOKER_MODE\|JOKERS_ARE' Hand.luau` FAILS | exit 1 |
| `grep -qE 'os\.\|coroutine\|game\|Instance\|math.random' Hand.luau` FAILS | exit 1 |
| `grep -c 'require(' Hand.luau` == 1 | 1 |
| `selene --config selene.pure.toml src/server/engine` | `0 errors` |
| hand spec exits 0, >= 9 cases | `10 passed, 0 failed` |
| `grep -q '2002'` / `'completing rank is not unique'` / `'hand must hold 5'` in the spec | pass / pass / pass |
| `grep -c 'Blocker'` in the spec >= 4 | 18 |
| `grep -q 'deepEqual'` in the spec | pass |

## Self-Check: PASSED

- `src/server/engine/Hand.luau` — FOUND
- `tests/engine/hand.spec.luau` — FOUND
- commits `996cdb0`, `21929f6`, `99b2278`, `febe3a8` — all FOUND in `git log`
- `tests/_wave3_isolated_05/` — confirmed ABSENT from the working tree and from every commit
