# Stack Research

**Domain:** Roblox multiplayer party game (real-time simultaneous card passing + hide-and-seek hunt), Luau, server-authoritative, Robux cosmetics, PC + mobile parity
**Researched:** 2026-11-02
**Confidence:** MEDIUM overall (tooling versions HIGH/MEDIUM, Roblox platform API behavior MEDIUM because create.roblox.com / devforum were unreachable from the research sandbox; see "Verification Gaps")

## Verification Gaps (read first)

- `create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`, `madstudioroblox.github.io`, `jsdotlua.github.io` all failed DNS in the research session. Roblox platform claims below come from WebSearch snippets of the official docs, GitHub pages (reachable), and training knowledge. Items are tagged accordingly.
- GitHub release pages show day/month only for several tools. Years were inferred from surrounding release history. Tools with an explicit 2026 date on the page: StyLua, Selene, luau-lsp, pesde.
- `gh api` was blocked for non-project repos, so no machine-readable release data. Re-run `rokit add` / `wally` resolution at M0 and let the tools tell you the real latest version.
- Every version below must be treated as "pin at M0 after the tool confirms it resolves", not as gospel.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| Luau with `--!strict` on every file | Studio-bundled (luau-lsp 1.70.1 bundles Luau 0.740) | Language + type checking | Strict types are the cheapest bug-prevention an AI agent has when it cannot human-playtest. New Type Solver is default for nonstrict/nocheck since the Nov 2025 announcement; strict is opt-in per Roblox. Use strict anyway. | HIGH (type solver status from official release-note snippets) |
| Rojo | 7.7.1 | Filesystem to Studio sync, `rojo build`, `rojo sourcemap`, `rojo syncback` | Mandated by the `roblox-ai-build` skill (git is source of truth). 7.7.0 added `syncback` (pull Studio-authored maps/UI back into the repo) and websocket/MessagePack serve. 7.7.1 fixes Windows path issues. | HIGH (GitHub releases page; 7.7.1 dated 02 Oct, year inferred 2026) |
| Rokit | 1.2.0 | Toolchain manager (pins Rojo, StyLua, Selene, luau-lsp, Wally) | Current successor to Aftman/Foreman in the Rojo org; one `rokit.toml` gives the agent and CI identical tool versions. | MEDIUM (version/date from GitHub page; year inferred) |
| Roblox Studio MCP | Pin `@chrrxs/robloxstudio-mcp` to an explicit version at M0, not `@latest` | Agent <-> Studio bridge (execute Luau, screenshots, playtest, multi-client test) | Skill pins Chrrxs fork: exposes `capture_screenshot`, `multiplayer_playtest`, `eval_server_runtime`, `eval_client_runtime`, `execute_luau`, `solo_playtest`, `get_runtime_logs`. Built-in official Studio MCP now exists (multi-agent update announced Aug 2026) and Roblox says it is the recommended path; the skill claims it cannot screenshot; re-verify at M0, because that claim may now be stale. | MEDIUM |
| ProfileStore | Vendor latest `main` as a single ModuleScript (no semver on repo page) | Player data: session lock, autosave, reconcile | Successor to ProfileService from the same author (loleris / MadStudioRoblox); ProfileService is not receiving updates. Skill mandates "ProfileStore, session-locked". Distributed as one ModuleScript, so vendoring it avoids a package-manager dependency for the one runtime lib you cannot do without. | MEDIUM (README + forum consensus; no official deprecation notice for ProfileService found; wiki unreachable) |
| Raw Roblox networking (`RemoteEvent` + thin typed `Net` module) | n/a | Client <-> server intents and state | See Networking section. ~10 players and low-rate discrete card actions do not justify a codegen/serialization library. | HIGH (reasoned; limits from official docs snippets) |
| Plain typed Luau modules + explicit state machine | n/a | Authoritative match/round/card-ring state | See State section. | HIGH (design recommendation) |
| Raw `Instance` UI + design-token module | n/a | All UI | See UI section. | MEDIUM-HIGH |
| `MarketplaceService` Game Passes (primary) | n/a | VIP lobby + permanent cosmetics | See Monetization section. | MEDIUM |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Jest-Lua (`jsdotlua/jest-globals` + `jsdotlua/jest`) | JestGlobals 3.10.0 (shown in README/migration guide); runner package version not verified | Unit tests for pure game logic (card ring, scoring, four-of-a-kind, seat order) | From M0/first card-engine phase. TestEZ is archived (Sep 2024). Jest v3.x has no globals: `require` `describe/it/expect` from JestGlobals explicitly. Runs only inside Roblox (not Lune/CI without Roblox). |
| Wally | 0.3.2 stable (0.4.0-alpha pre-releases exist) | Package manager for dev-deps (Jest) | Only if you take Jest-Lua. Dependency surface is tiny, so this choice is reversible. Run `wally-package-types` (version unverified) after install or strict-mode type resolution of Wally packages breaks. |
| pesde | 0.7.4 (09 Sep 2026, explicit date) | Alternative package manager; can consume Wally packages | Switch to this if Wally install/types become painful. Actively maintained; Wally's last stable looks older. |
| StyLua | 2.6.0 (10 Oct 2026) | Formatter | Always. `stylua --check` in CI; agent runs `stylua src` before commit. |
| Selene | 0.32.0 (01 Oct 2026) | Linter | Unused variables, shadowing, deprecated API. `std = "roblox"`. Overlaps with luau-lsp analyze; keep config minimal. |
| luau-lsp | 1.70.1 (27 Sep 2026) | CLI typechecker (`luau-lsp analyze`) + editor LSP | The headless "does it typecheck" gate for the agent and CI, no Studio needed. Needs `rojo sourcemap` output + Roblox global type definitions. |
| Lune | 0.11.1 (21 Oct per GitHub page, year inferred) | Standalone Luau runtime for scripts | Optional: repo scripts (asset-registry validation, manifest generation). Do not depend on it for game tests. |
| Signal + Trove (Sleitnick RbxUtil `signal`, `trove`) | versions not verified | Event objects and cleanup | Optional; a 40-line in-repo Signal and a small Janitor are equally fine. Use one or the other, not ad-hoc BindableEvents everywhere. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `rojo serve` + Studio plugin | Live sync of scripts | Rule: scripts are written to the filesystem only. MCP creates/edits non-script Instances (maps, UI shells). Never let MCP `execute_luau` write script Source, or Rojo will overwrite it and git will not see it. |
| `rojo sourcemap default.project.json -o sourcemap.json` | Feeds luau-lsp | Regenerate in CI and pre-commit. |
| `rojo syncback` (7.7.0+) | Pull Studio-built content into repo | Use for UI screens and map metadata the agent built through MCP. Check output into git. |
| Roblox Device Emulator (Studio) | Phone/tablet/PC viewport testing | Mandatory review step per skill: phone-resolution capture of every screen. |
| Studio local multi-client test (via `multiplayer_playtest`) | 3-10 client card-pass testing | Only way to exercise the real simultaneous-passing path before publish. |
| Open Cloud Luau Execution + `place-ci-cd-demo` (Roblox repo) | Optional headless test runs in CI | Needs an API key and uploaded test place = human gate (`NEEDS_HUMAN.md`). Not v1-critical; Jest in Studio via MCP is the default loop. Rate limits in docs conflicted (5/min vs 45/min), verify. |

## Concrete Recommendations by Question

### 1. Tooling and workflow

**Use Rojo. Not Studio-only.** The AI agent drives Studio through MCP, but filesystem edits are far cheaper in tokens, diffable, reviewable and resumable across sessions than script edits through MCP round-trips, and the `roblox-ai-build` skill makes this a hard rule. MCP stays for: running Luau in Studio, placing/iterating Instances (maps, UI), screenshots, play/multiplayer tests.

Repository shape (recommended):

```
default.project.json        # Rojo project
rokit.toml  wally.toml  selene.toml  stylua.toml  .luaurc
src/server/   -> ServerScriptService.Server
src/client/   -> StarterPlayer.StarterPlayerScripts.Client
src/shared/   -> ReplicatedStorage.Shared   (pure game logic lives here; no Instance access)
vendor/ProfileStore.luau
Packages/     (wally output, gitignored)
maps/*.rbxm   (per-map geometry referenced via $path so `rojo build` assembles the full place)
manifest/     (buildings.manifest.json, asset-kit.json per skill)
```

Critical Rojo gotcha: set `$ignoreUnknownInstances: true` on `Workspace` (and Lighting) in the project file, otherwise Rojo deletes the maps/terrain you built in Studio on next sync. Terrain and large maps do not diff in git; keep per-map `.rbxm` files and accept binary diffs. (MEDIUM, from Rojo behavior knowledge, not re-verified this session.)

Quality gates (run by agent before every commit; same commands in CI):

```
stylua --check src
selene src
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap sourcemap.json src      # add --definitions globalTypes.d.luau per luau-lsp docs
rojo build default.project.json -o build/spoons.rbxl  # smoke test: project still assembles
```

Testing: Jest-Lua, in-Studio, driven through MCP (`execute_luau` / playtest). The architectural rule that makes this work: the card engine, seat ring, scoring and round state machine are pure modules in `src/shared/` taking and returning plain tables. They need no Instances, so they can be unit-tested exhaustively (3-player edge case: 1 spoon; 10-player: 8 spoons; ring closing; wrap; joker wilds). Instance-dependent code (hide-spot validation raycasts, spoon pickup) is tested by Studio play-mode scripts that assert on state and logs, per the skill. Live `TeleportService` reserved servers, live DataStore load and real Robux purchases validate only on a published place (human gate).

CI: GitHub Actions with Rokit install, then the quality-gate commands. Headless test execution is optional (Open Cloud Luau Execution).

Pin `@chrrxs/robloxstudio-mcp` to an exact version rather than `@latest --auto-install-plugin`: the server executes arbitrary Luau in your Studio session and `@latest` means unreviewed upstream changes run with that power. Write the live tool names into `CLAUDE.md` at M0 as the skill requires, behind a single adapter module.

### 2. Networking

**Recommendation: plain `RemoteEvent`s behind one in-repo typed `Net` module. No ByteNet / Blink / Zap / Warp / Red.**

Why:
- Traffic is tiny: up to ~10 players, each issuing a handful of discrete actions per second at peak (pile take, select, pass). Remote bandwidth is nowhere near the constraint; Roblox's limit is roughly 500 invocations/second per client per remote type, orders of magnitude above human tapping. (HIGH, official docs snippet)
- Buffer/codegen libraries add a toolchain step (Blink and Zap require a codegen binary and an IDL) and a dependency whose maintenance you do not control. Benchmarks in the community are self-run and contradict each other; one source claims a ByteNet crash vector, single-source and unverified. For an agent-driven project each extra moving part is a failure surface.
- Libraries are valuable at hundreds of replicated entities per frame (shooters, MMOs). This game's hot path is a card event, not a position stream.
- Revisit trigger: if MicroProfiler / Network stats shows remote traffic on the hot path (it should not), adopt **Blink** (stable 0.18.9; 1.0.0-pre.10 exists, avoid pre-releases) or **Zap** (0.6.29), both of which give typed contracts via codegen. Prefer those over ByteNet/Warp. (LOW-MEDIUM, comparisons are community-sourced)

Primitive guidance:
- **`RemoteEvent` for everything gameplay-critical** (reliable, ordered). Card actions MUST be reliable.
- **`UnreliableRemoteEvent`**: not needed for v1. Candidate only for lossy cosmetic streams (hunt trail/emote flourishes). Payload limit is 900 bytes (official page; older mirrors say 1000; oversize is silently dropped live), and it shares the ~500/s budget. Never use for state that must converge.
- **`RemoteFunction`: avoid.** Never server->client invoke (a malicious or lagging client can yield the server thread forever). Client->server request/response can be replaced by event + ack/reject event. If used at all, only client->server, wrapped in a timeout.

Wire design for the card engine (MEDIUM, design recommendation):
- Client sends **intents, not state**: `TakeFromLeftPile {}`, `SelectCard {cardId}`, `PassCard {cardId}`. The server derives the seat from the `Player`, never from an argument.
- Server assigns **opaque per-round card ids**; the client never sends rank/suit, and never learns other players' hands.
- Private hand -> `FireClient` to the owner only. Public state (phase, seat ring order, pile *counts*, who left the table, timer, scoreboard) -> broadcast. Never put hand contents in Attributes/ValueObjects (replicated to everyone).
- Sequence numbers: client attaches a monotonically increasing `seq`; server replies with accept/reject + authoritative snapshot of the affected pile/hand. Client may animate optimistically (local select highlight, immediate left-pile lock) but reconciles to the server snapshot. Mobile latency of 150-300 ms makes pure wait-for-server feel bad; optimistic local lock avoids double-take.
- Server resolves races by arrival order per seat queue; the card ring is single-threaded Luau, so no locking is needed as long as each handler runs to completion without yielding mid-mutation. Do not yield (DataStore, Marketplace, Wait) inside a card-ring mutation.

Rate limiting and validation (server `Net` module):
- Per-player, per-remote **token bucket** (`os.clock()` based). Starting numbers to tune in playtest: card actions burst 8, refill ~8/s; purchase/UI prompts burst 2, refill 1/s; hide-spot placement burst 10, refill 10/s. Drop excess silently, count violations, kick only on sustained abuse (e.g. hundreds of violations in 10 s), since a laggy-then-bursting phone is not an exploiter.
- Validate every argument: `typeof`, finite numbers (reject NaN/inf), integer ranges, string lengths, `Instance` args checked for class and for being a descendant of an allowed root (or better, never accept Instances from clients).
- Gate by phase: reject card actions outside the Card phase, from seated-out players, from the hider, etc. State machine owns legality.

### 3. State management

**Recommendation: server-side plain typed module tables with an explicit phase state machine; card ring as a pure reducer-style module. No Rodux, no Matter, no Charm for v1.**

- `Match` (roster, round index, hider rotation, totals) -> `Round` (phase: Hide / Card+Hunt / RoundEnd / Podium, timer, spoon set) -> `CardTable` (ordered seat ring with per-seat hand, left pile, right pile aliasing the next seat's left pile, dealer deck, joker count).
- Model the ring as an array of seats plus pure functions: `takeFromLeft(table, seat)`, `passToRight(table, seat, cardId)`, `detectFourOfAKind(hand)` (jokers as wild), `removeSeat(table, seat)` (closes the chain by relinking neighbours; with the wrap the dealer deck stays under the last seat's right pile). Everything returns new/updated plain tables, so Jest can drive thousands of random simulated rounds and assert invariants: total cards constant, no deck exhaustion, spoons = N - 2, ring never has a hole.
- Scoring (1000 - 100/place; remaining seconds x 10; hider survival) in a pure `Scoring` module, taking timestamps as arguments (inject `now`) to be deterministic in tests.
- Rodux is retired legacy Roblox tooling and ceremony without benefit here. Matter ECS targets thousands of entities; this game has ~10 players and a handful of piles. Charm (0.11.1, active) and its `charm-sync` are a reasonable escape hatch if client state graph grows; it is not needed for v1.
- Client keeps a small `ClientState` module (current phase, my hand, ring snapshot, timer) with `Changed` signals that the UI subscribes to. Rendering code reads state, never mutates it.
- Match-level state is **session-scoped**, not in the profile. Only durable per-player data (loadout, lifetime stats, schema version) goes to ProfileStore (per skill Section 9 "save split").
- Shrinking circle on the client is a layout recomputation from the ring snapshot (tween seat positions), not a physics concern.

### 4. UI framework

**Recommendation: raw Instances built in code by small component functions, driven by one `Tokens` module. No Roact/React-Lua/Fusion/Iris.**

- Why raw: the card UI is ~5 animated cards, 2 piles, a ring/seat indicator and a few menus. That is within reach of straightforward imperative code with tweens; frameworks add indirection, a Wally dependency with typing friction, and per-frame overhead on low-end phones. It also matches the skill's workflow of building and visually iterating UI through MCP and persisting approved screens as idempotent builder scripts or Rojo `.rbxmx` (`syncback`).
- React-Lua (jsdotlua, v17.2.1) is Roblox's own and the right pick *if* UI grows past roughly a dozen stateful screens; avoid for v1. A DevForum respondent noted games benefit from explicit, low-overhead code; the community is split. (LOW, opinion)
- Fusion 0.3 (last release shown is 0.3-beta, 30 Aug, 2024-ish per page): stale and a different mental model (scopes). Vide (Solid-like, 218 commits, no releases listed): promising but low adoption and unverified maintenance. Iris is immediate-mode for debug/dev tooling, not shipping game UI. Skip all four.

Cross-device parity (MEDIUM-HIGH; ScreenInsets enum values verified in official docs snippets, rest is established practice):
- **One input path:** use `GuiButton.Activated` (fires for mouse click, touch tap and gamepad select). Do not fork logic on `UserInputService.TouchEnabled`; branch only on layout/size if at all. Tap-select-then-tap-send was specified precisely so one handler serves both.
- **Sizing:** Scale-based `UDim2` + `UIAspectRatioConstraint` / `UISizeConstraint` / `UITextSizeConstraint`; a root `UIScale` driven by viewport height (reference 1080p, clamped, recomputed on `ViewportSize` change) keeps card art consistent between a 6-inch phone and a 27-inch monitor.
- **Safe areas:** set `ScreenGui.ScreenInsets = DeviceSafeInsets` for interactive HUD (clears camera notches/cutouts); `CoreUISafeInsets` when UI must also avoid Roblox's top-bar; `TopbarSafeInsets` for top-bar-adjacent elements; `None` only for non-interactive backgrounds. Do not use raw `GuiService:GetGuiInset()` math as the primary mechanism. Test with the Studio Device Emulator.
- **Targets:** minimum ~48 px tap targets (Roblox's own mobile guidance is roughly this; exact number not re-verified), 5-card hand must fit portrait-width 360 px with overlap/fan; nothing critical under the thumb stick area (bottom-left) or jump button (bottom-right). Landscape is the default phone orientation in Roblox, but test portrait.
- **Hunt controls:** use the default Roblox PlayerModule touch thumbstick and `ProximityPrompt` for spoon pickup (cross-input, built-in touch button, no custom hit-testing). Cap prompt `MaxActivationDistance` to implement the close-range pickup, and server-validate distance and line of sight on pickup.
- **Feedback:** explicit button states and `TweenService` micro-animations for pile take / card select / pass (the game's "feel" lives here), per the skill's UI polish rules.

### 5. Monetization

Two currencies/archetypes check against `robux-item-design`: **this project has no earned currency** (match points are score, not spendable) and is cosmetics + access only. The skill's "price ladder of currency packs" does not apply and should not be invented; its constraints that do apply: server-side grant, persisted, exact price/grant shown, no gambling, `competitive_advantage: false` on every item, single versioned `EconomyConfig`, and a one-sentence `reason_to_buy` per SKU. Record in the EconomyConfig rationale that currency packs, time-skips and accelerators are deliberately absent (they would violate the "nothing purchasable affects competitive outcome" rule or have no friction to sell). Archetypes used: `cosmetic`, `convenience` (VIP access), optionally `starter_bundle`.

| Item | Product type | Why |
|------|--------------|-----|
| VIP lobby access | **Game Pass** (primary). Subscription is the alternative if recurring revenue is wanted. | One-time permanent access; Roblox holds ownership. Subscriptions API exists (`GetUserSubscriptionStatusAsync(player, subscriptionId)` server-only, `PromptSubscriptionPurchase` client-side; verified by reference snippet) but adds renewal-state handling and subscription tier setup. |
| Spoon skins, special decks, character cosmetics (hats, trails, emotes), hider effects, podium cosmetics | **Game Pass per permanent cosmetic or per cosmetic *bundle*** (primary) | Roblox is the source of truth for ownership; no DataStore ownership record, no `ProcessReceipt`, no double-grant bugs, ownership survives data loss. Matches the skill rule: permanent unlocks -> game passes. |
| Anything repeatable (none currently) | Developer Product | Only if design adds a consumable later (e.g. gifting). Requires full receipt pipeline below. |

Decision flagged for roadmap (research flag): game passes must be created in Creator Hub (human gate, or Open Cloud if a pass-creation API is available; **not verified**). A catalog of 50+ individually priced cosmetics is tedious as passes. Fallback pattern: **Developer Product per cosmetic, ownership recorded in the ProfileStore profile, server rejects re-prompt if already owned**, using the hardened receipt flow below. Choose after the first catalog size estimate; design the `Shop` module behind an interface (`Owns(player, itemId)`, `Prompt(player, itemId)`) so either backend plugs in.

Game Pass flow (MEDIUM; pcall and caching behavior from forum + docs snippets):
1. On `PlayerAdded`, for each equipped/visible-relevant pass, `MarketplaceService:UserOwnsGamePassAsync(userId, passId)` in `pcall` with retry; cache result in the session profile table. Never call it per-frame or per-respawn.
2. On `MarketplaceService.PromptGamePassPurchaseFinished`, treat the client-originating event as a *trigger only*, then re-confirm with a server-side `UserOwnsGamePassAsync` before granting. Results may lag right after purchase (a ~10 s false window is reported by forum posts; unverified), so poll with backoff a few times instead of trusting one call.
3. Persist only the *equipped loadout* and settings in ProfileStore; owned = derived from Roblox. Keep a cached `owned` mirror for lobby UI speed, but re-verify on lobby entry.
4. Equip validation: server checks ownership before allowing any equip, since all cosmetics are equipped in the lobby only; round start snapshots loadouts (dealer's deck skin, hider's spoon skin) and ignores changes mid-round.

Developer Product receipt flow (only if used):
- `MarketplaceService.ProcessReceipt` is a single callback per game; `BindReceiptHandler` (per-ReceiptType, optional product-ID filter, takes precedence, falls through to ProcessReceipt) is the newer alternative (official reference snippet). Do not set both for the same products.
- Idempotency: key on `receiptInfo.PurchaseId`; claim the id atomically (inside the session-locked profile via `profile.Data.ProcessedReceipts`, or `UpdateAsync`) before granting. Reference sample warns the same receipt can reach multiple servers.
- Return `Enum.ProductPurchaseDecision.PurchaseGranted` only after the grant is durable in the claimed record; `NotProcessedYet` on any failure or if the profile is unavailable. Do not yield indefinitely: receipts are reportedly polled every 10 s and overlapping handlers cause "already being processed" errors, and a Sep 2026 DevForum post mentions a "ProcessReceipt needs a fix" banner tied to listing products outside the game (LOW; could not open the post; check Creator Hub for the banner after setup).
- Prompt via `PromptProductPurchase`; show exact Robux price and what is granted; never prompt for something already owned.

Hard design constraint carried into stack: nothing purchasable may reach scoring, spoon findability, or round logic. Enforce structurally: `Scoring`, `CardTable`, `SpoonPlacement` modules must not import `Shop`/`Cosmetics`. Cosmetic data flows one way: loadout snapshot -> visual layer only. Hider "glint color" must be audited so it cannot change detection radius, LOS or contrast beyond the default (the PROJECT.md "visual only" rule).

### 6. Data persistence

- **ProfileStore** (vendored). Not ProfileService (no updates), not DataStore2 (obsolete), not raw `DataStore:SetAsync` (no session lock, dupe/overwrite risk). Backwards-compatible with ProfileService data if ever needed (per docs snippet).
- API shape to expect (from author docs/training; wiki unreachable, **verify on first use**): `ProfileStore.New(storeName, template)`, `store:StartSessionAsync(key, ...)` (returns profile or nil), `profile:Reconcile()`, `profile.Data`, `profile:AddUserId(userId)` (GDPR), `profile.OnSessionEnd`, `profile:EndSession()`; a Mock store for Studio when API Services are off.
- Profile template (versioned): `{ SchemaVersion = 1, Loadout = {...}, Settings = {...}, Stats = {...}, ProcessedReceipts = {} }` (receipts only if dev-product path). Migrations keyed on `SchemaVersion`.
- Lifecycle per skill: start session on `PlayerAdded` (kick if it fails), end on `PlayerRemoving`, rely on ProfileStore autosave plus `BindToClose` flush.
- Do NOT write match score, hands, or timers into the profile (session-scoped). Store lifetime stats (matches won) only at match end.
- **MemoryStoreService:** not needed for v1. Only consider for cross-server VIP matchmaking/party codes. Per skill Section 9, instance VIP lobbies via `TeleportService` **reserved servers** and treat the main lobby as the default join. (Native Roblox paid private servers are the platform-level alternative to a coded VIP lobby; not researched here, flag.)
- Limits/cost awareness: in-experience DataStore budgets scale with concurrent users (official snippet); Roblox's "Extended Services" data store storage/request pricing was announced for 2026 (default allowance reported as 100 MB + 1 MB per lifetime player; docs pages disagreed on applicability and request prices). At this game's scale it is immaterial, but record the footprint (one small profile per player) in `PERF_BUDGET.md`. (LOW-MEDIUM)
- "Studio Access to API Services" must be enabled by a human for DataStore/ProfileStore testing (skill human gate).

### Anti-cheat stack notes that affect tool choices

- Hidden spoons that exist in `Workspace` replicate their positions to every client (ESP risk). Keep placed spoons out of `Workspace` until the hunt starts, and rely on `StreamingEnabled` with a modest `StreamingTargetRadius` so far spoons are not replicated to a seeker at all. The skill already mandates StreamingEnabled; this is an additional reason. Expect this to be a roadmap pitfall for the Hunt phase. (MEDIUM, reasoned from platform behavior)
- Server validates all spoon pickups (distance + raycast LOS) and all hider placements (raycast to standable surface, `PathfindingService` reachability from the seeker spawn, visibility from a standable position).

## Installation

```bash
# One-time: install Rokit (https://github.com/rojo-rbx/rokit), then in the repo:
rokit init
rokit add rojo-rbx/rojo@7.7.1
rokit add JohnnyMorganz/StyLua@2.6.0
rokit add Kampfkarren/selene@0.32.0
rokit add JohnnyMorganz/luau-lsp@1.70.1
rokit add UpliftGames/wally@0.3.2      # only if using Jest-Lua via Wally
# optional: rokit add lune-org/lune@0.11.1 ; rokit add JohnnyMorganz/wally-package-types@<verify>

# wally.toml (dev-dependencies only)
# [dev-dependencies]
# JestGlobals = "jsdotlua/jest-globals@3.10.0"
# Jest        = "jsdotlua/jest@<match JestGlobals; verify>"
wally install

# ProfileStore: download the single ModuleScript from the MadStudioRoblox/ProfileStore repo
# into vendor/ProfileStore.luau and record its commit hash in manifest/asset-kit.json

# MCP (pin an explicit version; do not use @latest)
claude mcp add robloxstudio -- npx -y @chrrxs/robloxstudio-mcp@<pinned> --auto-install-plugin
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Rojo + git | Studio-only + MCP | Never for this project; skill forbids logic that exists only in Studio and token cost is higher. |
| Wally | pesde 0.7.4 | If Wally install or type resolution breaks; pesde is more actively released and consumes Wally packages. |
| Jest-Lua | TestEZ | Never for new work (archived Sep 2024). |
| Plain RemoteEvents + `Net` wrapper | Blink / Zap | If profiling shows remote traffic is hot. Prefer these over ByteNet/Warp for typed contracts. |
| Plain module state | Charm 0.11.1 (+ charm-sync) | If the client state graph balloons (many screens reading many slices). |
| Raw Instance UI | React-Lua 17.2.1 | If UI grows past ~12 stateful screens or you add a UI-heavy second mode. |
| Game Pass per cosmetic | Developer Product per cosmetic + profile ownership | If the catalog is too large to manage as passes, or you need rotating/limited availability. |
| Game Pass for VIP | Subscription | If recurring revenue and a retained-benefit model are desired. |
| ProfileStore | Hand-rolled `UpdateAsync` session lock | Never; cost/benefit is poor. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| ProfileService (new work) | Not receiving updates; ProfileStore is the successor, same author, compatible data | ProfileStore |
| DataStore2 / raw `SetAsync` for player data | No session lock, dupe and overwrite risk | ProfileStore |
| TestEZ | Archived Sep 2024 | Jest-Lua |
| Rodux / Roact (legacy) | Retired lineage; React-Lua is the maintained successor if you need it | Plain state / raw UI (React-Lua if needed) |
| Matter ECS | Built for thousands of entities; unjustified ceremony for ~10 players | Plain typed modules |
| Fusion 0.3 / Iris for game UI | Stale mental-model churn / debug-tool-oriented | Raw UI + Tokens |
| RemoteFunction server->client | Client can hang the server thread | RemoteEvent + ack |
| UnreliableRemoteEvent for card/state traffic | Dropped packets break convergence; 900-byte cap, silent drops | Reliable RemoteEvent |
| Client-trusted score, hand, or four-of-a-kind | Trivially exploitable (project constraint) | Server-authoritative reducer |
| `PromptGamePassPurchaseFinished` as a grant | Client-originated signal | Server re-check with `UserOwnsGamePassAsync` |
| Score multipliers or any competitive-affecting SKU | Project hard rule + policy risk | Cosmetics and access only |
| Inventing a soft currency / currency packs | Not in the design; skill's currency-pack ladder does not fit a points-scored cosmetics game | Cosmetic SKUs behind `EconomyConfig` |
| `@latest` auto-updating MCP in production workflow | Arbitrary-Luau-executing tool; unreviewed updates | Pinned version, adapter module |
| Unsanitized free-model assets | Malware vector (skill Section 3) | Edit-mode insert, strip scripts, registry in `asset-kit.json` |
| `Workspace` without `$ignoreUnknownInstances` in Rojo | Rojo deletes Studio-built maps | Set it, keep maps as `.rbxm` |

## Stack Patterns by Variant

**If the Studio built-in MCP gains screenshot/input/multiclient tools:**
- Move off the Chrrxs fork; keep the adapter module so it is a one-file change.
- Because the skill's "official MCP cannot screenshot" statement may be out of date (Aug 2026 official update focused on multi-agent support).

**If remote profiling shows traffic problems at 10 players:**
- Introduce Blink/Zap for the hot remotes only, keep the rest plain.
- Because codegen contracts reduce bytes and add compile-time types, but only matter on hot paths.

**If the cosmetic catalog exceeds what you can manage as Game Passes:**
- Switch `Shop` backend to Developer Products + profile ownership + hardened receipt handler.
- Because Creator Hub management of dozens of passes is manual; the `Shop` interface hides the change.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| luau-lsp 1.70.1 | Luau 0.740 | Bundled; Studio's Luau may differ slightly; Selene 0.32.0 parser added `if local`/`if const` syntax, so keep Selene/luau-lsp/StyLua updated together if you use new Luau syntax. |
| Rojo 7.7.1 | Studio Rojo plugin of the same version | Install plugin matching CLI (`rojo plugin install` or Studio plugin marketplace) to avoid sync protocol mismatch; 7.7.0 switched to websockets/MessagePack. |
| Wally packages | Strict mode | Run `wally-package-types` against `sourcemap.json` after `wally install` or imported types resolve to `any`. |
| JestGlobals 3.x | No globals | Explicitly require `describe`/`it`/`expect`; TestEZ-style matchers differ (`toBe` vs deep `toEqual`). |
| Charm 0.11.1 | Newer Luau | Release notes mention type-error fixes for a new Luau version; only relevant if adopted. |
| ProfileStore | ProfileService data | Same keys load; do not mix `MessageAsync` use with old module on the same data. |

## Sources

- GitHub rojo-rbx/rojo releases (7.7.1, 7.7.0 syncback + websocket) - HIGH
- GitHub rojo-rbx/rokit releases (1.2.0) - MEDIUM (year inferred)
- GitHub UpliftGames/wally releases (0.3.2 stable, 0.4.0-alpha) - MEDIUM
- GitHub pesde-pkg/pesde releases (0.7.4, 09 Sep 2026) - HIGH
- GitHub JohnnyMorganz/StyLua (2.6.0, 10 Oct 2026), Kampfkarren/selene (0.32.0, 2026-10-01), JohnnyMorganz/luau-lsp (1.70.1, Luau 0.740) release pages - HIGH
- GitHub MadStudioRoblox/ProfileStore README (single ModuleScript, player-data oriented, `StartSessionAsync`) + WebSearch of forum threads on ProfileStore vs ProfileService - MEDIUM
- GitHub jsdotlua/jest-lua README (JestGlobals 3.10.0 Wally install, aligned to Jest 27.4.7) + WebSearch snippets of TestEZ migration guide and TestEZ archive status - MEDIUM
- GitHub 1Axen/blink releases (0.18.9 / 1.0.0-pre.10), red-blox/zap releases (0.6.29), ffrostflame/bytenet README, WebSearch of community benchmark threads - MEDIUM/LOW
- GitHub littensy/charm releases (0.11.1), jsdotlua/react-lua releases (17.2.1), dphfox/Fusion releases (0.3), centau/vide README - MEDIUM
- GitHub Chrrxs/robloxstudio-mcp README (tool list, install command, based on boshyxd v2.7.0); WebSearch (Roblox Rust MCP repo note that built-in Studio MCP is now recommended; Aug 2026 multi-agent update via MoguraVR) - MEDIUM
- WebSearch snippets of official Roblox docs: UnreliableRemoteEvent (900-byte limit, ~500/s shared), MarketplaceService reference (`BindReceiptHandler`, `GetUserSubscriptionStatusAsync`, `PromptSubscriptionPurchase`), ScreenInsets enum, DataStore rate limits page (last updated 2026-10-19), Extended Services, Luau Execution API, 2026-08-10 release notes (New Type Solver) - MEDIUM (primary pages unreachable in sandbox)
- Local skills: `roblox-ai-build` (Rojo-as-source-of-truth, MCP pin, ProfileStore, UI rules, reserved-server VIPs, human gates), `robux-item-design` (EconomyConfig, game-pass vs dev-product rule, no-pay-to-win) - HIGH (read directly)
- Not reachable, unverified: create.roblox.com, devforum.roblox.com (including the Sep 2026 "ProcessReceipt needs a fix" post), robloxapi.github.io, madstudioroblox.github.io, jsdotlua.github.io

---
*Stack research for: Roblox multiplayer party game (Spoons)*
*Researched: 2026-11-02*
