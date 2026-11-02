import 'package:flutter/foundation.dart';

import 'auth_state.dart';

abstract class AuthService extends ChangeNotifier {
  AuthState get state;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

String authErrorMessage(String code) => switch (code) {
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' ||
  'invalid-email' ||
  'user-disabled' => 'E-posta veya şifre hatalı. Lütfen tekrar deneyin.',
  'too-many-requests' =>
    'Çok fazla deneme yapıldı. Lütfen daha sonra tekrar deneyin.',
  'network-request-failed' =>
    'Bağlantı kurulamadı. İnternet bağlantınızı kontrol edin.',
  _ => 'Giriş şu anda tamamlanamadı. Lütfen daha sonra tekrar deneyin.',
};
