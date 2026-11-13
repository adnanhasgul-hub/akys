// Stage 1.7A paired forward-check measurements; same snapshots as Stage 1.6.
// dart --packages=.dart_tool/package_config.json tool/solver_v2/forward_compare.dart 6-open bounded on 120
import 'dart:convert';
import 'dart:io';

import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import 'clinical_resilience.dart' as fixtures;
import '../../test/solver_v2/support/reference_clinical_quality.dart';

int? processRss({required bool peak}) {
  try {
    return peak ? ProcessInfo.maxRss : ProcessInfo.currentRss;
  } on UnsupportedError {
    return null;
  }
}

// Linux process user+system CPU; not a per-function CPU profiler.
int? cpuTicks() {
  try {
    final stat = File('/proc/self/stat').readAsStringSync();
    final fields = stat
        .substring(stat.lastIndexOf(')') + 2)
        .trim()
        .split(RegExp(r'\s+'));
    return int.parse(fields[11]) + int.parse(fields[12]);
  } on FileSystemException {
    return null;
  }
}

void main(List<String> args) {
  if (args.length != 4) throw ArgumentError('case strategy on|off seconds');
  final name = args[0], strategy = args[1], seconds = int.parse(args[3]);
  if (!['on', 'off'].contains(args[2])) throw ArgumentError('on|off');
  final forward = args[2] == 'on';
  if (!['deadends', 'combined', 'twophase', 'bounded'].contains(strategy) ||
      seconds <= 0) {
    throw ArgumentError('arguments');
  }
  final problem = fixtures.resilienceProblem(name);
  final people = problem.doctors.length, days = problem.slotsPerDay.length;
  final revisionResult = Process.runSync('git', ['rev-parse', 'HEAD']);
  if (revisionResult.exitCode != 0) {
    throw StateError('Cannot determine source revision');
  }
  final sourceRevision = (revisionResult.stdout as String).trim();
  if (name.endsWith('-open') || name.endsWith('-tight')) {
    if (!const SolutionValidator()
        .validate(problem, fixtures.resilienceWitness(problem))
        .isValid) {
      throw StateError('invalid fixture witness');
    }
  }
  var independentlyChecked = 0;
  void checkQuality(Solution candidate) {
    final expected = const ReferenceClinicalQualityCalculator().calculate(
      problem,
      candidate.assignments,
    );
    final actual = candidate.clinicalQuality!.components;
    if (actual.length != 19 ||
        List.generate(
          19,
          (i) => expected[i].toString() == actual[i].toString(),
        ).contains(false)) {
      throw StateError('reference quality mismatch');
    }
    independentlyChecked++;
  }

  late final TransitionSession session;
  late final Stopwatch watch;
  Solution? seen, first;
  int? firstMicros;
  session = TransitionSession(
    problem,
    forwardChecking: forward,
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
      checkQuality(candidate);
      first = candidate;
      firstMicros = watch.elapsedMicroseconds;
    },
  );
  watch = Stopwatch()..start();
  final initialCpu = cpuTicks();
  int? restrictedProofMicros;
  SearchResult? result;
  final marks = <Map<String, Object?>>[];
  for (final deadline in seconds > 30 ? [30, seconds] : [seconds]) {
    do {
      final remaining = (deadline * 1000000 - watch.elapsedMicroseconds).clamp(
        0,
        1 << 62,
      );
      result = session.run(
        maxNodes: 1024,
        timeLimit: Duration(microseconds: remaining),
      );
      if (session.restrictedVerdict == RestrictedVerdict.provenInfeasible) {
        restrictedProofMicros ??= watch.elapsedMicroseconds;
      }
      if (result.best != null && !identical(result.best, seen)) {
        if (seen != null &&
            result.best!.clinicalQuality!.compareTo(seen.clinicalQuality!) >=
                0) {
          throw StateError('non-improving replacement');
        }
        seen = result.best;
        checkQuality(seen!);
        final check = const SolutionValidator().validate(
          session.problem,
          seen,
          localEvidence: session,
        );
        if (!check.isValid) {
          throw StateError('invalid incumbent: ${check.errors}');
        }
      }
    } while (result.canResume &&
        watch.elapsedMicroseconds < deadline * 1000000);
    final current = result.best;
    final currentCpu = cpuTicks();
    if (session.phase == TransitionPhase.substitution &&
        session.restrictedVerdict != RestrictedVerdict.provenInfeasible) {
      throw StateError('unsafe B phase');
    }
    marks.add({
      'seconds': deadline,
      'assignments': current?.assignments,
      'restrictedVerdict': session.restrictedVerdict.name,
      'independentlyChecked': independentlyChecked,
      'observedMicros': watch.elapsedMicroseconds,
      'status': result.status.name,
      'stage': session.phase.name,
      'visitedNodes': session.totalVisitedNodes,
      'forwardChecks': session.forwardChecks,
      'forwardPruned': session.forwardPruned,
      'forwardRootPruned': session.forwardRootPruned,
      'forwardWallTicks': session.forwardCheckTicks,
      'stopwatchFrequency': Stopwatch().frequency,
      'cpuTicksFromStart': initialCpu == null || currentCpu == null
          ? null
          : currentCpu - initialCpu,
      'restrictedProofMicros': restrictedProofMicros,
      'proofMicros':
          result.status == SearchStatus.infeasible ||
              result.status == SearchStatus.optimal
          ? watch.elapsedMicroseconds
          : null,
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
      'case': name,
      'seed': fixtures.resilienceSeed,
      'strategy': strategy,
      'budgetSeconds': seconds,
      'forwardChecking': forward,
      'cpuTicksPerSecond': Process.runSync('getconf', [
        'CLK_TCK',
      ]).stdout.toString().trim(),
      'sourceRevision': sourceRevision,
      'runtime': Platform.version,
      'firstMicros': firstMicros,
      'firstQuality': first?.clinicalQuality?.components
          .map((x) => x.toString())
          .toList(),
      'snapshot': session.problem.toMessage(),
      'marks': marks,
      'independentReferenceChecks': independentlyChecked,
      'instrumentation': '1024-node steps; one callback and independent validation at first incumbent; all candidate solutions validated by ClinicalQualityEvaluator; observed incumbents additionally validated',
    }),
  );
}
