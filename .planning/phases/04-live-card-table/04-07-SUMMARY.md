---
phase: 04-live-card-table
plan: 07
subsystem: server-core
tags: [stall-detector, reject-throttle, D-20, D-22, pure-core]
requires: [04-01, 04-02]
provides: [StallDetector, RejectThrottle]
affects: [04-12, 04-14]
key-files:
  created:
    - src/server/core/StallDetector.luau
    - src/server/core/RejectThrottle.luau
    - tests/card/stall.spec.luau
    - tests/card/reject_throttle.spec.luau
  modified: []
key-decisions:
  - "D-20: noteApply takes no event parameter; a valve event is unfeedable"
  - "D-22 reviewed in Phase 4: gateway order kept, log throttled at the sink, trade-off accepted, no kicking this phase"
metrics:
  completed: 2026-11-07
---

# Phase 4 Plan 07: StallDetector and RejectThrottle Summary

Valve-independent stall cue (accepted actions without progress AND 45 s) and a per-user reject-log throttle that closes 01-CONTEXT D-22 without touching Gateway.luau.

## Commits
- f56fbba StallDetector + stall.spec
- 9b17db4 RejectThrottle + reject_throttle.spec

## D-22 decision (quotable)
Reviewed in Phase 4: the gateway check order is kept and a wrong-phase rejection still charges no token. The real exposure was the unthrottled per-rejection warn, so the onReject sink gets a per-user log throttle (first 3 per 10 s window, one summary of the suppressed count when the window closes). The trade-off, that a real diagnostic can be lost inside a flood, is accepted and compensated by the summary and a per-user streak. No kicking in this phase; `streakOf` is reserved for Phase 8. Gateway.luau is byte-identical.

## Measured
- `tests/run.luau --root tests/card`: 23 passed, 0 failed, 0 todo. Full `tests/run.luau`: 695 passed, 0 failed, 0 todo. stylua, selene (std and pure), check-guards (105 files) and `scripts/verify.luau` clean.
- Healthy control: `max actionsSinceProgress = 70, worst ratio to 96 x liveSeats = 0.243 (70 / 288), margin = 4.1x, progress events = 6, actions = 380`. Outside the 2x finding line.
- Stuck scenario: 8 cues over 3000 actions, first at deci 864, repeats exactly 300 deci apart.

## Mutations (verbatim)
1. Valve-keyed detector (injected): `[stall] MUTATION valve-keyed cues = 0; real detector cues = 8`.
2. Wall-time condition removed from StallDetector (temporary edit, restored): `FAIL ... neither condition alone arms the cue / armed on the action count alone (expected 0, got 1)`; 13 passed, 1 failed.
3. Action condition removed (`actions >= 0`, restored): 4 FAIL, e.g. `armed on wall time alone (expected 0, got 19)`, `300 actions at 9 seats is below 96 x 9 and must not arm (expected 0, got 1)`; 10 passed, 4 failed.
4. Unthrottled sink (injected): `[throttle] MUTATION unthrottled logs 10/10; real throttle logs 3/10`.
5. Per-code throttle (injected): `[throttle] MUTATION per-code logs 10/10; real throttle logs 3/10`.
6. Real throttle with logging limit removed (temporary edit, restored): 5 FAIL, e.g. `decision 4 (expected false, got true)`, `summary on the closing call (expected 7, got nil)`; 18 passed, 5 failed.

## Findings / deviations
- The mutations in the plan (valve-keyed, unthrottled, per-code) are injected dependencies and are green by design; "going red" was shown additionally by editing the real modules (2, 3, 6) and restoring.
- FINDING: the healthy-control margin (4.1x) rests on a scripted 380-action spacing that is an approximation of measured pacing, not a measurement. A threshold halved to 48/seat (the valve's own value) gives about 2.05x and would still pass the "margin >= 2" assertion, so the healthy control cannot separate 96 from 48. The justification for 96 over 48 is the Card.luau/config_lock relation to the valve, not this control. Threshold not adjusted. Phase 8 should tune on `stall_armed`/`stall_cleared` telemetry.
- Throttle windows are aligned to the user's first rejection; a streak continues only when the very next window is the one opening.
- Deviation: none to scope. Wiring (`Main.server.luau`, `forget` on PlayerRemoving, Sync push on a gateway reject) is plan 04-14.

## Self-Check: PASSED
Files and both commits exist; Gateway.luau unchanged.
