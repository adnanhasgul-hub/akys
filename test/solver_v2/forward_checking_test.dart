import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import 'optional_search_test.dart' as exhaustive;
import 'clinical_reliability_test.dart' as generated;
import 'clinical_resilience_test.dart' as checks;
import 'support/reference_clinical_quality.dart';
import '../../tool/solver_v2/clinical_resilience.dart';

Doctor senior(
  String id, {
  int cap = 8,
  Set<int> blocked = const {},
  Set<int> must = const {},
  List<DateTime> previous = const [],
}) => Doctor(
  id: id,
  seniorityLevel: SeniorityLevel.k1,
  maxDuties: cap,
  unavailable: blocked,
  must: must,
  previousDuties: previous,
);
Problem problem(
  List<Doctor> doctors,
  List<int> slots, {
  List<SlotRequirement>? requirements,
  List<DutyRole>? roles,
}) => Problem(
  startDate: DateTime.utc(2026, 11),
  doctors: doctors,
  slotsPerDay: slots,
  slotRoles:
      roles ?? List.filled(slots.fold(0, (a, b) => a + b), DutyRole.senior),
  slotRequirements:
      requirements ??
      List.filled(slots.fold(0, (a, b) => a + b), SlotRequirement.required),
  dayDifficulties: List.filled(
    slots.length,
    const DayDifficulty(weekdayScore: 3),
  ),
);
TransitionSession session(Problem p, bool on, {String method = 'bounded'}) =>
    TransitionSession(
      p,
      forwardChecking: on,
      earlyDeadEnds: true,
      candidateOrdering: method != 'deadends',
      experimentalTwoPhase: method == 'bounded' || method == 'twophase',
      clinicalBounds: method == 'bounded',
    );

void oracleCheck(Problem p) {
  final a = exhaustive.oracle(p, substitutions: false);
  final rows = a.isNotEmpty ? a : exhaustive.oracle(p, substitutions: true);
  final qs = rows
      .map((r) => const ReferenceClinicalQualityCalculator().calculate(p, r.$1))
      .toList();
  qs.sort((a, b) {
    for (var k = 0; k < 19; k++) {
      final c = a[k].compareTo(b[k]);
      if (c != 0) return c;
    }
    return 0;
  });
  for (final on in [false, true]) {
    for (final method in checks.strategies) {
      final s = session(p, on, method: method), r = checks.finish(s);
      expect(
        r.status,
        qs.isEmpty ? SearchStatus.infeasible : SearchStatus.optimal,
      );
      expect(
        s.restrictedVerdict,
        a.isEmpty
            ? RestrictedVerdict.provenInfeasible
            : RestrictedVerdict.feasible,
      );
      if (qs.isNotEmpty) {
        expect(
          r.best!.clinicalQuality!.components.map((x) => x.toString()).toList(),
          qs.first.map((x) => x.toString()).toList(),
        );
      }
      if (!on) expect(s.forwardChecks, 0);
    }
  }
}

void main() {
  for (final day in [0, 1, 3]) {
    test('empty required domain at day $day prunes root, both phases', () {
      final p = problem(
        [
          senior('s', blocked: {day}),
          Doctor(id: 'j', group: DutyGroup.junior, unavailable: {day}),
        ],
        [1, 1, 0, 1],
      );
      oracleCheck(p);
      final s = session(p, true), r = checks.finish(s);
      expect(r.status, SearchStatus.infeasible);
      expect(s.forwardRootPruned, 2);
      expect(r.visitedNodes, 0);
    });
  }
  test('A has no senior; B junior allowed only after root proof', () {
    final p = problem([Doctor(id: 'j', group: DutyGroup.junior)], [1]);
    oracleCheck(p);
    final s = session(p, true);
    final a = s.run(maxNodes: 1);
    expect(a.pauseReason, PauseReason.stageTransition);
    expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
    expect(s.forwardRootPruned, 1);
    final b = checks.finish(s);
    expect(b.status, SearchStatus.optimal);
    expect(b.best!.clinicalQuality!.components.first.toString(), '1');
    expect(
      const SolutionValidator()
          .validate(s.problem, b.best!, localEvidence: s)
          .permanentApprovalAllowed,
      false,
    );
  });
  test('capacity exhausted by prefix eliminates future required domain', () {
    final p = problem([senior('s', cap: 1)], [1, 0, 0, 1]);
    oracleCheck(p);
    final s = session(p, true);
    checks.finish(s);
    expect(s.forwardRootPruned, 0);
    expect(s.forwardPruned, greaterThan(0));
  });
  test('prefix rest eliminates domain while individual root domains exist', () {
    final p = problem([senior('s')], [1, 1]);
    oracleCheck(p);
    final s = session(p, true);
    checks.finish(s);
    expect(s.forwardRootPruned, 0);
    expect(s.forwardPruned, greaterThan(0));
  });
  test('previous-month rest empties first domain', () {
    final p = problem(
      [
        senior('s', previous: [DateTime.utc(2026, 10, 31)]),
      ],
      [1],
    );
    oracleCheck(p);
    final s = session(p, true);
    checks.finish(s);
    expect(s.forwardRootPruned, 2);
  });
  test('empty optional is legal, must can be satisfied there', () {
    oracleCheck(
      problem(
        [
          senior('s', must: {0}),
        ],
        [1, 0, 0, 1],
        requirements: [SlotRequirement.optional, SlotRequirement.optional],
      ),
    );
    oracleCheck(problem([], [1], requirements: [SlotRequirement.optional]));
  });
  test('same-day required slots: individual domains do not prove joint feasibility', () {
    final p = problem([senior('s')], [2]);
    oracleCheck(p);
    final s = session(p, true);
    checks.finish(s);
    expect(s.forwardRootPruned, 0);
    expect(s.forwardPruned, greaterThan(0));
    oracleCheck(problem([senior('a'), senior('b')], [2]));
  });
  test(
    'unassigned must is fixed date, never guessed person-slot placement',
    () {
      oracleCheck(
        problem(
          [
            senior('a', must: {1}),
            senior('b'),
          ],
          [1, 1],
        ),
      );
      oracleCheck(
        problem(
          [
            senior('a', must: {0, 3}),
          ],
          [1, 0, 0, 1],
        ),
      );
    },
  );
  test('large blocked-final-day case proven with zero DFS decisions', () {
    final s = session(resilienceProblem('15-blocked'), true),
        r = checks.finish(s);
    expect(r.status, SearchStatus.infeasible);
    expect(r.visitedNodes, 0);
    expect(s.forwardRootPruned, 2);
  });
  test('200 independent models: on/off, four strategies, exact 19-vector', () {
    final random = Random(170700);
    for (var i = 0; i < 200; i++) {
      oracleCheck(generated.generated(random, i));
    }
  });
  test('zero budgets, cancellation and resume never manufacture proof', () {
    final p = problem(
      [senior('s'), Doctor(id: 'j', group: DutyGroup.junior)],
      [2, 0, 0, 2],
      roles: [
        DutyRole.senior,
        DutyRole.junior,
        DutyRole.senior,
        DutyRole.junior,
      ],
      requirements: [
        SlotRequirement.required,
        SlotRequirement.optional,
        SlotRequirement.required,
        SlotRequirement.optional,
      ],
    );
    final s = session(p, true);
    expect(
      s.run(maxNodes: 100, timeLimit: Duration.zero).status,
      SearchStatus.timeoutWithoutSolution,
    );
    expect(s.run(maxNodes: 0).status, SearchStatus.paused);
    expect(s.forwardChecks, 0);
    expect(s.restrictedVerdict, RestrictedVerdict.pending);
    var r = s.run(maxNodes: 1);
    while (r.best == null && r.canResume) {
      r = s.run(maxNodes: 1);
    }
    final best = r.best;
    expect(s.run(maxNodes: 100, timeLimit: Duration.zero).best, same(best));
    expect(s.restrictedVerdict, RestrictedVerdict.feasible);
    final resumed = checks.finish(s), fresh = checks.finish(session(p, true));
    expect(resumed.best!.assignments, fresh.best!.assignments);
    expect(resumed.visitedNodes, fresh.visitedNodes);
    final c = session(p, true)..cancel();
    expect(c.run(maxNodes: 100).status, SearchStatus.cancelled);
    expect(c.forwardChecks, 0);
  });
  test('default remains disabled', () {
    final s = TransitionSession(problem([senior('s')], [1]));
    checks.finish(s);
    expect(s.forwardChecking, false);
    expect(s.forwardChecks, 0);
  });
}
