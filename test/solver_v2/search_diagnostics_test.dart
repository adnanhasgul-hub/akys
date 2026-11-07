import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import 'clinical_search_test.dart' as fixture;

void main() {
  test('first incumbent observer fires once and preserves A/B safety', () {
    for (final noSenior in [false, true]) {
      var calls = 0;
      late final TransitionSession session;
      session = TransitionSession(
        fixture.input(noSenior: noSenior),
        candidateOrdering: true,
        earlyDeadEnds: true,
        experimentalTwoPhase: true,
        onFirstIncumbent: (solution) {
          calls++;
          expect(() => session.run(maxNodes: 1), throwsStateError);
          final result = const SolutionValidator().validate(
            session.problem,
            solution,
            localEvidence: session,
          );
          expect(result.isValid, true);
          if (noSenior) expect(result.permanentApprovalAllowed, false);
        },
      );
      var result = session.run(maxNodes: 1);
      while (result.canResume) {
        result = session.run(maxNodes: 1);
      }
      expect(result.status, SearchStatus.optimal);
      expect(calls, 1);
    }
  });
  test('mandatory pruning counter tracks rejected partial branches', () {
    final p = Problem(
      startDate: DateTime.utc(2026, 11),
      doctors: [
        Doctor(id: 'a', seniorityLevel: SeniorityLevel.k1, must: {0}),
        Doctor(id: 'b', seniorityLevel: SeniorityLevel.k2),
      ],
      slotsPerDay: [1],
      slotRoles: [DutyRole.senior],
      slotRequirements: [SlotRequirement.required],
      dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
    );
    final s = SearchSession(p, earlyDeadEnds: true);
    final r = s.run(maxNodes: 100);
    expect(r.status, SearchStatus.optimal);
    expect(s.mandatoryPruned, 1);
    expect(s.feasibilityPruned, 0);
  });
  test('capacity pruning counter counts infeasible prefixes', () {
    final p = Problem(
      startDate: DateTime.utc(2026, 11),
      doctors: [
        Doctor(id: 'a', seniorityLevel: SeniorityLevel.k1, maxDuties: 1),
      ],
      slotsPerDay: [1, 1],
      slotRoles: [DutyRole.senior, DutyRole.senior],
      slotRequirements: [SlotRequirement.required, SlotRequirement.required],
      dayDifficulties: [
        const DayDifficulty(weekdayScore: 3),
        const DayDifficulty(weekdayScore: 3),
      ],
    );
    final s = SearchSession(p, earlyDeadEnds: true);
    final r = s.run(maxNodes: 100);
    expect(r.status, SearchStatus.infeasible);
    expect(s.feasibilityPruned, 1);
    expect(s.mandatoryPruned, 0);
  });
}
