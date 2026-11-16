import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import '../../tool/solver_v2/quality_trace.dart' as trace;

void main() {
  test('one-node sampling captures every incumbent and strict improvement', () {
    final p = Problem(
      startDate: DateTime.utc(2026, 11),
      doctors: [
        Doctor(id: 'senior', seniorityLevel: SeniorityLevel.k1),
        Doctor(id: 'j1', group: DutyGroup.junior, maxDuties: 1),
        Doctor(id: 'j2', group: DutyGroup.junior, maxDuties: 2),
      ],
      slotsPerDay: [2],
      slotRoles: [DutyRole.senior, DutyRole.junior],
      slotRequirements: [SlotRequirement.required, SlotRequirement.optional],
      dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
    );
    final s = SearchSession(p, candidateOrdering: true, earlyDeadEnds: true);
    Solution? last;
    var updates = 0;
    SearchResult result;
    do {
      result = s.run(maxNodes: 1);
      if (result.best != null && !identical(last, result.best)) {
        expect(
          const SolutionValidator().validate(p, result.best!).isValid,
          true,
        );
        if (last != null) {
          expect(
            result.best!.clinicalQuality!.compareTo(last.clinicalQuality!),
            lessThan(0),
          );
        }
        last = result.best;
        updates++;
      }
    } while (result.canResume);
    expect(result.status, SearchStatus.optimal);
    expect(updates, s.incumbentImprovements + 1);
    expect(updates, greaterThan(1));
  });
  for (final (n, days) in [(6, 30), (10, 30), (15, 31), (20, 31)]) {
    for (final variant in ['mixed', 'surplus', 'forced', 'ratio']) {
      test('$n/$days $variant has a validated independent witness', () {
        final p = trace.traceScenario(n, days, variant);
        expect(
          const SolutionValidator().validate(p, trace.witness(p)).isValid,
          true,
        );
        expect(
          p.doctors.where((d) => d.group == DutyGroup.senior).length,
          greaterThanOrEqualTo(4),
        );
        expect(
          p.doctors.where((d) => d.group == DutyGroup.junior).length,
          greaterThan(0),
        );
      });
    }
  }
  test(
    'restricted phase is exhaustively impossible, substitution is proven',
    () {
      final p = trace.traceScenario(6, 30, 'transition');
      final s = TransitionSession(
        p,
        candidateOrdering: true,
        earlyDeadEnds: true,
      );
      expect(s.run(maxNodes: 100).pauseReason, PauseReason.stageTransition);
      expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
      final b = s.run(maxNodes: 100);
      expect(b.status, SearchStatus.optimal);
      final valid = const SolutionValidator().validate(
        s.problem,
        b.best!,
        localEvidence: s,
      );
      expect(valid.isValid, true);
      expect(valid.substitutionCount, 1);
      expect(valid.permanentApprovalAllowed, false);
    },
  );
}
