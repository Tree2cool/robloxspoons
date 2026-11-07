---
phase: 04-live-card-table
plan: 14
subsystem: server-adapter
tags: [card, adapter, wiring, deci-lock]
requires: [04-01, 04-03, 04-06, 04-07, 04-12, 04-13]
provides: [CardService, wired Main.server, deci_lock gate]
key-files:
  created: [src/server/services/CardService.luau, tests/card/deci_lock.spec.luau]
  modified: [src/server/Main.server.luau]
metrics:
  suite: "816 passed, 0 failed, 0 todo (25.43 s)"
  verify: "all 14 automated steps passed (28.3 s)"
---

# Phase 4 Plan 14: CardService and boot wiring Summary

Thin Roblox adapter that builds IdleClock/StallDetector objects from the single `AUTO_PASS_DECI` call, runs one 10 Hz Heartbeat sweep, and wires Main so Draw/Pass, the throttled reject sink, the real seated roster and a RoundStub run the card table with Phases 5/6 absent.

Commits: eb03881 (CardService), 92f09d4 (Main), plus the spec commit.

## Both handoffs
1. `seatedUserIds` placeholder `{}` is replaced: `NetServer.start` gets a closure over the forward-declared `cardService` upvalue returning `cardService:seatedUserIds()`; CardService keeps its own seated list (set at start, cleared by `onSeatRemoved` / `removePlayer`).
2. `IdleClock.new({autoPassDeci = AUTO_PASS_DECI, ...})` and `StallDetector.new(...)` are built in `buildCores` and injected as `idle = idle, stall = stall`. No numeric literal anywhere.

## deci_lock results (comment-stripped, with negative controls)
- Scanned 51 files; CardService stripped length 6960.
- Call `CardTiming.autoPassDeci(` is in exactly `src/server/services/CardService.luau`; whole statement pinned including both arguments; `autoPassDeci = AUTO_PASS_DECI` appears once, inside `IdleClock.new(`; no `autoPassDeci = <digit>` in `src/`.
- Realised window printed: `(7.9, 8.1]`.
- os.clock files: CardService, NetServer, RoundDriver. GetServerTimeNow files: CardService, RoundDriver.

## Mutations (each watched go red, then restored)
- M1 `autoPassDeci` +1: red in `cardtable` ("shipped number expected 80, got 81"), `config_lock` x2, `deci_lock` x2 (80 and window `(8, 8.2]`, "worst-case window 8.2 <= 8.1"). Five reds across three plans.
- M2 `autoPassDeci(7.5, 10)`: `whole statement pinned (both arguments) (expected a truthy value, got false)`.
- M3 `autoPassDeci = 80,` into IdleClock (constant computed but unconnected): `AUTO_PASS_DECI is read exactly once (expected 1, got 0)`.
- M4 call left in a comment, code uses literal 80: `exactly one file calls CardTiming.autoPassDeci ... (expected {CardService}, got {})` -- the comment does not satisfy the gate.
- M5 `os.clock()` added to Main: `os.clock files (expected {CardService, NetServer, RoundDriver}, got {Main, ...})`.

## Deviations
1. **[Plan defect] naive-conversion inputs.** The plan says `convertNaively(0.7, 10) == 8`. Measured false: `0.7*10` and `2.9*10` are exact in IEEE double (04-01 found the same). The gate uses `(0.07, 100)` (= 7.000000000000001, ceil gives 8, real gives 7); the plan's inputs stay in the list as non-violating controls. Non-vacuity asserts at least one naive violation.
2. **`seatPoses` type.** Takes `{ { position, look } }` (index = seat, i.e. `mapSpec.cardTable.seats` as is) instead of the plan's `{seat, position, look}`; `SeatSpec` has three fields, no seat field.
3. **`CardService.nowDeci` and `CardService.newRejectThrottle`** are module-level functions (not on the instance) so Main can read the single clock expression and the throttle values before an instance exists, without importing shared config itself.
4. **`removePlayer`** added to the returned record (PlayerRemoving needs it).
5. **`jokerMode`**: `CardPool.JOKER_MODE` widens to `string` and a `::` cast did not satisfy `verify.luau`; narrowed with an explicit if-expression plus an assert (04-11 trap; found by `verify.luau`, not by the suite).
6. The Heartbeat sweep is not pcall-wrapped; a throwing tick logs via the engine's error output.

## Exact shipped surface
```luau
export type SeatPose = { position: CardTable.Vec3, look: CardTable.Vec3 }
export type Deps = {
	publisher: CardRouting.Publisher,
	setPhase: (phase: Gateway.RoundPhase) -> (),
	onCompleted: (seat: number, playerId: number, rank: number) -> (),
	onTelemetry: (name: string, data: { [string]: number }) -> (),
	seatPoses: () -> { SeatPose },
}
export type CardService = {
	startRound, endRound, onIntent, onGatewayReject, removePlayer, seatedUserIds, destroy
}
CardService.new(deps) / CardService.nowDeci() / CardService.newRejectThrottle()
```
Plan 04-15 marker: `-- Plan 04-15: avatar seat / hold / release goes here` with no-op `holdAvatar` / `releaseAvatar`.

## What this does and does not prove
CardService cannot load in Lune. Proven: the conversion site, its arguments, that the constant reaches `IdleClock.new`, clock-file placement, and (by 04-12/04-13) the pure pieces. NOT proven: that `NetServer` maps `toPlayer` to `FireClient(player)` (M-12), that parenting remotes after connecting avoids a dropped-message window (Studio observation), that a live three-player round deals/passes/benches (M-17), the Heartbeat accumulator's behaviour, the avatar hold (still a no-op, 04-15), and Main's wiring (source-checked only). The reject-sink and PlayerRemoving wiring have no executed test.

## Notes
- STATE.md, ROADMAP.md, REQUIREMENTS.md untouched; `requirements.mark-complete` not run.
- Gateway.luau and src/server/engine untouched.
- A full-suite run costs about 25 s on this container; budget not re-measured here.

## Self-Check: PASSED
