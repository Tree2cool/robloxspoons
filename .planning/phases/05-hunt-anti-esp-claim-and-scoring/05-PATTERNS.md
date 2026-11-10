# Phase 5: Hunt, Anti-ESP, Claim and Scoring - Pattern Map

**Mapped:** 2026-11-10
**Files analyzed:** 27 (13 new source, 6 edited source, 8 new or edited spec/fake, plus doc rows)
**Analogs found:** 27 / 27 with a real analog for structure. Client hunt visuals: partial only (Phase 4 UI is the sole precedent, and it is not a hunt).

All paths are relative to `/home/user/robloxspoons`. Line numbers were read on 2026-11-10. `src/server/engine/` and `src/server/core/Gateway.luau` are FROZEN: read-only context, never edited, never imported by name into new design decisions beyond what Phase 4 already does.

## Read this first: seven traps the analogs expose

1. **The adapter seam is where the last real bug lived.** `CardSeatHold` (pure) was fully covered by `tests/card/seathold.spec.luau`; `CardService.makeSeatHold` (the adapter closures) had NO test. `character.PrimaryPart` is not set when `CharacterAdded` fires; `pivotTo` returned false, the hold deferred with nothing to retry it, and a player stayed frozen and Scriptable. Found by a live Studio session, fixed in commit `63d1796` (2026-11-10), gated afterwards by `primaryPartProblems` in `tests/card/service_wiring.spec.luau:174`. **For `HuntService`, `positionOf`, `walkSpeedOf`, the Raycast closure and the collision-group assignment are the exact same species of code: Roblox-API closures injected into a pure core.** Each needs a named source-scan function (not a generic one) in `tests/hunt/service_wiring.spec.luau`. In particular `positionOf` must tolerate a character whose `HumanoidRootPart` has not arrived (Research Pitfall 9) and the scan must prove it by looking for the nil-return branch.
2. **R3 bans the substring `os.` in pure zones, scanned over comment-stripped text including string literals.** A variable named `pos` fails on `pos.x`. It has bitten twice (`zones.luau:56-58` comment, `SpoonPlacement.luau` documents the convention). Name positions `at`, `p`, `eye`, `spot`, `centre`, `from`, `to`. Never `pos`, `cos.`, `pos2`. Also bans `coroutine` and `_G[`. This applies to every file in `src/server/core/`, including the six new ones, because the whole directory is a pure zone (`zones.luau:12`). It does NOT apply to `HuntService.luau` (services are not a pure zone) or `src/client`.
3. **A pure core cannot `require` shared config (R6).** `HuntTable`, `Visibility`, `Plausibility`, `Scoring` receive every number through `Deps`/a `cfg` parameter. Only `HuntService.luau` does `require(ReplicatedStorage.Shared.Config.Hunt)`. The Phase 4 precedent for keeping the vocabulary in sync is a drift/lock spec in `tests/` (which may require across mounts): `tests/card/config_lock.spec.luau`, `tests/placement/config_lock.spec.luau`.
4. **`FireClient` / `FireAllClients` / `OnServerEvent` are NetServer-only (R4, `zones.luau:44-50`).** `HuntService` and `HuntTable` get a `Publisher` and nothing else. The second `Hunt` remote and its audience closures go inside `NetServer.start`, beside `cardRemote`.
5. **`seathold.spec` asserts an EXACT telemetry list** (`tests/card/seathold.spec.luau:180`: `t.deepEqual(telemetry, { "seat_hold_deferred:7" })`). Do not add new telemetry events inside `CardSeatHold` or its `Effects`. Hunt telemetry belongs to `HuntTable`'s own `onTelemetry` dep. Adding a new event name to a path some existing spec pins with `deepEqual` fails that spec.
6. **`tests/placement/config_lock.spec.luau:38` pins exactly ten `Placement` constants** (`t.equal(count, 10, "an eleventh constant must be decided, not slipped in")`). `GLINT_RANGE` goes in the new `Config/Hunt.luau` (Research F3/O1), not `Placement.luau`.
7. **`tests/net/manifest.spec.luau:38,202` hard-codes `FORBIDDEN_KEYS` (7 names) and `seen == 14`.** Adding `Claim` makes it 3 x 7 = 21 and `realValidators()` (line 44) plus the two loose-validator mutants (lines 228-248) enumerate `Draw` and `Pass` by name. Update all four deliberately, and extend `FORBIDDEN_KEYS` with `pos`, `position`, `x`, `y`, `z` (a client-stated position is exactly what the server must never trust). Note that string appears in a TEST file, so R3 does not apply.

---

## File Classification

### Server pure cores (headless, Lune-tested, `src/server/core/`)

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `src/server/core/HuntTable.luau` | service (pure composing core) | event-driven + request-response (claim) | `src/server/core/CardTable.luau` (injected `Deps`, publish after mutate, `tick`, `removePlayer`) | exact (role + shape) |
| `src/server/core/HuntRouting.luau` | utility (pure, audience as data) | transform | `src/server/core/CardRouting.luau` (frozen `KINDS`/`AUDIENCE`/`PRIVATE_KINDS`, `assertPublic`, `makePublisher`) | exact |
| `src/server/core/Visibility.luau` | utility (pure sweep) | transform / batch | `src/server/core/StallDetector.luau` + `IdleClock.luau` (state + injected inputs, returns a command/transition list) | role-match |
| `src/server/core/Plausibility.luau` | utility (pure sampler) | transform / batch | `src/server/core/StallDetector.luau` (per-key counters, strikes) + `RejectThrottle.luau` (per-user window, `isFinite` hardening) | role-match |
| `src/server/core/SpoonRegistry.luau` | model (pure record store) | CRUD | `src/server/core/SpoonPlacement.luau` (consumes the default-spot pool) for input shape; `Bucket.luau` for the small-state-machine shape | partial |
| `src/server/core/Scoring.luau` | utility (pure arithmetic + append-only ledger) | transform | `src/server/core/CardTiming.luau` (pure integer-deci arithmetic, one call site) and `RoundLifecycle.luau` (deadline EXCLUSIVE, deci integers) | role-match |

### Server Roblox adapters (thin)

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `src/server/services/HuntService.luau` | service (adapter) | event-driven (5 Hz sweep, 4 Hz sample) + request-response | `src/server/services/CardService.luau` (two clocks, `RunService.Heartbeat` subtracted accumulator, `makeSeatHold` closures, `abortStart` rollback, `watchCharacter`) | exact |
| `src/server/services/NetServer.luau` (EDIT: `Hunt` remote + hunt publisher) | service (adapter) | pub-sub | itself, lines 40-42, 99-125, 128-129 (`cardRemote`, `CardRouting.makePublisher`) | exact |
| `src/server/Main.server.luau` (EDIT: `Claim` handler, wire `RoundDriver`, `onCompleted` -> hunt, `PlayerRemoving`) | config / wiring | request-response | itself (`handlers` table lines 46-62, `cardService` upvalue pattern, `onCompleted` stub lines 126-128) | exact |
| `src/server/services/RoundDriver.luau` (READ ONLY unless F1 needs a change) | service (adapter) | event-driven | itself | exact |

### Shared

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `src/shared/Config/Hunt.luau` (NEW) | config | n/a | `src/shared/Config/Card.luau` (WHY-header, SCREAMING_SNAKE, seconds not deci, "requires nothing") and `Config/Placement.luau` (locked values, header names consumers) | exact |
| `src/shared/Net/Manifest.luau` (EDIT: `Claim`) | config (registry) | request-response | `Draw`/`Pass` entries, lines 47-60 | exact |
| `src/shared/Config/RateLimits.luau` (EDIT: `Claim` bucket) | config | n/a | `byIntent.Draw`/`Pass`, lines 14-29 | exact |

### Client

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `src/client/net/ClientNet.luau` (EDIT: `onHunt`) | service | pub-sub | itself, `onCard` (lines 12-25 per Phase 4) | exact |
| `src/client/ui/HuntClient.luau` (NEW: reveal -> local Part + prompt; HUD; spectate camera) | component | event-driven | `src/client/ui/CardClient.luau` (receive handler, synchronous, owns view lifetime) | role-match |
| small hunt view modules (`SpoonView`, `SpectateCamera`, `RemainingHud`) | component | event-driven | `src/client/ui/*` renderers + `src/shared/Card/Layout.luau` for any pure arithmetic | partial |

### Tests and guards

| New/Modified File | Role | Closest Analog | Match |
|---|---|---|---|
| `tests/harness/HuntRecording.luau` | test fake | `tests/harness/RecordingPublisher.luau` (with `leak` switch) | exact |
| `tests/hunt/privacy.spec.luau` | test (anti-ESP gate) | `tests/card/privacy.spec.luau` | exact |
| `tests/hunt/service_wiring.spec.luau` | test (source scan of adapter) | `tests/card/service_wiring.spec.luau` | exact |
| `tests/hunt/client_discipline.spec.luau` (HuntClient scan) | test (source scan of client) | `tests/card/renderer_discipline.spec.luau` + `tests/card/round_end.spec.luau` | exact |
| `tests/hunt/{scoring,visibility,claim,plausibility,round_end}.spec.luau` | test | `tests/card/idle.spec.luau`, `stall.spec.luau`, `round_end.spec.luau`, `seathold.spec.luau` | exact |
| `tests/hunt/config_lock.spec.luau` | test (spec-lock) | `tests/placement/config_lock.spec.luau`, `tests/card/config_lock.spec.luau` | exact |
| `tests/net/manifest.spec.luau` (EDIT) | test | itself | exact |
| `tests/card/deci_lock.spec.luau` (RE-RUN, maybe EDIT) | test | itself, lines 203-233 | exact |
| `scripts/ci/zones.luau` (EDIT, optional) | config | itself | exact |
| `MANUAL-CHECKS.md` (EDIT: M-18..M-24) | docs | M-11..M-17 block, lines 7-32 | exact |

---

## Pattern Assignments

### `src/server/core/HuntTable.luau` (pure composing core)

**Analog:** `src/server/core/CardTable.luau` (661 lines). `HuntTable` is its sibling: it owns the hidden state and composes `SpoonRegistry`, `Visibility`, `Plausibility`, `Scoring`.

**Header style to copy** (CardTable.luau:1-40): `--!strict`, then a numbered list of guarantees. Hunt's numbered list must state at least: (1) PURE ZONE, every effect injected; (2) RULE 6, mutate then publish, no yield, the claim is ONE synchronous function; (3) RULE 7, the actor is the `userId` the adapter derived, `spoonId` is the only payload field and is an opaque id; (4) RULE 3, hidden positions live only in `SpoonRegistry` plain tables and leave only through `SpoonVisible` to an entitled hunter; (5) silent reject (D-08), no distinguishable reject kind; (6) round end publishes BEFORE it clears (D-16, Pattern 5).

**Imports** (CardTable.luau:41-47). Sibling-relative requires within the pure zone are legal:
```lua
local Engine = require("../engine/Engine")
local CardRouting = require("./CardRouting")
local IdleClock = require("./IdleClock")
local StallDetector = require("./StallDetector")
```
For `HuntTable`: `require("./HuntRouting")`, `require("./SpoonRegistry")`, `require("./Visibility")`, `require("./Plausibility")`, `require("./Scoring")`. Do not require `../engine/*` except `Rng` if the id shuffle lives here (`Rng.new(seed)`, `src/server/engine/Rng.luau:25`; seed comes from the adapter, mixed source, never a counter: `CardService.freshSeed`, lines 83-85). No `Config` requires (R6).

**Deps object, values not modules** (CardTable.luau:55-83). Copy the structure and the comment "Values, never config modules (guard R6)". Fields to carry (Research Pattern 1): `publisher: HuntRouting.Publisher`, `nowDeci: () -> number`, `positionOf`, `walkSpeedOf`, `rttOf`, `lineOfSight`, `endRound: (reason: string) -> boolean` (or a `lifecycle` object), `rng`, `cfg` values (glint range, hysteresis, LoS-loss ticks, pickup range/margin, eye/reach heights, speed slack, strikes, rtt clamp, scoring constants), `onTelemetry: (name: string, data: { [string]: number }) -> ()`.

**The `Ctx` / `pending` / `after` publish-after-mutate shape** (CardTable.luau:117-120):
```lua
type Step = () -> ()
-- One sweep's working set. `pending` is what goes on the wire, in order; `after` is the Phase 5 sinks,
-- fired once everything is published so a throwing sink cannot swallow a message a client awaits.
type Ctx = { now: number, pending: { Step }, after: { Step } }
```
Copy this idiom for `claim`: mutate (`claimedBy`, `foundDeci`, `remaining`, ledger row) into locals, push publish steps, run them after the mutation block. This is what the Research Pattern 4 `publishClaimEvents` should look like in practice. Where `CardTable` fires `after` sinks so a throwing sink cannot swallow a message, `HuntTable` should fire `deps.endRound("AllSpoonsClaimed")` last of all (D-16: after the final claim's own `ClaimOk`/`SpoonsRemaining` publishes, scoring publish happens in `finish`).

**Public surface to mirror** (CardTable.luau:85-111): `start`, `onIntent`/`claim`, `tick` (called by the adapter's sweep), `removePlayer` (the one generic removal; hunters and visible sets only, claimed spoons stay claimed per Pitfall 11 and rule 8's spirit), `isLive`, `debugState` (test seam only; comment says so, copy that sentence).

**Input hardening to copy** (Bucket.luau:24-26 and RejectThrottle.luau:50-56 `isFinite` + integer checks on `userId`/`nowDeci`): validate `spoonId` is a finite integer even though the Manifest already did, because the core is also driven by specs and by `onGatewayReject`-style paths.

**What NOT to copy:**
- `CardTable`'s `Engine` coupling and `copyOf` card-face machinery. `HuntTable` has no engine.
- The `onGatewayReject` resync path. Silent means silent (D-08): a rejected claim sends NOTHING. There is no `ClaimRejected` kind and no `Sync`-style ack.
- `assignCopies`/`rankOf` anywhere. `rankOf` is in `secretNames` (zones.luau:73) and a hit in client/shared fails R5.
- `debugState` handing out raw spoon positions to anything but a spec. It must never be wired in production.

**Rules that must hold (not analog-derived):**
- `Completed.rank` is the CARD rank, not the place (Research F2). The place counter is `HuntTable`'s own. A mutant using the card rank must fail a spec fed ranks `{7, 2, 5}` expecting bonuses 1000, 900, 800.
- Time is `deps.nowDeci()` read ONCE at claim entry (arrival time, SCORE-02). No `GetServerTimeNow`, no `os`.
- `lifecycle:isOpen` may end the round re-entrantly (Pitfall 5). `false` means return immediately. Deadline is EXCLUSIVE.

---

### `src/server/core/HuntRouting.luau` (pure, audience as data)

**Analog:** `src/server/core/CardRouting.luau` (211 lines). Near copy of the structure, different vocabulary.

**Frozen vocabulary and audience table** (CardRouting.luau:70-93):
```lua
local KINDS = { "RoundStart", "Sync", "Notice", "Table", "Stall", "Depths", "RoundEnd" }
table.freeze(KINDS)

local AUDIENCE: { [string]: Audience } = {
	RoundStart = "seated",
	Sync = "owner",
	...
}
table.freeze(AUDIENCE)

local PRIVATE_KINDS: { [string]: true } = { Sync = true, Notice = true }
table.freeze(PRIVATE_KINDS)
```
Hunt kinds (Research privacy-gate section): `SpoonVisible {id,x,y,z}` owner, `SpoonHidden {id}` owner, `SpoonsRemaining {count}` all, `HuntStart {}` owner, `ClaimOk {spoonId}` owner, `Spectate {bounds}` owner, `HuntEnd {scoreboard}` all. Audience vocabulary becomes `"owner" | "all"`, not `"seated"`; Research says the Card remote's `seated` set is the wrong audience. `PRIVATE_KINDS` is `{ SpoonVisible, SpoonHidden, ClaimOk, Spectate, HuntStart }`.

**The throwing backstop and publisher assembly** (CardRouting.luau:103-137): `audienceOf` errors on an unknown kind; `assertPublic` errors when a private kind is sent to a broadcast method; `makePublisher(effects)` assembles `toPlayer`/`toAll` around them, so "the guard a spec drives is the guard that ships; NetServer supplies only effect closures". Copy all three verbatim, rename `toSeated` to whatever the hunt audience needs (`toHunters` is NOT needed if the only fan-out is `toAll`; `SpoonHidden` on claim goes `toPlayer` per member of `visibleTo[spoonId]`, which is what Research Pitfall 4 prescribes).

**Effects type** (CardRouting.luau:29-34): `fireToPlayer`, `fireToMany`, `fireToAll`, plus a roster accessor. Keep the shape so `NetServer` supplies four one-line closures.

**What NOT to copy:** `split`, `publish`, `assignCopies`, the `Notice`/`PublicEvent` unions. Hunt has no event batching: each message is one kind. Never add a kind carrying a list of spoons (D-01, D-09). The `HuntEnd` payload carries scores and no positions (unfound-spoon reveal is Phase 7).

**Spec twin:** `tests/card/routing.spec.luau` (475 lines) drives `CardRouting` directly; mirror its enumeration of `KINDS`/`AUDIENCE` with a completeness test, `table.isfrozen` assertions, and `assertPublic` throwing for each private kind.

---

### `src/server/core/Visibility.luau` (pure sweep)

**Analog:** `src/server/core/StallDetector.luau` (state held in the closure, `noteApply`, injected `onTelemetry`) and `IdleClock.luau` (`tick(nowDeci) -> { Command }`: mutate then return the list; nothing published from here).

**Return-a-list, publish elsewhere** (IdleClock.luau:23-24 guarantee 6 + 49-52 `Command` union): `Visibility.step(...)` returns `{ shown, hidden }` and mutates its own `visible[userId][spoonId]` state. It publishes nothing. `HuntTable.tick` publishes after the step returns.

**Exports a predicate written once:** IdleClock exports `legal`. `Visibility` should export `eyeOf(root, cfg)` once (Research F5: `root + (EYE_HEIGHT - REACH_HEIGHT)` default, M-23 settles it) so both the sweep and its spec call the same function.

**Injected closure counted by the spec:** the `los` closure is a dep, as `onTelemetry` is in `StallDetector`. The spec counts calls and asserts the prefilter proof: `los` is NOT called for any pair beyond `GLINT_RANGE` (Research Visibility core). Mutation: remove the prefilter, `los` call count rises above the pair bound.

**Squared-distance, no sqrt; no `pos`:** `local dx, dy, dz = eye.x - s.x, ...` Name the table param `at`/`eye`/`spot` (trap 2).

**Hysteresis** per Research Pattern 3; Pitfall 10 sets the test shape (stationary 100 ticks -> exactly one show per visible spoon; jitter +-1 stud across the edge -> at most one show and one hide; no-hysteresis mutant must exceed the cap).

**What NOT to copy:** the engine-state `View` shape. Visibility sees `hunters` only (D-11, Pitfall 8): it iterates the hunter set, never "all players with a root".

---

### `src/server/core/Plausibility.luau` (pure reach check + speed sampler)

**Analog:** `src/server/core/RejectThrottle.luau` (per-user entry map, window arithmetic, `forget`, `isFinite` hardening, a `Decision` record) and `StallDetector.luau` (strike counting with an injected telemetry sink).

**Per-user entry map + forget** (RejectThrottle.luau:37-47, 57-80): `entries: { [number]: Entry }`, `forget(userId)` called from `removePlayer`. Strikes live in `Entry`.

**Hardening idiom** (RejectThrottle.luau:51-53, also Bucket.luau:24-26):
```lua
if type(userId) ~= "number" or not isFinite(userId) then
	error(`RejectThrottle.note: userId must be a finite number, got {tostring(userId)}`)
end
```
Apply to `rtt`, `walkSpeed`, positions: a NaN rtt must not widen the slack. The clamp `[0, RTT_CLAMP]` is applied here, in the pure core, so it is testable.

**Escalation is log-only** (D-07, Research Claim): `STRIKES_TO_ESCALATE = 3` emits an `onTelemetry` event with flat numeric data, and the adapter-side `warn` goes through `RejectThrottle`-shaped throttling. Do not kick. Copy RejectThrottle's header sentence "THIS PHASE DOES NOT KICK ANYBODY ... Do not delete it and do not act on it before Phase 8".

**Silent:** `Plausibility.reach` returns a boolean. There is exactly one failure outcome. A spec asserts that every failure path produces byte-identical publisher output (empty), so no oracle exists for the threshold.

**Spec shape:** `tests/card/reject_throttle.spec.luau` (166 lines) for window/threshold boundary tests with the injected clock; test at threshold +- epsilon and with rtt slack widening (Research test map HUNT-08).

---

### `src/server/core/SpoonRegistry.luau` (pure record store)

**Analog:** `src/server/core/SpoonPlacement.luau` for the input (the default-spot pool and the autoFill source, passed in as plain data, never a map node) and `CardTable.SeatSpec` (CardTable.luau:62) for the "struct built field by field, no map node in scope" rule.

**Struct built field by field** (CardTable.luau header point 8 + `CardService.startRound` lines 380-388): the registry constructor takes `{ x, y, z }` triples and builds its own records `{ id, x, y, z, claimedBy, foundDeci }`. It must never keep a reference to the caller's table.

**Opaque ids:** ids come from a shuffle of `1..N` using `Rng`, never an index into the spot list (Research Don't-Hand-Roll). Seed supplied by the adapter via a `freshSeed()`-style mixed source. Test: ids carry no placement order (a spec asserts the id sequence is not monotonic in spot index across several seeds, with a non-vacuity count).

**`claimedBy` is a userId number, `nil` = unfound** (Research Pattern 4).

**What NOT to copy:** `SpoonPlacement`'s validation logic. `SpoonRegistry` consumes already-validated spots.

---

### `src/server/core/Scoring.luau` (pure arithmetic + ledger)

**Analog:** `src/server/core/CardTiming.luau` for the "arithmetic lives in a pure core because the adapter cannot be loaded by Lune; single call site; tests pin both" pattern (CardService.luau header lines 17-20), and `src/server/core/RoundLifecycle.luau` for integer-deci, exclusive-deadline semantics.

**Name is load-bearing:** `guardedNamePrefixes = { "Scoring", "CardTable", "SpoonPlacement" }` (zones.luau:62) makes `Scoring*` a FOUND-05 root. Keep the filename `Scoring.luau`. No path from it to cosmetics/shop (rule 1). `tests/guards/fixtures/import-pure-zone` already proves by-location coverage; add a real-file closure check (Research FOUND-05 row).

**Config as a parameter** (Research Code Examples): `export type Config = { BONUS_FIRST, BONUS_STEP, CAP_DECI, HIDER_DENOM_DECI, HIDER_MAX, POINTS_PER_DECI }`. The adapter builds it from `Config/Hunt.luau` + `Config/Round.luau` and passes values in (R6). The seconds-to-deci conversion is NOT re-written: reuse `CardTiming`'s function or a sibling in the same file, called from exactly one site. Add a `deci_lock`-style test pinning the call site.

**Integers only:** hider score is `floor((8000 * sum + 3000 * n) / (6000 * n))` (Research Pitfall 12), rule stated in the file header, boundary vectors tested (all unfound = 4000, all found at deci 0 = 0, one of two found at 1500 deci = 3000).

**Test vectors are the ROADMAP's worked examples** (CONTEXT locks them as test vectors): `findPoints(1600 deci) == 1600`, `bonus(3) + findPoints(600) == 1400`, bonus-only seeker, ceiling `bonus(1) + 3000 == 4000` asserted as an equation over the config.

**Name hygiene:** no `pos`, no `os.`. Words like `position` in comments are fine, but `pos` as an identifier before `.` is not.

---

### `src/server/services/HuntService.luau` (thin Roblox adapter)

**Analog:** `src/server/services/CardService.luau` (503 lines). Copy its architecture; do NOT copy its size (this is the file Research warns about).

**Header** (CardService.luau:1-31): "Deliberately thin ... Every behaviour lives in a pure core with its own tests ... (This file names game:GetService, so Lune cannot load it. Specs reach it by comment-stripped source scan ...)". Keep the two-clocks paragraph (lines 9-14) but invert the emphasis: `HuntService` must NOT read any clock itself.

**Clock rule, stricter than CardService:** CardService.luau:70-73 owns the one `os.clock()` expression:
```lua
local function nowDeci(): number
	return math.floor(os.clock() * Round.DECISECONDS_PER_SECOND)
end
```
`HuntService` imports `CardService.nowDeci` (exported at line 138 `CardService.nowDeci = nowDeci`) and uses it. `tests/card/deci_lock.spec.luau:221-233` pins `os.clock` to exactly `CardService`, `NetServer`, `RoundDriver` (and `CardClient` for the client list). Adding `os.clock` to `HuntService` FAILS that spec. That is the intended gate; keep it. `GetServerTimeNow` appears only to publish a countdown deadline outward, if at all, and NEVER feeds `foundDeci` (Research anti-pattern: ARCHITECTURE.md section 4 step 3 is superseded).

**Imports** (CardService.luau:32-53): relative requires for cores, absolute `ReplicatedStorage.Shared...` for config:
```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CardService = require("./CardService")           -- nowDeci
local HuntTable = require("../core/HuntTable")
local HuntConfig = require(ReplicatedStorage.Shared.Config.Hunt)
local Placement = require(ReplicatedStorage.Shared.Config.Placement)   -- PICKUP_RANGE, PICKUP_MARGIN, EYE_HEIGHT, REACH_HEIGHT
local Round = require(ReplicatedStorage.Shared.Config.Round)
```
The `-- Shared config is fetched by absolute DataModel path ... (guard rule R6)` comment (CardService.luau:50-52) is repeated at every such site; copy it.

**10 Hz sweep -> 5 Hz sweep** (CardService.luau:411-421) with the SAME subtracted, clamped accumulator. `tests/card/service_wiring.spec.luau:sweepProblems` gates it; the Hunt twin must too:
```lua
local interval = 1 / CardConfig.SWEEP_HZ
local accumulator = 0
sweepConnection = RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	if accumulator >= interval then
		accumulator = math.min(accumulator - interval, interval)
		table_:tick()
	end
end)
```
Hunt has TWO rates (5 Hz visibility, 4 Hz movement sample). Prefer ONE accumulator at the visibility rate and let `HuntTable.tick` decide which ticks also sample movement (a counter in the pure core), so the adapter keeps a single accumulator and the one scan. Two accumulators double the gate surface.

**Atomic start with rollback** (CardService.luau:321-337 `abortStart`, 339-428 `startRound`): everything fallible inside `pcall(function() ... end)`, `announced` flag, `if not started then abortStart(announced) return false end`. Copy. `beginHunt()` must be atomic the same way: build `HuntTable`, `driver.beginRound()`, collision-pair toggle, connect Heartbeat, all inside one pcall; rollback restores the collision pair to collidable, clears the table, disconnects the sweep. Gate it with an `atomicProblems`-style scan.

**Refusals say why** (commit `b50a74b`, CardService.luau:342-359): every `return false` is preceded by `deps.onTelemetry("hunt_begin_refused_<reason>", { ... })` with a flat numeric table. Never a bare `return false`.

**Telemetry convention (2026-11-10):** `onTelemetry(name: string, data: { [string]: number })`, flat table of numbers; the sink prints the payload, sorted, one line per event (`Main.server.luau:130-139`). Every Hunt event carries its identifying numbers (`userId`, `spoonId`, `strikes`, `remaining`), never just the name. Commit `aa55c45` records the reason: `seat_hold_deferred` once said a hold deferred without saying whose. Strings cannot ride in the table; encode reasons in the event NAME.

**Injected-effects adapter closures, the cautionary pair** (CardService.luau:186-227 `makeSeatHold`):
```lua
local function humanoidOf(playerId: number): Humanoid?
	local player = Players:GetPlayerByUserId(playerId)
	local character = if player ~= nil then player.Character else nil
	if character == nil then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end
...
pivotTo = function(playerId: number, pose: CardSeatHold.Pose): boolean
	local player = Players:GetPlayerByUserId(playerId)
	local character = if player ~= nil then player.Character else nil
	if character == nil or character.PrimaryPart == nil then
		return false
	end
```
Model `positionOf`, `walkSpeedOf`, `rttOf` and `lineOfSight` the same way: each tolerates a missing Player, Character, root or Humanoid by returning nil/false/safe default ("a player can leave between the decision and the effect", CardService.luau:157-158). `positionOf` returns a PLAIN table `{ x, y, z }` (not a `Vector3`) so the pure core never sees a Roblox type.

**Character watching** (CardService.luau:257-300 `watchCharacter`): the PrimaryPart wait-and-retry loop plus the "character that already exists" branch (`= player.Character`). The collision-group assignment (`CharacterAdded` AND `DescendantAdded` AND already-present characters, Research Pitfall 3) must follow the SAME skeleton and gets its own scan. A character with no group collides silently, which is the same invisible-failure class.

**Lines of reuse for the collision group:** Research "Collision group adapter" snippet. Register at boot with `pcall(function() PhysicsService:RegisterCollisionGroup(GROUP) end)`; toggle `CollisionGroupSetCollidable(GROUP, GROUP, false)` at hunt start and `true` at end and in `abortStart`.

**Raycast closure** (Research Pattern 2): ONE reused `RaycastParams`, `RespectCanCollide = true` set EXPLICITLY, `CollisionGroup = PLAYERS_GROUP`, `IgnoreWater = true`. Direction is the full vector to the target (magnitude is the ray length), trimmed by `LOS_END_TRIM`.

**NO Instance creation of any kind** in this file: no `Instance.new`, no `SetAttribute`, no `ProximityPrompt`, no `ObjectValue`/`*Value` (HUNT-01 on the adapter). Gate it by source scan.

**Public surface** (CardService.luau:96-116 `CardService` type): `beginHunt`, `finish(roundId, reason)`, `onClaim(userId, payload)`, `onSeekerCompleted(playerId)`, `removePlayer`, `destroy`. `onCompleted` in `Main` forwards `(seat, playerId, rank)` to `onSeekerCompleted(playerId)`; the card `rank` is discarded there on purpose (F2).

**What NOT to copy:** `holdAvatar`/`releaseAvatar`/`seatHold` (avatar movement lock; a hunter must move freely), `buildCores` idle/stall wiring, `newRejectThrottle` (reuse `CardService.newRejectThrottle()` for the plausibility log rather than a second throttle).

---

### `src/server/services/NetServer.luau` (EDIT: `Hunt` remote)

**Analog:** itself. The ONLY file allowed to call `FireClient`/`FireAllClients`/`OnServerEvent` (guard R4; `zones.luau:44-50`; `check-guards.luau` whole-word scan). Do not weaken the guard to make room; extend this file.

**Create the second server-to-client remote exactly as `cardRemote` is created** (NetServer.luau:40-42):
```lua
local cardRemote = Instance.new("RemoteEvent")
cardRemote.Name = "Card"
```
Add `huntRemote` named `"Hunt"`. Parent it LAST with the others (lines 128-129: "Parent only after every connection above exists"). Add `huntRemote:Destroy()` to `destroy` (lines 143-144) and a `huntRemote`/`huntPublisher` field to the `NetServer` export type (lines 38-45).

**Publisher assembly** (NetServer.luau:111-126): one `HuntRouting.makePublisher({ fireToPlayer, fireToMany, fireToAll, ... })` with four one-line closures against `huntRemote`. The existing `roster: { [number]: Player? }` (lines 55-60) already maps `userId -> Player` and is cleaned in `PlayerRemoving` (line 78). Reuse it; do not build a second roster. The "They left between the routing decision and the send. Ordinary, not an error" guard (lines 113-116) is copied into the hunt `fireToPlayer`.

**What it must NOT do:** decide anything. The header says (lines 10-14) this file "assembles and decides nothing". Hunt audience decisions live in `HuntRouting`; the test is `tests/hunt/privacy.spec.luau`.

**Deps:** `seatedUserIds` (Deps line 36) exists for the card audience. Hunt's `all` audience uses `FireAllClients`; if a hunters-only broadcast is ever needed it takes a `huntersUserIds` dep, built the same way.

**Header update:** "This file now owns TWO remotes" (line 8) becomes three; keep the V-12 sentence ("ordering is guaranteed per connection per direction, including across different RemoteEvent instances").

---

### `src/shared/Net/Manifest.luau` (EDIT: `Claim`) and `src/shared/Config/RateLimits.luau` (EDIT)

**Analog:** the `Draw` and `Pass` entries (Manifest.luau:47-60).
```lua
Pass = {
	phases = { "Round" } :: { RoundPhase },
	validate = Validate.exactKeys({
		seq = Validate.integer({ min = 0, max = 2 ^ 31 }),
		cardId = Validate.integer({ min = 1, max = 64 }),
	}),
```
`Claim`:
```lua
Claim = {
	phases = { "Round" } :: { RoundPhase },
	validate = Validate.exactKeys({ spoonId = Validate.integer({ min = 1, max = 64 }) }),
},
```
Copy the explanatory comment style (Manifest.luau:40-45): state that `spoonId` is an OPAQUE PER-ROUND ID carrying no placement information, that the 64 is a sanity cap not a rule, and that there is no `pos`, `position`, `x`, `y`, `z`, `time`, `userId` key a client could send. `Manifest.luau` requires only `./Validate` (pure zone `src/shared/Net`); add no other require.

**RateLimits** (RateLimits.luau:14-29): add `Claim = { burst = 4, refillPerSecond = 2 }` with the same "LOW CONFIDENCE (V-34) ... starting values for Phase 8 tuning, not measured" comment. Bucket is keyed per `(userId, intent)`, so Claim gets its own bucket (Research Pitfall 7).

**Test edits:** see trap 7. `tests/net/manifest.spec.luau` lines 38, 44, 202, 228-248. The existing "every intent's phases subset of PHASES" case (lines 52-59 per Phase 4) covers `Claim` automatically; keep its `seen > 0` non-vacuity line.

---

### `src/shared/Config/Hunt.luau` (NEW)

**Analog:** `src/shared/Config/Card.luau` (header, 1-40) with `Config/Placement.luau` (header names who consumes it).

**Conventions to copy:**
- `--!strict`, then a long WHY-comment header with numbered points recording the decision IDs (D-02, D-03, D-04, D-07, D-18) and, for EVERY number, whether it is locked or a first-pass tuning value for Phase 8. Research confidence for all of `GLINT_RANGE=25`, `GLINT_HYSTERESIS=3`, `LOS_LOSS_TICKS=2`, `SPEED_SLACK=1.5`, `STRIKES_TO_ESCALATE=3`, `RTT_CLAMP=0.5`, `SWEEP_HZ=5`, `MOVE_SAMPLE_HZ=4` is LOW BY DESIGN; say so.
- "THIS FILE HOLDS SECONDS, NOT DECISECONDS" (Card.luau:3-6). Same here. The conversion is the one pure function plus one call site (see `Scoring`).
- Things that are deliberately NOT here, listed in the header (Card.luau point 6): `PICKUP_RANGE`, `PICKUP_MARGIN`, `EYE_HEIGHT`, `REACH_HEIGHT` stay in `Placement.luau` and are read from there, never duplicated ("a second copy is how a locked value drifts"). Scoring constants: decide whether `BONUS_FIRST=1000`, `BONUS_STEP=100`, find rate, `HIDER_MAX=4000`, `HIDER_DENOM_SECONDS=30.0*10` live here or in `Round.luau`; `ROUND_CAP_SECONDS` already lives in `Round.luau`.
- Ends with `return { NAME = value, ... }` SCREAMING_SNAKE. "This file requires nothing."
- D-18: no purchasable glint variant and NO seam for one. A `GLINT_*` table keyed by anything but a number fails review. Add a lock-spec assertion that the module contains no table-valued entries.

**Spec-lock twin:** `tests/hunt/config_lock.spec.luau` modelled on `tests/placement/config_lock.spec.luau:25-38` (pin each value with `t.equal`, count the keys, message "an Nth constant must be decided, not slipped in") AND the cross-file invariant `GLINT_RANGE > PICKUP_RANGE + PICKUP_MARGIN` (tests may require across mounts by relative path; Research F3). Also `GLINT_RANGE + GLINT_HYSTERESIS` leave-radius > enter radius.

---

### `src/client/net/ClientNet.luau` (EDIT) and `src/client/ui/HuntClient.luau` (NEW)

**Analog:** `ClientNet.onCard` (Phase 4 pattern, `04-PATTERNS.md` lines 347-364) and `src/client/ui/CardClient.luau`.

`OnClientEvent` is owned by `src/client/net/ClientNet.luau` (`zones.luau:52`). Add `ClientNet.onHunt(handler)` there; `HuntClient` NEVER names `OnClientEvent` (R4 will fail it). Resolve the `Hunt` remote once at boot BEFORE connecting any handler; the existing `WaitForChild` is a yield point and the receive handler itself must be synchronous and non-yielding (V-12, Pitfall 11).

**Reveal and hide** (Research Code Examples, `HuntClient`): `SpoonVisible` creates a LOCAL `Part` under a client-created folder plus a `ProximityPrompt` created BY THE CLIENT (D-05); `prompt.Triggered` calls `ClientNet.send("Claim", { spoonId = p.id })`; `SpoonHidden` calls `:Destroy()` and clears the view map. A `ProximityPrompt` appears ONLY in `src/client`; `src/server` contains none (scan).

**Discipline of the client file** is gated by the same method as `tests/card/renderer_discipline.spec.luau` (1328 lines; header lines 1-17: "src/client/ui cannot be loaded by Lune ... this gates the DISCIPLINE rather than the behaviour ... That is a weak kind of gate and it says so") and `tests/card/round_end.spec.luau` (the `ENDER`/`VIEW_HEAD` anchored-slice trick, lines 18-22, to avoid a `slice` landing in the wrong function). Required hunt scans: prompt created only inside the `SpoonVisible` handler; `:Destroy()` in the `SpoonHidden` handler; receive handler body has no `task.wait`, `:Wait(`, `WaitForChild`, `InvokeServer`; the spectate camera sets `CameraType = Enum.CameraType.Scriptable` and clamps to the bounds payload.

**Device-dependent items stay manual**: client-created prompt renders and fires on a phone (M-19, assumption A5; fallback is a client-drawn tap button sending the same `Claim`), spectate bounds (M-21).

**Guard note:** Do NOT add `HuntClient` to `guardedNamePrefixes`. Phase 4 already reasoned this through (zones.luau:35-49): guarded roots also get R3, whose `os.` needle trips on `pos.X`. D-18 means the glint has no cosmetic seam anyway, so there is nothing to protect.

**Greenfield part:** the spectator free camera has no analog in the repo (no `CurrentCamera` code exists under `src/client` today). Research Open Question O3 (parked character vs none) is soft; structure per Research, no pattern to copy.

---

### `src/server/Main.server.luau` (EDIT: wiring)

**Analog:** itself. Wiring only (header line 2: "no gameplay logic lives here").

- **Handlers table** (lines 46-62): add `Claim = function(userId, payload) if huntService ~= nil then huntService:onClaim(userId, payload) end end`. The comment on line 44-45 states "An intent with no handler errors, so a manifest entry can never be silently unroutable"; adding `Claim` to the Manifest without a handler turns into `onError` at runtime. The `huntService` upvalue is declared next to `cardService` (line 42), assigned after construction; copy the nil-guard.
- **`onCompleted`** (lines 126-128) is currently a `print` stub whose comment says "Phase 5 owns the hunt". Replace the body with a forward to `huntService:onSeekerCompleted(playerId)` keeping the print as telemetry. D-15.
- **Round wiring, Research F1:** `RoundDriver.new(function(roundId, reason) print(...) end)` (lines 34-36) is never started and its `onEnded` only prints. Replace with `onEnded(roundId, reason)` -> `huntService:finish(roundId, reason)` THEN `cardService:endRound()`. `driver` is constructed before `huntService`, so use the same upvalue-assigned-later pattern as `cardService`. Do NOT reset `roundStarted` (Phase 6's); the plan must not "fix" it silently.
- **Telemetry sink** (lines 130-139) is the model: sorted `key=value` parts, one line. Reuse the exact closure for `HuntService`'s `onTelemetry` (extract it to a local function so there is ONE sink; do not paste a second copy).
- **`PlayerRemoving`** (lines 164-169): add `huntService:removePlayer(player.UserId)` beside `cardService:removePlayer`, and `rejectThrottle:forget` already happens there.
- **Reject sink:** keep `rejectThrottle:note(userId, tostring(code), CardService.nowDeci())` as the one reject-log path. A rejected `Claim` at the gateway is silent to the client; the card-style `onGatewayReject` resync is NOT forwarded to the hunt (nothing to resync).

---

### Tests

#### `tests/hunt/privacy.spec.luau` (THE anti-ESP gate)

**Analog:** `tests/card/privacy.spec.luau` (842 lines). Study its oracle shape and mutants closely.

**Fixture shape** (privacy.spec.luau:19-102): a `newFixture(opts)` that builds the REAL core with a recording publisher, takes `Options { leak, wrap, userIds, seed }`, returns `{ ct, rec, state, users, ... }`. `wrap` is a function `(base, state, seatOfUser) -> Publisher` that lets a mutation inject a broken publisher around the recorder. Copy this exactly: the hunt oracle is `newFixture({ wrap = broadcastSpoonVisible })`.

**Oracle by walking recorded calls, not by trusting the router** (privacy.spec.luau:1-3 "every assertion reads what was actually called, never what the router claims"; helper `publicWalkProblems` lines 162-186 walks recursively by KEY NAME and returns `(problems, nodesVisited, publicCalls)`). For Hunt: recursively flatten numbers from every publisher call; for each unclaimed spoon and each user, assert no `(x,y,z)` triple equal to that spoon's position appears in a message to a user who is not entitled (within glint range at that tick with LoS). Return `(problems, visited, candidateTriples)`.

**Non-vacuity** (every helper returns a count the test asserts): the entitled path DID send at least N reveals, and the oracle saw at least one candidate triple. A vacuous "nothing was sent" must FAIL. Mirror `t.truthy(visited > 0, ...)`.

**Mutation set** (privacy.spec.luau:679-737 `MUTATION: five leaks each turn the gate red`): clean control through the SAME helpers first (`t.deepEqual(cleanA, {}, "control: case 1 helper")`), then each mutation through the same helper, `t.truthy(#problems > 0, ...)`, a running `mutations += 1`, a `print` with the first problem, and `t.equal(mutations, N, "mutation count")` at the end. Hunt mutants (Research privacy section item 5): (1) broadcast `SpoonVisible` to all; (2) a full spoon list inside `SpoonsRemaining`; (3) resend every tick; (4) spectator inherits visibility; plus a NOT-a-broadcast mutant that the `leak` switch cannot see, like mutation 5 (Notice to the wrong player, lines 713-735): `SpoonVisible` delivered to the wrong hunter by an identity check.

**The `leak` switch**: `tests/harness/RecordingPublisher.luau:20-30` documents why the fake is SILENT in leak mode ("one that announced its own defect would let a gate pass by reading the announcement"). `HuntRecording.luau` copies this verbatim: `toPlayer` recorded as `toAll` when `leak` is set; no log line, no flag.

**Shape gate** (privacy.spec.luau:BANNED_PUBLIC at 158): a banned-key set per public kind. For `SpoonsRemaining` and `HuntEnd`: no key named `x, y, z, position, spoons, list`. Assert `HuntRouting.audienceOf` throws for any kind outside the frozen list.

**What NOT to copy:** the engine-state hashing and the `Livelock` hijack (lines 220-260). Hunt has no hash.

**Honest split recorded in the requirements table:** HUNT-01 is machine-proved for the core and the adapter source, human-proved for the live replication audit (M-18). The spec's header must say so, as `service_wiring.spec` says what it does not prove.

#### `tests/hunt/service_wiring.spec.luau` (adapter source scan)

**Analog:** `tests/card/service_wiring.spec.luau` (350 lines). The file header (lines 1-11) is the template: names why Lune cannot load the file, says the gate is a SCAN and says so, names the shape ("a clean control on the real source, a non-vacuity size, a no-defect TWIN ... and mutants that are the REAL source text edited in memory, each of which must be seen by the SAME problems function").

**Helpers to copy verbatim** (lines 15-37): `SERVICE_PATH`, `slice(text, from, to)`, `replaceOnce(text, old, new)` (asserts the needle exists, so a mutant that edits nothing errors instead of passing vacuously), `at(body, needle, from)`.

**Problems-function skeleton** (lines 40-93 `atomicProblems`): takes `raw`, strips with `lex.stripComments(raw)` (`scripts/ci/lex.luau`), slices a function body between two markers, returns `(problems, sizeA, sizeB)`. Return the body size so the test can assert non-vacuity.

**Test shape** (lines 213-217 and 219-267):
```lua
t.test("WR-03: startRound is atomic ...", function()
	local problems, startSize, abortSize = atomicProblems(raw)
	t.deepEqual(problems, {}, "clean path")
	t.truthy(startSize > 1500 and abortSize > 300, `non-vacuity: bodies ...`)
end)

t.test("WR-03 MUTATION: ...", function()
	local twin = replaceOnce(raw, "cardTable = nil", "cardTable = nil")
	t.deepEqual((atomicProblems(twin)), {}, "the no-defect twin must be green")
	local mutants: { { name: string, edited: string } } = { ... }
	local seen = 0
	for _, mutant in mutants do
		local problems = atomicProblems(mutant.edited)
		t.truthy(#problems >= 1, `mutant "{mutant.name}" was not seen`)
		if #problems >= 1 then seen += 1 end
	end
	t.equal(seen, #mutants, "every mutant seen")
end)
```

**The lesson recorded in the code** (service_wiring.spec.luau:196-199):
```lua
-- "= player.Character", not "player.Character": the latter is a PREFIX of player.CharacterAdded on
-- the Connect line, so the loose form matched the mutant and the gate could not fire. Caught by
-- running the mutation, not by reading the check.
```
This is the repo's recurring failure: gates that cannot fire. Every needle must be checked against the MUTANT, not only the clean text. The executor must RUN each mutation (edit the real source in memory, call the checker) and see a nonzero problem count before declaring a gate done; a gate whose needle is a prefix of something present in the mutant reads green on the mutant.

**Required scans** (Research Pattern 6, one problems-function each so a failure names itself):
1. `rayProblems`: the function that builds the `RaycastParams` contains `RespectCanCollide = true`, `CollisionGroup =`, and a `Raycast(` call. Mutant: delete the `RespectCanCollide` line (Research lists this as required).
2. `noInstanceProblems`: `HuntService` contains no `Instance.new`, `SetAttribute`, `ProximityPrompt`, `ObjectValue`, `Value` construction; `src/server` tree contains no `ProximityPrompt` anywhere (walk with `fs.readDir`, as `deci_lock.spec.luau:52` does).
3. `clockProblems`: no `os.clock`, no `GetServerTimeNow`; confirm `deci_lock` still passes, which is itself the "no third clock" gate.
4. `sweepProblems` twin: the `Heartbeat` callback subtracts and clamps the accumulator and ticks the table; contains no `task.wait`, `:Wait(`, `WaitForChild`, `InvokeServer` (rule 6 on the adapter). Mutants: unclamped, reset-instead-of-subtract, tick removed (copy lines 296-318).
5. `characterProblems`: collision group assigned on `CharacterAdded`, on `DescendantAdded`, and to an already-existing character; waits for `PrimaryPart`/root (copy the `primaryPartProblems` structure, lines 174-208).
6. `positionOfProblems`: `positionOf` has a nil-return branch for a missing character/root (Pitfall 9). Mutant: remove it.
7. `atomicProblems` for `beginHunt` (pcall; rollback restores sweep, collision pair, table; refusals emit telemetry).
8. `publishOrderProblems`: in the end path, the publish of `HuntEnd` appears before the clear (Pattern 5; this is the Phase 4 `RoundEnd` bug, WR-05, `table.clear(seated)` before `toSeated`), copy `audienceProblems`' ordering check (`clear < told` at lines 83-86).
9. `FireClient`/`FireAllClients`/`OnServerEvent` never named in `HuntService` (R4 already enforces; the scan confirms and gives a local failure message).

#### `tests/hunt/{claim,round_end,visibility,plausibility,scoring}.spec.luau`

**Analogs:** `tests/card/round_end.spec.luau` for end-of-round ordering and exactly-once (the Hunt twin: a publisher whose audience is read from LIVE state, and a mutant that clears first and must deliver nothing, Research Pattern 5); `tests/card/idle.spec.luau` and `stall.spec.luau` for injected-time pure cores; `tests/core/round.spec.luau` for `RoundLifecycle`.

**Claim spec:** two `claim` calls back to back with the same `nowDeci` assert exactly one winner, one ledger row, `remaining` decremented once, one `ClaimOk`. Mutation: a variant whose check and write are separated by an injected yielding hook (Research Pattern 4), plus "publish before mutate" and "clear before publish". Boundary: claim at `deadline - 1` scores 1 point; at `deadline` scores nothing.

**House mutation style, all of it** (this repo's recurring failure is gates that cannot fire; several were caught only by running the mutation):
1. A clean control through the same helper (`t.deepEqual(clean, {}, "control: ...")`).
2. A non-vacuity assertion (a count of what the check looked at; `seen > 0`; a body size; a minimum number of calls).
3. A no-defect twin (identity edit) that must read green, so no mutant can be red for harness reasons.
4. A mutation of the REAL source or REAL core configuration that must fire, driven through the SAME checker, named `MUTATION:` at the start of the case name (valve.spec.luau:176 convention, `tests/engine/valve.spec.luau`).
5. For injected-option mutations (cores), the pair rule: run broken AND clean on the same fixture and assert the clean one fires where the broken one does not.
6. Run the mutation by hand before committing (record the observed count in the plan summary).

#### `tests/card/seathold.spec.luau` and the telemetry constraint

`seathold.spec` shows the injected-effects test: a `recorder()` returning `(Effects, log, telemetry)` with each effect appending a string (lines 12-37), then `t.deepEqual(log, { "scriptable:7:true", "freeze:7:true", "pivot:7:1,2,3" })` to pin ORDER, and an exact telemetry list at line 180. Copy the `recorder` idiom for `HuntTable`'s injected deps (publisher, `positionOf`, `lineOfSight`) to pin ordering (mutate, then publish; `ClaimOk` before `SpoonsRemaining`; end last). Because the existing spec pins exact telemetry for CardSeatHold, add Hunt telemetry only in Hunt files.

#### `tests/net/manifest.spec.luau` (EDIT) and `tests/card/deci_lock.spec.luau`

See trap 7. `deci_lock.spec.luau:203-233` is re-run, not edited, unless `HuntService` legitimately needs a place in the `os.clock` list (it must not; it imports `CardService.nowDeci`). If a plan finds it needs `os.clock`, that is a design smell to surface, not a list to extend.

---

### `scripts/ci/zones.luau` and `scripts/verify.luau`

**zones.luau (edit is optional and small):** `pureZones` already contains `src/server/core`, so every new core file is an R2/R3 root and is under the selene pure allow-list with NO registration. `guardedNamePrefixes = { "Scoring", "CardTable", "SpoonPlacement" }` already covers `Scoring`. Do not add `HuntService` (a service file may need `os.`-containing identifiers legitimately; Phase 4 withdrew the same proposal for the same reason, zones.luau:35-49). `secretNames` (line 73): consider adding nothing; `SpoonDefaultSpot` etc. already guard the client and shared trees. The header contract (lines 3-7) is "additions allowed, removals never".

**verify.luau (14 steps, `scripts/verify.luau:22-85`):** `STEPS` is an ordered array of `{ name, kind, run }` run in CI order, stopping at the first failure. The order: tool versions, `lune setup`, stylua, selene (shipped), pure-zone list (kind `zones`, captured), selene pure allow-list (`${{ steps.zones.outputs.list }}` placeholder), sourcemap, typecheck roblox, typecheck standard (pure zones + tooling), structural guards `check-guards.luau`, map contract, tests (`lune run tests/run.luau`), build, built-place require check. Phase 5 adds NO step: new specs under `tests/hunt/` are discovered automatically by `tests/run.luau` (any `**/*.spec.luau`; a spec that registers nothing FAILS), new pure files are picked up by the zones list, new shipped files by the typecheck. Do not add a step to run hunt specs separately. `tests/ci/verify.spec.luau` ties the step list to the workflow YAML; if a step is ever added, both must change. After a green run `verify` prints every unticked manual check.

**stylua matters:** format step is `stylua --check src scripts tests`. Tabs, as in all the excerpts above. Wrapped long lines the way stylua does (see CardService's wrapped `assert` at lines 61-64).

---

### `MANUAL-CHECKS.md` (EDIT: M-18..M-24, written BEFORE execution)

**Analog:** the Phase 4 block (MANUAL-CHECKS.md lines 7-32). Rows were written in plan 04-02, "before any UI wave was executed, so that nothing device-dependent can be ticked by a machine". Copy:
- the lead paragraph that assigns each check to a phase and states which are blocking;
- the sentence "Silence is not success: `lune run scripts/verify.luau` prints every unticked check after a green run.";
- the close-block table `| Row | Blocking | Carries | A failure means |` with a concrete consequence per row;
- the sentence "nothing below is ticked, and no machine may tick it".
Next free id is M-18 (last used M-17, per Research Wave 0). Rows from Research: M-18 replication audit (command-bar script on a CLIENT in a 2-player session, walks `Workspace`, `ReplicatedStorage`, `ReplicatedFirst`, `StarterGui`, `Lighting`, `Players.LocalPlayer`; its Studio-only debug print of spoon positions is removed in the same commit), M-19 client prompt on phone and PC, M-20 two-client race, M-21 collisions + spectator, M-22 validator-vs-live LoS + MicroProfiler, M-23 eye/root offset, M-24 Gate G3 session. State for each what a failure means and whether it blocks. Also note the Verification Debt rows touched (V-18, V-21, V-22; V-23, V-34 left as measurement rows) and that nothing here upgrades a claim's confidence without a primary-source re-fetch.

The new-file `NEEDS_HUMAN.md` row pattern (Phase 4 touched it) follows the same "written before execution" rule.

---

## Shared Patterns

### Cross-mount access (R6)
**Source:** `src/server/services/NetServer.luau:21-24`, `CardService.luau:50-53`.
**Apply to:** `HuntService.luau`, the `NetServer` edit, `Main.server.luau`, every `src/client/ui/*` hunt file.
```lua
-- Shared modules are fetched by absolute DataModel path: src/server and src/shared are separate Rojo
-- mounts, so a relative require would resolve on disk and fail in Studio (guard rule R6).
local Manifest = require(ReplicatedStorage.Shared.Net.Manifest)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
```
Pure cores under `src/server/core` never do this; they take values through `Deps` / a `cfg` parameter.

### Injected clock and deciseconds (rule 5)
**Source:** `CardService.luau:70-73` (the one expression), `RoundLifecycle.luau` (integer deci, exclusive deadline), `tests/card/deci_lock.spec.luau:203-233`.
**Apply to:** `HuntTable`, `Visibility`, `Plausibility`, `Scoring`, `HuntService`. Pure code sees `nowDeci: () -> number` or a number argument; never `os.clock` (R3 bans `os.`). `HuntService` takes `CardService.nowDeci`.

### Pure core, thin adapter, with a gate on the adapter
**Source:** `CardTable`/`CardService`, `CardSeatHold`/`makeSeatHold`, `Gateway`/`NetServer`, `RoundLifecycle`/`RoundDriver`.
**Apply to:** `HuntTable`/`HuntService`. The adapter header states "Deliberately thin" and "(This file names game:GetService, so Lune cannot load it. Specs reach it by comment-stripped source scan and by testing the pure pieces it wires; that the wiring behaves in a live server is manual check M-xx.)" (CardService.luau:6-8). **Every adapter closure gets a named scan in `tests/hunt/service_wiring.spec.luau`; a pure core covered at 100% with an ungated adapter is how the PrimaryPart bug lived for a week.**

### Publish after mutate, no yield inside a mutation (rule 6)
**Source:** `CardTable.luau` header point 2 and the `Ctx { pending, after }` shape (lines 117-120); `RoundLifecycle.luau:9` ("State is marked ended BEFORE onEnded is invoked").
**Apply to:** `HuntTable.claim`, `HuntTable.finish`, `removePlayer`.

### Round end publishes before it clears (the Phase 4 WR-05 bug)
**Source:** `CardService.endRound` lines 431-451 and `tests/card/service_wiring.spec.luau` `audienceProblems` (ordering check). `RoundEnd` was once published after `table.clear(seated)` and `toSeated` reads `seated`, so it reached nobody.
**Apply to:** `HuntTable.finish`: build the scoreboard, read the audience from live state, publish `HuntEnd`, THEN clear hunters, visible sets, spectators. Contain the publish in a `pcall` with a telemetry on failure (`round_end_publish_failed`, CardService.luau:445) so a failed publish cannot stop the state reset.

### Telemetry convention (established 2026-11-10)
**Source:** `Main.server.luau:130-139`; commits `aa55c45` (telemetry carries its data), `b50a74b` (refusals say why).
**Apply to:** all hunt `onTelemetry` calls. Events carry a flat table of numbers; the sink prints the payload, sorted, not just the name. No strings in the data table; encode a reason in the event name. Refusal paths never return a bare `false`.
```lua
onTelemetry = function(name, data)
	local parts: { string } = {}
	for key, value in data do
		table.insert(parts, `{key}={value}`)
	end
	table.sort(parts)
	print(`[Spoons] telemetry {name} {table.concat(parts, " ")}`)
end,
```

### Guard rules that bind every new file (`scripts/ci/check-guards.luau`, `zones.luau`)
| Rule | Scope | What it means here |
|---|---|---|
| R1 strict header | `src`, `scripts`, `tests` | `--!strict` is line 1 of every new `.luau`, specs and fakes included |
| R2 FOUND-05 closure | roots = `guardedNamePrefixes` files + every file in a pure zone | no transitive require path containing `cosmetic`, `shop`, `catalog`, `loadout`, `economy`, `monetiz`, `gamepass`, `purchase`, `skin` from any `src/server/core/*` hunt file |
| R3 banned constructs | pure zones + guarded roots | no `coroutine`, no `_G[`, and the substring `os.` in comment-stripped text including string literals: a variable `pos` fails on `pos.x` (bit twice). Use `at`, `p`, `eye`, `spot` |
| R4 Net hygiene | `src` only | `OnServerEvent`, `FireClient`, `FireAllClients` only in `NetServer.luau`; `FireServer`, `OnClientEvent` only in `ClientNet.luau` |
| R5 secret names | `src/client`, `src/shared` | `SpoonDefaultSpot`, `DecoyAnchor`, `SeekerSpawn`, `HiderSpawn`, `rankOf` never in client/shared code or strings (comments are stripped first) |
| R6 cross-mount | `src` | a `require` must resolve identically on disk and in the DataModel; pure cores never reach `src/shared`/`ReplicatedStorage` |

### Frozen runtime vocabularies with a drift test
**Source:** `CardRouting.luau:70-93`, `Manifest.PHASES`, `manifest.spec.luau:35-50`.
**Apply to:** `HuntRouting.KINDS/AUDIENCE/PRIVATE_KINDS`. `table.freeze`, assert `table.isfrozen` and exact contents in a spec. Where a vocabulary must exist on both sides of a mount (the client's handled-kind list), assert deep equality in a drift test.

### Config as values, locked by a spec
**Source:** `Config/Card.luau`, `Config/CardPool.luau`, `tests/placement/config_lock.spec.luau`, `tests/card/config_lock.spec.luau`.
**Apply to:** `Config/Hunt.luau`. Never inline a number in a gameplay module.

---

## No Analog Found

| File / concern | Role | Data Flow | Reason | Nearest structural precedent |
|---|---|---|---|---|
| Spectator free-roaming camera (client) | component | event-driven | no `CurrentCamera`/`Scriptable` camera code exists in `src/client` | Research Open Question O3 and manual check M-21; keep the decision (bounds clamp, no reveals) server-side as a membership test |
| `PhysicsService` collision-group boot registration | service | one-shot | no `PhysicsService` use anywhere in `src/` | Research "Collision group adapter" snippet; wrap in `pcall` (Pitfall 2); structure after `watchCharacter` for the assignment half |
| `Workspace:Raycast` line-of-sight closure | utility (adapter) | request-response | the validator models LoS in pure geometry (`Obb.segmentHits`, `MapValidator`), no runtime ray exists | Research Pattern 2. `Obb.segmentHits` stays the validator's; do not add a second sight model in Lua (Don't-Hand-Roll) |
| Client-created `ProximityPrompt` | component | event-driven | no prompt or local-Instance reveal exists | Research Code Examples (`HuntClient`); A5 fallback is a tap button sending the same `Claim` |
| Ledger (`Scoring.newLedger`, append-only rows) | model | CRUD | no ledger exists; `Bucket`'s per-key map is the closest data shape | Research Code Examples (`Scoring`), ARCHITECTURE.md |

## Read-only context (FROZEN)

- `src/server/engine/**` (`Engine`, `Types`, `Pool`, `Rng`, `Ring`, `Invariants`): not edited. `Rng.new(seed)` (`Rng.luau:25`) may be required by `SpoonRegistry`/`HuntTable`; mind its header warning that small seeds give a constant first output (hence `freshSeed()`).
- `src/server/core/Gateway.luau`: not edited. Its check order is `isKnown -> phase gate -> bucket -> validate -> dispatch` and its header says "nothing may be reordered". A new `Claim` intent rides this chain unchanged: unknown intent, wrong phase, rate limit and bad payload are all rejected before `HuntService.onClaim` runs. `NetServer` already works around its lack of a payload on reject by carrying `inFlightPayload` (NetServer.luau:62-66).

## Metadata

**Analog search scope:** `src/server/{core,services,engine}`, `src/shared/{Net,Config}`, `src/client/net`, `scripts/ci/{zones,check-guards,lex}.luau`, `scripts/verify.luau`, `tests/{card,harness,net,placement}`, `MANUAL-CHECKS.md`, `.planning/phases/04-live-card-table/04-PATTERNS.md`, git log (2026-11-10 fixes `63d1796`, `aa55c45`, `b50a74b`).
**Files read in full or in targeted ranges:** 05-RESEARCH.md, 04-PATTERNS.md, CardSeatHold, CardTable (head), CardRouting, RejectThrottle (head), IdleClock (head), CardService (head, `makeSeatHold`, `startRound`, `endRound`), NetServer, Main.server, Manifest, RateLimits, Card.luau (head), Placement.luau (head), zones.luau, verify.luau (STEPS), privacy.spec (fixture, helpers, mutation case), service_wiring.spec, seathold.spec (head), renderer_discipline.spec (head), round_end.spec (head), RecordingPublisher, MANUAL-CHECKS.md (head), config_lock.spec (Placement), deci_lock.spec (clock list).
**Not read (cited from Phase 4 map or Research only):** `src/client/ui/CardClient.luau`, `Obb.luau`, `SpoonPlacement.luau`, `StallDetector.luau` body, `check-guards.luau` body, `routing.spec`, `idle.spec`, `stall.spec`, `reject_throttle.spec`.
**Pattern extraction date:** 2026-11-10
