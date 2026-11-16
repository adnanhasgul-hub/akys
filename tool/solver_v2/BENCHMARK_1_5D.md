# AKYS V2 1.5D — experimental first-incumbent restart

Baseline `415f77cb2aa23f6571e0724fe87e9bf6e791a3ec`. `experimentalTwoPhase` is explicit and off by default; it requires clinical mode plus the existing combined ordering/dead-end strategy. No clinical constraints, objective components or default strategy are changed.

## Proof and frontier design

Phase 1 uses the combined DFS. Its first incumbent is independently validated. The current prefix and all cursors are then discarded, but the incumbent and same immutable problem snapshot remain. Phase 2 restarts at the root and tries every physician before the empty optional value. It uses the same hard constraints, feasibility pruning and clinical objective. A completed phase-2 traversal covers the entire permitted space, so only that traversal may prove its incumbent optimal. If phase 1 exhausts without finding any incumbent, its full traversal can prove infeasibility. Interrupted or cancelled traversals prove neither.

Simply changing the order in the live DFS frontier would make already-consumed cursor indexes refer to different candidates and could skip branches; it is therefore not done. Restarting revisits decisions and incurs duplicate work: `qualityPhaseStartNode` measures phase-1 candidate attempts, not an exact count of distinct repeated states in a bounded phase-2 prefix. If phase 2 exhausts, the phase-1 subtree is covered again. Cursor, prefix, incumbent and phase are process-local and persist during cooperative pause/resume; no serialized checkpoint or portable proof is implemented.

The above phases are independent of senior-substitution A/B. B opens only after a completed restricted A infeasibility proof. The B phase has its own first-incumbent restart, using the original session-local transition authority. Substitution results remain ineligible for durable approval.

## Measurement methodology

30 and 120 seconds are checkpoints within the same run. Main 6/10/15/20-doctor fixtures are each measured three times per strategy; four independent single-threaded Dart VM JIT processes share the four-CPU cgroup quota. Node-at-a-time tracing, timestamping and independent incumbent validation are included in elapsed time. Results are observational wall times, not isolated single-process latency. The 31-day main fixtures span December 2026. Additional `surplus`, `ratio` and `rank` fixtures are three-second exploratory comparisons, three repeats each; they are not 30/120-second evaluations. Forced and substitution fixtures terminate when exact proof completes. Clinical quality comparisons are exact lexicographic comparisons, not weighted scores.

The `rank` fixture changes `seniorityRank` while maintaining the existing K-level inputs; the present V2 quality function uses K levels, not this rank field. This limits conclusions about the effect of individualized ranks.

## 30/120 second main fixture comparison

| Physicians | Strategy | First ms range | 30s fill | 120s fill | Improvement count range | 120s status |
|---:|---|---|---|---|---|---|
| 6 | deadends | 23.812–100.636 | 13–13 | 13–13 | 14–14 | feasibleNotProven |
| 6 | combined | 18.972–42.764 | 8–8 | 9–9 | 82–82 | feasibleNotProven |
| 6 | twophase | 54.712–71.364 | 13–13 | 13–13 | 15–15 | feasibleNotProven |
| 10 | deadends | 18.430–29.461 | 24–24 | 24–24 | 21–21 | feasibleNotProven |
| 10 | combined | 38.032–53.561 | 6–6 | 7–7 | 72–72 | feasibleNotProven |
| 10 | twophase | 55.639–83.826 | 24–24 | 24–24 | 16–16 | feasibleNotProven |
| 15 | deadends | 62.367–109.840 | 31–31 | 31–31 | 28–28 | feasibleNotProven |
| 15 | combined | 42.733–153.168 | 5–5 | 5–5 | 58–58 | feasibleNotProven |
| 15 | twophase | 45.639–57.666 | 31–31 | 31–31 | 34–34 | feasibleNotProven |
| 20 | deadends | 29.780–76.224 | 31–31 | 31–31 | 13–13 | feasibleNotProven |
| 20 | combined | 65.052–102.833 | 4–4 | 5–5 | 54–56 | feasibleNotProven |
| 20 | twophase | 44.491–60.726 | 31–31 | 31–31 | 19–19 | feasibleNotProven |

## Full quality vectors, first repetition

Every vector uses the 19-component minimization convention; all other repetitions and each event are in the compressed trace.

| Physicians | Strategy | First vector | 30s vector | 120s vector |
|---:|---|---|---|---|
| 6 | deadends | `0,-13,0,-6,-8,-8,-8,2,2,2,2,1,1,3,4,1/4,1/4,17,46` | `0,-13,0,-8,-8,-8,-6,0,0,2,2,1,1,2,2,1/4,1/4,14,44` | `0,-13,0,-8,-8,-8,-6,0,0,2,2,1,1,2,2,1/4,1/4,14,44` |
| 6 | combined | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-8,0,-8,-8,-8,-6,2,2,2,3,1,1,2,2,1/4,29/84,22,50` | `0,-9,0,-8,-8,-8,-6,2,2,2,3,1,1,2,2,1/4,25/84,22,50` |
| 6 | twophase | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,11,40` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,7,40` |
| 10 | deadends | `0,-24,0,-5,-8,-8,-9,2,3,2,3,2,4,2,3,5/6,5/6,31,40` | `0,-24,0,-6,-8,-8,-8,1,2,2,3,2,4,2,3,2/3,2/3,29,38` | `0,-24,0,-7,-8,-8,-7,2,3,2,3,2,4,2,3,2/3,2/3,29,40` |
| 10 | combined | `0,0,0,-6,-6,-6,-12,3,3,2,2,2,2,3,3,1/4,1/4,12,36` | `0,-6,0,-7,-7,-6,-10,2,3,2,3,2,3,3,4,1/3,7/12,16,39` | `0,-7,0,-7,-7,-7,-9,2,3,2,3,2,3,3,4,1/4,1/2,26,44` |
| 10 | twophase | `0,0,0,-6,-6,-6,-12,3,3,2,2,2,2,3,3,1/4,1/4,12,36` | `0,-24,0,-7,-7,-7,-9,2,3,2,4,3,5,3,4,1/4,1/4,26,44` | `0,-24,0,-7,-7,-7,-9,2,3,2,4,3,5,3,4,1/4,1/4,26,44` |
| 15 | deadends | `0,-31,0,-4,-8,-9,-10,2,4,3,5,2,3,3,5,1,13/7,44,47` | `0,-31,0,-5,-8,-10,-8,2,3,3,5,2,3,3,5,5/6,19/12,38,47` | `0,-31,0,-5,-8,-10,-8,2,3,3,5,2,3,3,5,5/6,65/42,38,47` |
| 15 | combined | `0,0,0,-5,-5,-10,-11,2,2,3,3,1,1,3,3,5/24,5/24,15,30` | `0,-5,0,-5,-6,-11,-9,2,2,3,3,1,2,3,4,1/5,13/40,22,36` | `0,-5,0,-6,-6,-10,-9,2,2,3,3,1,2,3,4,1/5,13/40,22,36` |
| 15 | twophase | `0,0,0,-5,-5,-10,-11,2,2,3,3,1,1,3,3,5/24,5/24,15,30` | `0,-31,0,-6,-6,-10,-9,2,4,3,4,1,2,3,4,1/2,5/8,22,36` | `0,-31,0,-6,-6,-10,-9,2,3,3,4,1,2,3,4,1/2,5/8,22,36` |
| 20 | deadends | `0,-31,0,-4,-9,-9,-9,2,3,3,5,2,3,3,5,1,2,47,47` | `0,-31,0,-6,-9,-8,-8,2,3,3,5,2,3,3,5,1,13/7,47,47` | `0,-31,0,-7,-8,-9,-7,2,3,3,5,2,3,3,5,1,13/7,47,47` |
| 20 | combined | `0,0,0,-6,-8,-8,-9,2,2,2,2,2,2,3,3,1/2,1/2,15,24` | `0,-4,0,-7,-9,-8,-7,2,2,2,2,2,2,2,3,1/2,5/6,16,25` | `0,-5,0,-7,-9,-7,-8,2,2,2,2,2,3,2,3,4/7,19/21,22,31` |
| 20 | twophase | `0,0,0,-6,-8,-8,-9,2,2,2,2,2,2,3,3,1/2,1/2,15,24` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,2/3,26/21,22,31` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,5/8,67/56,22,31` |

## Additional fixtures

`surplus`, `ratio`, `rank` were compared using a three-second exploratory budget only (not 30/120 seconds), three repetitions per strategy and scale. `forced` and `transition` are exact terminating test cases for two-phase strategy, three repetitions. See compressed traces for every vector, event, snapshot and status.

| Physicians | Experimental vs dead-ends at 120s | Experimental vs combined at 120s |
|---:|---|---|
| 6 | 3 worse | 3 better |
| 10 | 3 worse | 3 better |
| 15 | 3 better | 3 better |
| 20 | 3 better | 3 better |

## Reproduction

```sh
dart --packages=.dart_tool/package_config.json tool/solver_v2/quality_trace.dart 6 30 mixed twophase 120
dart --packages=.dart_tool/package_config.json tool/solver_v2/quality_trace.dart 6 30 mixed combined 1 profile
flutter test --no-pub test/solver_v2
```

Compressed trace: `gzip -dc tool/solver_v2/results/stage_1_5d_traces.json.gz`.

## One-second instrumentation sample

Each profile/plain pair below is one sequential process on the same machine, not a statistically reliable benchmark. Both use node-at-a-time trace and per-incumbent independent validation; `profile` adds per-check stopwatches and depth maps. A higher profiled count in one trial reflects scheduling/JIT variability, not evidence of negative instrumentation cost.

| People | Strategy | Nodes plain / profiled | Complete valid / invalid leaves | Direct quality calls and measured ms | `_allowed` calls and measured ms | Empty OPTIONAL attempts |
|---:|---|---:|---:|---:|---:|---:|
| 6 | combined | 211986 / 204182 | 25227 / 0 | 25227 / 664.11 | 186001 / 29.59 | 18181 |
| 6 | twophase | 433827 / 388796 | 18472 / 0 | 18472 / 528.78 | 353368 / 48.05 | 35428 |
| 10 | combined | 103001 / 100401 | 23131 / 0 | 23131 / 674.45 | 93769 / 16.42 | 6632 |
| 10 | twophase | 196860 / 196795 | 16938 / 0 | 16938 / 577.69 | 183791 / 29.94 | 13004 |
| 15 | combined | 65733 / 66200 | 20265 / 0 | 20265 / 650.57 | 63029 / 12.83 | 3171 |
| 15 | twophase | 87210 / 78178 | 13637 / 0 | 13637 / 617.81 | 74384 / 15.8 | 3794 |
| 20 | combined | 51065 / 46725 | 15468 / 0 | 15468 / 616.42 | 44889 / 11.47 | 1836 |
| 20 | twophase | 47138 / 48767 | 14048 / 0 | 14048 / 652.85 | 46861 / 9.2 | 1906 |

For the 6-doctor combined profile, post-first node attempts at depths 59, 58 and 57 were 83,448, 53,144 and 27,538 respectively. Depth and empty-OPTIONAL attempt distributions for every profiled case are in the trace. Each complete leaf is either rejected by the remaining must check or passed to the direct evaluator; other hard-invalid choices are rejected before becoming a leaf. Counts and stopwatches perturb execution.

The quality stopwatch covers direct evaluator calls, including its internal validation. `firstValidationCalls`/ticks measure the additional first-incumbent validation in two-phase mode, whose successful check itself invokes the evaluator once. The independent tracer validates each observed incumbent and invokes the evaluator again; those calls and timings are outside the direct profile counters. The `_allowed` timer excludes `_prune`, missed-must scanning, leaf checks and validation: it is not a full hard-constraint CPU profile. Stopwatch sums include instrumentation overhead.

The 30/120-second main runs did not prove optimality. Phase-1 restart points were 109, 171, 258 and 300 visited candidates for the 6/10/15/20-doctor fixtures, identically across repeats. These counts represent extra phase-1 traversal before the full restart, not a measured count of nodes duplicated by the deadline. The experimental strategy was better than combined in all 12 paired 120-second comparisons; compared with dead-ends-only it was worse in all six paired 6/10-doctor runs and better in all six 15/20-doctor runs.

In the three-second exploratory variants, experimental versus dead-ends-only was better in six and worse in six `surplus` pairs, better in three and worse in three `ratio` pairs with six missing dead-ends incumbents, and better in six and worse in six `rank` pairs. It was better than combined in all 12 pairs per variant. These exploratory comparisons cannot establish 30/120-second outcomes. Twelve experimental `forced` runs proved restricted-stage optimality; three `transition` runs proved restricted infeasibility and then substitution-stage optimality. The latter proof is session-local; persistent approval remains prohibited.

Two hundred seed-151204 small clinical problems (including must/cannot, optional positions and previous-month boundaries) were checked against the independent exhaustive oracle; pause/resume, deadline, cancellation, profile neutrality and A/B cases are included in the solver test suite. The independent 19-component reference tests and existing regressions remain active. The experimental algorithm stays opt-in pending broader isolated performance experiments and a separately designed asynchronous worker integration.
