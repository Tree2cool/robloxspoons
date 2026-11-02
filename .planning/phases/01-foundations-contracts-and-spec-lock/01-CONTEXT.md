# Phase 1: Foundations, Contracts and Spec Lock - Context

**Gathered:** 2026-11-02
**Status:** Ready for planning

<domain>
## Phase Boundary

The repo builds, lints, typechecks and tests headless in CI; the structural guards that
keep no-pay-to-win and card-engine purity true are enforced as hard build failures; and
every contract that parallel work in Phases 2 and 3 depends on is fixed.

**Requirements:** FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07,
FOUND-08, MAP-01, SCORE-06

**Not this phase:** the card engine itself (Phase 2), the placement rules (Phase 3), any
gameplay UI (Phase 4+), the five shipped maps (Phase 7).

</domain>

<decisions>
## Implementation Decisions

### CI and Quality Gates

- **D-01:** **Every check hard-fails.** Formatting, style lint, strict typecheck, and both
  structural guard rules (FOUND-05, FOUND-06) each fail the build. No advisory tier. The
  owner chose maximum strictness deliberately: a guard that does not block is
  documentation, and FOUND-05 exists precisely because conventions get forgotten.
- **D-02:** **CI runs on every push to any branch and on every pull request.** GitHub
  Actions (repo is `Tree2cool/robloxspoons`).
- **D-03:** **Local pre-commit hook runs the fast checks only** — format and lint. Strict
  typecheck and the test suite are left to CI so commits stay fast enough that nobody
  reaches for `--no-verify`.
- **D-04:** **Un-automatable criteria get a `MANUAL-CHECKS.md` plus a helper script.** The
  script runs everything verifiable without Studio; the document lists each check that
  needs a human with Studio open, so nothing silently passes unverified. This exists
  because the container running the build has no Roblox Studio MCP — see
  `<constraints>`.

### Studio and Filesystem Split

- **D-05:** **Map geometry lives as one committed `.rbxm` per map**, built in Studio,
  exported, committed to git, and mounted by Rojo. Chosen over `rojo syncback` (rewrites
  broad swathes of the tree and can clobber hand-written code) and over a single `.rbxl`
  (opaque binary, no parallel map work). Five independent files is what parallel map
  building in Phase 7 requires.
- **D-06:** **Rojo manages code only.** It owns `ServerScriptService`,
  `ReplicatedStorage` and `StarterPlayer`. **`Workspace` carries
  `$ignoreUnknownInstances`** so anything built in Studio survives a sync. Maps mount
  explicitly as named `.rbxm` files. This is the setting that silently destroys work if
  wrong, which is why it is also a manual check (D-04).
- **D-07:** **Scripts are authored on the filesystem; non-script instances are authored in
  Studio.** All Luau is written to files and synced; geometry, attachments and
  hand-placed instances are Studio work. Matches the `roblox-ai-build` ruleset and keeps
  all code reviewable in git.
- **D-08:** **Phase 1 ships a mechanically complete gray-box reference map** — untextured
  blocks, but with real spawn points, at least 16 default spots, standable surfaces and
  genuine sightlines. No art. It must be good enough for Phase 3 to validate placement
  against and Phase 5 to run the hunt in. A single box room was rejected as too simple to
  surface real problems.

### Map Contract (MAP-01)

- **D-09:** **Default hiding spots are tagged marker parts placed in Studio**, read via
  `CollectionService`. Chosen over a Luau coordinate table because hiding places have to
  be judged by looking at the room — typing CFrames is how spots end up inside walls. The
  validator reads the tags.
- **D-10:** **Every map must declare, through the shared contract:**
  - Seeker spawn points and the hider spawn point
  - A playable bounds volume (one authority per map for placement validity and
    out-of-bounds, instead of per-map guesswork)
  - A metadata block — display name, recommended player range, size class — so map
    rotation (MAP-04) can reason about maps without hardcoding
  - Decoy item anchors (the maze needs them; putting them in the contract stops the maze
    becoming a special case)
  - **A card table anchor plus 9 seat anchors** — see D-11
- **D-11:** **The card table is a physical location in every map.** Owner's addition, and
  it changes the card phase from an abstract menu into a place: for example the hotel's
  table sits in the lobby. **9 seat anchors** (max seekers = 10 players − 1 hider). This
  reconciles with the research's 2D-ScreenGui hand: avatars sit at a real table, the hand
  is a screen overlay. The architecture already assumed seats keep fixed physical chairs
  while the ring closes up logically, so no rework is implied.
- **D-12:** **The validator does structural checks in Phase 1 and gains the real placement
  rules in Phase 3**, in the same tool. Phase 1 checks: required folders present, ≥16
  tagged spots, spawns exist, bounds volume present, card table and 9 seats present,
  metadata well-formed. This lets map authoring begin before Phase 3 lands.

### Data Isolation (FOUND-07)

- **D-13:** **A separate Roblox test universe**, with Studio pointed at its DataStores.
  True isolation rather than an in-code convention. **This requires a Creator Hub setup
  step only the owner can perform — a human gate on Phase 1 closing.** The weaker in-code
  `RunService:IsStudio()` guard was explicitly not chosen.

### Card Phase Staging (emerged from D-11, inherited by Phases 4 and 5)

- **D-14:** **The camera is locked to the table during the card phase.** Looking around
  the map while passing cards is not possible. This enforces hunt fairness in code rather
  than through per-map layout, and **removes** a constraint: map authors do not need to
  screen the table off from hiding areas, so the table can sit somewhere scenic. Pairs
  with UX-02 (movement controls hidden during the card phase).
- **D-15:** **A player who completes four of a kind stands up from their chair and runs.**
  No teleport to a spawn. Fully diegetic: the table's position becomes part of each map's
  routing, and everyone at the table sees who just left. This is the concrete form of
  CARD-17's "starting gun" moment and of the Core Value's "not a menu transition".
  Consequence for Phase 7 map authoring: the table's placement is a level-design decision
  affecting run distance, not just set dressing.

### Post-Research Decisions (added 2026-11-02 after 01-RESEARCH.md)

- **D-16:** **Rokit is the toolchain install path, in CI and locally.** Research found
  `api.github.com` returning 403 in this container, which would have broken `rokit install`;
  the owner opened the domain and it now returns 200. **No bespoke direct-download bootstrap
  script is needed** — that research recommendation is superseded. If a future environment
  blocks the API again, the fallback is a pinned direct-download script, not a different tool.
- **D-17:** **The pinned toolchain is executed locally during this phase.** Nothing in
  01-RESEARCH.md was actually run — all command and config syntax was read from source at
  release tags. Every CI command, config file and script must therefore be executed at least
  once end to end before Phase 1 is considered done. Owner has approved running the pinned
  third-party binaries (rojo, stylua, selene, luau-lsp, lune) from official GitHub releases.
- **D-18:** **The gray-box reference map is generated by a Lune script.** This is a
  deliberate, scoped exception to D-07 (instances authored in Studio): there is no Studio in
  the build container, and Phases 3 and 5 need real geometry to validate placement and run
  the hunt against. The generator produces spawns, the bounds volume, 16 tagged default
  spots, the card table and 9 seat anchors. Shipped art maps (MAP-05..09) remain
  Studio-authored per D-07; only the gray-box fixture is code-generated. It may be refined
  in Studio later and re-exported.
- **D-19:** **The playable bounds volume is a single axis-aligned box Part per map.** Chosen
  for trivial authoring and a point-in-box check. Accepted limitation: it is coarse, so for a
  multi-floor mansion it only catches gross out-of-bounds. If Phase 3's placement work shows
  this is too loose, the contract can move to a union of volumes then — it is a contract
  change, not a rewrite.

### Defaults Taken Without Asking (post-research)

Research raised five owner questions; four are D-16..D-19 above. The rest are defaulted:

- **Studio tripwire for FOUND-07:** add `RunService:IsStudio()` as a *secondary* refusal on
  production DataStore writes, in addition to the separate test universe. D-13 rejected
  `IsStudio()` as *the mechanism*, not as defence in depth.
- **Deadline tie rule:** a claim arriving exactly on the deadline decisecond is **outside**
  the round (deadline exclusive), resolved by server arrival order. A 100ms edge case;
  exclusive is the simpler invariant to test.
- **Persistence skeleton scope for Phase 1:** environment config plus a Mock-selection seam
  only. No real DataStore work — that is Phase 7.

### Claude's Discretion

Not discussed; defaulting to the research recommendations in `research/STACK.md` and
`research/ARCHITECTURE.md`:

- Package manager — Wally as default, pesde as fallback. The dependency surface is tiny,
  so the choice is reversible.
- Module and folder layout, including the `server/engine/` boundary that FOUND-06 lints.
- Test harness mechanics — a small in-repo harness so engine tests do not depend on Jest;
  Jest-Lua stays optional for Studio-side tests.
- `Net` gateway internals: token-bucket rate-limit shape and starting numbers (research
  marks the numbers LOW confidence, to be tuned in playtest), argument validation
  including NaN, phase gating.
- Round-end FSM internals: absolute deadlines, round-ID tokens, injected clock for the
  SCORE-06 test.
- Rokit-pinned tool versions (StyLua, Selene, luau-lsp) and CI job layout.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project authority
- `.planning/PROJECT.md` — full game design, every decided rule, scoring formulas,
  monetization model, constraints, Key Decisions log. Authoritative over any research
  file where they disagree.
- `.planning/REQUIREMENTS.md` — the 10 requirements in this phase, plus full v1 scope and
  out-of-scope with reasons.
- `.planning/ROADMAP.md` § "Phase 1: Foundations, Contracts and Spec Lock" — goal, the 5
  success criteria, the spec-lock defaults, the research flags.
- `CLAUDE.md` — the eight non-negotiable structural rules.

### Research
- `.planning/research/SUMMARY.md` § **Verification Debt** — **MUST be re-checked first.**
  Every Roblox platform claim is unverified against primary docs. Re-check rows V-1 to
  V-6, V-8 to V-10, V-14, V-30, V-31 for this phase and record what changed.
- `.planning/research/SUMMARY.md` § Contradictions #1 — engine location and test runner.
  Resolved toward `server/engine/` under a headless runner. Includes the required
  `require`-style spike (V-4).
- `.planning/research/STACK.md` — toolchain, Rojo/Rokit, `Net` module, persistence.
- `.planning/research/ARCHITECTURE.md` § 6 — the map contract and folder layout.
- `.planning/research/ARCHITECTURE.md` — round state machine, absolute deadlines,
  round-ID tokens.
- `.planning/research/PITFALLS.md` — C4 (timer and round-end races), C7 (remote hygiene),
  C10 (cosmetic leakage), C11/C12 (persistence), C14 (map scope).

### Skills
- `anthropic-skills:roblox-ai-build` — house ruleset for building Roblox experiences;
  source of D-07's scripts-via-filesystem rule.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

None. The repository is empty apart from `.planning/` and `CLAUDE.md` — no Rojo project,
no place file, no Luau source, no dependency manifest. This phase creates the first code.

### Established Patterns

None yet in code. The patterns this phase must *establish*, because everything downstream
depends on them:

- `--!strict` on every file, enforced by a hard-failing typecheck gate (D-01)
- One typed `Net` gateway as the sole client-to-server path (FOUND-04)
- `server/engine/` as a Roblox-API-free zone, lint-enforced (FOUND-06)
- No import path from `Scoring` / `CardTable` / `SpoonPlacement` to cosmetics or shop,
  lint-enforced (FOUND-05)

### Integration Points

- **Phase 2** consumes: the headless test harness, `server/engine/` boundary, the FOUND-06
  lint rule, and the spec-lock decisions (CARD-09, CARD-10).
- **Phase 3** consumes: the map contract (D-09 to D-12) and the structural validator it
  extends with real placement rules.
- **Phase 4/5** consume: the `Net` gateway, the round-end FSM, and inherit D-14/D-15.
- **Phase 7** consumes: the per-map `.rbxm` convention (D-05) and the full contract (D-10).

</code_context>

<specifics>
## Specific Ideas

- **The card table, in the owner's words:** "The spot where the actual dealing should also
  be on every map, for example the hotel could be like a table with 10 chairs in the
  lobby." Captured as D-11, with the seat count corrected to 9 (max seekers).
- **Gray-box means mechanically complete, not minimal** — real sightlines and standable
  surfaces, because Phase 3's placement validation and Phase 5's hunt need geometry
  complex enough to surface real problems (D-08).

</specifics>

<constraints>
## Environment Constraints

- **No Roblox Studio MCP in this container.** Everything code-side can be produced and
  verified headless — Rojo project, Rokit manifest, lint rules with deliberately failing
  fixtures, strict typecheck, `Net` gateway, round-end FSM test, structural map
  validator. **Success criterion 1's Studio-sync half cannot be verified here** and is
  covered by D-04's manual check.
- **A separate test universe (D-13) is a human gate** — a Creator Hub step only the owner
  can perform.
- **Five Roblox documentation hosts are DNS-blocked** by the environment's network policy:
  `create.roblox.com`, `devforum.roblox.com`, `robloxapi.github.io`,
  `madstudioroblox.github.io`, `jsdotlua.github.io`. Phase-level research must note what
  it could not verify rather than upgrading confidence.

</constraints>

<deferred>
## Deferred Ideas

None — the discussion stayed within phase scope.

Two decisions made here (D-14 camera lock, D-15 stand-up-and-run) are *implemented* in
Phases 4 and 5 rather than Phase 1. They are recorded here because they emerged from the
Phase 1 map-contract decision (D-11) and must not be re-litigated later. They need no new
requirement IDs — CARD-17 and UX-02 already cover them.

</deferred>

---

*Phase: 01-foundations-contracts-and-spec-lock*
*Context gathered: 2026-11-02*
