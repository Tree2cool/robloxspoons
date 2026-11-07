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

## 04-09 found a real forced-pass / prediction interaction the plan did not anticipate

This is the valve showing up where nobody looked for it. `ValveForcedPass` fires in roughly **1 round
in 12** at a full roster, so this is an ordinary race, not a corner case.

**The race:** a forced pass lands while the player's own `Pass` is still in flight. Naively folding
both would put the display at **3 cards**, breaking the plan's own "hand is 4 or 5" invariant.

**What 04-09 did:** the fold now **skips a predicted action the server is certain to reject** — a
`Pass` unless the display hand is 5, a `Draw` unless it is 4 with a non-empty inbox. In that race the
forced card is reported `Removed` and the pending entry is left untouched until its ack.

**The consequence the plan did not foresee, now asserted in case 11:** the player's own doomed `Pass`
**also returns as `Returned`** when the forced-pass `Sync` lands. So a single forced pass can produce
*two* visible changes — a card leaving that the player did not choose, and their own in-flight card
coming back. **Plans 04-16/17/18 must render that pair coherently**, or it will read as the UI
glitching precisely in the ~8% of rounds the valve touches.

## Three concrete notes for the client waves (04-16, 04-17, 04-18)

1. **`Change.Removed.cardId` is `number?`.** A rolled-back `Draw` placeholder has no id, because the
   client never learned it (draw intents carry no card — rule 7). **Treat a `Removed` with no id as
   "a face-down placeholder leaves".** Do not assume an id is present.
2. **Build a fresh reducer per round (04-18).** `ackSeq` is not reset within a round, so reusing a
   reducer across rounds would carry a stale high-water mark.
3. **What case 8 actually proves.** The "correction" is a hand-crafted `onSync`, because the stub
   server has no correcting path of its own. What it establishes is that the reducer's change list
   for a **correction** is byte-identical to a **rejection's** and to a **lost message's** — which is
   exactly D-11/D-12's requirement that all three look the same to the player. It does not prove a
   real server correction, which is M-13.

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

## 04-12 disproved one of its own plan's claims — and the plan-checker's flag 4 is what saved the gate

**The plan asserted that an interleaved pass into the seat being benched "does not commute".** 04-12
measured it: **it DOES commute.** Hash, deadlines, strikes and action counts are all identical to the
serial run. It also tried the benched seat's own `Draw` as the interleave, same result.

**So the per-command `tick` mutant is caught ONLY by the structural assertion** — "at the first
publish of a sweep, all commands have already been applied" (`first publish with 1 of 2 applies
done`). That assertion exists **because the plan-checker added it as flag 4** in the final revision,
specifically so the mutant would not depend on a scenario happening not to commute. Without it this
gate would have been dead, and the composite-snapshot comparison would have reported no difference.
04-12 prints the limit rather than asserting the plan's false claim.

**The intent-level mutant (publishing between `apply` and `idle:sync`) is caught both ways** —
structurally and by the snapshot (real deadlines 585,585 vs mutant 585,580).

## Environment gotcha: Lune runs the main script inside a coroutine

`coroutine.isyieldable()` is **true on Lune's main thread**, because the main script itself runs in a
coroutine. 04-12's first yielding publisher therefore **killed the process silently mid-suite** — no
error, just a truncated run. Its fix: yield only on the one thread the test rig names explicitly.
Any later plan using a yielding fake must do the same.

## Contract facts for plans 04-13 and 04-14, measured by 04-12

- **The authoritative `Deps` and `CardTable` type text is in `src/server/core/CardTable.luau`.** Quote
  it; do not re-derive it. The `Sync` / `RoundStart` / `Notice` / `Stall` key sets and the telemetry
  names are listed in `04-12-SUMMARY.md`.
- **Publish order is actor `Sync`, `Table`, `Notice`, then other `Sync`s** — `CardRouting.publish`
  sends the Table batch **before** ForcedPass notices. The plan listed Notice before Table; 04-12
  kept `publish` as the wave-2 handoff required rather than reordering it.
- **The `Stall` payload is `{ active }` only.** `Deps` carries no cue seconds and `StallDetector`
  keeps `cueDeci` private, so **the client (04-18) reads `STALL_CUE_SECONDS` itself.**
- **The sweep scenario needs `maxStrikes = 1`**: with the shipped 3, an `AutoPass` and a `Bench` for
  the same seat can never share a sweep. Injecting `IdleClock` makes that a one-line substitution —
  another payoff of taking the cores as objects through `Deps`.

## Weak gate recorded, not closed (cheap follow-up for the code review)

**Sinks-after-publish ordering is not directly asserted** in 04-12. The crude "sinks fire first" edit
also made them fire twice, so its failures are weak evidence rather than a clean signal. A dedicated
assertion is a cheap addition.

## Checker flag W6 was load-bearing, and the proof is a privacy bug

04-13 built the **swap mutant**: `fireToPlayer` broadcasts, `fireToAll` targets a single player.
**The whole-file greps stayed GREEN** — `FireClient` 2, `FireAllClients` 1, exactly the expected
totals. Only the **per-closure-body** assertion caught it: `fireToPlayer FireClient (expected 1,
got 0)`.

Why this matters beyond the gate: that swap routes the **private per-player `Sync`** — a seat's own
hand — through a broadcast. It is a **CARD-13 / rule 3 violation**, the exact leak this phase's
privacy work exists to prevent, and occurrence-counting across the file would have passed it.
The plan-checker raised this as flag W6 ("asserting `FireAllClients` exactly once does not bind
which closure it sits in"); it is now demonstrated rather than argued.

Body slicing by consecutive effect markers was **not** formatting-brittle in practice (bodies
measured 185 / 211 / 89 / 38 characters), so the stated fallback was unnecessary.

Deleting `assertPublic` from `makePublisher` turns **three** tests red across two plans — netguard
cases 1 and 2, and routing.spec's "makePublisher is the shipped assembly". Deleting it from `toAll`
alone, or from both methods, gives the same three. The shipped-assembly approach means there is no
longer a copy that can silently drift from production.

## HANDOFF: plan 04-14 must replace `Main.server.luau`'s placeholder `seatedUserIds`

04-13 added `seatedUserIds: () -> { number }` to `NetServer.Deps`, which broke the roblox-platform
typecheck of the **existing** `NetServer.start` call in `Main.server.luau` — a file not in 04-13's
plan. It added a **placeholder returning `{}`** with a comment saying CardService replaces it.

**A placeholder returning an empty roster means `toSeated` reaches nobody.** If 04-14 does not
replace it, the public `Table` batch silently goes to zero clients and every seat sees only its own
`Sync`. **04-14 must replace it with the real roster.**

## Shipped transport contracts for 04-14 and 04-18

- `NetServer.start` returns `{ gateway, remote, cardRemote, publisher, destroy }`.
- **Both remotes are parented AFTER every `Connect`** — deliberately, to avoid a dropped-message
  window. (That this actually avoids it needs a Studio observation; it is not proven here.)
- `PlayerRemoving` clears `roster[player.UserId]` beside `gateway:forget`; `PlayerAdded` and an
  initial seed from `Players:GetPlayers()` keep it current.
- `ClientNet.resolve(): ()` is **idempotent** and resolves both the Intent and Card remotes.
- `ClientNet.onCard(handler) -> RBXScriptConnection` **errors** with "ClientNet.onCard called before
  ClientNet.resolve" if `resolve` has not run. Its connected closure only calls the handler.
- `OnClientEvent` appears in exactly **1** file under `src/`; `FireClient`/`FireAllClients` only in
  `NetServer.luau`.

## A fifth confirmation on `verify.luau`

04-13's roster typed as `{ [number]: Player? }`: `verify.luau` rejected the nil comparisons against a
plain `Player`, while `tests/run.luau`, selene **and** stylua all passed. Five independent
confirmations now (04-06, 04-08, 04-10, 04-12, 04-13).

## A typecheck trap for the renderer waves, found by 04-11

**The standard-platform solver widens string-literal-union tables to `string` when they pass through
`table.freeze({...})`.** So a frozen table of literal-union keys loses its narrowing and the
typecheck fails. 04-11's fix: **build the typed local first, freeze it afterwards.** Any later plan
freezing a literal-keyed table will hit this.

(This is the **fifth** independent confirmation of the `verify.luau` gap — the suite ran green before
`verify.luau` did, again.)

## 04-11's shipped copy facts the renderers need

- **Hint table: 20 cells** (state x input). 41 strings audited in total — 20 cells, 17 messages
  including 2 joker explainers and the rotate prompt, and 2 callouts.
- **Longest strip string is exactly 34 characters** — "Auto-passed a card. Strike 1 of 3." — i.e. hard
  against the cap. Longest callout is 40, with the display name truncated to 18. Worst-case strip
  headroom measured **1.806** against a `>= 1.5` assertion, over 4 viewports and 156 measurements.
- **The forced-pass copy names no card on purpose:** "Table stuck. We passed for you." That is what
  makes it read correctly in 04-09's race (a forced pass landing while the player's own `Pass` is in
  flight produces two changes at once) **and** after a `Draw` placeholder rollback, where there is no
  `cardId` to name at all.
- **Exclamation marks appear only in the starting-gun callouts.** A stray one in an AFK line turns
  the gate red (`stray exclamation: message waiting`), as does any error copy
  (`forbidden error copy: ... contains "rejected"`) — D-12's silent-rejection rule, enforced.
- **The "four F4 rewrites" are four UI-SPEC rows but five literals**, because the RightPileSink Touch
  and Mouse strings share one row.
- **D-30 order is asserted, not assumed:** a never-restoring mutant and a flourish-first mutant both
  fail with explicit order traces (`D-30: flourish at 4 not after controls restored at -1`).

**Self-consistency catch worth copying:** the `Controls` header says "legacy controls getter" rather
than spelling `GetControls` / `PlayerModule`, because the `src/`-wide forbidden-identifier scan
**reads comments too**. A header that named the identifiers would have failed the very scan it
documents. 50 files walked, 0 hits, negative control fires exactly once.

## Bookkeeping the orchestrator owns

**Do not run `requirements.mark-complete` from an executor.** Plans 04-01 and 04-02 each ran it
independently and each reverted it: it would have marked UX-01, UX-02, UX-03 and CARD-13/16/17
**complete** off plans that deliver only test fakes, guard fixtures and manual-check rows. That is
the exact false claim M-11..M-17 exist to prevent. `state.advance-plan` also errors on this
STATE.md's format, and the roadmap updater rewrites `stopped_at` to stale text. Two independent
refusals is a finding about the tooling, not a coincidence.

**Requirements stay unticked until the device matrix is signed.** Four of the five ROADMAP success
criteria for this phase are device-dependent and this container has no Studio and no phone.
