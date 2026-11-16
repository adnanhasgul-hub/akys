@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/runtime/lifecycle.dart';

void main() {
  test(
    'Chromium refuses unsupported worker instead of running synchronous DFS',
    () async {
      expect(OptimizationController.supported, false);
      final c = OptimizationController();
      addTearDown(c.dispose);
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => ticks++,
      );
      addTearDown(timer.cancel);
      await c.start(
        Problem(
          startDate: DateTime.utc(2026, 11),
          doctors: [Doctor(id: 's', seniorityLevel: SeniorityLevel.k1)],
          slotsPerDay: [1],
          slotRoles: [DutyRole.senior],
          slotRequirements: [SlotRequirement.required],
          dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
        ),
      );
      expect(c.value.state, OptimizationState.failed);
      expect(c.value.error, contains('worker'));
      expect(c.value.nodes, 0);
      expect(c.value.best, isNull);
      expect(c.hasWorker, false);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(ticks, greaterThan(0));
    },
  );
}
