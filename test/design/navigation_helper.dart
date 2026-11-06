import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:akys/core/design/akys_design_system.dart';

Future<void> navigateSchedule(WidgetTester tester, String label) async {
  final title = label == 'Görev Dağılımı'
      ? 'Görevler'
      : label == 'Genel Bakış' &&
            tester.view.physicalSize.width / tester.view.devicePixelRatio <
                AkysTokens.tablet
      ? 'Özet'
      : label;
  if (['Ayarlar', 'Birleşik Görünüm', 'Geçmiş Aylar'].contains(title) &&
      tester.view.physicalSize.width / tester.view.devicePixelRatio <
          AkysTokens.tablet) {
    await tester.tap(find.text('Diğer'));
    await tester.pumpAndSettle();
  }
  final target = find.text(title).last;
  if (find.text(title).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(title),
      100,
      scrollable: find
          .descendant(
            of: find.byType(AkysAdaptiveNavigation),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder activeScheduleScroll() =>
    find.byKey(const ValueKey('schedule-pages')).evaluate().isEmpty
    ? find.byType(Scrollable).first
    : find
          .descendant(
            of: find.byKey(const ValueKey('schedule-pages')),
            matching: find.byType(Scrollable),
          )
          .first;

Future<void> expandScheduleSection(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    200,
    scrollable: activeScheduleScroll(),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
}
