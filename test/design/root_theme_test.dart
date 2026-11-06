import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/app/akys_app.dart';
import 'package:akys/core/auth/auth_state.dart';
import 'package:akys/core/auth/login_screen.dart';
import 'package:akys/core/design/akys_design_system.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';

import '../widget_test.dart' show FakeAuth;
import 'navigation_helper.dart';

void expectClinical(ThemeData theme) {
  expect(theme.colorScheme.primary, const Color(0xFF006B68));
  expect(theme.colorScheme.onSurface, const Color(0xFF123047));
  expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F8FA));
  expect(theme.colorScheme.primaryContainer, const Color(0xFFDDF3EF));
  expect(theme.textTheme.headlineLarge!.color, AkysTokens.navy);
  expect(theme.dialogTheme.backgroundColor, Colors.white);
  expect(theme.cardTheme.color, Colors.white);
  expect(theme.inputDecorationTheme.fillColor, Colors.white);
}

void main() {
  testWidgets(
    'Production MaterialApp owns Clinical Teal including signed-out route',
    (t) async {
      await t.pumpWidget(AkysApp(auth: FakeAuth(AuthStatus.signedOut)));
      await t.pumpAndSettle();
      expectClinical(t.widget<MaterialApp>(find.byType(MaterialApp)).theme!);
      expectClinical(Theme.of(t.element(find.byType(LoginScreen))));
      final box = t.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(LoginScreen),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color, AkysTokens.background);
    },
  );
  testWidgets(
    'Root theme reaches every schedule destination and root Navigator dialog',
    (t) async {
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        AkysApp(
          auth: FakeAuth(AuthStatus.authorized),
          scheduleRepository: FirestoreScheduleRepository(
            FakeFirebaseFirestore(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expectClinical(Theme.of(t.element(find.byType(Scaffold))));
      Navigator.of(t.element(find.byType(Scaffold)))
          .pushNamed('/work_schedule');
      await t.pumpAndSettle();
      for (final label in [
        'Genel Bakış',
        'Nöbet',
        'Görevler',
        'Personel',
        'Birleşik Görünüm',
        'Geçmiş Aylar',
        'Ayarlar',
      ]) {
        await navigateSchedule(t, label);
        expectClinical(Theme.of(t.element(find.byType(Scaffold).last)));
        expect(t.takeException(), isNull);
      }
      await navigateSchedule(t, 'Personel');
      await t.scrollUntilVisible(
        find.text('Personel Ekle'),
        150,
        scrollable: activeScheduleScroll(),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Personel Ekle'));
      await t.pumpAndSettle();
      expectClinical(Theme.of(t.element(find.byType(AlertDialog))));
      await t.tap(find.text('Vazgeç'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
}
