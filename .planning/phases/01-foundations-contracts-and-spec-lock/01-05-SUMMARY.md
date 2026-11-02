---
phase: 01-foundations-contracts-and-spec-lock
plan: 05
subsystem: net
tags: [validation, nan, rate-limit, token-bucket, manifest, d-20, tdd, strict-typing]

requires:
  - phase: 01-01
    provides: pinned toolchain, selene.pure.toml, .luaurc, Rojo project with ReplicatedStorage.Shared mount
  - phase: 01-02
    provides: lune run tests/run.luau harness, Test API, FakeClock
provides:
  - "Validate: hand-written portable isFinite plus number/integer/string/literal/exactKeys validators"
  - "Manifest: intent registry (Ping only), runtime PHASES constant (D-20), isKnown"
  - "Bucket: pure injected-clock token bucket (drops, never queues)"
  - "RateLimits: all burst/refill numbers in one table (LOW confidence)"
affects: [01-09, 01-10, 01-12, phase-04, phase-05, phase-06]

tech-stack:
  added: []
  patterns:
    - "Validators return (ok, result): clean value on success, a Code string on rejection, never throw"
    - "Fixed check order: forbidden type, expected type, finite, integer, range"
    - "Every rejection spec asserts the exact code; every spec was mutation-checked"
    - "Runtime constants for cross-phase vocabularies (PHASES), enforced by a subset spec with a negative control"

key-files:
  created:
    - src/shared/Net/Validate.luau
    - src/shared/Net/Manifest.luau
    - src/shared/Config/RateLimits.luau
    - src/server/core/Bucket.luau
    - tests/net/validate.spec.luau
    - tests/net/manifest.spec.luau
    - tests/core/bucket.spec.luau
  modified: []

key-decisions:
  - "D-20 is a runtime constant: Manifest.PHASES = Lobby, Hide, Round, Podium, frozen, with a spec-enforced subset rule"
  - "Ping carries a required finite integer nonce so manual check M-03's NaN payload reaches isFinite"
  - "integer is capped at +/-2^53 (NotInteger beyond), because 1e308 % 1 == 0"
  - "Bucket refuses a non-finite, negative or backwards clock without touching state"

patterns-established:
  - "A test that expects rejection must assert why; a test for a clock/ordering rule must make the rule the ONLY possible cause of the rejection"

requirements-completed: []
requirements-contributed: [FOUND-04]

duration: ~1 session
completed: 2026-11-02
---

# Phase 1 Plan 05: Validate, Manifest, RateLimits and Bucket Summary

**A hand-written `isFinite` (`type(v)=="number" and v == v and v ~= +-inf`) gates every numeric validator ahead of any range comparison, the `Ping` intent carries a required finite integer `nonce` so the live NaN check is real, the D-20 phase names exist as a frozen runtime `PHASES` constant with a subset-enforcing spec, and a pure injected-clock token bucket drops rather than queues. 60 new cases, all mutation-checked; full suite 97 passed.**

## Performance

- **Tasks:** 3 of 3 (TDD, one RED and one GREEN commit each, no REFACTOR needed)
- **Files created:** 7 (no files modified)
- **New cases:** validate 26, manifest 15, bucket 19
- **Full suite:** `97 passed, 0 failed, 0 todo in 0.39s`

## Task Commits

| Feature | RED | GREEN |
|---------|-----|-------|
| Validate | `a74e08d` test | `94f4c50` feat |
| Manifest | `61c76e7` test | `65e0e1e` feat |
| Bucket + RateLimits | `f5ea421` test | `d660aa2` feat |

No `refactor(...)` commits: nothing needed tidying after GREEN (`stylua` and the type fixes were folded into the GREEN commits).

## Exported signatures (plan 01-09 composes these; do not guess)

### `src/shared/Net/Validate.luau`

```lua
export type Code = string
export type Validator = (value: unknown) -> (boolean, unknown)
export type NumberOpts = { min: number?, max: number? }
export type StringOpts = { maxLen: number, minLen: number? }
export type KeysOpts = { maxDepth: number?, maxEntries: number? }

return {
	isFinite  = (v: unknown) -> boolean,
	number    = (opts: NumberOpts) -> Validator,
	integer   = (opts: NumberOpts) -> Validator,
	string    = (opts: StringOpts) -> Validator,          -- implemented as local `string_` so the global `string` library is not shadowed
	exactKeys = (schema: { [string]: Validator }, opts: KeysOpts?) -> Validator,
	literal   = (expected: string | number | boolean) -> Validator,
}
```

`number`/`integer` take a table (pass `{}` for no range). `maxDepth` defaults to 4, `maxEntries` to 32. Constructors **do** raise on a non-finite `min`/`max`/`maxLen`/`minLen`/numeric literal (a programmer error at definition time); validators themselves never throw.

**Rejection codes** (the full vocabulary): `ForbiddenType`, `WrongType`, `NotFinite`, `NotInteger`, `OutOfRange`, `TooLong`, `TooShort`, `NotLiteral`, `NotTable`, `TooDeep`, `TooLarge`, `MissingKey`, `UnknownKey`. A field failure inside `exactKeys` surfaces the field's own code.

**Order of checks.** Every validator: forbidden type, expected type, finite, integer (magnitude cap 2^53 then `% 1`), range. `exactKeys`: forbidden type, `NotTable`, bounded whole-value walk (`TooDeep` / `TooLarge` / `ForbiddenType`, which also covers keys and nested values), `MissingKey` (schema keys in sorted order), `UnknownKey`, then each field validator. A message that is both missing a key and carrying an unknown one reports `MissingKey`. `exactKeys` returns a **fresh clean table** with no metatable and uses `next`/`rawget` throughout, so a hostile metatable runs no code.

### `src/shared/Net/Manifest.luau`

```lua
export type RoundPhase = "Lobby" | "Hide" | "Round" | "Podium"
export type Intent = { phases: { RoundPhase }, validate: Validate.Validator }

return {
	intents = { [string]: Intent },          -- exactly one key in Phase 1: Ping
	isKnown = (name: unknown) -> boolean,
	MAX_NAME_LENGTH = 64,
	PHASES = { RoundPhase },                 -- table.freeze'd runtime constant
}
```

`isKnown` returns false unless `type(name) == "string"`, `#name > 0`, `#name <= 64`, and `intents[name] ~= nil` (plain index; the spec proves zero lookups happen for garbage names).

### `src/server/core/Bucket.luau`

```lua
export type Spec = { burst: number, refillPerSecond: number }
export type Store = {
	take: (self: Store, userId: number, intent: string, spec: Spec) -> boolean,
	forget: (self: Store, userId: number) -> (),
	rejections: (self: Store) -> number,
	count: (self: Store) -> number,
}
export type Deps = { clock: { now: () -> number } }

return { new = (deps: Deps) -> Store }
```

Call as `store:take(userId, intent, spec)`. The clock is **seconds**, injected, must be finite and non-negative. The module's only export is `new`; `take`/`forget` are methods on the returned store.

### `src/shared/Config/RateLimits.luau`

```lua
export type Spec = { burst: number, refillPerSecond: number }
RateLimits.default   : Spec                          -- { burst = 4, refillPerSecond = 4 }
RateLimits.byIntent  : { [string]: Spec }            -- { Ping = { burst = 2, refillPerSecond = 1 } }
RateLimits.forIntent(name: string) -> Spec           -- byIntent[name] or default
```

**LOW CONFIDENCE.** These numbers are starting points to be tuned in playtest (research V-34), not derived values. They are config, never inlined in logic.

## Spec-lock decision: the round phase vocabulary (D-20)

The phase names are `Lobby | Hide | Round | Podium`, exported at runtime as `Manifest.PHASES` (frozen) and as the `RoundPhase` type. **`Round` is the single concurrent card-and-hunt phase**: PROJECT.md puts one 5:00 cap on "the card/hunt phase" and D-15 lets a finisher leave the table mid-pass, so the scramble and the hunt overlap rather than follow each other. Phases 4 and 5 must not invent two names for it.

A type alone cannot enforce this, because types are erased and `phases` is a plain string array at runtime. Enforcement mechanism, all in `tests/net/manifest.spec.luau`:

1. `#PHASES == 4` and `deepEqual` against the four values in order.
2. `table.isfrozen(PHASES)` and an `insert` attempt throws, so no module can append a competing name.
3. For every entry in `Manifest.intents`, `phaseProblems(intent.phases)` must be empty (non-empty list, every name in `PHASES`). It also asserts at least one intent was checked, so the loop cannot pass over nothing.
4. **Negative control:** the same `phaseProblems` function is driven with `{"Scramble"}` (the originally proposed name), `{"Round","Play"}`, `{"Hunt"}`, `{"round"}` (case), a mixed list, and `{}`, each asserted to yield the exact problem strings; a clean list yields none. Mutation: replacing Ping's phases with `{"Lobby","Scramble"}` fails 2 cases.

A later phase adding an intent with a stale name fails this spec on its first run. Rejected names appear nowhere in shipped code (non-comment grep clean).

## The `Ping` payload and why it has a `nonce`

Schema: `exactKeys({ nonce = integer({ min = 0, max = 2^31 }) })`, allowed in all four phases. Verdicts, all asserted by code in the spec:

| Payload | Result |
|---------|--------|
| `{ nonce = 0 }` | accepted, returns `{ nonce = 0 }` |
| `{}` | `MissingKey` |
| `{ nonce = 0/0 }` | `NotFinite` |
| `{ nonce = math.huge }` / `-math.huge` | `NotFinite` |
| `{ nonce = 0, x = 1 }` | `UnknownKey` |
| `{ nonce = 1.5 }` | `NotInteger` |
| `{ nonce = -1 }` / `{ nonce = 2^31 + 1 }` | `OutOfRange` |
| `{ nonce = "7" }` | `WrongType` |
| `{ nonce = function() end }` | `ForbiddenType` |
| `nil` / `7` | `NotTable` |

**Why a nonce.** FOUND-04 and phase success criterion 4 both name NaN, and the only live (Studio) proof of NaN rejection is manual check **M-03**. With an empty schema a NaN field would bounce as `UnknownKey` and never reach `isFinite`, so M-03 would prove the envelope and nothing about NaN. One required finite integer makes the live NaN payload genuinely exercise the finite check. It is required, not optional, so `{}` is `MissingKey` and no optionality support is needed. Mutation: swapping Ping's schema for `exactKeys({})` fails 4 cases including the NaN one.

## Verbatim output

### RED evidence (each module genuinely absent when its spec first ran)

```
$ lune run tests/run.luau -- --filter validate
error requiring module "../../src/shared/Net/Validate": could not resolve child component "Net"
FAIL tests/net/validate.spec.luau::<load>
0 passed, 1 failed, 0 todo in 0.03s                       exit 1

$ lune run tests/run.luau -- --filter manifest
error requiring module "../../src/shared/Net/Manifest": could not resolve child component "Manifest"      exit 1

$ lune run tests/run.luau -- --filter bucket
error requiring module "../../src/server/core/Bucket": could not resolve child component "core"
FAIL tests/core/bucket.spec.luau::<load>
0 passed, 1 failed, 0 todo in 0.04s                       exit 1
```

Honest note: these are load failures (the module did not exist), not assertion failures, the same RED shape as wave 2's Rng. A behavioural RED is impossible for a brand new module. The mutation checks below are the stronger evidence that the specs can fail for the right reasons.

### GREEN

```
$ lune run tests/run.luau -- --filter validate    26 passed, 0 failed, 0 todo in 0.03s
$ lune run tests/run.luau -- --filter manifest    15 passed, 0 failed, 0 todo in 0.03s
$ lune run tests/run.luau -- --filter bucket      19 passed, 0 failed, 0 todo in 0.06s
$ lune run tests/run.luau                         97 passed, 0 failed, 0 todo in 0.39s
```

### Mutation checks (mutate a copy, run, restore with `cmp`; every restore verified)

| Mutation | Result |
|----------|--------|
| Validate: drop the `v == v` NaN clause | **7 FAIL** (isFinite NaN, number NaN, integer NaN, literal, field failure, vector table, fuzz) |
| Validate: first success path rejects | 1 FAIL (number range) |
| Validate: drop the 2^53 cap on `integer` | 2 FAIL (1e308 case, vector table) |
| Manifest: do the lookup before the type/length check | 1 FAIL (`isKnown rejects ... BEFORE any lookup`) |
| Manifest: Ping phases contain an invented name | 2 FAIL (subset rule, Ping all phases) |
| Manifest: Ping schema replaced with `exactKeys({})` | 4 FAIL (accept, MissingKey, NaN, distinct codes) |
| Bucket: remove the `math.min` cap | 1 FAIL (cap holds) |
| Bucket: skip the finite/negative clock check | 1 FAIL (non-finite clock) |
| Bucket: `forget` is a no-op | 1 FAIL (forget frees buckets) |
| Bucket: accept a backwards clock | **initially 0 FAIL, a survivor**; see Divergence 3. After strengthening: 1 FAIL |
| Bucket: reject a backwards clock but overwrite `last` | 1 FAIL |

### Gates (final tree)

```
stylua --check src tests                                                    exit 0
selene --config selene.pure.toml src/shared/Net src/server/core             0 errors / 0 warnings / 0 parse errors
selene src tests                                                            0 errors / 0 warnings / 0 parse errors
luau-lsp analyze --platform standard --base-luaurc .luaurc
    src/shared/Net src/server/core src/shared/Config tests/net tests/core   no output beyond [INFO]/[WARN], exit 0
rojo sourcemap ... -o build/01-05/sourcemap.json                            Created sourcemap, exit 0
luau-lsp analyze --platform roblox --sourcemap build/01-05/sourcemap.json
    --definitions=tools/types/globalTypes.None.d.luau src                   exit 0, 0 [ERROR] lines
```

Plan acceptance greps: `v == v` present, `math.isfinite` absent from `Validate.luau`; the non-comment purity greps over `Validate.luau`, `Manifest.luau` and `Bucket.luau` all match nothing; no competing phase literal and no `DrawCard|PassCard|PlaceSpoon|ClaimSpoon|BuySkin` in `Manifest.luau`; `math.min`, `forget`, `rejections` present in `Bucket.luau`; `FakeClock` present in the bucket spec; the Validate spec names the rejection codes 81 times (requirement was 9).

## Deviations from Plan

### Divergences found by executing

**1. [Divergence] `value % 1 == 0` accepts 1e308, so the plan's integer recipe is insufficient**
- Plan: "`integer` tests `value % 1 == 0` only after `isFinite` has passed", and "1e308 fails (NotFinite or NotInteger)". 1e308 is finite, and `1e308 % 1 == 0`, so that recipe **accepts** it.
- Fix: `integer` also rejects `abs(value) > 2^53` with `NotInteger` (beyond 2^53 doubles skip integers, so "whole" no longer means exact). Applied before the range check, so it holds with or without a range. 2^53 itself is accepted. Mutation-checked.

**2. [Divergence] `luau-lsp analyze` type errors do NOT contain the string `ERROR`; counting `[ERROR]` lines gives a false green**
- Wave 1's fourth trap says to fail on any `[ERROR]` line. That catches a missing sourcemap, but real type errors print as `file(line,col): TypeError: ...`. My first post-GREEN check for Manifest used `grep -c ERROR` and printed `0` while three `TypeError`s existed; they showed only when I grepped `Error`, and the exit code was 1.
- Fix/guidance: the exit code is the signal for type errors; the `[ERROR]` scan is a separate, additional check for sourcemap load failure. Plan 01-10/01-11 CI should assert **both**: exit 0 and no `[ERROR]` lines. Never use a count of one string as the only gate.

**3. [Divergence / test defect] The first backwards-clock case survived the mutation "accept a backwards clock"**
- The first spec drained the bucket and then moved the clock back. The mutant (negative elapsed time subtracts tokens, then `last` is overwritten) still produced exactly the same observable result, by arithmetic coincidence, so the test passed while the rule was unenforced. This is wave 2's "passes for the wrong reason" again.
- Fix: added `a backwards clock is refused even when tokens ARE available`, in which two tokens remain, so the clock rule is the only possible cause of the rejection, and which also proves the refused take burned nothing. The mutant now fails it; the original case is kept (it kills the "reject but overwrite last" mutant).

**4. [Divergence] Luau array invariance: `{ RoundPhase }` is not `{ string }`**
- `luau-lsp` rejected passing `intent.phases` to a `{ string }` parameter and the `:: { string }` cast. The subset helper in the spec takes `{ any }`, with a comment explaining why (a bad name is exactly the input it must accept in order to reject).
- Also `table.freeze({ ... })` returns a widened `{ string }`, losing the union; `Manifest.luau` freezes in a separate statement after the typed declaration.

**5. [Divergence] Bucket's module exports only `new`**
- The plan's artifact lists `exports: ["new", "take", "forget"]`, but its own `Store` type puts `take`/`forget` on the returned store as `self`-methods. I followed the type; calling `Bucket.take` as a module function does not exist.

**6. [Divergence] `scripts/ci/check-guards.luau` and `zones.luau` do not exist in this worktree**
- Plan 01-05's verification block runs `lune run scripts/ci/check-guards.luau`; that belongs to sibling plans 01-03/01-04 and was not present at the base commit. Pure-zone compliance was instead verified with `selene --config selene.pure.toml` (allow-list) plus the plan's non-comment purity greps. The authoritative whole-tree run remains plan 01-10.

### Additions beyond the plan (tightening only, Rule 2)

- `PHASES` is `table.freeze`d and the spec proves an insert throws.
- `exactKeys` walks keys as well as values for forbidden types, and reports `ForbiddenType` ahead of `UnknownKey`, so a function smuggled under an unknown key is named for what it is.
- Extra codes beyond the plan's list: `WrongType`, `TooShort`, `NotLiteral`.
- Bucket refuses a NaN `userId` (assigning a NaN table key raises) and a malformed `Spec` (non-finite or negative burst/refill), returning false instead of throwing.
- Bucket rejects a negative clock reading, not just a non-finite or backwards one, as the plan's behaviour list required; a bad reading never allocates state for a never-seen user (`count()` asserted).
- A fuzz case (`grants never exceed burst + refill * elapsed`) and a fuzz case (`number never accepts a non-finite value, whatever range`), both via the wave-2 driver.
- A "validators never throw" case feeding hostile metatables (`__index`, `__len`, `__iter`, `__eq` all raising), cycles, functions, threads and buffers to every validator.
- A lookup-counting proof that `isKnown` does type and length checks before the table lookup (installs a counting `__index` on `Manifest.intents` for one case and restores it in a `pcall` guard).

**Total deviations:** 6 divergences, 6 tightening additions. No check weakened, no `todo` used, no architectural change.

## Notes for plan 01-09 (the gateway that composes these)

- Call `Manifest.isKnown(name)` first, then check `intent.phases` contains the current phase, then `Bucket:take(userId, name, RateLimits.forIntent(name))`, then `intent.validate(payload)`. Take the bucket before validating so a flood of garbage is cheap.
- The clock handed to `Bucket.new` must return **seconds, finite and non-negative**. Any other reading is silently a drop (and is tallied in `rejections()`); a wall clock that can step backwards will therefore drop traffic rather than grant it.
- Call `store:forget(userId)` from the adapter's `PlayerRemoving`.
- `exactKeys` already returns the clean copy; hand **that** to the handler, not the raw payload.

## Known Stubs

None. `Ping` is the only intent by design (no Phase 4/5/7 placeholders).

## Threat Flags

None new. Register status: T-1-01 (high) mitigated and mutation-verified; T-1-02 mitigated; T-1-25 mitigated (both-direction key check, depth and entry caps); T-1-26 (high) mitigated (positive type allow-list, covers nested values and keys); T-1-27 mitigated and proven by lookup counting; T-1-50 mitigated (runtime `PHASES` plus subset spec with negative control); T-1-28 mitigated (backwards, negative and non-finite clock all refuse and leave state untouched).

## Self-Check: PASSED

- All 7 created files exist and are tracked; `git status --short` was empty after the last commit.
- Commits `a74e08d`, `94f4c50`, `61c76e7`, `65e0e1e`, `f5ea421`, `d660aa2` present in `git log`; each RED precedes its GREEN.
- Every `.luau` created begins `--!strict`.
- STATE.md, ROADMAP.md and REQUIREMENTS.md were not touched.
