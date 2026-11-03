# Phase 2 — Deferred Items

Out-of-scope discoveries logged during execution. Each names the plan that found it, why it was
not fixed in place, and what a fix would cost.

## D-02-01 — `Rng` needs a warm-up: the FIRST draw from a small seed is not uniform

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
