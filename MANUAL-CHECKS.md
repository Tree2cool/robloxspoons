# Manual Checks (D-04)

Phase 1 produced everything the automated chain can verify. These nine checks need Roblox Studio, the Creator
Hub or a real playtest, which the build container does not have. Each check is owned by the phase that raised it:
M-01 to M-06 belong to Phase 1 (**Phase 1 closes only when those boxes are ticked**), M-07 to Phase 2's pacing
claim, and M-08 and M-09 to Phase 3's placement constants. Phase 3's closure depends on M-08 but not on M-09,
which needs a full-roster playtest that does not exist yet. Silence is
not success: `lune run scripts/verify.luau` prints every unticked check after a green run.

How to use this file:

- Do the checks in any order, except M-04 first if you want M-03 and M-06 to run against the dev experience.
- Tick a box by changing `- [ ]` to `- [x]` and filling in who and when. Keep the line format exactly
  (`- [ ] M-0x signed off: <name> <date>`); `scripts/verify.luau` parses it.
- Record anything surprising under the check ("Observed"), even when it passes.

~~Also an owner action: the first green GitHub Actions run.~~ **Closed 2026-11-03.** `ci.yml` has now
run on the remote and is green: six runs on `claude/happy-cerf-ughp67`, the latest being
[run 6](https://github.com/Tree2cool/robloxspoons/actions/runs/41582812758) on commit `3ea2af0`.
All fourteen verify steps appear as separate green steps in the job, so the workflow genuinely runs
the gates rather than merely exiting 0. This also settles the two things the build container could
not check: `actions/checkout@v7` resolves, and the SHA-pinned `CompeyDev/setup-rokit` installs the
pinned toolchain on a clean `ubuntu-latest` runner.

Prerequisites for everything below: Roblox Studio, Rokit (`https://github.com/rojo-rbx/rokit`), and a fresh clone:

```sh
git clone https://github.com/Tree2cool/robloxspoons && cd robloxspoons
rokit install
lune setup
mkdir -p build && rojo build default.project.json -o build/spoons.rbxl
```

`build/spoons.rbxl` is the built place used by M-02, M-03, M-05 and M-06.

---

## M-01 (FOUND-01) Rojo sync does not delete Workspace content

**Why manual:** needs a real Rojo to Studio sync.

1. In the clone run `rokit install`, then `rojo plugin install`. The plugin version must match the CLI (`rojo --version`
   prints 7.7.1). Rojo 7.7.0 switched the protocol to websockets and MessagePack, so a stale plugin cannot sync.
2. Run `rojo serve` and leave it running.
3. In Studio open an empty Baseplate, open the Rojo plugin and press Connect.
4. In the Explorer, add a Part to `Workspace` (Home tab, Part) and name it `SurvivalTest`.
5. Edit any file under `src/shared/Config/` (add a comment), save, and wait for the plugin to sync it.
6. Press Disconnect, then Connect again to force a full re-sync.

**Expected:** `Workspace.SurvivalTest` is still there after steps 5 and 6. This holds because `default.project.json` sets
`$ignoreUnknownInstances: true` on `Workspace` and gives it no `$path`. Code appears under `ServerScriptService.Server`,
`ReplicatedStorage.Shared` and `StarterPlayer.StarterPlayerScripts.Client`.

Observed: Passed on Windows 2026-11-03. Baseplate + rojo serve 7.7.1 (CLI and plugin matched;
the plugin's "a newer compatible version" notice was informational). A Part named `SurvivalTest`
added by hand in Workspace survived an edit-sync of `src/shared/Config/Round.luau` AND a full
Disconnect/Connect re-sync. Code appeared under the three mounts as expected.

- [x] M-01 signed off: alejandrog_m 2026-11-03

---

## M-02 (FOUND-03) `require` resolves in a real Studio server

**Why manual:** `scripts/ci/check-built-place.luau` re-resolves every require under Roblox's published rules, but only
Studio's own runtime can confirm those rules were read correctly.

1. Open `build/spoons.rbxl` in Studio (File, Open from File).
2. In `ServerScriptService` insert a new `Script` named `M02`, not part of the repo, with this body:

   ```lua
   local SpikeA = require(game.ServerScriptService.Server.engine.SpikeA)
   print("M02 value:", SpikeA.value)
   ```
3. Press Play (or Run) and read the Output window.

**Expected:** `M02 value: 42` and no `Requested module experienced an error while loading` or `is not a valid member`
message. `SpikeA` requires `SpikeB` by relative string, so a `42` proves require-by-string resolves in a server context.
Delete the `M02` script afterwards; do not save it.

Observed: _

Observed: PASSES 2026-11-03, Windows, Studio Play on the dev place. The server booted with no
`Unknown require` and no missing-member error: `[Spoons] persistence mode: Mock` (Main:24),
`map loaded: GrayBox` (Main:33), `server ready (round driver: true)` (Main:70), and the client
reached `client boot: Ping sent` (Main:7). Every relative string require therefore resolves under
Roblox's own rules, which is the half `check-built-place` could not prove.

- [x] M-02 signed off: alejandrog_m 2026-11-03

---

## M-03 (FOUND-04) A live client firing a bad payload is rejected

**Why manual:** needs a real client-server boundary. The exhaustive NaN, infinity, non-integer, over-long, extra-key and
missing-key cases live in `tests/net/validate.spec.luau` and `tests/core/gateway.spec.luau`; this proves the live remote
reaches that same validator.

`Ping` is validated by `exactKeys({ nonce = integer({ min = 0, max = 2^31 }) })`. The `nonce` field exists specifically so
a NaN is not bounced as an unknown key before it reaches the finite check.

1. Open `build/spoons.rbxl`, then Test, Start with one Server and one Player (or Play Solo and use the Server/Client toggle).
2. In the **Server** output, watch for `warn` lines. The server logs each rejection through `onReject` with the intent
   name and a code.
3. On the **Client**, open the command bar (View, Command Bar, with the Client context selected) and run these one at a time:

   ```lua
   local r = game.ReplicatedStorage:WaitForChild("Intent")
   r:FireServer("Ping", { nonce = 1 })        -- A: valid
   r:FireServer("Ping", { nonce = 0/0 })      -- B: NaN
   r:FireServer("Ping", { nonce = 0, extra = 1 })  -- C: unknown key
   r:FireServer("Ping", {})                   -- D: missing key
   r:FireServer("NotAnIntent", {})            -- E: unknown intent
   ```
4. Wait about 5 seconds so the rate bucket refills (`Ping` allows a burst of 2, refilling 1 per second), then run:

   ```lua
   for _ = 1, 10 do r:FireServer("Ping", { nonce = 1 }) end   -- F: flood
   ```

**Expected:**

| Fire | Result |
|------|--------|
| A | accepted: server prints the `Ping` userId and nonce, no rejection |
| B | rejected with code `NotFinite`, nothing dispatched |
| C | rejected, code `UnknownKey` |
| D | rejected, code `MissingKey` |
| E | rejected, code `UnknownIntent`, before any state is allocated |
| F | the first couple are accepted, then `RateLimited` rejections appear; the server stays responsive |

Record which row produced which code. B is the live proof of the NaN half of FOUND-04 and of phase success criterion 4.

Observed: _

Observed: PASSES 2026-11-03. A real client fired across the wire in a Studio Play session.
Accept path: `[Spoons] Ping from 3811489179 nonce=1`.
Rejections, each with its OWN distinct code (four different codes from four payloads, so the
gateway discriminates rather than merely refusing):
  - `{nonce = 0/0}`                 -> `NotFinite`   <- the one that matters
  - `{}`                            -> `MissingKey`
  - `{nonce = 1, extra = true}`     -> `UnknownKey`
  - intent `"NotAThing"`            -> `UnknownIntent`
`NotFinite` specifically confirms the required `nonce` field earns its place: a NaN survives
serialisation, passes the key check, and reaches the hand-written `isFinite` (hand-written because
Selene 0.32.0's luau std has no `math.isnan`). With `exactKeys({})` it would have bounced as
`UnknownKey` and proved nothing about NaN.

- [x] M-03 signed off: alejandrog_m 2026-11-03

---

## M-04 (FOUND-07) Separate test universe; production Studio API access is OFF

**OWNER-ONLY.** This is a Creator Hub step that only the experience owner can perform. It is the one check an
assistant must never attempt or assume.

Why a new *experience*: data stores are consistent per experience (universe), so a new place inside the production
experience is NOT isolation.

1. In Creator Hub create a **new experience** (for example "Spoons Dev"). Publish this project to it
   (`build/spoons.rbxl` opened in Studio, File, Publish to Roblox, choose the new experience).
2. Note the dev **Place ID** and **Universe ID** (Creator Hub, the experience's page, or `game.PlaceId` and `game.GameId`
   in the Studio command bar).
3. In the dev experience only: Experience Settings, Security, turn on **Enable Studio Access to API Services**.
4. In the production experience: confirm that same toggle is **OFF**.
5. Set the production place's **Maximum Players** to 10 (see M-05).
6. Record the ids:
   - the dev Place ID goes into `servePlaceIds` in `default.project.json` (so `rojo serve` refuses any other place),
   - both universe ids and the dev place id go into `src/shared/Config/Environments.luau`
     (`PRODUCTION_UNIVERSE_ID`, `DEV_UNIVERSE_ID`, `DEV_PLACE_ID`; they are all 0 until this is done).
   Plan 01-12 does this edit once you supply the numbers.

**Verification:**

- In the dev place, run a one-line DataStore write in the command bar:
  `game:GetService("DataStoreService"):GetDataStore("m04"):SetAsync("k", 1)`. It must **succeed**.
- Open the production place in Studio and run the same line. It must **fail** with `StudioAccessToApisNotAllowed`.
- With `PRODUCTION_UNIVERSE_ID` filled in, press Play from the production place: the server must refuse to boot with
  `Refusing real persistence: this is a Studio session and game.GameId matches the production universe id ...`.

Observed: 2026-11-03. **Both experiences now exist and both ids are recorded.**

| Role | Experience | GameId (universe) | PlaceId |
|------|-----------|-------------------|---------|
| production | `SPOONS [BETA]` | 10774453248 | 123236339661606 |
| dev | `Spoons Dev` | 10774461969 | 120922388251092 |

Both places were uploaded with **Save to Roblox As** after Studio's **Publish As** failed repeatedly
with a bare "Save failed" (creating the experience on the Creator Hub first and uploading into it
worked, so it was Studio-side, not an account restriction). "Enable Studio Access to API Services"
is ON for `Spoons Dev`.

Recorded in code, and now machine-checked rather than eyeballed: `Environments.luau` holds all three
ids with no zeros, `default.project.json` has `"servePlaceIds": [120922388251092]`, and
`tests/project/project.spec.luau` asserts that the two files agree, that no id is a placeholder zero,
that dev and production are different universes, and that `servePlaceIds` never names production.
Each of those assertions was mutation-proven to fail when its subject is broken.

M-04's three command-bar checks — **2 of 3 passed, the third deferred by owner decision**:

1. ~~In **`Spoons Dev`** the DataStore write must succeed.~~ **PASSED 2026-11-03.** Observed:
   `GameId 10774461969 -> WROTE | nil`. The line printed `game.GameId` alongside the result, so the
   pass is tied to the dev experience and cannot have come from the wrong place open in Studio.
2. ~~In **`SPOONS [BETA]`** the same line must **fail** with `StudioAccessToApisNotAllowed`.~~
   **FAILED then PASSED 2026-11-03.**

   First run: `GameId 10774453248 -> WROTE | nil`. The write to a production data store went
   through from Studio, so "Enable Studio Access to API Services" was still ON for production and
   FOUND-07's primary control was not in place. Worth keeping on the record: the in-code
   PersistenceMode tripwire would NOT have covered this, because it guards the server boot path and
   not a hand-run command-bar write. That is why D-13 makes the toggle the primary control.

   After turning the toggle off: `GameId 10774453248 -> REFUSED | 403: Cannot write to DataStore
   from studio if API access is not enabled.`, with Studio also logging
   `DataStoreService: StudioAccessToApisNotAllowed`. Refused, by the specific expected reason, in
   the experience named by its own printed GameId.

   One side effect of the first run is recorded deliberately: key `k` was written to the real
   production `m04` data store. Nothing reads that store, so it is inert, but it is a live
   production write and should be treated as one.

3. **DEFERRED by owner decision 2026-11-03.** In `SPOONS [BETA]`, press Play and confirm the
   server refuses to boot with `Refusing real persistence: ... matches the production universe id
   10774453248`.

   Why deferred rather than run: seeing it fire needs the new `PRODUCTION_UNIVERSE_ID` inside the
   production place, and `servePlaceIds` now makes `rojo serve` refuse production on purpose, so the
   only route is publishing a build over the live production place. That is a disproportionate
   action for a **secondary** control, given check 2 proved the primary one works and
   `PersistenceMode.decide` is unit-tested directly in `tests/core/persistence.spec.luau`. It will
   be exercised naturally at the first real deploy.

   Carried in `NEEDS_HUMAN.md`. What is NOT claimed: the tripwire has never fired in a live Studio
   session. Its logic is tested; its wiring to `game.GameId` in a real place is not.

Dev access re-confirmed after the production toggle was flipped, to rule out having traded one
problem for another: `GameId 10774461969 -> WROTE | nil`. The setting is per-experience, as expected.

**Scope of this sign-off:** the separate dev universe exists, all ids are recorded and machine-checked,
Studio writes succeed in dev and are refused in production with `StudioAccessToApisNotAllowed`. The
boot tripwire (check 3) is deferred and is NOT covered by this tick.

- [x] M-04 signed off: alejandrog_m 2026-11-03   (checks 1 and 2; check 3 deferred, see above)

---

## M-05 (FOUND-08) Place Maximum Players = 10 and an 11th join is refused

**Why manual:** `Players.MaxPlayers` is ReadOnly in script, so the cap is a **place setting**, and Studio's local
multi-client limit means the 11th-join behaviour needs a published place. The code-side kick path (`Admission`,
`PlayerGate`) is unit-tested.

1. Creator Hub, the place's settings, **Maximum Players** = 10 for both the dev and production places.
2. Join the published dev place with ten clients (friends, alts, or a Studio local server with the maximum client count
   the machine allows plus real devices).
3. Attempt an 11th join.

**Expected:** the 11th join is refused (by the platform at the cap, or kicked by `PlayerGate` with its full-server
message if it slips through). The server stays at 10 and keeps running.

Observed: 2026-11-03. Step 1 done — **Maximum Players = 10 on both places**, dev and production.

Steps 2 and 3 are **unrun**: they need ten simultaneous real clients, which the owner does not have
available. The code-side half of FOUND-08 is covered without them — `Admission` and `PlayerGate` are
unit-tested over the full boundary table (3-player minimum, 10-player cap, each refusal asserting its
own reason code), and the 11th-join refusal at the cap is platform behaviour, not our code.

**Scope of this sign-off:** the place setting is confirmed. An observed 11th-join refusal is NOT
claimed, and is carried in `NEEDS_HUMAN.md` for the first playtest that reaches ten players.

- [x] M-05 signed off: alejandrog_m 2026-11-03   (cap set on both places; 11th-join unobserved, see above)

---

## M-06 (MAP-01) The gray-box map loads and reads sanely

**Why manual:** visual, in-engine.

1. Open `build/spoons.rbxl` in Studio and Play (watch the Output window for errors from `MapLoader`).
2. In Explorer confirm `ServerStorage.Maps.GrayBox` exists with `Geometry` and `Data` children.
3. Open View, Tag Editor. Select the tag `SpoonDefaultSpot` and use its visualiser: ~~**18**~~ **21** tagged parts are listed.
   (`lune run scripts/maps/validate-map.luau maps/gray-box.rbxm` reports ~~18~~ **21** spots and 9 seats; the contract minimum is 16.)
4. Under `Data`, confirm the **9** seat anchors (`Seat1` to `Seat9`) ring the table anchor.
5. Confirm only `Geometry` was cloned into `Workspace` (`Data` must not appear there).
6. Walk the sightlines from the seeker spawn: at least some spots must be hidden from the nearest seeker spawn.

**Map edit workflow (record, do not skip):** a mounted `.rbxm` is Rojo-owned. Edit the map in Studio, then
**export over `maps/gray-box.rbxm`** (right-click the `GrayBox` model, Save to File, overwrite the file) and commit.
Otherwise the next Rojo sync overwrites your edit. After exporting, re-run
`lune run scripts/maps/validate-map.luau maps/gray-box.rbxm`.

Observed: _

Observed: PASSES 2026-11-03. `[Spoons] map loaded: GrayBox` with no per-map branch, and the
gray-box renders as designed: four rooms, perimeter walls, the card table centred. Loaded from
`ServerStorage.Maps.GrayBox`.
NOTE: the Workspace-contents half of this check (Geometry present; `Data` and `GrayBox` ABSENT,
which is the anti-ESP property) was not separately confirmed in the Explorer. Re-confirm when
convenient; `tests/maps/graybox.spec.luau` asserts it statically and `MapLoader` clones only
`Geometry`, but the live tree was not eyeballed.

2026-11-04 (Phase 3, plan 03-06): the signed observation above was made against the
ContractVersion 1 map with 18 default spots. That map no longer exists -- the reference map is now
ContractVersion 2 with 21 spots, every one of which passes the real placement rules
(`tests/placement/graybox_spots.spec.luau`). The steps above have been renumbered to 21. The
claim M-06 signs -- "the map loads and reads sanely" -- is unchanged, but it has NOT been
re-observed in Studio against the v2 map. `M-10` is that re-run.

- [x] M-06 signed off: alejandrog_m 2026-11-03

---

## M-07 (CARD-11) Calibrate the simulator's human model against a real playtest

**Why manual:** no simulation can answer it. Gate G1's **solvability** half is a theorem that does
not depend on the bot model at all. Its **pacing** half measures the bot, and two assumptions behind
that bot have never been checked against a person:

- **V-35** — whether a lognormal reaction-time distribution over roughly 250-900ms represents real
  players. Carried as Verification Debt since project init.
- **A4** — whether humans deviate from perfectly greedy play often enough to matter. Surfaced by
  Phase 2's research and never closed.

Phase 2 removed these from the critical path rather than resolving them: the anti-livelock valve
makes zero-stall a property of the engine instead of a bet on player behaviour, so a wrong human
model no longer breaks the game. It still makes the **pacing numbers** (median 16.2s to first
completion, p95 23.7s) claims about a simulated player rather than a real one.

1. At the first playtest that reaches a full roster, record time-to-first-completion per round.
2. Compare the distribution against the G1 report's confirm-stage figures for `k=3, j=1`.
3. Record how often a player passes a card the greedy policy would have kept.

**Expected:** the measured median sits inside the simulated p95. A large divergence means the
pacing half of G1 should be re-run with a corrected reaction model; it does **not** threaten
solvability.

Observed: _

- [ ] M-07 signed off: <name> <date>   (Phase 4/6 playtest; not blocking Phase 2)

---

## M-08 (HIDE-06 / D-18) The place's CharacterMaxSlopeAngle is at least 30

**Why manual:** it is a place setting outside the repo, like `Players.MaxPlayers` (M-05) and the FOUND-07
persistence toggle. Nothing in the repo can detect it being changed back.

Steps: open `build/spoons.rbxl` in Studio, select `StarterPlayer`, read `CharacterMaxSlopeAngle`. The platform
default is 89 and `src/shared/Config/Placement.luau` sets `MAX_SLOPE_DEGREES = 30`, so the default already
satisfies this. **Expected:** the value is at or above 30. If it is ever lowered below 30, the live game will
refuse a slope the validator accepted and a validated spot on the graybox ramp becomes unreachable in play.
Record the observed value even when it passes.

**Blocking: yes for Phase 3's close.** It is a one-reading check against a value that already defaults correctly.

Observed: _

- [ ] M-08 signed off: <name> <date>   (Studio reading; blocking Phase 3)

---

## M-09 (HIDE-07 / D-10) The reference capsule covers real avatars at the scale extremes

**Why manual:** V-19 is only partly primary-sourced. The per-axis avatar scale limits, the R15 default
`HipHeight` and any camera-height formula were **not found in primary documentation**; the 90-105 percent height
and 70-100 percent width figures come from a web-search summary (assumption A6). D-10 makes placement validity
scale-**independent** by construction (the rule function takes no avatar argument), but the canonical capsule's
dimensions are only exact for avatars inside that envelope, and Avatar Settings' Custom Scale or a script can
leave it.

Steps: at the first playtest that reaches a full roster, stand avatars at the scale extremes beside a validated
default spot on the graybox and confirm each can reach the spoon. Also record whether the place uses Player
Choice or Custom Scale in Avatar Settings.

**Expected:** every avatar in the place's envelope can reach a validated spot. Until this is signed off, D-11's
bias toward rejecting is the mitigation, not a verification. A failure means the capsule is too permissive in
the reach direction and `REACH_HEIGHT` must come down.

**Blocking: no for Phase 3.** It needs a Phase 4/6 playtest. Carried, not deferred silently.

Observed: _

- [ ] M-09 signed off: <name> <date>   (Phase 4/6 full-roster playtest; not blocking Phase 3)
