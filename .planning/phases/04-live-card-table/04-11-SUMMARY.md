---
phase: 04-live-card-table
plan: 11
subsystem: card-hud
tags: [hints, controls, ux-02, ux-04, pure-zone]
requires: [04-01, 04-04, 04-08]
provides: [Hints, Controls]
affects: [04-16, 04-17, 04-18, 04-19]
key-files:
  created:
    - src/shared/Card/Hints.luau
    - src/shared/Card/Controls.luau
    - tests/card/hints.spec.luau
    - tests/card/controls.spec.luau
metrics:
  completed: 2026-11-07
---

# Phase 4 Plan 11: Hints and Controls Summary

Pure `Hints` (20-cell state x input table, strip messages, callouts, audit) and the pure `Controls.hide/restore/onLocalCompleted` seam over injected effects, with a src-wide scan that no legacy-controls identifier exists.

## Measured
- `tests/card`: 134 passed (3 readings 0.24 / 0.27 / 0.28 s; minimum 0.24 s, within the 2.09 s allocation).
- Full suite: 806 passed, 0 failed. `scripts/verify.luau`: all 14 automated steps passed (29.4 s), including the standard-platform typecheck.
- Hint table: 20 cells. `audit` measured 41 strings (20 cells + 17 messages incl. 2 joker explainers + rotate prompt + 2 callouts).
- Longest strip string: 34 chars, "Auto-passed a card. Strike 1 of 3." Worst-case strip headroom over the 4 reference viewports: 1.806 (assertion >= 1.5), 156 measurements. Longest callout: 40 chars (name truncated to 18).
- Forbidden-identifier scan: 50 files walked, 0 hits; negative control fires exactly once.

## Mutations, watched red (clean control green in the same case)
1. `missing cell: Selected/Gamepad`
2. `too long: message waiting is 40 > 34`
3. `stray exclamation: message waiting`
4. `forbidden error copy: message waiting contains "rejected"`
5. never-restores: `completed order: setTouchControls:false,bindSink,destroyOverlay,startFlourish | D-30: flourish at 4 not after controls restored at -1`
6. flourish-first: `completed order: ...,destroyOverlay,startFlourish,unbindSink,setTouchControls:true | D-30: flourish at 4 not after controls restored at 6`
7. reenable-first: `restore order: setTouchControls:false,bindSink,setTouchControls:true,unbindSink,setTouchControls:true`

## Shipped types (04-16, 04-18, 04-19 build against these)
```luau
export type Effects = {
	setTouchControls: (enabled: boolean) -> (),
	bindSink: () -> (),
	unbindSink: () -> (),
	destroyOverlay: () -> (),
	startFlourish: () -> (),
}
export type Controls = {
	hide: (self: Controls) -> (),
	restore: (self: Controls) -> (),
	onLocalCompleted: (self: Controls) -> (),
	isHidden: (self: Controls) -> boolean,
}
Controls.new(effects: Effects): Controls
```
Hints additionally exports `Owes`, `AuditInput`, `KIND_OF`, `sampleMessages(jokerExplainers?)`, `sampleCallouts()`. `strike(k >= 3, _)` returns the benched line.

## Deviations
- **[Rule 3] Typecheck.** The standard-platform solver widens annotated string-literal-union arrays/tables to `string` through `table.freeze({...})`. In `Hints.luau` the typed local is built first and frozen after; in the specs a few `:: any` casts and record-shaped cases (`{ name, kind }`, since `{ name, nil }` is not a 2-array) were needed. The suite ran green before verify.luau did (fifth confirmation of that gap).
- `audit` is fed flat sample maps (`sampleMessages`, `sampleCallouts`) rather than the function tables, so a mutation is an injected string; the plan interface left this open.
- The Controls header avoids spelling the four forbidden identifiers (the scan covers comments); it says "legacy controls getter" instead.
- The header's "four rewritten strings" is the UI-SPEC row count; the rewritten literals number five (RightPileSink Touch and Mouse count as one row).

## Notes
- The rendering consequence from 04-09 (forced pass landing while the player's own Pass is in flight, and a rolled-back Draw placeholder with no id) is covered: "Table stuck. We passed for you." names no card.
- No gate was impossible to fail. The `reenable-first` mutant is caught only by the restore-order check, not the D-30 check, which is correct.

UX-02 remains human-gated under M-11; this plan does not claim it met on device.

## Self-Check: PASSED
