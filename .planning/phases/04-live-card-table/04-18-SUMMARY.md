---
phase: 04-live-card-table
plan: 18
subsystem: client-assembly
tags: [roblox, luau, client, input, controls, wiring]
requires: [04-09, 04-11, 04-13, 04-16, 04-17]
provides: [CardControls, CardInput, CardClient, Main.client boot, renderer discipline cases 12-15]
affects: [04-19, 04-20]
key-files:
  created:
    - src/client/ui/CardControls.luau
    - src/client/ui/CardInput.luau
    - src/client/ui/CardClient.luau
  modified:
    - src/client/Main.client.luau
    - src/client/ui/CardHand.luau
    - src/client/ui/CardStrip.luau
    - tests/card/renderer_discipline.spec.luau
    - tests/card/deci_lock.spec.luau
metrics:
  completed: 2026-11-07
  tasks: 3
  commits: ca9d9d8, 9beb719, e43507b
---

# Phase 4 Plan 18: CardControls, CardInput, CardClient Summary

The Roblox backend behind the pure control seam (touch-controls toggle plus a High-priority CAS key sink), a LastInputTypeChanged-driven input layer with keyboard and gamepad accelerators, and the one wiring file that routes every `onCard` message through a fresh per-round reducer into the renderer; gated by four new discipline cases (169 specs in tests/card, every mutation red).

**UX-01, UX-02, UX-03 and UX-04 are NOT closed by this plan.** None of CardControls, CardInput or CardClient can load in Lune; they are typechecked (`verify.luau`, roblox platform) and text-scanned only. Control hide/restore and respawn is **M-11**; glass, thumb reach and insets is **M-12**; feel at 150-300 ms is **M-13**; audio ids are **M-16**.

## Verification (measured)

- `lune run tests/run.luau`: **841 passed, 0 failed, 0 todo in 25.41s**
- `lune run tests/run.luau -- --root tests/card`: **169 passed, 0 failed** (was 165), **0.43 / 0.45 / 0.46 s** on the clean tree (three readings)
- `lune run scripts/verify.luau`: **exit 0, all 14 steps** (typecheck roblox + standard, structural guards, tests, build, built-place)
- `stylua --check src scripts tests`, `selene src scripts tests` 0/0/0, `check-guards` ok (139 files)
- **Per-spec cost:** 04-17 measured 0.39-0.41 s for 165 specs; now 0.43-0.46 s for 169 with three more scanned files and four new cases, i.e. about **+0.03 to +0.05 s**. Text scans only. Well inside the ~0.80 s remaining; no sample size, mutation, non-vacuity assertion or control was cut.
- **Forbidden-identifier scan:** `grep -rn 'GetControls\|PlayerModule\|ControlModule\|ModalEnabled' src` prints nothing (comments included). `grep -rn rankOf src/shared src/client` prints nothing. `FireServer` appears only in `ClientNet.luau`. No "enforced" or "prevents" anywhere in the three new files; the control-hiding header says "ergonomics, not a security layer" and "meant to".

## Shipped contracts (M-11's matrix needs these)

**Effects construction** (`CardControls.makeEffects(onDestroyOverlay, onStartFlourish)`, and `CardControls.new(...)` = `Controls.new(makeEffects(...))`):

| Effect | Implementation |
|---|---|
| `setTouchControls(enabled)` | `GuiService.TouchControlsEnabled = enabled` |
| `bindSink()` | `ContextActionService:BindActionAtPriority("SpoonsSinkMove", handler, false, Enum.ContextActionPriority.High.Value, Space, W, A, S, D, Up, Down, Left, Right)`; handler returns `Enum.ContextActionResult.Sink` |
| `unbindSink()` | `ContextActionService:UnbindAction("SpoonsSinkMove")` |
| `destroyOverlay`, `startFlourish` | the two callbacks, passed through |

`SINK_ACTION`, `SINK_PRIORITY`, `SINK_KEYS` are exported so the input layer and the matrix read one source.

**CAS actions in CardInput**, all at `SINK_PRIORITY + 1` (above the sink), `createTouchButton = false`, one bind site and one unbind site (a loop over a `bindings` list):

| Action | Keys | Handler |
|---|---|---|
| `SpoonsSlot` | One..Five and KeypadOne..KeypadFive | `selectSlot(1..5)`; Sink for mapped keys, Pass otherwise |
| `SpoonsCommit` | Space, Return, KeypadEnter, ButtonA | `commit()`; Sink |
| `SpoonsStep` | ButtonL1 (-1), ButtonR1 (+1), DPadLeft (-1), DPadRight (+1) | `moveSelection(delta)`; Sink for mapped, Pass otherwise |

Only `Begin` acts; both phases are sunk for a handled key so the release does not leak. **Both gamepad tables (`GAMEPAD_STEPS`, `GAMEPAD_COMMIT`) are data.** D-09: `LastInputTypeChanged` mapped through `Hints.kindOf`; nil leaves the set alone; `PreferredInput` appears in a comment only. The seed is `GetLastInputType()`, falling back to Touch when touch is enabled and a keyboard is not, else Mouse.

**CardClient** exports `start`, `destroy`, `setHooks`, `hud`. `Hooks = { onRoundStart(payload, localSeat), onTable(events, depths, localSeat), startFlourish(completedEvent) }` is what plan 04-19 plugs into. `Main.client` calls `ClientNet.resolve()`, then `CardClient.new():start()`, then the unchanged `Ping`.

## Wiring contract compliance

1. All of Hand, Piles, Strip parent to `hud:handZone()`.
2. `refresh` calls `hud:resolve(size)` then `relayoutAll` BEFORE `hand:apply` whenever the display hand size changes to 4 or 5.
3. `hand:setJokerMode(jokerMode)` runs at build, before the first `refresh`.
4. A commit supplies `Removed{cardId}`; a draw supplies `Added{}`.
5. A fresh `Prediction.new` per `RoundStart`.
6. `STALL_CUE_SECONDS` read from `Config.Card` for the stall message.
7. `start` calls `ClientNet.resolve()` itself (idempotent) as well as Main, before `onCard`.

04-17's distinction is intact: the hand records its own strip tap; the keyboard and gamepad route through the new `Hand:markSent` so their sends are not rendered as forced removals.

## Deviations from Plan

**1. [Rule 3 - plan contradiction] Task 3 case 4 versus Main.client's Ping.** The plan says `ClientNet.send` is called in exactly one file under `src/client` while also saying to keep Main's `Ping`. Both cannot hold. The gate asserts the call-site set is exactly `{Main.client.luau, ui/CardClient.luau}`, that Main's only literal intent is `Ping`, that `CardClient` has exactly one send site, and that no other file names `Pass` or `Draw` as a literal intent. Intent (one *card* send path) is preserved.

**2. [Rule 3 - plan contradiction] `GetServerTimeNow` in the client versus `deci_lock`.** The plan wires the countdown to `Workspace:GetServerTimeNow()`, but `deci_lock.spec` allowed that identifier in two server files only. The allowlist now names `src/client/ui/CardClient.luau` as the third file, with a comment; it remains an exact `deepEqual`, so a second client reader (mutation below) fails. `os.clock` stays server-only; the display clock accumulates `RenderStepped`'s `dt`.

**3. [Rule 2 - contract extras]** `CardHand.markSent(cardId)` (keyboard and gamepad sends otherwise render as `ForcedOut`, a neutral ring on desktop where the keyboard is the main accelerator) and `CardStrip.clearMessage()` (the plan says to clear the stall cue and revert the joker explainer, and the strip had no way to).

**4. [Rule 3 - plan wording]** Case 1 compares `ClientNet.resolve(` against `CardClient.new(` rather than the bare name `CardClient`, since the `require` line necessarily precedes the call and would make the planned needle fail on a correct boot. Case 3's balance needed `CardInput` to have one bind site (a loop), because three separate bind calls would exceed its single unbind loop.

**5. [Type traps hit, `verify.luau` only]** Five, all passing `tests/run.luau` first: the roblox-platform solver widened `Hints.kindOf`'s result to `string` (rebuilt through literal comparisons in `CardInput.kindFromName`); tuple/if-expression returns of literal unions widened (split into two functions with direct returns); `xpcall` of a void function returns one value (the handler captures the traceback instead); stylua joined `table.insert(...)` and a following `(r.ui :: Ui)...` statement into a call (replaced with a local); `Hints.HINT.RightPileSink` was not found as a key (index through a typed `Hints.State` local).

## Known gaps (recorded, not fixed)

- **No depth data reaches the client.** The `Table` payload is the public event list only; `Prediction.onTable` wants a depth list. CardClient passes the reducer its own current (empty) list rather than inventing numbers. **Plan 04-19's per-seat stacks need a server-supplied depth field**, a wire change that is not this plan's to make. This is the largest open item for 04-19.
- **No round-end message exists** among the five kinds. The overlay ends on the local seat's `Completed` or `SeatRemoved`, or on the next `RoundStart`. If the server ends a round without removing the local seat, the overlay and the hidden controls persist until the next round. Worth confirming against `CardService.endRound` in M-17.
- **`CardHud.new` calls `WaitForChild` and may `:Wait()` for a camera** inside the `RoundStart` handler path. Both return immediately when the object exists, which is the normal case, but that is not asserted. The yield gate scopes `CardClient.luau` only, as planned.
- **Audio:** a Sound whose id fails to load never fires `Ended` and is never destroyed. Ids are empty by contract until M-16, so nothing is created now.
- **Recorded, not implemented:** (1) next-frame false-then-true retoggle of `TouchControlsEnabled`, only if M-11's stuck-touch case reproduces; (2) gamepad degrading to the Mouse hint set, a one-line data change in `Hints.KIND_OF` and in the two `GAMEPAD_*` tables.
- Unchanged from 04-17: a fumbled fast double-tap sends, deliberately (D-02/D-03); no debounce anywhere.

## Gate output (printed counts)

```
renderer_discipline[12]: Main.client offsets: ClientNet.resolve( = 103, CardClient.new( = 139
renderer_discipline[13]: CardClient stripped 13702 chars, yield needles task.wait,WaitForChild,:Wait(, hits 0
renderer_discipline[14]: CardControls bind/unbind 1/1, CardInput bind/unbind 1/1
renderer_discipline[15]: scanned 11 client files (CardClient,CardControls,CardFace,CardHand,CardHud,CardInput,CardPiles,CardStrip,CardTheme,ClientNet,Main.client)
renderer_discipline[15]: ClientNet.send( hit list: CardClient.luau=1,Main.client.luau=1
renderer_discipline[1]: 9 files (was 6) ; [10]: Connect/Disconnect CardClient=1/1, CardInput=1/1
```

Each new case has a clean control, a non-vacuity assertion, negative controls (a comment does not count), a no-defect twin on the real file (identity edit is clean), and in-memory real-source mutants.

## Mutations on the shipped files (edited on disk, run, restored; tree clean afterwards)

| # | Edit | Red output (verbatim) |
|---|------|------|
| M1 | `Main.client`: `ClientNet.resolve()` replaced | `FAIL ...::ClientNet.resolve is called before any CardClient construction in Main.client` / `non-vacuity: both needles were found in the shipped Main.client (expected a truthy value, got false)` |
| M2 | `task.wait(1)` in CardClient | `CardClient yields nowhere (expected {  }, got { [1] = "task.wait" })` |
| M3 | `UnbindAction` -> `Unbound` in CardInput | `CardInput: 1 bind against 0 unbind (expected a truthy value, got false)` |
| M4 | a second `ClientNet.send` line in CardClient | `exactly one card send path, and it is CardClient (expected {  }, got { [1] = "CardClient has 2 send sites, expected exactly 1" })` |
| M5 | `ClientNet.send("Pass", ...)` in CardHand | `ClientNet.send( is called from src/client/Main.client.luau,src/client/ui/CardClient.luau,src/client/ui/CardHand.luau, expected ...` and `src/client/ui/CardHand.luau names the intent Pass as a literal` |
| M6 | `os.clock()` and literal `48` in CardClient | `deci_lock: os.clock files (expected {3 server files}, got {4 incl. src/client/ui/CardClient.luau})` and `geometry literal in src/client/ui/CardClient.luau (expected {  }, got { [1] = "48" })` |
| M7 | `jokerMode == "Wild"` and `Color3.new` in CardClient | `joker mode Wild named 1 times` and `the only file with a colour or font constructor is CardTheme (... got { CardTheme.luau, CardClient.luau })` |
| M8 | a `GetControls` comment and `GetServerTimeNow` in CardInput | `src/client/ui/CardInput.luau names GetControls`; `forbidden identifier in src/client/ui/CardInput.luau (expected 0, got 1)`; `GetServerTimeNow files (... got { CardClient, CardInput, CardService, RoundDriver })` |

Counts: M1-M5 each 168 passed / 1 failed; M6, M7 167 / 2; M8 166 / 3. All restored to 169 passed.

**Honest notes on these gates.** (a) M1 is caught first by the *non-vacuity* assertion, because removing `resolve` makes a needle absent; the ordering predicate is separately exercised by the in-spec "moved after" and "comment only" mutants. (b) Case 13 scans `CardClient` text only, so a yield inside a module it calls is not seen. (c) No gate can reach the claim "hints switch live" or "Space does not jump": those are Roblox behaviours (M-11).

## What is NOT proven (M-rows)

- **M-11** (highest risk): `TouchControlsEnabled` and the CAS sink on PC, phone and gamepad under both input-system settings; held-key and down-thumb recovery on re-enable; the finisher controllable within one second; respawn mid-round; the gamepad column (V-27, device behaviour unverified).
- **M-12:** glass, thumb reach, insets, the strip at the largest text size. **M-13:** a tap feels immediate and a return reads as a return at 150-300 ms. **M-16:** audio ids (all empty, silent by contract). **M-17:** a live three-player round, including the round-end gap above.

No Studio and no phone were available. UX-02 remains human-gated under M-11. Requirements were not touched; `requirements.mark-complete` was not run. STATE.md and ROADMAP.md were not touched.

## Self-Check: PASSED

Files present: CardControls.luau, CardInput.luau, CardClient.luau, Main.client.luau, this summary. Commits present: ca9d9d8, 9beb719, e43507b.
