# AKYS V2 1.7A — optimistic future REQUIRED domains

Base: 15791f5a67fd214e209cfdd35d33ed8269073d2e on
feature/akys-v2-solver-core, clean at start. Stage 1.6 benchmark and clinical
review were inspected. No quality/model/default/V1/Firebase changes.

## Algorithm and proof

`forwardChecking` is an explicit option on SearchSession and TransitionSession,
default false. It is independent of the existing pruning switches. At the first
budget-permitted run of each phase, scan every REQUIRED slot. After every allowed
candidate is appended to the actual DFS prefix, repeat for unassigned REQUIRED
slots. OPTIONAL slots are never obligations; an assigned OPTIONAL doctor still
consumes capacity/rest through the ordinary prefix checks. A/B inherit the switch
but independently evaluate their own root; existing B authorization is unchanged.

For a prefix P and future required slot s, the domain includes every doctor who:
- passes the existing `_allowed(doctor, s)` checks for forbidden dates, role and
  group eligibility under this phase, previous-month rest, prefix rest/duplicate
  prevention and remaining personal capacity;
- has no distinct mandatory day within less than three calendar days of s.
  Mandatory dates are immutable obligations, not guessed future assignments.

Problem construction already requires personal caps <= clinic cap. No candidate
is reserved for another future slot, and future optional attendance is not
assumed. Future must-day capacity is not reserved either. This is deliberately
optimistic: it can miss impossibility but cannot introduce it.

Proof: if a valid completion C extended P, its assignee d for s must pass every
listed condition. Prefix assignments persist in C; adding assignments cannot
undo unavailability, spent capacity, prior rest, roles or a distinct hard must
date. Thus C's assignee lies in the computed domain. An empty domain contradicts
the existence of C. OPTIONAL blanks do not invalidate this argument because
only required slots are demanded. Nonempty domains do NOT prove joint
feasibility: doctors can be shared across domains but cannot necessarily fill
all slots (same-day duplicates, aggregate capacity and rest).

A's empty senior domain proves only the restricted phase impossible. B may have
a junior candidate and must be checked separately after the trusted A verdict.
Root failure marks only that SearchSession complete; TransitionSession retains
its existing private stage-construction and local proof capability. Timeout,
node budget and cancellation are checked before root checking; they never create
proof. Pause/resume retains the prefix/cursors and completed root-check flag.
The experimental two-phase restart can reuse the unchanged root necessary
condition. Checks are synchronous/atomic, not preempted mid-scan: a time budget
can overshoot by one check. No UI/Worker timing guarantee is made.

Instrumentation: forwardChecks, forwardPruned, forwardRootPruned and
forwardCheckTicks. Root failures count in pruned prefixes but are not DFS
assignment attempts. totalVisitedNodes sums A+B; existing SearchResult node
counts remain phase-local for compatibility. Stopwatch ticks measure elapsed
check time INCLUDING its instrumentation, not dedicated per-function CPU time.
The benchmark also samples Linux /proc/self/stat user+system CPU ticks and
process RSS; these measure the whole process, not just this function.

## Independent verification

New tests cover first/middle/last-day empty domains, B-only junior eligibility,
prefix capacity/rest failure, previous-month rest, optional blanks and must,
multiple same-day required positions, individually nonempty but jointly
impossible domains, must-date compatibility, cancellation/budget guards and
resume. Two hundred new deterministic models (seed 170700), both switch states
and four strategies, are compared to independent exhaustive enumeration and a
separately implemented exact 19-component reference calculator (1,600 searches).
The oracle does not call `_allowed` or the new domain-check function. Every
observed incumbent is independently validated; no objective order is changed.

## Measurement plan

Same Stage 1.6 snapshots, no regenerated constraints: eight problematic cells
(four strategies x one-second/120-second budget), each off/on = 16 runs. Four
normal clinics 6/30,10/30,15/31,20/31 use bounded two-phase off/on = eight runs.
Total 24 runs, sequential separate VMs. Long off blocked cases cost at most
eight minutes; eight normal trials at most sixteen minutes. On blocked cases
are expected to terminate early. The 30s point is a checkpoint in the same 120s
trajectory; early exact results are labeled with actual proof time, not invented
later observations. This is a single repeat per cell, not a statistical claim.

One-second pilot: blocked/on proved impossible with zero DFS assignments and two
root rejections. Open cases found valid incumbents off/on. Check elapsed cost
ranged roughly 6–52 ms per second in the four on pilots; first-solution times were
noisy (about 30–44 ms). These pilot figures are not the final comparison.

`run_forward.py OUTPUT_DIR` requires clean committed source; atomic outputs are
source-checked and reused after interruption. Interrupted partial runs may need
repeating; complete outputs never do. No simultaneous benchmark VMs or tests
run during timing. Full snapshots, exact quality, assignments, proof status,
first/proof times, counters, CPU/RSS and source revision are retained.

## Completed results

Measurement source: `721475b90118cf738c44db9c7f9744879331b75a`.
All 24 paired cells completed sequentially, with no concurrent benchmark VM.
The old eight problem/budget cells are each measured off and on (16 runs).
Normal-clinic validation adds four sizes x off/on (eight runs), specifically
using bounded two-phase, not all four normal-clinic strategies. Same seed and
snapshots as Stage 1.6; results are new matched timings, not reused baselines.

All eight blocked/off trials remained TIMEOUT_NO_FEASIBLE and A=PENDING.
All eight blocked/on trials proved A and B infeasible in 9.874–16.333 ms,
with two empty-root rejections and zero DFS assignment attempts. Actual domain
check elapsed time was 0.745–1.523 ms. The larger end-to-end proof observation
includes cold execution and measurement overhead. No baseline proof time exists:
120 seconds is a timeout, so a precise speedup ratio would be misleading.

All eight normal-clinic runs found valid incumbents and remained
FEASIBLE_UNPROVEN. On/off clinical vectors matched at both 30 and 120 seconds
for every normal snapshot. No new clinical-scale optimality claim is made.
In this single trial, first solution was slower with checking for 6/10/20
and faster for 15 doctors. The 6-doctor increase was 24.652 to 36.175 ms; this
is a measurable sample regression, not evidence of a universal slowdown.
At 120s, forward checking eliminated 576,583 prefixes on 6 doctors and 13,516
on 10, but none on 15 or 20. Its measured elapsed share was respectively
4.76%, 2.06%, 0.68%, 0.19%. Fewer visited decisions is not by itself a speedup:
proof status, elapsed budget and incumbent quality must also be compared.

Environment: Linux 6.18.57 x86_64, AMD EPYC 9V74, five visible CPUs, cgroup
400000/100000 (four CPU equivalents); Dart 3.13.7 VM JIT. Fixed ordering off/on,
one repetition per cell, no CPU pinning, shared host. No profiler was used.
Solver check Stopwatch calls, first/observed incumbent independent validation,
reference quality calculations and CPU/RSS observations remain overhead.
Linux CPU ticks use CLK_TCK=100 and sum process user+system time across threads;
VM compiler/GC threads can make CPU time exceed elapsed wall time. A displayed
0.00s for a short proof is timer quantization, not zero CPU work. No dedicated
per-function CPU profiler was run; check-wall time is not mislabeled as CPU time.
Process peak RSS was 206.6–254.4 MiB and includes the VM. An early proof's RSS
cannot fairly establish memory savings against a 120s JIT-warmed run.

## Regression and independent evidence

Final `dart analyze lib/solver_v2 test/solver_v2 tool/solver_v2` and
`flutter analyze --no-pub`: no issues.
`flutter test --no-pub test/solver_v2 --reporter expanded`: **152 passed**,
comprising the original 136 and 16 new tests. The initial 150-test run passed
before measurement; two additional B role/optional-must boundary tests passed
in the final run. Measurement code and solver did not change between these runs.

The new seeded suite performs 1,600 completed searches (200 cases x on/off x
four strategies), checking feasibility, A/B outcome and all 19 exact reference
components against independent exhaustive enumeration. Existing oracle,
500-schedule quality-reference, bounds, evidence spoofing, cancellation, timeout
and pause/resume suites remain passing. Additional targeted cases show:
- root rejection of first/middle/last-day impossibility;
- B opens only after A proof and still rejects an ineligible junior senior role;
- prefix capacity/rest eliminates future REQUIRED domains;
- previous-month rest and exact-three-day must dates remain respected;
- OPTIONAL blanks remain legal; a junior must can be satisfied in an optional
  senior role in B without falsely pruning the empty optional domain;
- individually nonempty domains do not prove a shared doctor's simultaneous
  availability for multiple REQUIRED slots;
- zero budgets and cancellation perform no root proof; resumed search retains
  the incumbent, node cursor and final result;
- substitutions still cannot receive permanent approval.

No false OPTIMAL/INFEASIBLE or hard violation was found. Finite test coverage is
not a universal formal verification; the superset-domain proof above supplies
the mathematical argument. Stored verdicts are historical observations, not
portable certificates or authorization to persist substitution schedules.

## Limits and next steps

Keep the default false. This feature is available explicitly for experiments;
it does not change V1, UI, Firebase or production behavior. The full domain scan
is synchronous and can overshoot a deadline by one atomic check. It does not
solve Hall/matching constraints, reserve capacity for all future must dates, or
prove simultaneous feasibility when individual domains are nonempty. Existing
DFS remains responsible for those constraints. Runtime and memory results are
single JIT trials, not Web/Android guarantees or statistical estimates.

Next, separately benchmark root-only vs full-prefix checking and investigate
cached immutable eligibility domains/incremental prefix counts if cost matters.
Any such change needs its own independent oracle validation; none is implemented
here. Do not enable a production default solely from this targeted blocked-day
success. Repeated interleaved timings and additional normal strategies are needed
before making a broader performance/default decision.

Reproduce from the measurement commit with `run_forward.py OUTPUT_DIR`, then
`summarize_forward.py OUTPUT_DIR REPORT_DIR`. The runner checks source identity
and reuses completed files after interruption. The archive
`results/stage_1_7a_traces.json.gz` includes all 24 runs, full snapshots,
assignments, vectors, first/proof times, counters and CPU/RSS values. All old
benchmark data is retained. A later documentation/test commit does not change
the archived measurement source revision.
## Matched measurements

|Case|Strategy|Budget s|Check|First ms|Proof ms|DFS A+B|Forward rejects (root)|Check wall ms|Process CPU s|Peak RSS MiB|Final status|
|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
|10-open|bounded|120|off|28.720|—|65679070|0 (0)|0.000|120.57|245.9|feasibleNotProven|
|10-open|bounded|120|on|33.123|—|67679773|13516 (0)|2474.812|120.65|251.2|feasibleNotProven|
|15-blocked|bounded|1|off|—|—|393760|0 (0)|0.000|1.23|246.4|timeoutWithoutSolution|
|15-blocked|bounded|120|off|—|—|47816523|0 (0)|0.000|120.31|248.7|timeoutWithoutSolution|
|15-blocked|bounded|1|on|—|11.449|0|2 (2)|0.745|0.01|244.7|infeasible|
|15-blocked|bounded|120|on|—|10.614|0|2 (2)|0.977|0.01|219.1|infeasible|
|15-blocked|combined|1|off|—|—|375286|0 (0)|0.000|1.29|246.5|timeoutWithoutSolution|
|15-blocked|combined|120|off|—|—|46990450|0 (0)|0.000|120.30|247.0|timeoutWithoutSolution|
|15-blocked|combined|1|on|—|10.702|0|2 (2)|0.811|0.02|235.7|infeasible|
|15-blocked|combined|120|on|—|9.874|0|2 (2)|0.850|0.01|233.6|infeasible|
|15-blocked|deadends|1|off|—|—|5987748|0 (0)|0.000|1.15|247.7|timeoutWithoutSolution|
|15-blocked|deadends|120|off|—|—|806556694|0 (0)|0.000|120.36|244.1|timeoutWithoutSolution|
|15-blocked|deadends|1|on|—|11.712|0|2 (2)|0.946|0.01|206.6|infeasible|
|15-blocked|deadends|120|on|—|10.346|0|2 (2)|0.795|0.00|237.9|infeasible|
|15-blocked|twophase|1|off|—|—|389339|0 (0)|0.000|1.22|246.3|timeoutWithoutSolution|
|15-blocked|twophase|120|off|—|—|47332967|0 (0)|0.000|120.42|246.2|timeoutWithoutSolution|
|15-blocked|twophase|1|on|—|16.333|0|2 (2)|1.523|0.02|245.1|infeasible|
|15-blocked|twophase|120|on|—|11.895|0|2 (2)|0.881|0.01|225.5|infeasible|
|15-open|bounded|120|off|42.355|—|39010000|0 (0)|0.000|120.54|246.2|feasibleNotProven|
|15-open|bounded|120|on|37.724|—|39037313|0 (0)|816.819|120.70|249.9|feasibleNotProven|
|20-open|bounded|120|off|36.601|—|9136475|0 (0)|0.000|120.41|246.7|feasibleNotProven|
|20-open|bounded|120|on|37.646|—|9137730|0 (0)|225.228|120.53|254.4|feasibleNotProven|
|6-open|bounded|120|off|24.652|—|91110238|0 (0)|0.000|120.56|248.4|feasibleNotProven|
|6-open|bounded|120|on|36.175|—|74152104|576583 (0)|5718.016|120.64|246.8|feasibleNotProven|

## Exact clinical vectors and OPTIONAL coverage

|Case|Strategy|Budget|Check|First quality|30s or early terminal/1s diagnostic|120s if reached|OPTIONAL first checkpoint → last|
|---|---|---:|---|---|---|---|---|
|10-open|bounded|120|off|`0,0,0,-12,0,0,-18,2,2,2,2,2,2,3,3,1/4,1/4,12,36`|`0,-23,0,-13,0,0,-17,2,3,2,4,3,5,2,3,3/8,1/2,19,37`|`0,-23,0,-13,0,0,-17,2,3,2,3,3,5,2,3,3/8,1/2,19,37`|23 → 23|
|10-open|bounded|120|on|`0,0,0,-12,0,0,-18,2,2,2,2,2,2,3,3,1/4,1/4,12,36`|`0,-23,0,-13,0,0,-17,2,3,2,4,3,5,2,3,3/8,1/2,19,37`|`0,-23,0,-13,0,0,-17,2,3,2,3,3,5,2,3,3/8,1/2,19,37`|23 → 23|
|15-blocked|bounded|1|off|—|—|not separately measured|None → None|
|15-blocked|bounded|120|off|—|—|—|None → None|
|15-blocked|bounded|1|on|—|—|not separately measured|None → None|
|15-blocked|bounded|120|on|—|—|not separately measured|None → None|
|15-blocked|combined|1|off|—|—|not separately measured|None → None|
|15-blocked|combined|120|off|—|—|—|None → None|
|15-blocked|combined|1|on|—|—|not separately measured|None → None|
|15-blocked|combined|120|on|—|—|not separately measured|None → None|
|15-blocked|deadends|1|off|—|—|not separately measured|None → None|
|15-blocked|deadends|120|off|—|—|—|None → None|
|15-blocked|deadends|1|on|—|—|not separately measured|None → None|
|15-blocked|deadends|120|on|—|—|not separately measured|None → None|
|15-blocked|twophase|1|off|—|—|not separately measured|None → None|
|15-blocked|twophase|120|off|—|—|—|None → None|
|15-blocked|twophase|1|on|—|—|not separately measured|None → None|
|15-blocked|twophase|120|on|—|—|not separately measured|None → None|
|15-open|bounded|120|off|`0,0,0,-15,0,0,-16,2,2,3,3,1,1,3,3,5/24,5/24,21,36`|`0,-27,-18,-18,0,0,-13,2,3,2,4,1,2,4,7,1/2,1/2,30,38`|`0,-27,-18,-18,0,0,-13,2,3,2,4,1,2,3,6,1/2,1/2,30,38`|45 → 45|
|15-open|bounded|120|on|`0,0,0,-15,0,0,-16,2,2,3,3,1,1,3,3,5/24,5/24,21,36`|`0,-27,-18,-18,0,0,-13,2,3,2,4,1,2,4,7,1/2,1/2,30,38`|`0,-27,-18,-18,0,0,-13,2,3,2,4,1,2,3,6,1/2,1/2,30,38`|45 → 45|
|20-open|bounded|120|off|`0,0,0,-18,0,0,-13,2,2,2,2,1,1,2,2,1/2,1/2,17,26`|`0,-31,0,-19,0,0,-12,2,3,2,3,1,2,2,3,5/8,9/8,17,26`|`0,-31,0,-19,0,0,-12,1,2,2,3,1,2,2,3,5/8,9/8,17,26`|31 → 31|
|20-open|bounded|120|on|`0,0,0,-18,0,0,-13,2,2,2,2,1,1,2,2,1/2,1/2,17,26`|`0,-31,0,-19,0,0,-12,2,3,2,3,1,2,2,3,5/8,9/8,17,26`|`0,-31,0,-19,0,0,-12,1,2,2,3,1,2,2,3,5/8,9/8,17,26`|31 → 31|
|6-open|bounded|120|off|`0,0,0,-7,0,0,-23,2,2,2,2,3,3,2,2,1/8,1/8,6,40`|`0,-13,0,-8,0,0,-22,2,2,2,2,2,2,2,2,1/8,1/8,8,42`|`0,-13,0,-8,0,0,-22,0,0,2,2,3,3,2,2,1/8,1/8,10,42`|13 → 13|
|6-open|bounded|120|on|`0,0,0,-7,0,0,-23,2,2,2,2,3,3,2,2,1/8,1/8,6,40`|`0,-13,0,-8,0,0,-22,2,2,2,2,2,2,2,2,1/8,1/8,8,42`|`0,-13,0,-8,0,0,-22,0,0,2,2,3,3,2,2,1/8,1/8,10,42`|13 → 13|

## Normal-clinic on/off comparisons

|Case|First ms off → on|30s quality on vs off|120s quality on vs off|Nodes off → on|Check share of elapsed 120s|
|---|---|---|---|---|---|
|6-open|24.652 → 36.175|equal|equal|91110238 → 74152104|4.76%|
|10-open|28.720 → 33.123|equal|equal|65679070 → 67679773|2.06%|
|15-open|42.355 → 37.724|equal|equal|39010000 → 39037313|0.68%|
|20-open|36.601 → 37.646|equal|equal|9136475 → 9137730|0.19%|
