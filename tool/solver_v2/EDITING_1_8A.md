# AKYS V2 — Stage 1.8A: manual editing

Base commit: `7231b2c067e60b2d2d1065cdbb344ea09d9e2d8f`.
Branch: `feature/akys-v2-solver-core`. Clean starting tree and matching HEAD
verified. Existing DFS, validator, quality evaluator and runtime inspected;
none modified. No UI, Firebase, persistence, push, merge or deploy.

## API

`ScheduleEditor(problem, assignments: ..., localEvidence: ...)` requires a complete
clinical problem snapshot. Assignments use existing slot order and doctor indices;
`-1` is the empty marker (including temporarily empty REQUIRED slots in a draft).
Missing initial assignments creates an empty draft. A mismatched slot count or
non-clinical snapshot throws ArgumentError. The Problem constructor continues to
reject contradictory input such as Must/Cannot overlap or invalid personal caps.

Operations: `assign(slot, doctor)`, `remove(slot)`, `move(from, to)`,
`swap(first, second)`, `lock(slot)`, `unlock(slot)`, `undo()`, `redo()`.
`current`, `canUndo`, `canRedo` expose immutable snapshots/history availability.

All edit operations work on copies and validate the final simultaneous candidate.
On rejection, `EditResult.after` is the same object as `before`; assignments,
locks, undo and redo history remain unchanged. Move requires an empty destination;
swap requires two filled slots. Assignment can replace an unlocked occupied slot.
Invalid indices return structured errors rather than partially changing the draft.
Accepted no-op commands are also recorded as history entries.

`EditIssue` includes a typed code, Turkish message, and where applicable slot,
UTC date and person ID. Codes distinguish missing requirements, roles, transition
evidence, unavailable dates, same-day duplicates, rest, previous-month rest,
capacity, locks, invalid indices, history and independent-validation failure.

## Drafts and clinical approval eligibility

* `incomplete`: only missing REQUIRED slots and/or unsatisfied Must days. Such
  removals are allowed to support incremental editing, but cannot be approved.
* `valid`: complete, independently validated non-substituting schedule.
* `provisionalTransition`: complete, validated B schedule, preview only.
* `invalid`: imported draft or historical snapshot with actual violations or
  missing/expired transition evidence. Never approvable.

All new edits reject hard violations. Initial imported invalid drafts can be
inspected with structured issues, but an edit must eliminate all non-incompleteness
errors to be accepted. This is deliberately conservative: no arbitrary bulk repair
or permission to introduce another violation is provided.

OPTIONAL emptiness alone is valid. Filled optional slots count toward all rules.
Must is a doctor-day obligation, satisfied by any eligible slot that day; same-day
duplicate assignment is still forbidden. Full schedules are cross-checked with
SolutionValidator, then passed to the existing ClinicalQualityEvaluator. Partial
validation is separately implemented to distinguish incompleteness from hard
violations; complete validation is not replaced by that implementation.

`canApprove` means clinical eligibility only. It does not grant publishing,
application authorization or Firestore permission. Nothing is published here.

## Locks and history

Locks are immutable `slot -> doctor index` maps, independent of assignments but
bound to this immutable problem's slot/doctor ordering. Remove, replace, move and
swap check all touched locks. Empty positions cannot be locked. Unlock is explicit.
Undo of a lock operation is an explicit reversal of that operation and restores
its earlier lock state. New successful edits clear redo; failed edits do not.

History stores assignment and lock data, not cached proof or quality. Undo/redo
restores the data and recomputes validity/quality. Accessing `current` rechecks
session authority too, because an external active B session can finish/cancel.
Thus undo cannot resurrect expired authorization. A historical imported invalid
snapshot may be restored, but remains explicitly invalid and unapprovable.
History is currently unbounded and in-memory; persistence and reoptimization lock
adapters are future work. Locks are not silently converted to solver constraints.

## A/B safety

No new proof or security bypass was added. Optional `localEvidence` must be a
real TransitionSession using the **identical** problem snapshot (use
`session.problem`, not a serialized clone).

* No session, pending A, timed-out A or cancelled A cannot authorize substitution.
* An active B session that has proven restricted infeasibility permits provisional
  candidates through existing `validatePhaseBCandidate` and
  `evaluatePhaseBCandidate` APIs. The editor itself never advances the search.
* A completed B session authorizes only its exact existing incumbent through
  `verifiesLocalTransition`; a different manual assignment is rejected, even if
  it might be mathematically feasible. General post-search B editing would require
  a separately reviewed capability design, not an inferred boolean permission.
* B solutions always have `canApprove == false`. Process-local evidence is not
  transferable proof and is not obtainable from an isolate result message alone.

Cancelling an active session revokes its candidate capability. Existing exact
incumbent evidence remains subject to the core's existing validation semantics.
No runtime API or core evidence semantics were modified.

## Quality and proof

Each complete validated candidate receives the same exact 19-component vector
from ClinicalQualityEvaluator. Legacy prototype metadata is reconstructed only
for compatibility with SolutionValidator; it is not an optimization objective.
`EditResult.qualityComparison` is exact lexicographic after-vs-before comparison
(negative = improved; null if either endpoint lacks valid complete quality).
Both full vectors are accessible. Manual edits may legitimately worsen quality;
this layer enforces hard constraints, not optimizer soft-objective restrictions.

`optimalityProven` is always false, including on import of an optimal solver
assignment and after undo. This stage grants no mathematical optimality claim.

## Tests and verification

24 new tests cover successful/rejected assignment; indices; atomic move/swap;
locks; undo/redo and redo retention on failure; immutable snapshots; REQUIRED and
OPTIONAL emptiness; Must; unavailable dates; same-day duplicate; three-day and
previous-month rest; personal capacity; role/competence; no-evidence, active,
completed, cancelled and mismatched-snapshot B contexts; exact quality delta;
proof invalidation; malformed snapshot. Complete valid results are cross-checked
with independent SolutionValidator and ClinicalQualityEvaluator.

Commands:

```sh
dart analyze lib/solver_v2 test/solver_v2 tool/solver_v2
flutter analyze --no-pub
flutter test --no-pub test/solver_v2 --reporter expanded
```

Final execution: **193 PASS** (169 previous + 24 new). Both Dart and Flutter
analyses completed with no issues. No build is required for this pure Dart module;
no new Android or Web execution claim is made. The previous Web worker limitation
remains. No benchmark or performance guarantee is added: edits synchronously scan
the schedule and full quality, so later UI integration should measure large drafts.

Changed files: `lib/solver_v2/editing/schedule_editor.dart`,
`test/solver_v2/schedule_editor_test.dart`, and this report.
