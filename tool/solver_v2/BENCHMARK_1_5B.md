# AKYS V2 1.5B — first-incumbent strategies

Baseline: commit `586697b34a0e4f811290d415ecb6b65525d2bae7`. The old path is preserved as `candidateOrdering: false, earlyDeadEnds: false` and remains the default. The strategies are deliberately opt-in; no UI or production integration is performed.

## Search and proof safety

DFS still visits slots in chronological snapshot order; the required/optional positions are not reordered. Baseline visits doctors in index order then the optional empty value. The new ordering visits empty first for an optional slot, then all doctors, placing the current day's must doctors first, then fewer previously assigned duties, then index. It recomputes the same ordering from the unchanged prefix and keeps every candidate. Cursor/frontier state therefore remains meaningful across pause and resume.

The optional dead-end check rejects a prefix only if every slot of a must day has passed without that doctor appearing on the day. Such a mandatory assignment is impossible to insert later into that chronological prefix. This check does not assume that a currently available candidate will remain available, and does not change capacity, role, rest, boundary, substitution or objective rules. It is separate from existing capacity pruning. Both new controls propagate into the two-phase session; neither a budget stop nor lack of an incumbent authorizes phase B. No new objective bound is used.

The old search spends large numbers of candidate nodes before reaching a complete solution on these examples. This is measured, not proof of the relative CPU cost of individual internal functions. Prefix scans for mandatory days, rest and counts and per-node allocation are observable in code; their individual cost has not been profiled.

## One-million-node comparison

Sequential individual Dart VM 3.13.7 JIT runs on AMD EPYC 9V74. Each strategy used the same snapshot and budget; elapsed times exclude VM startup. First incumbent time is measured on the first 100-node observation boundary, and is thus an upper bound. `firstFeasibleNode` records the exact visited-node counter. All reported incumbents passed `SolutionValidator`.

| Doctors / days | Baseline | Ordering only | Dead-end only | Combined first time / node |
|---|---|---|---|---|
| 6 / 30 | none within 1M | none within 1M | none within 1M | ≤27.625 ms / 185 |
| 10 / 30 | none within 1M | none within 1M | none within 1M | ≤41.966 ms / 457 |
| 15 / 31 | none within 1M | none within 1M | none within 1M | ≤39.757 ms / 945 |
| 20 / 31 | none within 1M | none within 1M | none within 1M | ≤46.506 ms / 1575 |

All strategies exhausted the 1M-node budget without proving optimality. A direct speedup ratio cannot be calculated when the baseline first-solution time is unknown. Recorded first/last qualities and timings are in `results/stage_1_5b_nodes.json`.

The 30-day fixtures cover November 2026. The 31-day fixtures cover December 2026 and correct the 1.5A 31-day fixture, which straddled a month boundary. Strategies within each 1.5B comparison use the same snapshot; December results are not directly comparable to the former 1.5A 31-day snapshot.

## 30 and 120 second measurements

6 doctors: four sequential single-process runs. 10/15/20 doctors: one size at a time, four concurrent processes sharing 4 CPUs; a brief Dart analysis overlapped early 10-doctor run. 30s and 120s are checkpoints within each run. Timings are wall times; each observed incumbent was independently validated. All timed results were unproven; no run is reported as optimal. For each row the 30/120 values are statuses at the checkpoints of the same run, not independent repetitions.

| Doctors / days | Strategy | First upper bound ms / node | At 30s | At 120s | Nodes at 120s | Validator |
|---|---|---|---|---|---:|---|
| 6 / 30 | baseline | none | timeoutWithoutSolution | timeoutWithoutSolution | 701044893 | no incumbent |
| 6 / 30 | ordering | none | timeoutWithoutSolution | timeoutWithoutSolution | 139287442 | no incumbent |
| 6 / 30 | deadends | ≤558.742 / 2780416 | feasibleNotProven | feasibleNotProven | 222934267 | valid |
| 6 / 30 | combined | ≤29.528 / 185 | feasibleNotProven | feasibleNotProven | 27310238 | valid |
| 10 / 30 | baseline | none | timeoutWithoutSolution | timeoutWithoutSolution | 661750989 | no incumbent |
| 10 / 30 | ordering | none | timeoutWithoutSolution | timeoutWithoutSolution | 59422580 | no incumbent |
| 10 / 30 | deadends | none | paused | timeoutWithoutSolution | 616692956 | no incumbent |
| 10 / 30 | combined | ≤133.298 / 457 | feasibleNotProven | feasibleNotProven | 10082459 | valid |
| 15 / 31 | baseline | none | timeoutWithoutSolution | timeoutWithoutSolution | 770183181 | no incumbent |
| 15 / 31 | ordering | none | timeoutWithoutSolution | timeoutWithoutSolution | 36927696 | no incumbent |
| 15 / 31 | deadends | none | timeoutWithoutSolution | timeoutWithoutSolution | 676747182 | no incumbent |
| 15 / 31 | combined | ≤115.215 / 945 | feasibleNotProven | feasibleNotProven | 7085756 | valid |
| 20 / 31 | baseline | none | timeoutWithoutSolution | timeoutWithoutSolution | 814090039 | no incumbent |
| 20 / 31 | ordering | none | timeoutWithoutSolution | timeoutWithoutSolution | 26190206 | no incumbent |
| 20 / 31 | deadends | none | timeoutWithoutSolution | timeoutWithoutSolution | 677630199 | no incumbent |
| 20 / 31 | combined | ≤125.158 / 1575 | feasibleNotProven | feasibleNotProven | 5394348 | valid |

For the 6-doctor single-process run, combined first incumbent was observed by 29.528 ms, versus 558.742 ms for dead-end-only (about 18.9× relative to these observation upper bounds). Baseline and ordering-only did not find a first incumbent in 120 seconds; a finite speedup against them is therefore not established. The 10/15/20 results have CPU sharing and must not be treated as single-process latency. Raw snapshot, vectors, statuses, elapsed times and node counts are in `results/stage_1_5b_time.json`.
