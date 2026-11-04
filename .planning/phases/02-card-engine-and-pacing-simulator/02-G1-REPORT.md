# Phase 2 Gate G1 Report

Generated 2026-11-04T02:11:36Z by `scripts/sim/sweep.luau`.

## 1. Verdict

**Selected pool: k = 3 extra ranks, j = 1 joker(s), auto-pass deadline 8.0s.**
Joker mode is a FLAG, not a selection: Wild and Blocker both clear every
bar at every N, and `Wild` is the default PROJECT.md records.

Marginal: **false**

| bar | measured worst case over the confirmed cells | bar | with margin |
|---|---|---|---|
| stalls | 0.070% | <= 0.500% | <= 0.250% |
| cleared fraction | see section 3 | = 1 - the stall ceiling | |
| median first | 16.2s | <= 45s | <= 36.0s |
| p95 first | 23.7s | <= 120s | <= 96.0s |
| occupancy | 0.825 | >= 0.600 | >= 0.660 |
| valve firing rate | 8.240% | <= 20.000% | <= 10.000% |

**G1: PASSES** on this evidence - **37 stalled round(s) observed for the selected pool in 320000 gated rounds** at 10000 rounds per cell - 0.012% aggregate, worst cell 0.070%, against a 0.500% ceiling. That is the claim, in its honest form: a measured property of a SELECTED configuration, never an unconditional property of the engine. The measured residual is printed above rather than rounded away, and section 4b says whether it was a cap artefact or a real one.

| stage | rounds per cell |
|---|---|
| search | 1000 |
| mechanism | 4000 |
| probe | 1000 |
| confirm | 10000 |

The search stage ran at its own round count and is a **search, not a gate**. The locked
10,000-rounds-per-cell bar is applied by the confirm stage, to the configuration that ships.

## 2. The five bars

| # | bar | threshold | where it comes from |
|---|---|---|---|
| 1 | stalls | stall rate <= 0.500% | amendment A8 resolution 2: an explicit residual ceiling, five times the measured 0.05-0.10% valve-ON residual and twenty times below the 10.6% a valve regression produces. The locked bar was ZERO; no pool this engine has reaches it |
| 2 | cleared fraction | every eligible round cleared, to within the same ceiling | the stalls bar from the other side, derived independently |
| 3 | pacing | median time to first completion <= 45s and p95 <= 120s | 02-CONTEXT amendment A2 |
| 4 | occupancy | mean occupancy >= 0.600 | amendment A2 and research 3.7: without it the rule picks k=0,j=1, one card circulating among nine seats |
| 5 | valve firing rate | <= 20.000% of rounds | amendment A8 resolution 1, re-derived from the measured curve. See the bar-sensitivity ladder in section 4b |

`Simulator.evaluateBars` is UNCHANGED and is evaluated for every Pacing cell alongside
these; its verdict rides on each cell in `02-sweep-data.json` as `lockedVerdict` and
`lockedFailures`, so the locked-constant view is in the artefact and can be read directly.

## 3. Confirmation stage

| N | mode | churn | stall | medFirst | p95First | medAll | p95All | occupancy | ramp | autoPass | dealAttempt mean/max | Cleared/Unsat/Livelock/Cap/Shortfall/Dead | bars | locked bars |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | Wild | false | 0.0000 | 6.0 | 12.3 | 6.0 | 12.3 | 0.885 | 1.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 3 | Wild | true | 0.0000 | 6.6 | 15.8 | 6.6 | 15.8 | 0.898 | 1.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 3 | Blocker | false | 0.0000 | 8.4 | 14.5 | 8.4 | 14.5 | 0.917 | 1.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 3 | Blocker | true | 0.0000 | 10.5 | 17.7 | 10.5 | 17.7 | 0.931 | 1.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 4 | Wild | false | 0.0000 | 6.8 | 13.2 | 11.0 | 17.1 | 0.887 | 2.4 | 0.0000 | 1.0/3 | 10000/0/0/0/0/0 | pass | pass |
| 4 | Wild | true | 0.0000 | 7.2 | 15.5 | 13.2 | 21.5 | 0.900 | 2.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 4 | Blocker | false | 0.0000 | 9.3 | 15.5 | 13.1 | 18.6 | 0.901 | 2.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 4 | Blocker | true | 0.0000 | 10.5 | 18.3 | 16.1 | 22.7 | 0.914 | 2.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 5 | Wild | false | 0.0000 | 7.9 | 14.7 | 14.9 | 21.8 | 0.874 | 3.4 | 0.0000 | 1.0/3 | 10000/0/0/0/0/0 | pass | pass |
| 5 | Wild | true | 0.0000 | 8.3 | 16.1 | 18.0 | 26.8 | 0.889 | 3.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 5 | Blocker | false | 0.0000 | 10.4 | 16.4 | 16.3 | 22.7 | 0.883 | 3.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 5 | Blocker | true | 0.0000 | 11.2 | 18.7 | 19.7 | 27.3 | 0.898 | 3.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 6 | Wild | false | 0.0000 | 9.0 | 15.9 | 18.1 | 25.9 | 0.861 | 4.4 | 0.0000 | 1.0/3 | 10000/0/0/0/0/0 | pass | valve-rate |
| 6 | Wild | true | 0.0000 | 9.2 | 17.3 | 21.8 | 31.6 | 0.877 | 4.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 6 | Blocker | false | 0.0000 | 11.7 | 17.5 | 19.4 | 27.3 | 0.867 | 4.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 6 | Blocker | true | 0.0000 | 12.3 | 19.7 | 23.1 | 31.7 | 0.885 | 4.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 7 | Wild | false | 0.0000 | 10.1 | 17.1 | 21.3 | 31.2 | 0.850 | 5.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 7 | Wild | true | 0.0000 | 10.3 | 18.0 | 25.3 | 36.4 | 0.867 | 5.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 7 | Blocker | false | 0.0001 | 12.8 | 18.5 | 22.6 | 32.4 | 0.855 | 5.4 | 0.0000 | 1.0/2 | 9999/0/0/1/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 7 | Blocker | true | 0.0000 | 13.4 | 20.6 | 26.6 | 36.2 | 0.874 | 5.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 8 | Wild | false | 0.0001 | 11.2 | 18.3 | 24.5 | 36.8 | 0.840 | 6.4 | 0.0000 | 1.0/2 | 9999/0/0/1/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 8 | Wild | true | 0.0000 | 11.3 | 19.4 | 28.7 | 40.4 | 0.860 | 6.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 8 | Blocker | false | 0.0001 | 14.0 | 19.6 | 25.8 | 67.9 | 0.846 | 6.4 | 0.0000 | 1.0/2 | 9999/0/0/1/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 8 | Blocker | true | 0.0000 | 14.3 | 21.4 | 29.8 | 40.9 | 0.865 | 6.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 9 | Wild | false | 0.0007 | 12.3 | 19.2 | 27.8 | 46.7 | 0.832 | 7.4 | 0.0000 | 1.0/3 | 9993/0/0/7/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 9 | Wild | true | 0.0002 | 12.4 | 20.4 | 32.3 | 46.9 | 0.853 | 7.3 | 0.0000 | 1.0/2 | 9998/0/0/2/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 9 | Blocker | false | 0.0003 | 14.9 | 20.9 | 29.2 | 74.6 | 0.838 | 7.4 | 0.0000 | 1.0/2 | 9997/0/0/3/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 9 | Blocker | true | 0.0002 | 15.3 | 22.6 | 33.5 | 50.9 | 0.858 | 7.3 | 0.0000 | 1.0/3 | 9998/0/0/2/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 10 | Wild | false | 0.0007 | 13.3 | 20.3 | 31.2 | 73.7 | 0.825 | 8.3 | 0.0000 | 1.0/2 | 9993/0/0/7/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 10 | Wild | true | 0.0004 | 13.4 | 21.5 | 35.7 | 53.1 | 0.847 | 8.3 | 0.0000 | 1.0/2 | 9996/0/0/4/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 10 | Blocker | false | 0.0005 | 15.8 | 21.8 | 32.7 | 82.1 | 0.830 | 8.3 | 0.0000 | 1.0/2 | 9995/0/0/5/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 10 | Blocker | true | 0.0004 | 16.2 | 23.7 | 36.9 | 62.2 | 0.851 | 8.3 | 0.0000 | 1.0/2 | 9996/0/0/4/0/0 | pass | stalls,cleared-fraction,valve-rate |

## 4. Known worst case: pure greedy with the valve disabled

These cells run `antiLivelockValve = false` with the auto-pass deadline disabled
(`math.huge`): pure greedy, no rescue, no deadline. They are **the known worst case** and
**the proof the valve is load-bearing**. A valve-off stall is a 1,300-1,900 action
non-progressing tail against a healthy round's ~313 actions.

| stage | N | k | j | mode | churn | rounds | stall (valve OFF) | Livelock | CapReached |
|---|---|---|---|---|---|---|---|---|---|
| mechanism | 10 | 1 | 0 | Wild | false | 4000 | 0.3683 | 1473 | 0 |
| mechanism | 10 | 1 | 1 | Wild | false | 4000 | 0.2687 | 1075 | 0 |
| mechanism | 10 | 1 | 2 | Wild | false | 4000 | 0.2055 | 822 | 0 |
| mechanism | 10 | 2 | 0 | Wild | false | 4000 | 0.1658 | 663 | 0 |
| mechanism | 10 | 2 | 1 | Wild | false | 4000 | 0.1013 | 405 | 0 |
| mechanism | 10 | 2 | 2 | Wild | false | 4000 | 0.0938 | 375 | 0 |
| mechanism | 10 | 3 | 0 | Wild | false | 4000 | 0.0867 | 347 | 0 |
| mechanism | 10 | 3 | 1 | Wild | false | 4000 | 0.0592 | 237 | 0 |
| mechanism | 10 | 3 | 2 | Wild | false | 4000 | 0.0465 | 186 | 0 |
| mechanism | 10 | 4 | 0 | Wild | false | 4000 | 0.0560 | 224 | 0 |
| mechanism | 10 | 4 | 1 | Wild | false | 4000 | 0.0362 | 145 | 0 |
| mechanism | 10 | 4 | 2 | Wild | false | 4000 | 0.0250 | 100 | 0 |
| mechanism | 10 | 6 | 0 | Wild | false | 4000 | 0.0280 | 112 | 0 |
| mechanism | 10 | 6 | 1 | Wild | false | 4000 | 0.0190 | 76 | 0 |
| mechanism | 10 | 6 | 2 | Wild | false | 4000 | 0.0143 | 57 | 0 |
| confirm | 10 | 3 | 1 | Wild | false | 10000 | 0.0621 | 621 | 0 |
| confirm | 10 | 3 | 1 | Wild | true | 10000 | 0.0358 | 358 | 0 |
| confirm | 10 | 3 | 1 | Blocker | false | 10000 | 0.0831 | 831 | 0 |
| confirm | 10 | 3 | 1 | Blocker | true | 10000 | 0.0533 | 533 | 0 |

**Comparison to the figures these bars were originally written against.** 02-CONTEXT
amendment A7-CORRECTION tabulated a prototype at 0.275% / 0.250% / 21.6% valve-off stalls
for k=1,j=1 / k=2,j=1 / k=2,j=2. The real engine does not reproduce them: amendment A8
records 9.6-10.6% at k=2,j=1, a factor of 40, traced to amendment A3 (the prototype seated
10 players; the real game seats 9 seekers because the hider does not play cards, so the
endgame is one rank deeper and 33 of 53 stalls occur at `liveCount == 2`). The table above
is the measurement that supersedes the prototype's. A second prototype claim also fails to
reproduce: k=2,j=2 was its bad pool, and measured it is indistinguishable from k=2,j=1.

## 4b. The valve

| stage | N | k | j | mode | churn | firing rate | firings/round | armed rate | seenResets | hit the action cap |
|---|---|---|---|---|---|---|---|---|---|---|
| confirm | 3 | 3 | 1 | Wild | false | 0.0000 | 0.000 | 0.0001 | 0 | 0 |
| confirm | 3 | 3 | 1 | Wild | true | 0.0000 | 0.000 | 0.0026 | 0 | 0 |
| confirm | 3 | 3 | 1 | Blocker | false | 0.0016 | 0.002 | 0.0016 | 0 | 0 |
| confirm | 3 | 3 | 1 | Blocker | true | 0.0000 | 0.000 | 0.0000 | 0 | 0 |
| confirm | 4 | 3 | 1 | Wild | false | 0.0014 | 0.002 | 0.0014 | 0 | 0 |
| confirm | 4 | 3 | 1 | Wild | true | 0.0000 | 0.000 | 0.0005 | 0 | 0 |
| confirm | 4 | 3 | 1 | Blocker | false | 0.0080 | 0.010 | 0.0080 | 0 | 0 |
| confirm | 4 | 3 | 1 | Blocker | true | 0.0024 | 0.004 | 0.0024 | 0 | 0 |
| confirm | 5 | 3 | 1 | Wild | false | 0.0065 | 0.008 | 0.0065 | 0 | 0 |
| confirm | 5 | 3 | 1 | Wild | true | 0.0022 | 0.003 | 0.0024 | 0 | 0 |
| confirm | 5 | 3 | 1 | Blocker | false | 0.0183 | 0.022 | 0.0183 | 0 | 0 |
| confirm | 5 | 3 | 1 | Blocker | true | 0.0071 | 0.008 | 0.0072 | 0 | 0 |
| confirm | 6 | 3 | 1 | Wild | false | 0.0144 | 0.018 | 0.0144 | 0 | 0 |
| confirm | 6 | 3 | 1 | Wild | true | 0.0064 | 0.008 | 0.0069 | 0 | 0 |
| confirm | 6 | 3 | 1 | Blocker | false | 0.0312 | 0.038 | 0.0312 | 0 | 0 |
| confirm | 6 | 3 | 1 | Blocker | true | 0.0133 | 0.017 | 0.0134 | 0 | 0 |
| confirm | 7 | 3 | 1 | Wild | false | 0.0263 | 0.035 | 0.0264 | 0 | 0 |
| confirm | 7 | 3 | 1 | Wild | true | 0.0134 | 0.016 | 0.0138 | 0 | 0 |
| confirm | 7 | 3 | 1 | Blocker | false | 0.0398 | 0.050 | 0.0400 | 0 | 0 |
| confirm | 7 | 3 | 1 | Blocker | true | 0.0197 | 0.025 | 0.0198 | 0 | 0 |
| confirm | 8 | 3 | 1 | Wild | false | 0.0341 | 0.043 | 0.0341 | 0 | 0 |
| confirm | 8 | 3 | 1 | Wild | true | 0.0189 | 0.025 | 0.0190 | 0 | 0 |
| confirm | 8 | 3 | 1 | Blocker | false | 0.0569 | 0.072 | 0.0569 | 0 | 0 |
| confirm | 8 | 3 | 1 | Blocker | true | 0.0322 | 0.040 | 0.0324 | 0 | 0 |
| confirm | 9 | 3 | 1 | Wild | false | 0.0437 | 0.058 | 0.0440 | 0 | 0 |
| confirm | 9 | 3 | 1 | Wild | true | 0.0311 | 0.038 | 0.0314 | 0 | 0 |
| confirm | 9 | 3 | 1 | Blocker | false | 0.0682 | 0.083 | 0.0687 | 0 | 0 |
| confirm | 9 | 3 | 1 | Blocker | true | 0.0440 | 0.055 | 0.0444 | 0 | 0 |
| confirm | 10 | 3 | 1 | Wild | false | 0.0586 | 0.075 | 0.0590 | 0 | 0 |
| confirm | 10 | 3 | 1 | Wild | true | 0.0359 | 0.047 | 0.0363 | 0 | 0 |
| confirm | 10 | 3 | 1 | Blocker | false | 0.0824 | 0.102 | 0.0830 | 0 | 0 |
| confirm | 10 | 3 | 1 | Blocker | true | 0.0477 | 0.061 | 0.0482 | 0 | 0 |

`seenResets` is in THIS section because `VALVE_SEEN_CAP` clears the whole observation
window on overflow: a non-zero count means the valve was **blind** for part of those rounds
rather than merely quiet, and without it a `ResidualLivelock` row cannot say whether the
valve failed to break the cycle or never saw it.

**Bar-sensitivity ladder.** The firing-rate bar is a judgement on a smooth monotone curve,
so here is what every candidate bar would have done, measured from this run's own search
grid. The bar this run used is marked.

TWO ladders, because they do not agree and the difference is the whole argument. The first
applies the FULL selection rule at each candidate bar - including the pool-level margin
correction, which demands a worst-case firing rate of at most HALF the bar - so it is the
pool each bar would actually SELECT. The second is the pool each bar would merely ADMIT on
a bare pass. At 7% they differ: the bar admits k=3 and selects k=6. A ladder showing only
the second would contradict this report's own verdict one section above it.

| candidate bar | pool it SELECTS | marginal | worst firing rate | worst stall rate | min occupancy | worst median first | worst p95 first |
|---|---|---|---|---|---|---|---|
| 40.000% | k=2, j=1, 8.0s deadline | false | 15.500% | 0.100% | 0.789 | 14.5s | 21.8s |
| 20.000% | k=3, j=1, 8.0s deadline | false | 9.400% | 0.000% | 0.825 | 16.4s | 23.5s | **<- the bar this run used**
| 15.000% | k=3, j=1, 3.0s deadline | false | 7.400% | 0.200% | 0.827 | 16.2s | 23.8s |
| 10.000% | k=4, j=1, 5.0s deadline | false | 4.900% | 0.000% | 0.838 | 18.2s | 26.2s |
| 7.000% | k=6, j=1, 8.0s deadline | false | 2.500% | 0.000% | 0.856 | 20.9s | 32.1s |
| 5.000% | k=6, j=1, 8.0s deadline | false | 2.500% | 0.000% | 0.856 | 20.9s | 32.1s |
| 4.000% | k=6, j=1, 5.0s deadline | false | 1.800% | 0.100% | 0.857 | 21.4s | 32.0s |
| 3.000% | k=6, j=1, 8.0s deadline | true | 2.500% | 0.000% | 0.856 | 20.9s | 32.1s |
| 2.000% | k=6, j=1, 5.0s deadline | true | 1.800% | 0.100% | 0.857 | 21.4s | 32.0s |
| 1.000% | none in the searched grid | - | - | - | - | - | - |

The stall, occupancy and pacing columns above are the SEARCH grid's 1,000-round cells,
so a single stalled round there reads as 0.100%; only the selected pool was confirmed at
10,000 rounds. Read them as the shape of the trade, not as a residual measurement.

And the same ladder on a bare pass, with no margin, for contrast:

| candidate bar | smallest pool whose worst cell clears it | worst firing rate there |
|---|---|---|
| 40.000% | k=1, j=1 | 32.300% |
| 20.000% | k=2, j=1 | 14.000% | **<- selected bar**
| 15.000% | k=2, j=1 | 14.000% |
| 10.000% | k=3, j=1 | 6.800% |
| 7.000% | k=3, j=1 | 6.800% |
| 5.000% | k=4, j=1 | 4.400% |
| 4.000% | k=6, j=1 | 2.100% |
| 3.000% | k=6, j=1 | 2.100% |
| 2.000% | k=6, j=1 | 1.800% |
| 1.000% | none in the searched grid | - |

### Triage

TRIAGE PENDING - run --stage triage and fold the rows in here

Which of `CapArtifact` and `ResidualLivelock` the residual turns out to be decides whether
the honest claim is "zero stalls" or "zero stalls for the selected pool". 02-09 measured
`valveSeenResetsTotal = 0` and `hitActionCap = false` across 6,000 gated rounds - every
gated stall there was a 300s `time-cap` round, which a raised ACTION cap cannot rescue.

## 5. Stall rate versus auto-pass timeout

**Margin evidence, not what the gate rests on.** Amendment A7 moved the zero-stall result
onto the engine's valve, so the auto-pass is a secondary mitigation and its deadline is a
product choice (CARD-16 benches a player after repeated strikes, so a short deadline would
be striking ordinary players several times a round).

| deadline | cells | worst stall | worst firing rate | total auto-passes | auto-pass rate |
|---|---|---|---|---|---|
| 1.5 | 216 | 1.0000 | 1.0000 | 38516 | 0.0010 |
| 3.0 | 216 | 1.0000 | 1.0000 | 58 | 0.0000 |
| 5.0 | 216 | 0.9990 | 1.0000 | 2 | 0.0000 |
| 8.0 | 216 | 1.0000 | 1.0000 | 0 | 0.0000 |
| inf | 216 | 1.0000 | 1.0000 | 0 | 0.0000 |

**Auto-pass probe** at a 1.0s deadline, N=10, k=2, j=1 Wild, 1000 rounds: `autoPassRate = 0.0138` (4332 auto-passes over 314398 actions), against the `AUTO_PASS_PROBE_MIN_RATE` bar of 0.0050. The probe exists because at a realistic shipped deadline the auto-pass correctly fires almost never, so its mechanism check has to be a probe rather than a bar on the gated cells.

## 6. Documented negative results

`k = 0` and `j = 0` are swept and REPORTED, never skipped (amendment A5). A dead pool
excluded by a silent skip is a dead pool nobody can see in the artefact.

(N=10, churn=false, 5.0s deadline - one slice; every cell is in `02-sweep-data.json`.)

| k | j | mode | circulation | stall | occupancy | DeadPool | Unsat | Livelock | Cap | bars |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | Wild | 0 | 0.0000 | 0.000 | 1000 | 0 | 0 | 0 | no-completions |
| 0 | 0 | Blocker | 0 | 0.0000 | 0.000 | 1000 | 0 | 0 | 0 | no-completions |
| 0 | 1 | Wild | 1 | 0.1540 | 0.185 | 0 | 0 | 0 | 154 | stalls,cleared-fraction,occupancy,valve-rate |
| 0 | 1 | Blocker | 1 | 0.9990 | 0.112 | 0 | 0 | 0 | 999 | stalls,cleared-fraction,median-first,p95-first,occupancy,valve-rate |
| 0 | 2 | Wild | 2 | 0.0030 | 0.356 | 0 | 0 | 0 | 3 | occupancy,valve-rate |
| 0 | 2 | Blocker | 2 | 0.9510 | 0.238 | 0 | 0 | 0 | 951 | stalls,cleared-fraction,median-first,p95-first,occupancy,valve-rate |
| 1 | 0 | Wild | 4 | 0.0000 | 0.556 | 0 | 0 | 0 | 0 | occupancy,valve-rate |
| 1 | 0 | Blocker | 4 | 0.0000 | 0.554 | 0 | 0 | 0 | 0 | occupancy,valve-rate |
| 2 | 0 | Wild | 8 | 0.0010 | 0.763 | 0 | 0 | 0 | 1 | - |
| 2 | 0 | Blocker | 8 | 0.0000 | 0.762 | 0 | 0 | 0 | 0 | - |
| 3 | 0 | Wild | 12 | 0.0000 | 0.822 | 0 | 0 | 0 | 0 | - |
| 3 | 0 | Blocker | 12 | 0.0010 | 0.822 | 0 | 0 | 0 | 1 | - |
| 4 | 0 | Wild | 16 | 0.0010 | 0.837 | 0 | 0 | 0 | 1 | - |
| 4 | 0 | Blocker | 16 | 0.0000 | 0.835 | 0 | 0 | 0 | 0 | - |
| 6 | 0 | Wild | 24 | 0.0000 | 0.855 | 0 | 0 | 0 | 0 | - |
| 6 | 0 | Blocker | 24 | 0.0000 | 0.857 | 0 | 0 | 0 | 0 | - |

The `k=0, j=0` rows are the **dead pool**: circulation `4k + j = 0`, so no card can move
and `Simulator.runRound` returns `DeadPool` with zero actions. The wild/blocker **cliff**
at `k = 0` is amendment A4's reason for the `k >= 1` floor: with one card circulating, a
Blocker joker cannot complete anything, so the joker flag becomes a cliff rather than a
flag and CARD-12's "both variants behind a flag" would be false. `j = 0` is the comparison
CONTEXT's literal tiebreak would have selected; it is measured here and NOT selected,
because PROJECT.md records the jokers as a design property.

## 7. Occupancy

This is the table that justifies amendment A2's third bar (mean occupancy >= 0.600).

(N=10, Wild, churn=false, 5.0s deadline.)

| k | j | circulation | occupancy | passes the occupancy bar |
|---|---|---|---|---|
| 0 | 0 | 0 | 0.000 | false |
| 0 | 1 | 1 | 0.185 | false |
| 0 | 2 | 2 | 0.356 | false |
| 1 | 0 | 4 | 0.556 | false |
| 1 | 1 | 5 | 0.635 | true |
| 1 | 2 | 6 | 0.694 | true |
| 2 | 0 | 8 | 0.763 | true |
| 2 | 1 | 9 | 0.788 | true |
| 2 | 2 | 10 | 0.806 | true |
| 3 | 0 | 12 | 0.822 | true |
| 3 | 1 | 13 | 0.825 | true |
| 3 | 2 | 14 | 0.828 | true |
| 4 | 0 | 16 | 0.837 | true |
| 4 | 1 | 17 | 0.838 | true |
| 4 | 2 | 18 | 0.838 | true |
| 6 | 0 | 24 | 0.855 | true |
| 6 | 1 | 25 | 0.857 | true |
| 6 | 2 | 26 | 0.857 | true |

The dead-table cell sits in this table next to the selection on purpose: `k=0, j=1`
measures ~0.17 occupancy at ten players and would pass every other bar while being barely
a game.

## 8. Carried debt

Verbatim from `02-VALIDATION.md`'s Manual-Only Verifications table:

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Whether a bot's reaction-time distribution represents real humans (V-35) | CARD-11 | Unverifiable without real playtests; carried as debt since project init | Calibrate in Phase 4/6 against live sessions |
| Whether humans deviate from pure greed often enough for the pacing half of G1 to mean anything (A4) | CARD-11 | Same class as V-35, and newly surfaced by this phase's research | Measure deviation rate at the first real playtest |

**Scope note, verbatim.** G1's **solvability** half is a theorem and needs no playtest - it
does not depend on the bot model at all. Its **pacing** half measures the bot, not the game,
until the two rows above are closed. Do not let a green pacing number read as a verified
claim about real players.

**Amendment A7 retired the old load-bearing assumption.** The zero-stall result no longer
depends on how often humans deviate from pure greed, because the engine's valve deviates
for them. What remains unverified is therefore the **pacing** model, not the solvability
claim - and amendment A8 made that valve far MORE load-bearing than A7 claimed: it rescues
roughly one round in ten at a full roster at the tight pools, not one in four hundred.

## 9. Reproduction

```
lune run scripts/sim/sweep.luau -- -- --stage both
```

- base seed: 21000, one block of 100000 per cell (cell i runs seeds base + i*block + 1..rounds)
- stages run: search, mechanism, confirm
- out: .planning/phases/02-card-engine-and-pacing-simulator
- round cap: 300s; Solvability action cap: 100000
- lune: Lune 0.11.1+740
- every non-cleared round's seed is carried in `02-sweep-data.json` as `failingSeeds`
  (capped at the first 20 per cell) and `hitActionCapSeeds`, so any row here can be replayed.

### The selection rule as implemented

1. k >= 1 (amendment A4: at k = 0 the Blocker variant is a cliff, not a flag)
2. j >= 1 (PROJECT.md's Key Decisions: jokers exist; the sweep CLEARS j, it does not minimise it)
3. every bar passes in BOTH joker modes and BOTH churn variants, at every N searched (OQ-D)
4. reject any pool whose valveFiringRate exceeds 0.2 (amendment A8, re-derived from the measured curve)
5. smallest passing pool: fewest extra ranks k first, then fewest jokers j; ties on the lower valve firing rate
6. auto-pass deadline: the largest FINITE candidate that clears, WITH MARGIN where any pool can

Departures from CONTEXT's literal rule, recorded rather than hidden:

- CONTEXT's literal 'then fewest jokers' tiebreak returns j = 0 and deletes the jokers. PROJECT.md's Key Decisions table records them as a design property and CLAUDE.md says PROJECT.md wins, so the search floor is j >= 1 and j = 0 is measured and reported as a comparison (report section 6).
- Amendment A8 replaced the ZERO stall bar with an explicit residual ceiling of 0.005 and the 1% valve-rate bar with 0.2; Simulator.evaluateBars is unchanged and its verdict is recorded on every cell as lockedVerdict/lockedFailures.
- Margin is applied at the POOL level as well as to the auto-pass walk. Applied only to the walk, the 'smallest passing pool' rule reports marginal = true at every bar value by construction, because successive k on the measured curve differ by less than the factor of two margin demands.

### Every candidate considered, with its named rejections

| k | j | deadline | cells | passed | with margin | rejected by | named failures | margin shortfalls | worst stall | worst firing rate | worst medFirst | worst p95 | worst occupancy |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 1.5 | 12 | false | false | k-floor | no-completions | no-completions | 0.0000 | 0.0000 | inf | inf | 0.000 |
| 0 | 0 | 3.0 | 12 | false | false | k-floor | no-completions | no-completions | 0.0000 | 0.0000 | inf | inf | 0.000 |
| 0 | 0 | 5.0 | 12 | false | false | k-floor | no-completions | no-completions | 0.0000 | 0.0000 | inf | inf | 0.000 |
| 0 | 0 | 8.0 | 12 | false | false | k-floor | no-completions | no-completions | 0.0000 | 0.0000 | inf | inf | 0.000 |
| 0 | 0 | inf | 12 | false | false | k-floor | no-completions | no-completions | 0.0000 | 0.0000 | inf | inf | 0.000 |
| 0 | 1 | 1.5 | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 1.0000 | 1.0000 | 273.1 | 296.6 | 0.112 |
| 0 | 1 | 3.0 | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 1.0000 | 1.0000 | 276.8 | 297.2 | 0.112 |
| 0 | 1 | 5.0 | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 0.9990 | 1.0000 | 276.3 | 297.8 | 0.112 |
| 0 | 1 | 8.0 | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 1.0000 | 1.0000 | 277.3 | 297.6 | 0.112 |
| 0 | 1 | inf | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 1.0000 | 1.0000 | 274.0 | 297.6 | 0.112 |
| 0 | 2 | 1.5 | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 0.9360 | 1.0000 | 201.9 | 279.8 | 0.240 |
| 0 | 2 | 3.0 | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 0.9560 | 1.0000 | 215.1 | 287.4 | 0.236 |
| 0 | 2 | 5.0 | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 0.9510 | 1.0000 | 210.7 | 283.6 | 0.238 |
| 0 | 2 | 8.0 | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 0.9510 | 1.0000 | 213.1 | 285.9 | 0.236 |
| 0 | 2 | inf | 12 | false | false | k-floor | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | cleared-fraction,median-first,occupancy,p95-first,stalls,valve-rate | 0.9480 | 1.0000 | 207.9 | 283.0 | 0.237 |
| 1 | 0 | 1.5 | 12 | false | false | j-floor | occupancy,valve-rate | occupancy,valve-rate | 0.0000 | 0.3290 | 14.8 | 24.5 | 0.551 |
| 1 | 0 | 3.0 | 12 | false | false | j-floor | occupancy,valve-rate | occupancy,valve-rate | 0.0010 | 0.3700 | 14.8 | 24.6 | 0.555 |
| 1 | 0 | 5.0 | 12 | false | false | j-floor | occupancy,valve-rate | occupancy,valve-rate | 0.0000 | 0.3690 | 14.7 | 24.3 | 0.554 |
| 1 | 0 | 8.0 | 12 | false | false | j-floor | occupancy,valve-rate | occupancy,valve-rate | 0.0000 | 0.4000 | 14.9 | 24.9 | 0.557 |
| 1 | 0 | inf | 12 | false | false | j-floor | occupancy,valve-rate | occupancy,valve-rate | 0.0000 | 0.3660 | 15.0 | 24.5 | 0.555 |
| 1 | 1 | 1.5 | 12 | false | false | bars | valve-rate | occupancy,valve-rate | 0.0010 | 0.3230 | 15.3 | 25.2 | 0.628 |
| 1 | 1 | 3.0 | 12 | false | false | bars | valve-rate | occupancy,valve-rate | 0.0010 | 0.3600 | 15.3 | 25.2 | 0.635 |
| 1 | 1 | 5.0 | 12 | false | false | bars | valve-rate | occupancy,valve-rate | 0.0020 | 0.3490 | 15.6 | 25.4 | 0.629 |
| 1 | 1 | 8.0 | 12 | false | false | bars | valve-rate | occupancy,valve-rate | 0.0000 | 0.3410 | 15.3 | 24.6 | 0.634 |
| 1 | 1 | inf | 12 | false | false | auto-pass-disabled | valve-rate | occupancy,valve-rate | 0.0010 | 0.3720 | 15.7 | 26.1 | 0.628 |
| 1 | 2 | 1.5 | 12 | false | false | bars | valve-rate | valve-rate | 0.0010 | 0.2940 | 16.1 | 26.4 | 0.696 |
| 1 | 2 | 3.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0000 | 0.3820 | 16.5 | 25.2 | 0.696 |
| 1 | 2 | 5.0 | 12 | false | false | bars | valve-rate | cleared-fraction,stalls,valve-rate | 0.0030 | 0.3740 | 16.2 | 26.0 | 0.694 |
| 1 | 2 | 8.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0020 | 0.3460 | 16.2 | 26.1 | 0.690 |
| 1 | 2 | inf | 12 | false | false | auto-pass-disabled | valve-rate | valve-rate | 0.0010 | 0.3560 | 16.2 | 26.0 | 0.692 |
| 2 | 0 | 1.5 | 12 | true | false | j-floor | - | valve-rate | 0.0000 | 0.1410 | 13.5 | 20.1 | 0.764 |
| 2 | 0 | 3.0 | 12 | true | false | j-floor | - | valve-rate | 0.0000 | 0.1650 | 13.6 | 20.4 | 0.763 |
| 2 | 0 | 5.0 | 12 | true | false | j-floor | - | valve-rate | 0.0010 | 0.1510 | 13.3 | 19.9 | 0.762 |
| 2 | 0 | 8.0 | 12 | true | false | j-floor | - | valve-rate | 0.0020 | 0.1630 | 13.8 | 20.2 | 0.764 |
| 2 | 0 | inf | 12 | true | false | j-floor | - | valve-rate | 0.0010 | 0.1740 | 13.5 | 20.2 | 0.764 |
| 2 | 1 | 1.5 | 12 | true | false | - | - | valve-rate | 0.0010 | 0.1400 | 14.6 | 21.5 | 0.789 |
| 2 | 1 | 3.0 | 12 | true | false | - | - | valve-rate | 0.0020 | 0.1550 | 14.4 | 21.8 | 0.792 |
| 2 | 1 | 5.0 | 12 | true | false | - | - | valve-rate | 0.0010 | 0.1460 | 14.2 | 21.3 | 0.788 |
| 2 | 1 | 8.0 | 12 | true | false | - | - | valve-rate | 0.0010 | 0.1550 | 14.5 | 21.8 | 0.789 |
| 2 | 1 | inf | 12 | true | false | auto-pass-disabled | - | cleared-fraction,stalls,valve-rate | 0.0030 | 0.1540 | 14.5 | 21.2 | 0.790 |
| 2 | 2 | 1.5 | 12 | true | false | - | - | valve-rate | 0.0020 | 0.1260 | 15.5 | 22.4 | 0.806 |
| 2 | 2 | 3.0 | 12 | true | false | - | - | valve-rate | 0.0010 | 0.1750 | 15.4 | 22.9 | 0.805 |
| 2 | 2 | 5.0 | 12 | true | false | - | - | valve-rate | 0.0020 | 0.1610 | 15.7 | 23.0 | 0.806 |
| 2 | 2 | 8.0 | 12 | true | false | - | - | cleared-fraction,stalls,valve-rate | 0.0030 | 0.1390 | 15.5 | 23.5 | 0.806 |
| 2 | 2 | inf | 12 | true | false | auto-pass-disabled | - | cleared-fraction,stalls,valve-rate | 0.0030 | 0.1580 | 15.6 | 22.6 | 0.806 |
| 3 | 0 | 1.5 | 12 | true | true | j-floor | - | - | 0.0010 | 0.0780 | 15.0 | 22.5 | 0.819 |
| 3 | 0 | 3.0 | 12 | true | false | j-floor | - | cleared-fraction,stalls | 0.0030 | 0.0800 | 15.2 | 22.4 | 0.820 |
| 3 | 0 | 5.0 | 12 | true | true | j-floor | - | - | 0.0010 | 0.0860 | 15.1 | 22.6 | 0.822 |
| 3 | 0 | 8.0 | 12 | true | true | j-floor | - | - | 0.0020 | 0.0950 | 14.8 | 22.3 | 0.821 |
| 3 | 0 | inf | 12 | true | true | j-floor | - | - | 0.0010 | 0.0900 | 15.1 | 22.6 | 0.820 |
| 3 | 1 | 1.5 | 12 | true | true | - | - | - | 0.0000 | 0.0680 | 16.2 | 24.2 | 0.826 |
| 3 | 1 | 3.0 | 12 | true | true | - | - | - | 0.0020 | 0.0740 | 16.2 | 23.8 | 0.827 |
| 3 | 1 | 5.0 | 12 | true | true | - | - | - | 0.0010 | 0.0860 | 16.3 | 23.0 | 0.825 |
| 3 | 1 | 8.0 | 12 | true | true | - | - | - | 0.0000 | 0.0940 | 16.4 | 23.5 | 0.825 |
| 3 | 1 | inf | 12 | true | true | auto-pass-disabled | - | - | 0.0010 | 0.0750 | 16.1 | 23.1 | 0.824 |
| 3 | 2 | 1.5 | 12 | true | true | - | - | - | 0.0000 | 0.0620 | 17.3 | 25.2 | 0.828 |
| 3 | 2 | 3.0 | 12 | true | true | - | - | - | 0.0020 | 0.0620 | 17.5 | 25.0 | 0.826 |
| 3 | 2 | 5.0 | 12 | true | false | - | - | cleared-fraction,stalls | 0.0030 | 0.0820 | 17.3 | 24.9 | 0.828 |
| 3 | 2 | 8.0 | 12 | true | true | - | - | - | 0.0010 | 0.0880 | 17.2 | 25.0 | 0.828 |
| 3 | 2 | inf | 12 | true | true | auto-pass-disabled | - | - | 0.0010 | 0.0720 | 17.1 | 25.1 | 0.829 |
| 4 | 0 | 1.5 | 12 | true | true | j-floor | - | - | 0.0000 | 0.0600 | 17.2 | 25.4 | 0.838 |
| 4 | 0 | 3.0 | 12 | true | true | j-floor | - | - | 0.0000 | 0.0570 | 17.4 | 25.3 | 0.836 |
| 4 | 0 | 5.0 | 12 | true | true | j-floor | - | - | 0.0010 | 0.0570 | 17.1 | 25.4 | 0.835 |
| 4 | 0 | 8.0 | 12 | true | true | j-floor | - | - | 0.0020 | 0.0610 | 17.5 | 25.3 | 0.836 |
| 4 | 0 | inf | 12 | true | true | j-floor | - | - | 0.0000 | 0.0500 | 17.3 | 25.3 | 0.835 |
| 4 | 1 | 1.5 | 12 | true | true | - | - | - | 0.0010 | 0.0440 | 18.1 | 27.3 | 0.839 |
| 4 | 1 | 3.0 | 12 | true | true | - | - | - | 0.0010 | 0.0550 | 18.1 | 26.9 | 0.837 |
| 4 | 1 | 5.0 | 12 | true | true | - | - | - | 0.0000 | 0.0490 | 18.2 | 26.2 | 0.838 |
| 4 | 1 | 8.0 | 12 | true | true | - | - | - | 0.0010 | 0.0610 | 18.5 | 26.8 | 0.837 |
| 4 | 1 | inf | 12 | true | true | auto-pass-disabled | - | - | 0.0020 | 0.0420 | 17.9 | 27.2 | 0.839 |
| 4 | 2 | 1.5 | 12 | true | true | - | - | - | 0.0000 | 0.0420 | 19.1 | 28.2 | 0.838 |
| 4 | 2 | 3.0 | 12 | true | true | - | - | - | 0.0020 | 0.0560 | 19.4 | 27.5 | 0.838 |
| 4 | 2 | 5.0 | 12 | true | true | - | - | - | 0.0010 | 0.0580 | 18.9 | 27.2 | 0.838 |
| 4 | 2 | 8.0 | 12 | true | true | - | - | - | 0.0010 | 0.0430 | 19.0 | 27.9 | 0.839 |
| 4 | 2 | inf | 12 | true | true | auto-pass-disabled | - | - | 0.0010 | 0.0550 | 19.0 | 27.6 | 0.839 |
| 6 | 0 | 1.5 | 12 | true | true | j-floor | - | - | 0.0000 | 0.0150 | 20.8 | 30.9 | 0.856 |
| 6 | 0 | 3.0 | 12 | true | true | j-floor | - | - | 0.0000 | 0.0260 | 21.2 | 31.0 | 0.855 |
| 6 | 0 | 5.0 | 12 | true | true | j-floor | - | - | 0.0000 | 0.0320 | 20.7 | 30.6 | 0.855 |
| 6 | 0 | 8.0 | 12 | true | true | j-floor | - | - | 0.0000 | 0.0240 | 21.0 | 31.2 | 0.855 |
| 6 | 0 | inf | 12 | true | true | j-floor | - | - | 0.0000 | 0.0250 | 20.7 | 30.5 | 0.856 |
| 6 | 1 | 1.5 | 12 | true | true | - | - | - | 0.0010 | 0.0210 | 21.0 | 31.8 | 0.859 |
| 6 | 1 | 3.0 | 12 | true | true | - | - | - | 0.0000 | 0.0210 | 21.8 | 32.3 | 0.857 |
| 6 | 1 | 5.0 | 12 | true | true | - | - | - | 0.0010 | 0.0180 | 21.4 | 32.0 | 0.857 |
| 6 | 1 | 8.0 | 12 | true | true | - | - | - | 0.0000 | 0.0250 | 20.9 | 32.1 | 0.856 |
| 6 | 1 | inf | 12 | true | true | auto-pass-disabled | - | - | 0.0010 | 0.0180 | 21.0 | 31.9 | 0.857 |
| 6 | 2 | 1.5 | 12 | true | true | - | - | - | 0.0010 | 0.0200 | 22.5 | 33.4 | 0.858 |
| 6 | 2 | 3.0 | 12 | true | true | - | - | - | 0.0010 | 0.0280 | 21.8 | 32.4 | 0.857 |
| 6 | 2 | 5.0 | 12 | true | true | - | - | - | 0.0000 | 0.0190 | 22.0 | 32.7 | 0.857 |
| 6 | 2 | 8.0 | 12 | true | true | - | - | - | 0.0010 | 0.0220 | 22.1 | 32.9 | 0.856 |
| 6 | 2 | inf | 12 | true | true | auto-pass-disabled | - | - | 0.0000 | 0.0320 | 21.2 | 32.3 | 0.857 |

