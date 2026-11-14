// Separate short, sequential VM experiment; never included in unit-test startup.
import 'dart:convert';
import 'dart:io';

import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';
import 'package:akys/solver_v2/editing/reoptimization.dart';

import 'clinical_resilience.dart';

void main() {
  final small = Problem(
    startDate: DateTime.utc(2026, 11),
    doctors: [
      Doctor(id: 's0', seniorityLevel: SeniorityLevel.k1),
      Doctor(id: 's1', seniorityLevel: SeniorityLevel.k1),
      Doctor(id: 'j0', group: DutyGroup.junior),
      Doctor(id: 'j1', group: DutyGroup.junior),
    ],
    slotsPerDay: [2, 0, 0, 2],
    slotRoles: [
      DutyRole.senior,
      DutyRole.junior,
      DutyRole.senior,
      DutyRole.junior,
    ],
    slotRequirements: [
      SlotRequirement.required,
      SlotRequirement.optional,
      SlotRequirement.required,
      SlotRequirement.optional,
    ],
    dayDifficulties: List.filled(4, const DayDifficulty(weekdayScore: 3)),
  );
  final large = resilienceProblem('6-open');
  final witness = resilienceWitness(large);
  if (!const SolutionValidator().validate(large, witness).isValid) {
    throw StateError('Invalid witness');
  }
  final rows = <Map<String, Object?>>[];
  final cases = <String, (Problem, List<int>, Map<int, int>)>{
    '4-small': (small, [1, -1, 0, -1], {0: 1}),
    '6-open-unlocked': (large, witness.assignments, {}),
    '6-open-three-locks': (
      large,
      witness.assignments,
      {
        for (final slot in [0, 8, 16]) slot: witness.assignments[slot],
      },
    ),
    '6-open-all-senior-locks': (
      large,
      witness.assignments,
      {
        for (var i = 0; i < large.slotDays.length; i++)
          if (witness.assignments[i] >= 0) i: witness.assignments[i],
      },
    ),
  };
  for (var rep = 1; rep <= 3; rep++) {
    for (final entry in cases.entries) {
      final (p, ref, locks) = entry.value;
      final watch = Stopwatch()..start();
      final request = ReoptimizationRequest(p, reference: ref, locks: locks);
      final preparation = watch.elapsedMicroseconds;
      final session = ReoptimizationSession(
        request,
        candidateOrdering: true,
        earlyDeadEnds: true,
        experimentalTwoPhase: true,
        clinicalBounds: true,
      );
      ReoptimizationResult? result;
      int? first;
      List<String>? firstQuality;
      while (watch.elapsedMicroseconds < 1000000) {
        result = session.run(
          maxNodes: 1000,
          timeLimit: Duration(
            microseconds: 1000000 - watch.elapsedMicroseconds,
          ),
        );
        if (result.error != null) throw StateError(result.error!);
        if (result.best != null && first == null) {
          first = watch.elapsedMicroseconds;
          firstQuality = result.best!.clinicalQuality!.components
              .map((c) => c.toString())
              .toList();
        }
        if (result.status == SearchStatus.optimal ||
            result.status == SearchStatus.infeasible) {
          break;
        }
      }
      watch.stop();
      final r = result!;
      rows.add({
        'case': entry.key,
        'repeat': rep,
        'doctors': p.doctors.length,
        'days': p.slotsPerDay.length,
        'locks': locks.length,
        'budgetUs': 1000000,
        'preparationUs': preparation,
        'firstObservedUs': first,
        'firstQuality': firstQuality,
        'totalUs': watch.elapsedMicroseconds,
        'nodes': r.visitedNodes,
        'status': r.status?.name,
        'phase': r.phase.name,
        'restrictedVerdict': r.restrictedVerdict.name,
        'minimumChangesProven': r.minimumChangesProven,
        'quality': r.best?.clinicalQuality?.components
            .map((c) => c.toString())
            .toList(),
        'changedPositions': r.diff?.changedPositions,
        'preservedLocks': r.diff?.preservedLocks.length,
        'emptyOptional': r.diff?.emptyOptionalSlots.length,
      });
      session.cancel();
    }
  }
  final sources = [
    'lib/solver_v2/solver.dart',
    'lib/solver_v2/solution_validator.dart',
    'lib/solver_v2/editing/schedule_editor.dart',
    'lib/solver_v2/editing/reoptimization.dart',
  ];
  final hashes = Process.runSync('git', [
    'hash-object',
    ...sources,
  ]).stdout.toString().trim().split('\n');
  stdout.writeln(
    jsonEncode({
      'sourceHead': Process.runSync('git', [
        'rev-parse',
        'HEAD',
      ]).stdout.toString().trim(),
      'sourceObjects': {
        for (var i = 0; i < sources.length; i++) sources[i]: hashes[i],
      },
      'runtime': Platform.version,
      'seed': resilienceSeed,
      'rows': rows,
    }),
  );
}
