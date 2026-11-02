---
phase: 01-foundations-contracts-and-spec-lock
plan: 03
subsystem: infra
tags: [lune, structural-guards, require-closure, no-pay-to-win, rojo-datamodel, fixtures]

requires:
  - phase: 01-01
    provides: pinned toolchain, .luaurc, default.project.json mounts, selene/stylua ignore lists
  - phase: 01-02
    provides: tests/run.luau harness, Test.Runner API, process.exec pattern, assert-the-reason rule
provides:
  - "scripts/ci/check-guards.luau: one CLI enforcing R1, R2, R3, R3b, R4, R5, R6 with hard exit codes"
  - "scripts/ci/zones.luau: single source of truth for pure zones, per-rule scan scopes, forbidden segments, Net owners, secret names, mounts"
  - "--print-zones: the pure-zone list for shell consumers, exits 1 with empty stdout on an empty list"
  - "tests/guards/guards.spec.luau plus nine fixture roots, each driven through the real CLI"
affects: [01-04, 01-05, 01-07, 01-10, 01-11, 01-12]

tech-stack:
  added: []
  patterns:
    - "Per-rule scan scope lives in zones.luau (scanDirs for R1, pure zones and roots for R2/R3/R3b, shippedDirs for R4/R5/R6)"
    - "Failure-expecting guard cases assert exit code AND the exact set of rule ids AND message substrings"
    - "A scan that finds nothing is a failure, never a pass"

key-files:
  created:
    - scripts/ci/zones.luau
    - scripts/ci/check-guards.luau
    - tests/guards/guards.spec.luau
    - tests/guards/fixtures/import-direct/src/server/core/Scoring.luau
    - tests/guards/fixtures/import-direct/src/server/CosmeticsBridge.luau
    - tests/guards/fixtures/import-transitive/src/server/core/CardTable.luau
    - tests/guards/fixtures/import-transitive/src/server/core/Util.luau
    - tests/guards/fixtures/import-transitive/src/server/core/ShopCatalog.luau
    - tests/guards/fixtures/import-nonliteral/src/server/core/Scoring.luau
    - tests/guards/fixtures/import-clean/src/server/core/Scoring.luau
    - tests/guards/fixtures/import-clean/src/server/core/Util.luau
    - tests/guards/fixtures/engine-suppressed/src/server/engine/Bad.luau
    - tests/guards/fixtures/strict-missing/src/server/services/NoHeader.luau
    - tests/guards/fixtures/strict-missing/src/server/services/WrongHeader.luau
    - tests/guards/fixtures/net-hygiene/src/server/services/Sneaky.luau
    - tests/guards/fixtures/secret-name/src/client/Leak.luau
    - tests/guards/fixtures/cross-mount/src/server/engine/Bad.luau
    - tests/guards/fixtures/cross-mount/src/shared/Config.luau
  modified: []

key-decisions:
  - "R3 also covers every module the R2 closure reaches, not only roots: a helper outside the zones with a computed require would otherwise make the closure unsound"
  - "Pure zones additionally forbid any non-relative require (@lune/..., @game/...), per the research text"
  - "R5 scans comment-stripped text, so documentation comments naming a secret tag do not trip it; string literals and code do"

patterns-established:
  - "A guard scope bug shows up as a violation in scripts/ or tests/ for R4/R5/R6; the fix is narrowing the scope, never the name lists"
  - "Mutation-check a guard: weaken the thing it guards, confirm its spec goes red, restore"

requirements-completed: []
requirements-contributed: [FOUND-05, FOUND-06, FOUND-02]

duration: ~1 session
completed: 2026-11-02
---

# Phase 1 Plan 03: Structural Guards Summary

**`check-guards` enforces FOUND-05 (transitive no-import path from Scoring/CardTable/SpoonPlacement to cosmetics/shop, error names the whole chain) plus strict-header, indirection ban, suppression ban, Net hygiene, secret-name and DataModel-twin rules; nine fixtures prove it fails for the right reason and passes clean.**

## Performance

- **Tasks:** 2 of 2
- **Files created:** 18 (no files modified)
- **Full suite after this plan:** `51 passed, 0 failed, 0 todo in 1.05s`; guard spec alone `14 passed, 0 failed, 0 todo in 0.69s`

## Task Commits

1. **Task 1: zones.luau and check-guards CLI** - `cb60f74` (feat)
2. **Task 2: nine fixtures and the guard spec** - `976e277` (test)

## Violation message format (later plans and MANUAL-CHECKS.md quote this)

One line per violation, sorted by file then line then rule:

```
<RULE_ID> <root-relative/path>:<line> <message>
check-guards: N violation(s)          (exit 1)
check-guards: ok (<fileCount> files, <requireCount> requires, <rootCount> guarded roots)   (exit 0)
```

`rootCount` counts guarded roots: files under `src/` named `Scoring*`/`CardTable*`/`SpoonPlacement*` plus every file inside a pure zone.

Rule ids actually emitted: `R1`, `R2`, `R3`, `R3b`, `R4`, `R5`, `R6`.

## Fixture to rule mapping and observed exit codes (verbatim)

All nine run directly through `lune run scripts/ci/check-guards.luau tests/guards/fixtures/<name>`:

```
=== import-direct
R2 src/server/core/Scoring.luau:2 forbidden import: Scoring -> CosmeticsBridge (path segment matches "cosmetic")
check-guards: 1 violation(s)
EXIT=1
=== import-transitive
R2 src/server/core/Util.luau:2 forbidden import: CardTable -> Util -> ShopCatalog (path segment matches "shop")
check-guards: 1 violation(s)
EXIT=1
=== import-nonliteral
R3 src/server/core/Scoring.luau:2 non-literal require: the require target is not a string literal
check-guards: 1 violation(s)
EXIT=1
=== import-clean
check-guards: ok (2 files, 1 requires, 2 guarded roots)
EXIT=0
=== engine-suppressed
R3b src/server/engine/Bad.luau:2 suppression comment in a pure zone: selene: allow
check-guards: 1 violation(s)
EXIT=1
=== strict-missing
R1 src/server/services/NoHeader.luau:1 first line must be exactly --!strict (found: local value = 1)
R1 src/server/services/WrongHeader.luau:1 first line must be exactly --!strict (found: --!nonstrict)
check-guards: 2 violation(s)
EXIT=1
=== net-hygiene
R4 src/server/services/Sneaky.luau:3 OnServerEvent may appear only in src/server/services/NetServer.luau
check-guards: 1 violation(s)
EXIT=1
=== secret-name
R5 src/client/Leak.luau:2 hidden-data name SpoonDefaultSpot must not appear in client or shared code
check-guards: 1 violation(s)
EXIT=1
=== cross-mount
R6 src/server/engine/Bad.luau:2 cross-mount require "../../shared/Config" resolves on disk but not in the DataModel (walk reached ServerScriptService.shared.Config)
check-guards: 1 violation(s)
EXIT=1
```

| Fixture | Rule asserted (exact set) | Exit |
|---|---|---|
| import-direct | R2 | 1 |
| import-transitive | R2 (chain `CardTable -> Util -> ShopCatalog`) | 1 |
| import-nonliteral | R3 | 1 |
| import-clean | none | 0 |
| engine-suppressed | R3b | 1 |
| strict-missing | R1 (both files) | 1 |
| net-hygiene | R4 | 1 |
| secret-name | R5 | 1 |
| cross-mount | R6 | 1 |

Real repository, with `scripts/ci/zones.luau` present:

```
$ lune run scripts/ci/check-guards.luau
check-guards: ok (17 files, 25 requires, 3 guarded roots)        exit 0
$ lune run scripts/ci/check-guards.luau --print-zones
src/server/engine src/server/core src/shared/Net                 exit 0
```

## Per-rule scan scope as implemented

| Rule | Scope | zones key |
|---|---|---|
| R1 strict header | every `.luau` under `src`, `scripts`, `tests` (fixtures/build/vendor/tools skipped) | `scanDirs` |
| R2 forbidden import closure | roots: guarded-name files under `src/` plus every pure-zone file | `guardedNamePrefixes`, `pureZones`, `forbiddenSegments` |
| R3 non-literal require, banned constructs | roots and every module the closure reaches | (derived) |
| R3b suppression comments, non-relative requires | pure zones only (unstripped text for suppressions) | `pureZones` |
| R4 Net hygiene | `src/` only | `shippedDirs`, `netOwners` |
| R5 secret names | under `src/client` and `src/shared` only | `shippedDirs`, `secretNames` |
| R6 DataModel twin, unresolvable require | `src/` only | `shippedDirs`, `mounts` / `default.project.json` |

R4, R5 and R6 do not look at `scripts/` or `tests/`. No name list was shortened and no per-file exception exists.

## `--print-zones` with an empty list (proved by execution)

`pureZones = {}` was temporarily set (backup restored byte for byte afterwards):

```
EXIT=1
STDOUT bytes: 0
STDERR: check-guards: --print-zones: zones.pureZones is empty; refusing to print nothing and exit 0
```

Restored: `src/server/engine src/server/core src/shared/Net`, exit 0. This path is not covered by an automated spec (the CLI reads the one real `zones.luau`, and adding a config-override flag would be a second way to bypass the guard); the manual proof above is the evidence.

## Mutation checks (the guard and its spec detect what they claim to)

| Mutation (then restored via `git checkout -- scripts/ci/zones.luau`) | Result |
|---|---|
| remove `"shop"` from `forbiddenSegments` | spec still green: `ShopCatalog` also matches `"catalog"`. Not a gap, but the mutation was not discriminating |
| remove `"shop"` AND `"catalog"` | `import-transitive` FAILS: `check-guards: ok (3 files, 2 requires, 3 guarded roots)` (expected 1, got 0) |
| `shippedDirs = { "src", "scripts", "tests" }` (the scope trap the plan warned about) | `check-guards` on the real repo reports R6 for `scripts/ci/*.luau` and R4 for `scripts/ci/zones.luau:40..46`; the real-repo spec case FAILS. The scope regression is caught |

An ad hoc tree outside the repo (comment-stripping and owner exemption): `--[==[ ]==]` and `--[[ ]]` blocks and a `-- require("./ShopLine")` comment are not counted, a `"a -- not a comment"` string does not swallow the require after it, and `OnServerEvent` in `NetServer.luau` / `FireServer` in `ClientNet.luau` are permitted. Result `check-guards: ok (4 files, 1 requires, 2 guarded roots)`, exit 0.

## Gates after the final commit

```
stylua --check src scripts tests          EXIT=0
selene src scripts tests                  0 errors / 0 warnings / 0 parse errors  EXIT=0
luau-lsp analyze --platform standard --base-luaurc .luaurc --ignore "**/fixtures/**" scripts tests src/server/engine   EXIT=0
lune run tests/run.luau                   51 passed, 0 failed, 0 todo in 1.05s
```

The luau-lsp run is the standard platform, so it does not use a sourcemap and trap 4 does not apply; this plan generated no `sourcemap.json` and wrote nothing to `build/`.

## Deviations from Plan

### Divergences found by executing

**1. [Divergence] `strict-missing` fixture lives in `src/server/services/`, not `src/server/core/`**
- The plan puts `NoHeader.luau` and `WrongHeader.luau` in `core/`, which is a pure zone. `WrongHeader`'s `--!nonstrict` there also trips R3b, so the fixture would fire two rules and could not prove R1 in isolation.
- Fix: moved to `services/`. The spec asserts the exact rule set `{ R1 }`.

**2. [Divergence] The R6 message follows the uniform line format**
- The plan wrote `R6 cross-mount require: <file>:<line> "<target>" ...`, which contradicts its own `<RULE_ID> <path>:<line> <message>` format. Emitted: `R6 <file>:<line> cross-mount require "<target>" resolves on disk but not in the DataModel (walk reached <dm path>)`. The substrings `cross-mount` and `resolves on disk but not in the DataModel` are intact.

**3. [Divergence] Rule id for suppression is `R3b`, and the plan's needles `R3` still match as a prefix**
- The spec asserts the exact id `R3b` rather than a prefix match, so `engine-suppressed` cannot pass by tripping R3.

**4. [Divergence] The plan's spec used `${...}` interpolation, which is not Luau**
- Used backtick interpolation. The plan allowed this.

**5. [Divergence] `luau-lsp` also loads the parent checkout's `.luaurc`**
- Output shows `Loading Luau configuration from /home/user/robloxspoons/.luaurc` in addition to the worktree's. Harmless here (identical file); recorded because it is a worktree environment fact, not a repo fact.

**6. [Environment] Sandbox refuses shell loops and `>/dev/null` around `luau-lsp`**
- The harness blocked compound commands it could not prove were not git. Fixture runs and the analyze run were driven by small scripts in the session scratchpad, not committed.

### Additions beyond the plan (Rule 2, tightening only)

- **A scan that finds zero files, or a root that is not a directory, exits 1** (`a scan of nothing must not look green`). Spec-covered. Without it a wrong root argument reads green.
- **R3 also applies to every module reached by the R2 closure**, not only roots (see key-decisions). Not triggered on the current tree.
- **Pure zones reject any non-relative require** (`@lune/...`, `@game/...`) as R3. The research text asks for it; the plan's rule list omitted it. Not triggered on the current tree.
- **Unknown arguments exit 1** (`check-guards: unknown argument: ...`). The literal `--` separator is tolerated because Lune 0.11.1 passes it through (wave-2 finding).
- **Comment stripper walks string, backtick and long-string literals** so a `--` inside a string cannot swallow the rest of a line. Strings are kept, as planned.
- **Spec asserts the exact set of rule ids and the violation count** on every failing fixture, plus extra cases for `--print-zones`, unknown flag, missing root and empty scan (14 cases rather than 10).
- **The init-module resolution rule is untested**: no `init.luau` exists yet. Implemented as `./` and `../` from an init module start at its directory's parent, mirrored on disk and in the DataModel so the two cannot disagree. Revisit if a later plan introduces init modules.

**Total deviations:** 6 divergences, 6 tightening additions. No rule weakened, no list shortened, no per-file exception, no `todo`.

## Known Stubs

None.

## Threat Flags

None new. Threat register: T-1-19 (R2 closure, proven by `import-direct` and `import-transitive`, mutation-checked), T-1-20 (R3, `import-nonliteral`), T-1-21 (R3b, `engine-suppressed`), T-1-07 (R5, `secret-name`), T-1-05 (R4, `net-hygiene`), T-1-12 (`import-clean` exits 0 with exact counts; whole body wrapped in `pcall`, internal error exits 1) all mitigated and demonstrated by execution.

## Notes for later plans

- `check-guards` is not yet wired into `scripts/verify.luau` or CI (plans 01-10 and 01-11). Splice `--print-zones` output into the FOUND-06 selene and luau-lsp invocations and check its exit status: the shell must not swallow it (`zones=$(lune run ... --print-zones) || exit 1`).
- Sibling wave-3 plans that add files under `src/` will be scanned: a new `src/shared/Net` file needs `--!strict` on line 1, only relative literal requires, and must stay inside its Rojo mount (R6).
- `rootCount` in the success line counts guarded roots as defined above; the figure will grow as pure-zone files land.

## Self-Check: PASSED

- All 18 created files exist and are tracked; `git status` clean for this plan's paths.
- Commits `cb60f74` and `976e277` present in `git log`.
- `.planning/STATE.md`, `.planning/ROADMAP.md` and `REQUIREMENTS.md` not touched.
