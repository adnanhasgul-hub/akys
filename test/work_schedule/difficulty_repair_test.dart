import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/engine/v13/fairness_optimizer.dart';
import 'package:akys/modules/work_schedule/engine/v13/difficulty_repair.dart';
import 'package:akys/modules/work_schedule/engine/v13/constraint_validator.dart';
import 'package:akys/modules/work_schedule/engine/v13/solver_result.dart';

import 'engine_test.dart' show sample;
import 'fairness_optimizer_test.dart' show compare;

void main() {
  test('November 41-point incumbent: bounded search preserves higher objectives', () async {
    final m = sample(2026, 11)..boundaryConfirmed = true;
    final baseline = await const FairnessOptimizer(
      nodeLimit: 10000,
      localCandidateLimit: 0,
    ).optimize(m);
    final before = baseline.report!;
    expect(before.people.values.map((p) => p.points), [
      33,
      33,
      32,
      30,
      33,
      41,
      30,
    ]);
    var accepted = 0;
    final repaired = await improveDifficultyLocally(
      m,
      baseline.solver.positions,
      candidateLimit: 2000,
      onAccepted: (before, after) {
        expect(compare(after, before), lessThan(0));
        accepted++;
      },
    );
    expect(accepted, greaterThan(0));
    final after = FairnessReport(m, repaired.positions);
    expect(after.stages['maximumDifficulty']!.single, lessThan(41));
    expect(
      const ConstraintValidator().validate(m, repaired.positions),
      isEmpty,
    );
    expect(compare(after.objective, before.objective), lessThanOrEqualTo(0));
    final keys = before.stages.keys.toList();
    final prior = keys.take(keys.indexOf('maximumDifficulty')).toList();
    final beforeHigh = [for (final key in prior) ...before.stages[key]!];
    final afterHigh = [for (final key in prior) ...after.stages[key]!];
    expect(compare(afterHigh, beforeHigh), lessThanOrEqualTo(0));
    expect(repaired.candidates, lessThanOrEqualTo(2000));
    final again = await improveDifficultyLocally(
      m,
      baseline.solver.positions,
      candidateLimit: 2000,
    );
    expect(
      jsonEncode(repaired.positions.map((p) => p.toJson()).toList()),
      jsonEncode(again.positions.map((p) => p.toJson()).toList()),
    );
    debugPrint(
      'BEFORE ${before.stages} AFTER ${after.stages} candidates=${repaired.candidates}',
    );
  });
  test('search-limited optimizer runs the post-search pass', () async {
    final m = sample(2026, 11)..boundaryConfirmed = true;
    final result = await const FairnessOptimizer(
      nodeLimit: 10000,
      localTimeLimit: Duration(seconds: 10),
    ).optimize(m);
    expect(result.solver.status, SolverStatus.searchLimitReached);
    expect(result.localRepair, isNotNull);
    expect(result.localRepair!.candidates, greaterThan(0));
    expect(result.report!.stages['maximumDifficulty']!.single, lessThan(41));
    expect(result.solver.optimalityProven, isFalse);
    expect(
      const ConstraintValidator().validate(m, result.solver.positions),
      isEmpty,
    );
  });
  test('emergency timeout marks the result partial', () async {
    final m = sample(2026, 11)..boundaryConfirmed = true;
    final baseline = await const FairnessOptimizer(
      nodeLimit: 10000,
      localCandidateLimit: 0,
    ).optimize(m);
    final partial = await improveDifficultyLocally(
      m,
      baseline.solver.positions,
      timeLimit: Duration.zero,
    );
    expect(partial.timedOut, isTrue);
    expect(partial.limitReached, isTrue);
    expect(identical(partial.positions, baseline.solver.positions), isTrue);
    final optimizerPartial = await const FairnessOptimizer(
      nodeLimit: 10000,
      localTimeLimit: Duration.zero,
    ).optimize(m);
    expect(optimizerPartial.localRepair!.timedOut, isTrue);
    expect(optimizerPartial.solver.status, SolverStatus.searchLimitReached);
    expect(optimizerPartial.solver.message, contains('kısmi'));
    expect(optimizerPartial.solver.optimalityProven, isFalse);
  });
  test('cancel and candidate budget preserve the incumbent', () async {
    final m = sample(2026, 11)..boundaryConfirmed = true;
    final baseline = await const FairnessOptimizer(
      nodeLimit: 10000,
      localCandidateLimit: 0,
    ).optimize(m);
    final cancel = SolverCancellation()..cancel();
    final stopped = await improveDifficultyLocally(
      m,
      baseline.solver.positions,
      cancellation: cancel,
    );
    expect(stopped.candidates, 0);
    expect(identical(stopped.positions, baseline.solver.positions), isTrue);
    final bounded = await improveDifficultyLocally(
      m,
      baseline.solver.positions,
      candidateLimit: 1,
    );
    expect(bounded.candidates, lessThanOrEqualTo(1));
    expect(const ConstraintValidator().validate(m, bounded.positions), isEmpty);
  });
  for (final count in [7, 11]) {
    test(
      'boundary and personal constraints preserved for $count people',
      () async {
        final m = sample(2026, 11, count: count)..boundaryConfirmed = true;
        m.constraints['p1']!.cannot.add(1);
        m.constraints['p2']!.must.add(5);
        m.boundary['p1'] = ['2026-10-31'];
        final result = await FairnessOptimizer(
          nodeLimit: 10000,
          localTimeLimit: const Duration(seconds: 10),
        ).optimize(m);
        expect(result.solver.hasValidIncumbent, isTrue);
        expect(
          const ConstraintValidator().validate(m, result.solver.positions),
          isEmpty,
        );
      },
    );
  }
}
