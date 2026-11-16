import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import '../../tool/solver_v2/clinical_resilience.dart';
import 'clinical_reliability_test.dart' as oracle;
import 'optional_search_test.dart' as exhaustive;
import 'support/reference_clinical_quality.dart';

TransitionSession strategy(Problem p, String name) => TransitionSession(
  p,
  earlyDeadEnds: true,
  candidateOrdering: name != 'deadends',
  experimentalTwoPhase: name == 'twophase' || name == 'bounded',
  clinicalBounds: name == 'bounded',
);
const strategies = ['deadends', 'combined', 'twophase', 'bounded'];

SearchResult finish(TransitionSession s) {
  var r = s.run(maxNodes: 1);
  Solution? previous;
  var iterations = 0;
  while (true) {
    if (s.phase == TransitionPhase.substitution) {
      expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
    }
    if (r.best != null && !identical(previous, r.best)) {
      expect(
        const SolutionValidator()
            .validate(s.problem, r.best!, localEvidence: s)
            .isValid,
        true,
      );
      final reference = const ReferenceClinicalQualityCalculator().calculate(
        s.problem,
        r.best!.assignments,
      );
      expect(
        r.best!.clinicalQuality!.components.map((x) => x.toString()).toList(),
        reference.map((x) => x.toString()).toList(),
      );
      if (previous != null) {
        expect(
          r.best!.clinicalQuality!.compareTo(previous.clinicalQuality!),
          lessThan(0),
        );
      }
      previous = r.best;
    }
    if (!r.canResume) return r;
    if (++iterations > 100000) fail('small fixture exceeded node guard');
    r = s.run(maxNodes: 1);
  }
}

void main() {
  for (final capacity in [1, 2]) {
    test(
      'optional coverage matches junior capacity $capacity with exact three-day gap',
      () {
        final p = Problem(
          startDate: DateTime.utc(2026, 11),
          doctors: [
            Doctor(id: 's', seniorityLevel: SeniorityLevel.k4, maxDuties: 2),
            Doctor(id: 'j', group: DutyGroup.junior, maxDuties: capacity),
          ],
          slotsPerDay: [2, 0, 0, 2],
          slotRoles: [
            DutyRole.senior,
            DutyRole.junior,
            DutyRole.senior,
            DutyRole.junior,
          ],
          slotRequirements: [
            SlotRequirement.required,
            SlotRequirement.optional,
            SlotRequirement.required,
            SlotRequirement.optional,
          ],
          dayDifficulties: List.filled(4, const DayDifficulty(weekdayScore: 3)),
        );
        for (final method in strategies) {
          final r = finish(strategy(p, method));
          expect(r.status, SearchStatus.optimal);
          expect(
            r.best!.clinicalQuality!.components[1].toString(),
            '-$capacity',
          );
        }
      },
    );
  }
  test('previous month boundary: two days blocked, three days allowed', () {
    for (final gap in [2, 3]) {
      final p = Problem(
        startDate: DateTime.utc(2026, 11),
        doctors: [
          Doctor(
            id: 's',
            seniorityLevel: SeniorityLevel.k1,
            previousDuties: [
              DateTime.utc(2026, 11).subtract(Duration(days: gap)),
            ],
          ),
        ],
        slotsPerDay: [1],
        slotRoles: [DutyRole.senior],
        slotRequirements: [SlotRequirement.required],
        dayDifficulties: [const DayDifficulty(weekdayScore: 5)],
      );
      final rows = exhaustive.oracle(p, substitutions: false);
      expect(rows.isEmpty, gap == 2);
      for (final method in strategies) {
        expect(
          finish(strategy(p, method)).status,
          gap == 2 ? SearchStatus.infeasible : SearchStatus.optimal,
        );
      }
    }
  });

  for (final name in resilienceCases.where(
    (x) => x.endsWith('open') || x.endsWith('tight'),
  )) {
    test('$name snapshot roundtrip and independent witness', () {
      final p = resilienceProblem(name);
      expect(Problem.fromMessage(p.toMessage()).toMessage(), p.toMessage());
      expect(
        const SolutionValidator().validate(p, resilienceWitness(p)).isValid,
        true,
      );
    });
  }
  for (final name in [
    '6-tight',
    '10-tight',
    '15-tight',
    '20-tight',
    '6-transition',
    '10-capacity',
  ]) {
    test('$name forced constraints have independently known outcome', () {
      for (final method in strategies) {
        final s = strategy(resilienceProblem(name), method), r = finish(s);
        final impossible =
            name.endsWith('capacity') || name.endsWith('blocked');
        expect(
          r.status,
          impossible ? SearchStatus.infeasible : SearchStatus.optimal,
        );
        if (name.endsWith('transition')) {
          expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
          expect(r.best!.clinicalQuality!.components.first.toString(), '8');
          expect(
            const SolutionValidator()
                .validate(s.problem, r.best!, localEvidence: s)
                .permanentApprovalAllowed,
            false,
          );
        }
      }
    });
  }
  test('blocked last day never yields false feasible or optimal result', () {
    for (final method in strategies) {
      final s = strategy(resilienceProblem('15-blocked'), method);
      final r = s.run(maxNodes: 1000);
      expect(r.best, isNull);
      expect([
        SearchStatus.timeoutWithoutSolution,
        SearchStatus.infeasible,
        SearchStatus.paused,
      ], contains(r.status));
      if (s.phase == TransitionPhase.substitution) {
        expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
      }
    }
  });
  test(
    'contradictory must/cannot is invalid input, not infeasibility proof',
    () {
      expect(() => resilienceProblem('20-conflict'), throwsArgumentError);
    },
  );
  test('200 new deterministic cases: all four strategies vs independent exhaustive oracle', () {
    final random = Random(resilienceSeed);
    for (var i = 0; i < 200; i++) {
      final p = oracle.generated(random, i);
      final a = exhaustive.oracle(p, substitutions: false);
      final rows = a.isNotEmpty ? a : exhaustive.oracle(p, substitutions: true);
      final qualities = rows
          .map(
            (r) =>
                const ReferenceClinicalQualityCalculator().calculate(p, r.$1),
          )
          .toList();
      qualities.sort((a, b) {
        for (var k = 0; k < 19; k++) {
          final c = a[k].compareTo(b[k]);
          if (c != 0) return c;
        }
        return 0;
      });
      for (final method in strategies) {
        final s = strategy(p, method);
        final r = finish(s);
        final expected = qualities.isEmpty ? null : qualities.first;
        expect(
          r.status,
          expected == null ? SearchStatus.infeasible : SearchStatus.optimal,
          reason: 'seed=$resilienceSeed case=$i method=$method',
        );
        if (expected != null) {
          expect(
            r.best!.clinicalQuality!.components
                .map((x) => x.toString())
                .toList(),
            expected.map((x) => x.toString()).toList(),
          );
        }
        expect(
          s.restrictedVerdict,
          a.isEmpty
              ? RestrictedVerdict.provenInfeasible
              : RestrictedVerdict.feasible,
        );
      }
    }
  });
  test('zero-time timeout, cancel and pause preserve A safety', () {
    for (final method in strategies) {
      final s = strategy(resilienceProblem('6-open'), method);
      expect(
        s.run(maxNodes: 1, timeLimit: Duration.zero).status,
        SearchStatus.timeoutWithoutSolution,
      );
      expect(s.restrictedVerdict, RestrictedVerdict.pending);
      final before = s.run(maxNodes: 1);
      final after = s.run(maxNodes: 1);
      expect(after.visitedNodes, greaterThanOrEqualTo(before.visitedNodes));
      s.cancel();
      expect(s.run(maxNodes: 1).status, SearchStatus.cancelled);
      expect(s.phase, TransitionPhase.done);
      expect(s.restrictedVerdict, RestrictedVerdict.cancelled);
    }
  });
}
