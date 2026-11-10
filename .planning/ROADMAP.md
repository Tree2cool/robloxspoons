# Roadmap: Spoons

## Overview

Spoons is built engine-first. The card ring is the highest-risk and most testable component, so it is written as a pure, headless Luau module and proven by a fuzz suite and a bot pacing simulator before any UI or networking exists. That simulator also decides whether jokers ship as wilds or fall back to blockers. A placement and map pipeline runs in parallel with the engine. The live card table and the hunt (with anti-ESP) then run in parallel and merge into a playable vertical slice, so the core feeling (four of a kind as a starting gun that flows into the hunt) is in front of playtesters before any breadth work. The hide phase and match lifecycle integrate the settled flow rules, then the five maps and the cosmetic catalog are added, and a final phase hardens PC and mobile parity for launch.

**Granularity:** standard | **Parallelization:** enabled | **Phases:** 8 | **Coverage:** 102/102 v1 requirements

## Standing Rule for Every Phase's Research Step

Every Roblox platform claim in the research is unverified against primary docs (five documentation hosts were DNS-blocked: `create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`, `madstudioroblox.github.io`, `jsdotlua.github.io`). **Each phase's research step must begin by re-checking the rows of the Verification Debt table in `.planning/research/SUMMARY.md` that name that phase in their "Re-check at" column**, and must record what was confirmed or changed. Nothing in that table has been upgraded above its stated confidence.

## Phases

- [x] **Phase 1: Foundations, Contracts and Spec Lock** - Toolchain, CI, typed gateway, lint guards, FSM skeleton, map contract, persistence skeleton, and the two blocking card-engine specs
- [x] **Phase 2: Card Engine and Pacing Simulator** - Pure headless card ring, fuzz suite, and the simulator gate that decides jokers-as-wilds versus blockers
- [x] **Phase 3: Placement Rules, Map Pipeline and Validator** - Shared placement rules and a validator that runs every default spot through them (parallel with Phase 2)
- [ ] **Phase 4: Live Card Table** - Server card shell, prediction/reconcile, AFK auto-pass, and the PC and mobile card UI (parallel with Phase 5)
- [ ] **Phase 04.1: First-Person Card Presentation** - (INSERTED) Camera locked on the player's own 3D cards in hand; replaces Phase 4's 2D overlay
- [ ] **Phase 5: Hunt, Anti-ESP, Claim and Scoring** - Server-only spoon data, per-client reveal, atomic claim, scoring ledger, round end (parallel with Phase 4; ends at the vertical-slice gate)
- [ ] **Phase 6: Hide Phase, Match Lifecycle and Churn** - Free placement UI, parkour room, full match flow, joiners/leavers, scoreboard and podium
- [ ] **Phase 7: Content and Monetization** - Two independent tracks: five maps (7a) and the cosmetic catalog, shop, persistence and VIP (7b)
- [ ] **Phase 8: Parity, Hardening and Soft Launch** - Device matrix, soak and anti-exploit audit, telemetry, economy review, cold-start decision

## Parallelization Map

```
P1 (sequential)
  |
  +--> P2 Card engine + simulator + joker gate  ----+
  |                                                 +--> P4 Live card table  --+
  +--> P3 Placement + map pipeline + validator --+--+                           +--> [G3 vertical slice] --> P6 --> P8
  |                                              +-----> P5 Hunt/anti-ESP/scoring --+                          ^
  |                                              +-----> P7a Maps (geometry authoring after G2) ---------------+
  +--> Floating track: ProfileStore, catalog schema, Owns/Prompt (from P2 onward) --> P7b ----------------------+
```

- Safely parallel: P2 with P3; P4 with P5; P7a (map geometry) with P4 through P6; the persistence floating track with everything.
- Strictly sequential: P1 before all; P2 before P4; P3 before P5 and before any of MAP-05..09; P4 and P5 before P6; P6 before P8.
- The five map builds (MAP-05, MAP-06, MAP-07, MAP-08, MAP-09) are mutually independent and parallelizable. Each is its own work item against the contract.

## Phase Details

### Phase 1: Foundations, Contracts and Spec Lock
**Goal**: The repo builds, lints and tests headless in CI, the structural guards that keep no-pay-to-win and engine purity true are enforced, and every contract that parallel work depends on is fixed
**Depends on**: Nothing (first phase)
**Requirements**: FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07, FOUND-08, MAP-01, SCORE-06
**Success Criteria** (what must be TRUE):
  1. A fresh clone syncs into Studio through Rojo without deleting Studio-authored map content in Workspace, and CI (format, lint, strict typecheck, `rojo build`) is green on every push
  2. The engine test suite and fuzz harness execute headless outside Studio in CI, proven by a spike showing the engine's `require` style works under both the headless runner and Roblox
  3. The build fails when a `Scoring`, `CardTable` or `SpoonPlacement` module gains an import path to any cosmetics or shop module, and fails when a file under `server/engine/` references a Roblox API (each demonstrated by a deliberately failing fixture)
  4. A client message with a malformed, NaN, wrong-phase or over-rate payload is rejected by the single typed gateway, and a Studio session cannot write to production player data
  5. A gray-box reference map loads through the shared map contract with no per-map code branch, the server refuses an 11th player and refuses to start under 3, and an injected-clock test shows round end firing exactly once even when a stale callback from an earlier round fires at the boundary
**Plans**: 12 plans in 7 waves
Plans:
- [x] 01-01-PLAN.md — Toolchain, pinned configs, vendored types, Rojo project, first green run (wave 1)
- [x] 01-02-PLAN.md — Headless test harness, fuzz helper, Rng, require spike, project-shape spec (wave 2)
- [x] 01-03-PLAN.md — check-guards: strict headers, FOUND-05 import closure, Net hygiene, secret names (wave 3)
- [x] 01-04-PLAN.md — Engine-purity allow-list fixtures and the three exit-code trap proofs (wave 3)
- [x] 01-05-PLAN.md — Validation vocabulary, intent manifest, token bucket (wave 3)
- [x] 01-06-PLAN.md — Round lifecycle exactly-once, RoundDriver, spec-lock todos (wave 3)
- [x] 01-07-PLAN.md — Map contract, structural validator, gray-box generator, validate-map CLI (wave 3)
- [x] 01-08-PLAN.md — Admission 10/3, PlayerGate, persistence isolation seam (wave 3)
- [x] 01-09-PLAN.md — Typed gateway, NetServer and ClientNet (wave 4)
- [x] 01-10-PLAN.md — MapLoader, boot wiring, built-place require re-resolution (wave 5)
- [x] 01-11-PLAN.md — CI workflow, pre-commit hook, verify script, MANUAL-CHECKS (wave 6)
- [x] 01-12-PLAN.md — Owner gate: test universe, place settings, servePlaceIds (wave 7, not autonomous)
**Research**: Verification pass only. Re-check Verification Debt rows V-1 to V-6, V-8 to V-10, V-14, V-30, V-31. Run the Lune/Roblox `require` spike (V-4).
**Spec lock (resolved defaults, each written as a test)**: Open Question 1, deal-time four-of-a-kind (re-shuffle so no seat starts complete, including wild-completable hands; this is CARD-09). Open Question 2, which four cards leave on a joker completion (spend naturals first; this is CARD-10). Open Question 17, player cap of 10 stated explicitly (FOUND-08).

### Phase 2: Card Engine and Pacing Simulator
**Goal**: A pure, headless, synchronous card-ring engine exists, is fuzz-proven, and a bot simulator has decided the joker question before any UI is built
**Depends on**: Phase 1
**Requirements**: CARD-01, CARD-03, CARD-04, CARD-05, CARD-06, CARD-07, CARD-08, CARD-09, CARD-10, CARD-11, CARD-12
**Success Criteria** (what must be TRUE):
  1. A scripted engine run for every table size from 3 to 10 never loses or duplicates a card: after every action the conservation invariant (hands plus piles equals initial minus four per completion) holds across 100k+ fuzzed actions, including random leavers, idle seats and mid-pass departures
  2. A hand can draw only at exactly 4 cards, a passed card always lands in the next live seat's left pile as resolved at execution time, and the last seat's passes land beneath the dealer's deck so the deck never runs dry
  3. A four-of-a-kind on draw removes that seat immediately, the ring closes up, and the removed seat's remaining cards reach the successor's left pile and are never destroyed
  4. The dealer and seat order for the next round are computed correctly from the previous find order, including the case where the first finder is the hider (deck goes to the highest-placed finisher actually seated) and the random round-1 dealer
  5. **Gate G1:** the bot pacing simulator reports zero stalls at every player count from 3 to 10 and acceptable time-to-first-completion, selecting the card pool and joker count; jokers ship as wilds (CARD-10) only if it passes, otherwise they ship as blockers (CARD-12), with both variants available behind a flag from the start

**Gate G1: PASSED** (2026-11-04). Criterion 5 is kept verbatim above so the gate's original wording stays
auditable against what was actually recorded. The verdict, every rejected cell with its named bar failures and
the pure-greedy worst case are in `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md`.

- **Selected configuration, shipped in `src/shared/Config/CardPool.luau`:** `EXTRA_RANKS = 3` (`k = 3`, so
  `ranks = seatCount + 3` where `seatCount` = seated seekers = players − 1; circulation `4k + j = 13`),
  `JOKERS = 1`, `JOKER_MODE = "Wild"` with Blocker live behind the flag, `ANTI_LIVELOCK_VALVE = true`,
  `AUTO_PASS_MAX_SECONDS = 8.0`, `AUTO_PASS_SELECTION = "uniform-random-from-hand"`.
- **Measured, not rounded.** 320,000 gated rounds at the locked 10,000 per (N, pool config), N = 3..10 × both
  joker modes × both churn variants: **37 stalled rounds — 0.012% aggregate, 0.070% in the worst cell — against
  the 0.500% residual ceiling** amendment A8 set. Median time to first completion 16.2s (bar 45s), p95 23.7s
  (bar 120s), minimum occupancy 0.825 (bar 0.600), worst valve firing rate 8.240% (bar 20.000%), `marginal = false`.
- **The recorded claim is narrow on purpose:** zero *observed* stalls was never reached and is not claimed. This
  is a measured property of the selected configuration at the confirmed round count, not an unconditional
  property of the engine. Criterion 5's literal "zero stalls" bar was not met by any pool this engine has; the
  bar became an explicit residual ceiling (amendment A8, owner-approved) with the measured residual printed.
- **Both variants really do ship behind a flag.** Wild and Blocker each clear every bar at every N, so CARD-12
  is a live flag rather than a contingency — which is also why `k >= 1` is mandatory.
- **Carried debt:** the solvability half of G1 is a theorem independent of the bot model; the **pacing** half
  measures the bot until V-35 (does the reaction-time distribution represent humans?) and A4 (do humans deviate
  from pure greed?) close at a real playtest. Carried in STATE.md.
**Plans**: 14 plans in 10 waves
Plans:
- [x] 02-03-PLAN.md — pure-zone R3 guard extension banning `coroutine` and `os.`, with two mutation fixtures (CLAUDE.md rules 5 and 6) (wave 1, before the engine exists)
- [x] 02-01-PLAN.md — shared type vocabulary plus the circulation, partition-identity and satisfiability invariants, each mutation-proven (wave 2)
- [x] 02-02-PLAN.md — SeatOrder: one total order for dealer and seat order, with a corpus covering the five unspecified cases (wave 2)
- [x] 02-04-PLAN.md — Pool: `poolConfig`, build, shuffle, and the CARD-09 deal with a rejection-fired assertion (wave 3)
- [x] 02-05-PLAN.md — Hand: completion detection, naturals-first retirement, and the Wild/Blocker divergence (wave 3)
- [x] 02-06-PLAN.md — Ring: pass/draw/wrap and the one generic seat removal with its terminal bucket (wave 3)
- [x] 02-13-PLAN.md — the engine's anti-livelock valve (amendment A7) plus the deterministic livelock fixture that proves it fires (wave 3)
- [x] 02-07-PLAN.md — Engine.apply: validation, all seven reject codes, the locked event order, the valve wiring, and newRound (wave 4)
- [x] 02-08-PLAN.md — the 100k-action fuzz suite with action-count and per-kind coverage assertions (wave 5)
- [x] 02-09-PLAN.md — the bot simulator, the six-outcome taxonomy, the five G1 bars, the mechanism checks, and the CI regression subset (wave 6)
- [x] 02-10-PLAN.md — owner decision on the joker floor and the AFK deadline, then the sweep CLI and its smoke test (wave 7, not autonomous)
- [x] 02-14-PLAN.md — run the search, mechanism, confirm and triage stages; commit the G1 report and the sweep data (wave 8)
- [x] 02-11-PLAN.md — the G1 decision in `Config/CardPool`, the three spec-lock todos become real tests (todo count 0), and 02-VALIDATION.md signed off (wave 9)
- [x] 02-12-PLAN.md — owner sign-off, then record the verdict in the planning documents and hand Phase 4 the two auto-pass constraints (wave 10, not autonomous)
**Research**: YES. Simulator design (stall definition, pacing targets, bot reaction-time model, snowball and start-up latency measurement). Domain design, not API research. Open Questions 3 and 6 are resolved here. Re-check V-15 and V-35.
**Note on CARD-10 and CARD-12**: both are mapped here and both are built, but exactly one is active in the shipped game, selected by Gate G1.

### Phase 3: Placement Rules, Map Pipeline and Validator
**Goal**: Placement validity is a single shared rule set, and a build-time validator proves every authored default spot obeys it, so no map can ship an unfindable spoon
**Depends on**: Phase 1
**Requirements**: HIDE-06, HIDE-07, MAP-02, MAP-03
**Success Criteria** (what must be TRUE):
  1. A placement-corpus test of known-good and known-bad coordinates (shelf out of reach, inside a wall, no line of sight, over a void) produces the expected accept or reject with a reason for each, and a spot is valid only when a reachable standable position exists within pickup range with clear line of sight
  2. The same placements produce the same verdict for avatars of different body scales
  3. The validator fails the build on a deliberately unfindable default spot, and passes the reference map with at least 16 default spots that each survive the real placement rules after exclusions
  4. **Gate G2:** the validator is green on the reference map and the full corpus, and the maze bake stress test (worst-case reachability) completes, so the five map builds may be authored
**Plans**: 11 plans in 8 waves
Plans:
- [ ] 03-01-PLAN.md — contract version 2: Node gains up, canCollide and shape, both snapshotters emit them identically, and the shape-parity gate (wave 1)
- [ ] 03-02-PLAN.md — the ten shipped placement constants (D-18) with the coupling invariants, the clearance cliff and two new MANUAL-CHECKS rows (wave 1)
- [ ] 03-03-PLAN.md — Obb: basis from look x up, point distance, segment-vs-OBB slab test and column span, with six degenerate cases and differential fuzz (wave 1)
- [ ] 03-04-PLAN.md — WalkGrid: multi-layer span field, slope-allowance erosion, link-verified 4-neighbour BFS, plus the MicroWorld fixtures including D-19 over-a-void (wave 2)
- [ ] 03-05-PLAN.md — SpoonPlacement: the locked six-reason order, bake and check, the placement corpus and the arity lock (wave 3)
- [ ] 03-06-PLAN.md — the graybox regenerated under D-17 STRICT: 21 authored spots that all pass, with the margin table and the reference-map time cap (wave 4)
- [ ] 03-07-PLAN.md — the adversarial maze generator and its oracle, with the 2.0 s bake cap and the corridor-3 vacuity control (wave 4)
- [ ] 03-08-PLAN.md — the validator placement stage, eight new issue codes with exact-set fixtures, both call sites injected and the comment-stripped spec lock (wave 5)
- [ ] 03-09-PLAN.md — seat winding and seat facing (D-20), and Phase 1 deferred-checks list closed out honestly (wave 6)
- [ ] 03-10-PLAN.md — Gate G2 report, the nine-gate observation table, the validation sign-off and the Verification Debt update (wave 7)
- [ ] 03-11-PLAN.md — owner sign-off on Gate G2 and M-08 in Studio, unblocking Phase 7a (wave 8, not autonomous)
**Research**: YES. Walkable-grid flood-fill versus Pathfinding (spike on the maze), StreamingEnabled effect on client preview, Lune-based CI validation, avatar normalisation scope (Open Question 12: spawn-time versus canonical reference avatar). Re-check V-17 to V-20, V-4.

### Phase 4: Live Card Table
**Goal**: Seekers can play the real-time simultaneous card scramble on PC and on a phone, and it feels immediate
**Depends on**: Phase 2 (stubbed completion events allow it to run without Phase 5)
**Requirements**: CARD-02, CARD-13, CARD-14, CARD-15, CARD-16, CARD-17, CARD-19, UX-01, UX-02, UX-03, UX-04
**Success Criteria** (what must be TRUE):
  1. A player taps a card once to select it and taps again to send it to their right pile, and an accidental single tap never sends a card
  2. A player sees their own five cards and only the pile depths of other seats, and a tap responds immediately at 150-300 ms simulated lag with the server correcting any mismatch without a visible glitch
  3. On a phone in landscape the hand and both piles are fully playable with touch targets of at least 48px, the default movement controls are hidden during the card phase, nothing sits under device safe areas, and on-screen hints match mouse, touch or keyboard
  4. An idle seat is auto-passed within the timeout so the circle keeps moving, and is benched after repeated strikes through the same seat-removal path as a disconnect
  5. Completing four of a kind plays a distinct starting-gun moment, and card faces (including jokers) remain legible for a colour-blind player
**Plans**: 20 plans in 10 waves
Plans:
- [ ] 04-01-PLAN.md — the RecordingPublisher fake, Config/Card, and the Gate G1 / D-32 spec-lock (wave 1)
- [ ] 04-02-PLAN.md — zones.luau extended for D-37 and D-38, three fixtures proving the new coverage fires, and MANUAL-CHECKS M-11..M-17 written before execution (wave 1)
- [ ] 04-03-PLAN.md — Draw and Pass in the Manifest with their buckets, and the rule-7 forbidden-key gate (wave 1)
- [ ] 04-04-PLAN.md — src/shared/Card registered as a pure zone; Faces: the rank ladder, the drawn-asset table, and the 50-face greyscale gate (wave 2)
- [ ] 04-05-PLAN.md — CardRouting: the audience as frozen data, the private-kind guard, ValveForcedPass stripping, and copy assignment (wave 2)
- [ ] 04-06-PLAN.md — IdleClock: the D-15 legal-action gating, 80 deci, three strikes, the uniform auto-pass, and D-35's no-auto-draw (wave 2)
- [ ] 04-07-PLAN.md — StallDetector independent of the valve (D-20), and RejectThrottle closing the D-22 revisit (wave 2)
- [ ] 04-08-PLAN.md — Layout: the whole UI-SPEC geometry as pure arithmetic, four viewports, the 48 px floor, and the F4 strip resolution (wave 3)
- [ ] 04-09-PLAN.md — Prediction: the auth + pending reducer, CARD-15's one-tap rule, cumulative ack and the rollback watchdog (wave 3)
- [ ] 04-10-PLAN.md — Flourish: the fixed-duration driver, the CARD-18 seam, and the F8 periodic scan (wave 3)
- [ ] 04-12-PLAN.md — CardTable: the pure server core, the CARD-13 privacy gate, and state-hash equivalence against the real engine (wave 3)
- [ ] 04-11-PLAN.md — Hints: the complete (state x input) copy table with the four F4 rewrites; Controls: the pure hide/restore seam and the src-wide GetControls scan (wave 4)
- [ ] 04-13-PLAN.md — the Card remote, the Publisher implementation and ClientNet.onCard (wave 4)
- [ ] 04-14-PLAN.md — CardService: the one deci conversion, the two clocks, the 10 Hz sweep, the RoundStub, and the throttled reject sink (wave 5)
- [ ] 04-15-PLAN.md — CardSeatHold: the server-enforced avatar hold and the instant release on completion (wave 6)
- [ ] 04-16-PLAN.md — CardTheme, CardHud and CardStrip: the ScreenGui with CoreUISafeInsets, the UITextSizeConstraint, and the no-magic-number gate (wave 6)
- [ ] 04-17-PLAN.md — CardFace, CardHand and CardPiles: the fan, the hit strips and both pile panels (wave 7)
- [ ] 04-18-PLAN.md — CardControls, CardInput and CardClient: the control effects, the input layer and the one wiring file (wave 8)
- [ ] 04-19-PLAN.md — CardSeatsView, CardCallout, CardFlourish and CardAudio: travelling cards, the who-went banner, the flourish surface and the sting (wave 9)
- [ ] 04-20-PLAN.md — the phase gate: the runtime budget decision, the mutation ledger, the honest requirement split, and the device matrix checkpoint (wave 10, not autonomous)
**UI hint**: yes
**Research**: Light. Re-check V-12, V-13, V-24, V-25, V-26, V-27 (remote ordering, control disable, ScreenInsets). Open Question 4 (AFK thresholds) tuned here and in Phase 6. Test on a real phone early. The basic deal hook is built here; the deck-skin flourish content lands in Phase 7 (CARD-18).

**Note on CARD-16 — two constraints inherited from Phase 2's Gate G1, both enforced by
`src/shared/Config/CardPool.luau`:**
1. The auto-pass deadline **must not exceed `AUTO_PASS_MAX_SECONDS` (8.0s)**. A longer deadline weakens a
   secondary mitigation (the engine's anti-livelock valve carries the stall job, amendment A7), and CARD-16
   benches a player after repeated strikes, so a *shorter* deadline would strike ordinary players several
   times a round. Open Question 4's tuning happens inside that ceiling, not above it.
2. The card the auto-pass sends **must be chosen by `AUTO_PASS_SELECTION` = `uniform-random-from-hand`**. This
   is the half that looks like a free implementation choice and is not. Deviation comes from the auto-pass
   choosing a card the player would NOT have chosen; the helpful-looking "auto-pass your worst card" is the
   player's own greedy choice, which makes the deviation exactly zero and means the simulator's result
   transfers nothing to the shipped game.

Also inherited: **`ValveForcedPass` fires in roughly 8% of rounds at a full roster** (up to 15.8% at tighter
pools) — a card leaves a player's hand that they did not choose, so it needs a real affordance, not an
edge-case path. The simulator's clock is float seconds while the shipped clock is integer deciseconds
(Non-Negotiable Rule 5), so round at the boundary. And the start-up ramp is real: ~8.3s at N=10 against a 4.6s
median time-to-first-completion at N=3, so far seats need a "waiting for cards" affordance. Evidence for all of
these: `.planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md`.

### Phase 04.1: First-Person Card Presentation (INSERTED)
**Goal**: The card phase is played from the seated player's own point of view — the camera locked on their own cards, the cards themselves 3D objects held in the avatar's hands with draw and pass animations, the table and the other players visible behind — without losing any guarantee the flat overlay was providing
**Depends on**: Phase 4
**Requirements**: CARD-02, CARD-13, CARD-15, CARD-17, CARD-19, UX-01, UX-02, UX-03, UX-04 (re-met, not newly met: Phase 4 met them against the 2D overlay this phase replaces)
**Success Criteria** (what must be TRUE):
  1. A seated player sees their own hand as 3D cards held in front of them, selects with one tap and passes with a second (CARD-02), and the fumbled double-tap behaves exactly as D-03 already decided
  2. Every card's on-screen hit target measures **>= 48 physical px on a real phone** — computable because the camera is locked, which is the whole reason this presentation is viable (UX-01, UX-03)
  3. All 50 faces remain nameable in greyscale at the new rendered size, on desk and on glass: identity still comes from `(rankGlyph, pipShape)` and never from colour (CARD-19, D-24)
  4. A player can still read how full the other seats are well enough to know whether they are about to be one of the two who get nothing (CARD-13), with the "X is out" callouts intact (D-40)
  5. Completing four of a kind still reads as a starting gun (CARD-17): overlay gone in the same frame, controls back instantly, the avatar already running while the flourish plays around it (D-30's ordering is unchanged)
  6. The card engine, the server shell, the net layer and the seat hold are **untouched** — this phase replaces a renderer, not a game
**Plans**: 10 (see the Plans list below)
**UI hint**: yes
**Research**: YES. 3D-to-screen hit testing with a locked camera, deterministic on-screen card size across viewports, mobile cost of per-card 3D geometry or ViewportFrames, and hand/arm animation sourcing (new asset work with no prior phase). Re-check V-25 (the 48 px floor) and V-34 against the new render path.

**Why this exists.** Phase 4 shipped a 2D `ScreenGui` hand overlay, decided as D-26 and D-27 on the grounds that a 3D card's on-screen size depends on camera framing and so the 48 px touch floor could not be asserted. **Locking the camera removes that objection**: a fixed camera makes each card's screen rect a computable, stable number, so the floor is assertable again. The owner confirmed on 2026-11-10 that the locked-camera first-person view is the intended game, having seen the reasoning. D-14 already required a locked camera during the card phase; this changes where it points and what the cards are made of.

**What it costs.** `CardFace`, `CardHand`, `CardPiles` and `Layout` are replaced. **M-12 and M-14's desk half are invalidated** — M-14 was signed against flat 72 x 92 faces. M-11 and M-13's timing survive untouched. Hand animations are new asset work in no prior phase's scope.

**Plans:** 10 plans in 7 waves. **Wave 0 is a spike and it gates every other wave:** the docs do not
settle how two `AlwaysOnTop` SurfaceGuis on different Parts order against each other, and a fan whose
layering is wrong is not a fan. Routes A and B share every geometric number, so the phase proceeds on
a provisional route behind one constant with one read site; M-18 settles it, and if it selects route B
then M-23 (lighting independence) goes live because scene lighting returns and the machine-gated
4.5:1 luma floor stops describing what the player sees.

Plans:
- [ ] 04.1-01-PLAN.md — the layering spike, the route seam, the HAND/CAMERA config, the comment-stripped source scanner every later gate uses, and every new MANUAL-CHECKS row, written before any renderer code (wave 0, gates all)
- [ ] 04.1-02-PLAN.md — `Projection.luau`: the pure pinhole model, the four-step transform order (F4) and the 48 px proof re-derived (wave 1)
- [ ] 04.1-03-PLAN.md — the locked camera: lock/release as Controls effects with one release site, `CardCamera`, and the camera discipline gate (wave 1)
- [ ] 04.1-04-PLAN.md — `viewportFrom` from two documented `GetInsetArea` calls (F1), and `Layout` gives up the hand and re-anchors the chrome, keeping `fan`/`slots` as a `Projection`-derived shim so every wave typechecks (wave 2)
- [ ] 04.1-06-PLAN.md — the face tree extracted unchanged, `CardCarrier` as an anonymous Part plus a PlayerGui SurfaceGui, and the T1/T2 privacy scans (wave 2)
- [ ] 04.1-05-PLAN.md — `CardHud` on the new recipe, the plate removed, the single pixel-to-GUI conversion, and the forbidden-coordinate-API gate (wave 3)
- [ ] 04.1-07-PLAN.md — `CardHand` rewritten: the 3D fan, the 2D hit buttons, every motion path, its own call site, and the no-gating gate (D-50) (wave 4)
- [ ] 04.1-08-PLAN.md — the depth rail: `Rail.luau` pure, its layout slot, the view, and F5/F6/F7 fixed (wave 4)
- [ ] 04.1-09-PLAN.md — the wiring, the 2D flourish deal retired in favour of the 3D hand-build, the `Layout` shim deleted with its last reader, and the git-asserted proof that the frozen set is frozen over `83517f7..HEAD` (wave 5)
- [ ] 04.1-10-PLAN.md — the three Studio probes with their own non-vacuity, and one controlled pre/post budget measurement (wave 6)

### Phase 5: Hunt, Anti-ESP, Claim and Scoring
**Goal**: A seeker who completes four of a kind can hunt server-hidden spoons that cheat clients cannot read, claim one without races, and be scored correctly, closing the loop into a playable vertical slice
**Depends on**: Phase 3 (and Phase 1)
**Requirements**: HUNT-01, HUNT-02, HUNT-03, HUNT-04, HUNT-05, HUNT-06, HUNT-07, HUNT-08, SCORE-01, SCORE-02, SCORE-03, SCORE-04, SCORE-05
**Success Criteria** (what must be TRUE):
  1. In a client-DataModel replication audit during a hunt, no hidden spoon position exists as an Instance, attribute or value anywhere the client can read, and a spoon becomes visible to a seeker only within glint range with clear line of sight
  2. When two players claim the same spoon in the same instant, exactly one wins, and a claim from a player who could not plausibly have reached the spoon is rejected
  3. Scoring matches the worked examples: 1600 find points for the 8th spoon found at 2:40 remaining; 800 bonus plus 600 find equals 1400 for the 3rd to four-of-a-kind finding at 1:00; 0 find points but a kept bonus for a seeker who finds nothing; seeker ceiling 4000
  4. The hider is scored at 4000 times the average fraction of a fixed 300 seconds their spoons survived, with unfound spoons counting as the full 300, and the round ends the instant the final spoon is claimed or at the 5:00 cap
  5. **Gate G3 (vertical slice):** on one map with 3 to 10 clients or bots, the full loop (cards, four-of-a-kind, hunt, claim, score) runs with auto-filled spoons, spoons-remaining is visible to seekers, collisions are off, and finished players can spectate
**Plans**: 19 plans in 6 waves
Plans:
- [ ] 05-01-PLAN.md — Config/Hunt: the fifteen constants, and the lock spec that keeps GLINT_RANGE above pickup reach (wave 1)
- [ ] 05-02-PLAN.md — MANUAL-CHECKS M-18..M-24 written BEFORE execution, with the Phase 5 close block (wave 1)
- [ ] 05-03-PLAN.md — the Claim intent, its bucket, and the forbidden-key gate extended to coordinates (wave 1)
- [ ] 05-04-PLAN.md — HuntRouting: the seven kinds as frozen data, plus the HuntRecording fake (wave 1)
- [ ] 05-05-PLAN.md — Scoring: the ROADMAP vectors as exact integers, and the one hider vector that discriminates the rounding rule (wave 1)
- [ ] 05-06-PLAN.md — SpoonRegistry: plain records, two shuffles so an id carries no placement, claimed exactly once (wave 1)
- [ ] 05-07-PLAN.md — Visibility: the 25-stud prefilter, the injected raycast, hysteresis and transition-only output (wave 1)
- [ ] 05-08-PLAN.md — Plausibility: the reach check with bounded rtt slack, the speed sampler, and the oracle gate (wave 1)
- [ ] 05-09-PLAN.md — HuntTable part 1: its OWN place counter (research F2), the sweep, spectators and removal (wave 2)
- [ ] 05-10-PLAN.md — the Hunt remote, the hunt publisher and ClientNet.onHunt (wave 2)
- [ ] 05-11-PLAN.md — SpoonView and RemainingHud: the client-created prompt and the count-only HUD (wave 2)
- [ ] 05-12-PLAN.md — HuntTable part 2: the atomic claim, the stale-reveal fan-out, and round end publishing before it clears (wave 3)
- [ ] 05-13-PLAN.md — SpectateCamera, HuntClient and the client boot; D-17 keeps the hunt third person (wave 3)
- [ ] 05-14-PLAN.md — HuntService: one raycast with RespectCanCollide explicit, one collision group, one accumulator (wave 4)
- [ ] 05-15-PLAN.md — privacy.spec: the anti-ESP oracle with five injected leaks and three non-vacuity counts (wave 4)
- [ ] 05-16-PLAN.md — client_discipline.spec: six scans over three files Lune cannot load (wave 4)
- [ ] 05-17-PLAN.md — service_wiring.spec: nine named adapter scans, twenty-nine run mutants (wave 5)
- [ ] 05-18-PLAN.md — Main.server: the round is wired for the first time (research F1), Claim routed, rank discarded (wave 5)
- [ ] 05-19-PLAN.md — the phase gate: the mutation ledger, the honest requirement split, the owner checkpoint (wave 6, not autonomous)
**UI hint**: yes
**Research**: YES. Client-created pickup affordance on a local-only visual, server-known position lag, time source precision for deciseconds, collision groups. Re-check V-21, V-22, V-23, V-30. Open Question 7 (hider-score denominator) is CONFIRMED by the owner: a fixed 300 s denominator, unfound spoons counting as the full 300, on the same timeline as find points. Recorded in SCORE-04. Open Question 10 (movement thresholds) first-pass here, tuned in Phase 8.

### Phase 6: Hide Phase, Match Lifecycle and Churn
**Goal**: A full match of 3 to 10 players runs end to end: players hide, play and rotate fairly, joiners and leavers never break the round, and the match ends with a correct winner
**Depends on**: Phase 3, Phase 4, Phase 5
**Requirements**: HIDE-01, HIDE-02, HIDE-03, HIDE-04, HIDE-05, HIDE-08, HIDE-09, HIDE-10, MATCH-01, MATCH-02, MATCH-03, MATCH-06, MATCH-07, MATCH-08, MATCH-09, MATCH-10, MATCH-11, MATCH-12, SCORE-07, SCORE-08, SCORE-10, MAP-04, SOC-01, SOC-02
**Success Criteria** (what must be TRUE):
  1. A hider places all N minus 2 spoons with a live ghost showing validity, sees an instant reason for any rejected spot, can undo and end early, and at 90 seconds any unplaced spoons auto-fill at random from the map's validated defaults
  2. While the hider works, seekers are in a closed-off parkour room; if the scheduled hider has left, the round still runs on auto-fill with no hider points awarded
  3. A match runs exactly as many rounds as the starting roster, every starting player hides exactly once, and everyone can see the hider rotation order; a mid-round joiner waits in the parkour room, enters at the next round start, adds no round and takes no hider turn; a leaver who rejoins is treated as a joiner
  4. If the roster drops below 3 the round in progress finishes, its points are awarded, and the match ends on current totals with no win credit; the lobby holds until 3 players with an intermission
  5. After each round the scoreboard shows four-of-a-kind bonus and find points separately, the top 3 by that round's score get a roughly 10-second podium, leaderstats show current score, and the match winner is the highest total with a deterministic tiebreak; maps are chosen at random without repeating the previous map
  6. **Gate G4:** scripted churn scenarios pass (hider gone, drop below 3, joiner in every phase, rejoiner, everyone leaves, character reset at the table), each phase waits for client-ready with a timeout, and chat is muted per phase for the hider and for finished players
**Plans**: TBD
**UI hint**: yes
**Research**: Light. `TextChatService` per-channel muting, spectate, `CharacterAutoLoads` and reset handling. Re-check V-28, V-29. Open Question 8 (mid-round leaver effects) is CONFIRMED: the round in progress finishes, its points are awarded, then the match ends on current totals with no win credit; spoons are fixed at round start and never retracted (MATCH-10). Open Question 18 (rejoin) takes the derived default recorded in MATCH-08. Open Question 5 (match tiebreak) remains the only owner decision outstanding here; default is higher best-round, then earlier four-of-a-kind placement. Includes a hider-versus-seeker expected-value simulation to confirm the "neutral in expectation" claim. Podium here renders the default loadout; equipped cosmetics and the unfound-spoon reveal arrive in Phase 7.

### Phase 7: Content and Monetization
**Goal**: The game has its five maps and its full cosmetic catalog, and nothing purchasable can touch score, findability or competitive outcome
**Depends on**: Phase 6 (Track 7a geometry authoring may start any time after Gate G2; Track 7b persistence work may start from Phase 2)
**Requirements**: MAP-05, MAP-06, MAP-07, MAP-08, MAP-09, SHOP-01, SHOP-02, SHOP-03, SHOP-04, SHOP-05, SHOP-06, SHOP-07, SHOP-08, SHOP-09, SHOP-10, SHOP-11, SHOP-12, SHOP-13, SHOP-14, SHOP-15, SHOP-16, CARD-18, SCORE-09, MATCH-04, MATCH-05
**Success Criteria** (what must be TRUE):
  1. Each of the five maps (hotel on a single floor, restaurant, mansion, maze with scattered decoy items, office) is playable end to end through the shared contract with no per-map code, passes the validator with at least 16 default spots, and stays within an acceptable time-to-first-find band
  2. A player can preview any item with its exact price, buy it, see it in an inventory view and equip it in the lobby only; a purchase is granted server-side, never granted twice, never lost, and is still owned after rejoining; loadout, stats and settings persist with session locking
  3. Every spoon skin passes the enforced template (fixed bounding box, scale, pickup hitbox, luminance/contrast floor) on every map, glint is identical for all players and cannot be bought or altered, character cosmetics change no collision or occlusion, and every deal animation has the same fixed duration
  4. The cosmetics are visible to the audience designed for them: the dealer's deck skin and deal animation play to the whole table at card-phase start, the hider's skin is what hidden spoons look like and a seeker's own skin shows on a carried spoon, the lobby shows each player's loadout on a plinth, and the round-end podium shows the top 3's equipped cosmetics and reveals unfound spoons with the hider's placement effect
  5. The default spoon and deck are free, some cosmetics unlock by achievement for non-paying players, VIP access is purchasable and grants no gameplay advantage, and a lint check confirms gameplay modules still have no import path to cosmetics or shop code
**Plans**: TBD
**UI hint**: yes
**Research**: Track 7b YES (`ProcessReceipt` versus `BindReceiptHandler`, `UserOwnsGamePassAsync` lag, pass-creation path, VIP route, ViewportFrame preview cost; re-check V-8 to V-11e). Track 7a standard patterns beyond the validator.
**Parallel tracks**: Track 7a is the five map builds, mutually independent (MAP-05, MAP-06, MAP-07, MAP-08, MAP-09) and parallelizable. Track 7b is cosmetics, shop, persistence and VIP, and shares no code with 7a. The planner may split this phase into two phases (7a and 7b) without changing any requirement mapping. Open Questions 11 (free/earned baseline), 14 (VIP route), 15 (Game Pass versus Developer Product switch) and 16 (deal-animation timing) are resolved here.

### Phase 8: Parity, Hardening and Soft Launch
**Goal**: The game is verified on real phones and under exploit pressure, first-time players learn it by playing, and the launch-blocking decisions are made on data
**Depends on**: Phase 6, Phase 7
**Requirements**: UX-05, UX-06, UX-07, SOC-03
**Success Criteria** (what must be TRUE):
  1. A first-time player is taught the loop by contextual prompts without a mandatory tutorial, and every screen has been captured at phone resolution and checked against the device matrix
  2. On real low-end mobile hardware a 10-player match holds an acceptable frame rate and memory stays flat across 10 rounds; supported devices and orientation are set explicitly with console and VR disabled
  3. A 10-bot-client soak and an anti-exploit audit (remote inventory, client-DataModel replication audit, movement-plausibility thresholds tuned on real latency data) find no remaining leak, and rate limits are tuned
  4. Friends can join each other through Roblox's native flow, and lobby-wait and unfound-at-timeout telemetry exist to drive the cold-start and bot-fill decision before soft launch
  5. **Gate G5:** the Robux economy review returns anything other than DO NOT SHIP and a purchase test on a published place passes
**Plans**: TBD
**UI hint**: yes
**Research**: YES for movement thresholds and client anti-tamper state; light otherwise. Re-check V-9, V-16, V-23, V-28, V-32, V-34. Real 9 to 10 player human playtest requires a published place (human gate). Cold start (existential risk) needs an owner decision and launch plan; Open Question 13 (bot fill) is decided here on telemetry.

## Requirement Coverage

| Phase | Count | Requirements |
|-------|-------|--------------|
| 1 | 10 | FOUND-01..08, MAP-01, SCORE-06 |
| 2 | 11 | CARD-01, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12 |
| 3 | 4 | HIDE-06, HIDE-07, MAP-02, MAP-03 |
| 4 | 11 | CARD-02, 13, 14, 15, 16, 17, 19, UX-01..04 |
| 5 | 13 | HUNT-01..08, SCORE-01..05 |
| 6 | 24 | HIDE-01..05, 08, 09, 10; MATCH-01, 02, 03, 06..12; SCORE-07, 08, 10; MAP-04; SOC-01, 02 |
| 7 | 25 | MAP-05..09, SHOP-01..16, CARD-18, SCORE-09, MATCH-04, MATCH-05 |
| 8 | 4 | UX-05, 06, 07, SOC-03 |
| **Total** | **102** | |

## Progress

**Execution Order:**
Phases execute in numeric order, with parallel pairs: 2 and 3, then 4 and 5, with Phase 7 track 7a overlapping 4 through 6.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundations, Contracts and Spec Lock | 12/12 | Complete | 2026-11-03 |
| 2. Card Engine and Pacing Simulator | 14/14 | Complete (Gate G1 PASSED) | 2026-11-04 |
| 3. Placement Rules, Map Pipeline and Validator | 0/TBD | Not started | - |
| 4. Live Card Table | 0/TBD | Not started | - |
| 5. Hunt, Anti-ESP, Claim and Scoring | 0/TBD | Not started | - |
| 6. Hide Phase, Match Lifecycle and Churn | 0/TBD | Not started | - |
| 7. Content and Monetization | 0/TBD | Not started | - |
| 8. Parity, Hardening and Soft Launch | 0/TBD | Not started | - |
