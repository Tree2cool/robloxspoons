# Deferred items — Phase 4

Everything here was deferred deliberately or recorded rather than fixed. Nothing in this file is an
oversight, and nothing in it should be "fixed" without reading the reason first: several entries are
locked decisions whose reversal would re-open a settled design question (T-4-165).

Format follows Phase 2's `deferred-items.md`. Ids are `D-04-NN`. Each entry has a **reason** and an
**owner** (the phase or step that picks it up). Sections:

- **A. Decided deferrals** from `04-CONTEXT.md` § Deferred Ideas (D-04-01 .. D-04-08).
- **B. Recorded fallbacks, deliberately not implemented** (D-04-09 .. D-04-12).
- **C. The AFK window — RESOLVED by owner decision D-39, 2026-11-07** (was D-04-13).
- **D. Accepted residuals and recorded gate weaknesses** (D-04-14 .. D-04-30), gathered from the
  plan 01-19 summaries and `04-EXEC-NOTES.md`.
- **E. Pre-launch carry-list** (D-04-31 .. D-04-33) — what Phase 4 deliberately left for Phase 8,
  indexed in one place because "before launch" scattered through plan prose is how a carry gets lost.

---

## A. Decided deferrals

### D-04-01 — Table-wide `ValveForcedPass` event
- **Reason:** rejected in favour of a private cue (D-18). A public event would tell the table which
  seat the valve touched, and the valve fires in roughly 1 round in 12 at a full roster, so it is not
  rare enough to be harmless.
- **Revisit when:** playtests show the receiving player is confused by cards arriving unprompted.
- **Owner:** Phase 8 (tuning on real sessions).

### D-04-02 — Drag-to-pile as a second pass gesture
- **Reason:** rejected (D-05) to keep one mechanic and one accident surface. A second gesture doubles
  the ways to mis-send.
- **Owner:** Phase 8 candidate, only if touch players ask for it.

### D-04-03 — Portrait support
- **Reason:** rejected (D-28). It is a whole second layout, not a variant of the first.
- **Revisit when:** telemetry shows portrait attempts are common. ~~Landscape lock itself is a
  Creator Dashboard setting and is human-only (M-15).~~ **Corrected 2026-11-08:** landscape lock is
  `StarterGui.ScreenOrientation`, an ordinary DataModel property, and Rojo 7.7.1 **can** set it via
  `$properties` (measured), so it is not human-only. The Dashboard's **Supported Devices** is a
  different setting and belongs to Phase 8 / UX-06 (D-04-33).
- **Owner:** Phase 8.

### D-04-04 — Ending a stalled round early
- **Reason:** out of this phase's boundary; round-end conditions belong to Phases 5 and 6. The D-20
  stall detector emits `stall_armed` / `stall_cleared` telemetry precisely so the decision can be made
  on data.
- **Owner:** Phase 8 (decides on the telemetry), with Phases 5/6 owning the mechanism.

### D-04-05 — Standings in the starting-gun callout
- **Reason:** out of boundary; placement and scoreboard presentation are Phases 5 and 6.
- **Owner:** Phases 5 and 6.

### D-04-06 — Tightening the auto-pass deadline below 8.0 s
- **Reason:** left at the ceiling (D-13) because **V-35 is open**: nobody has shown the simulator's
  reaction-time model represents humans. 8.0 s is the conservative end, **not a validated number**.
- **Owner:** Phase 6 or Phase 8, on real session data (M-17 supplies the first evidence). Any
  tightening hits the same two quantisation terms described in D-04-13.

### D-04-07 — Widening the fuzz `k` grid to cover the shipped `k = 3`
- **Status: NOT done in Phase 4, and no plan 01-19 owned it.** CONTEXT.md called it "cheap to do while
  Phase 4 is already touching the suite"; in the event nothing touched the engine fuzz. **No cost was
  measured.** Phase 2's 194,567-action conservation result remains not a claim about the shipped pool.
- **Reason it stayed deferred:** the suite is already the phase's budget concern (+1.24 s of 3.00 s)
  and the widened grid has no measurement behind it.
- **Owner:** Phase 8, or a Phase 2 follow-up. Measure the cost first; the controlled pre/post method
  in `04-BUDGET-LOG.md` is the one to use.

### D-04-08 — Extending the CI regression subset past N = 3/6/10
- **Reason:** every observed residual stall was at N >= 7 (worst cell N = 9), so the CI subset cannot
  see the regime the residual lives in. Not done in Phase 4.
- **Owner:** Phase 8.

## B. Recorded fallbacks, deliberately NOT implemented

These are written down so that nobody mistakes the absence for an oversight. Each is a response to a
specific M-row failure and **must not be built speculatively**.

### D-04-09 — Optional sort-the-hand-by-rank
- **Reason:** rejected now because a re-sort on draw moves slots under a thumb, which is precisely the
  mis-tap this phase's hit model exists to avoid.
- **Owner:** Phase 8 candidate.

### D-04-10 — The next-frame `TouchControlsEnabled` retoggle
- **Reason:** a **recorded fallback**, only for the community-reported stuck-touch bug on re-enable.
  Implementing it without a reproduction adds a frame-timing hack to a seam that may not need it.
- **Trigger:** M-11 reproduces stuck touch. **Owner:** whoever signs M-11.

### D-04-11 — The gamepad degrade-to-Mouse fallback
- **Reason:** V-27's device behaviour is open. If M-11's gamepad cell fails, the fallback is a
  one-line data change in two places (`Hints.KIND_OF` and the two `GAMEPAD_*` tables).
- **Trigger:** M-11 gamepad cell fails. **Owner:** whoever signs M-11.

### D-04-12 — `Humanoid.Sit` on converted seat Parts
- **Reason:** the recorded next attempt if the avatar-hold mechanism (A2: `Dev*MovementMode =
  Scriptable` + zeroed humanoid + `PivotTo`) fails M-11's cheat-client cell. It is a **map-contract
  change** (the seat anchors would have to become seat Parts), so it is **not a hot fix**.
- **Owner:** Phase 6 (map contract). Phase 6 also inherits the hold seam for the hider.

## C. The AFK window — an open owner decision

### D-04-13 — RESOLVED 2026-11-07 by owner decision D-39

**The owner kept 80 deci and restated CARD-16's bound as applying to the CONFIGURED value.** No code,
test or config change. `AUTO_PASS_DECI` remains 80, which *is* exactly 8.0 s as configured and is the
value every Gate G1 cell ran at. `REQUIREMENTS.md`'s CARD-16 entry carries the new wording. See
`04-CONTEXT.md` D-39 for the full reasoning and the measured window.

**What remains carried into Phase 8:** `79` deci is still the one-line fix if a real playtest ever
shows the realised `(7.9, 8.1]` s window matters, and it travels with **V-35 / M-07** — whether the
bot reaction-time model resembles humans — which is the open half of why 8.0 s was chosen at all.

*Original text, kept for the record:* The realised AFK window is (7.9, 8.1] s against CARD-16's "must not exceed 8.0 s"
- **Status: OPEN — awaiting the owner's choice** (keep-80 / set-79 / widen-the-requirement). The
  choice and its reason are to be recorded here when made. Nothing has been changed.
- **The arithmetic, derived rather than estimated.** `nowDeci = floor(10 * clock)`. An arming at real
  time `c` stores `floor(10c) + D`, so the deadline first becomes observable at elapsed
  `(D - frac(10c)) / 10`. **Flooring is ONE-SIDED-SHORT**: it can only shorten the window, never
  lengthen it. The 10 Hz sweep adds up to **+0.1 s** of lateness on top.

  | `D` | detection elapsed | + sweep (<= 0.1 s) | vs the locked 8.0 s |
  |-----|-------------------|--------------------|---------------------|
  | 80 (shipped) | [7.900, 8.000] | **8.100** | over by up to 0.1 s |
  | 79 | [7.800, 7.900] | **8.000** | not over |

  Re-run in plan 04-20 as a Monte-Carlo over 200,000 arming and sweep phases (no analytic shortcut):
  `D = 80` gave 7.9007 .. 8.0996 s, `D = 79` gave 7.8002 .. 7.9999 s. The earlier 100,000-phase check
  agrees.
- **Two corrections to earlier drafts.** (1) The window is ~7.9-8.1 s, **not** 7.9-8.2 s, and the
  deviation is one-sided-short, **not** "+-0.1 s": research assumption A5's "+-0.1 s on arming" is
  wrong and should be read as "-0.1 s". (2) `D = 79` **closes** the overshoot (maximum ~8.000 s); it
  does not merely halve it.
- **Scale.** The Gate G1 sweep recorded **zero** auto-passes at this deadline (2 at 5.0 s, 58 at 3.0 s,
  38,516 at 1.5 s). The 0.1 s bounds an event that is nearly unobservable in play.
- **What `D = 79` would actually touch** (re-derived in plan 04-20 against the tree; the plan said
  four edits, the tree says five plus the call site):
  1. `tests/card/config_lock.spec.luau:50` — 04-01 case 2, `deci == 80`.
  2. `tests/card/cardtable.spec.luau:784` — 04-12 case 1b, `t.equal(deci, 80)` and the chain figures.
  3. `tests/card/deci_lock.spec.luau:159-163` — 04-14 case 2, `80`.
  4. `tests/card/deci_lock.spec.luau:187-194` — 04-14 case 3: `best == 7.9` and `worst <= 8.1` become
     7.8 and 8.0.
  5. **Not in the plan's list:** `tests/card/deci_lock.spec.luau:26` / `:111` — the `WHOLE_LINE` pin
     that fixes **both arguments** of the `autoPassDeci(...)` call (04-14 M2). It must change with
     the call site or it goes red by design.
  6. The call site itself, `src/server/services/CardService.luau:58`. **It is not literally a
     one-argument tweak**: the first argument today is the locked constant
     `CardPool.AUTO_PASS_MAX_SECONDS` (asserted by `config_lock`), so 79 needs a derived expression or
     a literal 7.9, and the ceiling `assert` beside it, plus the comments in `CardService` and
     `deci_lock.spec`, must be reworded.
  Plus the STATE carry entry. `idle.spec`, and the other `autoPassDeci = 80` literals in
  `cardtable.spec`, inject their own `Deps` and are independent of the shipped value.
- **Owner:** the project owner (plan 04-20 checkpoint 2). If `set-79`, the edits above are gap-closure
  work before Phase 4 closes. Phases 6 and 8 inherit both the arithmetic and the lever.

## D. Accepted residuals and recorded gate weaknesses

### D-04-14 — A fumbled fast double-tap sends (D-02 / D-03)
- **Reason:** deliberate. There is **no debounce anywhere**; the single-tap-never-sends guarantee
  holds, but two quick taps on the same card are two taps and the second is a legitimate commit.
  A debounce would add input latency to every honest tap to protect against a fumble.
- **Owner:** M-13 and M-17 must *observe and record* what it does, so the accepted residual is seen
  rather than assumed. Phase 8 decides whether telemetry justifies revisiting.

### D-04-15 — No gate covers the service-layer wiring
- **What:** `CardService` and `Main.server` require Roblox services and cannot load in Lune, so the
  Heartbeat accumulator, the reject sink, the `PlayerRemoving` paths, the `CardSeatHold` call sites
  (`onCompleted`, `onSeatRemoved`, `removePlayer`, `endRound`) and the "release before flourish" call
  order are **source-checked and typechecked only**. Recorded by 04-13, 04-14 and 04-15.
- **Exception:** the `RoundEnd` publish is gated by `round_end.spec` (source scan, 7 mutants).
- **Follow-up:** one source-scan gate covering all those call sites at once, built on the
  `round_end.spec` pattern. **Owner:** code-review step for Phase 4, or a gap-closure plan.

### D-04-16 — Sinks-after-publish ordering is not directly asserted (04-12)
- **What:** the crude "sinks fire first" edit also made them fire twice, so its failures are weak
  evidence. A dedicated assertion (the sink observes that the Table batch is already recorded) is cheap.
- **Owner:** same follow-up as D-04-15.

### D-04-17 — D-20 stall threshold tuning
- **What:** the healthy control cannot distinguish 96 from 48 actions per seat (4.1x margin at 96,
  ~2.05x at 48, both pass `margin >= 2`). The case for 96 rests on
  `Types.VALVE_ARM_ACTIONS_PER_SEAT`, not on the control. The 380-action healthy script is an
  approximation of measured pacing.
- **Owner:** Phase 8, on `stall_armed` / `stall_cleared` telemetry.

### D-04-18 — Rate limits are starting values (V-34)
- **What:** `Draw` and `Pass` each burst 8 / refill 6 per second. Not measured. The platform ceiling
  (~500 requests/s/client) gives no gameplay number. The reject **log** is throttled per user, so a
  real diagnostic can be lost inside a throttled flood (D-22 closed on that trade-off); `streakOf`
  exists for Phase 8 to act on. **Phase 4 kicks nobody.**
- **Owner:** Phase 8.

### D-04-19 — `readViewport` may double-count insets under `CoreUISafeInsets`
- **What:** `readViewport` takes camera size plus `GuiService:GetGuiInset()`; whether that counts the
  inset twice under `CoreUISafeInsets` is unverified (recorded in the `CardHud` header).
- **Owner:** M-12 observation; fix only on evidence.

### D-04-20 — Review-only paths with no executed test
- **What:** the strip's `task.delay` cancellation (04-16), the held-return `task.delay` and
  `Tween.Completed:Once` on destroyed instances, and the dashed-gradient `NumberSequence` ordering
  (04-17), the `pcall` around table-place construction (04-19), and `CardHud.new`'s possible yield in
  the `RoundStart` handler path (04-18). None of these files loads in Lune.
- **Owner:** code review; M-12/M-13/M-17 exercise them on a device.

### D-04-21 — UI-SPEC deviations routed to a human look
- **What:** the joker corner star uses `TEXT_SIZE.BODY` (20), not the UI-SPEC's 24 (`CardTheme` has no
  24, and adding one collides with `DESIGN` under renderer-discipline case 1) -> **M-14**. The
  backdrop is parented to the Hud's Root and so also sinks touches over the table region -> **M-12 /
  M-13** (camera-drag interference).
- **Owner:** M-12, M-13, M-14.

### D-04-22 — 3D table cosmetics are starting values
- **What:** stack heights and positions (seat anchor + 3 studs along `look`; the real table height is
  unknown because the map's `Seats` pose is the avatar's), the `Hop` pool cap (over-cap hops are
  dropped silently by design), the `Completion` flourish face (a `TextLabel` in a `SurfaceGui`; the
  copy index only picks the pip, so the suit shown can differ from the real copy).
- **Owner:** M-12 / M-14 / M-17; Phase 7 owns anything that becomes a cosmetic.

### D-04-23 — Audio
- **What:** all audio ids are empty by contract until M-16, so the client is silent. A `Sound` whose id
  fails to load never fires `Ended` and is never destroyed. A repeated own draw/pass within 120 ms can
  have the first sound's delayed `Stop` cut the second.
- **Owner:** M-16 (owner-uploaded assets; non-blocking for the phase).

### D-04-24 — Flourish limits that cannot be closed
- **What:** a synchronous infinite loop in a flourish's `play` cannot be stopped in Luau, and "every
  parent a flourish could reach" cannot be enumerated, so the F8 escape check is a scan, not a proof.
  `Interactable` is tested on `GuiButton` only (it defaults to true on every GuiObject).
- **Owner:** Phase 7, which supplies `play` through the injected registry and **cannot** supply a
  duration (an unequal duration would be a pay-to-win defect).

### D-04-25 — The forced-pass pair is rendered, but only a human can say it reads
- **What:** a forced pass landing while the player's own `Pass` is in flight produces two visible
  changes (a card leaving that was not chosen, and the player's own card returning). Rendered as a
  held return then a fly-back (04-17). Roughly 1 round in 12 at a full roster.
- **Owner:** M-13, M-17.

### D-04-26 — Seat-pose publication must not widen
- **What:** seat poses cross the network in `RoundStart` (the `Seats` folder lives under `Data`, never
  cloned into Workspace). Narrowness is enforced by passing four-field structs, not map nodes.
- **Owner:** Phases 5 and 6 must not widen it to anything else under `Data`.

### D-04-27 — Tooling findings (not product defects)
- **What:** `requirements.mark-complete` falsely ticks UX-01..03 and CARD-13/16/17 from plans that
  deliver only fakes and manual-check rows (ten executors independently found this);
  `state.advance-plan` errors on this `STATE.md` format; the roadmap updater rewrites `stopped_at`
  to stale text; `verify.luau` catches seven type errors `tests/run.luau` does not (04-06, 04-08, 04-10,
  04-12, 04-13, 04-14, 04-18); `analyze.luau --ignore` is refused by the sandbox.
- **Owner:** orchestrator / GSD tooling. **Do not run `requirements.mark-complete` for this phase.**

### D-04-28 — A stale file name in `ROADMAP.md`
- **What:** `ROADMAP.md` still lists plan 04-19 as "CardTableView ...". Plan 04-19 renamed it
  `CardSeatsView.luau` because `check-guards` matches `guardedNamePrefixes` by prefix and a `CardTable*`
  renderer became a FOUND-05 guarded root and R3-failed. Fixed in plan 04-20 in
  `src/shared/Config/Card.luau` (a comment) and `.planning/research/ARCHITECTURE.md`; `ROADMAP.md` is
  orchestrator-owned and **still needs the edit** (line 175). `04-19-PLAN.md` is a historical record
  and is left as written; `04-19-SUMMARY.md` deviation 1 explains the rename. The local identifier
  `CardTableView` inside `CardSeatsView.luau` is a variable name, not a file name, and is code.
- **Owner:** orchestrator.

### D-04-29 — Gate weaknesses recorded in the mutation ledger
- **What:** see `04-VALIDATION.md` § Mutation ledger: the order-dependent counters in `flourish.spec`
  (04-10), `layout.spec`'s unconditional `mutations += 1` (04-08), 04-16's
  "no string literal except empty" really meaning "no literal containing a space", 04-17's M6
  (the dedicated `Active`-sink problem is not what fires first), 04-18's M1 (caught first by the
  non-vacuity assertion), and 04-19's per-message Depths truth check (only the final message).
- **Owner:** Phase 4 code-review step.

### D-04-30 — Count mismatches found in plan prose
- **What:** 04-12 states "fourteen" and "all nine" mutations; 04-06 requires `grep -c 'MUTATION:'`
  >= 5 and the file has 4. Recorded as findings in `04-VALIDATION.md` and **not** edited away.
- **Owner:** none; a record, so the next phase's planner does not copy the pattern.

---

## E. Pre-launch carry-list

Items Phase 4 deliberately left for pre-launch. They were scattered across plan prose and
`MANUAL-CHECKS.md` as the words "before launch", which is how a carry gets lost; this is the index.
**Owner for all three: Phase 8 (Parity, Hardening and Soft Launch).**

### D-04-31 — The three audio asset ids
- **What:** `Config.Card.AUDIO.STING`, `.DRAW` and `.PASS` ship `""`. Phase 4 is **silent on
  purpose**, not silent by omission: `CardAudio.makeSound` returns before constructing a `Sound` for
  an empty id, so no instance exists under `SoundService` and every play call returns immediately.
  M-16's Expected names this as a pass ("ids supplied **or deliberately left silent**").
- **Reason:** owner decision 2026-11-08, deferring to pre-launch. Uploading now would mean judging
  M-14 and M-17 against assets chosen before the game had been played.
- **Picking it up:** uploaded audio is **private to the uploader**, so it must come from the account
  or group that owns universe `10774461969` or it will not play in `Spoons Dev`. Audio is
  **moderated after upload**, and a pending id is indistinguishable from an empty one at the UI.
  `DRAW` and `PASS` are cut at `AUDIO.OWN_CAP_SECONDS = 0.12` so they cannot smear into the next
  action; `STING` is **not** capped. Volume is `AUDIO.VOLUME = 0.3`. Changing any id is a one-line
  edit to `src/shared/Config/Card.luau` and needs no code change.
- **Owner:** Phase 8.

### D-04-32 — Re-run the M-11 matrix under `PlayerScriptsUseInputActionSystem = Enabled`
- **What:** M-15 pinned the flag to `Disabled` so Phase 4's control-hide matrix had one fewer
  variable. The platform default flips to the Input Action System in **early 2027**, under the
  project, with no commit to blame.
- **Why it is a real risk and not paperwork:** D-29 and D-30 (controls hide while seated, control
  returns instantly) are verified only under `Disabled`. If IAS changes how
  `PlayerModule:GetControls():Disable()` behaves, a seated player could walk away from the table or a
  finisher could be held still and lose find-order score -- and the flip arrives without a deploy.
- **Owner:** Phase 8. Already written at `MANUAL-CHECKS.md` M-11 and `04-RESEARCH.md` (V-26).

### D-04-33 — Production place settings
- **What:** `SPOONS [BETA]` (place `123236339661606`) has had **nothing** set by M-15.
  `StarterGui.ScreenOrientation` and `PlayerScriptsUseInputActionSystem` were set on `Spoons Dev`
  only, and the Creator Dashboard's **Supported Devices** was not touched on either.
- **Reason:** D-23 pins `servePlaceIds` to the dev place, so Rojo cannot reach production; production
  still runs Phase 1-3 code with no card UI to orient; and setting it would mean publishing Phase 4
  over the live place, which D-23 already declined once as not worth a production publish.
- **Note:** Rojo 7.7.1 **can** set both properties via `$properties` (measured 2026-11-08, see M-15),
  so the orientation half can be code rather than a human step whenever production is next published.
  Supported Devices stays a Dashboard setting and belongs to **UX-06**.
- **Owner:** Phase 8 (UX-06: "supported devices and orientation are set explicitly with console and
  VR disabled").
