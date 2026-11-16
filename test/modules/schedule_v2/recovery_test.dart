import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/modules/schedule_v2/recovery/store.dart';
import 'package:akys/modules/schedule_v2/data/draft_session.dart';
import 'package:akys/modules/schedule_v2/data/draft_repository.dart';
import 'package:akys/modules/schedule_v2/workspace.dart';

import 'persistence_test.dart' as fixtures;

// Test transport only. Real encryption is tested independently in Chromium.
class MemoryRecovery implements RecoveryStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String owner) async => values[owner];
  @override
  Future<void> write(String owner, String plaintext) async {
    values[owner] = plaintext;
  }

  @override
  Future<void> delete(String owner) async {
    values.remove(owner);
  }
}

Future<void> loaded() => Future<void>.delayed(Duration.zero);
void main() {
  test('malformed retry does not partially restore a valid snapshot', () async {
    final store = MemoryRecovery();
    store.values['a'] = jsonEncode({
      'schema': 1,
      'owner': 'a',
      'payload': fixtures.fixture().encode(),
      'retry': {'id': 42},
    });
    final w = ScheduleWorkspace();
    final s = DraftSession(
      w,
      FirestoreDraftRepository(
        FakeFirebaseFirestore(),
        fixtures.Authorization(),
      ),
      owner: 'a',
      recoveryStore: store,
    );
    await loaded();
    final before = w.draftPayload;
    await expectLater(s.recover(), throwsA(anything));
    expect(w.draftPayload, before);
    expect(s.recoveryCandidate, isNotNull);
    s.dispose();
    w.dispose();
  });

  test('unsaved draft recovers with locks only for same owner', () async {
    final store = MemoryRecovery();
    final repo = FirestoreDraftRepository(
      FakeFirebaseFirestore(),
      fixtures.Authorization(),
    );
    final w = ScheduleWorkspace(initial: fixtures.fixture().problem)
      ..restore(fixtures.fixture());
    final s = DraftSession(w, repo, recoveryStore: store, owner: 'a');
    await loaded();
    await s.flushRecovery();
    s.dispose();
    w.dispose();
    final other = ScheduleWorkspace();
    final b = DraftSession(other, repo, recoveryStore: store, owner: 'b');
    await loaded();
    expect(b.recoveryCandidate, isNull);
    b.dispose();
    other.dispose();
    final restored = ScheduleWorkspace();
    final a = DraftSession(restored, repo, recoveryStore: store, owner: 'a');
    await loaded();
    expect(a.recoveryCandidate, isNotNull);
    await a.recover();
    expect(restored.capture().assignments, fixtures.fixture().assignments);
    expect(restored.currentLocks, fixtures.fixture().locks);
    expect(a.dirty, true);
    expect(restored.editor.current.optimalityProven, false);
    await a.save();
    expect(a.error, isNull);
    expect(store.values['a'], isNull);
    a.dispose();
    restored.dispose();
  });
  test(
    'fresh server conflict blocks recovery and retains local candidate',
    () async {
      final store = MemoryRecovery();
      final repo = FirestoreDraftRepository(
        FakeFirebaseFirestore(),
        fixtures.Authorization(),
      );
      final w = ScheduleWorkspace(initial: fixtures.fixture().problem)
        ..restore(fixtures.fixture());
      final s = DraftSession(w, repo, recoveryStore: store, owner: 'a');
      await loaded();
      await s.save();
      final original = s.record!;
      w.names['senior-stable'] = 'Unsaved name';
      await s.flushRecovery();
      s.dispose();
      w.dispose();
      await repo.save(
        repo.prepare(
          original.snapshot,
          id: original.scheduleId,
          expectedVersion: 1,
        ),
      );
      final next = ScheduleWorkspace();
      final session = DraftSession(
        next,
        repo,
        recoveryStore: store,
        owner: 'a',
      );
      await loaded();
      final before = next.draftPayload;
      await expectLater(session.recover(), throwsA(isA<VersionConflict>()));
      expect(next.draftPayload, before);
      expect(session.recoveryCandidate, isNotNull);
      await session.discardRecovery();
      expect(store.values, isEmpty);
      session.dispose();
      next.dispose();
    },
  );
  test('closed owner ignores late recovery data and malformed envelope fails closed', () async {
    final store = MemoryRecovery()..values['a'] = '{"schema":1,"owner":"b"}';
    final w = ScheduleWorkspace();
    final s = DraftSession(
      w,
      FirestoreDraftRepository(
        FakeFirebaseFirestore(),
        fixtures.Authorization(),
      ),
      owner: 'a',
      recoveryStore: store,
    );
    await loaded();
    expect(s.recoveryCandidate, isNull);
    expect(s.recoveryError, isNotNull);
    s.dispose();
    w.dispose();
  });
}
