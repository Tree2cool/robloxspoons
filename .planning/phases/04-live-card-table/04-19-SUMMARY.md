---
phase: 04-live-card-table
plan: 19
subsystem: client-table-place
tags: [roblox, luau, client, flourish, audio, callout, privacy, wire]
requires: [04-10, 04-14, 04-17, 04-18]
provides: [CardSeatsView, CardCallout, CardFlourish, CardAudio, Depths kind, RoundEnd kind, CardHud.newGui/mount/newOverlay]
affects: [04-20, Phase 7]
key-files:
  created:
    - src/client/ui/CardSeatsView.luau
    - src/client/ui/CardCallout.luau
    - src/client/ui/CardFlourish.luau
    - src/client/ui/CardAudio.luau
    - tests/card/flourish_surface.spec.luau
    - tests/card/round_end.spec.luau
  modified:
    - src/server/core/CardRouting.luau
    - src/server/core/CardTable.luau
    - src/server/services/CardService.luau
    - src/client/ui/CardClient.luau
    - src/client/ui/CardHud.luau
    - src/shared/Config/Card.luau
    - tests/card/privacy.spec.luau
    - tests/card/routing.spec.luau
    - tests/card/netguard.spec.luau
metrics:
  completed: 2026-11-07
  tasks: 3 plus 2 wire gaps
  commits: cc26501, c7de26d, 2017abc, e1a94a4, 405ef90
---

# Phase 4 Plan 19: the table as a place, plus two wire gaps

Per-seat 3D stacks from server-supplied depths, pooled face-down hops driven by public `Passed` events, a who-went callout that survives the hand's destruction, a flourish Surface whose scan covers five input-taking kinds and whose `destroyOffenders` really destroys them, silent-by-contract audio, and two wire changes found at integration (`Depths`, `RoundEnd`).

**Not claimed closed: CARD-13, CARD-17, UX-01, UX-02, UX-03.** None of CardSeatsView, CardCallout, CardFlourish, CardAudio, CardClient can load in Lune. They are typechecked (`verify.luau`, both platforms) and text-scanned, plus one function (`offenderKind`) executed over fakes. Whether stacks read, a hop reads as a pass, one extra card is a visible step, the starting gun reads as a starting gun, the callout fits, and any audio exists are **M-12, M-14, M-16, M-17**. UX-02 on a phone (controls really return after `RoundEnd`) is **M-11**. CARD-17's feel half is open. `requirements.mark-complete` was not run; STATE.md, ROADMAP.md, REQUIREMENTS.md untouched.

## Verification (measured)

- `lune run tests/run.luau`: **858 passed, 0 failed, 0 todo in 25.35s**
- `lune run tests/run.luau -- --root tests/card`: **186 passed, 0 failed** (04-18 left 169), **0.52 / 0.55 / 0.55 s** on the clean tree (three readings)
- `lune run scripts/verify.luau`: **all 14 automated steps passed in 27.9s**
- `stylua --check src scripts tests`, `selene` 0/0/0, `check-guards: ok (145 files, 436 requires, 36 guarded roots)`. `grep rankOf src/shared src/client` and the forbidden-identifier grep print nothing.
- **Per-spec cost:** 04-18 measured 0.43-0.46 s for 169 specs; now 0.52-0.55 s for 186 (+17 specs): about **+0.09 s** for this plan including both wire gaps. Of that, the larger part is `luau.load` compiling the extracted predicate 8 times and the 7 full-source mutations in `round_end.spec`. No sample size, mutation, non-vacuity assertion or clean control was cut. Remaining budget for 04-20 is about 0.70 s.

## Surface.scan kind coverage (the F8 hole)

`offenderKind` is one predicate shared by `scan` and `destroyOffenders` (`offendersUnder(` appears exactly 3 times: definition, scan, destroyOffenders), so what is reported is exactly what is destroyed. It reports: **Active** GuiObject, **Interactable** GuiButton, **ClickDetector**, **ProximityPrompt**, **TextBox**.

The gate EXECUTES the real predicate text (extracted from the stripped source, `luau.load`) over 8 fakes: 5 input kinds detected, plus a plain Frame (Interactable=true, Active=false), a Part and a disabled button that must NOT be reported. Printed: `flourish_surface case 3: 8 probes run, 5 kinds detected, 0 problems`.

## Wire gap 1: pile depths (own commit cc26501)

New public kind `Depths` = `{ depths = { count per seat } }`, built by `CardTable` from live engine state at apply time (so a later command in the same sweep cannot change what this batch says) and published right after `RoundStart` and after every `Table` batch. Dealer first message at the deal measured `13,0,0`: the dealer is the tallest by construction, no marker. The client validates (finite, non-negative) and feeds the reducer and the stacks; anything malformed is ignored, never repaired.

**Privacy assertion result:** `privacy case 6: 25 Depths messages, 125 nodes walked, first = 13,0,0`, 0 problems. The helper checks, per message: sent `toSeated`; key set is exactly `depths`; recursive key-name walk bans `rank, cardId, copy, hand, inbox, faces, card, cards, fifth`; every value is a non-negative integer (never a table); the last message equals the true inbox sizes.

Mutations (injected publishers, each through the same helper; no-defect twin asserted green first, 25 messages):

| Mutant | Red output |
|---|---|
| `rank` added to the payload | `50 problems, e.g. Depths call 1 keys are depths,rank, expected exactly depths` (and case 2's walk also reddens) |
| a `cardId` table in place of a count | `51 problems, e.g. Depths1.depths.1.cardId is a card-identity key inside a Depths payload` |
| stale zeros | `1 problems, e.g. the last Depths says seat 1 holds 0, truth is 13` |

Real-source (CardTable edited, restored): `return { depths = depths, rank = 1 }` turned **4 failed** (case 2 walk, the five-leaks control, case 6, the depths mutation control: `call2:Depths.rank crossed to a public audience`...). `seat.inbox[1]` in place of `#seat.inbox` turned **2 failed** (`Depths call 1 has 1 entries`, `the last Depths says seat 1 holds 17, truth is 13`). Both restored to 171.

## Wire gap 2: RoundEnd (own commit c7de26d)

`CardService.endRound` now publishes `toSeated("RoundEnd", {})` after `seatHold:releaseAll()` and BEFORE `table.clear(seated)` (toSeated reads that list; clearing first reaches nobody), guarded on a live round and contained so a failed publish cannot stop the reset (telemetry `round_end_publish_failed`). The client handler runs `endRoundView()` (teardown, which restores controls, plus the table place) and drops the round. `teardown` is idempotent, so a `RoundEnd` after the seat's own Completed does nothing twice. Reusing `SeatRemoved` stays rejected; `src/server/engine/` untouched.

`round_end.spec`: source-scan gate with 7 in-memory mutants of the REAL text, no-defect twins, and real-source mutations. Verbatim: `RoundEnd named 0 times in CardService, expected 1`; `endRound does not publish toSeated("RoundEnd", {})`; `RoundEnd is published after table.clear(seated): it would reach nobody`; `RoundEnd is published before the avatar hold is released`; `RoundEnd is not registered in the handler table exactly once`; `endRoundView does not call teardown() (controls would stay hidden)`; `onRoundEnd does not call endRoundView() (controls would stay hidden)`. On disk: `table.clear(seated)` moved before the send turned 2 red; `onRoundEnd` calling `destroyUi()` instead turned 2 red. `privacy.spec` also asserts it is public and payload-free. Kinds are now seven; routing/netguard counts updated (6 -> 7, attempts 14, 21).

**Caveat:** this is a scan of CardService, which cannot load in Lune. That the controls actually come back on a phone is **M-11**.

## Mutations on the shipped files (edited on disk, run, restored; tree clean after)

| # | Edit | Red output (verbatim) |
|---|------|------|
| M1 | `inst:IsA("ClickDetector")` -> `false` | `clean path ... ClickDetector: expected ClickDetector, got nil` |
| M2 | a second `task.delay(` | `exactly one task.delay (the Scheduler's) (expected 1, got 2)` |
| M3 | `part.CanQuery = false` dropped from CardSeatsView | `CardSeatsView ... CanQuery = false appears 0 times for 1 part sites` |
| M4 | audio guard `if assetId == ""` -> `if false` | `clean path ... no empty-string guard found` |
| M5 | callout `plain` sets `Active = true` | `plain sets Active = false (expected 1, got 0)` |
| M6 | a text object in CardSeatsView | `CardSeatsView names no TextLabel (expected 0, got 1)` |
| M7 | flourish `DisplayOrder` literal `50` | `the flourish ScreenGui's DisplayOrder is Card.FLOURISH_DISPLAY_ORDER (expected a truthy value, got false)` |
| M8 | `Depths = onDepths` removed | `Depths is dispatched (expected a truthy value, got false)` |

Each: 185 passed / 1 failed; restored 186 passed. In-memory: the five single-kind scan mutants plus the "Interactable on every GuiObject" mutant are all red; the audio negative control prints `guard offset 44 after constructor offset 11`; real offsets `guard 595, constructor 642`. Part-site gate: two sites with one property each reports shortfalls, a re-enable is reported, dropping any of the four properties from either file is red, and **the shape shipped is one creation helper per file** (`sites == 1` in both CardSeatsView and CardFlourish, counts exact).

## Defaults vs the cut-off

`Flourish.totalOf`: Completion **1.2 s**, Deal **0.6 s** against a **1.5 s** cut-off (margin 0.3 s and 0.9 s; the gate requires 0.2 s). The implementation reads each step's seconds from `Flourish.DEFAULTS` by name and adds no step. **Timer trio asserted by count:** exactly one each of `task.delay(`, `task.cancel(`, `task.spawn(`, and `FLOURISH_DURATION_SECONDS` read once, where the driver is constructed. The delay wrapper does not cancel a timer from inside its own callback (that would abort the driver's own teardown).

## Dispositions

- **F5 (callout coverage):** accepted and recorded in the CardCallout header; 68 design px, about 24% of TableRegion at 640x360 and 33% at 844x390, under the ~40% ceiling.
- **F8:** dedicated ScreenGui at `FLOURISH_DISPLAY_ORDER` (5) below the hand's (10), asserted on config and on the live objects at runtime; scan plus `destroyOffenders` as above.
- **D-18:** the forced-pass cue stays private (`Notice` toPlayer only); the table sees an ordinary pass (unchanged, covered by privacy case 3).
- **D-20:** the stall cue reads `{ active }` only; `STALL_CUE_SECONDS` stays client-side (unchanged from 04-18).

## Deviations from Plan

**1. [Rule 3 - blocking] `CardTableView.luau` renamed `CardSeatsView.luau`.** `scripts/ci/zones.luau` `guardedNamePrefixes` contains `"CardTable"` and check-guards matches by prefix, so the planned name made the renderer a FOUND-05 guarded root and R3-failed its `require(ReplicatedStorage...)`. A client renderer must not be one (Phase 7 plugs deck-skin data in here). The exported type is still `TableView`. Later plans and 04-20's table that name the planned filename need updating.

**2. [Rule 1 - plan wording would break the scan] `Interactable` is tested on `GuiButton` only.** The plan says to flag every GuiObject with `Interactable` true. It defaults to true on every GuiObject, so that rule flags every plain Frame and destroys the default flourishes' own cards on the first scan (mutation "Interactable on every GuiObject" is red against the plain-Frame probe). Whether a plain Frame with `Interactable = true, Active = false` sinks input is an unverified Roblox behaviour (docs hosts blocked): **M-17**.

**3. [Rule 2 - missing wire] Two public kinds, `Depths` and `RoundEnd`** (the brief asked for the sixth for round end and for server-supplied depths; both are separate public kinds, so there are seven).

**4. [Rule 3] `CardHud` gained `newGui`, `mount`, `newOverlay`.** The callout must outlive the hand (D-30 destroys the hand's ScreenGui at completion, so a callout parented to the hand's `tableRegion` could never show the self callout). `newGui` also keeps the `ScreenInsets` assignment in a single site for both new ScreenGuis (UX-03). The flourish ScreenGui and the callout overlay use it.

**5. [Rule 3] Snapshot watches dedicated containers only.** `workspaceRoot` passed to the Surface is a Folder `SpoonsFlourish` that CardClient creates, never Workspace itself: `destroyEscaped` would delete a respawning character. Live roots are excluded from the diff so a second flight's root is not mistaken for an escape from the first.

**6. [Rule 2] `defaults` and `makeDriver` take a `Stage`** (seat position, table centre, deal geometry from the solution) because the plan's `defaults()` had no way to place anything. Added to `Config.Card`: `TABLE_CARD_STUDS`, `SEAT_STACK_OFFSET_STUDS`, `HOP_PEAK_STUDS`, `FLOURISH_FAN_SPACING_STUDS`, `AUDIO.OWN_CAP_SECONDS` so no stud or time literal sits in a client file. CardClient's own `playSound` was removed in favour of `CardAudio`; the sting now plays for every seat's Completed (the plan: same for everyone), where 04-18 played it for the local seat only.

**7. [Gate harness defect caught by running it]** The first client "does not tear down" mutant keyed on `teardown()\n round = nil`, which `onRoundStart` also opens with, so the mutant landed in the wrong function. Rekeyed on the handler's own header; the twin now asserts the edited text is the one intended.

## Known gaps (recorded, not fixed)

- **Stack heights and positions are starting values.** Seat anchor + 3 studs along `look` at the anchor's y; the real table height is unknown (the map's Seats pose is the avatar's, not the table's). M-12.
- Hops start/end at the current stack tops; no cap on `Hop` parts beyond the pool. An over-cap hop is dropped silently by design.
- The self callout and the other callouts are removed at `RoundEnd`/next `RoundStart` even if mid-fade.
- A repeated own draw/pass within 120 ms: the first sound's delayed `Stop` can cut the second. Cosmetic, M-16.
- Flourish `Completion` renders a face with a `TextLabel` in a `SurfaceGui` on a Part (public ranks only; the copy index only picks the pip, so the suit shown can differ from the real copy). Legibility is M-14/M-17.
- Case 13 of the discipline spec scans `CardClient` text only; the `pcall` around table-place construction (a failure there warns and leaves the hand working) has no executed test.
- Weak check: the on-disk `Depths` source mutation to `rank = 1` was caught by four tests, but the per-seat count truth check only sees the final message.

## What is NOT proven

M-11 (controls return after `RoundEnd` on a phone; movement after a flourish), M-12 (stack height step, hop arc, callout fit, thumb reach), M-14 (face legibility on a 3D part), M-16 (all audio ids empty; sting/draw/pass exist), M-17 (a live three-player round: the starting gun reads as one, the deal reads as arriving, `Interactable` semantics, a real mid-flight input sink being destroyed). CARD-17's feel half is explicitly open.

## Self-Check: PASSED

Files present: the four client files, both specs, this summary. Commits present: cc26501, c7de26d, 2017abc, e1a94a4, 405ef90.
