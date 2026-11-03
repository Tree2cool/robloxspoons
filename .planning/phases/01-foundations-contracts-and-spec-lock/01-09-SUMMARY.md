---
phase: 01-foundations-contracts-and-spec-lock
plan: 09
subsystem: net
tags: [gateway, rate-limit, phase-gate, d-20, remote-event, tdd, strict-typing]

requires:
  - phase: 01-03
    provides: guard rule R4 (Net hygiene) and the net-hygiene fixture
  - phase: 01-05
    provides: Validate, Manifest (PHASES), Bucket, RateLimits
provides:
  - "Gateway.new(deps): five-step check order, returns (ok, code), contained dispatch"
  - "NetServer.start(deps): the one RemoteEvent 'Intent' and the one server connection"
  - "ClientNet.send(intentName, payload?): the one client FireServer site"
  - "Guards-spec cases that count owners over the real src/ tree"
affects: [01-10, 01-12, phase-04, phase-05]

tech-stack:
  added: []
  patterns:
    - "Pure gateway with every dependency injected; the Roblox adapter only derives userId and forwards"
    - "Validator codes pass through to the caller, so tests assert WHY, not just that it was rejected"

key-files:
  created:
    - src/server/core/Gateway.luau
    - src/server/services/NetServer.luau
    - src/client/net/ClientNet.luau
    - tests/core/gateway.spec.luau
  modified:
    - tests/guards/guards.spec.luau

key-decisions:
  - "Phase gate runs BEFORE the bucket (orchestrator instruction and 01-05 handoff), overriding the plan body's order"
  - "Validation rejections surface the validator's own code, not a collapsed 'Malformed'"
  - "Rate limits remain PROVISIONAL / LOW confidence: default burst 4 refill 4/s, Ping burst 2 refill 1/s"

requirements-completed: []
requirements-contributed: [FOUND-04]

completed: 2026-11-03
---

# Phase 1 Plan 09: Gateway, NetServer and ClientNet Summary

**A pure five-step gateway (known intent, phase gate, token bucket, validate, contained dispatch) that hands the handler the clean `exactKeys` copy and reports a specific code for every refusal, fronted by exactly one RemoteEvent named `Intent`, one `OnServerEvent` connection and one `FireServer` site, with the singularity asserted twice (guard R4 and a real-tree walk). Full suite 305 passed, 0 failed, 3 todo (baseline 284).**

## Task Commits

| Step | Commit |
|------|--------|
| RED: gateway vector suite (module absent, load failure, `0 passed, 1 failed`) | `1d4f07d` test |
| GREEN: Gateway | `29dad62` feat |
| NetServer, ClientNet, guards-spec cases | `052f8f6` feat |

No REFACTOR commit needed.

## Published shapes (plan 01-10 wires, Phase 4 extends)

```lua
-- src/server/core/Gateway.luau
export type Code = string
export type RoundPhase = "Lobby" | "Hide" | "Round" | "Podium"
export type Intent = { phases: { RoundPhase }, validate: (value: unknown) -> (boolean, unknown) }
export type Deps = {
	manifest: { intents: { [string]: Intent }, isKnown: (name: unknown) -> boolean },
	bucket: { take: (self: any, userId: number, intent: string, spec: any) -> boolean, forget: (self: any, userId: number) -> () },
	rateFor: (intent: string) -> any,
	getPhase: () -> RoundPhase,
	dispatch: (userId: number, intent: string, payload: unknown) -> (),
	onReject: (userId: number, intent: unknown, code: Code) -> (),
	onError: (userId: number, intent: string, err: unknown) -> (),
}
export type Gateway = {
	handle: (self: Gateway, userId: number, intentName: unknown, payload: unknown) -> (boolean, Code),
	forget: (self: Gateway, userId: number) -> (),
}
return { new = new, PHASES = PHASES }   -- PHASES frozen
```

```lua
-- src/server/services/NetServer.luau
export type Deps = {
	getPhase: () -> Gateway.RoundPhase,
	dispatch: (userId: number, intent: string, payload: unknown) -> (),
	onReject: (userId: number, intent: unknown, code: Gateway.Code) -> (),
	onError: (userId: number, intent: string, err: unknown) -> (),
}
NetServer.start(deps: Deps): NetServer   -- { gateway, remote, destroy }
```

`ClientNet.send(intentName: string, payload: { [string]: any }?)`.

**Codes.** Gateway-originated: `Ok`, `UnknownIntent`, `WrongPhase`, `RateLimited`, `HandlerError`. Validation rejections pass through the validator code: `MissingKey`, `UnknownKey`, `NotFinite`, `NotInteger`, `OutOfRange`, `WrongType`, `ForbiddenType`, `NotTable`, `TooLong`, etc. (`Malformed` exists only as a fallback if a validator returns a non-string).

**Remote name:** `Intent` (in `ReplicatedStorage`). **For manual check M-03:** fire `remote:FireServer("Ping", { nonce = 1 })` for acceptance; `{ nonce = 0/0 }` is rejected `NotFinite`, which genuinely reaches `isFinite`. A bare `{}` is `MissingKey`.

**PHASES duplication.** `Gateway.PHASES` duplicates `Manifest.PHASES` because a relative require from `src/server/core` to `src/shared/Net` is a cross-mount require (R6). It is made safe by the spec case `D-20 drift` (`deepEqual` plus frozen). D-20 is enforced at runtime too: a case sets the phase to `"Scramble" :: any` (and `"round"`) and asserts `WrongPhase` with zero dispatch. `RoundPhase` was not widened.

## Rate limits: PROVISIONAL, LOW confidence

`RateLimits.default = { burst = 4, refillPerSecond = 4 }`, `Ping = { burst = 2, refillPerSecond = 1 }`. Starting points only (research V-34); to be tuned in playtest. Not settled.

## Verbatim evidence

RED:
```
$ lune run tests/run.luau -- --filter gateway
... 0 passed, 1 failed, 0 todo in 0.10s     (module absent: load failure, same shape as 01-05)
```
GREEN: `19 passed, 0 failed, 0 todo` (gateway). Guards: `16 passed, 0 failed`. Full: `305 passed, 0 failed, 3 todo in 9.62s`.

Nine gates, using the settled detector (exit 0 and no `Failed to load` / `Sourcemap parsing failed` / `TypeError`): stylua, selene, selene-pure, rojo build, luau-lsp pure zones + tests, luau-lsp roblox `src`, check-guards (`check-guards: ok (51 files, 85 requires, 12 guarded roots)`), test suite: all PASS. Purity grep over non-comment lines of Gateway.luau: clean. `grep -rl OnServerEvent src` -> only NetServer.luau; `FireServer` -> only ClientNet.luau; in NetServer the connection (line 60) precedes `remote.Parent =` (line 69).

### Mutation checks (every restore verified with `cmp`)

| Mutation to Gateway | Result |
|---|---|
| hand `payload` instead of the clean copy | 1 FAIL (clean copy) |
| skip phase gate | 3 FAIL (WrongPhase, phase-before-bucket, Scramble) |
| never consult the bucket | 5 FAIL |
| let unknown names through | 3 FAIL (incl. count()==0) |
| collapse validator code to `Malformed` | 4 FAIL (vector table etc.) |
| swallow handler error as Ok | 1 FAIL |
| run bucket before phase gate | 1 FAIL (`WrongPhase is decided before the bucket`) |

### Guard-spec cases proven able to fail

1. Added a comment-only `FireServer` in `src/client/Extra.luau`: the new `FireServer` case FAILED with `src/client/Extra.luau, src/client/net/ClientNet.luau (expected 1, got 2)`, while `check-guards` still printed `ok` (R4 ignores comments). This shows the real-tree walk catches what R4 does not.
2. Added real code `r:FireServer(1)` in the same file: the new case failed, the real-repo guard case failed, and `check-guards` reported `R4 src/client/Extra.luau:3 FireServer may appear only in src/client/net/ClientNet.luau`. Reverted (`git status` clean).

## Deviations from Plan

**1. [Divergence] Check order: phase gate before bucket.** The plan body lists isKnown, bucket, phase, validate. The orchestrator's instruction and the 01-05 handoff say isKnown, phase, bucket, validate. I followed the latter. Consequence: a wrong-phase message neither charges a token nor allocates bucket state (asserted by a case). The plan's acceptance wording "bucket call precedes validate" still holds. The token is still charged before validation.

**2. [Divergence] Specific rejection codes instead of a single `Malformed`.** The plan's Code union has `Malformed`; the orchestrator requires asserting `MissingKey`, `NotFinite` etc. `Code` is therefore `string` and validator codes pass through. This loses a closed union for the codes, a deliberate trade for assertability.

**3. [Divergence] `xpcall(deps.dispatch, handler, ...)` failed typecheck** (`Function only returns 1 value, but 2 are required`), as did `pcall` with `local ok, err`, because the callee returns nothing. Fixed with an `xpcall` over a closure whose handler captures the error into an upvalue. Behaviour unchanged, `grep xpcall` still matches.

**4. [Divergence] Guards case count.** The plan says guards reports 12 cases; the actual count is 16 (14 existing + 2 new). The plan's arithmetic was stale; no case is missing.

**5. [Divergence] My own over-broad gate command.** Running `luau-lsp analyze` on `tests` without `--ignore "**/fixtures/**"` reports TypeErrors from deliberately-broken fixtures. That was my command, not a repo defect; the correct scope exits 0. No `scripts/verify.luau` exists yet (01-10), so the nine gates were run by hand.

**6. [Additions, tightening only]** Extra cases: hostile-metatable payload, bad-clock reading, real `Manifest` Ping path (accept, NaN nonce `NotFinite`, bare `MissingKey`), flood from one user does not starve another, phase gate allocates no bucket state.

## Known Stubs

None. NetServer has no unit test by design; its live behaviour is manual check M-03 (01-12).

## Threat Flags

None new. T-1-01, T-1-02, T-1-03, T-1-05, T-1-27, T-1-40, T-1-41 (line order verified), T-1-42 mitigated as planned.

## Self-Check: PASSED

Files exist: Gateway.luau, NetServer.luau, ClientNet.luau, gateway.spec.luau. Commits `1d4f07d`, `29dad62`, `052f8f6` present; RED precedes GREEN. REQUIREMENTS.md untouched; phase not marked complete.
