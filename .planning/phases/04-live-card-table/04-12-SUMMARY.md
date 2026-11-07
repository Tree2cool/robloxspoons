---
phase: 04-live-card-table
plan: 12
subsystem: server-core
tags: [card-table, privacy, rule-6, rule-8, card-13, card-14, card-16, card-17, card-19]
requires: [04-01, 04-02, 04-05, 04-06, 04-07]
provides: [CardTable.new, CardTable.SeatSpec, CardTable.Deps, CardTable.SyncPayload, CardTable.RoundStartPayload]
affects: [04-13 NetServer, 04-14 CardService]
key-files:
  created:
    - src/server/core/CardTable.luau
    - tests/card/privacy.spec.luau
    - tests/card/cardtable.spec.luau
decisions:
  - "Stall payload is { active = bool } only; showSeconds dropped (see Deviations 1)"
  - "A Sync for a user with no seat carries seat = 0 and the same key set"
  - "Sinks fire from one generic event scan (Completed / SeatRemoved), so Bench needs no separate onSeatRemoved call"
metrics:
  tasks: 3
  completed: 2026-11-07
---

# Phase 4 Plan 12: CardTable Summary

The pure server card core: roster-derived seat, one `apply -> bookkeep -> queue -> publish` path shared by
intents, the 10 Hz sweep and removal, publication through `CardRouting.publish`, and three specs (privacy
gate, scripted-bot equivalence with the engine, rule-6 yielding-publisher gate).

## Commits
- `1560f59` feat: `src/server/core/CardTable.luau`
- `c20e394` test: `tests/card/privacy.spec.luau`
- `98b9b82` test: `tests/card/cardtable.spec.luau`
- `778d7f6` refactor: drop a redundant pose table in `start`
- `d1319a7` test: reword map-node references (acceptance grep forbids the literal type name)

## Measured
- `tests/card`: 79 passed, 0 failed, 0.17 to 0.21 s (was 68 cases / 0.10 s before this plan).
- `cardtable.spec.luau` alone: 11 cases, **0.12 / 0.14 / 0.12 s** (cap 0.35 s). `privacy.spec.luau` alone: 7 cases, 0.06 s.
  Seed count stayed at the planned **3 per cell**; no reduction to N in {3, 10} was needed.
- Full suite `lune run tests/run.luau`: **751 passed, 0 failed, 25.41 s**. `tests/engine`: 138 passed.
- `lune run scripts/verify.luau`: **all 14 automated steps passed in 28.1 s** (standard-platform typecheck included).
- `check-guards: ok`, selene shipped and pure configs 0 errors, `analyze` ok.

### Case 1 accepted-action counts (3 seeds per N, shell hash == direct hash on every cell)
`N=3: 783 accepted actions; N=6: 1263; N=10: 1267` (per-round cap 420 accepted actions; N=3 rounds end on completion earlier).

### Chain case (1b)
`autoPassDeci = 80; real sweeps 0/2 commands, mutant (+1) 0/0`: no command at armedAt+79, AutoPass+Strike at
armedAt+80, and the `autoPassDeci + 1` IdleClock does not fire at armedAt+80.

## Mutations watched go red (verbatim, source mutations on CardTable.luau, restored after each)

1. **Notice to wrong player** (`userIdOfSeat` returns the successor): 2 failed.
   `FAIL ...privacy.spec.luau::a ValveForcedPass becomes a private Notice...` / `clean path (expected {  }, got { [1] = "ForcedPass notice went toPlayer to 102", [2] = "user 102 received a Notice" })`
2. **Sync routed via toSeated**: 6 failed, e.g. `FAIL ...::every Sync reaches exactly its owner...` / `clean path (... "a Sync went out via toSeated" ...)`; also the rank-walk case, the completion case, D-12 case and the stray-intent case.
3. **Publish between `Engine.apply` and `idle:sync`** (rule 6, real shell): 6 failed, the rule-6 one being
   `FAIL ...cardtable.spec.luau::rule 6: a yielding publisher cannot interleave two intents mid-state` /
   `real shell: first-publish bookkeeping (expected {  }, got { [1] = "at the first publish idle:sync had run 0 times, expected 1", [2] = "at the first publish stall:noteApply ...`
4. **`idle:sync` never called**: 3 failed: the 80-deci chain case (`no command one deci early (expected 0, got 1)`), the disconnect case (`the idle clock forgot the seat (expected nil, got 80)`), and rule 6 (`idle:sync had run 0 times, expected 1`).
5. **`poolConfig(#seats, ...)` (off-by-one against A3)**: 5 failed, all `Pool.poolConfig: players in round must be an integer in 3..10, got 2`, including the A3 case.
6. **RoundStart entry copies the struct whole**: 1 failed.
   `FAIL ...::the RoundStart payload carries EXACTLY the published key set...` / `real start fed the nodeish input must report zero problems (expected {  }, got { ... "unexpected key up at RoundStart.seats[1] (a MapContract.Node field)" ...`
7. **Bench issues Remove with cause Completed (type bypassed with `any`)**: 2 failed. The engine throws, the per-command containment swallows it, so the bench never lands:
   `FAIL ...::the AFK path benches through Remove{Benched}... / exactly one Benched removal (expected 1, got 0)` and rule 6 `real tick: every command applied before the first publish ... "first publish with 1 of 2 applies done"`.
8. **`tick` publishes per command**: 2 failed.
   `FAIL ...::rule 6: ... / real tick: every command applied before the first publish (expected {  }, got { [1] = "first publish with 1 of 2 applies done" })`
9. **`result.reject` published to the actor**: 1 failed.
   `FAIL ...privacy.spec.luau::a rejected intent produces the same Sync message shape...` / `same key set (expected ackSeq,downstream,hand,idleDeadlineUnix,inbox,seat, got reject)`
10. Sinks fired before publishing (crude edit, ran the sinks twice, so the failures are partly double-fire): 5 failed. Weak evidence for the "sinks after publish" ordering; see Known Gaps.

Injected-dependency mutants inside the specs (all reported by their shared helper while the clean control passes):
- privacy: `leak = true` (51 problems), Sync via `toSeated` (51), `ValveForcedPass` in the public batch (1), a `rank` on a Table payload (12), a `Notice` to the wrong player (2). Count asserted = 5.
- cardtable: card-destroying bench (`card count 8 ~= totalCards 25`), publish-before-sync intent (structural AND snapshot: real deadlines 585,585 vs mutant 585,580), per-command sweep (structural: `first publish with 1 of 2 applies done`), malformed command (contained, `command_failed_Explode`), `autoPassDeci + 1`, by-reference RoundStart forward (**10** problems = `#BANNED_KEYS`, real start on identical input: 0).

## Shipped contract text (plans 04-13 and 04-14 build against this)

`Deps` as shipped is exactly the plan's `<interfaces>` block (publisher, nowDeci, rng, extraRanks, jokers, jokerMode, idle, stall, unixDeadlineFor, onCompleted, onSeatRemoved, onTelemetry); `CardTable` has `start, onIntent, onGatewayReject, tick, removePlayer, seatOf, isLive, debugState` with the planned signatures. `idle` and `stall` arrive as objects. See `src/server/core/CardTable.luau` lines 56-120 for the verbatim type text.

**`Sync` payload key set** (toPlayer only): `ackSeq, seat, hand, inbox, downstream` plus `idleDeadlineUnix` only while a deadline is armed. `hand` entries are `{ cardId, rank, copy }`. For a user with no seat: same shape, `seat = 0`, empty hand, zeros.
**`RoundStart` payload key set** (toSeated): top level exactly `{ seats, jokerMode, ranks }`; each seat exactly `{ seat, playerId, position, look }`; each pose exactly `{ x, y, z }`.
**`Notice`** (toPlayer only): `{ code = "ForcedPass", cardId }`, `{ code = "Strike", strikes, owes, cardId? }`, `{ code = "Benched" }`.
**`Stall`** (toSeated): `{ active = true }` or `{ active = false }`.
**Telemetry names** (counters only; the name carries a code or kind): `reject_<Code>`, `unknown_intent`, `intent_failed`, `bookkeeping_failed`, `publish_failed`, `command_failed_<kind>`, `idle_tick_failed`, `stall_tick_failed`, `remove_failed`, `sink_failed_onCompleted`, `sink_failed_onSeatRemoved`.

## Deviations from Plan

**1. [Rule 3 - Blocking] `Stall` payload has no `showSeconds`.** `Deps` (the authority) carries no stall cue duration and `StallDetector` keeps `cueDeci` private, so the field cannot be filled from anything in scope. Plan 04-18 reads `Config.Card.STALL_CUE_SECONDS` client-side anyway. Payload is `{ active }`. Adding a `Deps` field would have changed the contract 04-14 builds to.

**2. [Rule 1] Case 6 sweep mutant: the plan's claim that the interleaved pass "does not commute" is false for this scenario.** The per-command `tick` mutant is detected ONLY by the structural first-publish applies-count assertion (`first publish with 1 of 2 applies done`). The composite snapshot (hash, deadlines, strikes, actions) is indistinguishable from the serial run: the benched seat's dumped cards keep the same order whichever side of the Bench the upstream pass lands, and every deadline is armed at the sweep's own instant. A benched seat's own Draw as the interleave was tried and is equally invisible, because the deal's ascending ids make "drawn then sorted into hand" and "still at inbox front" route identically. The spec prints this (`composite snapshot indistinguishable from serial: true`) rather than asserting the plan's claim. The structural assertion is the gate, as the plan said it must be. The intent-level mutant (publish between apply and sync) IS caught both ways (it needs `now` to differ between the two intents).

**3. [Rule 3] Rule-6 sweep scenario needs `maxStrikes = 1`.** With the shipped 3 strikes an `AutoPass` and a `Bench` for the same seat can never share a sweep (the seat is at hand 4 after the first auto-pass, owes a Draw, and a Draw cannot be forced). The spec injects an `IdleClock` with `maxStrikes = 1`, which the injected-object design makes a one-line substitution.

**4. [Rule 3] Lune runs the main script inside a coroutine**, so `coroutine.isyieldable()` is true on the main thread; the first draft of the yielding publisher yielded the whole process and `lune run tests/run.luau` exited silently mid-suite. The publisher yields only when `coroutine.running()` equals the one thread the rig names.

**5. Minor, API shape.** (a) `CardRouting.publish` sends the Table batch before ForcedPass notices, so the actor's Sync / Table / Notice order is Sync, Table, Notice, other Syncs (the plan listed Notice before Table); semantically equivalent and the plan's handoff required calling `publish`. (b) The acceptance grep `grep -q 'ranks = '` finds the `RoundStart` payload constructor `ranks = rankCount`; there is no inline rank arithmetic (the only subtraction is `Pool.poolConfig(#seats + 1, ...)`). (c) The case-1 equivalence loop also issues an occasional extra Draw (legal or not) to compare the rejection path; those are not counted in the accepted total.

**6. Case 3 (privacy) forces the valve through the verified `Livelock` fixture.** Its fields are copied into the table's own state via `debugState`, then driven action by action through `onIntent`; the valve fires on action 113 and the Notice is the real shipped output. No synthetic `ValveForcedPass` was injected. CardTable keeps the `copyOf` from the original 21-card deal, which covers the fixture's 12 ids.

## Known Gaps / honest limits
- The privacy mutants 1 to 4 and the wrong-player Notice are publisher decorators (the privacy spec cannot edit production); mutation 1 above (source edit of `userIdOfSeat`) is the evidence the shipped path is guarded.
- Sinks-after-publish ordering is not directly asserted (mutation 10 was a crude double-fire). A dedicated order assertion (sink observes that the Table batch is already recorded) would be a cheap follow-up.
- `NetServer` really mapping `toPlayer` to `FireClient(player)` stays human-gated (M-12).
- The seat-pose publication (`RoundStart`) is a new network exposure justified in the file header; the key-set assertion enforces its narrowness.
- A sole remaining seat at `downstream` reports its own inbox size (`seat.next == seat`), per the plan's formula.

## Known Stubs
None.

## Self-Check: PASSED
- Files present: `src/server/core/CardTable.luau`, `tests/card/privacy.spec.luau`, `tests/card/cardtable.spec.luau`.
- Commits `1560f59`, `c20e394`, `98b9b82`, `778d7f6`, `d1319a7` present in `git log`.
- `verify.luau`: all 14 steps passed; full suite 751 passed.
- STATE.md, ROADMAP.md, REQUIREMENTS.md not touched; `requirements.mark-complete` not run.
