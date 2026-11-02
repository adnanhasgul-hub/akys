import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'auth_state.dart';
import 'login_screen.dart';

/// Every current route is private. Future public share routes must be explicitly
/// separated at the app router; unknown routes never become public implicitly.
class AuthGate extends StatelessWidget {
  const AuthGate({required this.auth, required this.child, super.key});
  final AuthService auth;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) => switch (auth.state.status) {
      AuthStatus.signedOut => LoginScreen(auth: auth),
      AuthStatus.authorized => child,
      AuthStatus.denied => AccessDeniedScreen(auth: auth),
      AuthStatus.unavailable => AccessDeniedScreen(
        auth: auth,
        unavailable: true,
      ),
      AuthStatus.checking => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    },
  );
}

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({
    required this.auth,
    this.unavailable = false,
    super.key,
  });
  final AuthService auth;
  final bool unavailable;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                unavailable ? 'Yetki doğrulanamadı' : 'Erişim yetkiniz yok',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                unavailable
                    ? 'Güvenliğiniz için erişim kapatıldı. Lütfen tekrar giriş yapın.'
                    : 'Bu hesap AKYS yöneticisi olarak yetkilendirilmemiş.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              LogoutButton(auth: auth),
            ],
          ),
        ),
      ),
    ),
  );
}

class LogoutButton extends StatefulWidget {
  const LogoutButton({required this.auth, super.key});
  final AuthService auth;
  @override
  State<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<LogoutButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.logout),
    label: const Text('Çıkış Yap'),
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await widget.auth.signOut();
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Çıkış tamamlanamadı. Lütfen tekrar deneyin.',
                    ),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}
