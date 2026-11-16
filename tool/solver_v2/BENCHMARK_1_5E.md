# AKYS V2 1.5E — optimistic clinical bounds

Baseline `6d7ed642ac68891961c67fe85102e0e0d6874e62`. Clinical bounds are experimental, explicitly selected with `clinicalBounds: true`; the default and all existing strategies remain unchanged. No feasibility rule or quality objective is relaxed.

## Mathematical bounds

All objectives use minimization form. Q1 is lower-bounded by the number of junior-to-senior assignments already present: later slots cannot undo those assignments. For Q2 count the days already covered by a junior, then add at most the minimum of (a) uncovered days with at least one remaining role that could in principle accept a junior and (b) total remaining junior personal capacity. Its negation is a lower bound. A senior role is included in remaining junior opportunities only in substitution phase B. For Q3 count days already containing at least two juniors, then add at most the minimum of (a) days with enough remaining potentially eligible positions to reach two and (b) total remaining junior capacity. Giving one capacity unit to a day that in reality needs two deliberately overestimates attainable Q3 and remains safe.

Availability, rest, previous-month boundaries, per-day collisions, must requirements, per-physician role eligibility and competition between days are deliberately ignored in these upper bounds. Relaxing these constraints enlarges the hypothetical completion set; it cannot reduce the optimistic coverage estimate. REQUIRED and OPTIONAL remaining slots are both treated as potentially fillable, which is optimistic. K levels affect later quality objectives and are not used in these first-three bounds. Junior capacity respects each current physician's `maxDuties` after prefix assignments.

Bounds are compared lexicographically to the incumbent only over Q1–Q3. The prefix is rejected only when the first differing optimistic component is strictly worse. If the three are equal, search continues: later objectives may still improve. No claim is made that the three individual optimistic values are jointly attainable. Q4–Q7 have a trivial lower bound of minus the number of days, while Q8–Q19 have zero as a trivial lower bound; these are not used for pruning in this stage. No unproven objective bound is used.

`optimisticClinicalPrefix` was tested before integration using independent complete assignment enumeration and `ReferenceClinicalQualityCalculator`, not the solver evaluator. With deterministic seed 150500, 500 generated problems in A and B modes produced 1,486 independent valid completions and 3,887 completable prefix checks; 179,645 additional enumerated prefixes had no completion and therefore no bound comparison was possible. The test verifies that the lexicographic bound never exceeds the independently calculated best completion.

The same immutable problem, A/B authority, optional decisions, candidate ordering, phase-2 exhaustive restart and pause/resume frontier are retained. An incomplete search cannot establish optimality or infeasibility. Bounds are evaluated only after a valid incumbent exists; first-solution searches have no objective-bound pruning. A/B substitution validation and the prohibition on permanent approval are unchanged.

## Measurement method

`quality_trace.dart` uses explicit strategies `twophase` and `bounded`, one-node observation and independent validation. Three 120-second runs per scale and strategy record 30-second checkpoints. Four single-threaded Dart VM JIT processes share a 4-CPU cgroup quota, so wall times are not isolated single-process results. Stopwatch timing for bound checks is included in `bounded` elapsed time; profiler overhead and concurrent scheduling can affect observed node throughput. No percentage-based or weighted clinical quality is used.

The four main snapshots reuse the 1.5D synthetic `mixed` fixtures. Each has an independently validated witness, dense restrictions and synthetic holidays. All `seniorityRank` metadata uses the fixture's default value 1; for more than four senior doctors the K1–K4 levels repeat. This is a documented representativeness limitation; the tested first-three bounds do not depend on these fields.

## 30/120 second measurements

| Doctors | Strategy | First ms | 30s optional fill | 120s optional fill | Nodes at 120s | Pruned at 120s | Bound cost sec | Status |
|---:|---|---|---|---|---|---|---|---|
| 6 | twophase | 31.79–65.64 | 13–13 | 13–13 | 50203486–50856373 | 0–0 | 0.000–0.000 | feasibleNotProven |
| 6 | bounded | 42.04–74.61 | 13–13 | 13–13 | 54928096–58795416 | 825850–882123 | 15.597–16.149 | feasibleNotProven |
| 10 | twophase | 72.40–101.66 | 24–24 | 24–24 | 21809944–22479561 | 0–0 | 0.000–0.000 | feasibleNotProven |
| 10 | bounded | 48.68–71.28 | 24–24 | 24–24 | 45127706–46079561 | 2308966–2349429 | 10.914–11.134 | feasibleNotProven |
| 15 | twophase | 45.73–60.86 | 31–31 | 31–31 | 9695161–10059787 | 0–0 | 0.000–0.000 | feasibleNotProven |
| 15 | bounded | 36.38–79.71 | 31–31 | 31–31 | 13269594–13600948 | 647468–663636 | 4.857–4.915 | feasibleNotProven |
| 20 | twophase | 57.10–89.84 | 31–31 | 31–31 | 5896596–6096022 | 0–0 | 0.000–0.000 | feasibleNotProven |
| 20 | bounded | 58.03–135.45 | 31–31 | 31–31 | 6866273–7052629 | 266901–274145 | 3.508–3.614 | feasibleNotProven |

## Exact vectors: first repeat

| Doctors | Strategy | First | 30s | 120s |
|---:|---|---|---|---|
| 6 | twophase | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,11,40` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,7,40` |
| 6 | bounded | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,11,40` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,7,40` |
| 10 | twophase | `0,0,0,-6,-6,-6,-12,3,3,2,2,2,2,3,3,1/4,1/4,12,36` | `0,-24,0,-7,-7,-7,-9,2,3,2,4,3,5,3,4,1/4,1/4,26,44` | `0,-24,0,-7,-7,-7,-9,2,3,2,4,3,5,3,4,1/4,1/4,26,44` |
| 10 | bounded | `0,0,0,-6,-6,-6,-12,3,3,2,2,2,2,3,3,1/4,1/4,12,36` | `0,-24,0,-7,-7,-7,-9,2,3,2,4,3,5,3,4,1/4,1/4,26,44` | `0,-24,0,-7,-7,-7,-9,2,3,2,3,3,5,2,3,1/4,1/4,31,44` |
| 15 | twophase | `0,0,0,-5,-5,-10,-11,2,2,3,3,1,1,3,3,5/24,5/24,15,30` | `0,-31,0,-6,-6,-10,-9,2,4,3,4,1,2,3,4,1/2,5/8,22,36` | `0,-31,0,-6,-6,-10,-9,2,3,3,4,1,2,3,4,1/2,5/8,22,36` |
| 15 | bounded | `0,0,0,-5,-5,-10,-11,2,2,3,3,1,1,3,3,5/24,5/24,15,30` | `0,-31,0,-6,-6,-10,-9,2,3,3,4,1,2,3,4,1/2,5/8,22,36` | `0,-31,0,-6,-6,-10,-9,1,2,3,4,1,2,3,4,1/2,5/8,14,28` |
| 20 | twophase | `0,0,0,-6,-8,-8,-9,2,2,2,2,2,2,3,3,1/2,1/2,15,24` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,2/3,26/21,22,31` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,5/8,67/56,22,31` |
| 20 | bounded | `0,0,0,-6,-8,-8,-9,2,2,2,2,2,2,3,3,1/2,1/2,15,24` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,2/3,26/21,22,31` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,5/8,67/56,22,31` |

## Paired 120-second lexicographic comparison

| Doctors | Bounded versus unbounded, three repeats |
|---:|---|
| 6 | 3 equal |
| 10 | 3 better |
| 15 | 3 better |
| 20 | 3 equal |

The full snapshot, every incumbent vector and timestamp, per-checkpoint status, bound checks/prunes and measured bound ticks are in `results/stage_1_5e_traces.json.gz`. Bound time includes stopwatch and bound computation overhead. Measurements do not establish global optimality when status remains `feasibleNotProven`.

## Reproduce

```sh
dart --packages=.dart_tool/package_config.json tool/solver_v2/quality_trace.dart 6 30 mixed bounded 120
flutter test --no-pub test/solver_v2
gzip -dc tool/solver_v2/results/stage_1_5e_traces.json.gz
```

The oracle additionally checked each of Q1, Q2 and Q3 independently against the minimum of that component over all valid completions of each completable prefix. The solver comparison covered 200 additional seed-150520 small problems in both unbounded and bounded A/B modes. Explicit regression verifies that equal Q1–Q3 bounds do not prune an improvement to the K4 component. All 112 V2 tests, including the independent 500-schedule clinical-quality reference and prior A/B and pause/resume tests, passed; `dart analyze` and `flutter analyze --no-pub` reported no issues.

In these measured fixtures, bounded and unbounded 120-second quality vectors were equal across all 6- and 20-doctor paired runs; bounded was lexicographically better in all 10- and 15-doctor pairs. These are bounded-time results, not proofs that one strategy globally dominates or that any solution is optimal. Bound timing includes instrumentation and was roughly 3.5–16.1 seconds depending on scale; no isolated single-process performance conclusion follows from the four-way concurrent measurements.
