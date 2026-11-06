# AKYS V2 solver core — stage 1.1 prototype

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
prunes only assignments that already violate the hard constraints; it does not
prune on the objective. Once the finite tree is exhausted, the best valid leaf is
provably optimal; no valid leaf proves infeasibility. A budget/time stop does not
prove either. Equal-quality branches are still enumerated. Complexity is
exponential; this is for small synthetic inputs, not production monthly planning.

A `SearchSession` owns its current assignment prefix, per-depth next-candidate
cursors, incumbent and visited-node count. `run(maxNodes: ...)` pauses between
candidate evaluations without restarting finished branches. A zero time limit
is a timeout, not infeasibility. An optional per-call deadline may cut off a run
at different points on different devices; fixed node budgets are deterministic.
Cancellation keeps the incumbent and is terminal for that session. Session
checkpoints are in-memory only, not serialized or written to Firestore. There
are no numerical lower/upper bounds or branch-and-bound optimality certificates.

`run` is synchronous: the caller must run bounded chunks in an appropriate
isolate/worker and yield between chunks. Calling it on a Flutter Web UI thread
can block rendering. Cancellation cannot interrupt a currently executing chunk;
it is observed when control returns. Neither Web Worker support nor Android
isolate transport has been implemented or tested here.

Not implemented: senior/junior roles, substitution, must-duty constraints,
previous-month boundary, clinical duty groups, pairing/solo priorities, daily
category or holiday fairness, difficulty score snapshots, triple-duty policy,
Firestore compatibility, manual edits, authorization and V1 migration.
