---
phase: 01-foundations-contracts-and-spec-lock
plan: 11
subsystem: ci-and-verification
tags: [github-actions, pre-commit, luau-lsp, verify, manual-checks, fresh-clone]

requires:
  - phase: 01-03
    provides: check-guards, --print-zones (exit 1 on empty list)
  - phase: 01-04
    provides: exit-code trap proofs, --formatter plain regression test
  - phase: 01-10
    provides: check-built-place
provides:
  - ".github/workflows/ci.yml: 14 hard-failing steps on every push and PR"
  - "scripts/ci/analyze.luau: the single luau-lsp gate (final detector form)"
  - ".githooks/pre-commit: stylua + selene on staged Luau only"
  - "scripts/verify.luau: local mirror of CI plus the unsigned manual-check list"
  - "MANUAL-CHECKS.md M-01..M-06, NEEDS_HUMAN.md, README.md"
affects: [01-12]

key-files:
  created:
    - .github/workflows/ci.yml
    - .githooks/pre-commit
    - scripts/dev/setup-hooks.sh
    - scripts/verify.luau
    - scripts/ci/analyze.luau
    - tests/ci/analyze.spec.luau
    - tests/ci/verify.spec.luau
    - MANUAL-CHECKS.md
    - NEEDS_HUMAN.md
    - README.md
  modified: []

key-decisions:
  - "luau-lsp is invoked through scripts/ci/analyze.luau, not bare, because the final detector form needs output inspection that a YAML run line cannot do portably"
  - "verify.luau holds the run strings character-for-character equal to ci.yml; a spec compares them"
  - "stylua in the hook needs --respect-ignores (proved by execution)"

requirements-completed: []
requirements-contributed: [FOUND-01, FOUND-02, FOUND-03, FOUND-05, FOUND-06, FOUND-07, FOUND-08, MAP-01, SCORE-06]

completed: 2026-11-03
---

# Phase 1 Plan 11: CI, hook, verify and manual checks Summary

**A 14-step hard-failing GitHub Actions workflow, a luau-lsp gate that passes only on exit 0 with none of the three failure markers, a format+lint pre-commit hook, and one `verify.luau` that mirrors CI and was rehearsed green from a fresh clone.**

## Task Commits

1. Task 1, ci.yml + hook + analyze wrapper: `9650539`
2. Task 2, verify.luau + drift spec: `53c14b3`
3. Task 3, MANUAL-CHECKS / NEEDS_HUMAN / README: `05b1272`

## CI has NOT run on the remote

This environment does not push. `ci.yml` has never executed on GitHub. The first green run is an owner action (listed in `NEEDS_HUMAN.md`, handed to 01-12). Unverified from this container (GitHub API returns 403 here): that `actions/checkout@v7` exists, and the SHA of `setup-rokit` v0.2.1 (taken from the plan, not re-fetched). If `checkout@v7` does not exist the first run will say so immediately.

## Deviation: luau-lsp is wrapped (Rule 2)

The plan's ci.yml called `luau-lsp analyze` directly, which relies on exit code alone. The critical notes require the final form (exit 0 AND none of `Failed to load`, `Sourcemap parsing failed`, `TypeError`). A YAML one-liner cannot do that, so both typecheck steps call `lune run scripts/ci/analyze.luau <args>`, which runs `luau-lsp analyze`, echoes its output, and fails on a non-zero code or any marker. It also refuses `--formatter` in any spelling and refuses to run with no paths. `tests/ci/analyze.spec.luau` (8 cases, each asserting the reason substring) covers: clean pass, real TypeError, lint-only (exit code path), missing sourcemap (`Failed to load`), malformed sourcemap (`Sourcemap parsing failed`, with no `[ERROR]` line asserted), valid sourcemap, both `--formatter` spellings, no arguments.

**Not reproduced:** the fifth refinement case (a TypeError that exits 0). Two minimal fixtures comparing a Lune `Instance.Parent` to nil printed nothing and exited 0, so I could not build a permanent fixture for it. The TypeError marker check covers it by construction, but no test proves that specific path. During development the wrapper did catch a real `TypeError` in my own `verify.luau` (verbatim: `scripts/verify.luau(102,10): TypeError: Expected this to be 'number', but got 'number?'`), which is the same class of case.

## Other deviations

- **Build step** is `mkdir -p build && rojo build ...` (rojo does not create the output dir; fresh clones have no `build/`). The plan's ci.yml omitted the mkdir.
- **`--print-zones` capture** has `|| exit 1` as well as `test -n`, per the critical notes.

## Pure-zone guard, observed

```
zones="$(true)" || exit 1; test -n "$zones" || {...; exit 1}
-> FATAL: empty pure-zone list - the FOUND-06 gate would be vacuous    rc=1
real command  -> pure zones: src/server/engine src/server/core src/shared/Net   rc=0
failing cmd   -> rc=1 (caught by || exit 1)
```

`grep -c 'steps.zones.outputs.list' ci.yml` = 2; `print-zones)` appears once (in the capture). Both asserted permanently in `tests/ci/verify.spec.luau`.

## StyLua ignore behaviour

`stylua --help` documents `--respect-ignores`: "Respect .styluaignore and glob matching for file paths provided directly to the tool". Proven by execution with a mis-formatted file under `tests/meta/fixtures/` (ignored path): without the flag `stylua --check` exited 1, with it exited 0. So the flag IS needed and the hook uses it; otherwise deliberately broken fixtures would be uncommittable. Selene's `exclude` is honoured for explicit files already (no flag).

## Pre-commit hook, observed

Negative test wrote `src/server/__hooktest.luau` inside the repo with a trap:

```
Diff in src/server/__hooktest.luau:
1   1    | --!strict
2        |-local x    =1
    2    |+local x = 1
hook exit code: 1   <-- MUST be non-zero
```

Commit was blocked, the file is gone, nothing committed. Also observed: a well-formatted file passes (rc 0); a lint-only finding (`local unused`) blocks (rc 1). The hook has no luau-lsp and no tests. The hook also ran on the three real commits of this plan.

## Stop at first failure, observed

An unplanned but genuine observation: the first end-to-end `verify.luau` run failed at step 9 on my own type error, printed the step, command, reason, stdout and stderr, said `later steps were NOT run`, and exited 1 (steps 10-14 did not execute).

## verify.luau end to end (verbatim, working tree)

```
-> [1/14] Tool versions ... ok
 ...
-> [8/14] Typecheck (roblox platform)            ok (2.0s)
-> [9/14] Typecheck (standard platform, ...)     ok (0.1s)
-> [10/14] Structural guards ...                 ok (0.1s)
-> [12/14] Tests (unit, fuzz, ...)               ok (14.4s)
-> [13/14] Build                                 ok (0.0s)
-> [14/14] Built-place require check (FOUND-03)  ok (0.1s)

verify: all 14 automated steps passed in 17.0s
NOT VERIFIED HERE - needs a human with Studio (see MANUAL-CHECKS.md)
  [ ] M-01 ... M-06 (all six listed)
  0 signed off, 6 unsigned.
real 0m17.080s
```

Suite: **330 passed, 0 failed, 3 todo** (baseline 316; +8 analyze cases, +6 verify/ci cases). `check-guards: ok (59 files, 121 requires, 12 guarded roots)`; `check-built-place: ok (17 requires in 24 modules)`.

## Fresh-clone rehearsal (performed, from the committed HEAD `05b1272`)

`git clone --local` into the session scratchpad, then in the clone:

```
git status --porcelain      -> (empty)
rokit install               -> NOT RUN: rokit is not installed here and api.github.com returns 403 (D-16 correction).
                               The pre-installed binaries on PATH were used instead. GitHub Actions is unaffected.
lune setup                  -> Type definitions for Lune v0.11.1 have been set up successfully.
git diff --quiet .luaurc    -> passed ("luaurc stable")
lune run scripts/verify.luau -> all 14 automated steps passed in 16.6s (real 0m16.602s), manual list printed
post-run git status --porcelain -> (empty)
lune run tests/run.luau     -> 330 passed, 0 failed, 3 todo
```

Nothing had to be committed to make the clone work: no untracked or gitignored dependency surfaced (`roblox.yml`, `.luaurc`, `tools/types/`, the `.rbxm`/`.rbxl` fixtures, `.gitattributes` normalisation all survived). Limits of this rehearsal: `~/.lune` typedefs are machine-global, so `lune setup` was a re-run, not a first install; the tools are the same pre-installed binaries rather than a fresh `rokit install`. The rehearsal directory was deleted.

## MANUAL-CHECKS.md

M-01..M-06 each with prerequisites, numbered steps, expected result, an "Observed" line and a parseable sign-off box. M-04 is marked OWNER-ONLY. M-03 uses `("Ping", {nonce = 1})` (accepted) and `{nonce = 0/0}` (rejected `NotFinite`), plus unknown key, missing key, unknown intent and a rate-limit flood, with the expected code for each taken from `Gateway.luau`. The codes `UnknownKey` and `MissingKey` come from the Gateway header comment, not a run.

## Known Stubs

None. `Environments.luau` ids remain 0 and `servePlaceIds` is not yet in `default.project.json`; both are 01-12's job once the owner supplies the numbers.

## Threat flags

None new.

## Self-Check: PASSED

Files exist (`ci.yml`, `pre-commit`, `setup-hooks.sh`, `verify.luau`, `analyze.luau`, both specs, `MANUAL-CHECKS.md`, `NEEDS_HUMAN.md`, `README.md`); commits `9650539`, `53c14b3`, `05b1272` in `git log`; REQUIREMENTS.md untouched; phase not marked complete.
