---
phase: 04-live-card-table
plan: 03
subsystem: net
tags: [manifest, rate-limits, rule-7, validation]
requires: []
provides: [Draw{seq} intent, Pass{seq,cardId} intent, per-intent buckets]
affects: [04-07, 04-09, 04-12, 04-13, 04-14]
key-files:
  modified:
    - src/shared/Net/Manifest.luau
    - src/shared/Config/RateLimits.luau
    - tests/net/manifest.spec.luau
requirements-completed: [CARD-02, CARD-14]
completed: 2026-11-06
---

# Phase 4 Plan 03: Draw and Pass intents Summary

Draw{seq} and Pass{seq,cardId} registered Round-only with exactKeys schemas, so rule 7 (no seat, target or hand index from the client) is structural, and a 14-case forbidden-key gate with injected-dependency mutations asserts it.

## Commits
- b5c86e6 feat: manifest entries, buckets
- e0b34fe test: rule-7 gate

## Rate limits
Draw and Pass: burst 8 / refill 6 each, separate buckets. These are STARTING VALUES for Phase 8 tuning, not measured (V-34 stays LOW confidence; the ~500/s platform ceiling does not give a gameplay number).

## Observed rejection codes (quote these, do not guess)
Both Draw and Pass, complete base payload plus one defect:
- seq NaN / +inf / -inf: NotFinite
- seq "1": WrongType
- seq 1.5: NotInteger
- seq -1: OutOfRange
- `{}`: MissingKey
- base + `extra`: UnknownKey
- any of seat,to,target,index,hand,slot,userId added: UnknownKey
- "nope": NotTable; nil: NotTable; function: ForbiddenType
- Pass cardId 0 or 65: OutOfRange; NaN: NotFinite; 1, 49, 64: accepted
Note MissingKey is reported before UnknownKey.

## Gate evidence
Clean run: `rule 7 gate: 14 cases ran, 0 failures` (hard `seen == 14`).
Injected-dependency mutations, all in-case asserted: `rule 7 mutations: (a) 1 (b) 2 (c) 14 (d) 14 red`
(tolerate `seat` on Draw; tolerate `index`,`target` on Pass; accept-all; reject-all with wrong code).

Source mutation (seat added to the real Draw schema), observed red, then reverted:
```
FAIL rule 7: no card intent accepts a seat, a pass target or a hand index
 ... got { [1] = "Draw/seat: expected UnknownKey, got true", [2] = "Draw/to: expected UnknownKey, got MissingKey", ... [7] = "Draw/userId: ... got MissingKey" }
FAIL negative control ...: the real Draw schema must reject seat (expected false, got true)
43 passed, 6 failed, 0 todo
```
Final: net suite 49 passed; full suite 665 passed, 0 failed, 0 todo; check-guards, stylua, selene, analyze all clean; verify.luau ran (2 unsigned manual checks, pre-existing).

## Deviations
- [Rule 3] The existing case "Manifest.intents has exactly one key: Ping" would fail on the new intents; updated to sort and expect Draw, Pass, Ping (committed with Task 1).
- Loosening cannot be modelled by adding a required `seat` field to a local exactKeys (that fails the other cases with MissingKey, as the first attempt showed); the mutation is instead a wrapper validator that tolerates a key. The plan's literal negative-control case 4 (local schema requiring seat) is still present.
- Gateway.luau untouched. No stubs, no new threat surface.

## Self-Check: PASSED
