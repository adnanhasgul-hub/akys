import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/application/schedule_controller.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreScheduleRepository repo;
  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreScheduleRepository(db);
  });
  Future<List<Personnel>> ready() async {
    await repo.initialize();
    await pumpEventQueue();
    return repo.watchPersonnel().first;
  }

  test(
    'Group persists independently in registry and individual personnel docs',
    () async {
      final before = await ready();
      final k6 = before[5];
      await repo.replacePersonnel(before, [
        for (final p in before)
          if (p.id == k6.id)
            p.copy(dutySeniorityGroup: DutySeniorityGroup.senior)
          else
            p,
      ]);
      await pumpEventQueue();
      final read = await repo.watchPersonnel().first;
      expect(read[5].seniorityRank, 6);
      expect(read[5].dutySeniorityGroup, DutySeniorityGroup.senior);
      expect(
        (await db.doc('work_schedule/main/personnel/${k6.id}').get())
            .data()!['dutySeniorityGroup'],
        'senior',
      );
      await repo.replacePersonnel(read, read.reversed.toList());
      await pumpEventQueue();
      final reordered = await repo.watchPersonnel().first;
      expect(reordered.first.dutySeniorityGroup, DutySeniorityGroup.junior);
      expect(reordered[1].id, k6.id);
      expect(reordered[1].dutySeniorityGroup, DutySeniorityGroup.senior);
    },
  );
  test('Legacy migration is rank-based, persisted, idempotent and preserves explicit K6 senior', () async {
    final people = seedPersonnel([], 'now');
    final raw = [
      for (final p in people)
        {...p.toJson(), 'displayName': 'Unrelated ${p.seniorityRank}'},
    ];
    for (final p in raw) {
      p.remove('dutySeniorityGroup');
    }
    raw[5]['dutySeniorityGroup'] = 'senior';
    await db.doc('work_schedule/main').set({
      'personnel': raw,
      'preserve': 'untouched',
    });
    // Simulate a registry predating complete per-person documents.
    await repo.initialize();
    await pumpEventQueue();
    final first = (await db.doc('work_schedule/main').get()).data()!;
    expect(first['preserve'], 'untouched');
    final migrated = await repo.watchPersonnel().first;
    expect(migrated.first.dutySeniorityGroup, DutySeniorityGroup.senior);
    expect(migrated.last.dutySeniorityGroup, DutySeniorityGroup.junior);
    expect(migrated[5].dutySeniorityGroup, DutySeniorityGroup.senior);
    for (final p in migrated) {
      expect(
        (await db.doc('work_schedule/main/personnel/${p.id}').get())
            .data()!['dutySeniorityGroup'],
        p.dutySeniorityGroup.name,
      );
    }
    await repo.initialize();
    await pumpEventQueue();
    expect(
      canonical((await db.doc('work_schedule/main').get()).data()),
      canonical(first),
    );
  });
  test('Missing or unknown fields decode safely without name matching', () {
    final raw = seedPersonnel([], 'now')[5].toJson()
      ..remove('dutySeniorityGroup');
    raw['displayName'] = initialNames.first;
    expect(
      Personnel.fromJson(raw).dutySeniorityGroup,
      DutySeniorityGroup.junior,
    );
    raw['dutySeniorityGroup'] = 'future-unknown';
    expect(
      Personnel.fromJson(raw).dutySeniorityGroup,
      DutySeniorityGroup.junior,
    );
    final old = {
      'personId': 'any',
      'displayName': 'Unrelated',
      'seniorityRank': 2,
      'activeAtCreation': true,
    };
    expect(
      PersonSnapshot.fromJson(old).dutySeniorityGroup,
      DutySeniorityGroup.senior,
    );
  });
  test(
    'New month takes current group; old snapshot and duties are untouched',
    () async {
      final c = ScheduleController(repo);
      addTearDown(c.dispose);
      await c.initialize();
      await pumpEventQueue();
      await c.createMonth(2026, 11, 56);
      final old = c.month!.clone();
      old.duties[3] = [old.people.first.personId];
      await c.save(old);
      await pumpEventQueue();
      final frozen = canonical(
        (await db.doc('work_schedule/main/months/2026-11').get()).data(),
      );
      final k6 = c.personnel[5];
      await c.updatePeople([
        for (final p in c.personnel)
          if (p.id == k6.id)
            p.copy(dutySeniorityGroup: DutySeniorityGroup.senior)
          else
            p,
      ]);
      await pumpEventQueue();
      await c.createMonth(2026, 12, 56);
      expect(
        c.month!.people
            .firstWhere((p) => p.personId == k6.id)
            .dutySeniorityGroup,
        DutySeniorityGroup.senior,
      );
      final previous = (await repo.loadMonth('2026-11'))!;
      expect(
        previous.person(k6.id).dutySeniorityGroup,
        DutySeniorityGroup.junior,
      );
      expect(previous.duties[3], old.duties[3]);
      expect(
        canonical(
          (await db.doc('work_schedule/main/months/2026-11').get()).data(),
        ),
        frozen,
      );
      final attempted = previous.clone();
      attempted.people[5] = PersonSnapshot(
        k6.id,
        'Changed',
        6,
        dutySeniorityGroup: DutySeniorityGroup.senior,
      );
      await expectLater(
        repo.saveMonth(attempted),
        throwsA(isA<ScheduleConflict>()),
      );
    },
  );
  test('Legacy month load is read-only; engine provenance and snapshot group remain frozen', () async {
    final people = await ready();
    final m = ScheduleMonth(
      year: 2026,
      month: 11,
      people: [
        for (final p in people)
          PersonSnapshot(p.id, p.displayName, p.seniorityRank),
      ],
      createdAt: 'now',
      updatedAt: 'now',
    );
    final raw = m.toJson()
      ..['schemaVersion'] = 1
      ..['engineVersion'] = '1.0.0'
      ..remove('snapshotGroupUpdates');
    for (final p in raw['personnelSnapshot'] as List) {
      (p as Map).remove('dutySeniorityGroup');
    }
    await db.doc('work_schedule/main/months/2026-11').set(raw);
    final frozen = canonical(raw);
    final loaded = (await repo.loadMonth('2026-11'))!;
    expect(loaded.engineVersion, '1.0.0');
    expect(loaded.people[5].dutySeniorityGroup, DutySeniorityGroup.junior);
    await repo.replacePersonnel(people, [
      for (final p in people)
        p.copy(dutySeniorityGroup: DutySeniorityGroup.senior),
    ]);
    await pumpEventQueue();
    expect(
      (await repo.loadMonth('2026-11'))!.people[5].dutySeniorityGroup,
      DutySeniorityGroup.junior,
    );
    expect(
      canonical(
        (await db.doc('work_schedule/main/months/2026-11').get()).data(),
      ),
      frozen,
    );
  });
  test('Explicit draft group refresh is audited, clears duties, freezes name/rank, and rejects stale or locked months', () async {
    final c = ScheduleController(repo);
    addTearDown(c.dispose);
    await c.initialize();
    await pumpEventQueue();
    await c.createMonth(2026, 11, 56);
    final month = c.month!.clone();
    month.duties[5] = [month.people.first.personId];
    month.manuallyEdited.add(5);
    await c.save(month);
    await pumpEventQueue();
    final prior = c.month!.clone();
    final k6 = c.personnel[5];
    await c.updatePeople([
      for (final p in c.personnel)
        if (p.id == k6.id)
          p.copy(name: 'Renamed', dutySeniorityGroup: DutySeniorityGroup.senior)
        else
          p,
    ]);
    await pumpEventQueue();
    final changed = await repo.refreshMonthDutyGroups(prior);
    await pumpEventQueue();
    expect(changed.duties, isEmpty);
    expect(changed.manuallyEdited, isEmpty);
    expect(changed.person(k6.id).dutySeniorityGroup, DutySeniorityGroup.senior);
    expect(changed.person(k6.id).displayName, prior.person(k6.id).displayName);
    expect(changed.person(k6.id).seniorityRank, 6);
    expect(
      changed.snapshotGroupUpdates.single['before'],
      containsPair(k6.id, 'junior'),
    );
    expect(
      changed.snapshotGroupUpdates.single['after'],
      containsPair(k6.id, 'senior'),
    );
    await expectLater(
      repo.refreshMonthDutyGroups(prior),
      throwsA(isA<ScheduleConflict>()),
    );
    final raw = changed.toJson()..['status'] = 'final';
    await db.doc('work_schedule/main/months/2026-11').set(raw);
    await expectLater(
      repo.refreshMonthDutyGroups(ScheduleMonth.fromJson(raw)),
      throwsA(isA<ScheduleConflict>()),
    );
  });
  test(
    'Public projection does not expose group management or refresh history',
    () {
      final m = ScheduleMonth(
        year: 2026,
        month: 11,
        people: [
          const PersonSnapshot(
            'p',
            'Name',
            6,
            dutySeniorityGroup: DutySeniorityGroup.senior,
          ),
        ],
        createdAt: 'now',
        updatedAt: 'now',
      );
      final projection = publicProjection(m);
      expect(
        (projection['people'] as List).single,
        isNot(contains('dutySeniorityGroup')),
      );
      expect(projection, isNot(contains('snapshotGroupUpdates')));
    },
  );
}
