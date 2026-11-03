---
phase: 02-card-engine-and-pacing-simulator
plan: 03
subsystem: infra
tags: [structural-guards, purity, mutation-proof, no-yield, server-clock, verification-debt]

requires:
  - phase: 01-03
    provides: "scripts/ci/check-guards.luau R3 machinery (BANNED_CONSTRUCTS findWord loop + needle loop), zones.luau scan scopes, tests/guards/guards.spec.luau CASES harness"
  - phase: 01-02
    provides: "tests/run.luau harness, Test.Runner API, assert-the-reason rule"
  - phase: 01-04
    provides: "tests/purity/purity.spec.luau and the tests/purity/fixtures/ convention"
provides:
  - "R3 bans `coroutine` (whole word) in pure zones, guarded roots and their require closure — CLAUDE.md rule 6 is now enforced by code"
  - "R3 bans the `os.` namespace in the same scope — CLAUDE.md rule 5 is now enforced by code"
  - "tests/purity/fixtures/engine-yield: mutation fixture proving the coroutine ban can fail"
  - "tests/purity/fixtures/engine-clock: mutation fixture proving the os. ban can fail"
  - "A standalone spec case asserting the ban is SCOPED, not repo-wide (tests/run.luau's os.clock stays legal)"
affects: [02-01, 02-02, 04, 06]

tech-stack:
  added: []
  patterns:
    - "A ban on a STANDARD Luau construct belongs in check-guards R3, not in selene.pure.toml: std = \"luau\" permits it by definition, so the allow-list lint structurally cannot catch it"
    - "`coroutine` as a findWord entry (whole identifier) and `os.` as a plain needle (dotted namespace) — pick the matcher by whether the bare word appears legitimately in prose"
    - "The intended SCOPE of a rule is itself a test case, so a future widening fails by name rather than in dozens of confusing places"

key-files:
  created:
    - tests/purity/fixtures/engine-yield/src/server/engine/Yielder.luau
    - tests/purity/fixtures/engine-clock/src/server/engine/Clocked.luau
  modified:
    - scripts/ci/check-guards.luau
    - tests/guards/guards.spec.luau

key-decisions:
  - "`coroutine` goes in BANNED_CONSTRUCTS (findWord, whole-identifier) so coroutine.yield/.resume/.wrap/.create are one rule while `coroutines` or `myCoroutineHelper` are not false hits"
  - "`os.` goes in the needle loop, NOT BANNED_CONSTRUCTS: the bare word `os` appears legitimately in prose and identifiers, the dotted namespace access does not"
  - "Because sf.text keeps string literals, a pure-zone file may not contain the substring `os.` even inside a string. Intentional over-strictness in a zone whose point is having no clock"
  - "No suppression mechanism was added for the new bans. A rule a developer can switch off in the file it governs is not a rule, and R3b already rejects in-file suppressions"
  - "R3's scope is UNCHANGED and now asserted. Scope was not widened: a repo-wide R3 self-trips on tests/run.luau's computed require and os.clock timer"
  - "Exactly two constructs added and nothing else: task., spawn(, delay( and :Wait() are Roblox API surface already caught by selene.pure.toml's undefined_variable = deny and luau-lsp --platform standard. coroutine and os are the only gaps because they are standard Luau"

patterns-established:
  - "Mutation-prove a new ban before trusting it: revert the guard edit, confirm the fixture reads green and the new spec rows go red, restore"

requirements-completed: []
requirements-contributed: [FOUND-06]

duration: ~1 session
completed: 2026-11-03
---

# Phase 2 Plan 03: Enforce the No-Yield and Server-Clock Rules Summary

**`check-guards` R3 now bans `coroutine` (whole word) and the `os.` namespace inside pure zones, guarded roots and their require closure, turning CLAUDE.md rules 5 ("the server is the only clock") and 6 ("no yields inside state mutations") from sentences into gates — mutation-proven by two fixtures that make the real CLI exit 1, with zero churn on the real repository.**

## Performance

- **Tasks:** 2 of 2
- **Files created:** 2; **modified:** 2
- **Full suite after this plan:** `336 passed, 0 failed, 3 todo in 15.12s` (baseline at `791910b` was `333 passed, 0 failed, 3 todo`; +3 = two fixture rows plus the scope case)
- **`scripts/verify.luau`:** `verify: all 14 automated steps passed in 16.9s` — unchanged from baseline
- **Guard spec alone:** `19 passed, 0 failed, 0 todo in 0.86s` (was 16)

## Task Commits

1. **Task 1: extend R3 with the coroutine and os. bans** — `661988a` (feat)
2. **Task 2: mutation fixtures that prove both new bans can fail** — `f970f68` (test)

## Why this was needed (the gap, re-measured this session)

`selene.pure.toml` sets `std = "luau"`. `coroutine.*` and `os.*` are **standard Luau**, so the
allow-list lint permits them by definition — it is not a tuning oversight, it is structural. Running
the repository's own pure config against the two new fixtures reconfirms the research measurement:

```
$ selene --config selene.pure.toml tests/purity/fixtures/engine-yield/src/server/engine \
                                   tests/purity/fixtures/engine-clock/src/server/engine
Results:
0 errors
0 warnings
0 parse errors
```

Before this plan, an engine module could yield mid-mutation and read a wall clock while **all 14
gates stayed green**. The ban therefore had to live in `check-guards` R3, which is an explicit
deny-list, rather than in the lint.

## The exact edits

New `BANNED_CONSTRUCTS` line (`scripts/ci/check-guards.luau`):

```luau
local BANNED_CONSTRUCTS = { "getfenv", "setfenv", "loadstring", "coroutine" }
```

New needle list inside `checkR3`:

```luau
for _, needle in { "rawget(_G", "rawget( _G", "_G[", "os." } do
```

Both are commented in place with the reason (standard-Luau blind spot, rules 5 and 6) so a future
reader does not mistake them for rule-2 (Roblox API) entries. The R3 line of the file's rule header
was updated to name the two new constructs. `SUPPRESSIONS` was not touched, no suppression
mechanism was added, and `scripts/ci/zones.luau` was not modified at all
(`git diff --stat scripts/ci/zones.luau` empty; `grep -c pureZones` unchanged at 2).

## Mutation proof — observed failing output, verbatim

Both fixtures driven through the real CLI:

```
=== engine-yield ===
R3 src/server/engine/Yielder.luau:10 banned construct: coroutine
R3 src/server/engine/Yielder.luau:15 banned construct: coroutine
check-guards: 2 violation(s)
exit=1
=== engine-clock ===
R3 src/server/engine/Clocked.luau:7 banned construct: os.
R3 src/server/engine/Clocked.luau:11 banned construct: os.
check-guards: 2 violation(s)
exit=1
```

| Fixture | Rule violated | Exact rule set fired | Exit |
|---|---|---|---|
| `tests/purity/fixtures/engine-yield` | CLAUDE.md rule 6 (`coroutine.yield` mid-mutation, `coroutine.resume`) | `{R3}` | 1 |
| `tests/purity/fixtures/engine-clock` | CLAUDE.md rule 5 (`os.clock`, `os.time`) | `{R3}` | 1 |

The exact-rule-set assertion (`t.deepEqual(ruleIds(output), case.rules)`) is what stops either
fixture from passing by tripping some unrelated rule — both are `--!strict` on line 1 with no
requires, so R1, R2, R3b, R4, R5 and R6 are all silent.

## Falsifiability check (the guard edit reverted, then restored)

With `scripts/ci/check-guards.luau` temporarily reverted to its pre-edit content, both fixtures read
**green** and the two new spec rows go **red**:

```
=== WITHOUT THE BAN: engine-yield ===
check-guards: ok (1 files, 0 requires, 1 guarded roots)
exit=0
=== WITHOUT THE BAN: engine-clock ===
check-guards: ok (1 files, 0 requires, 1 guarded roots)
exit=0
=== WITHOUT THE BAN: guards suite ===
FAIL tests/guards/guards.spec.luau::guard fixture tests/purity/fixtures/engine-yield
FAIL tests/guards/guards.spec.luau::guard fixture tests/purity/fixtures/engine-clock
17 passed, 2 failed, 0 todo in 0.90s
```

Restored byte for byte (`git diff --stat` showed only `tests/guards/guards.spec.luau`). This is the
house standard satisfied: **both new gates have been watched failing**, and both have been watched
failing to fail when the thing that enforces them is removed.

## Zero churn, and the scope is now itself a test

```
$ lune run scripts/ci/check-guards.luau
check-guards: ok (59 files, 122 requires, 12 guarded roots)        exit 0
$ lune run scripts/ci/check-guards.luau --print-zones
src/server/engine src/server/core src/shared/Net                   exit 0
```

Identical to the pre-edit baseline: `src/server/engine`, `src/server/core` and `src/shared/Net`
contain no `coroutine` and no `os.` today, which is exactly why this plan was scheduled in wave 1 —
the ban is free now and expensive after the engine exists. The engine is born under the rule.

The ban is **scoped, not repo-wide**. `tests/run.luau` legitimately calls `os.clock()` for the suite
timer (lines 79 and 153), and a repo-wide R3 would also self-trip on its computed require and on
`check-guards.luau`'s own `getfenv` strings. A new standalone case makes that intent falsifiable:

```
ok   tests/guards/guards.spec.luau::R3's coroutine/os ban is scoped to pure zones, not repo-wide
```

It asserts a green repo-wide run reports neither `tests/run.luau` nor either new message. Without
it, a future widening of R3's scope would surface as dozens of unrelated-looking failures instead of
one named test.

## Verification debt: the engine's half of V-15 is retired

V-15 asked whether non-yielding handlers are atomic and whether two handlers can interleave inside
one state mutation — a question whose answer depends on Roblox platform behaviour that research
could not verify against primary docs (all five Roblox doc hosts were DNS-blocked).

**The engine's half of V-15 is now retired permanently, and not by verifying the platform claim but
by making it irrelevant: an engine that cannot yield cannot be corrupted by handler interleaving,
regardless of what the platform does.** R3 statically forbids `coroutine` anywhere in
`src/server/engine`, `src/server/core`, `src/shared/Net` or any module their require closure reaches,
so there is no construct available with which to yield mid-mutation. The remaining half of V-15 —
the behaviour of real `OnServerEvent` handlers that *drive* the engine, and replication scope —
becomes load-bearing in Phase 4 and is still open there.

Rule 5's enforcement is the same shape: the pure zones cannot read a clock at all, so the only time
value the engine can see is one passed in from outside, in the integer deciseconds the design
mandates.

## Threat register dispositions discharged

| Threat ID | Disposition | Evidence |
|---|---|---|
| T-2-11 | mitigated | `os.` banned in pure zones and closure; `engine-clock` makes the real CLI exit 1 with `banned construct: os.` |
| T-2-12 | mitigated | `coroutine` banned as a whole word; `engine-yield` makes the real CLI exit 1; V-15's engine half retired |
| T-2-13 | mitigated | `guards.spec.luau` asserts the EXACT rule set per fixture; R3b still rejects in-file suppressions and no suppression path was added for the new bans |
| T-2-14 | mitigated | the "not repo-wide" case asserts `tests/run.luau`'s legitimate `os.clock` is never reported |
| T-2-15 | accepted | a CI lint script has no identity, data or privilege surface |

## Gates after the final commit

```
stylua --check src scripts tests                                              EXIT=0
selene src scripts tests                        0 errors / 0 warnings / 0 parse errors
selene --config selene.pure.toml src/server/engine src/server/core src/shared/Net
                                                0 errors / 0 warnings / 0 parse errors
lune run scripts/ci/check-guards.luau           check-guards: ok (59 files, 122 requires, 12 guarded roots)
lune run tests/run.luau                         336 passed, 0 failed, 3 todo in 15.12s
lune run scripts/verify.luau                    verify: all 14 automated steps passed in 16.9s
```

No CI step was added: the new fixtures run inside `tests/run.luau`, which `ci.yml` already invokes,
so there is no `run:`-string drift (`tests/ci/verify.spec.luau` asserts those strings byte-identical
and stayed green).

## Notes for later plans

- Plans **02-01** and **02-02** write the card engine into `src/server/engine`. `coroutine` and any
  `os.` access — including inside a string literal — are now hard failures there. Time values must
  be parameters, in integer deciseconds.
- The fixtures live under `tests/purity/fixtures/` (not `tests/guards/fixtures/`) because
  `02-VALIDATION.md`'s Wave 0 list names those paths and because they document the *purity* claim,
  even though the rule enforcing them is R3. `zones.ignoreSegments` contains `"fixtures"`, so they
  are invisible to a real-repository scan, and `--ignore "**/fixtures/**"` keeps them out of the
  typecheck step.
- Adding a further construct to R3 is a one-line change plus a fixture. Pick `findWord` for
  whole identifiers, the needle loop for dotted namespaces.

## Deviations from Plan

None — plan executed exactly as written. Both tasks' acceptance criteria passed on the first run and
no deviation rule was invoked.

## Self-Check: PASSED

- `scripts/ci/check-guards.luau` — FOUND, contains `coroutine` and `"os."`
- `tests/purity/fixtures/engine-yield/src/server/engine/Yielder.luau` — FOUND, contains `coroutine.yield`
- `tests/purity/fixtures/engine-clock/src/server/engine/Clocked.luau` — FOUND, contains `os.clock`
- `tests/guards/guards.spec.luau` — FOUND, contains `banned construct: coroutine`, `engine-yield`, `engine-clock`, `not repo-wide`
- Commits `661988a` and `f970f68` — FOUND in `git log`
