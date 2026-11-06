# AKYS V2 1.5A — clinical-scale benchmark

Baseline `bebb7663f7a5aa80aa1f31038f4d247c068a4073`; Dart 3.13.7 VM JIT, Linux x86_64, AMD EPYC 9V74, cgroup quota 4 CPUs. No Flutter release/AOT or memory measurement.

Four long-running VM processes ran concurrently against the 4-vCPU quota. The 30-second and 120-second rows are checkpoints from the **same** run, not independent samples. One long run per size; scheduling and VM warmup affect wall time. First incumbent timing, if available, is a chunk-observation upper bound (at most 100 candidate nodes after it is found). Every observed incumbent is checked by `SolutionValidator`; the evaluator also validates every complete clinical candidate.

| Doctors | Days | Required | Optional | Budget | Nodes | Nodes/s | Status | First solution | Optimality |
|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 6 | 30 | 30 | 30 | 30 s | 142708686 | 4756937 | timeoutWithoutSolution | none | not proven |
| 6 | 30 | 30 | 30 | 120 s | 593995208 | 4949960 | timeoutWithoutSolution | none | not proven |
| 10 | 30 | 30 | 30 | 30 s | 154226245 | 5140871 | timeoutWithoutSolution | none | not proven |
| 10 | 30 | 30 | 30 | 120 s | 664033397 | 5533611 | timeoutWithoutSolution | none | not proven |
| 15 | 31 | 31 | 31 | 30 s | 177174595 | 5905815 | timeoutWithoutSolution | none | not proven |
| 15 | 31 | 31 | 31 | 120 s | 762890423 | 6357420 | timeoutWithoutSolution | none | not proven |
| 20 | 31 | 31 | 31 | 30 s | 187087051 | 6236231 | timeoutWithoutSolution | none | not proven |
| 20 | 31 | 31 | 31 | 120 s | 807128148 | 6726067 | timeoutWithoutSolution | none | not proven |

All long-run first and last quality vectors are null; no incumbent improvement occurred. A valid witness exists for every standard/tight/hard snapshot: all required senior slots follow the repeating indices `[3, 1, 2, 0]`, all junior slots are empty. This is independently checked by the fixture tests. Thus the timeout is **not** evidence of impossibility. These runs used SearchSession restricted phase A only; clinical-scale B transition timing was not measured.

## Three fixed-node runs per scenario

Fresh VM processes were run sequentially. Times below are min–max elapsed milliseconds within the search (VM startup excluded). Standard/tight/hard hit the 100,000-node limit without an incumbent. Impossible cases have total physician capacity strictly below required slots; feasibility pruning proves infeasibility. All scenarios have one required and one optional slot per day.

| Doctors | Days | Variant | Nodes | Status | Elapsed ms, min–max |
|---:|---:|---|---:|---|---:|
| 6 | 30 | standard | 100000 | paused | 40.673–54.746 |
| 6 | 30 | tight | 100000 | paused | 42.459–60.654 |
| 6 | 30 | hard | 100000 | paused | 44.581–48.036 |
| 6 | 30 | impossible | 6 | infeasible | 2.867–3.607 |
| 10 | 30 | standard | 100000 | paused | 34.512–44.645 |
| 10 | 30 | tight | 100000 | paused | 35.976–46.438 |
| 10 | 30 | hard | 100000 | paused | 35.927–47.178 |
| 10 | 30 | impossible | 10 | infeasible | 3.347–3.591 |
| 15 | 31 | standard | 100000 | paused | 34.858–38.745 |
| 15 | 31 | tight | 100000 | paused | 35.931–47.638 |
| 15 | 31 | hard | 100000 | paused | 34.032–42.273 |
| 15 | 31 | impossible | 15 | infeasible | 2.411–4.647 |
| 20 | 31 | standard | 100000 | paused | 31.467–44.984 |
| 20 | 31 | tight | 100000 | paused | 35.232–47.555 |
| 20 | 31 | hard | 100000 | paused | 31.905–42.626 |
| 20 | 31 | impossible | 20 | infeasible | 2.816–3.658 |

Synthetic data contains K1–K4, junior groups, required/optional slots, personal maxima, previous-month rest, must/cannot dates and holiday scores. `tight` and `hard` add distinct unavailable dates while preserving the witness; their names describe constraints, not a proven hardness ordering. The generator is formula-based and does not use random seed. Full primitive snapshots and per-run measurements are in `results/stage_1_5a.json`.

## Reproduction

```sh
dart --packages=.dart_tool/package_config.json tool/solver_v2/clinical_benchmark.dart 6 30 standard seconds 120
dart --packages=.dart_tool/package_config.json tool/solver_v2/clinical_benchmark.dart 6 30 hard node-budget 100000
flutter test --no-pub test/solver_v2
```

## Bottleneck review (code inspection, not profiling)

- DFS can try N candidates for every required slot and N+1 for optional slots; optional empty is visited after doctor candidates. With 30–31 optional slots the tree grows sharply.
- Assignment checks scan the current prefix for rest, duplicate and count; leaf must checks generate and scan lists. Complete candidates invoke independent validation and all 19 exact-rational components. No leaf was reached in the long runs, so these costs were not individually measured.
- Required-capacity pruning ignores role, date availability and spacing; it proves the constructed capacity-deficit cases but offers limited guidance on feasible cases. Exact restricted-stage infeasibility must finish before B opens. B-stage cost was not measured.
- Prefix, cursor and immutable snapshot have bounded in-memory footprint; validation, quality evaluation and candidate construction allocate temporary lists and exact fractions. Memory/allocation were not profiled.

Future work: profile candidate/leaf and allocation costs; evaluate mathematically proven role/date/rest capacity bounds and safe candidate ordering, preserving exhaustive proofs, A/B authorization and deterministic ties. Do not infer clinical-scale performance guarantees from these VM results.
