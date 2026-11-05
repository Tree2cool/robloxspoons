# Phase 4: Live Card Table - Pattern Map

**Mapped:** 2026-11-05
**Files analyzed:** 41 (22 new source, 7 edited source, 12 new spec/fake, plus 2 doc rows)
**Analogs found:** server and test side 27 / 27 with a real analog. Client UI 0 / 9 (greenfield, structural precedent only).

All paths are relative to `/home/user/robloxspoons`. Line numbers were read on 2026-11-05.

## Read this first: five traps the analogs expose

1. **A pure server core cannot `require` shared config.** `src/server/core/CardTable.luau` is in the `src/server/core` pure zone, and `src/shared` is a separate Rojo mount (guard R6). The core receives every number (strike count, `AUTO_PASS_DECI`, stall threshold, `PENDING_TIMEOUT`) through `Deps`. Only the Roblox adapter `CardService.luau` does the absolute `ReplicatedStorage.Shared...` require. Where a vocabulary must be duplicated (the `RoundPhase` type is the precedent), a drift test ties the copy to the source (`Gateway.PHASES` vs `Manifest.PHASES`).
2. **`rankOf` is about to become a forbidden identifier in `src/client` and `src/shared`.** Validation adds it to `secretNames`. R5 is a raw substring scan (`string.find(text, name, from, true)`, `scripts/ci/check-guards.luau:528-532`). It also hits comments. RESEARCH.md Integration 3 puts `assignCopies(rankOf, ranks)` in `src/shared/Card/Faces.luau`, which would trip the new rule. **Put copy assignment in the server (`CardTable` or `CardRouting`), or rename the parameter, and keep the word `rankOf` out of every comment under `src/shared` and `src/client`.** Today `rankOf` appears in neither tree (grep: zero hits), so the rule starts clean.
3. **`guardedNamePrefixes` matches the file's basename by prefix.** `CardTable` covers `CardTable.luau` only. `CardService`, `CardRouting`, `IdleClock` and `StallDetector` do not get the FOUND-05 no-cosmetics import check unless a prefix is added (one line, `zones.luau:24`).
4. **`OnServerEvent` is already owned by `NetServer.luau` (R4).** `CardService` must not name `OnServerEvent`, `FireClient` or `FireAllClients`. The Publisher implementation lives inside `NetServer.luau`.
5. **Adding `src/shared/Card` to `pureZones` is a one-token edit with a test-time cost.** `tests/purity/purity.spec.luau:74-93` shells out to `check-guards --print-zones` and runs `selene` once per zone. Expect roughly +0.4 s for the new zone, against the +3 s phase budget.

---

## File Classification

### Server pure cores (headless, Lune-tested)

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `src/server/core/CardTable.luau` | service (pure core) | request-response + event-driven | `src/server/core/Gateway.luau` (`new(deps)`, injected deps, contained dispatch) | role-match |
| `src/server/core/IdleClock.luau` | service (pure core) | event-driven (injected clock) | `src/server/core/RoundLifecycle.luau` (injected `nowDeci`, exactly-once, deciseconds) | role-match |
| `src/server/core/StallDetector.luau` | utility (pure core) | transform / batch | `src/server/core/RoundLifecycle.luau` (state plus injected clock) and `src/server/core/Bucket.luau` (per-key counters) | partial |
| `src/server/core/CardRouting.luau` | utility (pure) | transform | `src/server/core/Gateway.luau` header (the check order written as data) and `Manifest.luau` `intents` table | partial |
| `src/server/core/RejectThrottle.luau` (D-22 log throttle, name is mine) | utility (pure) | transform | `src/server/core/Bucket.luau` | role-match |

### Server Roblox adapters (thin)

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `src/server/services/CardService.luau` | service (adapter) | event-driven (10 Hz sweep) + request-response | `src/server/services/RoundDriver.luau` | exact (pattern) |
| `src/server/services/NetServer.luau` (EDIT: second remote plus Publisher) | service (adapter) | pub-sub (server to client) | itself (`NetServer.start`, lines 36-82) | exact |
| `src/server/Main.server.luau` (EDIT: handlers, composition, `RoundStub`) | config / wiring | request-response | itself (`handlers` table, lines 46-68) | exact |
| avatar seat/hold/release (inside `CardService`) | service | event-driven | **none, greenfield** | none |

### Shared (pure zone `src/shared/Card/` plus config plus Net)

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `src/shared/Net/Manifest.luau` (EDIT: add `Draw`, `Pass`) | config (registry) | request-response | the existing `Ping` entry, lines 84-92 | exact |
| `src/shared/Config/RateLimits.luau` (EDIT: per-intent rows) | config | n/a | `byIntent.Ping`, lines 123-125 | exact |
| `src/shared/Config/Card.luau` (NEW) | config | n/a | `src/shared/Config/CardPool.luau` (values with a why-comment header) | exact |
| `src/shared/Card/Prediction.luau` | model (pure reducer) | event-driven | structural: `Bucket.luau` (pure state plus injected clock). No reducer analog. | partial |
| `src/shared/Card/Layout.luau` | utility (pure arithmetic) | transform | structural: `src/server/core/Obb.luau` / `WalkGrid.luau` (pure geometry) | partial |
| `src/shared/Card/Faces.luau` | model (pure tables) | transform | `src/shared/Net/Validate.luau` (pure vocabulary table) | partial |
| `src/shared/Card/Hints.luau` | config / utility | transform | `Manifest.PHASES` plus a completeness spec | partial |
| `src/shared/Card/Flourish.luau` | service (pure driver) | event-driven | `src/server/core/RoundLifecycle.luau` with `tests/harness/FakeScheduler.luau` | role-match |

### Client (greenfield)

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `src/client/net/ClientNet.luau` (EDIT: `onCard`) | service | pub-sub | itself (lines 12-25) | exact |
| `src/client/Main.client.luau` (EDIT: boot the UI) | entry | n/a | itself (6 lines) | exact |
| `src/client/ui/Controls.luau` | adapter | request-response | **none, greenfield** | none |
| `src/client/ui/CardHud.luau` (ScreenGui root) | component | event-driven | **none, greenfield** | none |
| `src/client/ui/Hand.luau`, `Piles.luau`, `StatusStrip.luau`, `Callout.luau`, `TableCards.luau` | component | event-driven | **none, greenfield** | none |
| `src/client/ui/Input.luau` (LastInputType, CAS accelerators) | adapter | event-driven | **none, greenfield** | none |

### Tests and guards

| New/Modified File | Role | Closest Analog | Match |
|---|---|---|---|
| `tests/harness/RecordingPublisher.luau` | test fake | `tests/harness/FakeClock.luau`, `FakeScheduler.luau` | exact |
| `tests/card/{prediction,privacy,idle,stall,flourish,faces,layout,hints,controls,cardtable}.spec.luau` | test | `tests/core/gateway.spec.luau`, `tests/core/round.spec.luau`, `tests/engine/valve.spec.luau` | exact |
| `tests/net/manifest.spec.luau` (EDIT) | test | itself | exact |
| `scripts/ci/zones.luau` (EDIT) | config | itself | exact |
| `MANUAL-CHECKS.md`, `NEEDS_HUMAN.md` (EDIT) | docs | existing M-01..M-10 rows | exact |

---

## Pattern Assignments

### `src/server/core/CardTable.luau` (pure core, request-response + event-driven)

**Analog:** `src/server/core/Gateway.luau` (the pure-core/adapter split) and `src/server/core/RoundLifecycle.luau` (injected clock).

**Why this file name is load-bearing:** `guardedNamePrefixes = { "Scoring", "CardTable", "SpoonPlacement" }` (`scripts/ci/zones.luau:24`). The filename `CardTable*` alone puts it under the FOUND-05 transitive no-cosmetics/shop check. The file is also under `src/server/core`, a pure zone (zones.luau:9), so no Roblox API, no `coroutine`, no `os.`.

**Header and strict style** (Gateway.luau:1-17). Copy the shape: `--!strict`, a "PURE ZONE" sentence, the numbered list of guarantees, and the rejection-code vocabulary in the header.
```lua
--!strict
-- The single typed gateway (FOUND-04). PURE ZONE: no Roblox API, no yields (CLAUDE.md rule 6).
-- The server derives the actor from the RemoteEvent's player argument; the client never names a
-- seat, a target or a hand index (CLAUDE.md rule 7), so `userId` arrives from the adapter and is
-- never read out of the payload.
```

**Injected-dependency constructor** (Gateway.luau:27-38, 48-56). This is the model for `CardTable.new(deps)`. Every external effect is a field on `Deps`:
```lua
export type Deps = {
	manifest: { intents: { [string]: Intent }, isKnown: (name: unknown) -> boolean },
	bucket: { take: (self: any, userId: number, intent: string, spec: any) -> boolean, forget: ... },
	rateFor: (intent: string) -> any,
	getPhase: () -> RoundPhase,
	dispatch: (userId: number, intent: string, payload: unknown) -> (),
	onReject: (userId: number, intent: unknown, code: Code) -> (),
	onError: (userId: number, intent: string, err: unknown) -> (),
}
...
local function new(deps: Deps): Gateway
	local function reject(userId: number, intentName: unknown, code: Code): (boolean, Code)
		deps.onReject(userId, intentName, code)
		return false, code
	end
```
For `CardTable.new`, `Deps` should carry at least: `publisher` (see the Publisher seam below), `nowDeci: () -> number`, `rng` (an `Rng` from `src/server/engine/Rng.luau`), `config` values (`autoPassDeci`, `maxStrikes`, `stallThreshold`), `onCompleted` (the `CompletionSink` stub), and `onTelemetry`.

**Engine seam** (Engine.luau:382-385). The whole public surface is two functions. Do not propose engine changes:
```lua
return {
	newRound = newRound,
	apply = apply,
}
```
`Engine.newRound(config: EngineConfig, seatPlayerIds: {PlayerId}, rng) -> State` (Engine.luau:65). `Engine.apply(state, intent) -> {ok, events, reject}`. Intent variants (Types.luau:91-94): `Draw{seat}`, `Pass{seat, cardId}`, `Remove{seat, cause}`. Build the config with `Pool.poolConfig(n, k, j, mode)` (Pool.luau:64), never `ranks = n - 1 + k` inline (CardPool.luau header says "the only place that subtraction is written").

**Require style inside the pure zone** (same mount, relative):
```lua
local Engine = require("../engine/Engine")
local Pool = require("../engine/Pool")
local Types = require("../engine/Types")
```
This is legal. `NetServer.luau:14-15` uses the same `"../core/Bucket"` form.

**Contained dispatch** (Gateway.luau:87-98). The model for "a throwing handler never escapes":
```lua
local caught: unknown = nil
local success = xpcall(function(): ()
	deps.dispatch(userId, name, clean)
end, function(e: unknown): ()
	caught = e
end)
if not success then
	deps.onError(userId, name, caught)
	return reject(userId, name, "HandlerError")
end
return true, "Ok"
```

**Rules binding this file (not copy-from-analog, but must hold):**
- Rule 6: call `Engine.apply`, take the returned `events`, and only AFTER it returns feed them to `CardRouting` and then `deps.publisher`. No `task`, no yield, no callback passed into `apply`.
- Rule 7: seat is resolved from `userId` via the table's own roster, never from the payload.
- Bench path narrows the removal cause type to `"Disconnected" | "Benched"`. `Engine.apply` throws on `Remove{Completed}` (RESEARCH Pitfall 5).
- Time-driven behaviour is `CardTable.tick(nowDeci) -> {Command}`. Do not schedule per-seat timers.

---

### `src/server/core/IdleClock.luau` (pure core, injected clock)

**Analog:** `src/server/core/RoundLifecycle.luau`.

**Injected scheduler/clock contract** (RoundLifecycle.luau:21-31, 44-46). Integer deciseconds, no `os`:
```lua
export type Scheduler = {
	nowDeci: () -> number,
	delay: (seconds: number, fn: () -> ()) -> () -> (),
}
export type Deps = {
	scheduler: Scheduler,
	onEnded: (roundId: number, reason: Reason) -> (),
}
local DECISECONDS_PER_SECOND = 10
local function new(deps: Deps): Lifecycle
```
`IdleClock` does NOT need `delay` (the 10 Hz sweep is the adapter's); it takes `nowDeci` as a plain argument to each call, which is even simpler to test. The header-comment style to copy is "State is marked ended BEFORE onEnded is invoked" (RoundLifecycle.luau:9, 40): mutate, then notify.

**Deci-conversion location.** The pure core receives `autoPassDeci` as a number. The conversion `math.floor(CardPool.AUTO_PASS_MAX_SECONDS * Round.DECISECONDS_PER_SECOND + 1e-9)` is written ONCE, in the adapter (see `CardService` below), because the pure core cannot require shared config. A spec-lock test asserts `== 80` and `<= 8.0 * 10` against the real config values (the test file lives outside every Rojo mount, so it may require across mounts).

**D-15 legal-action predicate** goes in this file, written once: `legal(seat) = (#hand == 4 and #inbox >= 1) or (#hand == 5)`. Read from engine state `Types.Seat` fields (`hand`, `inbox`, Types.luau:59-67). D-35: at hand 4 the expiry yields a strike and NO `Draw` command. Make `tick`'s command type exclude an auto-draw so the mutation "an auto-draw fires" is a type error as well as a test failure.

---

### `src/server/core/StallDetector.luau` (pure, D-20)

**Analog:** `src/server/core/Bucket.luau` (small pure state machine with per-key counters and a defensive input check). Reuse its input-hardening idiom (lines 24-26):
```lua
-- NaN is the only number that is not equal to itself; the two infinities are excluded explicitly.
local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end
```
**Independence rule:** the detector must be keyed on `noteApply` calls (accepted-action count without a `Completed`/`SeatRemoved`), NEVER on `ValveForcedPass`. The mandatory mutation case ("stuck, valve silent") is expressed by feeding it a valve-free event stream. Emit telemetry via an injected `onTelemetry` sink.

---

### `src/server/core/CardRouting.luau` (pure, event to audience as data)

**Analog (structural):** the `Manifest.intents` table (`src/shared/Net/Manifest.luau:83-93`) and `Gateway.luau` header lines 7-12. Both express a policy as a plain table a test can enumerate. From RESEARCH Pattern 1:
```lua
local AUDIENCE = { Sync = "owner", Notice = "owner", Table = "seated", Stall = "seated", RoundStart = "seated" }
```
Add `PRIVATE_KINDS = { Sync = true, Notice = true }` here. Use `table.freeze` as `PHASES` does (Manifest.luau:73-74, Gateway.luau:45-46) so a later module cannot widen the audience at runtime:
```lua
local PHASES: { RoundPhase } = { "Lobby", "Hide", "Round", "Podium" }
table.freeze(PHASES)
```
Per-event routing (RESEARCH Integration 2): strip `ValveForcedPass` from the public `Table` batch and turn it into a private `Notice` to the affected seat's player. Keep the seat-to-userId lookup inside `CardTable`, not here.

**Copy assignment lives here or in `CardTable`, not in `src/shared/Card/`** (trap 2). Copy the RESEARCH Integration 3 loop verbatim but keep it server-side; its input is `State.rankOf` (Types.luau:80).

---

### The Publisher seam (answers the R4 constraint)

**Closest existing injected-dependency example:** `Gateway.new(deps)` for the shape, and `Bucket.new({ clock = clock })` (Bucket.luau:22, gateway.spec.luau:36-37) for a one-field dep object.

**Why it is forced.** `scripts/ci/zones.luau:44-45`:
```lua
		FireClient = "src/server/services/NetServer.luau",
		FireAllClients = "src/server/services/NetServer.luau",
```
`check-guards.luau:512-523` fails any file under `src/` other than the owner that contains these identifiers as a whole word. So `CardTable` and `CardService` can never call them.

**Interface (defined in `CardTable.luau` or `CardRouting.luau`, implemented only in `NetServer.luau`):**
```lua
export type Publisher = {
	toPlayer: (userId: number, kind: string, payload: unknown) -> (),
	toSeated: (kind: string, payload: unknown) -> (),
	toAll: (kind: string, payload: unknown) -> (),
}
```

**NetServer implementation site** (the existing pattern to extend, `NetServer.luau:36-82`): create the second RemoteEvent exactly as `Intent` is created (lines 37-38), parent it last (line 69), and add the guard that throws when a `PRIVATE_KINDS` kind is passed to `toSeated`/`toAll`. Extract that guard as a pure function so a spec can call it directly (RESEARCH says "extract the pure guard function"; put it in `CardRouting` and have `NetServer` call it).
```lua
local remote = Instance.new("RemoteEvent")
remote.Name = "Intent"
...
remote.Parent = ReplicatedStorage   -- parent LAST, after every connection exists
```
For the new remote, `NetServer` also needs a roster `userId -> Player` so `toPlayer` can call `FireClient`. Clean up on `Players.PlayerRemoving` in the same handler that already calls `gateway:forget` (lines 65-67).

---

### `src/server/services/CardService.luau` (thin Roblox adapter)

**Analog:** `src/server/services/RoundDriver.luau`. Copy its shape exactly: a doc header stating what is bound and why it is thin; absolute `ReplicatedStorage.Shared` requires; a `makeScheduler()` that binds the real clock; a `new(...)` that returns a plain table of closures.

**Header + cross-mount require documentation** (RoundDriver.luau:1-18). The "two clocks" paragraph must be repeated and respected:
```lua
-- Two clocks, never mixed in one calculation:
--   * os.clock()          the scheduling and scoring clock. ...
--   * GetServerTimeNow()  Unix seconds, smoothed and monotonic: what a client countdown needs. It is used
--                         ONLY to publish a deadline outward and is never fed back into the core.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RoundLifecycle = require("../core/RoundLifecycle")
-- Shared config is fetched by absolute DataModel path, not a relative require: src/server and src/shared are
-- separate Rojo mounts, so a relative path would cross a mount boundary (check-guards rule R6).
local Config = require(ReplicatedStorage.Shared.Config.Round)
```
For `CardService`: `local CardPool = require(ReplicatedStorage.Shared.Config.CardPool)` and `...Config.Card` and `...Config.Round`, then pass VALUES into `CardTable.new`.

**Real clock binding** (RoundDriver.luau:30-42), reuse verbatim for `nowDeci`, and `task.delay` plus `task.cancel` for any one-shot:
```lua
nowDeci = function(): number
	return math.floor(os.clock() * Config.DECISECONDS_PER_SECOND)
end,
delay = function(seconds: number, fn: () -> ()): () -> ()
	local thread = task.delay(seconds, fn)
	return function() task.cancel(thread) end
end,
```
**Publishing a deadline outward** (RoundDriver.luau:51-58): `publishedUnix = Workspace:GetServerTimeNow() + remainingSeconds` computed from a deci difference. Same for `idleDeadlineUnix` in `Sync`.

**10 Hz sweep:** a `RunService.Heartbeat` accumulator (or `task.wait(0.1)` loop) calls `CardTable.tick(nowDeci())` and applies each returned command OUTSIDE any `apply`, then publishes (rule 6). Do not create per-seat timers.

**NO ANALOG, greenfield (server code):**
- Seating an avatar at a `Seat1..Seat9` anchor, holding it, and releasing it on `Completed`/bench (D-15, D-29..D-31). Research verified there is no `Humanoid|.Sit|SeatPart|PivotTo|WalkSpeed` code in `src/`. Closest structural precedent: `src/server/services/MapLoader.luau` (a service that reads the map contract anchors). Read it for how seat anchors are located before writing the hold.
- Setting `Player.DevComputerMovementMode` / `DevTouchMovementMode` (server only).
Both are Roblox-API code, so they live in `CardService`, never in a pure core, and each needs a Studio check (M-11).

---

### `src/shared/Net/Manifest.luau` (EDIT: add `Draw` and `Pass`)

**Analog:** the `Ping` entry (Manifest.luau:83-93) and the module-level doc ("One line per intent: later phases add theirs here and nowhere else").
```lua
local intents: { [string]: Intent } = {
	Ping = {
		phases = PHASES,
		validate = Validate.exactKeys({ nonce = Validate.integer({ min = 0, max = 2 ^ 31 }) }),
	},
}
```
New entries (RESEARCH Integration 1, with `phases = { "Round" }`; the type is `{ RoundPhase }` so a bare string array literal needs the annotation or a cast the way `gateway.spec.luau:50` does with `"Round" :: Gateway.RoundPhase`):
```lua
Draw = { phases = { "Round" }, validate = Validate.exactKeys({ seq = Validate.integer({ min = 0, max = 2 ^ 31 }) }) },
Pass = { phases = { "Round" }, validate = Validate.exactKeys({
	seq = Validate.integer({ min = 0, max = 2 ^ 31 }),
	cardId = Validate.integer({ min = 1, max = 64 }),
}) },
```
`Manifest.luau:61` requires only the sibling `./Validate`. Do not add any other require (pure zone `src/shared/Net`). If a `Resync` intent is chosen (Open Question 5) it is a third row here, plus a `RateLimits.byIntent` row.

### `src/shared/Config/RateLimits.luau` (EDIT)

**Analog:** lines 123-125.
```lua
RateLimits.byIntent = {
	Ping = { burst = 2, refillPerSecond = 1 },
} :: { [string]: Spec }
```
Add `Draw` and `Pass` rows. Keep the LOW CONFIDENCE header comment (lines 2-3) and extend it; `Bucket` is keyed per `(userId, intent)` (Bucket.luau:13) so each intent gets its own bucket.

### `src/shared/Config/Card.luau` (NEW)

**Analog:** `src/shared/Config/CardPool.luau`. Copy the structure: `--!strict`, a long WHY-comment header that records the decision IDs (D-13, D-16, D-17, D-20, D-32) and which values are NOT knobs, then `return { NAME = value, ... }` with SCREAMING_SNAKE names (CardPool.luau:51-58). Contents per RESEARCH: `MAX_STRIKES = 3`, `AFK_WARN_SECONDS = 2.0`, `FLOURISH_DURATION_SECONDS = 1.5`, tween durations, stall parameters, `PENDING_TIMEOUT_SECONDS = 1.0`.
Do NOT duplicate `AUTO_PASS_MAX_SECONDS`; leave that in `CardPool`.

---

### `src/shared/Card/*.luau` (NEW PURE ZONE)

**How a pure zone is declared** (`scripts/ci/zones.luau`):
- Line 9: `pureZones = { "src/server/engine", "src/server/core", "src/shared/Net" },`
- Lines 3-7: the header states "nothing is ever removed", and a Roblox-datatype validator would go in a NEW directory outside the list.
- Line 56 `ignoreSegments` and line 14 `scanDirs = { "src", "scripts", "tests" }` need no edit.

**Exactly what registering a new zone requires:**
1. Edit `zones.luau:9` to `pureZones = { "src/server/engine", "src/server/core", "src/shared/Net", "src/shared/Card" },`. This is the ONLY registration site. `check-guards.luau:358` (R2/R3 roots), `:481` (R3 scan) and `:619` (`--print-zones`) all read this list. R1 already covers it (`scanDirs` includes `src`).
2. Effects, automatically: the FOUND-06 no-Roblox-API lint (`selene.pure.toml` allow-list) now runs on the directory through `tests/purity/purity.spec.luau:74-93` (it asks `check-guards --print-zones`, so no test edit is needed); R3 bans `coroutine`/`os.` there.
3. Every file in it needs `--!strict` on line 1 (R1).
4. Requires inside the zone are sibling-relative (`require("./Faces")`), the way `Manifest.luau:61` does. A require of `../Config/Card` stays inside the `src/shared` mount, so it is legal for R6 and Lune can resolve it.
5. Add a client and shared secret scan: `secretNames = { "SpoonDefaultSpot", "DecoyAnchor", "SeekerSpawn", "HiderSpawn" }` (zones.luau:49) gets `"rankOf"`. The R5 scope is `src/client` and `src/shared` only (`check-guards.luau` `secretClientDirs`, line ~504). Add a fixture beside `tests/guards/fixtures/secret-name/src/client/Leak.luau` if the existing spec (`tests/guards/guards.spec.luau:72`) does not already iterate over `secretNames`.
6. Optional, one-line each: `guardedNamePrefixes` gets `"Flourish"` and `"CardHud"` (UI-SPEC requires a require-graph assertion that the client driver and UI have no path to cosmetics/shop; this reuses FOUND-05), and `netOwners` gets `OnClientEvent = "src/client/net/ClientNet.luau"`, mirroring `FireServer` at line 46.

A pure module that must be tested by Lune has to be required from `tests/` by relative path (`require("../../src/shared/Card/Layout")`), exactly as `tests/core/gateway.spec.luau:6-12` does.

**Per-file structural precedent (no direct analog for any of them):**

| File | Nearest structural precedent |
|---|---|
| `Prediction.luau` | Pure reducer over `auth + pending[]`. No reducer exists in the tree. Follow the shape of `Bucket.new(deps)` returning a record of closures plus an `export type`, and `RoundLifecycle`'s "mutate first, then notify" ordering. |
| `Layout.luau` | Pure arithmetic returning rects. Precedent: `src/server/core/Obb.luau` and `WalkGrid.luau` are pure geometry cores with spec files. |
| `Faces.luau` | Static tables plus a total mapping. Precedent: `Validate.luau`'s vocabulary and `Manifest.PHASES` with `table.freeze`. Keep rank-ladder and joker-map tables exhaustive and frozen so the "joker map exhaustive" mutation (a third `JokerMode`) is detectable. |
| `Hints.luau` | Static (state x input) table; completeness is a spec, as `manifest.spec.luau:52-59` asserts the `phases` subset rule over every intent and asserts the loop ran (`seen > 0`). |
| `Flourish.luau` | Injected scheduler, cancellable one-shot, token guard. Direct precedent: `RoundLifecycle` backstop (`begin`, cancel, round-id token) tested with `FakeScheduler`. |

---

### `src/client/net/ClientNet.luau` (EDIT: add `onCard`)

**Analog:** itself, lines 12-25.
```lua
local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote == nil then
		remote = ReplicatedStorage:WaitForChild("Intent") :: RemoteEvent
	end
	return remote :: RemoteEvent
end

function ClientNet.send(intentName: string, payload: { [string]: any }?)
	getRemote():FireServer(intentName, payload or {})
end
```
`FireServer` stays here (R4, zones.luau:46). Add a second lazily-resolved remote for the card stream and `ClientNet.onCard(handler)` that connects `OnClientEvent`. **Pitfall 11:** the existing `WaitForChild` is a yield point. Resolve both remotes once at boot, before connecting any handler, and keep the handler itself synchronous and non-yielding.

### `src/client/Main.client.luau` (EDIT)

**Analog:** itself (6 lines, `require("./net/ClientNet")`). Relative requires within `src/client` are fine (same mount). Shared modules are fetched by `ReplicatedStorage.Shared.Card...` absolute path because `src/client` mounts to `StarterPlayer.StarterPlayerScripts.Client` (default.project.json:17-20) and `src/shared` to `ReplicatedStorage.Shared`. This is the same trick `NetServer.luau:18` uses on the server side.

---

### `src/client/ui/*` — NO ANALOG, GREENFIELD

`src/client/` today holds only `Main.client.luau` and `net/ClientNet.luau`. There is no UI code, no framework and (D-34) none may be added. State that plainly in the plans.

**Proposed structure, so executors do not invent one** (modelled on the pure-core/adapter split of `Gateway`/`NetServer`):
- Every module under `src/client/ui/` is a *renderer only*: `Instance.new`, property assignment, `TweenService`, connections. All decisions come from `src/shared/Card/*` (`Layout`, `Prediction`, `Hints`, `Faces`, `Flourish`).
- One `ScreenGui` root created in `CardHud.luau` with `ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets` set explicitly (UX-03, V-24). Test the constant in `layout.spec` the way RESEARCH specifies.
- `Controls.luau` exposes ONLY `hide()` and `restore()`, both idempotent. Use the RESEARCH "Control hiding behind one seam" example verbatim as the starting point. No `PlayerModule` or `GetControls` string anywhere in `src/` (grep-guard, `controls.spec`).
- Fonts: `BuilderSans` Regular plus Bold only. There is no Gotham fallback (N-1).
- Strip text uses `UITextSizeConstraint` (D-36).

The unit under test for the renderer's Roblox-touching code is a Studio/phone check (M-11 onward), not Lune.

---

## Tests

### `tests/harness/RecordingPublisher.luau` (NEW test fake)

**Analog:** `tests/harness/FakeClock.luau` (full file) and `tests/harness/FakeScheduler.luau:21-33,105-115`. Pattern: `--!strict`, an exported record type, `local function new(): T`, `return { new = new }`. State is closed over, observable only through returned functions, no yields.
```lua
--!strict
export type FakeClock = { now: () -> number, advance: (seconds: number) -> () }

local function new(): FakeClock
	local t = 0
	return {
		now = function() return t end,
		advance = function(seconds: number) t += seconds end,
	}
end

return { new = new }
```
`RecordingPublisher.new()` returns the three `Publisher` functions plus a `calls: () -> { Call }` accessor, where `Call = { method: "toPlayer"|"toSeated"|"toAll", userId: number?, kind: string, payload: unknown }`. Also expose a `mode` option (`"honest"` or broadcast-leak) so the mutation case can inject the broken variant. The injected-bad-dependency idiom is `FakeScheduler.Options.cancelIsNoop` (lines 29, 53-60), which models a defect the production dependency could have.

### Spec files `tests/card/*.spec.luau`

**Analog for structure:** `tests/core/gateway.spec.luau` and `tests/core/round.spec.luau`.

**Spec skeleton** (gateway.spec.luau:6-12, 28, 30-60, 100+):
```lua
local FakeClock = require("../harness/FakeClock")
local Test = require("../harness/Test")
...
return function(t: Test.Runner)
	local function harness(): Harness
		-- build the Deps with recording closures: dispatched, rejections, errors
	end

	local function expectRejected(h: Harness, userId: number, intent: unknown, payload: unknown, code: string)
		local before = #h.dispatched
		local ok, got = h.gateway:handle(userId, intent, payload)
		t.equal(ok, false, "must be rejected")
		t.equal(got, code, "wrong rejection code")
		t.equal(#h.dispatched, before, "a rejected message must never reach dispatch")
```
Rules from the headers: *assert the SPECIFIC reason, not "rejected"* (gateway.spec.luau:1-3), *use the injected clock, nothing sleeps*, and a test-local manifest is fine because `tests/` is not a Rojo mount, so cross-mount relative requires are legal (gateway.spec.luau:4-5).

**Harness API:** `t.test(name, fn)`, `t.equal`, `t.deepEqual`, `t.truthy`, `t.falsy`, `t.contains`, `t.throws`, `t.fuzz` (`tests/harness/Test.luau:15-31`). Discovery is automatic: any `**/*.spec.luau` under the `--root`, and a spec that registers nothing FAILS the run (`tests/run.luau:1-6`). A new `tests/card/` directory needs no registration.

**Non-vacuity assertion idiom** (manifest.spec.luau:52-59). Copy for every gate:
```lua
local seen = 0
for name, intent in Manifest.intents do
	seen += 1
	t.deepEqual(phaseProblems(intent.phases), {}, `intent {name} declares an unacceptable phase list`)
end
t.truthy(seen > 0, "the subset check ran over zero intents, which proves nothing")
```
**Negative-control idiom** (manifest.spec.luau:61-70): drive the SAME checker function with known-bad input and assert it reports it. For example the D-20 case: `phaseProblems({ "Scramble" })` returns `{ "unknown phase: Scramble" }`.

**The "MUTATION:" naming convention — `tests/engine/valve.spec.luau`:**
- Case name begins literally with `MUTATION:`: `t.test("MUTATION: with the valve disabled, nothing escapes", function()` (valve.spec.luau:176).
- The mutation is an *injected option on the fixture*, never an edit of source. Header lines 38-40: "Takes the fixture's own options table rather than two positional booleans, so that the flag the MUTATION case turns off is spelled out in the case that depends on it", then `newRun({ antiLivelockValve = false, valveSeed = 1 })` (line 177).
- Every mutation case is a PAIR: it runs the broken configuration AND the clean configuration on the same fixture and asserts the clean one fires where the broken one does not (valve.spec.luau:177-200: valve-off asserts `firings == 0`, then valve-on asserts `firings >= 1` and "visits states the valve-off run never reaches").
- It also asserts the fixture itself is valid, so a vacuous fixture fails: `t.equal(off.state.valve.observations, 2000, "one observation per action, valve off")` and the cycle-equality hashes (lines 185-187).

Model the 25 mutation rows in `04-VALIDATION.md` the same way: `RecordingPublisher.new({ leak = true })`, `IdleClock.new({ autoPassDeci = 81 })`, `CardTable.new({ ..., pickCard = lowestRank })`, each in a `MUTATION:`-named case beside its clean control and a count assertion.

**Link simulation for `prediction.spec`:** use `FakeScheduler` (`advance(seconds)`, `nowDeci()`, `delay`, `pending()`), not wall time. Latency of 150/300 ms is `advance(0.15)` / `advance(0.3)`. Note `FakeScheduler` floors to deciseconds (`math.floor(seconds * 10)`, line 49 and 80), so 0.15 s becomes 1 deci. Pick 0.2 s and 0.3 s, or model 150 ms as 1 deci and say so in the spec.

**Seeded fuzz:** `tests/harness/Fuzz.luau` plus `t.fuzz(name, { seed, iterations, gen, check })`. Bound iterations (budget: `prediction` fuzz <= 1.0 s).

**`tests/net/manifest.spec.luau` (EDIT):** extend with one case per forbidden key (`seat`, `to`, `target`, `index`) for each of `Draw`/`Pass`, asserting `UnknownKey`, plus NaN and extra-key cases. Copy the exact-code style at lines 9-10 (`local NAN: number = 0 / 0`). The existing "every intent's phases list is non-empty and a subset of PHASES" case (lines 52-59) will automatically cover the new entries.

**`cardtable.spec` against the real engine:** build the round the way `src/server/engine/Pool.luau:64` does (`Pool.poolConfig(n, k, j, mode)`) and `Rng.new(seed)` (`src/server/engine/Rng.luau:25`). Use a non-trivial seed, since the Rng header warns about small seeds (Rng.luau:15).

---

### `scripts/ci/zones.luau` (EDIT) — summary of every needed line

```lua
pureZones = { "src/server/engine", "src/server/core", "src/shared/Net", "src/shared/Card" },   -- line 9
guardedNamePrefixes = { "Scoring", "CardTable", "SpoonPlacement", "CardRouting", "CardService", "Flourish", "CardHud" },  -- line 24, optional but recommended (trap 3)
netOwners = { ..., OnClientEvent = "src/client/net/ClientNet.luau" },                          -- optional
secretNames = { "SpoonDefaultSpot", "DecoyAnchor", "SeekerSpawn", "HiderSpawn", "rankOf" },    -- line 49
```
The header comment at lines 3-7 is the contract: additions are allowed, removals never. Adding a name to `guardedNamePrefixes` is a hard failure for any existing file that matches and fails the import check, so run `lune run scripts/ci/check-guards.luau` after each edit.

**R6 reminder:** `scripts/ci/check-guards.luau` rule R6 resolves each `require` and requires disk and DataModel to agree. `Manifest.luau:61` (`require("./Validate")`) is a same-directory example that passes.

---

## Shared Patterns

### Cross-mount access (R6)
**Source:** `src/server/services/NetServer.luau:16-19` and `src/server/services/RoundDriver.luau:16-18`.
**Apply to:** `CardService.luau`, the `NetServer.luau` edit, `Main.server.luau`, `src/client/Main.client.luau`, every `src/client/ui/*.luau`.
```lua
-- Shared modules are fetched by absolute DataModel path: src/server and src/shared are separate Rojo
-- mounts, so a relative require would resolve on disk and fail in Studio (guard rule R6).
local Manifest = require(ReplicatedStorage.Shared.Net.Manifest)
local RateLimits = require(ReplicatedStorage.Shared.Config.RateLimits)
```
Pure cores under `src/server/core` never do this. They take values through `Deps`.

### Injected clock and deciseconds (rule 5)
**Source:** `RoundDriver.luau:32-34`, `FakeScheduler.luau:21-24`, `FakeClock.luau`.
**Apply to:** `IdleClock`, `CardTable.tick`, `Flourish`, `StallDetector`, `RejectThrottle`.
Pure code sees `nowDeci: () -> number` or a number argument, never `os.clock` (R3 bans `os.` in pure zones).

### Pure core, thin adapter
**Source:** `Gateway.luau` + `NetServer.luau`; `RoundLifecycle.luau` + `RoundDriver.luau`.
**Apply to:** `CardTable`/`CardService`, `Flourish`/`ui/*`, `Prediction`/`ui/Hand`. Adapter header states "Deliberately thin: all behaviour and every test live in core/X" (NetServer.luau:3-4, RoundDriver.luau:2-3).

### Contained handler plus reject sink (D-22 decision site)
**Source:** `Gateway.luau:48-52, 87-98` and the existing sink in `Main.server.luau:62-67`:
```lua
onReject = function(userId, intent, code)
	warn(`[Spoons] rejected {tostring(intent)} from {userId}: {code}`)
end,
```
**Apply to:** the D-22 decision. RESEARCH Integration 6 recommends keeping the gateway order and throttling this unthrottled `warn` with a small pure per-user counter (`RejectThrottle`), plus forwarding card-intent rejects to the card core so the client's `seq` is acked. Record the decision in the plan and mark `01-CONTEXT.md` D-22 reviewed. Do not touch `Gateway.luau:56-79`, whose header says "nothing may be reordered" and whose order is spec-locked.

### Frozen runtime vocabularies with a drift test
**Source:** `Manifest.luau:71-74` plus `Gateway.luau:19-23, 45-46` and `manifest.spec.luau:35-50`.
**Apply to:** `CardRouting.AUDIENCE`/`PRIVATE_KINDS`, the `Faces` rank ladder and joker map, `Hints` table. `table.freeze` them and assert `table.isfrozen` and the exact contents in a spec. Where a copy must exist on both sides of the mount, assert deep-equality of the two (the drift test).

### Config as values
**Source:** `src/shared/Config/CardPool.luau:51-58`, `RateLimits.luau:121-125`. **Apply to:** all tunables. Never inline a number in a gameplay module.

### Spec-lock tests
**Source:** `manifest.spec.luau:35-50`, `tests/engine/spec_lock.spec.luau`. **Apply to:** D-02 (no debounce exists), D-13 (`AUTO_PASS_DECI == 80`), D-14 (`AUTO_PASS_SELECTION == "uniform-random-from-hand"`), `ANTI_LIVELOCK_VALVE == true`, D-35, D-24, `ScreenInsets` constant. These live in `tests/` and may require `src/shared/Config/CardPool.luau` directly.

---

## No Analog Found

| File / concern | Role | Data Flow | Reason | Nearest structural precedent |
|---|---|---|---|---|
| `src/client/ui/*` (all UI modules) | component | event-driven | `src/client/` has no UI code and D-34 forbids a framework | pure-core/adapter split of `Gateway`/`NetServer`; decisions in `src/shared/Card/*` |
| `src/client/ui/Controls.luau` | adapter | request-response | no control-hiding code exists; `GetControls()` is on a removal path (V-26) | RESEARCH "Control hiding behind one seam" example |
| `src/client/ui/Input.luau` | adapter | event-driven | no input handling exists | RESEARCH `LastInputTypeChanged` plus CAS notes |
| Avatar seat / hold / release / `Dev*MovementMode` | service | event-driven | no `Humanoid`/`Sit`/`PivotTo`/`WalkSpeed` anywhere in `src/` | `MapLoader.luau` for locating the seat anchors only |
| `Prediction.luau` reducer | model | event-driven | no reducer or optimistic-state code exists | `Bucket.luau` closure-record style |
| `Layout.luau` | utility | transform | no screen geometry exists | `Obb.luau`, `WalkGrid.luau` pure arithmetic |
| `RoundStub` (phase to `Round`, roster, start a `CardTable`) | wiring | request-response | `Main.server.luau:35-43` has a phase holder with a setter and "the real phase machine is Phase 4/6 work", nothing more | the `currentPhase` / `setPhase` pair in `Main.server.luau:36-43`; remove the `local _ = setPhase` shim when wiring it |

## Metadata

**Analog search scope:** `src/server/{core,services,engine}`, `src/shared/{Net,Config}`, `src/client`, `scripts/ci`, `tests/{harness,core,net,engine,guards,purity}`, `default.project.json`.
**Files read in full or in targeted ranges:** Gateway, NetServer, ClientNet, Main.client, Main.server, RoundDriver, RoundLifecycle (head), Bucket (head), Admission (head), Manifest, RateLimits, CardPool, zones, check-guards (R2/R4/R5 ranges), Types, Engine (head and tail), Pool (poolConfig), FakeClock, FakeScheduler, Test (head), valve.spec (head and MUTATION case), gateway.spec (head and harness), round.spec (head), manifest.spec (head), purity.spec (head), run.luau (head).
**Pattern extraction date:** 2026-11-05
