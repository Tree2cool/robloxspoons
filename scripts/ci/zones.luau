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
	--
	-- PHASE 4 ADDED NOTHING HERE, deliberately (D-38, proposed and then withdrawn 2026-11-05).
	-- Two reasons, both verified against check-guards.luau rather than reasoned about:
	--   1. It would be redundant. Line 341: "Roots for R2/R3: guarded-name files under src/, then
	--      EVERY FILE IN A PURE ZONE." So src/server/core/* (CardTable, CardRouting, IdleClock,
	--      StallDetector, RejectThrottle, CardSeatHold) and src/shared/Card/* (once it is a pure
	--      zone) are already guarded roots whatever they are named.
	--   2. The one prefix that would add something -- `Card`, which would pull in src/client/ui --
	--      is harmful. (a) Guarded roots also get R3, whose `os.` needle scans comment-stripped
	--      text INCLUDING string literals; `pos.X` and `anchorPos.Y` both match it, so a `Card*`
	--      client file would fail the build on ordinary identifiers. (b) Phase 7 REQUIRES the card
	--      UI to import cosmetic data: the dealer's deck skin and deal animation play to the whole
	--      table (CARD-18). Rule 1 protects the modules that decide OUTCOMES, not the layer that
	--      draws them.
	-- tests/guards/fixtures/import-pure-zone proves the by-location coverage against THIS list.
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
		-- Phase 4: the card UI must not subscribe to a remote itself. One client file owns the
		-- receive side, exactly as one server file owns the send side (R4).
		OnClientEvent = "src/client/net/ClientNet.luau",
	},
	-- R5: hidden-data vocabulary must never reach client or shared code (CLAUDE.md rule 3)
	-- `rankOf` (Phase 4, D-37 as corrected 2026-11-05): State.rankOf IS the shuffled deck
	-- permutation, so it is the single identifier that turns a card id into a rank.
	-- SCOPE, stated precisely because the original decision got it wrong: R5 scans `sf.text`, which
	-- line 324 sets to stripComments(raw). So a `rankOf` in a COMMENT is invisible to this rule --
	-- and leaks nothing, so that is the right scope. String literals are KEPT in sf.text, so
	-- `rankOf` in code or in a string IS caught, which is the leak that matters. This is why Phase 4
	-- put copy assignment server-side in CardRouting rather than in src/shared/Card/Faces.luau.
	secretNames = { "SpoonDefaultSpot", "DecoyAnchor", "SeekerSpawn", "HiderSpawn", "rankOf" },
	-- Fallback mount map when a scanned root has no default.project.json (fixtures)
	mounts = {
		{ path = "src/server", datamodel = "ServerScriptService.Server" },
		{ path = "src/shared", datamodel = "ReplicatedStorage.Shared" },
		{ path = "src/client", datamodel = "StarterPlayer.StarterPlayerScripts.Client" },
	},
	ignoreSegments = { "fixtures", "build", "vendor", "tools" },
}
