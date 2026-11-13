// Stage 1.6 fixtures only. No solver behavior changes.
import 'package:akys/solver_v2/solver.dart';

import 'quality_trace.dart' as prior;

const resilienceSeed = 160600;
const resilienceCases = [
  '6-open',
  '10-open',
  '15-open',
  '20-open',
  '6-tight',
  '10-tight',
  '15-tight',
  '20-tight',
  '6-transition',
  '10-capacity',
  '15-blocked',
  '20-conflict',
];

Problem resilienceProblem(String name) {
  final parts = name.split('-');
  final n = int.parse(parts[0]), kind = parts[1];
  final days = n < 15 ? 30 : 31;
  final source = prior.traceScenario(n, days, n == 15 ? 'surplus' : 'mixed');
  final message = source.toMessage();
  final doctors = message['doctors'] as List;
  for (var i = 0; i < n; i++) {
    final d = doctors[i] as Map;
    // Vary K-level concentrations independently from identity and rank.
    if (d['group'] == 'senior') d['seniorityLevel'] = i < 3 ? 'k1' : 'k4';
    if (kind == 'open') {
      // End-of-month restrictions retain the explicit senior witness.
      final blocked = {...(d['unavailable'] as List).cast<int>()};
      for (var day = days - 7; day < days; day++) {
        if ((day + i + resilienceSeed) % 3 == 0 &&
            (i >= 4 || [3, 1, 2, 0][day % 4] != i)) {
          blocked.add(day);
        }
      }
      d['unavailable'] = blocked.toList()..sort();
      continue;
    }
    if (kind == 'tight' || kind == 'transition') {
      final assigned = [
        for (var day = 0; day < days; day++)
          if ([3, 1, 2, 0][day % 4] == i) day,
      ];
      d['must'] = assigned;
      d['unavailable'] = [
        for (var day = 0; day < days; day++)
          if (!assigned.contains(day)) day,
      ];
      d['maxDuties'] = assigned.length;
      if (kind == 'transition' && i == 3) {
        d['group'] = 'junior';
        d.remove('seniorityLevel');
      }
    }
    if (kind == 'capacity') {
      d['maxDuties'] = 0;
      d['must'] = <int>[];
    }
    if (kind == 'blocked') {
      d['unavailable'] = {
        ...(d['unavailable'] as List).cast<int>(),
        days - 1,
      }.toList();
    }
    if (kind == 'conflict' && i == 0) {
      d['must'] = [3];
      d['unavailable'] = [3];
    }
  }
  return Problem.fromMessage(message);
}

Solution resilienceWitness(Problem p) => prior.witness(p);
