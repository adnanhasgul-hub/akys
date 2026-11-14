# AKYS V2 — Stage 1.8B: locked reoptimization

Base `1e7f58b25fa415a341c36bfe643cdcaed23d7606`, branch
`feature/akys-v2-solver-core`. HEAD and clean tree verified. Baseline 193 V2
tests executed successfully before edits. Stage 1.8A editor, solver, independent
validator and 1.7B runtime API inspected. No V1/Firebase/production changes.

## API and ownership

```dart
final request = ReoptimizationRequest.fromEditor(editor);
final session = ReoptimizationSession(request);
var result = session.run(maxNodes: 10000, timeLimit: Duration(milliseconds: 100));
// Repeated run() resumes this exact frontier; stageTransition may require another call.
// session.cancel(); // next run returns cancelled and any validated incumbent
```

Alternatively `ReoptimizationRequest(problem, reference: ids, locks: slotToId)`
accepts immutable snapshots from other pure Dart callers. Reference IDs use the
existing doctor index and slot order; diffs also provide stable doctor string IDs,
UTC date and position role. No input editor mutation, history modification or
automatic result application occurs. The editor may continue changing without
changing an already-created request. Reference arrays/lock maps are copied.

`request.problem` can be passed to the existing `OptimizationController` for
real VM isolate execution. Its worker and host now accept equal clinical quality
when reference distance strictly improves. No UI integration added. Web worker
remains unsupported; small Chromium arithmetic tests do not establish nonblocking
browser optimization. Android was not rebuilt/retested for this pure Dart stage.

## Exact locks and preflight

New `Problem.fixedAssignments` is an immutable slot -> doctor map. This is an
additional explicit constraint, not a conversion to doctor-day Must (which would
allow a different same-day slot). The empty OPTIONAL choice is rejected when the
slot is locked. Every assigned doctor still passes the existing role, eligibility,
availability, rest, previous-month and capacity checks. Candidate ordering and
frontier/cursor behavior remain unchanged; forbidden candidates are safely rejected.

Serialization preserves fixed assignments and optional `referenceAssignments`.
Old messages default to empty locks and no reference tie-break. Source clinical
rules, slots, dates, identities, scores and REQUIRED/OPTIONAL flags are not rewritten.
A locked OPTIONAL slot remains OPTIONAL in the model but must keep its occupant.
Independent SolutionValidator checks exact locks itself, including missing slots.
The editor also recognizes fixed snapshot constraints; it cannot remove/unlock
those by pretending they are mutable local locks. Unlock in the original editor,
then create a new request to change a frozen optimization problem.

Before creating any search session, request preflight reports structured
`ReoptimizationInputException.issues`: invalid indices, lock/reference mismatch,
conflict with an existing fixed constraint, duplicate day, rest/previous-month,
unavailability, competence/group and capacity violations. It also checks the union
of locked dates and Must obligations for rest/capacity contradictions. Source
Problem validation still handles malformed snapshots. Nonempty candidate domains
or passing preflight do NOT prove feasibility; harder global contradictions remain
for DFS. Conflicting locks cannot be relaxed to get a result.

## Clinical quality then change count

The objective is the ordered pair `(existing ClinicalQuality[19], changedSlots)`.
Comparison first uses ALL 19 exact rational components. Only exact equality reaches
the integer count of slots where candidate doctor differs from reference (including
empty <-> filled). A two-position swap therefore counts as two changed positions.
No 20th clinical component is added, no weights, normalization or existing priority
change is introduced. Full equality retains the earlier incumbent deterministically.

`referenceAssignments` only affects clinical-mode tie-breaking. Legacy prototype
mode explicitly rejects a reference tie-break instead of silently applying a wrong
objective. Ordinary problems without a reference retain their old incumbent behavior.
No previous optimum or reference solution is seeded into DFS. Thus a timeout before
any newly validated candidate has `best == null`, even when the user has a reference
schedule. The original draft is still preserved outside the search.

`minimumChangesProven` is true only for a complete core `optimal` result: minimum
changes **among clinical optima of the new lock-constrained problem**, not minimum
changes among all feasible schedules and not a guarantee relative to another problem.
A time-limited result may have worse quality than the reference; it is an unapplied
preview, not an automatic replacement. The reference may itself be incomplete.

## Pruning and proof scope

No new pruning, strategy default or forward-check default. Existing clinical prefix
bounds only prune a strictly worse Q1–Q3 prefix; equality stays searchable, so an
equal-clinical but lower-change solution cannot be lost. Clinical mode already
disables prototype objective pruning. Capacity/domain relaxations may ignore the
additional obligation of locked OPTIONAL slots: that is an optimistic superset
and weakens pruning without excluding a valid solution. `_allowed` enforces locks
when computing domains; final candidates always satisfy them. Exhaustive tests
check both pruning off and all existing optional controls on.

Each request creates a fresh TransitionSession. A stays substitution-free; B opens
only after that exact new snapshot's restricted problem is proven infeasible.
A timeout, cancellation or copied prior result does not authorize B. Q1 transition
count remains strictly higher priority than reference distance.

A lock placing a junior in a senior position can itself make restricted A
infeasible, even if the original unlocked problem had a senior solution. This is
explicitly a proof about the **lock-constrained snapshot**, not proof of inherent
senior shortage in the original clinic. Preflight does not call such a lock
'authorized': it defers the transition-evidence question to fresh A/B search.
It filters only the typed missing-transition-evidence preflight issue; no validator
proof bypass or trusted serialized flag is added. B incumbents are independently
validated against the actual new session. Evidence for the original/unlocked
snapshot is rejected. All reoptimization results remain preview-only for durable
approval (`permanentApprovalAllowed == false`).

## Results and failure safety

`ReoptimizationResult` exposes the core status, pause reason, A/B phase, restricted
verdict, cumulative nodes, validated best, diff and optional technical error.
`ReoptimizationDiff` lists changed slot/date/role/before-person/after-person,
changed-position count, preserved lock map and currently empty OPTIONAL slots.
Every returned incumbent passes SolutionValidator with current local evidence.
Technical failure cancels the session and retains the last validated incumbent;
no optimum/minimum proof is reported. Timeout and cancellation also retain that
incumbent without promoting its proof. Node-budget pauses can be resumed normally.

The adapter is synchronous; long calls belong off the UI thread. No progress,
threading or Web support is inferred from the API alone. The existing isolate
controller is the supported VM execution option and has dedicated new tests.

## Verification

* Baseline: 193 PASS.
* Final VM V2 suite: 214 PASS (193 existing + 19 reoptimization + 2 real-isolate).
* Chromium: 20 PASS (19 reoptimization + existing unsupported-worker behavior).
* Dart analysis and full Flutter analysis: no issues.
* 200 fixed-seed (`1802`) small problems x pruning off/on = 400 new comparisons.
  Independent Cartesian enumeration checks hard constraints, then exact lock
  filtering. A feasibility is determined before considering B. Independent
  ReferenceClinicalQualityCalculator computes all 19 components; independently
  counted slot differences break ties. Optimal quality, change count, infeasibility
  and A/B outcomes match. Rejected preflight cases are also checked against an empty
  independent feasible set. No solver incumbent/pruning implementation is reused
  as the oracle. Existing quality/reference/proof/oracle regressions remain enabled.
* Targeted tests: single/multiple/OPTIONAL locks, preflight conflicts, Must/Cannot,
  rest/capacity, immutable reference, later equal-quality better incumbent,
  clinical priority over fewer changes, timeout/resume, cancellation, failure,
  fresh A/B proof, minimum transition count, serialization and validator rejection.

Commands:

```sh
dart analyze lib/solver_v2 test/solver_v2 tool/solver_v2
flutter analyze --no-pub
flutter test --no-pub test/solver_v2 --reporter expanded
flutter test --no-pub --platform chrome test/solver_v2/reoptimization_test.dart test/solver_v2/lifecycle_web_test.dart --reporter expanded
dart run tool/solver_v2/reoptimization_benchmark.dart
```

## Measured performance (not a speedup guarantee)

Raw results: `results/stage_1_8b_reoptimization.json`, with source fingerprints.
Linux x86_64 hosted AMD EPYC 9V74, 5 visible CPUs; Dart 3.13.7 VM JIT. One process,
sequential runs, 3 repeats, 1 second wall budget including preparation, 1,000-node
checkpoints. Explicit combined/two-phase/bounds selections match prior fixture
experiments; defaults are unchanged. Seed `160600`, prior synthetic `6-open`
witness retained. No concurrent benchmark/build/test. First observation includes
preparation and checkpoint delay; it is not an exact DFS-leaf timestamp.

| Scenario | Locks | Median first observed | Median total | Median nodes | Result (all 3) |
|---|---:|---:|---:|---:|---|
| 4 doctors / 4-day small fixture | 1 | 1.354 ms | 1.359 ms | 42 | optimal, minimum changes proven |
| 6 doctors / 30 days | 0 | 1.842 ms | 1,000.058 ms | 606,982 | feasible, unproven |
| 6 doctors / 30 days | 3 | 3.283 ms | 1,000.040 ms | 633,031 | feasible, unproven |
| 6 doctors / 30 days | 30 | 2.375 ms | 1,000.094 ms | 698,367 | feasible, unproven |

All returned incumbents validated. Preserved locks were respectively 1/0/3/30.
Final changed slots were 2/25/27/13; these are NOT comparable quality scores across
different constrained problems. Small fixture fills two reference-empty OPTIONAL
slots because clinical coverage outranks reference similarity. The three 30-day
variants each ended with 17 empty OPTIONAL slots; their full, different 19-vectors
are in the JSON. No clinical optimum or minimum-change proof was reached in those
one-second runs. Cold JIT/shared host variability is present; no clinical-scale
latency, memory or performance-regression guarantee follows from this experiment.

## Scope and remaining limits

No automatic apply to editor/history, no lock relaxation, no warm incumbent seed,
no new clinical objective/bound, no default change, no checkpoint persistence,
no Firebase/Flutter UI integration. Complete search can still be expensive.
Reference/locks use immutable snapshot indices; rebuilding a differently ordered
personnel list requires an explicit ID-based adapter outside this stage. Existing
source fields and typed serialized snapshots retain doctor identities.

Changed: solver snapshot/candidate tie support, independent validator lock check,
editor fixed-snapshot protection, runtime tie comparison (host + worker), new
reoptimization adapter, 2 test files, benchmark tool/JSON and this report.
