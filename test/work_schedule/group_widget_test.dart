import '../design/navigation_helper.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/presentation/schedule_page.dart';

import 'schedule_widget_test.dart' show host;

class RejectGroupWrites extends FirestoreScheduleRepository {
  RejectGroupWrites(FakeFirebaseFirestore super.db);
  @override
  Future<void> replacePersonnel(
    List<Personnel> before,
    List<Personnel> after,
  ) async {
    throw const ScheduleConflict('Kayıt reddedildi.');
  }
}

Future<void> openPeople(
  WidgetTester tester,
  ScheduleRepository repo,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(host(SchedulePage(repository: repo)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Personel').first);
  await tester.tap(find.text('Personel').first);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('person-details-initial-resident-6')),
    200,
    scrollable: activeScheduleScroll(),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('person-details-initial-resident-6')),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('duty-group-initial-resident-6')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Admin changes K6 from Çömez to Kıdemli independently of rank on desktop',
    (tester) async {
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      await openPeople(tester, repo, const Size(1400, 1000));
      final control = find.byKey(
        const ValueKey('duty-group-initial-resident-6'),
      );
      expect(
        tester.widget<DropdownButton<DutySeniorityGroup>>(control).value,
        DutySeniorityGroup.junior,
      );
      await tester.tap(control);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kıdemli').last);
      await tester.pumpAndSettle();
      final people = await tester.runAsync(() => repo.watchPersonnel().first);
      final p = people!.firstWhere((p) => p.id == 'initial-resident-6');
      expect(p.seniorityRank, 6);
      expect(p.dutySeniorityGroup, DutySeniorityGroup.senior);
      expect(
        tester.widget<DropdownButton<DutySeniorityGroup>>(control).value,
        DutySeniorityGroup.senior,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '320px group control remains usable and failed write restores persisted group',
    (tester) async {
      final repo = RejectGroupWrites(FakeFirebaseFirestore());
      await openPeople(tester, repo, const Size(320, 750));
      final control = find.byKey(
        const ValueKey('duty-group-initial-resident-6'),
      );
      await tester.tap(control);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kıdemli').last);
      await tester.pumpAndSettle();
      expect(find.text('Kayıt reddedildi.'), findsOneWidget);
      expect(
        tester.widget<DropdownButton<DutySeniorityGroup>>(control).value,
        DutySeniorityGroup.junior,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Month group refresh requires confirmation; cancel preserves snapshot and duties',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreScheduleRepository(db);
      await tester.runAsync(() async {
        await repo.initialize();
        await pumpEventQueue();
        final people = await repo.watchPersonnel().first;
        final m = ScheduleMonth(
          year: 2026,
          month: 11,
          people: [
            for (final p in people)
              PersonSnapshot(
                p.id,
                p.displayName,
                p.seniorityRank,
                dutySeniorityGroup: p.dutySeniorityGroup,
              ),
          ],
          createdAt: 'now',
          updatedAt: 'now',
        );
        m.duties[1] = [people.first.id];
        await repo.saveMonth(m, create: true);
        await pumpEventQueue();
        await repo.replacePersonnel(people, [
          for (final p in people)
            if (p.seniorityRank == 6)
              p.copy(dutySeniorityGroup: DutySeniorityGroup.senior)
            else
              p,
        ]);
        await pumpEventQueue();
      });
      await tester.pumpWidget(host(SchedulePage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026 Kasım · Taslak').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nöbet').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayın Gruplarını Güncelle'));
      await tester.pumpAndSettle();
      expect(find.textContaining('mevcut nöbetler temizlenir'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      final old = await tester.runAsync(() => repo.loadMonth('2026-11'));
      expect(old!.people[5].dutySeniorityGroup, DutySeniorityGroup.junior);
      expect(old.duties, isNotEmpty);
      await tester.tap(find.text('Ayın Gruplarını Güncelle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Onayla'));
      await tester.pumpAndSettle();
      final refreshed = await tester.runAsync(() => repo.loadMonth('2026-11'));
      expect(
        refreshed!.people[5].dutySeniorityGroup,
        DutySeniorityGroup.senior,
      );
      expect(refreshed.duties, isEmpty);
      expect(refreshed.snapshotGroupUpdates, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
