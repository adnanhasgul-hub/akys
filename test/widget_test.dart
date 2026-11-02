import 'dart:async';

import 'package:akys/app/akys_app.dart';
import 'package:akys/core/auth/auth_service.dart';
import 'package:akys/core/auth/auth_state.dart';
import 'package:akys/core/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuth extends AuthService {
  FakeAuth(AuthStatus status) : _state = AuthState(status);
  AuthState _state;
  Completer<void>? pendingSignIn;
  AuthFailure? signInFailure;
  String? submittedEmail;
  @override
  AuthState get state => _state;
  void emit(AuthStatus status) {
    _state = AuthState(status);
    notifyListeners();
  }

  @override
  Future<void> signIn(String email, String password) async {
    submittedEmail = email;
    if (pendingSignIn != null) await pendingSignIn!.future;
    if (signInFailure != null) throw signInFailure!;
  }

  @override
  Future<void> signOut() async => emit(AuthStatus.signedOut);
}

void main() {
  test('Admin yetkisi yalnızca boolean true custom claim ile verilir', () {
    const policy = AdminAuthorization();
    expect(policy.allows(null), isFalse);
    expect(policy.allows({}), isFalse);
    expect(policy.allows({'admin': false}), isFalse);
    expect(policy.allows({'admin': 'true'}), isFalse);
    expect(policy.allows({'admin': true}), isTrue);
  });

  test('Kimlik hataları hesap varlığını açığa çıkarmaz', () {
    expect(
      authErrorMessage('user-not-found'),
      authErrorMessage('wrong-password'),
    );
    expect(
      authErrorMessage('invalid-credential'),
      authErrorMessage('wrong-password'),
    );
    expect(
      authErrorMessage('internal-error'),
      isNot(contains('internal-error')),
    );
  });

  testWidgets('Oturumsuz kullanıcı login görür; kayıt ve şifre sıfırlama yok', (
    tester,
  ) async {
    final auth = FakeAuth(AuthStatus.signedOut);
    addTearDown(auth.dispose);
    await tester.pumpWidget(AkysApp(auth: auth));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Giriş Yap'), findsOneWidget);
    expect(find.text('Çalışma Çizelgesi'), findsNothing);
    for (final text in [
      'Üye Ol',
      'Kayıt Ol',
      'Hesap Oluştur',
      'Şifremi unuttum',
    ]) {
      expect(find.text(text), findsNothing);
    }
  });

  testWidgets('Yetkisiz oturum private shell göremez', (tester) async {
    final auth = FakeAuth(AuthStatus.denied);
    addTearDown(auth.dispose);
    await tester.pumpWidget(AkysApp(auth: auth));
    expect(find.text('Erişim yetkiniz yok'), findsOneWidget);
    expect(find.text('Çalışma Çizelgesi'), findsNothing);
  });

  testWidgets('Admin shell görür; logout login ekranına döner', (tester) async {
    final auth = FakeAuth(AuthStatus.authorized);
    addTearDown(auth.dispose);
    await tester.pumpWidget(AkysApp(auth: auth));
    expect(find.text('AKYS'), findsOneWidget);
    expect(find.text('Çalışma Çizelgesi'), findsOneWidget);
    expect(find.text('Ameliyat Notları'), findsOneWidget);
    await tester.tap(find.text('Çıkış Yap'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Çalışma Çizelgesi'), findsNothing);
  });

  for (final status in [AuthStatus.signedOut, AuthStatus.denied]) {
    testWidgets('Doğrudan private route girişleri korunur: ${status.name}', (
      tester,
    ) async {
      final auth = FakeAuth(status);
      addTearDown(auth.dispose);
      tester.platformDispatcher.defaultRouteNameTestValue = '/work_schedule';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await tester.pumpWidget(AkysApp(auth: auth));
      await tester.pumpAndSettle();
      expect(find.text('Çalışma Çizelgesi'), findsNothing);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      for (final route in [
        '/personnel',
        '/duty',
        '/task_distribution',
        '/operative_notes',
        '/share/unimplemented',
        '/unknown',
      ]) {
        unawaited(navigator.pushNamed(route));
        await tester.pumpAndSettle();
        expect(find.text('Çalışma Çizelgesi'), findsNothing);
        expect(find.text('Ameliyat Notları'), findsNothing);
        expect(
          find.text(
            status == AuthStatus.signedOut
                ? 'Giriş Yap'
                : 'Erişim yetkiniz yok',
          ),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets(
    'Yetki kaldırıldığında ve doğrulama hatasında shell hemen kapanır',
    (tester) async {
      final auth = FakeAuth(AuthStatus.authorized);
      addTearDown(auth.dispose);
      await tester.pumpWidget(AkysApp(auth: auth));
      auth.emit(AuthStatus.checking);
      await tester.pump();
      expect(find.text('Çalışma Çizelgesi'), findsNothing);
      auth.emit(AuthStatus.unavailable);
      await tester.pumpAndSettle();
      expect(find.text('Yetki doğrulanamadı'), findsOneWidget);
      expect(find.text('Çalışma Çizelgesi'), findsNothing);
    },
  );

  testWidgets('Mobil login, şifre gösterme, Enter, loading ve Türkçe hata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = FakeAuth(AuthStatus.signedOut)
      ..pendingSignIn = Completer<void>()
      ..signInFailure = const AuthFailure(
        'E-posta veya şifre hatalı. Lütfen tekrar deneyin.',
      );
    addTearDown(auth.dispose);
    await tester.pumpWidget(AkysApp(auth: auth));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'admin@example.test');
    await tester.enterText(fields.last, 'test-input');
    await tester.tap(find.byTooltip('Şifreyi göster'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isFalse,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(auth.submittedEmail, 'admin@example.test');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    auth.pendingSignIn!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('E-posta veya şifre hatalı. Lütfen tekrar deneyin.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
