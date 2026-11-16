import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import 'clinical_reliability_test.dart' as fixture;
import 'clinical_search_test.dart' as examples;

void main() {
  test('equal Q1–Q3 bound never prunes a better K4 objective', () {
    final p = Problem(
      startDate: DateTime.utc(2026, 11),
      doctors: [
        Doctor(id: 'k1', seniorityLevel: SeniorityLevel.k1),
        Doctor(id: 'k4', seniorityLevel: SeniorityLevel.k4),
      ],
      slotsPerDay: [1],
      slotRoles: [DutyRole.senior],
      slotRequirements: [SlotRequirement.required],
      dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
    );
    final s = SearchSession(
      p,
      candidateOrdering: true,
      earlyDeadEnds: true,
      experimentalTwoPhase: true,
      clinicalBounds: true,
    );
    var r = s.run(maxNodes: 100);
    while (r.canResume) {
      r = s.run(maxNodes: 100);
    }
    expect(r.status, SearchStatus.optimal);
    expect(r.best!.assignments, [1]);
    expect(r.best!.clinicalQuality!.components[3].toString(), '-1');
    expect(s.clinicalBoundChecks, greaterThan(0));
  });
  test('bound rejects inferior coverage while keeping true optimum', () {
    final p = examples.input();
    final s = SearchSession(
      p,
      candidateOrdering: true,
      earlyDeadEnds: true,
      experimentalTwoPhase: true,
      clinicalBounds: true,
    );
    var r = s.run(maxNodes: 1000);
    while (r.canResume) {
      r = s.run(maxNodes: 1000);
    }
    expect(r.status, SearchStatus.optimal);
    expect(r.best!.clinicalQuality!.compareTo(fixture.optimum(p)!), 0);
    expect(s.clinicalBoundChecks, greaterThan(0));
    expect(s.clinicalPruned, greaterThan(0));
  });
  test('200 problems match independent exhaustive oracle with bounds and two-phase A/B', () {
    final random = Random(150520);
    for (var i = 0; i < 200; i++) {
      final p = fixture.generated(random, i), expected = fixture.optimum(p);
      for (final bounded in [false, true]) {
        final s = TransitionSession(
          p,
          candidateOrdering: true,
          earlyDeadEnds: true,
          experimentalTwoPhase: true,
          clinicalBounds: bounded,
        );
        var r = s.run(maxNodes: 1);
        while (r.canResume && s.phase == TransitionPhase.restricted) {
          r = s.run(maxNodes: 3);
        }
        if (expected != null) {
          expect(
            r.status,
            SearchStatus.optimal,
            reason: 'case $i bound=$bounded',
          );
          expect(s.restrictedVerdict, RestrictedVerdict.feasible);
          expect(r.best!.clinicalQuality!.compareTo(expected), 0);
          expect(
            const SolutionValidator().validate(s.problem, r.best!).isValid,
            true,
          );
        } else {
          expect(
            s.restrictedVerdict,
            RestrictedVerdict.provenInfeasible,
            reason: 'case $i',
          );
          final b = fixture.optimum(s.problem, b: s);
          while (r.canResume) {
            r = s.run(maxNodes: 3);
          }
          expect(
            r.status,
            b == null ? SearchStatus.infeasible : SearchStatus.optimal,
            reason: 'B $i bound=$bounded',
          );
          if (b != null) {
            expect(r.best!.clinicalQuality!.compareTo(b), 0);
            final v = const SolutionValidator().validate(
              s.problem,
              r.best!,
              localEvidence: s,
            );
            expect(v.isValid, true);
            expect(v.permanentApprovalAllowed, false);
          }
        }
      }
    }
  });
  test('bounds preserve resume, deadline, and cancel state', () {
    final p = examples.input(),
        s = TransitionSession(
          p,
          candidateOrdering: true,
          earlyDeadEnds: true,
          experimentalTwoPhase: true,
          clinicalBounds: true,
        );
    expect(
      s.run(maxNodes: 1, timeLimit: Duration.zero).status,
      SearchStatus.timeoutWithoutSolution,
    );
    expect(s.restrictedVerdict, RestrictedVerdict.pending);
    var r = s.run(maxNodes: 1);
    while (r.best == null && r.canResume) {
      r = s.run(maxNodes: 1);
    }
    expect(r.best, isNotNull);
    expect(r.status, SearchStatus.feasibleNotProven);
    final before = r.best;
    expect(s.run(maxNodes: 1, timeLimit: Duration.zero).best, same(before));
    while (r.canResume) {
      r = s.run(maxNodes: 1);
    }
    expect(r.status, SearchStatus.optimal);
    expect(r.best!.clinicalQuality!.compareTo(fixture.optimum(s.problem)!), 0);
    final c = TransitionSession(
      p,
      candidateOrdering: true,
      earlyDeadEnds: true,
      experimentalTwoPhase: true,
      clinicalBounds: true,
    );
    c.cancel();
    expect(c.run(maxNodes: 1).status, SearchStatus.cancelled);
    expect(c.restrictedVerdict, RestrictedVerdict.cancelled);
  });
}
