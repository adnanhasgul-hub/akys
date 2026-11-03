import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/engine/duty_engine.dart';
import 'package:akys/modules/work_schedule/engine/task_engine.dart';

ScheduleMonth sample(int year, int month, {int count = 7, int? total}) =>
    ScheduleMonth(
      year: year,
      month: month,
      people: [
        for (var i = 1; i <= count; i++) PersonSnapshot('p$i', 'Dr. $i', i),
      ],
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      requiredDuties: total,
    );
void main() {
  test(
    'Seed is idempotent; reorder is contiguous and preserves active flags',
    () {
      final seed = seedPersonnel([], 'now');
      expect(seed.length, 7);
      expect(seedPersonnel(seed, 'later'), same(seed));
      final r = reorderPersonnel([
        seed.first.copy(active: false),
        ...seed.skip(1),
      ], seed.reversed.map((p) => p.id).toList());
      expect(r.map((p) => p.seniorityRank), [1, 2, 3, 4, 5, 6, 7]);
      expect(r.last.active, false);
      expect(() => reorderPersonnel(seed, ['bad']), throwsArgumentError);
    },
  );
  for (final ym in [(2026, 2), (2026, 11), (2026, 12)]) {
    test('Full-month ${ym.$1}-${ym.$2}: valid, balanced, deterministic', () {
      final m = sample(ym.$1, ym.$2);
      final r = const DutyEngine().generate(m);
      expect(r.errors, isEmpty, reason: r.errors.join(';'));
      expect(validateDuties(r.month!), isEmpty);
      expect(statistics(r.month!).values.every((s) => s.total <= 8), true);
      expect(
        jsonEncode(const DutyEngine().generate(m).month!.toJson()),
        jsonEncode(r.month!.toJson()),
      );
    });
  }
  test('Cannot, must and previous-month boundary survive generation', () {
    final m = sample(2026, 11);
    m.constraints['p1'] = PersonalConstraints(cannot: {1, 2}, must: {5});
    m.boundary['p2'] = ['2026-10-31'];
    final r = const DutyEngine().generate(m);
    expect(r.errors, isEmpty);
    expect(r.month!.duties[5], contains('p1'));
    expect(r.month!.duties[1], isNot(contains('p2')));
    expect(validateDuties(r.month!), isEmpty);
  });
  test(
    'Fixed conflicts, >8, cannot/must, boundary and impossible capacity reject',
    () {
      for (final c in [
        PersonalConstraints(must: {1, 2}),
        PersonalConstraints(must: {1}, cannot: {1}),
        PersonalConstraints(must: {1, 4, 7, 10, 13, 16, 19, 22, 25}),
      ]) {
        final m = sample(2026, 11);
        m.constraints['p1'] = c;
        expect(const DutyEngine().generate(m).month, isNull);
      }
      final m = sample(2026, 11)..boundary['p1'] = ['2026-10-31'];
      m.constraints['p1'] = PersonalConstraints(must: {1});
      expect(const DutyEngine().generate(m).month, isNull);
      expect(
        const DutyEngine().generate(sample(2026, 11, count: 2)).month,
        isNull,
      );
    },
  );
  test('Month round trip freezes historical snapshot', () {
    final m = sample(2026, 11);
    expect(jsonEncode(m.clone().toJson()), jsonEncode(m.toJson()));
    expect(m.clone().people.first.seniorityRank, 1);
  });
  test('Primary, backup, return, unavailable, overrides and collisions', () {
    final m = sample(2026, 11);
    m.tasks[ClinicTask.outpatient] = const TaskAssignment('p1', 'p2');
    m.duties[1] = ['p1'];
    expect(dailyTasks(m, 1).first.personId, 'p1');
    expect(dailyTasks(m, 2).first.personId, 'p2');
    expect(dailyTasks(m, 3).first.personId, 'p1');
    m.duties[1] = ['p1', 'p2'];
    expect(dailyTasks(m, 2).first.personId, isNull);
    final o = TaskOverride('2026-11-02', ClinicTask.outpatient, 'p3');
    m.overrides[o.key] = o;
    m.tasks[ClinicTask.ward] = const TaskAssignment('p3', 'p4');
    expect(dailyTasks(m, 2).first.manual, true);
    expect(dailyTasks(m, 2).first.warnings, isNotEmpty);
  });
}
