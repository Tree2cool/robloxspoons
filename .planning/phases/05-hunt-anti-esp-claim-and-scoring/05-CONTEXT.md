# Phase 5: Hunt, Anti-ESP, Claim and Scoring - Context

**Gathered:** 2026-11-10
**Status:** Ready for planning
**Mode:** Auto-answered. The four grey areas below were put to the owner on 2026-11-09 as tables of
recommendations; the owner did not answer them before saying "do 4.1 then 5 overnight". Every
recommendation is taken as given here, unchanged from what was shown, so the owner is accepting
something they have already read rather than something invented after they went to bed. Each
decision records why. The two genuinely NEW questions that arose after that conversation are marked
**OPEN - OWNER** and were given the conservative answer.

<domain>
## Phase Boundary

A seeker who completes four of a kind can hunt server-hidden spoons that a cheat client cannot
read, claim one without races, and be scored correctly - closing the loop into a playable vertical
slice (Gate G3).

In scope: HUNT-01..08, SCORE-01..05.

Explicitly NOT in scope:
- Hider placement UI, the hide phase, match lifecycle, rotation, joiners and leavers, the
  scoreboard and podium (Phase 6). This phase runs on **auto-filled spoons** from Phase 3's
  validated default spots, which is deliberate: the anti-ESP model is the most expensive thing in
  the project to retrofit, so the hunt is built on data spoons BEFORE a hider UI exists to create
  them (`SUMMARY.md`, "Anti-ESP before the hide UI").
- Cosmetics, spoon skins, the shop (Phase 7). **Gameplay code must never import them** - rule 1.
- Movement-threshold tuning on real latency (Phase 8). This phase ships a first pass.

</domain>

<decisions>
## Implementation Decisions

### Already settled - DO NOT RE-OPEN

These are locked in `PROJECT.md` or by prior owner confirmation. They are listed so the planner
does not spend a question on them:
- **The scoring formulas.** Four-of-a-kind bonus 1000, -100 per place after. Find points = seconds
  remaining on the 5:00 cap x 10. Never finding a spoon = 0 find points, bonus kept. Seeker ceiling
  4000. The worked examples in the ROADMAP's success criteria are the test vectors.
- **The hider denominator** (Open Question 7, confirmed by the owner): a **fixed 300 s**, unfound
  spoons counting as the full 300, on the same timeline as find points.
- **The time source.** `os.clock()` floored to integer deciseconds is the scoring clock;
  `GetServerTimeNow()` is for client countdowns ONLY and is never fed back in. Established by
  Phase 4 in `CardService` and `RoundDriver`; a third expression of it is how the two drift apart.

### Area 1 - Anti-ESP and the reveal (HUNT-01, HUNT-02)

- **D-01: The server sends a per-client `SpoonVisible` on the TRANSITION into visibility and a
  `SpoonHidden` on the transition out. Never a standing list, never a periodic resend.** A list is
  a map; a resend is a map sampled over time. The client learns a position only while it is
  entitled to it and forgets it when it is not.
- **D-02: Glint range is 25 studs.** Well above `PICKUP_RANGE = 7.0` so you see before you can
  take - the moment of spotting is distinct from the moment of claiming - and far below "across the
  map", which is what PROJECT.md forbids ("finding one takes actually sweeping a space, not
  spotting a glow from across the map"). It is a tuning number for Phase 8, not a locked one.
- **D-03: Line of sight is ONE `Workspace:Raycast` from the seeker's eye at `EYE_HEIGHT = 4.0` to
  the spoon, with `RaycastParams.RespectCanCollide` set EXPLICITLY to `true`.** This is not a
  preference. V-18 is open against this phase and is sharp: the property **defaults to `false`,
  the opposite of the sight model Phase 3's validator used**. Leave it unset and CI and the live
  game disagree about what blocks sight, so a spot the validator passed can hide a spoon that is
  visible through a wall in play. Multi-ray to the spoon's corners was considered and rejected for
  this phase: it multiplies cost at 5 Hz per seeker per spoon for a precision nobody has asked for.
- **D-04: Visibility is evaluated at 5 Hz per seeker, not per frame.** Matches V-34's interest
  rate. At 10 players and 8 spoons a per-frame evaluation is 4800 raycasts a second for a reveal
  that cannot be perceived faster than the glint's own fade.

### Area 2 - Claim, races and plausibility (HUNT-03, HUNT-04, HUNT-08)

- **D-05: The pickup affordance is a `ProximityPrompt` CREATED BY THE CLIENT on the client's own
  local visual. Never a server instance.** A server-side prompt at the spoon's position is a
  replicated Instance carrying a hidden position - HUNT-01 straight through the floor, and
  PROJECT.md forbids it explicitly. The server re-validates every claim; the prompt is an
  affordance, not an authority.
- **D-06: A race is decided by first-to-arrive in ONE non-yielding server handler, with a
  `claimedBy` field set synchronously.** Rule 6: no yields inside state mutations. A yield between
  the check and the write is exactly how two claimants both win. The loser gets a silent no-op.
- **D-07: A claim is rejected when the claimant's server-known position exceeds
  `PICKUP_RANGE + PICKUP_MARGIN + walkSpeed * rtt` from the spoon.** Sampled at about 4 Hz. On a
  violation: log and escalate on repeats rather than act on a single sample. V-23 says the
  server-known position of a client-owned character LAGS, so a tight check would reject honest
  players on bad connections; the rtt term is that slack made explicit rather than fudged. Open
  Question 10 says these are first-pass numbers tuned in Phase 8, and nothing here should read as
  measured.
- **D-08: A rejected claim is SILENT - indistinguishable from the spoon simply not being there.**
  Phase 4's D-12 set this precedent for exactly the same reason: a distinguishable rejection tells
  a cheat client that its probe was detected, which turns the anti-cheat into an oracle.

### Area 3 - HUD, collisions and spectating (HUNT-05, HUNT-06, HUNT-07)

- **D-09: Spoons-remaining is a COUNT, published on change.** Never positions, never "warmer".
- **D-10: Player-to-player collisions are disabled with ONE `PhysicsService` collision group,
  applied at round start for the whole round.** Per-phase toggling is a state machine whose failure
  mode is two players wedged in a doorway during the one phase it matters.
- **D-11: A spectator is a free-roaming camera with no character, bounded to the map, and
  RECEIVES NO SPOON REVEALS.** A spectator that inherits a seeker's visibility is an ESP channel
  with extra steps - a player could finish, spectate, and call positions out. The reveal is keyed
  to a seeker's own eye position and a spectator has none.
- **D-12: Anyone whose round is over can spectate**, per HUNT-07.

### Area 4 - Round end, the scoring boundary and the Phase 4 seam

- **D-13: Scoring is a PURE module at `src/server/core/Scoring.luau`** - no Roblox API, so the
  worked examples run headless in CI. FOUND-05's lint rule already names `Scoring` as a guarded
  root, so the no-pay-to-win import ban applies to it the moment the file exists.
- **D-14: Compute per event, publish once.** A find's points are computed at the instant of arrival,
  because that is when the clock reading is correct; the scoreboard is published once at round end,
  because Phase 6 owns the scoreboard and a mid-round publish is surface for a wrong number to be
  seen and remembered.
- **D-15: Completions arrive through the sink Phase 4 already exposes** at
  `src/server/Main.server.luau`'s `onCompleted`, not by reaching into `CardService`. Phase 4 built
  that seam for this phase and its comment says so.
- **D-16: Round end fires IMMEDIATELY AND SYNCHRONOUSLY on the claim that takes the final spoon,
  before any scoring publish.** Phase 4 already paid for this lesson: `RoundEnd` had to be
  published BEFORE `table.clear(seated)` or it carried nothing, because the audience was read from
  the thing being cleared. The same shape applies here - publish while the state still exists.

### OPEN - OWNER (new questions, answered conservatively)

- **D-17: RESOLVED BY THE OWNER, 2026-11-10 — "First person, its own phase."** The hunt keeps the
  standard Roblox camera **in this phase**, and a first-person hunt is now **Phase 05.1**, with its
  own goal, five success criteria and a research flag. This is no longer a declined preference or
  an open question: it is scheduled work with a home.
  **The tripwire in 05-16 (`CD-05`) becomes MORE important, not less** — it fails if a
  `CameraMode`/`firstperson` seam appears in Phase 5. Now that another phase owns this, a seam
  drifting in here would silently pre-empt that phase's design rather than merely exceed scope.
  The original reasoning, kept because Phase 05.1 inherits it: The owner said "the game should be first person", then clarified it as the card phase,
  where the argument was fully worked through and the 48 px objection resolved by locking the
  camera. **None of that reasoning transfers to the hunt**, which is free movement across a parkour
  map where a forced first-person camera is a significant and separate playability decision. Phase
  04.1's context deferred the hunt camera to this phase precisely so it would be decided with the
  glint and line-of-sight model in hand. The conservative answer is to leave it, and to raise it.
  **If the owner wants a first-person hunt, say so and it becomes its own phase** - it would
  interact with glint visibility, line of sight and the plausibility check all at once.
- **D-18: The glint is a fixed world effect with no purchasable variant, and this phase builds no
  seam for one.** SHOP-03 says glint appearance and range cannot be bought. Rule 1 says gameplay
  code must never import cosmetics. Building a "glint style" hook now would be building the import
  path the lint rule exists to forbid.

### Claude's Discretion

All of the above. The decisions most worth a second look in the morning, in order:
1. **D-17** (the hunt is not first person) - the one place this phase declines to follow a stated
   owner preference, deliberately and with a reason.
2. **D-02** (glint 25 studs) - a feel number nobody has playtested.
3. **D-07** (plausibility thresholds) - explicitly first-pass, explicitly Phase 8's to tune.

</decisions>

<code_context>
## Existing Code Insights

### Reusable assets
- `src/server/core/SpoonPlacement.luau`, `MapValidator.luau`, `WalkGrid.luau`, `Obb.luau` - Phase 3.
  The graybox validates at **21 spots, 9 seats**, so auto-fill has a pool to draw from.
- `src/shared/Config/Placement.luau` already holds `PICKUP_RANGE = 7.0`, `PICKUP_MARGIN = 1.5`,
  `EYE_HEIGHT = 4.0`. The glint range is NOT there yet and belongs beside them.
- `src/shared/Net/Manifest.luau` + `Validate.luau` - the typed gateway. New kinds are declared
  there; `NetServer` is the only file allowed to call `FireClient`/`FireAllClients` (guard R4).
- `src/server/core/Gateway.luau` - **FROZEN, lines 56-79 especially.** Do not edit.
- `src/server/engine/` - **FROZEN.** The card engine has nothing to do with this phase.

### Established patterns
- Pure core plus a thin Roblox adapter. **The 2026-11-10 seat bug is the cautionary case**: the
  pure core was fully covered because its effects are injected, the adapter had NO test, and the
  bug lived in the seam. Every adapter this phase adds needs a gate even if only a source scan.
- Per-client sends go through `NetServer`'s publisher; the audience is computed server-side.
  `privacy.spec` is the precedent for proving a message carries counts and not contents.
- Mutation discipline: clean control, non-vacuity assertion, no-defect twin, and a mutation of the
  REAL source that must fire. Gates that cannot fire are this repo's recurring failure.

### Integration points
- `Main.server.luau` `onCompleted` - the completion sink Phase 4 left for this phase.
- `RoundDriver` / `RoundLifecycle` - the round cap and the single-fire end. Phase 1 proved end fires
  exactly once even with a stale callback from an earlier round.
- `MapLoader` / `MapContract` - spot and seat poses, contract version 2.

</code_context>

<specifics>
## Specific Ideas

The ROADMAP's five success criteria are the acceptance bar and criterion 3 carries exact numbers:
1600 find points for the 8th spoon found at 2:40 remaining; 800 bonus + 600 find = 1400 for the 3rd
to four-of-a-kind finding at 1:00; 0 find points but a kept bonus for a seeker who finds nothing;
seeker ceiling 4000. **These are test vectors, not illustrations.**

Gate G3 is a vertical slice: cards, four-of-a-kind, hunt, claim, score, on one map, 3 to 10 clients
or bots, with auto-filled spoons, spoons-remaining visible, collisions off and finished players
spectating.

</specifics>

<deferred>
## Deferred Ideas

- **A first-person hunt camera** (D-17). Its own phase if the owner wants it.
- **Movement-threshold tuning on real latency data** - Phase 8, Open Question 10.
- **Bot fill for the cold start** - Phase 8, Open Question 13, decided on telemetry.
- **Multi-ray line of sight** to a spoon's corners instead of one ray to its centre. Rejected here
  on cost; revisit if playtests show spoons visible around corners.

</deferred>
