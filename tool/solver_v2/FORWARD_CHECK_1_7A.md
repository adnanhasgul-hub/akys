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
