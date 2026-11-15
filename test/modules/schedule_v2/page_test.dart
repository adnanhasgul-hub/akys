import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akys/core/design/clinical_teal_theme.dart';
import 'package:akys/modules/schedule_v2/schedule_page.dart';
import 'package:akys/modules/schedule_v2/workspace.dart';
import 'package:akys/solver_v2/solver.dart';

void main() {
  for (final width in [360.0, 414.0, 768.0, 1440.0]) {
    testWidgets('responsive width $width and 200 percent text', (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final w = ScheduleWorkspace();
      addTearDown(w.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: ClinicalTealTheme.light,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: V2SchedulePage(workspace: w),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.byIcon(Icons.people));
      await t.pumpAndSettle();
      expect(find.text('Hekim ekle'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Kalite / Arama'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('status')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('add doctor with validation and explicit reset confirmation', (
    t,
  ) async {
    final w = ScheduleWorkspace();
    addTearDown(w.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: ClinicalTealTheme.light,
        home: V2SchedulePage(workspace: w),
      ),
    );
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byIcon(Icons.people));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('add-doctor')));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Ad soyad'),
      'Uzun İsimli Test Hekimi',
    );
    await t.tap(find.text('Uygula'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yeni taslak'));
    await t.pumpAndSettle();
    expect(w.problem.doctors.length, 1);
    expect(find.text('Uzun İsimli Test Hekimi'), findsOneWidget);
  });
  testWidgets('assignment menu and lock undo', (t) async {
    final base = ScheduleWorkspace.emptyMonth(2026, 11);
    final w = ScheduleWorkspace(
      initial: Problem(
        doctors: [Doctor(id: 'S', seniorityLevel: SeniorityLevel.k1)],
        startDate: base.startDate,
        slotsPerDay: base.slotsPerDay,
        slotRoles: base.slotRoles,
        slotRequirements: base.slotRequirements,
        dayDifficulties: base.dayDifficulties,
      ),
    );
    addTearDown(w.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: ClinicalTealTheme.light,
        home: V2SchedulePage(workspace: w),
      ),
    );
    await t.tap(find.byKey(const Key('slot-0')));
    await t.pumpAndSettle();
    await t.tap(find.text('Ata'));
    await t.pumpAndSettle();
    await t.tap(find.text('S'));
    await t.pumpAndSettle();
    expect(w.editor.current.assignments[0], 0);
    await t.tap(find.byKey(const Key('slot-0')));
    await t.pumpAndSettle();
    await t.tap(find.text('Kilitle'));
    await t.pumpAndSettle();
    expect(w.editor.current.locks, {0: 0});
    await t.tap(find.byKey(const Key('undo')));
    await t.pumpAndSettle();
    expect(w.editor.current.locks, isEmpty);
  });
}
