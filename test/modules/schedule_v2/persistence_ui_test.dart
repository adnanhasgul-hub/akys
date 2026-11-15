import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/core/auth/auth_service.dart';
import 'package:akys/core/auth/auth_state.dart';
import 'package:akys/modules/schedule_v2/v2_app.dart';
import 'package:akys/modules/schedule_v2/schedule_page.dart';
import 'package:akys/modules/schedule_v2/data/draft_repository.dart';

import 'persistence_test.dart' as fixtures;

class Auth extends AuthService {
  AuthStatus status = AuthStatus.authorized;
  @override
  AuthState get state => AuthState(status);
  void emit(AuthStatus next) {
    status = next;
    notifyListeners();
  }

  @override
  Future<void> signIn(String email, String password) async =>
      emit(AuthStatus.authorized);
  @override
  Future<void> signOut() async => emit(AuthStatus.signedOut);
}

void main() {
  testWidgets(
    'claim refresh hides private UI without losing local draft; signout wipes it',
    (t) async {
      final auth = Auth();
      addTearDown(auth.dispose);
      final repo = FirestoreDraftRepository(
        FakeFirebaseFirestore(),
        fixtures.Authorization(),
      );
      await t.pumpWidget(V2App(auth: auth, repository: repo));
      await t.pumpAndSettle();
      final w = t
          .widget<V2SchedulePage>(find.byType(V2SchedulePage))
          .workspace!;
      w.restore(fixtures.fixture());
      await t.pumpAndSettle();
      auth.emit(AuthStatus.checking);
      await t.pump();
      expect(find.byType(V2SchedulePage), findsNothing);
      expect(w.closed, false);
      auth.emit(AuthStatus.authorized);
      await t.pumpAndSettle();
      expect(
        t.widget<V2SchedulePage>(find.byType(V2SchedulePage)).workspace,
        same(w),
      );
      expect(w.currentLocks, {0: 0});
      auth.emit(AuthStatus.unavailable);
      await t.pumpAndSettle();
      expect(find.byType(V2SchedulePage), findsNothing);
      expect(w.closed, false);
      auth.emit(AuthStatus.signedOut);
      await t.pumpAndSettle();
      expect(w.closed, true);
      auth.emit(AuthStatus.authorized);
      await t.pumpAndSettle();
      expect(
        t.widget<V2SchedulePage>(find.byType(V2SchedulePage)).workspace,
        isNot(same(w)),
      );
    },
  );
  testWidgets(
    'save, new draft discard warning, list, open, version and disabled approval',
    (t) async {
      final auth = Auth();
      addTearDown(auth.dispose);
      final repo = FirestoreDraftRepository(
        FakeFirebaseFirestore(),
        fixtures.Authorization(),
      );
      await t.pumpWidget(V2App(auth: auth, repository: repo));
      await t.pumpAndSettle();
      final w = t
          .widget<V2SchedulePage>(find.byType(V2SchedulePage))
          .workspace!;
      w.restore(fixtures.fixture(incomplete: true));
      await t.pumpAndSettle();
      await t.tap(find.text('Kaydedilmemiş değişiklikler').first);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('save-draft')));
      await t.pumpAndSettle();
      expect(find.text('Kaydedildi • v1'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Kalıcı onay kapalı'),
            )
            .onPressed,
        isNull,
      );
      w.edit((e) => e.unlock(0));
      await t.pumpAndSettle();
      await t.tap(find.text('Yeni taslak'));
      await t.pumpAndSettle();
      expect(find.text('Değişiklikleri bırak'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await t.pumpAndSettle();
      expect(w.editor.current.assignments[0], 0);
      await t.tap(find.text('Taslakları aç'));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('v1 • draft'));
      await t.pumpAndSettle();
      await t.tap(find.text('Değişiklikleri bırak'));
      await t.pumpAndSettle();
      expect(w.currentLocks, {0: 0});
    },
  );
  testWidgets('repository without Auth cannot render persistent UI', (t) async {
    await t.pumpWidget(
      V2App(
        repository: FirestoreDraftRepository(
          FakeFirebaseFirestore(),
          fixtures.Authorization(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Yetkilendirme gerekli.'), findsOneWidget);
    expect(find.byType(V2SchedulePage), findsNothing);
  });
}
