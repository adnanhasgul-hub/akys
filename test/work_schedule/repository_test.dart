import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/application/schedule_controller.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/engine/duty_engine.dart';

import 'engine_test.dart' show sample;

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreScheduleRepository repo;
  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreScheduleRepository(db);
  });
  test('Firestore seed is idempotent and uses stable non-name IDs', () async {
    await repo.initialize();
    await pumpEventQueue();
    await repo.initialize();
    await pumpEventQueue();
    final people = await repo.watchPersonnel().first;
    expect(people.length, 7);
    expect(
      (await db.collection('work_schedule/main/personnel').get()).docs.length,
      7,
    );
    expect(people.first.displayName, initialNames.first);
    expect(people.first.id, isNot(contains('Adnan')));
  });
  test(
    'Existing collection is preserved when registry is first created',
    () async {
      final p = Personnel(
        id: 'existing',
        displayName: 'Dr. Existing',
        seniorityRank: 5,
        createdAt: 'now',
        updatedAt: 'now',
      );
      await db.doc('work_schedule/main/personnel/existing').set(p.toJson());
      await repo.initialize();
      await pumpEventQueue();
      expect((await repo.watchPersonnel().first).single.id, 'existing');
    },
  );
  test(
    'Rank transaction and stale write protection; no physical deletion',
    () async {
      await repo.initialize();
      await pumpEventQueue();
      final before = await repo.watchPersonnel().first;
      final after = before.reversed.toList();
      await pumpEventQueue();
      await repo.replacePersonnel(before, after);
      await pumpEventQueue();
      final read = await repo.watchPersonnel().first;
      expect(read.map((p) => p.seniorityRank), [1, 2, 3, 4, 5, 6, 7]);
      expect(read.first.id, before.last.id);
      await expectLater(
        repo.replacePersonnel(before, before),
        throwsA(isA<ScheduleConflict>()),
      );
      await expectLater(
        repo.replacePersonnel(read, read.skip(1).toList()),
        throwsA(isA<ScheduleConflict>()),
      );
      await pumpEventQueue();
      await repo.replacePersonnel(read, [
        read.first.copy(active: false),
        ...read.skip(1),
      ]);
      await pumpEventQueue();
      expect((await repo.watchPersonnel().first).first.active, false);
    },
  );
  test(
    'Month persistence preserves snapshots and rejects stale/locked edits',
    () async {
      var m = await repo.saveMonth(sample(2026, 11), create: true);
      await expectLater(
        repo.saveMonth(sample(2026, 11), create: true),
        throwsA(isA<ScheduleConflict>()),
      );
      final stale = m.clone();
      m.constraints['p1']!.cannot.add(2);
      m = await repo.saveMonth(m);
      expect(
        (await repo.loadMonth(m.id))!.constraints['p1']!.cannot,
        contains(2),
      );
      await expectLater(
        repo.saveMonth(stale),
        throwsA(isA<ScheduleConflict>()),
      );
      final changed = m.clone();
      changed.people[0] = const PersonSnapshot('p1', 'Changed', 9);
      await expectLater(
        repo.saveMonth(changed),
        throwsA(isA<ScheduleConflict>()),
      );
      m = const DutyEngine().generate(m).month!;
      m.status = MonthStatus.finalised;
      m = await repo.saveMonth(m);
      final invalid = m.clone();
      invalid.duties.clear();
      await expectLater(
        repo.saveMonth(invalid),
        throwsA(isA<ScheduleConflict>()),
      );
      expect((await repo.loadMonth(m.id))!.people.first.displayName, 'Dr. 1');
    },
  );
  test('Share projection and revoke/reopen lifecycle is atomic at repository boundary', () async {
    var m = const DutyEngine().generate(sample(2026, 11)).month!
      ..status = MonthStatus.finalised;
    m = await repo.saveMonth(m, create: true);
    final token = await repo.share(m);
    expect(token, matches(RegExp(r'^[a-f0-9]{48}$')));
    final projection = (await db.doc('shared_schedules/$token').get()).data()!;
    expect(projection.containsKey('constraints'), false);
    m = (await repo.loadMonth(m.id))!;
    expect(m.status, MonthStatus.published);
    await repo.revoke(m, token);
    expect(
      (await db.doc('shared_schedules/$token').get()).data()!['revoked'],
      true,
    );
    m = (await repo.loadMonth(m.id))!;
    final token2 = await repo.share(m);
    expect(token2, isNot(token));
    m = (await repo.loadMonth(m.id))!..status = MonthStatus.draft;
    m = await repo.saveMonth(m);
    expect(
      (await db.doc('shared_schedules/$token2').get()).data()!['revoked'],
      true,
    );
    expect(m.shareTokens, isEmpty);
    await expectLater(repo.share(m), throwsA(isA<ScheduleConflict>()));
  });
  test(
    'Controller freezes active personnel and imports previous month boundary',
    () async {
      await repo.initialize();
      await pumpEventQueue();
      final people = await repo.watchPersonnel().first;
      final previous = ScheduleMonth(
        year: 2026,
        month: 10,
        people: [
          for (final p in people)
            PersonSnapshot(p.id, p.displayName, p.seniorityRank),
        ],
        createdAt: 'now',
        updatedAt: 'now',
      );
      previous.duties[31] = [people.first.id];
      await repo.saveMonth(previous, create: true);
      await pumpEventQueue();
      await repo.replacePersonnel(people, [
        ...people.take(6),
        people.last.copy(active: false),
      ]);
      final c = ScheduleController(repo);
      addTearDown(c.dispose);
      await c.initialize();
      await pumpEventQueue();
      expect(c.personnel.length, 7);
      expect(await c.createMonth(2026, 11, 48), true);
      expect(c.month!.people.length, 6);
      expect(c.month!.boundaryConfirmed, true);
      expect(c.month!.boundary[people.first.id], ['2026-10-31']);
      final now = await repo.watchPersonnel().first;
      await pumpEventQueue();
      await repo.replacePersonnel(now, now.reversed.toList());
      expect(c.month!.people.first.seniorityRank, 1);
    },
  );
  test('Generation requires explicit manual boundary confirmation', () async {
    final c = ScheduleController(repo);
    addTearDown(c.dispose);
    await c.initialize();
    await pumpEventQueue();
    await c.createMonth(2026, 11, 56);
    expect(await c.generate(), false);
    expect(c.error, contains('sınır'));
    final confirmed = c.month!.clone()..boundaryConfirmed = true;
    await c.save(confirmed);
    expect(await c.generate(), true);
    expect(validateDuties(c.month!), isEmpty);
  });
}
