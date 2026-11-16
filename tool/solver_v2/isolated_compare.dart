// Standalone, single-process benchmark; no solver profiling enabled.
// dart --packages=.dart_tool/package_config.json tool/solver_v2/isolated_compare.dart 6 30 mixed bounded 1
import 'dart:convert';
import 'dart:io';

import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import 'quality_trace.dart' as fixtures;

int? processRss({required bool peak}) {
  try {
    return peak ? ProcessInfo.maxRss : ProcessInfo.currentRss;
  } on UnsupportedError {
    return null;
  }
}

void main(List<String> args) {
  if (args.length != 5) {
    throw ArgumentError('people days variant strategy repeat');
  }
  final people = int.parse(args[0]),
      days = int.parse(args[1]),
      variant = args[2],
      strategy = args[3],
      repeat = int.parse(args[4]);
  if (!['deadends', 'combined', 'twophase', 'bounded'].contains(strategy)) {
    throw ArgumentError('strategy');
  }
  final problem = fixtures.traceScenario(people, days, variant);
  final revisionResult = Process.runSync('git', ['rev-parse', 'HEAD']);
  if (revisionResult.exitCode != 0) {
    throw StateError('Cannot determine source revision');
  }
  final sourceRevision = (revisionResult.stdout as String).trim();
  if (!const SolutionValidator()
      .validate(problem, fixtures.witness(problem))
      .isValid) {
    throw StateError('fixture witness invalid');
  }
  late final TransitionSession session;
  late final Stopwatch watch;
  Solution? seen, first;
  int? firstMicros;
  session = TransitionSession(
    problem,
    candidateOrdering: strategy != 'deadends',
    earlyDeadEnds: true,
    experimentalTwoPhase: strategy == 'twophase' || strategy == 'bounded',
    clinicalBounds: strategy == 'bounded',
    onFirstIncumbent: (candidate) {
      final check = const SolutionValidator().validate(
        session.problem,
        candidate,
        localEvidence: session,
      );
      if (!check.isValid) {
        throw StateError('invalid first incumbent: ${check.errors}');
      }
      first = candidate;
      firstMicros = watch.elapsedMicroseconds;
    },
  );
  watch = Stopwatch()..start();
  SearchResult? result;
  final marks = <Map<String, Object?>>[];
  for (final deadline in [30, 120]) {
    do {
      final remaining = (deadline * 1000000 - watch.elapsedMicroseconds).clamp(
        0,
        1 << 62,
      );
      result = session.run(
        maxNodes: 1024,
        timeLimit: Duration(microseconds: remaining),
      );
      if (result.best != null && !identical(result.best, seen)) {
        seen = result.best;
        final check = const SolutionValidator().validate(
          session.problem,
          seen!,
          localEvidence: session,
        );
        if (!check.isValid) {
          throw StateError('invalid incumbent: ${check.errors}');
        }
      }
    } while (result.canResume &&
        watch.elapsedMicroseconds < deadline * 1000000);
    final current = result.best;
    marks.add({
      'seconds': deadline,
      'observedMicros': watch.elapsedMicroseconds,
      'status': result.status.name,
      'stage': session.phase.name,
      'visitedNodes': result.visitedNodes,
      'clinicalPruned': session.clinicalPruned,
      'mandatoryPruned': session.mandatoryPruned,
      'feasibilityPruned': session.feasibilityPruned,
      'boundChecks': session.clinicalBoundChecks,
      'improvements': session.incumbentImprovements,
      'currentRssBytes': processRss(peak: false),
      'peakRssBytes': processRss(peak: true),
      'quality': current?.clinicalQuality?.components
          .map((x) => x.toString())
          .toList(),
      'optionalFilled': current == null
          ? null
          : [
              for (var i = 0; i < current.assignments.length; i++)
                if (session.problem.slotRequirements[i] ==
                        SlotRequirement.optional &&
                    current.assignments[i] != unfilledSlot)
                  i,
            ].length,
      'optimalityProven': result.status == SearchStatus.optimal,
    });
    if (!result.canResume) break;
  }
  stdout.writeln(
    jsonEncode({
      'people': people,
      'days': days,
      'variant': variant,
      'seed': fixtures.scenarioSeed,
      'strategy': strategy,
      'repeat': repeat,
      'sourceRevision': sourceRevision,
      'runtime': Platform.version,
      'firstMicros': firstMicros,
      'firstQuality': first?.clinicalQuality?.components
          .map((x) => x.toString())
          .toList(),
      'snapshot': session.problem.toMessage(),
      'marks': marks,
      'instrumentation': '1024-node steps; one callback and independent validation at first incumbent; all candidate solutions validated by ClinicalQualityEvaluator; observed incumbents additionally validated',
    }),
  );
}
