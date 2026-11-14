// Separate command: no UI/Firebase; real isolate, short sequential measurements.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';
import 'package:akys/solver_v2/runtime/lifecycle.dart';

import 'clinical_resilience.dart';

Future<void> main() async {
  final sourceFiles =
      Directory('lib/solver_v2/runtime')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path)
          .toList()
        ..sort();
  final hashes = Process.runSync('git', [
    'hash-object',
    ...sourceFiles,
  ]).stdout.toString().trim().split('\n');
  final sourceObjects = {
    for (var i = 0; i < sourceFiles.length; i++) sourceFiles[i]: hashes[i],
  };
  final p = resilienceProblem('6-open');
  final rows = <Map<String, Object?>>[];
  for (var rep = 1; rep <= 3; rep++) {
    final direct = TransitionSession(
      p,
      candidateOrdering: true,
      earlyDeadEnds: true,
      experimentalTwoPhase: true,
      clinicalBounds: true,
    );
    final wall = Stopwatch()..start();
    final r = direct.run(
      maxNodes: 1 << 30,
      timeLimit: const Duration(milliseconds: 300),
    );
    if (r.best != null &&
        !const SolutionValidator()
            .validate(direct.problem, r.best!, localEvidence: direct)
            .isValid) {
      throw StateError('invalid baseline');
    }
    rows.add({
      'mode': 'direct bulk',
      'repeat': rep,
      'wallUs': wall.elapsedMicroseconds,
      'nodes': direct.totalVisitedNodes,
      'status': r.status.name,
    });
    for (final progress in [100, 10000]) {
      final c = OptimizationController();
      var events = 0, beats = 0, maxGap = 0, prior = 0;
      final ui = Stopwatch()..start();
      final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
        final now = ui.elapsedMicroseconds;
        if (prior != 0 && now - prior > maxGap) maxGap = now - prior;
        prior = now;
        beats++;
      });
      final listener = c.events.listen((_) {
        events++;
      });
      final started = Stopwatch()..start();
      await c.start(
        p,
        options: OptimizationOptions(
          budget: const Duration(milliseconds: 300),
          progressInterval: Duration(milliseconds: progress),
          candidateOrdering: true,
          earlyDeadEnds: true,
          experimentalTwoPhase: true,
          clinicalBounds: true,
        ),
      );
      if (c.value.state != OptimizationState.timedOut) {
        await c.events
            .firstWhere((s) => s.state == OptimizationState.timedOut)
            .timeout(const Duration(seconds: 5));
      }
      final snapshot = c.value;
      final cancel = Stopwatch()..start();
      await c.cancel();
      cancel.stop();
      timer.cancel();
      rows.add({
        'mode': 'isolate',
        'progressMs': progress,
        'repeat': rep,
        'wallUs': started.elapsedMicroseconds,
        'workerUs': snapshot.elapsed.inMicroseconds,
        'firstUs': snapshot.firstFeasible?.inMicroseconds,
        'nodes': snapshot.nodes,
        'events': events,
        'heartbeats': beats,
        'maxHeartbeatGapUs': maxGap,
        'cancelUs': cancel.elapsedMicroseconds,
        'retainedBest': c.value.best != null,
        'quality': snapshot.best?.clinicalQuality?.components
            .map((x) => x.toString())
            .toList(),
        'status': snapshot.state.name,
      });
      await listener.cancel();
      await c.dispose();
    }
  }
  stdout.writeln(
    jsonEncode({
      'sourceHead': Process.runSync('git', [
        'rev-parse',
        'HEAD',
      ]).stdout.toString().trim(),
      'runtimeSourceObjects': sourceObjects,
      'runtime': Platform.version,
      'seed': resilienceSeed,
      'budgetMs': 300,
      'rows': rows,
    }),
  );
}
