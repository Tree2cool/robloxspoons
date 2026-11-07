---
phase: 04-live-card-table
plan: 16
subsystem: client-ui
tags: [roblox-ui, screengui, safe-area, text-constraint, discipline-gate]
requires: [04-04, 04-08, 04-11, 04-13]
provides:
  - CardTheme (single home for colour, font, stroke)
  - CardHud (ScreenGui root, zones, viewport re-solve, rotate prompt)
  - CardStrip (single-line strip, drain bar)
  - tests/card/renderer_discipline.spec.luau
affects: [04-17, 04-18, 04-19]
key-files:
  created:
    - src/client/ui/CardTheme.luau
    - src/client/ui/CardHud.luau
    - src/client/ui/CardStrip.luau
    - tests/card/renderer_discipline.spec.luau
decisions:
  - "Hand-4 AFK cue pulses nothing; countdown text and drain bar carry it, left-pile ring keeps one meaning"
  - "ScreenInsets mapped through INSETS_BY_NAME[Layout.SCREEN_INSETS], not concatenation (see Deviations)"
metrics:
  tasks: 3
  completed: 2026-11-07
---

# Phase 4 Plan 16: CardTheme, CardHud, CardStrip Summary

One ScreenGui with explicit `CoreUISafeInsets` mapped from the pure `Layout.SCREEN_INSETS` string, a
single-line status strip with a `UITextSizeConstraint`, a separate rotate-prompt gui, and a
comment-stripped discipline gate whose needles are derived from `Layout.DESIGN` and `Config.Card`.

## Commits
- b8513e7 CardTheme
- e8a8e0d CardHud + CardStrip
- 99d743e renderer_discipline.spec

## Shipped types (04-17/18/19 build against these)
`Hud`: `resolve(self, handSize) -> Layout.Solution`, `solution() -> Solution?`, `tableRegion() -> Frame`,
`handZone() -> Frame`, `gui() -> ScreenGui`, `destroy()`, `onViewportChanged(fn)`. Constructors:
`CardHud.new(handSize): Hud`, `CardHud.newRotatePrompt(): RotatePrompt`.
`Strip`: `setHint(state, kind)`, `setMessage(text, seconds)`, `setCountdown(owes, secondsLeft?)`,
`clearCountdown()`, `relayout(solution)`, `destroy()`. `CardStrip.new(parent: Frame, solution)`. The
parent must be the Hud's `handZone` (design units; rects are converted relative to the hand zone).
Precedence: countdown > message > hint. Frames are in design units under one `UIScale`.
`CardTheme` additionally exports `PLATE_OPACITY = 0.85` (the spec's 0.15 transparency as its complement,
so it does not collide with `TWEEN.DRAW = 0.15`; the HUD uses `1 - PLATE_OPACITY`).

## Verification
- `scripts/verify.luau`: all 14 steps passed (typecheck roblox + standard, guards, selene, stylua).
- `tests/run.luau`: 822 passed, 0 failed, 0 todo. `tests/card` root: 150 cases, 0.30 / 0.33 / 0.37 s
  (minimum of three 0.30 s, in-process, no subprocess gate).

### Printed scan output
```
[1] 3 files, 22 needles: 0.58,0.85,1.5,8,12,16,24,28,32,48,52,60,68,72,84,92,96,108,144,300,350,760
[2] per-file hits CardTheme.luau=14,CardStrip.luau=0,CardHud.luau=0
[3] 3 files, needles: 0.08,0.12,0.15,0.18,0.2,0.25,0.3,0.4,0.8,1.5,2,2.5,3
[4] 3 files, 9 identifiers, 0 hits
[5] CardHud raw 9787 -> stripped 6056, Enum.ScreenInsets. hits 1
[6] CardStrip raw 6557 -> stripped 4037, problems 0
```
Negative controls inside the spec: `UDim2.fromOffset(144, 92)` reports exactly 2 hits while a comment, a
string and `slot144x` report 0; a `-- ...Enum.ScreenInsets.CoreUISafeInsets` comment gives 0 hits and the
same text in code gives 1; a comment-only presence of the four strip settings is reported missing; a
comment holding a contradicting assignment is not a contradiction. Cases 5 and 6 additionally inject
defects into the REAL stripped text (wrong member, second assignment, `IgnoreGuiInset`, respawn flag
true, unlinked mapping, comment attack, scaled/wrapped/rich text, literal `MaxTextSize`, prose in the
strip) and assert each is reported.

### Mutations on shipped files (each run red, restored with `git checkout -- file`)
| # | Mutation | Red case |
|---|---|---|
| M1 | `UDim2.fromOffset(144, 92)` in CardHud | geometry literal (case 1) |
| M2 | enum member `DeviceSafeInsets` | ScreenInsets mapping (case 5) |
| M3 | second `ScreenInsets` assignment | case 5 |
| M4 | strip `TextWrapped = true` | one-line strip (case 6) |
| M5 | `MaxTextSize = 20` literal | case 6 |
| M6 | `Color3.fromRGB` in CardHud | single palette home (case 2) |
| M7 | `0.15` literal in CardStrip | timing home (case 3) |
| M8 | `rankOf` in a CardHud comment | forbidden identifier (case 4, raw text) |
| M9 | `IgnoreGuiInset = true` | case 5 |
| M10 | mapping unlinked from `Layout.SCREEN_INSETS` | case 5 |
| M11 | `UITextSizeConstraint` removed | case 6 |
| M12 | `0.18` in CardTheme | case 3 (theme not exempt for timings) |
| M13 | `144` in CardTheme | case 1 (theme allowance is exact) |
| M14 | prose string in strip | case 6 |
| M15 | `DESIGN.PILE_W = 88` plus literal 88 in HUD | case 1 (needle list follows DESIGN) |
| M16 | `Layout.SCREEN_INSETS = "DeviceSafeInsets"` | case 5 and layout.spec |

All 16 went red on exactly the intended case; none was unreachable.

## Deviations from Plan

**1. [Rule 1 - Plan defect] "composed by concatenation" is not implementable.** The plan asked for
`"ScreenInsets = Enum.ScreenInsets.." .. Layout.SCREEN_INSETS`, but an enum member cannot be built from
a string by concatenation, and it also contradicts the plan's own acceptance grep
(`Enum.ScreenInsets.CoreUISafeInsets` in CardHud) and its "exactly once" assertion. Implemented the
plan's other stated route: a one-entry local table `INSETS_BY_NAME` keyed by the string, read as
`INSETS_BY_NAME[Layout.SCREEN_INSETS]`. The gate asserts `Enum.ScreenInsets.` exactly once, the member
equals `Layout.SCREEN_INSETS`, `.ScreenInsets` is assigned exactly once, and the assignment reads through
the map. A one-sided change to either side fails (M2, M10, M16). Both ScreenGuis share one `applyInsets`
helper, which is how there is one assignment for two guis.

**2. [Rule 3] Case 1 needs an explicit CardTheme allowance.** Text sizes and the corner radius collide
with geometry by coincidence (16 = LIFT, 28 = STRIP_H, 8 = STRIP_MARGIN, 0.85 = SCALE_MIN) and colour
channels collide too (24, 32, 52). The spec blanks `Color3.fromRGB(...)` arguments and allows exactly
`{8, 16, 28, 0.85}` in CardTheme only. M13 proves any other geometry number there is still caught. The
plate transparency is stored as `PLATE_OPACITY = 0.85` because `0.15` is `TWEEN.DRAW`, which case 3
forbids anywhere in the folder.

**3. Needle exclusion is whole numbers 0..4 only.** A first version excluded every value <= 4, which
silently dropped 0.58, 0.85 and 1.5; the printed needle list exposed it and it was fixed before any
commit.

**4. Case 3 also includes `AFK_WARN_SECONDS`** (the strip reads it for the drain fraction), beyond the
plan's `TWEEN` and `PULSE_HZ`.

**5. The "no string literal other than empty" claim** is asserted weakly: no literal containing a space
(instance and property names have none). Case 6, with a prose-injection control (M14).

## Known limits and what is NOT proven
- **No visual claim.** This container has no Studio and no phone. UX-01, UX-02 and UX-03 are NOT closed.
  Target size on glass and the strip at `PreferredTextSize = Largest`: **M-12**. Insets on a notched
  device and whether insets alone suffice: **M-12** (header comment in CardHud). Landscape lock:
  **M-15**; whether a script-side `LandscapeSensor` request overrides it is unverified (N-3). Overlay
  gone in the same frame as completion and respawn survival: **M-11**. Builder Sans availability: **M-16**.
- The CardHud construction is typechecked (roblox platform) and text-scanned, never executed; CardHud
  and CardStrip cannot load in Lune.
- `readViewport` takes insets from `GuiService:GetGuiInset()` and positions zones relative to the safe
  origin; whether that double counts under `CoreUISafeInsets` is the M-12 observation.
- The strip stores a `task.delay` thread and cancels it on the next message and on destroy; this is
  source-reviewed only (no executed test).
- The zero-gap clearance trap in the brief does not arise: this plan asserts no rect clearance. The
  second trap (two constants encoding one intent) is the reason M13/M15 exist; both reach case 1.
- **Forced-pass pair rendering (04-09 race):** not rendered here, since this plan draws no cards. The
  strip's forced-pass copy names no card, so it reads correctly with either change. The two-change
  rendering (a card leaving that the player did not choose plus their own in-flight card returning, and a
  `Removed` with no `cardId` meaning a face-down placeholder leaves) is owed to 04-17/04-18.

## Known Stubs
None.

## Threat Flags
None. `src/client/ui` stays outside the guarded roots as directed; no `guardedNamePrefixes` change.

## Not touched
STATE.md, ROADMAP.md, REQUIREMENTS.md; `requirements.mark-complete` not run.
