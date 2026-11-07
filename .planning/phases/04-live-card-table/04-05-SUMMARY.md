---
phase: 04-live-card-table
plan: 05
subsystem: card-routing
tags: [privacy, CARD-13, CARD-19, publisher, copy-assignment]
requires: [04-01, 04-02]
provides: [CardRouting.makePublisher, CardRouting.split, CardRouting.publish, CardRouting.assignCopies]
key-files:
  created:
    - src/server/core/CardRouting.luau
    - tests/card/routing.spec.luau
decisions:
  - "CardRouting.publish added (not in plan) so the notice recipient is decided in shipped code and the noticeTarget mutant is reachable"
metrics:
  tests: "19 cases in tests/card, full suite 691 passed / 0 failed in 24.87 s"
  budget: "assignCopies case 0.005-0.009 s against a 0.25 s cap"
---

# Phase 4 Plan 05: CardRouting Summary

Frozen audience table, throwing `assertPublic`, pure `makePublisher` assembly, `split` that strips
`ValveForcedPass` to a private `ForcedPass` notice and drops `Completed.fifth`, and server-side
`assignCopies` (ascending id, 4-per-rank validated).

Commits: feat (CardRouting.luau), test (routing.spec.luau).

## Deviations from Plan

**1. [Rule 2 - gap] Added `CardRouting.publish(publisher, events, copyOf, userIdOfSeat)`.** The plan
lists a "Notice sent to the wrong player" mutant and a "Table payload gains a rank" mutant, but the
planned API had no shipped function that decides a notice's recipient or sends the Table batch, so
neither mutant could be an injected dependency on shipped code. `publish` is 12 lines: one
`toSeated("Table", batch)` and one `toPlayer(userIdOfSeat(seat), "Notice", ...)` per notice. Plan
04-12 (CardTable) should call it rather than re-deriving the routing.

**2. `audienceOf` needed `string?` annotation plus cast** to satisfy luau-lsp (frozen-table index widened
to string). No behaviour change.

## Mutation results (all run, all red, restored)

Spec-level (injected broken dependency, same gate helper as the clean control; clean/mutant counts printed):
- Publisher `leak` mode: `privateLeaks clean=0 mutant=2` (non-vacuity: 2 private calls routed).
- Leaky split (ValveForcedPass forwarded): `defects clean=0 mutant=1`; mutant forwarded 3 events.
- `noticeTarget = successor`: `recipient clean=102 mutant=103`; also asserted the broadcast-leak gate sees 0
  for this mutant, proving it needs its own row.
- Rank decoration of Table payload: `rankLeaks clean=0 mutant=2` of 3 inspected.
- Copy assignment: reused index rejected; descending visit differs on 40/41 ids.

Production-source mutants (edited CardRouting.luau, ran `--root tests/card`, restored with git checkout):
- Delete `assertPublic` from `toAll`: `FAIL makePublisher is the shipped assembly... toAll(Sync) throws exactly for private kinds (expected false, got true)`. 18 passed, 1 failed.
- Insert ValveForcedPass into public list: 3 FAIL (`Drew and Passed only (expected 2, got 3)`; `clean control (expected 0, got 1)`; `no valve marker in the public batch`). 16 passed, 3 failed.
- Add `fifth` to the Completed entry: `FAIL ... no fifth key on the public entry (expected a falsy value, got true)`.
- Descending copy visit: `FAIL MUTANT B: descending visit differs from the ascending assignment (expected a truthy value, got false)`. Note the permutation gate itself stays green (descending is a valid permutation); only the compare-to-production assertion catches it.
- Notice routed to `seat + 1`: `FAIL clean: notice goes to seat 2's player only (expected { [1] = 102 }, got { [1] = 103 })`.

## Verification

- `lune run tests/run.luau`: 691 passed, 0 failed, 0 todo in 24.87s
- `lune run scripts/ci/check-guards.luau`: ok (103 files, 300 requires, 25 guarded roots)
- stylua --check, selene, selene.pure.toml on src/server/core, analyze on src/server/core + tests/card: clean
- assignCopies case: 200 deals, 7000 ids, 0.005-0.009 s (cap 0.25 s; no seed reduction needed)

## Known gaps

- A Table-payload rank mutant on PRODUCTION source was not run: `split` never reads `rankOf`, so there is
  no one-line production edit that adds a non-retired rank without new plumbing. The spec-level
  decorating-publisher mutant covers it.
- NetServer (04-13) is not loaded; its assembly via `makePublisher` is only verifiable there.

## Self-Check: PASSED
