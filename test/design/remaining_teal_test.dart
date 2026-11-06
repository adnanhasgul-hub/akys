import 'navigation_helper.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/core/design/akys_design_system.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/domain/difficulty.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/presentation/schedule_page.dart';
import 'package:akys/modules/work_schedule/presentation/combined_day_cards.dart';
import 'package:akys/modules/work_schedule/presentation/difficulty_widgets.dart';

import '../work_schedule/engine_test.dart' show sample;
import '../work_schedule/task_workday_test.dart' show workMonth;
import '../work_schedule/schedule_widget_test.dart' show host;
import 'schedule_teal_test.dart' show viewport, themed;

void main() {
  for (final size in [(320.0, 2.0), (800.0, 1.0), (1440.0, 2.0)]) {
    testWidgets('Remaining screens ${size.$1} / ${size.$2}', (t) async {
      viewport(t, size.$1, size.$2);
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      await repo.saveMonth(sample(2026, 11), create: true);
      await t.runAsync(() async {
        await repo.initialize();
        await pumpEventQueue();
        final people = await repo.watchPersonnel().first;
        await repo.replacePersonnel(people, [
          people.first.copy(
            name: 'Dr. Çok Uzun İsimli Muhammed Örnek Hekim Soyadı',
          ),
          ...people.skip(1),
        ]);
      });
      await t.pumpWidget(host(SchedulePage(repository: repo)));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('2026 Kasım · Taslak').last);
      await t.pumpAndSettle();
      for (final section in [
        'Personel',
        'Görev Dağılımı',
        'Birleşik Görünüm',
        'Ayarlar',
      ]) {
        await navigateSchedule(t, section);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: section);
        if (section == 'Personel') {
          await t.scrollUntilVisible(
            find.byKey(const ValueKey('person-details-initial-resident-1')),
            150,
            scrollable: activeScheduleScroll(),
          );
          await t.pumpAndSettle();
          await t.tap(
            find.byKey(const ValueKey('person-details-initial-resident-1')),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
      }
    });
    testWidgets('Combined expanded day ${size.$1} / ${size.$2}', (t) async {
      viewport(t, size.$1, size.$2);
      final m = sample(2026, 11);
      m.people[0] = const PersonSnapshot(
        'p1',
        'Dr. Çok Uzun İsimli Muhammed Örnek Hekim Soyadı',
        1,
      );
      m.duties[1] = ['p1'];
      var edited = false;
      await t.pumpWidget(
        themed(
          CombinedDayCards(
            month: m,
            hardErrors: const ['Dinlenme kuralı ihlali'],
            onEdit: (d, task) => edited = true,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('2 · Pazartesi'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Görevi düzenle').first,
        150,
        scrollable: activeScheduleScroll(),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Görevi düzenle').first);
      expect(edited, isTrue);
      expect(find.text('Nöbet sonrası izin'), findsOneWidget);
      expect(
        find.text('Dr. Çok Uzun İsimli Muhammed Örnek Hekim Soyadı'),
        findsWidgets,
      );
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('Weekend has no active edit action or missing-task warnings', (
    t,
  ) async {
    final m = ScheduleMonth.fromJson({
      ...sample(2026, 11).toJson(),
      'taskWorkdaySchemaVersion': 1,
    });
    await t.pumpWidget(themed(CombinedDayCards(month: m, onEdit: (_, _) {})));
    await t.pumpAndSettle();
    await t.tap(find.text('1 · Pazar'));
    await t.pumpAndSettle();
    expect(find.text('Görevi düzenle'), findsNothing);
    expect(find.text('Görev yok (resmî iş günü değil)'), findsWidgets);
    expect(find.text('Görev karşılanamıyor'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('Settings cancel and failed save are explicit at 200 percent', (
    t,
  ) async {
    viewport(t, 320, 2);
    DifficultySettings? saved;
    await t.pumpWidget(
      MaterialApp(
        theme: ClinicalTealTheme.light,
        home: Scaffold(
          body: DifficultySettingsPanel(
            settings: DifficultySettings.defaults(),
            busy: false,
            onSave: (s) async {
              saved = s;
              return false;
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('weekday-1-3')));
    await t.pumpAndSettle();
    await t.tap(find.text('10').last);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Değişikliklerden Vazgeç'),
      180,
      scrollable: activeScheduleScroll(),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Değişikliklerden Vazgeç'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Puanlama Ayarlarını Kaydet'));
    await t.pumpAndSettle();
    await t.tap(find.text('Puanlama Ayarlarını Kaydet'));
    await t.pumpAndSettle();
    expect(saved!.weekdayScores.first, 3);
    await t.scrollUntilVisible(
      find.textContaining('Ayarlar kaydedilemedi.'),
      100,
      scrollable: activeScheduleScroll(),
    );
    expect(find.textContaining('Ayarlar kaydedilemedi.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Personnel reorder and name edit persist through existing callbacks',
    (t) async {
      viewport(t, 1440, 1);
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      await t.pumpWidget(host(SchedulePage(repository: repo)));
      await t.pumpAndSettle();
      await t.tap(find.text('Personel').first);
      await t.pumpAndSettle();
      final before = await t.runAsync(() => repo.watchPersonnel().first);
      final list = t.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      list.onReorderItem!(0, 1);
      await t.pumpAndSettle();
      final after = await t.runAsync(() => repo.watchPersonnel().first);
      expect(after![1].id, before!.first.id);
      expect(after.map((p) => p.seniorityRank), [1, 2, 3, 4, 5, 6, 7]);
      expect(after[1].dutySeniorityGroup, before.first.dutySeniorityGroup);
      await t.tap(find.byKey(ValueKey('person-details-${after.first.id}')));
      await t.pumpAndSettle();
      await t.tap(find.text('İsmi düzenle').first);
      await t.pumpAndSettle();
      await t.enterText(
        find.byType(TextFormField),
        'Dr. Çok Uzun İsimli Muhammed Örnek Hekim Soyadı',
      );
      await t.tap(find.text('Kaydet'));
      await t.pumpAndSettle();
      final edited = await t.runAsync(() => repo.watchPersonnel().first);
      expect(edited!.first.displayName, contains('Çok Uzun'));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Task assignment validation and manual override persist', (
    t,
  ) async {
    viewport(t, 1440, 1);
    final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
    await repo.saveMonth(sample(2026, 11), create: true);
    await t.pumpWidget(host(SchedulePage(repository: repo)));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('2026 Kasım · Taslak').last);
    await t.pumpAndSettle();
    await navigateSchedule(t, 'Görev Dağılımı');
    await t.pumpAndSettle();
    await expandScheduleSection(t, 'Aylık görev ayarları');
    await t.ensureVisible(find.text('Asıl / Yedek Seç').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Asıl / Yedek Seç').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();
    expect(find.text('Farklı iki personel seçin.'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    final fields = find.descendant(
      of: dialog,
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await t.tap(fields.first);
    await t.pumpAndSettle();
    await t.tap(find.text('K1 Dr. 1').last);
    await t.pumpAndSettle();
    await t.tap(fields.last);
    await t.pumpAndSettle();
    await t.tap(find.text('K2 Dr. 2').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();
    final saved = await t.runAsync(() => repo.loadMonth('2026-11'));
    expect(saved!.tasks[ClinicTask.outpatient]!.primary, 'p1');
    expect(saved.tasks[ClinicTask.outpatient]!.backup, 'p2');
    await navigateSchedule(t, 'Birleşik Görünüm');
    await t.pumpAndSettle();
    await t.tap(find.text('1 · Pazar'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Görevi düzenle').first,
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Görevi düzenle').first);
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('K3 Dr. 3').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();
    final overridden = await t.runAsync(() => repo.loadMonth('2026-11'));
    expect(overridden!.overrides['2026-11-01|outpatient']!.personId, 'p3');
    expect(t.takeException(), isNull);
  });
  for (final day in [28, 29]) {
    testWidgets('Holiday work period uses existing snapshot on October $day', (
      t,
    ) async {
      viewport(t, 320, 2);
      final m = workMonth(2026, 10);
      await t.pumpWidget(themed(CombinedDayCards(month: m, onEdit: (_, _) {})));
      await t.pumpAndSettle();
      // Select a date through the same callback exposed by the dropdown.
      t
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .onChanged!(day);
      await t.pumpAndSettle();
      await t.tap(find.text('$day · ${dayNames[m.date(day).weekday - 1]}'));
      await t.pumpAndSettle();
      if (day == 28) {
        expect(find.textContaining('13.00 öncesi'), findsWidgets);
        expect(find.text('Görevi düzenle'), findsNWidgets(5));
      } else {
        expect(find.text('Görevi düzenle'), findsNothing);
        expect(find.text('Görev karşılanamıyor'), findsNothing);
      }
      expect(t.takeException(), isNull);
    });
  }
}
