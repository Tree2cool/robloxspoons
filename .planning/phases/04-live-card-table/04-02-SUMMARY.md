---
phase: 04-live-card-table
plan: 02
subsystem: ci-guards
tags: [guards, zones, fixtures, manual-checks, found-05, r5]
requires: []
provides:
  - "rankOf banned from src/shared and src/client (code and string literals)"
  - "OnClientEvent owned by src/client/net/ClientNet.luau (R4)"
  - "four guard fixtures proving FOUND-05 by-location coverage, R4 client ownership, R5 scope"
  - "MANUAL-CHECKS.md M-11..M-17 and four NEEDS_HUMAN rows, written before the UI waves"
affects: [04-04, 04-13, 04-20]
tech-stack:
  added: []
  patterns: ["every guard gets a clean control and a mutation injected into its config dependency"]
key-files:
  created:
    - tests/guards/fixtures/import-pure-zone/src/server/core/IdleClock.luau
    - tests/guards/fixtures/import-pure-zone/src/server/core/CosmeticsBridge.luau
    - tests/guards/fixtures/net-hygiene-client/src/client/ui/CardHud.luau
    - tests/guards/fixtures/net-hygiene-client/src/client/ui/ShopPanel.luau
    - tests/guards/fixtures/secret-rankof/src/shared/Leak.luau
    - tests/guards/fixtures/secret-rankof-comment/src/shared/Fine.luau
  modified:
    - scripts/ci/zones.luau
    - tests/guards/guards.spec.luau
    - MANUAL-CHECKS.md
    - NEEDS_HUMAN.md
decisions:
  - "D-38 withdrawn: guardedNamePrefixes byte-identical, comment records why"
  - "D-37 comments-included withdrawn: R5 scope is code plus string literals"
metrics:
  tasks: 3
  files: 10
completed: 2026-11-06
---

# Phase 4 Plan 02: Guards and Device Rows Summary

One `secretNames` entry (`rankOf`), one `netOwners` entry (`OnClientEvent`), four fixtures that prove existing guards (each watched going red under a mutated config), and manual checks M-11..M-17 written before any UI work.

## Commits

- 6170d11 feat: zones.luau entries
- test: four guard fixtures + spec cases
- docs: M-11..M-17 and NEEDS_HUMAN rows

## check-guards before and after (guarded roots identical)

```
before: check-guards: ok (97 files, 283 requires, 23 guarded roots)
after:  check-guards: ok (97 files, 283 requires, 23 guarded roots)
```

`guardedNamePrefixes` is byte-identical (`{ "Scoring", "CardTable", "SpoonPlacement" }`); `pureZones` untouched.

Probe values: comment-only rankOf survives strip `false`, string literal `true`, `pos.X` trips `os.` `true`.
`grep -rn rankOf src/shared src/client` and `grep -rn OnClientEvent src` are both empty.

## Fixture output (unmodified prefix list)

```
import-pure-zone:
R2 src/server/core/IdleClock.luau:6 forbidden import: IdleClock -> CosmeticsBridge (path segment matches "cosmetic")
check-guards: 1 violation(s)                                            exit=1

net-hygiene-client:
R4 src/client/ui/CardHud.luau:9 OnClientEvent may appear only in src/client/net/ClientNet.luau
check-guards: 1 violation(s)                                            exit=1   (no R2)

secret-rankof:
R5 src/shared/Leak.luau:5 hidden-data name rankOf must not appear in client or shared code
check-guards: 1 violation(s)                                            exit=1   (string line 5, not comment line 2)

secret-rankof-comment:
check-guards: ok (1 files, 0 requires, 0 guarded roots)                 exit=0
```

## Mutations (each injected into zones.luau, watched red, restored with `git checkout -- scripts/ci/zones.luau`)

| Mutation | Result |
|----------|--------|
| remove `src/server/core` from `pureZones` | `import-pure-zone` -> `ok (2 files, 1 requires, 0 guarded roots)` exit 0; spec FAILs `import-pure-zone` (plus `import-clean` and `--print-zones`, expected collateral) |
| add `src/client/ui` to `pureZones` | `net-hygiene-client` -> `R2 ...CardHud -> ShopPanel (path segment matches "shop")` + `R4`; spec FAILs it. This is the Phase 7 alarm ringing; it can only ring because the `require("./ShopPanel")` is present |
| remove `OnClientEvent` from `netOwners` | `net-hygiene-client` -> `ok (2 files, 1 requires, 0 guarded roots)` exit 0 (the pinned probe output); spec FAILs |
| remove `rankOf` from `secretNames` | `secret-rankof` -> `ok (1 files, 0 requires, 0 guarded roots)` exit 0; spec FAILs |

After restore: guard suite `23 passed, 0 failed, 0 todo`, repo guard ok with 23 guarded roots.

## verify.luau (derived at execution time, nothing hard-coded)

```
before MANUAL-CHECKS edit: 8 signed off, 2 unsigned.
after:                     8 signed off, 9 unsigned.   (+7; M-11..M-17 listed under NOT VERIFIED HERE)
```

## Timing

Full suite, two runs here: `661 passed, 0 failed, 0 todo in 27.37s` and `27.72s`. The 20.53 s figure in the plan is from a different machine and I did not take a before reading on this one, so I cannot attribute a clean delta to the four fixtures. The guard spec alone runs in 0.91-0.93 s for 23 tests. The 04-20 budget owner should re-measure on a quiet CI runner; this reading is flagged rather than treated as a pass or fail against 23.5 s.

## Deviations from Plan

**1. [Rule 1 - Plan defect] IdleClock needle line number.** The plan's fixture A needle was `src/server/core/IdleClock.luau:2`, but the plan's own fixture content puts the `require` on line 6 (after a 4-line comment). The observed output is `:6`, so the case asserts `:6`. No behaviour changed.

**2. Bash tool restrictions.** In this worktree the shell refused heredocs and loops, so files were written with the Write/Edit tools. No effect on content.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

All six fixture files, the spec cases, `zones.luau`, `MANUAL-CHECKS.md` (7 headings, 7 sign-off lines) and `NEEDS_HUMAN.md` (4 new rows) exist; three task commits exist.
