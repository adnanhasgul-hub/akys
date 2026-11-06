import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/core/design/akys_design_system.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/domain/difficulty.dart';
import 'package:akys/modules/work_schedule/presentation/schedule_page.dart';
import 'package:akys/modules/work_schedule/presentation/reference_schedule_widgets.dart';
import 'package:akys/modules/work_schedule/presentation/difficulty_widgets.dart';

import '../work_schedule/v13_integration_test.dart' show positioned;
import '../work_schedule/engine_test.dart' show sample;
import '../work_schedule/schedule_widget_test.dart' show host;
import 'navigation_helper.dart';

void main() {
  testWidgets(
    'Open month menu stays synchronized through repeated month changes',
    (t) async {
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      await repo.saveMonth(sample(2026, 11), create: true);
      await repo.saveMonth(sample(2026, 12), create: true);
      await t.pumpWidget(host(SchedulePage(repository: repo)));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('2026 Kasım · Taslak').last);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Ay ve işlemler'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Sonraki kayıtlı ay'));
      await t.pumpAndSettle();
      expect(find.text('Aralık 2026'), findsWidgets);
      await t.tap(find.byTooltip('Önceki kayıtlı ay'));
      await t.pumpAndSettle();
      expect(find.text('Kasım 2026'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Reference calendar 414px scale $scale reads roles without writes',
      (t) async {
        t.view.physicalSize = const Size(414, 896);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final m = positioned();
        final before = jsonEncode(m.toJson());
        await t.pumpWidget(
          MaterialApp(
            theme: ClinicalTealTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(414, 896),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(child: DutyMonthGrid(month: m)),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Kıdemli + Çömez'), findsOneWidget);
        await t.tap(find.text('1').first);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(jsonEncode(m.toJson()), before);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'List/calendar switching preserves persisted month and selected navigation',
    (t) async {
      t.view.physicalSize = const Size(414, 896);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      await repo.saveMonth(positioned(), create: true);
      final before = jsonEncode((await repo.loadMonth('2026-11'))!.toJson());
      await t.pumpWidget(host(SchedulePage(repository: repo)));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('2026 Kasım · Taslak').last);
      await t.pumpAndSettle();
      await navigateSchedule(t, 'Nöbet');
      await t.tap(find.text('Takvim'));
      await t.pumpAndSettle();
      expect(find.byType(DutyMonthGrid), findsOneWidget);
      await navigateSchedule(t, 'Personel');
      await navigateSchedule(t, 'Nöbet');
      expect(find.byType(DutyMonthGrid), findsOneWidget);
      await t.tap(find.text('Liste'));
      await t.pumpAndSettle();
      expect(find.byType(DutyMonthGrid), findsNothing);
      expect(jsonEncode((await repo.loadMonth('2026-11'))!.toJson()), before);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Compact score controls respect 1–10 and save through existing callback',
    (t) async {
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
                return true;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final plus = find.byTooltip('Pazartesi puanını artır');
      for (var i = 0; i < 12; i++) {
        await t.tap(plus);
        await t.pumpAndSettle();
      }
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is IconButton && w.tooltip == 'Pazartesi puanını artır',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('weekday-1-10')), findsOneWidget);
      await t.scrollUntilVisible(find.text('Puanlama Ayarlarını Kaydet'), 100);
      await t.pumpAndSettle();
      await t.tap(find.text('Puanlama Ayarlarını Kaydet'));
      await t.pumpAndSettle();
      expect(saved!.weekdayScores.first, 10);
      expect(t.takeException(), isNull);
    },
  );
}
