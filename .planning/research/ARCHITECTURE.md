# Architecture Research

**Domain:** Server-authoritative Roblox round-based party game (real-time simultaneous card ring + hide-and-seek hunt)
**Researched:** 2026-11-02
**Confidence:** MEDIUM overall. HIGH on the card-engine topology (derived from the project's own rules, not from outside sources). MEDIUM on Roblox platform patterns (mostly established practice, only partly re-verified online). LOW on the latency numbers and on a few engine behaviors that must be measured in Studio (see "Verification Status").

Scope note: this file covers structure, boundaries, data flow and build order. Library and tool choices belong in STACK.md. Where this file names a tool (ProfileStore, Rojo, Lune) it is because the architecture depends on the capability, not as a final stack decision.

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│ CLIENT (per player)                                                      │
│  Controllers: Phase, CardTable (prediction), Hide (ghost preview),       │
│               Hunt (local glint/spoon visuals), Lobby/Loadout, Podium    │
│  UI: ScreenGui card view (radial opponents + own hand), HUD, menus       │
│  Input: one abstraction over mouse click / touch tap (same code path)    │
└───────────▲───────────────────────────────┬──────────────────────────────┘
            │ state: attributes (public,    │ intents only (no targets, no
            │ coarse) + RemoteEvents        │ positions of other seats):
            │ (private/fine)                │ Draw, Pass(cardId), PlaceSpoon,
            │                               │ ClaimSpoon, EndHide, Equip, Buy
┌───────────┴───────────────────────────────▼──────────────────────────────┐
│ SERVER: ServerScriptService/Server                                       │
│                                                                          │
│  ┌─ Orchestration ──────────────────────────────────────────────────┐    │
│  │ MatchService ─▶ RoundStateMachine ◀── RosterService (join/leave) │    │
│  └───────┬──────────────┬──────────────────┬────────────────────────┘    │
│          │ phase hooks  │                  │                              │
│  ┌───────▼─────┐ ┌──────▼───────┐ ┌────────▼────────┐ ┌────────────────┐ │
│  │CardTable    │ │HideService   │ │HuntService      │ │MapService      │ │
│  │Service      │ │ (placement,  │ │ (SpoonRegistry, │ │ (load/unload   │ │
│  │ (shell)     │ │  autofill)   │ │  InterestMgr,   │ │  MapSpec,      │ │
│  │   │         │ │    │         │ │  ClaimService)  │ │  walkable bake)│ │
│  │   ▼         │ │    ▼         │ └────────┬────────┘ └───────┬────────┘ │
│  │CardEngine   │ │PlacementRules│          │                  │          │
│  │ (pure core) │ │ (pure+queries│          │                  │          │
│  └──────┬──────┘ └──────────────┘          │                  │          │
│         │ events (FourOfKind, SpoonFound, RoundEnd...)        │          │
│  ┌──────▼───────────────────────────────────▼──────────────────▼──────┐  │
│  │ ScoringService (append-only round ledger → match totals)           │  │
│  └──────┬─────────────────────────────────────────────────────────────┘  │
│         │ at MatchEnd only                                               │
│  ┌──────▼──────────────────────────────────────────────────────────┐     │
│  │ PlayerDataService (ProfileStore) ◀── MonetizationService        │     │
│  │ CosmeticService (catalog + loadout snapshots)                   │     │
│  └─────────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────────────────┐
│ STORAGE / CONTENT                                                        │
│  ServerStorage/Maps/<MapId>  (Geometry cloned to Workspace; Data stays   │
│  server-only)  ·  ReplicatedStorage/Shared (pure modules, catalog,       │
│  cosmetic assets)  ·  DataStore (via ProfileStore): ownership, stats     │
└──────────────────────────────────────────────────────────────────────────┘
```

Three rules hold the whole thing together:

1. **Functional core, imperative shell.** The card ring, scoring formulas and placement rules are pure Luau with no Roblox instances. They take a command and return `{ok, reason, events}`. Services (the shell) own remotes, timers and replication. This makes the hardest component testable and fuzzable outside Roblox, and removes event-ordering surprises from inside mutations.
2. **Clients send intents, never targets or positions of secrets.** The client says "draw" or "pass card X". The server resolves who the right-hand neighbor is, at the moment the command runs.
3. **Interest management over broadcast.** Each client receives only what it is allowed to know: its own hand, public pile depths, and spoons within glint range. Secret data is never placed in a replicated Instance, attribute or Value object.

### Component Responsibilities

| Component | Responsibility | Implementation notes |
|-----------|----------------|----------------------|
| **RosterService** | Single source of truth for who is in the match/round. Converts `PlayerAdded/Removing` into domain events (`Joined`, `Left`) keyed by `userId`. | State logic must never call `Players:GetPlayers()` directly. Records are `userId`-keyed so they survive leave/rejoin. |
| **MatchService** | Match lifecycle: freeze starting roster, hider rotation queue, round counter (= starting roster size, min 3), match totals, winner. | Owns "volatile match state". Never persisted. |
| **RoundStateMachine** | Table-driven FSM: `Lobby → MatchStart → [RoundSetup → Hide → Play → RoundScoring → Podium] × R → MatchEnd → Lobby`. | `Play` is one state containing the card table and the hunt concurrently. They share the single 5:00 timer. |
| **CardEngine** (pure) | Ring of seats, hands, inbox queues, deck build and deal, draw/pass commands, four-of-a-kind detection, seat removal. | No Roblox API. Unit and property tested under Lune or the plain `luau` CLI. |
| **CardTableService** (shell) | Maps remotes to engine commands, rate-limits, applies the engine's event list to replication and scoring. | Only place the engine meets the network. |
| **HideService** | Hider placement remote, validation via PlacementRules, spoon records, early-end, 90s cap, autofill from the map's default spots. | Writes `SpoonRecord`s to HuntService's registry. |
| **PlacementRules** (shared, pure-ish) | `isValid(pos, normal, ctx, world)` where `world` is an injected query interface (raycast, walkable lookup). | Same module runs on the client for ghost coloring and on the server as authority. |
| **MapService** | Clones `Geometry` into Workspace, reads server-only `Data`, builds or loads the walkable grid, unloads at round end. | One map resident at a time. Caches the bake per map id. |
| **HuntService** | `SpoonRegistry` (plain data, not Instances), `InterestManager` (who may see which spoon), `ClaimService` (atomic pickup), carried-spoon attachment. | Fires `SpoonFound`. |
| **ScoringService** | Subscribes to engine and hunt events, appends to the round ledger, finalizes at round end, accumulates match totals. | Pure formula module plus a thin event adapter. Uses server time only. |
| **PlayerDataService** | ProfileStore sessions: owned cosmetics, equipped loadout, lifetime stats, receipt history. | Written to on match end and on purchase, never per round tick. |
| **CosmeticService** | Catalog lookup, validates equip requests against ownership, takes a `LoadoutSnapshot` at round start. | Dealer's deck skin, hider's spoon skin and podium cosmetics are read from the snapshot, never live. |
| **MonetizationService** | `ProcessReceipt`, game-pass checks, VIP gating. | Grants must be idempotent and return `PurchaseGranted` only after the profile write. |
| **WaitingRoom / Podium stage** | Shared, map-independent stages placed at fixed far-off coordinates (parkour room, podium stand). | Built once, not five times. See Decisions. |
| **Client controllers** | One per concern (Phase, CardTable, Hide, Hunt, Loadout, Podium). Read replicated state, send intents, own all purely visual state (selection, animations, glint). | Card selection (tap once to select) is client-only and never replicated. |

---

## Recommended Project Structure

Rojo-managed. Anything the client needs to run goes in `shared`. Anything else stays on the server.

```
src/
├── shared/                         # → ReplicatedStorage.Shared (ships to every client)
│   ├── Net/                        # Remote manifest + payload schemas; server creates remotes at boot
│   ├── Config/                     # Decided numbers: durations, scoring, glint/pickup radii, rate limits
│   ├── Types/                      # Luau type exports (Card, SeatView, SpoonRecord, MapSpec...)
│   ├── Placement/                  # PlacementRules (+ WalkableGrid reader) used by client preview AND server
│   ├── Catalog/                    # CosmeticCatalog (id → kind, asset, price, product id)
│   └── Util/                       # Signal, Maid, small helpers
├── server/                         # → ServerScriptService.Server (never replicated)
│   ├── Main.server.luau            # Bootstrap: require services, Init() all, then Start() all
│   ├── engine/                     # Pure, Roblox-free, test-runnable under Lune
│   │   ├── CardEngine.luau         # apply(cmd) → {ok, reason, events}
│   │   ├── SeatRing.luau           # circular doubly linked list + inbox deques
│   │   ├── Deque.luau
│   │   ├── Deck.luau               # build(seatCount), shuffle(rng), deal()
│   │   ├── HandRules.luau          # findFourOfAKind(hand) with wilds
│   │   └── ScoringFormulas.luau    # fourOfKindBonus, findPoints, hiderPoints
│   ├── services/                   # The imperative shell (listed above)
│   └── tests/                      # Lune/Jest-Lua specs for engine/ and Placement/
├── client/                         # → StarterPlayer.StarterPlayerScripts.Client
│   ├── Main.client.luau
│   ├── controllers/
│   ├── ui/                         # CardSeatsView, Hand, PileWidgets, HUD, Menus
│   └── input/                      # Pointer abstraction (mouse + touch → same events)
├── maps/                           # → ServerStorage.Maps (one folder per map)
│   ├── _contract/                  # MapSpec type, validator, gray-box reference map
│   ├── hotel/  restaurant/  mansion/  maze/  office/
├── stages/                         # → ServerStorage.Stages: WaitingRoom (parkour), PodiumStage
└── assets/                         # → ReplicatedStorage.Assets: cosmetic models, card art, UI sprites
```

### Structure Rationale

- **`server/engine/` is separate from `server/services/`.** The rule is "engine files may not reference `game`, `workspace`, `Players`, `task`, or remotes". Enforce with a lint rule. This is what lets the card engine be built and fuzzed before any UI or network exists.
- **Card rules stay server-side.** The client does not need the ring or deck RNG. Only `Types`, a small hand-legality helper and `Placement` ship to clients. Keep the shuffle server-only.
- **Everything in ReplicatedStorage and the client is readable by exploiters.** That is fine for the placement rules and the catalog. It is not fine for default spot data, spoon positions or deck order.
- **`ServerStorage/Maps` holds whole map models.** Only the `Geometry` child is cloned into Workspace, so authored default spots and spawn data are not in anything replicated.
- **Shared stages** (waiting room, podium) are built once because they do not vary per map.
- **No Knit/Flamework-style framework.** A 30-line bootstrap that requires modules and calls `Init`/`Start` is enough. (Knit is no longer maintained to my knowledge; LOW confidence, not re-verified. Irrelevant if no framework is used.)

---

## 1. Round and Match State Machine

**Where it lives:** server only, in `RoundStateMachine`, driven by `MatchService`. Clients observe it; they never advance it.

**Shape:** table-driven states, each a module with `enter(ctx)`, `run(ctx) → nextStateName`, `exit(ctx)`. `run` yields until its exit condition or deadline. States never talk to each other; they read and write `RoundContext`.

```
Lobby ─(≥3 ready, countdown)→ MatchStart (freeze roster, build hider queue)
  └→ RoundSetup (pick hider, pick/load map, snapshot loadouts, compute spoons = N−2,
                 freeze seat order from previous find order)
      └→ Hide  (hider alone on map; seekers in waiting room parkour; ≤90s; EndHide or cap → autofill)
          └→ Play (deal, teleport seekers to table seats, start 5:00; card table + hunt concurrent;
                   ends on: all spoons claimed OR timer 0)
              └→ RoundScoring (finalize ledger, hider points, add to match totals)
                  └→ Podium (~10s, top 3, cosmetics from snapshot)
                      └→ next RoundSetup  — or MatchEnd (winner, persist stats) → Lobby
```

**Patterns that make it survive churn:**

- **Deadlines, not countdowns.** Store `PhaseEndsAt = workspace:GetServerTimeNow() + duration`. Replicate that absolute timestamp as an attribute on a public `GameState` object (`Phase`, `Round`, `RoundsTotal`, `PhaseEndsAt`). Clients render their own countdown. Late joiners get the correct state for free because attributes replicate on join.
- **Wait with a predicate and a deadline.** One helper, `waitUntil(deadline, predicate, wakeSignal)`, used by every state. Exit conditions are events (`EndHide`, `SpoonFound`, `RosterChanged`) plus a polling safety net.
- **Roster events, not instance polling.** States subscribe to `RosterService.Left/Joined`. The round ledger is keyed by `userId` so a leaver's points stay and a rejoiner can resume.
- **Fixed-at-start data, live-at-end data.** `MatchService` stores the starting roster and hider queue. Round count is fixed from it and never changes on joins. Spoon count is fixed in `RoundSetup`.
- **Every state has a safe abort.** If the hider leaves during `Hide`, autofill runs immediately. If everyone but one leaves, `Play` ends and `MatchEnd` runs. If the roster drops below 3 mid-match, define the behavior explicitly (recommend: finish the current round, then end the match early with current totals).

**Late join policy (derived from PROJECT.md, needs owner sign-off):** the table roster is frozen at the start of `Play`. Someone who joins during `Hide` can be seated at deal time and plays normally as a seeker. Someone who joins after the deal goes straight to the hunt with no four-of-a-kind bonus. Spoon count was fixed at `RoundSetup`, so late joiners simply mean more losers, which matches "fewer points by design".

---

## 2. Real-Time Card Engine (core answer)

### 2.1 Data model

Observe what the rules actually say: a pass moves a card from your hand to your right neighbor's left pile, and your right pile *is* their left pile. So there is **one shared object per edge of the ring, owned by the receiving seat**. Model it as a FIFO queue called `inbox`.

```lua
type Seat = {
  userId: number,
  chair: number,          -- fixed physical chair index 1..9 (visual only)
  hand: { Card },         -- 4 normally, 5 between draw and pass
  inbox: Deque<Card>,     -- the seat's LEFT pile. Pass appends to the neighbor's inbox; draw pops the front.
  next: Seat,             -- right neighbor (receives my passes)
  prev: Seat,             -- left neighbor (feeds my inbox)
}
type Ring = { head: Seat?, size: number, version: number }  -- version bumps on every topology change
```

- **Draw** (`hand` size must be 4, `inbox` non-empty): pop front of own `inbox`, push into own `hand`. "Left pile locks" is simply the rule `#hand == 5 ⇒ draw rejected`. No lock object is needed.
- **Pass** (`hand` size must be 5, card id must be in `hand`): remove from own `hand`, push to back of `seat.next.inbox`.
- **The wrap** is not a special case. The deck is just the dealer's `inbox` at deal time (shuffled, all remaining cards). The last seat's `next` is the dealer because the ring is closed, so its passes append to the back of the dealer's `inbox`, which is exactly "underneath the deck". "Dealer" matters only for deal time, seating order and the deck skin.
- **Between actions, nothing is replicated except depths.** Pile contents are never needed by any client. A client learns `#inbox` of each seat and its own hand, and that is all.

**Key structural property (this is what kills the race-condition problem):** every command mutates exactly *one seat's hand* and *one inbox* (own inbox for draw, neighbor's inbox for pass). Hands are only ever changed by their owner's commands. The only shared mutable structure is the inbox, and its two operations are append (by upstream) and pop-front (by owner). They commute except when the queue is empty.

### 2.2 Concurrency and the "same pile boundary, same frame" race

- Luau on a Roblox server is single-threaded and cooperative. Each remote handler runs to completion unless it yields. **If a handler never yields between validate and mutate, it is atomic.** The engine is pure and synchronous, so each `apply(cmd)` is atomic by construction.
- Two players touching the same boundary (A passes into B's inbox; B draws from B's inbox) are processed in **server arrival order**. Outcomes:
  - B's draw arrives first and the inbox is empty → rejected with `EmptyPile`; B's client shows the pile as empty and lets them tap again. No corruption.
  - A's pass arrives first → B's draw gets that card.
  - Both are valid in either order; the result differs only in *which* card B gets, which is inherent to a simultaneous game.
- **Ordering is deterministic and recorded.** Every accepted command gets a monotonically increasing server `commandSeq` and `os.clock()` timestamp. Four-of-a-kind *place* is the order in which `apply` returned a `Completed` event. Ties in the same frame are therefore impossible to produce and trivially explainable.
- **Never yield inside `apply` or between validating and applying.** No `WaitForChild`, no `task.wait`, no DataStore or MarketplaceService calls, no `:Wait()`. Do not fire BindableEvents from inside the engine; return an `events` array and let the shell publish after the mutation (this also sidesteps Roblox's immediate vs deferred signal-behavior differences, LOW confidence on which is the current default, which is exactly why the engine must not depend on it).
- **Use one RemoteEvent for all card intents** (`CardIntent` with `{kind, seq, cardId?}`), not separate Draw and Pass remotes. Same-remote ordering is the safer assumption; cross-remote ordering is not something to rely on (MEDIUM confidence; the DevForum thread "Remote Event Ordering" exists but could not be fetched in this session). Do not use `UnreliableRemoteEvent` for card traffic; its docs state it does not guarantee delivery or order and caps payloads at 900 bytes.

### 2.3 Dynamic topology: the shrinking wrapped ring (concrete answer)

Structure: **circular doubly linked list of `Seat` objects**, with a stable `chair` number per seat for visuals. Do not use an array plus modulo for `next`; holes after removals make that fragile.

Two removal reasons, which behave differently:

| Reason | Hand cards | Inbox cards | Why |
|--------|------------|-------------|-----|
| `Completed` (four of a kind) | The four qualifying cards leave play. A 5th card (draw happens before check, so hand is 5) is appended to `next.inbox`. | Appended to `next.inbox` (conserved). | A completed rank is removed whole, so every remaining rank still has all four cards in circulation and the game stays solvable. |
| `Left` (disconnect, kicked) | **All** hand cards appended to `next.inbox`. | Appended to `next.inbox`. | A disconnect must not delete cards from play, or ranks become unsolvable and the circle can stall forever. This is the case most likely to be missed. |

Removal procedure (all inside one `apply`, so atomic):

```lua
function SeatRing.remove(ring, seat, reason)
  local succ, pred = seat.next, seat.prev
  -- 1. route cards (see table above) into succ.inbox  (back of queue)
  -- 2. relink: pred.next = succ; succ.prev = pred   (if ring.size == 1, ring becomes empty)
  -- 3. if ring.head == seat then ring.head = succ end
  -- 4. ring.size -= 1; ring.version += 1
  -- 5. mark seat.removed = true so any in-flight command from that user is rejected
end
```

Why this holds up while traffic is flowing:

- Commands never carry a target. A pass resolves `seat.next` *when it executes*. So a pass that was sent before a neighbor left lands in the correct new neighbor. There is no stale pointer to reconcile.
- Because only the acting seat's hand can change in a command, **at most one completion can occur per command**. There is no cascade to resolve.
- If the removed seat was the deck holder, the deck (its inbox) is appended to the successor's inbox. No special dealer-handover code is needed.
- A ring of size 1 is a self-loop (`next == prev == self`). Passes go to its own inbox and draws come from it. This works with no special case, so the last seeker at the table can still finish. The size-0 case just closes the table. Write explicit tests for sizes 3, 2, 1, 0.
- The **fixed-chair visual model** (recommended): chairs never move. Removal leaves an empty chair and cards visibly fly past it to the next occupied chair. This avoids re-layout animation entirely and keeps the topology logic purely logical. `ring.version` goes out in every public sync so clients know when to redraw arrows.

Four-of-a-kind check happens **only on draw** (hand reaches 5). Proof: a pass leaves 4 cards that are a subset of a 5-card set that had no four of a kind (the check ran when it became 5), and subsets of a no-four-of-a-kind set cannot contain one, wilds included. The check is therefore O(5) once per draw. Also check once at deal time and re-deal if anyone starts complete. Prefer to spend naturals over jokers when choosing which four leave play (design call; it keeps wilds circulating).

### 2.4 Deck sizing (must be parametrized, then simulated)

PROJECT.md says the dealer holds "the remaining deck" but does not fix the card pool. A fixed 52 + jokers deck is a poor fit for 2 seekers (44-card deck) versus 9 seekers (16-card deck). Make the pool a function: `Deck.build(seatCount, jokerCount)` using `seatCount + k` ranks, so spare cards are a small constant. Because the engine is pure, build a **headless Monte Carlo pacing simulator** in the same phase as the engine and tune `k`, joker count and bot reaction time against a target time-to-first-finisher. This is cheap and removes a major tuning risk. After `m` completions, spare cards stay constant (a whole rank leaves with each finisher).

### 2.5 Client prediction versus strict confirmation

Do both, split by what is knowable:

| Action | Strategy | Why |
|--------|----------|-----|
| **Pass** (tap selected card) | **Optimistic.** Client immediately animates the card to the right pile and shows hand = 4, sends `{kind=Pass, seq, cardId}`. On server reject, snap it back. | The client already knows the card. The outcome is deterministic except for rare rejects (seat state changed). Removes a full round trip from the most frequent action. |
| **Draw** (tap left pile) | **Optimistic animation, authoritative content.** Lift a face-down card into the hand instantly, flip it when the server ack arrives with the real `cardId`. Do not let the player select it until the ack. | The card identity is unknowable on the client. Do not prefetch the top-of-pile identity; it adds an information leak and complexity for a small gain in v1. |
| **Four-of-a-kind** | **Strict.** Only ever the server's `Completed` event moves a player out of the table. | Scoring and anti-cheat depend on it. |

Reconciliation: every intent carries a client `seq`. Server replies on a per-player `HandSync` with `{ackSeq, hand}`. The client discards predictions with `seq <= ackSeq` and re-applies any unacked ones on top of the authoritative hand. Because card intents travel on a single ordered remote, replay is deterministic.

Latency guidance (LOW confidence, based on typical Roblox round-trip experience; **measure on real mobile devices early**): round trips of roughly 50-150 ms on PC and 100-250 ms on mobile. With the split above, pass feels instant and draw shows a lift immediately with a reveal about one round trip later. Under ~150 ms reveal is comfortable; beyond ~250 ms the draw reveal will feel sticky and is the first thing to rework. High-ping players are disadvantaged in a race game; server arrival order is the tiebreak and nothing more elaborate (lag compensation) is warranted.

### 2.6 Replication scoping

| Data | Audience | Channel | Cadence |
|------|----------|---------|---------|
| Own hand (card ids) | That player only | `HandSync` via `FireClient` | On every change, immediate (tiny payload, includes `ackSeq`) |
| Per-seat public view: `{userId, chair, inboxDepth, handCount (4/5), locked}` and `ring.version` | Everyone at the table | `TableSync` via `FireAllClients` | Coalesced: dirty flag, flushed at ~10-20 Hz from one Heartbeat flusher |
| Topology events: `SeatLeft{userId, reason}`, `Dealt` | Everyone | Event remotes, immediate | On occurrence (drive animations) |
| Other players' hands and inbox contents | **Nobody** | Never sent | n/a |
| Phase, round, deadlines | Everyone | Attributes on `GameState` | On change |

Do **not** put hands or piles in `Value` objects or attributes under a replicated container. They replicate to everyone, which is an information leak. Do **not** fire `FireAllClients` once per pass; with nine players tapping this multiplies traffic for no visual benefit. Provide a `RequestFullSync` remote so reconnects and late joiners can rebuild the view.

### 2.7 Anti-abuse specific to the card table

- Validate `kind`, `seq` (number, strictly increasing), `cardId` (belongs to caller's hand).
- Token-bucket rate limit per player (start around 8 commands/s burst, tune after playtests). Reject silently; log counters.
- Server never trusts client timestamps. Scoring uses server time only.
- An exploiter who sees their own hand and plays optimally is indistinguishable from a good player. Fair information is the only defense; the architecture's job is to ensure no *other* information leaks.

---

## 3. Hide Phase: Placement Validation

**Validity predicate (single definition used everywhere):** a spoon position `P` is valid iff there exists a reachable, standable cell `S` such that `dist(S, P) ≤ PickupRadius` and a ray from `eye(S)` to `P` is unobstructed. Tie this deliberately to the same predicate used to claim a spoon, so "valid placement" and "can actually be picked up" cannot diverge.

**Hybrid architecture (recommended):**

1. **Bake once per map (server, at map load; cache by map id): `WalkableGrid`.**
   - Sample a grid (about 2-stud spacing) inside the map's play volume: raycast down to find floors, check agent clearance with a part-bounds query, and keep a cell only if slope and step height are within player ability.
   - Flood-fill from the map's `SeekerReleasePoints` over cells with a step-height limit based on a conservative fraction of the character's jump height (set character jump constants once in `Config` and bake against about 80% of them, so nothing requires a precision jump). The result is a `reachable` flag per cell.
   - Use `PathfindingService` here only as an optional **verification** step on a sample of cells, not as the primary mechanism. Official docs describe `ComputeAsync` with `Path.Status == Success` as the only reachability signal, with known limitations (vertical placement, agent parameters, paths that can change); it is async, per-query, and a spoon on a shelf is not a navmesh point.
2. **Per placement (server, authoritative):** reject if outside the `PlayVolume` or inside a `Forbidden` zone; reject if overlapping geometry (part-bounds query); reject if closer than `MinSpoonSpacing` to another spoon; then query the grid for reachable cells within `PickupRadius`, sorted by distance, and `Workspace:Raycast` from eye height to `P` for each candidate (early exit on first clear). Cost is a handful of raycasts per placement.
3. **Client preview:** the same `Placement` module runs against the client's own raycasts for green/red ghost feedback. The grid is not secret and can be replicated as part of the map's public data. The server re-runs the full check and its answer always wins.

Use `Workspace:Raycast` with reusable `RaycastParams`. `FindPartOnRay` is legacy; community sources call it deprecated, though official reference pages still show it, so treat as "do not use for new code" (MEDIUM).

**Why not pure PathfindingService:** async, rate-sensitive, models a walker not a viewer, cannot answer "visible from where".
**Why not pure precomputed volumes:** hand-authored volumes defeat "free placement" and cost every map worker significant time.

**Pitfalls to engineer around:** moving doors and dynamic props change reachability, so keep maps static or make doors non-blocking; the bake can be slow on large maps (mansion, maze), so cache and, if needed, bake in coroutine slices during map load; and streaming gaps can make the client preview disagree with the server, which is acceptable because the server is authoritative.

**Autofill:** on cap expiry, `HideService` picks remaining spoons at random from the map's server-only `DefaultSpots`, and these spots are validated by the contract validator (section 6) so the fallback can never produce an unfindable spoon.

---

## 4. Spoon Hunt: Glint, Claim, and Anti-Leak

**Core idea:** hidden spoons are **data, not Instances**, on the server. They never exist in Workspace or any replicated container until a specific client is allowed to see one.

```
SpoonRegistry: id → { pos, normal, hiderId, skinId, state = Hidden|Claimed, finderId?, foundAt? }
```

**Interest management (`InterestManager`), about 5 Hz:**

- For each seeker out of the table, for each `Hidden` spoon (at most 8 × 9 = 72 pairs), check server-known `HumanoidRootPart` distance ≤ `GlintRadius` and a server raycast for line of sight.
- On entering range, send `SpoonVisible{id, pos, normal, skinId}` to that client only. On leaving range (with hysteresis), send `SpoonHidden{id}`.
- The client creates a purely local spoon visual and glint only while it holds such an entry. It cannot render or locate a spoon outside glint range because it was never told where it is. An injector learns exactly what a legitimate player sees.
- Glint radius and line-of-sight rules are global `Config`, not per-map and never purchasable.
- Do not use StreamingEnabled as a secrecy tool. It is a performance feature with large radii.
- Do not store spoon positions in attributes, `Value` objects or `ObjectValue`s anywhere.
- The hider alone receives their own spoons' positions (`HiderSpoonState`) during the hide phase.

**Claim (no double-claim race):**

1. Client sends `ClaimSpoon{id}` when within pickup range of a locally visible spoon.
2. Server checks, with no yielding between check and write: spoon exists and is `Hidden`; claimant is out of the table and not already carrying a spoon; claimant's server-side position is within `PickupRadius + LatencySlack` of the spoon (the server's view of a client-owned character lags, so allow slack of a few studs and re-check line of sight loosely).
3. If valid, set `state = Claimed`, `finderId`, `foundAt = GetServerTimeNow()` in the same synchronous block. Single-threaded execution means the first handler to run wins; the second sees `Claimed` and is rejected.
4. Then publish `SpoonFound` (to scoring, and to all clients for HUD), attach the carried-spoon model to the claimant's character on the server (visible to everyone, wearing the *claimant's* skin), and tell the client to remove the local ground visual.
5. The client may optimistically hide its ground spoon on claim and restore it on reject.

**Skins:** the ground spoon uses the **hider's** skin (carried in `SpoonVisible`); the carried spoon uses the **claimant's** skin. Both come from the round's `LoadoutSnapshot`.

**Other exposures to close:** default-spot markers must not live in replicated geometry (they would hand injectors a prior over spoon locations); the hider's ghost positions are client-private; and `SpoonFound` carries only the id, not positions of remaining spoons.

---

## 5. Scoring and the Persistence Boundary

**Scoring:**

- `ScoringFormulas` (pure): `fourOfKindBonus(place) = max(0, 1000 − 100·(place−1))` and `findPoints(secondsRemaining) = floor(secondsRemaining · 10)`, matching PROJECT.md. Number validation: 5:00 = 300 s → 3000 max, which matches the table. Use server timestamps, rounded to 100 ms.
- `ScoringService` keeps an **append-only round ledger** keyed by `userId`: `FourOfKind{place, t}`, `SpoonFound{t, remaining}`, `HiderSurvival{spoonId, seconds}`. It computes round scores at `RoundScoring` and adds them to `MatchService.totals`. A ledger (not mutable counters) makes tie cases, leavers, and debugging auditable.
- The hider formula is **not defined** in PROJECT.md ("roughly the inverse"). It must be fixed as a decision before the scoring phase; see Open Decisions.

**Persistence boundary:**

| Volatile (server memory, per match) | Persisted (ProfileStore, per player) |
|-------------------------------------|--------------------------------------|
| Roster, hider queue, round index, ring, hands, spoon registry, ledger, match totals, loadout snapshots | Owned cosmetic ids, equipped loadout, lifetime stats (matches, wins, rounds, spoons found), settings, recent receipt ids |

- Match state is **never** written to a DataStore. A server crash loses the match, which is acceptable for a party game.
- Stats are written **once at `MatchEnd`**, not per round, to stay inside DataStore budgets and avoid partial-match garbage. ProfileStore holds the session lock and autosaves; the architecture only mutates `profile.Data`.
- ProfileStore is described by its maintainers as the successor to ProfileService (faster lock-conflict handling, 300 s default autosave); its docs say it targets per-player data, not leaderboards or global state (HIGH for this description, from the project docs). Leaderboards, if wanted later, are a separate OrderedDataStore concern.
- **Loadout snapshot** at `RoundSetup`: copy each player's equipped ids into the round context. Mid-round purchases or equips cannot change anything in flight, which also enforces "cosmetics are equipped in the lobby, never mid-round".
- **Purchases:** `MarketplaceService.ProcessReceipt` must be idempotent (record receipt id in the profile), grant, save, and only then return `PurchaseGranted`. Verify game-pass ownership on the server rather than trusting a client signal. Nothing in this path touches `ScoringService`; keep that dependency edge absent in code so the "no pay-to-win" rule is structural, not just policy.
- **VIP lobbies:** treat as a game-pass-gated reserved/private server of the same place (`TeleportService:ReserveServer`) running the identical code. This is the lowest-cost way to honor "access only"; confirm at implementation time (LOW-MEDIUM).
- Recommend a **single place** where lobby and match share a server: the lobby is a phase, not a separate place. Players joining mid-match are the late-join case above.

---

## 6. Map Content Architecture

**Build model:** each map is a Model under `ServerStorage/Maps/<MapId>` with a fixed child layout, authored in Studio and synced as `.rbxm` or inside the place; code does not care which. A `MapSpec` ModuleScript sits alongside.

```
<MapId>/
├── Geometry/            # the ONLY part cloned to Workspace; includes lighting preset ref
├── Data/                # SERVER-ONLY, never cloned
│   ├── PlayVolume       # Parts defining in-bounds (CanCollide off, anchored)
│   ├── Forbidden/       # optional exclusion volumes
│   ├── HiderSpawn       # CFrame marker
│   ├── CardTable        # anchor + SeatAnchors/1..9 (clockwise, facing centre)
│   ├── SeekerRelease/   # ≥1 CFrame markers where seekers appear after leaving table (also flood-fill seeds)
│   └── DefaultSpots/    # ≥16 markers (CFrame + normal)
└── MapSpec              # ModuleScript returning { id, displayName, theme, ... overrides = {} }
```

`MapSpec` exposes only data; gameplay numbers (glint radius, durations, scoring) are global and maps **cannot override them**. This prevents per-map balance drift and protects the pay-to-win rule.

**The shared contract and validator are the parallelism enabler.** Build, early and before any map work:

1. `maps/_contract/MapSpec` type and a written authoring checklist.
2. A **validator** (runs in Studio via command bar/plugin, and optionally in CI via Lune, which can read Roblox model/place files; MEDIUM confidence for the CI workflow, since only the capability was confirmed) that asserts: required children exist; seat anchors ≥ 9 (the max seeker count is one less than the 10-player roster cap, but 9 anchors is the specified bound); ≥ 16 default spots; markers lie on the walkable grid; **every default spot passes `PlacementRules` against the baked grid** (closing the loop so autofill can never fail); release points and hider spawn are reachable; the play volume bounds all of the above; no scripts or unanchored physics in `Geometry`.
3. A gray-box **reference map** that passes the validator, so each map worker has a working example and the engine team has a test fixture.

With these, five workers can build five maps independently, and "done" is mechanically checkable.

**Map-specific notes:** the hotel (single floor), restaurant, mansion and office are standard interior builds. The maze with scattered decoy items needs the decoys to be static decor (they replicate to everyone, which is fine); the maze is also the worst case for the bake (long corridors, narrow clearances), so test it first. Watch part count and StreamingEnabled behavior on mobile for the mansion and maze.

**Shared stages:** the parkour waiting room and the podium stage are single, map-independent builds placed at far-off fixed coordinates. Seekers are teleported (`PivotTo`) into the waiting room at `Hide` start and to table seats at `Play` start. Per-map waiting rooms are a possible later re-skin, not a v1 need. The podium reuses real characters posed on three anchors, with equipped poses and effects drawn from the loadout snapshot.

---

## Architectural Patterns

### Pattern 1: Command/Result engine (functional core)

**What:** `engine.apply(state, cmd) → {ok, reason?, events[]}`; no side effects. The shell publishes events afterward.
**When:** all logic that must be correct under concurrency: card table, scoring formulas, placement rules.
**Trade-offs:** needs a thin adapter layer; pays back in testability and zero re-entrancy bugs.

```lua
local result = CardEngine.apply(state, { kind = "Pass", userId = uid, cardId = id, seq = n })
if result.ok then
  for _, e in result.events do EventBus:Publish(e) end   -- after mutation, never inside
end
```

### Pattern 2: Public state in attributes, private state in remotes

**What:** coarse, non-secret, late-join-critical state (phase, round, deadlines) on a replicated `GameState` object's attributes; fine-grained or private state via remotes with an explicit `RequestFullSync`.
**When:** always. Attributes give correct state to late joiners for free; remotes give scoping.
**Trade-offs:** two mechanisms to keep consistent; mitigate by funneling both through one `ReplicationService`.

### Pattern 3: Interest-managed secrets

**What:** server holds secret entities as plain data and streams per-client "you may now know this" messages.
**When:** spoons; also any future hidden info. **Trade-off:** some server CPU (trivial at 72 pairs).

### Pattern 4: Stable identity by `userId`

**What:** all round and match records keyed by `userId`, resolving `Player` lazily.
**When:** everywhere in match and round code. **Why:** `Player` instances disappear on leave, so any reference held in the ledger becomes dead.

### Pattern 5: Single manifest for remotes

**What:** `Net` declares every remote, its direction and its payload validator; server creates them at boot; clients `WaitForChild` the folder once.
**Trade-off:** slight ceremony; removes stringly-typed drift and centralizes validation. Heavier codegen libraries (ByteNet, Blink) are not needed at this traffic level.

---

## Data Flow

### Card action flow

```
Tap pile / tap-tap card
   ↓ (client: optimistic animation, seq++)
CardIntent{kind, seq, cardId?}  ──ordered RemoteEvent──▶ CardTableService
   ↓ rate limit + schema check
CardEngine.apply()  (atomic; resolves seat.next itself)
   ↓ {ok, events}
   ├─▶ HandSync (owner only, immediate, ackSeq)
   ├─▶ dirty flag → TableSync (all, ≤20 Hz)
   └─▶ events: Completed{userId, place} ─▶ ScoringService ledger
                                         ─▶ SeatLeft broadcast, teleport to SeekerRelease
```

### Spoon lifecycle

```
HideService (validated placement or autofill)
   ↓ SpoonRecord (data only)
HuntService.SpoonRegistry
   ↓ ~5 Hz distance + LoS per (seeker, spoon)
SpoonVisible → that client only → local visual + glint
   ↓ ClaimSpoon{id}
ClaimService (atomic) → SpoonFound ─▶ ScoringService, HUD, carried-spoon attach
                                   └▶ if all claimed: RoundStateMachine → RoundScoring
```

### State management

```
RosterService events ──▶ RoundStateMachine ──▶ phase hooks to services
                                  │
                                  └──▶ GameState attributes (public) ──▶ client controllers (read-only)
MatchService.totals ◀── ScoringService (at RoundScoring)
PlayerDataService   ◀── MatchService (at MatchEnd only)
```

### Key flows

1. **Round start:** RoundSetup picks hider (queue by userId), loads map, snapshots loadouts, fixes spoon count and seat order; Hide begins.
2. **Hide to Play:** EndHide or the 90 s cap triggers autofill, the registry is sealed, seekers are teleported to seats, and the deal and the 5:00 timer start together.
3. **Round end:** all spoons claimed, or timeout. Ledger finalizes, hider points are computed from `foundAt` times, totals update, and Podium begins.
4. **Seat order carry-over:** the previous round's find order (first finder = dealer) becomes the next round's seating; this is stored in `RoundContext` at `RoundScoring` and read at `RoundSetup`.

---

## Build Order and Parallelism

### Dependency graph

```
L0 (sequential, small, FIRST):
  Rojo skeleton · Net manifest · Config (decided numbers) · Types · bootstrap
  · MapSpec contract + validator + gray-box reference map · RosterService · FSM skeleton with stub states
        │
        ├────────────── L1 (all parallel once L0 is done) ──────────────────────────┐
        │  A  CardEngine pure core + tests + Monte Carlo pacing sim   [CRITICAL PATH]│
        │  B  PlayerDataService + CosmeticCatalog + Monetization receipts            │
        │  C  PlacementRules + WalkableGrid bake + MapService (needs reference map)  │
        │  D  Shared stages: waiting-room parkour, podium stage                      │
        │  E  Client shell: pointer abstraction, UI kit, CardSeatsView against a     │
        │     MOCK engine feed (no server needed)                                    │
        │  F  Maps 1..5 content (needs only the contract + validator)                │
        ▼
L2 (integration; partially parallel):
  G  CardTableService + prediction/reconcile + replication     (A + E + Net)
  H  HuntService: registry, InterestManager, Claim, carried spoon  (C + FSM)
     ── can be built against AUTOFILLED spoons before the hide UI exists
  I  ScoringService event adapter + ledger                      (A formulas + events from G/H)
  J  HideService + hider placement UI + early end + cap         (C + FSM + E)
        ▼
L3: Match layer (needs G+H+I): hider rotation, seat-order carry-over, scoreboard,
    mid-round join, leaver cleanup, Podium, loadout application (spoon/deck/char skins)
        ▼
L4: VIP lobby, purchase UX, mobile parity pass, bot soak test (10 simulated clients), tuning
```

### Strictly sequential edges

- L0 contracts before anything else (Net schema, Config, MapSpec contract). Changing them later invalidates parallel work.
- Engine (A) before CardTableService (G); `PlacementRules` and the contract (C) before the HideService (J) and the validator's autofill check.
- Registry and claim (H) before the scoring adapter's find events (I).
- FSM skeleton before any service that has phase hooks.

### Safe to parallelize

- A, B, C, D, E and F are independent after L0 and touch disjoint directories (`engine/`, `PlayerData`+`Catalog`, `Placement`+`MapService`, `stages/`, `client/ui`, `maps/*`). Each of the five maps is its own work item.
- H can proceed with autofilled spoons while J is still under construction; this puts the full loop (cards to hunt to score) in front of playtesters sooner.
- B (persistence, catalog, receipts) has no dependency on gameplay and can run for the whole project.

### Recommended phase slicing for the roadmap

1. **Foundations and contracts** (L0).
2. **Card engine + pacing sim**, in parallel with **map contract + first map + placement/bake** and **persistence**.
3. **Playable vertical slice:** one map, autofilled spoons, card UI with prediction, hunt with interest management and claim, scoring, FSM. This is the core-value loop; do it before breadth.
4. **Free-placement hide phase** (reachability and line of sight, early end, cap, client preview).
5. **Match structure:** rotation, seat carry-over, scoreboard, podium, mid-round join, churn handling.
6. **Content and monetization in parallel:** maps 2-5, cosmetics, purchase flow, VIP.
7. **Parity, performance and soak:** mobile pass, bot-driven 10-client soak, tuning.

---

## Scaling Considerations

The game is capped at 10 players per server, so "scale" means correctness under churn and per-server cost, not user counts.

| Concern | Approach |
|---------|----------|
| Card traffic (≤9 players, human tap rates) | Trivial CPU. Bandwidth control comes from coalesced `TableSync` and a tiny `HandSync`. |
| Interest management | 72 pair checks at 5 Hz plus ≤72 raycasts: negligible. |
| Walkable bake | The only potentially heavy step. Cache per map; slice across frames; test on maze and mansion first. |
| Memory and mobile | One map resident at a time; unload at round end; consider StreamingEnabled for large maps and verify on low-end phones. |
| DataStore budget | Writes only at MatchEnd and on purchase. Autosave handled by the module. |
| Matches per server | Persistent server hosts successive matches; lobby is a phase. Public servers fill naturally. |

### Scaling priorities

1. **First bottleneck:** map load plus bake time between rounds. Fix by caching, background slicing, and doing the bake during Lobby or while the previous round's podium plays.
2. **Second:** mobile memory and streaming hitches on large maps. Fix with part-count budgets in the map contract.

---

## Anti-Patterns

### Anti-Pattern 1: Hand or pile state in replicated Values/attributes

**What people do:** store each player's hand in a `StringValue` under the player for easy UI binding.
**Why it's wrong:** replicates to every client, leaking every hand, and invites client-writable assumptions.
**Do this instead:** `FireClient` the owner their hand; broadcast depths only.

### Anti-Pattern 2: Client sends the target seat

**What people do:** `PassCard(cardId, targetSeat)`.
**Why it's wrong:** the ring changes while commands are in flight; stale targets cause lost cards or exploits.
**Do this instead:** server resolves `seat.next` at execution time.

### Anti-Pattern 3: Spoon parts in Workspace, hidden by transparency

**What people do:** place spoon models in the map and toggle visibility.
**Why it's wrong:** positions replicate to all clients, so injectors read them directly.
**Do this instead:** server-only data plus per-client `SpoonVisible` messages.

### Anti-Pattern 4: Deleting a disconnecting player's cards

**What people do:** destroy the seat and its cards on leave.
**Why it's wrong:** removes naturals from ranks, so remaining players can be permanently unable to complete anything.
**Do this instead:** route all of a leaver's cards into the successor's inbox; only a completed four of a kind removes cards from play.

### Anti-Pattern 5: Yielding inside a mutation

**What people do:** call `WaitForChild`, a DataStore, or a signal `:Wait()` between validating and writing.
**Why it's wrong:** another handler can run in the gap, breaking the atomicity that all race-safety relies on.
**Do this instead:** keep engine and claim paths synchronous; do all async work before or after.

### Anti-Pattern 6: Reading `Players:GetPlayers()` in round logic

**Why it's wrong:** it silently changes mid-round, so rosters, spoon counts and hider queues drift.
**Do this instead:** go through `RosterService` and the frozen round roster.

### Anti-Pattern 7: Per-placement PathfindingService calls, `FindPartOnRay`, per-action `FireAllClients`, persisting match state

Each is a known cost or legacy trap. Use the baked grid with `Workspace:Raycast`, coalesced syncs, and in-memory match state.

### Anti-Pattern 8: Letting purchases or cosmetics touch scoring code

**Do this instead:** keep `MonetizationService`/`CosmeticService` with no import path to `ScoringService` or `HuntService` configuration. Cosmetics are data on the loadout snapshot and are consumed only by presentation code.

---

## Integration Points

### External services

| Service | Integration pattern | Notes |
|---------|---------------------|-------|
| DataStore via ProfileStore | `PlayerDataService` only; other services get read accessors | Session locking; teleports can produce lock contention, so release profiles cleanly on leave. |
| MarketplaceService | `ProcessReceipt` and game-pass checks in `MonetizationService` | Idempotent; return granted only after save. |
| TeleportService | VIP reserved servers | Same place, same code. |
| PathfindingService | Optional bake verification only | Not on the hot path. |

### Internal boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| FSM ↔ services | Phase hooks (`onEnter/onExit`) and an event bus | Services never advance phases; they emit events the FSM listens for. |
| CardTableService ↔ CardEngine | Direct call, returns events | Engine has no outward dependencies. |
| HideService → HuntService | `SpoonRecord` hand-off at hide end | Single write path into the registry. |
| ScoringService ← engine/hunt | Events only | No back-calls. |
| Server ↔ client | `Net` manifest remotes, attributes on `GameState` | Intents up, scoped state down. |
| Maps ↔ code | `MapSpec` + fixed folder layout | Validated mechanically. |

---

## Open Decisions (owner input needed; they change the architecture)

1. **Hider scoring formula** is undefined ("inverse of seekers"). Suggest: per spoon `10 × survivalSeconds` (unfound = 300 s), averaged or summed, capped to match the 3000 seeker ceiling. Needs a decision before the scoring phase.
2. **Card pool composition** (`seatCount + k` ranks, joker count). Resolve with the pacing simulator, not by argument.
3. **Fifth card on completion:** PROJECT.md says "their 4 cards leave with them". Because the check fires on draw (hand = 5), a fifth card exists. Recommended: it goes to the successor's inbox. Confirm.
4. **Seat order edge cases:** order for non-finders, and where the previous round's hider is seated.
5. **Scheduled hider is gone** when their turn arrives: skip the round (match shortens) or run with autofill and no hider points (keeps rounds = starting count and pacing). Recommend the latter.
6. **Podium ranking:** round score or running match total? PROJECT.md says "top 3 players" at round end without saying which.
7. **Match tiebreak** for equal totals.
8. **Late-join seating** (the policy above) and **minimum-roster abort** (match ends if the roster drops below 3?).

## Verification Status

| Claim | Status |
|-------|--------|
| `UnreliableRemoteEvent`: no ordering or delivery guarantee, 900-byte cap | Verified against Roblox reference (HIGH) |
| ProfileStore is the ProfileService successor, per-player data focus, 300 s autosave | Verified against project docs and DevForum (HIGH-MEDIUM) |
| PathfindingService gives reachability only via `ComputeAsync` status; has documented limitations | Verified against Roblox docs (MEDIUM-HIGH) |
| `FindPartOnRay` legacy; use `Workspace:Raycast` | Community sources agree; no official deprecation notice found (MEDIUM) |
| Lune can read/write Roblox model and place files | Verified from project README snippets (MEDIUM); the CI workflow built on it is unverified |
| Same-remote ordering for RemoteEvents; Signal deferred-vs-immediate default | **Not verified** (DevForum host unreachable in this session). Treat as an assumption to test in Studio. |
| Latency figures, tap-rate limits, glint/pickup radii, 5 Hz interest rate | LOW; starting points to be tuned by playtest |
| Single-threaded atomicity of non-yielding handlers; instance/attribute replication scope; `ProcessReceipt` semantics | Established Roblox behavior from long-standing practice; not re-fetched here (MEDIUM) |

## Sources

- Roblox UnreliableRemoteEvent reference: https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent (HIGH)
- Roblox character pathfinding guide and Path reference: https://create.roblox.com/docs/mechanics/pathfinding, https://create.roblox.com/docs/reference/engine/classes/Path (HIGH)
- ProfileStore documentation: https://madstudioroblox.github.io/ProfileStore and DevForum announcement https://devforum.roblox.com/t/profilestore/3190543 (HIGH-MEDIUM)
- Lune runtime: https://github.com/lune-org/lune (MEDIUM)
- Raycasting versus `FindPartOnRay` discussions on the Roblox DevForum (community, MEDIUM)
- Remaining statements derive from the project's own rules in `.planning/PROJECT.md` and established Roblox practice (flagged per item above).

---
*Architecture research for: server-authoritative Roblox round-based card + hunt party game*
*Researched: 2026-11-02*
