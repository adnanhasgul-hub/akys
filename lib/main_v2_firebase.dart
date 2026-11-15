// Explicit emulator-only connected entry. Production is not enabled by this task.
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'core/auth/firebase_auth_service.dart';
import 'modules/schedule_v2/v2_app.dart';
import 'modules/schedule_v2/data/draft_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const host = String.fromEnvironment('AKYS_V2_EMULATOR_HOST');
  if (!['127.0.0.1', 'localhost', '10.0.2.2'].contains(host)) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Yerel Firebase Emulator adresi gerekli. Production bağlantısı kapalı.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  final app = await Firebase.initializeApp(
    name: 'akys-v2-emulator',
    options: const FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: '1:123456:web:local',
      messagingSenderId: '123456',
      projectId: 'demo-akys',
    ),
  );
  final auth = FirebaseAuth.instanceFor(app: app);
  await auth.useAuthEmulator(host, 9099);
  final db = FirebaseFirestore.instanceFor(app: app);
  db.useFirestoreEmulator(host, 8080, automaticHostMapping: false);
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
