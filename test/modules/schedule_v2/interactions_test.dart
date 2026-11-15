import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akys/core/design/clinical_teal_theme.dart';
import 'package:akys/modules/schedule_v2/workspace.dart';
import 'package:akys/modules/schedule_v2/schedule_page.dart';
import 'package:akys/solver_v2/solver.dart';

ScheduleWorkspace workspace() => ScheduleWorkspace(
  initial: Problem(
    doctors: [
      Doctor(id: 'S1', seniorityLevel: SeniorityLevel.k1),
      Doctor(id: 'S2', seniorityLevel: SeniorityLevel.k4),
    ],
    startDate: DateTime.utc(2026, 11),
    slotsPerDay: [1, 0, 0, 1],
    slotRoles: [DutyRole.senior, DutyRole.senior],
    slotRequirements: [SlotRequirement.required, SlotRequirement.required],
    dayDifficulties: List.filled(4, const DayDifficulty(weekdayScore: 3)),
  ),
);
Future<void> page(WidgetTester t, ScheduleWorkspace w) async {
  addTearDown(w.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: ClinicalTealTheme.light,
      home: V2SchedulePage(workspace: w),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'month and year selection explicitly resets dated configuration',
    (t) async {
      final w = workspace();
      await page(t, w);
      await t.tap(find.byKey(const Key('month')));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Next month'));
      await t.pumpAndSettle();
      await t.tap(find.text('15'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.textContaining('Ay değişiminde'), findsOneWidget);
      await t.tap(find.text('Yeni taslak'));
      await t.pumpAndSettle();
      expect(w.problem.startDate, DateTime.utc(2026, 12));
      expect(w.problem.slotsPerDay.length, 31);
    },
  );
  testWidgets(
    'doctor constraints validate conflicts and preserve selected days',
    (t) async {
      final w = workspace();
      await page(t, w);
      await t.tap(find.text('Hekimler'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Hekim düzenle').first);
      await t.pumpAndSettle();
      await t.ensureVisible(
        find.widgetWithText(TextField, 'Tutacak günler (1,4,7)'),
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Tutacak günler (1,4,7)'),
        '1',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Tutamaz günler (2,5)'),
        '1',
      );
      await t.tap(find.text('Uygula'));
      await t.pumpAndSettle();
      expect(find.textContaining('Girdi geçersiz.'), findsOneWidget);
      expect(w.problem.doctors.first.must, isEmpty);
      await t.ensureVisible(find.byTooltip('Tutamaz günlerini seç'));
      await t.tap(find.byTooltip('Tutamaz günlerini seç'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilterChip, '1'));
      await t.tap(find.widgetWithText(FilterChip, '2'));
      await t.tap(find.text('Günleri uygula'));
      await t.pumpAndSettle();
      await t.tap(find.text('Uygula'));
      await t.pumpAndSettle();
      await t.tap(find.text('Yeni taslak'));
      await t.pumpAndSettle();
      expect(w.problem.doctors.first.must, {0});
      expect(w.problem.doctors.first.unavailable, {1});
    },
  );
  testWidgets('remove doctor requires explicit draft reset', (t) async {
    final w = workspace();
    await page(t, w);
    await t.tap(find.text('Hekimler'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Hekim düzenle').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Hekimi çıkar'));
    await t.pumpAndSettle();
    expect(w.problem.doctors.length, 2);
    await t.tap(find.text('Yeni taslak'));
    await t.pumpAndSettle();
    expect(w.problem.doctors.map((d) => d.id), ['S2']);
  });
  testWidgets('day optional slots and manual holiday reach exact snapshot', (
    t,
  ) async {
    final w = workspace();
    await page(t, w);
    await t.tap(find.byTooltip('Gün pozisyonları ve tatil').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Pozisyon ekle'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Manuel tatil adı (boş = tatil yok)'),
      'Test Tatili',
    );
    await t.enterText(
      find.widgetWithText(
        TextField,
        'Tatil puanı 1–10 (hafta günü ile maksimum)',
      ),
      '9',
    );
    await t.tap(find.text('Uygula'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yeni taslak'));
    await t.pumpAndSettle();
    expect(w.problem.slotRequirements[1], SlotRequirement.optional);
    expect(w.problem.dayDifficulties![0].effectiveScore, 9);
    expect(find.text('⚑ Manuel tatil: Test Tatili'), findsOneWidget);
  });
  testWidgets('touch swap, undo, redo and move menus use atomic editor', (
    t,
  ) async {
    final w = workspace();
    w.edit((e) => e.assign(0, 0));
    w.edit((e) => e.assign(1, 1));
    await page(t, w);
    await t.tap(find.byKey(const Key('slot-0')));
    await t.pumpAndSettle();
    await t.tap(find.text('Takas'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('#2: S2'));
    await t.pumpAndSettle();
    expect(w.editor.current.assignments, [1, 0]);
    await t.tap(find.byKey(const Key('undo')));
    await t.pumpAndSettle();
    expect(w.editor.current.assignments, [0, 1]);
    await t.tap(find.byKey(const Key('redo')));
    await t.pumpAndSettle();
    expect(w.editor.current.assignments, [1, 0]);
    w.edit((e) => e.remove(1));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('slot-0')));
    await t.pumpAndSettle();
    await t.tap(find.text('Taşı'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('#2: Boş'));
    await t.pumpAndSettle();
    expect(w.editor.current.assignments, [-1, 1]);
  });
  testWidgets('real long-press drag swaps and locked source remains fixed', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final w = workspace();
    w.edit((e) => e.assign(0, 0));
    w.edit((e) => e.assign(1, 1));
    await page(t, w);
    final gesture = await t.startGesture(
      t.getCenter(find.byKey(const Key('slot-0'))),
    );
    await t.pump(const Duration(seconds: 1));
    await gesture.moveTo(t.getCenter(find.byKey(const Key('slot-1'))));
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect(w.editor.current.assignments, [1, 0]);
    w.edit((e) => e.lock(0));
    await t.pumpAndSettle();
    final locked = await t.startGesture(
      t.getCenter(find.byKey(const Key('slot-0'))),
    );
    await t.pump(const Duration(seconds: 1));
    await locked.moveTo(t.getCenter(find.byKey(const Key('slot-1'))));
    await locked.up();
    await t.pumpAndSettle();
    expect(w.editor.current.assignments, [1, 0]);
  });
}
