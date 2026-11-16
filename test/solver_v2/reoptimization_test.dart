import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';
import 'package:akys/solver_v2/editing/schedule_editor.dart';
import 'package:akys/solver_v2/editing/reoptimization.dart';

import 'schedule_editor_test.dart' as f;
import 'clinical_reliability_test.dart' as generated;
import 'optional_search_test.dart' as exhaustive;
import 'support/reference_clinical_quality.dart';

ReoptimizationResult finish(ReoptimizationSession s) {
  for (var i = 0; i < 10000; i++) {
    final r = s.run(maxNodes: 1000);
    expect(r.error, isNull);
    if (r.status == SearchStatus.optimal ||
        r.status == SearchStatus.infeasible) {
      return r;
    }
  }
  throw StateError('small fixture did not finish');
}

void valid(ReoptimizationSession s, ReoptimizationResult r) {
  expect(r.best, isNotNull);
  expect(
    const SolutionValidator()
        .validate(s.problem, r.best!, localEvidence: s.localEvidence)
        .isValid,
    true,
  );
  for (final e in s.problem.fixedAssignments.entries) {
    expect(r.best!.assignments[e.key], e.value);
  }
}

Matcher inputError(EditCode code) => isA<ReoptimizationInputException>().having(
  (e) => e.issues.map((i) => i.code),
  'code',
  contains(code),
);

void main() {
  test('single editor lock becomes exact immutable constraint, reference unchanged', () {
    final editor = ScheduleEditor(f.fixture(), assignments: [0, 1]);
    editor.lock(0);
    final before = editor.current;
    final request = ReoptimizationRequest.fromEditor(editor);
    editor.unlock(0);
    editor.assign(0, 1);
    expect(request.reference, [0, 1]);
    expect(request.locks, {0: 0});
    final s = ReoptimizationSession(request);
    final r = finish(s);
    valid(s, r);
    expect(r.diff!.preservedLocks, {0: 0});
    expect(before.assignments, [0, 1]);
    expect(editor.current.assignments, [1, 1]);
    expect(r.minimumChangesProven, true);
  });
  test('multiple exact locks including optional retained', () {
    final p = f.fixture(
      doctors: [
        f.senior('s'),
        Doctor(id: 'j', group: DutyGroup.junior),
      ],
      days: [2],
      roles: [DutyRole.senior, DutyRole.junior],
      requirements: [SlotRequirement.required, SlotRequirement.optional],
    );
    final s = ReoptimizationSession(
      ReoptimizationRequest(p, reference: [0, 1], locks: {0: 0, 1: 1}),
    );
    final r = finish(s);
    valid(s, r);
    expect(r.best!.assignments, [0, 1]);
    expect(r.diff!.preservedLocks.length, 2);
    expect(r.diff!.emptyOptionalSlots, isEmpty);
  });
  test(
    'conflicting intrinsic lock and reference mismatch rejected before search',
    () {
      final data = f.fixture().toMessage()..['fixedAssignments'] = {'0': 0};
      final p = Problem.fromMessage(data);
      expect(
        () => ReoptimizationRequest(p, reference: [1, 0], locks: {0: 1}),
        throwsA(inputError(EditCode.locked)),
      );
      expect(
        () => ReoptimizationRequest(
          f.fixture(),
          reference: [0, 1],
          locks: {1: 0},
        ),
        throwsA(inputError(EditCode.locked)),
      );
    },
  );
  test('same day and adjacent locked assignments fail preflight', () {
    for (final days in [
      [2],
      [1, 1],
    ]) {
      expect(
        () => ReoptimizationRequest(
          f.fixture(days: days),
          reference: [0, 0],
          locks: {0: 0, 1: 0},
        ),
        throwsA(
          inputError(days.length == 1 ? EditCode.duplicateDay : EditCode.rest),
        ),
      );
    }
  });
  test('capacity and previous month lock conflicts fail preflight', () {
    expect(
      () => ReoptimizationRequest(
        f.fixture(doctors: [f.senior('s', cap: 1)]),
        reference: [0, 0],
        locks: {0: 0, 1: 0},
      ),
      throwsA(inputError(EditCode.capacity)),
    );
    expect(
      () => ReoptimizationRequest(
        f.fixture(
          doctors: [
            f.senior('s', previous: [DateTime.utc(2026, 10, 31)]),
          ],
        ),
        reference: [0, -1],
        locks: {0: 0},
      ),
      throwsA(inputError(EditCode.previousMonthRest)),
    );
  });
  test('cannot, skill and Must conflicts fail preflight', () {
    expect(
      () => ReoptimizationRequest(
        f.fixture(
          doctors: [
            f.senior('s', cannot: {0}),
          ],
        ),
        reference: [0, -1],
        locks: {0: 0},
      ),
      throwsA(inputError(EditCode.unavailable)),
    );
    expect(
      () => ReoptimizationRequest(
        f.fixture(
          doctors: [
            f.senior('s', roles: {DutyRole.junior}),
          ],
        ),
        reference: [0, -1],
        locks: {0: 0},
      ),
      throwsA(inputError(EditCode.role)),
    );
    expect(
      () => ReoptimizationRequest(
        f.fixture(
          doctors: [
            f.senior('s', must: {1}),
          ],
        ),
        reference: [0, -1],
        locks: {0: 0},
      ),
      throwsA(inputError(EditCode.rest)),
    );
  });
  test('reference length, indices and empty locks rejected', () {
    expect(
      () => ReoptimizationRequest(f.fixture(), reference: [], locks: {}),
      throwsA(isA<ReoptimizationInputException>()),
    );
    expect(
      () =>
          ReoptimizationRequest(f.fixture(), reference: [0, 1], locks: {2: 0}),
      throwsA(inputError(EditCode.slotIndex)),
    );
    expect(
      () => ReoptimizationRequest(
        f.fixture(),
        reference: [0, -1],
        locks: {1: -1},
      ),
      throwsA(inputError(EditCode.doctorIndex)),
    );
  });
  test(
    'same clinical quality chooses later reference and proves minimum changes',
    () {
      final p = f.fixture(days: [1]);
      final s = ReoptimizationSession(
        ReoptimizationRequest(p, reference: [1], locks: {}),
      );
      Solution? first;
      for (var i = 0; i < 20 && first == null; i++) {
        first = s.run(maxNodes: 1).best;
      }
      expect(first!.assignments, [0]);
      final r = finish(s);
      valid(s, r);
      expect(r.best!.assignments, [1]);
      expect(r.best!.clinicalQuality!.compareTo(first.clinicalQuality!), 0);
      expect(r.diff!.changedPositions, 0);
      expect(r.minimumChangesProven, true);
    },
  );
  test(
    'clinical improvement wins over preserving reference optional emptiness',
    () {
      final p = f.fixture(
        doctors: [
          f.senior('s'),
          Doctor(id: 'j', group: DutyGroup.junior),
        ],
        days: [2],
        roles: [DutyRole.senior, DutyRole.junior],
        requirements: [SlotRequirement.required, SlotRequirement.optional],
      );
      final s = ReoptimizationSession(
        ReoptimizationRequest(p, reference: [0, -1], locks: {0: 0}),
      );
      final r = finish(s);
      valid(s, r);
      expect(r.best!.assignments, [0, 1]);
      final change = r.diff!.changes.single;
      expect(change.slot, 1);
      expect(change.beforePersonId, isNull);
      expect(change.afterPersonId, 'j');
      expect(change.date, DateTime.utc(2026, 11));
      expect(change.role, DutyRole.junior);
    },
  );
  test('empty optional reported when no candidate exists', () {
    final p = f.fixture(
      days: [2],
      roles: [DutyRole.senior, DutyRole.junior],
      requirements: [SlotRequirement.required, SlotRequirement.optional],
    );
    final s = ReoptimizationSession(
      ReoptimizationRequest(p, reference: [0, -1], locks: {0: 0}),
    );
    final r = finish(s);
    valid(s, r);
    expect(r.diff!.emptyOptionalSlots, [1]);
  });
  test('zero deadline does not seed reference or claim infeasible', () {
    final s = ReoptimizationSession(
      ReoptimizationRequest(f.fixture(), reference: [0, 1], locks: {0: 0}),
    );
    final r = s.run(maxNodes: 100, timeLimit: Duration.zero);
    expect(r.status, SearchStatus.timeoutWithoutSolution);
    expect(r.best, isNull);
    expect(r.minimumChangesProven, false);
    expect(s.localEvidence.restrictedVerdict, RestrictedVerdict.pending);
    final done = finish(s);
    valid(s, done);
  });
  test(
    'timeout with incumbent retains valid result; resume proves tie optimum',
    () {
      final s = ReoptimizationSession(
        ReoptimizationRequest(
          f.fixture(days: [1]),
          reference: [1],
          locks: {},
        ),
      );
      ReoptimizationResult r = s.run(maxNodes: 1);
      while (r.best == null) {
        r = s.run(maxNodes: 1);
      }
      final paused = s.run(maxNodes: 100, timeLimit: Duration.zero);
      valid(s, paused);
      expect(paused.status, SearchStatus.feasibleNotProven);
      expect(paused.minimumChangesProven, false);
      final done = finish(s);
      expect(done.best!.assignments, [1]);
      expect(done.minimumChangesProven, true);
    },
  );
  test('cancellation before and after incumbent preserves reference and proof distinction', () {
    for (final after in [false, true]) {
      final request = ReoptimizationRequest(
        f.fixture(days: [1]),
        reference: [1],
        locks: {},
      );
      final s = ReoptimizationSession(request);
      if (after) {
        while (s.run(maxNodes: 1).best == null) {}
      }
      s.cancel();
      final r = s.run(maxNodes: 1000);
      expect(r.status, SearchStatus.cancelled);
      expect(r.minimumChangesProven, false);
      expect(request.reference, [1]);
      if (after) {
        valid(s, r);
      } else {
        expect(r.best, isNull);
      }
    }
  });
  test('locked junior senior forces fresh A proof of constrained snapshot before B', () {
    final p = f.fixture(
      doctors: [
        f.senior('s'),
        Doctor(id: 'j', group: DutyGroup.junior),
      ],
      days: [1],
    );
    final s = ReoptimizationSession(
      ReoptimizationRequest(p, reference: [1], locks: {0: 1}),
    );
    final a = s.run(maxNodes: 10000);
    expect(a.pauseReason, PauseReason.stageTransition);
    expect(a.best, isNull);
    expect(a.restrictedVerdict, RestrictedVerdict.provenInfeasible);
    final b = finish(s);
    valid(s, b);
    expect(b.best!.assignments, [1]);
    expect(b.best!.clinicalQuality!.components.first.toString(), '1');
    expect(b.permanentApprovalAllowed, false);
    // A different unlocked snapshot must not reuse this constrained proof.
    expect(s.localEvidence.verifiesLocalTransition(p, b.best!), false);
  });
  test('A solution keeps B closed and junior reference does not authorize transition', () {
    final p = f.fixture(
      doctors: [
        f.senior('s'),
        Doctor(id: 'j', group: DutyGroup.junior),
      ],
      days: [1],
    );
    final s = ReoptimizationSession(
      ReoptimizationRequest(p, reference: [1], locks: {}),
    );
    final r = finish(s);
    valid(s, r);
    expect(r.best!.assignments, [0]);
    expect(r.restrictedVerdict, RestrictedVerdict.feasible);
  });
  test('B minimizes transitions before reference distance', () {
    final p = f.fixture(
      doctors: [
        f.senior('s', cap: 1),
        Doctor(id: 'j', group: DutyGroup.junior),
      ],
      days: [1, 0, 0, 1],
    );
    final s = ReoptimizationSession(
      ReoptimizationRequest(p, reference: [1, 1], locks: {}),
    );
    final r = finish(s);
    valid(s, r);
    expect(r.best!.clinicalQuality!.components.first.toString(), '1');
    expect(r.diff!.changedPositions, 1);
  });
  test('problem roundtrip retains constraints, defaults and reference; validator rejects broken lock', () {
    final request = ReoptimizationRequest(
      f.fixture(),
      reference: [1, 0],
      locks: {0: 1},
    );
    final copy = Problem.fromMessage(request.problem.toMessage());
    expect(copy.fixedAssignments, {0: 1});
    expect(copy.referenceAssignments, [1, 0]);
    final s = ReoptimizationSession(request);
    final r = finish(s);
    final changed = Solution([0, 1], r.best!.quality);
    expect(
      const SolutionValidator()
          .validate(copy, changed)
          .errors
          .any((e) => e.contains('Kilitli')),
      true,
    );
    final editor = ScheduleEditor(copy, assignments: r.best!.assignments);
    expect(editor.remove(0).accepted, false);
    expect(editor.unlock(0).accepted, false);
    expect(TransitionSession(copy).forwardChecking, false);
    expect(() => copy.fixedAssignments[0] = 0, throwsUnsupportedError);
    expect(() => copy.referenceAssignments![0] = 0, throwsUnsupportedError);
  });
  test(
    'failure retains validated incumbent and never exposes optimal proof',
    () {
      final s = ReoptimizationSession(
        ReoptimizationRequest(
          f.fixture(days: [1]),
          reference: [1],
          locks: {},
        ),
      );
      while (s.run(maxNodes: 1).best == null) {}
      final r = s.run(maxNodes: -1);
      expect(r.error, isNotNull);
      valid(s, r);
      expect(r.optimalityProven, false);
      expect(s.run(maxNodes: 100).error, isNotNull);
    },
  );
  test('200 locked problems: independent exhaustive constraints, reference arithmetic and tie oracle', () {
    final random = Random(1802);
    for (var i = 0; i < 200; i++) {
      final base = generated.generated(random, i);
      final n = base.slotDays.length;
      final reference = List.generate(
        n,
        (_) => random.nextInt(base.doctors.length + 1) - 1,
      );
      final locks = <int, int>{
        for (var k = 0; k < n; k++)
          if (reference[k] >= 0 && random.nextBool()) k: reference[k],
      };
      final data = base.toMessage()
        ..['fixedAssignments'] = {
          for (final e in locks.entries) '${e.key}': e.value,
        }
        ..['referenceAssignments'] = reference;
      final p = Problem.fromMessage(data);
      List<List<int>> rows(bool b) => exhaustive
          .oracle(base, substitutions: b)
          .map((r) => r.$1)
          .where((a) => locks.entries.every((e) => a[e.key] == e.value))
          .toList();
      final aRows = rows(false);
      final allowed = aRows.isNotEmpty ? aRows : rows(true);
      List<ReferenceFraction>? bestQ;
      int? bestChanges;
      for (final a in allowed) {
        final q = const ReferenceClinicalQualityCalculator().calculate(p, a);
        final changes = List.generate(
          n,
          (k) => k,
        ).where((k) => a[k] != reference[k]).length;
        int order = 0;
        if (bestQ != null) {
          for (var k = 0; k < 19; k++) {
            order = q[k].compareTo(bestQ[k]);
            if (order != 0) break;
          }
        }
        if (bestQ == null ||
            order < 0 ||
            (order == 0 && changes < bestChanges!)) {
          bestQ = q;
          bestChanges = changes;
        }
      }
      try {
        ReoptimizationRequest(base, reference: reference, locks: locks);
      } on ReoptimizationInputException {
        expect(allowed, isEmpty, reason: 'unsafe preflight seed 1802 index $i');
      }
      // Direct core also tested for contradictory locks, bypassing preflight only.
      for (final pruning in [false, true]) {
        final s = TransitionSession(
          p,
          enablePruning: pruning,
          candidateOrdering: pruning,
          earlyDeadEnds: pruning,
          experimentalTwoPhase: pruning,
          clinicalBounds: pruning,
          forwardChecking: pruning,
        );
        var r = s.run(maxNodes: 1000000);
        if (r.pauseReason == PauseReason.stageTransition) {
          r = s.run(maxNodes: 1000000);
        }
        expect(
          r.status,
          allowed.isEmpty ? SearchStatus.infeasible : SearchStatus.optimal,
          reason: 'seed 1802 index $i prune $pruning',
        );
        if (bestQ != null) {
          expect(
            r.best!.clinicalQuality!.components
                .map((x) => x.toString())
                .toList(),
            bestQ.map((x) => x.toString()).toList(),
          );
          final actual = List.generate(
            n,
            (k) => k,
          ).where((k) => r.best!.assignments[k] != reference[k]).length;
          expect(actual, bestChanges);
          expect(
            const SolutionValidator()
                .validate(s.problem, r.best!, localEvidence: s)
                .isValid,
            true,
          );
        }
        expect(
          s.restrictedVerdict,
          aRows.isNotEmpty
              ? RestrictedVerdict.feasible
              : RestrictedVerdict.provenInfeasible,
        );
      }
    }
  });
}
