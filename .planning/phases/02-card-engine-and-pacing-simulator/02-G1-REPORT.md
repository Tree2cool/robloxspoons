# Phase 2 Gate G1 Report

Generated 2026-11-04T01:26:24Z by `scripts/sim/sweep.luau`.

## 1. Verdict

**Selected pool: k = 6 extra ranks, j = 1 joker(s), auto-pass deadline 8.0s.**
Joker mode is a FLAG, not a selection: Wild and Blocker both clear every
bar at every N, and `Wild` is the default PROJECT.md records.

Marginal: **false**

| bar | measured worst case over the confirmed cells | bar | with margin |
|---|---|---|---|
| stalls | 0.040% | <= 0.500% | <= 0.250% |
| cleared fraction | see section 3 | = 1 - the stall ceiling | |
| median first | 21.2s | <= 45s | <= 36.0s |
| p95 first | 31.8s | <= 120s | <= 96.0s |
| occupancy | 0.856 | >= 0.600 | >= 0.660 |
| valve firing rate | 2.580% | <= 7.000% | <= 3.500% |

**G1: PASSES** on this evidence - **14 stalled round(s) observed for the selected pool in 320000 gated rounds** at 10000 rounds per cell - 0.004% aggregate, worst cell 0.040%, against a 0.500% ceiling. That is the claim, in its honest form: a measured property of a SELECTED configuration, never an unconditional property of the engine. The measured residual is printed above rather than rounded away, and section 4b says whether it was a cap artefact or a real one.

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
| 5 | valve firing rate | <= 7.000% of rounds | amendment A8 resolution 1, re-derived from the measured curve. See the bar-sensitivity ladder in section 4b |

`Simulator.evaluateBars` is UNCHANGED and is evaluated for every Pacing cell alongside
these; its verdict rides on each cell in `02-sweep-data.json` as `lockedVerdict` and
`lockedFailures`, so the locked-constant view is in the artefact and can be read directly.

## 3. Confirmation stage

| N | mode | churn | stall | medFirst | p95First | medAll | p95All | occupancy | ramp | autoPass | dealAttempt mean/max | Cleared/Unsat/Livelock/Cap/Shortfall/Dead | bars | locked bars |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | Wild | false | 0.0000 | 11.2 | 21.9 | 11.2 | 21.9 | 0.929 | 1.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 3 | Wild | true | 0.0000 | 13.8 | 27.6 | 13.8 | 27.6 | 0.941 | 1.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 3 | Blocker | false | 0.0000 | 15.0 | 25.5 | 15.0 | 25.5 | 0.944 | 1.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 3 | Blocker | true | 0.0000 | 19.9 | 30.3 | 19.9 | 30.3 | 0.957 | 1.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 4 | Wild | false | 0.0000 | 11.5 | 22.0 | 18.7 | 28.5 | 0.919 | 2.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 4 | Wild | true | 0.0000 | 13.0 | 25.3 | 23.1 | 34.7 | 0.933 | 2.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 4 | Blocker | false | 0.0000 | 14.9 | 25.2 | 21.6 | 30.1 | 0.927 | 2.5 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 4 | Blocker | true | 0.0000 | 17.8 | 29.2 | 26.8 | 35.6 | 0.941 | 2.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 5 | Wild | false | 0.0000 | 12.5 | 22.8 | 24.1 | 33.6 | 0.905 | 3.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 5 | Wild | true | 0.0000 | 13.4 | 25.1 | 28.9 | 39.8 | 0.919 | 3.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 5 | Blocker | false | 0.0000 | 15.9 | 25.9 | 26.5 | 34.3 | 0.911 | 3.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 5 | Blocker | true | 0.0000 | 17.4 | 28.9 | 31.0 | 40.1 | 0.926 | 3.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 6 | Wild | false | 0.0000 | 13.4 | 23.4 | 28.4 | 37.4 | 0.893 | 4.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 6 | Wild | true | 0.0000 | 13.9 | 25.3 | 33.1 | 44.9 | 0.908 | 4.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 6 | Blocker | false | 0.0000 | 16.5 | 26.6 | 30.0 | 38.1 | 0.897 | 4.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 6 | Blocker | true | 0.0000 | 17.9 | 28.9 | 34.6 | 44.2 | 0.913 | 4.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 7 | Wild | false | 0.0000 | 14.4 | 24.7 | 32.0 | 42.1 | 0.882 | 5.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 7 | Wild | true | 0.0000 | 14.8 | 26.1 | 36.7 | 49.3 | 0.898 | 5.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 7 | Blocker | false | 0.0002 | 17.6 | 27.4 | 33.1 | 41.8 | 0.885 | 5.4 | 0.0000 | 1.0/2 | 9998/0/0/2/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 7 | Blocker | true | 0.0001 | 18.4 | 29.1 | 38.2 | 48.3 | 0.903 | 5.4 | 0.0000 | 1.0/2 | 9999/0/0/1/0/0 | pass | stalls,cleared-fraction |
| 8 | Wild | false | 0.0000 | 15.4 | 25.7 | 35.3 | 45.9 | 0.872 | 6.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 8 | Wild | true | 0.0000 | 15.6 | 26.9 | 40.7 | 54.0 | 0.889 | 6.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 8 | Blocker | false | 0.0001 | 18.7 | 28.4 | 36.4 | 45.9 | 0.875 | 6.4 | 0.0000 | 1.0/2 | 9999/0/0/1/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 8 | Blocker | true | 0.0000 | 19.4 | 29.9 | 41.5 | 52.5 | 0.893 | 6.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | pass |
| 9 | Wild | false | 0.0000 | 16.6 | 27.3 | 38.6 | 50.2 | 0.864 | 7.4 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 9 | Wild | true | 0.0000 | 16.5 | 28.3 | 44.1 | 58.2 | 0.882 | 7.3 | 0.0000 | 1.0/2 | 10000/0/0/0/0/0 | pass | valve-rate |
| 9 | Blocker | false | 0.0001 | 20.1 | 29.4 | 39.8 | 50.5 | 0.867 | 7.4 | 0.0000 | 1.0/2 | 9999/0/0/1/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 9 | Blocker | true | 0.0001 | 20.4 | 30.8 | 44.9 | 56.8 | 0.885 | 7.4 | 0.0000 | 1.0/2 | 9999/0/0/1/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 10 | Wild | false | 0.0001 | 17.4 | 28.5 | 41.9 | 55.3 | 0.856 | 8.4 | 0.0000 | 1.0/2 | 9999/0/0/1/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 10 | Wild | true | 0.0004 | 17.7 | 29.4 | 47.7 | 62.6 | 0.875 | 8.3 | 0.0000 | 1.0/2 | 9996/0/0/4/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 10 | Blocker | false | 0.0001 | 21.0 | 30.5 | 43.1 | 55.0 | 0.859 | 8.3 | 0.0000 | 1.0/2 | 9999/0/0/1/0/0 | pass | stalls,cleared-fraction,valve-rate |
| 10 | Blocker | true | 0.0002 | 21.2 | 31.8 | 48.5 | 61.1 | 0.878 | 8.3 | 0.0000 | 1.0/2 | 9998/0/0/2/0/0 | pass | stalls,cleared-fraction,valve-rate |

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
| confirm | 10 | 6 | 1 | Wild | false | 10000 | 0.0180 | 180 | 0 |
| confirm | 10 | 6 | 1 | Wild | true | 10000 | 0.0121 | 121 | 0 |
| confirm | 10 | 6 | 1 | Blocker | false | 10000 | 0.0242 | 242 | 0 |
| confirm | 10 | 6 | 1 | Blocker | true | 10000 | 0.0168 | 168 | 0 |

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
| confirm | 3 | 6 | 1 | Wild | false | 0.0000 | 0.000 | 0.0163 | 0 | 0 |
| confirm | 3 | 6 | 1 | Wild | true | 0.0000 | 0.000 | 0.0422 | 0 | 0 |
| confirm | 3 | 6 | 1 | Blocker | false | 0.0009 | 0.001 | 0.0574 | 0 | 0 |
| confirm | 3 | 6 | 1 | Blocker | true | 0.0000 | 0.000 | 0.1022 | 0 | 0 |
| confirm | 4 | 6 | 1 | Wild | false | 0.0001 | 0.000 | 0.0163 | 0 | 0 |
| confirm | 4 | 6 | 1 | Wild | true | 0.0000 | 0.000 | 0.0358 | 0 | 0 |
| confirm | 4 | 6 | 1 | Blocker | false | 0.0018 | 0.002 | 0.0373 | 0 | 0 |
| confirm | 4 | 6 | 1 | Blocker | true | 0.0004 | 0.000 | 0.0543 | 0 | 0 |
| confirm | 5 | 6 | 1 | Wild | false | 0.0015 | 0.002 | 0.0154 | 0 | 0 |
| confirm | 5 | 6 | 1 | Wild | true | 0.0006 | 0.001 | 0.0233 | 0 | 0 |
| confirm | 5 | 6 | 1 | Blocker | false | 0.0035 | 0.005 | 0.0335 | 0 | 0 |
| confirm | 5 | 6 | 1 | Blocker | true | 0.0016 | 0.002 | 0.0392 | 0 | 0 |
| confirm | 6 | 6 | 1 | Wild | false | 0.0028 | 0.003 | 0.0150 | 0 | 0 |
| confirm | 6 | 6 | 1 | Wild | true | 0.0015 | 0.002 | 0.0224 | 0 | 0 |
| confirm | 6 | 6 | 1 | Blocker | false | 0.0068 | 0.008 | 0.0353 | 0 | 0 |
| confirm | 6 | 6 | 1 | Blocker | true | 0.0034 | 0.004 | 0.0293 | 0 | 0 |
| confirm | 7 | 6 | 1 | Wild | false | 0.0072 | 0.009 | 0.0208 | 0 | 0 |
| confirm | 7 | 6 | 1 | Wild | true | 0.0035 | 0.004 | 0.0191 | 0 | 0 |
| confirm | 7 | 6 | 1 | Blocker | false | 0.0108 | 0.013 | 0.0356 | 0 | 0 |
| confirm | 7 | 6 | 1 | Blocker | true | 0.0064 | 0.008 | 0.0262 | 0 | 0 |
| confirm | 8 | 6 | 1 | Wild | false | 0.0087 | 0.011 | 0.0222 | 0 | 0 |
| confirm | 8 | 6 | 1 | Wild | true | 0.0060 | 0.007 | 0.0217 | 0 | 0 |
| confirm | 8 | 6 | 1 | Blocker | false | 0.0137 | 0.017 | 0.0417 | 0 | 0 |
| confirm | 8 | 6 | 1 | Blocker | true | 0.0093 | 0.012 | 0.0270 | 0 | 0 |
| confirm | 9 | 6 | 1 | Wild | false | 0.0160 | 0.019 | 0.0327 | 0 | 0 |
| confirm | 9 | 6 | 1 | Wild | true | 0.0107 | 0.013 | 0.0258 | 0 | 0 |
| confirm | 9 | 6 | 1 | Blocker | false | 0.0197 | 0.025 | 0.0491 | 0 | 0 |
| confirm | 9 | 6 | 1 | Blocker | true | 0.0137 | 0.017 | 0.0339 | 0 | 0 |
| confirm | 10 | 6 | 1 | Wild | false | 0.0177 | 0.022 | 0.0358 | 0 | 0 |
| confirm | 10 | 6 | 1 | Wild | true | 0.0115 | 0.015 | 0.0259 | 0 | 0 |
| confirm | 10 | 6 | 1 | Blocker | false | 0.0258 | 0.032 | 0.0617 | 0 | 0 |
| confirm | 10 | 6 | 1 | Blocker | true | 0.0169 | 0.021 | 0.0365 | 0 | 0 |

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
| 20.000% | k=3, j=1, 8.0s deadline | false | 9.400% | 0.000% | 0.825 | 16.4s | 23.5s |
| 15.000% | k=3, j=1, 3.0s deadline | false | 7.400% | 0.200% | 0.827 | 16.2s | 23.8s |
| 10.000% | k=4, j=1, 5.0s deadline | false | 4.900% | 0.000% | 0.838 | 18.2s | 26.2s |
| 7.000% | k=6, j=1, 8.0s deadline | false | 2.500% | 0.000% | 0.856 | 20.9s | 32.1s | **<- the bar this run used**
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
| 20.000% | k=2, j=1 | 14.000% |
| 15.000% | k=2, j=1 | 14.000% |
| 10.000% | k=3, j=1 | 6.800% |
| 7.000% | k=3, j=1 | 6.800% | **<- selected bar**
| 5.000% | k=4, j=1 | 4.400% |
| 4.000% | k=6, j=1 | 2.100% |
| 3.000% | k=6, j=1 | 2.100% |
| 2.000% | k=6, j=1 | 1.800% |
| 1.000% | none in the searched grid | - |

### Triage

**No round ended on the action cap; nothing to triage.**

`hitActionCapSeeds` - the `capArtifactCandidates` the triage stage consumes - is **empty in all
32 gated cells**, and empty across all 1,132 cells of this run, over 1,501,000 simulated rounds.
`02-triage.json` is therefore absent by measurement rather than by omission: `--stage triage`
refuses an empty `--seeds` list, and a hand-written file of zero classified rows would be an
artefact with no run behind it.

The 14 stalled gated rounds are every one of them `CapReached` with `hitActionCap = false`:

| N | mode | churn | stalled | outcome | hitActionCap | seenResets | seeds |
|---|---|---|---|---|---|---|---|
| 7 | Blocker | false | 2 | CapReached | false | 0 | 111524302, 111526600 |
| 7 | Blocker | true | 1 | CapReached | false | 0 | 111627685 |
| 8 | Blocker | false | 1 | CapReached | false | 0 | 111924538 |
| 9 | Blocker | false | 1 | CapReached | false | 0 | 112321863 |
| 9 | Blocker | true | 1 | CapReached | false | 0 | 112430917 |
| 10 | Wild | false | 1 | CapReached | false | 0 | 112528430 |
| 10 | Wild | true | 4 | CapReached | false | 0 | 112621986, 112623813, 112625682, 112625816 |
| 10 | Blocker | false | 1 | CapReached | false | 0 | 112730610 |
| 10 | Blocker | true | 2 | CapReached | false | 0 | 112828927, 112829078 |

**What that makes them, deduced rather than assumed.** `Simulator` reaches
`finish("CapReached", true)` only from `actions >= actionCap`; the two paths that reach
`CapReached` with the flag false are the 300s `time-cap` and the `circulation-zero` branch. Every
cell of this sweep runs with `sabotage = "None"`, under which circulation is constant and at
least 1, so `circulation-zero` is unreachable. All 14 are therefore 300s `time-cap` rounds, and a
cap raised to ten times `SOLVABILITY_ACTION_CAP` cannot change a single one of them. That is the
same result 02-09 saw over 6,000 gated rounds and 02-10's rehearsal saw over 9,600; this run
reproduces it over 320,000.

**`valveSeenResets` is 0 on every one of those cells**, and 0 across all 320,000 gated rounds, so
the valve was watching rather than blind everywhere a stall occurred. The blind-versus-watching
distinction this subsection exists to draw is therefore settled in the watching direction.

**And the limit of what can be said.** Neither `CapArtifact` nor `ResidualLivelock` applies,
because both are labels for an ACTION-cap round and these are time-cap rounds - a third category
the triage vocabulary has no word for. Nor can this report say whether the 14 were cycles: with
the valve enabled, cycle detection is disabled by design (02-09, because a repeated state hash
proves non-termination only under deterministic dynamics with no escape mechanism), so a
`time-cap` round carries no evidence either way. What is measured is narrower and is all that is
claimed: they were not action-cap artefacts, the valve was not blind, and at the same pool and
roster the valve-disabled twins livelock in 1.21% to 2.42% of rounds against this 0.004%.

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
| 2 | 0 | Wild | 8 | 0.0010 | 0.763 | 0 | 0 | 0 | 1 | valve-rate |
| 2 | 0 | Blocker | 8 | 0.0000 | 0.762 | 0 | 0 | 0 | 0 | valve-rate |
| 3 | 0 | Wild | 12 | 0.0000 | 0.822 | 0 | 0 | 0 | 0 | valve-rate |
| 3 | 0 | Blocker | 12 | 0.0010 | 0.822 | 0 | 0 | 0 | 1 | valve-rate |
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
- `02-sweep-data.json` is exactly as that run wrote it (sha256
  `25f470a0ba9540d67d1886fe4e517ee1cc371a32eb513fce0946772433e774e3`); nothing after the run
  touched it
- **three edits were made to this file by hand after the run, and `scripts/sim/sweep.luau` was
  corrected so a re-run emits all three directly.** (1) The verdict's headline sentence was a
  hardcoded "zero observed stalls" literal, which printed beside a non-zero measured residual in
  the same sentence; it is now rendered from the stalled-round count. (2) Section 4b's ladder was
  captioned as the pool each bar "would have selected" while computing the pool each bar would
  ADMIT, so its 7% row read k=3 against this report's own k=6 verdict; both ladders are now shown
  and labelled. (3) Section 4b's triage placeholder was replaced by the measured result. Edits 1
  and 2 were regenerated from the committed JSON by the corrected code paths, so the text here is
  what the fixed script emits rather than prose written over the data.
- every non-cleared round's seed is carried in `02-sweep-data.json` as `failingSeeds`
  (capped at the first 20 per cell) and `hitActionCapSeeds`, so any row here can be replayed.

### The selection rule as implemented

1. k >= 1 (amendment A4: at k = 0 the Blocker variant is a cliff, not a flag)
2. j >= 1 (PROJECT.md's Key Decisions: jokers exist; the sweep CLEARS j, it does not minimise it)
3. every bar passes in BOTH joker modes and BOTH churn variants, at every N searched (OQ-D)
4. reject any pool whose valveFiringRate exceeds 0.07 (amendment A8, re-derived from the measured curve)
5. smallest passing pool: fewest extra ranks k first, then fewest jokers j; ties on the lower valve firing rate
6. auto-pass deadline: the largest FINITE candidate that clears, WITH MARGIN where any pool can

Departures from CONTEXT's literal rule, recorded rather than hidden:

- CONTEXT's literal 'then fewest jokers' tiebreak returns j = 0 and deletes the jokers. PROJECT.md's Key Decisions table records them as a design property and CLAUDE.md says PROJECT.md wins, so the search floor is j >= 1 and j = 0 is measured and reported as a comparison (report section 6).
- Amendment A8 replaced the ZERO stall bar with an explicit residual ceiling of 0.005 and the 1% valve-rate bar with 0.07; Simulator.evaluateBars is unchanged and its verdict is recorded on every cell as lockedVerdict/lockedFailures.
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
| 2 | 0 | 1.5 | 12 | false | false | j-floor | valve-rate | valve-rate | 0.0000 | 0.1410 | 13.5 | 20.1 | 0.764 |
| 2 | 0 | 3.0 | 12 | false | false | j-floor | valve-rate | valve-rate | 0.0000 | 0.1650 | 13.6 | 20.4 | 0.763 |
| 2 | 0 | 5.0 | 12 | false | false | j-floor | valve-rate | valve-rate | 0.0010 | 0.1510 | 13.3 | 19.9 | 0.762 |
| 2 | 0 | 8.0 | 12 | false | false | j-floor | valve-rate | valve-rate | 0.0020 | 0.1630 | 13.8 | 20.2 | 0.764 |
| 2 | 0 | inf | 12 | false | false | j-floor | valve-rate | valve-rate | 0.0010 | 0.1740 | 13.5 | 20.2 | 0.764 |
| 2 | 1 | 1.5 | 12 | false | false | bars | valve-rate | valve-rate | 0.0010 | 0.1400 | 14.6 | 21.5 | 0.789 |
| 2 | 1 | 3.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0020 | 0.1550 | 14.4 | 21.8 | 0.792 |
| 2 | 1 | 5.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0010 | 0.1460 | 14.2 | 21.3 | 0.788 |
| 2 | 1 | 8.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0010 | 0.1550 | 14.5 | 21.8 | 0.789 |
| 2 | 1 | inf | 12 | false | false | auto-pass-disabled | valve-rate | cleared-fraction,stalls,valve-rate | 0.0030 | 0.1540 | 14.5 | 21.2 | 0.790 |
| 2 | 2 | 1.5 | 12 | false | false | bars | valve-rate | valve-rate | 0.0020 | 0.1260 | 15.5 | 22.4 | 0.806 |
| 2 | 2 | 3.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0010 | 0.1750 | 15.4 | 22.9 | 0.805 |
| 2 | 2 | 5.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0020 | 0.1610 | 15.7 | 23.0 | 0.806 |
| 2 | 2 | 8.0 | 12 | false | false | bars | valve-rate | cleared-fraction,stalls,valve-rate | 0.0030 | 0.1390 | 15.5 | 23.5 | 0.806 |
| 2 | 2 | inf | 12 | false | false | auto-pass-disabled | valve-rate | cleared-fraction,stalls,valve-rate | 0.0030 | 0.1580 | 15.6 | 22.6 | 0.806 |
| 3 | 0 | 1.5 | 12 | false | false | j-floor | valve-rate | valve-rate | 0.0010 | 0.0780 | 15.0 | 22.5 | 0.819 |
| 3 | 0 | 3.0 | 12 | false | false | j-floor | valve-rate | cleared-fraction,stalls,valve-rate | 0.0030 | 0.0800 | 15.2 | 22.4 | 0.820 |
| 3 | 0 | 5.0 | 12 | false | false | j-floor | valve-rate | valve-rate | 0.0010 | 0.0860 | 15.1 | 22.6 | 0.822 |
| 3 | 0 | 8.0 | 12 | false | false | j-floor | valve-rate | valve-rate | 0.0020 | 0.0950 | 14.8 | 22.3 | 0.821 |
| 3 | 0 | inf | 12 | false | false | j-floor | valve-rate | valve-rate | 0.0010 | 0.0900 | 15.1 | 22.6 | 0.820 |
| 3 | 1 | 1.5 | 12 | true | false | - | - | valve-rate | 0.0000 | 0.0680 | 16.2 | 24.2 | 0.826 |
| 3 | 1 | 3.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0020 | 0.0740 | 16.2 | 23.8 | 0.827 |
| 3 | 1 | 5.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0010 | 0.0860 | 16.3 | 23.0 | 0.825 |
| 3 | 1 | 8.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0000 | 0.0940 | 16.4 | 23.5 | 0.825 |
| 3 | 1 | inf | 12 | false | false | auto-pass-disabled | valve-rate | valve-rate | 0.0010 | 0.0750 | 16.1 | 23.1 | 0.824 |
| 3 | 2 | 1.5 | 12 | true | false | - | - | valve-rate | 0.0000 | 0.0620 | 17.3 | 25.2 | 0.828 |
| 3 | 2 | 3.0 | 12 | true | false | - | - | valve-rate | 0.0020 | 0.0620 | 17.5 | 25.0 | 0.826 |
| 3 | 2 | 5.0 | 12 | false | false | bars | valve-rate | cleared-fraction,stalls,valve-rate | 0.0030 | 0.0820 | 17.3 | 24.9 | 0.828 |
| 3 | 2 | 8.0 | 12 | false | false | bars | valve-rate | valve-rate | 0.0010 | 0.0880 | 17.2 | 25.0 | 0.828 |
| 3 | 2 | inf | 12 | false | false | auto-pass-disabled | valve-rate | valve-rate | 0.0010 | 0.0720 | 17.1 | 25.1 | 0.829 |
| 4 | 0 | 1.5 | 12 | true | false | j-floor | - | valve-rate | 0.0000 | 0.0600 | 17.2 | 25.4 | 0.838 |
| 4 | 0 | 3.0 | 12 | true | false | j-floor | - | valve-rate | 0.0000 | 0.0570 | 17.4 | 25.3 | 0.836 |
| 4 | 0 | 5.0 | 12 | true | false | j-floor | - | valve-rate | 0.0010 | 0.0570 | 17.1 | 25.4 | 0.835 |
| 4 | 0 | 8.0 | 12 | true | false | j-floor | - | valve-rate | 0.0020 | 0.0610 | 17.5 | 25.3 | 0.836 |
| 4 | 0 | inf | 12 | true | false | j-floor | - | valve-rate | 0.0000 | 0.0500 | 17.3 | 25.3 | 0.835 |
| 4 | 1 | 1.5 | 12 | true | false | - | - | valve-rate | 0.0010 | 0.0440 | 18.1 | 27.3 | 0.839 |
| 4 | 1 | 3.0 | 12 | true | false | - | - | valve-rate | 0.0010 | 0.0550 | 18.1 | 26.9 | 0.837 |
| 4 | 1 | 5.0 | 12 | true | false | - | - | valve-rate | 0.0000 | 0.0490 | 18.2 | 26.2 | 0.838 |
| 4 | 1 | 8.0 | 12 | true | false | - | - | valve-rate | 0.0010 | 0.0610 | 18.5 | 26.8 | 0.837 |
| 4 | 1 | inf | 12 | true | false | auto-pass-disabled | - | valve-rate | 0.0020 | 0.0420 | 17.9 | 27.2 | 0.839 |
| 4 | 2 | 1.5 | 12 | true | false | - | - | valve-rate | 0.0000 | 0.0420 | 19.1 | 28.2 | 0.838 |
| 4 | 2 | 3.0 | 12 | true | false | - | - | valve-rate | 0.0020 | 0.0560 | 19.4 | 27.5 | 0.838 |
| 4 | 2 | 5.0 | 12 | true | false | - | - | valve-rate | 0.0010 | 0.0580 | 18.9 | 27.2 | 0.838 |
| 4 | 2 | 8.0 | 12 | true | false | - | - | valve-rate | 0.0010 | 0.0430 | 19.0 | 27.9 | 0.839 |
| 4 | 2 | inf | 12 | true | false | auto-pass-disabled | - | valve-rate | 0.0010 | 0.0550 | 19.0 | 27.6 | 0.839 |
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

