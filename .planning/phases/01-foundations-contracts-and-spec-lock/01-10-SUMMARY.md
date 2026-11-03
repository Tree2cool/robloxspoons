---
phase: 01-foundations-contracts-and-spec-lock
plan: 10
subsystem: boot-and-ci
tags: [map-loader, boot, check-built-place, rojo, lune, require-resolution, strict-typing]

requires:
  - phase: 01-03
    provides: check-guards, zones.luau, --print-zones (exit 1 on empty)
  - phase: 01-06
    provides: RoundDriver
  - phase: 01-07
    provides: MapContract Node shape, MapValidator, maps/gray-box.rbxm
  - phase: 01-08
    provides: Persistence, PlayerGate
  - phase: 01-09
    provides: NetServer, ClientNet
provides:
  - "MapLoader.snapshot / MapLoader.load: Roblox snapshotter, one pure validator, no per-map branch, Geometry-only mount"
  - "Main.server.luau: single boot entry (Persistence, PlayerGate, RoundDriver, MapLoader, NetServer last)"
  - "Main.client.luau: one Ping { nonce = 1 } at boot"
  - "scripts/ci/check-built-place.luau: Roblox-rule require re-resolution over the built .rbxl"
  - "scripts/ci/lex.luau: comment stripping and require extraction shared by both CI checkers"
affects: [01-11, 01-12, phase-03, phase-04]

tech-stack:
  added: []
  patterns:
    - "Failure cases mutate the real built place in-test (deserializePlace, edit, serializePlace) and assert the diagnostic substring"
    - "The two require checkers share one lexer so they cannot disagree about which requires exist"

key-files:
  created:
    - src/server/services/MapLoader.luau
    - scripts/ci/check-built-place.luau
    - scripts/ci/lex.luau
    - tests/project/built_place.spec.luau
    - tests/project/fixtures/empty.rbxl
  modified:
    - src/server/Main.server.luau
    - src/client/Main.client.luau
    - scripts/ci/check-guards.luau

key-decisions:
  - "Lexing helpers extracted from check-guards into lex.luau (a behaviour-preserving move) rather than copied, so both checkers strip comments identically"
  - "check-built-place scans every code mount, not only pure zones; @game is banned only in pure zones, other aliases everywhere"
  - "Filesystem cross-check compares the DataModel path the disk resolver reaches against the instance Roblox reaches, not just basenames"

requirements-completed: []
requirements-contributed: [FOUND-01, FOUND-03, FOUND-04, FOUND-07, FOUND-08, MAP-01, SCORE-06]

completed: 2026-11-03
---

# Phase 1 Plan 10: MapLoader, boot wiring and check-built-place Summary

**A Roblox map snapshotter emitting the CI Node shape from CFrame only, a single server boot sequence with NetServer opening last, and a checker that re-resolves all 17 requires in the built `.rbxl` under Roblox rules, proven able to fail six different ways.**

## Task Commits

1. Task 1, MapLoader: `848fc28`
2. Task 2, boot wiring: `275b6f1`
3. Task 3, check-built-place + lex extraction + spec: `098ce56`

## MapLoader

Emits exactly 01-07's Node: `name`, `className`, primitive-only `attributes`, **sorted** `tags`, `children` in document order, and for `BasePart` only `position`, `look`, `size`, `anchored`. Position and look come from `CFrame.Position` and `CFrame.LookVector`; `.Position` is never read. Negative zero is normalised with `n + 0`. Tags come from `CollectionService:GetTags`. Divergence from `scripts/maps/snapshot.luau`: none in shape; the only differences are API-level (live `Instance` and `CollectionService` versus the Lune `Instance` and `GetTags`).

`load(mapId)` finds `ServerStorage.Maps[mapId]`, snapshots, validates, errors with `<CODE> <path> <message>` lines when invalid, and clones **only** `Geometry` into Workspace. `Data` is never cloned. No `mapId ==` anywhere. Tag names are not typed in the file. It returns `(mountedGeometry, MapSpec)`.

Caveat: MapLoader itself is not executed under Lune (it needs `ServerStorage`, `CollectionService`, `Workspace`). It is statically typed against the Roblox platform, covered by guard rules and by the built-place check's require resolution. Runtime behaviour awaits Studio (M-06).

## Boot order (Main.server.luau)

1. `Persistence.select()` (line 23; the `Refuse` error is not caught)
2. `PlayerGate.new()`
3. `RoundDriver.new(onEnded -> print roundId, reason)`
4. `MapLoader.load(DEFAULT_MAP_ID)` with `DEFAULT_MAP_ID = "GrayBox"`
5. `NetServer.start({getPhase, dispatch, onReject, onError})` (line 53)

`getPhase` reads one local holder starting at `"Lobby"`. `dispatch` routes `Ping` (prints `userId` and `nonce`) and **errors for any intent with no handler**. `onReject` and `onError` use `warn`. Client sends `ClientNet.send("Ping", { nonce = 1 })`. `grep -rl OnServerEvent src` still lists only `NetServer.luau`.

**Not wired, stated explicitly:**
- `RoundDriver` is constructed (so its lifecycle exists and `onEnded` logs) but nothing calls `beginRound`; there is no phase machine yet (Phase 4/6). `driver` is referenced only in the final ready print.
- `setPhase` is defined but unused, so there is no `Lobby` to `Hide` transition. Same reason.
- None of this has run in Studio: PlayerGate, Persistence `Refuse`, MapLoader and NetServer on a live server are all unexecuted until M-01..M-06.
- Persistence `select()` is called with no template (profile template is Phase 7).

## check-built-place

`deserializePlace` reads `Source` out of the **binary `.rbxl`** (assumption A4 confirmed for places too); the `.rbxlx` fallback was **not** needed. `deserializePlace` returns a `DataModel` Instance (not a list of roots).

Verbatim, real built place:

```
$ lune run scripts/ci/check-built-place.luau build/spoons.rbxl --verbose
StarterPlayer.StarterPlayerScripts.Client.Main "./net/ClientNet" -> StarterPlayer.StarterPlayerScripts.Client.net.ClientNet
ServerScriptService.Server.Main "./core/Gateway" -> ServerScriptService.Server.core.Gateway
 ... (15 more lines)
ServerScriptService.Server.engine.SpikeA "./SpikeB" -> ServerScriptService.Server.engine.SpikeB
ReplicatedStorage.Shared.Net.Manifest "./Validate" -> ReplicatedStorage.Shared.Net.Validate
check-built-place: ok (17 requires in 24 modules)
```

### Proven able to fail

Real source edit (appended `require("./Nope")` to `src/server/engine/SpikeA.luau`, rebuilt, checked, reverted; `git status` clean afterwards):

```
ServerScriptService.Server.engine.SpikeA "./Nope" -> UNRESOLVED under Roblox rules: no child named Nope under ServerScriptService.Server.engine
check-built-place: FAILED with 1 problem(s)
exit=1
```

Permanent cases in `tests/project/built_place.spec.luau` (11, each asserting a distinctive substring, run against the real place mutated in memory): missing file (`cannot read`), empty DataModel fixture (`ServerScriptService.Server is missing from the built place` and `no literal requires were found`), unresolved require (`no child named Nope`), non-ModuleScript target (`target is a Folder, not a ModuleScript`), `@game` in a pure zone, `@lune/fs` alias, **filesystem mismatch** (module moved so Roblox resolves it and disk does not: `the filesystem resolver finds no file at src/server/services/Bucket.luau`), script smuggled under GrayBox (`contains a Script`), missing GrayBox mount.

The empty-place case uses a committed 79-byte `tests/project/fixtures/empty.rbxl` (bare `DataModel`); the missing-file case is also covered. Both chosen.

### Divergences and discoveries

- **`Instance.new` and `DataModel.new` are not globals/members** under Lune: `roblox.Instance.new("DataModel")` is the form. First spec run failed on this; fixed in the test.
- **`Parent` is typed non-nil** by the Lune typedefs, so a `== nil` comparison is a `TypeError` (`Types Instance and nil cannot be compared`). Resolved with a `:: Inst?` cast at the one site. `luau-lsp` exit code was 0 even with the `TypeError` printed, which re-confirms the settled detector: exit code alone is not enough. I caught it only by grepping the output.
- **Plan deviation, scope:** the plan scans "pure zones". The checker scans all three code mounts (17 requires include services and the client) and applies the `@game` ban to pure zones only. Strictly more coverage, no check weakened.
- **Plan deviation, `files_modified`:** added `scripts/ci/lex.luau` and edited `scripts/ci/check-guards.luau` (removed `lineAt`, `findWord`, `stripComments`, `extractRequires`, now imported). Behaviour preserving: guard output was `52 files, 87 requires` at baseline, `52 files, 94 requires` after the boot wiring, `53 files, 95 requires` right after the lex extraction, and `55 files, 110 requires` at the end; the growth is new files and requires being scanned, with no violation. The guards spec passes unchanged.
- Init modules (`init.luau`) have no instance in the repo today; the disk resolver implements Luau's rule (`./` from an init module starts one level up) but that branch is untested.
- Module count is 24 because `Script`/`LocalScript` count too; `src/server` is mounted as a Folder (no `init`), so the `Main` Script sits under `ServerScriptService.Server`.

## Gates (verbatim)

```
pure zones: src/server/engine src/server/core src/shared/Net
empty-zone assertion: zones=""; test -n "$zones"  ->  exit 1
stylua --check src scripts tests                         ok
selene src scripts tests                                 0 errors / 0 warnings / 0 parse errors
selene --config selene.pure.toml <zones>                 0 errors / 0 warnings / 0 parse errors
luau-lsp (roblox, sourcemap) src                         rc 0, no "Failed to load"/"Sourcemap parsing failed"/TypeError/SyntaxError
luau-lsp (standard) <zones> scripts tests                rc 0, same absence checks
check-guards: ok (55 files, 110 requires, 12 guarded roots)
lune run tests/run.luau                                  316 passed, 0 failed, 3 todo   (baseline 305, +11)
rojo build default.project.json -o build/spoons.rbxl     Built project to spoons.rbxl
```

`--print-zones` was captured into a variable with its status checked and non-empty asserted, as specified.

## What remains for Studio

- **M-01:** Rojo sync / FOUND-01 in a real Studio session.
- **M-02:** require-by-string in Studio against this exact place. This plan's check is the automated proxy; it cannot see Roblox's real runtime.
- **M-03:** fire a NaN `nonce` at `Intent` from the client and confirm rejection; the boot Ping gives it a live path.
- **M-04:** Studio boot against production id fails at `Persistence.select`.
- **M-05:** place Maximum Players setting. **M-06:** `MapLoader` loads GrayBox, mounts only `Geometry`, no per-map branch.

## Known Stubs

None that block the plan. `setPhase` and `driver.beginRound` are intentionally unused (see above).

## Threat flags

None new. T-1-43, T-1-44, T-1-06 mitigated and proven by failing cases; T-1-07 and T-1-34 mitigated in code but runtime-unverified (Studio); T-1-10 and T-1-49 mitigated by boot order, asserted by line numbers (23 versus 53).

## Self-Check: PASSED

Files exist (`MapLoader.luau`, `check-built-place.luau`, `lex.luau`, `built_place.spec.luau`, `empty.rbxl`); commits `848fc28`, `275b6f1`, `098ce56` in `git log`; REQUIREMENTS.md untouched; phase not marked complete.
