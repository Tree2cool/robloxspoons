# Phase 4: Live Card Table - Research

**Researched:** 2026-11-05
**Domain:** Roblox/Luau server card shell around a pure engine + vanilla-UI card table for PC and phone
**Confidence:** MEDIUM overall. HIGH on transport, ordering, ScreenInsets, fonts and project integration (primary docs fetched or code read). MEDIUM on the control-hiding mechanism: the only mechanism this phase's own documents named is now known to be on a removal path, and every replacement is documented but unproven in this project. LOW on all device-feel claims (nothing in this container can run Studio or a phone).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

### Tap-select / tap-pass (CARD-02, CARD-15)

- **D-01: The committing second tap lands on the SAME CARD.** Tap a card to select it; tap that
  same card again to send it to your right pile. The owner considered and rejected making the
  right pile the commit target.
- **D-02: There is NO gate, debounce or arming delay. Selection and commit are both instant.**
  The owner first chose an animation gate, then explicitly removed it: *"Honestly remove the
  0.5s, make it instant."* Speed wins over accident-proofing.
- **D-03: CARD-15 therefore rests entirely on "one tap alone never sends a card."** This is
  exactly what ROADMAP success criterion 1 requires in its own words ("an accidental single tap
  never sends a card"), so the requirement is met literally and not by approximation.
  **The residual, recorded honestly:** a fumbled fast double-tap on a single card WILL send that
  card. There is no mechanism that prevents it and none is wanted. Do not add a debounce later
  to "fix" this without re-opening D-02 — it was a deliberate trade.
- **D-04 (derived from D-01 + D-02, not asked): cancelling can only be "tap a different card" or
  "tap off the hand".** The owner chose "selection follows the tap", whose option text said
  tapping the selected card would clear it — but D-01 makes a second tap on the selected card
  the SEND. The send wins. So: tapping another card moves the selection; tapping off the hand
  clears it; tapping the selected card commits it. Flagged to the owner at the time and not
  contradicted.
- **D-05: One mechanic only — no drag, no flick, on any platform.** PROJECT.md makes
  identical-with-thumb-and-mouse a first-class property; a second input path is a second
  accident surface and doubles what every reconcile test must cover.
- **D-06: The right pile is a destination only, inert to taps.** It shows where cards go and how
  deep it is. It does not need to meet the 48px target floor, which frees real estate in the
  landscape layout.
- **D-07: The left-pile draw is instant and unguarded.** You can only draw at exactly 4 cards
  and you always want to draw eventually, so an accidental draw costs nothing strategically.
  CARD-15 names passing, not drawing. Keeping it instant also keeps the four-of-a-kind check —
  which happens only on draw — feeling immediate.

### Input parity and hints (UX-04)

- **D-08: Mouse clicks exactly the same targets as a thumb, plus OPTIONAL keyboard
  accelerators** (number keys to select, one key to commit) for players who want them. The
  pointer path is the guaranteed one; the keyboard is additive and must not become the only way
  to do anything.
- **D-09: Hints follow the LAST INPUT ACTUALLY USED and switch live.** Not device type at join.
  This is what handles a touchscreen laptop, a phone with a paired mouse, and someone who picks
  up a controller mid-round.

### Prediction and reconciliation (CARD-14)

- **D-10: The client applies the action locally the instant it commits, before any server
  acknowledgement.** Required by CARD-14's "feels immediate at 150-300 ms"; waiting for the ack
  is a visible stall on every single pass. Both draw and pass are predicted.
- **D-11: On a server disagreement the card RETURNS VISIBLY** — a short deliberate motion back
  into the hand. Not a silent snap. The criterion is "no visible glitch", which a deliberate
  motion satisfies and a teleport does not.
- **D-12: A hard rejection looks IDENTICAL to a correction, with no message.** Rate-limited,
  `NotYourCard`, `HandNotFour`, `HandNotFive`, `InboxEmpty`, `SeatNotLive`, `UnknownCard`,
  `UnknownSeat` — all of them just return the card silently. A legitimate player should never
  see one; a message would be noise at best and would hand a prober the name of the guard they
  tripped. Reject codes stay server-side telemetry.

### AFK auto-pass and benching (CARD-16)

- **D-13: The auto-pass deadline is 8.0 s — the locked ceiling itself.** `CardPool.AUTO_PASS_MAX_SECONDS`
  is 8.0 and Phase 4 must not exceed it; the owner chose to sit exactly at it. Evidence: the G1
  sweep recorded **0 auto-passes across its 8.0 s cells** (2 at 5.0 s, 58 at 3.0 s, 38,516 at
  1.5 s), so at 8.0 s it fires only for genuinely absent players and essentially cannot strike a
  player who is merely slow on a phone. The bot reaction-time model's realism is itself
  unverified (V-35), so the conservative end is the honest pick. Phase 6 or Phase 8 may tighten
  it on real session data.
- **D-14: `AUTO_PASS_SELECTION` = `uniform-random-from-hand` is LOCKED and is not a tuning
  knob.** A card drawn uniformly at random from the hand. The helpful-looking "auto-pass your
  worst card" is the player's own greedy choice, which makes the deviation exactly zero and
  means the simulator's auto-pass numbers transfer nothing to the shipped game. This is the half
  that looks like a free implementation choice and is not.
- **D-15: The idle clock runs ONLY while the seat has a legal action available** — hand at 4 with
  a non-empty inbox (can draw), or hand at 5 (owes a pass). It pauses otherwise. Without this,
  the ~8.3 s start-up ramp at a full table would strike far seats for waiting on cards that have
  not reached them yet. This is the single most likely thing to be implemented wrong.
- **D-16: A late visible countdown.** Nothing for most of the window, then a clear countdown or
  draining indicator for the last couple of seconds. An engaged player never sees it; a
  distracted one gets a real chance to act before losing a card; a struck player cannot claim
  they had no warning.
- **D-17: Three strikes benches the player, and ANY real action resets the count to zero.**
  Forgiving to one bad connection moment or one phone call; an absent player is gone in roughly
  half a minute at an 8 s deadline. Benching goes through the **one generic seat-removal
  operation** (CLAUDE.md rule 8) with cause `Benched`, so the benched seat's cards route to the
  successor and are never destroyed.

### Forced pass, start-up ramp and stalls

- **D-18: A `ValveForcedPass` shows a PRIVATE cue to the affected player only.** The table sees
  an ordinary pass. The owner chose this over a named table-wide event.
  **The consequence, recorded:** the downstream player receives a card with no explanation and
  nothing marks it as forced. Accepted. This is NOT a rare path — the valve fires in roughly 8%
  of rounds at a full roster (3.59-8.24% per cell at N=10, up to 15.8% at tighter pools), so the
  cue must be built as an ordinary feature with real art and real copy, not as an edge case.
- **D-19: During the start-up ramp, cards are VISIBLY TRAVELLING the ring toward you.** The wait
  reads as the deal arriving rather than as nothing happening. Diegetic, needs no text, and it
  doubles as the thing that teaches a new player how the chain flows. The ramp is real and
  measured: ~8.3 s at N=10 against a 4.6 s median time-to-first-completion at N=3.
- **D-20: The stall cue is driven by its OWN server-side no-progress detector, never by valve
  events.** This is mandatory, not stylistic. Phase 2 verification replayed 15 residual stalled
  seeds: all ran 2,431-4,429 actions without clearing against a healthy mean of ~380, and **3 of
  the 15 had the valve armed with ZERO firings**. The valve fires only on an *exact* whole-table
  state repeat, so a stuck trajectory that never exactly repeats is invisible to it. A cue keyed
  off valve events would be silent in exactly the rounds that need it.
  The detector's threshold is Claude's discretion; it should also emit telemetry so Phase 8 has
  a real signal rather than a guess. **Ending the round early was considered and rejected as
  out of boundary** — round-end conditions belong to Phases 5 and 6.

### Card faces (CARD-19)

- **D-21: Engine ranks map to REAL playing-card ranks, with the four suits as the four copies.**
  The engine has no suits: a rank is an integer and `ranks = seated seekers + 3`, so a round uses
  between 5 ranks (3 players) and **12 ranks (10 players)**, four copies each, plus one joker.
  Twelve fits inside A,2..10,J,Q,K (thirteen), so a round is a subset of a standard deck. Chosen
  because this is the classic card game Spoons — "four of a kind" is a concept players arrive
  already knowing — and because suits give the four copies separate identities, so a player can
  track what they have passed.
- **D-22: The engine-rank-integer to card-rank-glyph mapping must be STABLE for the whole
  round.** A player must see the same glyph for the same rank from deal to completion. The
  mapping itself is Claude's discretion; its stability is not.
- **D-23: The joker is visually unmistakable AND states its current rule on the face.** This is
  load-bearing beyond art: `CardPool.JOKER_MODE` is a **live flag** ("Wild" shipped, "Blocker"
  live behind the flag, both clearing every G1 bar), so the same card means two different things
  depending on configuration. The face must be able to say which, or the flag silently lies to
  the player. Do not hard-code wild semantics into the joker's art or copy.
- **D-24: Colour-blind safety is guaranteed by "GREYSCALE MUST SURVIVE", as a falsifiable
  test.** Shape and glyph carry all rank and copy identity; colour is decorative only. Render
  the whole card set in greyscale and every rank, every copy and the joker must stay
  distinguishable. This turns CARD-19 from a reviewer's opinion into a test, and it also covers
  total achromatopsia, which a tuned palette cannot.
  **Compatibility note:** real suits satisfy this only because the four pips are shape-distinct
  shapes. Red/black must never be the ONLY difference between two cards. Phase 7's purchasable
  deck skins inherit this rule.

### Layout — PC and mobile (UX-01, UX-02, UX-03)

- **D-25: The hand is an OVERLAPPING FAN** showing each card's corner index, with the selected
  card lifting clear to show its full face. Mirrors a held hand, keeps the hand compact enough to
  leave room for both piles, and the lift doubles as the selection affordance from D-01.
- **D-26: Your two piles sit at the two BOTTOM CORNERS, flanking the fan** — left pile
  bottom-left, right pile bottom-right. Both land where thumbs rest in landscape, and it
  preserves the real geometry (upstream on your left, downstream on your right), so the screen
  teaches the chain direction. Tapping the real 3D stacks instead was considered and rejected: a
  3D target's on-screen size depends on framing, which would make the 48px floor something you
  verify per map rather than guarantee.
- **D-27: The camera frames the table into the UPPER portion and the hand overlay lives below
  it, never covering it.** The table must stay a place, not a wallpaper — you watch stacks grow,
  see cards travel (D-19), and see someone stand up and run (D-15, carried from Phase 1). The
  "table as backdrop" option was rejected explicitly because it turns the card phase back into
  the menu transition the Core Value forbids.
- **D-28: LANDSCAPE IS LOCKED in the place's supported-orientation settings**, with an in-game
  rotate prompt only as a fallback for anything that slips through. Portrait is not supported;
  five cards plus two piles does not fit. **This is a Creator Dashboard setting, so it is a human
  gate** — add it to `MANUAL-CHECKS.md` and `NEEDS_HUMAN.md` alongside the existing place
  settings rows.
- **D-29 (derived from D-15 of Phase 1, not asked): movement controls are hidden PER PLAYER
  WHILE SEATED, not for the whole `Round` phase.** A finisher stands up and runs mid-round and
  needs controls back the instant they complete. UX-02 plus D-14/D-15 of `01-CONTEXT.md` make
  this the only consistent reading.

### The starting gun (CARD-17)

- **D-30: Control returns to the finisher INSTANTLY.** The set slams down, the chair pushes
  back, and the player is already running while the flourish plays around them. **This is a
  scoring constraint, not a feel preference:** find order drives SCORE-01..03, so any beat that
  holds the finisher still is literally taking points off them. No celebration may block input.
- **D-31: The table sees the diegetic event PLUS a brief callout naming who went.** The four
  cards visibly leave play and that player's avatar stands and runs (D-15 of Phase 1). The
  callout is added because the information is already public and "someone is already out there"
  is the pressure the whole design runs on — there are two fewer spoons than players. A player
  head-down in their hand on a phone would otherwise miss it. **Round placement / standings in
  the callout were rejected as out of boundary** (Phases 5 and 6).
- **D-32: Built behind a hook with an EXPLICIT FIXED DURATION that Phase 7 plugs into.**
  PROJECT.md requires every deal animation to have the same fixed duration so none confers an
  advantage. Defining that contract now is what makes it enforceable later instead of a retrofit,
  and an unequal-duration animation would be a pay-to-win defect, not a cosmetic bug.
- **D-33: Audio in Phase 4 is a completion sting plus quiet feedback for YOUR OWN draw and
  pass** — and deliberately little or nothing for other seats' passes, because nine players
  passing constantly is a cacophony. A starting gun that makes no sound is not a starting gun,
  and Gate G3's slice exists to prove the core feeling.

### Carried forward from earlier phases — do NOT re-open

- **From `01-CONTEXT.md`:** D-11 (the card table is a physical location in every map, 9 seat
  anchors, hand is a screen overlay), D-14 (camera locked to the table during the card phase),
  D-15 (a finisher stands up and runs — no teleport; this IS the concrete form of CARD-17),
  D-20 (phase vocabulary `Lobby | Hide | Round | Podium`; `Round` is the single phase where
  cards and hunt overlap).
- **From CLAUDE.md:** rule 5 (the server is the only clock; integer deciseconds), rule 6 (no
  yields inside state mutations — events are returned, then published), rule 7 (the client
  never names a pass target or a hand index; it sends stable card IDs and the server resolves
  `next` at execution time), rule 8 (one generic seat-removal operation; a removed seat's cards
  route to the successor and are never destroyed).
- **From Gate G1 (`CardPool.luau`):** `EXTRA_RANKS = 3`, `JOKERS = 1`, `JOKER_MODE = "Wild"`
  with Blocker live behind the flag, `ANTI_LIVELOCK_VALVE = true` (must stay true),
  `AUTO_PASS_MAX_SECONDS = 8.0`, `AUTO_PASS_SELECTION = "uniform-random-from-hand"`.

### Derived constraints the planner must honour (not discussed — forced by existing decisions)

- **Hands are per-player private.** CARD-13 gives a client its own hand and only the pile
  *depths* of others. A client must never receive another seat's hand contents in any form. This
  is the card-table analogue of CLAUDE.md rule 3 and the same cheat-client reasoning applies.
- **The engine must not be made to require shared config.** `src/server` and `src/shared` are
  separate Rojo mounts and guard rule R6 fails a relative require across them. The Phase 4
  adapter reads `CardPool` by absolute DataModel path and passes the values into an
  `EngineConfig` **value** — exactly as `src/shared/Config/CardPool.luau`'s own header states.
- **Round timing crosses a unit boundary.** The simulator's clock is float seconds; the shipped
  clock is integer deciseconds (rule 5). Round at the boundary when carrying any
  simulator-derived timing across — including the 8.0 s deadline.
- **`ValveForcedPass` may cross the network, and carries no hash by design** (`Types.luau`
  comment). Do not add state hashes to anything client-bound.

- **D-34: NO new third-party dependency, and no UI framework. Vanilla Roblox UI only.** This is
  forced by the container, not a style preference. There is no `wally.toml` and no `Packages/` in
  the tree, `rokit.toml` holds only rojo/stylua/selene/luau-lsp/lune, and **`rokit install` cannot
  work here at all** — `api.github.com/repos/.../releases/tags/...` returns 403, which is exactly
  what `01-CONTEXT.md` D-16's correction records (the toolchain was installed by downloading
  release archives directly). So adding Fusion, React-lua or any other UI library would mean
  inventing a second bespoke vendoring path for a dependency nobody has decided to take on.
  Build the card UI from `ScreenGui` / `Frame` / `ImageLabel` / `TextLabel` and plain Luau.
  If a planner or executor believes a library is genuinely required, that is a BLOCKER to raise
  with the owner, never something to install.

### Claude's Discretion


- The exact `Draw` / `Pass` intent payload shapes and their `Validate` schemas (within rule 7:
  stable card IDs only, never a seat or hand index).
- **D-22 of `01-CONTEXT.md` — the gateway's phase-gate-before-token-bucket order.** Flagged
  there for revisit in "Phase 4 or Phase 8". Carried as a planner decision: either charge a
  token on wrong-phase rejection, or keep the order and add a cheap repeat-offender counter.
  Record whichever is chosen and why; do not treat the current order as settled.
- Rate limits for the new intents in `src/shared/Config/RateLimits.luau`. The current default is
  burst 4 / refill 4 per second, set before any card traffic existed. A player acts roughly
  twice a second at speed, so the default is plausible but unvalidated; tuning lands in Phase 8.
- The state-publication shape (full snapshot versus deltas), the client-side predicted-state
  representation, and the reconcile trigger.
- The no-progress detector's threshold (D-20), and the countdown's exact visual form (D-16).
- The rank-integer to card-rank mapping (D-22), card art, the fan's geometry, and the fixed
  duration chosen for the D-32 hook.
- Whether the AFK strike count lives on the engine state or beside it (the engine is pure; a
  strike is shell bookkeeping, so beside it is the expected answer).

### Deferred Ideas (OUT OF SCOPE)


- **Table-wide `ValveForcedPass` event.** Considered and rejected in favour of a private cue
  (D-18). Worth revisiting if playtests show the receiving player is confused by cards arriving
  unprompted.
- **Drag-to-pile as a second pass gesture.** Rejected (D-05) to keep one mechanic and one
  accident surface. A candidate for Phase 8 if touch players ask for it.
- **Portrait support.** Rejected (D-28). Would be a whole second layout; revisit only if
  telemetry shows portrait attempts are common.
- **Ending a stalled round early.** Out of boundary — round-end conditions belong to Phases 5
  and 6. The no-progress detector (D-20) should emit telemetry so that decision can be made on
  data in Phase 8.
- **Standings in the starting-gun callout** (first out, second out). Out of boundary — round
  placement and scoreboard presentation are Phases 5 and 6.
- **Tightening the auto-pass deadline below 8.0 s.** Deliberately left at the ceiling (D-13)
  because V-35 is open. Phase 6 or Phase 8 may lower it on real session data.
- **Widening the fuzz suite's `k` grid to cover the shipped `k = 3`.** Carried from Phase 2's
  verification; its 194,567-action conservation result is not a claim about the shipped pool.
  Cheap to do while Phase 4 is already touching the suite.
- **Extending the CI regression subset past N = 3/6/10.** Every observed residual stall was at
  N >= 7 (worst cell N = 9), so the CI subset cannot see the regime the residual lives in.

</deferred>

### Project Constraints (from CLAUDE.md)

- Non-negotiable rules 1, 3, 5, 6, 7, 8 bind this phase: gameplay code has no import path to cosmetics/shop (lint FOUND-05); nothing hidden is a replicated Instance or client-visible; the server is the only clock, integer deciseconds; no yields inside state mutations (events returned then published); the client names stable card IDs only, never a seat, target or hand index; seat removal is one generic operation and a removed seat's cards are never destroyed.
- Rule 2 (the engine references no Roblox API) and the pure-zone lint: do not touch `src/server/engine/`.
- `--!strict` everywhere; every CI check hard-fails; full PC and mobile parity; touch targets >= 48px; `ScreenInsets` set explicitly; movement controls hidden during the card phase.
- PROJECT.md wins over research; do not re-open Key Decisions. Every Roblox platform claim must be re-checked against primary docs (done here; see Verification Debt Re-check).

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CARD-02 | One tap selects, a second tap sends to the right pile | Intent surface and `Pass{seq, cardId}` schema (Integration 1); pure selection/commit reducer (Integration 4); hit-strip model is already in UI-SPEC |
| CARD-13 | Own hand + only pile depths of others | Per-player send seam and privacy test (Integration 2); `depths` vector is the only cross-seat data (Architecture, wire shapes) |
| CARD-14 | Immediate at 150-300 ms, server reconciles | Pending-queue + cumulative-ack reducer, watchdog resync (Integration 4); V-12 closed, so the ordered private stream is documented |
| CARD-15 | One tap alone never sends | Rests on D-01..D-03; pure reducer test "single commit-less tap emits no intent"; no debounce (D-02) |
| CARD-16 | Idle auto-pass, strikes, bench | `IdleClock` pure core, deci rounding rule, `Remove{Benched}` (Integration 5); hand-4 expiry is an OPEN QUESTION with a recommendation |
| CARD-17 | Starting-gun moment | Flourish driver contract + mocked-clock tests; server releases the avatar and restores controls on `Completed` (Control hiding, Integration 8) |
| CARD-19 | Legible, colour-blind-safe faces | `copy` assignment (Integration 3), identity-key injectivity + drawn-asset distinctness, Gotham font trap (Verification Debt N-1) |
| UX-01 | Phone-playable, targets >= 48 px | Pure `Layout` arithmetic test; V-25 settled: Roblox publishes no numeric minimum, 48 is the project's own floor |
| UX-02 | Movement controls hidden during card phase | V-26 re-check: `GetControls()` is undocumented and on a removal path. Layered replacement in Control hiding |
| UX-03 | Safe areas | V-24 verified; `CoreUISafeInsets`; layout test over four viewports; real-device observation remains |
| UX-04 | Hints match input method | `LastInputTypeChanged` (documented); pure input-kind map + hint-table completeness test; V-27 partially verified |
</phase_requirements>

## Summary

Phase 4 is integration work, not discovery. The engine is finished and the transport exists; the new surface is (a) two manifest intents, (b) a pure server card-table core that wraps `Engine.apply` and decides *who is told what*, (c) one new server-to-client remote owned by `NetServer`, (d) a pure client reducer for prediction, and (e) a vanilla-UI renderer. The recommended shape keeps every decision in pure modules that Lune can run, and leaves only `Instance.new`, `TweenService` and the Studio/phone checks outside the headless suite. Four of the five roadmap success criteria remain device-dependent; the research below says exactly which assertions can be moved to arithmetic and which cannot.

The standing Verification Debt rule paid off, and it changed two things this phase's own documents rely on. **V-26 is the headline:** `require(PlayerScripts.PlayerModule):GetControls():Disable()` appears nowhere in Roblox's official documentation, and a staff-authored release post (2026-06-11) says the legacy endpoints "may no longer exist" once the new Input-Action-System player scripts are on, with that becoming the engine default in early 2027 and the only option by mid-2027. DevForum posts from August and October 2026 confirm `GetControls()` is already missing on opted-in places. UX-02 and D-29 therefore cannot rest on it. The documented replacements are: server-set `Player.DevComputerMovementMode` / `DevTouchMovementMode = Scriptable`, client-set `GuiService.TouchControlsEnabled = false`, and a higher-priority sinking binding for keys. None is proven in this project, so a Studio matrix check is mandatory. **V-12 closed in the favourable direction:** the docs now guarantee RemoteEvent ordering across different RemoteEvent instances, so the earlier "cross-remote not guaranteed" caution is superseded.

Two more traps found by reading code and docs rather than assumptions. (1) The repo's guard rule R4 confines `FireClient`/`FireAllClients` to `NetServer.luau`, so the UI-SPEC's "card publish module" cannot call them; the privacy seam must be an interface that `NetServer` implements and the pure core receives. (2) `Enum.Font.Gotham*` "has been removed" and maps to Montserrat, so the UI-SPEC's Gotham fallback is not a fallback at all.

**Primary recommendation:** Build `CardTable` as a pure server core (`src/server/core/CardTable.luau`, which also puts it under the existing FOUND-05 no-cosmetics lint by filename) that takes an injected `Publisher { toPlayer, toSeated, toAll }` and an injected deci clock; add `Draw{seq}` / `Pass{seq, cardId}` to the Manifest; reduce the client to a pure `auth + pending[]` fold in a new pure zone `src/shared/Card/`; hide controls with a layered, server-authoritative mechanism behind one `Controls` seam and prove it in a Studio matrix, never via `GetControls()`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Card legality, completion, valve, seat removal | Server engine (`Engine.apply`) | — | Pure, fuzz-proven, already done; shell never reimplements a rule |
| Seat lookup (userId to SeatId), copy assignment, who-sees-what | Server pure core (`CardTable`) | `NetServer` (Roblox edge) | Rule 7: seat derived from the Player, never the payload. Decisions are pure and testable; the edge only fires remotes |
| Per-player vs broadcast delivery | `NetServer` (sole owner of `FireClient`/`FireAllClients`, guard R4) | Pure core chooses the method via `Publisher` | The privacy decision is data in the pure core; the Roblox call is confined by an existing lint |
| Idle clock, strikes, bench decision | Server pure core (`CardTable` + `IdleClock`) | Roblox adapter ticks it at 10 Hz | Rule 5: server is the only clock; strikes are shell bookkeeping, not engine state |
| No-progress (stall) detector | Server pure core | Telemetry sink | D-20 mandates independence from valve events |
| Holding the avatar at the seat / releasing it on `Completed` | Server (Roblox adapter) | Client hides UI only | A cheat client can re-enable controls; staying seated must be server-enforced. Client hiding is ergonomics, not enforcement |
| Prediction, rollback, selection state | Client pure reducer (`src/shared/Card/`) | Client renderer | Pure so it can be tested at simulated lag without Roblox |
| Layout, hit strips, safe-area arithmetic | Client pure `Layout` | Renderer applies results | UX-01/UX-03 become arithmetic assertions |
| Rendering, tweens, audio | Client renderer (`src/client/ui/`) | — | Only the Roblox-API-touching layer; thin by design |
| Hiding default controls (UI occlusion) | Client (`GuiService.TouchControlsEnabled`) | Server (`Dev*MovementMode`) | See Control hiding |
| Flourish duration enforcement | Client driver (injected clock) | Phase 7 registry | Driver owns duration; content never does (D-32) |

## Verification Debt Re-check (standing rule; do this before trusting anything below)

Primary-source access: `create.roblox.com` `.md` pages and `/docs/api/search` answered 200 `text/markdown` / `application/json`; `devforum.roblox.com/t/<id>.json` and `/search.json` answered 200 via `curl` (the `WebFetch` tool still cannot resolve `devforum.roblox.com`). All docs pages cited below carry `last_updated` 2026-11-04. DevForum is community plus staff posts: treated as MEDIUM and labelled.

| Row | Status | What was found | Source |
|-----|--------|----------------|--------|
| **V-12** same-remote / cross-remote ordering | **VERIFIED, and the old caution is superseded** | RemoteEvents are reliable and ordered per connection per direction, "**including across different RemoteEvent instances**"; holds for `FireClient` and `FireAllClients`. UnreliableRemoteEvent has neither guarantee and no ordering relationship to RemoteEvents. RemoteFunction vs RemoteEvent order is NOT guaranteed. Ordering is of handler *start*, not completion: a yielding handler can be overtaken. Undelivered messages are lost on disconnect. | `https://create.roblox.com/docs/scripting/events/remote.md` (`last_updated: 2026-11-04T22:23:23Z`), section "Delivery guarantees" |
| **V-13** deferred vs immediate | **VERIFIED** | `Workspace.SignalBehavior` `Default` is currently equivalent to `Immediate` and "will eventually switch" to `Deferred`; template places are set to `Deferred`. Resumption points are listed. The repo sets no `SignalBehavior` (grep of `default.project.json`: no match), so the built place runs `Default`. Design stance: be correct under both (the engine returns events after `apply`; no handler may read a result synchronously after triggering it). | `https://create.roblox.com/docs/scripting/events/deferred.md` (`last_updated: 2026-11-04T22:23:23Z`) |
| **V-24** ScreenInsets | **VERIFIED (orchestrator pass, not redone)** | `CoreUISafeInsets` = 2, recommended for interactive UI | `04-DEBT-RECHECK.md`; `.../enums/ScreenInsets.md` (`2026-11-04T22:23:21Z`) |
| **V-25** Roblox minimum touch target | **VERIFIED ABSENT (negative claim, MEDIUM)** | Roblox publishes **no numeric minimum**. Searched: `ui/position-and-size.md`, `production/game-design/ui-ux-design.md`, `production/publishing/adaptive-design.md`, `production/publishing/accessibility.md`, `ui/buttons.md`, `projects/cross-platform.md`, `tutorials/.../interactive-ui.md` and the search endpoint with four phrasings: none gives 44, 48 or any pixel floor. `position-and-size.md` does say the default mobile controls "occupy a portion of the bottom-left and bottom-right corners; avoid placing important info or virtual buttons in these zones", and gives qualitative thumb-zone guidance. **48 px stays a project decision; 44 stays an unattributed third-party figure. Cite neither as platform fact.** The same page independently supports UX-02 (the default thumbstick sits exactly where D-26 puts the left pile). | `https://create.roblox.com/docs/ui/position-and-size.md` (`2026-11-04T22:23:28Z`) |
| **V-26** disable default controls | **STILL OPEN, but materially CHANGED; do not use `GetControls()`** | See next subsection | Several, below |
| **V-27** ContextActionService / gamepad | **PARTIALLY VERIFIED (API existence); device behaviour STILL OPEN** | `BindAction` / `BindActionAtPriority` exist; handlers return `Sink` (or `nil`) to consume or `Pass` to fall through to lower priority; `createTouchButton` creates an `ImageButton` in a `ContextActionGui` and "a maximum of 7 touch buttons" (we pass `false`, so irrelevant). `GuiService.SelectedObject`, `GuiService.GuiNavigationEnabled`, `GuiObject.Selectable` all exist. `UserInputService.LastInputTypeChanged` exists. `UserInputService.PreferredInput` (new, read-only) exists but reports the *anticipated* primary input, which is not D-09's "last input actually used"; use `LastInputTypeChanged` for D-09 and optionally seed with `PreferredInput`. Gamepad behaviour (A, LB/RB, whether default GUI navigation steals A on a selected button) is a Studio Controller Emulator check, which the IAS page documents as available. **Recommendation: keep the gamepad column, implemented with CAS bindings (not `SelectedObject`), gated on the M-check below; drop it only if that check fails.** | `.../classes/ContextActionService.md`, `.../classes/GuiService.md`, `.../classes/GuiObject.md`, `.../classes/UserInputService.md` (all `2026-11-04T22:2x`) |
| **V-34** rate-limit numbers | **STILL OPEN (tune in Phase 8), now with a documented ceiling** | Platform throttle is "approximately **500 requests per second per client**, shared among all remote events of the same type"; RemoteEvent excess is **delayed in order**, UnreliableRemoteEvent excess is **dropped**. The docs give no gameplay-appropriate number, so burst/refill stay a project parameter. Note `Bucket` is keyed per `(userId, intent)`, so `Draw` and `Pass` each get their own bucket. | `.../classes/RemoteEvent.md` ("Throttling", `2026-11-04T22:23:20Z`); `scripting/events/remote.md` |
| **V-35** bot reaction model represents humans | **STILL OPEN, cannot be closed by documentation** | Needs a real playtest. Its home is `MANUAL-CHECKS.md` **M-07**, which is still unticked. Do not describe D-13's 8.0 s as validated; it is the conservative end chosen *because* V-35 is open. | `MANUAL-CHECKS.md` M-07 |

### V-26 in detail (the priority)

**What the docs say.** `PlayerModule`, `GetControls`, `ControlModule` appear in **zero** official engine/guide pages: `grep -il playermodule` over the fetched `UserInputService`, `ContextActionService`, `GuiService`, `Player`, `StarterPlayer`, `PlayerScripts`, `Workspace` and Input Action System pages returned nothing, and `/docs/api/search?q=PlayerModule` and `?q=GetControls` returned only unrelated pages. So `GetControls():Disable()` has never been a documented API; it is a convention from DevForum threads. [VERIFIED: create.roblox.com docs search + grep, 2026-11-05]

**What changed under it.** The official release post "[Full Release] Input Action System (IAS) & Newly Converted Player Scripts!" (staff, 2026-06-11) migrates all default player scripts to the Input Action System behind `Workspace.PlayerScriptsUseInputActionSystem`, and states: "If your custom input code references internal methods within the legacy PlayerModule (e.g., `GetControls()`), you may need to update those scripts since those legacy endpoints may no longer exist ... we recommend avoiding direct dependencies on internal PlayerModule components." Rollout, per the same post: **Phase 1 (now) Default = Disabled; Phase 2 ETA early 2027 Default = Enabled ("games referencing the old player scripts ... will likely break"); Phase 3 ETA mid 2027 property removed, old scripts inaccessible.** [CITED: https://devforum.roblox.com/t/4678416 , fetched as `/t/4678416.json`; staff post, ETAs are estimates]. Corroboration that this is live now: a community post of 2026-08-25 in the canonical "disable controls" thread says `:GetControls()` is not in `PlayerModule`; a post of 2026-10-31 says the module moved to `game.StarterPlayer.PlayerModule` and movement is toggled via `InputContexts.CharacterContext.Enabled`; the migration guide (community, 2026-06-14) says the new module "does not return anything by default" and has "no self.controls". [CITED: https://devforum.roblox.com/t/400699 , /t/4681909] The official property doc confirms the relocation: with the flag on "the player scripts live under StarterPlayer (controlled by `StarterPlayer.CreateDefaultPlayerModule`)". [VERIFIED: `.../classes/Workspace.md`, `PlayerScriptsUseInputActionSystem`]. `Workspace.PlayerScriptsUseInputActionSystem` is a `RolloutState`: `Default` tracks the engine-wide phase, `Disabled` opts out regardless, `Enabled` opts in regardless. [VERIFIED: `.../enums/RolloutState.md`]

**IAS is not a clean escape hatch yet.** A 2026-09-23 bug report (closed "fixed" by staff 2026-09-24 after private messaging, fix not described) says `Enabled=false` on `CharacterContext` / `MoveAction` did not stop movement, a sink-with-same-keycodes workaround stopped only keycode bindings and **not** `Scriptable`-type thumbstick bindings, and `ControlModule:Enable/Disable` did nothing. [CITED: https://devforum.roblox.com/t/4889933 , MEDIUM; one reporter, resolution undocumented]. Treat every IAS-side disable as unproven until the Studio matrix passes.

**Re-enable is a known sore point even on the legacy path.** DevForum reports: after `Controls:Enable()` a key that was held during the disabled period does not resume movement until released and re-pressed (2024-04, `/t/2947221`); on touch, re-enabling after disabling left the jump button "stuck" and the thumbstick dead (2025-06, `/t/3677974`); setting `GuiService.TouchControlsEnabled = false` immediately after a jump froze the jump button in Automatic mode (2024-01, `/t/2794501`). All three are community reports, none re-tested here. They bear directly on D-15/D-30 ("controls back the instant a finisher stands up"). [CITED: devforum threads above, LOW-MEDIUM]

**Documented mechanisms that exist today (official docs):**

| Mechanism | Where | Documented behaviour | Restores cleanly? |
|-----------|-------|----------------------|-------------------|
| `Player.DevComputerMovementMode = Scriptable` / `Player.DevTouchMovementMode = Scriptable` | **Server** only: "cannot be set using a LocalScript (must be set on the server using a Script)" | `DevComputerMovementMode.Scriptable`: "Disables all default controls and allows you to script your own control scheme." `DevTouchMovementMode.Scriptable`: "The player's character will not respond to default controls." Default comes from `StarterPlayer.Dev*MovementMode`. | Set back to `UserChoice` (or the captured `StarterPlayer` default). Server-authoritative, so it matches D-29/D-30 where the server already knows the moment of `Completed`. Costs one replication hop. **Unverified: whether it also hides the touch thumbstick *UI*, and whether the IAS scripts honour it.** |
| `GuiService.TouchControlsEnabled` | Client | "Used to enable and disable touch controls and touch control display UI. Defaults to `true`." Supersedes the deprecated `UserInputService.ModalEnabled`. | Set back to `true`. Has the two community re-enable bug reports above. **Unverified under IAS.** |
| `ContextActionService:BindActionAtPriority(..., false, priority, keys)` returning `Sink` | Client | Higher-priority handler consuming `Space`, `W/A/S/D`, arrows, gamepad thumbsticks before default bindings | `UnbindAction` removes it; we never touched the default scripts' own state, so there is nothing to un-break. **Unverified whether CAS sinking still reaches the IAS scripts**; the IAS-native equivalent is a new `InputContext` with higher `Priority` and `Sink = true` (documented in the IAS guide). Does not stop touch thumbstick, per the 4889933 report. |
| `StarterPlayer.CreateDefaultPlayerModule = Disabled` | Place property | "New explicit mechanism to prevent the engine overriding your custom player scripts" | Not a toggle; a different design (we would own movement). Out of scope for Phase 4. |

**Recommendation (prescriptive):**
1. **Do not call `GetControls()`, do not require `PlayerModule` at all.** Put all control hiding behind one module `src/client/ui/Controls.luau` with `hide()` / `restore()` and no other API, so the mechanism can be swapped without touching callers.
2. **Layer, in this order:** (a) **server holds the avatar** while seated (see below), which is the only part that is security-relevant; (b) server sets `Player.DevTouchMovementMode` and `Player.DevComputerMovementMode` to `Scriptable` at seat and back at stand/`Completed`/bench; (c) client sets `GuiService.TouchControlsEnabled = false` at seat and `true` at stand, to remove the thumbstick *graphics* from under the left pile; (d) client binds keyboard accelerators (`1`..`5`, `Space`, `Enter`) with `BindActionAtPriority` returning `Sink`, so `Space` does not also jump the avatar.
3. **`restore()` must be idempotent and safe to call twice**, and must be invoked from the same code path as destroying the hand overlay (UI-SPEC: "overlay gone in the same frame"). Order inside the `Completed` handler: destroy overlay, `restore()`, then start the flourish.
4. **Pin `Workspace.PlayerScriptsUseInputActionSystem` explicitly** (recommend `Disabled` for Phase 4 so the matrix has one fewer variable), because leaving it `Default` means the engine flips the player scripts under the project in early 2027 without any commit. Re-run the matrix with `Enabled` before launch. This is a place setting set in Studio, so it is a human gate: add to `NEEDS_HUMAN.md`. Whether Rojo `$properties` can set it with the pinned Rojo 7.7.1 reflection database is unknown [ASSUMED: it likely cannot, the property is newer than the pin].
5. **Studio matrix (new manual check, proposed M-11):** rows = {IAS Disabled, IAS Enabled}; columns = {PC keyboard, phone touch, gamepad}; for each: `hide` leaves no thumbstick graphics and no movement from touch/keys; `restore` while holding `W` / while thumb is down resumes movement within one second without releasing; measured seat-release to first controllable frame. Pass = every cell passes, or the failing cell has a recorded fallback. If layer (b) fails under IAS, the fallback that restores cleanly is layer (a) alone plus (c)/(d): the avatar is held by the server, the client merely hides UI, and nothing about the default scripts was mutated, so there is nothing to restore.

**What actually has to be enforced (flagged because it is easy to miss).** `Main.server.luau` and the map contract contain no avatar-seating code: grep for `Humanoid|.Sit|SeatPart|PivotTo|WalkSpeed` over `src/` finds only comments; seats are plain `Seat1..Seat9` Parts in the map contract. D-15/D-30/D-31 ("the avatar stands and runs") therefore require **new server code** to place the avatar at its seat anchor, hold it, and release it. Client-side control hiding cannot be the thing that keeps a seeker at the table: a cheat client can re-enable controls and walk off to hunt before completing a set. The hold must be server-side. [ASSUMED: server mechanism, e.g. pivot to the anchor pose plus `Humanoid.WalkSpeed`/`JumpHeight` set to 0 or an anchored root; choose and Studio-verify in the plan. Not verified here.]

### Other things the re-check turned up (affect the UI-SPEC; none re-opens a CONTEXT decision)

| # | Finding | Evidence | Consequence |
|---|---------|----------|-------------|
| N-1 | **`Enum.Font.Gotham`, `GothamMedium`, `GothamBold` "have been removed"; using them maps to the Montserrat family.** The UI-SPEC's Gotham fallback is therefore Montserrat, with different metrics, silently. Builder Sans is confirmed: `rbxasset://fonts/families/BuilderSans.json`; `BuilderSans`, `BuilderSansMedium`, `BuilderSansBold`, `BuilderSansExtraBold` enums exist. | `.../enums/Font.md`, `.../datatypes/Font.md` (`2026-11-04`) | Use Builder Sans Regular + Bold as the only fallback chain; delete the Gotham fallback from the plan. Whether the *family* ships Regular and Bold weights is still a Studio observation. |
| N-2 | **`GuiService.PreferredTextSize` (Settings > Text Size: Medium/Large/Larger/Largest) scales text even with `TextScaled = false`**, and is *not* applied only when `TextScaled` is on or a `UITextSizeConstraint` caps it. | `production/publishing/accessibility.md` (`2026-11-04T22:23:17Z`) | UI-SPEC says every strip string fits at 20 px bold with `TextScaled = false`. At Larger/Largest it may not. The strip-width check must be run at `Largest` in Studio (the scale factor is not documented; [ASSUMED] it is material), and the plan must choose: add `UITextSizeConstraint` (fixed max) so the single-line budget is guaranteed, or accept truncation. The 38-character cap and F4 are affected. |
| N-3 | **`StarterGui.ScreenOrientation` and `PlayerGui.ScreenOrientation` exist** (`LandscapeLeft/Right/Sensor`, `Portrait`, `Sensor`); `PlayerGui.CurrentScreenOrientation` reports the actual orientation. | `.../classes/StarterGui.md`, `PlayerGui.md`, `.../enums/ScreenOrientation.md` | D-28 stands (Creator Dashboard setting, human gate). But the rotate-prompt fallback can key off `CurrentScreenOrientation` instead of comparing viewport sizes, and a code-side `LandscapeSensor` request is available as belt and braces. Not verified that a script-side request overrides the dashboard. |
| N-4 | **Guard R4 confines `FireClient` and `FireAllClients` to `src/server/services/NetServer.luau`** and `FireServer` to `ClientNet.luau`. | `scripts/ci/zones.luau` `netOwners` | The UI-SPEC's privacy test wording ("the card publish module does not reference `FireAllClients`") is already enforced by lint, but it also means the card shell can *never* call `FireClient` itself. See Integration 2. |
| N-5 | `lune` is installed at `~/.rokit/bin/lune` and is not on `PATH` in this container. Full suite: **657 passed in 23.07 s** here. | `export PATH=$HOME/.rokit/bin:$PATH; lune run tests/run.luau` | Every command in Validation Architecture assumes that export. |

## Standard Stack

D-34 forbids any new third-party dependency and any UI framework. There is no npm/Wally in play. "Stack" here is the platform surface and the in-repo toolchain.

### Core (all built in or already pinned)
| Component | Version | Purpose | Why standard |
|-----------|---------|---------|--------------|
| Luau `--!strict` | per `rokit.toml` luau-lsp 1.70.1 | All code | CLAUDE.md platform constraint |
| Rojo | 7.7.1 [VERIFIED: `rokit.toml`] | Build/sync | Existing; do not bump (cannot `rokit install` here) |
| Lune | 0.11.1 [VERIFIED: `rokit.toml`] | Headless test runner | Existing `tests/run.luau` harness |
| stylua 2.6.0 / selene 0.32.0 | [VERIFIED: `rokit.toml`] | Format / lint | CI gates, hard-fail |
| `ScreenGui` `ScreenInsets = CoreUISafeInsets` | V-24 | Safe area | Documented recommendation |
| `UIScale`, `UICorner`, `UIStroke`, `UIGradient`, `TextButton`/`ImageButton` | built in | Card UI | D-34 |
| `TweenService` | built in | Card motion | [ASSUMED: standard; not re-fetched, not a debt row] |
| `ContextActionService` | built in, V-27 | Keyboard / gamepad accelerators with priority sinking | Documented |
| `UserInputService.LastInputTypeChanged` | built in | D-09 hint switching | Documented |
| `TextService:GetTextSize` | built in | Strip-width measurement (Studio only) | UI-SPEC test |
| `task.spawn` / `task.delay` / `task.cancel` | Luau task library | Flourish thread + cut-off | UI-SPEC flourish contract |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Own prediction reducer | Roblox Server Authority / IAS server input broadcast | Out of scope: `AuthorityMode` is a different networking model for character movement, not for a card game's discrete intents. Do not adopt. |
| `Dev*MovementMode` + `TouchControlsEnabled` | `GetControls()` | Rejected: undocumented and on a removal path (V-26) |
| Custom `InputContext` sink | CAS sink | IAS-native, documented; but does not stop touch `Scriptable` bindings. Use CAS now, revisit when the pin moves to `Enabled` |

**Installation:** none. **Version verification:** versions above read from `rokit.toml`; no registry applies (D-34).

## Architecture Patterns

### System Architecture Diagram

```
 CLIENT (phone / PC)                              SERVER
 -------------------                              ------
 tap / click / key
   |
   v
 ClientNet-fed ui (renderer) -- intents --> [Intent RemoteEvent]  (existing, client->server)
   ^   |  Draw{seq} | Pass{seq,cardId}              |
   |   v                                            v
   | pure reducer                               NetServer.OnServerEvent  (player -> userId)
   | auth + pending[]                               |
   | (predict now)                                  v
   |                                          Gateway.handle   isKnown -> phase gate -> bucket -> validate
   |                                                |  (reject: onReject -> CardTable.onGatewayReject -> private Sync)
   |                                                v
   |                                          dispatch(userId, "Pass", clean)
   |                                                |
   |                                                v
   |                                          CardTable (PURE) : userId -> seat (never from payload)
   |                                                |   IdleClock.noteAction / StallDetector.noteApply
   |                                                v
   |                                          Engine.apply(state, intent) -- synchronous, returns events
   |                                                |  (valve may append ValveForcedPass + Passed)
   |                                                v
   |                                          route(events):
   |                                            owner  : Sync{ackSeq, hand faces, counts, idleDeadlineUnix}  -> toPlayer
   |                                            affected: Notice{ForcedPass / Strike / Benched}             -> toPlayer
   |                                            seated : Table{events stripped of ValveForcedPass, depths}  -> toSeated
   |                                            seated : Stall cue                                          -> toSeated
   |                                                |
   |                                                v
   |   [Card RemoteEvent]  <-- Publisher{toPlayer,toSeated,toAll} implemented ONLY in NetServer (FireClient / FireAllClients, guard R4)
   |   (server->client, ordered with everything else: V-12)
   |<----------------- Sync / Table / Notice
   v
 reducer.onSync / onTable -> diff -> renderer tweens (return = D-11)

 10 Hz Heartbeat sweep (adapter) --> CardTable.tick(nowDeci) --> commands: AutoPass | Strike | Bench | StallCue
                                      (commands are applied OUTSIDE any apply, then published; rule 6)
 Completed event --> CompletionSink (stub in Phase 4; Phase 5 hunts) + server releases avatar + restore controls
```

### Recommended Project Structure
```
src/
├── server/
│   ├── core/
│   │   ├── CardTable.luau        # PURE. Name matters: FOUND-05 guards files named CardTable* (no cosmetics/shop import path)
│   │   ├── IdleClock.luau        # PURE. Per-seat deci deadline, strikes, D-15 legal-action gating
│   │   ├── StallDetector.luau    # PURE. D-20, independent of valve events
│   │   └── CardRouting.luau      # PURE. event -> audience table (the privacy decision as data)
│   └── services/
│       ├── NetServer.luau        # EDIT: add the Card server->client RemoteEvent + Publisher impl (sole FireClient owner)
│       └── CardService.luau      # NEW thin Roblox adapter: Heartbeat sweep, Player<->userId, avatar hold/release, Dev*MovementMode
├── shared/
│   ├── Card/                     # NEW PURE ZONE (add to scripts/ci/zones.luau pureZones)
│   │   ├── Faces.luau            # rank ladder, copy assignment, identity key, drawn-asset table, joker rule table
│   │   ├── Layout.luau           # pure rect arithmetic for the UI-SPEC geometry
│   │   ├── Prediction.luau       # reducer: auth + pending[], onSync/onTable/commit, watchdog
│   │   ├── Hints.luau            # input-kind map + hint/copy tables
│   │   └── Flourish.luau         # driver (injected clock + scheduler + registry)
│   ├── Config/
│   │   └── Card.luau             # NEW: strikes, AFK_WARN_SECONDS, FLOURISH_DURATION_SECONDS, tween durations, stall params, PENDING_TIMEOUT
│   └── Net/Manifest.luau         # EDIT: add Draw, Pass (phases = { "Round" })
└── client/
    ├── net/ClientNet.luau        # EDIT: add onCard(handler); keep FireServer here (R4)
    ├── ui/                       # NEW: Roblox-API-touching renderer ONLY (hand, piles, strip, callouts, Controls.luau)
    └── Main.client.luau          # EDIT: boot the card UI
tests/card/                       # NEW: see Validation Architecture
```
Rationale for `src/shared/Card/` as a **new pure zone**: client-side pure modules cannot require `src/shared` relatively (guard R6 crosses a mount) and cannot be required absolutely by Lune; putting the pure logic *in* `src/shared` lets both thin adapters use absolute paths and Lune specs use relative ones, exactly like `Manifest`/`Validate` today. Adding a directory to `pureZones` also brings the FOUND-06 no-Roblox-API lint with it, which is what makes the "pure" claim enforceable rather than promised. `zones.luau` states that additions are allowed and removals are not.

### Pattern 1: Publisher seam (answers the privacy question)
**What:** `CardTable` never touches a remote. It is constructed with `publisher: { toPlayer: (userId, kind, payload) -> (), toSeated: (kind, payload) -> (), toAll: (kind, payload) -> () }`. `NetServer` provides the real implementation (the only file allowed to say `FireClient`/`FireAllClients`); tests provide a recording fake. A constant `PRIVATE_KINDS = { Sync = true, Notice = true }` lives in `CardRouting`; the real `toAll`/`toSeated` **error** if called with a private kind, so the invariant is structural, not a convention.
**When to use:** every server-to-client message in this phase.
**Example:**
```lua
-- Source: project pattern (Gateway/NetServer split); guard R4 in scripts/ci/zones.luau
export type Publisher = {
	toPlayer: (userId: number, kind: string, payload: unknown) -> (),
	toSeated: (kind: string, payload: unknown) -> (),
	toAll: (kind: string, payload: unknown) -> (),
}
-- CardRouting: the audience is data, so a test can enumerate it.
local AUDIENCE = { Sync = "owner", Notice = "owner", Table = "seated", Stall = "seated", RoundStart = "seated" }
```

### Pattern 2: Commands out of a pure tick
**What:** `CardTable.tick(nowDeci)` returns a list of commands (`AutoPass{seat}`, `Strike{seat,n}`, `Bench{seat}`, `StallCue{}`); the adapter then calls `CardTable.applyIntent` for each, outside any other `apply`. Never schedule per-seat `task.delay` timers.
**When to use:** all time-driven behaviour. Matches `RoundLifecycle`/`RoundDriver` (injected clock, thin adapter) and rule 6.

### Pattern 3: Authoritative-snapshot + pending queue (client)
See Integration 4.

### Anti-Patterns to Avoid
- **Calling `FireClient` from the card module.** Fails guard R4 and defeats the recording-fake test.
- **Deriving "forced vs chosen" on the client by guessing.** `ValveForcedPass` precedes `Passed` in the engine's event list; the server must turn it into a private `Notice` and strip it from the public batch.
- **Sending `Completed.fifth` or any rank to non-holders** beyond what the public event is meant to show (the four retired faces are public by design; the fifth card's face is not).
- **Hashing or exposing engine `valve`/`hash` data.** `Types.luau` forbids hashes in client-bound events.
- **Passing `cause = "Completed"` to `Remove` from the shell.** `Engine.apply` *throws* on it (Engine.luau lines 289-306). Narrow the shell's parameter type to `"Disconnected" | "Benched"`.
- **Per-seat timers or yields inside the apply path** (rule 6).
- **A client-held timestamp used for anything but UI display** (rule 5). `seq` is a counter, not a clock.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Payload validation for `Draw`/`Pass` | Ad-hoc `type(x) == "number"` checks | `Validate.exactKeys` + `Validate.integer` | NaN/inf/extra-key/forbidden-type handling, and the Gateway returns a *clean copy* to the handler |
| Rate limiting | New counters in the shell | Existing `Bucket` via `RateLimits.byIntent` | Already clock-injected and NaN-proof (T-1-28) |
| Seat removal (disconnect, bench) | A second removal path | `Engine.apply({kind="Remove", seat, cause})` | Rule 8; routes cards to the successor; one op for all causes |
| Legality, completion, valve, forced pass | Any rule in the shell | `Engine.apply` | Fuzz-proven; the shell's whole job is to adapt |
| Auto-pass card choice | "Pass the worst card" | Uniform draw over the hand from an injected `Rng` | D-14 / `CardPool.AUTO_PASS_SELECTION`; the greedy choice zeroes the deviation the simulator measured |
| Round timing | A second clock | `os.clock()` floored to deciseconds for scheduling; `GetServerTimeNow()` only to publish a deadline outward | The two-clock discipline in `RoundDriver` |
| Suit pips from rotated Frames | Hand-built hearts/spades | Glyphs if Studio shows them; else an owner-uploaded 4-cell sprite sheet | UI-SPEC, shape distinctness for D-24 |
| Layout in the renderer | Pixel maths inside GUI code | The pure `Layout` module | It is the only way UX-01/UX-03 become headless assertions |
| Tween timing for flourish cut-off | Trusting the flourish to end | Driver-owned cancellable thread + injected scheduler | UI-SPEC D-32 contract |

**Key insight:** every place this phase is tempted to add logic to the Roblox-touching layer is a place a test can no longer reach it. Keep the Roblox layer to `Instance.new`, property assignment, tweens and remote wiring.

## Integration Mechanics (the seven questions)

### 1. The adapter seam: how a `Draw`/`Pass` intent travels, and the files

`ClientNet.send("Pass", {seq=n, cardId=id})` -> `Intent` RemoteEvent `FireServer(intentName, payload)` -> `NetServer`'s `OnServerEvent(player, intentName, payload)` calls `gateway:handle(player.UserId, ...)` -> `Gateway` order is `isKnown -> phase gate -> bucket -> validate -> dispatch (xpcall)` [VERIFIED: `Gateway.luau` lines 56-98] -> `deps.dispatch(userId, name, clean)` (the `handlers` table in `Main.server.luau`; today only `Ping`; "an intent with no handler errors") -> `CardService`/`CardTable.onIntent(userId, name, clean)` -> userId resolved to a SeatId via the table's own roster -> `Engine.apply(state, {kind="Pass", seat=seat, cardId=clean.cardId})` -> returned `events` fed to `CardRouting` -> `Publisher`.

**Create:** `src/server/core/{CardTable,IdleClock,StallDetector,CardRouting}.luau`, `src/server/services/CardService.luau`, `src/shared/Card/*`, `src/shared/Config/Card.luau`, `src/client/ui/*`, `tests/card/*`.
**Edit:** `src/shared/Net/Manifest.luau` (add `Draw`, `Pass`), `src/shared/Config/RateLimits.luau` (per-intent entries), `src/server/services/NetServer.luau` (second remote + `Publisher`; also route `onReject` for card intents to `CardTable.onGatewayReject`), `src/server/Main.server.luau` (handlers + composition + a minimal round-start stub, since the real phase machine is "Phase 4/6 work" per its own comment), `src/client/net/ClientNet.luau` (`onCard`), `src/client/Main.client.luau`, `scripts/ci/zones.luau` (pure zones; `secretNames`; optionally `netOwners.OnClientEvent`), `MANUAL-CHECKS.md`, `NEEDS_HUMAN.md`.

**Proposed schemas (Claude's discretion, within rule 7):**
```lua
-- Source: src/shared/Net/Manifest.luau pattern. phases = { "Round" } for both.
Draw = { phases = { "Round" }, validate = Validate.exactKeys({ seq = Validate.integer({ min = 0, max = 2 ^ 31 }) }) },
Pass = { phases = { "Round" }, validate = Validate.exactKeys({
	seq = Validate.integer({ min = 0, max = 2 ^ 31 }),
	cardId = Validate.integer({ min = 1, max = 64 }),   -- 4*12 + 1 = 49 cards max at 10 players; 64 is a sanity cap, not a rule
}) },
```
`exactKeys` already rejects `seat`, `to`, `target`, `index` as `UnknownKey`, so rule 7 is structural, and `tests/net/manifest.spec.luau` should assert exactly that for each forbidden key name. `seq` is a client-chosen correlation counter, not a timestamp, not a seat, not an index (rule 5 and 7 untouched).

**Not in the payload, resolved server-side:** the seat (from `userId` via the roster) and the pass target (`Ring.pass` resolves `next` inside `apply`).

**Scaffolding the phase needs but nobody owns:** with Phase 5/6 absent, something must set the phase to `"Round"`, build `seatPlayerIds` (players minus one hider, `SeatOrder` ordering is Phase 6) and start a `CardTable`. Recommend a deliberately dumb `RoundStub` (3+ players present, first player hides, roster order = join order) labelled as Phase 6's to replace. Completion events go to an injected `CompletionSink` whose Phase 4 implementation only logs/releases the avatar.

### 2. Per-player replication (CARD-13) and how it is tested headlessly

**Mechanism:** the Publisher seam above. Guard R4 means `FireClient`/`FireAllClients` exist in exactly one file, so the question "is any private data broadcast?" reduces to "which `Publisher` method does `CardTable` call for each message kind?", and that is a pure function of `CardRouting`. Defence in depth: `NetServer`'s real `toAll`/`toSeated` throw on `PRIVATE_KINDS`.

**What is private, what is public:**

| Message | Audience | Contents |
|---------|----------|----------|
| `Sync` | owner only (`toPlayer`) | `ackSeq`, my hand as `{cardId, rank, copy}` list in arrival order, my inbox count, my downstream count, `idleDeadlineUnix?` |
| `Notice` | affected player only | `ForcedPass{cardId}`, `Strike{n, autoPassedCardId?}`, `Benched` |
| `Table` | all seated (`toSeated`) | batch of `Drew{seat,cardId}`, `Passed{seat,to,cardId}`, `Completed{seat, faces=[{cardId,rank,copy} x4]}`, `SeatRemoved{seat,cause}` plus `depths[seat]`; **`ValveForcedPass` stripped** |
| `Stall`, `RoundStart` | all seated | cue flag; roster, joker mode |

Ids carry no rank (`Types.luau` header: `rankOf` is the shuffled permutation), so public `Drew`/`Passed` leak nothing about faces. `Completed` publicly carries the four retired faces on purpose (UI-SPEC: they turn face-up at the seat). `rankOf` is never reassigned after the deal [VERIFIED: grep `rankOf[...] =` over `src/server/engine`: no matches], so a face record never changes mid-round.

**Headless test:** a `RecordingPublisher` capturing `(method, userId?, kind, payload)`. With 3 seated players run a scripted deal + draw + forced pass; assert (a) every `Sync` is `toPlayer` to its owner only and that player 2's recorder contains none of player 1's `Sync`; (b) the forced-pass `Notice` goes to exactly the affected player; (c) the public `Table` batch for the same step contains an ordinary `Passed` and contains **no** `ValveForcedPass`; (d) no payload sent via `toSeated`/`toAll` contains a `rank` field for a card not in a `Completed.faces`. Mutation: replace the fake's `toPlayer` routing with broadcast, or make the router send `Sync` via `toSeated`; test must fail. Also assert `NetServer`'s guard: calling `toAll("Sync", ...)` throws (testable by extracting the pure guard function and exercising it directly).

**Not testable headlessly:** that `NetServer` really maps `toPlayer` to `FireClient(player)`; that is a four-line adapter, covered by guard R4 plus M-check "two real clients, one sees only its own hand" (fold into the Studio multi-client session).

### 3. The `copy` assignment

Confirmed stable, deterministic, and engine-free: for each natural rank `r`, collect the ids `i` with `rankOf[i] == r`, sort ascending, `copy = position (1..4)`; jokers get `copy = 1..jokers` (one joker shipped). Because `rankOf` is fixed per round [VERIFIED above], the table is computed once at deal, held by the shell, and never recomputed. The mapping depends only on `rankOf`, not on `seatCount` or inbox order. It leaks nothing: within a rank, relative id order is uniformly random (ids are shuffled deck positions), and a client only ever receives the record for cards it holds.
```lua
-- Source: derived from Types.luau (CardId = deck position; rankOf = shuffled permutation)
local function assignCopies(rankOf: { number }, ranks: number): { number }
	local copyOf, seen = {}, table.create(ranks, 0)
	for id = 1, #rankOf do
		local r = rankOf[id]
		if r == 0 then copyOf[id] = 1
		else seen[r] += 1; copyOf[id] = seen[r] end  -- ids visited ascending, so copy = ascending-id order
	end
	return copyOf
end
```
Tests: for 200 seeds over N=3..10 via `Pool.deal`, each natural rank's copies are exactly a permutation of `{1,2,3,4}`; result is identical on a second call; every id has a copy. Assert the loop actually ran (count == `totalCards`), so the property cannot pass vacuously.

### 4. Prediction and reconciliation

**State the client keeps (pure, `src/shared/Card/Prediction.luau`):**
- `auth`: the last `Sync` (hand as ordered `{cardId, rank, copy}`, `inbox`, `downstream`, `ackSeq`, `idleDeadlineUnix`).
- `pending`: FIFO of `{seq, kind="Draw"} | {seq, kind="Pass", cardId, sentAtClientTime}`.
- `selectedCardId?` (UI-only; never sent; cleared silently if that card leaves, per UI-SPEC).
- `nextSeq`.
- Derived `display = fold(pending, auth)`: `Pass` removes `cardId` from the hand and adds 1 to `downstream`; `Draw` (only if display hand is 4 and `inbox > 0`) subtracts 1 from `inbox` and appends a face-down placeholder `{cardId = nil}`.

**Rules (all testable):**
1. `commit` (second tap on the selected card) appends to `pending`, bumps `nextSeq`, returns the intent to send `{name, payload}`. A `Pass` can only name a `cardId` present in the *display* hand with a non-nil id, so a card the client has not yet been told about (a just-drawn placeholder) is un-passable. This is exactly the UI-SPEC's "information-limited, not a gate" and satisfies rule 7 with no hand index anywhere.
2. `onSync(s)`: `auth = s`; drop every pending entry with `seq <= s.ackSeq` (**cumulative ack**: anything at or below the ack that the new `auth` does not reflect was rejected); re-fold. The diff between old `display` and new `display` is what the renderer animates: a card present before and absent now is a Return (D-11) *only if* it had been predicted away; a card newly present is an Arrival/flip.
3. `onTable(batch)`: folds public events into depths and into "someone passed me a card" counters; own-seat `Drew`/`Passed` echoes are ignored for the hand (the owner's hand comes only from `Sync`).
4. A `ValveForcedPass` or AFK auto-pass arrives as a private `Notice` plus a `Sync` whose hand lacks a card the player never committed: the reducer treats it as a server-initiated removal (Forced out state), clears selection if it was that card, and does not touch `pending`.
5. **Watchdog:** a gateway-level rejection (`RateLimited`, `WrongPhase`, validate failure) never reaches the card core, so its `seq` is never acked individually. If `pending` is non-empty and the oldest `sentAt` is older than `Config.Card.PENDING_TIMEOUT_SECONDS` (suggest 1.0 s, a UI timing value, not scoring), the reducer asks the adapter to send a harmless `Resync{seq}` intent (or: `onGatewayReject` also pushes a `Sync` with the current `ackSeq`). A later cumulative ack then resolves everything older. Without this, a rate-limited tap leaves a card visibly gone forever, which is the exact "visible glitch" criterion 2 forbids.
6. D-12: engine rejects, shell rejects (no seat, benched) and gateway rejects all resolve identically for the user: the card returns, no text.

**Server side of the contract:** after *every* Draw/Pass attempt by a seated player the server sends that player a `Sync` with `ackSeq = seq` (accepted or rejected: same message shape, so D-12 identity holds at the wire level too), and pushes a `Sync` on any seat-affecting change not caused by their own intent (forced pass, auto-pass, bench).

**Public-event volume (for the planner's budget):** a healthy round is ~380 actions over a 300 s cap; peak start-up ~20 actions/s table-wide. One `Table` batch per server step per client, coalesced at <= 10 Hz, plus one `Sync` to the actor, is well below the documented 500 req/s platform ceiling (that ceiling is client-to-server; no server-to-client figure is documented) [ASSUMED: no server-to-client throttle is a concern at this volume].

**Headless test design:** a `FakeLink` driving the reducer and a stub server step through a virtual clock with configurable latency 150 and 300 ms each way. Scenarios: happy pass; reject (hand not five); gateway-drop + watchdog; valve after draw (events `Drew, ValveForcedPass, Passed` for the same seat while a Pass is pending); two rapid passes with the first rejected (cumulative ack must roll back both effects correctly or keep the second); out-of-order Sync older than `auth` (ignore by `ackSeq` monotonicity). Invariants checked after every step: `display == auth` when `pending` is empty; emitted intents contain only keys `seq`/`cardId`; no `Pass` names a nil or absent id; hand never exceeds 5 or drops below 4 in display. The "visible within one frame" and "smooth return" judgements are device checks, but the *model* guarantees that the display changes in the same call as `commit`.

### 5. The AFK clock (D-15) and the deciseconds boundary

**Where bookkeeping lives:** beside the engine, in `IdleClock` (pure, `src/server/core/`). Per live seat: `{ deadlineDeci: number?, strikes: number }`. The engine is untouched.

**Legal-action predicate (the thing most likely to be wrong):** `legal(seat) = (#hand == 4 and #inbox >= 1) or (#hand == 5)`. The core reads this from engine state *after every successful apply* for every seat whose hand/inbox could have changed (the actor, the receiving seat of a pass, the seat after a removal), not on a timer. Transition rules:
- becomes legal (was not): arm `deadline = nowDeci + AUTO_PASS_DECI`;
- stays legal after the seat's **own accepted action**: re-arm (a real action resets `strikes` to 0, D-17);
- becomes illegal: disarm (pause). Because a legal-to-illegal transition occurs only through the seat's own action or a forced/auto pass, "pause" and "reset" coincide in practice; after a valve forced pass the seat is again legal and gets a fresh window.
- removed seat: drop its entry.

**Rounding rule at the boundary (rule 5):** `AUTO_PASS_DECI = math.floor(CardPool.AUTO_PASS_MAX_SECONDS * Round.DECISECONDS_PER_SECOND + 1e-9)` = 80, so conversion can never exceed the ceiling, and a spec-lock test asserts `AUTO_PASS_DECI <= AUTO_PASS_MAX_SECONDS * 10` and `== 80` at the shipped config. `nowDeci = math.floor(os.clock() * 10)` exactly as `RoundDriver`. Honest consequence of flooring a continuous clock and sweeping at 10 Hz: the realised window is roughly **7.9 s to 8.2 s of wall time**, an unavoidable quantisation of +-0.1 s on arming and up to +0.1 s of sweep lateness; this is below the simulator's model noise and below the platform's own jitter. The locked constraint is on the configured value; if the owner reads the ceiling as a hard wall-clock bound, use 79 deci. [ASSUMED interpretation; surfaced in Open Questions]

**What expiry does:**
- hand = 5: pick a card **uniformly at random from the hand** via an injected `Rng` (never "worst card", D-14), issue `Pass` as a server-originated intent through the same `applyIntent` path, `strikes += 1`, publish a private `Notice{Strike}`.
- strikes reach 3: issue `Remove{seat, cause="Benched"}` (the one generic removal), publish `Notice{Benched}`, release the avatar, hide the hand overlay (the UI-SPEC copy is the only thing this phase shows; spectate/leave is Phase 6).
- hand = 4 with a non-empty inbox: **see Open Question 1**; recommended: strike only, no card movement.

**Client countdown:** the server publishes `idleDeadlineUnix = Workspace:GetServerTimeNow() + remainingSeconds` only on arm/re-arm inside `Sync`, never fed back (two-clock rule, `RoundDriver` lines 9-11). The client shows the cue when `deadlineUnix - GetServerTimeNow() <= AFK_WARN_SECONDS (2.0)`.

**Tests:** fake `nowDeci`; table-driven transitions; a seat at 4/empty never accrues idle time across 1000 deci; hand-5 seat expires at exactly +80; any accepted action resets strikes; third strike emits exactly one `Bench` and the engine then reports the seat not live; the **uniformity** of the auto-pass choice (5-card hand, 5000 draws from a seeded Rng, each card within tolerance) with a mutation that substitutes a deterministic "worst card" and must fail; spec-lock on `AUTO_PASS_SELECTION == "uniform-random-from-hand"` and `ANTI_LIVELOCK_VALVE == true`.

### 6. D-22 of `01-CONTEXT.md`: phase gate before token bucket

**Recommendation: keep the order. Do not reorder the Gateway. Add a cheap repeat-offender counter in the `onReject` path, and throttle the *logging*.**

| | Keep (phase gate first) | Charge a token on wrong-phase |
|---|---|---|
| Server cost per wrong-phase message | O(1), allocation-free (`Gateway` header) | A bucket lookup/refill, and it allocates a per-user per-intent entry on first use |
| What it buys an attacker | Zero tokens consumed, but also nothing gained: the message is dropped and nothing is dispatched | Nothing; just a slower attacker |
| Legitimate-player effect | None | Spends tokens at phase edges (a `Pass` landing just after the round ends is `WrongPhase`); small, but it is a real cost to honest players for no security gain |
| Cost to the change | None | Reorders a documented "nothing may be reordered" check chain and rewrites its spec-lock tests |
| The actual exposure | `onReject` currently `warn`s once per rejection (`Main.server.luau`): a `WrongPhase` flood is a **log-spam / CPU** vector, throttled only by the platform's ~500 req/s | Same exposure |

So the real defect is the unthrottled `warn`, not the order. Fix: in the reject sink keep a per-user `{count, windowStartDeci}`, log the first N per window and then a single summary, emit a telemetry counter, and (Phase 8) kick on a sustained streak. This is a ~20-line pure function with a clean test and no Gateway change. Record the decision in the plan; mark `01-CONTEXT.md` D-22 as "reviewed in Phase 4: kept, with log throttling".

### 7. Headless testability: honest split

**Can be tested in Lune (and should be, with mutation):**
- `Layout` arithmetic: four viewports (844x390 notched, 640x360, 932x430, 1920x1080), inset rect containment, `scale = clamp(min(W/760, H/350), 0.85, 1.5)`, every hit rect >= 48 physical px after scale, `TableRegion >= 58%` with the 300 px guard, lifted card clear of the strip, fan-to-pile gap >= 24, no overlap between the two piles and the fan. This covers UI-SPEC acceptance tests 1 and 2 fully, and the *arithmetic half* of 3.
- `Prediction` reducer and the link simulation at 150/300 ms (virtual time).
- Privacy via recording `Publisher`; `CardRouting` audience table; stripping `ValveForcedPass`.
- `IdleClock`, `StallDetector` (including "no valve event, still stalls"), AFK selection uniformity, deci rounding.
- `Faces`: copy assignment, identity-key injectivity (50 faces: 12 ranks x 4 + joker x 2 modes), drawn-asset distinctness (reads the renderer's own pip table), exhaustive `JokerMode` map, rank ladder stability.
- `Hints`: input-kind map exhaustive over the `UserInputType` names, the hint table has a string for every (state x input) cell, each <= 38 chars, a conservative width proxy (38 x 12 px = 456 <= strip width).
- Flourish driver (a)-(f) with `FakeScheduler`/`FakeClock` (both exist in `tests/harness/`).
- Manifest schemas for `Draw`/`Pass`, including the forbidden-key list.
- `CardTable` integration against the real `Engine` for N = 3..10 with scripted bots: events routed, `Remove` causes, no yield, same final state hash as driving the engine directly.
- Guards: new pure zones registered, `rankOf` added to `secretNames`, FOUND-05 covers the new `CardTable*` file.

**Genuinely needs Studio or a phone (cannot be moved to a unit test):**
- Camera projection of the 3D table bounds into TableRegion (UI-SPEC test 3) - needs `Camera:WorldToViewportPoint` on real geometry.
- That a GUI at a given `AbsoluteSize` really occupies >= 48 physical px on glass, thumb reach, and `CoreUISafeInsets` on a notched device.
- Suit glyphs rendering at 16 px; Builder Sans weights; greyscale legibility of spade vs club (the pure test proves *distinct assets*, not *distinguishable pixels*).
- Tween feel: "gone within one frame", "smooth return, no teleport" at real latency.
- Control hide/restore (V-26) on PC, phone and gamepad, under both IAS settings.
- Audio, flourish look, starting-gun feel, text at `PreferredTextSize = Largest`, landscape lock, real multi-client privacy.
- Of the five success criteria, **1 and 4 are mostly machine-checkable; 2, 3, 5 are device-dependent** (2 and 5 each have a machine-checkable core).

## Runtime State Inventory

Not applicable: this is a greenfield build phase, not a rename/refactor/migration. (Place settings it adds - landscape lock, IAS pin - are listed as human gates under Open Questions and Environment Availability.)

## Common Pitfalls

### Pitfall 1: Believing `GetControls()` is the current API
**What goes wrong:** the control-hide silently no-ops on opted-in places and breaks for everyone when the engine default flips (early 2027).
**Why it happens:** it is a 2019-era DevForum convention, never documented.
**How to avoid:** the `Controls` seam and layered mechanism above; Studio matrix under both IAS settings; pin the property.
**Warning signs:** `GetControls` is `nil`; thumbstick still visible; avatar walks away from the table.

### Pitfall 2: Client-only "seated"
**What goes wrong:** a cheat client re-enables controls and hunts before completing a set.
**How to avoid:** the server holds the avatar; client hiding is cosmetic. Test: server-side hold exists independent of any client message.

### Pitfall 3: Restore race (D-30)
**What goes wrong:** finisher is held for a beat, or on touch the restored thumbstick is dead/stuck (community reports above); a key held during the disabled period does not resume.
**How to avoid:** restore from the same frame as overlay destruction; measure in the Studio matrix; keep `restore()` idempotent; if the stuck-touch bug reproduces, re-assert by toggling `TouchControlsEnabled` false then true on the next frame (a recorded fallback, not a first resort).

### Pitfall 4: Unacked rejected intent leaves a phantom
**What goes wrong:** a rate-limited or wrong-phase tap never reaches the card core, so the predicted removal is never rolled back.
**How to avoid:** cumulative `ackSeq` plus the pending-age watchdog (Integration 4).

### Pitfall 5: Calling `Remove{Completed}` or treating it as bench/disconnect
`Engine.apply` throws by design. Narrow the shell's type; test that the bench path uses `"Benched"` and the disconnect path `"Disconnected"`.

### Pitfall 6: Assertions that cannot fire
**What goes wrong:** the project's own record is ~22 such assertions in Phase 2 and 9 in Phase 3.
**How to avoid:** the Validation Architecture rules below (non-vacuity counts, clean control beside every mutation, mutation by injected dependency). Budget it per gate.

### Pitfall 7: Subprocess "trap" tests inflate CI
**Evidence:** measured here: `tests/traps` = 5.7 s for 15 cases because each shells out to stylua/selene/rojo; `tests/sim` = 5.9 s; `tests/engine` = 1.5 s; `tests/core` = 0.06 s. **Avoid adding subprocess-based gates in this phase**; express new gates as in-process pure checks (guard fixtures for `check-guards` run in ~0.5 s total).

### Pitfall 8: Text-size accessibility breaks the single-line strip
See N-2. Test at `Largest` in Studio and decide on `UITextSizeConstraint`.

### Pitfall 9: Font fallback is Montserrat, not Gotham
See N-1.

### Pitfall 10: `FireClient` in the card module
Fails guard R4 (and the right design is the `Publisher`).

### Pitfall 11: Handler ordering assumed to mean completion ordering
V-12 guarantees handler *start* order. A handler that yields (e.g., `WaitForChild`) can be overtaken. Keep the client's `OnClientEvent` handler synchronous and non-yielding, and `ClientNet.getRemote()` resolved before connecting (the existing `WaitForChild("Intent")` is a yield point: resolve both remotes once at boot, before any gameplay message can arrive; messages arriving with no connected handler are queued in order up to a bounded limit, then dropped with an error).

### Pitfall 12: `Drew` for own seat treated as the face
Public `Drew` carries an id only. The face arrives only in the owner's `Sync`.

## Code Examples

### Deci conversion with the ceiling guard
```lua
-- Source: src/server/services/RoundDriver.luau (nowDeci) + src/shared/Config/CardPool.luau
local Round = require(ReplicatedStorage.Shared.Config.Round)   -- adapter only; the pure core receives the number
local AUTO_PASS_DECI = math.floor(CardPool.AUTO_PASS_MAX_SECONDS * Round.DECISECONDS_PER_SECOND + 1e-9)
assert(AUTO_PASS_DECI <= CardPool.AUTO_PASS_MAX_SECONDS * Round.DECISECONDS_PER_SECOND)
```

### EngineConfig value built from CardPool by absolute path (adapter)
```lua
-- Source: CardPool.luau header; Pool.poolConfig is "the only place that subtraction is written"
local CardPool = require(ReplicatedStorage.Shared.Config.CardPool)
local config = {
	ranks = seatedSeekers + CardPool.EXTRA_RANKS,   -- prefer Pool.poolConfig(n, k, j, mode) rather than inlining
	jokers = CardPool.JOKERS,
	jokerMode = CardPool.JOKER_MODE,
	antiLivelockValve = CardPool.ANTI_LIVELOCK_VALVE,
}
```
Use `Pool.poolConfig` rather than the inline subtraction (the header forbids computing `n - 1` elsewhere).

### Control hiding behind one seam (never GetControls)
```lua
-- Source: GuiService.md (TouchControlsEnabled), ContextActionService.md (BindActionAtPriority/Sink)
local GuiService = game:GetService("GuiService")
local CAS = game:GetService("ContextActionService")
local Controls = {}
local bound = false
function Controls.hide()
	GuiService.TouchControlsEnabled = false
	if not bound then
		bound = true
		CAS:BindActionAtPriority("SpoonsSinkMove", function() return Enum.ContextActionResult.Sink end, false,
			Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D)
	end
end
function Controls.restore()
	GuiService.TouchControlsEnabled = true
	if bound then bound = false; CAS:UnbindAction("SpoonsSinkMove") end
end
return Controls
```
(The server-side `Dev*MovementMode` toggle and the avatar hold live in `CardService`.)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `require(PlayerModule):GetControls():Disable()` | IAS player scripts; `Dev*MovementMode = Scriptable`, `TouchControlsEnabled`, sinking `InputContext`/CAS | Full release 2026-06-11; default flips ETA early 2027; legacy removed ETA mid 2027 | V-26; Pin the flag, abstract behind `Controls` |
| `UserInputService.ModalEnabled` | `GuiService.TouchControlsEnabled` | Already deprecated in docs | Do not use `ModalEnabled` |
| Cross-remote ordering "not guaranteed" | RemoteEvents ordered across instances | Documented as of 2026-11-04 | Simplifies design; still prefer one envelope |
| `Enum.Font.Gotham*` | Removed; maps to Montserrat. `BuilderSans` is current | Per `Font.md` | Drop the Gotham fallback |
| Default `SignalBehavior` = Immediate | "Will eventually" be Deferred | Pending | Write order-independent handlers |

**Deprecated/outdated:** `UserInputService.ModalEnabled`; `Enum.Font.Gotham*`; the `GetControls()` idiom.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Rojo 7.7.1 cannot set `Workspace.PlayerScriptsUseInputActionSystem` via `$properties` (property newer than the pinned reflection DB) | V-26 detail | Low: if it can, the pin becomes code instead of a human gate |
| A2 | The server-side avatar hold can be done with `Humanoid` speed/jump zeroing or an anchored root; the exact mechanism is unverified | V-26 "what must be enforced" | Medium: the plan must choose and Studio-verify; wrong choice = avatar can slide or physics jitters |
| A3 | `PreferredTextSize = Largest` increases `TextScaled=false` text materially (docs state it scales, not by how much) | N-2 | Medium: strip strings may overflow; mitigated by the Studio check |
| A4 | No server-to-client throttle concern at ~200 small messages/s table-wide | Integration 4 | Low-Medium: docs document only the client-to-server limit; coalescing to <= 10 Hz is the mitigation |
| A5 | Reading D-13's "must not exceed 8.0" as a bound on the configured value, with +-0.1-0.2 s wall-clock quantisation acceptable | Integration 5 | Low: use 79 deci if the owner wants a strict wall-clock bound |
| A6 | `TweenService` behaviour as relied on by UI-SPEC durations | Standard Stack | Low |
| A7 | Studio's network-latency simulator exists for the 150-300 ms check (setting name not re-verified) | Validation Architecture | Low: fall back to an artificial delay in the client send wrapper under a debug flag |
| A8 | Server-originated `Pass` (auto-pass) is applied through the same `applyIntent` path as client intents without needing the gateway | Integration 5 | Low |

## Open Questions

1. **What does hand-4 expiry do? (needs owner confirmation; unmodelled in Phase 2)**
   - Known: D-15 runs the idle clock when "hand at 4 with a non-empty inbox (can draw)"; UI-SPEC has a `Draw a card: 2` countdown. The Phase 2 simulator modelled the AFK deadline **only at hand = 5** ("A DRAW carries no deadline", `Simulator.luau` lines 713-716), so auto-draw behaviour was never measured.
   - Unclear: what the shell does at a hand-4 expiry.
   - Recommendation: **strike only; no card moves; restart the window.** Reason: an auto-draw can complete a set for an absent player, which would hand them a completion and the kept placement bonus (see PROJECT scoring: "0 find points but a kept bonus") for doing nothing, i.e. an exploit. The cost is that an AFK drawer stalls the table until benched (~24 s at 3 x 8 s); the UI-SPEC copy needs a hand-4 strike line without "Auto-passed a card". If the owner prefers circle-keeps-moving over exploit-resistance, the alternative is auto-draw followed by the random auto-pass, with the completion forfeited. Decide before planning the strike copy.
2. **Who holds the avatar, and how?** Nothing in the tree seats or releases avatars (Pitfall 2 / A2). The plan needs a task and a Studio check; this is server code in the Roblox adapter.
3. **Pin `PlayerScriptsUseInputActionSystem` to Disabled or Enabled now?** Recommend Disabled for Phase 4 verification and a pre-launch re-run under Enabled; owner/Studio action.
4. **PreferredTextSize**: add `UITextSizeConstraint` (guaranteed single line) or allow truncation? Plan decision after the Studio check.
5. **Resync mechanism**: `Resync{seq}` intent vs server push on `onGatewayReject`. Either satisfies the reducer contract; pick one in planning (the intent adds a manifest entry and bucket; the push needs `NetServer` to forward rejects of card intents to the card core).
6. **Widening the fuzz `k` grid to {1,2,3} and extending the CI subset** (deferred ideas): cost unmeasured; `tests/engine` runs in 1.5 s today, but the `k=3` grid and N>=7 cells are the heavy ones. Only do it if the added time is measured and stays within the budget below.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| lune | All headless tests | yes, at `~/.rokit/bin/lune` (not on PATH) | 0.11.1 | `export PATH=$HOME/.rokit/bin:$PATH` |
| stylua / selene / luau-lsp / rojo | CI gates | yes, same directory | 2.6.0 / 0.32.0 / 1.70.1 / 7.7.1 | — |
| `create.roblox.com` docs (`.md`, search) | Research / future re-checks | yes | — | — |
| `devforum.roblox.com` | Research | yes via `curl`; **not** via `WebFetch` | — | `curl` + `.json` |
| `rokit install` | New tools | **no** (api.github.com 403) | — | None; D-34 forbids new deps anyway |
| Roblox Studio | M-checks, camera projection, control matrix, tween feel | **no** | — | Human gate |
| Real phone (notched, landscape) | UX-01/UX-03, thumb reach | **no** | — | Human gate (UI-SPEC acceptance 4) |
| Controller | Gamepad column (V-27) | no | — | Studio Controller Emulator (documented), then a real pad |
| Creator Dashboard | Landscape lock (D-28), audio ids, sprite asset | owner only | — | Human gate |

**Missing with no fallback (block "done", not "start"):** Studio, a real phone, Creator Dashboard actions. All are expressed as manual checks (M-11 onward; M-10 is the last used) and `NEEDS_HUMAN.md` rows.
**Missing with fallback:** none that block execution.

## Validation Architecture

> `workflow.nyquist_validation` is `true` in `.planning/config.json`. Every command assumes `export PATH=$HOME/.rokit/bin:$PATH`. Use `--root`, not `--filter engine`: the `--filter` label collides across suites (deferred item D-02-09-2).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Project harness `tests/harness/Test.luau` (`t.test/equal/deepEqual/truthy/throws/fuzz`) on Lune 0.11.1 |
| Config file | `tests/run.luau` (discovers `**/*.spec.luau`; exits non-zero on failing, unloadable, empty or filter-matching-nothing runs) |
| Reusable fakes | `tests/harness/FakeClock.luau` (seconds), `FakeScheduler.luau`, `Fuzz.luau`; add `tests/harness/RecordingPublisher.luau` |
| Quick run command | `lune run tests/run.luau -- --root tests/card` |
| Full suite command | `lune run tests/run.luau` (657 pass in 23.07 s here, baseline for this phase) |

### Phase Requirements to Test Map
| Req ID | Behaviour | Test Type | Automated Command | File Exists? |
|--------|-----------|-----------|-------------------|--------------|
| CARD-02 | Select then commit emits exactly one `Pass{seq,cardId}`; selection follows tap; tap-off clears | unit (reducer) | `lune run tests/run.luau -- --root tests/card` (`prediction.spec`) | Wave 0 |
| CARD-13 | Owner-only `Sync`; public batch has depths only; no rank outside `Completed.faces` | unit (recording publisher) | same (`privacy.spec`) | Wave 0 |
| CARD-14 | Display changes in the commit call; rollback on reject; watchdog; cumulative ack at 150/300 ms virtual latency | unit (link sim) | same (`prediction.spec`) | Wave 0 |
| CARD-15 | A single tap never emits an intent; no debounce exists (D-02/D-03 lock) | unit + spec-lock | same | Wave 0 |
| CARD-16 | D-15 gating, 80 deci, 3 strikes, reset on action, bench via `Benched`, uniform choice, D-13/D-14 constants | unit | same (`idle.spec`) | Wave 0 |
| CARD-17 | Flourish hard-capped at 1.5 s, yield cancelled, input fires during it, scan catches Active/escaped instances | unit (mocked clock) | same (`flourish.spec`) | Wave 0 |
| CARD-19 | 50-face identity key injective; distinct drawn asset per key; copy permutation; joker map exhaustive | unit | same (`faces.spec`) | Wave 0 |
| UX-01 | All hit rects >= 48 physical px at 4 viewports and the 0.85 scale floor | unit (`Layout`) | same (`layout.spec`) | Wave 0 |
| UX-02 | `Controls.hide/restore` call order and idempotence against a fake; no `GetControls`/`PlayerModule` reference in `src/` | unit + grep guard | same (`controls.spec`) + `check-guards` | Wave 0 |
| UX-03 | Interactive rects inside the inset rect; `ScreenInsets` constant is `CoreUISafeInsets` | unit | same (`layout.spec`) | Wave 0 |
| UX-04 | Input-kind map exhaustive; hint table complete and <= 38 chars | unit | same (`hints.spec`) | Wave 0 |
| (cross) rule 7 | `Draw`/`Pass` reject `seat`/`to`/`target`/`index`/NaN/extra keys | unit | `lune run tests/run.luau -- --root tests/net` | extend `manifest.spec` |
| (cross) rule 1 | `CardTable*` has no path to cosmetics/shop | guard | `lune run scripts/ci/check-guards.luau` | existing, new file covered by filename |
| (cross) rule 3 | `rankOf` not referenced in `src/client` or `src/shared` | guard | same | edit `zones.luau` `secretNames` |
| (device) criteria 2, 3, 5 | Feel, thumb reach, safe area, control restore, pips, greyscale, audio | manual | `MANUAL-CHECKS.md` M-11.. | Wave 0 (write) |

### Observable signals and who can see them
| Signal | Machine-checkable? | Sampling |
|--------|--------------------|----------|
| Layout rect arithmetic, hint strings, face tables, reducer state, publisher call log, deci deadlines, flourish teardown time on a fake clock | Yes | every commit |
| `check-guards` zones / secret names / R4 / R6 / FOUND-05 | Yes | every commit and wave merge |
| Pending-vs-ack convergence at 150 and 300 ms | Yes (virtual time) | every commit; also under a seeded fuzz of reject patterns |
| Camera projection of table bounds; GUI physical size on glass; tween smoothness; control restore; glyph rendering; greyscale legibility; text at Largest; audio; flourish look | **No: human-gated** | once per wave that changes UI, and at the phase gate |
| V-35 (human reaction model) | No: needs playtest (M-07) | phase 6/8 |

**Sampling rate rationale.** Pure tests run in milliseconds, so run all of `tests/card` on every task commit. The only failure mode that sampling can miss is a *time-dependent interleaving*, so the prediction and idle tests use fixed virtual-time scripts plus a seeded fuzz of {latency in 150..300 ms, reject mask, forced-pass injection} with a bounded iteration count (target <= 1 s, see budget).

### Mutation tests (budgeted per gate, mandatory)
For every row, the test must (1) include a **clean control** that passes with the real implementation, (2) include a **non-vacuity assertion** (count of cases/viewports/faces/players/rejects exercised), and (3) express the mutation by **injecting a broken dependency** rather than editing source (the pattern used in `valve.spec` "MUTATION" cases).

| Gate | Mutation that must turn the gate red |
|------|--------------------------------------|
| Privacy: face record private | Publisher fake routes `Sync` through `toSeated`/`toAll` |
| Privacy: forced pass private | Router sends `ValveForcedPass` in the public batch; or sends the `Notice` to the wrong player |
| Privacy: no rank leak | `Table` payload gains a `rank` for a non-retired card |
| NetServer guard | Real `toAll("Sync")` does not throw |
| 48 px floor | `STEP` 60 -> 44; scale floor 0.85 -> 0.7; hit strip width shrunk by the 12 px overlap |
| Safe area | Layout ignores the inset; hand rect extends under the inset |
| TableRegion >= 58% | HandZone 144 -> 170 |
| Lifted card vs strip | lift 16 -> 20 (the checker's F1 case) |
| Greyscale: key injective | collapse two pip shapes in the data |
| Greyscale: drawn asset | point two pip ids at the same asset |
| Joker map exhaustive | add a third `JokerMode` string; test must fail until mapped |
| Copy assignment | skip the ascending sort / reuse a copy index |
| D-15 idle gating | clock also runs at hand 4 / empty inbox; or runs at hand 4 only |
| 8.0 s ceiling | `AUTO_PASS_DECI` 80 -> 81 |
| Strike reset | an accepted action does not reset strikes |
| Bench path | bench issues `Remove` with cause `Completed` (engine throws) or bypasses `Remove` |
| D-14 selection | auto-pass picks the lowest-rank card (greedy) |
| Stall independence (D-20) | detector keyed on `ValveForcedPass`; must fail the "stuck, valve silent" case |
| Prediction: rollback | `onSync` does not drop acked pending; watchdog never fires |
| Prediction: rule 7 | commit emits a hand index or a `to` key |
| Prediction: placeholder | `Pass` allowed for a nil-id placeholder |
| Flourish: cut-off | remove the teardown timer -> (a) fails; arm the cut-off after `play` -> (b) fails |
| Flourish: scan | an `Active` GuiObject / an instance outside `ctx.root` must be caught; a scan that never runs must fail the control |
| Hints | delete one cell of the (state x input) table |
| Manifest | add `seat`/`index` as allowed keys |
| Controls | `restore()` not called on `Completed`; `GetControls` string present in `src/` |

### Sampling Rate
- **Per task commit:** `lune run tests/run.luau -- --root tests/card` (target <= 3 s) plus `lune run scripts/ci/check-guards.luau`.
- **Per wave merge:** full `lune run tests/run.luau` plus stylua/selene/analyze as in `ci.yml`.
- **Phase gate:** full suite green, then the manual matrix M-11..M-1x, before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `tests/card/{layout,faces,hints,prediction,privacy,idle,stall,flourish,controls,cardtable}.spec.luau` - cover the table above.
- [ ] `tests/harness/RecordingPublisher.luau` - shared fake for privacy and integration.
- [ ] `scripts/ci/zones.luau` - add `src/shared/Card` to `pureZones`; add `rankOf` to `secretNames`; consider `netOwners.OnClientEvent = ClientNet`; consider `guardedNamePrefixes` entries `Flourish`, `CardHud` so the client driver and UI have no path to cosmetics/shop (UI-SPEC requires a require-graph assertion; this reuses the existing mechanism, a one-line change).
- [ ] `MANUAL-CHECKS.md` rows M-11.. and matching `NEEDS_HUMAN.md` rows: M-11 control hide/restore matrix (V-26); M-12 real-phone landscape (48 px on glass, thumb reach, notched safe area, Largest text); M-13 prediction feel at 150-300 ms; M-14 greyscale render of all 50 faces; M-15 landscape lock + IAS pin (Creator Dashboard / place settings); M-16 audio ids, pip sprite, font weights; M-17 three-player starting-gun playtest (also supplies M-07 evidence).

### Test-runtime budget (live concern)
Baseline 23.07 s (this container) against the original ~20 s target already overshot twice. Measured costs: pure engine tests are cheap (1.5 s for 138 cases); **subprocess traps are the expensive kind (5.7 s for 15)**. Plan for Phase 4: all new specs in-process and pure; target **<= +3.0 s** total, i.e. suite <= ~26 s locally. Allocation: layout/faces/hints/privacy/flourish/controls <= 0.5 s combined; `prediction` fuzz <= 1.0 s; `idle` + `stall` <= 0.5 s; `cardtable` integration (<= 50 scripted rounds at N in {3,6,10}, roughly 380 actions each) <= 1.0 s. Add a per-spec elapsed print or assertion so the budget is enforced rather than hoped for. Do not widen the fuzz `k` grid or the CI N-subset in this phase unless its marginal cost is measured first and fits the allocation (Open Question 6). No new `lune`/`stylua`/`selene` subprocess gates.

## Security Domain

`security_enforcement` is not set to false in `.planning/config.json` (absent = enabled).

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Platform identity (`Player.UserId` from `OnServerEvent`) |
| V3 Session Management | no | — |
| V4 Access Control | **yes** | Seat derived server-side from the Player; engine `NotYourCard`/`SeatNotLive`; private-only delivery of hands |
| V5 Input Validation | **yes** | `Validate.exactKeys` + `Validate.integer`; Gateway passes a clean copy |
| V6 Cryptography | no | None; the engine Rng is for fairness, not secrecy; **seed it from a non-guessable source** (do not seed with a small sequential counter; `Rng.new` header notes small-seed weakness) |
| V8 Data Protection | **yes** | Hand/face data per-player only; `rankOf` never client-visible; no hashes in client-bound events |
| V11 Business Logic | **yes** | Rate limiting, idle/bench logic cannot be abused for a free completion (Open Question 1) |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Forged `cardId` of another seat | Tampering/EoP | Engine `NotYourCard`; server resolves seat from Player |
| Replay after seat removal | Tampering | Engine `SeatNotLive` |
| Client names a target or index | Tampering | `exactKeys` rejects the key (`UnknownKey`); spec-lock test |
| Reading others' hands from replication | Information disclosure | Hands exist only server-side; faces go `toPlayer` only; `rankOf` in `secretNames` |
| Broadcast of a private message by a later edit | Information disclosure | `Publisher` guard throws; guard R4 confines the Roblox calls; mutation-tested |
| Wrong-phase / flood spam | DoS | Gateway order + per-intent bucket; **log throttling** (Integration 6); platform ~500/s ceiling |
| Client re-enables controls to leave the table | EoP (gameplay) | Server-side avatar hold; client hiding is cosmetic |
| AFK player farms a placement bonus through auto-draw | Business logic | Strike-only at hand 4 (recommended) |
| Spoofed or huge `seq` | Tampering | Bounded integer; used only for correlation/ack |
| Exploit reading `Drew` ids to infer ranks | Information disclosure | Ids are shuffled deck positions; no rank info |
| `Remove{Completed}` injected by wiring bug | Tampering | Engine throws; shell type excludes it |

## Sources

### Primary (HIGH confidence): fetched 2026-11-05, all `last_updated: 2026-11-04`
- `https://create.roblox.com/docs/scripting/events/remote.md` - delivery guarantees (V-12), throttling pointer
- `https://create.roblox.com/docs/reference/engine/classes/RemoteEvent.md` - ~500 req/s throttle (V-34)
- `https://create.roblox.com/docs/scripting/events/deferred.md` - SignalBehavior (V-13)
- `https://create.roblox.com/docs/reference/engine/classes/GuiService.md` - `TouchControlsEnabled`, `SelectedObject`, `GuiNavigationEnabled`
- `https://create.roblox.com/docs/reference/engine/classes/UserInputService.md` - deprecated `ModalEnabled`, `PreferredInput`, `LastInputTypeChanged`
- `https://create.roblox.com/docs/reference/engine/classes/ContextActionService.md` - `BindAction`, `BindActionAtPriority`, Sink/Pass
- `https://create.roblox.com/docs/reference/engine/enums/DevComputerMovementMode.md`, `DevTouchMovementMode.md`, `classes/Player.md` - Scriptable, server-only setting
- `https://create.roblox.com/docs/reference/engine/classes/Workspace.md`, `StarterPlayer.md`, `enums/RolloutState.md` - `PlayerScriptsUseInputActionSystem`
- `https://create.roblox.com/docs/input/input-action-system.md` - InputContext Priority/Sink, Controller Emulator
- `https://create.roblox.com/docs/reference/engine/enums/Font.md`, `datatypes/Font.md` - Gotham removed, BuilderSans
- `https://create.roblox.com/docs/production/publishing/accessibility.md` - `PreferredTextSize`
- `https://create.roblox.com/docs/ui/position-and-size.md` - default controls occupy bottom corners; thumb zones (V-25: no numeric minimum anywhere searched)
- `https://create.roblox.com/docs/reference/engine/enums/ScreenOrientation.md`, `classes/StarterGui.md`, `PlayerGui.md`
- Repository code read directly: `Gateway.luau`, `NetServer.luau`, `ClientNet.luau`, `Manifest.luau`, `Validate.luau`, `Bucket.luau`, `Engine.luau`, `Types.luau`, `RoundDriver.luau`, `CardPool.luau`, `RateLimits.luau`, `Round.luau`, `scripts/ci/zones.luau`, `scripts/sim/Simulator.luau`, `tests/run.luau`, `default.project.json`, `rokit.toml`; suite timings measured by running them.

### Secondary (MEDIUM): DevForum, fetched via `curl .../t/<id>.json`
- `https://devforum.roblox.com/t/4678416` - staff release post, IAS + player-script rollout phases and the `GetControls()` warning (2026-06-11)
- `https://devforum.roblox.com/t/4889933` - IAS default-controls disable report, staff reply (2026-09-23/24)
- `https://devforum.roblox.com/t/4681909` - community migration guide (2026-06-14)
- `https://devforum.roblox.com/t/400699` - canonical "disable controls" thread with 2026 posts saying `GetControls()` is gone

### Tertiary (LOW): community bug reports, single reporter each, not re-tested
- `https://devforum.roblox.com/t/2947221` (held key after re-enable), `/t/3677974` (touch stuck after re-enable), `/t/2794501` (JumpButton frozen after `TouchControlsEnabled=false`)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - nothing new; toolchain read from `rokit.toml`.
- Architecture: HIGH for transport, publisher seam, idle clock, reducer contract (derived from code read); MEDIUM for the exact wire shapes (marked discretion).
- Control hiding (V-26): MEDIUM-LOW - the old method's removal path is documented by staff; every replacement is documented but unproven here and one has an unresolved bug report.
- Verification Debt: V-12/V-13/V-24 HIGH; V-25 MEDIUM (negative claim); V-27 MEDIUM; V-34 MEDIUM; V-35 open by nature.
- Pitfalls / validation architecture: HIGH for what is headless; device claims are explicitly LOW until M-checks run.

**Research date:** 2026-11-05
**Valid until:** 2026-11-19 (14 days). The IAS rollout is fast-moving (an ETA of early 2027 for the default flip) and the V-26 findings should be re-checked at plan execution time and again before launch.
