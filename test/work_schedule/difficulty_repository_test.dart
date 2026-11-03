import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/domain/difficulty.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/application/schedule_controller.dart';

import 'difficulty_test.dart' show scoring;
import 'engine_test.dart' show sample;

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreScheduleRepository repo;
  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreScheduleRepository(db);
  });
  test(
    'Admin configuration persistence and stale revision protection',
    () async {
      final defaults = await repo.loadDifficultySettings();
      expect(defaults.weekdayScores, [3, 3, 3, 1, 6, 9, 5]);
      final changed = DifficultySettings(
        weekdayScores: [4, 4, 4, 2, 7, 10, 6],
        preHolidayDifficultyScore: 8,
      );
      final saved = await repo.saveDifficultySettings(defaults, changed);
      await pumpEventQueue();
      expect(saved.revision, 1);
      expect(
        (await repo.loadDifficultySettings()).weekdayScores,
        changed.weekdayScores,
      );
      expect(
        (await db.doc('work_schedule/main/settings/difficulty').get())
            .data()!['preHolidayDifficultyScore'],
        8,
      );
      await expectLater(
        repo.saveDifficultySettings(defaults, changed),
        throwsA(isA<ScheduleConflict>()),
      );
    },
  );
  test(
    'New months take live settings; existing month snapshots remain frozen',
    () async {
      final c = ScheduleController(repo);
      addTearDown(c.dispose);
      await c.initialize();
      await pumpEventQueue();
      expect(await c.createMonth(2026, 11, 54), true);
      await pumpEventQueue();
      final old = (await repo.loadMonth('2026-11'))!;
      expect(old.difficultySchemaVersion, 1);
      expect(old.difficultyScore(5), 1);
      final frozen = canonical(old.toJson());
      await c.saveDifficulty(
        DifficultySettings(
          weekdayScores: [4, 4, 4, 10, 7, 8, 6],
          preHolidayDifficultyScore: 9,
        ),
      );
      await pumpEventQueue();
      expect(await c.createMonth(2026, 12, 54), true);
      expect(c.month!.difficultyScore(3), 10);
      expect(c.month!.difficultyScore(31), 9);
      expect(canonical((await repo.loadMonth('2026-11'))!.toJson()), frozen);
    },
  );
  test('Every holiday score persists separately, and snapshot mutations are rejected', () async {
    await repo.initialize();
    await pumpEventQueue();
    final c = ScheduleController(repo);
    addTearDown(c.dispose);
    await c.initialize();
    await pumpEventQueue();
    final snapshot = scoring(
      2026,
      3,
      overrides: {
        '2026-03-19': 1,
        '2026-03-20': 4,
        '2026-03-21': 9,
        '2026-03-22': 6,
      },
    );
    expect(await c.createMonth(2026, 3, 54, difficulty: snapshot), true);
    await pumpEventQueue();
    final saved = (await repo.loadMonth('2026-03'))!;
    expect(saved.holidayDifficultyOverrides, snapshot.overrides);
    final changed = ScheduleMonth.fromJson({
      ...saved.toJson(),
      'holidayDifficultyOverrides': {
        '2026-03-19': 8,
        '2026-03-20': 4,
        '2026-03-21': 9,
        '2026-03-22': 6,
      },
    });
    await expectLater(
      repo.saveMonth(changed),
      throwsA(isA<ScheduleConflict>()),
    );
  });
  test('Unsupported calendar or missing scores blocks writes instead of assuming no holidays', () async {
    final c = ScheduleController(repo);
    addTearDown(c.dispose);
    await c.initialize();
    await pumpEventQueue();
    expect(await c.createMonth(2040, 11, 54), false);
    expect(c.error, contains('takvim'));
    expect(await repo.loadMonth('2040-11'), isNull);
    expect(await c.createMonth(2026, 3, 54), false);
    expect(c.error, contains('puan'));
    expect(await repo.loadMonth('2026-03'), isNull);
  });
  test(
    'Settings changed while holiday popup is open rejects stale month creation',
    () async {
      final c = ScheduleController(repo);
      addTearDown(c.dispose);
      await c.initialize();
      await pumpEventQueue();
      final old = await c.prepareDifficulty(2026, 11);
      await repo.saveDifficultySettings(
        await repo.loadDifficultySettings(),
        DifficultySettings(
          weekdayScores: [4, 4, 4, 2, 7, 10, 6],
          preHolidayDifficultyScore: 7,
        ),
      );
      await pumpEventQueue();
      expect(await c.createMonth(2026, 11, 54, difficulty: old), false);
      expect(c.error, contains('ayarları değişti'));
      expect(await repo.loadMonth('2026-11'), isNull);
    },
  );
  test(
    'Legacy months read without writes or retroactive holiday assumptions',
    () async {
      final raw = sample(2026, 11).toJson()
        ..remove('difficultySchemaVersion')
        ..remove('difficultySettingsSnapshot')
        ..remove('holidayCalendarSnapshot')
        ..remove('holidayDifficultyOverrides');
      await db.doc('work_schedule/main/months/2026-11').set(raw);
      final loaded = (await repo.loadMonth('2026-11'))!;
      expect(loaded.difficultySchemaVersion, 0);
      expect(loaded.difficultyScore(5), 1);
      expect(loaded.holidayCalendarSnapshot, isEmpty);
      expect(
        canonical(
          (await db.doc('work_schedule/main/months/2026-11').get()).data(),
        ),
        canonical(raw),
      );
    },
  );
  test('Public share projection excludes settings, holiday overrides and management data', () {
    final m = ScheduleMonth.fromJson({
      ...sample(2026, 3).toJson(),
      'difficultySchemaVersion': 1,
      'difficultySettingsSnapshot': DifficultySettings.defaults().toJson(),
      'holidayCalendarSnapshot': scoring(
        2026,
        3,
      ).calendar.map((h) => h.toJson()).toList(),
      'holidayDifficultyOverrides': scoring(2026, 3).overrides,
    });
    final p = publicProjection(m);
    for (final key in [
      'difficultySettingsSnapshot',
      'holidayCalendarSnapshot',
      'holidayDifficultyOverrides',
    ]) {
      expect(p.containsKey(key), false);
    }
  });
  test('Explicit group refresh preserves V1.2 difficulty snapshot and schema version', () async {
    final c = ScheduleController(repo);
    addTearDown(c.dispose);
    await c.initialize();
    await pumpEventQueue();
    await c.createMonth(2026, 11, 54);
    await pumpEventQueue();
    final old = c.month!.clone();
    final frozen = canonical(old.difficultySettingsSnapshot!.toJson());
    await c.updatePeople([
      for (final p in c.personnel)
        if (p.seniorityRank == 1)
          p.copy(dutySeniorityGroup: DutySeniorityGroup.junior)
        else
          p,
    ]);
    await pumpEventQueue();
    final updated = await repo.refreshMonthDutyGroups(old);
    expect(updated.schemaVersion, 3);
    expect(updated.difficultySchemaVersion, 1);
    expect(canonical(updated.difficultySettingsSnapshot!.toJson()), frozen);
    expect(updated.holidayDifficultyOverrides, old.holidayDifficultyOverrides);
    expect(
      updated.person(old.people.first.personId).dutySeniorityGroup,
      DutySeniorityGroup.junior,
    );
  });
}
