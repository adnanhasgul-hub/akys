import 'dart:async';

import 'package:akys/solver_v2/runtime/lifecycle.dart';

import '../clinical_resilience.dart';

Future<Map<String, Object?>> measurePlatform(
  OptimizationController c,
  String fixture,
  bool experimental,
  int repeat,
) async {
  final clock = Stopwatch()..start();
  int? started, first;
  var beats = 0, prior = 0, gap = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
    final now = clock.elapsedMicroseconds;
    if (prior != 0 && now - prior > gap) gap = now - prior;
    prior = now;
    beats++;
  });
  final events = c.events.listen((s) {
    if (s.state != OptimizationState.preparing) {
      started ??= clock.elapsedMicroseconds;
    }
    if (s.best != null) first ??= clock.elapsedMicroseconds;
  });
  await c.start(
    resilienceProblem(fixture),
    options: OptimizationOptions(
      budget: const Duration(seconds: 2),
      candidateOrdering: experimental,
      earlyDeadEnds: experimental,
      experimentalTwoPhase: experimental,
      clinicalBounds: experimental,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final before = c.value.nodes;
  final id = c.value.runId;
  c.extend(const Duration(seconds: 2));
  await Future<void>.delayed(const Duration(milliseconds: 700));
  final watch = Stopwatch()..start();
  await c.cancel();
  watch.stop();
  final state = c.value;
  if (state.runId != id || state.nodes < before) {
    throw StateError('Frontier reset');
  }
  await events.cancel();
  timer.cancel();
  await c.dispose();
  return {
    'fixture': fixture,
    'seed': 160600,
    'repeat': repeat,
    'experimental': experimental,
    'startedUs': started,
    'firstObservedUs': first,
    'firstSolverUs': state.firstFeasible?.inMicroseconds,
    'wallUs': clock.elapsedMicroseconds,
    'nodes': state.nodes,
    'cancelUs': watch.elapsedMicroseconds,
    'maxEventLoopGapUs': gap,
    'beats': beats,
    'extensionSameRun': true,
    'state': state.state.name,
    'proof': state.proof.name,
    'validIncumbent': state.best != null,
    'quality': state.best?.clinicalQuality?.components
        .map((e) => e.toString())
        .toList(),
  };
}
