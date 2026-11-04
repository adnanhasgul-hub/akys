import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/engine/duty_engine.dart';
import 'package:akys/modules/work_schedule/engine/v13/feasibility_solver.dart';
import 'package:akys/modules/work_schedule/engine/v13/constraint_validator.dart';

import 'engine_test.dart' show sample;

void main() {
  test('Five cannot benchmark and cooperative responsiveness', () async {
    final m = sample(2026, 11);
    m.constraints['p1']!.cannot.addAll([1, 5, 9, 13, 17]);
    final old = Stopwatch()..start();
    final oldResult = const DutyEngine().generate(m);
    old.stop();
    var beats = 0;
    final gaps = <int>[];
    final gapWatch = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      beats++;
      gaps.add(gapWatch.elapsedMilliseconds);
      gapWatch.reset();
    });
    final clock = Stopwatch()..start();
    final result = await const FeasibilitySolver(
      nodeLimit: 5000,
      yieldEvery: 8,
    ).solve(m);
    clock.stop();
    timer.cancel();
    expect(result.hasValidIncumbent, true);
    expect(const ConstraintValidator().validate(m, result.positions), isEmpty);
    expect(beats, greaterThan(0));
    debugPrint(
      'BENCH platform=${kIsWeb ? 'web' : 'native-vm'} oldMs=${old.elapsedMilliseconds} oldValid=${oldResult.month != null} newMs=${clock.elapsedMilliseconds} states=${result.visitedStates} status=${result.statusCode} coverageProven=${result.optimalityProven} beats=$beats maxGapMs=${gaps.reduce((a, b) => a > b ? a : b)}',
    );
  });
}
