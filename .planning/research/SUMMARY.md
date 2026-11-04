# Project Research Summary

**Project:** Spoons (working title; repo `robloxspoons`)
**Domain:** Roblox multiplayer party game. A real-time simultaneous card-passing scramble (Spoons) feeding a server-hosted hide-and-seek hunt. PC and mobile parity, cosmetics-only Robux monetization.
**Researched:** 2026-11-02
**Synthesized against:** `.planning/PROJECT.md` as revised after research (2026-11-02). Where PROJECT.md and a research file disagree, PROJECT.md wins and the item is recorded as DECIDED.
**Confidence:** MEDIUM overall. Design-level conclusions are HIGH (four researchers converge and PROJECT.md closed most gaps). Roblox platform API behaviour, limits and tool versions are MEDIUM to LOW until re-verified, because five documentation hosts were unreachable during research (see Verification Debt).

Detail files: STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md (same directory).

---

## Executive Summary

Spoons is a server-authoritative, round-based party game whose hard part is not the hunt but the **card ring**: simultaneous passing around a circle that shrinks as players leave for the hunt, wraps so the deck never empties, and (maybe) contains wild jokers. Nobody has tuned this variant, so the solvability of the table is unproven. All four researchers and PROJECT.md independently reach the same build method. Write the ring as a **pure, synchronous, headless module** (functional core, imperative shell), fuzz it, and drive it with a bot pacing simulator **before any UI or networking exists**. The same simulator is the gate for the joker-as-wild decision, with jokers-as-blockers as the pre-agreed fallback. The ring is a circular doubly-linked list of seats. Each seat has a `hand` and an `inbox` (its left pile, a FIFO deque). Passing appends to `seat.next.inbox`. The wrap needs no special case because the dealer's inbox is the deck.

The recommended approach is deliberately boring around that core. Use Rojo with git as the source of truth, `--!strict` Luau, plain `RemoteEvent`s behind one typed and validated `Net` gateway (no codegen networking library), and a table-driven round state machine with absolute deadlines and round-ID tokens. Treat anything hidden as **server-side data, never replicated Instances**: hands, spoon positions and the default-spot pool. Each client learns a secret only through per-client interest management (distance plus line of sight). Maps are data behind a contract and an automated validator that must exist before the five maps are built. Persistence is ProfileStore. The shop sits behind an `Owns/Prompt` interface with Game Passes as the preferred backend. No-pay-to-win is enforced structurally: `Scoring`, `CardTable` and `SpoonPlacement` have no import path to cosmetics or shop code, and a lint rule enforces it. The roadmap should be **8 phases** with two real parallel pairs (engine with placement/map pipeline; card table with hunt), merging into a vertical slice before breadth.

The main risks, ranked by cost-if-wrong rather than likelihood:

1. Cold start below the 3-player minimum, which code cannot fully fix.
2. A replication leak in the spoon or hand model, which is expensive to retrofit.
3. Joker or deck-composition unsolvability, bounded by the simulator gate.
4. Correctness races in the card, claim and round-end paths.
5. AFK players stalling the whole circle.

Most gameplay design questions the researchers raised are now closed in PROJECT.md. About 18 genuinely open items remain, and only two are blocking for the card engine (deal-time four-of-a-kind and which four cards leave on a joker completion). **Every Roblox-platform claim in this research is unverified against primary docs**, so each phase-level research step should start by re-checking the items in the Verification Debt table.

---

## Settled by PROJECT.md (do not re-open)

These were open questions in the research files. They are decided.

| Topic | Decision | Open in |
|-------|----------|---------|
| Hider scoring | `4000 x (average fraction of the round their spoons survived)`. Neutral in expectation by design. | ARCH #1, PITFALLS C9 |
| Jokers | Wilds, **gated on the headless solvability simulator at N=3..10**. Fallback if it fails: jokers are blockers that never complete a set. | PITFALLS C3 |
| Mid-round joiners | Wait in the parkour room, queue to the **next round start**, play fully, no added round, no hider turn. **Supersedes ARCH's "seat at deal / straight to hunt" policy.** | ARCH late-join, FEATURES Q1 |
| Dealer collision | If last round's first finder is this round's hider, the deck goes to the highest-placed finisher **actually seated**. Round-1 dealer is random. | PITFALLS C9, FEATURES Q3 |
| Seat order | Finishers in find order, then the empty-handed seeker, then everyone else (previous hider, returning joiners). | ARCH #4, PITFALLS C9 |
| Departed hider | Round still runs on auto-fill, no hider points, nobody hides twice. **Supersedes PITFALLS' "skip the round".** | ARCH #5, FEATURES LIFE-03 |
| Podium | Top 3 **by round score**, not match total. | ARCH #6, FEATURES Q4 |
| Round clock | 5:00 is a **cap**. Round end fires immediately on the last spoon claim. | PITFALLS M1 |
| Removed seat's cards | Go to the successor's inbox, never deleted. The completed four leave play; the fifth card and the left pile pass on. | ARCH #3 |
| Four-of-a-kind check | On draw only. | PITFALLS C3 |
| Soft currency / crates | None. Direct-purchase cosmetics only. **Overrides FEATURES' SHOP-05/PROG-02/PROG-04 (earn-only coins).** | FEATURES Q5 |
| Game Pass vs Dev Product | Game Passes preferred. | STACK |
| New cosmetic line | Purchasable deal animations (shuffle-and-deal flourish at card-phase start). | FEATURES CARD-06 |
| Cosmetic visibility fixes | All three in scope: podium spoon reveal with the hider's effect, dealer reveal flourish, lobby loadout plinths. | FEATURES HIDE-05, CARD-06 |
| Spoon skins | Enforced template (fixed bounding box, scale, pickup hitbox, luminance floor). Glint is fixed and non-purchasable. | PITFALLS C10 |
| No-pay-to-win structure | `Scoring`, `CardTable`, `SpoonPlacement` have no import path to cosmetics/shop; lint-enforced. | PITFALLS C10 |
| Mobile card phase | Movement controls disabled, targets >=48px, `ScreenInsets` set explicitly. | PITFALLS C13 |
| Avatar normalisation scope (OQ-12) | **Resolved Phase 3: a canonical reference avatar (D-10).** `SpoonPlacement.check` takes no avatar argument. Residual risk is `M-09`, not an open question | Phase 3 context |
| Phase 3 Open Question 1 (spot validity under the real rules) | **Resolved STRICT (D-17):** every authored default spot must pass, no exclusions | Phase 3 context |
| Other | Min 3 players. Rounds = starting roster. Timing from server arrival, integer deciseconds. >=16 default spots per map. Native `TextChatService`. Native friend-join. | various |

Knock-on effects the roadmapper should carry into requirements:

- Hider turns are neutral in expectation only if the denominator is pinned (see Open Question 7).
- "Departed hider" and "returning joiner" both mean a forfeited hider turn. A player who leaves and rejoins is a joiner (derived default, confirm).
- FEATURES' participation-reward and daily-login ideas must be redesigned **without currency** or dropped.

---

## Cross-Cutting Consensus (high confidence)

Where two or more researchers independently arrived at the same answer. Confidence is HIGH on the design conclusion. The specific Roblox mechanism noted in each row is MEDIUM until re-verified.

| # | Conclusion | Agreement | Caveat |
|---|-----------|-----------|--------|
| 1 | **Card engine is pure, headless, synchronous, with property/fuzz tests and a bot pacing simulator, built before any UI or networking.** One command mutates exactly one hand and one inbox. No yields in `apply`. Events returned, published after mutation. | STACK, ARCH, PITFALLS (C2, C3, M10, "do first"), PROJECT. FEATURES calls it the core engine risk. | Disagreement on file location and test runner (Contradiction 1). |
| 2 | **Hidden spoon positions are never Instances in Workspace** or any replicated container, attribute or Value. The server holds spoons as data and reveals one per client on range plus line of sight (about 5 Hz). Same for hands, piles and default spots. | ARCH (Pattern 3), PITFALLS (C1), FEATURES (INTEG-02), PROJECT. STACK agrees on the goal but leaned on StreamingEnabled (Contradiction 2). | Client-local pickup affordance is unverified (V-22). |
| 3 | **Map contract plus automated validator exist before the five maps are built.** The validator must run every authored default spot through the **real placement rules**, so autofill can never produce an unfindable spoon. One reference map first. No per-map code branches. | ARCH (section 6), PITFALLS (C8, C14), FEATURES (MAP-02, dependency notes). | Structural checks can ship in Phase 1. The placement-rule check needs Phase 3. |
| 4 | **Plain `RemoteEvent`s behind one typed `Net` module.** Intents not state, server resolves targets, stable card IDs, per-player token bucket, reliable events for state, no server-to-client `RemoteFunction`, no `UnreliableRemoteEvent` for state. Codegen libraries (Blink/Zap) only if profiling demands. | STACK, ARCH, PITFALLS (C7), PROJECT. | Rate-limit numbers are LOW and must be tuned in playtest. |
| 5 | **No invented soft currency.** | STACK, PITFALLS (M8), PROJECT. FEATURES dissented; overruled. | Open Question 11 covers the legitimate worry behind FEATURES' dissent (no-purchase players). |
| 6 | **Server arrival time is the only clock.** Absolute deadlines (not countdowns), round-ID token on every scheduled callback, idempotent one-way `endRound`, integer deciseconds. | ARCH, PITFALLS (C4), PROJECT. | `GetServerTimeNow` vs `os.clock` precision unverified (V-30). |
| 7 | **Seat removal is one generic operation** used for completion, disconnect and AFK. Cards are routed to the successor, never deleted. | ARCH, PITFALLS (C5), FEATURES (LIFE-04), PROJECT. | None. |
| 8 | **Server resolves the pass target at execution time.** Client never sends a target seat or hand index. | STACK, ARCH, PITFALLS (C2). | None. |
| 9 | **Spoon claim is synchronous**: check state, set `claimed` before any yield, server-known position only. | ARCH, PITFALLS (C6), FEATURES (INTEG). | Server-side position lag tolerance is LOW. |
| 10 | **Gameplay modules must not import cosmetics/shop.** Cosmetics are data on a frozen loadout snapshot. | All four, PROJECT. | Lint rule design is a Phase 1 item. |
| 11 | **ProfileStore for player data, Game Pass as recoverable ownership source.** Mutate in memory, persist at match end and on purchase. Never write match state. | STACK, ARCH, PITFALLS (C11, C12). | Exact API shape unverified (V-8). |
| 12 | **Raw Instance UI with a `Tokens` module and a single `Activated` input path.** Hand is a 2D ScreenGui, not world-space cards. | STACK, ARCH, PITFALLS (C13), FEATURES (UX-02). | None. |

---

## Contradictions Between Researchers (surfaced, not averaged)

| # | Disagreement | Positions | Recommendation |
|---|--------------|-----------|----------------|
| 1 | **Engine location and test runner.** | STACK: pure logic in `src/shared/`, tested with Jest-Lua, which "runs only inside Roblox". ARCH: engine in `server/engine/` (server-only, shuffle never shipped to clients), tested under Lune or the plain `luau` CLI. PITFALLS: Lune or Jest-Lua. | **Follow ARCH.** The 100k+-action fuzz across 8 table sizes and the Monte Carlo simulator need to run fast and headless in CI, which in-Studio Jest cannot do. Keep engine under `server/engine/` with zero Roblox API references (lint-enforced). Use a tiny in-repo test harness for engine tests so they do not depend on Jest. Keep Jest-Lua optional for Studio-side tests. Phase 1 must include a spike proving the engine's `require` style works under both Lune and Roblox, since Lune uses path requires. Unverified (V-4). |
| 2 | **Spoon visibility mechanism.** | STACK: keep spoons out of Workspace until hunt, "rely on StreamingEnabled with a modest radius", use `ProximityPrompt` for pickup. ARCH/PITFALLS: do **not** use StreamingEnabled as a secrecy tool, server-only data, client-local visuals. PITFALLS C1 explicitly rejects server-side `ProximityPrompt` on real spoon Parts. PITFALLS lists "real parts plus small streaming radius" as a fallback. | **Follow ARCH/PITFALLS/PROJECT.** PROJECT.md forbids replicated spoon Instances, so the PITFALLS fallback is out. Pickup must use a client-created prompt or button on the local-only visual, with server re-validation on `ClaimSpoon`. STACK's StreamingEnabled note is superseded for secrecy. StreamingEnabled remains a perf question (Open Question 9). |
| 3 | **Reachability method for placement rails.** | STACK and PITFALLS: `PathfindingService` reachability from the seeker spawn. ARCH: baked `WalkableGrid` flood-fill as primary, Pathfinding only as sampled verification (async, per-query, a spoon on a shelf is not a navmesh point). | **Follow ARCH** (reasoned against documented Pathfinding limits). Spike both on the maze in Phase 3 before locking. Needs phase research. |
| 4 | **Scope of avatar normalisation.** | PITFALLS: force a fixed `HumanoidDescription` scale on all characters at spawn. PROJECT.md: scale normalised "during placement validation". | Not settled. Treated as an open item (Open Question 12). The spawn-time version is cleaner but changes avatar identity for every player, so it is a product decision. |
| 5 | **Bot fill.** | FEATURES: high value for cold start, hunt bots costly, "strongly debatable". PITFALLS: avoid bot seekers (undermines hide-and-seek and scoring). PROJECT: deferred. | Keep deferred, but build the **bot-driven seat seam in Phase 2** (simulator bots use the same command API as humans). That makes dev/test bots free and keeps shipped card-only fill cheap later. |
| 6 | **VIP implementation.** | ARCH/STACK: game-pass-gated `TeleportService:ReserveServer` with identical code. FEATURES/PITFALLS: prefer Roblox native private servers, do not build a custom system. STACK flags native as unresearched. | Open (Open Question 14). Phase 7 research decides. |
| 7 | **Verification status of platform claims.** | ARCH marks `UnreliableRemoteEvent` limits and Pathfinding docs "Verified against Roblox reference (HIGH)" and lists `create.roblox.com` URLs as HIGH sources. STACK and PITFALLS state `create.roblox.com` was unreachable and their figures are search-snippet only. | **Carried here as MEDIUM pending re-fetch.** Not upgraded to HIGH. |
| 8 | **Superseded by PROJECT.md.** | Late-join policy (ARCH vs PITFALLS/PROJECT), departed hider (PITFALLS skip vs ARCH/FEATURES/PROJECT auto-fill), soft currency (FEATURES vs rest), jokers via deck-cap (PITFALLS C3 option b) vs simulator gate. | Resolved. PITFALLS' joker option (b) survives as a tuning knob: the simulator chooses the joker count, which can be low or zero. |

---

## Key Findings

### Recommended Stack

Tooling is conventional and low-risk. The one thing that must change from the raw STACK.md is the **test runner decision** (Contradiction 1). All version numbers are "pin at M0 after the tool resolves"; STACK.md itself says so.

**Core technologies:**
- **Luau `--!strict` everywhere**: cheapest bug prevention for a project developed largely without human playtesting.
- **Rojo 7.7.1 plus Rokit 1.2.0**: git is the source of truth. `$ignoreUnknownInstances` on Workspace so Rojo does not delete Studio-built maps. Maps kept as `.rbxm`. Scripts only via filesystem.
- **StyLua 2.6.0, Selene 0.32.0, luau-lsp 1.70.1**: format, lint, headless typecheck. CI gates plus a `rojo build` smoke test.
- **Lune (0.11.1) or the `luau` CLI**: headless engine tests and the pacing simulator (promoted by this synthesis; STACK listed Lune as optional).
- **Jest-Lua** (optional, in-Studio only) plus Wally 0.3.2 or pesde 0.7.4: Studio-side tests. TestEZ is archived.
- **ProfileStore (vendored single ModuleScript)**: session-locked player data; successor to ProfileService.
- **Plain `RemoteEvent` plus typed `Net` module**: no ByteNet/Blink/Zap/Warp unless profiling forces it (then Blink or Zap, not ByteNet/Warp).
- **Plain typed modules plus explicit state machine**: no Rodux, Matter or Charm for v1.
- **Raw Instance UI plus design tokens**: no React-Lua/Fusion/Vide/Iris for v1.
- **Game Passes** for permanent cosmetics and VIP, behind `Owns(player,itemId)` / `Prompt(player,itemId)`. Developer Products with profile ownership and a hardened `PurchaseId`-deduped receipt handler are the fallback if the catalog is too large to manage as passes.
- **Studio MCP**: pin `@chrrxs/robloxstudio-mcp` to an exact version behind one adapter module. Re-check whether the official built-in Studio MCP now covers screenshots and multi-client.

### Expected Features

Adjusted for PROJECT.md. FEATURES.md IDs retained for traceability.

**Must have (table stakes, v1):**
- Lobby with 3-player gate, intermission, parkour activity (LOB-01/03), equip station (LOB-02), VIP access (LOB-04)
- Roster freeze, visible hider order, leavers, abort below 3, AFK auto-pass, match end (LIFE-01..06)
- Authoritative card engine, neighbour labels, optimistic prediction with reconcile, accidental-pass protection, four-of-a-kind "starting gun" moment (CARD-01..05)
- Hider placement mode with live ghost, instant reasons, undo, early end; auto-fill from >=16 defaults; non-punishing parkour (HIDE-01..03)
- Glint and proximity pickup, spoons-remaining HUD, spectator, collisions off (HUNT-01..04)
- Breakdown scoreboard (bonus and find shown separately), podium (SCORE-01/02)
- Server authority, anti-ESP, remote hygiene (INTEG-01..03)
- Mobile-first layout, input-aware prompts, colour-blind-safe cards, scaling and low-end performance (UX-02..05), contextual first-run prompts (UX-01)
- Shop with preview, inventory, receipts (SHOP-01..04); five maps with authoring tools and no-repeat rotation (MAP-01..03)
- Leaderstats, native chat, native friend join (SOC-01..03)

**Promoted to v1 by PROJECT.md** (FEATURES had these as P2 or v1.x): dealer reveal flourish (CARD-06), podium spoon reveal with hider effect (HIDE-05), lobby loadout plinths (new), purchasable deal animations (new).

**Dropped or redesigned by PROJECT.md:** SHOP-05 (earn-only coins), PROG-02 (participation coins), PROG-04 (daily-login coins). Participation recognition, if wanted, must be non-currency (stats, badges).

**Should have (v1.x, trigger-based):** bot fill (LOB-05), reconnect-into-match (LIFE-07), leaderboards (SOC-05), badges (PROG-05), themed sets (SHOP-06), proximity audio/haptic cue (HUNT-05), hider spectate HUD (HIDE-04), joker callout (CARD-07).

**Defer (v2+):** rotating stock, gifting, Premium perk, quests/seasons, gamepad (unless demand), quick-chat, seasonal map skins.

**Requirements-list gaps.** PROJECT.md "Active" omits items the research calls table stakes. The roadmapper should add them:
- No-repeat random map rotation (MAP-03)
- Colour-blind-safe and legible card faces (UX-04, PITFALLS L6)
- Contextual first-run prompts (UX-01)
- Player-to-player collision groups off (HUNT-04)
- Client-ready barrier with timeout at phase start (PITFALLS M7)
- Per-phase chat channel muting for hider and finished players (PROJECT lists hider chat as out of scope, which means muting is required)
- Explicit device settings (disable Console/VR unless gamepad is built) and explicit `ScreenOrientation`
- Studio write-protection from production DataStores
- Leaderstats

### Architecture Approach

Functional core and imperative shell. A server-side `RoundStateMachine` (Lobby, MatchStart, [RoundSetup, Hide, Play, RoundScoring, Podium] x R, MatchEnd) drives services that call pure modules. `Play` is one state containing the card table and the hunt concurrently under one 5:00 cap. Public coarse state (phase, round, `PhaseEndsAt`) rides attributes on a `GameState` object. Private or fine state rides remotes. Match state is session-scoped and never persisted; only loadout, ownership and lifetime stats go to ProfileStore, written at match end.

**Major components:**
1. **CardEngine (pure)**: `SeatRing`, `Deque`, `Deck.build(seatCount, k, jokers)`, `HandRules`, `apply(cmd) -> {ok, reason, events}`; stable card IDs; `commandSeq`.
2. **CardTableService (shell)**: one ordered `CardIntent` remote with `seq`/`ackSeq`, owner-only `HandSync`, coalesced `TableSync` at 10-20 Hz, `RequestFullSync`.
3. **HuntService**: `SpoonRegistry` (plain data), `InterestManager` (about 5 Hz distance plus line of sight), atomic `ClaimService`, carried-spoon attach using the claimant's skin.
4. **HideService plus PlacementRules**: shared pure rules with injected world queries (client ghost advisory, server authoritative); baked walkable grid; stratified auto-fill from server-only default spots.
5. **MapService plus map contract**: clone `Geometry` only; `Data/` stays server-only; gameplay numbers global and not overridable per map.
6. **ScoringService**: append-only ledger keyed by `userId`; pure formulas; injected clock.
7. **RoundStateMachine, MatchService, RosterService**: deadlines, round-ID tokens, `userId`-keyed roster.
8. **PlayerDataService, CosmeticService, MonetizationService**: no import path from gameplay modules; loadout snapshot taken at `RoundSetup`.

**Key patterns:** command/result engine; public attributes versus private remotes; interest-managed secrets; identity by `userId`; single remote manifest.

**Observation not stated in any single file:** at deal time only the dealer's inbox holds cards (the deck). Every other seat's left pile is empty, so the first passes ripple down the chain from the dealer. Pacing at round start and positional advantage (seat order derives from find order) are therefore properties the simulator must measure explicitly, including a snowball check (does finishing well compound into a runaway lead?). This is a measurement requirement, not a reopening of the seat-order rule.

### Critical Pitfalls, Ranked by Cost-If-Wrong

| Rank | Risk | Cost if wrong | Likelihood | Mitigation in this plan | Phase |
|------|------|---------------|-----------|--------------------------|-------|
| 1 | **Cold start below the 3-player minimum.** New game, sparse CCU, servers sit at 1-2 players. | Existential. Not fixable by code alone. | HIGH | Parkour room doubles as lobby activity; server fill and friend-join; visible "waiting for N" gate. Decide bot fill with data, but design the bot seam in Phase 2 and decide before soft launch, not after. Marketing budget is outside code. | 2 (seam), 6, 8 |
| 2 | **Replication leak of hands, spoons or default spots.** Spoons as Workspace Parts, hands in Values, full-state remote, default-spot markers in replicated geometry. | HIGH recovery (rework visibility model, UI and spoons). Ruins a hide-and-seek game. | HIGH | Server-only spoon data plus `SpoonVisible` per-client messages (Phase 5). Lint and CI grep from Phase 1. Replication audit in the client DataModel is an exit gate for Phase 5 and again in Phase 8. | 1, 5, 8 |
| 3 | **Joker or deck unsolvable at some table size.** Wild completion strands the real fourth card and removes a wild from circulation; invisible at N=3, appears at 8-10. | MEDIUM recovery (constants hotfix) if caught pre-UI, expensive if tuning and feel were built on a bad deck. Stalls waste up to 5:00 for everyone. | MEDIUM-HIGH | Simulator gate in Phase 2 before any UI. Joker-blocker engine variant implemented behind a flag from day one (cheap because pure). Gate passes only at zero stalls for N=3..10. | 2 |
| 4 | **Purchasable cosmetics leaking into gameplay.** Glint colour, dull spoon skin as camouflage, ornate deck, collidable accessory, avatar scale, unbounded deal-animation length. | MEDIUM-HIGH. Trust and policy damage; refunds. Cheap to prevent structurally early, costly after SKUs ship. | HIGH | Import-graph lint (Phase 1), visual-only catalog schema, spoon template with luminance floor, fixed glint, deck template, accessory constraints, fixed-duration deal animation template, economy review gate. | 1, 5, 7, 8 |
| 5 | **Purchase or persistence loss.** Multiple `ProcessReceipt` owners, grant before save, no `PurchaseId` dedupe, Studio writing to production keys, load failure then default-data overwrite. | HIGH (paid items lost, review-bombing). | MEDIUM-HIGH | Game Pass primary (Roblox holds ownership). ProfileStore with Mock and a test universe in Phase 1. Single `PurchaseService`. Published-place purchase test. | 1, 7, 8 |
| 6 | **Card correctness races.** Stale hand index, yield inside a mutation, client-resolved pass target, double draw or pass, optimistic desync. | MEDIUM if the pure engine exists; catastrophic if logic leaks into handlers. | HIGH | Engine is pure and synchronous; card IDs; preconditions as idempotency; `seq`/`ackSeq`; conservation invariant asserted after every simulated action. | 2, 4 |
| 7 | **AFK or idle player stalls the whole circle.** One frozen seat drains upstream and starves downstream. | MEDIUM (state-machine work) but near-certain on Roblox and wrecks a 9-player round. | VERY HIGH | Auto-pass then bench, implemented through the same `remove(Left)` path as disconnect. Fuzz with random AFK seats. Thresholds are open (Open Question 4). | 2, 4, 6 |
| 8 | **Round-end, timer and claim races.** Claim at the deadline, double `endRound`, stale `task.delay` from an earlier round, double-claim, last claim versus timeout. | LOW-MEDIUM (token guards). Scoring correctness is the user-visible harm. | HIGH | Absolute deadline checked lazily in every handler, round-ID token, idempotent `endRound`, claim sets `claimed` before any yield, injected-clock boundary tests at deadline -1/0/+1. | 1, 5 |
| 9 | **Placement rails fail (false negatives or positives) and hiders are incentivised to defeat them.** | LOW-MEDIUM if maps-as-data; high player frustration. | HIGH | Placement corpus, shared rule data with client preview, `placementEpoch`, stratified auto-fill, unfound-at-timeout telemetry. | 3, 6, 8 |
| 10 | **Mobile layout and performance.** 5 cards plus 2 piles versus thumbstick; low-end Android memory; leaked map instances. | MEDIUM (re-layout, device matrix). | VERY HIGH | Controls disabled in card phase, >=48px, `ScreenInsets`, phone-resolution capture of every screen, real low-end device test, full map teardown each round. | 4, 8 |
| 11 | **Match length and drop-off.** 10 rounds with idle finishers. | MEDIUM. Mitigated by the decided early-end rule. | HIGH | Round ends on last claim; spectate and live feed; hider EV versus seeker EV simulation. | 6, 8 |

---

## Implications for Roadmap

One reconciled sequence of **8 phases**. This merges ARCHITECTURE's L0-L4 layering (7 slices) and PITFALLS' P1-P8 tags into a single order. Phases 2 and 3 run in parallel, and Phases 4 and 5 run in parallel. The pure card engine and simulator are Phase 2, the earliest point the joker decision can be taken.

### Phase 1: Foundations, Contracts and Spec Lock

**Rationale:** Net schema, Config and the MapSpec contract invalidate all parallel work if changed later. This is the only strictly sequential phase, and it is small.
**Delivers:**
- Rojo project, pinned toolchain, CI gates (`stylua`, `selene`, `luau-lsp analyze`, `rojo build`).
- `Config` with every decided number, unit-tested against the worked examples (1600 find points; 800 + 600 = 1400; seeker ceiling 4000).
- `Net` gateway: typed manifest, schema checks, phase and role gating, token bucket, no `RemoteFunction`, dev remotes env-gated.
- `RoundStateMachine` skeleton: absolute deadlines, round-ID tokens, idempotent `endRound`, injectable clock, per-round cleanup scope, `RosterService` keyed by `userId`.
- Lints: engine purity, gameplay-to-cosmetics import ban, no secrets in replicated containers, no debug remotes.
- `MapSpec` contract v1, structural validator, gray-box reference map.
- ProfileStore vendored with Mock and a test universe, plus Studio write-protection.
- A written spec resolving the two BLOCKING open questions (1, 2), each expressed as a test.
- Engine test-runner spike (Contradiction 1).
**Addresses:** INTEG-01/03, LIFE-06, M9 config, persistence skeleton (PROG-01).
**Avoids:** C4, C7, C9, C10 (structural), C12 (skeleton), M6, M9.
**Research flag:** Skip deep research. Do a verification pass on tool versions and run the Lune/Roblox `require` spike (V-1 to V-6).

### Phase 2: Card Engine and Pacing Simulator (joker gate), critical path

**Rationale:** Highest-risk and most testable component, with no dependency on Roblox. The joker decision cannot be taken until it exists. Parallel with Phase 3.
**Delivers:**
- `SeatRing` (circular doubly-linked list), `Deque`, `Deck.build(seatCount, k, jokers)`, `HandRules`, `CardEngine.apply`.
- `remove(Completed | Left)`, an `autoPass` command, and the pure seat-order and dealer function (previous find order, roster, hider, collision rule).
- Fuzz and property suite:
  - Conservation invariant after every action: `sum(hands) + sum(inboxes) == initial - 4 x completions`.
  - 100k+ actions per table size, for seekers 2..9 (N=3..10).
  - Ring sizes 3, 2, 1, 0; random leavers and AFK seats; mid-pass leave; deterministic seeds.
- Bot pacing simulator with parametrised human reaction-time distributions. It measures:
  - Time to first completion and completion-order spread.
  - Stall rate and joker effect.
  - Positional advantage by seat and snowball effect.
  - Start-up latency (only the dealer's inbox is non-empty at deal).
- **Gate G1:** joker-as-wild ships only at zero stalls for N=3..10 at the chosen `(k, jokers)` with acceptable pacing. Otherwise switch to the joker-blocker variant. Both variants live behind a flag from the start. Output goes into `Config`.
- Bot-driven seat seam: sim bots use the same command API as humans (reused for soak tests and optional shipped fill).
**Addresses:** CARD-01, LIFE-04 (engine side), CARD-07 (partly).
**Avoids:** C2, C3, C5 (seat removal), M3 (interval constant), M10.
**Research flag:** YES for simulator design (stall definition, pacing targets, bot model). This is domain design, not API research. No external docs exist for this variant.

### Phase 3: Placement Rules, Map Pipeline and Validator (parallel with Phase 2)

**Rationale:** The validator that proves default spots obey the real placement rules must be green before maps 2-5 are authored. Independent of the card engine.
**Delivers:**
- `PlacementRules` (shared, pure, injected world queries), walkable-grid bake or Pathfinding, decided by a maze spike.
- `MapService` (clones `Geometry` only), stratified auto-fill.
- Validator v2: every default spot run through the real rules, >=16 usable after exclusions, play-volume and reachability checks, no scripts in Geometry.
- Placement corpus of known-good and known-bad coordinates.
- The avatar-normalisation decision (Open Question 12).
- Reference map plus a maze bake stress test.
**Addresses:** MAP-02, HIDE-02 (data side), INTEG-02 (default-spot secrecy).
**Avoids:** C8, C14, C1 (default-spot leak).
**Gate G2:** validator green on the reference map and passes the corpus.
**Research flag:** YES. Grid versus Pathfinding, StreamingEnabled effect on client preview, Lune-based CI validation (V-17 to V-20).

### Phase 4: Live Card Table (server shell, prediction, PC and mobile UI) (parallel with Phase 5)

**Rationale:** Needs Phase 2. Can run without Phase 5 using stubbed completion events.
**Delivers:**
- `CardTableService`: ordered `CardIntent` remote, `seq`/`ackSeq`, owner-only `HandSync`, coalesced `TableSync`, `RequestFullSync`.
- AFK auto-pass wired in.
- 2D card UI: 5 cards plus 2 piles, neighbour labels, persistent selection (no hover), tap-select then tap-pass with accidental-pass protection.
- Default movement controls disabled in the card phase; >=48px targets; `ScreenInsets` set explicitly.
- Four-of-a-kind stinger and feed; unmistakable joker art; colour-blind-safe faces.
- Basic deal flourish hook (the purchasable variants come in Phase 7).
- Tested at 150-300 ms simulated lag and on a real phone early.
**Addresses:** CARD-02..05, LIFE-04, UX-02..04.
**Avoids:** C2 (client side), C13, M4, L3, L4.
**Research flag:** Light. Verify same-remote ordering and the `PlayerModule` control-disable mechanism (V-12, V-26). Otherwise standard.

### Phase 5: Hunt, Anti-ESP, Claim and Scoring (parallel with Phase 4)

**Rationale:** Needs Phase 3 and the FSM only. Runs against auto-filled spoons and a stub completion trigger. Putting the anti-ESP model in before the hide UI exists is deliberate: it is the most expensive thing to retrofit.
**Delivers:**
- `SpoonRegistry` as data only.
- `InterestManager` (about 5 Hz, hysteresis), per-client `SpoonVisible`/`SpoonHidden`, client-local visuals and pickup affordance.
- Atomic `ClaimService` (`claimed` set before any yield, server-known position, latency slack), carried spoon with the claimant's skin.
- Fixed non-purchasable glint constants; spoon-skin template and luminance floor defined as an art spec.
- `ScoringService` ledger and formulas: four-of-a-kind bonus, find points, hider survival.
- Round end on last claim; collision groups; spectator basics.
**Exit (Gate G3):** one map, 3-10 clients or bots, full loop cards to hunt to score, replication audit clean in client DataModel mode, claim race test yields exactly one winner.
**Addresses:** HUNT-01..04, INTEG-02, SCORE-01 (ledger), HUNT-06.
**Avoids:** C1, C4, C6, C10 (glint).
**Research flag:** YES. Client-local prompt feasibility, server-side position lag, time source (V-21 to V-23, V-30).

### Phase 6: Hide Phase, Match Lifecycle and Churn

**Rationale:** Integrates the settled flow rules. Needs 3, 4 and 5.
**Delivers:**
- `HideService` with free-placement UI (centred reticle, ghost, instant reason, undo, spoons-remaining, early end), `placementEpoch`, 90s cap, stratified auto-fill, departed-hider path (no points, round runs).
- Parkour waiting room (catch floors, no kills), 3-player lobby gate and intermission, shared podium stage.
- Match layer: roster freeze, hider rotation, seat-order and dealer carry-over, joiner queue, leaver cleanup, abort below 3.
- AFK bench, scoreboard with bonus and find shown separately, baseline podium (top 3 by round score, about 10 s) with unfound-spoon reveal, ready barrier, chat channel muting, no-repeat map rotation, match end.
- A hider-versus-seeker expected-value simulation to confirm the "neutral in expectation" claim.
**Gate G4:** scripted churn scenarios pass (hider gone, drop below 3, joiner in every phase, rejoiner, everyone leaves, character reset at the table).
**Addresses:** LIFE-01..05, HIDE-01..03, SCORE-02, LOB-01/03, HUNT-03, M7.
**Avoids:** C5, C8, M1, M5, M6, M7, M11.
**Research flag:** Light. `TextChatService` channel permissions, spectate. Standard FSM patterns.

### Phase 7: Content and Monetization (two independent tracks)

**Rationale:** Breadth after the loop is proven. The two tracks share no code.
**Track 7a: Maps 2-5** (hotel, restaurant, mansion, office; maze finalised). Each map is its own work item against the contract. Each must pass the validator, stay within a time-to-first-find band, and carry sanitised assets. This track can start any time after Gate G2 and run alongside Phases 4-6.
**Track 7b: Cosmetics, shop and VIP.**
- Catalog schema with visual fields only; loadout snapshot at `RoundSetup`.
- Shop with preview-before-buy behind `Owns/Prompt`; Game Pass backend, Dev Product backend only if the catalog size demands it.
- Spoon skins (template plus contrast test on all maps), deck skins (template), deal animations (fixed-duration template), character cosmetics (non-collidable, size caps), hider effects, podium cosmetics.
- Podium spoon reveal with hider effect, dealer reveal flourish, lobby showcase plinths, VIP access.
- Persistence and the `Owns/Prompt` interface start earlier as a floating track (from Phase 2) because they have no gameplay dependency.
**Avoids:** C10, C11, C12, C14, M8.
**Research flag:** YES for 7b (`ProcessReceipt` vs `BindReceiptHandler`, `UserOwnsGamePassAsync` lag, pass-creation path, VIP route, ViewportFrame preview cost). Standard for 7a beyond the validator.

### Phase 8: Parity, Hardening and Soft Launch

**Rationale:** Final verification gates. Data-dependent decisions are taken here.
**Delivers:**
- Device matrix (phone-resolution capture of every screen, real low-end Android at 60 FPS with 10 players, memory flat across 10 rounds).
- 10-bot-client soak, anti-exploit audit (remote inventory, client-DataModel replication audit, movement-sanity thresholds with real latency data), rate-limit tuning.
- `robux-economy-review` and a published-test-place purchase test.
- Telemetry (unfound-at-timeout per map, round-length distribution, drop-off round), the cold-start/bot-fill decision on lobby-wait data, and the Game Pass vs Developer Product call once catalog size is known.
**Gate G5:** economy review is not DO NOT SHIP and the purchase test is green.
**Avoids:** C6, C7, C13, M2, M3, M8.
**Research flag:** YES for movement thresholds and the client-anti-tamper state (V-23, V-32). Light otherwise.

### Phase Ordering Rationale

- **Engine before everything gameplay-shaped.** It is simultaneously the highest-risk and most testable component, and the joker gate and the `Deck.build` constants (which feed `Config`) come out of it.
- **Placement and map pipeline in parallel with the engine.** They share only Phase 1's contracts. The validator's "real placement rules" check forces placement before maps 2-5, and the maze is the worst-case bake so it is tested first.
- **Anti-ESP before the hide UI.** Retrofitting the spoon visibility model after spoons exist as Parts is the most expensive retrofit in the project, so the hunt (Phase 5) is built on auto-filled data spoons before the hider UI (Phase 6).
- **Vertical slice before breadth.** Gate G3 puts the core-value loop (scramble flowing into the hunt) in front of playtesters before the five maps and the cosmetic catalog.
- **Cosmetics last, constraints first.** The import-graph lint, visual-only schema and spoon template are Phase 1 and 5 work, so late cosmetic work cannot violate the monetization-integrity rule.

### Parallelization Map

```
P1 (sequential)
  |
  +--> P2 Card engine + simulator + joker gate  ----+
  |                                                 +--> P4 Live card table  --+
  +--> P3 Placement + map pipeline + validator --+--+                           +--> [G3 vertical slice] --> P6 --> P8
  |                                              +-----> P5 Hunt/anti-ESP/scoring --+                          ^
  |                                              +-----> P7a Maps 2-5 (any time after G2) --------------------+
  +--> Floating track: ProfileStore, catalog schema, Owns/Prompt, MonetizationService (P2 onward) --> P7b ------+
```

Safely parallel: P2 with P3; P4 with P5; P7a with P4-P6; the floating persistence track with everything. Strictly sequential edges: P1 before all; P2 before P4; P3 before P5 and before P7a maps 2-5; P4 and P5 before P6; P6 before P8.

### Research Flags Summary

- **Needs `/gsd-research-phase`:** Phase 2 (simulator design), Phase 3 (reachability, StreamingEnabled, Lune CI), Phase 5 (client-local pickup, position lag, time source), Phase 7b (receipts, passes, VIP, previews), Phase 8 (movement thresholds, anti-tamper).
- **Light or verification only:** Phase 1 (toolchain and runner spike), Phase 4 (ordering, controls disable, ScreenInsets), Phase 6 (chat channels).
- **Standard patterns, skip research:** Phase 7a map authoring beyond the validator.

---

## Open Questions (genuinely undecided after PROJECT.md)

"Blocking" is relative to the card engine (Phase 2). Items marked NON-BLOCKING list the phase that needs them.

| # | Question | Status | Recommended default | Needed by |
|---|----------|--------|--------------------|-----------|
| 1 | **Deal-time four-of-a-kind.** Check is on draw only, so a seat dealt a complete set completes on its first draw (a free instant finish). Re-deal, or allow? | **BLOCKING** | Re-shuffle until no seat starts complete (including wild-completable hands). Test it. | P1 spec |
| 2 | **Which four cards leave on completion** when a 5-card hand has jokers plus naturals, or all four are jokers? Which card is the fifth? | **BLOCKING** | Spend naturals first, keep jokers circulating (ARCH design call). Four jokers count as a set only if the simulator says it is safe. | P1 spec, P2 |
| 3 | **Card pool composition and pacing target.** Ranks per seat count (`seatCount + k`), joker count, and what counts as acceptable time-to-first-completion. | NON-BLOCKING for engine code (parameterised). It is the simulator's output and the gate's pass criteria. | Resolve by simulation, not by argument. | P2 |
| 4 | **AFK thresholds.** Idle seconds before auto-pass, which card auto-pass chooses, strikes before bench, what bench does (remove seat, spectate). | NON-BLOCKING for engine (engine exposes `autoPass` and `remove(Left)`). | Auto-pass a random non-set card after a timeout, bench after N strikes via the `Left` path. Tune in playtest. | P4, P6 |
| 5 | **Match tiebreak** for equal totals. | NON-BLOCKING | Pick one deterministic rule (for example higher best-round, else earlier four-of-a-kind placement). Needs owner choice. | P6 |
| 6 | **Seat order inside "everyone else"** (previous hider, returning joiners) and round-1 order beyond the random dealer. | NON-BLOCKING | Deterministic: previous hider, then joiners by join order, tiebreak by `userId`. Round 1 seeded random. | P2 spec |
| 7 | **Hider-score denominator.** "Fraction of the round" is ambiguous when the round ends early on the last claim. Is it survival over the fixed 300 s, over actual elapsed time, and when does the survival clock start (card-phase start or first completion)? With elapsed time, the last spoon always survives 100 percent. | NON-BLOCKING for engine. Blocks P5 scoring and the neutral-EV claim. | Fixed 300 s on the same timeline as find points; unfound spoons survive to round end. Owner to confirm; validate with the EV simulation. | P5, P6 |
| 8 | **Mid-round leaver effects.** Abort below 3 immediately or finish the round? Retract a spoon if a seeker leaves before finding one? What do aborted matches award? | NON-BLOCKING | Finish the round then end with current totals; no retraction (spoons fixed at round start); no win credit on abort. Owner to confirm. | P6 |
| 9 | **StreamingEnabled suitability** for large maps (mansion, maze). It is a performance feature, not a secrecy tool. | NON-BLOCKING | Decide with real-phone tests; client preview may disagree with server (server wins). | P3, P8 |
| 10 | **Anti-teleport movement thresholds** and claim distance tolerance. | NON-BLOCKING | Sample about 4 Hz, rubber-band and log, escalate on repeats; tolerance about `walkSpeed x rtt`. All LOW until measured. | P5, P8 |
| 11 | **Free or earned cosmetics without a currency.** PROJECT says direct purchase only, but a shop with nothing free for non-buyers risks reading as predatory (FEATURES, PITFALLS M8). | NON-BLOCKING | Decide a baseline free set and whether any items are unlocked by achievement (podium finishes, badges) rather than coins. | P7 |
| 12 | **Avatar scale normalisation scope.** Only during placement validation (PROJECT), or force fixed scale for all characters at spawn (PITFALLS)? | NON-BLOCKING | Prefer spawn-time normalisation if the product accepts it; otherwise validate on a canonical reference avatar. | P3 |
| 13 | **Bot fill.** Whether to ship labelled, stats-excluded card bots, and for which roles. | NON-BLOCKING; high-cost decision. | Dev/test bots from P4; shipped decision on lobby-wait telemetry, before soft launch. | P6-P8 |
| 14 | **VIP route.** Roblox native private servers or a coded reserved-server lobby. | NON-BLOCKING | Research native first; custom only if it fails. Keep VIP out of any public rankings. | P7b |
| 15 | **Game Pass vs Developer Product switch point.** Pass creation is a manual Creator Hub step (human gate); dozens of individually priced items are tedious as passes. | NON-BLOCKING | Count the catalog first. `Shop` stays behind `Owns/Prompt` so the backend is swappable. | P7b, P8 |
| 16 | **Deal-animation and podium-reveal timing.** Does the 5:00 clock (and hider survival) start at animation start or at pass unlock? What is the maximum duration? | NON-BLOCKING | Clock starts at unlock for everyone. Enforce one fixed duration across every purchasable variant (template), as with spoon skins, so animation length is not a lever. | P4, P7b |
| 17 | **Player cap.** 10 is implied by the simulator range (N=3..10) and the 9-seat anchors, but not stated as a constraint. | NON-BLOCKING | State it explicitly in requirements. | P1 |
| 18 | **Rejoin policy.** A leaver who rejoins is treated as a joiner and forfeits any unplayed hider turn (derived from "joiners never hide"). Reconnect-into-match is not in v1 scope. | NON-BLOCKING | Confirm the derived default. | P6 |

---

## Verification Debt

The container blocked `create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`, `madstudioroblox.github.io` and `jsdotlua.github.io`. **First action: add those hosts to the environment's allowed domains.** GitHub release and README pages were reachable. Nothing below has been upgraded from its source confidence. **Phase 3 re-check note (2026-11-04):** `create.roblox.com` was reachable only via `curl` on `.md` URLs (`WebFetch` failed); `madstudioroblox.github.io`, `jsdotlua.github.io` and `lune-org.github.io` remained unreachable. No confidence level was raised that could not be re-sourced.

**Tooling and workflow**

| ID | Claim | Source and stated confidence | Re-check at |
|----|-------|------------------------------|-------------|
| V-1 | Pinned versions (Rojo 7.7.1, Rokit 1.2.0, Wally 0.3.2, Lune 0.11.1, StyLua 2.6.0, Selene 0.32.0, luau-lsp 1.70.1 / Luau 0.740, pesde 0.7.4). Years for Rojo, Rokit and Lune were inferred. Only StyLua, Selene, luau-lsp and pesde carried explicit 2026 dates. | STACK, HIGH/MEDIUM | P1: let `rokit add` resolve and pin the result |
| V-2 | Jest-Lua runner package version; `wally-package-types` version | STACK, unverified | P1, only if Jest is used |
| V-3 | ProfileService is "not receiving updates" (no official deprecation notice found) | STACK, MEDIUM | P1 |
| V-4 | Jest-Lua runs only inside Roblox; Lune runs engine code and reads Roblox model files; the CI map-validation workflow built on that | STACK vs ARCH, MEDIUM / unverified. **Phase 3 (2026-11-04): ANSWERED by a spike and independently re-verified by the orchestrator. HIGH for what was tested.** Under Lune 0.11.1 `CanCollide`, `CFrame.UpVector` and `CFrame.RightVector` all read correctly from a deserialized Part; only the derived `Position` fails (assumption A5). `Part.Shape` reads but a `Ball` Part still has className `"Part"`. The graybox Ramp reads `UpVector = (0.421, 0.907, 0)`, `acos(0.907) = 24.90 deg`, the true angle, and plan 03-01's graybox case asserts it every CI run. D-02 and D-03 needed no workaround. Not re-sourced from primary docs (`lune-org.github.io` unreachable); the evidence is behavioural | P1 spike, P3 (done) |
| V-5 | Chrrxs MCP tool list and pin; official Studio MCP "cannot screenshot" may be stale after the Aug 2026 update | STACK, MEDIUM | P1 |
| V-6 | Rojo `$ignoreUnknownInstances` behaviour on Workspace | STACK, MEDIUM, not re-verified | P1 |
| V-7 | Open Cloud Luau Execution rate limits (docs conflicted, 5/min vs 45/min) | STACK, unverified | Only if CI test execution is adopted |

**Persistence and monetization**

| ID | Claim | Source and stated confidence | Re-check at |
|----|-------|------------------------------|-------------|
| V-8 | ProfileStore API shape (`New`, `StartSessionAsync`, `Reconcile`, `AddUserId`, `OnSessionEnd`, `EndSession`, Mock). Wiki unreachable. | STACK, MEDIUM | P1 first use |
| V-9 | Session-lock steal after a crash takes about 80 s | PITFALLS, LOW (forum claim) | P1, P8 |
| V-10 | DataStore budgets (about 60 + 10 per player per minute), `BindToClose` grace about 30 s, Extended Services pricing | PITFALLS LOW-MEDIUM; STACK LOW-MEDIUM | P1, P7 |
| V-11 | `ProcessReceipt` is a single callback per game; `BindReceiptHandler` is the newer alternative; receipts polled about every 10 s; a Sep 2026 "ProcessReceipt needs a fix" banner | STACK MEDIUM / LOW | P7b |
| V-11a | `UserOwnsGamePassAsync` lag after purchase (about 10 s reported); `PromptGamePassPurchaseFinished` is a trigger only | STACK, MEDIUM | P7b |
| V-11b | Pass-creation API via Open Cloud; Studio "API Services" writes to production DataStores | STACK (not verified), PITFALLS (training) | P7b, P1 |
| V-11c | Subscription API names (`GetUserSubscriptionStatusAsync`, `PromptSubscriptionPurchase`) | STACK, snippet | Only if subscriptions are considered |
| V-11d | Paid Random Items policy details and regional gating | FEATURES/PITFALLS, snippet MEDIUM | Moot (no crates); re-check if that ever changes |
| V-11e | Native private-server options and pricing; `TeleportService` reserved-server reconnect; `SocialService:PromptGameInvite`; badge creation fees | FEATURES, STACK, PITFALLS | P6, P7b |

**Networking and runtime**

| ID | Claim | Source and stated confidence | Re-check at |
|----|-------|------------------------------|-------------|
| V-12 | Same-remote ordering guarantee for `RemoteEvent` (cross-remote not guaranteed) | ARCH, explicitly not verified | P4: test in Studio |
| V-13 | Signal deferred vs immediate default | ARCH, LOW (engine avoids depending on it) | P4 |
| V-14 | `UnreliableRemoteEvent` 900-byte cap and about 500 invocations/s limit per client per remote | STACK HIGH, ARCH HIGH; but see Contradiction 7, treated as MEDIUM | P1 |
| V-15 | Single-threaded atomicity of non-yielding handlers; instance/attribute replication scope | ARCH, MEDIUM, established practice | P2, P5 |
| V-16 | Studio local multi-client cap (historically 8) vs the 10 needed; MCP `multiplayer_playtest` client count | PITFALLS, unverified | P4, P8 |

**Hide and hunt**

| ID | Claim | Source and stated confidence | Re-check at |
|----|-------|------------------------------|-------------|
| V-17 | `PathfindingService:ComputeAsync` limitations (agent params, vertical placement, async) | ARCH, MEDIUM-HIGH. **Phase 3: RETIRED for this phase by D-05; no `PathfindingService` is used.** Its documented defaults (`AgentRadius` 2, `AgentHeight` 5) served only as a cross-check on the capsule sizing. Still relevant to Phase 5's hunt if it ever pathfinds | P3 (retired) |
| V-18 | `FindPartOnRay` legacy; use `Workspace:Raycast` | ARCH, MEDIUM. **Phase 3: RETIRED for this phase by D-01 (the rules use no Roblox raycast). OPEN AGAINST PHASE 5, more sharply than before: `RaycastParams.RespectCanCollide` defaults to `false`, the OPPOSITE of D-03's model.** Phase 5's line-of-sight raycast must set it `true`, or CI and the live game will disagree about what blocks sight and a validated spot can hide a spoon in play. Confidence in the default: HIGH (read from `create.roblox.com` via `curl` on `.md` URLs) | P3 (retired), **P5 (OPEN)** |
| V-19 | Server-set character scale via `HumanoidDescription`; effect on reach and camera height | PITFALLS, training. **Phase 3: PARTLY CONFIRMED, MEDIUM / LOW, unchanged and not upgraded.** The `HumanoidDescription` scale mapping, the HipHeight formula and classic proportions came from primary docs (MEDIUM). **Per-axis scale limits, the R15 default HipHeight and any camera-height formula were NOT found**; the 90-105% height / 70-100% width figures came from a web-search summary (LOW). D-10's canonical capsule makes placement validity scale-independent by construction (arity lock, gate 6), but whether the capsule bounds real avatars is unverified: D-11's bias toward rejecting is the mitigation, not a verification. Human gate: `M-09` (unsigned, not blocking Phase 3). No confidence raised because the primary source could not be re-fetched | P3 (partly), M-09 |
| V-20 | `StreamingEnabled` interactions with client raycasts for placement preview | PITFALLS/ARCH, training. **Phase 3: deferral to Phase 6 confirmed sound; MEDIUM-HIGH.** This phase's rules run over a snapshot of `ServerStorage.Maps[mapId]`, never Workspace, so they have no streaming dependence. The client-preview question stays with Phase 6 | P3 (deferral confirmed), P6 |
| V-21 | `PhysicsService` collision-group setup for player-player collisions off | PITFALLS, training | P5 |
| V-22 | **Client-created `ProximityPrompt` or button works as the sole pickup affordance on a local-only visual** (STACK assumed a server `ProximityPrompt`, which PROJECT.md now forbids) | PITFALLS/STACK, unverified | P5 |
| V-23 | Server-known `HumanoidRootPart` position lags client-owned characters; slack of a few studs suffices | ARCH, LOW | P5, P8 |
| V-30 | `workspace:GetServerTimeNow()` vs `os.clock()` precision and monotonicity for deciseconds scoring | ARCH/PITFALLS, training | P1, P5 |

**UI and platform**

| ID | Claim | Source and stated confidence | Re-check at |
|----|-------|------------------------------|-------------|
| V-24 | `ScreenInsets` enum values and behaviour | STACK/PITFALLS, MEDIUM-HIGH (snippets) | P4 |
| V-25 | Roblox mobile minimum target size (48 px used; 44 px is a third-party guideline) | STACK/FEATURES, not verified | P4 |
| V-26 | Disable default controls via `require(PlayerScripts.PlayerModule):GetControls():Disable()` still works | PITFALLS, MEDIUM | P4 |
| V-27 | `ContextActionService` mobile button behaviour; `GuiService.SelectedObject` for gamepad | FEATURES, training | P4 |
| V-28 | `Players.CharacterAutoLoads = false`, `ResetButtonCallback` via `SetCore`, console/VR device settings, `ScreenOrientation` | PITFALLS, training | P6, P8 |
| V-29 | `TextChatService` per-channel muting; chat age check (Jan 2026) | FEATURES MEDIUM, PITFALLS training | P6 |

**Security and design**

| ID | Claim | Source and stated confidence | Re-check at |
|----|-------|------------------------------|-------------|
| V-31 | Client-server boundary guidance (validate values, rate limit server-side) | PITFALLS, MEDIUM-HIGH (snippet) | P1 |
| V-32 | Client anti-tamper (Hyperion) state | PITFALLS, MEDIUM-LOW | P8 |
| V-33 | Comparable-game conventions (MM2, Flee the Facility, NDS) | FEATURES, LOW-MEDIUM | Not required |
| V-34 | Latency figures (50-150 ms PC, 100-250 ms mobile), tap rates, glint and pickup radii, 5 Hz interest rate, rate-limit numbers (burst 8 / 8 per s) | ARCH LOW; STACK starting points | Tune in P4, P5, P8 |
| V-35 | A simulated-bot model's reaction-time distribution represents humans | Sim design, unverified | Calibrate against real playtests (P4/P6) |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Tool choices are well-reasoned and consistent with the `roblox-ai-build` skill (HIGH). Versions are MEDIUM (some years inferred). Roblox platform APIs (ProfileStore, receipts, game passes) are MEDIUM because doc hosts were unreachable. |
| Features | MEDIUM | HIGH on the project-specific interaction analysis (derived from PROJECT.md). MEDIUM-LOW on comparable-game inventories (search returned SEO spam). Several recommendations (coins) are now overridden. |
| Architecture | MEDIUM | HIGH on card-engine topology (derived from the project's own rules and the shape of the ring). MEDIUM on Roblox platform patterns. LOW on latency numbers and unverified engine behaviours (remote ordering, signal mode). |
| Pitfalls | MEDIUM | HIGH on design-derived reasoning (races, solvability, spec holes, cosmetic leakage). MEDIUM on platform facts from training knowledge and snippets. |

**Overall confidence:** MEDIUM. The *design* is better specified than typical greenfield (PROJECT.md closed most gaps), so planning risk is low. The *platform-fact* layer is the thing that is not yet trustworthy, and it should be re-verified at the start of each phase that touches it.

### Gaps to Address

- **Joker solvability is unproven.** Handle through the Phase 2 gate. Do not build UI polish for joker presentation until G1 passes.
- **Pacing targets are undefined.** Phase 2 must pick or request a target time-to-first-completion, or the gate has no pass criterion.
- **Hider-score denominator** (Open Question 7). Resolve before Phase 5 scoring; validate neutrality with the Phase 6 EV simulation.
- **Reachability method** (Contradiction 3) and **avatar scaling** (Contradiction 4) are Phase 3 decisions backed by spikes on the maze.
- **Cold-start strategy.** Not solvable by code; needs an explicit owner decision and launch plan before Phase 8.
- **Real 9-10 player human playtest.** Studio multi-client is capped; the first true N=9/10 test needs a published place (human gate).
- **Platform-fact verification** (Verification Debt). Run at the start of each phase using the table's "Re-check at" column.
- **Requirements-list gaps** (Key Findings, Expected Features) should be folded into PROJECT.md Active before roadmap creation.

---

## Sources

### Primary (HIGH confidence)
- `.planning/PROJECT.md` (revised 2026-11-02): design, scoring, monetization rules, settled decisions.
- GitHub release pages: rojo-rbx/rojo (7.7.1, 7.7.0 syncback), pesde-pkg/pesde (0.7.4, 09 Sep 2026), JohnnyMorganz/StyLua (2.6.0), Kampfkarren/selene (0.32.0), JohnnyMorganz/luau-lsp (1.70.1, Luau 0.740). Local skills `roblox-ai-build` and `robux-item-design` / `robux-economy-review`.

### Secondary (MEDIUM confidence)
- GitHub: rojo-rbx/rokit (1.2.0, year inferred), UpliftGames/wally, MadStudioRoblox/ProfileStore README, jsdotlua/jest-lua README, lune-org/lune, 1Axen/blink, red-blox/zap, littensy/charm, jsdotlua/react-lua, Chrrxs/robloxstudio-mcp.
- Search-snippet excerpts of Roblox docs: client-server boundary (updated June 2026), UnreliableRemoteEvent, MarketplaceService reference, ScreenInsets, Pathfinding, adaptive design, DataStore limits page (2026-10-19).
- ProfileService developer-products tutorial (receipt dedupe, about 30 recent IDs).

### Tertiary (LOW confidence, needs validation)
- Comparable-game feature inventories (MM2, Flee the Facility, NDS); community benchmarks for networking libraries; DevForum threads (remote ordering, ProcessReceipt dedupe, "ProcessReceipt needs a fix" banner) not fetched; forum claims on session-lock steal time and `UserOwnsGamePassAsync` lag; training knowledge on DataStore budgets, `BindToClose` grace, Studio multi-client cap, anti-tamper state; all latency, tap-rate, radius and rate-limit starting values.

---
*Research completed: 2026-11-02*
*Ready for roadmap: yes. Fold the Requirements-list gaps into PROJECT.md Active, and resolve Open Questions 1 and 2 in the Phase 1 spec.*

---

## Structured return for the orchestrator

**Files synthesized:** STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md (all in `/home/user/robloxspoons/.planning/research/`), checked against PROJECT.md.

**Output:** `/home/user/robloxspoons/.planning/research/SUMMARY.md` was **not created**. The Write tool refused, so the orchestrator must write the content above. No commit was made, as instructed.

### Executive summary
Spoons is a server-authoritative party game whose core risk is the unproven card ring. Build it as a pure, headless engine with a bot pacing simulator first. That simulator also decides jokers-as-wilds versus jokers-as-blockers. Hidden state (hands, spoons, default spots) stays server-side and reaches each client only through interest management. Maps, placement rules and no-pay-to-win are enforced by contract, validator and import-graph lint.

### Roadmap implications (8 phases, one reconciled sequence)
1. **Foundations, Contracts and Spec Lock.** Sequential and small. Includes the Lune-versus-Roblox test-runner spike.
2. **Card Engine and Pacing Simulator (joker gate G1).** Critical path.
3. **Placement Rules, Map Pipeline and Validator.** Parallel with 2.
4. **Live Card Table (prediction and PC/mobile UI).** Parallel with 5.
5. **Hunt, Anti-ESP, Claim and Scoring.** Parallel with 4. The merge is the vertical slice (G3).
6. **Hide Phase, Match Lifecycle and Churn.**
7. **Content and Monetization.** 7a (maps 2-5) can start after G2. 7b is cosmetics, shop and VIP, with persistence as a floating track from Phase 2.
8. **Parity, Hardening and Soft Launch.**

### Research flags
- **Needs research:** Phases 2, 3, 5, 7b and 8.
- **Light or verification only:** Phases 1, 4 and 6.
- **Standard patterns:** Phase 7a, beyond the validator.

### Confidence
Overall MEDIUM. Design-level conclusions are HIGH. Platform facts are MEDIUM to LOW until the blocked hosts are reachable.

### Gaps and flags for the orchestrator
- **Blocking open questions for the engine (2):** deal-time four-of-a-kind, and which four cards leave on a joker completion. Both go in the Phase 1 spec.
- **Hider-score denominator is ambiguous** in an otherwise settled formula: fixed 300 s versus elapsed time, and when the survival clock starts. Recommend a fixed 300 s on the same timeline as find points, pending owner confirmation.
- **Researcher contradictions surfaced, not averaged:**
  - Engine location and test runner (resolved toward ARCH: `server/engine/` under Lune).
  - Spoon visibility mechanism (resolved toward PROJECT).
  - Reachability method (grid versus Pathfinding, spiked in Phase 3).
  - Avatar normalisation scope (left open).
  - VIP route (left open).
  - ARCH labels some platform claims HIGH while STACK and PITFALLS say the same hosts were unreachable (carried as MEDIUM).
- **Requirements-list gaps.** PROJECT.md Active omits several research-backed table stakes: map rotation, colour-blind-safe cards, a ready barrier, chat channel muting, collision groups, explicit device and orientation settings, and Studio write-protection. The summary lists them.
