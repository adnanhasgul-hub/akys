import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/app/akys_app.dart';
import 'package:akys/core/auth/auth_state.dart';
import 'package:akys/core/design/clinical_teal_theme.dart';
import 'package:akys/core/design/akys_components.dart';
import 'package:akys/core/design/akys_adaptive_navigation.dart';
import 'package:akys/modules/work_schedule/data/schedule_repository.dart';

import '../widget_test.dart' show FakeAuth;

Widget gallery(Widget child) => MaterialApp(
  theme: ClinicalTealTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
void main() {
  for (final size in [
    const Size(320, 750),
    const Size(768, 1000),
    const Size(1440, 1000),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Home responsive ${size.width} scale $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final auth = FakeAuth(AuthStatus.authorized);
        addTearDown(auth.dispose);
        await tester.pumpWidget(AkysApp(auth: auth));
        await tester.pumpAndSettle();
        expect(find.text('AKYS'), findsOneWidget);
        expect(find.text('A Klinik Yönetim Sistemi'), findsOneWidget);
        await tester.ensureVisible(find.text('Ameliyat Notları'));
        await tester.tap(find.text('Ameliyat Notları'));
        await tester.pumpAndSettle();
        expect(find.text('Yakında'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          Theme.of(tester.element(find.text('AKYS'))).colorScheme.primary,
          AkysTokens.primary,
        );
      });
    }
  }
  test('Semantic foreground/background contrast meets AA', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    for (final status in AkysStatus.values) {
      final (fg, bg, _) = AkysStatusChip.tokens(status);
      expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: status.name);
    }
    expect(
      contrast(AkysTokens.primary, Colors.white),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(AkysTokens.navy, AkysTokens.background),
      greaterThanOrEqualTo(4.5),
    );
    expect(contrast(AkysTokens.muted, Colors.white), greaterThanOrEqualTo(4.5));
    expect(contrast(AkysTokens.border, Colors.white), greaterThanOrEqualTo(3));
  });
  testWidgets('All common components fit narrow scaled layout', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      gallery(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AkysPageHeader(
              title: 'Klinik çalışma alanı',
              description: 'Uzun Türkçe açıklama ve kayıt bilgileri',
            ),
            const AkysSectionHeader(title: 'Örnekler'),
            const AkysStatCard(
              label: 'Toplam kayıt',
              value: '128',
              icon: Icons.description_outlined,
            ),
            AkysPrimaryButton(
              label: 'Çalışma alanını görüntüle',
              icon: Icons.arrow_forward,
              onPressed: () {},
            ),
            const AkysSecondaryButton(
              label: 'Devre dışı işlem',
              onPressed: null,
            ),
            for (final status in AkysStatus.values)
              AkysStatusChip(
                label: '${status.name}: açıklamalı durum',
                status: status,
              ),
            const AkysEmptyState(
              title: 'Henüz kayıt yok',
              message: 'Yeni kayıtlar burada görünecek.',
            ),
            AkysErrorState(message: 'Lütfen yeniden deneyin.', onRetry: () {}),
            const AkysLoadingState(),
            const AkysFormField(label: 'Açıklama'),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Keyboard can activate home module without changing auth flow', (
    tester,
  ) async {
    final auth = FakeAuth(AuthStatus.authorized);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      AkysApp(
        auth: auth,
        scheduleRepository: FirestoreScheduleRepository(
          FakeFirebaseFirestore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Çalışma Çizelgesi'));
    Focus.of(context).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Genel Bakış'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Form validation and confirm cancel/accept are explicit', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    bool? answer;
    await tester.pumpWidget(
      gallery(
        Builder(
          builder: (context) => Form(
            key: form,
            child: Column(
              children: [
                AkysFormField(
                  label: 'Ad',
                  validator: (v) => (v ?? '').isEmpty ? 'Gerekli' : null,
                ),
                AkysPrimaryButton(
                  label: 'Devam',
                  onPressed: () async {
                    if (form.currentState!.validate()) {
                      answer = await AkysConfirmDialog.show(
                        context,
                        title: 'Onay',
                        message: 'Devam edilsin mi?',
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Devam'));
    await tester.pump();
    expect(find.text('Gerekli'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Örnek');
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(answer, false);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Onayla'));
    await tester.pumpAndSettle();
    expect(answer, true);
  });
  for (final width in [320.0, 800.0, 1440.0]) {
    testWidgets('Adaptive navigation $width exposes overflow destinations', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      int selected = 0;
      final destinations = [
        for (final label in [
          'Genel Bakış',
          'Nöbet',
          'Görevler',
          'Personel',
          'Geçmiş Aylar',
          'Ayarlar',
        ])
          AkysDestination(label: label, icon: Icons.calendar_month),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ClinicalTealTheme.light,
          home: Scaffold(
            body: AkysAdaptiveNavigation(
              destinations: destinations,
              selectedIndex: 0,
              onSelected: (v) => selected = v,
              body: const Text('İçerik'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (width < 720) {
        await tester.tap(find.text('Diğer'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Ayarlar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayarlar'));
      await tester.pumpAndSettle();
      expect(selected, 5);
      expect(tester.takeException(), isNull);
    });
  }
}
