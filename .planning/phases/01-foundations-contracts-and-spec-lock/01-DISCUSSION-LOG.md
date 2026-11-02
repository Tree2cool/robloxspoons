# Phase 1: Foundations, Contracts and Spec Lock - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-11-02
**Phase:** 01-foundations-contracts-and-spec-lock
**Areas discussed:** CI gate strictness, Studio vs filesystem, Map contract shape, Data isolation
**Area selection:** all four offered areas selected

---

## Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| CI gate strictness | Hard-fail vs report for lint/typecheck/guards | ✓ |
| Studio vs filesystem | Code vs Studio authoring; `rojo syncback` | ✓ |
| Map contract shape | How a map declares default spots and spawns | ✓ |
| Data isolation | Separate test universe vs in-code guard | ✓ |

---

## CI Gate Strictness

### Violation handling

| Option | Description | Selected |
|--------|-------------|----------|
| All hard-fail | Any violation fails the build, formatting included | ✓ |
| Guards+types hard, lint soft | Guards and typecheck block; style reports | |
| All advisory at first | Nothing blocks until the codebase matures | |

**User's choice:** All hard-fail
**Notes:** Maximum strictness chosen deliberately. Trade-off accepted: a stray formatting slip blocks the same as a pay-to-win import.

### CI trigger scope

| Option | Description | Selected |
|--------|-------------|----------|
| Every push + PR | Runs on all branches and PRs | ✓ |
| PRs + main only | Cheaper, quieter | |
| Every push + PR, split jobs | Same coverage, fast/slow jobs separated | |

**User's choice:** Every push + PR

### Local pre-commit

| Option | Description | Selected |
|--------|-------------|----------|
| Fast checks locally | Format + lint on pre-commit; typecheck/tests in CI | ✓ |
| CI only | No local hooks | |
| Everything locally | Full suite on pre-commit | |

**User's choice:** Fast checks locally
**Notes:** Rejected full-suite hooks on the grounds that slow commits lead to `--no-verify`.

### Un-automatable criteria

| Option | Description | Selected |
|--------|-------------|----------|
| Checklist + helper script | MANUAL-CHECKS.md plus a script for everything verifiable | ✓ |
| Checklist only | Document the manual steps | |
| Defer to Studio access | Mark blocked until Studio is available | |

**User's choice:** Checklist + helper script
**Notes:** Driven by the absence of a Roblox Studio MCP in this container, surfaced before the area was discussed.

---

## Studio vs Filesystem

### Map geometry source of truth

| Option | Description | Selected |
|--------|-------------|----------|
| Per-map .rbxm in git | Export each map, commit, Rojo mounts it | ✓ |
| rojo syncback | Pull the place back into the repo | |
| One place file | Single committed .rbxl | |

**User's choice:** Per-map .rbxm in git
**Notes:** Supports parallel map building in Phase 7; syncback rejected for clobber risk, single .rbxl for merge conflicts and opacity.

### Rojo management scope

| Option | Description | Selected |
|--------|-------------|----------|
| Code only, ignore Workspace | `$ignoreUnknownInstances` protects Studio work | ✓ |
| Rojo owns everything | Repo is complete truth, Studio is a viewer | |
| Code + shared stages only | Middle ground | |

**User's choice:** Code only, ignore Workspace

### Script vs instance authoring

| Option | Description | Selected |
|--------|-------------|----------|
| Scripts via files, rest in Studio | Matches the roblox-ai-build ruleset | ✓ |
| Everything via files | Fully reproducible, poor authoring feel | |

**User's choice:** Scripts via files, rest in Studio

### Reference map scope

| Option | Description | Selected |
|--------|-------------|----------|
| Gray-box, mechanically complete | Real spawns, ≥16 spots, real sightlines, no art | ✓ |
| Minimal test room | Single box room | |
| Gray-box of a real map | Gray-box the actual hotel | |

**User's choice:** Gray-box, mechanically complete

---

## Map Contract Shape

### Default spot declaration

| Option | Description | Selected |
|--------|-------------|----------|
| Tagged parts in Studio | Marker parts read via CollectionService | ✓ |
| Luau data file per map | Committed CFrame table | |
| Tags, exported to data | Place in Studio, export to Luau | |

**User's choice:** Tagged parts in Studio

### Contract requirements (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| Seeker spawns + hider spawn | Named spawn points | ✓ |
| Playable bounds volume | One authority per map | ✓ |
| Metadata block | Name, player range, size class | ✓ |
| Decoy item anchors | Needed by the maze, generalised | ✓ |

**User's choice:** All four, **plus a user-originated addition**: "The spot where the actual dealing should also be on every map, for example the hotel could be like a table with 10 chairs in the lobby."
**Notes:** Accepted and recorded as CONTEXT D-11. Seat count corrected from 10 to 9 (10 players − 1 hider = 9 seekers). This addition generated two follow-up questions (camera and leaving the table) that were not in the original area plan.

### Validator scope in Phase 1

| Option | Description | Selected |
|--------|-------------|----------|
| Structural now, rules in P3 | Structure checks now; placement rules added in Phase 3 | ✓ |
| Wait for Phase 3 | Build the whole validator at once | |
| Structural + stub interface | Structure plus an unimplemented hook | |

**User's choice:** Structural now, rules in P3

---

## Data Isolation

| Option | Description | Selected |
|--------|-------------|----------|
| Separate test universe | Second Roblox universe; true isolation | ✓ |
| In-code guard | `RunService:IsStudio()` refusal with a dev flag | |
| Both | Guard now, universe later | |

**User's choice:** Separate test universe
**Notes:** Accepted the one-time Creator Hub setup cost. Recorded as a human gate on Phase 1 closing.

---

## Card Phase Staging (follow-ups from the card table addition)

### Table sightlines

| Option | Description | Selected |
|--------|-------------|----------|
| Enclosed table area | Layout constraint: no sightlines to hiding areas | |
| Open, rely on close-range glint | No constraint, slight advantage risk | |
| Camera locked to table | Enforced in code, not per-map layout | ✓ |

**User's choice:** Camera locked to table
**Notes:** Noted to the user that this *removes* a map-authoring constraint rather than adding one — the table can sit somewhere scenic.

### Leaving the table on four of a kind

| Option | Description | Selected |
|--------|-------------|----------|
| Stand up and run | Fully diegetic; table position affects routing | ✓ |
| Teleport to seeker spawn | Equalises run distance, breaks continuity | |
| Stand up, brief freeze | Continuity plus a readable beat | |

**User's choice:** Stand up and run

---

## Claude's Discretion

Areas not discussed, defaulted to research recommendations: package manager (Wally,
pesde fallback), module and folder layout, test harness mechanics, `Net` gateway
internals and rate-limit numbers, round-end FSM internals, Rokit tool versions, CI job
layout.

## Deferred Ideas

None — the discussion stayed within phase scope. D-14 and D-15 are Phase 1 decisions
implemented in Phases 4 and 5; they are not deferrals.
