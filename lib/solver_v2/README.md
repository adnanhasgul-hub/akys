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

**Junior-to-senior substitution is NOT implemented.** The restricted search can
prove infeasibility, but there is no independently verifiable proof artifact or
trusted two-phase authorization in the current model. Neither a boolean nor a
serialized status is accepted as proof; the validator rejects junior assignments
to senior slots unconditionally, including after a restricted infeasible result.
Timeout or node budget is not a proof. To enable the feature safely, add a
problem-bound, independently checkable unsatisfiability certificate or a trusted
verifier that replays the complete restricted search, then implement a separate
substitution-minimizing phase bound to the validated certificate. Until then this
is a conservative, incomplete clinical prototype, not production-ready.

Other missing decisions include substitution minimization, complete K-level
hierarchy and ranking semantics, junior vacancy policy, advanced fairness and
difficulty, real clinical snapshot migration, persistent checkpoints and
worker/isolate integration. The synthetic benchmark is not a clinical-scale
performance claim.
