---
phase: 01-foundations-contracts-and-spec-lock
plan: 04
subsystem: testing
tags: [selene, luau-lsp, stylua, lune, engine-purity, exit-code-traps, negative-controls]

requires:
  - phase: 01-01
    provides: pinned toolchain, .luaurc, selene.pure.toml, vendored globalTypes.None.d.luau
  - phase: 01-02
    provides: lune test harness (tests/run.luau, Test.luau)
provides:
  - "Executed proof that both FOUND-06 engine-purity layers can fail (selene value lint, luau-lsp standard-platform type check)"
  - "Executed proofs of all four luau-lsp exit-code traps, asserting diagnostic text and exit code"
  - "Executed proof that CI-mode stylua --check and selene (roblox std) can fail"
  - "Regression test banning --formatter plain from gate files"
affects: [01-03, 01-10, 01-11, 01-12]

tech-stack:
  added: []
  patterns:
    - "Every negative proof asserts the diagnostic text AND the exit code; positive controls ride in the same case"
    - "Config-isolation by nested .luaurc (nearest wins), not --base-luaurc"
    - "CI-mode negative proofs feed tools via stdin so no ignore list can apply"

key-files:
  created:
    - tests/purity/purity.spec.luau
    - tests/purity/fixtures/engine-roblox-value/src/server/engine/Bad.luau
    - tests/purity/fixtures/engine-roblox-type/src/server/engine/BadType.luau
    - tests/purity/fixtures/engine-clean/src/server/engine/Good.luau
    - tests/traps/traps.spec.luau
    - tests/traps/fixtures/lint-only/Lint.luau
    - tests/traps/fixtures/lint-only-disabled/Lint.luau
    - tests/traps/fixtures/lint-only-disabled/.luaurc
    - tests/traps/fixtures/type-error/TypeError.luau
    - tests/traps/fixtures/roblox-member/Member.luau
  modified: []

key-decisions:
  - "A1 held: luau-lsp --platform standard flags a type-only Instance; guard rule R7 NOT needed"
  - "Sourcemap-failure detection must match BOTH '[ERROR] Failed to load' and 'Sourcemap parsing failed'; counting [ERROR] lines alone misses a malformed sourcemap"

patterns-established:
  - "Mutation-check a trap proof: flip the guarded setting, confirm the proof goes red, restore"

requirements-completed: []
requirements-contributed: [FOUND-06, FOUND-02]

duration: 1 session
completed: 2026-11-02
---

# Phase 1 Plan 04: Engine-Purity Fixtures and Exit-Code Trap Proofs Summary

**Both FOUND-06 layers and all four luau-lsp exit-code traps are now permanent, executed fixtures that assert the diagnostic text as well as the exit code; executing them found that a malformed sourcemap passes silently AND prints no `[ERROR]` line.**

## Performance

- **Tasks:** 2 of 2
- **Files created:** 10 (no files modified)
- **Full suite:** `57 passed, 0 failed, 0 todo in 8.69s` (5 purity cases, 15 trap cases)
- The trap spec takes about 8s because several cases load the 677 KB definitions file; `--filter purity` runs in 0.1s.

## Task Commits

1. **Task 1: purity fixtures and spec** - `a32b158` (test)
2. **Task 2: trap fixtures and spec** - `c951855` (test)

## Observed exit codes (every row was executed; verbatim diagnostics asserted)

### Purity (5 cases)

| # | Case | Command | Observed exit | Asserted diagnostic |
|---|------|---------|---------------|---------------------|
| P1 | value ref `game` fails allow-list lint | `selene --config selene.pure.toml <engine-roblox-value>` | **1** | `undefined_variable`, ``"`game` is not defined"`` |
| P2 | linter cannot see a type-only ref | `selene --config selene.pure.toml <engine-roblox-type>` | **0** | `0 errors` |
| P3 | typecheck catches the type-only ref | `luau-lsp analyze --platform standard --base-luaurc .luaurc BadType.luau` | **1** | `Unknown type 'Instance'` |
| P4 | clean file passes both layers | selene.pure + analyze standard on `Good.luau` | **0 / 0** | `0 errors`; no `TypeError` |
| P5 | real pure zones clean | `selene --config selene.pure.toml src/server/engine` (+ zones from check-guards when present) | **0** | `0 errors` |

### Traps (15 cases; the plan's 12 plus 3 for the fourth trap)

| # | Case | Observed exit | Asserted diagnostic / note |
|---|------|---------------|----------------------------|
| T1 | TRAP 1: `lintErrors: true`, lint-only file | **1** | `LocalUnused`, and no `TypeError` (proves lint-only) |
| T2 | TRAP 1 counter: nested `.luaurc` `lintErrors: false`, byte-identical file | **0** | `LocalUnused` still printed; `lint-only-disabled/.luaurc` loaded; sources asserted byte-equal |
| T3 | TRAP 1: committed `.luaurc` | n/a | decoded JSON: `lintErrors == true`, `typeErrors == true` |
| T4 | TRAP 2: default formatter on type error | **1** | `TypeError: Expected this to be 'number', but got 'string'` |
| T5 | TRAP 2: `--formatter plain`, same file | **0** | `(W0) TypeError` (printed as a warning, exit 0) |
| T6 | TRAP 2: gate files do not use the flag | n/a | detector proven to match `--formatter plain` and `--formatter=plain` first; scans `.github/workflows/*`, `.githooks/*`, `scripts/verify.luau` |
| T7 | TRAP 3: roblox platform + `--definitions` | **1** | `Key 'ThisMemberDoesNotExist' not found in external type 'Part'` |
| T8 | TRAP 3: roblox platform, no `--definitions` | **1** | `does not download definitions files`, `Unknown global 'Instance'`; member NOT mentioned (DIVERGENCE, see below) |
| T9 | TRAP 3: omit `--platform` (default roblox) vs `--platform standard` on `BadType.luau` | **0** vs **1** | standard run: `Unknown type 'Instance'` |
| T10 | TRAP 3: definitions file pinned | n/a | size 677555 bytes |
| T11 | TRAP 4: missing sourcemap path | **0** | `[ERROR] Failed to load ... for workspace 'CLI'`, exactly one `[ERROR]` |
| T12 | TRAP 4: malformed sourcemap | **0** | `Sourcemap parsing failed, sourcemap is not loaded: ...`, zero `[ERROR]` lines (DIVERGENCE) |
| T13 | TRAP 4 control: valid sourcemap | **0** | zero `[ERROR]`, no `Failed to load`, no `Sourcemap parsing failed` |
| T14 | CI: `stylua --check -` bad input | **1** | `Diff in stdin`; control: well-formatted input exits 0 |
| T15 | CI: `selene -` bad input | **1** | `undefined_variable`, `someGlobalThatDoesNotExist`; control: `game:GetService` accepted (roblox std active) |

## Assumption A1

**A1 held.** `luau-lsp analyze --platform standard` flags a type-only `Instance`:
`BadType.luau(2,30): TypeError: Unknown type 'Instance'`, exit 1, while `selene --config selene.pure.toml` on the same file exits 0. This is what justifies layer 2 rather than treating it as belt-and-braces. The R7 fallback (a Roblox type-identifier scan in `scripts/ci/check-guards.luau`) was **not implemented** because it was not needed.

## Divergences from research (recorded, not silently adapted)

1. **Trap 3 without `--definitions` is not silent for this fixture.** Research said the run would simply not check the member. Observed: exit **1** with `WARNING: --platform is set to 'roblox' but no definitions files are provided. 'luau-lsp analyze' does not download definitions files` and `TypeError: Unknown global 'Instance'`. The verdict still differs from the with-definitions run (different reason), and the member error is still never reported, so the plan's assertion survives; the test now also asserts the real reason. A file that does not touch a Roblox global would still pass with only that WARNING.
2. **Trap 4 has a second, quieter variant.** A *malformed* sourcemap prints `Sourcemap parsing failed, sourcemap is not loaded: [json.exception.parse_error.101] ...`, exits 0, and prints **no `[ERROR]` line**. The 01-01 / 01-02 technique of counting `[ERROR]` lines would read this as healthy. **Plans 01-10 and 01-11 must fail on either `[ERROR]` or `Sourcemap parsing failed`** (or, more robustly, on any `Failed to load` / `Sourcemap parsing failed` substring).
3. **`process.exec` stdin syntax.** The plan's `{ stdin = ... }` is not valid in Lune 0.11.1; the typedef is `{ stdio = { stdin = ... } }`. Used the latter.
4. **Trap-2 plain-formatter output shape.** Prefix is `file:2:1-43: (W0) TypeError:` versus the default `file(2,1): TypeError:`.
5. **Worktree nesting side effect.** In this worktree luau-lsp also logs `Loading Luau configuration from /home/user/robloxspoons/.luaurc` (the parent checkout) because the worktree sits inside it. Harmless here (same config) but explains the extra INFO line.

## Mechanism for the CI-mode negative proofs

**stdin**, the plan's first choice; no fallback needed. Evidence the tools really checked the input:
- `stylua --check -` on `local x    =1\n`: exit 1, stdout `Diff in stdin:` with the `-local x    =1` / `+local x = 1` diff. Control `local x = 1\n`: exit 0.
- `selene -` on an undefined global: exit 1, `error[undefined_variable]: ``someGlobalThatDoesNotExist`` is not defined` located at `-:2:11`, `1 errors`. Control using `game:GetService("Players")`: exit 0, which also shows the Roblox std (`selene.toml`) is the one in force.

Because the input never touches a path, `.styluaignore` and `selene.toml`'s `exclude` cannot be what made the result. Whether the tools honour those ignore lists for explicitly named file arguments is therefore still **unsettled**; plan 01-11 (pre-commit hook) should test it.

## Mutation checks (the proofs themselves can fail)

| Mutation (restored afterwards) | Result |
|---|---|
| `.luaurc` `lintErrors` set to `false` | T1 FAILS (`expected a falsy value, got true`, with `LocalUnused` printed) and T3 FAILS (`expected true, got false`); the nested-config counter case still passes, as it should |
| temporary `.githooks/pre-commit` containing `--formatter plain` | T6 FAILS naming the file |

`git diff` was clean for `.luaurc` after restoration; the temporary hook file was removed.

## Deviations from Plan

### Auto-fixed / additions (Rules 2-3)

**1. [Rule 2 - Missing critical] Fourth trap not covered by the plan**
- Added T11-T13 (missing, malformed, valid-control sourcemap), as the orchestrator required. Generated sourcemaps live under `build/01-04/` (gitignored); the valid control is a hand-written 1-line JSON so it does not depend on `rojo sourcemap` or on 01-07's `default.project.json` edit.

**2. [Rule 2] Assertions strengthened beyond the plan**
- Every failure case also asserts the diagnostic text. T2 asserts the lint is still reported and that the nested `.luaurc` was the one loaded. T6 proves its own detector first, and enumerates `.github/workflows/*` and `.githooks/*` rather than only three named files. T9 compares the same file under both platforms. T3 parses the JSON rather than string-matching `"lintErrors": true`.

**3. [Rule 3 - Blocking] `process.exec` stdin option shape** (see Divergence 3).

**4. [Rule 3 - Blocking] `scripts/ci/check-guards.luau` not yet landed**
- Plan 01-03 builds it in parallel. P5 therefore always checks the hard-coded `src/server/engine` and, **when the file exists**, additionally checks every zone from `--print-zones` (skipping directories that do not exist yet). **The `--print-zones` branch was NOT exercised in this worktree**, so its output format (whitespace-separated paths) is an assumption until 01-03 merges. Re-run `lune run tests/run.luau -- --filter purity` after the merge.

**Total deviations:** 4, none weakened a check. No rule loosened, no case dropped, no config touched.

## Notes for later plans

- `luau-lsp analyze` over `tests/` must pass `--ignore "**/fixtures/**"`: the trap and purity fixtures are deliberately ill-typed. Verified `luau-lsp analyze --platform standard --base-luaurc .luaurc --ignore "**/fixtures/**" tests` exits 0.
- Gate chains (01-10, 01-11): do not rely on analyze's exit code for the roblox-platform step; assert no `Failed to load` and no `Sourcemap parsing failed` in its output.

## Known Stubs

None.

## Threat Flags

None. Threat register: T-1-12 mitigated (executed, mutation-checked); T-1-22 mitigated (A1 settled by execution); T-1-23 mitigated (677555-byte assertion in T10); T-1-24 mitigated (T6); T-1-51 mitigated (T14/T15 via stdin with positive controls).

## Self-Check: PASSED

- All 10 created files present and tracked; commits `a32b158` and `c951855` in `git log`.
- `stylua --check src tests` exit 0; `selene src tests` 0 errors; `luau-lsp analyze --platform standard --base-luaurc .luaurc --ignore "**/fixtures/**" tests` exit 0.
- Full suite `57 passed, 0 failed, 0 todo`.
- STATE.md, ROADMAP.md and REQUIREMENTS.md untouched.
