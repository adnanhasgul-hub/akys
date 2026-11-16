import 'dart:async';

import 'package:akys/solver_v2/runtime/lifecycle.dart';

import '../clinical_resilience.dart';

Future<Map<String, Object?>> measureController(
  OptimizationController c,
  String mode,
  int rep,
) async {
  final watch = Stopwatch()..start();
  var ticks = 0, prior = 0, maxGap = 0;
  int? firstObserved;
  final delays = <int>[];
  var events = 0;
  final tick = Timer.periodic(const Duration(milliseconds: 5), (_) {
    final t = watch.elapsedMicroseconds;
    if (prior != 0 && t - prior > maxGap) maxGap = t - prior;
    prior = t;
    ticks++;
  });
  final listener = c.events.listen((s) {
    events++;
    if (s.best != null) firstObserved ??= watch.elapsedMicroseconds;
    if (s.transportDelay != null) delays.add(s.transportDelay!.inMicroseconds);
  });
  await c.start(
    resilienceProblem('6-open'),
    options: const OptimizationOptions(
      budget: Duration(seconds: 3),
      candidateOrdering: true,
      earlyDeadEnds: true,
      experimentalTwoPhase: true,
      clinicalBounds: true,
    ),
  );
  if (c.value.state == OptimizationState.preparing) {
    await c.events.firstWhere((s) => s.state != OptimizationState.preparing);
  }
  if (c.value.state == OptimizationState.failed) {
    throw StateError(c.value.error!);
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  final cancelWatch = Stopwatch()..start();
  await c.cancel();
  cancelWatch.stop();
  tick.cancel();
  await listener.cancel();
  final s = c.value;
  await c.dispose();
  if (s.best == null ||
      s.state != OptimizationState.cancelled ||
      s.forcedTermination) {
    throw StateError(
      'No cooperatively preserved solution: ${s.state} ${s.error}',
    );
  }
  delays.sort();
  return {
    'mode': mode,
    'repeat': rep,
    'firstObservedUs': firstObserved,
    'workerFirstUs': s.firstFeasible?.inMicroseconds,
    'workerUs': s.elapsed.inMicroseconds,
    'wallUs': watch.elapsedMicroseconds,
    'nodes': s.nodes,
    'nodesPerSecond': s.nodes * 1000000 / s.elapsed.inMicroseconds,
    'cancelLatencyUs': cancelWatch.elapsedMicroseconds,
    'forced': s.forcedTermination,
    'deliveryMedianUs': delays.isEmpty ? null : delays[delays.length ~/ 2],
    'deliveryMaxUs': delays.isEmpty ? null : delays.last,
    'events': events,
    'mainTicks': ticks,
    'maxMainGapUs': maxGap,
    'state': s.state.name,
    'proof': s.proof.name,
    'quality': s.best?.clinicalQuality?.components
        .map((c) => c.toString())
        .toList(),
  };
}
