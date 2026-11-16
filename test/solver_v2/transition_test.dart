import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

TransitionSession legacyTransition(Problem p, {bool enablePruning = true}) =>
    TransitionSession(
      p,
      enablePruning: enablePruning,
      mode: OptimizationMode.prototypeLegacy,
    );

Problem problem(
  int seniorCount,
  int juniorCount,
  List<int> days, {
  int cap = 8,
}) => Problem(
  startDate: DateTime.utc(2026, 11, 1),
  doctors: [
    for (var i = 0; i < seniorCount; i++) Doctor(id: 's$i', maxDuties: cap),
    for (var i = 0; i < juniorCount; i++)
      Doctor(id: 'j$i', group: DutyGroup.junior, maxDuties: cap),
  ],
  slotsPerDay: days,
  slotRoles: [
    for (final n in days)
      for (var i = 0; i < n; i++) DutyRole.senior,
  ],
);
SearchResult finish(TransitionSession s, {int budget = 1}) {
  var r = s.run(maxNodes: budget);
  while (r.canResume) {
    r = s.run(maxNodes: budget);
  }
  return r;
}

void main() {
  const validator = SolutionValidator();
  test('real seniors cover schedule; no phase B', () {
    final s = legacyTransition(problem(1, 1, [1, 0, 0, 1]));
    final r = finish(s);
    expect(r.best, isNotNull);
    expect(s.restrictedVerdict, RestrictedVerdict.feasible);
    expect(s.phase, TransitionPhase.done);
    expect(validator.validate(s.problem, r.best!).isValid, isTrue);
  });
  test('one substitution, bound snapshot, forged claim rejected', () {
    final original = problem(0, 1, [1]);
    final s = legacyTransition(original);
    final r = finish(s);
    expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
    expect(r.status, SearchStatus.optimal);
    expect(r.best!.quality.first, 1);
    final valid = validator.validate(s.problem, r.best!, localEvidence: s);
    expect(valid.isValid, isTrue);
    expect(valid.substitutionCount, 1);
    expect(valid.permanentApprovalAllowed, isFalse);
    expect(validator.validate(s.problem, r.best!).isValid, isFalse);
    expect(
      validator.validate(original, r.best!, localEvidence: s).isValid,
      isFalse,
    );
    expect(
      validator
          .validate(s.problem, Solution([0], [0, 0, 1]), localEvidence: s)
          .isValid,
      isFalse,
    );
  });
  test(
    'two substitutions and phase B pause/resume; impossible with limits',
    () {
      final s = legacyTransition(problem(0, 1, [1, 0, 0, 1]));
      final first = s.run(maxNodes: 100);
      expect(first.canResume, isTrue);
      expect(s.phase, TransitionPhase.substitution);
      final r = finish(s);
      expect(r.best!.quality.first, 2);
      expect(
        validator.validate(s.problem, r.best!, localEvidence: s).isValid,
        isTrue,
      );
      final bad = legacyTransition(problem(0, 1, [1, 1]));
      expect(finish(bad).status, SearchStatus.infeasible);
    },
  );
  test(
    'phase B timeout preserves locally verified incumbent without proof',
    () {
      final s = legacyTransition(problem(0, 2, [1, 0, 0, 1]));
      var r = s.run(maxNodes: 100);
      expect(s.phase, TransitionPhase.substitution);
      while (r.best == null) {
        r = s.run(maxNodes: 1);
      }
      final held = r.best!;
      final stopped = s.run(maxNodes: 100, timeLimit: Duration.zero);
      expect(stopped.status, SearchStatus.feasibleNotProven);
      expect(stopped.best, same(held));
      expect(
        validator.validate(s.problem, held, localEvidence: s).isValid,
        isTrue,
      );
      expect(
        validator
            .validate(s.problem, held, localEvidence: s)
            .permanentApprovalAllowed,
        isFalse,
      );
    },
  );
  test('timeout and cancellation do not authorize transition', () {
    final s = legacyTransition(problem(0, 1, [1]));
    expect(
      s.run(maxNodes: 50, timeLimit: Duration.zero).status,
      SearchStatus.timeoutWithoutSolution,
    );
    expect(s.restrictedVerdict, RestrictedVerdict.pending);
    expect(s.phase, TransitionPhase.restricted);
    s.cancel();
    expect(s.run(maxNodes: 50).status, SearchStatus.cancelled);
    expect(s.restrictedVerdict, RestrictedVerdict.cancelled);
  });
  test('independent exhaustive oracle verifies minimum substitutions with pruning on and off', () {
    for (var ns = 0; ns <= 2; ns++) {
      for (var nj = 0; nj <= 2; nj++) {
        for (var mask = 1; mask < 16; mask++) {
          final p = problem(ns, nj, [
            for (var d = 0; d < 4; d++) (mask >> d) & 1,
          ], cap: 2);
          final days = p.slotDays;
          int? minimum;
          void enumerate(List<int> a) {
            if (a.length < days.length) {
              for (var i = 0; i < p.doctors.length; i++) {
                enumerate([...a, i]);
              }
              return;
            }
            final counts = List<int>.filled(p.doctors.length, 0);
            for (var i = 0; i < a.length; i++) {
              counts[a[i]]++;
              if (counts[a[i]] > 2) return;
              for (var j = 0; j < i; j++) {
                if (a[i] == a[j] && (days[i] - days[j]).abs() < 3) return;
              }
            }
            final n = a
                .where((i) => p.doctors[i].group == DutyGroup.junior)
                .length;
            if (minimum == null || n < minimum!) minimum = n;
          }

          enumerate([]);
          for (final pruned in [true, false]) {
            final s = legacyTransition(p, enablePruning: pruned);
            final r = finish(s, budget: 3);
            if (minimum == null) {
              expect(r.status, SearchStatus.infeasible);
            } else if (minimum == 0) {
              expect(s.restrictedVerdict, RestrictedVerdict.feasible);
              expect(r.best, isNotNull);
            } else {
              expect(r.status, SearchStatus.optimal);
              expect(r.best!.quality.first, minimum, reason: '$ns/$nj/$mask');
              expect(
                validator
                    .validate(s.problem, r.best!, localEvidence: s)
                    .isValid,
                isTrue,
              );
            }
          }
        }
      }
    }
  });
}
