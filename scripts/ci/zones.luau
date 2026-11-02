--!strict
-- Single source of truth for the structural guards.
-- `pureZones` are the directories that must contain NO Roblox API reference (FOUND-06) and that
-- are required directly by Lune specs. `src/shared/Net` is included because Phase 1's Manifest
-- and Validate are deliberately Roblox-API-free so the gateway vectors can be tested headless.
-- If a later phase needs a Roblox datatype validator, it goes in a NEW directory outside this
-- list; nothing is ever removed from `src/server/engine` or `src/server/core`.
return {
	pureZones = { "src/server/engine", "src/server/core", "src/shared/Net" },
	-- R1 (strict header) scans everything we author. R3 (non-resolvable constructs)
	-- scans ONLY the pure zones and guarded roots -- see implementation item 4. A
	-- repo-wide R3 would self-trip on tests/run.luau's computed require and on
	-- check-guards.luau's own getfenv strings. Do not widen it to match R1.
	scanDirs = { "src", "scripts", "tests" },
	-- R4 (Net hygiene), R5 (secret names) and R6 (DataModel twin) scan ONLY shipped code.
	-- This is not a loophole, it is correctness: this very file names `OnServerEvent` and
	-- `SpoonDefaultSpot` as table keys, `tests/guards/guards.spec.luau` names them as expected
	-- output substrings, and `tests/`/`scripts/` legitimately require across Rojo mounts
	-- (`../../src/server/...`) because they are never mounted at all. Scanning them with these
	-- three rules makes `check-guards` fail on its own source, and the only way an executor could
	-- make it pass would be to WEAKEN the rules. Narrow the scope instead.
	shippedDirs = { "src" },
	-- FOUND-05 roots: any file under src/ whose name starts with one of these (CLAUDE.md rule 1)
	guardedNamePrefixes = { "Scoring", "CardTable", "SpoonPlacement" },
	-- A resolved require path containing any of these segments (case-insensitive) is forbidden
	-- from a guarded root. One-line change to add a new module family.
	forbiddenSegments = {
		"cosmetic",
		"shop",
		"catalog",
		"loadout",
		"economy",
		"monetiz",
		"gamepass",
		"purchase",
		"skin",
	},
	-- R4 Net hygiene: these identifiers may appear ONLY in the named file
	netOwners = {
		OnServerEvent = "src/server/services/NetServer.luau",
		OnServerInvoke = "src/server/services/NetServer.luau",
		RemoteFunction = "src/server/services/NetServer.luau",
		UnreliableRemoteEvent = "src/server/services/NetServer.luau",
		FireClient = "src/server/services/NetServer.luau",
		FireAllClients = "src/server/services/NetServer.luau",
		FireServer = "src/client/net/ClientNet.luau",
	},
	-- R5: hidden-data vocabulary must never reach client or shared code (CLAUDE.md rule 3)
	secretNames = { "SpoonDefaultSpot", "DecoyAnchor", "SeekerSpawn", "HiderSpawn" },
	-- Fallback mount map when a scanned root has no default.project.json (fixtures)
	mounts = {
		{ path = "src/server", datamodel = "ServerScriptService.Server" },
		{ path = "src/shared", datamodel = "ReplicatedStorage.Shared" },
		{ path = "src/client", datamodel = "StarterPlayer.StarterPlayerScripts.Client" },
	},
	ignoreSegments = { "fixtures", "build", "vendor", "tools" },
}
