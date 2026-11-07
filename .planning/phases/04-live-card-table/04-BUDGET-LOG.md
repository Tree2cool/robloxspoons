# Phase 4 — test runtime budget log

> Evidence for plan 04-20's budget decision checkpoint. **Append one row per wave.**
> Written by the orchestrator, because the measurement that matters is a *controlled* one and no
> single executor can take it: each sees only its own worktree.

## Why wall clock alone is useless here

The same unchanged tree has measured **20.15 s, 26.88 s and 31.54 s** on this container at different
times — an 11 s spread, roughly 3.7x this phase's entire +3 s allowance. An absolute ceiling read off
any one of those is noise, which is why `04-VALIDATION.md` makes the 23.5 s figure a target rather
than a tripwire and makes the per-spec allocation the gate.

**The method that does work, and the one used below:** measure the pre-wave commit and the post-wave
commit *back to back on the same machine under the same load*, and compare the **delta**. A git
worktree at the earlier commit makes this exact.

## Measurements

| Wave | Pre-wave commit | Pre (min) | Post (min) | **Delta** | Cases | Note |
|------|-----------------|-----------|------------|-----------|-------|------|
| 1 | `ae376d6` | 26.88 s (657) | 27.98 s (677) | **+1.10 s** | +20 | Measured back to back. Includes the four guard fixture roots (~0.9 s of subprocess work), which was the single largest named cost in the allocation table and is now **spent** — later waves are in-process pure specs and should be far cheaper. |

| 2 | `64cae6e` | 24.33 s (677) | 24.15 s (733) | **~0.00 s** (-0.18 s, i.e. within noise) | +56 | Measured back to back. Includes the `src/shared/Card` pure zone's extra selene subprocess, which plan 04-04 had budgeted at ~0.4 s — **it is below run-to-run noise at this scale.** 56 new cases for no measurable wall-clock cost, because they are all in-process pure specs. |

| 3 | `7292028` | 24.24 s (733) | 24.83 s (792) | **+0.59 s** | +59 | Four plans, all in-process pure specs. `cardtable.spec` is the heaviest single spec in the phase at 0.12-0.14 s against its 0.35 s cap (3 seeds/cell). |

| 4 | `da7e7dd` | 24.91 s (792) | 24.53 s (812) | **~0.00 s** (-0.38 s, within noise) | +20 | Two plans, both pure in-process specs. |

| 5 | `72db3ef` | 24.88 s (812) | 25.11 s (816) | **+0.23 s** | +4 | One plan. `deci_lock` scans 51 files through `lex.stripComments`, which is the cost here rather than the 4 cases. |

| 6 | `0c37c63` | 24.44 s (816) | 24.72 s (832) | **+0.28 s** | +16 | Two plans. `renderer_discipline` scans comment-stripped source in process, so no subprocess cost. |

| 7 | `61658c1` | 25.39 s (832) | 25.20 s (837) | **~0.00 s** (-0.19 s, within noise) | +5 | One plan. Executor measured its own spec at +0.01-0.03 s and cut nothing. |

| 8 | `5addff5` | 25.39 s (837) | 25.37 s (841) | ~0.00 s | +4 | One plan; executor measured its own spec at +0.03-0.05 s. |
| 9 | `c2e01eb` | 25.66 s (841) | 24.89 s (858) | **~0.00 s** (-0.77 s, noise) | +17 | One plan plus two wire gaps and the `Surface` contract. Executor measured `tests/card` at +0.09 s. |

---

## THE AUTHORITATIVE FIGURE — measure the phase, not the sum of waves

| | Commit | Cases | Min of 2 |
|---|---|-------|----------|
| **Pre-phase** | `ae376d6` (before wave 1) | 657 | **23.65 s** |
| **Post-phase** | after wave 9 | 858 | **24.89 s** |
| **PHASE COST** | | **+201 cases** | **+1.24 s** |

**+1.24 s against the +3.0 s allowance. The budget holds with 1.76 s of headroom.**

### Re-measured after the code-review fixes, on a quieter machine

| | Commit | Cases | Min of 2 |
|---|--------|-------|----------|
| Pre-phase | `ae376d6` | 657 | **20.91 s** |
| Post-fixes | HEAD | 871 | **21.90 s** |
| **FINAL PHASE COST** | | **+214 cases** | **+0.99 s** |

**+0.99 s against the +3.0 s allowance — 2.01 s of headroom**, including the 13 cases the
code-review fixes added (5 Warning gates plus 5 Info gates and a new `service_wiring.spec`).

Both readings used the same method, and they agree to within 0.25 s on the *cost* (+1.24 s vs
+0.99 s) while the absolute wall clock moved by ~3 s between them (23.65 s vs 20.91 s for the
identical 657-case commit). **That is the case for the pre/post method in one line: the absolute
numbers drift with the container, the delta does not.**

### Why this differs from the sum of the per-wave deltas (~2.20 s)

**Summing per-wave deltas accumulates measurement noise; a single phase-wide pre/post does not.**
Each wave's delta carried roughly +/-0.5 s of container noise, and nine of those summed drift upward
even when several individual waves measured *negative* (waves 2, 4, 7, 8 and 9 all read at or below
zero, which is not physically possible as a real cost).

**So the per-wave rows above are useful for attribution — they tell you wave 1's guard fixtures were
the one real subprocess cost — but the phase-wide row is the number the budget decision should use.**
Had I reported the running sum at the gate, I would have claimed ~2.20 s of 3.00 s and left only
0.80 s of apparent headroom, when the true figure is 1.24 s used and 1.76 s free.

**Lesson for later phases: take ONE controlled pre/post measurement across the whole phase. Use
per-wave deltas only to attribute cost, never to total it.**

**Watch item for waves 7-9.** Three renderer plans and the gate plan remain, with **0.80 s** left.
04-16's text-scan gate cost ~0.28 s together with 04-15's pure spec; 04-17/18/19 each add a similar
scan over a growing `src/client/ui`. If a per-plan spec threatens the remaining budget, **cut sample
sizes — never a mutation, a non-vacuity assertion or a clean control** (04-20's rule). A genuine
overrun is an owner decision at 04-20's checkpoint, not something to absorb silently. (wave 1 1.10 s, wave 2 ~0.00 s,
wave 3 0.59 s, wave 4 ~0.00 s, wave 5 0.23 s, wave 6 0.28 s, wave 7 ~0.00 s), for **+180 cases** across 17 of 20 plans.

**Note on how the two waves differ.** Wave 1's 1.10 s was almost entirely the four guard **fixture
roots** — subprocess work, the single largest named cost in the allocation table, and now spent.
Wave 2's 56 pure in-process cases cost nothing measurable. That is the shape the allocation table
predicted, and it means the remaining waves (also pure specs, plus renderer specs) should stay cheap.
**The thing to watch is any NEW subprocess gate, not the case count.**

## What this means for 04-20's checkpoint

- Do **not** compare a post-phase reading against the 20.15 s baseline recorded during planning.
  That number was taken on a quiet machine and the machine is not quiet now; the pre-wave reading
  above for the very same commit was 26.88 s.
- Take the final reading the same way: `git worktree add` at the pre-phase commit, measure both,
  compare the delta.
- Three consecutive readings within ~0.3 s of each other (as wave 1's were) indicate a *stable*
  machine, not an absence of load — stability and speed are different properties.
