import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import 'clinical_reliability_test.dart' as reference;
import 'clinical_search_test.dart' as fixtures;

void main() {
  test('200 small problems retain exact oracle optimum and A/B proof', () {
    final random = Random(151204);
    for (var i = 0; i < 200; i++) {
      final source = reference.generated(random, i);
      final p = Problem(
        doctors: [
          for (var d = 0; d < source.doctors.length; d++)
            Doctor(
              id: source.doctors[d].id,
              group: source.doctors[d].group,
              seniorityLevel: source.doctors[d].seniorityLevel,
              maxDuties: source.doctors[d].maxDuties,
              unavailable: source.doctors[d].unavailable,
              previousDuties: source.doctors[d].previousDuties,
              must: {
                if ((i + d) % 4 == 0 &&
                    !source.doctors[d].unavailable.contains(0))
                  0,
              },
            ),
        ],
        slotsPerDay: source.slotsPerDay,
        startDate: source.startDate,
        slotRoles: source.slotRoles,
        slotRequirements: source.slotRequirements,
        dayDifficulties: source.dayDifficulties,
      );
      final expected = reference.optimum(p);
      final s = TransitionSession(
        p,
        candidateOrdering: true,
        earlyDeadEnds: true,
        experimentalTwoPhase: true,
      );
      var result = s.run(maxNodes: 1);
      while (result.canResume && s.phase == TransitionPhase.restricted) {
        result = s.run(maxNodes: 2);
      }
      if (expected == null) {
        expect(
          s.restrictedVerdict,
          RestrictedVerdict.provenInfeasible,
          reason: 'case $i',
        );
        final b = reference.optimum(s.problem, b: s);
        while (result.canResume) {
          result = s.run(maxNodes: 2);
        }
        expect(
          result.status,
          b == null ? SearchStatus.infeasible : SearchStatus.optimal,
          reason: 'case $i B',
        );
        if (b != null) {
          expect(result.best!.clinicalQuality!.compareTo(b), 0);
          final valid = const SolutionValidator().validate(
            s.problem,
            result.best!,
            localEvidence: s,
          );
          expect(valid.isValid, true);
          expect(valid.permanentApprovalAllowed, false);
        }
      } else {
        expect(result.status, SearchStatus.optimal, reason: 'case $i A');
        expect(s.restrictedVerdict, RestrictedVerdict.feasible);
        expect(result.best!.clinicalQuality!.compareTo(expected), 0);
        expect(
          const SolutionValidator().validate(s.problem, result.best!).isValid,
          true,
        );
      }
    }
  });
  test('restricted timeout and cancellation cannot open B', () {
    final s = TransitionSession(
      fixtures.input(noSenior: true),
      candidateOrdering: true,
      earlyDeadEnds: true,
      experimentalTwoPhase: true,
    );
    expect(
      s.run(maxNodes: 1, timeLimit: Duration.zero).status,
      SearchStatus.timeoutWithoutSolution,
    );
    expect(s.restrictedVerdict, RestrictedVerdict.pending);
    s.cancel();
    expect(s.run(maxNodes: 1).status, SearchStatus.cancelled);
    expect(s.restrictedVerdict, RestrictedVerdict.cancelled);
    expect(s.permitsPhaseBCandidate(s.problem), false);
  });
  test(
    'B deadline and resume keep local proof and only provisional incumbent',
    () {
      final s = TransitionSession(
        fixtures.input(noSenior: true),
        candidateOrdering: true,
        earlyDeadEnds: true,
        experimentalTwoPhase: true,
      );
      var r = s.run(maxNodes: 1000);
      expect(r.pauseReason, PauseReason.stageTransition);
      expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
      expect(
        s.run(maxNodes: 1, timeLimit: Duration.zero).status,
        SearchStatus.timeoutWithoutSolution,
      );
      do {
        r = s.run(maxNodes: 1);
      } while (r.best == null && r.canResume);
      expect(r.best, isNotNull);
      expect(r.status, SearchStatus.feasibleNotProven);
      expect(
        const SolutionValidator()
            .validate(s.problem, r.best!, localEvidence: s)
            .permanentApprovalAllowed,
        false,
      );
      while (r.canResume) {
        r = s.run(maxNodes: 1);
      }
      expect(r.status, SearchStatus.optimal);
      expect(
        const SolutionValidator()
            .validate(s.problem, r.best!, localEvidence: s)
            .isValid,
        true,
      );
    },
  );
  test(
    'optional profiling preserves result and counts complete candidates',
    () {
      final p = fixtures.input();
      final profile = SearchProfile();
      SearchResult finish(SearchSession s) {
        var r = s.run(maxNodes: 1000);
        while (r.canResume) {
          r = s.run(maxNodes: 1000);
        }
        return r;
      }

      final observed = finish(
        SearchSession(
          p,
          candidateOrdering: true,
          earlyDeadEnds: true,
          experimentalTwoPhase: true,
          profile: profile,
        ),
      );
      final plain = finish(
        SearchSession(
          p,
          candidateOrdering: true,
          earlyDeadEnds: true,
          experimentalTwoPhase: true,
        ),
      );
      expect(observed.status, SearchStatus.optimal);
      expect(
        observed.best!.clinicalQuality!.compareTo(plain.best!.clinicalQuality!),
        0,
      );
      expect(
        profile.completedLeaves,
        profile.validLeaves + profile.invalidLeaves,
      );
      expect(profile.qualityCalls, profile.validLeaves);
      expect(profile.firstValidationCalls, 1);
      expect(profile.hardCalls, greaterThan(0));
    },
  );
  test(
    'restart keeps first incumbent and survives pauses, deadlines and cancel',
    () {
      final p = fixtures.input();
      final s = SearchSession(
        p,
        candidateOrdering: true,
        earlyDeadEnds: true,
        experimentalTwoPhase: true,
      );
      var r = s.run(maxNodes: 1);
      while (r.best == null && r.canResume) {
        r = s.run(maxNodes: 1);
      }
      expect(r.best, isNotNull);
      expect(s.qualityPhaseStartNode, isNotNull);
      expect(r.status, SearchStatus.feasibleNotProven);
      final incumbent = r.best;
      final timed = s.run(maxNodes: 100, timeLimit: Duration.zero);
      expect(timed.status, SearchStatus.feasibleNotProven);
      expect(timed.best, same(incumbent));
      while (r.canResume) {
        r = s.run(maxNodes: 1);
      }
      expect(r.status, SearchStatus.optimal);
      expect(r.best!.clinicalQuality!.compareTo(reference.optimum(p)!), 0);
      final cancelled = SearchSession(
        p,
        candidateOrdering: true,
        earlyDeadEnds: true,
        experimentalTwoPhase: true,
      );
      var c = cancelled.run(maxNodes: 1);
      while (c.best == null && c.canResume) {
        c = cancelled.run(maxNodes: 1);
      }
      final retained = c.best;
      cancelled.cancel();
      expect(cancelled.run(maxNodes: 1).status, SearchStatus.cancelled);
      expect(cancelled.best, same(retained));
    },
  );
}
