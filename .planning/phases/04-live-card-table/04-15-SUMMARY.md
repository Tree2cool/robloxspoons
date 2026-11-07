---
phase: 04-live-card-table
plan: 15
subsystem: server-card-table
tags: [seat-hold, ux-02, card-17, m-11, unproven]
requires: [04-02, 04-12, 04-14]
provides: [core/CardSeatHold, CardService seat-hold effects]
affects: [04-20, phase-6-map-contract]
key-files:
  created: [src/server/core/CardSeatHold.luau, tests/card/seathold.spec.luau]
  modified: [src/server/services/CardService.luau, MANUAL-CHECKS.md]
requirements: [UX-02, CARD-17]
metrics:
  completed: 2026-11-07
---

# Phase 4 Plan 15: CardSeatHold Summary

Pure hold/release bookkeeping (stop before place; capability back before control) with the Roblox
effects (`Dev*MovementMode = Scriptable`, zeroed humanoid, `PivotTo`) wired into CardService. **The
hold is an attempt. Whether it holds anything is UNPROVEN pending M-11 (assumption A2).**

## What shipped
- `CardSeatHold.luau` (pure zone): hold, release, onCharacterAdded, forget, releaseAll, isHeld, heldCount.
  Pose is copied on hold. `pivotTo == false` queues the pose, emits `seat_hold_deferred`, and the next
  `onCharacterAdded` re-applies the same pose.
- `CardService.luau`: marker block replaced. Restore targets captured from `StarterPlayer` at boot.
  Seat hold is built per service instance (so telemetry reaches `deps.onTelemetry`). Release sits first in
  `onCompleted` (already before `deps.onCompleted`), and in `onSeatRemoved`, `removePlayer`, and `endRound`
  via `releaseAll`. `CharacterAdded` and `PlayerRemoving` (-> `forget`) connections are tracked and
  disconnected in `destroy`.
- `MANUAL-CHECKS.md` M-11: six server-hold rows; cheat cell kept as four separately recorded attempts
  (a TouchControlsEnabled, b WalkSpeed, c Humanoid:Move, d CFrame/PivotTo). Nothing ticked.

## Measured
- `tests/run.luau`: 826 passed, 0 failed (25.0 s; card root 154 passed).
- `scripts/verify.luau`: all 14 automated steps passed in 28.2 s; M-11 still listed unsigned.
- Forbidden-identifier scan over `src/` (`GetControls|PlayerModule|ControlModule|ModalEnabled`): 0 hits.
  Words "enforced"/"prevents" appear nowhere in the two source files; the remaining "cannot" hits are
  pre-existing unrelated comments.

## Mutations (each run red, then restored)
Clean control: `seathold: clean control 0 problems over 5 checks` (non-vacuity asserts exactly 5 checks;
a first draft asserting >= 6 failed and exposed my own miscount).
- pivot-first -> `hold order: pivot:7:1,2,3,scriptable:7:true,freeze:7:true`
- control-first -> `release order: ...,scriptable:7:false,freeze:7:false`
- not-idempotent -> `second release added 2 entries | release of a never-held player logged freeze:9:false,scriptable:9:false`
- no-refreeze -> `respawn tail: pivot:7:1,2,3`
- Real-source mutation (swapped the two release lines in `CardSeatHold.luau`): `FAIL ... release restores
  capability before control (D-30)` and `FAIL ... MUTATION` (152 passed, 2 failed); restored -> 154 passed.
- The four mutants are alternate implementations of the interface driven through the same injected effects,
  not patches of the real file; the real-source swap above is the check that the real module is what is judged.
  A no-defect twin of the mutant harness is asserted green so the mutants cannot be red for harness reasons.

## Deviations
- [Rule 3] The seat hold is constructed inside `CardService.new` (not module level) so its telemetry reaches
  the instance's `deps.onTelemetry`; `holdAvatar`/`releaseAvatar` became closures there. Marker comment
  converted to a section heading.
- The acceptance grep `Humanoid\b` hits the interface-mandated effect name `freezeHumanoid` (4 lines); no
  Roblox type is named. Left as specified.
- `releaseAll` in the core calls the shared release closure, so ordering holds there too.

## Not verified / limits
- Nothing here runs a Roblox server. `CardService` effects are covered by typecheck (roblox platform) and
  review only; no spec asserts the wiring (call sites in `onCompleted`, `removePlayer`, `endRound`,
  `PlayerRemoving`) beyond the pure core. A source-scan for the wiring would be a reasonable follow-up but
  was not added (time budget, no subprocess gate).
- `Dev*MovementMode`/`GetControls`-free design is untested under IAS; M-11 rows 1-6 are the evidence.
- `onCompleted` ordering in `CardTable` (release callback before `deps.onCompleted`) was read, not changed.

## Known Stubs
None.

## Threat Flags
None beyond the plan's register (T-4-107 stays `mitigate, UNPROVEN`).

## Commits
- fafc021 feat(04-15): CardSeatHold pure core + spec
- e102efb feat(04-15): CardService effects + M-11 rows

## Self-Check: PASSED
