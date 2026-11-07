# Phase 4 — execution carry-forwards

> Facts discovered by executors mid-phase that later waves need and would otherwise rediscover.
> Orchestrator-maintained. **Append, never rewrite.**

## Tooling

- **`tests/run.luau` does NOT catch what CI catches. Run `scripts/verify.luau`.**
  Plan 04-06 wrote a spec that `tests/run.luau` ran green while `verify.luau`'s standard-platform
  typecheck rejected it, on command-union field access. An executor that runs only the suite can
  hand back a type-broken spec that passes locally and fails CI. Every executor brief from wave 3
  onward says to run `verify.luau`.
  *Mitigation used in 04-06:* type command lists as `{ any }` in specs where the union field access
  trips the stricter checker.
- **`analyze.luau --ignore '**/fixtures/**'` is refused by the sandbox.** Run analyze without
  `--ignore`; it passes, and `verify.luau` passes too.
- **Some worktrees refuse heredocs and shell loops** (plan 04-02 hit this). Use the Write/Edit tools
  instead; content is unaffected.
- **`lune` is at `~/.rokit/bin/lune`, never on `PATH`.** `--root`, never `--filter`.

## Measurement

- **Compare case counts and deltas, never raw wall clock.** The same unchanged tree has measured
  **20.15 s, 26.88 s, 27.08 s and 31.54 s** on this container. Wave 1's apparent 4.5 s "breach"
  was 1.10 s of real cost once measured against a worktree at the pre-wave commit under the same
  load. Method and running total live in `04-BUDGET-LOG.md`.

## Cross-plan handoffs

- **Plan 04-12 must CALL `CardRouting.publish(publisher, events, copyOf, userIdOfSeat)`**, not
  re-derive the routing. Plan 04-05 added it as a deviation because the planned API left the
  "Notice to wrong player" and "Table gains a rank" mutants with no shipped code to attach to — they
  could only ever have been spec-local. It sends the public batch once via `toSeated("Table")` and
  each notice via `toPlayer(userIdOfSeat(seat), "Notice")`.
- **Plan 04-13 must build `NetServer`'s publisher via `CardRouting.makePublisher` AND add the
  source assertion that it does.** 04-05 could not verify this from its own worktree because
  `NetServer` is not loaded there. Without that assertion the R4 guard reverts to being tested
  against a rebuilt copy, which is exactly the defect the plan-checker caught (deleting
  `assertPublic` from production left the suite green).
- **Rejection codes, measured by 04-03** — for D-12's silent-rejection assertions: `UnknownKey`,
  `MissingKey`, `NotFinite`, `WrongType`, `NotInteger`, `OutOfRange`, `NotTable`, `ForbiddenType`.
  `exactKeys` reports `MissingKey` before `UnknownKey`.
- **Rate limits shipped by 04-03:** `Draw` and `Pass` each get burst 8 / refill 6 per second. These
  are starting values for Phase 8, not measured; V-34 stays LOW confidence.

## Gates with a known, recorded limit

- **"Table gains a rank for a non-retired card" has no production-source mutant.** `split` never
  reads `rankOf`, so no one-line production edit produces it; a spec-level decorating publisher
  covers it. Recorded by 04-05 rather than papered over.
- **The descending-copy mutant shows which half of that gate works.** The permutation assertion
  stays *green* on it (descending is still a valid permutation); only the
  compare-against-production assertion catches it. That assertion is load-bearing.

## HARD DEPENDENCY: plan 04-19 must implement `Surface` or F8's protection is incomplete

Plan 04-10 added **`Surface.destroyOffenders(root) -> number`** as a Rule-2 deviation, and the reason
matters: the planned `Surface` contract had `scan` return **descriptions only**, so "the offending
instance is destroyed" was not expressible. Without destruction, a mid-flight `Active` GuiObject
would be **reported and then go on sinking input until the cut-off** — which is exactly the F8 hole
the plan-checker found, half-fixed.

**So plan 04-19 owes two things, and D-30 depends on both:**
1. **`Surface.destroyOffenders(root)`** — actually destroys what `scan` finds, returning the count.
2. **`Surface.scan` must cover all FIVE input-taking kinds**, not just `Active`. 04-10's driver
   *trusts* that coverage and says so; it is **not proven** in 04-10's spec. If 04-19's `scan` covers
   only `Active`, the flourish gate passes while the real hole stays open.

Why this is not cosmetic: D-30 requires control to return to the finisher **instantly**, and find
order drives SCORE-01..03 — holding a finisher still literally costs them points. An input-sinking
GuiObject during the 1.5 s flourish breaks that silently.

## A third confirmation: `verify.luau` catches what `tests/run.luau` does not

Plan 04-10 hit it too: `local ok, err = pcall(voidFn)` is rejected by the standard-platform
typecheck and **passes** under `tests/run.luau`. Its fix was a small `attempt` helper for void
functions. Three independent confirmations now (04-06 command unions, 04-08 literal-table iteration,
04-10 `pcall` of a void function). **Run `verify.luau`.**

## Gate weaknesses executors recorded rather than hid

- **04-10's "3 mutations" counter is order-dependent module state.** If the F8 case fails first, the
  `(f)` count assertion fails as a **cascade**, so that second failure is not an independent signal.
  Read it as one finding, not two.
- **04-10's rule-1 spec-lock reads the driver source** and asserts its only require is
  `../Config/Card` and that nothing names shop or cosmetics. That is the enforcement for the driver
  side of FOUND-05, since the renderer deliberately is not a guarded root.

## Findings from executors that are NOT defects, and must not be "fixed"

- **The D-20 stall threshold's healthy control cannot distinguish 96 from 48** (plan 04-07, reported
  as a finding exactly as instructed, rather than adjusting the number). Measured: max
  `actionsSinceProgress` = 70 against `96 x liveSeats` = 288, a **4.1x margin**, worst case at 3 live
  seats. But a threshold halved to **48** per seat — the valve's own value — would still give ~2.05x
  and still pass the `margin >= 2` assertion.
  **So the case for 96 rests on `Types.VALVE_ARM_ACTIONS_PER_SEAT` (asserted in the spec), not on
  this control.** The 380-action healthy script is an approximation of measured pacing, not a
  measurement. **Phase 8 should tune this on the `stall_armed` / `stall_cleared` telemetry.** Do not
  treat the 4.1x margin as evidence that 96 is right; treat it as evidence that 96 is not obviously
  wrong.
  *Stuck-scenario control, for contrast:* 3000 actions with **zero** valve firings produced 8 cues,
  first at deci 864, repeats exactly 300 deci apart — so the detector does fire precisely where the
  valve is blind, which is the property D-20 exists for.

- **The arming boundary is exact:** `tick(449)` does not arm, `tick(450)` does, once the action
  condition is met. Both the action count AND wall time are required; removing either turns the gate
  red (4 failures and 1 failure respectively).

## Two reusable lessons from 04-08's rect arithmetic — read before writing any further rect gate

Plans 04-16, 04-17 and 04-19 all do geometry checks. Both of these are mutation-killing traps that
04-08 hit and fixed, not hypotheticals.

1. **A boundary mutation that lands EXACTLY on the boundary needs the check to treat *touching* as a
   violation.** The `LIFT = 20` mutation (checker FLAG F1, a live contradiction in the UI-SPEC) puts
   the lifted card's top at exactly the strip's bottom edge — **gap 0, not overlap**. A strict
   intersection test (`a.bottom > b.top`) would have left that mutation **green**. 04-08's lift check
   treats a zero gap as a violation, and the mutation is 8/8 red as a result. Any further
   "X must not cover Y" assertion in this phase must decide, explicitly, whether touching is a
   violation — and for every clearance in the UI-SPEC it is, because the spec states clearances as
   "4 px clear", not "not intersecting".

2. **One mutation does not necessarily reach the gate you think it does, if two constants encode the
   same intent.** `STEP = 44` alone did **not** trip the `below touch floor:` assertion, because the
   hit-strip width `HIT_W` is a **separate constant** — so shrinking the step left the floor check
   happily passing. 04-08 added a `hit overlap:` check, which is 8/8 red. **Before trusting a
   mutation, confirm which assertion it actually reaches**, and add the missing one when a second
   constant can independently satisfy the first.

Also recorded by 04-08, as honest narrowing rather than defects: `SCALE_MIN = 0.7` only trips the
step *relation* on the reference viewports (none is small enough to clamp to 0.7), so the physical
form was proved on a contrived 500x250 viewport; and `HIT_W = 48` is red only where scale < 1, which
is correct — at scale >= 1 a 48-wide strip really is >= 48 physical px.

**Measured geometry, for the renderer plans to build against:** tightest TableRegion fractions are
**59.08%** (phone notched) and **59.14%** (phone large) against the 58% threshold; the 0.85 floor
case (600x300) measures a **51 px** hit strip; the spec's worked examples reproduce (750x369 ->
scale 0.987, fraction 0.615; 1920x1080 -> scale 1.5, fraction 0.800).

**`verify.luau` caught a second type error `tests/run.luau` missed** — iterating a literal
`{ leftPile = ..., rightPile = ... }` types as `unknown` under the roblox-platform analyze. That is
now two independent confirmations; the rule stands for every remaining wave.

## Bookkeeping the orchestrator owns

**Do not run `requirements.mark-complete` from an executor.** Plans 04-01 and 04-02 each ran it
independently and each reverted it: it would have marked UX-01, UX-02, UX-03 and CARD-13/16/17
**complete** off plans that deliver only test fakes, guard fixtures and manual-check rows. That is
the exact false claim M-11..M-17 exist to prevent. `state.advance-plan` also errors on this
STATE.md's format, and the roadmap updater rewrites `stopped_at` to stale text. Two independent
refusals is a finding about the tooling, not a coincidence.

**Requirements stay unticked until the device matrix is signed.** Four of the five ROADMAP success
criteria for this phase are device-dependent and this container has no Studio and no phone.
