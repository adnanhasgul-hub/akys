# AKYS V2 solver core — stage 1.2 prototype

This module is independent of Flutter and Firebase. `Doctor`, `Problem`, and
`Solution` are immutable snapshots. `Problem.toMessage`/`fromMessage` and
`SearchResult.toMessage` use primitive maps/lists suitable as a starting point for
isolate or worker protocols. Worker execution, transport, and persistence are not
implemented or verified. No existing UI or V1 engine uses this module.

A problem contains consecutive day indices and an exact number of required slots
per day. A solution assigns one doctor index to each slot. The incremental hard
checks enforce unavailable dates, per-doctor maxima and a minimum difference of
three calendar-day indices; this also prevents duplicate same-day assignments.
Quality is minimized lexicographically: (1) maximum minus minimum duty count,
(2) sum of squared counts. Doctor input order breaks exact ties deterministically.

The iterative depth-first search tries doctors in input order at each slot. It
prunes infeasible prefixes whose remaining total capacity is too small. Once an
incumbent exists, it also computes a safe lexicographic lower bound: current
maximum load minus floor(final total / doctor count), clamped at zero, and the
minimum sum of squares obtained by water-filling current counts while ignoring
availability, rest, and individual upper limits. Relaxation enlarges the set of
completions; neither bound can overstate the best achievable value. A bound not
better than the incumbent can be pruned because exact ties retain the first
solution in input order. `enablePruning: false` reproduces the original search. Once the finite tree is exhausted, the best valid leaf is
provably optimal; no valid leaf proves infeasibility. A budget/time stop does not
prove either. Equal-quality branches may be pruned. Complexity is
exponential; this is for small synthetic inputs, not production monthly planning.

A `SearchSession` owns its current assignment prefix, per-depth next-candidate
cursors, incumbent and visited-node count. `run(maxNodes: ...)` pauses between
candidate evaluations without restarting finished branches. A zero time limit
is a timeout, not infeasibility. An optional per-call deadline may cut off a run
at different points on different devices; fixed node budgets are deterministic.
Cancellation keeps the incumbent and is terminal for that session. Session
checkpoints are in-memory only, not serialized or written to Firestore. There
is no separately serialized proof certificate or persisted frontier.

`run` is synchronous: the caller must run bounded chunks in an appropriate
isolate/worker and yield between chunks. Calling it on a Flutter Web UI thread
can block rendering. Cancellation cannot interrupt a currently executing chunk;
it is observed when control returns. Neither Web Worker support nor Android
isolate transport has been implemented or tested here.

Not implemented: senior/junior roles, substitution, must-duty constraints,
previous-month boundary, clinical duty groups, pairing/solo priorities, daily
category or holiday fairness, difficulty score snapshots, triple-duty policy,
Firestore compatibility, manual edits, authorization and V1 migration.

An independent `SolutionValidator` recomputes slot count, indices, availability,
capacity, rest and quality without using search internals. Result messages expose
`pauseReason` and `canResume` for node-budget and deadline stops.

## Synthetic benchmark

Flutter 3.47.9 / Dart 3.13.7, Linux VM, one un-warmed in-process run: four
doctors (maximum three duties), seven consecutive one-slot days. Original DFS:
1,508 candidate visits, 2,379 µs. Branch-and-bound: 272 visits, 487 µs. Both
exhausted their search and proved quality `[1, 13]` optimal. Wall times vary
with JIT, host load and execution order; these single-run numbers do not prove
clinical-scale performance. The test suite also compares 512 generated small
problems with a separate exhaustive oracle, both uninterrupted and resumed.

## Stage 1.3 clinical constraints and safety boundary

`Problem.startDate` is an optional UTC midnight, and day indices are offsets from
it. Clinical callers must supply it and a `slotRoles` entry per slot. The nullable
fields preserve existing stage-1.2 synthetic callers; they are not a clinical
mode. The constructor rejects non-midnight/non-UTC dates, previous dates on or
after the start, role count mismatch, must/cannot intersections and personal
maximum above the configurable clinical maximum (default 8). `Doctor` carries
identity, group, optional typed K1–K4 senior level, position eligibility, must
and cannot day indices, and previous duties. K-level is metadata only; it is not
an optimization objective. The prototype's integer duty-balance objective remains
only a placeholder, not the final AKYS clinical objective.

When roles are provided, senior slots accept only seniors and junior slots only
juniors. Must-duty days are checked on complete assignments, previous dates are
checked using UTC calendar differences, and all earlier hard checks still apply.
The independent validator separately applies these restrictions and checks all
must duties, including on manually constructed assignments.

## Stage 1.3B: two-phase local substitution protocol

`TransitionSession` deep-copies the problem through its primitive message model
and exposes the resulting immutable snapshot as `session.problem`. It requires a
clinical start date and explicit slot roles. Phase A runs the exact restricted
solver: if it finds any valid schedule, its verdict becomes `feasible` and
phase B remains closed while optimization continues. Only complete restricted exhaustion without a solution
sets `provenInfeasible` and creates the private phase-B search. A deadline or node
budget without a solution remains pending; cancellation closes the session.
`PauseReason.stageTransition` distinguishes phase completion from a node limit.
Both frontiers are retained in memory across calls.

Phase B permits an otherwise eligible junior in a senior slot. It minimizes the
number of such assignments as the first quality component, followed by the
existing prototype balance vector. Capacity pruning is retained; objective
pruning is disabled in phase B because the previous bounds do not include this
new first component. Complete search proves the minimum; time/budget interruption
only returns the current valid incumbent without an optimality claim.

The `final` process-local session encapsulates the actual restricted search,
immutable verdict and private B engine. `SolutionValidator.validate` accepts a
junior senior-slot assignment only when its optional local evidence is the real
session, the exact `session.problem` object is used, and the solution matches
that session's current B incumbent. It independently verifies assignment hard
constraints, substitution count and the entire reported quality vector. An
identical reconstructed or modified problem is a different snapshot and fails
this capability check. A forged serialized `proved` flag is not an input.

This is not an independently portable proof certificate. The local session
trusts the correctness of the in-process restricted enumerator, and a compromised
client process cannot establish a trustworthy Firestore/server proof. The
validator's `permanentApprovalAllowed` is false for any substitution solution,
even if locally valid; no persistence or server authorization is implemented.
A production system needs a trusted server-side verifier that replays phase A or
validates an independently checkable, problem-bound unsatisfiability certificate.
Cancellation and timeout do not prove infeasibility. Search remains synchronous,
exponential, and in-memory; Web Worker integration is unverified.

Other missing decisions include complete K-level
hierarchy and ranking semantics, junior vacancy policy, advanced fairness and
difficulty, real clinical snapshot migration, persistent checkpoints and
worker/isolate integration. The synthetic benchmark is not a clinical-scale
performance claim.

## Stage 1.4A: restricted phase optimizes

Phase A uses the existing `SearchSession` optimize behavior; there is no separate
feasibility-only mode. Finding an incumbent sets `RestrictedVerdict.feasible`,
which permanently prevents phase B for this session, but the phase stays
`restricted` until the frontier is exhausted. `feasibleNotProven` plus a pause
reason retains the incumbent and frontier; resuming does not revisit completed
branches. Only exhaustion returns `optimal`. Timeout or cancellation after an
incumbent retains it without converting the result into an infeasibility proof.
If there is no incumbent, only complete restricted exhaustion opens phase B;
node/time limits and cancellation never do so. Existing capacity and prototype
quality lower-bound pruning are unchanged. No new clinical quality objective or
clinical objective pruning is implemented in this stage.

## Stage 1.4B: independent clinical snapshot and quality

`Problem.dayDifficulties` is an optional immutable per-day list paired with a UTC
midnight start date. Each entry stores the admin's weekday score, optional
holiday name and optional holiday score, both scores integer 1–10. The effective
score is `max(weekdayScore, holidayScore)`; a holiday name and score must occur
together. Date and ISO weekday are derived from UTC day offsets via `dateForDay`
and `weekdayForDay`; effective score is exposed by `difficultyForDay`. Existing
roles, groups, K1–K4 and caps remain in the snapshot. All fields round-trip
through the problem message; legacy snapshots with no scores remain readable.

`ClinicalQualityEvaluator` requires a complete clinical snapshot, a K1–K4 level
for every senior, and a `SolutionValidator`-valid solution including process-local
proof for a substitution. It does not call the solver's objective. The vector
has 19 components; all are minimized, and comparison is lexicographic:

1. Q1: number of junior doctors assigned to senior positions.
2. Q2–Q3: negative number of days with at least one, then at least two, doctors
   whose persistent group is junior (including a temporary senior-position holder).
3. Q4: negative counts of days with exactly one senior-group doctor for K4,
   K3, K2, K1, in that order. Any number of junior-group doctors may also work
   that day. Two senior-group doctors make the day ineligible. Persistent group,
   not a temporary role, determines whether a doctor is senior. Doctors of equal
   K-level are aggregated, with no within-level objective.
4. Q5: for Saturday, Friday, Sunday, Thursday in that order, two values each:
   maximum of the senior/junior within-group count ranges, then their sum.
5. Q6: each doctor's duty count divided by their personal maximum, with each
   group's ratio range computed exactly; first the worse group, then the sum.
6. Q7: the worse senior/junior range of total difficulty scores, then the
   greatest individual total across both groups. Every duty receives exactly
   that day's effective score, independent of role.

An empty or singleton group has range zero. For Q5 and Q7, all doctors in the
snapshot, including zero-capacity doctors, participate in their group. For Q6 a
doctor whose maximum is zero is excluded from ratios; hard validation already
forbids assigning duties to them, and an empty/singleton eligible group has range
zero. Caps remain hard maxima, never targets. Empty populations have individual
maximum zero. Equal components proceed to the next component; equal full vectors
compare equal. Exact normalized `BigInt` fractions and cross multiplication avoid
floating-point rounding in all comparisons. Weekday is the real calendar day;
holidays do not replace its category.

The evaluator checks validity through the independent validator, including its
existing prototype-quality consistency check. It never grants persistent approval
for a local-only substitution. This stage does not integrate the clinical vector
into `SearchSession`, alter its prototype objective, or add/change branch-and-
bound. In particular, prototype objective bounds must be reconsidered before
1.4C uses the new vector. Fixed slot counts and roles constrain which coverage/second-junior alternatives
can exist; stage 1.4B.1 adds optional slot representation as described below.


## Stage 1.4B.1: optional slot model (validation only)

`slotRequirements` contains one `SlotRequirement.required` or `.optional` entry
per slot, in the same order as roles. Old messages without this field restore all
slots as required. The exact sentinel `unfilledSlot` (`-1`) means an unfilled
optional slot; a missing assignment, `-1` in a required slot, and all other
negative or out-of-range indices are invalid. Filled optional slots count as
ordinary duties and undergo the same role, rest, previous-month boundary, must,
cannot and capacity checks. Quality ignores unfilled slots and counts filled
ones normally. These requirements are included in the immutable snapshot and its
message round-trip.

## Stage 1.4C.1: optional-slot search

DFS enumerates the existing doctor indices first, followed by `unfilledSlot`
for an optional position; required positions never have a vacancy candidate.
Vacancies count as visited candidates, do not count towards load, and are ignored
when evaluating substitution counts and duty counts. Must-duty checks remain
on complete leaves and can force an optional slot to be filled. Every occupied
slot uses the existing hard checks. Both A and B enumerate optional vacancies;
A still opens B only after the entire restricted search proves infeasibility.

Capacity pruning compares remaining available capacity with the number of
remaining **required** slots only. Because the eventual total assigned duties
can vary, the fixed-total load range and squared-load objective bounds are
**disabled for the entire search whenever any optional slot exists**. In
phase B only the safe capacity bound is used. No 19-component clinical objective
is connected to the search. The prototype balance quality counts filled duties
only and can therefore favor leaving optional slots empty; it is not the clinical
coverage objective.

A/B frontiers, node budgets, pauses and timeouts include vacancy candidates.
The independent validator still validates required and filled optional slots,
and phase-B local evidence and the prohibition on permanent approval remain
unchanged. Small generated mixed optional problems are compared against an
independent exhaustive oracle with pruning on and off. A single un-warmed Linux
VM run, Flutter 3.47.9 / Dart 3.13.7, three doctors and three slots (one required,
two optional): baseline 51 nodes / 821 µs, pruning 51 nodes / 204 µs, both
optimal with `[0, 3]`. Times are noisy and ordering/JIT-dependent; objective
pruning is disabled here, so no general performance benefit is implied. These
small results do not demonstrate clinical-scale performance.
