import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/domain/duty_positions.dart';
import 'package:akys/modules/work_schedule/engine/v13/constraint_validator.dart';
import 'package:akys/modules/work_schedule/engine/v13/fairness_optimizer.dart';
import 'package:akys/modules/work_schedule/engine/v13/solver_result.dart';

import 'engine_test.dart' show sample;
import 'difficulty_test.dart' show scoring, weightedMonth;

DutyPositions r(
  ScheduleMonth m,
  int day,
  String s, [
  List<String> j = const [],
]) => DutyPositions(
  date: dateKey(m.date(day)),
  seniorDutyPersonId: s,
  juniorDutyPersonIds: j,
  seniorRoleIsSubstitution:
      m.person(s).dutySeniorityGroup == DutySeniorityGroup.junior,
  seniorRoleOriginalGroup: m.person(s).dutySeniorityGroup.name,
  juniorVacancyReason: j.isEmpty ? 'NOT_PROVEN' : null,
);
int compare(List<num> a, List<num> b) {
  for (var i = 0; i < a.length; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}

ScheduleMonth tiny() {
  final m = sample(2026, 2, count: 6);
  for (var d = 3; d <= 28; d++) {
    m.constraints['p${(d - 1) % 4 + 1}']!.must.add(d);
  }
  for (var i = 5; i <= 6; i++) {
    m.constraints['p$i']!.cannot.addAll(List.generate(27, (i) => i + 2));
  }
  return m;
}

void main() {
  test(
    'Exhaustive independent enumeration equals optimizer lex optimum',
    () async {
      final m = tiny();
      final candidates = <List<DutyPositions>>[];
      for (final swap in [false, true]) {
        for (final j in [
          <String>[],
          ['p5'],
          ['p6'],
          ['p5', 'p6'],
        ]) {
          final rows = [
            r(m, 1, swap ? 'p2' : 'p1', j),
            r(m, 2, swap ? 'p1' : 'p2'),
            for (var d = 3; d <= 28; d++) r(m, d, 'p${(d - 1) % 4 + 1}'),
          ];
          if (const ConstraintValidator().validate(m, rows).isEmpty) {
            candidates.add(rows);
          }
        }
      }
      candidates.sort(
        (a, b) => compare(
          FairnessReport(m, a).objective,
          FairnessReport(m, b).objective,
        ),
      );
      final result = await const FairnessOptimizer(nodeLimit: 5000).optimize(m);
      expect(result.optimalityProven, true);
      expect(
        result.report!.objective,
        FairnessReport(m, candidates.first).objective,
      );
      expect(
        const ConstraintValidator().validate(m, result.solver.positions),
        isEmpty,
      );
      expect(result.solver.positions.first.seniorDutyPersonId, 'p1');
      expect(result.hierarchyExceptionAccepted, false);
    },
  );
  test(
    'K1 solo K2 paired is monthly violation; reversed hierarchy preferred',
    () {
      final m = sample(2026, 11);
      final bad = FairnessReport(m, [
        r(m, 1, 'p1'),
        r(m, 4, 'p2', ['p5']),
      ]);
      final good = FairnessReport(m, [
        r(m, 1, 'p2'),
        r(m, 4, 'p1', ['p5']),
      ]);
      expect(bad.hierarchyViolations, 1);
      expect(good.hierarchyViolations, 0);
      expect(compare(good.objective, bad.objective), lessThan(0));
    },
  );
  test('K4 solo priority with equal hierarchy', () {
    final m = sample(2026, 11);
    final a = FairnessReport(m, [r(m, 1, 'p4')]);
    final b = FairnessReport(m, [r(m, 1, 'p3')]);
    expect(compare(a.objective, b.objective), lessThan(0));
  });
  test('Substituted junior pairing is lower rank than all actual seniors', () {
    final m = sample(2026, 11);
    final report = FairnessReport(m, [
      r(m, 1, 'p4'),
      r(m, 4, 'p5', ['p6']),
    ]);
    expect(report.hierarchyViolations, 1);
    expect(report.substitutions, 1);
  });
  test('Within-group load advantage uses rank for senior and junior', () {
    final m = sample(2026, 11);
    final a = FairnessReport(m, [
      r(m, 1, 'p2', ['p6']),
    ]);
    final b = FairnessReport(m, [
      r(m, 1, 'p1', ['p5']),
    ]);
    expect(
      compare(a.stages['groupDutyCounts']!, b.stages['groupDutyCounts']!),
      lessThan(0),
    );
  });
  test(
    'Friday Saturday Sunday remain distinct and Saturday spread matters',
    () {
      final m = sample(2026, 11);
      final concentrated = FairnessReport(m, [r(m, 7, 'p1'), r(m, 14, 'p1')]);
      final balanced = FairnessReport(m, [r(m, 7, 'p1'), r(m, 14, 'p2')]);
      expect(
        compare(balanced.stages['saturday']!, concentrated.stages['saturday']!),
        lessThan(0),
      );
      final report = FairnessReport(m, [
        r(m, 6, 'p1'),
        r(m, 7, 'p2'),
        r(m, 8, 'p3'),
      ]);
      expect(report.people['p1']!.categories[2], 1);
      expect(report.people['p2']!.categories[3], 1);
      expect(report.people['p3']!.categories[4], 1);
    },
  );
  test('Easy Thursday favors senior, holiday Thursday is not easy', () {
    final m = sample(2026, 10);
    final a = FairnessReport(m, [r(m, 1, 'p1')]);
    final b = FairnessReport(m, [r(m, 1, 'p2')]);
    expect(compare(a.stages['thursday']!, b.stages['thursday']!), lessThan(0));
    final weighted = weightedMonth(m, scoring(2026, 10));
    final h = FairnessReport(weighted, [r(weighted, 29, 'p1')]);
    expect(h.people['p1']!.easyThursday, 0);
    expect(h.people['p1']!.categories[1], 1);
    expect(h.people['p1']!.holidays, 1);
  });
  test('Average and totals separate and boundary points excluded', () {
    final m = sample(2026, 11);
    m.boundary['p1'] = ['2026-10-31'];
    final report = FairnessReport(m, [
      r(m, 5, 'p1'),
      r(m, 12, 'p1'),
      r(m, 19, 'p2'),
    ]);
    expect(report.people['p1']!.points, 2);
    expect(report.people['p1']!.average, 1);
    expect(report.people['p2']!.average, 1);
    expect(
      report.stages.keys.toList().indexOf('averageDifficulty'),
      lessThan(report.stages.keys.toList().indexOf('totalDifficulty')),
    );
  });
  for (final count in [7, 11]) {
    test('Budget retains valid deterministic provisional incumbent $count', () async {
      final m = sample(2026, 11, count: count);
      final a = await const FairnessOptimizer(nodeLimit: 150).optimize(m);
      final b = await const FairnessOptimizer(nodeLimit: 150).optimize(m);
      debugPrint(
        'FAIRNESS ${kIsWeb ? 'web' : 'vm'} people=$count states=${a.solver.visitedStates} ms=${a.solver.elapsedMilliseconds} status=${a.solver.statusCode}',
      );
      expect(a.solver.hasValidIncumbent, true);
      expect(a.optimalityProven, false);
      expect(a.hierarchyExceptionAccepted, false);
      expect(a.solver.status, SolverStatus.searchLimitReached);
      expect(a.report!.substitutions, 0);
      expect(
        const ConstraintValidator().validate(m, a.solver.positions),
        isEmpty,
      );
      expect(
        jsonEncode(a.solver.positions.map((r) => r.toJson()).toList()),
        jsonEncode(b.solver.positions.map((r) => r.toJson()).toList()),
      );
    });
  }
  test('Cancellation is not an optimum proof', () async {
    final token = SolverCancellation()..cancel();
    final r = await const FairnessOptimizer().optimize(
      tiny(),
      cancellation: token,
    );
    expect(r.solver.cancelled, true);
    expect(r.optimalityProven, false);
  });

  test(
    'Hierarchy exception accepted only after exhaustive necessity proof',
    () async {
      final m = tiny();
      for (var i = 5; i <= 6; i++) {
        m.constraints['p$i']!.cannot
          ..clear()
          ..addAll([
            for (var d = 1; d <= 28; d++)
              if (d != 4) d,
          ]);
      }
      final result = await const FairnessOptimizer(nodeLimit: 5000).optimize(m);
      expect(result.optimalityProven, true);
      expect(result.report!.hierarchyViolations, greaterThan(0));
      expect(result.hierarchyExceptionAccepted, true);
      expect(result.report!.vacancies, 27);
      expect(
        const ConstraintValidator().validate(m, result.solver.positions),
        isEmpty,
      );
    },
  );
  test('Substitution and coverage precede all fairness components', () {
    final m = sample(2026, 11);
    final real = FairnessReport(m, [r(m, 1, 'p1')]);
    final promoted = FairnessReport(m, [
      r(m, 1, 'p5', ['p6']),
    ]);
    expect(compare(real.objective, promoted.objective), lessThan(0));
    final covered = FairnessReport(m, [
      r(m, 1, 'p2', ['p5']),
      r(m, 4, 'p1'),
    ]);
    final empty = FairnessReport(m, [r(m, 1, 'p2'), r(m, 4, 'p1')]);
    expect(covered.hierarchyViolations, greaterThan(0));
    expect(compare(covered.objective, empty.objective), lessThan(0));
  });
  test(
    'Top senior hierarchy violations outrank aggregate lower-rank violations',
    () {
      final m = sample(2026, 11);
      final top = FairnessReport(m, [
        r(m, 1, 'p1'),
        r(m, 4, 'p2', ['p5']),
      ]);
      final lower = FairnessReport(m, [
        r(m, 1, 'p3'),
        r(m, 4, 'p4', ['p5']),
        r(m, 7, 'p4', ['p6']),
      ]);
      expect(
        compare(
          lower.stages['monthlyHierarchy']!,
          top.stages['monthlyHierarchy']!,
        ),
        lessThan(0),
      );
    },
  );
}
