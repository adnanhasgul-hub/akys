import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/data/calendar/turkey_holidays.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/application/schedule_controller.dart';
import 'package:akys/modules/work_schedule/application/schedule_export.dart';
import 'package:akys/modules/work_schedule/engine/task_engine.dart';
import 'package:akys/modules/work_schedule/engine/duty_engine.dart';

import 'engine_test.dart' show sample;

ScheduleMonth workMonth(int year, int month) {
  final m = ScheduleMonth.fromJson({
    ...sample(year, month).toJson(),
    'taskWorkdaySchemaVersion': 1,
    'taskHolidayCalendarSnapshot': TurkeyHolidayCalendar.month(
      year,
      month,
    ).map((h) => h.toJson()).toList(),
  });
  for (final t in ClinicTask.values) {
    m.tasks[t] = const TaskAssignment('p1', 'p2');
  }
  return m;
}

void main() {
  test('Normal weekday assignments and conflict checks remain active', () {
    final tasks = dailyTasks(workMonth(2026, 10), 26);
    expect(tasks.length, 5);
    expect(
      tasks.every((t) => t.active && !t.halfDay && t.personId == 'p1'),
      true,
    );
    expect(tasks.every((t) => t.warnings.isNotEmpty), true);
  });
  for (final day in [24, 25, 29]) {
    test(
      'Weekend or full holiday $day suppresses primary backup manual and warnings',
      () {
        final m = workMonth(2026, 10);
        m.duties[day - 1] = ['p1', 'p2'];
        m.overrides['2026-10-$day|outpatient'] = TaskOverride(
          '2026-10-$day',
          ClinicTask.outpatient,
          'p1',
        );
        final tasks = dailyTasks(m, day);
        expect(tasks.length, 5);
        expect(
          tasks.every(
            (t) =>
                !t.active &&
                t.personId == null &&
                !t.backup &&
                !t.manual &&
                t.warnings.isEmpty,
          ),
          true,
        );
        expect((publicProjection(m)['dailyTasks'] as Map)['$day'], isEmpty);
      },
    );
  }
  test('Half holiday weekday keeps assignments only before 13:00 and backup still works', () {
    final m = workMonth(2026, 10)..duties[27] = ['p1'];
    final tasks = dailyTasks(m, 28);
    expect(
      tasks.every(
        (t) => t.active && t.halfDay && t.backup && t.personId == 'p2',
      ),
      true,
    );
    expect(
      (publicProjection(m)['dailyTasks'] as Map)['28'][0]['halfDay'],
      true,
    );
    final ics = utf8.decode(personalIcs(m, 'p2'));
    expect(ics, contains('13.00 öncesi'));
  });
  test('Half holiday on weekend remains inactive', () {
    expect(dailyTasks(workMonth(2028, 10), 28).every((t) => !t.active), true);
  });
  test(
    'Legacy month retains old behavior, roundtrip keeps new policy frozen',
    () {
      final old = sample(2026, 10);
      expect(dailyTasks(old, 29).every((t) => t.active), true);
      final saved = workMonth(2026, 10).clone();
      expect(saved.taskWorkdaySchemaVersion, 1);
      expect(dailyTasks(saved, 29).every((t) => !t.active), true);
    },
  );
  test('Task workday activation leaves duties, scores and duty statistics identical', () {
    final old = sample(2026, 10)..duties[29] = ['p1'];
    final before = statistics(old)['p1']!;
    final next = ScheduleMonth.fromJson({
      ...old.toJson(),
      'taskWorkdaySchemaVersion': 1,
      'taskHolidayCalendarSnapshot': TurkeyHolidayCalendar.month(
        2026,
        10,
      ).map((h) => h.toJson()).toList(),
    });
    expect(next.duties, old.duties);
    expect(
      [for (var d = 1; d <= old.days; d++) next.difficultyScore(d)],
      [for (var d = 1; d <= old.days; d++) old.difficultyScore(d)],
    );
    expect(statistics(next)['p1']!.totalDifficulty, before.totalDifficulty);
    expect(statistics(next)['p1']!.total, before.total);
  });
  test('Explicit legacy draft activation persists without touching duty snapshot, rejects repeat and stale update', () async {
    final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
    final old = await repo.saveMonth(sample(2026, 10), create: true);
    final c = ScheduleController(repo);
    addTearDown(c.dispose);
    await c.initialize();
    await pumpEventQueue();
    c.select(old.id);
    expect(await c.applyTaskWorkdays(), true);
    final saved = (await repo.loadMonth(old.id))!;
    expect(saved.revision, old.revision + 1);
    expect(saved.taskWorkdaySchemaVersion, 1);
    expect(saved.duties, old.duties);
    expect(saved.difficultySchemaVersion, old.difficultySchemaVersion);
    expect(await c.applyTaskWorkdays(), false);
    await expectLater(repo.saveMonth(old), throwsA(isA<ScheduleConflict>()));
  });
  test('New months automatically snapshot workdays and later calendar changes cannot mutate them', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreScheduleRepository(db);
    final c = ScheduleController(repo);
    addTearDown(c.dispose);
    await c.initialize();
    await pumpEventQueue();
    expect(await c.createMonth(2026, 11, 54), true);
    final saved = (await repo.loadMonth('2026-11'))!;
    expect(saved.taskWorkdaySchemaVersion, 1);
    expect(dailyTasks(saved, 1).every((t) => !t.active), true);
    final changed = ScheduleMonth.fromJson({
      ...saved.toJson(),
      'taskHolidayCalendarSnapshot': TurkeyHolidayCalendar.month(
        2026,
        10,
      ).map((h) => h.toJson()).toList(),
    });
    await expectLater(
      repo.saveMonth(changed),
      throwsA(isA<ScheduleConflict>()),
    );
  });
  test('Final month cannot activate the workday policy', () async {
    final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
    final old = await repo.saveMonth(sample(2026, 10), create: true);
    final frozen = old.toJson()..['status'] = 'finalised';
    // Simulates an already-final production document without generating duties.
    await repo.db.doc('work_schedule/main/months/2026-10').set(frozen);
    final next = ScheduleMonth.fromJson({
      ...frozen,
      'taskWorkdaySchemaVersion': 1,
      'taskHolidayCalendarSnapshot': TurkeyHolidayCalendar.month(
        2026,
        10,
      ).map((h) => h.toJson()).toList(),
    });
    await expectLater(repo.saveMonth(next), throwsA(isA<ScheduleConflict>()));
  });
}
