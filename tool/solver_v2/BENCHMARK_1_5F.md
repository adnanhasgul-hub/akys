# AKYS V2 1.5F — isolated strategy comparison

Baseline `b77fe55c9318ba940f8f0a0b967b9eb448960968`. This study does not change search objectives, pruning rules or strategy defaults. Each benchmark runs in its own Dart VM process and no other benchmark process overlaps it. The 30- and 120-second values are checkpoints in the same run, not separate repetitions. Three repeats are required per strategy and fixture; a completed exact search is recorded as such rather than waiting out the budget.

Fixture seed 150300, from `quality_trace.dart`, with independently validated hard-constraint witness: 6/30 `mixed`, 10/30 `ratio`, 15/31 `surplus`, 20/31 `rank`. They cover changing group ratios, K-level patterns, dense must/cannot, previous-month boundaries, varied caps, holiday scores and additional optional slots. The `rank` fixture varies the separate `seniorityRank` field; V2 quality presently uses K-level rather than that field. Some fixtures have repeated K levels across senior doctors; this limits clinical representativeness.

`isolated_compare.dart` runs up to 1,024 nodes per invocation and records the first incumbent via a one-time observer. No `SearchProfile` is used. Every clinical candidate is checked by the independently implemented `SolutionValidator` inside `ClinicalQualityEvaluator`; each observed incumbent is additionally checked by the benchmark. Strict incumbent replacement count is obtained from the search session. The Q1–Q3 bounded strategy includes its built-in per-check bound stopwatch. Mandatory-day, feasibility and Q1–Q3 prefix-prune counts are recorded separately. Candidates rejected by the immediate hard-eligibility check are not included in those prefix-prune counters. Current and peak process RSS are sampled at each checkpoint; peak includes the Dart VM and is not solver-only memory. A partial search is never called optimal.

Environment: Linux 6.18.57 x86_64, AMD EPYC 9V74, cgroup quota four CPUs, Dart 3.13.7 VM JIT. Exactly one benchmark VM ran at any time. VM startup and snapshot construction are outside the elapsed search clock; observed incumbent validation is included. No release/AOT comparison is claimed. RSS is process-wide and does not isolate solver allocations.

For interruption-safe execution, commit the measurement tooling, activate the Flutter SDK and run `tool/solver_v2/run_isolated.sh /workspace/akys-v15f-results`. It checks a clean working tree and refuses to reuse results with a different source revision. Each output is written atomically; `sourceRevision` is retained per run. Generate tables only after all 48 runs with `python3 tool/solver_v2/summarize_isolated.py /workspace/akys-v15f-results /workspace/akys-v15f-summary`.

## Final evidence and decision

All 48 sequential runs completed before the environment restart. Their source is
`6372cd3c6ef518f289a087332c71086b1e17a77b`; results were recovered intact and
checked for identical snapshots and source revision. No timing runs were repeated
on the restarted host. The archive `results/stage_1_5f_traces.json.gz` contains all
48 raw measurements and four deduplicated snapshots, including all repetitions'
first/30/120-second exact vectors, RSS, counts, runtime and proof flags.

| Fixture | Senior / junior | Required / optional slots | Seed |
|---|---|---|---|
| 6 doctors / 30 days, mixed | 4 / 2 | 30 / 30 | 150300 |
| 10 doctors / 30 days, ratio | 4 / 6 | 30 / 30 | 150300 |
| 15 doctors / 31 days, surplus | 6 / 9 | 31 / 62 | 150300 |
| 20 doctors / 31 days, rank | 8 / 12 | 31 / 31 | 150300 |

All runs found a valid incumbent in 16.39–51.97 ms. All 96 checkpoints were in
restricted stage A with `feasibleNotProven`; B never opened. No clinical-scale
optimum or infeasibility proof was obtained. Small oracle tests, rather than these
four feasible fixtures, cover B, cancellation and proof correctness.

At both deadlines and in all three repeats, deadends won on 6 and 15 doctors,
bounded won on 10 doctors, and bounded tied twophase on 20 doctors. These are
exact lexicographic comparisons within each snapshot, not weighted scores.
For 6 doctors bounded and twophase tie, both losing to deadends on Saturday
fairness despite their smaller difficulty spread. For 15 doctors deadends covers
28 junior days versus bounded's 27 and twophase's 26 at 120 seconds. All fill 45
optional positions: total occupancy alone would conceal the higher-priority
coverage difference. Combined's 120-second occupancy is only 9/7/7/5 across the
four scales despite many incumbent replacements; replacement count alone is not
quality. First solutions for combined/twophase/bounded leave all optional slots
empty, while deadends already covers 13/28/27/31 junior days.

Single candidate recommendation: **two-phase + safe Q1–Q3 bounds (bounded)**
for the next clinical acceptance evaluation, not an automatic default change.
It retains fast first solutions at all scales, beats combined everywhere, never
loses to unbounded twophase here, and wins or ties on two of four fixtures.
Its weaknesses are the 6-doctor Saturday distribution and 15-doctor junior-day
coverage compared with deadends. Keep deadends as a quality alternative,
twophase as a bound-overhead control, combined as a first-feasibility reference,
and baseline as the mathematical regression reference. Four correlated synthetic
fixtures do not justify a universal clinical default; the existing default stays
unchanged. No dynamic selector is added.

## Measurement limitations

The fixed sequence deadends/combined/twophase/bounded was repeated three times
per fixture; it was not randomized or CPU-pinned. Shared-host scheduling, JIT
and caches can affect timings. No profiler was enabled, but first-incumbent
validation, counters, checkpoint validation and bounded's internal stopwatch
still cost time. Each VM is separate and sequential, not one warmed VM for the
entire matrix. Maximum checkpoint overshoot was 154 microseconds. 30 seconds is
a checkpoint of the 120-second trajectory, not an independent 30-second run.
Peak process RSS ranges 243.9–248.7 MiB and includes VM overhead; it cannot be
interpreted as solver allocation size or a statistically meaningful memory win.

Only four composite fixtures were measured, one per scale, rather than a full
cross-product of all clinical variants. All have an independently validated
witness and therefore do not measure clinical-scale B-stage proof latency.
Repetitions are three timing trials of the same deterministic snapshot, not
independent patient populations. Rank variation alone does not test a new rank
objective. Small-oracle evidence does not establish production readiness or
Web/Android runtime performance. No new algorithm, bound, objective, default,
V1 behavior, UI, Firebase access, push or deployment is part of this change.

## 30/120-second results

| Doctors / fixture | Strategy | First ms range | 30s filled | 120s filled | 120s nodes | Prefix prunes | Improvements | Peak RSS MiB | Status |
|---|---|---|---|---|---|---|---|---|---|
| 6 / mixed | deadends | 19.59–25.72 | 13–13 | 13–13 | 83901125–85703650 | 7–7 | 14–14 | 244.3–246.2 | feasibleNotProven |
| 6 / mixed | combined | 16.47–21.60 | 8–8 | 9–9 | 29055673–29591620 | 0–0 | 82–82 | 244.5–248.7 | feasibleNotProven |
| 6 / mixed | twophase | 16.98–20.21 | 13–13 | 13–13 | 56002115–58069810 | 0–0 | 15–15 | 244.6–244.9 | feasibleNotProven |
| 6 / mixed | bounded | 16.39–21.39 | 13–13 | 13–13 | 63284249–64578808 | 961222–1007662 | 15–15 | 244.0–244.9 | feasibleNotProven |
| 10 / ratio | deadends | 47.59–51.97 | 30–30 | 30–30 | 50755983–52636661 | 18–18 | 12–12 | 244.2–245.5 | feasibleNotProven |
| 10 / ratio | combined | 19.75–28.50 | 7–7 | 7–7 | 14994516–15496857 | 0–0 | 68–68 | 244.1–245.0 | feasibleNotProven |
| 10 / ratio | twophase | 20.36–27.68 | 29–29 | 29–29 | 21501612–22448376 | 0–0 | 7–7 | 244.3–245.6 | feasibleNotProven |
| 10 / ratio | bounded | 18.89–19.52 | 30–30 | 30–30 | 67105614–68394565 | 3931513–4006362 | 22–22 | 244.4–246.1 | feasibleNotProven |
| 15 / surplus | deadends | 26.06–30.77 | 45–45 | 45–45 | 84743991–87289744 | 104–104 | 23–23 | 244.1–244.8 | feasibleNotProven |
| 15 / surplus | combined | 22.99–27.71 | 6–6 | 7–7 | 10385042–10484098 | 0–0 | 78–78 | 244.1–244.7 | feasibleNotProven |
| 15 / surplus | twophase | 24.05–31.62 | 45–45 | 45–45 | 33101959–33265271 | 0–0 | 35–35 | 244.3–244.8 | feasibleNotProven |
| 15 / surplus | bounded | 23.67–24.97 | 45–45 | 45–45 | 35451171–36780462 | 324273–340495 | 54–58 | 244.5–244.5 | feasibleNotProven |
| 20 / rank | deadends | 19.88–22.45 | 31–31 | 31–31 | 12105563–12894385 | 36–36 | 13–13 | 244.3–246.4 | feasibleNotProven |
| 20 / rank | combined | 25.36–31.04 | 4–4 | 5–5 | 6846366–6905667 | 0–0 | 56–56 | 244.2–245.4 | feasibleNotProven |
| 20 / rank | twophase | 23.18–28.76 | 31–31 | 31–31 | 6546804–6637524 | 0–0 | 19–19 | 244.2–245.1 | feasibleNotProven |
| 20 / rank | bounded | 25.61–32.15 | 31–31 | 31–31 | 7402081–7763496 | 287730–301781 | 19–19 | 243.9–244.5 | feasibleNotProven |

## Exact quality vectors, first repetition

| Doctors | Strategy | First | 30s | 120s |
|---:|---|---|---|---|
| 6 | deadends | `0,-13,0,-6,-8,-8,-8,2,2,2,2,1,1,3,4,1/4,1/4,17,46` | `0,-13,0,-8,-8,-8,-6,0,0,2,2,1,1,2,2,1/4,1/4,14,44` | `0,-13,0,-8,-8,-8,-6,0,0,2,2,1,1,2,2,1/4,1/4,14,44` |
| 6 | combined | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-8,0,-8,-8,-8,-6,2,2,2,3,1,1,2,2,1/4,29/84,22,50` | `0,-9,0,-8,-8,-8,-6,2,2,2,3,1,1,2,2,1/4,25/84,22,50` |
| 6 | twophase | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,7,40` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,7,40` |
| 6 | bounded | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,7,40` | `0,-13,0,-8,-8,-8,-6,2,2,2,2,1,1,2,2,1/4,1/4,7,40` |
| 10 | deadends | `0,-28,0,-6,-8,-8,-8,2,3,2,3,1,2,3,4,1/2,3/4,33,46` | `0,-30,0,-6,-8,-8,-8,1,1,2,3,3,5,2,3,1/4,1/4,35,42` | `0,-30,0,-7,-8,-8,-7,2,3,2,3,2,3,3,4,1/8,1/8,35,46` |
| 10 | combined | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-7,0,-8,-8,-8,-6,2,3,2,3,1,2,2,3,1/3,7/12,22,50` | `0,-7,0,-8,-8,-8,-6,2,3,2,3,1,2,2,3,1/3,7/12,22,50` |
| 10 | twophase | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-29,0,-8,-8,-8,-6,2,3,2,4,2,3,2,3,1/4,3/8,32,50` | `0,-29,0,-8,-8,-8,-6,2,3,2,4,2,3,2,3,1/4,3/8,32,50` |
| 10 | bounded | `0,0,0,-7,-7,-8,-8,2,2,2,2,3,3,2,2,1/8,1/8,10,42` | `0,-30,0,-8,-8,-8,-6,2,3,2,3,2,3,2,3,1/4,1/4,35,44` | `0,-30,0,-8,-8,-8,-6,2,3,2,3,2,3,2,3,1/4,1/4,35,41` |
| 15 | deadends | `0,-27,-18,-4,-8,-9,-10,2,3,3,5,2,4,3,6,6/7,6/7,44,47` | `0,-28,-17,-5,-8,-10,-8,2,3,3,5,2,4,3,5,5/6,5/6,34,42` | `0,-28,-17,-5,-8,-10,-8,2,3,3,5,2,4,3,5,5/6,5/6,33,42` |
| 15 | combined | `0,0,0,-5,-5,-10,-11,2,2,3,3,1,1,3,3,5/24,5/24,15,30` | `0,-3,-3,-5,-6,-10,-10,2,2,3,3,1,1,3,4,1/4,11/24,14,30` | `0,-4,-3,-5,-6,-11,-9,2,2,3,3,1,1,3,4,1/4,3/8,22,36` |
| 15 | twophase | `0,0,0,-5,-5,-10,-11,2,2,3,3,1,1,3,3,5/24,5/24,15,30` | `0,-26,-19,-6,-6,-10,-9,2,3,3,5,1,2,3,6,1/8,1/8,28,36` | `0,-26,-19,-6,-6,-11,-8,2,3,2,4,1,2,3,6,1/4,1/4,25,33` |
| 15 | bounded | `0,0,0,-5,-5,-10,-11,2,2,3,3,1,1,3,3,5/24,5/24,15,30` | `0,-26,-19,-6,-6,-10,-9,2,3,3,5,1,2,3,6,1/8,1/8,25,33` | `0,-27,-18,-6,-6,-10,-9,2,4,3,5,1,2,3,6,1/8,1/8,31,39` |
| 20 | deadends | `0,-31,0,-4,-9,-9,-9,2,3,3,5,2,3,3,5,1,2,47,47` | `0,-31,0,-6,-9,-8,-8,2,3,3,5,2,3,3,5,1,13/7,47,47` | `0,-31,0,-7,-8,-9,-7,2,3,3,5,2,3,3,5,1,13/7,47,47` |
| 20 | combined | `0,0,0,-6,-8,-8,-9,2,2,2,2,2,2,3,3,1/2,1/2,15,24` | `0,-4,0,-7,-10,-7,-7,2,2,2,2,2,2,2,3,4/7,19/21,22,31` | `0,-5,0,-7,-9,-7,-8,2,2,2,2,2,3,2,3,4/7,23/28,22,31` |
| 20 | twophase | `0,0,0,-6,-8,-8,-9,2,2,2,2,2,2,3,3,1/2,1/2,15,24` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,2/3,26/21,22,31` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,5/8,67/56,22,31` |
| 20 | bounded | `0,0,0,-6,-8,-8,-9,2,2,2,2,2,2,3,3,1/2,1/2,15,24` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,2/3,26/21,22,31` | `0,-31,0,-7,-10,-7,-7,2,3,2,3,2,3,2,3,5/8,67/56,22,31` |

## 120s paired comparisons

| Doctors | bounded vs deadends | bounded vs combined | bounded vs twophase |
|---:|---|---|---|
| 6 | 3 worse | 3 better | 3 equal |
| 10 | 3 better | 3 better | 3 better |
| 15 | 3 worse | 3 better | 3 better |
| 20 | 3 better | 3 better | 3 equal |

## Regression verification after recovery

- `dart analyze lib/solver_v2 test/solver_v2 tool/solver_v2`: no issues.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub test/solver_v2 --reporter expanded`: 115 passed.
  The first sandboxed attempt could not open localhost test sockets (EPERM);
  rerunning with local socket access passed all tests; no tests were disabled.
- Includes the 200-case independent exhaustive, strategy, two-phase and bounded
  oracle suites, 500 independent clinical-quality references, and 500 bound
  problems (3,887 checked prefixes, 1,486 solutions).
- Existing A/B, spoofed evidence, timeout, cancellation and pause/resume coverage
  remains passing. Added diagnostic tests verify counters and callback reentry
  rejection without changing the objective or feasible solution set.
- Changed files across this stage: `lib/solver_v2/solver.dart` (observability and
  callback reentry guard), `test/solver_v2/search_diagnostics_test.dart`,
  `tool/solver_v2/isolated_compare.dart`, `run_isolated.sh`,
  `summarize_isolated.py`, this report and `results/stage_1_5f_traces.json.gz`.
