import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../core/design/clinical_teal_theme.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/auth_gate.dart';
import 'schedule_page.dart';
import 'workspace.dart';
import 'data/draft_repository.dart';
import 'data/draft_session.dart';

class V2App extends StatelessWidget {
  const V2App({super.key, this.workspace, this.repository, this.auth});
  final ScheduleWorkspace? workspace;
  final DraftRepository? repository;
  final AuthService? auth;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AKYS V2',
    debugShowCheckedModeBanner: false,
    theme: ClinicalTealTheme.light,
    locale: const Locale('tr'),
    supportedLocales: const [Locale('tr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: repository == null
        ? V2SchedulePage(workspace: workspace)
        : auth == null
        ? const Scaffold(body: Center(child: Text('Yetkilendirme gerekli.')))
        : _AuthorizedWorkspace(auth: auth!, repository: repository!),
  );
}

/// Retain unsaved data during a token refresh, but never render it before AuthGate
/// authorizes. Sign-out and denial dispose state; temporary failure hides it.
class _AuthorizedWorkspace extends StatefulWidget {
  const _AuthorizedWorkspace({required this.auth, required this.repository});
  final AuthService auth;
  final DraftRepository repository;
  @override
  State<_AuthorizedWorkspace> createState() => _AuthorizedWorkspaceState();
}

class _AuthorizedWorkspaceState extends State<_AuthorizedWorkspace> {
  ScheduleWorkspace? workspace;
  DraftSession? session;
  String? ownerId;
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(changed);
    resolve();
  }

  void resolve() {
    final status = widget.auth.state.status;
    final uid = widget.auth.state.userId;
    if (workspace != null && ownerId != uid) {
      session?.dispose();
      workspace?.dispose();
      session = null;
      workspace = null;
    }
    ownerId = uid;
    if (status == AuthStatus.authorized && workspace == null) {
      workspace = ScheduleWorkspace();
      session = DraftSession(workspace!, widget.repository);
    }
    if ([AuthStatus.signedOut, AuthStatus.denied].contains(status)) {
      session?.dispose();
      workspace?.dispose();
      session = null;
      workspace = null;
    }
  }

  void changed() {
    if (!mounted) return;
    final state = widget.auth.state;
    if (ownerId != state.userId ||
        [AuthStatus.signedOut, AuthStatus.denied].contains(state.status)) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    setState(resolve);
  }

  @override
  void dispose() {
    widget.auth.removeListener(changed);
    session?.dispose();
    workspace?.dispose();
    super.dispose();
  }

  Future<void> logout() async {
    if (session?.saving == true || session?.dirty == true) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Kaydedilmemiş değişiklikler'),
          content: Text(
            session?.saving == true
                ? 'Kayıt isteği sürüyor. Çıkış yapılsın mı? Sunucunun önceden kabul ettiği kayıt geri alınmaz; sonucu daha sonra geçmişten kontrol edin.'
                : 'Kaydetmeden çıkış yapılsın mı?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Çıkış yap'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    try {
      await widget.auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Çıkış tamamlanamadı: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authorized = widget.auth.state.status == AuthStatus.authorized;
    return Stack(
      children: [
        Offstage(
          offstage: !authorized,
          child: workspace == null
              ? const SizedBox.shrink()
              : V2SchedulePage(
                  key: ObjectKey(workspace),
                  workspace: workspace,
                  persistenceSession: session,
                  repository: widget.repository,
                  logout: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Yetkiyi yeniden doğrula',
                        onPressed: widget.auth.refreshAuthorization,
                        icon: const Icon(Icons.verified_user_outlined),
                      ),
                      IconButton(
                        tooltip: 'Çıkış yap',
                        onPressed: logout,
                        icon: const Icon(Icons.logout),
                      ),
                    ],
                  ),
                ),
        ),
        if (!authorized)
          AuthGate(auth: widget.auth, child: const SizedBox.shrink()),
      ],
    );
  }
}
