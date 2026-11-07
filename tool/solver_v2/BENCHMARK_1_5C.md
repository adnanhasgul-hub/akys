# AKYS V2 1.5C — incumbent quality traces

Baseline `8e701529bc4f5cc01df652e938d4ade24640fb65`. This is an observational benchmark; the solver, clinical quality vector, pruning and default strategy are unchanged.

## Method and fixtures

`quality_trace.dart PEOPLE DAYS VARIANT STRATEGY SECONDS` advances `TransitionSession` by **one visited candidate node per call**, so no incumbent replacement is skipped. Every replacement is checked using `SolutionValidator` against the live session; a non-strict lexicographic improvement aborts the run. The trace records timestamp, stage, node counter, complete 19-component vector, optional occupancy and assignments for each first solution and each subsequent improvement. Stopwatch timestamps are observations after validation; tracer and validator overhead is included in the budgets. Checkpoints at 30 and 120 seconds are from the same run, not independent runs. If exact search completes earlier, the terminal result is not falsely described as a later timed checkpoint. The outer wall deadline ends cooperative one-node stepping; `paused` or `feasibleNotProven` does not prove infeasibility or optimality.

Each scale has deterministic formula seed `150300`; no real person or patient data. The 30-day horizon is November and the 31-day horizon December 2026. `mixed` has respectively 4/2, 5/5, 6/9, 8/12 senior/junior doctors, 30 or 31 required senior positions and the same number of optional junior positions, dense must/cannot, previous-month rest, different individual maxima and synthetic holidays. `surplus` adds a second optional junior slot per day. `ratio` uses an alternative senior/junior split at each scale (5/1, 4/6, 4/11 and 4/16). In these three variants, the repeating senior witness `[3,1,2,0]` with empty optional positions satisfies all hard constraints and is verified before each run. The `forced` fixture disallows every non-witness assignment and has zero-capacity other doctors, giving exactly one feasible schedule. The `transition` fixture has no senior and one required senior slot: exhaustive restricted search proves A infeasible, then one junior substitution makes B feasible; the proof is local, not a portable certificate.

Measurements ran on Linux x86_64, Dart 3.13.7 VM JIT, AMD EPYC 9V74 with 4 CPU quota. At most four independent single-threaded processes ran concurrently, sharing the quota; measurements are not single-process-only latency. Each 120-second scenario/strategy is repeated three times unless explicitly stated. Compare 19 components lexicographically; do not interpret them as weighted scores or percentages.


Senior rank metadata uses the model default of 1 in these fixtures, while K1–K4 level determines the current quality hierarchy; for more than four seniors, levels repeat. The present V2 solver does not use `seniorityRank`. This limits how the samples represent individualized seniority.

## Mixed strategy comparison — three repeats

| Physicians | Strategy | First solution ms range | 120s found | Optional slots filled at 120s | Improvements (min–max) |
|---:|---|---|---:|---|---|
| 6 | baseline | none | 0/3 | none | 0–0 |
| 6 | ordering | 17.781–45.831 | 3/3 | 9–9 | 82–82 |
| 6 | deadends | 31.776–37.386 | 3/3 | 13–13 | 14–14 |
| 6 | combined | 23.502–80.719 | 3/3 | 8–9 | 70–82 |
| 10 | baseline | none | 0/3 | none | 0–0 |
| 10 | ordering | 17.872–44.032 | 3/3 | 7–7 | 72–72 |
| 10 | deadends | 24.542–77.179 | 3/3 | 24–24 | 21–21 |
| 10 | combined | 33.027–72.082 | 3/3 | 7–7 | 72–72 |
| 15 | baseline | none | 0/3 | none | 0–0 |
| 15 | ordering | 35.142–81.043 | 3/3 | 5–5 | 58–58 |
| 15 | deadends | 35.169–69.007 | 3/3 | 31–31 | 28–28 |
| 15 | combined | 56.480–94.383 | 3/3 | 5–5 | 58–58 |
| 20 | baseline | none | 0/3 | none | 0–0 |
| 20 | ordering | 29.927–73.806 | 3/3 | 5–5 | 55–56 |
| 20 | deadends | 40.421–49.309 | 3/3 | 31–31 | 13–13 |
| 20 | combined | 70.886–109.789 | 3/3 | 4–5 | 50–54 |

## Full quality vectors — first repeat of each combined fixture

All 19 values are ordered minimization components (maximized objectives are negative); numbers may be exact fractions. The first, 30s and 120s vectors and every incumbent event for all three repeats and all strategies are available in `results/stage_1_5c_traces.json.gz`.

| Fixture | Physicians | First vector | 30s vector | 120s vector | Optional fill first / 30 / 120 |
|---|---:|---|---|---|---|
| mixed | 6 | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-8,0,-8,-8,-8,-6,2,2,2,3,1,1,2,2,1/4,29/84,22,50` | `0,-8,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,29/84,22,50` | 0 / 8 / 8 |
| mixed | 10 | `0,0,0,-6,-6,-6,-12,3,3,2,2,2,2,3,3,1/4,1/4,12,36` | `0,-6,0,-7,-7,-6,-10,2,3,2,3,2,3,3,4,1/3,7/12,16,39` | `0,-7,0,-7,-7,-7,-9,2,3,2,3,2,3,3,4,1/4,1/2,26,44` | 0 / 6 / 7 |
| mixed | 15 | `0,0,0,-5,-5,-10,-11,2,2,3,3,1,1,3,3,5/24,5/24,15,30` | `0,-5,0,-5,-6,-11,-9,2,2,3,3,1,2,3,4,1/5,13/40,22,36` | `0,-5,0,-6,-6,-10,-9,2,2,3,3,1,2,3,4,1/5,13/40,22,36` | 0 / 5 / 5 |
| mixed | 20 | `0,0,0,-6,-8,-8,-9,2,2,2,2,2,2,3,3,1/2,1/2,15,24` | `0,-4,0,-7,-9,-7,-8,2,2,2,2,2,2,2,3,4/7,31/42,22,31` | `0,-4,0,-7,-10,-7,-7,2,2,2,2,2,2,2,3,4/7,31/42,22,31` | 0 / 4 / 4 |
| surplus | 6 | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-6,0,-8,-8,-8,-6,2,2,2,2,1,1,2,3,1/4,9/28,22,50` | `0,-6,0,-8,-8,-8,-6,2,2,2,2,1,1,2,3,1/4,9/28,22,50` | 0 / 6 / 6 |
| surplus | 10 | `0,0,0,-6,-6,-6,-12,3,3,2,2,2,2,3,3,1/4,1/4,12,36` | `0,-4,-3,-7,-6,-6,-11,2,3,2,3,2,3,3,3,1/4,3/8,16,39` | `0,-5,-3,-7,-6,-6,-11,2,3,2,3,2,3,3,4,1/4,3/8,16,39` | 0 / 7 / 8 |
| surplus | 15 | `0,0,0,-5,-5,-10,-11,2,2,3,3,1,1,3,3,5/24,5/24,15,30` | `0,-3,-3,-5,-6,-10,-10,2,2,3,3,1,1,3,4,1/4,11/24,14,30` | `0,-4,-3,-5,-6,-11,-9,2,2,3,3,1,1,3,4,1/2,5/8,22,36` | 0 / 6 / 7 |
| surplus | 20 | `0,0,0,-6,-8,-8,-9,2,2,2,2,2,2,3,3,1/2,1/2,15,24` | `0,-3,-2,-7,-8,-8,-8,2,2,2,2,2,2,2,3,1/2,2/3,16,25` | `0,-3,-3,-7,-8,-8,-8,2,2,2,2,2,2,2,3,1/2,3/4,16,25` | 0 / 5 / 6 |
| ratio | 6 | `0,0,0,-6,-6,-6,-12,3,3,2,2,2,2,3,3,1/4,1/4,12,36` | `0,-4,0,-7,-7,-7,-9,2,2,1,1,2,2,3,3,1/4,1/4,23,44` | `0,-4,0,-8,-7,-7,-8,2,2,1,1,2,2,2,2,1/2,1/2,31,44` | 0 / 4 / 4 |
| ratio | 10 | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-7,0,-8,-8,-8,-6,2,3,2,3,1,2,2,3,1/3,7/12,22,50` | `0,-7,0,-8,-8,-8,-6,2,3,2,3,1,2,2,3,1/3,7/12,22,50` | 0 / 7 / 7 |
| ratio | 15 | `0,0,0,-7,-8,-8,-8,2,2,4,4,2,2,3,3,1/8,1/8,18,44` | `0,-6,0,-8,-8,-7,-8,2,3,4,4,2,3,3,4,1/6,7/24,18,42` | `0,-6,0,-8,-8,-7,-8,2,3,4,4,2,3,3,4,1/6,7/24,18,42` | 0 / 6 / 6 |
| ratio | 20 | `0,0,0,-7,-8,-8,-8,2,2,4,4,2,2,3,3,1/8,1/8,18,44` | `0,-5,0,-7,-8,-8,-8,2,2,4,4,2,3,3,4,1/7,15/56,18,44` | `0,-6,0,-7,-8,-8,-8,2,3,4,4,2,3,3,4,1/6,7/24,18,44` | 0 / 5 / 6 |

Component mapping: Q1 substitutions; Q2/Q3 negated junior-day coverage and two-junior-day coverage; Q4–Q7 negated K4–K1 single-senior-day counts; Q8–Q15 Saturday/Friday/Sunday/Thursday worst and total group gaps; Q16–Q17 normalized workload gaps; Q18–Q19 difficulty gap and highest individual load. Each trace includes exact first/30/120 vectors, occupancy, stage, incumbent improvement timestamps/nodes and terminal status.

## Reproduction

```sh
dart --packages=.dart_tool/package_config.json tool/solver_v2/quality_trace.dart 6 30 mixed combined 120
dart --packages=.dart_tool/package_config.json tool/solver_v2/quality_trace.dart 6 30 transition combined 120
flutter test --no-pub test/solver_v2
```

## Observations and decision

On the mixed fixtures, all 12 baseline runs had no incumbent at the outer 120-second limit. Every ordering-only, dead-ends-only and combined run found a validated incumbent. In all three repetitions at all four scales, dead-ends-only produced a strictly better 120-second clinical vector than combined. Its first solution already filled 13, 24, 31 and 31 optional slots respectively. For these one-optional-slot-per-day fixtures, these values attain the independent upper bound `min(number of days, sum of junior capacities)`; this proves the junior-coverage component is maximal in those schedules, not that the full quality vector is optimal. Combined starts with zero optional fills and reached 8–9, 7, 5 and 4–5 respectively in 120 seconds. Ordering-only also starts with zero and reached 9, 7, 5 and 5. In the one-optional-slot fixtures Q3 is always zero by construction.

All 48 `forced` runs (four scales, four strategies, three repeats) terminated in restricted stage with `optimal` after exhausting the unique-solution tree. All 12 `transition` runs (four strategies, three repeats) proved restricted infeasibility and then `optimal` in substitution stage. Their process-local validator reports one substitution and does not authorize permanent approval. Realistic mixed/surplus/ratio 120-second runs did not prove optimality. Alternative-ratio and surplus fixtures were measured with combined only: conclusions about strategy ordering do not extend to those fixtures.

The empty-first traversal and zero-filled initial combined solution are directly observed. The ordering-only and combined strategies follow different candidate sequences than the original order; the evidence is consistent with DFS spending time in a large subtree and finding high-coverage candidates late, but node-depth/leaf-frequency profiles were not collected. The clinical implementation has no objective-bound pruning (code inspection). The individual cost of hard checks, full quality evaluation, rational arithmetic and allocations was not profiled; sparse complete leaves and calculation cost are hypotheses, not measured causes. Tracer overhead and concurrent scheduling affect all absolute timings.

Do not make the combined strategy the clinical default based on these results. Dead-ends-only was better on these fixtures, while the earlier 1.5B fixture showed cases where combined found an incumbent and dead-ends-only had not within the same budget. The evidence supports further single-process, independently profiled and more diverse comparison before selecting a default. No new optimization or default change is included here.

Read the compressed trace with `gzip -dc tool/solver_v2/results/stage_1_5c_traces.json.gz` or any gzip-capable JSON reader.
