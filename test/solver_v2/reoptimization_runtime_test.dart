@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/runtime/lifecycle.dart';
import 'package:akys/solver_v2/editing/reoptimization.dart';

import 'schedule_editor_test.dart' as f;

void main() {
  test('isolate transports locks and accepts equal clinical quality with fewer changes', () async {
    final p = f.fixture(days: [1, 0, 0, 1]);
    final request = ReoptimizationRequest(p, reference: [1, 0], locks: {1: 0});
    final controller = OptimizationController();
    addTearDown(controller.dispose);
    final seen = <OptimizationSnapshot>[];
    final subscription = controller.events.listen(seen.add);
    addTearDown(subscription.cancel);
    await controller.start(
      request.problem,
      options: const OptimizationOptions(budget: Duration(seconds: 3)),
    );
    if (controller.value.state != OptimizationState.optimal) {
      await controller.events
          .firstWhere(
            (e) =>
                e.state == OptimizationState.optimal ||
                e.state == OptimizationState.failed,
          )
          .timeout(const Duration(seconds: 5));
    }
    expect(controller.value.error, isNull);
    expect(controller.value.state, OptimizationState.optimal);
    expect(controller.value.best!.assignments, [1, 0]);
    final solutions = seen
        .where((e) => e.best != null)
        .map((e) => e.best!)
        .toList();
    for (var i = 0; i < solutions.length; i++) {
      expect(solutions[i].assignments[1], 0);
      if (i > 0) {
        expect(
          request.problem.compareClinicalCandidates(
            solutions[i],
            solutions[i - 1],
          ),
          lessThanOrEqualTo(0),
        );
      }
    }
  });
  test('isolate exposes later equal-quality tie improvement instead of rejecting it', () async {
    final request = ReoptimizationRequest(
      f.fixture(days: [1]),
      reference: [1],
      locks: {},
    );
    final controller = OptimizationController();
    addTearDown(controller.dispose);
    final seen = <Solution>[];
    final subscription = controller.events.listen((e) {
      if (e.best != null) seen.add(e.best!);
    });
    addTearDown(subscription.cancel);
    await controller.start(request.problem);
    if (controller.value.state != OptimizationState.optimal) {
      await controller.events
          .firstWhere(
            (e) =>
                e.state == OptimizationState.optimal ||
                e.state == OptimizationState.failed,
          )
          .timeout(const Duration(seconds: 5));
    }
    expect(controller.value.error, isNull);
    expect(controller.value.best!.assignments, [1]);
    expect(seen.any((s) => s.assignments.single == 0), true);
    expect(
      seen.first.clinicalQuality!.compareTo(seen.last.clinicalQuality!),
      0,
    );
  });
}
