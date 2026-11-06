import 'navigation_helper.dart';

import 'package:akys/modules/work_schedule/presentation/v13_solver_panel.dart';

import '../work_schedule/v13_integration_test.dart' show positioned;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/core/design/akys_design_system.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/domain/duty_positions.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/presentation/schedule_page.dart';
import 'package:akys/modules/work_schedule/presentation/compact_duty_card.dart';
import 'package:akys/modules/work_schedule/presentation/solver_status_summary.dart';

import '../work_schedule/engine_test.dart' show sample;
import '../work_schedule/schedule_widget_test.dart' show host;
import '../work_schedule/difficulty_test.dart' show scoring, weightedMonth;

Widget themed(Widget w) => MaterialApp(
  theme: ClinicalTealTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: w)),
);
void viewport(WidgetTester t, double width, double scale) {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  for (final config in [
    (2, 320.0, 1.0),
    (11, 320.0, 2.0),
    (12, 1440.0, 1.0),
    (2, 800.0, 2.0),
    (11, 1440.0, 2.0),
  ]) {
    testWidgets(
      'Overview/duty ${config.$1} width ${config.$2} scale ${config.$3}',
      (tester) async {
        viewport(tester, config.$2, config.$3);
        final m = sample(
          2026,
          config.$1,
          total: DateTime.utc(2026, config.$1 + 1, 0).day,
        );
        for (var d = 1; d <= m.days; d++) {
          m.duties[d] = ['p${(d - 1) % 7 + 1}'];
        }
        final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
        await repo.saveMonth(m, create: true);
        await tester.pumpWidget(host(SchedulePage(repository: repo)));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Aktif Personel'),
          100,
          scrollable: activeScheduleScroll(),
        );
        await tester.pumpAndSettle();
        expect(find.text('Aktif Personel'), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('${m.title} · Taslak').last);
        await tester.pumpAndSettle();
        await navigateSchedule(tester, 'Nöbet');
        await tester.pumpAndSettle();
        expect(find.byType(CompactDutyCard), findsNWidgets(m.days));
        await tester.pumpAndSettle();
        expect(find.text('Pozisyon bilgisi kayıtlı değil'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Roles, substitution and vacancy remain distinct with long names',
    (tester) async {
      viewport(tester, 320, 2);
      final m = sample(2026, 11);
      m.people[4] = const PersonSnapshot(
        'p5',
        'Dr. Çok Uzun İsimli Muhammed Örnek Hekim Soyadı',
        5,
        dutySeniorityGroup: DutySeniorityGroup.junior,
      );
      final r = DutyPositions(
        date: '2026-11-01',
        seniorDutyPersonId: 'p5',
        juniorDutyPersonIds: [],
        seniorRoleIsSubstitution: true,
        seniorRoleOriginalGroup: 'junior',
        juniorVacancyReason: 'NOT_PROVEN: Aylık zorunluluk kanıtlanmadı.',
      );
      var edits = 0;
      await tester.pumpWidget(
        themed(
          CompactDutyCard(
            month: m,
            day: 1,
            position: r,
            positionsKnown: true,
            onEdit: () => edits++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('— (Boş)'), findsOneWidget);
      expect(find.text('Geçici senior · kalıcı grup Çömez'), findsOneWidget);
      expect(
        tester.widget<Card>(find.byType(Card)).color,
        AkysTokens.background,
      );
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Grup: Çömez'), findsOneWidget);
      expect(find.textContaining('Boşluk gerekçesi:'), findsOneWidget);
      await tester.ensureVisible(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(m.people[4].dutySeniorityGroup, DutySeniorityGroup.junior);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Holiday labels and real hard errors have separate semantics', (
    tester,
  ) async {
    final m = weightedMonth(sample(2026, 10), scoring(2026, 10));
    await tester.pumpWidget(
      themed(
        CompactDutyCard(
          month: m,
          day: 29,
          errors: const ['Maksimum nöbet ihlali'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cumhuriyet'), findsOneWidget);
    expect(
      tester.widget<Card>(find.byType(Card)).color,
      AkysTokens.errorSurface,
    );
    expect(find.text('1 zorunlu kural hatası'), findsOneWidget);
  });
  testWidgets('Search limit keeps valid state distinct from hierarchy proof', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const SolverStatusSummary(
          valid: true,
          hierarchyProven: false,
          optimal: false,
          searchLimited: true,
          finished: true,
        ),
      ),
    );
    expect(find.text('Hard constraint: GEÇERLİ'), findsOneWidget);
    expect(find.textContaining('imkânsızlık anlamına gelmez'), findsOneWidget);
    expect(find.textContaining('kanıtlanmadı;'), findsOneWidget);
    expect(find.text('Geçerli çizelge bulunamadı'), findsNothing);
    await tester.pumpWidget(
      themed(
        const SolverStatusSummary(
          valid: null,
          hierarchyProven: false,
          optimal: false,
          searchLimited: true,
          finished: true,
        ),
      ),
    );
    expect(find.text('Geçerli çizelge bulunamadı'), findsOneWidget);
    await tester.pumpWidget(
      themed(
        const SolverStatusSummary(
          valid: true,
          hierarchyProven: true,
          optimal: true,
          searchLimited: false,
          finished: true,
        ),
      ),
    );
    expect(find.text('Genel optimizasyon: tamamlandı'), findsOneWidget);
  });
  testWidgets('Month selector loading empty and selection are view-only', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const AkysMonthSelector(
          options: [],
          selectedId: null,
          onChanged: null,
          loading: true,
        ),
      ),
    );
    expect(find.text('Aylar yükleniyor'), findsOneWidget);
    await tester.pumpWidget(
      themed(
        const AkysMonthSelector(options: [], selectedId: null, onChanged: null),
      ),
    );
    expect(find.textContaining('Henüz kayıtlı ay yok'), findsOneWidget);
    String? selected;
    await tester.pumpWidget(
      themed(
        AkysMonthSelector(
          options: const [
            AkysMonthOption(
              id: '2026-11',
              title: '2026 Kasım',
              statusLabel: 'Taslak',
              status: AkysStatus.info,
            ),
          ],
          selectedId: null,
          onChanged: (v) => selected = v,
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026 Kasım · Taslak').last);
    await tester.pumpAndSettle();
    expect(selected, '2026-11');
  });

  testWidgets('V1.3 panel fits 320px at 200 percent text scale', (
    tester,
  ) async {
    viewport(tester, 320, 2);
    await tester.pumpWidget(
      themed(
        V13SolverPanel(
          enabled: true,
          month: positioned(),
          onSave: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hard constraint: GEÇERLİ'), findsOneWidget);
    await tester.ensureVisible(
      find.text('Günlük senior / junior pozisyonları'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Günlük senior / junior pozisyonları'));
    await tester.pumpAndSettle();
    expect(find.byType(CompactDutyCard), findsNWidgets(30));
    expect(tester.takeException(), isNull);
  });
}
