import 'package:akys/app/akys_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AKYS shell başlığını ve bağımsız modülleri gösterir', (
    tester,
  ) async {
    await tester.pumpWidget(const AkysApp());

    expect(find.text('AKYS'), findsOneWidget);
    expect(find.text('A Klinik Yönetim Sistemi'), findsOneWidget);
    expect(find.text('Çalışma Çizelgesi'), findsOneWidget);
    expect(find.text('Ameliyat Notları'), findsOneWidget);
    expect(find.text('Yakında'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dar Android ekranında shell taşmaz', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const AkysApp());

    expect(find.text('AKYS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
