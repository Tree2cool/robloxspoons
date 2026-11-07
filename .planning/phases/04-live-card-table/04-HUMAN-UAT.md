---
status: partial
phase: 04-live-card-table
source: [04-VERIFICATION.md, MANUAL-CHECKS.md]
started: 2026-11-07
updated: 2026-11-07
---

# Phase 4 — human UAT

**Phase 4 does not close until items 1-7 are signed.** Four of the five ROADMAP success criteria are
device-dependent; the build container has no Studio and no phone, so no machine run can close them.
Full procedures live in `MANUAL-CHECKS.md` (M-11..M-17) — this is the working checklist in the order
that wastes least time.

**Machine state behind this**: 871 tests pass / 0 failed / 0 todo, `verify.luau` 14/14,
`check-guards: ok (146 files, 440 requires, 36 guarded roots)`, `src/server/engine/` and
`Gateway.luau` at zero diff against the pre-phase commit, suite cost +0.99 s of a +3.00 s allowance.

## Current Test

[awaiting human testing — start at item 1]

## Tests

### 1. M-15 — landscape lock and the IAS flag  *(do first: gates 4 and 5)*
expected: landscape locked in the Creator Dashboard, and
`Workspace.PlayerScriptsUseInputActionSystem` **pinned explicitly** rather than left `Default`
(the default flips the player scripts under the project in early 2027).
result: [pending]

### 2. M-16 — owner assets  *(non-blocking, but do it before 3 and 7)*
expected: audio ids and suit pips uploaded; a Builder Sans weight confirmed present. A missing
weight is a **blocker to raise, not a substitution** — `Enum.Font.Gotham*` was removed from the
platform and maps to Montserrat, which would silently change the typeface and invalidate every
glyph-width figure in the UI-SPEC. Empty audio ids are **silent by contract**, not broken.
result: [pending]

### 3. M-14 — greyscale, all 50 faces  *(desk work, no device needed)*
expected: every rank, copy and the joker stay distinguishable with saturation at -1. **Check spade
vs club at 16 px first — it is the hardest pair.** Also look at the joker corner star, which ships
at 20 rather than the UI-SPEC's 24 (CardTheme has no 24 and adding one collides with the geometry
scan).
result: [pending]

### 4. M-11 — control hide/restore  *(HIGHEST RISK — budget real time)*
expected: 6 cells (IAS Disabled/Enabled x PC/phone/gamepad) plus **4 separately recorded**
cheat-client attempts. **Ticking on cell (a) `TouchControlsEnabled` alone is forbidden** — it is a UI
toggle, not an exploit; the owning client simulates its own character, so (b) `WalkSpeed`,
(c) `Humanoid:Move` and (d) a `CFrame`/`PivotTo` write are the ones that matter.
`Dev*MovementMode = Scriptable` is documented to disable the default control scripts, which is
**not** the same as refusing a `Move` call. **Watch for stuck-touch and held-key bugs on re-enable.**
If it fails, three fallbacks are pre-recorded and ordered (D-04-10, D-04-11, D-04-12) — the third is
a **Phase 6 map-contract change, not a hot fix**. Do not improvise a fourth.
**Includes new step 7 (UX-04)**: on one multi-input device, confirm the hint wording follows the
**last input actually used** and switches without a reload.
result: [pending]

### 5. M-12 — real phone, landscape
expected: 48 px targets on glass; thumb reach; nothing under the notch or top bar; the status strip
at `PreferredTextSize = Largest`; other seats' depth stacks rendering; and **a second client seeing
only its own hand**. Two known items to look at: the lifted card's **12 px overhang is deliberately
not hit-tested** (tapping it selects the neighbour — accepted, because widening it drops the
neighbour below 48 px), and whether `readViewport` **double-counts insets** under
`CoreUISafeInsets` is an open question recorded in the `CardHud` header.
result: [pending]

### 6. M-13 — prediction feel at 150-300 ms
expected: the card is visibly gone **within a frame**; a correction reads as a **return**, not a
teleport; and a rejection is **indistinguishable** from a correction (D-12 — a legitimate player must
never be able to tell). This is also where **D-03's accepted residual** is observed: a fumbled fast
double-tap **will** send a card, deliberately.
result: [pending]

### 7. M-17 — three-client playtest
expected: the starting gun reads as one, and the finisher is **running before the flourish ends**.
Also the behavioural half of three code-review fixes that are **source-scanned only**, because
`CardService` cannot load headlessly:
  - **WR-03** — a failed `startRound` leaves a **retryable** service (not wedged).
  - **WR-04** — a gateway reject **returns the card immediately**, not after the 1.0 s watchdog.
  - **WR-05** — a removed seat still receives `RoundEnd`, `Depths` and later `Table` batches.
  - And the integration-found case no section owned: **after a round ends without removing your
    seat, do your movement controls come back?** On a phone a failure looks like having no movement
    controls at all.
result: [pending]

### 8. V-35 / M-07 — the 8.0 s AFK deadline on real people  *(not blocking Phase 4)*
expected: evidence on whether the bot reaction-time model resembles humans. This is the open half of
why 8.0 s was chosen, and it travels with owner decision **D-39** (80 deci kept; `79` remains the
one-line fix if the realised `(7.9, 8.1]` s window turns out to matter). Phase 6/8.
result: [pending]

## Open owner question — not a test

**WR-05 / D-31 callout scope.** The code-review fix keeps removed seats in the audience until
`endRound`, so a finisher still receives `RoundEnd`, `Depths` and later `Table` batches — and
therefore still sees later "X is out" callouts. The fixer read D-31 as covering **every seat dealt
into the round**. If you meant callouts only for seats still **in the card phase**, it is a one-line
revert. Nothing private is exposed either way: `Table`, `Depths` and `Stall` are all public kinds.

**Also still deferred:** IN-02 (a capped `task.delay` can cut a later sound short) and IN-04 (the
callout overlay loses its relayout once the HUD is destroyed at completion). Both need a behaviour
judgement rather than a mechanical fix.
