import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/core/design/akys_design_system.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/presentation/schedule_page.dart';

import '../work_schedule/schedule_widget_test.dart' show host;
import '../work_schedule/engine_test.dart' show sample;
import 'schedule_teal_test.dart' show viewport;
import 'navigation_helper.dart';

import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/engine/task_engine.dart';

import '../work_schedule/task_workday_test.dart' show workMonth;

import 'package:akys/modules/work_schedule/presentation/v13_solver_panel.dart';

import '../work_schedule/v13_integration_test.dart' show positioned;

void main() {
  for (final width in [320.0, 414.0, 800.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('All destinations width=$width scale=$scale', (t) async {
        viewport(t, width, scale);
        if (width < AkysTokens.tablet) {
          t.view.physicalSize = Size(width, 750);
        }
        final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
        await repo.saveMonth(sample(2026, 11), create: true);
        await t.pumpWidget(host(SchedulePage(repository: repo)));
        await t.pumpAndSettle();
        for (final label in [
          'Nöbet',
          'Görevler',
          'Personel',
          'Birleşik Görünüm',
          'Geçmiş Aylar',
          'Ayarlar',
          'Genel Bakış',
        ]) {
          await navigateSchedule(t, label);
          expect(t.takeException(), isNull, reason: label);
        }
        final nav = t.widget<AkysAdaptiveNavigation>(
          find.byType(AkysAdaptiveNavigation),
        );
        expect(nav.selectedIndex, 0);
        expect(
          find.text('Diğer'),
          width < AkysTokens.tablet ? findsOneWidget : findsNothing,
        );
      });
    }
  }
  testWidgets(
    'Unsaved scoring survives tab and More navigation; back exits module',
    (t) async {
      viewport(t, 414, 1);
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      await t.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SchedulePage(repository: repo),
                  ),
                ),
                child: const Text('Modülü aç'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Modülü aç'));
      await t.pumpAndSettle();
      await navigateSchedule(t, 'Ayarlar');
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('weekday-1-3')),
        100,
        scrollable: activeScheduleScroll(),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('weekday-1-3')));
      await t.pumpAndSettle();
      await t.tap(find.text('10').last);
      await t.pumpAndSettle();
      await navigateSchedule(t, 'Nöbet');
      await navigateSchedule(t, 'Ayarlar');
      expect(find.byKey(const ValueKey('weekday-1-10')), findsOneWidget);
      final persisted = await t.runAsync(() => repo.loadDifficultySettings());
      expect(persisted!.weekdayScores.first, 3);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('Modülü aç'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Keyboard activates More and Escape closes it without changing page',
    (t) async {
      viewport(t, 320, 2);
      await t.pumpWidget(
        host(
          SchedulePage(
            repository: FirestoreScheduleRepository(FakeFirebaseFirestore()),
          ),
        ),
      );
      await t.pumpAndSettle();
      Focus.of(t.element(find.text('Diğer'))).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('Ayarlar'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Ayarlar'), findsNothing);
      expect(
        t
            .widget<AkysAdaptiveNavigation>(find.byType(AkysAdaptiveNavigation))
            .selectedIndex,
        0,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('V1.3 panel state and configured flag survive tab navigation', (
    t,
  ) async {
    viewport(t, 1440, 1);
    final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
    await repo.saveMonth(positioned(), create: true);
    await t.pumpWidget(host(SchedulePage(repository: repo)));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('2026 Kasım · Taslak').last);
    await t.pumpAndSettle();
    await navigateSchedule(t, 'Nöbet');
    await expandScheduleSection(t, 'Planlama araçları');
    final panel = find.byType(V13SolverPanel);
    final state = t.state(panel);
    expect(t.widget<V13SolverPanel>(panel).enabled, v13SolverEnabled);
    if (v13SolverEnabled) {
      await t.scrollUntilVisible(
        find.text('V1.3 deneysel nöbet motoru'),
        100,
        scrollable: activeScheduleScroll(),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Hard constraint: GEÇERLİ'), findsOneWidget);
    } else {
      expect(find.text('V1.3 deneysel nöbet motoru'), findsNothing);
    }
    await navigateSchedule(t, 'Personel');
    await navigateSchedule(t, 'Nöbet');
    expect(identical(t.state(panel), state), isTrue);
    expect(t.takeException(), isNull);
  });
  test(
    'November 1 legacy Sunday tasks originate in compatibility calculation',
    () {
      final legacy = sample(2026, 11);
      for (final task in ClinicTask.values) {
        legacy.tasks[task] = const TaskAssignment('p1', 'p2');
      }
      expect(legacy.date(1).weekday, DateTime.sunday);
      expect(legacy.taskWorkdaySchemaVersion, 0);
      expect(
        dailyTasks(legacy, 1).every((t) => t.active && t.personId == 'p1'),
        isTrue,
      );
      final current = workMonth(2026, 11);
      expect(
        dailyTasks(
          current,
          1,
        ).every((t) => !t.active && t.personId == null && t.warnings.isEmpty),
        isTrue,
      );
      expect(legacy.taskWorkdaySchemaVersion, 0);
    },
  );
}
