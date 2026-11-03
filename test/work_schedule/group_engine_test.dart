import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/engine/duty_engine.dart';

import 'engine_test.dart' show sample;

/// A full-month hard-valid fixture in which everyone except one junior has
/// fixed dates. The junior has exactly two feasible alternatives, one beside
/// K2 and the other beside K4. Seniors cannot move or swap to satisfy the test.
(ScheduleMonth, int, int, String) criticalFixture() {
  final base = const DutyEngine().generate(sample(2026, 11, total: 54)).month!;
  for (final a in base.duties.entries) {
    if (a.value.length != 2 || !a.value.contains('p2')) continue;
    final junior = a.value.firstWhere((id) => id != 'p2');
    if (base.person(junior).dutySeniorityGroup != DutySeniorityGroup.junior) {
      continue;
    }
    for (final b in base.duties.entries) {
      if (b.value.length != 1 || b.value.single != 'p4') continue;
      final bad = base.clone();
      bad.duties[a.key]!.remove(junior);
      bad.duties[b.key]!.add(junior);
      if (validateDuties(bad).isNotEmpty) continue;
      for (final p in bad.people) {
        final dates = bad.duties.entries
            .where((e) => e.value.contains(p.personId))
            .map((e) => e.key)
            .toSet();
        bad.constraints[p.personId] = PersonalConstraints(
          must: p.personId == junior ? ({...dates}..remove(b.key)) : dates,
          cannot: List.generate(bad.days, (i) => i + 1)
              .where(
                (d) =>
                    !dates.contains(d) && !(p.personId == junior && d == a.key),
              )
              .toSet(),
        );
      }
      return (bad, a.key, b.key, junior);
    }
  }
  throw StateError(
    'No full-month K2/K4 equivalent hard-valid alternatives found.',
  );
}

void main() {
  test(
    'Seed groups are explicit; rank changes and renaming never change group',
    () {
      final people = seedPersonnel([], 'now');
      expect(people.map((p) => p.dutySeniorityGroup), [
        ...List.filled(4, DutySeniorityGroup.senior),
        ...List.filled(3, DutySeniorityGroup.junior),
      ]);
      final k6 = people[5].copy(dutySeniorityGroup: DutySeniorityGroup.senior);
      expect(k6.seniorityRank, 6);
      final changed = k6.copy(rank: 1, name: 'Unrelated name');
      expect(changed.dutySeniorityGroup, DutySeniorityGroup.senior);
      final reordered = reorderPersonnel(
        people,
        people.reversed.map((p) => p.id).toList(),
      );
      expect(reordered.first.seniorityRank, 1);
      expect(reordered.first.dutySeniorityGroup, DutySeniorityGroup.junior);
    },
  );
  test(
    'Explicit groups take precedence over rank for two-person composition',
    () {
      final m = sample(2026, 11);
      m.people[0] = const PersonSnapshot(
        'p1',
        'Any name',
        1,
        dutySeniorityGroup: DutySeniorityGroup.junior,
      );
      m.people[5] = const PersonSnapshot(
        'p6',
        'Another name',
        6,
        dutySeniorityGroup: DutySeniorityGroup.senior,
      );
      expect(preferredDutyComposition(m, ['p1', 'p6']), true);
      expect(preferredDutyComposition(m, ['p1', 'p5']), false);
    },
  );
  test('Senior+junior is strongly preferred to homogeneous pairings', () {
    final mixed = sample(2026, 11)
      ..duties.addAll({
        2: ['p1', 'p5'],
        9: ['p2', 'p6'],
      });
    final homogeneous = mixed.clone();
    homogeneous.duties[2] = ['p1', 'p2'];
    homogeneous.duties[9] = ['p5', 'p6'];
    expect(compareScore(objective(mixed), objective(homogeneous)), lessThan(0));
  });
  test('Engine moves junior from fixed K4 to fixed K2 without changing load or staffing needs', () {
    final (bad, highDay, lowDay, junior) = criticalFixture();
    expect(validateDuties(bad), isEmpty);
    expect(bad.duties[highDay], ['p2']);
    expect(bad.duties[lowDay], containsAll(['p4', junior]));
    final original = jsonEncode(bad.toJson());
    final before = statistics(bad);
    final optimized = const DutyEngine().optimize(bad).month!;
    expect(validateDuties(optimized), isEmpty);
    expect(optimized.duties[highDay], containsAll(['p2', junior]));
    expect(optimized.duties[lowDay], ['p4']);
    for (final p in bad.people) {
      expect(
        statistics(optimized)[p.personId]!.total,
        before[p.personId]!.total,
      );
    }
    expect(
      objective(optimized)[DutyObjective.staffing.index],
      objective(bad)[DutyObjective.staffing.index],
    );
    expect(jsonEncode(bad.toJson()), original);
    final generated = const DutyEngine().generate(bad);
    expect(generated.errors, isEmpty);
    expect(generated.month!.duties[highDay], contains(junior));
    expect(generated.month!.duties[lowDay], ['p4']);
    expect(
      jsonEncode(generated.month!.toJson()['duties']),
      jsonEncode(const DutyEngine().generate(bad).month!.toJson()['duties']),
    );
  });
  for (final group in DutySeniorityGroup.values) {
    test(
      'Homogeneous ${group.name} remains hard-feasible, with soft warnings',
      () {
        final m = sample(2026, 11);
        for (var i = 0; i < m.people.length; i++) {
          final p = m.people[i];
          m.people[i] = PersonSnapshot(
            p.personId,
            p.displayName,
            p.seniorityRank,
            dutySeniorityGroup: group,
          );
        }
        final r = const DutyEngine().generate(m);
        expect(r.errors, isEmpty);
        expect(validateDuties(r.month!), isEmpty);
        final day = r.month!.duties.entries
            .firstWhere((e) => e.value.length == 2)
            .key;
        expect(compositionWarning(r.month!, day), contains('sağlanamadı'));
      },
    );
  }
  test('Statistics distinguish solo, paired and companion-junior counts', () {
    final m = sample(2026, 11)
      ..duties.addAll({
        1: ['p2'],
        4: ['p2', 'p5'],
        7: ['p2', 'p4'],
        10: ['p5', 'p6'],
      });
    final s = statistics(m);
    expect(s['p2']!.total, 3);
    expect(s['p2']!.solo, 1);
    expect(s['p2']!.paired, 2);
    expect(s['p2']!.withJunior, 1);
    expect(s['p5']!.withJunior, 1);
    expect(compositionWarning(m, 7), isNotNull);
  });
}
