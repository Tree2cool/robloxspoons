# Manual Checks (D-04)

Phase 1 produced everything the automated chain can verify. These six checks need Roblox Studio or the Creator
Hub, which the build container does not have. **Phase 1 closes only when every box below is ticked.** Silence is
not success: `lune run scripts/verify.luau` prints every unticked check after a green run.

How to use this file:

- Do the checks in any order, except M-04 first if you want M-03 and M-06 to run against the dev experience.
- Tick a box by changing `- [ ]` to `- [x]` and filling in who and when. Keep the line format exactly
  (`- [ ] M-0x signed off: <name> <date>`); `scripts/verify.luau` parses it.
- Record anything surprising under the check ("Observed"), even when it passes.

Also an owner action: **the first green GitHub Actions run.** The build environment cannot push, so
`.github/workflows/ci.yml` has never run on the remote. After pushing a branch, confirm the `ci` workflow goes green
and record the run URL in `NEEDS_HUMAN.md`.

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

Observed: _

- [ ] M-01 signed off: <name> <date>

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

- [ ] M-02 signed off: <name> <date>

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

- [ ] M-03 signed off: <name> <date>

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

Observed (ids stay out of this file if you prefer; record them in `Environments.luau`): _

- [ ] M-04 signed off: <name> <date>

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

- [ ] M-06 signed off: <name> <date>
