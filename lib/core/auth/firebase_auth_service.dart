import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'auth_service.dart';
import 'auth_state.dart';

class FirebaseAuthService extends AuthService {
  FirebaseAuthService(this._auth) {
    _authSubscription = _auth.authStateChanges().listen(
      _resolve,
      onError: (Object _) => _failClosed(),
    );
    // Claim refreshes must also invalidate previously rendered private content.
    _tokenSubscription = _auth.idTokenChanges().listen(
      _resolve,
      onError: (Object _) => _failClosed(),
    );
  }

  final FirebaseAuth _auth;
  final _authorization = const AdminAuthorization();
  late final StreamSubscription<User?> _authSubscription;
  late final StreamSubscription<User?> _tokenSubscription;
  AuthState _state = const AuthState(AuthStatus.checking);
  int _generation = 0;
  bool _disposed = false;

  @override
  AuthState get state => _state;

  void _emit(AuthStatus status) {
    if (_disposed) return;
    _state = AuthState(status);
    notifyListeners();
  }

  void _failClosed() {
    _generation++;
    _emit(AuthStatus.unavailable);
  }

  Future<void> _resolve(User? user) async {
    final generation = ++_generation;
    if (user == null) {
      _emit(AuthStatus.signedOut);
      return;
    }
    _emit(AuthStatus.checking);
    try {
      final token = await user.getIdTokenResult();
      if (_disposed || generation != _generation) return;
      if (_auth.currentUser?.uid != user.uid) {
        _emit(AuthStatus.signedOut);
        return;
      }
      _emit(
        _authorization.allows(token.claims)
            ? AuthStatus.authorized
            : AuthStatus.denied,
      );
    } catch (_) {
      if (generation == _generation) _failClosed();
    }
  }

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(authErrorMessage(error.code));
    } catch (_) {
      throw const AuthFailure(
        'Giriş şu anda tamamlanamadı. Lütfen tekrar deneyin.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    // Hide private content immediately, even if the sign-out request fails.
    _generation++;
    _emit(AuthStatus.checking);
    try {
      await _auth.signOut();
      _emit(AuthStatus.signedOut);
    } catch (_) {
      _failClosed();
      throw const AuthFailure('Çıkış tamamlanamadı. Lütfen tekrar deneyin.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_authSubscription.cancel());
    unawaited(_tokenSubscription.cancel());
    super.dispose();
  }
}
