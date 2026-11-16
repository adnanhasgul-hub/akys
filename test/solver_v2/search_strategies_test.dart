import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import 'clinical_reliability_test.dart' as fixture;

void main() {
  test(
    'four strategies agree with exhaustive oracle on 200 seeded problems',
    () {
      final random = Random(1502);
      for (var i = 0; i < 200; i++) {
        final base = fixture.generated(random, i);
        // Add must constraints without creating an invalid must/cannot input.
        final docs = [
          for (var d = 0; d < base.doctors.length; d++)
            Doctor(
              id: base.doctors[d].id,
              group: base.doctors[d].group,
              seniorityLevel: base.doctors[d].seniorityLevel,
              maxDuties: base.doctors[d].maxDuties,
              unavailable: base.doctors[d].unavailable,
              previousDuties: base.doctors[d].previousDuties,
              must: {
                if ((i + d) % 4 == 0 &&
                    !base.doctors[d].unavailable.contains(0))
                  0,
              },
            ),
        ];
        final p = Problem(
          doctors: docs,
          slotsPerDay: base.slotsPerDay,
          startDate: base.startDate,
          slotRoles: base.slotRoles,
          slotRequirements: base.slotRequirements,
          dayDifficulties: base.dayDifficulties,
        );
        final expected = fixture.optimum(p);
        for (final (ordered, dead) in [
          (false, false),
          (true, false),
          (false, true),
          (true, true),
        ]) {
          final search = SearchSession(
            p,
            candidateOrdering: ordered,
            earlyDeadEnds: dead,
          );
          var result = search.run(maxNodes: 3);
          while (result.canResume) {
            result = search.run(maxNodes: 3);
          }
          expect(
            result.status,
            expected == null ? SearchStatus.infeasible : SearchStatus.optimal,
            reason: 'case $i $ordered/$dead',
          );
          if (expected != null) {
            expect(
              result.best!.clinicalQuality!.compareTo(expected),
              0,
              reason: 'case $i $ordered/$dead',
            );
            expect(
              const SolutionValidator().validate(p, result.best!).isValid,
              true,
            );
          }
          final session = TransitionSession(
            p,
            candidateOrdering: ordered,
            earlyDeadEnds: dead,
          );
          var phase = session.run(maxNodes: 100000);
          if (expected == null) {
            expect(
              session.restrictedVerdict,
              RestrictedVerdict.provenInfeasible,
            );
            final b = fixture.optimum(session.problem, b: session);
            phase = session.run(maxNodes: 100000);
            expect(
              phase.status,
              b == null ? SearchStatus.infeasible : SearchStatus.optimal,
              reason: 'B case $i',
            );
            if (b != null) {
              expect(phase.best!.clinicalQuality!.compareTo(b), 0);
              expect(
                const SolutionValidator()
                    .validate(
                      session.problem,
                      phase.best!,
                      localEvidence: session,
                    )
                    .isValid,
                true,
              );
            }
          } else {
            expect(phase.status, SearchStatus.optimal);
            expect(session.restrictedVerdict, RestrictedVerdict.feasible);
            expect(phase.best!.clinicalQuality!.compareTo(expected), 0);
          }
        }
      }
    },
  );
  test('new strategies never treat deadline or cancellation as proof', () {
    final p = fixture.generated(Random(90), 0);
    for (final (ordered, dead) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      final s = TransitionSession(
        p,
        candidateOrdering: ordered,
        earlyDeadEnds: dead,
      );
      expect(
        s.run(maxNodes: 100, timeLimit: Duration.zero).status,
        SearchStatus.timeoutWithoutSolution,
      );
      expect(s.restrictedVerdict, RestrictedVerdict.pending);
      s.cancel();
      expect(s.run(maxNodes: 100).status, SearchStatus.cancelled);
    }
  });
}
