import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/domain/duty_positions.dart';
import 'package:akys/modules/work_schedule/presentation/v13_solver_panel.dart';

import 'engine_test.dart' show sample;
import 'schedule_widget_test.dart' show host;

ScheduleMonth positioned() {
  final m = sample(2026, 11, count: 8)..boundaryConfirmed = true;
  m.dutyPositions = [
    for (var d = 1; d <= 30; d++)
      DutyPositions(
        date: dateKey(m.date(d)),
        seniorDutyPersonId: 'p${(d - 1) % 4 + 1}',
        juniorDutyPersonIds: ['p${(d - 1) % 4 + 5}'],
        seniorRoleIsSubstitution: false,
        seniorRoleOriginalGroup: 'senior',
      ),
  ];
  sync(m);
  m.v13Diagnostics = {'optimalityProven': true, 'hierarchyProven': true};
  return m;
}

void sync(ScheduleMonth m) {
  m.duties.clear();
  for (final r in m.dutyPositions!) {
    m.duties[int.parse(r.date.substring(8))] = [
      r.seniorDutyPersonId!,
      ...r.juniorDutyPersonIds,
    ];
  }
  m.requiredDuties = m.duties.values.fold(0, (a, b) => a + b.length);
}

void main() {
  test('Legacy JSON remains without inferred positions', () {
    final m = sample(2026, 11);
    expect(m.clone().dutyPositions, isNull);
    expect(m.clone().toJson().containsKey('dutyPositions'), false);
  });
  test(
    'Repository position roundtrip preserves identity metadata and snapshots',
    () async {
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      final m = positioned();
      final saved = await repo.saveMonth(m, create: true);
      final read = (await repo.loadMonth(m.id))!;
      expect(
        read.dutyPositions!.map((p) => p.toJson()).toList(),
        saved.dutyPositions!.map((p) => p.toJson()).toList(),
      );
      expect(
        read.people.map((p) => p.toJson()).toList(),
        m.people.map((p) => p.toJson()).toList(),
      );
      expect(read.v13Diagnostics, m.v13Diagnostics);
    },
  );
  test('Invalid role and mismatched compatibility list rejected', () async {
    final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
    final m = positioned();
    m.duties[1] = ['p1'];
    await expectLater(
      repo.saveMonth(m, create: true),
      throwsA(isA<ScheduleConflict>()),
    );
  });
  test(
    'Manual valid edit invalidates proof and finalization is blocked',
    () async {
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      final m = await repo.saveMonth(positioned(), create: true);
      final row = m.dutyPositions!.first;
      m.dutyPositions![0] = DutyPositions(
        date: row.date,
        seniorDutyPersonId: row.seniorDutyPersonId,
        juniorDutyPersonIds: [],
        seniorRoleIsSubstitution: false,
        seniorRoleOriginalGroup: 'senior',
        juniorVacancyReason: 'NOT_PROVEN: manuel',
      );
      sync(m);
      final saved = await repo.saveMonth(m);
      expect(saved.v13Diagnostics!['optimalityProven'], false);
      expect(saved.v13Diagnostics!['hierarchyProven'], false);
      saved.status = MonthStatus.finalised;
      await expectLater(
        repo.saveMonth(saved),
        throwsA(isA<ScheduleConflict>()),
      );
    },
  );
  test(
    'Dropping roles and legacy-style manual moves cannot lose positions',
    () async {
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      final m = await repo.saveMonth(positioned(), create: true);
      m.dutyPositions = null;
      await expectLater(repo.saveMonth(m), throwsA(isA<ScheduleConflict>()));
    },
  );
  test('Changed constraints invalidate prior proof', () async {
    final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
    final m = await repo.saveMonth(positioned(), create: true);
    m.constraints['p1']!.cannot.add(2);
    final saved = await repo.saveMonth(m);
    expect(saved.v13Diagnostics!['optimalityProven'], false);
  });
  test('Substitution and vacancy reason persist', () async {
    final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
    final m = positioned();
    m.dutyPositions![0] = DutyPositions(
      date: '2026-11-01',
      seniorDutyPersonId: 'p5',
      juniorDutyPersonIds: [],
      seniorRoleIsSubstitution: true,
      seniorRoleOriginalGroup: 'junior',
      juniorVacancyReason: 'NOT_PROVEN',
    );
    sync(m);
    await repo.saveMonth(m, create: true);
    final r = (await repo.loadMonth(m.id))!.dutyPositions!.first;
    expect(r.seniorRoleIsSubstitution, true);
    expect(r.seniorRoleOriginalGroup, 'junior');
    expect(r.juniorVacancyReason, startsWith('NOT_PROVEN'));
  });
  testWidgets('Feature flag defaults off', (tester) async {
    expect(v13SolverEnabled, false);
    await tester.pumpWidget(
      host(V13SolverPanel(month: positioned(), onSave: (_) async => true)),
    );
    expect(find.text('V1.3 deneysel nöbet motoru'), findsNothing);
  });
  testWidgets(
    'Enabled preview reports validity and manual edit invalidates proof',
    (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: SingleChildScrollView(
              child: V13SolverPanel(
                enabled: true,
                month: positioned(),
                onSave: (_) async => true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hard constraint: GEÇERLİ'), findsOneWidget);
      await tester.ensureVisible(
        find.text('Günlük senior / junior pozisyonları'),
      );
      await tester.tap(find.text('Günlük senior / junior pozisyonları'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(Icons.edit).first);
      await tester.tap(find.byIcon(Icons.edit).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.tap(find.text('Önizlemeye Uygula'));
      await tester.pumpAndSettle();
      expect(
        find.text('Genel optimizasyon: tamamlanmadı; geçici taslak'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Save requires explicit confirmation; cancel causes no write', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SingleChildScrollView(
            child: V13SolverPanel(
              enabled: true,
              month: positioned(),
              onSave: (_) async {
                writes++;
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('V1.3 Taslağını Kaydet'));
    await tester.tap(find.text('V1.3 Taslağını Kaydet'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    await tester.tap(find.text('V1.3 Taslağını Kaydet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taslağı Kaydet'));
    await tester.pumpAndSettle();
    expect(writes, 1);
  });
  testWidgets('Search progress and cancel controls respond', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SingleChildScrollView(
            child: V13SolverPanel(
              enabled: true,
              month: positioned(),
              onSave: (_) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('V1.3 Önizleme Oluştur'));
    await tester.pump();
    expect(find.text('Aramayı İptal Et'), findsOneWidget);
    await tester.tap(find.text('Aramayı İptal Et'));
    await tester.pumpAndSettle();
    expect(find.text('Aramayı İptal Et'), findsNothing);
    expect(find.textContaining('Ziyaret:'), findsOneWidget);
  });
}
