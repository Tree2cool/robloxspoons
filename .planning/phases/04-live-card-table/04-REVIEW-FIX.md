---
phase: 04-live-card-table
fixed_at: 2026-11-07T00:00:00Z
review_path: .planning/phases/04-live-card-table/04-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 4: Code Review Fix Report

**Fixed at:** 2026-11-07
**Source review:** `.planning/phases/04-live-card-table/04-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope (WR-01..WR-05): 5, fixed: 5, skipped: 0
- Optional Info findings taken (local and cheap): IN-01, IN-03, IN-05, IN-06, IN-07
- Deferred by instruction: IN-02, IN-04
- Suite: 858 -> **871 passed, 0 failed, 0 todo**. `verify.luau` 14/14. `check-guards: ok (146 files, 440 requires, 36 guarded roots)`.
- `src/server/engine/` and `Gateway.luau` have zero diff against the baseline.

Every gate below was watched go red against the real source (or the broken dependency) and restored. The verbatim red output is quoted.

## Fixed Issues

### WR-01: Draw-owed strike carried no fresh deadline

**Files modified:** `src/server/core/CardTable.luau`, `tests/card/cardtable.spec.luau`
**Commit:** 6a6b683
**Applied fix:** The `Strike` branch of `tick` now queues a `Sync` for the struck seat when no `AutoPass` already did (`autoSeat ~= seatId`) and the seat is still live. The Pass-owed path is unchanged (its AutoPass apply already produces one).
**Gate:** `WR-01: a Draw-owed strike carries the re-armed deadline to the struck seat`. Clean control: exactly one Draw-owed Strike notice reached the dealer (non-vacuity) and exactly one `Sync` with `idleDeadlineUnix == 1008`. Mutation is an injected broken dependency: a publisher that drops every `Sync`; the same helper must read 0 matches.
**Observed red** (fix line disabled in the real source):
```
FAIL tests/card/cardtable.spec.luau::WR-01: a Draw-owed strike carries the re-armed deadline to the struck seat
     the struck seat got no Sync carrying the re-armed deadline (expected 1, got 0)
```
Green: `cardtable WR-01: real struck/fresh-Sync 1/1 (2 calls), Sync-dropping mutant 1/0`.
**Note:** the client-side optional clamp in `refreshCountdown` was not applied; the server push alone removes the stale deadline.

### WR-02: StallDetector minimum-time gate dead before the first progress event

**Files modified:** `src/server/core/CardTable.luau`, `tests/card/cardtable.spec.luau`
**Commit:** eb25a1f
**Applied fix:** `CardTable.start` calls `deps.stall:noteProgress(ctx.now)` after `idle:sync`, anchoring the detector to the round's own clock. The fixture gained a `startNow` option so a spec can start from a realistic base.
**Gate:** `WR-02: the stall gate holds from a REALISTIC base clock, not only from deci 0`. Starts the round at deci 1,234,567, applies 300 accepted actions (past the 96 x 3 = 288 action threshold) within 10 deci, so ONLY the 45 s condition stands between the table and a cue. Control: no cue at +1 s, one cue at +45 s, 300 actions counted. Mutation: an anchor-ignoring detector (the pre-fix behaviour).
**Observed red** (anchor line deleted from the real source):
```
FAIL tests/card/cardtable.spec.luau::WR-02: the stall gate holds from a REALISTIC base clock, not only from deci 0
     a cue fired 1 s into the round on the action count alone (expected 0, got 1)
```
Green: `cardtable WR-02: base 1234567; real early/late cues 0/1, anchor-ignoring mutant 1/2, actions 300`.

### WR-03: startRound was not atomic

**Files modified:** `src/server/services/CardService.luau`, `tests/card/service_wiring.spec.luau` (new), `tests/card/round_end.spec.luau`
**Commit:** d60fe9f
**Applied fix:** All fallible work (cores, `CardTable.new`, the hold loop, `setPhase`, `start`, the sweep connect) runs under `pcall`. On failure `abortStart(announced)` stops the sweep, releases every hold, sends `RoundEnd` if the round had already been announced, clears the audience, nils `cardTable`, restores `Lobby`, and emits `start_round_failed`. `startRound` returns false and the service is retryable.
**Gate:** `service_wiring.spec` is a comment-stripped source scan, because `CardService` cannot load under Lune (it names `game:GetService`). Clean control with non-vacuity sizes, a no-defect twin, and 7 mutants that are the real source edited in memory (no pcall, failure branch never taken, rollback forgets table / holds / audience / phase, half-announced round ignored). **It is a scan, not a behavioural test.** That a failed start really leaves a retryable service live is M-17.
**Existing gates touched, and why this is not a weakening:**
- `round_end.spec` asserted `RoundEnd` appears exactly once in `CardService`. `abortStart` is a deliberate second publish site, so that probe is now per body: exactly one in `endRound`, exactly one in `abortStart`, exactly two in the file.
- Two `round_end` mutants keyed on the first `seatHold:releaseAll()`, which now sits in `abortStart`. They were silently landing in the wrong function. They are re-keyed to `endRound`'s own call (`"\n\t\tseatHold:releaseAll()"`, two tabs). This was caught because the gate went red (`service: seated cleared before the send must turn the gate red`), then fixed so it can fail again.
**Observed red** (pre-fix `CardService.luau` restored):
```
FAIL tests/card/service_wiring.spec.luau::WR-03: startRound is atomic, and abortStart restores every piece of state
     clean path (expected {  }, got { [1] = "startRound or abortStart body not found" })
```
Green: `service_wiring WR-03: startRound 2100 chars, abortStart 353 chars, 0 problems` and `7/7 mutants seen, twin green`.
**Status:** fixed: requires human verification (behaviour, M-17).

### WR-04: gateway-reject Sync neither reconciled nor was throttled

**Files modified:** `src/server/core/CardTable.luau`, `src/server/services/CardService.luau`, `src/server/services/NetServer.luau`, `src/server/Main.server.luau`, `src/server/core/RejectThrottle.luau` (comment), `src/shared/Card/Prediction.luau` (comment), `tests/card/cardtable.spec.luau`, `tests/card/netguard.spec.luau`
**Commit:** 8b6aa3f
**Applied fix (both defects, push made to work rather than the record corrected):**
1. *Reconcile.* The reject sink received no payload and `Gateway.luau` is frozen, so the rejected `seq` was unknowable. `NetServer` now carries the in-flight raw payload (set and cleared around the one synchronous `gateway:handle`) and passes it as a fourth argument to `onReject`. `CardTable.onGatewayReject` reads **only** `seq` from that unvalidated payload, accepts it only as a finite non-negative integer <= 2^31 (the manifest's bound), and **raises** `lastAck` (never lowers it, because the client ignores a Sync whose ack is below what it holds). The `Sync` is then at or above the rejected seq, so `fold` drops the pending entry and the card returns immediately.
2. *Throttle.* `Main.server` passes `decision.log` (the existing per-user `RejectThrottle` verdict) as `push`. A throttled-off reject still records the ack, so the next `Sync` of any kind carries it, but sends nothing. The 1.0 s watchdog remains the backstop for a suppressed push. Open Question 5's "push primary, watchdog backstop" is now true as shipped; the `Prediction` and `RejectThrottle` headers were corrected to say so (the old text described a push at the *old* ack, which resolved nothing).
**Gates:**
- `cardtable.spec` `WR-04`: drives the REAL `CardTable` and the REAL `Prediction` reducer (predicted Draw -> gateway reject -> push -> `onSync`). Control: hand 5 -> 4, pending 0. Mutation is a broken dependency: the pre-fix call with no payload. Also asserts 7 invalid hints (`NaN`, -1, 1.5, 2^31+2, `"7"`, `{}`, `inf`) never move the ack, a throttled-off reject sends 0 calls, the throttled ack is not lost and a lower hint does not lower it (observed through the WR-01 strike Sync), and a seatless user gets the seat-0 shape.
- `netguard.spec` `WR-04`: source scan that `NetServer` hands `inFlightPayload` to the sink and `Main` passes the payload and `decision.log`. Two in-memory mutants (payload dropped, unthrottled `true`) are seen. `NetServer`/`Main` cannot load under Lune, so these are scans.
**Observed red** (three separate edits to the real `CardTable.luau`):
```
hint ack disabled:      the rejected Draw's placeholder was not removed by the push (expected 4, got 5)
push gate removed:      a throttled-off reject still sent something (expected 0, got 1)
raise-only removed:     the throttled ack was lost, or a lower hint lowered it (expected 7, got 3)
```
Green: `cardtable WR-04: real hand 5->4 pending 0; payload-dropping mutant 5->5 pending 1` and `7 invalid hints rejected, throttled-off push sent 0 calls, ack kept at 7`.
**Status:** fixed: requires human verification (a live reject round trip is a Studio observation; the in-flight-payload carrier assumes `gateway:handle` does not yield on the card path, which it does not today).

### WR-05: removed seats never received RoundEnd, Depths or later Table batches

**Files modified:** `src/server/services/CardService.luau`, `tests/card/service_wiring.spec.luau`
**Commit:** afa9b24
**Applied fix:** `onSeatRemoved` no longer calls `unseat`; it only releases the avatar. `seated` (the audience of every public kind) is now "dealt into this round" and keeps a finisher, benched or disconnected seat until `endRound` clears it. Only `removePlayer` (a real leaver) unseats. This is the reviewer's second option but it solves the audience rather than only `RoundEnd`: the client is built to keep its place after its hand is gone (D-30 "self callout survives the hand's destruction", `onTable` uses `place` after local completion), so the server unseating contradicted the client design. No privacy change: `Table`, `Depths` and `Stall` are public kinds and a removed seat's client learns nothing it was not already shown. `endRound`'s release loop now also covers finishers, which is idempotent.
**D-31 note:** this reads D-31 ("the table is told who went") as covering every seat dealt in, finisher or not. If the owner meant the callout only for seats still in the card phase, that is a decision to record; the code is a one-line change to revert.
**Gate:** `service_wiring.spec` `WR-05`: `onSeatRemoved` and `onCompleted` bodies must not call `unseat(`, `onSeatRemoved` must still release the avatar, `removePlayer` must still drop a leaver. Twin plus 4 in-memory mutants. Scan, not behaviour.
**Observed red** (`unseat(playerId)` reintroduced into the real source):
```
FAIL tests/card/service_wiring.spec.luau::WR-05: a removed seat stays in the audience, a leaver does not
     clean path (expected {  }, got { [1] = "onSeatRemoved unseats: a removed seat would miss RoundEnd, Depths and later Table", [2] = "onCompleted unseats: a finisher would miss RoundEnd, Depths and later Table" })
```
Green: `service_wiring WR-05: onSeatRemoved 92 chars, removePlayer 215 chars, 0 problems`, `4/4 mutants seen, twin green`.
**Status:** fixed: requires human verification (client-visible behaviour, M-17).

## Optional Info findings taken

| ID | Commit | Change | Gate and observed red |
|----|--------|--------|-----------------------|
| IN-07 | 6aeb170 | `Layout.solve` clamps `handTop` to >= 0 | `layout.spec`: six degenerate solves (400x100, 640x120, 844x140 with insets, hands 4/5) have no negative region and `problems` still flags `height below guarantee`; checker proven by a hand-built negative region. Red: `a negative region at 400x100 hand 4 (expected {  }, got { [1] = "tableRegion 400x-22.39999999999999" })` |
| IN-03 | cfe8992 | sweep accumulator `math.min(accumulator - interval, interval)` | `service_wiring` scan. Red: `clean path (expected {  }, got { [1] = "the sweep accumulator is not clamped to one interval after subtracting" })` |
| IN-05 | f027d61 | the flourish `Scheduler.nowDeci` returns 0 (the type requires the member, no driver code reads it, and `flourish.spec` builds a `Scheduler` with it, so dropping it would ripple); unused `Round` require removed | `renderer_discipline` scan for `time()` / `os.clock` / `tick()`. Red: `CardFlourish reads a clock (expected 0, got 1)` |
| IN-06 | bedec15 | `newRotatePrompt` captures `pg.ScreenOrientation` and `destroy` restores it | `renderer_discipline` scan. Red: `clean path (expected {  }, got { [1] = "destroy does not restore the captured orientation" })` |
| IN-01 | 1e7977b | each `buildUi` piece registers a cleanup the moment it exists; the failure path unwinds newest first, then destroys the hud | `renderer_discipline` scan, 3 mutants. Red: `clean path (expected {  }, got { [1] = "piles is built but not registered for cleanup after it exists" })` |

IN-01, IN-03, IN-05 and IN-06 are scans of source that cannot load under Lune; none proves the runtime behaviour.

## Deferred Issues

### IN-02: capped-sound `task.delay` can cut a later play short
**File:** `src/client/ui/CardAudio.luau:62-70`
**Reason:** deferred by instruction. The fix needs a behaviour judgement (per-sound token versus restarting the cap window), not a mechanical edit. Cosmetic and silent until asset ids exist (M-16).

### IN-04: callout overlay loses relayout once the hand's HUD is destroyed
**File:** `src/client/ui/CardClient.luau:310-314`, `src/client/ui/CardHud.luau:240-247`
**Reason:** deferred by instruction. Giving `newOverlay` its own `ViewportSize` connection adds a new client-side listener and a lifetime decision, not a mechanical fix.

## Defects that turned out narrower than reported

None were non-defects. Two qualifications to the review text:
- **WR-05** is described as dormant because `roundStarted` never resets. It is live today for every finisher, as the task brief says: a completion is unseated immediately.
- **WR-04**'s "make the push work" was only possible by passing the raw payload to the sink, because the rejected `seq` is otherwise unknowable and `Gateway.luau` is frozen. That is the one place a client-supplied value is read before validation; it is bounded to a single integer key that can only raise that user's own ack.

## Mutation-gate maintenance found along the way

- Two `round_end` mutants were silently relocated by an unrelated edit (above). A first-occurrence `replaceOnce` keyed on a string that later appears earlier in the file will do this again; key mutants on a context-unique needle.
- `tests/card/layout.spec.luau` needed `Layout.Rect`, not a bare `Rect`: the suite ran green and `verify.luau`'s standard-platform typecheck rejected it (eighth confirmation this phase).

---

_Fixed: 2026-11-07_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
