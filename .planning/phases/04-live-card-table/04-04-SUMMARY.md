---
phase: 04-live-card-table
plan: 04
subsystem: card-faces
tags: [pure-zone, greyscale, CARD-19, D-21, D-22, D-23, D-24]
requires: [04-01, 04-02]
provides: [src/shared/Card/Faces.luau, pureZones registration of src/shared/Card, faces.spec gate]
affects: [04-05, 04-12, 04-17]
key-files:
  created: [src/shared/Card/Faces.luau, tests/card/faces.spec.luau]
  modified: [scripts/ci/zones.luau, tests/guards/guards.spec.luau]
decisions:
  - "faceOf takes an optional third arg `mode` so a joker face is constructible without requiring CardPool"
  - "pip codepoints built with utf8.char: the pure selene config warns on the unicode escape"
metrics:
  tasks: 2
  completed: 2026-11-07
---

# Phase 4 Plan 04: Card Faces Summary

Frozen, table-driven face vocabulary (rank ladder `A K Q J 10 7 4 2 5 3 9 8`, suit per copy, drawn-asset
pips, joker WILD/BLOCK band) with a self-`audit` that takes its tables as arguments, plus the CARD-19
greyscale gate. `src/shared/Card` is now a registered pure zone.

Commits: a2711ad (Faces + zone), 260b086 (spec), plus the guards.spec fix commit.

## Gate design
Layer 1: all 50 identity keys distinct (`audit` visited count asserted == 50). Layer 2: each suit's DRAWN
asset (glyph, or the four sprite numbers when `pipSource = "sprite"`) is distinct, read from the same
table the renderer uses; both sources asserted green. Spade vs club at 16 px is the hardest pair for
the human half. Tint is not in the key; case 8 flips every `isRedByDefault` and proves nothing moves.
D-37: zero `rankOf` hits in `src/shared` and `src/client`; no `os.` in Faces.

## Mutations watched red (verbatim, abridged to the load-bearing line)
Each was a SOURCE edit of Faces.luau (then restored), in addition to the injected-copy mutations the spec
runs itself.
- Club silhouette collapsed to spade: `duplicate identity key: A/spade ...`, `duplicate silhouette: spade`
  (6 cases red).
- Diamond glyph = heart glyph: `expected {  }, got { [1] = "duplicate drawn asset: ♥" }` (6 cases red).
- Blocker shape = star: `expected {  }, got { [1] = "duplicate joker band: Blocker" }` (6 cases red).
- Sprite x forced to 0: `audit is not green under pipSource = sprite (... "duplicate drawn asset: 0,0,64,64" x3)`.
- Audit weakened to read `pip.suit` instead of the drawn glyph (a proxy): only
  `MUTATION: pointing two pip ids at the same drawn asset turns the gate red` fails, `expected a truthy
  value, got false` -- proving the audit must read the drawn asset.

## Measured
- `lune run scripts/ci/check-guards.luau`: `check-guards: ok (103 files, 296 requires, 25 guarded roots)`
- `--print-zones`: `src/server/engine src/server/core src/shared/Net src/shared/Card`
- `--root tests/card`: 15 passed, 0 failed, 0 todo
- Full suite: 687 passed, 0 failed, 0 todo in 24.66s (before the guards.spec fix: 686 passed, 1 failed).
  Wave-1 baseline 677 in 27.83 s; this run 25.14 s. The +0.4 s selene cost is below run-to-run noise.
- `lune run scripts/verify.luau`: all 14 automated steps passed in 27.1s (includes the standard-platform
  analyze over the new zone).

## Deviations
1. [Rule 1] `tests/guards/guards.spec.luau:233` pinned the exact `--print-zones` string; the plan said no
   test edit was needed. Updated it to include `src/shared/Card`.
2. [Rule 3] `\u{...}` escapes raise `bad_string_escape` warnings under `selene.pure.toml`; used
   `utf8.char(0x2660)` etc. (utf8 passes the pure lint).
3. `faceOf(rank, copy, mode?)` gained the optional mode argument (see decisions); errors by name if a joker
   is requested without it.

## Not closed
CARD-19's human half remains open under M-14 and M-16 (distinguishable pixels at 16 px, Builder Sans
glyph coverage). Not ticked. STATE/ROADMAP/REQUIREMENTS untouched per orchestrator instruction.

## Addendum: case 8 strengthened (coordinator request)
Case 8 (`colour is not part of any identity key`) now also asserts `Faces.faceOf(r, c).key` equals the
independently rebuilt `(glyph, silhouette)` key for all 48 faces, so both public key paths are checked.
Source mutations, restored afterwards:
- `keyOf` folds tint: red, `a tint flip changed a key (expected A/spadeb, got A/spade)`. The original
  case 8 already caught this, because its reference was rebuilt independently.
- `faceOf` key folds tint: red with the new assertion, `faceOf key differs from the (glyph, silhouette)
  rule (expected A/spade, got A/spadeb)`. The original case 8 would NOT have caught this; that was the gap.
Recorded limit: `audit` never calls `keyOf`/`faceOf` (it rebuilds keys itself), so a tint-folding bug in
those two is caught only by case 8, not by the audit.
Suite after: 687 passed, 0 failed, 0 todo in 23.73s.

## Self-Check: PASSED
