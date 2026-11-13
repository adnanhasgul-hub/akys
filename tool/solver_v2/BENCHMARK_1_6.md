# AKYS V2 1.6 — clinical resilience validation

Starting revision: b53549737b733baf2c8ad62e69c45edf14a8326a.
Only fixture, measurement, test and reporting code changes; solver and defaults
remain unchanged. Seed 160600 is used for end-of-month restrictions and the new
200-case oracle suite; the underlying reproducible fixture generator retains
seed 150300. Neither seed represents real personnel or patients.

## Planned matrix and resource budget

Four open synthetic clinics (6/30, 10/30, 15/31, 20/31) add end-of-month cannot
constraints and concentrated K1/K4 levels to the earlier mixed/surplus templates.
They retain previous-month rest, heterogeneous personal caps, required senior
positions, optional junior positions and explicitly synthetic holiday scores.
Four tight variants force every required day with must/cannot dates and exact
personal caps; optional positions are impossible because all capacity is used.
A 6-doctor transition variant changes the forced day-0/4/... doctor to junior:
A is impossible, and exactly eight B substitutions are necessary. A 10-doctor
zero-capacity case is impossible by total capacity. A 15-doctor blocked-last-day
case is impossible independently because no doctor is available that day, but
bounded search may remain UNKNOWN. A 20-doctor must/cannot conflict is invalid
input, not a mathematical infeasibility result, and is tested before search.
Small exhaustive tests add fully/partly fillable optional positions and exact
2-versus-3-day previous-month boundary cases.

Preflight: one-second bounded trials found first solutions for all four open
fixtures in about 18–28 ms. Tight and transition cases completed in about 30–40
ms. Capacity infeasibility completed in about 4 ms. Blocked-last-day remained
unknown after one second. These are pilot observations, not final comparisons.
The pilot revealed a nullable fixture-map construction issue, fixed before the
measurement source commit. Test expectations were also corrected to distinguish
node-budget PAUSED from wall-time TIMEOUT and to respect completed B contexts;
no production behavior was changed to satisfy tests.

Plan: four strategies, sequential separate Dart VM processes. Open and tight,
transition and capacity cases have a 120-second maximum, with a 30-second
checkpoint when still running; blocked-last-day has a separate one-second
budget. Invalid conflict runs as a construction test. Expected long-run time
is 16 x 120 seconds = 32 minutes plus terminal runs, compilation and startup.
A 180-second external watchdog guards each 120-second process. No concurrent
benchmark processes; tests run before or after timing. One timing repetition
per cell in this expanded validation matrix; the previous three-repeat 1.5F
results are preserved but are not pooled with these different snapshots.

`run_resilience.py OUTPUT_DIR` requires a clean committed source, verifies source
revision before reusing outputs, writes each run to a temporary file, flushes
and atomically renames it. Completed runs survive interruption and are reused;
an interrupted in-flight run can require repetition. Full snapshots and source
revision are in every JSON. Exact 19-component reference calculation checks
first and observed incumbents; production independent SolutionValidator checks
every complete candidate before quality evaluation. Each observed incumbent is
additionally validated. No claim of timing every intermediate incumbent is made:
run calls process up to 1024 nodes. The strict replacement count comes from the
session. Profiling is off; validation/reference arithmetic and counters remain
part of timing. RSS is process-wide, not solver-only allocation.

## Completed execution and regression evidence

Measurement source: `f71e8635f93c078d050a96c7921c10f32f7f0f24`.
44 planned primary/short-diagnostic runs completed, then the four blocked-day
runs were extended in separate, sequential 120-second processes (48 formal runs
total, plus the preflight pilot). Their one-second outputs were retained, not
overwritten. This added at most eight minutes: approximately 40 minutes of
long-run search budget, plus terminal runs/startup. All outputs survived the
subsequent environment restart; no completed measurements were repeated.

Environment: Linux 6.18.57 x86_64, AMD EPYC 9V74, five visible CPUs with cgroup
quota 400000/100000 (four CPU equivalents), Dart 3.13.7 VM JIT. Only one benchmark
VM ran at a time. The host was not CPU-pinned; order was fixed, not randomized.
No profiler, AOT, Flutter UI or mobile/Web benchmark was used. Startup/snapshot
construction are outside the search clock. These measurements include additional
independent reference checks and must not be treated as pure solver timings or
compared as speed ratios against different 1.5F snapshots/instrumentation.

Results: 20 OPTIMAL (16 tightly forced, four forced-transition), four INFEASIBLE
(zero capacity), 16 FEASIBLE_UNPROVEN (open clinics), eight TIMEOUT_NO_FEASIBLE
(four one-second and four 120-second blocked-day trials). The separate invalid
must/cannot case was rejected before search and was never called INFEASIBLE.
No hard violation or reference-vector mismatch was detected. All open first
solutions arrived in 16.407–29.360 ms. None of the open clinical trials proved
optimality. Maximum observed checkpoint overshoot was 1,861 microseconds.
Peak process RSS was 199.2–265.4 MiB; short runs and JIT startup make this unsuitable
for concluding that one algorithm intrinsically needs less memory.

The forced-transition witness requires the same junior on day indices
0,4,8,12,16,20,24,28. All other doctors are forbidden on those dates. Thus A is
independently impossible and B needs exactly eight transitions, not merely a
solver-reported optimum. The four long blocked-day runs retained A=PENDING at
both checkpoints: no incumbent, no B authorization, no false impossibility proof.
Independent reasoning establishes infeasibility (all doctors forbidden on the
last required day); the solver itself did not establish it within budget.

Verification before timed runs:
- `dart analyze lib/solver_v2 test/solver_v2 tool/solver_v2`: no issues.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub test/solver_v2 --reporter expanded`: **136 passed**,
  including the previous 115 and 21 new tests.
- New 200-seed cases compare all four strategies (800 searches) to independent
  exhaustive enumeration and the second reference quality implementation.
- Existing 200-case strategy/A-B/oracle suites, 500 quality references, bound
  safety, timeout, cancellation and pause/resume regressions remain passing.
- New cases cover full/partial OPTIONAL coverage, exact calendar rest boundary,
  dense constraints, invalid conflict classification, forced minimum transition,
  no permanent approval for substitutions, and no false optimum on blocked days.
- No tests were disabled. Initial new-test failures were API-expectation issues:
  node-budget PAUSED, terminal CANCELLED phase, and attempting active-B candidate
  evaluation after completion. The independent oracle now calculates quality
  directly with the separate reference implementation, not an active-B bypass.

Reproduction: check out the measurement source and use `run_resilience.py DIR`
for the 44-cell matrix. Run `resilience_compare.dart 15-blocked STRATEGY 120`
sequentially for the four extended cells, writing each to a temporary file and
renaming only after successful completion; keep the shorter results separately.
`summarize_resilience.py MAIN_DIR EXTENDED_DIR OUTPUT_DIR` verifies all 48 records,
source and snapshots and regenerates the tables/archive. The archived source
revision is the measurement revision, not the later documentation commit.
`results/stage_1_6_traces.json.gz` contains all raw runs and descriptive per-person
statistics. No existing benchmark outputs were removed.

The following tables separate measured results from the clinical interpretation
in `CLINICAL_REVIEW_1_6.md`. Every vector uses exact rational strings; all
components are compared in minimization form without weights or tolerance.
## Final matrix

|Case|Senior / junior|Required / optional|Must / cannot entries|
|---|---|---|---|
|10-capacity|5 / 5|30 / 30|0 / 60|
|10-open|5 / 5|30 / 30|8 / 78|
|10-tight|5 / 5|30 / 30|30 / 270|
|15-blocked|6 / 9|31 / 62|8 / 108|
|15-open|6 / 9|31 / 62|8 / 121|
|15-tight|6 / 9|31 / 62|31 / 434|
|20-open|8 / 12|31 / 31|8 / 164|
|20-tight|8 / 12|31 / 31|31 / 589|
|6-open|4 / 2|30 / 30|8 / 42|
|6-tight|4 / 2|30 / 30|30 / 150|
|6-transition|3 / 3|30 / 30|30 / 150|

## Performance (one repetition per cell)

|Case / budget|Strategy|First ms|Final elapsed s|Nodes|Pruned prefixes|Optional filled|Improvements|Peak RSS MiB|Status / restricted verdict|
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
|10-capacity / 120s|bounded|—|0.003|10|0|None|0|203.7|infeasible / provenInfeasible|
|10-capacity / 120s|combined|—|0.005|10|0|None|0|242.0|infeasible / provenInfeasible|
|10-capacity / 120s|deadends|—|0.002|10|0|None|0|244.2|infeasible / provenInfeasible|
|10-capacity / 120s|twophase|—|0.003|10|0|None|0|199.2|infeasible / provenInfeasible|
|10-open / 120s|bounded|18.99|120.000|65586247|2496748|23|24|253.5|feasibleNotProven / feasible|
|10-open / 120s|combined|22.16|120.000|25576417|0|9|71|265.4|feasibleNotProven / feasible|
|10-open / 120s|deadends|20.25|120.000|95138320|13|24|21|256.5|feasibleNotProven / feasible|
|10-open / 120s|twophase|28.32|120.000|39577322|0|23|21|249.4|feasibleNotProven / feasible|
|10-tight / 120s|bounded|22.82|0.035|690|0|0|0|244.7|optimal / feasible|
|10-tight / 120s|combined|33.19|0.049|630|0|0|0|227.8|optimal / feasible|
|10-tight / 120s|deadends|17.68|0.019|630|0|0|0|245.2|optimal / feasible|
|10-tight / 120s|twophase|24.01|0.038|690|0|0|0|235.0|optimal / feasible|
|15-blocked / 1s|bounded|—|1.001|403445|0|None|0|242.3|timeoutWithoutSolution / pending|
|15-blocked / 1s|combined|—|1.001|347299|0|None|0|244.5|timeoutWithoutSolution / pending|
|15-blocked / 1s|deadends|—|1.001|5839411|104|None|0|244.8|timeoutWithoutSolution / pending|
|15-blocked / 1s|twophase|—|1.002|354701|0|None|0|244.7|timeoutWithoutSolution / pending|
|15-open / 120s|bounded|22.21|120.000|39832415|668448|45|38|253.6|feasibleNotProven / feasible|
|15-open / 120s|combined|24.98|120.000|12574602|0|8|57|262.6|feasibleNotProven / feasible|
|15-open / 120s|deadends|23.37|120.000|82133809|104|45|12|257.1|feasibleNotProven / feasible|
|15-open / 120s|twophase|29.36|120.000|30395337|0|45|36|246.8|feasibleNotProven / feasible|
|15-tight / 120s|bounded|21.74|0.036|1550|0|0|0|245.0|optimal / feasible|
|15-tight / 120s|combined|21.41|0.032|1457|0|0|0|230.9|optimal / feasible|
|15-tight / 120s|deadends|21.00|0.022|1457|0|0|0|244.8|optimal / feasible|
|15-tight / 120s|twophase|31.19|0.047|1550|0|0|0|244.8|optimal / feasible|
|20-open / 120s|bounded|24.68|120.000|9290384|350747|31|12|255.9|feasibleNotProven / feasible|
|20-open / 120s|combined|25.79|120.000|8814023|0|6|33|250.4|feasibleNotProven / feasible|
|20-open / 120s|deadends|19.97|120.000|14794861|36|31|9|255.9|feasibleNotProven / feasible|
|20-open / 120s|twophase|27.38|120.000|8245926|0|31|5|255.6|feasibleNotProven / feasible|
|20-tight / 120s|bounded|22.79|0.036|1333|0|0|0|245.0|optimal / feasible|
|20-tight / 120s|combined|22.23|0.033|1271|0|0|0|225.0|optimal / feasible|
|20-tight / 120s|deadends|19.82|0.022|1271|0|0|0|242.4|optimal / feasible|
|20-tight / 120s|twophase|22.06|0.038|1333|0|0|0|242.2|optimal / feasible|
|6-open / 120s|bounded|16.41|120.000|93491853|1200290|13|15|260.5|feasibleNotProven / feasible|
|6-open / 120s|combined|17.31|120.000|62301791|0|10|52|249.4|feasibleNotProven / feasible|
|6-open / 120s|deadends|29.18|120.000|160572171|7|13|18|258.1|feasibleNotProven / feasible|
|6-open / 120s|twophase|17.31|120.000|92698907|0|13|15|261.0|feasibleNotProven / feasible|
|6-tight / 120s|bounded|27.08|0.041|450|0|0|0|244.8|optimal / feasible|
|6-tight / 120s|combined|29.25|0.035|390|0|0|0|218.5|optimal / feasible|
|6-tight / 120s|deadends|16.94|0.018|390|0|0|0|226.0|optimal / feasible|
|6-tight / 120s|twophase|20.21|0.027|450|0|0|0|227.5|optimal / feasible|
|6-transition / 120s|bounded|25.89|0.036|450|0|0|0|245.0|optimal / provenInfeasible|
|6-transition / 120s|combined|23.66|0.028|390|0|0|0|241.9|optimal / provenInfeasible|
|6-transition / 120s|deadends|29.05|0.031|390|0|0|0|243.9|optimal / provenInfeasible|
|6-transition / 120s|twophase|24.84|0.032|450|0|0|0|244.9|optimal / provenInfeasible|
|15-blocked / 120s|bounded|—|120.000|47865957|0|None|0|246.0|timeoutWithoutSolution / pending|
|15-blocked / 120s|combined|—|120.000|48038465|0|None|0|246.1|timeoutWithoutSolution / pending|
|15-blocked / 120s|deadends|—|120.000|815353380|104|None|0|245.1|timeoutWithoutSolution / pending|
|15-blocked / 120s|twophase|—|120.000|45076295|0|None|0|246.0|timeoutWithoutSolution / pending|

## Exact quality vectors

A single early terminal mark denotes a proof at its actual elapsed time, not a separate 30/120-second measurement.

|Case|Strategy|First|30s or early terminal|120s (if still running)|
|---|---|---|---|---|
|10-capacity / 120s|bounded|—|—|terminal or 1s diagnostic; not measured|
|10-capacity / 120s|combined|—|—|terminal or 1s diagnostic; not measured|
|10-capacity / 120s|deadends|—|—|terminal or 1s diagnostic; not measured|
|10-capacity / 120s|twophase|—|—|terminal or 1s diagnostic; not measured|
|10-open / 120s|bounded|`0,0,0,-12,0,0,-18,2,2,2,2,2,2,3,3,1/4,1/4,12,36`|`0,-23,0,-13,0,0,-17,2,3,2,4,3,5,2,3,3/8,1/2,19,37`|`0,-23,0,-13,0,0,-17,2,3,2,3,3,5,2,3,3/8,1/2,19,37`|
|10-open / 120s|combined|`0,0,0,-12,0,0,-18,2,2,2,2,2,2,3,3,1/4,1/4,12,36`|`0,-8,0,-12,0,0,-18,2,3,2,3,2,3,3,4,1/4,1/2,9,33`|`0,-9,0,-12,0,0,-18,2,3,2,3,2,3,3,4,1/4,1/2,11,33`|
|10-open / 120s|deadends|`0,-24,0,-6,0,0,-24,2,3,3,4,2,4,3,5,5/6,5/6,40,43`|`0,-24,0,-9,0,0,-21,1,2,2,3,2,4,2,3,3/8,3/8,29,38`|`0,-24,0,-9,0,0,-21,1,2,2,3,2,4,2,3,3/8,3/8,29,38`|
|10-open / 120s|twophase|`0,0,0,-12,0,0,-18,2,2,2,2,2,2,3,3,1/4,1/4,12,36`|`0,-23,0,-12,0,0,-18,2,3,2,3,3,5,2,3,1/4,3/8,19,33`|`0,-23,0,-13,0,0,-17,2,3,2,4,3,5,2,3,3/8,1/2,19,37`|
|10-tight / 120s|bounded|`0,0,0,-8,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|`0,0,0,-8,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|terminal or 1s diagnostic; not measured|
|10-tight / 120s|combined|`0,0,0,-8,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|`0,0,0,-8,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|terminal or 1s diagnostic; not measured|
|10-tight / 120s|deadends|`0,0,0,-8,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|`0,0,0,-8,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|terminal or 1s diagnostic; not measured|
|10-tight / 120s|twophase|`0,0,0,-8,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|`0,0,0,-8,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|terminal or 1s diagnostic; not measured|
|15-blocked / 1s|bounded|—|—|terminal or 1s diagnostic; not measured|
|15-blocked / 1s|combined|—|—|terminal or 1s diagnostic; not measured|
|15-blocked / 1s|deadends|—|—|terminal or 1s diagnostic; not measured|
|15-blocked / 1s|twophase|—|—|terminal or 1s diagnostic; not measured|
|15-open / 120s|bounded|`0,0,0,-15,0,0,-16,2,2,3,3,1,1,3,3,5/24,5/24,21,36`|`0,-27,-18,-18,0,0,-13,2,3,2,4,1,2,4,7,1/2,1/2,30,38`|`0,-27,-18,-18,0,0,-13,2,3,2,4,1,2,3,6,1/2,1/2,30,38`|
|15-open / 120s|combined|`0,0,0,-15,0,0,-16,2,2,3,3,1,1,3,3,5/24,5/24,21,36`|`0,-4,-3,-15,0,0,-16,2,2,3,3,1,1,3,4,1/4,11/24,20,36`|`0,-4,-4,-15,0,0,-16,2,2,3,3,1,1,3,4,1/3,13/24,20,36`|
|15-open / 120s|deadends|`0,-27,-18,-7,0,0,-24,2,3,3,5,2,4,3,6,5/6,5/6,46,47`|`0,-28,-17,-10,0,0,-21,2,3,3,5,2,4,3,5,33/56,33/56,33,41`|`0,-28,-17,-10,0,0,-21,2,3,3,5,2,4,3,5,33/56,33/56,33,41`|
|15-open / 120s|twophase|`0,0,0,-15,0,0,-16,2,2,3,3,1,1,3,3,5/24,5/24,21,36`|`0,-27,-18,-17,0,0,-14,2,3,2,4,1,2,4,7,1/2,1/2,32,40`|`0,-27,-18,-18,0,0,-13,2,3,2,4,1,2,4,7,1/2,1/2,30,38`|
|15-tight / 120s|bounded|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|terminal or 1s diagnostic; not measured|
|15-tight / 120s|combined|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|terminal or 1s diagnostic; not measured|
|15-tight / 120s|deadends|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|terminal or 1s diagnostic; not measured|
|15-tight / 120s|twophase|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|terminal or 1s diagnostic; not measured|
|20-open / 120s|bounded|`0,0,0,-18,0,0,-13,2,2,2,2,1,1,2,2,1/2,1/2,17,26`|`0,-31,0,-19,0,0,-12,2,3,2,3,1,2,2,3,5/8,9/8,17,26`|`0,-31,0,-19,0,0,-12,1,2,2,3,1,2,2,3,5/8,9/8,17,26`|
|20-open / 120s|combined|`0,0,0,-18,0,0,-13,2,2,2,2,1,1,2,2,1/2,1/2,17,26`|`0,-5,0,-19,0,0,-12,2,2,2,2,1,2,2,3,1/2,7/10,17,26`|`0,-6,0,-19,0,0,-12,2,3,2,2,1,2,2,3,1/2,5/6,17,26`|
|20-open / 120s|deadends|`0,-31,0,-7,0,0,-24,2,3,3,5,2,3,3,5,1,2,47,47`|`0,-31,0,-8,0,0,-23,2,3,3,5,2,3,3,5,6/7,12/7,44,47`|`0,-31,0,-9,0,0,-22,2,3,3,5,2,3,3,5,6/7,71/42,44,47`|
|20-open / 120s|twophase|`0,0,0,-18,0,0,-13,2,2,2,2,1,1,2,2,1/2,1/2,17,26`|`0,-31,0,-19,0,0,-12,2,3,2,3,1,2,2,3,5/8,9/8,17,26`|`0,-31,0,-19,0,0,-12,2,3,2,3,1,2,2,3,5/8,9/8,17,26`|
|20-tight / 120s|bounded|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|terminal or 1s diagnostic; not measured|
|20-tight / 120s|combined|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|terminal or 1s diagnostic; not measured|
|20-tight / 120s|deadends|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|terminal or 1s diagnostic; not measured|
|20-tight / 120s|twophase|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|`0,0,0,-8,0,0,-23,1,1,1,1,1,1,2,2,0,0,51,51`|terminal or 1s diagnostic; not measured|
|6-open / 120s|bounded|`0,0,0,-7,0,0,-23,2,2,2,2,3,3,2,2,1/8,1/8,6,40`|`0,-13,0,-8,0,0,-22,2,2,2,2,2,2,2,2,1/8,1/8,8,42`|`0,-13,0,-8,0,0,-22,0,0,2,2,3,3,2,2,1/8,1/8,10,42`|
|6-open / 120s|combined|`0,0,0,-7,0,0,-23,2,2,2,2,3,3,2,2,1/8,1/8,6,40`|`0,-10,0,-7,0,0,-23,2,2,2,3,2,2,2,2,1/8,41/168,9,40`|`0,-10,0,-8,0,0,-22,2,2,2,3,2,2,2,2,1/8,41/168,10,42`|
|6-open / 120s|deadends|`0,-13,0,-6,0,0,-24,3,3,3,3,4,4,2,3,1/4,1/4,14,43`|`0,-13,0,-7,0,0,-23,0,0,2,2,3,3,2,2,1/8,1/8,13,44`|`0,-13,0,-8,0,0,-22,0,0,2,2,3,3,2,2,1/8,1/8,10,42`|
|6-open / 120s|twophase|`0,0,0,-7,0,0,-23,2,2,2,2,3,3,2,2,1/8,1/8,6,40`|`0,-13,0,-8,0,0,-22,2,2,2,2,2,2,2,2,1/8,1/8,8,42`|`0,-13,0,-8,0,0,-22,0,0,2,2,3,3,2,2,1/8,1/8,10,42`|
|6-tight / 120s|bounded|`0,0,0,-8,0,0,-22,0,0,0,0,1,1,0,0,0,0,25,55`|`0,0,0,-8,0,0,-22,0,0,0,0,1,1,0,0,0,0,25,55`|terminal or 1s diagnostic; not measured|
|6-tight / 120s|combined|`0,0,0,-8,0,0,-22,0,0,0,0,1,1,0,0,0,0,25,55`|`0,0,0,-8,0,0,-22,0,0,0,0,1,1,0,0,0,0,25,55`|terminal or 1s diagnostic; not measured|
|6-tight / 120s|deadends|`0,0,0,-8,0,0,-22,0,0,0,0,1,1,0,0,0,0,25,55`|`0,0,0,-8,0,0,-22,0,0,0,0,1,1,0,0,0,0,25,55`|terminal or 1s diagnostic; not measured|
|6-tight / 120s|twophase|`0,0,0,-8,0,0,-22,0,0,0,0,1,1,0,0,0,0,25,55`|`0,0,0,-8,0,0,-22,0,0,0,0,1,1,0,0,0,0,25,55`|terminal or 1s diagnostic; not measured|
|6-transition / 120s|bounded|`8,-8,0,0,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|`8,-8,0,0,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|terminal or 1s diagnostic; not measured|
|6-transition / 120s|combined|`8,-8,0,0,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|`8,-8,0,0,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|terminal or 1s diagnostic; not measured|
|6-transition / 120s|deadends|`8,-8,0,0,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|`8,-8,0,0,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|terminal or 1s diagnostic; not measured|
|6-transition / 120s|twophase|`8,-8,0,0,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|`8,-8,0,0,0,0,-22,1,1,1,1,2,2,1,1,0,0,55,55`|terminal or 1s diagnostic; not measured|
|15-blocked / 120s|bounded|—|—|—|
|15-blocked / 120s|combined|—|—|—|
|15-blocked / 120s|deadends|—|—|—|
|15-blocked / 120s|twophase|—|—|—|

## Within-snapshot lexicographic winners

|Case|30 seconds|120 seconds|
|---|---|---|
|6-open|bounded, twophase|bounded, deadends, twophase|
|10-open|deadends|deadends|
|15-open|deadends|deadends|
|20-open|bounded, twophase|bounded|

Archived A/B verdicts are historical process observations, not transferable proof
certificates. Deserializing these JSON records does not authorize substitutions
or permanent approval. The trusted in-process evidence boundary remains intact.

Changed files in this stage: `clinical_resilience.dart`, `resilience_compare.dart`,
`run_resilience.py`, `summarize_resilience.py`, `BENCHMARK_1_6.md`,
`CLINICAL_REVIEW_1_6.md`, `results/stage_1_6_traces.json.gz` under
`tool/solver_v2/`, and `test/solver_v2/clinical_resilience_test.dart`.
