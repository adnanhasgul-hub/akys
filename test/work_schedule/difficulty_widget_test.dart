import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/modules/work_schedule/presentation/difficulty_widgets.dart';
import 'package:akys/modules/work_schedule/domain/difficulty.dart';
import 'package:akys/modules/work_schedule/data/calendar/turkey_holidays.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/presentation/schedule_page.dart';

import 'schedule_widget_test.dart' show host;

void main() {
  testWidgets('No-holiday month returns immediately without popup', (
    tester,
  ) async {
    Map<String, int>? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await chooseHolidayScores(
                context,
                TurkeyHolidayCalendar.month(2026, 11),
              );
            },
            child: const Text('Başlat'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Başlat'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, isEmpty);
  });
  testWidgets(
    'Holiday popup requires every score, accepts distinct daily scores and half-day labels',
    (tester) async {
      Map<String, int>? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await chooseHolidayScores(
                  context,
                  TurkeyHolidayCalendar.month(2026, 3),
                );
              },
              child: const Text('Başlat'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Başlat'));
      await tester.pumpAndSettle();
      expect(find.text('Resmî Tatil Nöbet Puanları'), findsOneWidget);
      expect(find.textContaining('Yarım gün'), findsOneWidget);
      final button = find.widgetWithText(
        FilledButton,
        'Puanları Onayla ve Ayı Oluştur',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      for (var d = 19; d <= 22; d++) {
        final field = find.byKey(ValueKey('holiday-score-2026-03-$d'));
        await tester.scrollUntilVisible(
          field,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text('${d - 18}').last);
        await tester.pumpAndSettle();
      }
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(result, {
        '2026-03-19': 1,
        '2026-03-20': 2,
        '2026-03-21': 3,
        '2026-03-22': 4,
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Cancelling holiday popup returns no approval', (tester) async {
    var completed = false;
    Map<String, int>? result = {'unexpected': 1};
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await chooseHolidayScores(
                context,
                TurkeyHolidayCalendar.month(2026, 10),
              );
              completed = true;
            },
            child: const Text('Başlat'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Başlat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(completed, true);
    expect(result, isNull);
  });
  testWidgets(
    '320px settings panel persists edits and restores default scores',
    (tester) async {
      tester.view.physicalSize = const Size(320, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      final settings = DifficultySettings.defaults();
      DifficultySettings? saved;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: DifficultySettingsPanel(
              settings: settings,
              busy: false,
              onSave: (next) async {
                saved = await repo.saveDifficultySettings(settings, next);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('weekday-1-3'));
      await tester.scrollUntilVisible(
        field,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Puanlama Ayarlarını Kaydet'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Puanlama Ayarlarını Kaydet'));
      await tester.pumpAndSettle();
      expect(saved!.weekdayScores.first, 10);
      final read = await tester.runAsync(() => repo.loadDifficultySettings());
      expect(read!.weekdayScores.first, 10);
      await tester.tap(find.text('Varsayılanları Geri Yükle'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('weekday-1-3')),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('weekday-1-3')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Actual month creation cancellation does not create a holiday month',
    (tester) async {
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      await tester.pumpWidget(host(SchedulePage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nöbet Hazırla'));
      await tester.pumpAndSettle();
      final month = find.byType(DropdownButtonFormField<int>).at(1);
      await tester.tap(month);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mart').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayı oluştur'));
      await tester.pumpAndSettle();
      expect(find.text('Resmî Tatil Nöbet Puanları'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      final m = await tester.runAsync(() => repo.loadMonth('2026-03'));
      expect(m, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Settings navigation saves points and no-holiday creation snapshots them',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      await tester.pumpWidget(host(SchedulePage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayarlar'));
      await tester.pumpAndSettle();
      expect(find.text('Nöbet Puanlama Ayarları'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('weekday-1-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Puanlama Ayarlarını Kaydet'));
      await tester.tap(find.text('Puanlama Ayarlarını Kaydet'));
      await tester.pumpAndSettle();
      final settings = await tester.runAsync(
        () => repo.loadDifficultySettings(),
      );
      expect(settings!.weekdayScores.first, 8);
      await tester.tap(find.text('Nöbet Hazırla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayı oluştur'));
      await tester.pumpAndSettle();
      expect(find.text('Resmî Tatil Nöbet Puanları'), findsNothing);
      final month = await tester.runAsync(() => repo.loadMonth('2026-11'));
      expect(month, isNotNull);
      expect(month!.difficultySettingsSnapshot!.weekdayScores.first, 8);
      expect(tester.takeException(), isNull);
    },
  );
}
