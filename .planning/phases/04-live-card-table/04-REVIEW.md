---
phase: 04-live-card-table
reviewed: 2026-11-07T00:00:00Z
depth: standard
files_reviewed: 35
files_reviewed_list:
  - src/server/core/CardTable.luau
  - src/server/core/CardRouting.luau
  - src/server/core/IdleClock.luau
  - src/server/core/StallDetector.luau
  - src/server/core/CardTiming.luau
  - src/server/core/RejectThrottle.luau
  - src/server/core/CardSeatHold.luau
  - src/server/services/CardService.luau
  - src/server/services/NetServer.luau
  - src/shared/Card/Faces.luau
  - src/shared/Card/Layout.luau
  - src/shared/Card/Prediction.luau
  - src/shared/Card/Flourish.luau
  - src/shared/Card/Hints.luau
  - src/shared/Card/Controls.luau
  - src/client/ui/CardTheme.luau
  - src/client/ui/CardHud.luau
  - src/client/ui/CardStrip.luau
  - src/client/ui/CardFace.luau
  - src/client/ui/CardHand.luau
  - src/client/ui/CardPiles.luau
  - src/client/ui/CardControls.luau
  - src/client/ui/CardInput.luau
  - src/client/ui/CardClient.luau
  - src/client/ui/CardSeatsView.luau
  - src/client/ui/CardCallout.luau
  - src/client/ui/CardFlourish.luau
  - src/client/ui/CardAudio.luau
  - src/client/net/ClientNet.luau
  - src/shared/Net/Manifest.luau
  - src/shared/Config/Card.luau
  - src/shared/Config/RateLimits.luau
  - src/server/Main.server.luau
  - src/client/Main.client.luau
  - scripts/ci/zones.luau
findings:
  critical: 0
  warning: 5
  info: 7
  total: 12
status: issues_found
---

# Phase 4: Code Review Report

**Reviewed:** 2026-11-07
**Depth:** standard
**Files Reviewed:** 35
**Status:** issues_found

## Summary

No Critical findings. The eight Non-Negotiable Rules held under review:

- **Rule 3 / CARD-13 (privacy):** Every `toPlayer` is `Sync` or `Notice`. `toSeated` and `toAll` pass through `assertPublic`. The `Depths` payload is built from `#seat.inbox` counts only. The public `Table` events carry card ids but no ranks. Ranks appear only on `Completed.faces`, which is the retired set. Card ids are shuffled deck positions (`Pool.luau` header), so an id does not reveal its rank. `NetServer`'s three closures are mapped correctly.
- **Rule 7:** `ClientNet.send` only ever receives `Draw{seq}` or `Pass{seq, cardId}`. The server derives the seat from `rosterSeat[userId]`. `Manifest` uses `exactKeys`, and `cardId` max 64 is above the largest possible id of 49.
- **Rule 2:** `src/server/engine/` has zero diff against `ae376d6`.
- **Rule 6:** `CardTable.tick` drains, applies and bookkeeps every command before it publishes. Each command is wrapped in `xpcall`.
- **Rule 8:** Removal goes through the single `Remove` path. No card is destroyed.
- **RoundEnd ordering:** `CardService.endRound` publishes `RoundEnd` before `table.clear(seated)`. The client's `endRoundView` calls `teardown()`, then `controls:restore()`, then `destroyPlace()`. That restores controls.

The five warnings are real defects in code paths no executed test reaches: the service layer, the client countdown, and the stall detector's anchoring. None is a rule violation.

Clean by group:
- Shared pure zone `Faces`, `Hints`, `Controls`, `Prediction` and `Flourish` (including `cancelAll` and teardown): no defects found beyond IN-07.
- `RejectThrottle`, `CardTiming` and `CardSeatHold`: no defects found.
- `CardSeatHold` is idempotent. `forget` followed by `release` is a safe no-op.

## Warnings

### WR-01: After a Draw-owed strike, the client countdown reads 0 for the whole next window and hides the strike message

**File:** `src/server/core/CardTable.luau:535-543` (cause), `src/client/ui/CardClient.luau:342-360,700-711` (effect)

**Issue:** `IdleClock.tick` resets `entry.deadlineDeci = nowDeci + window` on a strike. For a seat that owes a Draw (hand 4, inbox >= 1) there is no `AutoPass`, so `CardTable.tick`'s `Strike` branch only queues a `Notice`. No `apply` runs and the signature is unchanged, so no `Sync` carries the new `idleDeadlineUnix`.

The client keeps the expired deadline in `reducer:idleDeadlineUnix()`:

1. `refreshCountdown` computes `secondsLeft` as negative and calls `setCountdown(owes, 0)` every frame.
2. `CardStrip.render` returns `countdownText or messageText or hintText`, so the countdown outranks the message.
3. `onNotice` sets the strike message after `refresh`, so "Strike 1 of 3" is never visible.
4. The player sees "0" for a full window, with no restarted timer, until the next `Sync`.

The Pass-owed path is unaffected, because its `AutoPass` apply produces a fresh `Sync`.

**Fix:** In the `Strike` branch, push a fresh `Sync` to the struck seat. This is the same shape as every other `Sync`, so D-12 is unaffected.
```lua
elseif kind == "Strike" then
    local playerId = st.seats[seatId].playerId
    queueNotice(ctx, playerId, notice)
    if autoSeat ~= seatId then -- an AutoPass already queued a Sync
        queueSync(ctx, playerId, syncFor(seatId, lastAck[playerId] or 0, ctx.now))
    end
```
Optionally, have `refreshCountdown` clamp a deadline already in the past to "no countdown".

### WR-02: `StallDetector`'s minimum-time gate is dead until the first progress event of each round

**File:** `src/server/core/StallDetector.luau:30-32,70-74`, `src/server/core/CardTable.luau:385-427`

**Issue:** `lastProgressDeci` starts at 0. `nowDeci` in production is `floor(os.clock() * 10)`, which is server uptime. `CardTable.start` never anchors the detector, since it only calls `idle:sync`.

So `nowDeci - lastProgressDeci` is already enormous on the first tick of a round. D-20's second required condition (>= 45 s with no progress) is therefore not enforced before the first `Completed` or `SeatRemoved`. Only the action count (96 x liveSeats) gates arming in that window.

The specs pass because they drive the detector from deci 0. The `tick(449)` and `tick(450)` boundary test proves the gate only when the clock starts at 0. Production never starts at 0.

**Fix:** In `shell.start`, anchor the detector with the round's own clock after `idle:sync`:
```lua
deps.idle:sync(viewOf(st), ctx.now, nil)
deps.stall:noteProgress(ctx.now) -- anchor lastProgressDeci to the round start
```
`noteProgress` is a no-op beyond zeroing the counter and setting the anchor while inactive. Add a spec that starts the detector at a large `nowDeci`.

### WR-03: `startRound` is not atomic. A throw after `cardTable` is assigned wedges the service with avatars held

**File:** `src/server/services/CardService.luau:286-336`

**Issue:** `cardTable = table_` is assigned before `table_:start(specs)`, and before the hold loop and the sweep connect. Three things can throw in between:

- `Engine.newRound`
- `seatHold:hold`, which calls `checkId`, or an effect that sets `Dev*MovementMode`
- `deps.seatPoses()` returning a pose with a nil field

After a throw:
- `cardTable ~= nil`, so every later `startRound` returns false.
- `seated` is populated and some avatars are held in `Scriptable` mode.
- There is no sweep, so no AFK clock and no recovery.
- `Main.server`'s `roundStarted` stays false, so it retries into the dead guard on every `PlayerAdded`.
- Only `endRound` or `destroy` recovers it, and nothing calls them.

**Fix:** Do the fallible work first, then commit. Or wrap the body:
```lua
local ok, err = pcall(function() --[[ hold loop, setPhase, start, connect ]] end)
if not ok then
    stopSweep()
    seatHold:releaseAll()
    table.clear(seated)
    cardTable = nil
    deps.setPhase("Lobby")
    deps.onTelemetry("start_round_failed", {})
    return false
end
```

### WR-04: The gateway-reject `Sync` push neither reconciles the display nor is it throttled

**File:** `src/server/core/CardTable.luau:466-476`, `src/server/Main.server.luau:103-109`, `src/shared/Card/Prediction.luau:266-275`

**Issue:** `Main.server` calls this push "the PRIMARY resync mechanism". It sends a `Sync` at `lastAck`, which is older than the rejected intent's `seq`. `Prediction.onSync` keeps pending entries with `p.seq > ackSeq`, and `fold` re-applies them, so the card stays visibly gone.

Only the 1.0 s watchdog (`PENDING_TIMEOUT_SECONDS`) brings it back. That is still D-11/D-12-compliant, but the push does no work and the comment is misleading.

The push also runs on every gateway rejection, including `RateLimited`. Each rejected message therefore costs a `syncFor` plus a `FireClient` carrying the hand, outside the limiter that rejected it. That amplifies a flood 1:1 on the outbound side. Neither `RejectThrottle` nor the bucket covers it.

**Fix:** Either remove the push, or make it work and throttle it:
- Ack nothing, but have the client treat any `Sync` as "re-derive". For example, drop pending entries older than the `Sync`'s arrival minus the round trip.
- Throttle `onGatewayReject` per user, for example with a second `RejectThrottle` using `decision.log` as the gate.
- Correct the comment to say the watchdog is the real mechanism.

### WR-05: Removed seats never receive `RoundEnd` or later public messages, so their table place leaks until the next `RoundStart`

**File:** `src/server/services/CardService.luau:300-303`, `src/server/services/CardService.luau:339-359`, `src/client/ui/CardClient.luau:638-650,687-698`

**Issue:** `onSeatRemoved` calls `unseat` for every cause, including `Completed`. `RoundEnd`, `Depths` and later `Table` batches use `toSeated`, so a finished, benched or disconnected seat gets none of them.

A finished player still holds a client-side `place`:
- the `SpoonsCardTable` folder of seat stacks in Workspace
- the `SpoonsFlourish` container
- the `CardCallouts` ScreenGui

These are never torn down by `RoundEnd`. Their stacks freeze on their last depths. They also get no later "X is out" callout or sting, so D-31's "the table is told who went" holds only for players still in the card phase.

Cleanup happens only in the next `RoundStart`'s `endRoundView`. A player who is not seated in that next round, such as the next hider, never receives `RoundStart` either. Their stale place persists indefinitely.

Today `Main.server`'s `roundStarted` never resets, so this is dormant. It becomes live when Phase 6 replaces the stub.

**Fix:** Send `RoundEnd` to every connected player, not just the seated:
```lua
deps.publisher.toAll("RoundEnd", {}) -- RoundEnd is already public ("seated" -> widen to "all")
```
Alternatively, keep a separate `participants` list that `endRound` uses for `RoundEnd` only. If removed seats are meant to miss later callouts, record that as a decision.

## Info

### IN-01: A partial `buildUi` failure leaks input bindings and a `RenderStepped` connection

**File:** `src/client/ui/CardClient.luau:515-558`

**Issue:** The failure handler destroys only `hud`. `CardPiles.new` has already connected `RenderStepped`. `CardInput.new` has already bound three `ContextActionService` actions at priority High+1, which is above the movement sink. If anything after them throws, none of these is released. The failure window is small, since only `input:kind`, `setInputKind`, `onKindChanged` and `onViewportChanged` follow `CardInput.new`, but the leak is permanent.

**Fix:** Track each constructed piece in a local list inside the pcall. On failure, destroy them in reverse order, then `hud`.

### IN-02: `CardAudio`'s capped-sound `task.delay` can cut a later play short

**File:** `src/client/ui/CardAudio.luau:62-70`

**Issue:** Each capped play schedules an unconditional `sound:Stop()`. Two own-draws within `OWN_CAP_SECONDS` leave the first delay stopping the second play early. It is silent and cosmetic until asset ids are set (M-16).

**Fix:** Keep a per-sound token and stop only if it still matches the token for that play.

### IN-03: The Heartbeat accumulator can build an unbounded backlog after a hitch

**File:** `src/server/services/CardService.luau:326-335`

**Issue:** It subtracts correctly, so it does not drift and cannot double-fire. It fires at most once per frame, though. After a long stall the accumulator holds many intervals, and `tick` then runs every frame until drained. `tick` reads `os.clock`, so each catch-up call is idempotent and harmless. The backlog is still unbounded.

**Fix:** After subtracting, clamp: `accumulator = math.min(accumulator, interval)`.

### IN-04: The callout overlay stops relaying out once the hand's HUD is destroyed

**File:** `src/client/ui/CardClient.luau:310-314`, `src/client/ui/CardHud.luau:240-247`

**Issue:** `buildPlace` registers the callout relayout through `hud:onViewportChanged`. `Hud.destroy` clears `subscribers` and disconnects the camera signal, and it runs at local completion (D-30). The `CardCallouts` overlay and its "You're out" banner outlive the hand but lose their relayout. A rotation or resize after finishing leaves the banner mispositioned. `CardHud.newOverlay` has no viewport listener of its own.

**Fix:** Give `newOverlay` its own `ViewportSize` connection, disconnected in `Overlay.destroy`.

### IN-05: The flourish scheduler's `nowDeci` is dead code and reads a clock

**File:** `src/client/ui/CardFlourish.luau:221-225`

**Issue:** It reads `time()`. The comment itself says the driver never calls it. It is an unused clock expression in a codebase with a "one clock" rule.

**Fix:** Drop the member if the `Flourish.Scheduler` type allows it. Otherwise return a constant, or accumulate frame time.

### IN-06: Boot-time side effects that are never reverted

**File:** `src/client/ui/CardHud.luau:~293`, `src/server/Main.server.luau:65,129-133`

**Issue:**
- `newRotatePrompt` sets `PlayerGui.ScreenOrientation = LandscapeSensor` and never restores it. Its `destroy` removes only the gui.
- `roundStarted` is set true on the first start and never reset, so there is exactly one round per server lifetime. This is acknowledged as the RoundStub and is Phase 6's to replace. Noting it so the single-round limit is not mistaken for a bug in Phase 4's own scope.

**Fix:** Capture and restore the orientation value in `RotatePrompt.destroy`. Phase 6 owns the `roundStarted` reset.

### IN-07: `Layout.solve` produces a negative table region on very short viewports

**File:** `src/shared/Card/Layout.luau:~155-160`

**Issue:** `handTop = designH - HANDZONE_H` goes negative when `designH < 144`. `Layout.problems` flags `height below guarantee`, but `solve` still returns negative `tableRegion` and `handZone` sizes, which then reach `UDim2.fromOffset`. This is unlikely on the supported device matrix, since the 0.85 scale floor puts the minimum viewport near 300 px. A degenerate embedded window or a bad inset read would produce visible garbage rather than an error.

**Fix:** Clamp the region heights to >= 0 in `solve`, or error as `safeRect` does.

---

_Reviewed: 2026-11-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
