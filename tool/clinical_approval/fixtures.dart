import 'dart:convert';
import 'dart:io';

import 'package:akys/solver_v2/solver.dart';
import 'package:akys/modules/schedule_v2/data/draft_snapshot.dart';

void main() {
  final p = Problem(
    startDate: DateTime.utc(2026, 11),
    doctors: [
      Doctor(id: 's', seniorityLevel: SeniorityLevel.k4),
      Doctor(id: 'j', group: DutyGroup.junior),
    ],
    slotsPerDay: [1, ...List.filled(29, 0)],
    slotRoles: [DutyRole.senior],
    slotRequirements: [SlotRequirement.required],
    dayDifficulties: List.filled(30, const DayDifficulty(weekdayScore: 3)),
  );
  final data = <String, String>{};
  for (final e in {
    'valid': [0],
    'missing': [-1],
    'transition': [1],
  }.entries) {
    data[e.key] = DraftSnapshot(
      p,
      {'s': 'Synthetic S', 'j': 'Synthetic J'},
      e.value,
      {},
    ).encode();
  }
  data['proof'] = jsonEncode({
    ...jsonDecode(data['valid']!) as Map,
    'proved': true,
  });
  final constrained = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(p.toMessage())) as Map,
  );
  (constrained['doctors'] as List).first['unavailable'] = [0];
  data['hard-constraint'] = DraftSnapshot(
    Problem.fromMessage(constrained),
    {'s': 'Synthetic S', 'j': 'Synthetic J'},
    [0],
    {},
  ).encode();
  stdout.writeln(jsonEncode(data));
}
