// Standalone Dart VM benchmark, intentionally excluded from flutter test.
// Usage: dart run tool/solver_v2/clinical_benchmark.dart <doctors> <days>
//        <standard|tight|hard|impossible> <node-budget|seconds> <limit>
import 'dart:convert';
import 'dart:io';

import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

Problem snapshot(int people, int days, String variant) {
  // Four seniors can cover 30 days under the eight-duty maximum. Additional
  // people are juniors. All identifiers and constraints are synthetic.
  final seniorCount = people < 4 ? people : 4;
  final impossible = variant == 'impossible';
  final doctors = <Doctor>[];
  for (var i = 0; i < people; i++) {
    final senior = i < seniorCount;
    final max = impossible ? 1 : (i == people - 1 ? 7 : 8);
    final blocked = <int>{
      if (i == 0) 0,
      if (variant == 'tight' || variant == 'hard') ...{
        (i * 3 + 4) % days,
        (i * 5 + 7) % days,
      },
      if (variant == 'hard') ...{
        (i * 7 + 11) % days,
        (i * 9 + 13) % days,
        (i * 11 + 17) % days,
      },
    };
    // Preserve an independently checkable four-senior cyclic witness.
    if (senior && !impossible) {
      blocked.removeWhere((day) => [3, 1, 2, 0][day % 4] == i);
    }
    doctors.add(
      Doctor(
        id: 'synthetic_$i',
        group: senior ? DutyGroup.senior : DutyGroup.junior,
        seniorityLevel: senior ? SeniorityLevel.values[i] : null,
        maxDuties: max,
        must: i == 0 && !impossible ? {3} : {},
        unavailable: blocked,
        previousDuties: i == 0 ? [DateTime.utc(2026, 10, 31)] : [],
      ),
    );
  }
  return Problem(
    startDate: DateTime.utc(2026, 11),
    doctors: doctors,
    slotsPerDay: List.filled(days, 2),
    slotRoles: [
      for (var i = 0; i < days; i++) ...[DutyRole.senior, DutyRole.junior],
    ],
    slotRequirements: [
      for (var i = 0; i < days; i++) ...[
        SlotRequirement.required,
        SlotRequirement.optional,
      ],
    ],
    dayDifficulties: [
      for (var i = 0; i < days; i++)
        DayDifficulty(
          weekdayScore: [5, 3, 3, 3, 1, 6, 9][i % 7],
          holidayName: i == 9 ? 'Synthetic holiday' : null,
          holidayScore: i == 9 ? 8 : null,
        ),
    ],
  );
}

void main(List<String> args) {
  if (args.length != 5) {
    stderr.writeln('expected people days variant mode limit');
    exit(64);
  }
  final people = int.parse(args[0]),
      days = int.parse(args[1]),
      variant = args[2],
      mode = args[3],
      limit = int.parse(args[4]);
  if (!['standard', 'tight', 'hard', 'impossible'].contains(variant) ||
      !['seconds', 'node-budget'].contains(mode) ||
      limit <= 0) {
    throw ArgumentError('Invalid arguments');
  }
  final p = snapshot(people, days, variant),
      search = SearchSession(snapshot(people, days, variant));
  final watch = Stopwatch()..start();
  Solution? seen;
  int? firstMicros;
  List<String>? firstQuality;
  final marks = <Map<String, Object?>>[];
  SearchResult? result;
  final timeTargets = mode == 'seconds'
      ? (limit >= 120 ? [30, 120] : [limit])
      : <int>[];
  var targetIndex = 0;
  while (true) {
    final targetNodes = mode == 'node-budget'
        ? limit - search.visitedNodes
        : 100000;
    if (targetNodes <= 0) break;
    final budget = search.best == null
        ? (targetNodes < 100 ? targetNodes : 100)
        : (targetNodes < 10000 ? targetNodes : 10000);
    final remaining = mode == 'seconds'
        ? Duration(
            microseconds:
                (timeTargets[targetIndex] * 1000000 - watch.elapsedMicroseconds)
                    .clamp(0, 1 << 62),
          )
        : null;
    result = search.run(maxNodes: budget, timeLimit: remaining);
    if (!identical(search.best, seen) && search.best != null) {
      seen = search.best;
      final validation = const SolutionValidator().validate(
        search.problem,
        seen!,
      );
      if (!validation.isValid) {
        throw StateError('Invalid incumbent: ${validation.errors}');
      }
      if (firstMicros == null) {
        firstMicros = watch.elapsedMicroseconds;
        firstQuality = seen.clinicalQuality!.components
            .map((x) => x.toString())
            .toList();
      }
    }
    final reached =
        mode == 'seconds' &&
        watch.elapsedMicroseconds >= timeTargets[targetIndex] * 1000000;
    if (reached ||
        !result.canResume ||
        (mode == 'node-budget' && search.visitedNodes >= limit)) {
      marks.add({
        'requestedSeconds': mode == 'seconds' ? timeTargets[targetIndex] : null,
        'elapsedMicros': watch.elapsedMicroseconds,
        'visitedNodes': search.visitedNodes,
        'nodesPerSecond':
            search.visitedNodes *
            1000000 ~/
            watch.elapsedMicroseconds.clamp(1, 1 << 62),
        'status': result.status.name,
        'pauseReason': result.pauseReason?.name,
        'firstMicrosUpperBound': firstMicros,
        'firstQuality': firstQuality,
        'lastQuality': search.best?.clinicalQuality?.components
            .map((x) => x.toString())
            .toList(),
        'incumbentImprovements': search.incumbentImprovements,
        'stage': 'A',
        'optimalityProven': result.status == SearchStatus.optimal,
        'incumbentValidated': search.best != null,
      });
      if (!result.canResume ||
          mode == 'node-budget' ||
          ++targetIndex >= timeTargets.length) {
        break;
      }
    }
  }
  stdout.writeln(
    jsonEncode({
      'people': people,
      'days': days,
      'variant': variant,
      'mode': mode,
      'limit': limit,
      'requiredSlots': days,
      'optionalSlots': days,
      'snapshot': p.toMessage(),
      'runtime': Platform.version,
      'marks': marks,
    }),
  );
}
