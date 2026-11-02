# Phase 1: Foundations, Contracts and Spec Lock - Research

**Researched:** 2026-11-02
**Domain:** Roblox/Luau toolchain (Rokit, Rojo, StyLua, Selene, luau-lsp, Lune), headless engine testing, structural CI guards, typed network gateway, map contract
**Confidence:** MEDIUM-HIGH. Tool versions, flags, config syntax and Roblox platform semantics are now backed by primary sources (tool source at release tags, Roblox's own `creator-docs` repo). The caveat is that **nothing was executed**: this session's auto-mode permission classifier denied running downloaded release binaries after a single `lune --version` (which succeeded and printed `lune 0.11.1`). Every command below is derived from reading source and docs, and the Wave 0 spike must run it.

## Provenance legend

| Tag | Meaning |
|-----|---------|
| `[VERIFIED: <how>]` | I fetched the primary artefact this session (release tag, source file, changelog, `git ls-remote`, HTTP status). "Source read" means the code was read, not run. |
| `[CITED: creator-docs/<path>]` | Roblox's official docs source repo `github.com/Roblox/creator-docs`, commit `c8f5276` (2026-10-29), read via `raw.githubusercontent.com`. This is the repo behind `create.roblox.com/docs`. It is a primary source, but it can lag the live site by days. |
| `[ASSUMED]` | Training knowledge or inference. Needs confirmation. Listed in the Assumptions Log. |

**Network reality (recorded, not worked around).** One attempt each to `create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`, `madstudioroblox.github.io`, `jsdotlua.github.io` failed at connect (HTTP `000`). They remain unreachable. **However** `raw.githubusercontent.com`, `git clone`/`git ls-remote` of public repos, and `github.com/.../releases/download/...` asset downloads all work, and that opens two primary sources the earlier research did not use: **Roblox's own `creator-docs` repo** and the **tool source repos**. `api.github.com` returns 403 here, which breaks Rokit in this container (see Environment Availability).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** **Every check hard-fails.** Formatting, style lint, strict typecheck, and both structural guard rules (FOUND-05, FOUND-06) each fail the build. No advisory tier. The owner chose maximum strictness deliberately: a guard that does not block is documentation, and FOUND-05 exists precisely because conventions get forgotten.
- **D-02:** **CI runs on every push to any branch and on every pull request.** GitHub Actions (repo is `Tree2cool/robloxspoons`).
- **D-03:** **Local pre-commit hook runs the fast checks only** — format and lint. Strict typecheck and the test suite are left to CI so commits stay fast enough that nobody reaches for `--no-verify`.
- **D-04:** **Un-automatable criteria get a `MANUAL-CHECKS.md` plus a helper script.** The script runs everything verifiable without Studio; the document lists each check that needs a human with Studio open, so nothing silently passes unverified. This exists because the container running the build has no Roblox Studio MCP.
- **D-05:** **Map geometry lives as one committed `.rbxm` per map**, built in Studio, exported, committed to git, and mounted by Rojo. Chosen over `rojo syncback` and over a single `.rbxl`. Five independent files is what parallel map building in Phase 7 requires.
- **D-06:** **Rojo manages code only.** It owns `ServerScriptService`, `ReplicatedStorage` and `StarterPlayer`. **`Workspace` carries `$ignoreUnknownInstances`** so anything built in Studio survives a sync. Maps mount explicitly as named `.rbxm` files. This is the setting that silently destroys work if wrong, which is why it is also a manual check (D-04).
- **D-07:** **Scripts are authored on the filesystem; non-script instances are authored in Studio.** All Luau is written to files and synced; geometry, attachments and hand-placed instances are Studio work.
- **D-08:** **Phase 1 ships a mechanically complete gray-box reference map** — untextured blocks, but with real spawn points, at least 16 default spots, standable surfaces and genuine sightlines. No art. It must be good enough for Phase 3 to validate placement against and Phase 5 to run the hunt in. A single box room was rejected as too simple.
- **D-09:** **Default hiding spots are tagged marker parts placed in Studio**, read via `CollectionService`. Chosen over a Luau coordinate table. The validator reads the tags.
- **D-10:** **Every map must declare, through the shared contract:** seeker spawn points and the hider spawn point; a playable bounds volume (one authority per map); a metadata block (display name, recommended player range, size class); decoy item anchors; **a card table anchor plus 9 seat anchors** (see D-11).
- **D-11:** **The card table is a physical location in every map.** 9 seat anchors (max seekers = 10 players − 1 hider). Avatars sit at a real table; the hand is a screen overlay. Seats keep fixed physical chairs while the ring closes up logically.
- **D-12:** **The validator does structural checks in Phase 1 and gains the real placement rules in Phase 3**, in the same tool. Phase 1 checks: required folders present, ≥16 tagged spots, spawns exist, bounds volume present, card table and 9 seats present, metadata well-formed.
- **D-13:** **A separate Roblox test universe**, with Studio pointed at its DataStores. True isolation rather than an in-code convention. **Requires a Creator Hub setup step only the owner can perform — a human gate on Phase 1 closing.** The weaker in-code `RunService:IsStudio()` guard was explicitly not chosen.
- **D-14 / D-15:** (Camera locked to table in the card phase; a player who completes four of a kind stands up and runs, no teleport.) Implemented in Phases 4 and 5. Recorded here so the map contract does not contradict them; they must not be re-litigated.

### Claude's Discretion

Not discussed; defaulting to the research recommendations in `research/STACK.md` and `research/ARCHITECTURE.md`:

- Package manager — Wally as default, pesde as fallback. The dependency surface is tiny, so the choice is reversible.
- Module and folder layout, including the `server/engine/` boundary that FOUND-06 lints.
- Test harness mechanics — a small in-repo harness so engine tests do not depend on Jest; Jest-Lua stays optional for Studio-side tests.
- `Net` gateway internals: token-bucket rate-limit shape and starting numbers (research marks the numbers LOW confidence, to be tuned in playtest), argument validation including NaN, phase gating.
- Round-end FSM internals: absolute deadlines, round-ID tokens, injected clock for the SCORE-06 test.
- Rokit-pinned tool versions (StyLua, Selene, luau-lsp) and CI job layout.

### Deferred Ideas (OUT OF SCOPE)

None — the discussion stayed within phase scope. D-14 and D-15 are implemented in Phases 4 and 5 and need no new requirement IDs (CARD-17 and UX-02 already cover them). Not this phase: the card engine itself (Phase 2), the placement rules (Phase 3), gameplay UI (Phase 4+), the five shipped maps (Phase 7).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FOUND-01 | Rojo project syncs to Studio, git is source of truth, `$ignoreUnknownInstances` on Workspace | Exact `default.project.json`; `$ignoreUnknownInstances` semantics read from Rojo 7.7.1 source (V-6); rbxm single-root rule; `servePlaceIds` safety |
| FOUND-02 | Toolchain pinned via Rokit; every Luau file `--!strict` | `rokit.toml` format verified from Rokit source; exact versions (V-1); `.luaurc`; strict-header guard rule |
| FOUND-03 | Engine tests and fuzz suite run headless in CI | Lune 0.11.1 harness; require-style spike (V-4); dual-resolver check; seeded PRNG without multiplies |
| FOUND-04 | Single typed gateway validates args (incl. NaN) and rate-limits | Single-envelope RemoteEvent; check order; token bucket; official Roblox guidance (V-31); remote delivery semantics (V-12 changed) |
| FOUND-05 | Build fails if Scoring/CardTable/SpoonPlacement import cosmetics/shop | Lune guard script with own resolver + transitive closure; failing fixtures |
| FOUND-06 | Build fails if the card engine references any Roblox API | Selene `std = "luau"` allow-list + `luau-lsp --platform standard`; failing fixtures |
| FOUND-07 | A Studio session cannot write to production player data | Human-gate steps; official Studio API Services behaviour; data stores are per-experience; `servePlaceIds` |
| FOUND-08 | 10-player cap, 3-player minimum to start | `Players.MaxPlayers` is read-only; pure `Admission` core + place setting + kick path |
| MAP-01 | Maps are data behind one shared contract | Instance layout, Luau types, snapshot-based validator, Lune `.rbxm` reading |
| SCORE-06 | Round end exactly once; stale callbacks can never affect a later round | `RoundLifecycle` with injected scheduler, round-ID tokens, idempotent `endRound`, boundary tests |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

Treated as locked decisions. Research does not contradict any of them.

- Roblox/Luau, `--!strict` everywhere. Full PC and mobile parity (no UI in this phase).
- **Rule 1:** gameplay code (`Scoring`, `CardTable`, `SpoonPlacement`) has no import path to cosmetics/shop; lint-enforced (FOUND-05).
- **Rule 2:** card engine lives in `server/engine/`, references no Roblox API, pure and synchronous; lint-enforced (FOUND-06).
- **Rule 3:** nothing hidden may be a replicated Instance (relevant to where map data lives: `ServerStorage`, never `Workspace`).
- **Rule 5:** server is the only clock; integer deciseconds. **Rule 6:** no yields inside state mutations. **Rule 7:** client sends intents with stable IDs, never targets or indices.
- **Rule 8:** seat removal is one generic operation; cards never destroyed (Phase 2).
- 3-player minimum, 10-player cap. Rounds per match = starting roster size.
- GSD workflow: do not skip from requirements to code; commit atomically.
- **Verification Debt rule:** re-check the table rows for this phase, record what was confirmed or changed, never upgrade confidence without re-fetching the primary source. This document does that below.

## Summary

Phase 1 creates the first code in an empty repo, so the research value is in exact, current tool detail and in four mechanical questions that were open. All four now have concrete answers.

**1. One source tree can satisfy both Lune and Roblox with plain relative string requires.** Roblox's own docs now define require-by-string (`./` = `script.Parent`, `../` = `script.Parent.Parent`, `@self/` = `script`, `@game/` = `game`), and Lune 0.11.1 implements Luau's require-by-string (`./`, `../`, `@alias`) with the same sibling/parent meaning. No darklua, shim or single-file trick is needed. The one real constraint is that a relative path only means the same thing in both worlds **inside a single Rojo `$path` mount**, because the filesystem tree only mirrors the DataModel within a mount. So the engine and the other headless cores must be self-contained (dependencies injected), and cross-mount imports belong only in untested Roblox adapters. A built-place consistency check (Lune reads `rojo build` output and re-resolves every require by DataModel semantics) turns the Roblox half of the spike into a CI-checkable fact.

**2. Both guards can be genuinely hard-failing without bespoke parsers for the hard part.** FOUND-06 uses an *allow-list* rather than a deny-list: Selene with `std = "luau"` (which defines no Roblox globals) plus `luau-lsp analyze --platform standard` over the engine directory. FOUND-05 uses a small Lune script that resolves literal string requires itself, bans every non-literal require in guarded zones, and walks the transitive closure. Selene's `restricted_module_paths` was evaluated and rejected because its own docs say it ignores string requires.

**3. Several earlier-research claims changed** (see Verification Debt): `UnreliableRemoteEvent` cap is 1000 bytes, not 900; DataStore server budgets are 60 + 40/player, not 10/player; ProfileStore session steal is 40 s, not about 80 s; RemoteEvent ordering is now documented as guaranteed *across* remotes; Rokit 1.2.0 is dated Sep 2025, not 2026; Selene 0.32.0's std library lacks `math.isfinite`, so the NaN check must be hand-written.

**4. Environment risks for the executor:** Rokit needs `api.github.com`, which is 403 in this container, so Wave 0 needs a pinned direct-download bootstrap (asset URLs verified); and running downloaded binaries needed permission this session was not granted for. Plan both as explicit tasks.

**Primary recommendation:** Pin Rojo 7.7.1, StyLua 2.6.0, Selene 0.32.0, luau-lsp 1.70.1 and Lune 0.11.1 in `rokit.toml`; keep the engine and all headless cores self-contained under `src/server/engine` and `src/server/core` using only `./`, `../`, `@self/` string requires; run tests under Lune with an in-repo harness; enforce FOUND-06 with Selene `std="luau"` plus a standard-platform typecheck, and FOUND-05 with a Lune closure-walking guard; prove each guard with a deliberately failing fixture executed through the real CLI entrypoint; put the human test-universe gate in the final wave with its instructions pre-written.

## Verification Debt Results (rows assigned to this phase)

| ID | Prior claim | Result | Evidence | Status now |
|----|-------------|--------|----------|------------|
| V-1 | Rojo 7.7.1, Rokit 1.2.0, Wally 0.3.2, Lune 0.11.1, StyLua 2.6.0, Selene 0.32.0, luau-lsp 1.70.1/Luau 0.740, pesde 0.7.4; several years inferred | **Confirmed, one correction.** All are the latest release tags. Dates now explicit: Rojo 7.7.1 = Oct 1 **2026** (7.7.0 = Jul 1 2026); Lune 0.11.1 = Oct 21 2026; StyLua 2.6.0 = 2026-10-10; Selene 0.32.0 = 2026-10-01; luau-lsp 1.70.1 = 2026-09-27 (Luau 0.740; unreleased main already syncing 0.742). **Rokit 1.2.0 = September 30th, 2025, not 2026** (year inference was wrong; still the latest tag). Wally 0.3.2 is the latest non-alpha tag (0.4.0-alpha.0/.1 exist). pesde latest tag `v0.7.4+registry.0.2.3` (date not checked). | `git ls-remote --tags` for each repo; each tool's `CHANGELOG.md` via raw.githubusercontent; release asset downloads returned HTTP 200 for rojo, stylua, selene, luau-lsp, lune and 206 for rokit | HIGH |
| V-2 | Jest-Lua package versions, `wally-package-types` version | Partially resolved. `jsdotlua/jest-lua` latest tag `v3.10.0`; `wally-package-types` latest tag `v1.7.0`. **Phase 1 does not use Jest or Wally** (see Standard Stack), so no action. | `git ls-remote --tags` | MEDIUM (tags only) |
| V-3 | ProfileService "not receiving updates" | **Confirmed, stronger.** ProfileService README says "FOR NEW PROJECTS - USE ProfileStore" and "no longer supported" (last commit 2024-10-13). ProfileStore HEAD `45c9847` (2025-07-31), Wally package `lm-loleris/profilestore` 1.0.3. | Cloned both repos | HIGH |
| V-4 | Jest-Lua runs only in Roblox; Lune runs engine code and reads Roblox model files | **Confirmed at source level, not executed.** Lune 0.11.1 implements Luau require-by-string; `@lune/roblox` has `deserializeModel`/`deserializePlace` (take file *contents*, not a path), `serializeModel`, and Instances support `GetChildren`, `GetDescendants`, `FindFirstChild`, `IsA`, `GetAttribute`, `GetTags`, `HasTag`, `QueryDescendants`. Tags are read from the `Tags` property. Roblox side: require-by-string semantics are documented. See "The require spike". | Lune v0.11.1 source/CHANGELOG/tests; `crates/lune-std-roblox/types.d.luau`; creator-docs `LuaGlobals.yaml` | HIGH for semantics, MEDIUM until executed |
| V-5 | Chrrxs MCP tool list/pin; official MCP "cannot screenshot" may be stale | **Partially checked.** README names `capture_screenshot`, `multiplayer_playtest`, `solo_playtest`, `eval_server_runtime`, `eval_client_runtime`, `execute_luau`, `get_runtime_logs`. Latest tag `v3.4.2`. README install examples use `@latest`; keep STACK's advice to pin. The "official MCP cannot screenshot" claim was **not** checked. Irrelevant to this container (no Studio MCP). | README via raw; `git ls-remote` | MEDIUM |
| V-6 | Rojo `$ignoreUnknownInstances` behaviour on Workspace | **Confirmed with refinements.** See "Rojo project file". Key facts: it is a per-node field; if unset it defaults to `true` when the node has no `$path` and `false` when it has one; the Studio plugin applies it in its diff to **unknown direct children** of that node during live sync; `rojo build` output is unaffected; `.rbxm` files must have exactly one top-level instance. | Rojo v7.7.1 `src/project.rs`, `plugin/src/Reconciler/diff.lua`, `src/snapshot_middleware/rbxm.rs` | HIGH |
| V-8 | ProfileStore API shape | **Confirmed.** `ProfileStore.New(store_name, template?)`, `store:StartSessionAsync(profile_key, params?)` (returns profile or nil; `params.Steal`, `params.Cancel`), `profile:Reconcile()`, `profile:AddUserId`, `profile:EndSession()`, `profile.OnSessionEnd` (Signal), `ProfileStore.Mock`, `ProfileStore.DataStoreState` (`NotReady`/`NoInternet`/`NoAccess`/`Access`). Single ModuleScript, 2242 lines. | ProfileStore `ProfileStore.luau` header docs | HIGH |
| V-9 | Session-lock steal about 80 s | **Contradicted.** Constants in source: `SESSION_STEAL = 40` s, `ASSUME_DEAD = 630` s, `LOAD_REPEAT_PERIOD = 10` s, `AUTO_SAVE_PERIOD = 300` s; all tunable via `ProfileStore.SetConstant`. The 80 s figure is not supported. | ProfileStore.luau lines 170-181, 1205-1230 | HIGH (for the current source) |
| V-10 | DataStore budgets "about 60 + 10 per player"; `BindToClose` grace about 30 s | **BindToClose 30 s confirmed. Budget corrected:** default server limits are `60 + numPlayers × 40` per minute for standard Read, Write and Remove, `5 + numPlayers × 2` for List. Budgets are configurable via `SetRateLimitForRequestType`. Extended Services pricing not checked (out of phase scope). | creator-docs `DataModel.yaml` (`BindToClose`), `cloud-services/data-stores/error-codes-and-limits.md` | HIGH |
| V-14 | `UnreliableRemoteEvent` 900-byte cap, about 500/s per client per remote | **Partially contradicted.** Docs say payloads **over 1000 bytes** are dropped (both `UnreliableRemoteEvent.yaml` and `scripting/events/remote.md`), not 900. The ~500 requests/s per client limit is confirmed and is **shared among all remote events of the same type**. Not used in v1. | creator-docs | HIGH |
| V-30 | `GetServerTimeNow` vs `os.clock` | **Resolved enough for Phase 1.** `GetServerTimeNow()` returns Unix seconds, smoothed so it is monotonic and tracks the local clock to 0.6%, and docs point to `os.clock()` for higher-precision use. `os.clock()` is sub-microsecond, unaffected by system clock adjustments, with an arbitrary baseline. Design consequence: inject a `Clock`; bind it to `os.clock()` on the server for scheduling and scoring, and use `GetServerTimeNow()` only to publish an absolute deadline to clients. | creator-docs `Workspace.yaml`, `os.yaml` | HIGH (docs); equivalence of the two on a live server is untested |
| V-31 | Client-server boundary guidance | **Confirmed.** Official page requires validating every client value, calls out NaN and inf explicitly ("NaN is of type number but fails all comparisons"), recommends token-bucket rate limiting, and says the server must be "a gatekeeper, not a relay". | creator-docs `scripting/security/client-server-boundary.md` | HIGH |
| V-11b (P1 part) | Studio "API Services" writes to production DataStores | **Confirmed.** Studio cannot reach DataStores by default (`StudioAccessToApisNotAllowed`); enabling "Enable Studio Access to API Services" (Experience Settings, Security) makes Studio hit the **same data stores as the live client**; docs recommend enabling it only on a separate test version of the game. Data stores are "consistent per game", so a second *place* in the same experience would share data; the test must be a separate *experience*. | creator-docs `data-stores/index.md`, `error-codes-and-limits.md` | HIGH |
| V-12 (informational, P4) | Same-remote ordering only; cross-remote not guaranteed | **Changed.** Docs now state RemoteEvents are reliable and ordered per connection per direction, **including across different RemoteEvent instances**. Ordering is for handler *start*, not completion. Excess client fire beyond the throttle is *delayed*, not dropped. RemoteFunction vs RemoteEvent order is not guaranteed. Re-test in Studio at Phase 4 as planned. | creator-docs `scripting/events/remote.md` "Delivery guarantees" | HIGH (docs) |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Client-to-server intent validation, rate limit, phase gate | API / Backend (server) | Browser / Client (builds envelope only) | Client is untrusted; server derives seat from `Player`, never from args (Rule 7) |
| Round lifecycle, deadlines, exactly-once end | API / Backend | — | Server is the only clock (Rule 5); pure core with injected scheduler |
| Player cap and minimum-to-start | API / Backend | Platform place setting (Creator Hub) | `Players.MaxPlayers` is read-only in script; place setting is the hard cap, server check is defence in depth |
| Map contract data (spawns, spots, bounds, table, seats) | Database / Storage (`ServerStorage`) | API / Backend (loader/validator) | Hidden data must not be a replicated Instance (Rule 3); only `Geometry` is ever cloned to Workspace |
| Map structural validation | CI (Lune, headless) | API / Backend (same pure validator at runtime) | One pure validator over a plain snapshot; two thin snapshotters |
| Card engine purity and import guards | CI (static analysis) | — | Structural, build-time |
| Persistence isolation | Platform (separate experience) | API / Backend (Mock fallback) | True isolation is a Creator Hub fact, not code |
| Studio sync of code | Local dev (Rojo) | — | Git is source of truth; Workspace content is Studio-owned |

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Rokit | 1.2.0 (2025-09-30) | Toolchain manager, `rokit.toml` | Locked by FOUND-02. `[tools]` table of `alias = "owner/repo@exact.version"`; version ranges are rejected [VERIFIED: Rokit source `lib/tool/spec.rs`] |
| Rojo | 7.7.1 (2026-10-01) | Filesystem to Studio sync, `rojo build`, `rojo sourcemap` | Locked by D-05/D-06. Plugin must match CLI version (`rojo plugin install`) [VERIFIED: Rojo source `src/cli/plugin.rs`] |
| StyLua | 2.6.0 (2026-10-10) | Formatter, `stylua --check` | Locked by FOUND-02 |
| Selene | 0.32.0 (2026-10-01) | Linter; also the FOUND-06 allow-list check | Locked by FOUND-02; warnings fail the run unless `--allow-warnings` is passed [VERIFIED: Selene source `selene/src/main.rs:728`] |
| luau-lsp | 1.70.1 (2026-09-27), Luau 0.740 | `luau-lsp analyze` strict typecheck in CI | Locked by FOUND-02. Needs Roblox definitions supplied explicitly |
| Lune | 0.11.1 (2026-10-21), Luau 0.740 | Headless test runner, guard scripts, map validator, `.rbxm` reader | Chosen by research Contradiction 1; same Luau version as luau-lsp 1.70.1 |

All versions [VERIFIED: git tags + CHANGELOGs + asset downloads, this session]. **Not executed.**

### Supporting

| Item | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `CompeyDev/setup-rokit` | v0.2.1 (commit `1d9390883f7ebce19d48f5b8d006e11d387c92ab`) | GitHub Action: installs Rokit, authenticates with `github.token`, runs `rokit install --no-trust-check` | CI. Pass `version: v1.2.0` (otherwise it installs the latest Rokit). Pin by commit SHA [VERIFIED: action.yml at v0.2.1] |
| `actions/checkout` | v7 (latest tag v7.0.1) | Checkout | CI [VERIFIED: `git ls-remote`] |
| `globalTypes.None.d.luau` | from luau-lsp tag 1.70.1, sha256 `9ad75109b8dc9197f6d1726208bfa0b12de47c3a43672a4fa43227f0cec609ee`, 677,555 bytes | Roblox API types for `luau-lsp analyze` | Vendor into `tools/types/`. `main` has a different file (updates continuously), so pin the tag copy [VERIFIED: sha256 computed] |
| `roblox.yml` (Selene std) | generated by `selene generate-roblox-std` | Roblox std library for Selene | Commit it with `roblox-std-source = "pinned"` so CI never needs the network. Size not measured [VERIFIED: Selene `docs/src/roblox.md`; generator fetches `API-Dump.json` from GitHub, HTTP 200 here] |
| darklua | v0.19.0 | `convert_require` rule | **Fallback only** if the require spike fails |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Wally/pesde now | Nothing in Phase 1 | The harness is in-repo, ProfileStore is deferred, Jest is not used. Add `wally.toml` when the first real dependency arrives. This satisfies the discretion note ("Wally as default") without creating an empty manifest. |
| Per-intent RemoteEvents | One envelope RemoteEvent | See Net gateway. Ordering is now guaranteed across remotes and the throttle is shared per type anyway, so per-intent buys nothing; a single `OnServerEvent` connection is the structural proof of "single gateway". |
| pre-commit (Python) framework | Plain `.githooks/pre-commit` + `git config core.hooksPath` | No Python dependency; tools come from Rokit shims. |
| luau-lsp `require-graph` for FOUND-05 | Own resolver in Lune | `require-graph --output-format json` exists (`{"nodes":[...],"edges":[[from,to],...]}`) but the CHANGELOG calls the JSON "experimental, subject to change" and node-label format under a sourcemap is unverified. Keep as an optional cross-check. |
| Selene `restricted_module_paths` for FOUND-05 | — | **Rejected:** its docs say it "does not check string require statements". |

**Installation (CI and dev machines):**
```bash
# rokit.toml is committed; then:
rokit install --no-trust-check      # CI only; locally accept the trust prompt once
lune setup                          # writes ~/.lune/.typedefs/0.11.1/ so @lune/* typechecks
selene generate-roblox-std          # once, commit roblox.yml
```

**Container fallback (api.github.com is 403 here):** download pinned assets directly. URL patterns verified (HTTP 200/206):
```
https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-linux-x86_64.zip
https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-linux-x86_64.zip
https://github.com/Kampfkarren/selene/releases/download/0.32.0/selene-0.32.0-linux.zip
https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.1/luau-lsp-linux-x86_64.zip
https://github.com/lune-org/lune/releases/download/v0.11.1/lune-0.11.1-linux-x86_64.zip
https://github.com/rojo-rbx/rokit/releases/download/v1.2.0/rokit-1.2.0-linux-x86_64.zip
```
Each zip contains one binary named after the tool.

## Architecture Patterns

### System Architecture Diagram

```
 developer / agent edits .luau files
        |
        v
 .githooks/pre-commit  --(staged *.luau)--> stylua --check ; selene (D-03: fast checks only)
        |
        v  git push (any branch) / pull_request                       (D-02)
 +----------------------------- GitHub Actions: one job, named steps, every step hard-fails (D-01) -----------------------------+
 | checkout -> setup-rokit(v1.2.0) -> lune setup                                                                               |
 |   1 stylua --check src scripts tests                                                                                        |
 |   2 selene (roblox std)  ;  selene --config selene.pure.toml  <pure zones>        <-- FOUND-06 allow-list                   |
 |   3 rojo sourcemap -> luau-lsp analyze --platform roblox (src) ; luau-lsp analyze --platform standard (pure zones, tests)    |
 |   4 lune run scripts/ci/check-guards.luau        <-- FOUND-02 strict header, FOUND-05 closure, FOUND-04/06 hygiene           |
 |   5 lune run tests/run.luau                      <-- unit + fuzz + guard-fixture meta-tests + map validator + project tests |
 |   6 rojo build -> build/spoons.rbxl ; lune run scripts/ci/check-built-place.luau  <-- Roblox-semantics require re-resolve   |
 +-----------------------------------------------------------------------------------------------------------------------------+
        |
        v
 scripts/verify.luau (D-04 helper): runs 1-6 locally + prints the MANUAL-CHECKS.md items still needing Studio

 Runtime (Roblox server):                                  Pure cores (headless-testable, no Roblox API)
 client --FireServer(intent, payload)--> RemoteEvent       src/server/core/Gateway  (injected: manifest, clock, getPhase, dispatch)
    --> services/NetServer (adapter, only OnServerEvent)---> check order: intent known? -> token bucket -> phase -> validate -> dispatch
 Players.PlayerAdded --> services/PlayerGate --------------> core/Admission (cap 10 / min 3)
 task.delay backstop --> services/RoundDriver -------------> core/RoundLifecycle (roundId token, absolute deadline, idempotent endRound)
 ServerStorage.Maps.GrayBox --> services/MapLoader --snapshot--> core/MapValidator --> core/MapContract (typed MapSpec)
```

### Recommended Project Structure

```
default.project.json   rokit.toml   stylua.toml   .styluaignore   selene.toml   selene.pure.toml   roblox.yml   .luaurc
.gitattributes (*.rbxm binary; text eol=lf)   .gitignore (build/ sourcemap.json)   .githooks/pre-commit
.github/workflows/ci.yml        MANUAL-CHECKS.md        maps/gray-box.rbxm        tools/types/globalTypes.None.d.luau
src/
  server/                       # mount: ServerScriptService.Server
    Main.server.luau
    engine/                     # PURE ZONE (FOUND-06). Self-contained: requires only siblings. Rng.luau now; card engine in Phase 2
    core/                       # PURE ZONE. Gateway, Bucket, RoundLifecycle, Admission, MapContract, MapValidator
    services/                   # Roblox adapters (NOT pure, not unit-tested): NetServer, PlayerGate, RoundDriver, MapLoader
  shared/                       # mount: ReplicatedStorage.Shared
    Net/ (Manifest.luau, Validate.luau)      Config/ (Limits.luau)
  client/                       # mount: StarterPlayerScripts.Client
    Main.client.luau   net/ClientNet.luau
scripts/ ci/check-guards.luau  ci/check-built-place.luau  maps/generate-graybox.luau  maps/validate-map.luau  verify.luau  dev/bootstrap-tools.sh
tests/ run.luau  harness/{Test,Fuzz,FakeClock}.luau  engine/  core/  maps/  project/  guards/{guards.spec.luau, fixtures/...}  spike/
```

`tests/`, `scripts/`, `tools/` are **not** Rojo-mounted. The "pure zone" list lives in one config table used by Selene invocations and by `check-guards`.

### Pattern 1: The require spike (V-4), the highest-value finding

**What:** Use only `require("./X")`, `require("../X")`, `require("@self/X")` string requires in Luau files that must run in both worlds.

**Why it works (both semantics are documented):**
- Roblox [CITED: creator-docs `reference/engine/globals/LuaGlobals.yaml`, `require`]: `./` begins at `script.Parent`; `../` begins at `script.Parent.Parent`; `@self/` begins at `script`; `@game/` begins at `game`; each further component is a child, `..` is the parent; resolution is non-blocking and **errors if the target does not exist at call time**. Only these prefixes are documented there; **custom `.luaurc` aliases are not documented for Roblox runtime**, so never use them in code that ships.
- Lune 0.11.1 [VERIFIED: Lune CHANGELOG 0.10.0 and `tests/require/tests/*.luau`]: since 0.10.0 `require` follows Luau's require-by-string; paths **must** start with `./`, `../` or `@`; `require("foo")` errors. `./module` finds `module.luau`/`module.lua`/`module/init.luau`. `@self` is for use inside `init.luau`. `.luaurc` `aliases` are supported.
- The two agree because Rojo names `CardEngine.luau` as ModuleScript `CardEngine`, and a directory as a Folder, so `./SeatRing` is the same sibling in both trees.

**The constraint that matters:** the equivalence holds only **within one Rojo `$path` mount**. From `src/server/engine/X.luau`, `../../shared/Y` is a real file on disk but resolves to nothing in the DataModel (`ServerScriptService.Server.engine` + `..`,`..` = `ServerScriptService`, which has no `shared`). Therefore:
- Pure zones require only files inside the same mount (engine: only engine siblings). Dependencies from other mounts are **injected as parameters**.
- Adapters in `src/server/services/` may use `@game/ReplicatedStorage/Shared/...` (Roblox-only, never unit-tested in Lune) to fetch shared modules and pass them into cores.
- Tests (Lune, unmounted) reach into cores by filesystem-relative path (`require("../../src/server/core/Gateway")`) and pass fake dependencies.

**Spike deliverables (Wave 0, before the rest is built):**
1. `src/server/engine/SpikeA.luau` requiring `./SpikeB`; `tests/spike/require.spec.luau` requiring A by relative path under Lune and asserting the value flows through.
2. `rojo build -o build/spike.rbxl`, then `scripts/ci/check-built-place.luau`: `fs.readFile` the rbxl, `roblox.deserializePlace`, walk every ModuleScript in the pure zones, extract literal requires from the `Source` property, re-resolve each using the **Roblox rules above over the DataModel**, and assert the target exists and is the same file the filesystem resolver picked. That is a CI-checkable proxy for "works in Roblox".
3. Human confirmation (MANUAL-CHECKS M-02): in Studio, run a Script that requires the spike module and prints a value. This is the only part that needs Studio.
4. Delete the spike files at the end of the phase (or keep `Rng` as the real first engine file).

**Fallback (named):** if the dual-resolver check or Studio disagrees, use **darklua** v0.19.0 with its `convert_require` rule to rewrite path requires to Roblox instance requires in a `build/` step, and point Rojo at the output. [ASSUMED: rule name and options not fetched; existence seen in the docs.rs source listing `rules/convert_require/roblox_require_mode.rs`.] Second fallback: relax the "engine is one directory" rule by making `src/` mirror the DataModel (`src/ServerScriptService/...`, `src/ReplicatedStorage/...`) so `../../../ReplicatedStorage/...` resolves in both; this depends on string-require traversal above a service reaching `game`, which is **unverified** (LOW).

### Pattern 2: Pure core + injected dependencies + thin Roblox adapter

Each headless-testable behaviour is a plain module taking a deps table (`clock`, `manifest`, `getPhase`, `dispatch`, `scheduler`). The Roblox glue in `services/` is a few lines. This is what lets `Gateway`, `RoundLifecycle`, `Admission` and `MapValidator` run under Lune with fakes, and it is why both FOUND-06 zones (`engine/`, `core/`) can share one lint config.

### Pattern 3: Snapshot-based map validation

The validator takes a plain-table `MapSnapshot` (no Instances). Two snapshotters produce it: Lune (from `.rbxm`, used in CI) and Roblox (from a live Instance, used by the server `MapLoader`). Unit tests hand-build snapshots; one integration test snapshots `maps/gray-box.rbxm`.

### Anti-Patterns to Avoid

- **Cross-mount relative requires** in pure code (Pattern 1 constraint).
- **Instance-path requires** (`require(script.Parent.X)`) anywhere Lune must run: Lune has no `script`.
- **A deny-list for Roblox identifiers** as the primary FOUND-06 mechanism: it silently misses any API not on the list. Use the allow-list (std library) approach.
- **`--formatter plain` with `luau-lsp analyze` in CI:** in that mode the process returns 0 even with errors [VERIFIED: `AnalyzeCli.cpp:359`, `if (format == ReportFormat::Luacheck) return 0`]. Use the default or `gnu` formatter.
- **Relying on lint warnings failing `luau-lsp analyze`:** only type errors and lint *errors* set a non-zero exit. Set `"lintErrors": true` in `.luaurc`, which converts every enabled lint into an error [VERIFIED: Luau 0.740 `Frontend::classifyLints`; `AnalyzeCli.cpp:118`].
- **`luau-lsp analyze --platform roblox` without definitions:** it only prints a warning and proceeds with no Roblox types; it never downloads them [VERIFIED: `AnalyzeCli.cpp:280-284`]. Default platform is `roblox`.
- **Putting map data under Workspace or ReplicatedStorage:** violates Rule 3. Mount maps under `ServerStorage.Maps`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Roblox-global detection for the engine | A regex deny-list of `game`, `workspace`, `Instance`... | Selene `std = "luau"` (allow-list) + `luau-lsp analyze --platform standard` | Allow-list covers APIs nobody thought to list, and the typechecker catches type-position references (`: Instance`) that Selene cannot see |
| Parsing `.rbxm`/`.rbxl` | A binary parser | `@lune/roblox` `deserializeModel`/`deserializePlace` | rbx-dom based; also provides `serializeModel` for generating fixtures and the seed map |
| Tool version management | Bash download scripts as the primary path | Rokit | Locked by FOUND-02. (Direct-download bootstrap is a container fallback only.) |
| Rate limiting | Ad-hoc cooldown tables per remote | One token-bucket module (official docs show the pattern) | Burst + steady refill is the documented approach [CITED: client-server-boundary.md] |
| Project assembly check | Custom "does it assemble" script | `rojo build -o build/spoons.rbxl` | FOUND-01 criterion names it |
| Roblox type definitions | Hand-written `.d.luau` | luau-lsp's `globalTypes.None.d.luau` | 677 KB generated from the API dump |
| Test runner framework | Importing Jest-Lua | ~150-line in-repo harness on Lune | Jest-Lua only runs inside Roblox; this is research Contradiction 1's resolution |

**Key insight:** The only bespoke code worth writing is (a) the ~150-line require resolver/closure walker in `check-guards`, because no stock tool resolves string requires into a policy check, and (b) the pure cores themselves. Everything else is configuration of stock tools.

## Concrete Configuration (exact file contents)

All files below are **unexecuted** drafts built from verified syntax. Wave 0 must run them.

### `rokit.toml` [VERIFIED: manifest format from Rokit source `lib/manifests/rokit.rs`, `lib/tool/spec.rs`]
```toml
[tools]
rojo = "rojo-rbx/rojo@7.7.1"
stylua = "JohnnyMorganz/StyLua@2.6.0"
selene = "Kampfkarren/selene@0.32.0"
luau-lsp = "JohnnyMorganz/luau-lsp@1.70.1"
lune = "lune-org/lune@0.11.1"
```
Prefer generating it with `rokit add` once so Rokit writes canonical casing; the content above is what it should produce. Version ranges are an error.

### `default.project.json` [VERIFIED: field names from Rojo 7.7.1 `src/project.rs`, which uses `deny_unknown_fields`]
```json
{
  "name": "Spoons",
  "globIgnorePaths": ["**/*.spec.luau", "**/*.spec.lua"],
  "tree": {
    "$className": "DataModel",
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "Server": { "$path": "src/server" }
    },
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "Shared": { "$path": "src/shared" }
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "StarterPlayerScripts": {
        "$className": "StarterPlayerScripts",
        "Client": { "$path": "src/client" }
      }
    },
    "ServerStorage": {
      "$className": "ServerStorage",
      "Maps": {
        "$className": "Folder",
        "GrayBox": { "$path": "maps/gray-box.rbxm" }
      }
    },
    "Workspace": {
      "$className": "Workspace",
      "$ignoreUnknownInstances": true
    }
  }
}
```
Notes the planner should carry into tasks:
- **Where `$ignoreUnknownInstances` is legal:** any project node (it is a `ProjectNode` field). Default when unset is `true` for a node with no `$path`, `false` for a node with `$path`. Setting it explicitly on `Workspace` is still required by FOUND-01 so the intent is in the file and a test can assert it.
- **What it actually does:** during live sync the plugin deletes instances it does not recognise among a node's children unless the node's metadata says to ignore them. It is **per node, direct children**, not recursive. A mounted `Client`/`Server` folder (has `$path`) therefore deletes Studio-created strays, which is intended for code.
- **A mounted `.rbxm` is Rojo-owned:** the `GrayBox` node has a `$path`, so edits made to it inside Studio are overwritten on the next sync until re-exported. Workflow: edit the map in Studio, "Save/Export selection" as `.rbxm` over `maps/gray-box.rbxm`, commit. Add this to MANUAL-CHECKS.
- The `.rbxm` must have **exactly one top-level instance** or Rojo errors ("only supports model files with one top-level instance"). The instance is renamed to the node name (`GrayBox`).
- `Maps` has no `$path`, so unknown children (a map someone is drafting in Studio) survive. `Lighting`, `Terrain`, other services are untouched because the root `DataModel` node defaults to ignore.
- `globIgnorePaths` keeps stray spec files from ever syncing. Fixtures live under `tests/`, not mounted.
- Optional safety (needs the human gate output): `"servePlaceIds": [<test place id>]` makes `rojo serve` refuse other places; `blockedPlaceIds` can name the production place. Both are real fields. Fill after FOUND-07.
- Rojo 7.7.x `serve` validates `Host`/`Origin` headers against DNS rebinding [VERIFIED: Rojo CHANGELOG]; no action.

### `.luaurc` [VERIFIED: key names from Luau 0.740 `Config.cpp`; Lune's own `.luaurc` uses the same shape]
```json
{
  "languageMode": "strict",
  "lint": { "*": true },
  "lintErrors": true,
  "typeErrors": true,
  "aliases": { "lune": "~/.lune/.typedefs/0.11.1/" }
}
```
- Unknown keys are an error (`Unknown key ...`), so no comments and no stray fields.
- `lintErrors: true` is what makes lint hard-fail under `luau-lsp analyze`.
- `languageMode: strict` sets the default, but FOUND-02 says *every file* is `--!strict`, so `check-guards` also requires the literal header.
- The `lune` alias is exactly what `lune setup` writes [VERIFIED: Lune `crates/lune/src/cli/setup.rs`]. Committing it makes `lune setup` a no-op on the file while still generating the typedef files CI needs. Whether `luau-lsp` expands `~` is **[ASSUMED]**; Lune writes it for editors to read, so it is expected to work. Wave 0 verifies; the fallback is `--base-luaurc` pointing to a CI-generated file.
- This alias is for `tests/` and `scripts/` only. Engine and shipped code never use aliases (Roblox runtime does not document them).

### `stylua.toml` [VERIFIED: option names and defaults from StyLua v2.6.0 README]
```toml
syntax = "Luau"
column_width = 120
line_endings = "Unix"
indent_type = "Tabs"
indent_width = 4
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
collapse_simple_statement = "Never"

[sort_requires]
enabled = false
```
`.styluaignore` (gitignore syntax): `tests/guards/fixtures/`, `build/`, `vendor/`, `tools/`. Pair with `.gitattributes` `* text=auto eol=lf` and `*.rbxm binary` so Windows checkouts do not make `--check` fail on CRLF. CLI: `stylua --check src scripts tests`.

### `selene.toml` and `selene.pure.toml` [VERIFIED: key names from Selene `selene-lib/src/lib.rs` (`deny_unknown_fields`, kebab-case) and docs]
```toml
# selene.toml  (shipped Roblox code, scripts, tests)
std = "roblox"
roblox-std-source = "pinned"
exclude = ["tests/guards/fixtures/**", "vendor/**", "build/**", "tools/**"]
```
```toml
# selene.pure.toml  (FOUND-06 allow-list for pure zones)
std = "luau"
exclude = []

[lints]
undefined_variable = "deny"
global_usage = "deny"
```
- Config is read from the working directory by default; a second file needs `--config`. Run: `selene src scripts tests` then `selene --config selene.pure.toml src/server/engine src/server/core`.
- `std = "luau"` is a built-in whose header says Roblox things (`CFrame.new()`, `Instance.new()`, `task.spawn()`) belong to `roblox_base.yml`, not here [VERIFIED: `default_std/luau.yml` comment]. It also lacks `warn` (a good thing in pure code: return events instead of logging).
- **Std gap:** `math.isfinite`, `math.isnan`, `math.isinf` exist in Luau 0.740 and are what Roblox's docs recommend for NaN checks, but are **absent from Selene 0.32.0's `luau.yml`** [VERIFIED: grep]. Selene would flag them. Implement the NaN check portably (`x == x and x ~= math.huge and x ~= -math.huge`) in one `Validate.isFinite`. Do not add a custom std unless a second gap appears.
- Selene's exit code is 1 on any warning unless `--allow-warnings` is passed. Do not pass it.
- `std = "roblox"` generates `roblox.yml` by downloading the API dump (GitHub-hosted); with `pinned` it is written to the working directory. Commit it.

### luau-lsp invocations [VERIFIED: source read, `src/main.cpp` and `src/AnalyzeCli.cpp` at 1.70.1; not run]
```bash
rojo sourcemap default.project.json --include-non-scripts -o sourcemap.json

# Roblox-aware: shipped code
luau-lsp analyze --platform roblox --sourcemap sourcemap.json \
  --definitions=tools/types/globalTypes.None.d.luau \
  --base-luaurc .luaurc --ignore "**/fixtures/**" src

# Standard platform: pure zones, scripts, tests. Unknown Roblox globals/types are errors.
luau-lsp analyze --platform standard --base-luaurc .luaurc --ignore "**/fixtures/**" \
  src/server/engine src/server/core scripts tests
```
- `--definitions=PATH` with no `@name=` is accepted and registered as `@roblox` (backwards-compat branch). `--definitions` uses assign chars `:` and `=`.
- Directories are traversed recursively for `.lua`/`.luau`; a path that does not exist exits 1 (a typo cannot silently pass).
- `--sourcemap` is ignored with a warning unless `--platform roblox`.
- `globalTypes.None` is the lowest security level (members a normal game script may use); other levels exist (`LocalUserSecurity`, `PluginSecurity`, `RobloxScriptSecurity`). Which level the Roblox runtime effectively exposes to game scripts is **[ASSUMED]**; if it causes false errors, switch level.
- Definitions never come from `create.roblox.com`; they come from the luau-lsp repo (generated from the Roblox-Client-Tracker dump on GitHub), so the blocked-host problem does not affect CI.
- `FFlag` handling: luau-lsp enables all Luau FFlags by default; `--no-flags-enabled` disables. Leave default.

### `.github/workflows/ci.yml`
```yaml
name: ci
on:
  push:            # D-02: every push, every branch
  pull_request:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  check:
    runs-on: ubuntu-latest        # [ASSUMED] current hosted label
    steps:
      - uses: actions/checkout@v7
      - uses: CompeyDev/setup-rokit@1d9390883f7ebce19d48f5b8d006e11d387c92ab  # v0.2.1
        with:
          version: v1.2.0
      - run: lune setup
      - name: Format
        run: stylua --check src scripts tests
      - name: Lint (shipped code)
        run: selene src scripts tests
      - name: Lint (pure zones, FOUND-06 allow-list)
        run: selene --config selene.pure.toml src/server/engine src/server/core
      - name: Sourcemap
        run: rojo sourcemap default.project.json --include-non-scripts -o sourcemap.json
      - name: Typecheck (roblox)
        run: luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions=tools/types/globalTypes.None.d.luau --base-luaurc .luaurc --ignore "**/fixtures/**" src
      - name: Typecheck (standard)
        run: luau-lsp analyze --platform standard --base-luaurc .luaurc --ignore "**/fixtures/**" src/server/engine src/server/core scripts tests
      - name: Structural guards
        run: lune run scripts/ci/check-guards.luau
      - name: Tests (unit, fuzz, guard fixtures, map validator)
        run: lune run tests/run.luau
      - name: Build
        run: rojo build default.project.json -o build/spoons.rbxl
      - name: Built-place require check
        run: lune run scripts/ci/check-built-place.luau build/spoons.rbxl
```
`setup-rokit` authenticates Rokit with `github.token`, which avoids the unauthenticated rate limit on `api.github.com`. Jobs may be split later for faster feedback; one job with named steps is the minimum that satisfies D-01 and keeps tool install cost to one run.

### `.githooks/pre-commit` (D-03)
```sh
#!/usr/bin/env sh
set -eu
files=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.luau$' || true)
[ -z "$files" ] && exit 0
# shellcheck disable=SC2086
stylua --check $files
selene $files
```
Install with `git config core.hooksPath .githooks` (put it in a `scripts/dev/setup` step and in README). GUI git clients may not have `~/.rokit/bin` on `PATH`; the hook should `export PATH="$HOME/.rokit/bin:$PATH"`. Do not run typecheck or tests here (D-03).

## Net gateway (FOUND-04)

**Recommendation: one envelope `RemoteEvent` (named `Intent`), created by the server at boot, with one `OnServerEvent` connection owned by `services/NetServer`, delegating to the pure `core/Gateway`.**

Why envelope, with current docs:
- Ordering across different RemoteEvents is now documented as guaranteed, and the 500/s throttle is shared per remote *type* [CITED: creator-docs `remote.md`], so splitting per intent gains neither ordering nor budget.
- One connection is a structural proof of "single gateway" that `check-guards` rule R4 can enforce: `OnServerEvent`, `OnServerInvoke`, `RemoteFunction`, `UnreliableRemoteEvent` may appear only in `src/server/services/NetServer.luau`, and `FireServer` only in `src/client/net/ClientNet.luau`.
- Connect the handler **before** parenting the RemoteEvent into `ReplicatedStorage` so no message can arrive with no handler connected; docs say messages arriving unhandled are queued with a bounded queue and then dropped with an error [CITED: `remote.md`].

**Check order (cheapest first, every attempt consumes a token):**
1. `intentName` is a string within a length cap and present in the manifest, else reject `UnknownIntent` (do not allocate per-name state for unknown names).
2. Token bucket for `(userId, intent)` (reject `RateLimited`). Charging before validation bounds CPU spent on garbage.
3. Phase gate: current phase is in the intent's allowed phases (reject `WrongPhase`). Phase comes from an injected `getPhase()`.
4. Payload validation (reject `Malformed`): `type`, finite numbers (NaN and ±inf), integer checks (`v % 1 == 0`), ranges, string length caps, tables with exactly the expected keys and no `nil` holes, no Instances ever. Cap table depth and size.
5. Dispatch the typed payload to the handler. Handlers must not yield (Rule 6). Wrap in `xpcall`, route errors to an injected `onError`, never let a throwing handler kill the connection.

The server derives the player from `OnServerEvent`'s first argument; the adapter hands the core `player.UserId`. The client never supplies a seat or a target (Rule 7).

**Do not rely on / do not do:**
- Do not rely on handler *completion* order: ordering is for handler start only [CITED].
- A client that fires above the throttle gets its excess messages **delayed, not dropped** [CITED], i.e. a flood becomes a server-side backlog. The server bucket must therefore drop, not queue.
- Do not use `RemoteFunction` (no gateway path) or `UnreliableRemoteEvent` for gameplay.
- Starting numbers from STACK (card actions burst 8 / refill 8 per second; prompts burst 2 / 1 per s; placement burst 10 / 10 per s) remain **LOW confidence** (V-34); keep them in one config table and test with them as parameters, not constants.

**Testable shape (Lune, injected `Clock`):** table-driven vectors for NaN (`0/0`), `math.huge`, `-math.huge`, `1.5` where an integer is required, over-long string, extra table key, mixed table, wrong type, unknown intent, wrong phase, burst exhaustion then refill after `clock.advance`, two players do not share buckets, `forget(userId)` frees state, and "rejected messages never reach `dispatch`". Vector3 component finiteness (`typeof(v) == "Vector3"`) is a Roblox-only test; keep the helper but test it in Studio or skip in Phase 1 unless a Vector3 intent exists.

## Player cap and minimum (FOUND-08)

- `Players.MaxPlayers` is **ReadOnly** and "can only be set through a specific place's settings on the Creator Dashboard" [CITED: creator-docs `Players.yaml`]. This confirms the correction to the question: scripts cannot set it.
- **Layering:** (1) Place setting Maximum Players = 10 in Creator Hub (human step, add to the same gate as FOUND-07); (2) server defence in depth: `PlayerGate` (adapter) calls pure `Admission.decide(currentCount, cap)` on `PlayerAdded` and `player:Kick(message)` for the 11th. Reserved servers and teleports may not honour the place cap [ASSUMED], which is why the code check exists; (3) `Admission.canStartMatch(readyCount, min)` is the only function that may allow a match to begin, with `min = 3` and `cap = 10` from `shared/Config/Limits.luau` passed in by the adapter.
- **Machine-testable:** boundary cases 0, 2, 3, 9, 10, 11, negative and non-integer inputs (reject), through the pure core, plus the adapter path with a fake players list. **Not machine-testable:** the platform actually refusing the 11th join. Studio's local multi-client cap is historically 8 (V-16, unverified), so the 11th-player behaviour is covered by unit tests plus the place setting being set, recorded in MANUAL-CHECKS.

## Round end exactly once (SCORE-06)

Pure `core/RoundLifecycle`, deps `{ scheduler, onEnded }` where `scheduler = { nowDeci: () -> number, delay: (seconds: number, fn: () -> ()) -> (() -> ()) }`. Production binds `nowDeci` to `math.floor(os.clock() * 10)` and `delay` to `task.delay` returning a `task.cancel` closure. Tests bind a `FakeScheduler` with `advance(seconds)`.

Design, taken from PITFALLS C4 and verified compatible with the docs above:
- `begin(durationSeconds)` allocates monotonically increasing `roundId`, computes `endsAtDeci = nowDeci() + duration*10` (integers), registers the backstop `delay` capturing `roundId`, and returns `roundId`.
- **Lazy deadline check:** every handler path (`claim`, `complete`) first asks `isOpen(roundId)`; if `nowDeci() >= endsAtDeci` it routes to `endRound(roundId, "Timeout")` and rejects the action.
- `endRound(roundId, reason)` is idempotent: returns `false` if `roundId` is not the active round or the round is already ended; otherwise sets state to ended **before** invoking `onEnded`, and fires `onEnded` exactly once. No yields inside.
- Stale callback: the backstop closure compares its captured `roundId` to the active one and no-ops on mismatch; additionally cancel it on `endRound`. **Test both guards independently** by giving `FakeScheduler` a mode where cancel is a no-op, so the token guard is proven without `task.cancel`.
- Boundary tests (the success criterion): (a) round 1 ends early, round 2 begins at t=10, advance to t=300 where round 1's stale backstop fires: round 2 is still active and `onEnded` has fired once; (b) last claim and timer expiry at the same tick in both orders: exactly one `onEnded`, and the second trigger returns `false`; (c) `endRound` called 100 times: one event; (d) a claim arriving at `nowDeci() >= endsAtDeci` is rejected. The tie rule (claim exactly at the deadline decisecond) is a spec-lock decision: recommended "events are processed in arrival order; the deadline is exclusive", and write it as the test.
- Scoring in later phases uses `nowDeci()` differences, so no float arithmetic ever reaches a score.

## Map contract (MAP-01)

### Instance layout (authoritative for Phase 3 and Phase 7)

Reconciles ARCH §6 with D-09 to D-11. Tags are authoritative for "what is a spot"; folders are organisation.

```
ServerStorage.Maps.<MapId>                Model (the .rbxm single top-level instance)
  Attributes: ContractVersion=1 (number), DisplayName (string), MinPlayers (number), MaxPlayers (number),
              SizeClass ("Small"|"Medium"|"Large")
  Geometry/            Folder   the ONLY thing ever cloned into Workspace; no Scripts of any kind
  Data/                Folder   server-only; never cloned (Rule 3)
    Bounds             Part     axis-aligned (identity rotation), Anchored, CanCollide=false, Transparency=1
    HiderSpawn         Part
    SeekerSpawns/      Folder   >=1 Part   (tag: SeekerSpawn)
    DefaultSpots/      Folder   >=16 Parts (tag: SpoonDefaultSpot)
    DecoyAnchors/      Folder   0..n Parts (tag: DecoyAnchor); folder required even if empty
    CardTable/         Folder
      TableAnchor      Part
      Seats/           Folder   exactly Seat1..Seat9, Parts, clockwise, look vector toward TableAnchor
```
Anchors are Parts (not Attachments) so position and orientation are readable without world-transform maths in Lune. All anchor Parts: `Anchored`, `CanCollide=false`, `CanQuery=false`, `CanTouch=false`, `Transparency=1`, size 1x1x1. Metadata uses Attributes on the root Model, not a ModuleScript, so the `.rbxm` carries no code (D-07) and the validator can ban scripts outright. The physical table and chairs (the visible set) live under `Geometry`; `Data/CardTable` holds only anchors.

Open choice to flag, not decide: `Bounds` is one axis-aligned Part. L-shaped mansions may want a union of volumes. Allowing `Bounds` to be a Folder of AABBs later is backward compatible with a `ContractVersion` bump.

### Luau types (`src/server/core/MapContract.luau`)
```lua
--!strict
export type Vec3 = { x: number, y: number, z: number }
export type Pose = { position: Vec3, look: Vec3 }            -- look = unit look vector
export type SizeClass = "Small" | "Medium" | "Large"
export type MapMetadata = {
	contractVersion: number, id: string, displayName: string,
	minPlayers: number, maxPlayers: number, sizeClass: SizeClass,
}
export type Aabb = { min: Vec3, max: Vec3 }
export type MapSpec = {
	metadata: MapMetadata,
	bounds: Aabb,
	hiderSpawn: Pose,
	seekerSpawns: { Pose },     -- >= 1
	defaultSpots: { Pose },     -- >= 16
	decoyAnchors: { Pose },     -- >= 0
	cardTable: { anchor: Pose, seats: { Pose } },  -- seats: exactly 9, index = seat number
}
-- Input to the validator: plain data, produced by a snapshotter
export type Node = {
	name: string, className: string,
	attributes: { [string]: string | number | boolean },
	tags: { string },
	position: Vec3?, size: Vec3?, look: Vec3?, anchored: boolean?,
	children: { Node },
}
export type Issue = { code: string, path: string, message: string }
```
`MapValidator.validate(root: Node): ({ Issue }, MapSpec?)` returns stable issue codes (for example `MAP_MISSING_FOLDER`, `MAP_SPOT_COUNT`, `MAP_SEAT_COUNT`, `MAP_META_INVALID`, `MAP_SCRIPT_FORBIDDEN`) so tests assert codes, not prose.

### What the Phase 1 validator checks (D-12) and what it defers
Checks: root Model with `Geometry` and `Data` folders; metadata attributes well-formed (`ContractVersion == 1`; non-empty `DisplayName` within a length cap; integers with `3 <= MinPlayers <= MaxPlayers <= 10`; `SizeClass` in enum); `Bounds`, `HiderSpawn`, `TableAnchor` present with positive size where relevant; `SeekerSpawns >= 1`; **tagged spots >= 16** inside `DefaultSpots`, and any tagged part outside its folder is an error; `DecoyAnchors` folder present; **exactly 9 seats named `Seat1`..`Seat9`**; no `Script`/`LocalScript`/`ModuleScript` anywhere; all anchors inside `Bounds` (cheap AABB test, recommended); each seat's look vector points toward `TableAnchor` and the seat order has consistent winding (recommended). **Deferred to Phase 3:** walkability, standable surfaces, `PlacementRules` per spot, reachability from spawns, sightlines.

### Reading `.rbxm` in CI
Yes. `@lune/roblox` `deserializeModel(fs.readFile(path))` returns `{ Instance }` [VERIFIED: Lune `types.d.luau`]. Instances expose `GetChildren`, `GetDescendants`, `FindFirstChild`, `IsA`, `GetAttribute`, `GetTags`/`HasTag` (reads the `Tags` property) [VERIFIED: Lune source `instance/base.rs`, `instance/mod.rs`]. Reading `Attributes`, `Tags`, `CFrame`, `Size`, `Anchored` from a Studio-exported binary `.rbxm` is expected to work but **has not been executed**; the integration test on the gray-box file is the proof. Use `part.CFrame` (and `.Position`/`.LookVector` derived from it) rather than the `Position` property, which is derived rather than serialised [ASSUMED].

### Gray-box reference map (D-08) without Studio
The container has no Studio. Lune can construct Instances and `serializeModel` them [VERIFIED: `types.d.luau`, `Instance.new` in README examples]. Recommended: `scripts/maps/generate-graybox.luau` builds a multi-room floor plan (walls, a corridor loop, a raised ledge, 16+ tagged spots at varied heights and occlusion, 3+ seeker spawns, hider spawn, bounds, a table with 9 seat anchors in a lobby) and writes `maps/gray-box.rbxm`. The committed `.rbxm` is then the artefact; a human refines it in Studio and re-exports. This is a deviation in spirit from D-07 ("non-script instances are authored in Studio") forced by the container, so it is listed under Open Questions. "Genuine sightlines" cannot be machine-verified; it is a MANUAL-CHECKS item (M-06).

## Test harness (FOUND-03)

- Runner: `lune run tests/run.luau [-- --filter name]`. It discovers `tests/**/*.spec.luau` with `fs.readDir`/`fs.isDir`, `require`s each (spec files return `function(t) ... end`), prints a per-test line and a summary, and calls `process.exit(1)` on any failure or any uncaught error.
- **Meta-test the harness:** one spec spawns `lune run tests/run.luau` against a fixture directory containing a deliberately failing spec via `process.exec` and asserts a non-zero code. Without this, "tests pass in CI" could be vacuous.
- Fuzz helper: `fuzz(name, { seed, iterations, gen, check })` prints the seed on failure and accepts `--seed=` to reproduce. Phase 1 ships the helper with a trivial property (for example the PRNG itself) so Phase 2 only supplies generators.
- **PRNG gotcha:** doubles lose precision above 2^53, so a 32-bit multiply-based generator (mulberry32, PCG32) is wrong in Luau. Use **xorshift32 with `bit32`** (`x ~ (x << 13)`, `x ~ (x >> 17)`, `x ~ (x << 5)` via `bit32.bxor/lshift/rshift`, results already truncated to 32 bits). Keep it in `src/server/engine/Rng.luau` as the first real, pure engine file so the FOUND-06 lint has something to chew on.
- Performance for the 100k+ action fuzz is a Phase 2 concern; Lune runs the same Luau VM, no JIT is needed for tens of thousands of iterations per second [ASSUMED].
- Spec-lock items (Open Questions 1, 2, 17): write them as `t.todo("CARD-09 ...")` and `t.todo("CARD-10 ...")` entries in `tests/engine/spec_lock.spec.luau` with the resolved default in the description (no engine exists yet), plus the real FOUND-08 cap tests. The harness must count `todo` separately and print them; they do not fail the run (the engine is out of scope) but they are visible, and Phase 2 converts them.

## Structural guards

### FOUND-06, engine purity: recommended implementation
**Selene `std = "luau"` allow-list + `luau-lsp analyze --platform standard` over `src/server/engine` and `src/server/core`**, plus `check-guards` hygiene rules.
- Selene catches any *value* reference to a name not in Luau's std (`game`, `workspace`, `script`, `task`, `Instance`, `Vector3`, `Enum`, `tick`, `wait`, `warn`...) as `undefined_variable` (deny).
- luau-lsp in standard platform catches *type-position* references (`local p: Instance`) as unknown types, and unknown globals as strict-mode errors. Expected from design; **[ASSUMED] until executed**, so the fixtures below must include a type-only reference.
- `check-guards` additionally fails on `selene: allow` / `--# selene:` suppression comments inside pure zones, and on any `require` that is not a literal `./`, `../` or `@self/` path.
- Why not a Lune grep alone: a deny-list is incomplete by construction. Why not Selene alone: it cannot see type annotations, and suppression comments can defeat it.

**Failing fixtures (success criterion 3), each executed through the real command and asserting non-zero exit from `tests/guards/guards.spec.luau` using `process.exec`:**
- `fixtures/engine-roblox-value/src/server/engine/Bad.luau`: `--!strict` file doing `local players = game:GetService("Players")`. Expected: `selene --config selene.pure.toml` exits 1.
- `fixtures/engine-roblox-type/src/server/engine/BadType.luau`: `export type Holder = { part: Instance }`. Expected: standard-platform `luau-lsp analyze` exits 1 (and Selene exits 0, proving the second layer is needed).
- `fixtures/engine-suppressed/...`: a `game` reference under `--# selene: allow(undefined_variable)`. Expected: `check-guards` exits 1.
- `fixtures/engine-clean/...`: a minimal clean engine file. Expected: all three exit 0, so a false positive also fails the suite.

### FOUND-05, no gameplay-to-cosmetics import path: recommended implementation
**`scripts/ci/check-guards.luau`**, a Lune script with its own literal-require resolver and transitive closure, run against the repo root by default or any root passed as an argument.
- Roots: every file named `Scoring*`, `CardTable*`, `SpoonPlacement*` anywhere under `src/`, plus every file in the pure zones.
- Forbidden targets: any resolved path (or raw `@game/...` string) with a segment matching, case-insensitively, `cosmetic`, `shop`, `catalog`, `loadout`, `economy`, `monetiz`, `gamepass`, `purchase`, `skin`. The list lives in one config table at the top of the script so a new module family is a one-line change.
- Sound by construction inside guarded zones because the same script forbids everything it cannot resolve: a non-literal `require`, a bare `require` identifier not immediately called with a string literal, `getfenv`, `loadstring`, `rawget(_G`, `script.Parent`-style instance requires. The threat model is accident and agent drift, not an adversary with metatable tricks; state that in the script header.
- Comment stripping before scanning (line comments and `--[=*[ ... ]=*]` blocks). Do not strip strings: leaving them in only produces false positives, which fail loudly and safely.
- Resolution: from file `a/b/C.luau`, `./X` is `a/b/X.luau|.lua|/init.luau`; `../X` one directory up; `@self/X` valid only from `init.luau`. Also resolve every require a second time using the **DataModel** rules against the Rojo project mounts (`src/server` to `ServerScriptService.Server`, etc.) and fail on a mismatch; that is the static twin of the built-place check.

**Failing fixtures:**
- `fixtures/import-direct/src/server/core/Scoring.luau` requires `../CosmeticsBridge` (file name `CosmeticsBridge.luau` exists in the fixture). Expected exit 1.
- `fixtures/import-transitive/...`: `CardTable` requires `./Util`, `Util` requires `./ShopCatalog`. Expected exit 1 and the message names the full path `CardTable -> Util -> ShopCatalog`.
- `fixtures/import-nonliteral/...`: `require(script.Parent.Cosmetics)` in a pure zone. Expected exit 1 (non-literal).
- `fixtures/import-clean/...`: passes, exit 0.

### Additional cheap rules in the same script
R1 every `.luau` under `src`, `scripts`, `tests` (not fixtures) starts with `--!strict` on line 1 (FOUND-02). R4 Net hygiene (above). R5 secret names: the literals `SpoonDefaultSpot`, `DecoyAnchor`, `SeekerSpawn` must not appear under `src/client` or `src/shared` (supports Rule 3, noted in SUMMARY as a Phase 1 lint/CI-grep item).

## Persistence isolation (FOUND-07)

### Human gate: exact steps (Creator Hub and Studio), to be written verbatim into `MANUAL-CHECKS.md` and `NEEDS-HUMAN` notes
1. In Creator Hub, create a **new experience** (a new *universe*), for example "Spoons (Dev)". A new *place inside the production experience is not enough*: data stores are "consistent per game, so any place in a game can access and change the same data" [CITED: `data-stores/index.md`].
2. In Studio: File, Publish to Roblox As..., choose the new dev experience. Note the dev **Place ID** and **Universe ID**.
3. In the dev experience only: Studio, File, Experience Settings, Security, enable **Enable Studio Access to API Services**, Save [CITED: `data-stores/index.md`].
4. In the **production** experience: confirm that toggle is **off** (it is off by default; Studio then fails with `StudioAccessToApisNotAllowed`) [CITED: error-codes page]. Also set the production place's Maximum Players to 10 (FOUND-08) in the place settings on the Creator Dashboard.
5. Record the dev Place ID in `default.project.json` as `servePlaceIds` so `rojo serve` refuses other places, and record both IDs in `shared/Config/Environments.luau` (placeholder `0` until the gate is done).
6. Verification: open the dev place in Studio, run a one-line DataStore write: it succeeds; open the production place file and attempt the same: it fails with `StudioAccessToApisNotAllowed`.

### Code side (small on purpose)
- No DataStore name suffixing is needed: isolation is by experience.
- A `Persistence` adapter selects `ProfileStore.Mock` when `ProfileStore.DataStoreState` is not `"Access"`, so an un-enabled Studio session degrades to a mock instead of crashing [VERIFIED: ProfileStore API]. ProfileStore itself (vendored single module, record commit `45c9847cbcf1fc260369c50eb335aba7c35aecdd`) is **not required to close Phase 1**; vendor it when the first phase saves data. ROADMAP's phrase "persistence skeleton" is satisfied by the environment config, the Mock-selection seam and the documented gate.
- Optional tripwire the planner may include only with owner consent, because D-13 rejected `IsStudio()` as the *mechanism*: refuse real stores when `RunService:IsStudio()` and `game.GameId` equals the production universe ID. Listed under Open Questions.

### Minimising the block
Do all code and CI first. The gate task is the **last wave**, depends on nothing else, and ships with pre-written instructions and a 3-line verification so the owner's work is about 15 minutes. Everything that consumes its output (`servePlaceIds`, `Environments.luau`) is a one-line follow-up committed after the gate. Phase 1 "closes" only when that follow-up lands (D-13), but no other task waits on it.

## Common Pitfalls

### Pitfall 1: Cross-mount relative requires pass Lune and fail in Roblox
**What goes wrong:** `require("../../shared/Config")` from `src/server/engine` resolves on disk but not in the DataModel.
**Why:** the filesystem mirrors the DataModel only inside one `$path` mount.
**How to avoid:** pure zones self-contained; DI for anything from another mount; the dual-resolver check in `check-guards` and `check-built-place`.
**Warning signs:** a pure-zone file with `../../`.

### Pitfall 2: `luau-lsp analyze` exits 0 with real problems
**What goes wrong:** lint warnings pass; `--formatter plain` always exits 0; missing definitions only warn.
**How to avoid:** `"lintErrors": true`; default formatter; always pass `--definitions`; analyse explicit directories so a typo exits 1. Add a fixture that must fail typecheck (for example assigning a string to a number) to prove the gate is live.

### Pitfall 3: Fixtures break their own tools
**What goes wrong:** deliberately bad files are picked up by `stylua --check`, Selene and `luau-lsp`, failing CI for the wrong reason.
**How to avoid:** `.styluaignore`, Selene `exclude`, luau-lsp `--ignore "**/fixtures/**"`, not Rojo-mounted, and `check-guards` takes a root argument so fixtures are scanned only when named.

### Pitfall 4: Guards with no proof they can fail
**What goes wrong:** a guard that never fires looks green forever.
**How to avoid:** the fixture suite runs through the real CLI and asserts non-zero exit; a `clean` fixture asserts zero. The harness itself is meta-tested.

### Pitfall 5: Rojo overwrites Studio edits to the mounted map
**What goes wrong:** `GrayBox` has a `$path`, so unexported Studio edits vanish on sync.
**How to avoid:** MANUAL-CHECKS documents "edit, export over `maps/*.rbxm`, commit"; D-06's manual check also verifies that Workspace content survives.

### Pitfall 6: Rojo plugin/CLI version drift
**What goes wrong:** 7.7.0 switched to websockets/MessagePack; a stale plugin cannot sync.
**How to avoid:** `rojo plugin install` from the pinned CLI; add the version to MANUAL-CHECKS.

### Pitfall 7: Selene std gaps
`math.isfinite` and friends are missing from Selene 0.32.0's `luau` std. Use the portable finite check. Re-test any new builtin against the pure config before using it in engine code.

### Pitfall 8: Rokit cannot reach `api.github.com`
The container returns 403, so `rokit install` fails there even though asset downloads work. Wave 0 includes the direct-download bootstrap; CI is unaffected.

### Pitfall 9: Throttled remotes queue instead of dropping
A flooding client builds a backlog at the server [CITED]. The gateway bucket must drop and count.

### Pitfall 10: CRLF breaks `stylua --check` on Windows
Add `.gitattributes` with LF normalisation.

### Pitfall 11: `lune setup` mutates `.luaurc`
Run in CI; committing the same alias makes it a no-op. Do not commit editor-specific settings it might also add.

## Code Examples

Illustrative and **unexecuted**. They show shape for tasks, not finished code.

### Token bucket step (pure) [pattern CITED: client-server-boundary.md token bucket example]
```lua
--!strict
export type Bucket = { tokens: number, last: number }
export type Spec = { burst: number, refillPerSecond: number }

local function take(b: Bucket, spec: Spec, now: number): boolean
	b.tokens = math.min(spec.burst, b.tokens + (now - b.last) * spec.refillPerSecond)
	b.last = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end
return take
```

### Portable finite check (replaces `math.isfinite` because of the Selene std gap)
```lua
--!strict
local function isFinite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
return isFinite
```

### Injected-clock round-end test (SCORE-06) shape
```lua
--!strict
local RoundLifecycle = require("../../src/server/core/RoundLifecycle")
local FakeScheduler = require("../harness/FakeScheduler")

return function(t)
	t.test("stale backstop from round 1 cannot end round 2", function()
		local sched = FakeScheduler.new({ cancelIsNoop = true }) -- prove the token guard alone
		local ended: { { number | string } } = {}
		local rl = RoundLifecycle.new({
			scheduler = sched,
			onEnded = function(id: number, why: string) table.insert(ended, { id, why }) end,
		})
		local r1 = rl:begin(300)
		assert(rl:endRound(r1, "AllSpoonsClaimed") == true)
		sched:advance(10)
		local r2 = rl:begin(300)
		sched:advance(290) -- t = 300: r1's stale backstop fires here
		t.equal(#ended, 1)
		t.equal(rl:isOpen(r2), true)
		sched:advance(10) -- t = 310: r2's deadline
		t.equal(#ended, 2)
		t.equal(rl:endRound(r2, "Timeout"), false) -- already ended, no second event
		t.equal(#ended, 2)
	end)
end
```

### Guard fixture runner (proves the guard fails through the real entrypoint)
```lua
--!strict
local process = require("@lune/process")
return function(t)
	t.test("transitive import into ShopCatalog fails the build", function()
		local r = process.exec("lune", { "run", "scripts/ci/check-guards.luau", "tests/guards/fixtures/import-transitive" })
		t.equal(r.ok, false)
		t.contains(r.stderr .. r.stdout, "CardTable -> Util -> ShopCatalog")
	end)
end
```

### Reading a map in Lune [VERIFIED API names: Lune `types.d.luau`]
```lua
--!strict
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local roots = roblox.deserializeModel(fs.readFile("maps/gray-box.rbxm"))
local map = roots[1]
local spots = {}
for _, d in map:GetDescendants() do
	if d:HasTag("SpoonDefaultSpot") then table.insert(spots, d) end
end
```

## State of the Art

| Old approach | Current approach | Changed | Impact |
|--------------|------------------|---------|--------|
| Instance-based `require(script.Parent.X)` only | Require-by-string with `./`, `../`, `@self`, `@game` in the Roblox runtime | documented in creator-docs `LuaGlobals.yaml` | One source tree can run under Lune and Roblox |
| Lune bare `require("foo")` | Luau-style: must start `./`, `../`, `@` | Lune 0.10.0, 2025-07-15 | Engine code must use relative paths |
| Same-remote-only ordering assumption | Ordered across remotes per connection | current creator-docs | Net design is free to use one envelope |
| `lune` reads files via `roblox.readPlaceFile(path)` | `deserializePlace(contents)` takes contents | Lune 0.11.x types | Use `fs.readFile` first |
| Aftman/Foreman | Rokit | Rojo-org standard | Locked by FOUND-02 |
| ProfileService | ProfileStore | author's README | Deferred use, vendor on first need |
| TestEZ | (archived) in-repo harness for pure code | Contradiction 1 | Locked |

**Deprecated/outdated claims from earlier research:** 900-byte unreliable cap (now 1000); DataStore 10/player (now 40/player); session steal 80 s (now 40 s); Rokit 2026 (it is 2025).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `luau-lsp analyze --platform standard` reports `Instance` as an unknown type and `game` as an unknown global in `--!strict` files | Structural guards (FOUND-06) | The second FOUND-06 layer would miss type-only references; fall back to a `check-guards` identifier scan for a known Roblox type list |
| A2 | `luau-lsp` expands `~` in `.luaurc` aliases | Concrete Configuration | `@lune/*` would fail to typecheck; use `--base-luaurc` generated in CI |
| A3 | `globalTypes.None.d.luau` is the right security level for normal game scripts | luau-lsp invocations | False "member not found" errors; switch to `PluginSecurity` or `RobloxScriptSecurity` |
| A4 | Lune reads `Attributes`, `Tags`, `CFrame`, `Size`, `Anchored`, and script `Source` correctly from Studio-exported binary `.rbxm`/`.rbxl` | Map contract, built-place check | Validator and built-place check need a different reader; fall back to `rojo build` to `.rbxmx` XML and parse |
| A5 | Roblox's `Position` property is derived and not serialised; use `CFrame` | Map contract | Minor |
| A6 | darklua `convert_require` can rewrite path requires to Roblox instance requires | Pattern 1 fallback | Fallback is unusable; try the DataModel-mirrored `src/` layout (also unverified) |
| A7 | Reserved servers/teleports may bypass the place Maximum Players | Player cap | Over-engineering only; code check is cheap |
| A8 | `ubuntu-latest` is a current hosted runner label | CI | Trivial |
| A9 | Lune executes tens of thousands of fuzz iterations per second without a JIT | Test harness | Phase 2 may need smaller iteration counts |
| A10 | Starting rate-limit numbers (burst 8/refill 8, etc.) are reasonable | Net gateway | Tuned in playtest (V-34); already LOW |
| A11 | Roblox relative string requires also work from a `Script` (not only `ModuleScript`) | Pattern 1 | `Main.server.luau` would need `@game` or instance paths; docs say "relative to the script that called require" which suggests yes |
| A12 | `GetServerTimeNow()` and `os.clock()` stay consistent enough on one server that an offset sampled at round start is safe for publishing deadlines | Round end | Clients show a drifting countdown; server logic is unaffected because it uses one clock |
| A13 | Selene's `exclude` globs, and `--config` with a second file, behave as read from source | Selene config | Fixture exclusion fails; use explicit file lists |

## Open Questions (RESOLVED)

> All six were resolved by owner decision after this research was written. See
> `01-CONTEXT.md` D-16..D-20 and its "Defaults Taken Without Asking" block.

1. **Gray-box map authored by a Lune generator rather than in Studio.**
   - Known: the container has no Studio; Lune can build and serialise instances; D-07/D-08 assume Studio authoring.
   - Unclear: whether the owner accepts a generated seed that a human then refines, or wants Phase 1 to wait for Studio time.
   - Recommendation: generate the seed headlessly (keeps CI-checkable and unblocks Phases 3 and 5 planning); mark the sightline review as MANUAL-CHECKS M-06. Needs a one-line owner confirmation because it bends D-07.
   - **RESOLVED: D-18** — owner approved the Lune generator as a deliberate, scoped exception to D-07. Shipped art maps (MAP-05..09) stay Studio-authored; only the gray-box fixture is code-generated.

2. **`Bounds` as a single axis-aligned Part vs a union of volumes.** Recommendation: single AABB in Phase 1, `ContractVersion` bump if Phase 7 needs L-shapes.
   - **RESOLVED: D-19** — single axis-aligned box Part per map. Coarseness accepted; moving to a union of volumes later is a contract change, not a rewrite.

3. **Optional in-code Studio tripwire for FOUND-07** (refuse real stores in Studio when `GameId` is the production universe). D-13 rejected `IsStudio()` as the mechanism, not necessarily as a supplement. Recommendation: omit unless the owner asks.
   - **RESOLVED: default taken** — include it as a *secondary* refusal on production DataStore writes, in addition to the separate test universe. D-13 rejected `IsStudio()` as *the mechanism*, not as defence in depth.

4. **Where does `Scoring`/`CardTable`/`SpoonPlacement` live?** Guard roots are by file name plus the pure zones. If Phase 5 puts `SpoonPlacement` in `src/shared/Placement` (ARCH layout), that mount cannot be a pure zone with the same self-containment rule.
   - **RESOLVED for Phase 1: guard roots are matched by basename anywhere under `src/`**, plus the pure zones listed in `scripts/ci/zones.luau` (`guardedNamePrefixes`). This means FOUND-05 holds wherever those files land, so Phase 1 needs no location decision. **Relocation is explicitly deferred to Phase 3**, which owns the placement rules and will choose `SpoonPlacement`'s home; if that mount cannot be a pure zone under the same self-containment rule, Phase 3 adjusts the zone list rather than weakening the guard.

5. **Tie rule at the round deadline** (claim exactly on the deadline decisecond). Recommendation above (deadline exclusive, arrival order).
   - **RESOLVED: default taken** — deadline **exclusive**, resolved by server arrival order. A claim arriving exactly on the deadline decisecond is outside the round. Exclusive is the simpler invariant to test.

6. **Persistence skeleton scope.** Roadmap text mentions it, requirements do not.
   - **RESOLVED: default taken** — environment config plus a Mock-selection seam only. No real DataStore work in Phase 1; that is Phase 7.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| node | optional tooling | yes | v22 | — |
| python3, cargo, docker | not required | yes | — | — |
| git, curl | everything | yes | — | — |
| rokit | FOUND-02 | no | — | **SUPERSEDED BY D-16.** `api.github.com` now returns 200, so `rokit install` works here as well as in CI (`setup-rokit`). The `scripts/dev/bootstrap-tools.sh` recommendation below is **void** — plan 01-01 asserts that file does NOT exist. Direct asset downloads remain the fallback only if a future environment blocks the API again. |
| rojo, stylua, selene, luau-lsp, lune | all | not installed | — | **Installed via Rokit per D-16** (not a bootstrap script). Release assets download (HTTP 200). Lune 0.11.1 was downloaded and printed `lune 0.11.1`; the other binaries were downloaded but **not executed** during research. **D-17: the owner has since approved executing the pinned toolchain**, so every gate command must be run for real in this phase. |
| Roblox Studio / Studio MCP | Rojo sync check, tag review, Net live test | no | — | MANUAL-CHECKS.md (D-04) |
| `create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`, `madstudioroblox.github.io`, `jsdotlua.github.io` | docs | no (`000`) | — | `Roblox/creator-docs` on raw.githubusercontent works |
| `raw.githubusercontent.com`, `git ls-remote/clone`, release asset URLs | verification, bootstrap | yes | — | — |
| `api.github.com` | Rokit, release lookups | **yes (200) — re-tested 2026-11-02** | — | **This row's 403 finding is STALE.** The owner opened the domain; Rokit works. `github.com` HTML pages and `gh api` were not re-tested. |

**Missing with no fallback:** Studio (covered by D-04 manual checks); the owner's Creator Hub gate (D-13).
**Missing with fallback:** all five tools and Rokit in this container (direct-download bootstrap). **Planner action:** make the bootstrap an explicit Wave 0 task and expect to need user permission to execute the pinned binaries.

## Validation Architecture

Framework summary: no test infrastructure exists (greenfield). Wave 0 creates all of it.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | In-repo harness on Lune 0.11.1 (`tests/run.luau`, `tests/harness/`); no Jest |
| Config file | none; `.luaurc` + `rokit.toml` pin the environment. Wave 0 creates `tests/run.luau` |
| Quick run command | `lune run tests/run.luau -- --filter <substring>` (target under 5 s) |
| Full suite command | `lune run scripts/verify.luau` (runs every CI step in order, then prints the manual-check list) |
| CI | `.github/workflows/ci.yml` runs the same steps on push and PR |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-01 | `Workspace` node has `$ignoreUnknownInstances == true`; project assembles; map mounts under `ServerStorage.Maps`; `.rbxm` has one root | unit + build | `lune run tests/run.luau -- --filter project` ; `rojo build default.project.json -o build/spoons.rbxl` | Wave 0 |
| FOUND-01 (Studio half) | Studio sync does not delete Workspace content | **manual** | MANUAL-CHECKS M-01 | Wave 0 |
| FOUND-02 | `rokit.toml` has exact versions for the five tools; every `.luau` starts `--!strict`; strict typecheck passes; a deliberately ill-typed fixture fails typecheck | unit + CI | `--filter project`, `lune run scripts/ci/check-guards.luau`, the two `luau-lsp analyze` commands | Wave 0 |
| FOUND-03 | Specs and fuzz run under Lune; a failing spec makes the runner exit non-zero | unit/meta | `lune run tests/run.luau` ; `--filter harness` | Wave 0 |
| FOUND-03 (require style) | Same source works under Lune and under Roblox resolution rules | spike + CI | `tests/spike/require.spec.luau`; `lune run scripts/ci/check-built-place.luau build/spoons.rbxl` | Wave 0 |
| FOUND-03 (Roblox runtime half) | `require` works in a real Studio server | **manual** | MANUAL-CHECKS M-02 | Wave 0 |
| FOUND-04 | Malformed/NaN/inf/wrong-phase/over-rate/unknown-intent rejected and never dispatched; per-player buckets; refill over time; only `NetServer` uses `OnServerEvent` | unit + guard | `--filter gateway` ; guards R4 + fixture | Wave 0 |
| FOUND-04 (live remote) | Real client firing a malformed payload is rejected | **manual** | MANUAL-CHECKS M-03 | Wave 0 |
| FOUND-05 | Direct, transitive and non-literal imports of cosmetics/shop fail; clean passes | fixture via real CLI | `--filter guards` | Wave 0 |
| FOUND-06 | Roblox value reference, type-only reference, suppressed reference in engine fail; clean passes | fixture via real CLI | `--filter guards` (invokes `selene --config selene.pure.toml`, standard-platform `luau-lsp`, `check-guards`) | Wave 0 |
| FOUND-07 | Environment config present; Mock selection when `DataStoreState ~= "Access"`; `servePlaceIds` recorded after gate | unit + **manual gate** | `--filter persistence`; MANUAL-CHECKS M-04 (owner) | Wave 0 / human |
| FOUND-08 | `Admission` boundary table (0,2,3,9,10,11, bad inputs); `canStartMatch` | unit | `--filter admission` | Wave 0 |
| FOUND-08 (platform) | Place Maximum Players = 10 set; 11th join refused | **manual** | MANUAL-CHECKS M-05 | Wave 0 |
| MAP-01 | Valid snapshot passes; each missing/wrong element produces its stable issue code; gray-box `.rbxm` validates; no script instances; 16 tagged spots, 9 seats | unit + integration | `--filter maps` ; `lune run scripts/maps/validate-map.luau maps/gray-box.rbxm` | Wave 0 |
| MAP-01 (loads in Studio) | `MapLoader` reads `ServerStorage.Maps.GrayBox` with no per-map branch; tags visible | **manual** | MANUAL-CHECKS M-06 | Wave 0 |
| SCORE-06 | Exactly one end; stale callback inert (with and without working cancel); boundary both orders; idempotent | unit | `--filter round` | Wave 0 |

### Sampling Rate
- **Per task commit:** pre-commit hook (stylua + selene on staged files) plus `lune run tests/run.luau -- --filter <area>`.
- **Per wave merge:** `lune run scripts/verify.luau` (full CI mirror locally).
- **Phase gate:** CI green on the branch head, `scripts/verify.luau` output attached, and every MANUAL-CHECKS item signed off (M-01..M-06 including the owner's M-04) before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `scripts/dev/bootstrap-tools.sh` (direct-download pinned tools) and permission to run them
- [ ] `rokit.toml`, `stylua.toml`, `selene.toml`, `selene.pure.toml`, `.luaurc`, `.styluaignore`, `.gitattributes`, `.gitignore`
- [ ] `tools/types/globalTypes.None.d.luau` (sha256 above), `roblox.yml` via `selene generate-roblox-std`
- [ ] `tests/run.luau`, `tests/harness/{Test,Fuzz,FakeClock,FakeScheduler}.luau`, harness meta-test
- [ ] The require spike (A/B files, spec, `check-built-place.luau`)
- [ ] `scripts/ci/check-guards.luau` and all fixtures
- [ ] `.github/workflows/ci.yml`, `.githooks/pre-commit`, `scripts/verify.luau`, `MANUAL-CHECKS.md`
- [ ] First pass of the whole CI chain executed once end to end (nothing here has been run)

**Machine-checkable in CI:** FOUND-02, 03, 05, 06, FOUND-04 logic, FOUND-08 logic, SCORE-06, MAP-01 structure, FOUND-01 file shape and `rojo build`. **Needs a human with Studio:** Rojo sync preserving Workspace (M-01), Roblox-runtime `require` (M-02), live remote rejection (M-03), the test-universe gate and production toggle check (M-04, owner), place Maximum Players and 11th-join (M-05), gray-box load and sightline review (M-06).

## Security Domain

`security_enforcement` is not disabled in config, so this section applies.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Roblox platform identity; server uses `Player.UserId` from `OnServerEvent` |
| V3 Session Management | no | Platform sessions; ProfileStore session locking is later |
| V4 Access Control | yes | Phase gating in the gateway; server derives actor from `Player`, never from payload (Rule 7) |
| V5 Input Validation | yes | Schema validators with NaN/inf/type/range/length checks; reject unknown keys |
| V6 Cryptography | no | none in this phase |
| V10 Malicious Code / supply chain | yes | Pin tools by exact version; pin third-party GitHub Action by commit SHA; vendored types pinned by sha256; no scripts allowed inside map `.rbxm` |
| V13 API / Web Service | yes | Rate limiting per player per intent; bounded queues; drop, do not buffer |
| V14 Configuration | yes | No secrets in repo; `permissions: contents: read` in CI; Studio API access off on production |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| NaN/inf in a numeric field bypassing comparisons | Tampering | `isFinite` before any range check [CITED: client-server-boundary.md] |
| Remote flood causing server backlog | Denial of service | Token bucket that drops; throttled excess is otherwise delayed, not dropped [CITED] |
| Wrong-phase or replayed intent | Tampering | Phase gate in gateway; round-ID tokens for scheduled work |
| Stale scheduled callback ends the wrong round | Tampering (logic) | Round-ID token + idempotent `endRound` (SCORE-06) |
| Client names a target/seat | Elevation of privilege | Intent carries stable IDs only; server resolves (Rule 7) |
| Malicious script smuggled in a map `.rbxm` or free model | Tampering | Validator forbids Script/LocalScript/ModuleScript in maps |
| Hidden data replicated to clients | Information disclosure | Map `Data` lives in `ServerStorage`; secret tag names banned in client/shared code (R5) |
| Compromised third-party CI action | Tampering | SHA-pin `setup-rokit`; minimal `permissions` |
| Studio session mutating production data | Tampering | Separate experience; production Studio API access off |
| `rojo serve` reachable via DNS rebinding | Spoofing | Rojo 7.7.x validates Host/Origin [VERIFIED: CHANGELOG]; keep default bind |

## Sources

### Primary (HIGH confidence)
- Roblox `creator-docs` repo, commit `c8f5276703948ef4868c9b9fd44fae619dbe2f11` (2026-10-29): `content/en-us/reference/engine/globals/LuaGlobals.yaml` (`require`), `.../classes/Players.yaml` (`MaxPlayers`), `.../classes/UnreliableRemoteEvent.yaml`, `.../classes/Workspace.yaml` (`GetServerTimeNow`), `.../libraries/os.yaml`, `.../libraries/math.yaml`, `.../classes/DataModel.yaml` (`BindToClose`, `GameId`), `scripting/events/remote.md`, `scripting/security/client-server-boundary.md`, `cloud-services/data-stores/{index,error-codes-and-limits}.md`
- Rojo v7.7.1 source and CHANGELOG: `src/project.rs`, `src/snapshot_middleware/{rbxm,mod}.rs`, `plugin/src/Reconciler/diff.lua`, `src/cli/{build,sourcemap,plugin}.rs`
- Rokit v1.2.0 source/CHANGELOG/README: `lib/manifests/rokit.rs`, `lib/tool/spec.rs`, `src/cli/install.rs`, `lib/sources/github/mod.rs`, `scripts/install.sh`
- Lune v0.11.1 source/CHANGELOG/tests: `crates/lune/src/cli/setup.rs`, `crates/lune-std-roblox/types.d.luau`, `crates/lune-roblox/src/instance/{base,mod}.rs`, `tests/require/tests/*`, `.luaurc`
- luau-lsp 1.70.1 source/CHANGELOG/README: `src/main.cpp`, `src/AnalyzeCli.cpp`, `src/operations/RequireGraph.cpp`, `scripts/README.md`, `scripts/globalTypes.None.d.luau`
- Luau 0.740: `Analysis/src/Frontend.cpp` (`classifyLints`), `Config/src/Config.cpp`, `VM/src/lmathlib.cpp`
- Selene 0.32.0 source/CHANGELOG: `selene/src/{main,opts}.rs`, `selene-lib/src/lib.rs`, `default_std/luau.yml`, `docs/src/roblox.md`, `docs/src/lints/restricted_module_paths.md`
- StyLua v2.6.0 README and CHANGELOG
- MadStudioRoblox/ProfileStore `ProfileStore.luau`, `README.md`, `wally.toml`; MadStudioRoblox/ProfileService README
- `CompeyDev/setup-rokit` v0.2.1 `action.yml`, `README.md`; `git ls-remote --tags` for all tools

### Secondary (MEDIUM confidence)
- Chrrxs/robloxstudio-mcp README (tool names, tags only)
- WebSearch results for Roblox require-by-string and DataStore isolation (used only to find the creator-docs paths; conclusions rest on the repo files)

### Tertiary (LOW confidence)
- darklua `convert_require` existence (docs.rs listing seen in a search result, not fetched)
- Everything in the Assumptions Log

### Not reachable
`create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`, `madstudioroblox.github.io`, `jsdotlua.github.io` (one attempt each, HTTP `000`), and `api.github.com` / github.com HTML (403).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH, versions and asset URLs verified against tags, changelogs and downloads; nothing executed.
- Architecture (require approach, pure cores, guards): MEDIUM-HIGH, rests on documented semantics on both sides; the dual-resolver check plus Studio M-02 close the remaining gap.
- Net, round-end, admission designs: HIGH on platform facts (official docs), MEDIUM on exact numbers (LOW for rate-limit values).
- Map contract and `.rbxm` reading: MEDIUM, Lune capability read from source, binary-format round trip unexecuted.
- Pitfalls: HIGH for those derived from source (exit codes, std gaps, API behaviour).

**Research date:** 2026-11-02
**Valid until:** about 2026-12-02 for tool versions (Rojo, Lune, Selene, luau-lsp all released within the last six weeks and move fast); Roblox docs claims re-check at Phase 4.
