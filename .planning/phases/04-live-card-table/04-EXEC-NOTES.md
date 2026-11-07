# Phase 4 — execution carry-forwards

> Facts discovered by executors mid-phase that later waves need and would otherwise rediscover.
> Orchestrator-maintained. **Append, never rewrite.**

## Tooling

- **`tests/run.luau` does NOT catch what CI catches. Run `scripts/verify.luau`.**
  Plan 04-06 wrote a spec that `tests/run.luau` ran green while `verify.luau`'s standard-platform
  typecheck rejected it, on command-union field access. An executor that runs only the suite can
  hand back a type-broken spec that passes locally and fails CI. Every executor brief from wave 3
  onward says to run `verify.luau`.
  *Mitigation used in 04-06:* type command lists as `{ any }` in specs where the union field access
  trips the stricter checker.
- **`analyze.luau --ignore '**/fixtures/**'` is refused by the sandbox.** Run analyze without
  `--ignore`; it passes, and `verify.luau` passes too.
- **Some worktrees refuse heredocs and shell loops** (plan 04-02 hit this). Use the Write/Edit tools
  instead; content is unaffected.
- **`lune` is at `~/.rokit/bin/lune`, never on `PATH`.** `--root`, never `--filter`.

## Measurement

- **Compare case counts and deltas, never raw wall clock.** The same unchanged tree has measured
  **20.15 s, 26.88 s, 27.08 s and 31.54 s** on this container. Wave 1's apparent 4.5 s "breach"
  was 1.10 s of real cost once measured against a worktree at the pre-wave commit under the same
  load. Method and running total live in `04-BUDGET-LOG.md`.

## Cross-plan handoffs

- **Plan 04-12 must CALL `CardRouting.publish(publisher, events, copyOf, userIdOfSeat)`**, not
  re-derive the routing. Plan 04-05 added it as a deviation because the planned API left the
  "Notice to wrong player" and "Table gains a rank" mutants with no shipped code to attach to — they
  could only ever have been spec-local. It sends the public batch once via `toSeated("Table")` and
  each notice via `toPlayer(userIdOfSeat(seat), "Notice")`.
- **Plan 04-13 must build `NetServer`'s publisher via `CardRouting.makePublisher` AND add the
  source assertion that it does.** 04-05 could not verify this from its own worktree because
  `NetServer` is not loaded there. Without that assertion the R4 guard reverts to being tested
  against a rebuilt copy, which is exactly the defect the plan-checker caught (deleting
  `assertPublic` from production left the suite green).
- **Rejection codes, measured by 04-03** — for D-12's silent-rejection assertions: `UnknownKey`,
  `MissingKey`, `NotFinite`, `WrongType`, `NotInteger`, `OutOfRange`, `NotTable`, `ForbiddenType`.
  `exactKeys` reports `MissingKey` before `UnknownKey`.
- **Rate limits shipped by 04-03:** `Draw` and `Pass` each get burst 8 / refill 6 per second. These
  are starting values for Phase 8, not measured; V-34 stays LOW confidence.

## Gates with a known, recorded limit

- **"Table gains a rank for a non-retired card" has no production-source mutant.** `split` never
  reads `rankOf`, so no one-line production edit produces it; a spec-level decorating publisher
  covers it. Recorded by 04-05 rather than papered over.
- **The descending-copy mutant shows which half of that gate works.** The permutation assertion
  stays *green* on it (descending is still a valid permutation); only the
  compare-against-production assertion catches it. That assertion is load-bearing.

## Bookkeeping the orchestrator owns

**Do not run `requirements.mark-complete` from an executor.** Plans 04-01 and 04-02 each ran it
independently and each reverted it: it would have marked UX-01, UX-02, UX-03 and CARD-13/16/17
**complete** off plans that deliver only test fakes, guard fixtures and manual-check rows. That is
the exact false claim M-11..M-17 exist to prevent. `state.advance-plan` also errors on this
STATE.md's format, and the roadmap updater rewrites `stopped_at` to stale text. Two independent
refusals is a finding about the tooling, not a coincidence.

**Requirements stay unticked until the device matrix is signed.** Four of the five ROADMAP success
criteria for this phase are device-dependent and this container has no Studio and no phone.
