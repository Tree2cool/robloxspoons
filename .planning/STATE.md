---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: planning
stopped_at: Phase 1 context gathered
last_updated: "2026-11-02T21:28:46.622Z"
last_activity: 2026-11-02 - Roadmap created (8 phases, 102/102 v1 requirements mapped)
progress:
  total_phases: 8
  completed_phases: 0
  total_plans: 12
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-11-02)

**Core value:** The two-stage race has to feel great: the frantic card scramble must flow into the spoon hunt so that getting four of a kind feels like a starting gun, not a menu transition.
**Current focus:** Phase 1 - Foundations, Contracts and Spec Lock

## Current Position

Phase: 1 of 8 (Foundations, Contracts and Spec Lock)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-11-02 - Roadmap created (8 phases, 102/102 v1 requirements mapped)

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: - min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Engine-first. Pure card engine and pacing simulator (Phase 2) precede all UI and networking; Gate G1 sits inside Phase 2.
- [Roadmap]: Parallel pairs are Phase 2 with Phase 3, and Phase 4 with Phase 5; they merge at Gate G3 (vertical slice) before breadth work.
- [Roadmap]: Map contract (MAP-01) lands in Phase 1, validator (MAP-02, MAP-03) in Phase 3 after placement rules; the five maps (Phase 7a) wait on Gate G2.
- [Roadmap]: Anti-ESP is designed into Phase 5 on auto-filled data spoons, before the hide UI exists (Phase 6).
- [Roadmap]: Lint guards FOUND-05 and FOUND-06 are Phase 1 so no-pay-to-win and engine purity hold for the whole project.
- [Roadmap]: Engine lives in `server/engine/`, tested headless (Lune or `luau` CLI), not Jest-Lua (research Contradiction 1, follows ARCHITECTURE).
- [Roadmap]: Phase 7 holds two independent tracks (maps 7a, cosmetics/shop 7b); the planner may split it without changing requirement mapping.
- [Roadmap]: CARD-18, SCORE-09, MATCH-04, MATCH-05 sit in Phase 7 because they need cosmetic content; Phase 4 and Phase 6 build the hooks and baseline.

### Pending Todos

None yet.

### Blockers/Concerns

- BLOCKING for card engine, resolve in Phase 1 spec: deal-time four-of-a-kind (default: re-shuffle so no seat starts complete, CARD-09) and which four cards leave on a joker completion (default: spend naturals first, CARD-10).
- Verification debt: every Roblox platform claim in research is unverified (doc hosts DNS-blocked). Each phase's research step starts by re-checking SUMMARY.md Verification Debt rows for that phase. Add the blocked hosts to the environment's allowed domains.
- Owner decisions CONFIRMED during initialization: hider-score denominator = fixed 300 s (OQ 7); mid-round leaver = finish the round then end on current totals, no win credit (OQ 8); free/earned cosmetic baseline = free defaults plus an achievement-unlocked set (OQ 11); player cap = 10 (OQ 17).
- Owner decisions still open: match tiebreak (OQ 5, default: higher best-round then earlier four-of-a-kind placement), avatar normalisation scope (OQ 12, Phase 3), VIP route (OQ 14, Phase 7b), Game Pass versus Developer Product switch point (OQ 15, Phase 7b), rejoin policy confirmation (OQ 18, derived default in MATCH-08), cold-start and bot-fill decision (OQ 13, Phase 8 on telemetry).
- Cold start below the 3-player minimum is an existential risk that code alone cannot fix; bot-fill decision is deferred to Phase 8 on telemetry.
- First true 9 to 10 player human playtest needs a published place (human gate); Studio multi-client is capped.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: --stopped-at
Stopped at: Phase 1 context gathered
Resume file: --resume-file

**Planned Phase:** 1 (Foundations, Contracts and Spec Lock) — 12 plans — 2026-11-02T21:28:46.598Z
