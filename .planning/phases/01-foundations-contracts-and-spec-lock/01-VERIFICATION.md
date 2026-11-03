---
phase: 01-foundations-contracts-and-spec-lock
verified: 2026-11-03T06:10:00Z
verifier: Claude (gsd-verifier)
commit: 70fd9ce
status: human_needed
score: 9/10 requirements COMPLETE, 1 PARTIAL
gate: none — Phase 1 is ungated (G1 belongs to Phase 2)
automated_evidence:
  verify_script: "14/14 steps green (16.9s), lune run scripts/verify.luau"
  test_suite: "333 passed, 0 failed, 3 todo (14.5s), lune run tests/run.luau"
  ci: "green on HEAD 70fd9ce — run 41584751433, all 14 gates as separate green steps"
requirements:
  FOUND-01: COMPLETE
  FOUND-02: COMPLETE
  FOUND-03: COMPLETE
  FOUND-04: COMPLETE
  FOUND-05: COMPLETE (with a scoping condition on Phase 7)
  FOUND-06: COMPLETE (transitive closure probed and held)
  FOUND-07: COMPLETE (with a standing re-check condition on Phase 7)
  FOUND-08: PARTIAL
  MAP-01: COMPLETE
  SCORE-06: COMPLETE
gaps:
  - truth: "FOUND-08: the server enforces a 3-player minimum to start"
    status: partial
    reason: >
      The 10-player cap half is implemented and wired (PlayerGate.new() is called from
      Main.server.luau on PlayerAdded). The 3-minimum half is a tested predicate with ZERO
      callers: PlayerGate.canStart / Admission.canStartMatch are referenced only by their own
      definitions and by tests. There is no match-start path in Phase 1, so nothing is being
      refused. This is not the deferred M-05 observation — it is a missing enforcement point.
    artifacts:
      - path: "src/server/services/PlayerGate.luau:73"
        issue: "PlayerGate.canStart has no caller anywhere in src/"
      - path: "src/server/Main.server.luau"
        issue: "no match-start path exists, so the 3-minimum is never consulted"
    missing:
      - "Either mark FOUND-08 partial, or carry an explicit item: Phase 6 (MATCH-01) must route match start through PlayerGate.canStart before FOUND-08 is ticked."
  - truth: "Traceability: every Phase 1 requirement has a completion claim"
    status: partial
    reason: >
      No SUMMARY marks MAP-01 or SCORE-06 as requirements-completed. 01-12, the phase-close plan,
      lists only FOUND-01..FOUND-08. Both are only ever requirements-contributed (01-06, 01-07,
      01-10, 01-11). The code and tests for both are strong and I verify both as COMPLETE, so this
      is a bookkeeping gap, not a capability gap — but anything driven off requirements-completed
      would leave MAP-01 and SCORE-06 silently Pending.
    artifacts:
      - path: ".planning/phases/01-foundations-contracts-and-spec-lock/01-12-SUMMARY.md"
        issue: "requirements-completed omits MAP-01 and SCORE-06"
    missing:
      - "Record MAP-01 and SCORE-06 completion at phase close (verifier's verdict: both COMPLETE)."
findings_summaries_overclaim:
  - claim: "Vendored, sha256-pinned Roblox type definitions (01-01-SUMMARY.md:11)"
    reality: >
      The only automated check is byte-length equality (677555) in tests/project/project.spec.luau:86
      and tests/traps/traps.spec.luau:184. No gate computes a hash. The sha256 is recorded in prose
      only. The file's hash does currently match the recorded value
      (9ad75109b8dc9197f6d1726208bfa0b12de47c3a43672a4fa43227f0cec609ee), so nothing is wrong today —
      but the file is length-pinned, not sha256-pinned, and a same-length substitution passes CI.
    severity: low
  - claim: "servePlaceIds must never name the production experience (tests/project/project.spec.luau:78-83)"
    reality: >
      The loop compares each servePlaceIds entry (a PlaceId) against Environments.PRODUCTION_UNIVERSE_ID
      (a UniverseId). The two namespaces never collide, so the assertion can never fire. No
      PRODUCTION_PLACE_ID constant exists to compare against. Probed both ways: the test case still
      fails correctly, because the preceding t.equal(servePlaceIds[1], DEV_PLACE_ID) does the real work.
      So the protection is genuine; the labelled sub-assertion is dead weight.
    severity: low
  - claim: "ROADMAP Phase 1: Spec lock (resolved defaults, each written as a test)"
    reality: >
      CARD-09, CARD-10 and CARD-12 are t.todo placeholders in tests/engine/spec_lock.spec.luau, not
      tests. The justification given in the file is sound (no engine exists until Phase 2, and a fake
      passing test is worse than a visible todo), and the decisions are recorded in ROADMAP.md and in
      the todo strings. But they are documented, not tested, and are honoured only if Phase 2 reads
      them. FOUND-08's spec-lock item (cap of 10) IS genuinely covered, by tests/core/admission.spec.luau.
      None of these are Phase 1 requirements, so nothing in the ten is affected.
    severity: informational
findings_coverage_notes:
  - "FOUND-05 is a filename deny-list. PROBED: a guarded root (Scoring.luau) importing a cosmetics module named Wardrobe.luau — matching none of the nine forbiddenSegments — leaves check-guards fully green (exit 0). Nothing forces Phase 7 cosmetics/shop code into a directory or filename that matches a forbidden segment, so the guard can become vacuous by naming alone."
  - "src/server/services/RoundDriver.luau has zero coverage of beginRound and deadlineUnix: neither is called anywhere, in tests or at runtime (Main.server.luau constructs the driver but never starts a round). Workspace:GetServerTimeNow() is therefore wholly unexercised. SCORE-06's exactly-once property is proven only in the pure core — which is where the logic lives, so this is a scope note, not a defect."
  - "Persistence.select (the Roblox adapter that reads game.GameId) is not unit-testable and is not covered. This is precisely the unobserved half recorded as M-04 check 3 / D-23."
  - "MapLoader.snapshot must emit the identical Node shape as scripts/maps/snapshot.luau, and no automated test can compare them (MapLoader needs Roblox). The only evidence of parity is M-06's live Studio load, which did pass end to end."
  - "The fuzz harness is proven on toy properties at 200 default iterations. Phase 2's 100k-action conservation fuzz has never been run through it."
  - "src/shared/Config/Environments.luau is mounted to ReplicatedStorage, so the production universe id and dev place id replicate to clients. Harmless (Roblox place and universe ids are public), noted for completeness."
findings_probes_that_held:
  - "FOUND-06 transitive hole: an engine module reaching a Roblox API through a helper OUTSIDE the pure zone. Probed two variants in a throwaway clone. Variant 1 (helper with a non-literal require) caught twice over — check-guards R3 closure (exit 1) AND the standard-platform typecheck. Variant 2 (helper with only a bare `workspace` global, no non-literal require) caught by the standard-platform typecheck, which follows the relative require: analyze exit 1, `TypeError: Unknown global 'workspace'`. The guard is stronger than its own documentation claims."
  - "roblox.yml silent degradation: probed selene with the pinned Roblox std missing (exit 1, 'failed to collect roblox standard library') and truncated to 100 bytes (exit 1, 19 errors). Both fail loudly. roblox.yml has no integrity check, but it needs none — it cannot degrade silently."
deferred:
  - truth: "M-04 check 3: the PersistenceMode boot tripwire fires in a live Studio session aimed at production"
    addressed_in: "First real deploy (D-23)"
    evidence: "Secondary control; logic unit-tested in tests/core/persistence.spec.luau (7 cases incl. an exhaustive Refuse > Mock > Real table); primary control verified by M-04 check 2 with the specific reason StudioAccessToApisNotAllowed. Observing it requires a publish over the live production place because servePlaceIds deliberately blocks rojo serve from reaching it."
  - truth: "M-05: an 11th join is observed being refused"
    addressed_in: "First ten-player playtest (D-23)"
    evidence: "Needs ten simultaneous real clients. Maximum Players = 10 confirmed on both places; Admission and PlayerGate unit-tested over the full boundary table (15 + 57 cases)."
  - truth: "D-22: the gateway checks phase BEFORE the rate-limit bucket, so wrong-phase spam is never throttled"
    addressed_in: "Phase 4 or Phase 8"
    evidence: "Recorded in 01-CONTEXT.md D-22 with cost and options. Correctly scoped — reviewed, not re-litigated. The current order is pinned by a test (gateway.spec.luau:224) so a future change is a deliberate edit, not a drift."
  - truth: "Verification Debt: every Roblox platform claim is unverified against primary docs (five DNS-blocked doc hosts)"
    addressed_in: "Every phase's research step (ROADMAP standing rule)"
    evidence: "Correctly scoped. Phase 1 materially reduced it by execution rather than by reading: M-01, M-02, M-03, M-06 confirmed Rojo sync, require resolution, live gateway rejection and map load in a real Studio session, and M-04 falsified an assumed-safe production setting."
human_verification:
  - test: "M-04 check 3 — press Play in SPOONS [BETA] and confirm the server refuses to boot with 'Refusing real persistence: ... 10774453248'"
    expected: "The server refuses to boot; the error originates from Persistence.select and is not caught"
    why_human: "Needs a Roblox Studio session against the live production place; deferred by D-23 to the first real deploy. MUST be closed before any real DataStore write ships (Phase 7)."
  - test: "M-05 — join the dev place with ten clients, then attempt an 11th"
    expected: "The 11th join is refused (by the platform cap, or kicked by PlayerGate with its full-server message); the server stays at 10 and keeps running"
    why_human: "Needs ten simultaneous real clients; deferred by D-23 to the first ten-player playtest."
  - test: "Re-run M-04 check 2 at the start of Phase 7 — in SPOONS [BETA] run DataStoreService:GetDataStore('m04'):SetAsync('k', 1) from the Studio command bar"
    expected: "REFUSED | 403 ... StudioAccessToApisNotAllowed"
    why_human: "FOUND-07's only enforcing control is a Creator Hub toggle outside the repo. This phase proved empirically that it can be ON while all 14 automated gates are green. Nothing in the repo can detect it being flipped back."
  - test: "M-06 residual — in a Studio Play session, confirm Workspace contains Geometry and does NOT contain Data or the GrayBox model"
    expected: "Only the cloned Geometry appears in Workspace; Data stays in ServerStorage (CLAUDE.md rule 3)"
    why_human: "Recorded in MANUAL-CHECKS.md M-06 as not separately eyeballed. tests/maps/graybox.spec.luau asserts it statically and MapLoader clones only Geometry, so this is a low-risk confirmation, not an open question."
---

# Phase 1: Foundations, Contracts and Spec Lock — Verification Report

**Phase Goal:** The repo builds, lints and tests headless in CI, the structural guards that keep
no-pay-to-win and engine purity true are enforced, and every contract that parallel work depends
on is fixed.

**Verified:** 2026-11-03 at commit `70fd9ce` (working tree clean; no source file was modified by
this verification — all experiments ran in a throwaway `git archive` copy outside the repo)
**Status:** human_needed — 9/10 COMPLETE, 1 PARTIAL, 2 owner-deferred manual sub-checks outstanding
**Re-verification:** No — initial verification

## Executive Verdict

Phase 1 delivers its goal. This is unusually well-built foundation work: the gates are real, the
failure-expecting tests assert reasons rather than exit codes, and the phase found and fixed a live
production defect that every automated gate had been green through. I tried three times to find a
hole in the structural guards and the guards won twice.

Two things should be corrected before Phase 1 is closed, neither of which is a capability gap:

1. **FOUND-08 should not be marked complete.** Its 3-player-minimum half has no enforcement point —
   `PlayerGate.canStart` has zero callers. This is a different issue from the deferred M-05 check and
   nobody has flagged it.
2. **MAP-01 and SCORE-06 have no completion claim in any SUMMARY.** Both are genuinely met; the
   bookkeeping just does not say so.

On the question I was asked directly: **the FOUND-07 sign-off does not overreach; the FOUND-08
sign-off does, on a dimension unrelated to its deferral.**

## Automated Evidence (executed, not read)

| Command | Result |
|---|---|
| `lune run scripts/verify.luau` | all 14 steps passed in 16.9s |
| `lune run tests/run.luau` | 333 passed, 0 failed, 3 todo in 14.5s |
| `lune run scripts/maps/validate-map.luau maps/gray-box.rbxm` | `ok (18 spots, 9 seats)`, exit 0 |
| GitHub Actions on HEAD `70fd9ce` | run `41584751433` success, all 14 gates as separate green steps |

The CI run matters more than the local run: it confirms the gates execute on a clean `ubuntu-latest`
runner rather than merely exiting 0, and it is on HEAD, not on an older commit. The six commits since
the previously-cited run `41582812758` are documentation-only (`git diff --stat 3ea2af0..HEAD` touches
only `MANUAL-CHECKS.md`, `NEEDS_HUMAN.md`, `01-CONTEXT.md` and a SUMMARY).

## Per-Requirement Verdicts

### FOUND-01 — Rojo syncs with `$ignoreUnknownInstances` on Workspace — COMPLETE

`default.project.json` gives `Workspace` `$ignoreUnknownInstances: true` and no `$path`; code mounts
are `src/server`, `src/shared`, `src/client`; `ServerStorage.Maps` has no `$path`, so Studio drafts
survive. Machine-checked by `tests/project/project.spec.luau` ("FOUND-01 Workspace ignores unknown
instances", "FOUND-01 Rojo mounts code only", "FOUND-01 spec files never sync"). The half that only
a human can prove — that a hand-placed Part actually survives a sync — is signed off in M-01 with a
specific observation: `Workspace.SurvivalTest` survived both an edit-sync of
`src/shared/Config/Round.luau` and a full Disconnect/Connect re-sync on Windows with matched CLI and
plugin at 7.7.1. `rojo build` is green in CI.

The unchecked box in REQUIREMENTS.md is, as briefed, a bookkeeping artefact. The code delivers.

### FOUND-02 — Toolchain pinned via Rokit; every file `--!strict` — COMPLETE

`rokit.toml` pins five tools to exact versions. `tests/project/project.spec.luau` asserts each pin by
string AND scans every entry for `^`, `~` or `*`, so a range cannot be introduced. `.luaurc` sets
`languageMode: strict`, `lintErrors: true`, `typeErrors: true` — all three asserted, and trap 1
(`tests/traps/traps.spec.luau`) proves by execution that `lintErrors: true` is what makes a lint-only
finding exit non-zero, with a counter-case showing `false` lets the same file pass.

`--!strict` on line 1 of every authored file is enforced by check-guards rule R1 over `src`, `scripts`
and `tests`, fixture-proven by `tests/guards/fixtures/strict-missing` which asserts the exact rule set
`{R1}`, both file paths, and `check-guards: 2 violation(s)` — so a missing header and a *wrong* header
are distinguished.

One accuracy note, recorded above: 01-01-SUMMARY claims the vendored `globalTypes.None.d.luau` is
"sha256-pinned". The automated check is byte length only. The hash is correct today; the enforcement
is weaker than the claim.

### FOUND-03 — Engine tests and the fuzz suite run headless in CI — COMPLETE

`tests/run.luau` discovers `**/*.spec.luau` by directory walk — no manifest, so a spec cannot be
forgotten — and exits non-zero on a failing case, a spec that fails to load, a spec that registers
nothing, a run that discovers no specs, or a filter matching nothing. Each of those is itself
meta-tested in `tests/meta/harness.spec.luau`. `tests/harness/Fuzz.luau` is a real property driver
and is self-tested for the two things that matter: that a failing property reports its iteration and
seed, and that `opts.seed` replays identically.

The require spike exists on all three sides, which is what the roadmap's "under both the headless
runner and Roblox" demands: `tests/spike/require.spec.luau` (Lune resolution of relative string
requires), `scripts/ci/check-built-place.luau` (re-resolves every require in the built `.rbxl` under
Roblox's published rules — 10 cases including unresolved targets, non-ModuleScript targets, banned
`@` aliases in shipped code, and disk/DataModel mismatches), and M-02, signed off from a live Studio
Play session that booted clean through `persistence mode: Mock`, `map loaded: GrayBox`,
`server ready` and `client boot: Ping sent`.

Scope note: the harness has only ever run toy properties at 200 iterations. Phase 2's 100k-action
conservation fuzz is the real load test.

### FOUND-04 — Single typed gateway, validates arguments including NaN, rate-limits per player — COMPLETE

`src/server/core/Gateway.luau` is the one entry point, pure and synchronous (CLAUDE.md rules 2 and 6),
with a fixed check order: `isKnown` → phase gate → `Bucket:take` → `validate` → dispatch inside
`xpcall`. `src/shared/Net/Validate.luau` uses a positive type allow-list and a hand-written `isFinite`
(`v == v` for NaN, explicit infinity rejection) because Selene 0.32.0's `luau` std has no
`math.isnan` — exactly the constraint the validation doc predicted. Rejection codes are specific
(`NotFinite`, `MissingKey`, `UnknownKey`, `UnknownIntent`, `WrongPhase`, `RateLimited`,
`HandlerError`), so a test can tell *why*.

Covered by 19 gateway cases, 25 validator cases and 18 bucket cases. The good ones: unknown names
allocate no bucket state across 100 attempts; a malformed flood cannot starve a different user; two
user ids do not share state; a hostile payload whose metatable raises is rejected without throwing
out of `handle`; a bad clock reading drops as `RateLimited` rather than refilling to the cap.

Structural uniqueness is enforced, not assumed: check-guards R4 pins `OnServerEvent`, `OnServerInvoke`,
`RemoteFunction`, `UnreliableRemoteEvent`, `FireClient`, `FireAllClients` to `NetServer.luau` and
`FireServer` to `ClientNet.luau`, fixture-proven, plus two tests that count files under `src/`
mentioning each identifier and assert the count is exactly 1.

And M-03 is the live proof, with the detail that makes it mean something: four payloads produced four
*different* codes across a real client-server boundary, including `NotFinite` from `{nonce = 0/0}`.
The `nonce` field was added deliberately so a NaN would reach the finite check instead of bouncing as
`UnknownKey` — that is a design decision made so a test could not pass for the wrong reason.

**Forward risk worth naming now:** R4's `netOwners` list covers only `Remote*` members. The other
client-driven server-side trigger paths — `ProximityPrompt.Triggered`, `ClickDetector.MouseClick`,
`Tool.Activated`, `Humanoid.Touched` — are not in the list and would bypass the gateway entirely.
None exist today, but Phase 5's spoon pickup affordance is the single most likely place one appears.
Adding them to `netOwners` is a one-line change and is cheap now.

### FOUND-05 — Build fails if Scoring/CardTable/SpoonPlacement import cosmetics or shop — COMPLETE, with a condition

check-guards R2 walks the transitive *literal* require closure from each guarded root (filename
prefix `Scoring`, `CardTable`, `SpoonPlacement` under `src/`, plus every pure-zone file) and fails on
any resolved path segment matching one of nine forbidden substrings, naming the whole chain. R3 closes
the indirection escape by banning non-literal requires, `getfenv`, `setfenv`, `loadstring`,
`rawget(_G` and `_G[` in roots *and in every file the closure reaches* — so a helper outside the zone
cannot launder the import back in.

Three fixtures, each asserting the exact rule set so it cannot pass by tripping a neighbour:
`import-direct` (`Scoring -> CosmeticsBridge`), `import-transitive`
(`CardTable -> Util -> ShopCatalog`), `import-nonliteral` (R3). The clean fixture asserts exact
counts (`ok (2 files, 1 requires, 2 guarded roots)`), so a guard that scanned nothing cannot satisfy
it — and a separate case proves a scan of nothing exits 1 with "a scan of nothing must not look
green". 01-03-SUMMARY also records a mutation matrix, including the honest admission that removing
`"shop"` alone was *not* a discriminating mutation because `ShopCatalog` also matches `"catalog"`.

**The condition.** `forbiddenSegments` is a deny-list over filenames and path segments. I probed this:
a guarded root `src/server/core/Scoring.luau` importing `src/server/core/Wardrobe.luau` — a cosmetics
module whose name matches none of `cosmetic, shop, catalog, loadout, economy, monetiz, gamepass,
purchase, skin` — leaves `check-guards` fully green (`ok (61 files, 123 requires, 14 guarded roots)`,
exit 0). This sits squarely inside the guard's own declared threat model ("accident and agent drift"),
not outside it: naming a module `Wardrobe` is drift, not a metatable trick.

For Phase 1 this is correct and complete — there is no cosmetics code to contain. For Phase 7 the
guard's soundness depends entirely on naming discipline that nothing enforces. The cheap fix, and the
one the existing path-segment matching already supports, is to require all cosmetics and shop code to
live under directories named `cosmetics/` and `shop/`, and to add a rule that fails if a guarded root
imports anything outside an explicit allow-list. Recommend recording this against FOUND-05 /
SHOP-* before Phase 7 authors its first module.

### FOUND-06 — Build fails if the card engine references any Roblox API — COMPLETE

Two independent layers, and the phase correctly proves the second one is *necessary* rather than
assuming it: `tests/purity/purity.spec.luau` includes "FOUND-06 layer 2 is necessary: the linter
accepts a type-only reference", which demonstrates the lint layer's blind spot before showing the
typecheck layer covering it.

- Layer 1: `selene --config selene.pure.toml` (std `luau`, `undefined_variable = "deny"`,
  `global_usage = "deny"`) over the pure zones. Fixture `engine-roblox-value` proves it fails.
- Layer 2: `luau-lsp analyze --platform standard` over the pure zones. Fixture `engine-roblox-type`
  proves it catches a type-only `Instance` reference. Trap 3 proves that omitting `--platform
  standard` accepts a Roblox type in a pure zone — i.e. the flag is load-bearing and known to be so.
- Layer 3: R3b bans every suppression comment (`selene: allow`, `--# selene`, `--!nocheck`,
  `--!nonstrict`, `-- luau-lsp:`, `--!native`) inside a pure zone, read from the *unstripped* text.
  Fixture `engine-suppressed` proves it, asserting the exact id `R3b` so it cannot pass as an R3.

The zone list cannot silently empty: `--print-zones` exits 1 with empty stdout on an empty list, CI
re-checks with `test -n "$zones"`, and `verify.luau` fails with "the FOUND-06 gate would be vacuous".
That specific failure mode — a gate spliced from an empty variable, analysing nothing, green — is the
kind of thing that normally ships.

**I probed the transitive hole and it held, twice.** An engine module reaching a Roblox API through a
helper *outside* the pure zone is caught by the standard-platform typecheck, which follows the
relative require: variant 1 (helper containing a non-literal require) was caught by both R3 and the
typecheck; variant 2 (helper with only a bare `workspace` global and no non-literal require) was
caught by the typecheck alone — `analyze` exit 1,
`TypeError: Unknown global 'workspace'`. The guard is stronger than its own documentation claims.

I also probed whether the pinned Selene Roblox std could degrade silently. It cannot: `roblox.yml`
missing gives exit 1 ("failed to collect roblox standard library"), and truncated to 100 bytes gives
exit 1 with 19 errors. No integrity check is needed.

The `scripts/ci/analyze.luau` wrapper implements exactly the five-times-refined detector the
validation doc settled on — pass only if exit code is 0 AND the output contains none of
`Failed to load`, `Sourcemap parsing failed`, `TypeError` — and refuses any `--formatter` argument
outright. All four exit-code traps have executing proofs, including the two distinct sourcemap failure
strings, and a drift test asserts no gate file contains `allow-warnings`, `continue-on-error` or
`--formatter plain`.

### FOUND-07 — A Studio session cannot write to production player data — COMPLETE, with a standing condition

**This is the requirement I was asked to judge independently, and I think the sign-off is honest.**

What actually prevents a write today is the platform control, and it is demonstrated rather than
assumed. M-04 check 2 ran the write from the Studio command bar in `SPOONS [BETA]`, printing
`game.GameId` alongside the result so the outcome is tied to the right experience, and got
`GameId 10774453248 -> REFUSED | 403: Cannot write to DataStore from studio if API access is not
enabled.` with `DataStoreService: StudioAccessToApisNotAllowed`. Refused, by the specific expected
reason. The dev side was re-confirmed after the flip (`GameId 10774461969 -> WROTE | nil`) to rule
out having traded one problem for another.

Supporting it: a genuinely separate universe (D-13, not a second place — data stores are
per-experience); three ids recorded in `Environments.luau` and machine-checked by
`tests/project/project.spec.luau` for placeholder zeros, exact-integer form, dev ≠ production, and
`servePlaceIds == DEV_PLACE_ID`; `PersistenceMode.decide` fail-closed with Refuse ordered *before*
Mock and 7 test cases including an exhaustive combination table and the important negative case
("a live production server is never Refused"); and the tripwire wired as the *first* statement of
`Main.server.luau` with its error deliberately uncaught.

And the decisive scope fact: Phase 1 ships no real DataStore code at all. `Real` mode raises
"Real persistence is not implemented until Phase 7". There is no production write path in this
repository to protect.

Against that, the deferred M-04 check 3 is a secondary control whose logic is unit-tested and whose
wiring to `game.GameId` is unobserved. D-23 states exactly that and claims nothing more. Given the
primary control is demonstrated and no write path exists, deferring it is proportionate, and I agree
with the decision. **Verdict: COMPLETE, not partial.**

The condition I would attach is about where the control *lives*. The one thing enforcing FOUND-07 is
a Creator Hub toggle outside the repository. This phase proved empirically that it can be OFF-by-
omission — ON for production, writing live data — while all 14 automated gates are green, and the
repo has no way to detect it being flipped back. The tripwire is the only in-repo backstop and has
never been seen working. So: re-run M-04 check 2 at the start of Phase 7, and close M-04 check 3
before the first real DataStore write ships. Both are recorded in `human_verification` above.

The one live production write that occurred during the failing run (key `k` in the `m04` store) is
correctly recorded as a real production write rather than glossed.

### FOUND-08 — Server enforces a 10-player cap and a 3-player minimum to start — PARTIAL

**This is the one sign-off I think overreaches, and not for the reason that was flagged.**

The cap half is complete. `Limits.MAX_PLAYERS = 10`; `Admission.decide` is pure, rejects NaN,
infinities and fractions before any comparison, and is tested across the boundary table with each
refusal asserting its own reason code (15 + 57 cases under `--filter admission`); `PlayerGate` is
wired in `Main.server.luau` before anything can accept input, and its `countAdmitted(refused) - 1`
accounting correctly handles the asynchronous kick so one refusal cannot cascade into wrongly
refusing a legitimate player. I traced the arithmetic at 10, 11 and 12 joins and it is right. The
place setting is 10 on both places. M-05's unobserved 11th join is a fine deferral: the platform cap
is the enforcer and our kick path is defence in depth for reserved servers and teleports (A7).

The 3-minimum half is where it breaks down. `PlayerGate.canStart` and `Admission.canStartMatch` are
thoroughly tested — including that garbage input never starts a match, and that the predicate agrees
with "there is always at least one spoon" for N = 3..10 — but `grep -rn canStart src` returns only
the definitions. **Nothing calls it.** There is no match-start path in Phase 1 (that is MATCH-01,
Phase 6), so the server does not currently refuse to start under 3; it holds a tested predicate that
will refuse once something asks.

That is defensible as phase scope. What is not defensible is marking the requirement complete,
because the requirement says *enforces*, and because ticking it now removes the only mechanism that
would make anyone check that Phase 6 actually routes match start through `PlayerGate.canStart`. The
module comment already asserts "Nothing else in the codebase may decide that a match can start" —
that invariant is currently unenforceable by any test, since there are zero call sites to inspect.

**Recommendation:** mark FOUND-08 partial, or mark it complete with an explicit carried item against
Phase 6. The deferred M-05 observation is fine; this is the gap that matters.

### MAP-01 — Maps are data behind one shared contract, with no per-map code branches — COMPLETE

`MapContract.luau` is pure data and types: 12 stable issue codes, `MIN_DEFAULT_SPOTS = 16`,
`SEAT_COUNT = 9` (10 players minus the hider, D-11), and the full D-10 contract — bounds volume,
hider and seeker spawns, default spots, decoy anchors, card table anchor, `Seat1..Seat9`, metadata.
`MapValidator` is a single pure function over a plain-data snapshot, which is what lets the identical
validator run in CI from a `.rbxm` and at runtime from a live tree.

The coverage is the strongest in the phase: 36 rejection cases each asserting a specific issue code,
plus a meta-test proving every code in `MapContract.ISSUE_CODES` has at least one case and that the
list has exactly 12 entries — so adding a code without a test fails. Plus determinism of issue
ordering, multiple independent faults each reported under its own code, the inclusive 16-spot
boundary, an empty `DecoyAnchors` folder being valid, and seats indexed by number rather than child
order.

The gray-box map is real, not a box: `validate-map.luau` reports 18 spots and 9 seats, and
`tests/maps/graybox.spec.luau` asserts spots at varied heights (at least four at y ≥ 6, at least four
distinct heights), seats on a radius-6 ring looking at the table and ordered clockwise, no script
instance anywhere, hidden data absent from `Geometry`, and — the one I liked most — that the committed
`.rbxm` is byte-identical to what the generator produces, so it cannot go stale. Four CLI failure
cases assert parse, read, usage and smuggled-script reasons rather than exit codes.

No per-map branch exists: `MapLoader.load(mapId)` validates then clones only `Geometry` into
Workspace, `Data` stays in ServerStorage (CLAUDE.md rule 3), and `Main.server.luau` passes a
`DEFAULT_MAP_ID` constant explicitly annotated as a configured default rather than a branch. M-06
confirmed it live: `[Spoons] map loaded: GrayBox`, four rooms, perimeter walls, table centred.

Residual: the two snapshotters (`MapLoader.snapshot` and `scripts/maps/snapshot.luau`) must emit the
identical Node shape and no automated test can compare them, since one needs Roblox. M-06's live load
is the only parity evidence — it did pass, end to end, through the real validator.

### SCORE-06 — Round end happens exactly once; a stale callback can never affect a later round — COMPLETE

`RoundLifecycle.luau` is pure, synchronous, integer-decisecond, and uses two *independent* guards
rather than one: the backstop is cancelled when its round ends, AND it carries its round id and
no-ops on mismatch. The file says the token guard must work with cancel as a no-op, and
`tests/core/round.spec.luau` proves it both ways — "stale backstop from round 1 cannot end round 2
(cancel works)" and "(cancel is a no-op, so the token alone does it)". That is the difference between
asserting a property and asserting an implementation.

21 cases cover: `endRound` called 100 times firing `onEnded` exactly once; both tie arrival orders at
the deadline (claim-then-timer and timer-then-claim); the deadline being exclusive; state marked
ended *before* `onEnded` runs so a re-entrant handler cannot double-end; `onEnded` legally beginning
the next round; `begin` while a round is live being an error rather than a silent overwrite; and
`begin` rejecting NaN and infinite durations. `isOpen` correctly routes an expired round to a single
Timeout end.

Scope note: the Roblox adapter `RoundDriver.luau` has no coverage of `beginRound` or `deadlineUnix` —
neither is called anywhere, in tests or at runtime, so `Workspace:GetServerTimeNow()` is entirely
unexercised. Its two-clock discipline (`os.clock()` for scheduling, `GetServerTimeNow()` only for
publishing outward, never fed back) is well documented and the right design, but it is documentation
rather than tested behaviour today. The logic that SCORE-06 is about lives in the pure core, so this
does not change the verdict. One theoretical note for Phase 4: if `task.cancel` ever threw inside
`endRound`, the round would be marked ended with `onEnded` never fired — turning "exactly once" into
"zero times". The current call pattern makes this unreachable (cancel is only invoked on a live
delayed thread), so it is a remark, not a defect.

## Roadmap Success Criteria

| # | Criterion | Verdict |
|---|---|---|
| 1 | Fresh clone syncs into Studio without deleting Workspace content; CI green on every push | MET — M-01 signed with a specific survival observation; CI green on HEAD, all 14 gates as separate steps; `on: push` with no branch filter, asserted by a test |
| 2 | Engine tests and fuzz run headless in CI, proven by a require spike under both runners | MET — `tests/spike/require.spec.luau` + `check-built-place.luau` (10 cases) + M-02 live |
| 3 | Build fails on a guarded import path or a Roblox API in `server/engine/`, each by a deliberately failing fixture | MET — 3 FOUND-05 fixtures, 3 FOUND-06 fixtures, all asserting exact rule sets and messages. See the FOUND-05 naming condition |
| 4 | Malformed / NaN / wrong-phase / over-rate rejected by the single gateway; a Studio session cannot write production data | MET — 19 + 25 + 18 unit cases, four distinct codes observed live in M-03, and M-04 check 2 verified by the specific reason |
| 5 | Gray-box map loads with no per-map branch; server refuses an 11th player and refuses to start under 3; injected-clock test shows one round end at the boundary | PARTIAL — map MET (live); 11th player implemented, wired and unit-tested, live refusal deferred (D-23, acceptable); **"refuses to start under 3" has no enforcement point** (see FOUND-08); round end MET and strongly tested |

## Gate G1

**Not applicable.** G1 is Phase 2's gate — ROADMAP.md line 79, inside Phase 2's success criteria:
the bot pacing simulator reporting zero stalls at every player count 3–10, which selects the card
pool and joker count and decides whether jokers ship as wilds (CARD-10) or blockers (CARD-12).
Phase 1 is ungated; G2–G5 belong to Phases 3, 5, 6 and 8. Phase 1 closes on its five success
criteria plus the six manual checks, and there is no G1 verdict to give here.

Relatedly: the spec-lock items that *feed* G1 (CARD-09, CARD-10, CARD-12) are recorded as three
`t.todo` entries, not tests. Reasonable — no engine exists to assert against, and the file argues
the case explicitly. But Phase 2 must convert all three, and the runner's todo count must reach 0
before Phase 2 closes.

## What the summaries claim that the code does not support

The most valuable section, so stated plainly. I found no false capability claim — every requirement
the summaries say is delivered, is delivered. The discrepancies are three accuracy issues and one
bookkeeping omission.

1. **"sha256-pinned" vendored type definitions** (01-01-SUMMARY:11) — the only machine check is byte
   length 677555, in two places. No gate hashes the file. The recorded sha256 does match the file
   today, so nothing is broken; the claim is just stronger than the enforcement.
2. **"servePlaceIds must never name the production experience"** (project.spec.luau:78-83) — compares
   PlaceIds against `PRODUCTION_UNIVERSE_ID`, two namespaces that never collide, so the assertion
   cannot fire. There is no `PRODUCTION_PLACE_ID` constant. I probed it both ways: the test case still
   fails correctly, because the preceding `t.equal(servePlaceIds[1], DEV_PLACE_ID)` is doing the work.
   01-12-SUMMARY's claim that "pointing servePlaceIds at the production place fails the third
   [assertion]" is true at the test-case level. The labelled loop is dead weight, not a hole.
3. **"Spec lock ... each written as a test"** (ROADMAP Phase 1) — three `t.todo` placeholders. Honest
   about itself, but documented rather than tested. Affects no Phase 1 requirement.
4. **MAP-01 and SCORE-06 appear in no `requirements-completed` list** — including 01-12's, the
   phase-close plan. Both are genuinely met (verdicts above). Pure traceability, but it would leave
   them Pending for anyone working from the summary frontmatter.

Also worth stating because it is the opposite of an overclaim: the FOUND-06 guard is **stronger** than
documented. `check-guards.luau`'s threat model says it "defends against accident and agent drift, not
against an adversary with metatable tricks", and the SUMMARY does not claim the transitive helper case
is covered — but I probed it twice and the standard-platform typecheck caught it both times.

## Should anything block Phase 1 from closing?

**No hard blocker.** One correction, and three items to carry.

**Correct before closing:**
- FOUND-08 → PARTIAL, or complete with an explicit Phase 6 condition that match start must route
  through `PlayerGate.canStart`. As it stands, ticking FOUND-08 retires the only check that would
  catch Phase 6 inventing its own start predicate — which the module itself forbids.
- Record MAP-01 and SCORE-06 completion (verifier's verdict: both COMPLETE).

**Carry forward, cheap now and expensive later:**
- FOUND-05's deny-list depends on naming discipline nothing enforces. Before Phase 7 authors a
  cosmetics module, require cosmetics and shop code to live under `cosmetics/` and `shop/`
  directories (path-segment matching already handles this), or invert R2 to an import allow-list.
- R4's `netOwners` covers only `Remote*` members. Add `ProximityPrompt.Triggered`,
  `ClickDetector.MouseClick`, `Tool.Activated` and `Humanoid.Touched` before Phase 5 builds the spoon
  pickup affordance, which is where one would naturally appear and bypass the gateway.
- Re-run M-04 check 2 at the start of Phase 7, and close M-04 check 3 before any real DataStore write
  ships. FOUND-07's only enforcing control lives outside the repo and this phase proved it can be
  wrong while everything reads green.

**Reviewed and correctly scoped, not re-litigated:** D-22 (phase before bucket — and I note the
current order is pinned by `gateway.spec.luau:224`, so changing it later will be a deliberate edit
rather than a drift), the deferred M-04 check 3 and M-05 11th join under D-23, and the Verification
Debt table. On that last one: Phase 1 reduced the debt by execution rather than by reading, and M-04
is the proof that doing so was worth it — it falsified a platform setting that four green gates and
nine summaries had implicitly assumed.

---

_Verified: 2026-11-03 at `70fd9ce`_
_Verifier: Claude (gsd-verifier) — goal-backward, against the codebase, not the summaries_
_No source file, REQUIREMENTS.md entry or ROADMAP entry was modified. All adversarial probes ran in a throwaway `git archive` copy outside the repository; `git status` is clean._
