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
