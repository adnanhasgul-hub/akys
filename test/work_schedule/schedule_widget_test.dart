import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:akys/core/theme/akys_colors.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/presentation/schedule_page.dart';
import 'package:akys/modules/work_schedule/presentation/shared_schedule_page.dart';

import 'engine_test.dart' show sample;

import 'package:akys/modules/work_schedule/engine/duty_engine.dart';
import 'package:akys/app/akys_app.dart';

import '../widget_test.dart' show FakeAuth;

import 'package:akys/core/auth/auth_state.dart';

Widget host(Widget child) => MaterialApp(
  theme: AkysColors.theme,
  locale: const Locale('tr'),
  supportedLocales: const [Locale('tr')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: child,
);
void main() {
  testWidgets('Desktop personnel UI persists add/edit and exposes ranks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
    await tester.pumpWidget(host(SchedulePage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personel').first);
    await tester.pumpAndSettle();
    expect(find.text('K1'), findsOneWidget);
    expect(find.text(initialNames.first), findsOneWidget);
    await tester.tap(find.text('Personel Ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Dr. Yeni');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(() => repo.watchPersonnel().first);
    expect(saved!.length, 8);
    await tester.scrollUntilVisible(
      find.text('Dr. Yeni'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Dr. Yeni'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    '320px mobile overview, selected month calendar and task view fit',
    (tester) async {
      tester.view.physicalSize = const Size(320, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FirestoreScheduleRepository(FakeFirebaseFirestore());
      await repo.saveMonth(
        const DutyEngine().generate(sample(2026, 11)).month!,
        create: true,
      );
      await tester.pumpWidget(host(SchedulePage(repository: repo)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026 Kasım · Taslak').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nöbet').first);
      await tester.pumpAndSettle();
      expect(find.text('Tutamaz / Tutacak'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('1 · Pazar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Görev Dağılımı').last);
      await tester.tap(find.text('Görev Dağılımı').last);
      await tester.pumpAndSettle();
      expect(find.text('Asıl / Yedek Seç'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Public projection renders independently from admin shell and hides revoked share',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final repo = FirestoreScheduleRepository(db);
      const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final m = sample(2026, 11);
      m.duties[1] = ['p1'];
      await db.doc('shared_schedules/$token').set(publicProjection(m));
      await tester.pumpWidget(
        host(SharedSchedulePage(token: token, repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('AKYS · Paylaşılan Çizelge'), findsOneWidget);
      expect(find.text('Personel'), findsNothing);
      expect(find.textContaining('Nöbet: Dr. 1'), findsOneWidget);
      await db.doc('shared_schedules/$token').update({'revoked': true});
      await tester.pumpAndSettle();
      expect(find.text('Bu paylaşım iptal edildi.'), findsOneWidget);
      expect(find.textContaining('Nöbet: Dr. 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Only the exact public token route bypasses AuthGate', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreScheduleRepository(db);
    const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await db
        .doc('shared_schedules/$token')
        .set(publicProjection(sample(2026, 11)));
    final auth = FakeAuth(AuthStatus.signedOut);
    addTearDown(auth.dispose);
    tester.platformDispatcher.defaultRouteNameTestValue =
        '/shared/schedule/$token';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(AkysApp(auth: auth, scheduleRepository: repo));
    await tester.pumpAndSettle();
    expect(find.text('AKYS · Paylaşılan Çizelge'), findsOneWidget);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/shared/schedule/not-a-token');
    await tester.pumpAndSettle();
    expect(find.text('Giriş Yap'), findsOneWidget);
    expect(find.text('Çalışma Çizelgesi'), findsNothing);
  });
}
