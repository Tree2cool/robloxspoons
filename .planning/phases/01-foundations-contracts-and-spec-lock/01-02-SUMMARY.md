---
phase: 01-foundations-contracts-and-spec-lock
plan: 02
subsystem: testing
tags: [lune, test-harness, fuzz, xorshift32, bit32, meta-test, strict-typing]

requires:
  - phase: 01-01
    provides: pinned toolchain, .luaurc, Rojo project, SpikeA/SpikeB canaries, selene.pure.toml
provides:
  - "lune run tests/run.luau: the single headless test entrypoint (discovery, --filter, --root, --seed, todo counting)"
  - "Test.luau registration/assertion API, sole owner of FuzzOpts and FuzzDriver, requires nothing"
  - "Fuzz.luau injected property driver; replayable failures (iteration + seed)"
  - "FakeClock and FakeScheduler (integer deciseconds, cancelIsNoop) for SCORE-06"
  - "Rng: pure bit32 xorshift32, first real engine module"
  - "Harness meta-test proving the runner exits 1 on failure, empty discovery, zero-case specs and unmatched filters"
  - "Machine-checked FOUND-01/FOUND-02 file-shape spec"
affects: [01-03, 01-04, 01-05, 01-06, 01-07, 01-08, 01-09, 01-10, 01-11, 01-12, phase-02]

tech-stack:
  added: []
  patterns:
    - "Specs return function(t: Test.Runner); the runner owns execution and accounting"
    - "Fuzz driver is injected (Test.new({ fuzzDriver })); absence registers a case that FAILS, never skips"
    - "Every failure-expecting meta case asserts the REASON, not just a non-zero exit"
    - "Runner is strict on arguments: an unknown flag exits 1"

key-files:
  created:
    - tests/run.luau
    - tests/harness/Test.luau
    - tests/harness/Fuzz.luau
    - tests/harness/FakeClock.luau
    - tests/harness/FakeScheduler.luau
    - tests/harness/modules.spec.luau
    - tests/meta/harness.spec.luau
    - tests/meta/fixtures/failing/bad.spec.luau
    - tests/meta/fixtures/passing/good.spec.luau
    - tests/meta/fixtures/zero-cases/empty.spec.luau
    - tests/meta/fixtures/empty/.gitkeep
    - tests/project/project.spec.luau
    - tests/engine/rng.spec.luau
    - tests/spike/require.spec.luau
    - src/server/engine/Rng.luau
  modified: []

key-decisions:
  - "Dynamic require of discovered specs works under Lune (manifest fallback NOT needed), but needs the .luau extension stripped and a typed-dynamic require for luau-lsp"
  - "Runner tolerates a literal '--' argument because Lune 0.11.1 passes it through to the script"
  - "A --filter that matches nothing is a failure (added beyond the plan)"
  - "FakeScheduler.advance steps time to each entry's due time while firing, then to the target"

patterns-established:
  - "A test that expects failure must assert why it failed; a bare exit-code check can pass for the wrong reason (it did, see Divergence 3)"
  - "Mutation-check a gate: break the thing it guards and confirm the gate goes red, then restore"

requirements-completed: []
requirements-contributed: [FOUND-03, FOUND-01, FOUND-02]

duration: ~1 session
completed: 2026-11-02
---

# Phase 1 Plan 02: Headless Test Harness, Meta-Test and Rng Summary

**`lune run tests/run.luau` is the single test entrypoint: 37 cases green in 0.37s, a meta-test proving it exits 1 on failure / empty discovery / zero-case specs / unmatched filters (each mutation-checked), and a pure bit32 xorshift32 `Rng` verified against an independent Python reference.**

## Performance

- **Tasks:** 3 of 3
- **Files created:** 15 (no files modified)
- **Full suite:** `37 passed, 0 failed, 0 todo in 0.37s`

## Accomplishments

- A runner that cannot read green while verifying nothing: it fails on a failing case, a spec that throws while loading or registering, a spec registering zero cases and zero todos (`no cases registered`), a run discovering zero specs, a `--filter` matching nothing, and any unknown argument.
- A meta-test that drives the real runner through `process.exec` against fixtures and asserts the exit code AND the reason.
- `t.fuzz` with no driver installed fails loudly (`fuzz driver not installed`); the driver is wired in `run.luau` and the wiring is mutation-proven.
- `Rng` matches a reference xorshift32 computed outside Luau (`270369, 67634689, 2647435461, 307599695, 2398689233` for seed 1).
- FOUND-01/FOUND-02 file shape (Workspace `$ignoreUnknownInstances`, code-only mounts, five exact pins with no ranges, `lintErrors`/`typeErrors`, vendored types size) is now an automated spec.
- The Lune half of the require spike passes. Assumptions A1/A2 were already confirmed by wave 1; the plan's fallbacks (darklua `convert_require`, a DataModel-mirrored `src/` tree) were **not required**.

## Task Commits

1. **Task 1: Test, FakeClock, FakeScheduler** - `895abc5` (feat)
2. **Task 2: runner, meta-test, project spec** - `0aba77e` (feat)
3. **Task 3 RED: failing Rng spec + require spike** - `e44cb7d` (test)
4. **Task 3 GREEN: Rng, Fuzz, wiring** - `8ec3ae0` (feat)

## Verbatim output

### Runner summary and the exit-code proofs

```
$ lune run tests/run.luau
...
37 passed, 0 failed, 0 todo in 0.37s                      exit 0

$ lune run tests/run.luau -- --root tests/meta/fixtures/failing
FAIL tests/meta/fixtures/failing/bad.spec.luau::this test is supposed to fail
     deliberate failure proving the runner can fail (expected 2, got 1)
0 passed, 1 failed, 0 todo in 0.00s                       exit 1

$ lune run tests/run.luau -- --root tests/meta/fixtures/zero-cases
FAIL tests/meta/fixtures/zero-cases/empty.spec.luau::<no cases registered>
     spec loaded but registered zero cases and zero todos
0 passed, 1 failed, 0 todo in 0.00s                       exit 1

$ lune run tests/run.luau -- --root tests/meta/fixtures/empty
0 passed, 0 failed, 0 todo in 0.00s
FAIL no spec files discovered under tests/meta/fixtures/empty: an empty run must not look green
                                                          exit 1
```

`lune run tests/run.luau | grep -c "deliberate failure"` printed `0`: the default sweep does not execute fixtures. `grep -c 'fuzz driver not installed'` on the full output printed `0`.

### `--filter` timing (acceptance: under 5 seconds)

```
$ time lune run tests/run.luau -- --filter project
... 6 ok lines ...
6 passed, 0 failed, 0 todo in 0.01s
real	0m0.051s                                          exit 0
```

`--filter rng`: `10 passed, 0 failed, 0 todo in 0.02s`. `--filter require`: `1 passed, 0 failed, 0 todo in 0.02s`.

### TDD RED (Task 3), before `Rng` and `Fuzz` existed

```
FAIL tests/engine/rng.spec.luau::<load>
     runtime error: error requiring module "../harness/Fuzz": could not resolve child component "Fuzz"
0 passed, 1 failed, 0 todo in 0.01s                       exit 1
```

### Mutation checks (the meta-test and wiring detect what they claim to)

| Mutation (applied to a copy, then restored) | Result |
|---|---|
| `if failed > 0` disabled in `run.luau` | meta-test FAILS 2 cases (`spec fails`, `zero cases`) |
| zero-case check disabled | meta-test FAILS `registers zero cases and zero todos` |
| zero-discovery check disabled | meta-test FAILS `no specs are discovered` |
| `fuzzDriver = Fuzz.driver` removed | `nextInt always lands in range` FAILS with `fuzz driver not installed`, exit 1 |
| `Rng.nextInt` made off by one (`hi - lo + 2`, clamp removed) | 3 rng cases FAIL, including the fuzz case: `fuzz "nextInt always lands in range" failed at iteration 30 with seed 1: ... out of range: 6` |

All originals restored (`git status` clean for those files; full suite green afterwards).

### Gate commands re-run after all changes (sourcemap regenerated first; trap 4)

```
1 stylua --check src tests                                   EXIT=0
2 selene src tests                                           0 errors / 0 warnings / 0 parse errors   EXIT=0
3 selene --config selene.pure.toml src/server/engine         0 errors / 0 warnings / 0 parse errors   EXIT=0
4 rojo sourcemap default.project.json --include-non-scripts
    -o sourcemap.json   (deleted beforehand)                 Created sourcemap at sourcemap.json  EXIT=0
5 luau-lsp analyze --platform roblox --sourcemap sourcemap.json
    --definitions=tools/types/globalTypes.None.d.luau src    EXIT=0, [ERROR] lines: 0
      [INFO] Loading definitions file: @roblox - tools/types/globalTypes.None.d.luau
      [WARN] client does not allow didChangeWatchedFiles registration ...
      [INFO] Loading Luau configuration from /home/user/robloxspoons/.luaurc
6 luau-lsp analyze --platform standard src/server/engine     EXIT=0
6b luau-lsp analyze --platform standard --base-luaurc .luaurc
    --ignore "**/fixtures/**" src/server/engine tests        EXIT=0
7 mkdir -p build && rojo build default.project.json
    -o build/spoons.rbxl                                     Built project to spoons.rbxl  EXIT=0
lune setup -> git diff --quiet .luaurc                        stable
```

All seven wave-1 gates still pass, plus the new `tests` scope under the standard platform. I confirmed the sourcemap loaded by counting `[ERROR]` lines (0), not by trusting exit 0.

## Published harness API (later plans use this verbatim)

```lua
local Test = require("../harness/Test")      -- from tests/<area>/x.spec.luau
return function(t: Test.Runner)
    t.test(name, fn); t.todo(name)
    t.equal(actual, expected, msg?)            -- == only
    t.deepEqual(actual, expected, msg?)        -- recursive, depth cap 8 (errors when exceeded)
    t.truthy(v, msg?); t.falsy(v, msg?)
    t.contains(haystack, needle, msg?)         -- plain find
    t.throws(fn, needleSubstring?)
    t.fuzz(name, { seed?, iterations?, gen = function(rng, i) ... end, check = function(value) ... end })
end
-- Test.new(options?: { seed: number?, fuzzDriver: Test.FuzzDriver? }) : Test.Runner
-- tests/run.luau calls: Test.new({ seed = seed, fuzzDriver = Fuzz.driver })
```

- **`Test.luau` owns `FuzzOpts` and `FuzzDriver`** and has zero `require`s. `Fuzz.luau` imports them from `Test.luau`, never the reverse.
- `FakeScheduler.new({ cancelIsNoop = true })` returns `{ nowDeci, delay, advance, pending }`. `FakeClock.new()` returns `{ now, advance }`.
- Specs are plain `.spec.luau` files returning `function(t)`. Spec-relative requires reach the engine as `"../../src/server/engine/X"` and the harness as `"../harness/Test"`.
- Run forms: `lune run tests/run.luau`, `lune run tests/run.luau -- --filter <sub>`, `... -- --root <dir>`, `... -- --seed <n>`. The `--` is optional.

## Deviations from Plan

### Divergences found by executing (not predicted by plan or research)

**1. [Divergence] Lune 0.11.1 rejects the file extension in a computed require string**
- The plan prescribed `"./engine/rng.spec.luau"`. Actual: `error requiring module "./harness/modules.spec.luau": could not resolve child component "modules.spec.luau"`.
- Fix: strip `.luau` -> `./harness/modules.spec`. Dynamic require of discovered paths then works. **The manifest fallback was NOT needed**; `luau.load` was not used.

**2. [Divergence] luau-lsp rejects a non-literal require**
- `tests/run.luau(95,10): TypeError: Unknown require: unsupported path`. With `typeErrors: true` this hard-fails the type gate.
- Fix: `local dynamicRequire: (string) -> any = (require :: any)`, one narrowly scoped cast with a comment. No rule or config was loosened. Chained casts (`require :: any :: T`) are a syntax error in Luau.

**3. [Divergence, and a live demonstration of the plan's core risk] Lune 0.11.1 does not consume the `--` separator**
- `lune run x -- --filter y` delivers `process.args = { "--", "--filter", "y" }` (verified with a scratch script; `lune run x --filter y` delivers `{ "--filter", "y" }`).
- The first runner rejected `--` as an unknown argument. The first meta-test run then showed **5 failures, but also 2 spurious passes**: "no specs discovered" and "unknown argument" passed because every invocation exited 1 for the wrong reason. A bare exit-code assertion cannot tell reasons apart.
- Fix: the runner skips a literal `--`; every failure-expecting meta case now also asserts the reason string (`no spec files discovered`, `no cases registered`, `matched no cases`, `unknown argument: --nonsense`). Both invocation forms are covered by a meta case. All documented `-- --filter` commands in plans and VALIDATION.md keep working unchanged.

**4. [Divergence] `pcall` of a `() -> ()` function types as one return value**
- `TypeError: Function only returns 1 value, but 2 are required here`. Fixed with `pcall(fn :: () -> any)` casts in `Test.luau`, `run.luau`, `Fuzz.luau`, `modules.spec.luau`.

**5. [Divergence] `process.SpawnResult` does not exist; the type is `process.ExecResult`** in the Lune 0.11.1 typedefs.

### Additions beyond the plan (Rule 2, tightening only)

- **`--filter` matching zero cases fails the run** (`FAIL filter ... matched no cases`). Without it a mistyped `--filter` in any quick-run command is a silent green. Meta-tested.
- **Unknown runner arguments exit 1** rather than being ignored. Meta-tested.
- **`tests/harness/modules.spec.luau` (11 cases)** exercises `Test`, `FakeClock` and `FakeScheduler`, which the plan's `<behavior>` lists but its file list omitted. Task 1 was marked `tdd` but no runner exists until task 2, so a true RED for task 1 was impossible; these specs were committed with task 1 and first executed in task 2 (all green on first run). Task 3 followed the real RED/GREEN sequence.
- **Fixture-exclusion meta case**: sweeps `tests/meta` with a filter that only the fixture would match; passes only if fixtures were skipped.
- **Extra Rng cases**: independent-reference vector, zero-seed vector, fuzz seed-override-and-replay.
- `Fuzz.driver` also reports generator failures (with iteration and seed), not just check failures.

### Design choice to be aware of

- `FakeScheduler.advance(s)` steps `nowDeci` to each due entry's time while firing it and ends at the target. A callback therefore observes the time it was due, and work it schedules is relative to that. The plan said only "fires every due entry in due-time order, exactly once"; ties break by registration order.
- `deepEqual` throws on exceeding depth 8 rather than returning equal/unequal, so a deep structure can never silently compare as equal.

**Total deviations:** 5 divergences, 5 tightening additions. No rule weakened, no check loosened, no `todo` used to get green, no architectural change.

## Known Stubs

None. (`Main.server.luau` / `Main.client.luau` stubs from wave 1 are unchanged.)

## Threat Flags

None new. Threat register status: T-1-12 mitigated and mutation-verified; T-1-16 mitigated (runner skips `fixtures`; `.styluaignore`/`selene.toml` exclude from wave 1; `--ignore "**/fixtures/**"` on analyze); T-1-17 mitigated (failures print iteration and seed; uninstalled driver fails loudly, mutation-verified); T-1-18 mitigated (no multiply, reference-vector spec, grep checks clean).

## Notes for later plans

- `lune run` nested inside the suite (the meta-test) requires `lune` on `PATH` for the child; CI must have Rokit's shims on `PATH` for the test step.
- Lune writes a raw `error requiring module ... [Stack Begin]` trace to stderr when a spec require fails, in addition to the runner's `FAIL <load>` line.
- Fixtures live under `tests/**/fixtures/**` and are only reachable via `--root`. Later guard/purity/trap fixtures follow the same rule.

## Self-Check: PASSED

- All 15 created files exist (verified via `git status` clean after commits and the suite running them).
- Commits `895abc5`, `0aba77e`, `e44cb7d`, `8ec3ae0` present in `git log`.
- `tests/harness/Fuzz.luau` was absent after task 1 and present after task 3; `Test.luau` contains no `require(`.
- Every `.luau` under `src/` and `tests/` begins `--!strict`.
- All seven wave-1 gates plus the `tests` standard-platform analyze re-run after the final commit: all exit 0.
