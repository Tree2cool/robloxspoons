---
phase: 02-card-engine-and-pacing-simulator
plan: 14
subsystem: g1-sweep-run
tags: [gate-g1, sweep, card-pool, valve, owner-decision]

requires:
  - phase: 02-10
    provides: scripts/sim/sweep.luau, the staged sweep CLI
provides:
  - "02-G1-REPORT.md: the Gate G1 verdict and the bar-sensitivity ladder"
  - "02-sweep-data.json: 1,132 cells, 1,501,000 rounds"
affects: [02-11, 02-12]

key-files:
  created:
    - .planning/phases/02-card-engine-and-pacing-simulator/02-G1-REPORT.md
    - .planning/phases/02-card-engine-and-pacing-simulator/02-sweep-data.json
  modified:
    - scripts/sim/sweep.luau

key-decisions:
  - "The sweep was run TWICE: the bar selected k=6, the owner chose k=3 from the ladder, and the sweep was re-run so the shipped pool is also the confirmed one"
  - "VALVE_RATE_MAX_SWEEP 0.07 -> 0.20, a regression guard at an owner-chosen operating point rather than a discovered threshold"
  - "No triage: zero action-cap rounds in all 1,132 cells"

requirements-completed: []
requirements-contributed: [CARD-11, CARD-12]

completed: 2026-11-04
---

# Phase 2 Plan 14: The G1 Sweep Run Summary

**Gate G1 passes. 1,501,000 rounds across 1,132 cells selected `k=3` extra ranks, `j=1` joker, Wild
default with Blocker as a live flag, at an 8.0s auto-pass deadline — with 37 stalled rounds in
320,000 printed rather than rounded away.**

This summary was written by the orchestrator after the fact, which is itself worth recording: Phase
2 verification found it missing (finding F1) because the plan's executor was lost to a container
restart and I ran the sweep directly afterwards. Every other plan in the phase has one.

## The run, twice

| run | bar | selected | confirmed at 10,000 rounds/cell | commit |
|-----|-----|----------|--------------------------------|--------|
| first | `VALVE_RATE_MAX = 0.07` | k=6, j=1, 8.0s | **k=6** | `88e4046` |
| second | `VALVE_RATE_MAX = 0.20` | **k=3**, j=1, 8.0s | **k=3** | `0d76087` |

**Why twice, and why it mattered.** The first run's own bar-sensitivity ladder showed that every
candidate from k=2 to k=6 cleared all five bars, and that the firing-rate curve is smooth and
monotone with **no elbow** — so the bar does not discover a pool, it chooses one. That made the
choice a question about how the game feels, which no bar can measure, and it went to the owner:

| bar | pool | first completion | p95 | occupancy | valve fires | stalls |
|-----|------|------------------|-----|-----------|-------------|--------|
| 40% | k=2 | 14.5s | 21.8s | 0.789 | 15.5% | 0.100% |
| 20% | **k=3** | **16.4s** | 23.5s | 0.825 | 9.4% | **0.000%** |
| 10% | k=4 | 18.2s | 26.2s | 0.838 | 4.9% | 0.000% |
| 7%  | k=6 | 20.9s | 32.1s | 0.856 | 2.5% | 0.000% |

The owner chose **k=3**: the tightest pool reaching a clean zero, giving up ~2s of starting-gun
speed against k=2 while cutting forced passes by a third, and avoiding k=6's ~45% slower start. A
valve firing is **not invisible** — a card leaves a hand the player did not choose — so the firing
rate is a feel cost, not only a safety statistic.

The re-run is the part that matters. The first run had confirmed **k=6** at 10,000 rounds per cell,
so the pool we actually ship would have had only 1,000-round search evidence behind it, where a
single stalled round reads as 0.1%. Shipping a configuration whose rigorous evidence was measured on
a *different* configuration is precisely the quiet gap this phase kept catching elsewhere.

## The verdict as measured

| bar | measured worst case | ceiling |
|-----|--------------------|---------|
| stalls | **0.070%** worst cell, 0.012% aggregate (37 of 320,000) | <= 0.500% |
| median first completion | 16.2s | <= 45s |
| p95 first | 23.7s | <= 120s |
| occupancy | 0.825 | >= 0.600 |
| valve firing rate | 8.24% | <= 20% |

`marginal = false`. Mechanism checks pass. 1428.9s wall time.

**Blocker survived on merit.** Both joker modes clear every bar at every roster size, so CARD-12 is
a live flag with real tests rather than the contingency it was written as.

**The valve is load-bearing, measured on matched cells:** valve-off twins at N=10 stall **3.58-8.31%**
against the shipped pool's 0.0116% residual — roughly 500x. (Phase 2 verification corrected my
earlier 6.2-8.3% figure: the churn variants are the low end.)

## Triage: none, and the reason is narrower than it looks

`capArtifactCandidates` is empty in all 1,132 cells and `hitActionCap` false in every confirm row,
so `02-triage.json` is absent by measurement. The conclusion — the residual is not a cap artefact,
and a raised action cap could not rescue it — is correct and conservative, because 300s is the
shipped round cap.

But verification finding **F3** sharpened this and it should not be forgotten: those counters track
the 100,000-**action** cap, while the gated cells are Pacing cells ending on the 300-**second**
clock at ~379 actions per round. "No action-cap rounds" was therefore structurally guaranteed for
those cells rather than discovered. **Whether the residual rounds are cycling or merely slow remains
formally open**, because cycle detection is disabled for every valve-ON cell by design.

## What this run does NOT claim

- Not that the engine cannot stall. The claim is about a **selected configuration at a confirmed
  round count**, with the residual printed.
- Not that the pacing figures describe real players. G1's **solvability** half is a theorem
  independent of the bot model; its **pacing** half measures the bot. V-35 and A4 stay open until a
  playtest — now tracked as MANUAL-CHECKS **M-07** rather than only in STATE.md.
- Not that the firing-rate bar was discovered. It is a regression guard at an owner-chosen operating
  point, and the report's section 2 now says so.

## Self-Check: PASSED

509 passed, 0 failed, **0 todo**; `verify.luau` 14/14.
