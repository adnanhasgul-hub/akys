// Standalone quality tracer. One solver node per call exposes every incumbent;
// the instrumentation overhead is included in all measurements.
// dart --packages=.dart_tool/package_config.json tool/solver_v2/quality_trace.dart PEOPLE DAYS VARIANT STRATEGY SECONDS
import 'dart:convert';
import 'dart:io';

import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

const int scenarioSeed = 150300;
Problem traceScenario(int people, int days, String variant) {
  if (variant == 'transition') {
    return Problem(
      startDate: DateTime.utc(2026, 11),
      doctors: [
        Doctor(id: 'synthetic_junior', group: DutyGroup.junior, maxDuties: 1),
      ],
      slotsPerDay: [1],
      slotRoles: [DutyRole.senior],
      slotRequirements: [SlotRequirement.required],
      dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
    );
  }
  if (people < 6 ||
      ![30, 31].contains(days) ||
      !['mixed', 'surplus', 'forced', 'ratio', 'rank'].contains(variant)) {
    throw ArgumentError('invalid fixture');
  }
  final start = days == 30 ? DateTime.utc(2026, 11) : DateTime.utc(2026, 12);
  final seniorCount = variant == 'ratio'
      ? (people == 6 ? 5 : 4)
      : people == 6
      ? 4
      : people == 10
      ? 5
      : people == 15
      ? 6
      : 8;
  final roles = <DutyRole>[],
      requirements = <SlotRequirement>[],
      counts = <int>[];
  for (var day = 0; day < days; day++) {
    final optional = variant == 'surplus' ? 2 : 1;
    counts.add(1 + optional);
    roles.add(DutyRole.senior);
    requirements.add(SlotRequirement.required);
    for (var j = 0; j < optional; j++) {
      roles.add(DutyRole.junior);
      requirements.add(SlotRequirement.optional);
    }
  }
  final doctors = <Doctor>[];
  for (var i = 0; i < people; i++) {
    final senior = i < seniorCount;
    final blocked = <int>{};
    if (variant == 'forced') {
      for (var d = 0; d < days; d++) {
        if (i >= 4 || [3, 1, 2, 0][d % 4] != i) blocked.add(d);
      }
    } else {
      for (var d = 0; d < days; d++) {
        if ((d * 7 + i * 11 + scenarioSeed) % 9 < 2 &&
            (i >= 4 || [3, 1, 2, 0][d % 4] != i)) {
          blocked.add(d);
        }
      }
    }
    final mandatory = <int>{};
    if (i < 4) {
      for (var d = 0; d < days; d++) {
        if ([3, 1, 2, 0][d % 4] == i && mandatory.length < 2) mandatory.add(d);
      }
    }
    final previous = i < 4 && [0, 2].contains(i)
        ? [start.subtract(const Duration(days: 1))]
        : <DateTime>[];
    doctors.add(
      Doctor(
        id: 'synthetic_$i',
        seniorityRank: variant == 'rank' ? people - i : 1,
        group: senior ? DutyGroup.senior : DutyGroup.junior,
        seniorityLevel: senior ? SeniorityLevel.values[i % 4] : null,
        maxDuties: i < 4
            ? 8
            : variant == 'forced'
            ? 0
            : 2 + (i % 7),
        must: mandatory,
        unavailable: blocked,
        previousDuties: previous,
      ),
    );
  }
  return Problem(
    startDate: start,
    doctors: doctors,
    slotsPerDay: counts,
    slotRoles: roles,
    slotRequirements: requirements,
    dayDifficulties: [
      for (var d = 0; d < days; d++)
        DayDifficulty(
          weekdayScore: [
            3,
            3,
            3,
            1,
            6,
            9,
            5,
          ][start.add(Duration(days: d)).weekday - 1],
          holidayName: d % 4 == 0 ? 'Synthetic holiday' : null,
          holidayScore: d % 4 == 0 ? 1 + (d % 10) : null,
        ),
    ],
  );
}

Solution witness(Problem p) {
  final assigned = <int>[], counts = List<int>.filled(p.doctors.length, 0);
  for (var d = 0; d < p.slotsPerDay.length; d++) {
    final who = [3, 1, 2, 0][d % 4];
    assigned.add(who);
    counts[who]++;
    for (var k = 1; k < p.slotsPerDay[d]; k++) {
      assigned.add(unfilledSlot);
    }
  }
  final sorted = [...counts]..sort();
  return Solution(assigned, [
    sorted.last - sorted.first,
    counts.fold<int>(0, (a, b) => a + b * b),
  ]);
}

Map<String, Object?> summarize(Problem p, Solution? s) {
  if (s == null) return {'quality': null, 'optionalFilled': null};
  return {
    'quality': s.clinicalQuality!.components.map((x) => x.toString()).toList(),
    'optionalFilled': [
      for (var i = 0; i < s.assignments.length; i++)
        if (p.slotRequirements[i] == SlotRequirement.optional &&
            s.assignments[i] != unfilledSlot)
          i,
    ].length,
    'assignments': s.assignments,
  };
}

void main(List<String> args) {
  if (args.length < 5 || args.length > 6) {
    stderr.writeln('expected people days variant strategy seconds [profile]');
    exit(64);
  }
  final people = int.parse(args[0]),
      days = int.parse(args[1]),
      variant = args[2],
      strategy = args[3],
      seconds = int.parse(args[4]);
  if (![
        'baseline',
        'ordering',
        'deadends',
        'combined',
        'twophase',
        'bounded',
      ].contains(strategy) ||
      seconds <= 0) {
    throw ArgumentError('invalid');
  }
  final p = traceScenario(people, days, variant);
  if (variant != 'transition' &&
      !const SolutionValidator().validate(p, witness(p)).isValid) {
    throw StateError('invalid fixture witness');
  }
  final profile = args.length == 6 && args[5] == 'profile'
      ? SearchProfile()
      : null;
  final session = TransitionSession(
    p,
    candidateOrdering:
        strategy == 'ordering' ||
        strategy == 'combined' ||
        strategy == 'twophase' ||
        strategy == 'bounded',
    earlyDeadEnds:
        strategy == 'deadends' ||
        strategy == 'combined' ||
        strategy == 'twophase' ||
        strategy == 'bounded',
    experimentalTwoPhase: strategy == 'twophase' || strategy == 'bounded',
    clinicalBounds: strategy == 'bounded',
    profile: profile,
  );
  final watch = Stopwatch()..start();
  final events = <Map<String, Object?>>[], marks = <Map<String, Object?>>[];
  Solution? previous;
  SearchResult? result;
  var nextMark = seconds >= 120 ? 30 : seconds;
  while (true) {
    final stageBefore = session.phase;
    result = session.run(maxNodes: 1);
    if (result.best != null && !identical(previous, result.best)) {
      final valid = const SolutionValidator().validate(
        session.problem,
        result.best!,
        localEvidence: session,
      );
      if (!valid.isValid) throw StateError('invalid incumbent ${valid.errors}');
      if (previous != null &&
          result.best!.clinicalQuality!.compareTo(previous.clinicalQuality!) >=
              0) {
        throw StateError('non-improving incumbent');
      }
      previous = result.best;
      events.add({
        'elapsedMicros': watch.elapsedMicroseconds,
        'node': result.visitedNodes,
        'stage': stageBefore.name,
        ...summarize(session.problem, previous),
      });
    }
    if (watch.elapsedMicroseconds >= nextMark * 1000000 || !result.canResume) {
      marks.add({
        'seconds': nextMark,
        'observedMicros': watch.elapsedMicroseconds,
        'status': result.status.name,
        'stage': stageBefore.name,
        'nodes': result.visitedNodes,
        'boundChecks': session.clinicalBoundChecks,
        'boundPruned': session.clinicalPruned,
        'boundTicks': session.clinicalBoundTicks,
        'stopwatchFrequency': Stopwatch().frequency,
        'optimalityProven': result.status == SearchStatus.optimal,
        'restrictedVerdict': session.restrictedVerdict.name,
        ...summarize(session.problem, previous),
      });
      if (!result.canResume || nextMark == seconds) break;
      nextMark = seconds;
    }
  }
  stdout.writeln(
    jsonEncode({
      'seed': scenarioSeed,
      'people': session.problem.doctors.length,
      'days': session.problem.slotsPerDay.length,
      'variant': variant,
      'strategy': strategy,
      'seconds': seconds,
      'runtime': Platform.version,
      'qualityPhaseStartNode': session.qualityPhaseStartNode,
      if (profile != null)
        'profile': {
          'completedLeaves': profile.completedLeaves,
          'validLeaves': profile.validLeaves,
          'invalidLeaves': profile.invalidLeaves,
          'qualityCalls': profile.qualityCalls,
          'qualityTicks': profile.qualityTicks,
          'firstValidationCalls': profile.firstValidationCalls,
          'firstValidationTicks': profile.firstValidationTicks,
          'hardCalls': profile.hardCalls,
          'hardTicks': profile.hardTicks,
          'stopwatchFrequency': Stopwatch().frequency,
          'emptyOptionalChoices': profile.emptyOptionalChoices,
          'emptyOptionalByDepth': profile.emptyOptionalByDepth.map(
            (k, v) => MapEntry(k.toString(), v),
          ),
          'postFirstNodesByDepth': profile.postFirstNodesByDepth.map(
            (k, v) => MapEntry(k.toString(), v),
          ),
        },
      'snapshot': session.problem.toMessage(),
      'events': events,
      'marks': marks,
    }),
  );
}
