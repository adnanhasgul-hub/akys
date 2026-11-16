import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/clinical_quality.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import 'optional_search_test.dart' as independent;

Problem generated(Random random, int n) {
  final seniorCount = random.nextInt(3), juniorCount = 1 + random.nextInt(2);
  return Problem(
    startDate: DateTime.utc(2026, 11, 1),
    doctors: [
      for (var i = 0; i < seniorCount + juniorCount; i++)
        Doctor(
          id: 'd$i',
          group: i < seniorCount ? DutyGroup.senior : DutyGroup.junior,
          seniorityLevel: i < seniorCount ? SeniorityLevel.values[i] : null,
          maxDuties: random.nextInt(3),
          unavailable: {
            if (random.nextInt(5) == 0) 0,
            if (random.nextInt(5) == 0) 3,
          },
          previousDuties: random.nextInt(6) == 0
              ? [DateTime.utc(2026, 10, 31)]
              : [],
        ),
    ],
    slotsPerDay: [2, 0, 0, 2],
    slotRoles: [
      DutyRole.senior,
      DutyRole.junior,
      DutyRole.senior,
      DutyRole.junior,
    ],
    slotRequirements: [
      for (var i = 0; i < 4; i++)
        random.nextBool() ? SlotRequirement.required : SlotRequirement.optional,
    ],
    dayDifficulties: [
      for (var i = 0; i < 4; i++)
        DayDifficulty(
          weekdayScore: 1 + random.nextInt(10),
          holidayName: i == 1 && n.isEven ? 'Tatil' : null,
          holidayScore: i == 1 && n.isEven ? 7 : null,
        ),
    ],
  );
}

ClinicalQuality? optimum(Problem p, {TransitionSession? b}) {
  final all = independent.oracle(p, substitutions: b != null);
  ClinicalQuality? best;
  for (final row in all) {
    final candidate = Solution(row.$1, row.$2);
    final q = b == null
        ? const ClinicalQualityEvaluator().evaluate(p, candidate)
        : const ClinicalQualityEvaluator().evaluatePhaseBCandidate(
            p,
            candidate,
            session: b,
          );
    if (best == null || q.compareTo(best) < 0) best = q;
  }
  return best;
}

void main() {
  test('clinical mode rejects missing data and legacy is explicit', () {
    final p = Problem(
      doctors: [Doctor(id: 's')],
      slotsPerDay: [1],
    );
    expect(() => SearchSession(p), throwsArgumentError);
    expect(() => TransitionSession(p), throwsArgumentError);
    expect(
      SearchSession(
        p,
        mode: OptimizationMode.prototypeLegacy,
      ).usesClinicalQuality,
      isFalse,
    );
    final partial = Problem(
      startDate: DateTime.utc(2026),
      doctors: [Doctor(id: 's', seniorityLevel: SeniorityLevel.k1)],
      slotsPerDay: [1],
      slotRoles: [DutyRole.senior],
      dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
    );
    expect(() => SearchSession(partial), throwsArgumentError);
    expect(
      () => SearchSession(Problem.fromMessage(partial.toMessage())),
      throwsArgumentError,
    );
  });
  test(
    '200 seeded independent exhaustive models agree in both modes of pruning',
    () {
      final random = Random(14042);
      var bCount = 0;
      for (var i = 0; i < 200; i++) {
        final p = generated(random, i);
        final aOpt = optimum(p);
        for (final pruning in [false, true]) {
          final search = SearchSession(p, enablePruning: pruning);
          final a = search.run(maxNodes: 100000);
          expect(
            a.status,
            aOpt == null ? SearchStatus.infeasible : SearchStatus.optimal,
            reason: 'case $i pruning $pruning A',
          );
          if (aOpt != null) {
            expect(
              a.best!.clinicalQuality!.compareTo(aOpt),
              0,
              reason: 'case $i A',
            );
          }
          final session = TransitionSession(p, enablePruning: pruning);
          var result = session.run(maxNodes: 100000);
          if (aOpt == null) {
            expect(
              session.restrictedVerdict,
              RestrictedVerdict.provenInfeasible,
            );
            expect(session.phase, TransitionPhase.substitution);
            final bOpt = optimum(session.problem, b: session);
            result = session.run(maxNodes: 100000);
            expect(
              result.status,
              bOpt == null ? SearchStatus.infeasible : SearchStatus.optimal,
              reason: 'case $i B',
            );
            if (bOpt != null) {
              bCount++;
              expect(
                result.best!.clinicalQuality!.compareTo(bOpt),
                0,
                reason: 'case $i B',
              );
              expect(
                const SolutionValidator()
                    .validate(
                      session.problem,
                      result.best!,
                      localEvidence: session,
                    )
                    .permanentApprovalAllowed,
                false,
              );
            }
          } else {
            expect(result.status, SearchStatus.optimal);
            expect(session.restrictedVerdict, RestrictedVerdict.feasible);
            expect(result.best!.clinicalQuality!.compareTo(aOpt), 0);
          }
        }
      }
      expect(bCount, greaterThan(0));
    },
  );
  test('clinical invalid input is not infeasibility and timeout or cancellation does not grant B', () {
    final p = generated(Random(89), 0);
    final s = TransitionSession(p);
    final timed = s.run(maxNodes: 10, timeLimit: Duration.zero);
    expect(timed.status, SearchStatus.timeoutWithoutSolution);
    expect(s.restrictedVerdict, RestrictedVerdict.pending);
    s.cancel();
    expect(s.run(maxNodes: 10).status, SearchStatus.cancelled);
    expect(s.restrictedVerdict, RestrictedVerdict.cancelled);
    expect(s.permitsPhaseBCandidate(s.problem), false);
  });
  test('19 component lexicographic and exact rational comparisons', () {
    for (var i = 0; i < 19; i++) {
      final x = [for (var j = 0; j < 19; j++) Exact.integer(j == i ? -1 : 0)];
      final y = [for (var j = 0; j < 19; j++) Exact.integer(j > i ? -1000 : 0)];
      expect(
        ClinicalQuality(x).compareTo(ClinicalQuality(y)),
        lessThan(0),
        reason: 'component $i',
      );
      expect(
        ClinicalQuality.fromMessage(ClinicalQuality(x).toMessage())
            .compareTo(ClinicalQuality(x)),
        0,
      );
    }
    expect(
      Exact(
        BigInt.from(1),
        BigInt.from(3),
      ).compareTo(Exact(BigInt.from(2), BigInt.from(6))),
      0,
    );
  });

  test(
    'proof is bound to the original session and snapshot, never serialized',
    () {
      final p = Problem(
        startDate: DateTime.utc(2026, 11),
        doctors: [Doctor(id: 'junior', group: DutyGroup.junior)],
        slotsPerDay: [1],
        slotRoles: [DutyRole.senior],
        slotRequirements: [SlotRequirement.required],
        dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
      );
      final first = TransitionSession(p);
      expect(first.run(maxNodes: 100).pauseReason, PauseReason.stageTransition);
      final result = first.run(maxNodes: 100);
      expect(result.status, SearchStatus.optimal);
      final copiedProblem = Problem.fromMessage(first.problem.toMessage());
      final copiedSolution = Solution.fromMessage(result.best!.toMessage());
      final other = TransitionSession(copiedProblem);
      expect(other.permitsPhaseBCandidate(other.problem), false);
      expect(
        first.verifiesLocalTransition(copiedProblem, copiedSolution),
        false,
      );
      expect(
        other.verifiesLocalTransition(other.problem, copiedSolution),
        false,
      );
      expect(
        const SolutionValidator()
            .validate(copiedProblem, copiedSolution, localEvidence: other)
            .isValid,
        false,
      );
      expect(
        const SolutionValidator()
            .validate(first.problem, result.best!, localEvidence: first)
            .permanentApprovalAllowed,
        false,
      );
    },
  );
}
