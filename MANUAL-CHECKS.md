# Manual Checks (D-04)

Phase 1 produced everything the automated chain can verify. These six checks need Roblox Studio or the Creator
Hub, which the build container does not have. **Phase 1 closes only when every box below is ticked.** Silence is
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

M-04's three command-bar checks (all unblocked now that the production id is live) — **2 of 3 passed, 1 unrun**:

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

3. In **`SPOONS [BETA]`**, re-sync this build and press **Play**: the server must refuse to boot with
   `Refusing real persistence: this is a Studio session and game.GameId matches the production
   universe id 10774453248`. This is the in-code tripwire firing for real; it was inert while
   `PRODUCTION_UNIVERSE_ID` was 0.

- [ ] M-04 signed off: <name> <date>   (isolation verified both ways; check 3, the boot tripwire, is unrun)

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

Observed: _

- [ ] M-05 signed off: <name> <date>

---

## M-06 (MAP-01) The gray-box map loads and reads sanely

**Why manual:** visual, in-engine.

1. Open `build/spoons.rbxl` in Studio and Play (watch the Output window for errors from `MapLoader`).
2. In Explorer confirm `ServerStorage.Maps.GrayBox` exists with `Geometry` and `Data` children.
3. Open View, Tag Editor. Select the tag `SpoonDefaultSpot` and use its visualiser: **18** tagged parts are listed.
   (`lune run scripts/maps/validate-map.luau maps/gray-box.rbxm` reports 18 spots and 9 seats; the contract minimum is 16.)
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

- [x] M-06 signed off: alejandrog_m 2026-11-03
