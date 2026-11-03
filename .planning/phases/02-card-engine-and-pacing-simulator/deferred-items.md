# Phase 2 — Deferred Items

Out-of-scope discoveries logged during execution. Each names the plan that found it, why it was
not fixed in place, and what a fix would cost.

## D-02-01 — ~~`Rng` needs a warm-up: the FIRST draw from a small seed is not uniform~~ **RESOLVED**

**Resolved 2026-11-03 by the orchestrator**, before wave 3, because plan 02-04's Fisher-Yates deal
and every seeded simulator trial are downstream of it and would have inherited the bias silently.
`Rng.new` now runs the recurrence `WARM_UP_STEPS = 3` times before handing out any value. Measured
over seeds 1..2000, the first `nextInt(1, 9)` went from chi-square **13051.60** (counts
1820,180,0,0,0,0,0,0,0) to **0.05**. One step already suffices; three is margin.

The recurrence itself is untouched, so `rng.spec.luau` still tests the same xorshift32 — its two
reference vectors were recomputed independently in Python rather than by running the changed code,
preserving the reason they exist. A new case asserts first-draw uniformity across 2,000 sequential
seeds and was mutation-proven: at `WARM_UP_STEPS = 0` it fails, at 1 it passes (genuinely uniform),
so it tests the property rather than the constant.

Original report follows.


**Found by:** plan 02-02 (`SeatOrder`'s round-1 seeded shuffle), 2026-11-03
**File:** `src/server/engine/Rng.luau` (not a plan 02-02 file)
**Severity:** affects fairness of any seeded shuffle driven by a small or sequential seed

xorshift32 with no warm-up returns a tiny first value for a small state, because its first three
shifts cannot spread the low bits. Measured against the shipped module:

```
seeds 1..1000 whose FIRST nextInt(1, 9) is 1:   1000 / 1000   (should be ~111)
same seeds, hashed before use:                   120 / 1000   (uniform)
second-draw histogram, seeds 1..1000:            1=119 2=112 3=112 4=112 5=112 6=110 7=106 8=111 9=106
```

So the first draw is unusable for small seeds and every draw after it is fine. Consequence for a
Fisher-Yates shuffle, which spends its first draw on the last position: with a sequential match seed,
`roster[1]` lands in the LAST seat every round. Observed in `SeatOrder` round 1 for seeds 7, 99 and
100 on a 9-seeker roster — all three put the same player last.

**Why plan 02-02 did not fix it:** `Rng.luau` is outside this plan's file list, it is a shared
dependency of the deck shuffle being written in the same wave (plan 02-01), and
`tests/engine/rng.spec.luau` pins exact reference outputs computed outside Luau — a warm-up changes
every one of them. Patching it locally inside `SeatOrder` would hide the defect from the other
consumers rather than remove it.

**Suggested fix (one plan, ~30 lines):** discard the first N draws (N = 4 is enough for xorshift32) or
hash the seed inside `Rng.new`, then recompute the reference vectors in `rng.spec.luau` and add a
case asserting the first draw is uniform across seeds 1..1000. Plan 02-07 or the phase's simulator
plans are the natural home, because they are the first code whose *results* depend on it.

**Interim guidance for consumers:** do not hand `Rng.new` a small sequential counter. Hash the seed
at the call site, or draw and discard once before the first meaningful draw.

---

## D-02-02 — `--filter` cannot isolate your own spec during a parallel wave

**Found by:** plans 02-04, 02-05 and 02-13 independently, wave 3, 2026-11-03
**File:** `tests/run.luau` (nobody's plan file)
**Severity:** process friction, not a product defect — but it wastes time and invites wrong conclusions

`tests/run.luau` **loads every discovered spec before applying `--filter`**. So while a parallel wave
is in flight, a sibling's RED spec — a test written before its module exists, which is exactly what
TDD produces — fails the run regardless of the filter. Three executors hit this independently:
`--filter engine/hand` reported failures that were entirely 02-04's and 02-06's half-written files.

The exit code of a filtered run is therefore untrustworthy precisely when you most want to isolate
your own work. It also produces alarming-looking artifacts: one whole-suite snapshot read
`420 passed, 9 failed` and the next `429 passed, 0 failed` with no commit in between — sibling
agents mid-write, not flakiness. Anyone chasing that as a real failure loses an hour.

**Workaround used (correct, costs nothing):** a throwaway `tests/_wave_isolated_NN/` directory
re-exporting your own spec, run with `--root`, deleted before the first commit.

**A fix would be:** apply `--filter` at discovery time rather than after load, so an unrelated spec
that cannot even be required is never loaded. Not done here because `tests/run.luau` is shared by
every plan in the wave and this is harness ergonomics, not correctness. Worth doing before the next
phase that runs a wide parallel wave.
