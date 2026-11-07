# Phase 4: Live Card Table - Context

**Gathered:** 2026-11-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 4 delivers the **live card table**: the Roblox shell around the already-proven pure
engine, and the PC + mobile UI that makes it playable.

In scope:
- The server-side card shell — the `Draw` / `Pass` intent surface through the existing typed
  gateway, the adapter that builds an `EngineConfig` from `src/shared/Config/CardPool.luau`,
  calling `Engine.apply`, and publishing the resulting events outward.
- Client prediction and reconciliation (CARD-14).
- AFK auto-pass and benching (CARD-16), inside the Gate G1 constraints.
- The card UI on PC and on a phone in landscape: hand, both piles, other seats' pile depths,
  card faces, hints (CARD-02, CARD-13, CARD-15, CARD-19, UX-01..04).
- The four-of-a-kind starting-gun moment as a fixed-duration hook (CARD-17).

Requirements: CARD-02, CARD-13, CARD-14, CARD-15, CARD-16, CARD-17, CARD-19, UX-01, UX-02,
UX-03, UX-04.

Explicitly NOT in scope (other phases own these):
- The hunt, glint, claim and scoring (Phase 5). Completion events are stubbed here so Phase 4
  runs without Phase 5.
- Round-end conditions, hider rotation, joiners/leavers, scoreboard, podium (Phase 6).
- Purchasable deck skins and deal-animation flourishes (Phase 7, CARD-18). Phase 4 builds the
  seam they plug into, not the content.
- First-time-player teaching, the device matrix sweep and rate-limit tuning on live data
  (Phase 8, UX-05..07).

</domain>

<decisions>
## Implementation Decisions

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

### Added 2026-11-05 after phase research (owner-decided)

Phase research surfaced two questions nothing had decided. Both were put to the owner and both
took the recommended option.

- **D-35: when the AFK clock expires at hand 4 (owing a DRAW), the player takes a STRIKE and
  NOTHING is drawn.** No auto-draw, ever.
  **Why this is not symmetry for its own sake:** four of a kind is checked **only on draw**
  (CLAUDE.md, Core Mechanic Reference). An auto-draw could therefore hand an absent player a
  completion — and with it the four-of-a-kind bonus and the kept placement bonus. The game would
  be paying someone for being away, which is the sharpest possible version of the fairness line
  PROJECT.md draws everywhere else.
  **Why starvation is not a counter-argument:** a seat that never draws hoards cards in its inbox,
  starving the ring. That self-corrects — at three strikes (D-17) the bench fires through the
  generic seat-removal path, which routes the whole hoarded inbox to the successor, so those cards
  rejoin circulation within roughly 24 seconds at the 8.0 s deadline (D-13). The engine's
  anti-livelock valve carries the table-level stall job independently (amendment A7).
  **Note for the planner:** the Gate G1 sweep modelled the auto-pass at hand 5 ONLY, so no
  simulator result speaks to hand-4 behaviour at all. Do not cite the sweep as evidence for this.
  The rejected alternative "auto-draw only when it cannot complete" would also have put
  hand-inspection logic in the shell, outside the pure engine, and modelled nothing the sweep ran.

- **D-36: the status strip stays exactly one line, enforced by a `UITextSizeConstraint`.**
  Phase research found `GuiService.PreferredTextSize` scales text even when `TextScaled = false`,
  so a player on the **Largest** accessibility setting would otherwise overflow the single-line
  strip that carries the AFK countdown and the strike warnings.
  **The accepted cost, stated plainly:** a player who chose Largest text gets smaller text here
  than they asked for. That is an accessibility compromise in the exact place strike warnings
  appear, and it was chosen over the alternatives because wrapping to two lines forces a third
  re-derivation of the HandZone budget (the strip height is what keeps the lifted card 4 px clear),
  and truncation would cut the clause that says what is about to happen — "Strike 2 of 3. One more
  benches you." truncated is worse than no message.
  **Planner:** every strip string must be measured at the **Largest** setting, not only the
  default. This is additional to checker FLAG F4, which found the strip ~6 px short of its own
  longest strings at default size.

- **Not decided here — carried as a human gate.** The IAS flag
  `Workspace.PlayerScriptsUseInputActionSystem` must be **pinned explicitly** rather than left to
  the platform default (which flips in early 2027), but the value belongs with whoever does the
  Studio pass and can observe the control-hiding layers actually working. Record it in
  `MANUAL-CHECKS.md` / `NEEDS_HUMAN.md` with the default of keeping legacy behaviour until the
  D-29 replacement is proven. See the V-26 entry in `.planning/STATE.md` for why this exists at
  all: `GetControls()` is undocumented, unsupported and slated for removal mid-2027.

### Added 2026-11-05 after pattern mapping (verified against the guard source)

Pattern mapping found two conflicts between the artefacts and the lint guards as they actually
behave. Both verified by reading `scripts/ci/zones.luau` and `scripts/ci/check-guards.luau`
directly, and both are binding on the planner.

- **D-37: copy assignment is SERVER-SIDE. The identifier `rankOf` must never appear anywhere in
  `src/shared/` or `src/client/` — comments included.**
  `04-RESEARCH.md` proposes `assignCopies(rankOf, ...)` in `src/shared/Card/Faces.luau`, while
  `04-VALIDATION.md`'s rule-3 gate adds `rankOf` to `zones.secretNames`. **These cannot both
  hold.** Guard R5 is a *raw plain-text substring scan* over the whole file
  (`check-guards.luau`: `string.find(sf.text, name, from, true)`), so it matches inside comments
  and string literals, not just code. Adding `rankOf` to `secretNames` while a shared module names
  it — even in a comment explaining the rule — fails the build.
  **Resolution:** the `copy` (1..4 → suit) assignment lives server-side, in `CardTable` or
  `CardRouting`. `src/shared/Card/` may receive an already-assigned `copy` but must never see or
  name `rankOf`. There are currently **zero** hits in either tree, so the rule starts clean —
  do not be the first.

- **D-38: `guardedNamePrefixes` must be extended, or most of the card shell gets NO FOUND-05
  check.** `zones.luau` has `guardedNamePrefixes = { "Scoring", "CardTable", "SpoonPlacement" }`
  and matches on the **file basename prefix**, so naming the core `CardTable.luau` covers exactly
  that one file. `CardRouting`, `CardService`, `IdleClock`, `StallDetector`, `Flourish` and the
  HUD modules would have **no import-path check to cosmetics or shop code at all**.
  This is Non-Negotiable Rule 1 — "what makes no-pay-to-win true rather than promised" — so a
  silent coverage hole here is the exact failure the rule exists to prevent. **The planner must add
  the new prefixes to `zones.luau` in the same wave that creates the files**, and a test must prove
  the new prefixes are actually covered (a fixture file under a new prefix with a forbidden import
  must fail the guard). Adding a prefix is a one-line change; discovering the gap in Phase 7 is not.

### CORRECTIONS 2026-11-05 — D-37 and D-38 were both wrong (orchestrator error, found by the plan-checker)

The plan-checker probed the guards empirically instead of reasoning about them, and both decisions
I added after pattern mapping were wrong. I verified its findings myself before accepting them.
**The corrected text below governs; the original D-37/D-38 wording above is superseded.**

- **D-37 CORRECTED: the identifier `rankOf` must not appear in `src/shared/` or `src/client/` CODE
  OR STRING LITERALS. The "comments included" half was FALSE and is withdrawn.**
  I claimed R5 scans raw file text and therefore matches comments. It does not.
  `check-guards.luau` sets `sf.text = stripComments(raw)` (line 324) and R5 scans `sf.text`, so a
  `rankOf` appearing **only in a comment is invisible to R5**. I had read `string.find(..., true)`
  and taken `plain = true` to mean "raw file text"; it means "no pattern matching". Two different
  things.
  **Verified empirically:** `lex.stripComments` applied to a file whose only `rankOf` is in a
  comment leaves no `rankOf` behind — the probe printed `comment-only rankOf survives strip: false`.
  **What is still true and still enforced:** `sf.text` **keeps string literals**, so `rankOf` in
  code or in a string is caught. That is the leak that matters; a comment naming the identifier
  leaks nothing. **Do not add a raw-text comment-inclusive scan** to rescue the original claim —
  it would buy no safety and would make every file that documents the rule fail the build.
  **Consequence for plan 04-02:** its fixture C puts `rankOf` in a comment only and asserts the
  guard goes red. It cannot. Put `rankOf` in code or a string literal.

- **D-38 WITHDRAWN: do NOT extend `guardedNamePrefixes`. FOUND-05 already covers the gameplay
  cores, and extending it to the renderer layer would break Phase 7 by design.**
  Two independent errors in the original:
  1. **The extension is mostly redundant.** `check-guards.luau:341` is explicit: *"Roots for R2/R3:
     guarded-name files under src/, then **every file in a pure zone**."* So `CardTable`,
     `CardRouting`, `IdleClock`, `StallDetector` and `RejectThrottle` in `src/server/core` are
     **already** FOUND-05 roots by location, whatever they are named — and `Faces`, `Hints`,
     `Layout`, `Prediction`, `Flourish`, `Controls` become roots the moment `src/shared/Card` is
     registered as a pure zone (plan 04-04). Nine of the ten proposed prefixes add nothing.
  2. **The one prefix that would add something — `Card` — is actively harmful**, for two separate
     reasons. First, guarded roots get **R3** as well as R2, and R3 bans the substring `os.` in
     comment-stripped text *including string literals*. R3's own source comment says that
     over-strictness is deliberate "in a zone whose whole point is having no clock". `CardService`
     legitimately needs a clock, and — verified empirically — the needle also matches ordinary
     identifiers: the probe printed `pos.X trips the os. needle: true`, so `pos.X` or
     `anchorPos.Y` in any `Card*` client file would fail the build. Second, and more
     fundamentally: **Phase 7 requires the card UI to import cosmetic data.** The dealer's deck
     skin and the deal animation play to the whole table (PROJECT.md, CARD-18); the renderer is
     precisely the layer that must touch cosmetics. Forbidding it would make Phase 7 impossible as
     designed.
  **What Rule 1 actually protects:** the modules that decide *outcomes* — `Scoring`, `CardTable`,
  `SpoonPlacement` — not the layer that draws them. The existing prefix list is correctly scoped.
  **What the planner must do instead:** add no prefixes, and **prove the coverage that already
  exists** — a fixture under `src/server/core` with a forbidden cosmetics import must fail R2 with
  the unmodified `zones.luau`. That is a real proof of a real guard, unlike the original plan's
  fixture A, which the checker observed goes red with or without the prefixes and therefore proved
  nothing.

### Owner decision at the phase gate, 2026-11-07

- **D-39: the deadline stays at 80 deci (8.0 s), and CARD-16's bound is restated as applying to the
  CONFIGURED value rather than the realised wall-clock window.** `AUTO_PASS_DECI` remains 80; no
  code, test or config changes.

  **What is true and now written down.** `nowDeci = floor(10 * clock)`, so expiry fires when
  `floor(10t) >= floor(10c) + D` and elapsed is `(D - frac(10c))/10`. Flooring is therefore
  **one-sided-SHORT** and can never lengthen the window. Confirmed by a 200,000-phase simulation and
  independently re-derived twice. At `D = 80` detection lands in **[7.900, 8.000]** and, with up to
  0.1 s of 10 Hz sweep lateness, the realised window is **7.9007 to 8.0996 s** — so a *literal*
  reading of "must not exceed 8.0 s" is exceeded by up to 0.1 s.

  **Why the owner kept 80.** 80 deci *is* exactly 8.0 s as configured, and it is the value D-13 chose
  and **every Gate G1 cell ran at** — so keeping it preserves the correspondence between the shipped
  game and the 320,000 gated rounds that justified it. The alternative (79 deci) genuinely **closes**
  the overshoot rather than halving it, but it moves off that number and costs more than the plan
  estimated: five test sites including a `WHOLE_LINE` argument pin the plan missed, plus the call site
  itself, which cannot be a one-argument tweak because its first argument is the config constant
  `config_lock` locks — needing a derived expression or a literal 7.9, a reworded `assert` and two
  comments.

  **The scale, which is why this is not a gamble.** The G1 sweep recorded **zero** auto-passes at this
  deadline (2 at 5.0 s, 58 at 3.0 s, 38,516 at 1.5 s). The 0.1 s therefore bounds an event the sweep
  never once observed firing.

  **Recorded honestly, not resolved away:** research assumption A5's "±0.1 s" is **wrong** and should
  read "−0.1 s on detection, +0.1 s from the sweep". `79` deci remains the one-line fix if a real
  playtest ever shows the realised window matters, and it is carried as **D-04-13** for Phase 8
  alongside **V-35** (whether the bot reaction-time model represents humans), which is the open half
  of why 8.0 s was chosen at all.

### Owner decision 2026-11-07 (second)

- **D-40: a seat that has left the card phase STILL receives the public round traffic, so a finisher
  keeps seeing later "X is out" callouts.** Confirms the shipped behaviour; **no revert.**

  **What this settles.** The WR-05 code-review fix made `onSeatRemoved` stop calling `unseat`, so
  `seated` now means "dealt into this round" rather than "still holding cards". A seat removed for
  **any** cause — `Completed`, `Benched` or `Disconnected` — stays in the audience until `endRound`
  and therefore continues to receive `RoundEnd`, `Depths` and later `Table` batches. **D-31 is read
  as covering every seat dealt into the round**, not only seats still at the table.

  **Why it is the right reading.** A finisher is out in the map hunting while the table plays on, and
  "someone else just left the table" is live competitive information to them — there are two fewer
  spoons than players, so every departure shortens their odds. D-31's callout exists to carry exactly
  that pressure. It also matches the client, which is **built to keep its place after its hand is
  gone** (D-30): the server unseating a finisher contradicted the client's own design and leaked their
  `place` (Workspace stacks, flourish container, callout GUI) until a `RoundStart` they might never
  receive.

  **Privacy is unaffected.** `Table`, `Depths` and `Stall` are **public** kinds — depths are counts,
  never identities (CARD-13). A removed seat gains no private data by staying in the audience; the
  per-player `Sync` and `Notice` remain owner-only.

  **Consequence to watch at M-17:** a finisher's HUD now receives traffic after their hand is gone,
  so the callout overlay must outlive the hand's destruction — which is why `CardHud` grew
  `newOverlay` (04-17). **IN-04 is the known rough edge there:** the overlay loses its relayout once
  the HUD is destroyed at completion. Still deferred, and now the clearest candidate to fix, because
  D-40 makes that path ordinary rather than rare.

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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The Gate G1 constraints on this phase (read FIRST — two of them are easy to break silently)
- `src/shared/Config/CardPool.luau` — the shipped pool and the two constraints on Phase 4
  (`AUTO_PASS_MAX_SECONDS`, `AUTO_PASS_SELECTION`). Its header comment explains WHY each is not a
  tuning knob; read the comment, not just the values.
- `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md` — sections 1 (verdict and
  residual), 4 and 4b (the valve, firing rates, bar-sensitivity ladder), 5 (the auto-pass deadline
  firing curve: 0 auto-passes at 8.0 s, 2 at 5.0 s, 58 at 3.0 s, 38,516 at 1.5 s).
- `.planning/phases/02-card-engine-and-pacing-simulator/02-CONTEXT.md` — amendments A3 (seatCount
  means seated seekers), A7, A7-CORRECTION, A8 (the valve's measured load-bearing role and the
  honest limits of the claim).

### Phase scope and requirements
- `.planning/ROADMAP.md` § "Phase 4: Live Card Table" — goal, the five success criteria, and the
  "Note on CARD-16" block naming both inherited constraints and the `ValveForcedPass` affordance.
- `.planning/REQUIREMENTS.md` — CARD-02, CARD-13..CARD-17, CARD-19, UX-01..UX-04. CARD-16's entry
  carries the G1 constraint inline.
- `.planning/PROJECT.md` § "2. Card phase" — the authoritative mechanic; § "Constraints" for the
  platform-parity and server-authority rules; the Key Decisions table rows on the valve, the
  auto-pass deadline and the auto-pass selection rule.

### Decisions this phase inherits
- `.planning/phases/01-foundations-contracts-and-spec-lock/01-CONTEXT.md` — D-11 (card table as a
  place, 9 seat anchors), D-14 (camera locked), D-15 (finisher stands and runs), D-20 (phase
  vocabulary), **D-22 (the gateway check-order question flagged for this phase)**.
- `CLAUDE.md` — Non-Negotiable Rules 3, 5, 6, 7 and 8 all bind this phase directly.

### Findings carried into Phase 4 — do not rediscover
- `.planning/STATE.md` § "Phase 2 verification findings carried into Phase 4" — the valve's
  detection limit (3 of 15 replayed stalls armed with zero firings), the open triage question,
  the fuzz suite's `k` grid being {1,2} and never covering the shipped `k = 3`, the CI subset
  regressing only N = 3/6/10 while every observed residual stall was at N >= 7, and the
  overstated "firing rate equals valve-off stall rate to three decimals" claim.
- `.planning/STATE.md` § "Notes that would otherwise be lost" — the float-seconds/deciseconds
  boundary, the ~8% valve firing rate, and the start-up ramp figures.
- `.planning/phases/02-card-engine-and-pacing-simulator/deferred-items.md` — D-02-09-2 (the
  `--filter engine` label collision) and D-02-09-3 (suite runtime) both bite anyone touching the
  test suite here.

### Verification Debt rows this phase must re-check before planning
- `.planning/research/SUMMARY.md` § "Verification Debt" — **V-12** (same-remote ordering
  guarantee for `RemoteEvent`; cross-remote NOT guaranteed — test in Studio), **V-13** (signal
  deferred vs immediate default), **V-24** (`ScreenInsets` enum values and behaviour), **V-25**
  (Roblox mobile minimum target size; 48 px is used, 44 px is a third-party guideline), **V-26**
  (disabling default controls via `PlayerModule:GetControls():Disable()`), **V-27**
  (`ContextActionService` mobile button behaviour, `GuiService.SelectedObject` for gamepad).
  Also **V-34** (rate-limit numbers, LOW confidence) and **V-35** (whether the bot
  reaction-time distribution represents humans — the open half of D-13's justification).
  None of these has been upgraded above its stated confidence. Record what was confirmed or
  changed; do not raise a confidence level without re-fetching a primary source.

### Code the phase builds on
- `src/server/engine/Types.luau` — `Intent`, `Event`, `Reject`, `State`, `EngineConfig`. The
  `ValveForcedPass` event's comment states it may cross the network and carries no hash.
- `src/server/engine/Engine.luau` — the whole public surface is `newRound` and `apply`.
- `src/server/core/Gateway.luau` — the locked check order and its rejection codes.
- `src/shared/Net/Manifest.luau` — the intent registry; new intents go here and nowhere else.
- `src/shared/Net/Validate.luau` — the validation vocabulary.
- `src/server/services/NetServer.luau` — the single `Intent` RemoteEvent and its `Deps`.
- `src/client/net/ClientNet.luau` — the client's only send path.
- `src/server/services/RoundDriver.luau` — the two-clock rule (`os.clock` for scheduling and
  scoring, `GetServerTimeNow` only for publishing a deadline outward; never mixed).
- `src/shared/Config/RateLimits.luau`, `src/shared/Config/Round.luau`,
  `src/shared/Config/Limits.luau`.
- `MANUAL-CHECKS.md` and `NEEDS_HUMAN.md` — where D-28's orientation setting and any real-phone
  check must be recorded.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- **`Engine.newRound` / `Engine.apply` are the only engine entry points**, both pure and
  synchronous, returning `{ ok, events, reject }`. The shell's job is to call `apply` and publish
  `events`; it must not reimplement any rule.
- **The typed gateway already exists end to end** — `NetServer` (Roblox edge) delegating to the
  pure `Gateway` (check order, token bucket, validation, dispatch inside `xpcall`). Phase 4 adds
  manifest entries and a dispatch handler; it does not build transport.
- **`Validate` provides the whole validation vocabulary** (`exactKeys`, `integer`, finiteness,
  reject codes). New intent schemas compose from it.
- **`Bucket` is the per-client token bucket**, already wired, parameterised from
  `RateLimits.forIntent`.
- **`RoundLifecycle` / `RoundDriver`** give exactly-once round end with an injected clock, and
  establish the two-clock discipline this phase must follow.
- **`Types.Event` is already the full event vocabulary** — `Drew`, `Passed`, `Completed`,
  `SeatRemoved`, `ValveForcedPass`. Every UI affordance in this phase keys off one of these.

### Established patterns
- `--!strict` everywhere; every check hard-fails in CI (01-CONTEXT D-01). No advisory tier.
- **Guard rule R6: no relative require across the `src/server` / `src/shared` mount boundary.**
  Shared modules are fetched by absolute DataModel path. Both `NetServer` and `RoundDriver`
  document this; the Phase 4 adapter must do the same for `CardPool`.
- **The pure zone** (`src/server/engine/`, and the pure cores under `src/server/core/`) may not
  touch a Roblox API, nor `coroutine`, nor `os.` — lint-enforced. All new UI and transport code
  lives outside it.
- Config values are **parameters, never inlined constants**, so tuning is a one-file change.
- Behaviour lives in a pure core with a deliberately thin Roblox adapter beside it
  (`Gateway`/`NetServer`, `RoundLifecycle`/`RoundDriver`). Phase 4's card shell should follow the
  same split so its logic stays headless-testable.
- Spec-lock tests: a decision that must not drift gets asserted by a test (`Manifest.PHASES`,
  the `Violation` order, the drift test between `Gateway.PHASES` and `Manifest.PHASES`). D-02,
  D-13, D-14, D-15 and D-24 are all candidates.

### Integration points
- **`src/client/` is nearly empty** — `Main.client.luau` sends one `Ping` and prints. There is no
  UI code, **no UI framework, and no package manager in the tree** (`rokit.toml` has only rojo,
  stylua, selene, luau-lsp, lune; there is no `wally.toml` and no `Packages/`). Any UI library
  would be a new dependency and a new decision; vanilla Roblox UI is the status quo.
- `default.project.json` mounts `src/client` to `StarterPlayerScripts`, and `Workspace` carries
  `$ignoreUnknownInstances`, so Studio-authored geometry survives a sync.
- Seat anchors and the card-table anchor already exist in the map contract and are validated
  (Phase 3: 21 spots, 9 seats). The 3D stacks of D-19/D-26 attach to those anchors.
- `Manifest.intents` currently holds only `Ping`; `RateLimits.byIntent` only `Ping`.

### Warnings from the record
- **Nine assertions structurally incapable of firing were found in Phase 3 alone, and ~22 in
  Phase 2.** The pattern recurs even when everyone is looking for it. **Budget mutation-testing
  for every gate in this phase** rather than treating it as optional.
- **CI timing will need revisiting here** — Phase 4 adds the most test weight of any remaining
  phase, and the suite is already at ~30 s against an original "~20 s" target.

</code_context>

<specifics>
## Specific Ideas

- The owner's exact words on the tap gate, after first choosing an animation-gated guard and then
  reconsidering: *"Honestly remove the 0.5s, make it instant."* The intermediate position was a
  half-second lift that still allowed quick double taps — which is self-cancelling, and
  resolving it is what produced D-02 and D-03.
- Real playing-card ranks and suits were chosen over bespoke symbols specifically because this is
  *the* card game Spoons and players already know what four of a kind means.
- The dealer needs no marker because the dealer's left pile **is** the remaining deck, so their
  stack is physically the tallest object on the table. The role is true by geometry rather than
  by a flag someone has to keep in sync.
- Pile depth precision is asymmetric on purpose: an exact count on your own two piles, stack
  height alone for the other seats. Your left-pile depth is the most actionable number you have;
  nine floating numbers on a phone is clutter.

</specifics>

<deferred>
## Deferred Ideas

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

---

*Phase: 04-live-card-table*
*Context gathered: 2026-11-05*
