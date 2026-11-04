import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/engine/v13/fairness_optimizer.dart';
import 'package:akys/modules/work_schedule/engine/v13/constraint_validator.dart';
import 'package:akys/modules/work_schedule/engine/v13/solver_result.dart';

import 'engine_test.dart' show sample;
import 'difficulty_test.dart' show scoring, weightedMonth;

void main() {
  for (final name in [
    '7-28',
    '7-30',
    '7-31',
    '11-30',
    'five-cannot',
    'overlap',
    'boundary',
    'holiday',
    'must-conflict',
    'senior-shortage',
    'junior-shortage',
    'promotion',
    'hard-month',
  ]) {
    test('Acceptance $name', () async {
      var m = sample(
        2026,
        name == '7-28'
            ? 2
            : name == '7-31'
            ? 12
            : 11,
        count: name == '11-30' ? 11 : 7,
      );
      if (name == 'five-cannot' || name == 'hard-month') {
        m.constraints['p1']!.cannot.addAll([1, 5, 9, 13, 17]);
      }
      if (name == 'overlap' || name == 'hard-month') {
        for (var i = 1; i <= 3; i++) {
          m.constraints['p$i']!.cannot.addAll([1, 8, 15, 22]);
        }
      }
      if (name == 'boundary' || name == 'hard-month') {
        m.boundary['p1'] = ['2026-10-31'];
      }
      if (name == 'holiday') {
        m = weightedMonth(sample(2026, 10), scoring(2026, 10));
      }
      if (name == 'must-conflict') {
        m.constraints['p1']!.must.add(1);
        m.constraints['p1']!.cannot.add(1);
      }
      if (name == 'senior-shortage') {
        for (var i = 1; i <= 4; i++) {
          m.constraints['p$i']!.cannot.addAll([1, 2, 3, 4]);
        }
      }
      if (name == 'promotion') {
        for (var i = 1; i <= 6; i++) {
          m.constraints['p$i']!.cannot.add(1);
        }
      }
      if (name == 'junior-shortage') {
        m.constraints['p5']!.cannot.addAll(List.generate(30, (i) => i + 1));
      }
      var maxGap = 0;
      final gap = Stopwatch()..start();
      final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        if (gap.elapsedMilliseconds > maxGap) maxGap = gap.elapsedMilliseconds;
        gap.reset();
      });
      final r = await const FairnessOptimizer(
        nodeLimit: 500,
        yieldEvery: 8,
      ).optimize(m);
      timer.cancel();
      expect(r.solver.status, isNot(SolverStatus.error));
      if (r.solver.hasValidIncumbent) {
        expect(
          const ConstraintValidator().validate(m, r.solver.positions),
          isEmpty,
        );
      } else {
        expect([
          SolverStatus.infeasible,
          SolverStatus.searchLimitReached,
        ], contains(r.solver.status));
      }
      if (name == 'must-conflict') expect(r.solver.infeasibilityProven, true);
      debugPrint(
        'ACCEPT ${kIsWeb ? 'web' : 'vm'} $name states=${r.solver.visitedStates} ms=${r.solver.elapsedMilliseconds} first=${r.solver.firstFeasibleMilliseconds} proof=${r.solver.proofMilliseconds} maxGap=$maxGap valid=${r.solver.hasValidIncumbent} status=${r.solver.statusCode} hierarchy=${r.report?.hierarchyViolations} hierarchyProven=${r.stages['monthlyHierarchy']?.optimalityProven} vacant=${r.report?.vacancies} substitutions=${r.report?.substitutions} optimal=${r.optimalityProven}',
      );
    });
  }
  for (final budget in [2000, 10000]) {
    test('Budget profile $budget and cancellation', () async {
      final token = SolverCancellation();
      int? requestMs;
      final watch = Stopwatch()..start();
      final r = await FairnessOptimizer(nodeLimit: budget, yieldEvery: 8)
          .optimize(
            sample(2026, 11, count: 11),
            cancellation: token,
            onProgress: (n, ms, first) {
              if (n >= budget ~/ 2 && requestMs == null) {
                requestMs = watch.elapsedMilliseconds;
                token.cancel();
              }
            },
          );
      expect(r.solver.cancelled, true);
      expect(r.optimalityProven, false);
      expect(r.solver.hasValidIncumbent, true);
      expect(
        const ConstraintValidator().validate(
          sample(2026, 11, count: 11),
          r.solver.positions,
        ),
        isEmpty,
      );
      debugPrint(
        'BUDGET ${kIsWeb ? 'web' : 'vm'} budget=$budget nodes=${r.solver.visitedStates} ms=${r.solver.elapsedMilliseconds} first=${r.solver.firstFeasibleMilliseconds} cancelLatency=${watch.elapsedMilliseconds - requestMs!}',
      );
    });
  }
}
