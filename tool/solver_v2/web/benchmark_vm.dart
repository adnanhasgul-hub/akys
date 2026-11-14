import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';
import 'package:akys/solver_v2/runtime/lifecycle.dart';

import '../clinical_resilience.dart';
import 'benchmark_shared.dart';

Future<void> main() async {
  final rows = <Map<String, Object?>>[];
  for (var rep = 1; rep <= 3; rep++) {
    int? first;
    final watch = Stopwatch()..start();
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    final session = TransitionSession(
      resilienceProblem('6-open'),
      candidateOrdering: true,
      earlyDeadEnds: true,
      experimentalTwoPhase: true,
      clinicalBounds: true,
      onFirstIncumbent: (_) {
        first = watch.elapsedMicroseconds;
      },
    );
    final before = ProcessInfo.currentRss;
    final r = session.run(
      maxNodes: 1 << 30,
      timeLimit: const Duration(seconds: 1),
    );
    final elapsed = watch.elapsedMicroseconds;
    timer.cancel();
    if (r.best == null ||
        !const SolutionValidator()
            .validate(session.problem, r.best!, localEvidence: session)
            .isValid) {
      throw StateError('Invalid direct result');
    }
    rows.add({
      'mode': 'VM direct',
      'repeat': rep,
      'firstUs': first,
      'totalUs': elapsed,
      'nodes': session.totalVisitedNodes,
      'nodesPerSecond': session.totalVisitedNodes * 1000000 / elapsed,
      'mainTicks': ticks,
      'rssBeforeBytes': before,
      'rssAfterBytes': ProcessInfo.currentRss,
      'state': r.status.name,
      'quality': r.best!.clinicalQuality!.components
          .map((q) => q.toString())
          .toList(),
      'cancelLatencyUs': null,
      'deliveryMedianUs': null,
    });
    final rss = ProcessInfo.currentRss;
    final row = await measureController(
      OptimizationController(),
      'VM isolate',
      rep,
    );
    row.addAll({
      'rssBeforeBytes': rss,
      'rssAfterBytes': ProcessInfo.currentRss,
    });
    rows.add(row);
  }
  stdout.writeln(
    jsonEncode({
      'runtime': Platform.version,
      'seed': resilienceSeed,
      'fixture': '6-open',
      'windowMs': 1000,
      'rows': rows,
      'memoryScope': 'whole Dart process RSS; not isolate-only; includes JIT, GC, shared pages',
    }),
  );
}
