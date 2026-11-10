# Phase 5: Hunt, Anti-ESP, Claim and Scoring - Research

**Researched:** 2026-11-10
**Domain:** server-authoritative hidden-object hunt on Roblox (interest management, atomic claim, pure scoring)
**Confidence:** MEDIUM-HIGH. Roblox API semantics are verified against create.roblox.com (pages last_updated 2026-11-10T00:40Z). Every number (glint range, hysteresis, plausibility factors, raycast cost) is a first-pass tuning value and says so.

<user_constraints>
## User Constraints (from 05-CONTEXT.md)

### Locked Decisions (DO NOT RE-OPEN)
- Scoring formulas: four-of-a-kind bonus 1000, -100 per place after. Find points = seconds remaining on the 5:00 cap x 10. Never finding a spoon = 0 find points, bonus kept. Seeker ceiling 4000. ROADMAP worked examples are TEST VECTORS.
- Hider denominator: fixed 300 s, unfound spoons count as the full 300, same timeline as find points.
- Time source: `os.clock()` floored to integer deciseconds is the scoring clock; `GetServerTimeNow()` is for client countdowns ONLY, never fed back. A third expression of the clock is how the two drift apart.
- D-01 `SpoonVisible` on the TRANSITION into visibility, `SpoonHidden` on the transition out. Never a standing list, never a periodic resend.
- D-02 Glint range 25 studs (tuning number for Phase 8).
- D-03 Line of sight = ONE `Workspace:Raycast` from the eye at `EYE_HEIGHT = 4.0` to the spoon, `RaycastParams.RespectCanCollide = true` set EXPLICITLY. Multi-ray rejected.
- D-04 Visibility evaluated at 5 Hz per seeker, not per frame.
- D-05 Pickup affordance is a `ProximityPrompt` CREATED BY THE CLIENT on its own local visual. Never a server instance. Server re-validates every claim.
- D-06 Race decided first-to-arrive in ONE non-yielding server handler, `claimedBy` set synchronously. Loser gets a silent no-op.
- D-07 Reject when claimant's server-known position exceeds `PICKUP_RANGE + PICKUP_MARGIN + walkSpeed * rtt`. Sampled about 4 Hz. On violation: log and escalate on repeats, do not act on a single sample. First-pass numbers, Phase 8 tunes.
- D-08 A rejected claim is SILENT.
- D-09 Spoons-remaining is a COUNT, published on change. Never positions, never "warmer".
- D-10 Player-to-player collisions disabled with ONE `PhysicsService` collision group, applied at round start for the whole round.
- D-11 Spectator = free-roaming camera, no character, bounded to the map, RECEIVES NO SPOON REVEALS.
- D-12 Anyone whose round is over can spectate.
- D-13 Scoring is a PURE module at `src/server/core/Scoring.luau`.
- D-14 Compute per event, publish once (scoreboard published once at round end).
- D-15 Completions arrive through the `onCompleted` sink at `src/server/Main.server.luau`.
- D-16 Round end fires IMMEDIATELY and SYNCHRONOUSLY on the claim that takes the final spoon, before any scoring publish; publish while the state still exists.
- D-17 (OPEN-OWNER) The hunt keeps the standard Roblox camera. No first-person hunt this phase.
- D-18 Glint is a fixed world effect with no purchasable variant and NO seam for one.

### Claude's Discretion
All of the above; most worth a second look: D-17, D-02, D-07.

### Deferred Ideas (OUT OF SCOPE)
First-person hunt camera; movement-threshold tuning on real latency (Phase 8); bot fill (Phase 8); multi-ray line of sight.
Also out of scope: hider placement UI, hide phase, match lifecycle, scoreboard/podium (Phase 6); cosmetics, spoon skins, shop (Phase 7).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HUNT-01 | Hidden positions only server-side, never Instance/attribute/value | `SpoonRegistry` plain tables in a pure core; reveal-only local visuals; leak gate modeled on privacy.spec; source scans on the adapter; manual replication audit M-24 |
| HUNT-02 | Position learned only within glint range with clear LoS | Pure `Visibility` sweep (distance prefilter, then injected LoS), 5 Hz, transition-only messages |
| HUNT-03 | Client prompt, server re-validates | Client-created ProximityPrompt -> `Claim` manifest intent -> server decides |
| HUNT-04 | Exactly one claimant | Single synchronous handler, `claimedBy` write, no yield; same-instant test |
| HUNT-05 | Seekers see spoons remaining | `SpoonsRemaining {count}` on change, audience all |
| HUNT-06 | Collisions disabled during hunt | PhysicsService group, assigned on CharacterAdded, pair toggled at round start/end |
| HUNT-07 | Finished player can spectate | `Spectate` owner message, client Scriptable camera clamped to map bounds, server-side no-reveal by construction |
| HUNT-08 | Implausible movement rejected | Pure `Plausibility` (reach check with rtt slack + 4 Hz speed sampler with strikes) |
| SCORE-01..05 | Bonus, find points, zero-find, hider score, round end | Pure `Scoring` + ledger; `RoundLifecycle` wired for the first time (see Finding F1) |
</phase_requirements>

## Summary

Hold every spoon as a plain Luau record (`{ id, x, y, z, claimedBy, foundDeci }`) inside a pure core (`HuntTable`) that is the only owner of hidden data. Nothing hidden is ever an Instance, attribute or Value. A 5 Hz adapter tick feeds the core each hunting seeker's eye position; the core pre-filters by squared distance (25 studs), calls an injected line-of-sight closure for survivors only (the adapter wraps ONE `Workspace:Raycast` with `RespectCanCollide = true`), diffs against that seeker's previous visible set, and emits `SpoonVisible` / `SpoonHidden` only for transitions. Worst case is 10 players, 8 spoons: at most about 9 hunters x 8 spoons = 72 pairs, 360 distance checks per second, and at most 360 raycasts per second (far fewer in practice, since the prefilter discards pairs beyond 25 studs). That cost is acceptable [ASSUMED: no Roblox doc gives a Raycast cost figure; M-28 measures it with the MicroProfiler].

The claim path is pinned by the debt re-check: the client's own prompt fires, the client sends `Claim { spoonId }` through the existing typed gateway (an ordinary rate-limited manifest kind), and one synchronous server function checks entitlement, range and plausibility, writes `claimedBy`, queues events, then publishes. The `spoonId` is an opaque per-round id, and the server additionally requires that the spoon is currently in the claimant's visible set, so a cheat client cannot claim by guessing ids. Scoring is a pure module and a pure ledger. Because the unit is the decisecond, **find points equal remaining deciseconds exactly** (10 points per second x 0.1 s per deci = 1 per deci), which removes a whole class of rounding bugs.

Two findings the CONTEXT did not know about change the plan (details in Findings F1 and F2): `RoundDriver:beginRound` is never called by anything and `RoundDriver`'s `onEnded` only prints, so **the 5:00 cap and the round-end path are not wired at all today**; and `Completed.rank` from the card table is the **card rank, not the finishing place**, so the place counter must be kept by the hunt core.

**Primary recommendation:** Build four pure cores (`Scoring`, `SpoonRegistry`+`Visibility`+`Plausibility` composed by `HuntTable`, and `HuntRouting`), one thin adapter `HuntService`, one new `Hunt` remote, one `Claim` manifest entry, and gate every adapter with a source scan plus a mutation of the real source. Wire `RoundDriver` for real in `Main.server.luau`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Spoon positions, `claimedBy`, ledger | Server pure core (`src/server/core`) | none | Rule 3: hidden data is server-side data only |
| Range + LoS evaluation | Server pure core (decision) | Server adapter (the Raycast closure) | Decision is testable headless; only the raycast touches Roblox |
| Reveal rendering (glint, spoon visual) | Browser/Client (local Part + Highlight/glow) | none | Built from a reveal, destroyed on hide; never replicated |
| Pickup affordance | Browser/Client (local ProximityPrompt) | none | D-05; the prompt is an affordance, not an authority |
| Claim decision | Server pure core | `HuntService` (input adapter) | Rule 6/7: one synchronous handler, server resolves everything |
| Plausibility / anti-teleport | Server pure core | adapter supplies position, walkSpeed, rtt | Pure math, injected inputs |
| Scoring | Server pure core (`Scoring`) | none | D-13: no Roblox API, runs in Lune |
| Spoons-remaining HUD | Server publishes count | Client renders | D-09 |
| Collision filtering | Server adapter (`PhysicsService`) | none | V-21: registration is server-script-only |
| Spectator camera | Browser/Client | Server decides who is a spectator | Camera is client-only; the no-reveal rule is a server membership test |
| Round clock / end | Server (`RoundLifecycle` via `RoundDriver`) | none | Rule 5 |

## Standard Stack

**No new dependencies.** Vanilla Roblox services and plain Luau only. No blocker identified. [VERIFIED: all APIs below present on create.roblox.com 2026-11-10]

### Core
| Component | Purpose | Notes |
|-----------|---------|-------|
| `Workspace:Raycast` (WorldRoot) + `RaycastParams` | One LoS ray per prefiltered seeker-spoon pair | `RespectCanCollide`, `CollisionGroup` verified (below) |
| `PhysicsService` | The one `Players` collision group | `RegisterCollisionGroup`, `CollisionGroupSetCollidable` (V-21 confirmed) |
| `ProximityPrompt` (client-created) | Pickup affordance on the local visual | Works parented to a BasePart/Attachment/Model in Workspace; client events fire in LocalScripts |
| `Player:GetNetworkPing()` | rtt for plausibility slack | Returns round-trip latency in seconds, server callable, thread-safe |
| `RunService.Heartbeat` accumulator | 5 Hz visibility sweep, 4 Hz movement sample | Same one-accumulator pattern as CardService |
| `RoundLifecycle` / `RoundDriver` | 5:00 cap, single-fire end | Exists; needs wiring (F1) |

### New repo modules (all hand-written, none are libraries)
| Module | Zone | Role |
|--------|------|------|
| `src/server/core/Scoring.luau` | pure, FOUND-05 guarded root by name | bonus, find points, hider score, ledger |
| `src/server/core/SpoonRegistry.luau` | pure | autoFill from default spots, claim, remaining |
| `src/server/core/Visibility.luau` | pure | distance prefilter, injected LoS, per-seeker transition diff |
| `src/server/core/Plausibility.luau` | pure | reach check with rtt slack; 4 Hz speed sampler with strikes |
| `src/server/core/HuntRouting.luau` | pure | frozen audience table + `makePublisher` (twin of CardRouting) |
| `src/server/core/HuntTable.luau` | pure | composes the above; owns hunters set, place counter, spectators; effects injected |
| `src/server/services/HuntService.luau` | Roblox adapter | Heartbeat, positions, raycast closure, collision group, intent entry |
| `src/shared/Config/Hunt.luau` | shared config | `GLINT_RANGE` etc. (see Open Question O1) |
| `src/client/ui/HuntClient.luau` (+ small view modules) | client | reveal -> local visual + prompt; spectate camera; remaining HUD |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| One `Hunt` remote | Reuse the `Card` remote | Card remote's audience vocabulary is `owner`/`seated`; hunt needs `hunters`/`all`. A second remote costs no ordering guarantee (V-12, noted in NetServer.luau header) |
| `PhysicsService` | `Workspace:RegisterCollisionGroup` | Both documented; the current Roblox collisions guide uses the Workspace form. D-10 and the debt re-check name PhysicsService, so keep it; the Workspace form is the fallback if PhysicsService ever reads as deprecated |
| Exclude-list for characters in the ray | `RaycastParams.CollisionGroup = "Players"` | See Pattern 2; the group form needs no per-tick list |

**Installation:** none.

**Version verification:** not applicable (no packages). Tooling note: `lune`, `selene`, `stylua`, `luau-lsp`, `rojo` are NOT installed in this research sandbox (`which` returned nothing), so no spec could be run here. CI is the only place the suite runs.

## Architecture Patterns

### System Architecture Diagram

```
 card phase                               HUNT (concurrent with card scramble, one 5:00 clock)
 ----------                               ----------------------------------------------------
 CardTable --Completed(seat,playerId,cardRank)--> Main.onCompleted  (D-15)
                                                      |
                                                      v
                                           HuntService:onSeekerCompleted(playerId)
                                                      |  place = ++placeCounter   (NOT cardRank)
                                                      v
                                      HuntTable: hunters[playerId]=true, ledger:recordBonus(place)
                                                      |
   Heartbeat (acc, 5 Hz) -> HuntService.sweep         |
        for each hunter: eye = root + (EYE-REACH)     |
        |                                             v
        +----------------> Visibility.step(hunters, unclaimed spoons, visibleSets)
                              1. dist^2 <= GLINT^2 ?  --no--> (not visible)
                              2. yes -> los(eye, spoon) = ONE Raycast, RespectCanCollide=true
                              3. diff vs previous visible set (with hysteresis)
                              -> transitions only
                                                      |
                             HuntRouting.publisher    v
          toPlayer(u, "SpoonVisible", {id,x,y,z}) / toPlayer(u, "SpoonHidden", {id})
                                                      |  NetServer (ONLY FireClient site, R4) -> Hunt remote
                                                      v
   CLIENT HuntClient: SpoonVisible -> local Part + glint + ProximityPrompt (MaxActivationDistance=PICKUP_RANGE)
                      SpoonHidden  -> Destroy both
                      prompt.Triggered -> ClientNet.send("Claim", {spoonId})
                                                      |
   Gateway (phase=Round, rate bucket, exactKeys) ---> Main handlers.Claim ---> HuntService:onClaim
                                                      v
   HuntTable.claim(userId, spoonId, nowDeci)   -- ONE synchronous function, no yield
       isOpen? -> hunter? -> spoon exists & unclaimed? -> in my visible set? -> position known?
       -> Plausibility.reach(rtt) -> (any fail: silent no-op, strike log)
       -> MUTATE: spoon.claimedBy=userId; foundDeci=now; hunter.done=true; remaining -= 1; ledger:recordFind
       -> queue events; publish AFTER mutation:
            ClaimOk -> claimer; Spectate -> claimer; SpoonHidden -> others who saw it; SpoonsRemaining -> all
       -> if remaining == 0: lifecycle:endRound(id,"AllSpoonsClaimed")   (D-16, synchronous)
                                                      |
   RoundLifecycle.onEnded (also fires on 5:00 Timeout) -> Main sink
        HuntTable.finish(): Scoring.finalize(ledger) -> publish "HuntEnd"+scoreboard to hunters+spectators+all
        BEFORE clearing hunters/visible sets  -> then CardService.endRound() -> collisions back on
```

### Recommended Project Structure
```
src/server/core/
  Scoring.luau  SpoonRegistry.luau  Visibility.luau  Plausibility.luau
  HuntRouting.luau  HuntTable.luau                (all pure; deps injected)
src/server/services/HuntService.luau              (adapter; gets a source-scan gate)
src/shared/Config/Hunt.luau                       (numbers, shared so the client reads PICKUP/GLINT)
src/shared/Net/Manifest.luau                      (+ Claim)
src/shared/Config/RateLimits.luau                 (+ Claim bucket)
src/client/ui/HuntClient.luau                     (reveal views, prompt, spectate camera, HUD)
tests/hunt/*.spec.luau                            (scoring, visibility, claim, plausibility, privacy, round_end, wiring)
```

### Pattern 1: Pure core, injected effects (the CardTable shape)
`HuntTable.new(deps)` takes `publisher`, `nowDeci`, `positionOf(userId): Vec3?`, `walkSpeedOf(userId): number`, `rttOf(userId): number`, `lineOfSight(from, to): boolean`, `endRound(reason)`, `onTelemetry`. Nothing in the file names a Roblox API. The adapter supplies those six closures and nothing else. This is exactly what let `CardSeatHold` be fully covered in its core; the lesson is that the adapter closures need their own gate (Pattern 6).

### Pattern 2: LoS ray that ignores characters with no per-tick list
`RaycastParams.CollisionGroup`: "Parts in collision groups that are set to **not** collide with this group are ignored" [CITED: RaycastParams datatype page, last_updated 2026-11-10]. If the character group `Players` is non-collidable with itself (D-10), a ray cast with `CollisionGroup = "Players"` ignores every character part with no `ExcludeInstances` rebuild. Without this, the seeker's own HumanoidRootPart (CanCollide true) would be the first thing every ray hits, and with `RespectCanCollide = true` other players' bodies would "block sight" and make spoons flicker in and out as players walk past. Do this in the adapter:

```lua
-- Source: RaycastParams page (create.roblox.com/docs/reference/engine/datatypes/RaycastParams.md)
local params = RaycastParams.new()
params.RespectCanCollide = true          -- D-03: EXPLICIT; the default is undocumented (V-18)
params.CollisionGroup = PLAYERS_GROUP    -- ignores parts in groups that do not collide with Players
params.IgnoreWater = true
local function lineOfSight(from: Vector3, to: Vector3): boolean
    local delta = to - from
    local shortened = delta - delta.Unit * LOS_END_TRIM   -- stop just short of the spoon's own surface
    return Workspace:Raycast(from, shortened, params) == nil
end
```
Reuse ONE `RaycastParams` (the datatype page: "you can change all of the members ... allowing you to reuse the same object"). The collision toggle only needs to be false while the round runs, and the sweep only runs while the round runs, so the two cannot disagree.

### Pattern 3: Visibility with hysteresis (transition-only output)
`Visibility.step(state, hunters, spoons, dt)` returns `{ shown: {{userId, spoonId}}, hidden: {{userId, spoonId}} }` and mutates `state.visible[userId][spoonId]`. Enter at `dist <= GLINT_RANGE` AND `los`; leave when `dist > GLINT_RANGE + GLINT_HYSTERESIS` OR LoS has failed on `LOS_LOSS_TICKS` consecutive ticks. Hysteresis keeps a player standing on the range edge or at a corner from producing a show/hide per tick (which would be a periodic resend by another name, against D-01). Starting values `GLINT_HYSTERESIS = 3` studs, `LOS_LOSS_TICKS = 2` [ASSUMED: feel numbers, Phase 8]. The 25-stud enter radius is unchanged.

### Pattern 4: Atomic claim (rule 6)
```lua
-- HuntTable.claim: no task.wait, no remote call, no Instance access, no callbacks that can yield.
local function claim(userId: number, spoonId: number)
    local nowDeci = deps.nowDeci()                       -- ARRIVAL time, read once, SCORE-02
    if not lifecycleOpen() then return end               -- isOpen may END the round (Timeout) re-entrantly; return after
    local hunter = hunters[userId];  if hunter == nil or hunter.spoonId ~= nil then return end
    local spoon = registry.byId[spoonId]; if spoon == nil or spoon.claimedBy ~= nil then return end
    if not (visible[userId] and visible[userId][spoonId]) then return end   -- entitlement: cannot claim what you were never shown
    local at = deps.positionOf(userId); if at == nil then return end        -- NB: not named "pos" (guard R3, see Pitfall 6)
    if not Plausibility.reach(at, spoon, deps.walkSpeedOf(userId), clampRtt(deps.rttOf(userId)), cfg) then
        strike(userId); return                                              -- silent (D-08)
    end
    -- ---- mutation: synchronous, one block ----
    spoon.claimedBy = userId;  spoon.foundDeci = nowDeci
    hunter.spoonId = spoonId
    remaining -= 1
    ledger:recordFind(userId, spoonId, nowDeci)
    -- ---- publish after mutation ----
    publishClaimEvents(userId, spoonId)
    if remaining == 0 then deps.endRound("AllSpoonsClaimed") end
end
```
Two claims "in the same instant" are two remote events delivered to two handler invocations that Roblox runs one after the other on the server; because the function never yields, the second sees `claimedBy ~= nil`. The spec drives two `claim` calls back to back with the same `nowDeci` and asserts exactly one winner, one ledger row, `remaining` decremented once, and one `ClaimOk`. Its mutation is a variant where the check and the write are separated by an injected yielding hook (see Validation Architecture).

`claimedBy` is a **userId** (number), not a seat index: a seat can be removed (rule 8) but the player is the identity scoring and the hider's spoon-survival record need. `nil` means unfound.

### Pattern 5: Round end publishes before it clears (D-16, the Phase 4 precedent)
Phase 4's bug: `RoundEnd` was published after `table.clear(seated)`, and `toSeated` reads `seated`, so it reached nobody. Apply the same shape: `HuntTable.finish(reason)` (a) builds the scoreboard from the ledger, (b) reads the audience (hunters + spectators + everyone) from live state, (c) publishes `HuntEnd`, (d) only then clears hunters, visible sets, spectators. Add the twin of `tests/card/round_end.spec`: a publisher whose audience is read from live state, with a mutant that clears first and must deliver nothing. `RoundLifecycle` already marks the round ended BEFORE invoking `onEnded`, so a re-entrant claim during finish sees a closed round.

### Pattern 6: Adapter gates (the 2026-11-10 lesson)
Lune cannot load a file that names `game:GetService`, so the adapters are gated by comment-stripped source scans over `scripts/ci/lex.stripComments`, exactly as `tests/card/service_wiring.spec.luau` does (clean control on real source, non-vacuity size, no-defect identity twin, mutants that are the REAL source edited in memory and must be seen by the SAME problems function). Required scans, one spec file `tests/hunt/service_wiring.spec.luau`:
- `HuntService` contains `RespectCanCollide = true`, `Raycast(`, and `CollisionGroup =` in the same function that builds the params; mutant: delete the `RespectCanCollide` line.
- `HuntService` has NO `Instance.new`, no `SetAttribute`, no `ProximityPrompt`, no `ObjectValue`/`Value` construction (HUNT-01 on the adapter). `src/server` contains no `ProximityPrompt` anywhere.
- `HuntService` has no `os.clock`/`GetServerTimeNow` (deci_lock already pins `os.clock` to named files; extend its allow-list test by confirming it still passes, which is itself a gate that a third clock was not added). It takes `CardService.nowDeci`.
- The `Heartbeat` callback body contains no `task.wait`, `:Wait(`, `WaitForChild`, `InvokeServer` (rule 6 on the adapter).
- Positions flow only through the publisher: `HuntService` never calls `FireClient` (guard R4 already enforces; scan confirms).
- Client: `HuntClient` creates `ProximityPrompt` only inside the `SpoonVisible` handler and calls `:Destroy()` in the `SpoonHidden` handler; its receive handler contains no yield (V-12/Pitfall 11).
- `PhysicsService:CollisionGroupSetCollidable` appears in `HuntService`; registration happens at boot, assignment on `CharacterAdded` including `DescendantAdded`.

### Anti-Patterns to Avoid
- **A server-side ProximityPrompt, Part, BillboardGui, Attachment or Value at a spoon position.** HUNT-01 through the floor (D-05, ARCHITECTURE.md section 4).
- **A standing `Spoons` list or periodic resend.** A map (D-01).
- **Raycasting every frame or every spoon.** Prefilter by squared distance first.
- **Using `Completed.rank` as the finishing place.** It is the card rank (Types.luau: "Rank = 1..config.ranks for naturals").
- **Feeding `GetServerTimeNow()` into `foundAt`.** ARCHITECTURE.md section 4 step 3 says `foundAt = GetServerTimeNow()`; that conflicts with the settled two-clock rule. `PROJECT.md` and CONTEXT win: use `nowDeci()`.
- **Writing `foundDeci`/`claimedBy` after a publish call.** Mutate, then publish.
- **Different messages for different reject reasons.** Silent means silent, including no `ClaimRejected` kind.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Audience routing | Ad hoc `if` chains in the adapter | `HuntRouting.makePublisher` over frozen `AUDIENCE` data (CardRouting twin) | The privacy decision must be enumerable and testable; guard R4 confines sends to NetServer |
| Intent validation | Manual payload checks in the handler | `Validate.exactKeys({ spoonId = Validate.integer{...} })` in the Manifest | Structural rule 7: no `spoon`, `pos`, `target` key can exist |
| Rate limiting | A claim cooldown timer | A `Claim` entry in `RateLimits.byIntent` | The per-(user,intent) `Bucket` is already there |
| Round clock and single-fire end | Own timer | `RoundLifecycle` via `RoundDriver` | Already proven (SCORE-06) |
| Reject log spam | Own throttle | `RejectThrottle` / the plausibility log goes through the same throttle shape | D-22 precedent |
| Collision between players | Per-part CanCollide toggling or Touched handlers | One collision group (D-10) | Per-phase toggling is the doorway-wedge failure mode |
| Rounding of the hider score | Float math with `/ 3000 * 4000` | Integer deci arithmetic with one stated rounding rule | Float drift breaks exact equality tests |
| Opaque ids | Index into the spot list | Ids from a shuffle of 1..N | The id must carry no placement information |
| Sight model | A second LoS implementation in Lua geometry | The single `Workspace:Raycast` (D-03); `Obb.segmentHits` stays the validator's | Two models for the same question is the CI/live divergence V-18 warned about |

**Key insight:** every piece of this phase is either "decide in a pure function" or "ask the platform one question". Anything that needs both belongs in the adapter's injected closure, and the closure is what the source-scan gate covers.

## Runtime State Inventory

Not a rename/refactor/migration phase. Omitted.

## Findings that change the plan

### F1. The round is not wired: `beginRound` is never called and `onEnded` only prints
`grep` over `src/`: `RoundDriver.beginRound` has no caller; `Main.server.luau` constructs `RoundDriver.new(function(roundId, reason) print(...) end)` and never starts a round; `CardService.endRound` has no caller either (only `destroy`). So today there is no 5:00 cap, no `AllSpoonsClaimed` end, and the card stub's round never ends. SCORE-05 and success criterion 4 need all of it. **Wire in `Main.server.luau`:** after `cardService:startRound()` returns true, `HuntService:beginHunt()` calls `driver.beginRound()` and builds the `HuntTable` for that `roundId` with `lifecycle` injected; `onEnded(roundId, reason)` calls `huntService:finish(roundId, reason)` and THEN `cardService:endRound()`. The `driver` is constructed before `huntService` in Main today, so use the same upvalue-assigned-later pattern Main already uses for `cardService`. Note also `roundStarted` in Main is never reset, so a session runs one round; that is Phase 6's, but the plan must not "fix" it silently.

### F2. `Completed.rank` is the CARD rank, not the place
`CardTable.Deps.onCompleted(seat, playerId, rank)` passes `event.rank`, and `Types.Rank` is the card rank. Place (SCORE-01) is the order completions arrive. `HuntTable` increments its own `placeCounter` in the sink. A spec feeds three completions with card ranks `{7, 2, 5}` and asserts places 1, 2, 3 and bonuses 1000, 900, 800 (a mutant using the card rank must fail).

### F3. `config_lock.spec` pins exactly ten placement constants
`tests/placement/config_lock.spec.luau` line 38: `t.equal(count, 10, "an eleventh constant must be decided, not slipped in")`. CONTEXT says glint range "belongs beside" `PICKUP_RANGE`. Putting `GLINT_RANGE` into `Placement.luau` would fail that spec. Recommendation: new `src/shared/Config/Hunt.luau` (same directory = beside), with its own lock spec, including the cross-file invariant `GLINT_RANGE > PICKUP_RANGE + PICKUP_MARGIN` (loaded by relative path in the spec, which scripts and tests may do). The alternative (add an 11th constant to Placement and bump the count) is legitimate but touches a spec whose message forbids slipping it in. See O1.

### F4. Adding `Claim` changes a hard-coded count in `tests/net/manifest.spec.luau`
Line 202: `t.equal(seen, 14, "2 intents x 7 forbidden keys must all have run")`. With Claim it is 3 x 7 = 21, and the `realValidators()` helper and the loose-validator mutants (lines 230-248) enumerate Draw and Pass explicitly. The plan must update them deliberately. Note `Claim` carries `spoonId`, which is not in `FORBIDDEN_KEYS = {seat,to,target,index,hand,slot,userId}`; add `pos`, `position`, `x`, `y`, `z` to the forbidden list so the gate also proves the client cannot send a position (a client-stated position is exactly what the server must never trust).

### F5. Root-point versus eye-point geometry (needs a human check)
Placement.luau: "the server knows only the HumanoidRootPart position and adds these offsets to it." But the validator models the root at `REACH_HEIGHT = 2.5` above the floor and the eye at `EYE_HEIGHT = 4.0` above the floor (`cellH + eyeHeight`, `cellH + reachHeight`). A real R15 root sits roughly 3 studs above the floor [ASSUMED: HipHeight page text was not fully read; V-19 is MEDIUM]. Adding `EYE_HEIGHT` (4.0) to the root position would put the eye about 7 above the floor, which sees over every 6.5 ledge the validator treats as occluding. Recommendation: `eye = root + Vector3.new(0, EYE_HEIGHT - REACH_HEIGHT, 0)` (= root + 1.5), a pure `Visibility.eyeOf(root, cfg)`. Because `REACH_HEIGHT` is already modelled below a real root (reject-biased), the real eye lands about 0.5 above the modelled one, a small error in the permissive direction for LoS; M-29 measures it. See O2.

## Common Pitfalls

### Pitfall 1: The ray hits a player, not a wall
**What goes wrong:** with `RespectCanCollide = true`, characters (CanCollide true) block sight; the seeker's own root is hit at distance 0, so no spoon is ever visible, or spoons flicker as players cross the line.
**Why:** the default group collides with everything.
**How to avoid:** Pattern 2 (`CollisionGroup = "Players"`, group non-collidable with itself). Test live (M-28). Fallback: rebuild an `ExcludeInstances` list of character models each tick (10 entries).
**Warning signs:** zero reveals in a 2-player test; reveals that vanish when a teammate stands between.

### Pitfall 2: Registering collision groups at runtime is costly and one-shot
`WorldRoot:RegisterCollisionGroup` "has a slight performance overhead based on the number of BaseParts" and the docs recommend registering at edit time [CITED: WorldRoot page]. Register once at server boot BEFORE the map mounts; re-registering an existing name is untested here, so guard with `pcall`. Budget: the engine supports 32 groups (V-21); this phase spends exactly one. The in-repo place cannot declare groups via Rojo as far as this research found [ASSUMED], so boot-time registration is the repo-controlled route.

### Pitfall 3: Characters spawn and respawn with new parts and accessories
Assigning `CollisionGroup` once on `CharacterAdded` misses accessories added later. The official sample connects `character.DescendantAdded` as well [CITED: workspace/collisions.md "Disable character collisions"]. Do both, for characters that already exist at boot (the pattern CardService uses for `watchCharacter`). A character with no group collides: the failure is silent.

### Pitfall 4: Stale reveals after the claim
When a spoon is claimed, every other hunter who had it visible must receive `SpoonHidden`; otherwise their client keeps a prompt on a taken spoon (harmless to score, since the server no-ops, but it leaks that the spoon existed there and invites repeated probing). Publish `SpoonHidden` to exactly the set `visibleTo[spoonId]`.

### Pitfall 5: `isOpen` can end the round inside your handler
`RoundLifecycle.isOpen` calls `endRound(..., "Timeout")` when the deadline has passed, and `onEnded` then runs finalisation synchronously. A claim handler that calls `isOpen` and then continues with stale locals can score a claim after the round ended. Treat `isOpen == false` as "return immediately"; the deadline is EXCLUSIVE, so a claim on the deadline decisecond scores nothing. Spec: claim at `deadline - 1` scores 1 deci = 1 point; claim at `deadline` scores nothing.

### Pitfall 6: Guard R3 bans the substring `os.` in pure zones
Per `zones.luau` comments, `pos.X` and `anchorPos.Y` match the `os.` needle because R3 scans comment-stripped text including string literals. In every new core file, name positions `at`, `p`, `centre`, `spot`, not `pos`. The word "pos" in a comment is fine (comments are stripped) but `pos.x` in code fails the build. `SpoonPlacement.luau` documents the same convention. Also avoid `coroutine`, `_G[`.

### Pitfall 7: Rate limit on `Claim` too tight or too loose
A rejected-by-bucket claim never reaches the core (and, unlike Draw/Pass, there is nothing to resync). A holding player mashing the prompt is not an attack. Starting value `Claim = { burst = 4, refillPerSecond = 2 }` [ASSUMED, V-34 LOW]. Bucket exhaustion must not reveal anything: the gateway already drops silently and `RejectThrottle` rate-limits the log.

### Pitfall 8: Spectator receives reveals via a "finished means inherits" shortcut
D-11. Enforce structurally: `Visibility.step` iterates `hunters` only, and `hunters[userId]` is removed (or marked `done`) on claim, removal or round end. A spec places a spectator at the exact position of a hunter who sees a spoon and asserts zero `SpoonVisible` to that user. Mutation: iterate "all players with a root".

### Pitfall 9: Reveal sent for a seeker whose character is missing or dead
`positionOf` returns nil (no character, no root, health 0): treat as "sees nothing" and emit `SpoonHidden` for their current set. Never fall back to the last known position.

### Pitfall 10: Hysteresis defeats the "no periodic resend" test unless asserted correctly
Test both directions: a stationary seeker over 100 ticks gets exactly one `SpoonVisible` per visible spoon and zero others; a seeker jittering +-1 stud across the 25-stud edge gets at most one show and at most one hide. Mutant: no hysteresis must exceed the cap.

### Pitfall 11: `claimedBy` race on removal
A hunter who disconnects after the mutation but before publish is harmless; one who disconnects BEFORE claiming is removed from `hunters` and `visible` (`HuntTable.removeHunter`, reachable from `Main`'s `PlayerRemoving`), and their already-claimed spoon stays claimed (rule 8's spirit: nothing is destroyed). Their ledger rows stay; Phase 6 decides what leavers are paid.

### Pitfall 12: Hider-score rounding drift
`score = 4000 * (sum of elapsedDeci_i) / (3000 * n)` with unfound `elapsedDeci = 3000`. Do it in integers: `floor((8000 * sum + 3000 * n) / (6000 * n))` (round half up). State the rule in the file header and test boundary cases: all unfound = 4000; all found at deci 0 = 0; one of two found at 1500 deci = 3000.

## Code Examples

### Scoring (pure, exact ROADMAP vectors)
```lua
--!strict
-- Scoring.luau (PURE ZONE, FOUND-05 guarded root). Config arrives as a parameter (guard R6).
export type Config = {
    BONUS_FIRST: number,        -- 1000
    BONUS_STEP: number,         -- 100
    CAP_DECI: number,           -- 3000  (Round.ROUND_CAP_SECONDS * DECISECONDS_PER_SECOND)
    HIDER_DENOM_DECI: number,   -- 3000  (a SEPARATE locked constant, equal today; Open Question 7)
    HIDER_MAX: number,          -- 4000
    POINTS_PER_DECI: number,    -- 1     (10 points/second / 10 deci/second)
}
local Scoring = {}
function Scoring.bonus(cfg: Config, place: number): number
    return math.max(0, cfg.BONUS_FIRST - cfg.BONUS_STEP * (place - 1))
end
function Scoring.findPoints(cfg: Config, deadlineDeci: number, arrivalDeci: number): number
    return math.max(0, deadlineDeci - arrivalDeci) * cfg.POINTS_PER_DECI   -- exclusive deadline: arrival == deadline -> 0
end
-- Vectors (tests/hunt/scoring.spec.luau):
--   findPoints at 2:40 remaining (1600 deci)                      == 1600
--   bonus(3) + findPoints(600 deci)                               == 800 + 600 == 1400
--   a seeker with a ledger bonus and no find row                  == bonus only, find == 0
--   bonus(1) + findPoints(3000 deci)                              == 4000  (ceiling)
return Scoring
```
Derived invariants worth their own tests: `findPoints` never exceeds `CAP_DECI * POINTS_PER_DECI`; `bonus` is non-increasing and never negative (place 11 = 0, 10 seekers max so place 10 = 100); the ceiling `bonus(1) + 3000 == 4000` is asserted as an equation over the config, not just a literal.

`Scoring.newLedger()` is append-only (ARCHITECTURE.md): rows `{kind="Bonus", userId, place}`, `{kind="Find", userId, spoonId, arrivalDeci}`; `ledger:finalize(cfg, deadlineDeci, spoonIds, hiderId)` returns `{ [userId] = { bonus, find, total }, hider = { score } }`. The scoreboard shows bonus and find separately (SCORE-07 is Phase 6 but the data shape is set here).

### Reveal on the client (local-only)
```lua
-- HuntClient.luau (synchronous handler; no yields, V-12)
local function onSpoonVisible(p: { id: number, x: number, y: number, z: number })
    local part = Instance.new("Part")            -- LOCAL: created by the client, never replicated to the server
    part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
    part.Position = Vector3.new(p.x, p.y, p.z)
    part.Parent = localFolder                    -- a folder the client created under Workspace
    local prompt = Instance.new("ProximityPrompt")
    prompt.MaxActivationDistance = Placement.PICKUP_RANGE
    prompt.RequiresLineOfSight = false           -- the server is the authority; do not double-gate on the camera
    prompt.ActionText = "Take"
    prompt.Parent = part
    prompt.Triggered:Connect(function() ClientNet.send("Claim", { spoonId = p.id }) end)
    views[p.id] = part
end
local function onSpoonHidden(p: { id: number })
    local part = views[p.id]; if part then part:Destroy(); views[p.id] = nil end
end
```
[CITED: ProximityPrompt page: works parented to a BasePart in the workspace; client events fire in LocalScripts. A client-created prompt's `Triggered` exists only on that client (debt re-check V-22).] Whether a client-created instance's prompt UI renders and fires on touch devices is [ASSUMED] and is manual check M-25.

### Visibility core
```lua
function Visibility.step(state, hunters, spoons, eyeOf, los, cfg)
    local shown, hidden = {}, {}
    local enter2 = cfg.GLINT_RANGE * cfg.GLINT_RANGE
    local leave = cfg.GLINT_RANGE + cfg.GLINT_HYSTERESIS; local leave2 = leave * leave
    for userId in hunters do
        local eye = eyeOf(userId)                           -- nil -> sees nothing (Pitfall 9)
        local seen = state.visible[userId]
        for _, s in spoons do                               -- unclaimed spoons only
            local was = seen[s.id] ~= nil
            local d2 = distSq(eye, s)
            if not was then
                if eye and d2 <= enter2 and los(eye, s) then seen[s.id] = 0; push(shown, userId, s) end
            else
                local blocked = (eye == nil) or d2 > leave2 or not los(eye, s)
                ... -- count consecutive LoS failures; hide at LOS_LOSS_TICKS or on range loss
            end
        end
    end
    return shown, hidden
end
```
Sketch only; the planner should write the exact function with the injected `los` counted by the spec (non-vacuity: the spec asserts `los` was NOT called for any pair beyond 25 studs, which is the prefilter's proof).

### Collision group adapter
```lua
-- Source: Roblox collisions guide, "Disable character collisions" (workspace/collisions.md); PhysicsService page
local PhysicsService = game:GetService("PhysicsService")
local GROUP = "Players"
pcall(function() PhysicsService:RegisterCollisionGroup(GROUP) end)    -- once, at boot, before the map mounts
local function applyTo(character: Model)
    local function assign(d: Instance) if d:IsA("BasePart") then d.CollisionGroup = GROUP end end
    for _, d in character:GetDescendants() do assign(d) end
    character.DescendantAdded:Connect(assign)
end
-- round start / round end (D-10: one group; the pair is the whole HUNT-06 switch)
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, true)
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| `Player:LoadCharacter` | `LoadCharacterAsync` (LoadCharacter marked deprecated, page 2026-11-10) | Not used in Phase 5; flag for Phase 6's character handling |
| `RaycastParams.FilterDescendantsInstances` + `FilterType` | `ExcludeInstances` / `IncludeInstances` documented first on the RaycastParams page, FilterDescendantsInstances still listed | Prefer the collision-group route for characters; if an exclude list is ever needed use `ExcludeInstances` [CITED: RaycastParams page]. `ExcludeInstances = nil` vs `{}` semantics: `IncludeInstances = {}` includes NOTHING |
| `PhysicsService` only | `WorldRoot:RegisterCollisionGroup` / `CollisionGroupSetCollidable` also exist and the current guide uses `workspace:` | Either works; D-10 names PhysicsService |
| `Workspace:FindPartOnRay` | `Raycast` | V-18 historical, no action |

## Verified / Assumed / Needs-a-human, per research question

### 1. Spoon visibility (D-01..D-04)
- VERIFIED: `RaycastParams.RespectCanCollide` behaviour (uses CanCollide in favour of CanQuery); default NOT stated on the page (matches 05-DEBT-RECHECK V-18). `CollisionGroup` semantics (ignores parts in groups not colliding with the given group; default group "Default" if omitted). Reusing one RaycastParams is sanctioned. `Raycast(origin, direction, params)`: the direction magnitude is the ray length, so the direction must be the full vector to the target. Pages: RaycastParams datatype and WorldRoot class, last_updated 2026-11-10T00:40Z.
- VERIFIED: data model fact that a client-created Instance is client-local (standard; also the premise of V-22).
- ASSUMED: ~360 raycasts/s worst case is cheap; per-ray cost not documented. ASSUMED: ending the ray 0.05 studs short of the spoon avoids self-grazing a surface (validator uses an inflate of `GEOM_EPSILON` the other way, graze = blocked; trims differ by design, both bias is tiny).
- HUMAN: M-28 (validated graybox spots are visible from open sightlines and hidden behind walls in live play; compares validator vs runtime), M-29 (eye offset), MicroProfiler look at the 5 Hz tick with 10 clients.

### 2. Claim (D-05..D-08)
- VERIFIED: `Player:GetNetworkPing()` returns round-trip latency in seconds, server-callable, thread-safe [CITED: Player page]. ProximityPrompt properties used (`MaxActivationDistance`, `RequiresLineOfSight` default behaviour: camera-to-object clear path, parent excluded) [CITED: ProximityPrompt page].
- ASSUMED: `GetNetworkPing()` is a smoothed enough estimate; clamp it to `[0, RTT_CLAMP = 0.5]` s so neither a spoofed slow link nor a spike widens the slack unboundedly (the ping is server-measured, so a client cannot forge it, but a deliberately laggy client can raise it; the clamp bounds that, and `walkSpeed` is read from the server humanoid, never the payload).
- ASSUMED: server-known root position lags (V-23, left as a measurement row). First-pass values live in `Config/Hunt.luau`: `SPEED_SLACK = 1.5` (horizontal speed up to 1.5 x WalkSpeed per 4 Hz sample, vertical ignored so falls and jumps do not trip it), `STRIKES_TO_ESCALATE = 3`. Escalation in Phase 5 is log-only (`warn` through RejectThrottle and a telemetry event), matching D-07 "log and escalate on repeats" without kicking anybody; Phase 8 decides the action.
- HUMAN: M-25 (client-created prompt appears and fires on phone and PC), M-26 (two clients, same spoon, one winner, loser silent).

### 3. Scoring (D-13..D-16)
- VERIFIED by reading source: `RoundLifecycle` ends exactly once, marks ended before `onEnded`, deadline exclusive (F1, Pitfall 5). `CardService.nowDeci` is the exported clock.
- VERIFIED: find points = remaining deci exactly; ceiling 4000 = 1000 + 3000.
- ASSUMED: rounding half up for the hider score (owner never specified; recorded in the header, easy to change). The ROADMAP gives no hider vector other than the ceiling, so the plan adds derived vectors (Pitfall 12) and labels them derived.

### 4. Spectating and collisions (D-10..D-12)
- VERIFIED: PhysicsService/WorldRoot API, 32-group limit and server-only registration (05-DEBT-RECHECK V-21), `BasePart.CollisionGroup` is a string property (max 100 characters), non-replicated property that the engine replicates through a private property internally [CITED: BasePart page]. Official character-collision sample matches Pattern 3's assign-on-descendant approach.
- ASSUMED: "no character" for a spectator. What `Character:Destroy()` does under `CharacterAutoLoads = true` (immediate respawn or not) is NOT verified, and `LoadCharacter` is deprecated, so Phase 5 should not delete characters. See O3.
- HUMAN: M-27 (finished player gets a free camera, cannot leave the map bounds, sees no spoons even standing where a hunter sees one).

### 5. Cost
Pairs: hunters x unclaimed spoons. 10 players = 1 hider + 9 seekers, 8 spoons, so at most 72 pairs per tick, 360 pair-checks per second at 5 Hz. Distance prefilter first (`dx*dx + dy*dy + dz*dz <= GLINT^2`, no sqrt), then one ray only for in-range, not-already-confirmed pairs. A seeker already seeing a spoon still pays one ray per tick to detect loss; a typical map (21 spots spread over a graybox) will have a fraction of the 72 pairs in 25 studs. Compare D-04: per-frame is 4800/s. [ASSUMED: acceptable; M-28 measures.] Not recommended: spatial hashing, LoS caching across ticks, multi-ray. An optional cheap optimisation if the profile asks: skip the ray for pairs where the seeker has not moved more than 0.25 studs since the last confirmed result.

## Privacy gate design (HUNT-01, modeled on `tests/card/privacy.spec`)

`tests/hunt/privacy.spec.luau` drives the REAL `HuntTable` against a recording publisher (`tests/harness/HuntRecording.luau`, twin of `RecordingPublisher`, with the same `leak` switch):
1. **No-leak oracle.** Collect every payload from every publisher call. Recursively flatten numbers. For each unclaimed spoon and each user, assert no triple `(x,y,z)` equal to that spoon's position appears in a message to that user unless that user is entitled (within 25 + 0 studs at the tick, with LoS). Non-vacuity: assert the entitled path DID send at least N reveals, and that the oracle saw at least one candidate triple (a vacuous "nothing sent" must fail).
2. **Shape gate.** Allowed kinds are the frozen `HuntRouting` list: `SpoonVisible {id,x,y,z}` (owner), `SpoonHidden {id}` (owner), `SpoonsRemaining {count}` (all), `HuntStart {}` (owner), `ClaimOk {spoonId}` (owner), `Spectate {bounds}` (owner), `HuntEnd {scoreboard}` (all). Every other kind throws (`assertPublic` analogue). `SpoonsRemaining` and `HuntEnd` payloads are asserted to contain no key named `x,y,z,position,spoons,list` (HuntEnd carries scores, no positions; unfound spoon reveal is Phase 7).
3. **No standing list / no resend.** Stationary seeker, 100 ticks: exactly one `SpoonVisible` per visible spoon. Moving in and out: one show, one hide per crossing.
4. **Spectator / non-hunter / hider** receive zero reveals at the same position as a hunter who receives one.
5. **Mutation set** (injected broken publishers/wrappers through the SAME checking helper): broadcasts `SpoonVisible` to all (must fire), sends a full spoon list in `SpoonsRemaining` (must fire), resends every tick (must fire the resend gate), spectator inherits visibility (must fire). Plus a no-defect twin that reads green.
6. **The replication audit itself** (criterion 1) cannot run in Lune: that is manual check M-24, a command-bar script run on a CLIENT in a live 2-player session that walks `Workspace`, `ReplicatedStorage`, `ReplicatedFirst`, `StarterGui`, `Lighting` and `Players.LocalPlayer` descendants and reports any Instance, attribute or ValueBase whose name matches `spoon` (case-insensitive) or whose position is within 0.5 studs of a hidden spoon position (positions listed from a server-side debug print gated behind a Studio-only flag, removed in the same commit). The honest split for the requirements table: HUNT-01 is machine-proved for the core and the adapter source, and human-proved for the live audit.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | 360 raycasts/s at the worst case is acceptable server cost | Summary, Cost | Tick hitches at 10 players; mitigation is the movement-delta skip, M-28 measures |
| A2 | Real R15 root height is about 3 studs above floor; eye = root + 1.5 matches the validator's eye | F5 | LoS disagrees with the validator by a few tenths; spoons visible over ledges; M-29 |
| A3 | `CollisionGroup = "Players"` on the ray makes it ignore characters when Players is non-colliding with itself | Pattern 2 | Players block sight; fallback `ExcludeInstances` list; M-28 |
| A4 | Pre-registered/booted collision group via `pcall(RegisterCollisionGroup)` is idempotent enough; Rojo cannot declare groups | Pitfall 2 | Group missing or duplicate error on restart; pcall contains it |
| A5 | A client-created ProximityPrompt renders and fires on touch devices | Code Examples | HUNT-03 unusable on mobile; fallback is a client-drawn tap button that sends the same `Claim` intent |
| A6 | Hysteresis 3 studs and 2-tick LoS-loss debounce | Pattern 3 | Flicker or sluggish hide; tuning |
| A7 | Speed slack 1.5 x WalkSpeed, 3 strikes, rtt clamp 0.5 s | Claim | False rejects on bad links (silent!) or missed teleports; Phase 8 |
| A8 | Hider score rounds half up | Scoring | A one-point difference at most; owner may specify |
| A9 | `Claim` bucket burst 4 / 2 per s | Pitfall 7 | Over-throttled honest mashing, or too loose |
| A10 | Spectator keeps a parked character rather than having none | O3 | D-11's "no character" is only structurally met (no reveals), not literally |
| A11 | Hider is treated as a spectator in the Phase 5 stub | O4 | Hider wanders the map in the slice; harmless (receives no reveals) |
| A12 | PhysicsService not deprecated in favour of Workspace methods | Alternatives | A rename; both documented today |

## Open Questions

| # | Question | Default taken (conservative) | Needs owner? |
|---|----------|------------------------------|--------------|
| O1 | Where does `GLINT_RANGE` live: new `Config/Hunt.luau`, or an 11th constant in `Placement.luau` (bumping the lock spec's "ten")? | New `Config/Hunt.luau` beside it; no existing spec touched; cross-file invariant tested | No, but reversible by one edit |
| O2 | Eye offset from the root: `EYE_HEIGHT - REACH_HEIGHT` (+1.5) or `EYE_HEIGHT` (+4.0)? | +1.5, to match the validator's model | Human check M-29 settles it with a live measurement |
| O3 | Spectator "no character" literally, or parked character? | Parked (WalkSpeed 0 via a tiny adapter effect, not deleted) with a Scriptable client camera; Phase 6 owns `CharacterAutoLoads`/`LoadCharacterAsync` | Yes, soft: D-11 reads "no character" |
| O4 | Is the hider a spectator during the Phase 5 stub? | Yes (receives `Spectate` at hunt start, no reveals) | No |
| O5 | What does a seeker who never completes four of a kind get at round end? | No bonus, no hunt, no reveals; they simply end with 0 | Phase 6 scoreboard decides display |
| O6 | Does a leaver's claimed spoon stay claimed, and what are they paid? | Stays claimed, ledger kept, payout is Phase 6 (MATCH-10) | Phase 6 |
| O7 | Reveal payload: position only, or also surface normal for orienting the glint? | Position only (`id,x,y,z`); the glint is a billboard/glow, not oriented. Skins arrive Phase 7 and must NOT be added here (D-18) | No |
| O8 | Is hunter-eye position taken at the sweep tick, or at the claim for LoS re-check on claim? | Sweep only; claim requires membership in the visible set, which already encodes range+LoS to within one tick. No second raycast on claim (cost, and it would be an oracle-prone reject path) | No |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| lune | running `tests/run.luau` | no (this sandbox) | n/a | CI only; the planner's tasks must not claim local green |
| selene / stylua / luau-lsp / rojo | verify chain | no (this sandbox) | n/a | CI only |
| create.roblox.com docs via `scripts/dev/roblox-doc.sh` | research | yes | pages dated 2026-11-10 | none needed |
| Roblox Studio (2-player local server) | M-24..M-29 | not checkable here | n/a | human step; Gate G3 is not closable without it |

**Missing with no fallback:** Studio for the manual checks (they are human steps by design).

## Validation Architecture

(`workflow.nyquist_validation` = true in config.json.)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Lune headless runner with the repo's own `tests/harness/Test.luau` |
| Config file | `tests/run.luau` (discovers `**/*.spec.luau`); guards in `scripts/ci/zones.luau` |
| Quick run command | `lune run tests/run.luau -- --filter hunt` |
| Full suite command | `lune run scripts/verify.luau` (mirrors CI order) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HUNT-01 | No hidden position in any message to non-entitled user; adapter creates no Instance/attribute | unit + source scan | `lune run tests/run.luau -- --filter hunt/privacy` | Wave 0 |
| HUNT-01 live | Client replication audit | manual | M-24 | Wave 0 (MANUAL-CHECKS.md) |
| HUNT-02 | Range 25, LoS via injected closure, prefilter proof, hysteresis, transition-only | unit | `-- --filter hunt/visibility` | Wave 0 |
| HUNT-03 | Claim intent in Manifest with exactKeys; client prompt only in client file | unit + source scan | `-- --filter net/manifest` and `hunt/wiring` | manifest spec exists (count 14 -> 21) |
| HUNT-04 | Two same-instant claims: one winner; mutant with a yield between check and write fires | unit | `-- --filter hunt/claim` | Wave 0 |
| HUNT-05 | `SpoonsRemaining` count on change only, all audience, no positions | unit | `-- --filter hunt/privacy` | Wave 0 |
| HUNT-06 | Adapter sets the pair non-collidable at start and back at end; assigns on CharacterAdded and DescendantAdded | source scan + M-27 | `-- --filter hunt/wiring` | Wave 0 |
| HUNT-07 | Spectator set membership, bounds payload, no reveals | unit + M-27 | `-- --filter hunt/privacy` | Wave 0 |
| HUNT-08 | Reach rejection at threshold +- epsilon; rtt slack widens; speed sampler strikes; silent | unit | `-- --filter hunt/plausibility` | Wave 0 |
| SCORE-01..04 | The ROADMAP vectors and derived hider vectors | unit | `-- --filter hunt/scoring` | Wave 0 |
| SCORE-05 | End on last claim, end on Timeout, end publishes before clear, exactly once | unit | `-- --filter hunt/round_end` | Wave 0 |
| FOUND-05 | `Scoring` has no import path to cosmetics (fixture exists; add a real-file check that Scoring's closure is clean) | guard | `lune run scripts/ci/check-guards.luau` | exists |
| Gate G3 | Full loop with 3-10 clients/bots, auto-fill | manual + sim | M-30 | Wave 0 |

### Mutation discipline (repo convention)
Each gate gets: clean control, non-vacuity count, no-defect twin, and a mutation of the REAL source (in-memory edit through the same checker) that must fire. Required mutants: remove `RespectCanCollide` from `HuntService` source; use `Completed.rank` as place; publish before mutate in claim; clear before publish in finish; iterate all players instead of hunters; remove the prefilter (the `los` call count rises above the pair bound); `GetServerTimeNow` in `foundDeci`; broadcast `SpoonVisible` to all; add a yield between check and write.

### Sampling Rate
- **Per task commit:** `lune run tests/run.luau -- --filter hunt`
- **Per wave merge:** full `lune run tests/run.luau` plus `check-guards`
- **Phase gate:** full `lune run scripts/verify.luau` green, then M-24..M-30 signed by a human

### Wave 0 Gaps
- [ ] `tests/hunt/` (scoring, visibility, claim, plausibility, privacy, round_end, wiring specs)
- [ ] `tests/harness/HuntRecording.luau` (twin of RecordingPublisher)
- [ ] `MANUAL-CHECKS.md` rows M-24..M-30, written BEFORE execution as Phase 4 did (next free id is M-24; last used is M-17): M-24 replication audit, M-25 client prompt on phone and PC, M-26 two-client race, M-27 collisions + spectator, M-28 validator-vs-live LoS + MicroProfiler, M-29 eye/root offset, M-30 Gate G3 session
- [ ] `tests/net/manifest.spec.luau` updated for Claim (count 14 -> 21 and forbidden list extended)
- [ ] `tests/card/deci_lock.spec.luau` re-run (must still pass: HuntService adds no `os.clock`)

## Security Domain

`security_enforcement` is not set to false in config.json, so included.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | platform-provided identity (the `Player` argument) |
| V3 Session Management | no | n/a |
| V4 Access Control | yes | entitlement = visible-set membership + hunter flag; actor derived from the `Player`, never the payload (rule 7) |
| V5 Input Validation | yes | `Validate.exactKeys` + `Validate.integer` in the Manifest; gateway phase gate `Round` |
| V6 Cryptography | partial | spoon ids and the auto-fill shuffle use `Rng` seeded from the mixed `freshSeed` source, never a round counter (ids must not be guessable or ordered by position) |
| V7 Error handling and logging | yes | rejected claims are silent to the client; server logs through the throttle |

### Known Threat Patterns
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Reading spoon positions from the DataModel (ESP) | Information disclosure | No hidden Instance; reveal-only messages; gates + M-24 |
| Injecting a `SpoonVisible`-like claim by guessing ids | Spoofing/Tampering | Visible-set entitlement; opaque shuffled ids |
| Teleport to a spoon and claim | Tampering | Reach check with rtt slack; 4 Hz speed sampler; strikes |
| Claim flood | Denial of service | Per-(user,intent) bucket; throttled log |
| Reject oracle (probing the plausibility threshold) | Information disclosure | Silent rejects, uniform no-op (D-08); no distinguishable reject codes |
| Client-supplied timestamp or position | Tampering | Schema has no such key; the forbidden-key gate is extended to prove it |
| Spectator relaying positions | Information disclosure | Reveals keyed to hunting seekers only |
| Cosmetic influence on findability | Elevation of privilege | Fixed glint, no skin seam (D-18); `Scoring`/`HuntTable` closure guarded |

## Sources

### Primary (HIGH confidence), all via `scripts/dev/roblox-doc.sh`, pages last_updated 2026-11-10T00:40Z
- create.roblox.com/docs/reference/engine/datatypes/RaycastParams.md (RespectCanCollide behaviour with no stated default, CollisionGroup semantics, Include/ExcludeInstances, reuse)
- .../classes/WorldRoot.md (Raycast signature, RegisterCollisionGroup overhead and edit-time recommendation)
- .../classes/PhysicsService.md (RegisterCollisionGroup, CollisionGroupSetCollidable, server-only)
- .../classes/BasePart.md (CollisionGroup property)
- .../classes/ProximityPrompt.md (parenting rule, Triggered, RequiresLineOfSight, MaxActivationDistance)
- .../classes/Player.md (GetNetworkPing, LoadCharacter deprecated)
- create.roblox.com/docs/workspace/collisions.md ("Disable character collisions" sample)
- .planning/phases/05-.../05-DEBT-RECHECK.md (V-18, V-21, V-22, V-30 taken as settled, not redone)

### Primary (codebase, read this session)
`Main.server.luau`, `CardService.luau`, `NetServer.luau`, `RoundDriver.luau`, `RoundLifecycle.luau`, `Manifest.luau`, `RateLimits.luau`, `Placement.luau`, `SpoonPlacement.luau`, `MapLoader.luau`, `MapContract.luau`, `CardRouting.luau`, `CardTable.luau` (Deps), `zones.luau`, `ClientNet.luau`, `tests/net/manifest.spec.luau`, `tests/placement/config_lock.spec.luau`, `tests/card/service_wiring.spec.luau`, `tests/card/privacy.spec.luau` (head), `.planning/research/ARCHITECTURE.md` section 4.

### Tertiary (LOW)
None used. V-23 and V-34 are deliberately left as measurement rows (05-DEBT-RECHECK); nothing here upgrades them.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH (no new dependencies; all APIs verified)
- Architecture: MEDIUM-HIGH (pure-core pattern proven in Phase 4; F1 and F2 are verified by reading source)
- Pitfalls: MEDIUM (Pitfalls 1, 3, 5, 6 are source- or doc-grounded; 7, 10 rest on tuning assumptions)
- Numbers (25/3/2/1.5/3/0.5/4/2): LOW by design, Phase 8

**Research date:** 2026-11-10
**Valid until:** 2026-12-10 (Roblox pages dated 2026-11-10; re-fetch `RaycastParams` and `ProximityPrompt` if the plan slips past a month)
