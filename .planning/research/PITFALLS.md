# Pitfalls Research

**Domain:** Roblox real-time multiplayer party game (simultaneous card-passing game plus server-hosted hide-and-seek hunt), competitive per-round scoring, Robux cosmetic monetization
**Project:** Spoons (working title; repo `robloxspoons`)
**Researched:** 2026-11-02
**Confidence:** MEDIUM overall. Design-specific pitfalls (race conditions, solvability, spec holes, cosmetic leakage) come from analysing PROJECT.md directly and are HIGH-confidence reasoning. Roblox-platform facts come from training knowledge plus web-search snippets of official docs. `create.roblox.com` could not be fetched in this session (network-blocked), so exact limits and API semantics are flagged "verify at phase research time".

## How to read this file

- **Severity:** C = critical (rewrite, exploit-wide-open, or revenue/policy blocker), H = high, M = moderate, L = minor.
- **Likelihood:** how often projects like this hit it, not how bad it is.
- **Provisional phase vocabulary.** No roadmap exists yet. Phase references below use these themes. The roadmapper should remap them to real phase numbers.

| Tag | Theme |
|-----|-------|
| P1 | Foundations: Rojo project, server-authoritative skeleton, remote gateway, match/round state machine, profile persistence skeleton |
| P2 | Card engine: pure, headless, simulated (no UI) |
| P3 | Card UI and table, PC and mobile |
| P4 | Hide and hunt mechanics: placement rails, spoon visibility, pickup |
| P5 | Round/match flow, scoring, player churn |
| P6 | Maps (5) and the map-as-data pipeline |
| P7 | Lobby, cosmetics, shop, persistence, purchases |
| P8 | Hardening: anti-exploit pass, perf/mobile QA, soft launch, economy review |

## Highest-leverage findings (read these first)

1. **The nastiest bugs are spec holes, not code bugs.** PROJECT.md leaves several rules undefined (see Pitfall C9: who sits where, what happens to a leaving player's pile, whether a wild-completed set strands orphan cards, and whether a mid-round joiner can skip the card stage). Each becomes a race or exploit if resolved ad hoc in code. Lock them in the P2 spec before writing the engine.
2. **"Server-authoritative" is not enough. Replication is the leak.** Anything placed in `Workspace`, `ReplicatedStorage`, Attributes, `ValueObject`s or a broadcast "table state" remote is readable by every exploiter. Hands, spoon positions and the default-spot pool must never be replicated to clients that should not know them (C1).
3. **The card engine's real load is correctness, not bandwidth.** At human click speed, 9 clients produce tens of remotes per second, which is trivial for a Roblox server. The failure modes are stale-index actions, yields inside state mutations, topology changes mid-action, and optimistic-UI desync (C2).
4. **The hider is financially motivated to make spoons unfindable.** Hider score rises with survival time, so the placement rails are the only counterweight to an arms race. Treat the rails as a first-class system with its own test corpus, not a validation afterthought (C8).
5. **Paid cosmetics will leak into gameplay unless the architecture forbids it.** The danger items are glint colour, spoon skin camouflage and hitbox, deck legibility, accessory size and avatar scale, none of which is a "score multiplier" (C10).
6. **Mobile layout is a first-class risk.** Seven or more tap targets (5 cards plus 2 piles) must coexist with the default thumbstick and jump button on a roughly 667px-wide landscape screen (C13).

---

## Critical Pitfalls

### C1: Hidden information leaks through replication (severity C, likelihood HIGH)

**What goes wrong:**
An exploiter reads other players' hands, the contents of piles or the deck, the hider's spoon positions, or the 16-plus default spot list, without breaking any remote. Four common leak paths:
1. A `TableState` remote or per-player Folder/Attribute holding every hand so the UI can "just render it". Client-side filtering is presentation, not security.
2. Spoons created as real `Part`s in `Workspace` (possibly with a `ProximityPrompt`, Attribute or tag). The instance replicates to every client immediately, including seekers still in the waiting room, so an exploiter can dump all spoon CFrames. The close-range glint is then purely cosmetic.
3. The hider's placement ghost or preview built as a server Part, which broadcasts positions live during the hide phase.
4. Default-spot markers left in `Workspace`/`ReplicatedStorage`, or the auto-fill pool in a shared module. The exploiter learns the candidate set. Real players learn it too by round 3, since the pool is fixed and public, which makes auto-filled spoons trivially findable; that is acceptable but should be a conscious choice.

**Why it happens:**
Roblox replicates the DataModel by default. Developers conflate "server decides" with "client cannot see". Real parts are the easiest way to build spoons, and a single full-state remote is the easiest way to build a UI.

**How to avoid:**
- Hands and piles: the server holds the ring state in plain Lua tables inside `ServerScriptService`-only modules. Send each player only their own hand (card IDs) and public data (hand/pile counts, whose seat is where). Card visuals for others are face-down meshes with no rank/suit data on the instance.
- Spoons: keep positions in server memory only. Do not create spoon `Part`s in `Workspace` at all. Options:
  - **Preferred:** the server polls each hunting seeker (about 5 to 10 Hz), does a distance and line-of-sight raycast against each unclaimed spoon, and sends that client a "spoon visible near you" event only when in range. The client spawns a local-only visual using the hider's skin ID. This makes "glints only at close range / in line of sight" enforceable rather than cosmetic.
  - **Fallback:** real parts in a model with StreamingEnabled and a small streaming radius. This is weaker, because anything inside the radius is readable and the radius protects only far spoons.
- Hider preview: the ghost is a client-local part. Only the final accepted placement goes to the server, as a `Vector3` plus nothing else.
- Default spots: keep markers and metadata in `ServerStorage` or server-only modules, never `Workspace`/`ReplicatedStorage`.
- Pickup: `ProximityPrompt` on real spoons reveals location through the prompt UI and the replicated instance. Use a client-created prompt or button that appears only for in-range spoons, with the server re-validating distance on every claim.

**Warning signs:**
- Any `ReplicatedStorage` module or Folder containing card, hand or spoon data.
- A remote whose payload includes every seat's data.
- Spoon instances visible in the Studio Explorer under the client view while in the waiting room. Check using Play (Client) mode with the Explorer pointed at the client DataModel.
- A glint implemented as a `PointLight`/`ParticleEmitter` on a Workspace spoon.

**Phase to address:** P1 (rule: no gameplay secrets in replicated containers; lint/grep CI check), P2 (hand/pile state server-only), P4 (spoon visibility model). Retrofitting this after spoons are built as parts is expensive.

---

### C2: Card action races, stale indices, yields inside mutations (severity C, likelihood HIGH)

**What goes wrong:**
The ring is a shared mutable structure that changes shape while players act on it. Typical corruptions:
- **Stale hand index.** The client sends "pass card #3". By the time the server processes it, a draw has shifted indices, so the wrong card is sent. Or the card is not in the hand at all.
- **Double draw / double pass** from tap spam or reconnect retries, giving a 6-card hand or duplicating a card (duplicated or vanished cards break solvability, see C3).
- **Target resolved on the client.** The client names the receiving pile, but the circle closed up one tick earlier. A card is added to a pile belonging to a seat that has left, and the card vanishes.
- **Yield mid-mutation.** A handler reads the ring, yields (`task.wait`, `WaitForChild`, a DataStore/Marketplace call, `PathfindingService:ComputeAsync`, a tween `Completed:Wait()`), then writes. Luau is single-threaded but not atomic across yields. Two handlers interleave and corrupt state. This is the classic Roblox race.
- **Optimistic client desync.** The client moves the card locally, the server rejects, and the UI stays wrong until the next full snapshot.

**Why it happens:**
Indices are the natural UI model. Handlers get written inline in `OnServerEvent` with convenience calls. Developers assume a single-threaded runtime means no races.

**How to avoid:**
- **Card engine is a pure, synchronous module** with no Roblox services, no yields and no side effects other than returning events. `apply(state, playerId, action) -> events`. All remote handlers call it, then fan out the resulting events. Unit-test it outside Studio.
- **Stable card IDs, not indices.** Every physical card has a unique ID for the round. Actions are `{type="draw", seq=n}` and `{type="pass", cardId=..., seq=n}`. The client never names a target; the server resolves "right pile" against the current ring at processing time.
- **Preconditions are the idempotency.** Draw requires hand size 4 and a non-empty left pile. Pass requires hand size 5 and the card is in the hand. A duplicate action is rejected by state, not by luck.
- **Server acknowledges with a full own-hand snapshot plus monotonically increasing `seq`.** The client discards snapshots older than its latest. The client may animate optimistically but always reconciles to the snapshot.
- **Use reliable `RemoteEvent`s for card actions.** Do not use `UnreliableRemoteEvent` for anything that changes card state (it can drop and reorder). Reserve it for ephemeral cosmetic effects.
- **No `RemoteFunction` calls from server to client**, ever; a hostile or lagging client can hang the server thread.
- **Ring topology as a linked structure with explicit leave semantics** (see C9 for the rule to specify). A seat leaving (four-of-a-kind, disconnect, AFK-kick) is one atomic operation: remove cards, splice pile contents downstream, relink, emit events.

**Warning signs:**
- A handler with `task.wait`/`:Wait()`/`Async` between a read of `state` and a write to `state`.
- The remote payload contains a hand index or a destination seat.
- Card count in the ring is not constant in a debug assertion (`sum(hands)+sum(piles)+deck == initialTotal - removedSets*4`).
- Playtesters report "my card disappeared" or "I had 6 cards".

**Phase to address:** P2 (engine design and invariants), P3 (client reconciliation). Gate P2 on a card-conservation invariant checked after every action in simulation.

---

### C3: Jokers plus a shrinking circle can make the table unsolvable (severity C, likelihood MEDIUM-HIGH)

**What goes wrong:**
Deck composition is treated as "4 of each rank plus some jokers". Because jokers are wild and a finisher's 4 cards leave play:
- A player completing 3 kings plus a joker removes the joker but strands the fourth king. That rank can now only be completed with remaining jokers. Several wild-completions deplete the jokers and strand orphan cards, leaving remaining players holding cards that cannot form any set.
- The table stalls with spoons still on the map, wasting up to 5:00 of the round for everyone. The stall is invisible in testing with 3 players and appears at 8 to 10.
- Conversely, too many jokers means instant completions by several players on the first draw (no scramble) and first place is decided by network latency alone.
- Also ambiguous: is completion checked on the 4-card hand only (after passing), or on the 5-card hand after drawing? If a drawn card completes a set among 5 cards, does the player finish immediately, or must they pass first? Different answers produce very different feel and different race windows.

**Why it happens:**
Real Spoons has a deck-cycle and no joker-removal problem. The shrinking-ring-with-wilds variant is novel, so nobody has tuned it, and the PROJECT.md design asserts solvability without proving it.

**How to avoid:**
- Define deck construction as a function of seeker count (ranks needed, copies, joker count) and **prove solvability by headless simulation** over N = 3 to 10 with thousands of bot-played rounds. Measure: stall rate (no legal completion reachable), median time-to-first-completion, spread of completion order, and joker effect.
- Decide the wild rule explicitly. Options: (a) jokers only count as wild when completing a set and the stranded orphan card is *also* retired from play (complex: removes a card from someone else's hand); (b) cap jokers so a wild-completion cannot make remaining sets uncompletable (provable by deck design); (c) re-inject replacement cards. Pick (b) if simulation allows it. It is the simplest to implement and explain.
- Decide check timing once: recommended is "checked after every hand mutation, including the 5-card state; a 5-card hand with a valid four-of-a-kind completes immediately". Spell out which cards leave (the four forming the set) and what happens to the fifth.
- Note the game structure forgives some unsolvability: only N-2 spoons exist, so the last 1 to 2 table players never matter. The harmful case is mid-ring (for example 5 players remaining, spoons left, nobody can complete).
- Add a **solvability watchdog** only as a last resort (for example, if no completion in X seconds after Y players left, server redistributes jokers). Prefer prevention by deck design.

**Warning signs:**
- Simulation shows non-zero stall rate for any N.
- Playtests where "nobody can finish" for over about 60 seconds.
- First finisher is consistently the player seated nearest the deck/dealer, or finish order tracks ping.

**Phase to address:** P2 (spec plus simulator before any UI). This is the highest-value early de-risking step in the project.

---

### C4: Round-end and timer races (severity C, likelihood HIGH)

**What goes wrong:**
- A player completes four-of-a-kind or grabs the last spoon in the same frame the 5:00 timer fires. The result is double scoring, a negative or oversized find-time, or a round ending twice.
- The timer thread (`task.delay`/`task.wait` loop) wakes late. A claim processed after the true deadline but before the timer thread wakes still scores.
- **Stale scheduled callbacks.** A `task.delay` from round 3 fires during round 4, ending it early.
- The last spoon is found while another handler is mid-score; both call `endRound()`.
- Score arithmetic uses floats or client time, producing off-by-one-tenth discrepancies. A client-reported timestamp is forged to claim "more time remaining".

**Why it happens:**
The timer is modelled as an independent thread racing the event handlers rather than as part of the state machine.

**How to avoid:**
- **Absolute deadline, lazy check.** Store `deadline = serverNow + 300` once. Every handler (pickup, completion, pass) first computes `now >= deadline` and, if so, routes to "round ended" before doing anything else. The timer thread is only a backstop that calls the same idempotent `endRound(roundId, reason)`.
- **Round ID token.** Every scheduled callback captures `roundId` and no-ops if it no longer matches. This is the one-line fix for stale-timer bugs. Use `task.cancel` on phase exit as well.
- **Idempotent, one-way phase transitions:** `Hide -> Card/Hunt -> Ending -> Podium -> Intermission`. `endRound` returns immediately if already `Ending`.
- **Server arrival time is the only clock.** Never accept a client timestamp. Compute remaining time from `workspace:GetServerTimeNow()` (or `os.clock()` on the server) at the moment the server processes the claim. Store scores as integer deciseconds (`math.floor(remaining * 10)`), so a point is exactly 100ms and there is no float drift.
- **Define tie-breaks:** the second claim processed after the same decisecond ranks after the first, deterministically by processing order.
- **Define order of effects at the boundary:** completions or claims processed before the deadline count, others do not. Document and test with an injected clock.
- Lag-switching cannot backdate a server-stamped claim, so the cheater only hurts themselves. Do not add lag compensation in v1. Find-points noise from ping (0 to 300ms is 0 to 30 points) is negligible against the 100-point bonus steps.

**Warning signs:**
- `endRound` callable from more than one place without a guard.
- Any `task.wait(300)` used as the round timer.
- Scores with fractional parts; scores differing between client display and server record.
- Logs showing two "round ended" lines.

**Phase to address:** P1 (state machine with phase tokens and an injectable clock), P5 (scoring boundaries). Include deterministic boundary tests (claim at deadline minus 1ms, at deadline, at deadline plus 1ms).

---

### C5: Disconnects, AFK and churn on the ring and in the round (severity C, likelihood VERY HIGH)

**What goes wrong:**
Roblox players join and leave constantly, and each seat carries structural state.
- **AFK/disconnected player stalls the whole ring.** Cards drain into their left pile (upstream keeps passing in; they never draw). Upstream players starve of draws, downstream gets nothing, and everyone stops. One AFK player ruins the round for 8 others.
- **Mid-pass leave.** The leaver's hand, left pile and any in-flight pass vanish, so cards leave play without being accounted for.
- **Cards in a leaving player's left pile are lost** unless explicitly spliced downstream (also applies to four-of-a-kind completion: the finisher's 4 cards leave, but their pile contents must not).
- **Hider disconnect** has more cases than "mid-hide". Handle: before any placement; after partial placement; at exact hide-cap; during hunt after hide (spoons stay, hider scoring must finalize without the hider); and a hider who rejoins. Waiting the full 90s after the hider has left makes 8 players idle for nothing: detect `PlayerRemoving` and trigger auto-fill **immediately**.
- **Below minimum.** Seekers dropping so a round has fewer than 2 seekers or N below 3, or N-2 spoons exceeds the remaining seekers (3 players, 1 spoon: one seeker leaves, the other has no competition). With 2 players, N-2 = 0 spoons: degenerate.
- **Designated hider already gone.** "Rounds = starting player count, everyone hides once" breaks as soon as anyone leaves. Either skip that round (match shortens) or choose a replacement hider (someone hides twice, breaking fairness). Pick skip, and end the match when no remaining player has an unplayed hider turn or when below the minimum.
- **Round never ends** because all remaining seekers left or finished but spoons remain; the timer idles up to 5:00.
- **Everyone leaves / server shutdown** mid-match. There is no resume (match state is session-scoped); just make sure profiles save (see C11).
- **Character reset.** A player presses Reset (or falls off the parkour) and the character dies. Card state must be bound to the `Player`, not the character, or reset becomes a free "leave the table" exploit.

**How to avoid:**
- Seat-removal is one engine operation used by every exit reason (completion, disconnect, AFK-kick), with cards accounted for and piles spliced downstream. Fuzz it in the simulator: random leavers at random ticks, assert conservation.
- **AFK policy at the card table:** if a seated player has not drawn or passed within N seconds while their left pile is non-empty, enter auto-play (draw and pass a random non-pair card) or remove the seat. Never let a seat block indefinitely. Record AFK strikes.
- Round-end predicate includes "no active seekers remain" and "remaining seekers < remaining spoons AND none at the table".
- Match controller keeps a roster with states (`Active/Left/Joiner`), a hider queue (starting roster in rotation order), and explicit rules: skip departed hiders, end the match below 3 players, show results then return everyone to lobby.
- Player-bound state (`Player` keyed, not `Character` keyed). Set `Players.CharacterAutoLoads = false` and spawn deliberately. Disable the reset button (`StarterGui:SetCore("ResetButtonCallback", false)`, client-side, so it is a UX measure, not security). Make state recover regardless.
- Leaver-score policy: leavers' points stay on the board but they cannot win rewards or the "winner" title (decide, document).

**Warning signs:**
- A playtest where one player alt-tabs and the table freezes.
- Conservation assertion failures in leave-fuzzing.
- Rounds that last exactly 5:00 with zero finds after a leave event.

**Phase to address:** P2 (seat-removal semantics), P5 (round/match controller and hider queue), P1 (state machine). Churn tests belong in P5's acceptance criteria.

---

### C6: Spoon claim, pickup and movement exploits (severity C, likelihood HIGH)

**What goes wrong:**
- **Double-claim** of one spoon by two seekers in the same frame, or a re-claim after a reconnect.
- **Non-hunting players claim spoons.** A player who has not completed four-of-a-kind (still at the table or in the waiting room), the hider, or a dead/spectating player fires the claim remote.
- **Teleport/fly/noclip.** Roblox characters are client-network-owned; the server cannot prevent teleporting, only detect it. With a minimally leaked spoon set (C1) the exploiter must still sweep the map, which makes movement checks effective. Without C1, teleport directly to each spoon.
- **Waiting-room escape.** A seeker noclips out during the hide phase and watches the hider place.
- **Distance spoofing.** The server trusts a client-supplied position or "I am near" flag.
- **Glint abuse:** the close-range reveal radius is derived on the client, or a long-range raycast is exposed.

**How to avoid:**
- Claim handler is synchronous: check `player.state == "Hunting"`, spoon exists and `claimed == false`, **set `claimed = true` before any yield**, then compute score from the server clock. One spoon, one winner, by construction.
- Server validates distance from the **server-known** `HumanoidRootPart` position to the spoon (pickup radius plus a latency tolerance: roughly `walkSpeed * rtt`), plus a line-of-sight raycast. Never read a position from the remote.
- Movement sanity: sample positions at about 4 Hz; flag displacement over `maxSpeed * dt * tolerance` (ignore the vertical component while falling). **Rubber-band to the last good position and log; do not kick on one violation** (false positives come from lag, physics and spawn teleports). Escalate on repeated violations.
- Server-enforced zones: during Hide, seekers must stay within the waiting-room volume (periodic check, teleport back). During Card, seated players are server-anchored (not `Seat` instances they can stand from). Spoon-claim is allowed only in `Hunting`.
- Hider is removed from the map (spectator pod) at hide end, with a server lock on placements the instant the phase ends (see C8).
- Remember the map geometry itself is always visible to exploiters. Do not design any "secret room" mechanic that depends on hidden geometry.
- Disable player-to-player collisions with a `PhysicsService` collision group. This removes body-blocking in hotel/maze doorways, parkour griefing and physics "fling" exploits.

**Warning signs:**
- Claim handler reads `player.Character.PrimaryPart.Position` after a yield, or reads a position from the payload.
- Same spoon claimed twice in logs; "found" counts exceeding N-2.
- A player's find times consistently far below map-traversal minimum.

**Phase to address:** P4 (claim and visibility model), P8 (movement-sanity tuning with real latency data).

---

### C7: No remote gateway: unvalidated, unthrottled, or leftover remotes (severity C, likelihood HIGH)

**What goes wrong:**
Every `RemoteEvent` is directly callable by any exploiter with arbitrary arguments at arbitrary rate. Typical holes:
- No type/shape check on arguments (tables with extra keys, NaN, huge strings, wrong types crash a handler).
- No state/role precondition ("hider-only" placement fired by a seeker; "equip" fired mid-round; "pass" fired when not seated).
- No rate limit, so a loop spams the server with placement or equip requests.
- Developer/test remotes left in production (`SkipPhase`, `ForceStart`, `GrantCosmetic`), or Studio-only guards implemented client-side.
- Min-players override (`3 -> 1`) left in for testing.
- Kick-on-first-violation, which bans legitimate mobile players when reconnect bursts deliver queued events at once.

**How to avoid:**
- **One validated remote wrapper** used by all remotes: schema check (type, range, count), caller-state check (phase and role), per-player token bucket, and per-remote budget. Roblox's own client-server boundary guidance says to validate that values are logical for the requested action and that client-side rate limits must never be the only limit (MEDIUM-HIGH confidence; official docs updated June 2026 per search snippet).
- Silent drop plus log for rate overflow; escalate (rubber-band, temporary action lockout) on sustained abuse; kick only for clear, repeated, heuristic-independent cheats.
- Treat the first argument of `OnServerEvent` (the `Player`) as the only trustworthy identity.
- Keep dev-only remotes in a module that is not loaded in production (server-side environment flag, `RunService:IsStudio()` plus a place-ID allowlist). Add a CI grep for known debug remote names.
- A real card-engine budget: at about 8 to 10 inputs per second per player for a legitimate human (tap pile, select, tap pass), set the bucket to roughly 2x that to absorb bursts. Server CPU is not the concern; abuse and advantage are.

**Warning signs:**
- A remote handler that begins by indexing into the payload with no checks.
- Remote names containing `Debug`, `Test`, `Admin`, `Give`.
- Server logs without any rejected-action counter.

**Phase to address:** P1 (build the gateway first; every later remote uses it). P8 (audit all remotes).

---

### C8: Placement rails fail, and hiders are incentivised to defeat them (severity C, likelihood HIGH)

**What goes wrong:**
Because hider score rises with how long spoons survive unfound, a hider's rational strategy is "make it unfindable". Rails are all that stand between the design and a stalled game.
- **False negatives:** the spot is reachable but rails reject it (for example, requires a jump the pathfinding agent was not configured for), so hiders get "invalid" for legitimate creative spots and burn 90s of clock.
- **False positives:** the spot passes rails but is practically unfindable (inside a mesh pocket, behind transparent/non-collidable decor, atop geometry reachable only by a glitch, between two near-flush props, an overhead ledge needing a perfect jump).
- **Client/server mismatch:** the client shows a green ghost, the server then rejects. Hiders blame the game.
- **Avatar scale.** Roblox players can run different body scales and Rthro proportions. Reach, camera height and the ability to see over or under a counter differ. A spot "findable" for a tall avatar may be unfindable for a short one, and a scale-boosted hider or seeker has a real advantage that was bought, not earned.
- **Timing race:** a placement in flight when the hider ends the phase early or the 90s cap hits. It is accepted after seekers are released, or the hider keeps moving spoons after release.
- **Count/duplicate:** more than N-2 spoons, two spoons in the same spot, spoons inside the card table or the waiting-room exclusion zone.
- **Cost:** `PathfindingService:ComputeAsync` yields and is not free. Calling it inline in the remote handler reintroduces C2.
- **Unfound-at-timeout rate:** if hiders succeed, rounds regularly run the full 5:00 with the last spoon never found. Players who found theirs sit idle (see C11).

**How to avoid:**
- Normalise characters: load every player with a fixed `HumanoidDescription` scale (apply scale values on the server at spawn) so reach, height and hitbox are identical. Cosmetics are accessories only.
- Server-side validation is the authority: in-bounds hide-zone volume (data), not inside collision geometry (`GetPartBoundsInBox`), pathfinding reachability from a seeker spawn to a standable point within pickup radius (agent params matching the normalised character, including jump), line-of-sight from at least one standable point, min spacing from other spoons, exclusion radius around the card table, the waiting room and spawns.
- Share the same rule data with the client for the live ghost preview, but treat client as advisory. Show *why* a spot was rejected (distinct reasons) and make rejection instant. Time spent on rejections must not be punished.
- Resolve placement asynchronously: validate in a queue per hider, with a `placementEpoch`. When the hide phase ends, increment the epoch and discard in-flight requests.
- Freeze placement on phase end; remove the hider from the map.
- Build a **placement corpus**: a set of known good and known bad coordinates per map (including adversarial spots), run by the map linter on every map change (see C14).
- Add a **findability audit** as a second filter: reject spots whose only line of sight is from a position within X studs of geometry that blocks the camera, or that fail a reachability test for the *smallest* supported camera. Tune with playtests.
- Telemetry from soft launch: unfound-at-timeout rate per map and per hider; use it to tighten rails. Treat a high rate as a rail bug, not a player skill outcome.
- Note the fixed 16-plus default-spot pool is the fallback, but the pool is also the benchmark for what "findable" means on each map.

**Warning signs:**
- Playtesters reporting "I can't find it" after the round.
- Rounds always ending on the timer.
- Hiders complaining about rejections without reasons.
- The ghost/placement result differing between Studio and live.

**Phase to address:** P4 (rails, character normalisation), P6 (per-map zones and corpus), P8 (telemetry tuning).

---

### C9: Specification holes in the ring, seats, dealer and joiners (severity C, likelihood HIGH)

PROJECT.md says to treat the numbers as decided, but several *rules* are undecided. Each hole becomes a bug if the engineer fills it silently. **Lock these in a P2 spec document before coding:**

| Hole | Why it matters | Suggested resolution (to confirm with the owner) |
|------|----------------|-----------------------------------------------|
| Dealer = previous round's first spoon finder, but that player may be **this round's hider** | The dealer must be a seeker at the table | Dealer = first eligible finder in previous find order who is a seeker this round |
| Seat order for players who found nothing, the previous hider, and new joiners | "Find order" is undefined for them | Total order: finders by find time, then non-finders by four-of-a-kind rank, then previous hider, then joiners by join order; deterministic tiebreak by userId |
| First round has no previous round | No dealer or order | Seeded random order, recorded for the match |
| What happens to a leaving player's **left pile** contents | Cards vanish, breaking solvability | Splice into the downstream player's left pile (append) |
| Pile order (FIFO or LIFO) and visibility of pile contents | Affects information and strategy | FIFO, contents hidden, counts public (confirm) |
| Check four-of-a-kind on 4 or 5 cards, wild counting, stranded orphans | See C3 | Resolve in the spec plus simulation |
| **Mid-round joiner timing** | Joining during the hunt without doing the card stage gives a free spoon grab and steals from table finishers; also leave-and-rejoin dodges | Queue joiners until the next round start (they remain seeker-only, no added round); never insert them into a live hunt or card table |
| N changes between rounds | Spoons = N-2 uses which N? | N is fixed at round start; joiners increase later rounds |
| Four-of-a-kind bonus for players who never complete | Must not go negative past place 10 | Zero; clamp at 0 |
| Hider score formula | "Roughly the inverse" is not a formula | Define it exactly; then check the hider-turn expected value against the seeker-turn expected value |
| Returning player after leaving | Could skip their hider turn if it is unattractive | Treated as a joiner; forfeits unplayed hider turn |

**Why it happens:** The design was specified at the feel/scoring level but not as a state machine.

**How to avoid:** Write the P2 spec as an explicit state machine plus invariants. Resolve each row. Express each decision as a test case.

**Warning signs:** Engineer asking "what if..." in code review; behaviour differing between code paths for the same situation.

**Phase to address:** Before P2 begins (spec/discuss phase), then P2 and P5.

---

### C10: Paid cosmetics leak into gameplay (severity C, likelihood HIGH)

The hard rule is "nothing purchasable may affect score, findability or competitive outcome". It is violated accidentally, not by score multipliers but by these vectors:

| Cosmetic | How it breaks the rule |
|----------|------------------------|
| **Hider effects: glint colour** | Glint is the findability mechanism. A dim/low-contrast glint colour against a map's floor makes spoons harder to find (hider advantage); a high-contrast neon glint makes them easier. |
| **Spoon skins (hider's skin shows on the ground)** | Camouflaged skins (wood on wood), small mesh, thin profile, emissive/neon or transparent materials change findability. A hider scored on survival time benefits directly. |
| **Spoon skin hitbox/pickup** | If pickup uses the visual mesh bounds, size affects reach and visibility. |
| **Special decks (set by the dealer)** | Ornate or low-contrast faces reduce readability for everyone else while the dealer is familiar with their own deck. Colour-only suits fail colour-blind users. Heavy particle/mesh decks hurt other players' FPS on phones. Jokers must stay unmistakable. |
| **Hats/accessories/trails** | Oversized accessories occlude other players' screens or block line of sight; collidable accessories change physics; trails and particles cost FPS for everyone; scale-changing items (and Roblox avatar scale in general) change reach and camera height. |
| **Emotes/animation packs** | Different hip heights or movement timing can alter hitboxes and look "faster". |
| **Hider placement effects** | An animation that locks input for 1s per spoon slows the hider; a faster one speeds them. A visible placement burst could reveal location to nearby exploiters. |
| **Podium effects** | Long unskippable animations stall the next round. |
| **VIP lobbies** | Friend-only lobbies enable collusion and leaderboard farming; keep them out of any public ranking. |

**How to avoid:**
- **Architecture rule:** gameplay modules (card engine, scoring, hunt, placement, claim) must never `require` the cosmetics, inventory or shop modules. Enforce with a CI grep or lint check. Gameplay reads only a frozen, validated `Loadout` snapshot of IDs, applied to visuals by a separate presentation layer.
- **Schema rule:** the `CosmeticCatalog` schema allows only visual fields (mesh/texture/colour palette IDs, price, category). Anything gameplay-ish (size, hitbox, speed, range) is absent, so it cannot be configured.
- **Normalised footprint:** every spoon skin must fit the same bounding volume, use the same pickup hitbox and the same glint implementation (server-owned; skins supply only a tint within a *tested* contrast range). Glint size, brightness, range and timing are server-side constants, independent of skin.
- **Map contrast test:** render every spoon skin on every map's hardest backgrounds and compare against the default spoon. Reject any skin that is meaningfully harder or easier to find than baseline. Include this in the cosmetic submission checklist.
- **Deck template:** all decks share identical index glyph placement, font size, contrast ratio and suit shapes; art varies only in back/border/face art outside the index. Redundantly encode suit by shape and colour. Perf budget per deck.
- **Accessories:** `CanCollide=false`, `CanQuery=false`, `CanTouch=false`, size caps, polygon and particle caps. Trails and particles are distance-culled.
- **Normalised avatar** (see C8): fixed scale, no avatar-bought height or reach advantage.
- **Equip rules:** server validates ownership and only accepts equips in the Lobby state; `Loadout` is frozen at round start. A client "equip" remote naming an unowned item is also free-cosmetics piracy.
- **Review gate:** run the `robux-economy-review` pay-to-win check on every SKU before launch; one pay-to-win item blocks shipping.

**Warning signs:**
- A cosmetic data table containing numeric fields beyond price.
- A glint colour picker that is a free colour.
- Playtesters saying one skin is "impossible to see".

**Phase to address:** P1 (architecture/lint rule), P4 (glint constants), P7 (catalog schema, tests), P8 (economy review).

---

### C11: `ProcessReceipt` and purchase-grant mistakes (severity C, likelihood HIGH)

**What goes wrong:**
- **Multiple `ProcessReceipt` assignments.** `MarketplaceService.ProcessReceipt` is a single callback per server; if two scripts assign it, the last one wins and the other product silently never grants. (MEDIUM-HIGH, from training; verify.)
- **Granting before persisting**, or returning `PurchaseGranted` when the save failed. The player is charged and has nothing after a crash.
- **No dedupe by `PurchaseId`.** Roblox may re-invoke the callback (retries, rejoin), so the player is granted twice or an item stacks.
- **Granting into an unloaded profile** or temporary default data that is later overwritten.
- **Yielding forever** in the callback while a profile loads; or throwing an error and returning nothing.
- **Trusting the client** (`PromptGamePassPurchaseFinished` or a client "I bought it" remote) to grant. Always grant server-side.
- **Game pass ownership caching.** `UserOwnsGamePassAsync` can lag right after purchase; handle with the finished-event plus re-check. (MEDIUM, verify.)
- **Placeholder IDs.** Product/pass IDs from a Studio-only or test universe do not exist in production; the shop shows items that cannot be bought or grants the wrong one.
- **Purchase during a round** and the grant touching match state (should only touch the profile and lobby).

**How to avoid:**
- One `PurchaseService` that owns the single `ProcessReceipt` callback. It:
  1. looks up the player's profile; if not loaded or the player is gone, returns `NotProcessedYet`;
  2. checks `PurchaseId` against a bounded recent-receipt log kept inside the profile (the ProfileService developer-products tutorial uses a ring of roughly 30 recent IDs; confirm sufficiency);
  3. applies the grant and writes the receipt ID to the *same* profile mutation;
  4. waits for the save to be durable (or the profile released), then returns `PurchaseGranted`.
- Any error path returns `NotProcessedYet`, never a silent success.
- **Prefer game passes for permanent cosmetics** where practical. Ownership is a Roblox-side source of truth, so a DataStore loss or a profile bug is recoverable by re-granting from pass ownership. Developer products for any consumable or repeatable purchases. If you choose products-only, maintain a purchase ledger, because a lost profile means lost paid items with no recovery path. (Design reasoning; HIGH.)
- All IDs live in one versioned `CosmeticCatalog`/`EconomyConfig`; verify each ID resolves in the production universe at startup (`GetProductInfo`).
- Test the full flow on a published test place with test Robux/purchases, not in Studio alone.
- Never hide the Robux price or the exact thing granted.

**Warning signs:**
- More than one `.ProcessReceipt =` in the codebase.
- Receipt handler with no early-return path for profile-not-loaded.
- Support reports "I paid but didn't get it".

**Phase to address:** P7 (PurchaseService), P8 (published-place purchase test and economy review).

---

### C12: Persistence: data loss, Studio writing to production, ID instability (severity H-C, likelihood MEDIUM-HIGH)

**What goes wrong:**
- Raw `DataStore` `SetAsync` without session locking, so two servers (teleport, rejoin, VIP) overwrite each other and cosmetics duplicate or vanish.
- Saving on every equip or every round, hitting request budgets. DataStore budgets are per-server and scale with player count (roughly 60 + 10 per player per minute for gets and sets; verify against the official limits page); saving per equip or per round across 10 players eats this.
- **Profile load failure -> default data -> overwrite.** The player shows an empty inventory and then the empty data is saved over the real profile.
- **BindToClose** missing, or registered inside `PlayerRemoving`. Servers get a short grace (roughly 30s) on shutdown; unsaved purchases are lost.
- **Studio with "API Services" enabled writes to the production DataStore** of the published game. Developer testing corrupts or wipes live data.
- **Unstable cosmetic IDs.** Using asset IDs or array indices as ownership keys. When an asset is moderated, replaced or reordered, owned items disappear or swap. Removed or seasonal items break equip logic.
- **No schema version**, so adding a cosmetic category or a field breaks old profiles.

**How to avoid:**
- Use **ProfileStore** (MadStudioRoblox; successor to ProfileService, session-locked; also the house rule in `roblox-ai-build`). Use `ProfileStore.Mock` for Studio, plus a separate test universe or place for integration tests. Never test persistence in the production universe.
- Persist only: owned cosmetic IDs, equipped loadout, a schema `Version`, the receipt log, optional stats. Match state is session-only (no resume).
- Mutate the in-memory profile on equip; autosave on a timer (ProfileStore default cadence is fine); save on `PlayerRemoving` and `BindToClose`.
- Stable internal IDs (`"spoon.gold_01"`) mapped to asset IDs in the catalog. Never reuse or renumber. Unknown owned IDs are preserved but hidden; equipped-but-missing falls back to default.
- If the profile fails to load: do not offer the shop, do not apply grants (`NotProcessedYet`), retry; kick with a clear message after N retries. Never play on temporary data that can overwrite.
- Version migration function chain (`v1 -> v2 -> ...`), tested with fixtures of old profiles.
- ProfileStore's session-lock steal after a crash takes a while (a forum report says roughly 80s; LOW confidence), so a player who rejoins immediately after a server crash may be briefly blocked. Handle with a "loading, please wait" state.

**Warning signs:**
- A `DataStoreService:GetDataStore` call outside the persistence module.
- Zero tests covering "profile load failed".
- Studio test sessions that mutate real keys.

**Phase to address:** P1 (persistence skeleton and test universe), P7 (schema, migrations, loadout).

---

### C13: Mobile parity failures (severity H, likelihood VERY HIGH)

**What goes wrong:**
- **Crowded bottom edge.** The default thumbstick (bottom-left) and jump button (bottom-right) compete with 5 cards plus 2 piles. A roughly 667pt-wide landscape screen minus about 2x140 for the default controls leaves about 390 for 7 targets, about 55px each before margins (estimate; verify on devices). Taps hit the jump button or a neighbouring card.
- **Tap targets below ~44 to 48px** (Apple HIG 44pt / Material 48dp, general UI guidance, not Roblox-specific).
- **Safe areas.** Notch/home-indicator cutouts and the Roblox top bar occlude UI. `ScreenGui.ScreenInsets` controls this: `CoreUISafeInsets` (default) keeps contents below the Roblox top bar; `DeviceSafeInsets` avoids cutouts only, with no top-bar inset (MEDIUM-HIGH; from docs search snippets). Anchoring card UI to hard offsets breaks across devices.
- **Hover-dependent states** (selection highlight on hover) do not exist on touch. Selection must persist visually until the second tap.
- **Camera control during search.** Sweeping a space on a phone needs second-finger camera drag, and tight corridors (maze, hotel) make the Roblox camera zoom into walls. Hunts that are fine on a mouse feel miserable on touch.
- **Console and other devices enabled by default.** If the experience's device settings are left at defaults, console and VR players can join a game with no gamepad UI navigation.
- **Performance on low-end phones.** 10 avatars with accessories, trails and particles; a heavy map; a high instance count; texture memory. Mobile clients crash from memory pressure rather than slowly degrading.
- **Different ProximityPrompt/hold behaviour** between devices makes pickup slower on one platform.
- **Orientation.** Portrait or auto-rotate if unset.

**How to avoid:**
- Hand UI is a 2D `ScreenGui`, not world-space 3D card meshes (3D tap targets depend on camera and distance). Use Scale-based sizing with `UIAspectRatioConstraint`/`UISizeConstraint`, and set `ScreenInsets` deliberately.
- **Disable the default movement controls during the card phase** (seated players do not need a thumbstick or jump button): `require(Player.PlayerScripts.PlayerModule):GetControls():Disable()`, re-enable at hunt start. This frees the full bottom of the screen for the hand. (Mechanism MEDIUM; verify it works with the current PlayerModule.)
- Minimum target size about 48px effective; selected state is persistent (raised/outlined card), not hover. Use `Activated` for unified touch and mouse input.
- Fan or overlap cards if needed, while keeping each card's hit area at or above the minimum.
- Set supported devices explicitly in experience settings (disable Console/VR unless gamepad navigation via `GuiService.SelectedObject` is built) and set `ScreenOrientation` explicitly (landscape).
- Maze and tight spaces: camera collision settings, wider corridors, and playtest the camera on a phone before art is final.
- Pickup interaction: a single large context button; no hold duration, identical across devices.
- Perf budgets (`PERF_BUDGET.md`): cap triangles, particles, trails, texture sizes per cosmetic and per map; cull cosmetics by distance; test on a genuinely low-end Android, not just an emulator. The `roblox-ai-build` rule: target 60 FPS on low-to-mid phones with the max party size, and include a phone-resolution capture of every UI screen.

**Warning signs:**
- UI authored only at desktop resolution; no phone-resolution review capture.
- Hit-test debugging shows taps registering on the jump button.
- Crash reports from mobile after several rounds (memory leak from uncleaned map instances).

**Phase to address:** P3 (card UI), P6 (maze/map camera), P8 (device matrix).

---

### C14: Map-heavy content: inconsistent spots, per-map special-casing, asset hazards (severity H, likelihood HIGH)

**What goes wrong:**
- Five maps authored at different quality; some spots unreachable, inside geometry, or clustered in one room. The ">= 16 defaults per map" count is met but the *usable* count after exclusions (spacing, already-used, exclusion radius) is under 8.
- Auto-fill picks 8 spots at random, and by chance all land in one room, or beside the card table, producing a trivial round.
- Per-map code branches (`if map == "Maze" then ...`) accumulate. The maze's decoy items are the only intended special case and must not become a pattern.
- Decoys that look like spoons but also have pickup behaviour or prompts, or decoys that show up in the glint logic.
- A map too small (instant finds, find-points dominated by speed) or too large (find-points dominated by walking time). Map choice then skews scoring.
- Free-model/Toolbox assets carrying backdoor scripts (`require(<id>)`, `loadstring`, `HttpGet`).
- Whole-map load: all five maps sitting in the world at once, or cloning a full map on round start causes a hitch and memory growth; old maps not fully cleaned (connections, instances) leak across rounds.
- Greybox maps shipped as finished (the `roblox-ai-build` default failure mode).

**How to avoid:**
- **Maps are data.** A `MapDefinition` schema: hide-zone volumes, exclusion volumes (card table, waiting room, spawns), default spots (with zone tag), seat anchors, waiting-room spawn, per-map tuning (pickup tolerance, etc.). Zero per-map code. Special mechanics become tagged parts or data flags (decoys are `CollectionService` tagged and purely decorative, with no prompt and no pickup path).
- **Map linter** (run via the Studio MCP `run_code` in Edit mode, programmatic raycast-first per `roblox-ai-build` review loop): every default spot reachable, standable-visible, not in geometry, not near exclusions, minimum spacing, >= 16 *usable after exclusions*, distribution across zones. Plus the placement corpus (C8).
- **Stratified auto-fill:** choose without replacement across zones, excluding spots near already-placed spoons, rather than uniform random over the whole pool.
- Load only the active map (instantiate from `ServerStorage`, not all five in `Workspace`). Destroy it fully at round end and disconnect everything. Track instance count per round to catch leaks. Decide StreamingEnabled with real phone tests, as client-side raycasts for the placement preview can miss unstreamed geometry.
- Playtest time-to-first-find and unfound rate per map, aiming to keep them within a band so map choice does not dominate score.
- Asset sanitisation: insert third-party assets only in Edit mode, strip every script, scan for backdoor patterns, register each asset in the asset-kit registry.
- Build one reference map end-to-end (map-as-data, linter, perf) before authoring the other four. Treat that map as the template and review the first instance in full.

**Warning signs:**
- Any `MapName ==` comparison in gameplay code.
- Linter reports "usable spots = 9".
- Per-round memory climbing in the Developer Console.

**Phase to address:** P6, with the schema and linter defined at the end of P4.

---

## Moderate Pitfalls

### M1: Dead time, match length and quitting (severity H, likelihood HIGH)

**What goes wrong:** A 10-player match is 10 rounds, each up to 90s hide + 5:00 hunt + 10s podium + transitions, potentially an hour or more. Typical Roblox sessions are far shorter (no hard number cited; treat as risk). Players who finish early wait for the last spoon (up to 5:00); players with no spoon stay at the card table until it ends; hiders sit out the hunt; the waiting-room parkour has no stakes. Players quit mid-match, which feeds C5 and shrinks future rounds.

**Prevention:**
- Make leaving free and joining easy (queued joiner flow, see C9). Never make a player feel trapped.
- Fill finished-player time: spectate hunters, emotes in a social space, a mini-feed of finds, a visible live scoreboard.
- Parkour room: give it a purpose (cosmetic-only finish effect, optional, but a fun distraction; reset on fall).
- Consider ending the round once the remaining table players cannot matter (for example, all N-2 spoons found already ends it). Consider an "unfound ticking" cue so the final hunt has a shared climax.
- Telemetry: round at which players quit, per-round duration distribution. Define a target median round length and a target match length, then tune.
- Offer match length as a lobby option (for example, a short match where each player hides once among a subset)? This would change "rounds = starting player count"; only raise it as a design question, not a unilateral change.
- Hider-turn balance: compute hider expected score versus seeker expected score by simulation. If hiding is clearly better or worse, players will dodge or abuse it (leave before your turn, rejoin as joiner). Also consider rotation order: a fixed order gives the last hider a decisive final-round advantage.

**Phase:** P5 (flow, balance sim), P8 (telemetry and tuning).

### M2: Cold start and empty lobbies (severity H, likelihood HIGH)

**What goes wrong:** The minimum is 3 players and the sweet spot is 6 to 10. With low CCU at launch, servers sit at 1 to 2 players, nothing starts, and players leave. Reviews say "empty".

**Prevention:** Lobby intermission with visible player count and a countdown that starts at 3; server fill rather than spreading across many servers (cap server count, prefer joining the fullest); lobby activities while waiting (parkour, cosmetics preview); friend-join and party invites; possibly use the VIP/private-server path for friends. Avoid bot fill for seekers unless explicitly designed (it undermines the hide-and-seek premise and scoring). Budget for a marketing/launch plan; this is not solvable by code alone.

**Phase:** P5 (lobby start rules), P8 (launch).

### M3: Automation and pass-rate spamming (severity M, likelihood HIGH)

**What goes wrong:** A scripted auto-solver or macro draws and passes optimally at machine speed; an autoclicker raises cycle rate. Server CPU is fine; the unfairness is the problem. A bot reading its own (legitimately known) hand cannot be detected by hand-state checks.

**Prevention:** Server-enforced minimum interval per transition (draw-to-pass and pass-to-draw), set just below the fastest plausible human (tune with playtest data; start around 100 to 150ms); statistical flagging of low-variance inter-action timing (humans jitter, bots do not); soft penalties (action drop plus log) rather than bans on a single signal. Accept residual risk: an assisted human at the floor interval is indistinguishable from a skilled human. Note Roblox's client anti-tamper (Hyperion on Windows) raises the bar for injecting executors but does not eliminate it (MEDIUM-LOW; verify current state).

**Phase:** P2 (interval constant), P8 (telemetry and tuning).

### M4: Optimistic-UI feel versus latency (severity M, likelihood HIGH)

**What goes wrong:** Round-trip on mobile is 100 to 300ms. If the card moves only after the server ack, passing feels sluggish and kills the "frantic" core value. If the client moves optimistically, rejections cause visible snap-back.

**Prevention:** Animate immediately on tap (client prediction with the selection state local), reconcile on snapshot (C2). Design the left-pile lock indicator as client-predicted. Use Studio's incoming replication lag simulation (network settings) and test at 150 to 300ms. Keep the rejection rate low by giving the client enough state (own hand, pile count) to predict correctly.

**Phase:** P3.

### M5: Ghosting and information sharing (severity M, likelihood HIGH)

**What goes wrong:** Players who already found a spoon chat or voice "it's under the sofa" to those still hunting; the hider tells a friend. The most common "exploit" in hide-and-seek games, and unsolvable by code for voice/third-party.

**Prevention:** Channel permissioning in `TextChatService`: finished/spectating players cannot post to hunters (separate channel); disable proximity voice; accept third-party collusion as residual. Do not over-invest; make the scoring design robust (hider loses score if they hide poorly) rather than policing friends.

**Phase:** P5/P8.

### M6: Stale state across rounds and phase transitions (severity M, likelihood HIGH)

**What goes wrong:** Leaked connections (for example, a `Heartbeat` connection from last round's claim logic), leftover spoon visuals, old UI, stale `roundId` callbacks, players stuck in seat state from a previous round.

**Prevention:** Per-round `Janitor`/`Maid` scope (or `Trove`) that owns every connection and instance created in a round; destroy it on round end. Round ID tokens (C4). Per-round assertion that world and state are at baseline when entering `Hide`.

**Phase:** P1, P5.

### M7: Round-start readiness (severity M, likelihood HIGH)

**What goes wrong:** The 90s hide clock and the 5:00 round timer start on the server regardless of whether a client has loaded (streaming, slow phone). The hider, or a slow seeker, loses real time, and find points (10 per second) are unfair to low-end devices.

**Prevention:** A ready barrier at phase start: wait for client "ready" ack from each participant with a short timeout (a few seconds), then start the clock for everyone. A slow client past the timeout proceeds (do not hold 8 players for 1). Preload the card UI and assets during the hide phase while seekers are in the waiting room (the design already has this window).

**Phase:** P5.

### M8: Shop and monetization design (severity H, likelihood HIGH) (per `robux-economy-review`)

**What goes wrong:**
- Thin catalog at launch (a few skins, no price ladder), no best-value anchor, no starter bundle, items without working purchase UI. The skill treats a 1 to 3 item shop as almost always under-built.
- Display-slot mismatch: spoon skins appear mainly when the buyer hides (about once per match) or carries a spoon; deck skins only when the buyer is dealer. Buyers pay for items they rarely see on show. Character cosmetics (always visible) carry most of the value. Expect low conversion on the rarely-shown slots, and weigh pricing accordingly.
- Wrongly applying the PvE economy pattern. The skills' two-currency model, time-skips and accelerators do not apply here: the game has no waits to sell skips for, and any accelerator or booster would be exactly the pay-to-win the project forbids. Do not add a soft currency or boosters to make the catalog "look complete".
- Paid random items (mystery crates). Roblox's Paid Random Items policy (page last updated 2026-10-15 per search) requires disclosing all outcomes and exact odds before purchase, covers indirect purchases (keys, tickets) and luck boosters, and has regional restrictions (for example, a reported UK restriction). v1 should use direct-purchase only.
- FOMO and misleading offers aimed at a young audience (countdown timers, unclear Robux amounts).
- Ignoring that no-purchase players need a good experience: offer at least some earned cosmetics (for example, by podium finishes) so the game does not feel pay-to-look.
- Custom VIP lobby systems that duplicate Roblox's native private-server mechanism.

**Prevention:** Single versioned `CosmeticCatalog` with price ladder (impulse / mid / premium), exact Robux price and exact contents displayed, preview before buying (ViewportFrame preview is a perf cost on mobile; budget it), a starter bundle, and a best-value anchor in any bundles. Run `robux-economy-review` before launch. Decide VIP via Roblox private servers (verify price rules) before building a custom system.

**Phase:** P7, P8.

### M9: Single-point config and magic numbers (severity M, likelihood HIGH)

**What goes wrong:** Scoring constants (1000, -100, x10), timers (90, 300), spots (>= 16), deck composition, rate limits, and prices scattered through scripts.

**Prevention:** Single typed `GameConfig` module (and `CosmeticCatalog`), unit-tested against PROJECT.md's worked examples (1600 find points; 800 + 600 = 1400).

**Phase:** P1/P5.

### M10: Testing limits (severity M, likelihood HIGH)

**What goes wrong:** Studio's local multi-client test supports a limited number of clients (verify the current cap; historically 8), so a 10-player table cannot be fully tested locally; a single MCP session is one client; reserved-server flows and live DataStore load validate only on a published place. Latency is not simulated by default.

**Prevention:** Test the pure card engine headless (simulator, N up to 10 with bots; consider running Luau outside Studio with a standalone runtime such as Lune, or TestEZ/Jest-Lua inside Studio; verify tooling). Then local multi-client (up to the cap) for integration, then a published test place with real people for 9 to 10. Use incoming-replication-lag simulation. Plan human playtests as explicit gates (`NEEDS_HUMAN.md`).

**Phase:** P2 (simulator), P8.

### M11: Reset, falling and hazards (severity M, likelihood MEDIUM)

**What goes wrong:** Parkour falls and hazards kill the character; Reset teleports the player; death during the table phase or hunt corrupts state. See C5 for the state-binding rule.

**Prevention:** Parkour has catch-floors that teleport back rather than kill; no kill bricks in hunt maps; `CharacterAutoLoads = false`; respawn handler restores the correct location per phase.

**Phase:** P5/P6.

---

## Minor Pitfalls

- **L1: Podium cosmetics stall flow.** Unskippable animations longer than the 10s moment. Cap animation length, make the next phase timer independent.
- **L2: Dealer disconnected before using a deck.** Fall back to the default deck if the dealer left or their loadout cannot be validated.
- **L3: Camera and UI on emotes.** Emote wheel conflicts with card UI during the table phase; disable emotes in-phase.
- **L4: Sound spam.** Nine players' simultaneous pass sounds saturate audio. Rate-limit and cull by distance.
- **L5: Nameplates.** Default `BillboardGui` nameplates clutter the card table and reveal nothing useful. Use styled, distance-culled ones.
- **L6: Colour-only information.** Suits or selection state conveyed only by colour. Use shape plus colour.
- **L7: Localisation/long names.** Cosmetic names overflowing mobile UI; use `UITextSizeConstraint`.
- **L8: Chat filtering of player-visible strings** (if any custom text is shown from users, such as nicknames), must use Roblox's text filtering. Currently no UGC text planned; keep it that way.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Cards as 3D world Parts with rank data on the instance | Fast visual prototype | Leaks hands (C1), tap targets bad on mobile (C13) | Never for real hands; face-down meshes without data are fine |
| Hand index in remote payload | Simpler UI code | Stale-index bugs (C2) | Never |
| Real spoon Parts in Workspace with a ProximityPrompt | Free pickup and glint | Total position leak (C1) | Only in a throwaway prototype before P4 |
| Inline handler logic with yields | Quick to write | Races (C2) | Never in the card engine/claim path |
| `task.wait(300)` for round timer | Trivial | Late wake, stale timers (C4) | Never; use deadline plus token |
| Per-map `if` branches | Fast for map 2 | 5-map maintenance cost (C14) | Never beyond tagged data flags |
| Raw DataStore instead of ProfileStore | Fewer dependencies | Duplication and loss (C12) | Never for ownership data |
| Hardcoded product IDs in scripts | Quick | Wrong-universe failures, shop drift (C11) | Never |
| Rate limit = kick | Simple | False positives on mobile bursts | Only for unambiguous cheats |
| Greybox maps through launch | Time saved | Looks like a prototype; perf unknowns | Only through layout lock |
| Skipping the headless simulator | Saves a week | Late discovery of unsolvable decks (C3) | Never |
| Test overrides (min players = 1, skip phase) | Faster dev | Left in production (C7) | Only behind a server env flag and an allowlist |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `MarketplaceService.ProcessReceipt` | Several scripts assign it; grant before save; no dedupe | One owner; dedupe by `PurchaseId`; grant and receipt in one profile write; `NotProcessedYet` on any failure |
| Game passes | Trusting a client finished-event; stale `UserOwnsGamePassAsync` | Server verifies; re-check after purchase event; use passes as recoverable source of truth |
| ProfileStore | Using it in Studio against production; not releasing on leave | `Mock` in Studio; test universe; release in `PlayerRemoving` and `BindToClose` |
| `BindToClose` | Registered inside `PlayerRemoving` | Register once at startup; iterate current players |
| `PathfindingService` | Yielding call inside a remote handler | Queue; separate from the card engine; agent params matching the normalised character |
| `TextChatService` | One global channel | Per-phase channels for ghosting control |
| `PhysicsService` | Default player collisions | Collision group for no player-player collisions |
| `TeleportService` / private servers | Building a custom VIP system | Prefer Roblox private servers; if custom, reserved servers with careful profile locking |
| `StreamingEnabled` | Enabled late; placement preview relies on unstreamed geometry | Decide early; test with phones; server remains authority |
| Rojo | Logic edited in Studio only | Git is the source of truth (house rule) |
| Toolbox / Creator Store | Inserting free models in Play mode | Edit mode, strip scripts, scan for backdoors, register assets |
| Studio MCP | Mutating the wrong place | Verify `PlaceId`/name before any mutation; undo waypoint |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Broadcasting full table state on every action | Bandwidth spikes, leak (C1) | Per-player own-hand snapshots plus small public deltas | 9 clients actively passing |
| Server raycast/glint polling too frequent or for all pairs | Server Heartbeat time climbs | 5 to 10 Hz, hunting seekers x unclaimed spoons only (about 9 x 8 = 72 pairs; trivial) | Only if polled per frame or with expensive pathfinding |
| Pathfinding per placement on the hot path | Hitches during hide | Queue and async; cache the navmesh | Many rapid placements |
| Cosmetic particles and trails on 10 avatars | FPS collapse on phones | Per-item budgets; distance culling | 10 players on low-end Android |
| Whole-map loads / leaked map instances | Memory growth per round, mobile crashes | Load one map; full cleanup; instance count telemetry | Round 5 to 10 on a phone |
| Many `ViewportFrame`s in the shop | Shop lag on mobile | Lazy single preview, low resolution | Large catalog |
| UI tweens on every card for every player | Frame drops | Pool UI objects; limit concurrent tweens | Many simultaneous passes |
| Texture-heavy decks (large `SurfaceAppearance`) | Memory spikes | Texture size caps; atlas | Mobile |
| Saving on every equip/round | DataStore throttling warnings | Mutate in memory; autosave timer | About 10 players per server with frequent saves |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Client-sent card index or target seat | Wrong or duplicated card; routing to departed seat | Card IDs; server resolves the target |
| Full table state sent to all clients | Everyone sees all hands | Per-player snapshot |
| Spoon Parts or markers replicated | Position dump | Server-memory spoons; proximity-gated client visuals |
| Default-spot pool readable | Exploiters and players precompute | Server-only storage |
| Client timestamps accepted | Forged find-time | Server arrival time only |
| Spoon claim without state and distance check | Non-hunter or teleporter claims | Synchronous claim with state, distance and LOS; claimed flag before yield |
| No movement sanity | Teleport/fly sweeps | Sampled speed check with rubber-band |
| Hide-phase waiting-room bounds not enforced | Spying on the hider | Server volume check |
| Equip remote without ownership or phase check | Free paid cosmetics; mid-round swaps | Ownership and Lobby-state validation; frozen `Loadout` |
| Leftover debug remotes | Full game takeover | Env-gated; CI grep |
| Grant on client signal | Free items or double grants | Server-only `ProcessReceipt` |
| RemoteFunction server-to-client | Hung server thread | Events only |
| `UnreliableRemoteEvent` for state changes | Dropped/reordered actions | Reliable for game state |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Wait for server ack before moving a card | Feels laggy, kills the frantic loop | Predict locally, reconcile |
| No feedback on rejected placement reason | Hider wastes the 90s | Show reason; instant client preview |
| Idle finished players | Boredom, quitting | Spectate, social activity, live feed |
| Hover-only affordances | Invisible on touch | Persistent states |
| Tiny cards on phones | Mis-taps and rage-quit | 48px targets; hide movement controls in card phase |
| Thumbstick and jump overlap the hand | Accidental jumps or lost taps | Disable default controls at the table |
| Podium unskippable | Delays the next round | Hard 10s, skippable for the owner |
| Matches feel endless with no progress marker | Mid-match quits | Round counter, match progress bar, clear standings |
| Unexplained scoring | "Why did I get 0?" | End-of-round breakdown (bonus plus find points) |
| Joker not obviously wild | Confusion | Distinct art plus tooltip on first sight |
| Shop without previews or clear prices | Distrust, low conversion | Preview, exact Robux price, exact contents |

## "Looks Done But Isn't" Checklist

- [ ] **Card engine:** conservation invariant passes after 100k+ simulated actions with random leavers, for every N in 3 to 10. Verify no stalls.
- [ ] **Seat removal:** leaving player's pile contents spliced downstream; mid-pass leave tested; in-flight actions to departed seats routed correctly.
- [ ] **Round timer:** boundary tests at deadline -1ms/0/+1ms; double `endRound` is a no-op; a stale timer from a prior round cannot fire.
- [ ] **Scoring:** reproduces PROJECT.md worked examples exactly (1600; 800 + 600 = 1400); integers only; bonus clamped at 0.
- [ ] **Spoon claim:** two simultaneous claims yield exactly one winner; non-hunter claims rejected; remote-supplied position ignored.
- [ ] **Replication audit:** in Play (Client), no hand, spoon or default-spot data is visible in the client DataModel or remote payloads outside the owner's.
- [ ] **Hider paths:** disconnect before/during/after placing, at cap, early end, and hider already departed at turn start; auto-fill is immediate on leave and stratified.
- [ ] **Match churn:** drop to below 3 players mid-match, everyone leaves, joiner during each phase, rejoiner, designated hider gone.
- [ ] **AFK at the table:** a frozen seat does not stall the round.
- [ ] **Remote gateway:** every remote has schema, state, rate; no debug remotes in production build.
- [ ] **Cosmetic neutrality:** gameplay modules do not `require` cosmetics; catalog schema has no gameplay fields; every spoon skin passes the contrast test on all 5 maps; decks share the index template; accessories non-collidable.
- [ ] **Avatar normalisation:** body scale identical for all; reach/height identical.
- [ ] **Purchases:** single `ProcessReceipt`; duplicate receipt is not re-granted; profile-unloaded returns `NotProcessedYet`; tested on a published test place; every SKU has working shop UI.
- [ ] **Persistence:** profile-load-failure path; Studio cannot write to production keys; schema migration test with an old fixture; unknown cosmetic IDs handled.
- [ ] **Mobile:** every screen captured at phone resolution; safe-area and top-bar tested; 48px targets; controls hidden in card phase; real low-end device 60 FPS with 10 players; console/VR device settings explicit; no memory growth over 10 rounds.
- [ ] **Maps:** each passes the linter (>= 16 usable defaults after exclusions); no map-name branches; first-find time within the target band; no free-model scripts.
- [ ] **Round readiness:** slow-loading client does not lose timer time; barrier has a timeout.
- [ ] **Match length:** measured median match duration and drop-off point from a real 6 to 10 player playtest.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Replication leaks (C1) discovered after launch | HIGH | Move state server-side and rework the visibility model; breaking changes to UI and spoons; announce reset of any affected leaderboards (none by default) |
| Card race bugs (C2) | MEDIUM | Extract pure engine; add invariants; replay logs through the simulator to reproduce |
| Unsolvable deck (C3) | MEDIUM | Change deck composition constants; ship hotfix; no data migration needed |
| Timer/boundary bugs (C4) | LOW | Add round-token guards; patch |
| Missing churn handling (C5) | MEDIUM | Add AFK auto-play/removal and hider-skip rules; mostly state machine work |
| Spoon exploits (C6) | MEDIUM | Tighten claim validation; add movement sanity; ban repeat offenders |
| Open remotes (C7) | MEDIUM | Put every remote behind the gateway; audit |
| Pay-to-win cosmetic discovered (C10) | MEDIUM-HIGH | Remove or retune the item immediately; refund or swap affected buyers; revise catalog schema |
| Double-grant or lost purchase (C11) | MEDIUM | Reconcile from pass ownership or receipt log; support grants; fix dedupe |
| Profile overwrite or loss (C12) | HIGH | Restore from ProfileStore history/backups if available; reconcile from pass ownership; compensation grants. Prevention is far cheaper |
| Mobile UI failure (C13) | MEDIUM | Re-layout the card UI; device matrix testing |
| Bad map spots (C14) | LOW-MEDIUM | Edit the data and rerun the linter; no code changes if map-as-data was kept |
| Quit-from-boredom (M1) | MEDIUM | Tune round/match length; add spectate and social features |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| C1 Replication leaks | P1 rules; P2; P4 | Client-DataModel audit shows no secret data; CI grep |
| C2 Card races | P2, P3 | Conservation invariant in simulator; stale-index test |
| C3 Unsolvable deck | P2 (pre-UI) | Simulator reports zero stalls for N = 3 to 10 |
| C4 Timer/round races | P1, P5 | Injected-clock boundary tests; stale-token test |
| C5 Churn/AFK/disconnect | P2, P5 | Leave-fuzzing; scripted churn scenarios |
| C6 Claim and movement exploits | P4, P8 | Two-claim test; non-hunter claim rejected; teleport test |
| C7 Remote gateway | P1, P8 | Remote inventory audit; abuse script bounced |
| C8 Placement rails | P4, P6, P8 | Placement corpus passes; unfound-at-timeout telemetry |
| C9 Spec holes | Pre-P2 spec | Written decisions plus tests for each row |
| C10 Cosmetic leakage | P1 rule; P4; P7; P8 | Lint on `require`; contrast test; economy review PASS |
| C11 ProcessReceipt | P7, P8 | Duplicate-receipt test; published-place purchase |
| C12 Persistence | P1, P7 | Load-failure and migration tests; Studio write protection |
| C13 Mobile parity | P3, P6, P8 | Phone-resolution captures; real-device 60 FPS; safe-area test |
| C14 Map content | P6 (schema end of P4) | Linter green on all five maps |
| M1 Dead time/match length | P5, P8 | Playtest drop-off data |
| M2 Cold start | P5, P8 | Lobby start-rate in soft launch |
| M3 Automation | P2, P8 | Timing-variance telemetry |
| M4 Latency feel | P3 | Playtest at 150 to 300ms simulated lag |
| M5 Ghosting | P5, P8 | Channel permissions test |
| M6 Stale state | P1, P5 | Baseline assertions across 10 rounds |
| M7 Readiness | P5 | Slow-client test |
| M8 Shop/policy | P7, P8 | `robux-economy-review` verdict is not DO NOT SHIP |
| M9 Config | P1 | Unit tests on the worked examples |
| M10 Testing limits | P2, P8 | Simulator plus published-place playtest |
| M11 Reset/hazards | P5, P6 | Reset-at-table scenario |

## Research flags for the roadmap

- **Needs deeper phase research:** P2 (deck composition, wild-rule solvability, simulation tooling), P4 (spoon visibility model, `PathfindingService` agent config for reachability, StreamingEnabled implications), P7 (Roblox private-server pricing/rules for VIP; game pass versus developer product choice for large catalogs; current `ProcessReceipt` semantics), P8 (movement-sanity thresholds, Hyperion state).
- **Standard patterns, unlikely to need research:** P3 UI layout (apart from device testing), P6 map authoring beyond the linter, most of P1.
- **Do first (cheap, high payoff):** write the C9 spec, build the headless simulator (C3), build the remote gateway (C7), stand up ProfileStore with a test universe (C12).

## Sources

- Read: `/home/user/robloxspoons/.planning/PROJECT.md` (design, scoring, monetization rules; basis for C3, C4, C5, C8, C9, C10). HIGH for design-derived reasoning.
- Read: `roblox-ai-build` skill (Rojo/git source of truth, ProfileStore with session locking, server-authoritative multiplayer, mobile-first rules, asset sanitisation, phone-resolution review captures, usage-budget discipline) and `robux-economy-review` skill (per-item audit, shop-level audit, ship/no-ship gate). Note the economy skills' two-currency/accelerator pattern does not apply to this cosmetics-only game (M8).
- Roblox client-server boundary docs: https://create.roblox.com/docs/en-us/scripting/security/client-server-boundary.md (via search snippet, updated June 2026; validation of remote values and rate limiting not client-only). MEDIUM-HIGH. Direct fetch of `create.roblox.com` failed in this session, so official limits and enum semantics are unverified.
- Roblox Paid Random Items policy: https://create.roblox.com/docs/production/monetization/paid-random-items (via search summary; page last updated 2026-10-15; odds must be disclosed before spend; indirect purchases and luck boosters covered; regional restrictions). MEDIUM.
- ScreenGui `ScreenInsets` reference: https://create.roblox.com/docs/reference/engine/classes/ScreenGui (via search snippet; `CoreUISafeInsets`, `DeviceSafeInsets`, `TopbarSafeInsets`). MEDIUM-HIGH.
- ProfileService developer-products tutorial (receipt dedupe, wait for save, ~30 recent IDs): https://madstudioroblox.github.io/ProfileService/tutorial/developer_products. MEDIUM.
- DevForum on ProcessReceipt dedupe via a single `UpdateAsync`: https://devforum.roblox.com/t/2462225. LOW-MEDIUM (community).
- ProfileStore repository (session locking, Mock, successor to ProfileService): https://github.com/madstudioroblox/profilestore. MEDIUM. The ~80s lock-steal figure is a forum claim; LOW.
- DataStore request-budget formulas, BindToClose grace (about 30s), single-callback `ProcessReceipt`, Studio API-services writing to production, and the Studio multi-client cap: training knowledge, not re-verified this session. LOW-MEDIUM; verify during P1/P7 phase research.
- Touch target guidance (44pt Apple HIG / 48dp Material): general UI guidance, not Roblox-specific. MEDIUM.

---
*Pitfalls research for: Roblox real-time multiplayer party game (Spoons card scramble + hide-and-seek hunt)*
*Researched: 2026-11-02*
