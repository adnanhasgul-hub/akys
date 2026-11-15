import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/auth/firebase_auth_service.dart';
import 'firebase_options.dart';
import 'modules/schedule_v2/data/draft_repository.dart';
import 'modules/schedule_v2/v2_app.dart';

/// Standard AKYS entry. Tests must explicitly select the isolated demo backend.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  const host = String.fromEnvironment('AKYS_V2_EMULATOR_HOST');
  if (host.isNotEmpty &&
      !['127.0.0.1', 'localhost', '10.0.2.2'].contains(host)) {
    throw StateError('Geçersiz yerel Emulator adresi.');
  }
  final app = host.isEmpty
      ? await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        )
      : await Firebase.initializeApp(
          name: 'akys-v2-emulator',
          options: const FirebaseOptions(
            apiKey: 'demo-api-key',
            appId: '1:123456:web:local',
            messagingSenderId: '123456',
            projectId: 'demo-akys',
          ),
        );
  final auth = FirebaseAuth.instanceFor(app: app);
  final db = FirebaseFirestore.instanceFor(app: app);
  if (host.isNotEmpty) {
    await auth.useAuthEmulator(host, 9099);
    db.useFirestoreEmulator(host, 8080, automaticHostMapping: false);
  }
  // Private data is server-backed, not shared through a persistent cross-account cache.
  db.settings = const Settings(persistenceEnabled: false);
  runApp(
    V2App(
      auth: FirebaseAuthService(auth),
      repository: FirestoreDraftRepository(
        db,
        FirebaseDraftAuthorization(auth),
      ),
    ),
  );
}
