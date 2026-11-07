---
phase: 04-live-card-table
plan: 17
subsystem: client-ui
tags: [roblox, luau, ui, hit-model, cards]
requires: [04-04, 04-08, 04-09, 04-16]
provides: [CardFace, CardHand, CardPiles, renderer discipline cases 7-11]
affects: [04-18, 04-19]
key-files:
  created:
    - src/client/ui/CardFace.luau
    - src/client/ui/CardHand.luau
    - src/client/ui/CardPiles.luau
  modified:
    - tests/card/renderer_discipline.spec.luau
metrics:
  completed: 2026-11-07
  tasks: 3
  commits: 239f97c, 3465e1f, 0a4846d
---

# Phase 4 Plan 17: CardFace, CardHand, CardPiles Summary

One card instance built once with six visual states and a table-driven joker band, a fan whose five hit strips and backdrop are created once and snap at commit, and two Active no-op-sink pile panels with a single shared pulse connection, gated by five new discipline cases (172 string literals examined, every mutation red).

## Verification (measured)

- `lune run tests/run.luau`: **837 passed, 0 failed, 0 todo in 24.74s**
- `lune run tests/run.luau -- --root tests/card`: **165 passed, 0 failed** (was 160), 0.39 / 0.41 / 0.41 s
- `lune run scripts/verify.luau`: **exit 0**, all 14 steps (typecheck roblox + standard, guards, tests, build, built-place)
- `stylua --check src scripts tests`, `selene` (0/0/0), `check-guards` ok, `grep rankOf src/shared src/client` empty
- **Per-spec cost:** same tree with the old spec 0.38 / 0.38 / 0.40 s, with the new spec 0.39 / 0.41 / 0.41 s. **About +0.01 to +0.03 s**, text scans only, well inside the 0.80 s remaining. No sample size, mutation, non-vacuity assertion or control was cut.

## Shipped type text (04-18 and 04-19 build against these)

```luau
-- CardFace.luau
export type Visual = "Idle" | "Selected" | "Arriving" | "InFlight" | "Returning" | "ForcedOut"
export type CardFace = {
	setFace: (self: CardFace, rank: number?, copy: number?, mode: string?) -> (),  -- nil, nil = back; rank 0 = joker, needs mode
	setVisual: (self: CardFace, visual: Visual) -> (),
	moveToSlot: (self: CardFace, slot: Layout.Slot, animate: boolean) -> (),
	flyTo: (self: CardFace, target: Vector2, visual: Visual, onDone: (() -> ())?) -> (),  -- target = card CENTRE, HandZone design units
	flip: (self: CardFace) -> (),   -- call flip() THEN setFace(): the side changes at the midpoint
	instance: (self: CardFace) -> Frame,
	destroy: (self: CardFace) -> (),
	setSolution: (self: CardFace, solution: Layout.Solution) -> (),
	placeAt: (self: CardFace, centre: Vector2, shrunk: boolean) -> (),
	setVisible: (self: CardFace, visible: boolean) -> (),
}
CardFace.new(parent: Frame, solution: Layout.Solution) -> CardFace
CardFace.centreOf(rect, solution) -> Vector2 ; CardFace.zoneRect(rect, solution) -> (UDim2, UDim2)
CardFace.PILE_ART_Y = 0.55 ; CardFace.pileArtCentre(panelRect, solution) -> Vector2

-- CardHand.luau
export type Hand = {
	apply: (self: Hand, display: Prediction.Display, changes: { Prediction.Change }, selectedCardId: number?) -> (),
	relayout: (self: Hand, solution: Layout.Solution) -> (),
	setInputKind: (self: Hand, kind: Hints.InputKind) -> (),
	setJokerMode: (self: Hand, mode: string?) -> (),
	destroy: (self: Hand) -> (),
}
CardHand.new(parent: Frame, solution: Layout.Solution, callbacks: { tapSlot: (cardId: number?) -> (), tapOff: () -> () }) -> Hand

-- CardPiles.luau
export type Piles = {
	setLeft: (self: Piles, count: number, state: "Drawable" | "Locked" | "Empty") -> (),
	setRight: (self: Piles, count: number) -> (),
	leftCentre: (self: Piles) -> Vector2,
	rightCentre: (self: Piles) -> Vector2,
	relayout: (self: Piles, solution: Layout.Solution) -> (),
	destroy: (self: Piles) -> (),
}
CardPiles.new(parent: Frame, solution: Layout.Solution, callbacks: { tapLeft: () -> (), tapRight: () -> () }) -> Piles
```

**Wiring contract for 04-18:**
- Pass `Hud:handZone()` as the parent of all three.
- Call `hand:relayout(solution)` with `Layout.solve(..., newHandSize)` **before** the `apply` that changes the hand size. `apply` never throws on a mismatch (D-12): it clamps to the last slot, which would visibly overlap.
- Call `hand:setJokerMode(mode)` from the round-start payload before the first `apply` that can contain a joker. Faces then errors by name if it was forgotten, deliberately.
- Both `tapSlot` and `tapLeft` are forwarded **unconditionally**, and the reducer decides. `tapSlot` passes `nil` for a placeholder.
- A commit's `Removed{cardId}` and a draw's `Added{}` are 04-18's to pass as the change list: `Prediction.tapSlot` and `tapLeftPile` return only an `Emit`, not changes.

## Accepted residuals, implemented as written

- **F7:** hit strips snap to the final layout at the instant of `relayout` while card visuals tween 0.12 s, so they disagree by up to 30 px for that window. No delay is added (D-02).
- **Lifted-card overhang:** a lifted card is drawn 72 wide but hit-tested 60, so a tap on its visible 12 px overhang selects the right neighbour. Widening it would drop that neighbour to 40.8 physical px.
- Recorded and unchanged: a fumbled fast double-tap on one card sends it, deliberately (D-02/D-03). There is no debounce anywhere.

## Design decisions worth knowing

- **Cards are never Active.** The strips are the only hit surface, in `Slot{i}` TextButtons at ZIndex 50, so z-order and the lift cannot move a hit. Gate case 11 asserts `Active = true` is absent from CardFace.
- **Backdrop is parented to the Hud's Root (`parent.Parent`), not to HandZone**, at ZIndex 0, because the UI-SPEC says "HandZone + TableRegion". Consequence: while the card HUD exists it also sinks touches over the table region, including camera drags there. That is as specified; the feel is **M-12/M-13**.
- **Matching is by cardId, not by diff.** The Display decides what exists; the Change list only picks how a card moves (Returned -> fly from the right pile, Flipped -> the placeholder turns over, Removed -> leave). A stale change is never looked up, and a second identical `apply` moves nothing.
- **Own send vs forced removal.** `Removed{cardId}` cannot say which. The hand records that *this player* tapped the selected card at hand 5 and uses `InFlight` for it, otherwise `ForcedOut` (neutral ring). Worst case if that guess is wrong is a ring colour.
- **The forced-pass pair (owed by 04-09/04-16).** When a `Removed` with an id and a `Returned` arrive in one batch, the returning card is already at its slot for hit-testing but is held invisible for `TWEEN.SEND` and then flies back. Reads as "that one left, then yours came back", not two crossing cards. **Not executed or watched anywhere; M-13/M-17.**
- **`Removed` with no id** is a face-down placeholder: it flies back to the left pile with `Returning`.
- **Pulse time** accumulates `RenderStepped`'s `dt` rather than reading `os.clock()`, because `tests/card/deci_lock` (correctly) allows `os.clock` in three server files only. That gate went red on my first draft.

## Deviations from Plan

**1. [Rule 3 - extras on the contract]** `CardFace` gained `setSolution`, `placeAt(centre, shrunk)`, `setVisible` and an optional `mode` on `setFace`; `Hand` gained `setJokerMode`; `CardFace` exports `centreOf`, `zoneRect`, `PILE_ART_Y`, `pileArtCentre`. Without them a viewport change, the origin of a flight, a held return and the live joker flag were inexpressible. The planned signatures are otherwise unchanged.

**2. [Plan wording, no behaviour change]** Task 3 case 3 says "no `Instance.new` appears inside a function whose name contains `relayout` or `apply`". My first body-finder regex captured the last letter of the name (`y`), found **zero** bodies, and the non-vacuity assertion `found N layout-path functions` failed it. Fixed; it now prints `apply(107), relayout(15)`.

**3. [Spec vs shipped token]** The joker corner star uses `TEXT_SIZE.BODY` (20), not the UI-SPEC's 24: `CardTheme` has no 24, and adding one would collide with `DESIGN.STRIP_TEXT_H`/`MIN_FAN_PILE_GAP` under case 1. A visual check (M-14 family).

**4. [Acceptance wording]** Task 2's `grep -c 'Active = true' CardPiles` needs at least 2 lines; the shared `buildPanel` produced one. Each panel now has an explicit `left.button.Active = true` / `right.button.Active = true`, which is also what the gate counts. Likewise `grep -iq 'error|invalid|rejected' CardHand` would match the header prose "no error path"; the real gate scans string literals and `error(`/`assert(`/`pcall(` calls instead.

**5. [Plan numbering]** The plan's four new cases became five (rank/suit/band literals, joker mode, hit-strip construction, Connect/Disconnect balance, plus an input-surface case for the sinks and D-12). The existing four `>= 2` file-count assertions are now `>= 5`.

## Gate output (printed needle lists and counts)

```
renderer_discipline[7]: 6 files, literals 172 (CardPiles=39, CardFace=65, CardHand=20, CardTheme=7, CardStrip=15, CardHud=26)
renderer_discipline[7]: glyph needles A,K,Q,J,10,7,4,2,5,3,9,8; word needles spade,heart,club,diamond,WILD,BLOCK
renderer_discipline[8]: 6 files, modes Wild,Blocker, 0 hits
renderer_discipline[9]: CardHand TextButton constructors 2 (limit 6); layout-path bodies apply(107),relayout(15)
renderer_discipline[10]: Connect/Disconnect per file CardPiles=1/1, CardFace=0/0, CardHand=1/1, CardTheme=0/0, CardStrip=0/0, CardHud=2/2
renderer_discipline[11]: CardHand Active = true x1, CardPiles sinks x2, CardFace Active = true x0
renderer_discipline[1]: 6 files, 22 needles: 0.58,0.85,1.5,8,12,16,24,28,32,48,52,60,68,72,84,92,96,108,144,300,350,760
```

Each case has negative controls (a comment and the word `Active` are not hits), a **no-defect twin** (an identity edit run through the same mutation function is clean, so a red mutant is not the harness), and in-memory real-source mutants.

## Mutations on the shipped files (edited on disk, suite run, restored)

Every one is exactly 1 failed of 165, and all restored to 165 passed:

| # | Edit | Red output |
|---|------|-----------|
| M1 | `bandText.Text = "WILD"` | `face literal in CardFace.luau ... face word "WILD" in literal "WILD"` |
| M2 | `corner1.rank.Text = "Q"` | `... rank glyph literal "Q"` |
| M3 | `if mode == "Blocker"` in CardFace | `joker mode Blocker named 1 times` |
| M4 | `Instance.new("TextButton")` inside `apply` | `constructor in a layout path: apply: ... Instance.new("TextButton")` |
| M5 | `c:Disconnect()` -> `c:Destroy()` in CardPiles | `CardPiles.luau: 1 Connect against 0 Disconnect` |
| M6 | right panel `.Active = true` removed | red via the **non-vacuity** assertion (sinks must be at least 2) |
| M7 | `frame.Active = true` in CardFace | `a card is Active (hit-testing belongs to the strips)` |
| M8 | `AutoButtonColor = true` | `CardHand lacks: AutoButtonColor = false` |
| M9 | a `"Invalid move"` literal in CardHand | `user-facing error wording in CardHand: "Invalid move"` |
| M10 | `Z_SELECTED = 16` (the LIFT value) | `geometry literal in CardFace.luau ... got "16"` |
| M11 | `TweenInfo.new(0.12, ...)` | `timing literal in CardFace.luau ... got "0.12"` |
| M12 | a `RenderStepped:Connect` with no Disconnect in CardHand | `CardHand.luau: 2 Connect against 1 Disconnect` |
| M13 | `local _r = rankOf` | `forbidden identifier in CardFace.luau (expected 0, got 1)` |

**Honest note on M6:** it is caught first by the `non-vacuity` assertion, whose condition combines the Active-sink count with another, rather than by the dedicated `CardPiles has N Active sinks` problem. Red either way, but the message is a poor one. The dedicated predicate is exercised by the in-spec mutants (`right sink lost`, `left sink lost`), which pass.

## What is NOT proven (M-rows that carry this plan's unverifiable claims)

None of CardFace, CardHand or CardPiles can load in Lune; they are typechecked (`verify.luau` roblox platform) and text-scanned only. **UX-01 and CARD-19's legibility are NOT closed.**

- **M-12:** target size on glass, thumb reach, the 12 px overhang and F7 in the hand, whether the backdrop over the table region interferes with camera drag, whether the safe-area insets double-count.
- **M-13:** that a tap feels immediate, that a single tap never sends on glass, that the 0.25 s Back return reads as a return rather than a teleport at 150-300 ms, and that the forced-pass pair (held return) reads coherently.
- **M-14:** greyscale on all 50 faces, spade versus club at 16 px, the dashed empty slot (a gradient on a UIStroke, which dashes the long edges only), and the 20 vs 24 joker star.
- **M-16:** Builder Sans, the four glyph codepoints in that font, and the sprite sheet (empty id draws a visible placeholder box).
- **M-17:** the three-player starting-gun playtest.

Review-only, no executed test: `task.delay` in the held return is guarded by `alive`/`destroyed` rather than cancelled; `Tween.Completed:Once` handlers on a destroyed instance are assumed to be dropped; the dashed-gradient `NumberSequence` keypoint ordering was built to be strictly increasing but never run.

## Known Stubs

None that block the goal. The sprite pip path draws a deliberate visible placeholder box until the M-16 asset exists, and `PIP_SOURCE` is `"glyph"` today so it is not reached.

## Self-Check: PASSED

- Files present: `src/client/ui/CardFace.luau`, `CardHand.luau`, `CardPiles.luau`, `tests/card/renderer_discipline.spec.luau`
- Commits present: 239f97c, 3465e1f, 0a4846d
