import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/engine/duty_engine.dart';

import 'engine_test.dart' show sample;

void main() {
  test('Equivalent totals favor lower duty count for the senior', () {
    final a = sample(2026, 11);
    a.duties.addAll({
      1: ['p2'],
      4: ['p2'],
      7: ['p1'],
    });
    final b = a.clone()..duties.clear();
    b.duties.addAll({
      1: ['p1'],
      4: ['p1'],
      7: ['p2'],
    });
    expect(compareScore(objective(a), objective(b)), lessThan(0));
  });
  for (final weekday in [4, 5, 6, 7]) {
    test('Category seniority preference weekday $weekday', () {
      final a = sample(2026, 11);
      final day = List.generate(
        a.days,
        (i) => i + 1,
      ).firstWhere((d) => a.date(d).weekday == weekday);
      final other = List.generate(
        a.days,
        (i) => i + 1,
      ).firstWhere((d) => a.date(d).weekday == 2);
      a.duties.addAll({
        day: [weekday == 4 ? 'p1' : 'p2'],
        other: [weekday == 4 ? 'p2' : 'p1'],
      });
      final b = a.clone();
      b.duties[day] = [weekday == 4 ? 'p2' : 'p1'];
      b.duties[other] = [weekday == 4 ? 'p1' : 'p2'];
      expect(compareScore(objective(a), objective(b)), lessThan(0));
    });
  }
  for (var category = 0; category < 5; category++) {
    test('Category $category balances independent counts', () {
      final a = sample(2026, 11);
      final days = List.generate(
        a.days,
        (i) => i + 1,
      ).where((d) => dayCategory(a.date(d)) == category).take(2).toList();
      final others = List.generate(
        a.days,
        (i) => i + 1,
      ).where((d) => dayCategory(a.date(d)) != category).take(2).toList();
      a.duties.addAll({
        days[0]: ['p1'],
        days[1]: ['p2'],
        others[0]: ['p1'],
        others[1]: ['p2'],
      });
      final b = a.clone();
      b.duties[days[1]] = ['p1'];
      b.duties[others[0]] = ['p2'];
      expect(
        objective(a)[DutyObjective.totalFairness.index],
        objective(b)[DutyObjective.totalFairness.index],
      );
      expect(
        objective(a)[DutyObjective.categoryFairness.index],
        lessThan(objective(b)[DutyObjective.categoryFairness.index]),
      );
    });
  }
  test('Thu to Sun penalty rejects same-week pairing at equal categories', () {
    final a = sample(2026, 11);
    a.duties.addAll({
      5: ['p1'],
      8: ['p2'],
      12: ['p2'],
      15: ['p1'],
    });
    final b = a.clone();
    b.duties[8] = ['p1'];
    b.duties[15] = ['p2'];
    expect(
      objective(a).take(DutyObjective.thuSun.index),
      objective(b).take(DutyObjective.thuSun.index),
    );
    expect(compareScore(objective(a), objective(b)), lessThan(0));
  });
  test('Second person prefers a senior duty partner', () {
    final a = sample(2026, 11, count: 9);
    a.duties.addAll({
      2: ['p1', 'p9'],
      9: ['p2'],
    });
    final b = a.clone();
    b.duties[2] = ['p1'];
    b.duties[9] = ['p2', 'p9'];
    expect(compareScore(objective(a), objective(b)), lessThan(0));
  });
  test('K1+K5 versus K2+K6: third K9 chooses day A', () {
    final a = sample(2026, 11, count: 9);
    a.duties.addAll({
      2: ['p1', 'p5', 'p9'],
      9: ['p2', 'p6'],
    });
    final b = a.clone();
    b.duties[2] = ['p1', 'p5'];
    b.duties[9] = ['p2', 'p6', 'p9'];
    expect(
      objective(a).take(DutyObjective.thirdPerson.index),
      objective(b).take(DutyObjective.thirdPerson.index),
    );
    expect(compareScore(objective(a), objective(b)), lessThan(0));
  });
  test('Staffing smoothness penalizes 1/3 oscillation', () {
    final a = sample(2026, 11);
    a.duties.addAll({
      2: ['p1', 'p2'],
      9: ['p3', 'p4'],
    });
    final b = a.clone();
    b.duties[2] = ['p1'];
    b.duties[9] = ['p2', 'p3', 'p4'];
    expect(
      objective(a)[DutyObjective.staffing.index],
      lessThan(objective(b)[DutyObjective.staffing.index]),
    );
  });
  test(
    'Seven people, 54 duties: junior never gets the equal lower-load advantage',
    () {
      final r = const DutyEngine().generate(sample(2026, 11, total: 54));
      expect(r.errors, isEmpty);
      expect(
        [
          for (final p in r.month!.people)
            statistics(r.month!)[p.personId]!.total,
        ],
        [7, 7, 8, 8, 8, 8, 8],
      );
    },
  );
  test('Nine people require and receive three-person days', () {
    final r = const DutyEngine().generate(sample(2026, 12, count: 9));
    expect(r.errors, isEmpty, reason: r.errors.join(';'));
    expect(r.month!.duties.values.any((v) => v.length == 3), true);
    expect(validateDuties(r.month!), isEmpty);
  });
  test('Three fixed people on one day are not rejected', () {
    final m = sample(2026, 11);
    for (final id in ['p1', 'p2', 'p3']) {
      m.constraints[id] = PersonalConstraints(must: {5});
    }
    final r = const DutyEngine().generate(m);
    expect(r.errors, isEmpty);
    expect(r.month!.duties[5]!.length, 3);
    expect(validateDuties(r.month!), isEmpty);
  });
  test(
    'Manual edits validate, record provenance and recalculate statistics',
    () {
      final m = const DutyEngine().generate(sample(2026, 11)).month!;
      ScheduleMonth? edited;
      int? target;
      String? who;
      search:
      for (final e in m.duties.entries) {
        for (final id in e.value) {
          for (var d = 1; d <= m.days; d++) {
            if (d == e.key) continue;
            try {
              edited = editDuty(m, e.key, d, id);
              target = d;
              who = id;
              break search;
            } on StateError {
              /* Continue searching for a feasible move. */
            }
          }
        }
      }
      expect(edited, isNotNull);
      expect(validateDuties(edited!), isEmpty);
      expect(edited.manuallyEdited, contains(target));
      expect(statistics(edited)[who]!.total, statistics(m)[who]!.total);
      final block = m.clone();
      block.constraints[who]!.cannot.add(target!);
      final from = block.duties.entries
          .firstWhere((e) => e.value.contains(who) && e.key != target)
          .key;
      expect(() => editDuty(block, from, target!, who!), throwsStateError);
      final finalMonth = m.clone()..status = MonthStatus.finalised;
      expect(() => editDuty(finalMonth, 1, 5, 'p1'), throwsStateError);
    },
  );
  test('Invariant checker catches max8, spacing and forbidden assignments', () {
    final m = sample(2026, 11);
    m.duties.addAll({
      for (var d = 1; d <= 9; d++) d: ['p1'],
    });
    m.constraints['p1']!.cannot.add(5);
    final errors = validateDuties(m);
    expect(errors.any((s) => s.contains('sekiz')), true);
    expect(errors.any((s) => s.contains('üç gün')), true);
    expect(errors.any((s) => s.contains('Tutamaz')), true);
  });
  test(
    'Staffing may relax balanced templates to preserve hard feasibility',
    () {
      final m = sample(2026, 11);
      for (final p in m.people) {
        if (p.personId != 'p1') m.constraints[p.personId]!.cannot.add(1);
        if (p.personId != 'p2') m.constraints[p.personId]!.cannot.add(2);
      }
      final r = const DutyEngine(nodeLimit: 50000).generate(m);
      expect(r.errors, isEmpty, reason: r.errors.join(';'));
      expect(validateDuties(r.month!), isEmpty);
      expect(r.month!.duties[1], ['p1']);
      expect(r.month!.duties[2], ['p2']);
    },
  );
  test('No-solution and bounded search are distinct', () {
    final m = sample(2026, 11);
    for (final c in m.constraints.values) {
      c.cannot.addAll(List.generate(30, (i) => i + 1));
    }
    expect(const DutyEngine().generate(m).month, isNull);
    final limited = const DutyEngine(nodeLimit: 1).generate(sample(2026, 11));
    expect(limited.searchLimited, true);
    expect(limited.errors.single, contains('kanıtı değildir'));
  });
}
