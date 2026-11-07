---
phase: 04-live-card-table
plan: 08
subsystem: ui-layout
tags: [layout, pure-zone, UX-01, UX-03]
requires: [04-01, 04-04]
provides: [Layout.DESIGN, Layout.solve, Layout.problems, Layout.scaleFor, Layout.SCREEN_INSETS]
key-files:
  created: [src/shared/Card/Layout.luau, tests/card/layout.spec.luau]
metrics: {tasks: 2, files: 2}
---

# Phase 4 Plan 08: Layout Summary

The UI-SPEC geometry as pure arithmetic: a frozen `Design` table, `scaleFor`, `solve` (full rect solution per hand size) and a counting `problems` auditor, with a 72-case `tests/card` root and 8 mutation rows.

UX-01 and UX-03 are **NOT closed**. This proves arithmetic only. Physical size on glass, thumb reach, `CoreUISafeInsets` behaviour on a notched device, the strip at `PreferredTextSize = Largest` and the camera projection into `tableRegion` remain **M-12 / M-11**.

## Commits
- 4e71b66 feat: Layout.luau
- second commit: spec, plus a typing fix in Layout (see deviations)

## Measured
- `tests/card`: 72 passed, 0 failed, 0.09 s (three readings, each 0.09 s; allocation 2.09 s)
- full suite: 744 passed, 0 failed, 24.57 s
- `scripts/verify.luau`: all 14 automated steps passed
- clean control: 8 viewport x hand pairs, 404 checks; 52 interactive rects; 36 lifted-slot checks; 64 hit-pair checks

| viewport | scale | tableRegionFraction | strip headroom |
|---|---|---|---|
| phone notched 844x390 | 1.0487 | 0.5908 | 1.82 |
| phone small 640x360 | 0.85 | 0.6222 | 1.81 |
| phone large 932x430 | 1.1605 | 0.5914 | 1.82 |
| desktop 1920x1080 | 1.5 | 0.7931 | 3.10 |

Floor case (600x300 clamps to 0.85): hit strip measures 51 physical px.

## Mutations (each with clean control asserted in the same case)
- STEP=44: red 8/8, `step below touch floor: 44 x 0.85 < 48`; also `hit overlap: slot1 and slot2` 8/8
- SCALE_MIN=0.7: red 8/8 `step below touch floor: 60 x 0.7 < 48`; physical on a 500x250 viewport 2/2 `below touch floor: slot1 is 42 x 75.6 physical`
- HIT_W=48: red 2/8 (only scale < 1), `below touch floor: slot1 is 40.8 x 91.8`
- HANDZONE_H=170: red 6/8, `table region too small: 0.5168 < 0.58`
- LIFT=20 (F1): `lift overlaps strip: slot1 lifted gap 0` 8/8 and `hit height: 108 ~= 92 + 20` 8/8
- INDEX_INSET_X=12 (F2): `index inset: 12 <= overlap 12` 8/8
- insets ignored: something outside the safe rect on 4/4 viewports
- PILE_MARGIN=-12: `outside safe rect: leftPile ...` and `rightPile` 8/8; blames no slot or fan
- FAN_BOTTOM_MARGIN=-16: `outside safe rect: slot1` and `fan` 8/8; blames no pile

## Deviations / findings
1. **[Rule 3] Typing**: a literal `{ leftPile = ..., rightPile = ... }` iterated in `problems` typed `unknown` under the roblox-platform analyze (which `tests/run.luau` does not run). Replaced with a typed list. Caught only by `verify.luau`.
2. **Spec-compat additions to `problems`**: added a `hit overlap:` check. Without it `STEP = 44` only trips the relation check, because `HIT_W` is a separate constant that would silently overlap neighbours. Lift clearance treats touching as a violation (gap <= EPS), required for LIFT=20 to be red since a 20 lift lands exactly at gap 0.
3. **Plan mismatch**: the plan says the SCALE_MIN=0.7 and HIT_W=48 mutations give `below touch floor:`. On the four reference viewports SCALE_MIN=0.7 only trips `step below touch floor:` (no reference viewport is small enough to clamp to 0.7), so the physical form is proven on a contrived 500x250 viewport. HIT_W=48 is red only where scale < 1 (2 of 8 pairs): at scale >= 1 a 48-wide strip really is 48 physical px.
4. Plan text says "seven"/"six" mutations in places and 8 in others; 8 rows asserted (`assert 8`).
5. Callout width is not in the UI-SPEC table; chosen as `STRIP_MAX_CHARS * CHAR_WIDTH_PROXY` capped to the strip width.
6. The strip is `safe width - 2 * STRIP_MARGIN`, per the plan interface table, though the objective text says "full safe width".
7. The two worst TableRegion fractions are 59.08% (phone notched) and 59.14% (phone large), above 58.

## Self-Check: PASSED
Both files exist and both commits are in git log. STATE.md, ROADMAP.md, REQUIREMENTS.md untouched.
