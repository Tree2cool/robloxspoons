---
phase: 03-placement-rules-map-pipeline-and-validator
plan: 10
subsystem: gate-evidence
tags: [gate-g2, validation, verification-debt, manual-checks]
requires: ["03-01", "03-02", "03-03", "03-04", "03-05", "03-06", "03-07", "03-08", "03-09"]
provides:
  - "03-G2-REPORT.md: Gate G2 verdict, nine-gate table, measured numbers, Phase 7a handoff, carried debt"
  - "03-VALIDATION.md signed off (nyquist_compliant, wave_0_complete), feedback-latency item left open"
  - "Verification Debt rows V-4, V-17, V-18, V-19, V-20 updated"
  - "MANUAL-CHECKS.md M-10 (blocking)"
key-files:
  created:
    - .planning/phases/03-placement-rules-map-pipeline-and-validator/03-G2-REPORT.md
  modified:
    - .planning/phases/03-placement-rules-map-pipeline-and-validator/03-VALIDATION.md
    - .planning/research/SUMMARY.md
    - MANUAL-CHECKS.md
requirements-completed: [MAP-02, MAP-03, HIDE-06, HIDE-07]
completed: 2026-11-04
---

# Phase 3 Plan 10: Gate G2 report Summary

Gate G2 is recorded as PASSED with named debt: a self-attested nine-gate table quoting verbatim red output, gate 9 demonstrated red on a new `src/` file and a new `tests/` file, M-10 added as a blocking Studio check, and the Verification Debt rows brought up to date.

## Verdict and evidence

`Gate G2: PASSED`. Fresh chain in this worktree: `verify.luau` 14/14 in 32.1 s; `tests/run.luau` `657 passed, 0 failed, 0 todo in 29.06s`; `validate-map: ok (21 spots, 9 seats)`; `--filter placement` 120 passed; `--filter maps` 88 passed; `--filter corpus` 40 passed; `--filter maze` 11 passed.

## Gate 9 demonstration (this plan's own output)

Deliberate `local gate9Probe: number = "not a number"` inserted before the final `return` of `src/server/core/SpoonPlacement.luau` (line 414) and at line 2 of `tests/placement/obb.spec.luau`:

```
src/server/core/SpoonPlacement.luau(414,1): TypeError: Expected this to be 'number', but got 'string'
analyze: FAILED: luau-lsp exited 1
tests/placement/obb.spec.luau(2,1): TypeError: Expected this to be 'number', but got 'string'
analyze: FAILED: luau-lsp exited 1
```
Both files restored, all three analyze invocations `analyze: ok`, working tree clean. `sourcemap.json` holds `Obb`, `Placement`, `SpoonPlacement`, `WalkGrid`. A first attempt (appended after the trailing `return`) gave `SyntaxError: Expected <eof>, got 'local'`, also red but not a type error, so it was redone. The repo-wide `--ignore "**/fixtures/**"` form is refused in a worktree, so analyze was run per directory (`src` roblox platform; `src/server/core scripts` and `tests/placement` standard platform). `verify.luau` itself ran its repo-wide steps 8 and 9 green.

## Gate rows that carry a qualification (none empty)

- Gate 3: covered across 03-06 (cap red, empty bake stops at `graybox did not bake: 4 faults` before the floors) and 03-07 (`counters.linkTests = 8`). Not a clean tick on 03-06.
- Gate 4: planned shelf target is `Unreachable`; mutation applied to the flat-room `OutOfReach` row.
- Gate 8: CI side key set only; runtime side substring-only. Value parity is unobserved in CI and carried as M-10.

## Deviations from Plan

1. **[Rule 1] Gate 9 first probe was a syntax error, not a type error.** Redone with the line before the `return`.
2. **[Plan defect] Maze column count.** Plan said 61,504; 03-07 measured 63,001. The report uses the measured figure.
3. **[Judgement] `03-VALIDATION.md` feedback-latency item left unticked.** Full suite 29.06 s is inside 30 s by 0.9 s, the `verify.luau` chain at 32.1 s is outside; this is the open owner decision on suite timing. `nyquist_compliant: true` is set on the automated-verification evidence, and the Approval line says what remains open.
4. **[Plan defect] Arity-lock filter.** The validation map named `--filter placement` for the HIDE-07 lock, but it lives in `config_lock.spec.luau`; the command column now says `--filter config_lock`.
5. Orchestrator's timings (28.4 s suite, 31.9 s chain) differ slightly from mine (29.06 s, 32.1 s); both are printed and attributed.

## Open items for the owner and the orchestrator

- **Suite timing (open owner decision, not recorded as accepted):** 15.94 s (Phase 1) to about 25-26 s (Phase 2, accepted) to 29.06 s now.
- **M-08 and M-10** unsigned and blocking; **M-09** unsigned, not blocking. M-06's signature line is byte-for-byte untouched.
- Phase 5: `RaycastParams.RespectCanCollide` defaults to `false`; V-18 left OPEN against Phase 5.
- V-19 is not upgraded (MEDIUM / LOW). `create.roblox.com` reachable only via `curl` on `.md` URLs; `madstudioroblox.github.io`, `jsdotlua.github.io`, `lune-org.github.io` unreachable.

## Commits

- b787191 docs(03-10): Gate G2 report, nine-gate table and M-10
- d399196 docs(03-10): sign off 03-VALIDATION and update Verification Debt rows

## Known Stubs

None. No source files changed; STATE.md and ROADMAP.md untouched.

## Self-Check: PASSED

`03-G2-REPORT.md` exists; `grep -c '^## M-' MANUAL-CHECKS.md` returns 10; `verify.luau` lists M-10 unsigned (`6 signed off, 4 unsigned`); no `TBD`, no `⬜ pending`, no `Approval:** pending` in `03-VALIDATION.md`; commits b787191 and d399196 present.
