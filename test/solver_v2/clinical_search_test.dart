import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';
import 'package:akys/solver_v2/clinical_quality.dart';

Solution raw(Problem p, List<int> xs, {bool phaseB = false}) {
  final counts = List<int>.filled(p.doctors.length, 0);
  var sub = 0;
  for (var i = 0; i < xs.length; i++) {
    final x = xs[i];
    if (x < 0) continue;
    counts[x]++;
    if (p.slotRoles![i] == DutyRole.senior &&
        p.doctors[x].group == DutyGroup.junior) {
      sub++;
    }
  }
  final order = [...counts]..sort();
  return Solution(xs, [
    if (phaseB) sub,
    if (order.isEmpty) 0 else order.last - order.first,
    counts.fold<int>(0, (a, b) => a + b * b),
  ]);
}

Problem input({bool noSenior = false}) => Problem(
  startDate: DateTime.utc(2026, 11, 1),
  doctors: [
    if (!noSenior) Doctor(id: 's', seniorityLevel: SeniorityLevel.k4),
    Doctor(id: 'j1', group: DutyGroup.junior, maxDuties: 1),
    Doctor(id: 'j2', group: DutyGroup.junior, maxDuties: 2),
  ],
  slotsPerDay: [2],
  slotRoles: [DutyRole.senior, DutyRole.junior],
  slotRequirements: [SlotRequirement.required, SlotRequirement.optional],
  dayDifficulties: [const DayDifficulty(weekdayScore: 5)],
);

/// Independent Cartesian enumeration, checking candidate hard constraints via
/// the independent validator. No solver frontier/pruning/incumbent code.
ClinicalQuality? oracle(Problem p, {TransitionSession? phaseB}) {
  final evaluator = ClinicalQualityEvaluator(), validator = SolutionValidator();
  ClinicalQuality? best;
  void enumerate(List<int> xs) {
    if (xs.length < p.slotDays.length) {
      final slot = xs.length;
      for (var i = 0; i < p.doctors.length; i++) {
        enumerate([...xs, i]);
      }
      if (p.slotRequirements[slot] == SlotRequirement.optional) {
        enumerate([...xs, unfilledSlot]);
      }
      return;
    }
    final candidate = raw(p, xs, phaseB: phaseB != null);
    final valid = phaseB == null
        ? validator.validate(p, candidate)
        : validator.validatePhaseBCandidate(p, candidate, session: phaseB);
    if (!valid.isValid) return;
    final q = phaseB == null
        ? evaluator.evaluate(p, candidate)
        : evaluator.evaluatePhaseBCandidate(p, candidate, session: phaseB);
    if (best == null || q.compareTo(best!) < 0) best = q;
  }

  enumerate([]);
  return best;
}

void main() {
  test('clinical optional coverage beats first incumbent, oracle and resume', () {
    final p = input(), session = TransitionSession(p);
    final watch = Stopwatch()..start();
    var r = session.run(maxNodes: 1);
    while (r.best == null) {
      r = session.run(maxNodes: 1);
    }
    final initial = r.best!.clinicalQuality!,
        firstMs = watch.elapsedMilliseconds;
    expect(session.restrictedVerdict, RestrictedVerdict.feasible);
    expect(session.phase, TransitionPhase.restricted);
    final timed = session.run(maxNodes: 100, timeLimit: Duration.zero);
    expect(timed.status, SearchStatus.feasibleNotProven);
    expect(timed.best, same(r.best));
    while (r.canResume) {
      r = session.run(maxNodes: 1);
    }
    watch.stop();
    expect(r.status, SearchStatus.optimal);
    expect(session.phase, TransitionPhase.done);
    final finalQ = r.best!.clinicalQuality!;
    final restored = Solution.fromMessage(r.best!.toMessage());
    expect(restored.clinicalQuality!.compareTo(finalQ), 0);
    expect(finalQ.compareTo(initial), lessThan(0));
    expect(r.best!.assignments, [0, 2]);
    expect(finalQ.compareTo(oracle(session.problem)!), 0);
    expect(
      const SolutionValidator().validate(session.problem, r.best!).isValid,
      isTrue,
    );
    final repeat = TransitionSession(p);
    var rr = repeat.run(maxNodes: 1000);
    while (rr.canResume) {
      rr = repeat.run(maxNodes: 1000);
    }
    expect(rr.best!.assignments, r.best!.assignments);
    expect(rr.best!.clinicalQuality!.compareTo(finalQ), 0);
    final rawRun = TransitionSession(p, enablePruning: false);
    var unpruned = rawRun.run(maxNodes: 1000);
    while (unpruned.canResume) {
      unpruned = rawRun.run(maxNodes: 1000);
    }
    expect(unpruned.best!.clinicalQuality!.compareTo(finalQ), 0);
    debugPrint(
      'CLINICAL_BENCH small nodes=${r.visitedNodes} firstMs=$firstMs totalMs=${watch.elapsedMilliseconds} first=${initial.components} final=${finalQ.components} status=${r.status.name}',
    );
  });
  test('B opens after proof, minimizes substitution and checks reported clinical quality', () {
    final s = TransitionSession(input(noSenior: true));
    var r = s.run(maxNodes: 100);
    expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
    expect(s.phase, TransitionPhase.substitution);
    final expected = oracle(s.problem, phaseB: s)!;
    while (r.canResume) {
      r = s.run(maxNodes: 100);
    }
    expect(r.status, SearchStatus.optimal);
    expect(r.best!.clinicalQuality!.compareTo(expected), 0);
    expect(r.best!.clinicalQuality!.components.first.toString(), '1');
    final withoutPruning = TransitionSession(
      input(noSenior: true),
      enablePruning: false,
    );
    var u = withoutPruning.run(maxNodes: 100);
    final independent = oracle(withoutPruning.problem, phaseB: withoutPruning)!;
    while (u.canResume) {
      u = withoutPruning.run(maxNodes: 100);
    }
    expect(u.status, SearchStatus.optimal);
    expect(u.best!.clinicalQuality!.compareTo(independent), 0);
    expect(u.best!.clinicalQuality!.compareTo(r.best!.clinicalQuality!), 0);
    final valid = const SolutionValidator().validate(
      s.problem,
      r.best!,
      localEvidence: s,
    );
    expect(valid.isValid, isTrue);
    expect(valid.permanentApprovalAllowed, isFalse);
    final fake = Solution(
      r.best!.assignments,
      r.best!.quality,
      clinicalQuality: ClinicalQuality([
        for (var i = 0; i < 19; i++) Exact.integer(99),
      ]),
    );
    expect(
      const SolutionValidator()
          .validate(s.problem, fake, localEvidence: s)
          .isValid,
      isFalse,
    );
  });
  test('B can improve a provisional transition incumbent', () {
    final p = Problem(
      startDate: DateTime.utc(2026, 11, 1),
      doctors: [
        Doctor(id: 'j1', group: DutyGroup.junior, maxDuties: 1),
        Doctor(id: 'j2', group: DutyGroup.junior, maxDuties: 2),
      ],
      slotsPerDay: [1],
      slotRoles: [DutyRole.senior],
      slotRequirements: [SlotRequirement.required],
      dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
    );
    final s = TransitionSession(p);
    var r = s.run(maxNodes: 100);
    expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
    while (r.best == null) {
      r = s.run(maxNodes: 1);
    }
    expect(r.status, SearchStatus.feasibleNotProven);
    final first = r.best!.clinicalQuality!;
    expect(r.best!.assignments, [0]);
    while (r.canResume) {
      r = s.run(maxNodes: 1);
    }
    expect(r.status, SearchStatus.optimal);
    expect(r.best!.assignments, [1]);
    expect(r.best!.clinicalQuality!.compareTo(first), lessThan(0));
    expect(
      const SolutionValidator()
          .validate(s.problem, r.best!, localEvidence: s)
          .permanentApprovalAllowed,
      isFalse,
    );
  });
  test(
    'clinical B proves minimum two substitutions when two are unavoidable',
    () {
      final p = Problem(
        startDate: DateTime.utc(2026, 11, 1),
        doctors: [Doctor(id: 'j', group: DutyGroup.junior, maxDuties: 2)],
        slotsPerDay: [1, 0, 0, 1],
        slotRoles: [DutyRole.senior, DutyRole.senior],
        slotRequirements: [SlotRequirement.required, SlotRequirement.required],
        dayDifficulties: [
          for (var i = 0; i < 4; i++) const DayDifficulty(weekdayScore: 3),
        ],
      );
      final s = TransitionSession(p);
      var r = s.run(maxNodes: 100);
      expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
      final expected = oracle(s.problem, phaseB: s)!;
      while (r.canResume) {
        r = s.run(maxNodes: 2);
      }
      expect(r.status, SearchStatus.optimal);
      expect(r.best!.clinicalQuality!.components.first.toString(), '2');
      expect(r.best!.clinicalQuality!.compareTo(expected), 0);
      expect(
        const SolutionValidator()
            .validate(s.problem, r.best!, localEvidence: s)
            .permanentApprovalAllowed,
        isFalse,
      );
    },
  );
  test(
    'small generated clinical problems match independent exhaustive oracle',
    () {
      for (var mask = 0; mask < 32; mask++) {
        final p = Problem(
          startDate: DateTime.utc(2026, 11, 1 + mask % 7),
          doctors: [
            Doctor(id: 's1', seniorityLevel: SeniorityLevel.k1, maxDuties: 2),
            Doctor(
              id: 's4',
              seniorityLevel: SeniorityLevel.k4,
              maxDuties: 1,
              unavailable: {if (mask & 1 != 0) 0},
            ),
            Doctor(
              id: 'j',
              group: DutyGroup.junior,
              maxDuties: 2,
              must: {if (mask & 2 != 0) 3},
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
            SlotRequirement.required,
            SlotRequirement.optional,
            SlotRequirement.required,
            if (mask & 4 != 0)
              SlotRequirement.required
            else
              SlotRequirement.optional,
          ],
          dayDifficulties: [
            for (var i = 0; i < 4; i++)
              DayDifficulty(
                weekdayScore: 1 + ((i + mask) % 10),
                holidayName: i == 0 && mask & 8 != 0 ? 'Tatil' : null,
                holidayScore: i == 0 && mask & 8 != 0 ? 9 : null,
              ),
          ],
        );
        final expected = oracle(p);
        for (final prune in [false, true]) {
          final session = SearchSession(p, enablePruning: prune);
          var r = session.run(maxNodes: 2);
          while (r.canResume) {
            r = session.run(maxNodes: 2);
          }
          if (expected == null) {
            expect(r.status, SearchStatus.infeasible, reason: '$mask');
          } else {
            expect(r.status, SearchStatus.optimal);
            expect(
              r.best!.clinicalQuality!.compareTo(expected),
              0,
              reason: '$mask',
            );
            expect(
              const SolutionValidator().validate(p, r.best!).isValid,
              isTrue,
            );
          }
        }
      }
    },
  );
  test('medium clinical synthetic bounded performance never claims unproven optimality', () {
    final p = Problem(
      startDate: DateTime.utc(2026, 11, 1),
      doctors: [
        for (var i = 0; i < 4; i++)
          Doctor(id: 's$i', seniorityLevel: SeniorityLevel.values[i]),
        for (var i = 0; i < 3; i++) Doctor(id: 'j$i', group: DutyGroup.junior),
      ],
      slotsPerDay: [2, 2, 2, 2, 2],
      slotRoles: [
        for (var d = 0; d < 5; d++) ...[DutyRole.senior, DutyRole.junior],
      ],
      slotRequirements: [
        for (var d = 0; d < 5; d++) ...[
          SlotRequirement.required,
          SlotRequirement.optional,
        ],
      ],
      dayDifficulties: [
        for (var d = 0; d < 5; d++) DayDifficulty(weekdayScore: d + 1),
      ],
    );
    final session = SearchSession(p);
    final watch = Stopwatch()..start();
    var result = session.run(maxNodes: 1);
    while (result.best == null && result.canResume) {
      result = session.run(maxNodes: 10);
    }
    final firstMs = watch.elapsedMilliseconds,
        first = result.best?.clinicalQuality;
    if (result.canResume) result = session.run(maxNodes: 2000);
    watch.stop();
    expect(result.best, isNotNull);
    expect(
      result.status,
      anyOf(SearchStatus.optimal, SearchStatus.feasibleNotProven),
    );
    if (result.canResume) expect(result.status, SearchStatus.feasibleNotProven);
    debugPrint(
      'CLINICAL_BENCH medium doctors=7 days=5 required=5 optional=5 budget=2000 nodes=${result.visitedNodes} firstMs=$firstMs totalMs=${watch.elapsedMilliseconds} improvements=${session.incumbentImprovements} first=${first?.components} final=${result.best!.clinicalQuality!.components} status=${result.status.name}',
    );
  });
  test(
    'second junior coverage is prioritized and equal ties deterministic',
    () {
      final p = Problem(
        startDate: DateTime.utc(2026, 11, 1),
        doctors: [
          Doctor(id: 's', seniorityLevel: SeniorityLevel.k4),
          Doctor(id: 'j1', group: DutyGroup.junior),
          Doctor(id: 'j2', group: DutyGroup.junior),
        ],
        slotsPerDay: [3],
        slotRoles: [DutyRole.senior, DutyRole.junior, DutyRole.junior],
        slotRequirements: [
          SlotRequirement.required,
          SlotRequirement.optional,
          SlotRequirement.optional,
        ],
        dayDifficulties: [const DayDifficulty(weekdayScore: 5)],
      );
      final s = SearchSession(p);
      final r = s.run(maxNodes: 1000);
      expect(r.status, SearchStatus.optimal);
      expect(r.best!.clinicalQuality!.components[1].toString(), '-1');
      expect(r.best!.clinicalQuality!.components[2].toString(), '-1');
      expect(r.best!.clinicalQuality!.compareTo(oracle(p)!), 0);
      expect(
        SearchSession(p).run(maxNodes: 1000).best!.assignments,
        r.best!.assignments,
      );
    },
  );
}
