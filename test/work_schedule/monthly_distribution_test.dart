import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/engine/v13/fairness_optimizer.dart';
import 'package:akys/modules/work_schedule/engine/v13/feasibility_solver.dart';
import 'package:akys/modules/work_schedule/engine/v13/constraint_validator.dart';
import 'package:akys/modules/work_schedule/engine/v13/solver_result.dart';

import 'engine_test.dart' show sample;
import 'fairness_optimizer_test.dart' show r, compare;

void main() {
  test('10k November: chronological CSP baseline is not a necessary hierarchy', () async {
    final m = sample(2026, 11)..boundaryConfirmed = true;
    final baseline = await const FeasibilitySolver(nodeLimit: 10000).solve(
      m,
      lexicographicObjective: (rows) => FairnessReport(m, rows).objective,
    );
    final bad = FairnessReport(m, baseline.positions);
    var j = 0;
    final witnessRows = [
      for (var d = 1; d <= 30; d++)
        r(
          m,
          d,
          'p${(d - 1) % 4 + 1}',
          d % 4 == 0 && d <= 24 ? [] : ['p${5 + j++ % 3}'],
        ),
    ];
    expect(const ConstraintValidator().validate(m, witnessRows), isEmpty);
    final witness = FairnessReport(m, witnessRows);
    expect(baseline.status, SolverStatus.searchLimitReached);
    expect(bad.stages['seniorSolo'], [2, 2, 1, 1]);
    expect(
      baseline.positions
          .where((p) => p.juniorDutyPersonIds.isEmpty)
          .map((p) => p.date),
      [for (var d = 25; d <= 30; d++) '2026-11-$d'],
    );
    expect(compare(witness.objective, bad.objective), lessThan(0));
    final fixed = await const FairnessOptimizer(nodeLimit: 10000).optimize(m);
    expect(
      const ConstraintValidator().validate(m, fixed.solver.positions),
      isEmpty,
    );
    expect(fixed.report!.stages['seniorSolo'], [0, 0, 0, 6]);
    expect(fixed.report!.hierarchyViolations, 0);
    expect(fixed.solver.seniorSubstitutionCount, 0);
    expect(fixed.solver.juniorVacancyCount, 6);
    expect(
      fixed.report!.stages['soloCalendarSpread']!.single,
      lessThan(bad.stages['soloCalendarSpread']!.single),
    );
    expect(
      compare(fixed.report!.objective, witness.objective),
      lessThanOrEqualTo(0),
    );
    expect(fixed.solver.visitedStates, lessThanOrEqualTo(10000));
    expect(fixed.optimalityProven, isFalse);
    expect(fixed.hierarchyExceptionAccepted, isFalse);
    final repeat = await const FairnessOptimizer(nodeLimit: 10000).optimize(m);
    expect(
      jsonEncode(repeat.solver.positions.map((p) => p.toJson()).toList()),
      jsonEncode(fixed.solver.positions.map((p) => p.toJson()).toList()),
    );
    debugPrint(
      'NOVEMBER 10k: baseline solo=${bad.stages['seniorSolo']} hierarchy=${bad.hierarchyViolations}; fixed solo=${fixed.report!.stages['seniorSolo']} dates=${fixed.solver.positions.where((p) => p.juniorDutyPersonIds.isEmpty).map((p) => p.date).toList()} hierarchy=${fixed.report!.hierarchyViolations} status=${fixed.solver.statusCode} states=${fixed.solver.visitedStates} ms=${fixed.solver.elapsedMilliseconds}',
    );
  });
  test('Calendar spread is below coverage, hierarchy, solo priority and duty counts', () {
    final m = sample(2026, 11);
    final report = FairnessReport(m, [
      for (var d = 1; d <= 30; d++) r(m, d, 'p${(d - 1) % 4 + 1}'),
    ]);
    final keys = report.stages.keys.toList();
    for (final high in [
      'seniorSubstitutions',
      'juniorVacancies',
      'monthlyHierarchy',
      'seniorSolo',
      'groupDutyCounts',
    ]) {
      expect(keys.indexOf(high), lessThan(keys.indexOf('soloCalendarSpread')));
    }
  });
  test(
    'Repair preserves personal and previous-month hard constraints',
    () async {
      final m = sample(2026, 11)..boundaryConfirmed = true;
      m.constraints['p5']!.must.addAll([2, 8]);
      m.constraints['p5']!.cannot.addAll([3, 9, 15, 21, 27]);
      m.boundary['p6'] = ['2026-10-31'];
      final before = jsonEncode(m.toJson());
      final result = await const FairnessOptimizer(nodeLimit: 10000)
          .optimize(m);
      expect(result.solver.hasValidIncumbent, isTrue);
      expect(
        const ConstraintValidator().validate(m, result.solver.positions),
        isEmpty,
      );
      expect(jsonEncode(m.toJson()), before);
    },
  );
  test(
    'Cancellation during repair keeps validated incumbent without proof',
    () async {
      final m = sample(2026, 11)..boundaryConfirmed = true;
      final cancel = SolverCancellation();
      final result =
          await const FairnessOptimizer(
            nodeLimit: 10000,
            yieldEvery: 1,
          ).optimize(
            m,
            cancellation: cancel,
            onProgress: (nodes, elapsed, first) {
              if (first != null) cancel.cancel();
            },
          );
      expect(result.solver.cancelled, isTrue);
      expect(result.solver.hasValidIncumbent, isTrue);
      expect(result.optimalityProven, isFalse);
      expect(result.solver.status, SolverStatus.searchLimitReached);
      expect(
        const ConstraintValidator().validate(m, result.solver.positions),
        isEmpty,
      );
    },
  );
  test(
    'Temporal objective improves spread with identical higher-priority values',
    () {
      final m = sample(2026, 11)..boundaryConfirmed = true;
      final reports = <FairnessReport>[];
      for (final solo in [
        {4, 8, 12, 16, 20, 24},
        {4, 8, 12, 16, 24, 28},
      ]) {
        var junior = 0;
        final rows = [
          for (var d = 1; d <= 30; d++)
            r(
              m,
              d,
              'p${(d - 1) % 4 + 1}',
              solo.contains(d) ? [] : ['p${5 + junior++ % 3}'],
            ),
        ];
        expect(const ConstraintValidator().validate(m, rows), isEmpty);
        reports.add(FairnessReport(m, rows));
      }
      for (final key in [
        'seniorSubstitutions',
        'juniorVacancies',
        'monthlyHierarchy',
        'seniorSolo',
        'groupDutyCounts',
      ]) {
        expect(reports[1].stages[key], reports[0].stages[key]);
      }
      expect(
        reports[1].stages['soloCalendarSpread']!.single,
        lessThan(reports[0].stages['soloCalendarSpread']!.single),
      );
      expect(compare(reports[1].objective, reports[0].objective), lessThan(0));
    },
  );
}
