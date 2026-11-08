# Manual Checks (D-04)

Phases 1 to 4 produced everything the automated chain can verify. These seventeen checks need Roblox Studio, the
Creator Hub, a real phone or a real playtest, which the build container does not have. Each check is owned by the
phase that raised it:
M-01 to M-06 belong to Phase 1 (**Phase 1 closes only when those boxes are ticked**), M-07 to Phase 2's pacing
claim, and M-08, M-09 and M-10 to Phase 3. M-08 and M-09 check placement constants; M-10 is different in kind: it is
the only check covering a gap CI cannot close (runtime versus CI snapshot values), not a check on an out-of-repo
setting. Phase 3's closure depends on M-08 and M-10 but not on M-09, which needs a full-roster playtest that does not
exist yet.

**M-11 to M-17 belong to Phase 4 (Live Card Table). M-11, M-12, M-13, M-14, M-15 and M-17 are blocking for Phase 4's
close; M-16 is not** (a missing audio id is silent by contract and the suit pips ship with a marked placeholder).
Note that four of Phase 4's five ROADMAP success criteria are device-dependent, and the build container has neither
Studio nor a phone, so these rows are the phase's real evidence rather than a formality. They were written in plan 04-02,
before any UI wave was executed, so that nothing device-dependent can be ticked by a machine. M-11 is the
highest-risk row in the phase. Silence is
not success: `lune run scripts/verify.luau` prints every unticked check after a green run.

**Phase 4 close block (written by plan 04-20; nothing below is ticked, and no machine may tick it).**
Phase 4 is **not complete** until M-11, M-12, M-13, M-14, M-15 and M-17 are signed by a human. What a failure of each
would mean for the requirement it carries:

| Row | Blocking | Carries | A failure means |
|-----|----------|---------|-----------------|
| M-11 | yes (highest risk) | UX-02, **UX-04**, D-29, D-30 | controls do not hide, or do not come back, or the avatar hold holds nothing: a finisher is held still and loses find-order score, or a seated player can walk away. Fallbacks D-04-10, D-04-11, D-04-12 only |
| M-12 | yes | UX-01, UX-03, D-36, CARD-13 | targets are not 48 px on glass, are unreachable by a thumb, sit under the notch or top bar, the strip wraps at Largest text, or a second client can see a hand that is not its own |
| M-13 | yes | CARD-14, CARD-02, CARD-15 | the card is not visibly gone within a frame at 150-300 ms, a return reads as a teleport, or a rejection is distinguishable from a correction |
| M-14 | yes | CARD-19, D-24 | spade and club (or any pair) are not reliably distinguishable in greyscale: the colour-blind half of CARD-19 is unmet. Enlarge the pip or thicken the silhouette, never lean on colour |
| M-15 | yes | D-28, D-29 note | landscape is not locked or the IAS flag is left at `Default`, which flips the player scripts under the project in early 2027 with no commit |
| M-16 | **no** | CARD-19, D-33 | audio is silent by contract and the pip sprite is a marked placeholder; a missing Builder Sans weight is a blocker to raise, not a font to substitute |
| M-17 | yes | CARD-02, CARD-15, CARD-17 (+ M-07 evidence) | the starting gun does not read as one, the finisher is not running before the flourish ends, or the fumbled double-tap (D-03) does something worse than expected |

Requirements UX-01, UX-02, UX-03 and UX-04 are **not met by any plan**; they are met only by these rows. Do not run
`requirements.mark-complete` for Phase 4.

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

Observed: **PASSES 2026-11-04.** `StarterPlayer.CharacterMaxSlopeAngle = 89` in `build/spoons.rbxl`,
read in Studio. That is the platform default and the project sets no override, so it clears the
`MAX_SLOPE_DEGREES = 30` requirement with 59 degrees of headroom. Recorded as the check asks even
though it passes: nothing in the repo can detect it being lowered later.

- [x] M-08 signed off: alejandrog_m 2026-11-04   (Studio reading; blocking Phase 3)

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

---

## M-10 (MAP-02 / D-02) The v2 reference map loads through MapLoader and validates in Studio

**Why manual:** this is the only check that can observe **value-level** parity between the two snapshotters.
`MapLoader` reads a live `ServerStorage.Maps.GrayBox` tree through Roblox APIs and cannot run under Lune, so CI can
compare the two snapshotters' **key sets** (gate 8) but never the values they emit from the same input. The structural
limit is real; this is the gate that covers it. It also re-runs M-06 against the ContractVersion 2, 21-spot map, since
M-06 was signed against the version 1, 18-spot map.

Steps: build and open the place (`mkdir -p build && rojo build default.project.json -o build/spoons.rbxl`), Play, and
watch the Output window. Then, in the Explorer: confirm `ServerStorage.Maps.GrayBox` exists with `Geometry` and `Data`;
confirm only `Geometry` was cloned into `Workspace` (`Data` and `GrayBox` must be **absent** there, the anti-ESP
property M-06's note records as never having been eyeballed); and in View > Tag Editor confirm the `SpoonDefaultSpot`
visualiser lists **21** tagged parts.

**Expected:** `[Spoons] map loaded: GrayBox` with **no** error from `MapValidator`. `MapLoader` runs the same
`MapValidator.validate` over its **own** snapshot of the live tree, against the same `Config.Placement` values, so a
value-level disagreement between the two snapshotters large enough to change any verdict surfaces here as a validation
failure naming an issue code, immediately and loudly, rather than as a map that is subtly different in play. A silent,
clean load is the evidence.

**Blocking: yes for Phase 3's close.** It is the same Studio session as M-08, so it costs nothing extra, and the thing
it covers is the one named structural gap in the phase's evidence.

Observed: **PASSES 2026-11-04.** Studio, `build/spoons.rbxl`, same session as M-08.
1. Output carried `[Spoons] map loaded: GrayBox  -  Server - Main:33` with **no `MapValidator`
   error**, between `persistence mode: Mock` and `server ready (round driver: true)`. A clean load
   is the evidence: `MapLoader` ran the same `MapValidator.validate` over its own snapshot of the
   live tree against the same `Config.Placement`, so no value-level disagreement between the two
   snapshotters is large enough to change a verdict.
2. `ServerStorage.Maps.GrayBox` present with both `Geometry` and `Data` (command bar, Edit mode:
   `GrayBox: yes | Geometry: yes | Data: yes`).
3. **`Workspace` held `Geometry` only — `Data` and `GrayBox` both absent.** This is the anti-ESP
   property (CLAUDE.md rule 3) and M-06's note records it as never previously eyeballed; this is
   its first direct observation. `Workspace.Geometry` showed `Lobby`, `Perimeter`, `Rooms`,
   `Core`, `CrateEastHall`, `CrateNorthEastRoom`, `CrateSouthWestRoom`, `Floor`, `Ledge`,
   `PillarEast`, `PillarWest`, `Ramp`, `ShelfSouthEastRoom` — `CrateNorthEastRoom` confirms the
   v2 map, since plan 03-06 added it for the fourth spot height.
4. `CollectionService:GetTagged("SpoonDefaultSpot")` returned **21**. (Used in place of the Tag
   Editor visualiser, which this Studio build does not list under View.)

Note: `ServerStorage` reads as EMPTY in the Explorer while Playing, because it does not replicate
to clients — that is the anti-ESP property working, not a missing map, and `MapLoader.luau:91`
would have thrown `ServerStorage.Maps does not exist` otherwise. An unrelated Studio warning,
`rbxassetid://203785492 ... Asset type does not match requested type`, is not from this repo.

- [x] M-10 signed off: alejandrog_m 2026-11-04   (Studio; blocking Phase 3)

---

## Phase 4 session plan — suggested order, and what blocks what

The seven sections below are self-contained. This is only the **order that wastes least time**, plus
the traps that are easy to hit. Owner decision 2026-11-07: the owner signs these personally.

**Do these two first — everything else is cheaper afterwards.**

1. **M-15 (Creator Dashboard + Studio, ~10 min).** Lock landscape, and **pin
   `Workspace.PlayerScriptsUseInputActionSystem` explicitly** rather than leaving it `Default`.
   Do it first for two reasons: **M-11's matrix requires toggling that flag**, so you need to know
   where it is, and **M-12 needs landscape already locked** or you are measuring the wrong layout.
2. **M-16 (asset upload, non-blocking).** Audio ids all ship **empty — silent by contract, not
   broken** — and the suit pips ship as a *marked placeholder*. Uploading before M-14 and M-17 means
   you judge the real thing rather than placeholders. If a Builder Sans weight is missing, that is a
   **blocker to raise, not a substitution**: `Enum.Font.Gotham*` was removed from the platform and
   maps to Montserrat, which would silently change the typeface and invalidate every glyph-width
   figure in the UI-SPEC.

**Then the desk work.**

3. **M-14 (greyscale, desk, ~15 min).** No phone needed. The automated side already proves all 50
   identity keys map to 50 distinct drawn assets; what a machine cannot judge is **legibility**.
   **Expect spade vs club at 16 px to be the hardest pair** — that is the one to look at first. Also
   check the joker corner star, which ships at `TEXT_SIZE.BODY` (20) rather than the UI-SPEC's 24,
   because `CardTheme` has no 24 and adding one collides with the geometry scan.

**Then the device work, in one Studio session if you can.**

4. **M-11 — the highest-risk row, and the one most likely to fail. Budget real time.**
   6 cells (IAS Disabled/Enabled x PC/phone/gamepad) plus 4 separately-recorded cheat-client attempts.
   **Do not tick on cell (a) `TouchControlsEnabled` alone** — that is a UI toggle, not an exploit. The
   owning client simulates its own character, so (b) `WalkSpeed`, (c) `Humanoid:Move` and (d) a
   `CFrame`/`PivotTo` write are the ones that matter. **`Dev*MovementMode = Scriptable` is documented
   to disable the default control scripts, which is NOT the same as refusing a `Move` call.**
   **Watch for stuck-touch and held-key bugs on re-enable** — community reports describe exactly that,
   and it is why the project does not claim the hold "prevents" anything (T-4-107 is
   `mitigate, UNPROVEN`).
   **If it fails, three fallbacks are pre-recorded and ordered** (`deferred-items.md`): D-04-10 a
   next-frame `TouchControlsEnabled` retoggle; D-04-11 gamepad degrading to the Mouse hint set (a
   one-line data change); D-04-12 `Humanoid.Sit` on converted seat Parts — **which is a Phase 6
   map-contract change, not a hot fix.** Do not improvise a fourth.
5. **M-12 (real phone, landscape).** Targets on glass, thumb reach, the notch and top bar, and the
   strip at `PreferredTextSize = Largest`. Two specific things to look at: the **12 px overhang** of a
   lifted card is deliberately not hit-tested (tapping it selects the neighbour — accepted, because
   widening it would drop the neighbour below 48 px), and **whether `readViewport` double-counts
   insets** under `CoreUISafeInsets` is an open question recorded in the `CardHud` header.
6. **M-13 (Studio, simulated lag).** 150–300 ms. The automated side proves *convergence*; what you
   are judging is whether it **feels** immediate, whether a return reads as a return rather than a
   teleport, and that a rejection is **indistinguishable** from a correction (D-12 — a legitimate
   player must never be able to tell). This is also where **D-03's accepted residual** is observed: a
   fumbled fast double-tap **will** send a card, deliberately.
7. **M-17 (three clients).** The starting gun, and the finisher **running before the flourish ends**.
   This also supplies the only evidence for **M-07 / V-35** — whether the bot reaction-time model
   resembles humans — which is the open half of why the 8.0 s deadline was chosen at all (D-39).

**One thing to verify that no section owns**, because it was found at integration and is
source-checked only: **after a round ends without removing your seat, do your movement controls come
back?** `endRound` now publishes a `RoundEnd` kind for exactly this, but `CardService` cannot be
loaded headlessly, so the fix is unproven. On a phone a failure looks like having no movement
controls at all.

---

## M-11 (UX-02 / D-29, D-30) Control hide and restore, under both Input Action System settings

**Why manual:** this is the highest-risk row in Phase 4. `require(PlayerScripts.PlayerModule):GetControls()` is
undocumented and on a staff-announced removal path (V-26), and no replacement is proven under the Input Action System
(IAS). The documented replacements (server-set `Player.DevComputerMovementMode` / `DevTouchMovementMode = Scriptable`,
client-set `GuiService.TouchControlsEnabled = false`, and a higher-priority sinking binding for keys) have never been run
in this project. Only a real input device and a real Studio session can show whether the controls come back cleanly.

Matrix: rows = `Workspace.PlayerScriptsUseInputActionSystem` set **Disabled**, then **Enabled**; columns = PC keyboard,
phone touch, gamepad. For **every** cell:

1. While seated, `Controls.hide()` leaves **no thumbstick or jump graphics** and produces no movement from touch or
   `W/A/S/D` / the left stick.
2. `Space` (or the gamepad jump button) does not jump.
3. `Controls.restore()` **while `W` is held**, and again **while a thumb is down**, resumes movement within one second
   *without* releasing and re-pressing.
4. Record the measured seat-release-to-first-controllable-frame time.

Watch for the three community bug reports: a held key that does not resume after re-enable, a stuck jump button, and a
dead thumbstick after `TouchControlsEnabled` is restored.

**Cheat-client cell, four separately recorded attempts.** `Dev*MovementMode = Scriptable` disabling the default control
scripts is **not** the same as the server refusing a `Move` call, so a hidden control is not a held avatar. From a
client-side executor or the Studio command bar on the client, while the avatar is held, attempt each of these and record
the result of **each one on its own line**:

- (a) `GuiService.TouchControlsEnabled = true`: expected to show the thumbstick again, which is cosmetic only.
- (b) `Humanoid.WalkSpeed = 16`: expected to leave the avatar in place because the server owns the hold.
- (c) `Humanoid:Move(Vector3.new(0, 0, -1))`: expected to leave the avatar in place.
- (d) a `CFrame` / `PivotTo` write on the character: expected to be corrected or ignored by the server.

**Ticking this check on attempt (a) alone is forbidden.** (a) only shows the control graphics, and says nothing about
whether the avatar can actually be moved.

**Expected:** every matrix cell passes, or a failing cell has a **written fallback**. If layer (b) (`Dev*MovementMode`)
fails under IAS, the recorded fallback is layer (a) alone (the server avatar hold) plus (c) and (d), because nothing in
the default scripts is mutated and so there is nothing to restore. A failing cell with no written fallback is not
acceptable.

**Blocking: yes for Phase 4's close.** It is the phase's highest-risk row.

**Server hold (plan 04-15).** The server sets `Dev*MovementMode = Scriptable`, a zeroed humanoid and a `PivotTo` on seating
(assumption A2, unverified; whether this holds anything is what these rows find out). Record each on its own line, under
**both** `PlayerScriptsUseInputActionSystem` settings:

1. A seated seeker still cannot move with a thumbstick, with `W/A/S/D`, with a gamepad stick, or by jumping.
2. The avatar sits at the seat anchor facing the table with **no sliding and no physics jitter** (A2's named failure mode).
3. **Respawn while seated**: the avatar returns to the seat and is still held.
4. On completion the avatar is controllable **within one second**; record the measured seat-release-to-first-controllable-frame
   time. The overlay is gone in the same frame, and the flourish visibly plays **around** a player who is already running
   (D-30, D-31).
5. **Cheat-client cell, the only cell that can show whether this layer holds anything.** From the **client** command bar while
   seated, try each in turn and record each separately (this is the same four-attempt cell as above, restated for the hold):
   - (a) `game:GetService("GuiService").TouchControlsEnabled = true`: does the thumbstick return, and does it move the avatar?
   - (b) `game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = 16`: does the server's value win, and how quickly?
   - (c) `game.Players.LocalPlayer.Character.Humanoid:Move(Vector3.new(0, 0, -1), false)`: a move request that bypasses the
     control scripts. `Scriptable` is documented to disable the default *controls*, which is not the same as refusing a `Move`
     call, so this is the sharpest test of the chosen mechanism.
   - (d) `game.Players.LocalPlayer.Character:PivotTo(CFrame.new(0, 10, 0))` and a direct `HumanoidRootPart.CFrame` write:
     does the avatar move, is it corrected, and how far does it get first?

   **Expected:** the avatar does not leave the seat, or is returned within a fraction of a second. **If any of b, c or d
   succeeds, the chosen mechanism does not hold the avatar** and the fallbacks apply in order: a seated state on a converted
   seat Part (a Phase 6 map-contract change), then a server-side position check returning a wandering avatar to its anchor.
   Do not tick M-11 on cell (a) alone; it only tests the cosmetic layer.
6. Record which mechanism passed, so the rejected list in `CardService.luau`'s header can be narrowed.

Observed:

### M-11 step 7 — UX-04: hints follow the LAST INPUT ACTUALLY USED (added 2026-11-07)

**Why this step exists:** the Phase 4 verifier found UX-04 had **no human path at all**.
`04-VALIDATION.md` assigned its human half to "the M-11 gamepad column, V-27", but M-11's procedure
only ever covered control hiding and the avatar hold — **nothing here tested hints**. `hints.spec`
proves the copy table and the input map are complete; it cannot prove the strip follows
`UserInputService.LastInputTypeChanged` on a real device. **The owner cannot sign a check that was
never written**, so this is it.

On **one** device that has more than one input available (a touchscreen laptop, or a phone with a
paired mouse or controller), while seated at the card table:

1. Use **touch**, then confirm the strip's hint wording is the touch form ("Tap...").
2. Use a **mouse**, then confirm it switches to the mouse form ("Click...") **without a reload**.
3. Use the **keyboard**, then confirm it switches to the keyboard form.
4. Use a **gamepad**, then confirm either the gamepad form appears **or** it degrades to the Mouse
   hint set — **D-04-11 records that degradation as an accepted fallback** if V-27 cannot be
   confirmed. Record which happened.
5. Confirm the switch is driven by **the last input actually used**, not by device type at join
   (D-09): a phone with a paired mouse must show mouse wording once the mouse is used.

**Fail means:** UX-04 is unmet — a player sees instructions for an input they are not using.

- [ ] M-11 step 7 (UX-04 hint switching) observed: <name> <date>

- [ ] M-11 signed off: <name> <date>

---

## M-12 (UX-01, UX-03 / D-36) Real phone, landscape: targets on glass, safe area, Largest text

**Why manual:** physical target size, thumb reach, the notch and the Roblox top bar, and rendered text width at the
largest text setting are device and setting dependent. The Studio device emulator does not prove any of them.

Steps: on a real notched phone in landscape, open the card table and confirm:

1. Every card slot, the left pile and the right pile measure **>= 48 physical px** on glass.
2. The fan and both piles are reachable with thumbs at rest, without shifting the grip.
3. Nothing interactive sits under the notch or the Roblox top bar, with `ScreenInsets = CoreUISafeInsets`.
4. Set Settings > Text Size to **Largest** and confirm every status-strip string stays on **one line**.
5. **Added 2026-11-08, carried over from M-16: confirm the four suit glyphs still render on this
   device.** M-16 step 2 says "on a phone" and was answered in Studio on Windows, which is not the
   same claim -- Roblox falls back per glyph to a system font, and Windows ships suit symbols where a
   phone may not. If any pip is a blank or a box here, M-16's sprite-sheet escalation is live and
   M-14's greyscale judgement was made against glyphs that do not ship. This step is the only place
   that risk is caught.

Record the device model, its physical resolution, and the measured status-strip width.

**Expected:** all four hold. A tight-but-passing strip is recorded with its measured width so a later copy change has a
baseline.

**Blocking: yes for Phase 4's close.**

Observed:

- [ ] M-12 signed off: <name> <date>

---

## M-13 (CARD-14) Prediction feel at 150-300 ms simulated lag

**Why manual:** virtual time in the headless suite proves that the client and server converge, not what it *feels*
like. Only a human watching a real client under real latency can judge whether a correction looks like a glitch.

Steps: with Studio's network latency simulation (or the debug send-delay flag if the setting cannot be found), set
150 ms, then 300 ms, and:

1. Commit a pass: the card is visibly gone **within one frame**.
2. Cause a server correction: it is a smooth return with **no teleport**.
3. Cause a hard rejection: it looks **identical** to a correction, with no message, no sound and no colour flash (D-12).
4. Fumble a fast double-tap, and record what happens, so D-03's accepted residual is observed rather than assumed.

**Expected:** 1 to 3 hold at both latencies; 4 is recorded whatever it shows.

**Blocking: yes for Phase 4's close.**

Observed:

- [ ] M-13 signed off: <name> <date>

---

## M-14 (CARD-19 / D-24) Greyscale render of all 50 faces

**Why manual:** the automated test proves face-key injectivity, not human legibility. Legibility at fan size is a
judgement about a rendered image.

Steps: render the fan-size corner index of all 12 ranks x 4 copies, plus the joker in both modes, in a grid with
`ColorCorrectionEffect.Saturation = -1`, at the reference viewport **and** on a real phone. A reviewer must be able to
name each rank and copy. Also measure glyph-versus-face luma contrast for both the black and the red pip.

**Spade versus club at 16 px is the expected hardest pair.** If they are not reliably distinguishable, enlarge the pip
to 20 or thicken the club silhouette. Never lean on colour.

**Expected:** all 50 faces named correctly in greyscale by someone who did not build them, on both surfaces.

**Blocking: yes for Phase 4's close.**

Observed:

- [ ] M-14 signed off: <name> <date>

---

## M-15 (D-28 / D-29 note) Landscape lock and the IAS flag pinned explicitly

**Why manual:** both are Creator Dashboard or place settings, which no repo change can set. The IAS flag is the
dangerous one: left at `Default`, the player scripts flip underneath the project in early 2027 with no commit to blame.

Steps:

**CORRECTED 2026-11-08.** The original wording sent you to the Creator Dashboard for orientation and to
"both places". Both were wrong. Orientation is a **DataModel property set in Studio**, not a Dashboard
setting — verified against primary docs (`StarterGui.ScreenOrientation`, `ScreenOrientation.md`,
`last_updated 2026-11-06`). The Dashboard has **Supported Devices** (which device *classes* may play),
which is a different setting that **Phase 8 owns** under UX-06. And production must **not** be touched
now: `servePlaceIds` is pinned to the dev place (D-23) so Rojo cannot reach production, prod still runs
Phase 1-3 code with no card UI to orient, and setting it would mean publishing Phase 4 over the live
place — which D-23 already declined once as not worth a production publish.

**Do all of this on `Spoons Dev` only (PlaceId 120922388251092). Production's settings belong to Phase 8.**

Steps, in Studio, both in the Properties panel:

1. Select **`StarterGui`** in the Explorer and set **`ScreenOrientation` = `LandscapeSensor`** (landscape
   with either side up). The default is `Sensor`, which follows the device freely — so leaving it alone
   is **actively wrong** for this layout, not merely unset.
2. Select **`Workspace`** and set **`PlayerScriptsUseInputActionSystem` explicitly to `Disabled`** — not
   left at `Default`. This is the dangerous one: at `Default` the player scripts flip underneath the
   project in **early 2027** with no commit to blame. Re-run M-11 under `Enabled` before launch.
3. **Save and publish to `Spoons Dev`.** These are place properties: they travel with the published
   place, not with your Studio session.
4. Record whether Rojo 7.7.1 can set each via `$properties`. **`StarterGui.ScreenOrientation` is an
   ordinary DataModel property, so it probably CAN** — in which case step 1 becomes code and stops
   being a human gate. The IAS flag probably cannot: it is newer than Rojo 7.7.1's pinned reflection
   database. Answer both either way.

**Leave the Studio API access toggles alone:** ON for `Spoons Dev`, OFF for `SPOONS [BETA]`. That is
FOUND-07's primary isolation control, and Phase 1 found it set the wrong way on production and fixed it.

**Expected:** `Spoons Dev` landscape-locked via `StarterGui.ScreenOrientation = LandscapeSensor`; the IAS flag explicitly `Disabled`; both published to dev; the Rojo `$properties` question answered for each. Production untouched until Phase 8.

**Blocking: yes for Phase 4's close.**

Observed:

**Steps 1 and 2 done on `Spoons Dev` 2026-11-08.** `game.StarterGui.ScreenOrientation` reads
`Enum.ScreenOrientation.LandscapeSensor` from the command bar.
`Workspace.PlayerScriptsUseInputActionSystem` reads **`Disabled`** in the Properties panel — the
command bar cannot print it (`lacking capability RobloxScript`), because the property is
`RobloxScriptSecurity` *to scripts*. That is a script-security level, not a Studio-editor
restriction: the IAS rollout guide itself says to set it from the Properties window, which is what
was done. **Read this one in the Properties panel, never by printing it.**

**Step 4 answered 2026-11-08 — Rojo 7.7.1 can set BOTH.** Measured, not assumed: built a throwaway Rojo
project per property and read the bytes out of the resulting `.rbxl`.

| Property | Rojo `$properties` | Written value in the built place |
|----------|--------------------|----------------------------------|
| `StarterGui.ScreenOrientation` | **yes** | `ScreenOrientation">2` (= `LandscapeSensor`) |
| `Workspace.PlayerScriptsUseInputActionSystem` | **yes** | `PlayerScriptsUseInputActionSystem">1` (= `Disabled`) |

So the prediction in step 4 was half wrong: the IAS flag is *not* missing from Rojo 7.7.1's
reflection database. A deliberately bogus property name made the same build **exit 1 with a stack
trace**, which proves Rojo validates names against that database rather than silently dropping an
unknown one — so the two successes above are real writes, not no-ops.

Caveat, untested: `rojo build` writing a property is not the same as `rojo serve`'s plugin applying
it to a live session. The plugin runs under plugin security, so the IAS flag may fail to apply live
even though the built file carries it correctly. If step 1-2 are ever moved into
`default.project.json`, verify by checking the Properties panel after a sync, not by assuming.

- [x] M-15 signed off: alejandrog_m 2026-11-08

---

## M-16 (CARD-19, D-33) Owner assets: audio ids, suit pips, Builder Sans weights

**Why manual:** audio asset ids and any sprite upload are owner-uploaded assets, and font availability is a property of
the Roblox platform that this container cannot query.

Steps:

1. Supply the three audio asset ids (completion sting, own draw, own pass) into the `AUDIO` table in
   `src/shared/Config/Card.luau`. An **empty id must stay silent, never an error.**
2. Confirm the four suit glyphs render at 16 px in Builder Sans on a phone. If any is missing or ugly, upload the
   4-cell sprite sheet.
3. Confirm Builder Sans **Regular and Bold** both exist. **`Enum.Font.Gotham*` has been removed and maps to
   Montserrat, so there is no fallback**: unavailability is a blocker to raise, not a substitution to make.

**Expected:** ids supplied (or deliberately left silent), glyphs legible, both weights present.

**Blocking: no.** A missing audio id is silent by contract and the suit pips ship with a marked placeholder. A missing
font weight is the exception: raise it as a blocker.

**HOW TO DO IT (added 2026-11-08; the steps above are unchanged).**

**Do step 3 before step 2.** Step 3 gates step 2: if a Builder Sans weight is missing, every glyph
judgement is being made in the wrong typeface. And step 3 is the only part of M-16 that can produce a
blocker.

Steps 2 and 3 are one look. Paste this into the Studio **command bar** (View -> Command Bar) on
`Spoons Dev`, press **Play (F5)**, look, press **Stop**, then **delete `StarterGui.M16Probe`**.
`default.project.json` does not mount `StarterGui`, so Rojo will neither manage nor remove the probe
and it would otherwise ship with the next publish.

```lua
local old = game.StarterGui:FindFirstChild("M16Probe")
if old then old:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "M16Probe"
gui.IgnoreGuiInset = true
gui.Parent = game.StarterGui
local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(245, 240, 225)
bg.Parent = gui
local suits = utf8.char(0x2660) .. " " .. utf8.char(0x2665) .. " " .. utf8.char(0x2663) .. " " .. utf8.char(0x2666)
local y = 24
for _, weight in { Enum.FontWeight.Regular, Enum.FontWeight.Bold } do
	for _, size in { 16, 20, 28 } do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(24, y)
		label.Size = UDim2.fromOffset(820, size + 8)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextSize = size
		label.TextColor3 = Color3.fromRGB(24, 24, 30)
		label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", weight)
		label.Text = `{weight.Name} {size}px   {suits}   A K Q J 10 7 4 2 5 3 9 8`
		label.Parent = bg
		y += size + 14
	end
end
print("M16Probe added under StarterGui. Press Play (F5) to view it, then DELETE it.")
```

The six rows are the two weights at the three sizes `CardTheme.TEXT_SIZE` actually defines
(`LABEL = 16`, `BODY = 20`, `HEADING = 28`), on the cream face colour, with the four suit codepoints
and the full `RANK_LADDER` from `Faces.luau`. Read it as:

| What to look for | Verdict |
|------------------|---------|
| Bold rows visibly heavier than Regular rows | **step 3 passes.** Identical weight means one fell back: **raise it as a blocker**, do not substitute a font |
| All four suit symbols appear as suit shapes | **step 2 passes** on presence |
| Blank gaps or `.notdef` boxes where a suit should be | the glyph path is unusable: upload the sprite sheet (below) |
| Spade vs club tellable apart on the 16px row | the pair M-14 flags as hardest. If not, M-14's remedy applies: enlarge the pip or thicken the club silhouette, **never lean on colour** |

**Step 2's escalation, if the glyphs fail.** This is already built; it is two one-line edits, not new
code. `CardFace.luau` creates both a glyph `TextLabel` and a sprite `ImageLabel` for every pip and
shows exactly one, chosen by `Faces.PIP_SOURCE`:

1. Upload a **1x4 sprite sheet, 256x64, cells 64x64** in the order **spade, heart, club, diamond** —
   that order and geometry are what `Faces.makePip` already computes
   (`sprite = { x = (index - 1) * 64, y = 0, w = 64, h = 64 }`), so a sheet in a different order
   silently mislabels every card.
2. Set `SPRITE_SHEET` in `src/client/ui/CardFace.luau:75` to the `rbxassetid://` id.
3. Set the single `PIP_SOURCE` local in `src/shared/Card/Faces.luau` (declared just above
   `RANK_LADDER`) from `"glyph"` to `"sprite"`. That one local feeds both the renderer's
   `Faces.PIP_SOURCE` and the audited `Faces.TABLES.pipSource`.
4. Re-run `lune run tests/run.luau`. It must stay green: the escalation is a supported state, not a
   change the suite resists.

While `SPRITE_SHEET` is `""` the sprite path draws a **visible box** in `CARD_BACK_PATTERN`, not
nothing, so a forgotten upload cannot pass as a rendered pip. The greyscale distinctness gate reads
whichever path `PIP_SOURCE` selects, so flipping to `"sprite"` makes the automated suite assert the
four `ImageRectOffset`/`ImageRectSize` pairs instead of the four codepoints -- it does not go
unchecked.

**Two defects on this escalation path were fixed on 2026-11-08, before anyone walked it.** Both were
found by walking it rather than by reading it. (1) `PIP_SOURCE` and `TABLES.pipSource` were two
separate `"glyph"` literals, so flipping one left the renderer drawing sprites while the greyscale
gate went on asserting the distinctness of four codepoints -- green over an unchecked renderer. They
are now one local, with a drift test. (2) The `MUTATION: pointing two pip ids at the same drawn asset`
test inherited the shipped value instead of stating which source each arm was about, so the flip this
step asks for turned it red for no real reason -- a false blocker sitting directly in step 2's path.
Each arm now sets `pipSource` explicitly. Verified by mutation in both directions: splitting the
literals again fires the new gate alone, a real glyph collision in the source still fires the old
ones, and the suite is green under `"glyph"` and `"sprite"` alike.

**Step 1's audio.** The three ids in `Config.Card.AUDIO` (`STING`, `DRAW`, `PASS`) are `""`, and
`CardAudio.makeSound` returns before constructing a `Sound` for an empty id, so **no Sound instance
exists and the play call returns immediately**: silence is the designed state, not a defect. Two
platform facts worth knowing before uploading:

- Uploaded audio is **private to the uploader by default**. Upload from whichever account or group
  owns universe `10774461969`, or the Sound will not play in `Spoons Dev`.
- Audio goes through **moderation** after upload, so an id can be valid and still silent for a while.
  That is indistinguishable from an empty id at the UI, which is the reason this row is non-blocking.

Own-action sounds are capped at `AUDIO.OWN_CAP_SECONDS = 0.12` so a long asset cannot smear into the
next action, and `AUDIO.VOLUME = 0.3`. Pick short assets: a 2-second sting will be cut to 0.12s.

Observed:

**Steps 2 and 3 pass in Studio on `Spoons Dev` (Windows), 2026-11-08.** The probe above rendered all
six rows:

- **Step 3 PASSES.** Builder Sans **Regular and Bold both exist and are visibly distinct** -- the Bold
  rows are clearly heavier than the Regular rows at all three sizes. No blocker to raise, and no
  substitution was needed.
- **Step 2 passes on presence.** All four suit codepoints render as real suit shapes at 16, 20 and 28
  px. No blanks and no `.notdef` boxes. Spade and club are tellable apart on the 16 px row.
- **So `PIP_SOURCE` stays `"glyph"` and no sprite sheet is needed.** The escalation path stays
  available and tested but is not being walked.

**Caveat, deliberately left open: this was desktop, and the step says "on a phone".** Roblox falls
back **per glyph** to a system font when the chosen family lacks one, and Windows ships suit symbols
(Segoe UI Symbol) where a phone may not. Whether what rendered is Builder Sans's own glyph or a
Windows fallback is **undetermined** -- the screenshot cannot settle it, and a per-glyph fallback is
device-dependent by nature. A desktop pass therefore does not license the phone claim. **M-12 step 5
now carries that re-check**, because M-12 is the only row that puts the real UI on real glass. If the
pips fail there, the sprite escalation is live and M-14 was judged against glyphs that do not ship.

**Step 1 (audio) is the only part of M-16 still open.** All three ids remain `""`, which is a passing
state under this row's own Expected ("ids supplied **or deliberately left silent**") -- but it has to
be a decision, not an oversight, so this box stays unticked until it is made.

- [ ] M-16 signed off: <name> <date>

---

## M-17 (CARD-02, CARD-15, CARD-17) Three-player starting-gun playtest

**Why manual:** whether the moment of completing a set reads as a starting gun is subjective, and tap behaviour needs
real thumbs. Three real players are the minimum roster.

Steps: run a real three-player session and confirm:

1. One tap selects, and only a second tap on the **same** card sends.
2. An accidental single tap **never** sends.
3. The completion sting, the avatar standing and running, and the who-went callout together read as a starting gun.
4. The finisher is **running before the flourish ends.**

This session also supplies the evidence **M-07** (CARD-11, the simulator's human reaction model, V-35) has been waiting
for since Phase 2. Run them together.

**Expected:** 1 to 4 hold, and the M-07 evidence is recorded in the same session.

**Blocking: yes for Phase 4's close.**

Observed:

- [ ] M-17 signed off: <name> <date>
