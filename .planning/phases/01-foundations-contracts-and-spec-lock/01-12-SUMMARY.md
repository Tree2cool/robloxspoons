---
phase: 01-foundations-contracts-and-spec-lock
plan: 12
subsystem: owner-gate-and-phase-close
tags: [manual-checks, creator-hub, foundation-07, foundation-08, environments, serveplaceids, ci]

requires:
  - phase: 01-08
    provides: PersistenceMode.decide, Environments.luau placeholders
  - phase: 01-11
    provides: MANUAL-CHECKS.md M-01..M-06, NEEDS_HUMAN.md, verify.luau manual-check reporting
provides:
  - "src/shared/Config/Environments.luau: real production and dev ids, no placeholder zeros"
  - "default.project.json: servePlaceIds restricting rojo serve to the dev place"
  - "tests/project/project.spec.luau: three assertions binding the two files together"
  - "MANUAL-CHECKS.md: all six boxes signed off, two with recorded deferred scope"
affects: []

key-files:
  created: []
  modified:
    - src/shared/Config/Environments.luau
    - default.project.json
    - tests/project/project.spec.luau
    - MANUAL-CHECKS.md
    - NEEDS_HUMAN.md
    - .planning/phases/01-foundations-contracts-and-spec-lock/01-CONTEXT.md

key-decisions:
  - "D-23: M-04 check 3 and M-05's 11th join are deferred with recorded scope, not ticked as verified"
  - "The ids are machine-checked, not eyeballed: project.spec.luau asserts servePlaceIds == DEV_PLACE_ID and that no id is zero"
  - "A failed check stays unticked until it is actually fixed and re-run - M-04 check 2 was recorded FAILED before it was recorded PASSED"

requirements-completed: [FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07, FOUND-08]
requirements-contributed: []

completed: 2026-11-03
---

# Phase 1 Plan 12: Owner gate and phase close Summary

**The Creator Hub gate ran and found a real defect: production Studio API access was ON, so a Studio
session could write live player data. It is now off and verified off. All six manual checks are
signed, two with explicitly recorded deferred scope.**

## Task Commits

| Commit | What |
|--------|------|
| `3ea2af0` | Real universe ids, `servePlaceIds`, three new binding assertions |
| `310a652` | CI owner action closed — `ci.yml` is green on the remote |
| `56600b5` | M-04 check 1 recorded passing |
| `618a7ea` | M-04 check 2 recorded **FAILING** |
| `9d456ae` | M-04 check 2 recorded passing after the fix |
| `1e005df` | M-04 and M-05 signed off, D-23 recorded |

## The experiences

| Role | Experience | GameId (universe) | PlaceId |
|------|-----------|-------------------|---------|
| production | `SPOONS [BETA]` | 10774453248 | 123236339661606 |
| dev | `Spoons Dev` | 10774461969 | 120922388251092 |

Both were uploaded with **Save to Roblox As**; Studio's **Publish As** failed repeatedly with a bare
"Save failed". Creating the experience on the Creator Hub first and uploading into it worked, so the
cause was Studio-side, not an account restriction.

## What the gate actually caught

The first production run of the M-04 DataStore line returned:

```
GameId 10774453248 -> WROTE | nil
```

A Studio session wrote to a live production data store. "Enable Studio Access to API Services" had
never been turned off for production, so FOUND-07's **primary** control was absent while every
automated gate was green. After turning it off:

```
GameId 10774453248 -> REFUSED | 403: Cannot write to DataStore from studio if API access is not enabled.
```

with Studio also logging `DataStoreService: StudioAccessToApisNotAllowed` — refused for the specific
expected reason, not merely refused.

Three things are worth carrying forward:

1. **The in-code tripwire would not have caught this.** `PersistenceMode.decide` guards the server
   boot path, not a hand-run command-bar write. D-13 was right to make the separate universe plus
   the toggle the primary control and the tripwire only defence in depth. Any later phase that
   treats the tripwire as the thing protecting production data is mistaken.
2. **The check only worked because it printed `game.GameId` alongside the result.** The first
   attempt was a bare `SetAsync` whose screenshot showed no error; that is indistinguishable from a
   wrong place being open, and a failure for an unrelated network reason is indistinguishable from
   the control working. Printing the id and the error text is what made the result mean something —
   the same "assert the reason, not the outcome" rule the rest of the phase runs on.
3. **One throwaway key reached the live production `m04` store** before the fix. Inert, nothing
   reads it, but it is a real production write and is recorded as one.

## Ids are machine-checked, not eyeballed

Rather than let `Environments.luau` and `default.project.json` agree by inspection,
`tests/project/project.spec.luau` now asserts:

- no id is a placeholder zero, and each is an exact integer below 2^53
- dev and production are different universes (if they matched there would be no isolation at all)
- `servePlaceIds` **equals** `DEV_PLACE_ID` and never names production

Each was mutation-proven to fail when its subject is broken: resetting `PRODUCTION_UNIVERSE_ID` to 0
fails the first, pointing `servePlaceIds` at the production place fails the third. A zero
`PRODUCTION_UNIVERSE_ID` is not a harmless placeholder — the tripwire refuses only when `game.GameId`
equals it, and no real experience has GameId 0, so a zero is a *disabled control*.

## CI had already run (correction)

`NEEDS_HUMAN.md` carried "ci.yml has never run remotely" as an open owner action. That was wrong:
six runs exist on this branch and all are green. Inspecting the job steps rather than the
conclusion confirms it is not a trivial pass — all fourteen gates appear as separate green steps.
That also settles the two things this container could not verify: `actions/checkout@v7` resolves and
the SHA-pinned `CompeyDev/setup-rokit` installs the pinned toolchain on a clean `ubuntu-latest`
runner. Latest: https://github.com/Tree2cool/robloxspoons/actions/runs/41582812758

## Deferred, with scope recorded (D-23)

Two sub-checks were deferred by owner decision rather than ticked as if verified:

| Deferred | Why | When it gets done |
|----------|-----|-------------------|
| M-04 check 3, the boot tripwire | Observing it fire needs a publish over the **live production place**, because `servePlaceIds` now deliberately stops `rojo serve` reaching production. Disproportionate for a secondary control whose logic is unit-tested and whose primary counterpart is verified | First real deploy |
| M-05's 11th join | Needs ten simultaneous real clients | First ten-player playtest |

**Not claimed:** that the tripwire has ever fired in a real Studio session, or that an 11th join has
been observed being refused. Both are carried in `NEEDS_HUMAN.md`.

## Known Stubs

None introduced.

## Threat flags

`T-1-10` (Studio writing production player data) is mitigated and, for the first time in this phase,
**demonstrated** rather than assumed — including the window where it was not mitigated at all.
`T-1-11` (`rojo serve` syncing into the wrong place) is mitigated by `servePlaceIds` and asserted by
a test.

`D-22` (the gateway checks phase before the rate-limit bucket) remains flagged and unexamined for
Phase 4 or 8. This plan did not touch it.

## Self-Check: PASSED

14/14 automated verify steps green locally and in CI; `--filter project` 20/20; all six manual
checks signed with deferred scope stated.
