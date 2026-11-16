import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:akys/modules/schedule_v2/data/draft_snapshot.dart';
import 'package:akys/modules/schedule_v2/data/draft_repository.dart';
import 'package:akys/modules/schedule_v2/data/draft_session.dart';
import 'package:akys/modules/schedule_v2/workspace.dart';
import 'package:akys/solver_v2/solver.dart';

class Authorization implements DraftAuthorization {
  bool allowed = true;
  @override
  Future<String> requireAdmin() async {
    if (!allowed) throw StateError('Unauthorized');
    return 'admin';
  }
}

DraftSnapshot fixture({
  bool incomplete = false,
  bool transition = false,
  int month = 12,
}) {
  final days = DateTime.utc(2026, month + 1, 0).day;
  final p = Problem(
    startDate: DateTime.utc(2026, month),
    doctors: [
      Doctor(
        id: 'senior-stable',
        seniorityRank: 2,
        seniorityLevel: SeniorityLevel.k4,
        maxDuties: 3,
        unavailable: transition ? {0} : {1},
        previousDuties: [DateTime.utc(2026, month, -2)],
      ),
      Doctor(
        id: 'junior-stable',
        group: DutyGroup.junior,
        maxDuties: 3,
        unavailable: {2},
      ),
    ],
    slotsPerDay: [for (var i = 0; i < days; i++) i == 0 || i == 3 ? 2 : 0],
    slotRoles: [
      DutyRole.senior,
      DutyRole.junior,
      DutyRole.senior,
      DutyRole.junior,
    ],
    slotRequirements: [
      SlotRequirement.required,
      SlotRequirement.optional,
      SlotRequirement.required,
      SlotRequirement.optional,
    ],
    dayDifficulties: [
      for (var i = 0; i < days; i++)
        DayDifficulty(
          weekdayScore: 3,
          holidayName: i == 0 ? 'Manuel tatil' : null,
          holidayScore: i == 0 ? 7 : null,
        ),
    ],
  );
  return DraftSnapshot(
    p,
    {'senior-stable': 'Uzun İsimli Hekim', 'junior-stable': 'Hekim İki'},
    incomplete
        ? [0, -1, -1, -1]
        : transition
        ? [1, -1, 0, 1]
        : [0, 1, 0, 1],
    {0: transition ? 1 : 0},
  );
}

class LostAcknowledgment extends FirestoreDraftRepository {
  LostAcknowledgment(super.db, super.authorization);
  bool fail = true;
  @override
  Future<DraftRecord> save(SaveDraft request) async {
    final result = await super.save(request);
    if (fail) {
      fail = false;
      throw TimeoutException('lost acknowledgment');
    }
    return result;
  }
}

void main() {
  test(
    'dirty cache follows names, assignments, locks, undo and restore',
    () async {
      final w = ScheduleWorkspace(initial: fixture().problem)
        ..restore(fixture());
      final session = DraftSession(
        w,
        FirestoreDraftRepository(FakeFirebaseFirestore(), Authorization()),
      );
      await session.save();
      expect(session.dirty, false);
      final original = w.draftPayload;
      expect(identical(w.draftPayload, original), true);
      w.names['senior-stable'] = 'Changed';
      expect(session.dirty, true);
      w.restore(fixture());
      expect(session.dirty, false);
      w.edit((e) => e.unlock(0));
      expect(session.dirty, true);
      w.edit((e) => e.undo());
      expect(session.dirty, false);
      w.edit((e) => e.remove(1));
      expect(session.dirty, true);
      w.edit((e) => e.undo());
      expect(session.dirty, false);
      session.dispose();
      w.dispose();
    },
  );

  test('invalid restored draft preserves assignments and locks as read-only preview', () {
    final original = fixture();
    final bad = DraftSnapshot(
      original.problem,
      original.names,
      [0, 0, 0, 1],
      {0: 0},
    );
    final workspace = ScheduleWorkspace(initial: original.problem);
    workspace.restore(DraftSnapshot.decode(bad.encode()));
    expect(workspace.loadedPreview, isNotNull);
    expect(workspace.capture().assignments, [0, 0, 0, 1]);
    expect(workspace.currentLocks, {0: 0});
    expect(workspace.editor.current.canApprove, false);
    workspace.dispose();
  });
  test('changing calendar month creates a new schedule instead of rewriting history', () async {
    final repo = FirestoreDraftRepository(
      FakeFirebaseFirestore(),
      Authorization(),
    );
    final workspace = ScheduleWorkspace(initial: fixture().problem)
      ..restore(fixture());
    final session = DraftSession(workspace, repo);
    await session.save();
    final oldId = session.record!.scheduleId;
    workspace.restore(fixture(month: 11));
    await session.save();
    expect(session.error, isNull);
    expect(session.record!.scheduleId, isNot(oldId));
    expect((await repo.open(oldId)).snapshot.problem.startDate!.month, 12);
    session.dispose();
    workspace.dispose();
  });
  test('UTC monthly snapshot preserves roles names ids constraints locks and exact quality', () {
    final original = fixture();
    final restored = DraftSnapshot.decode(original.encode());
    expect(restored.problem.toMessage(), original.problem.toMessage());
    expect(restored.names, original.names);
    expect(restored.locks, original.locks);
    expect(restored.slotIds, original.slotIds);
    expect(restored.quality!.compareTo(original.quality!), 0);
    expect(restored.approvalAllowed, false);
    expect(restored.optimalityProven, false);
  });
  test(
    '30/31 days and previous month dates survive without timezone conversion',
    () {
      for (final m in [11, 12]) {
        final d = DraftSnapshot.decode(fixture(month: m).encode());
        expect(d.problem.startDate, DateTime.utc(2026, m));
        expect(
          d.problem.doctors.first.previousDuties.first,
          DateTime.utc(2026, m, -2),
        );
        expect(d.problem.slotsPerDay.length, m == 11 ? 30 : 31);
      }
    },
  );
  test(
    'incomplete required positions persist but cannot authorize approval',
    () {
      final d = DraftSnapshot.decode(fixture(incomplete: true).encode());
      expect(d.checked.canApprove, false);
      expect(d.quality, isNull);
      expect(d.locks, {0: 0});
    },
  );
  test('B preview quality restored independently without portable proof', () {
    final d = DraftSnapshot.decode(fixture(transition: true).encode());
    expect(d.hasTransition, true);
    expect(d.quality!.components.length, 19);
    expect(d.approvalAllowed, false);
    expect(d.checked.canApprove, false);
  });
  test(
    'stored quality is recalculated; fake proof and slot identity are rejected',
    () {
      final data = jsonDecode(fixture().encode()) as Map<String, dynamic>;
      data['quality']['components'][0]['numerator'] = '999';
      final d = DraftSnapshot.decode(jsonEncode(data));
      expect(d.quality!.components[0].toString(), '0');
      expect(d.warnings, isNotEmpty);
      data['proved'] = true;
      expect(
        () => DraftSnapshot.decode(jsonEncode(data)),
        throwsFormatException,
      );
      data.remove('proved');
      data['slotIds'][0] = 'forged';
      expect(
        () => DraftSnapshot.decode(jsonEncode(data)),
        throwsFormatException,
      );
    },
  );
  test('duplicate or out of range positions never become approved on load', () {
    final data = jsonDecode(fixture().encode()) as Map<String, dynamic>;
    data['assignments'][1] = 0;
    final d = DraftSnapshot.decode(jsonEncode(data));
    expect(d.checked.canApprove, false);
    expect(d.quality, isNull);
    data['assignments'][1] = 99;
    expect(() => DraftSnapshot.decode(jsonEncode(data)), throwsFormatException);
  });
  test('valid save open list history and atomic metadata', () async {
    final db = FakeFirebaseFirestore();
    final r = FirestoreDraftRepository(db, Authorization());
    final a = await r.save(r.prepare(fixture()));
    expect(a.version, 1);
    expect(a.updatedAt, isNotNull);
    expect((await r.list()).length, 1);
    final b = await r.save(
      r.prepare(
        fixture(incomplete: true),
        id: a.scheduleId,
        expectedVersion: 1,
      ),
    );
    expect(b.version, 2);
    expect((await r.history(a.scheduleId)).map((v) => v.version), [2, 1]);
    expect(
      (await r.open(a.scheduleId, version: 1)).snapshot.quality,
      isNotNull,
    );
    expect(
      (await db
              .collection('v2_schedules')
              .doc(a.scheduleId)
              .collection('events')
              .get())
          .docs
          .length,
      2,
    );
  });
  test('stale version rejected and previous payload preserved', () async {
    final r = FirestoreDraftRepository(
      FakeFirebaseFirestore(),
      Authorization(),
    );
    final saved = await r.save(r.prepare(fixture()));
    await expectLater(
      r.save(
        r.prepare(
          fixture(incomplete: true),
          id: saved.scheduleId,
          expectedVersion: 0,
        ),
      ),
      throwsA(isA<VersionConflict>()),
    );
    expect(
      (await r.open(saved.scheduleId)).snapshot.assignments,
      fixture().assignments,
    );
  });
  test('idempotent retry does not create an extra version or event', () async {
    final db = FakeFirebaseFirestore();
    final r = FirestoreDraftRepository(db, Authorization());
    final request = r.prepare(fixture());
    await r.save(request);
    final again = await r.save(request);
    expect(again.version, 1);
    expect((await r.history(again.scheduleId)).length, 1);
    expect(
      (await db
              .collection('v2_schedules')
              .doc(again.scheduleId)
              .collection('events')
              .get())
          .docs
          .length,
      1,
    );
  });
  test(
    'revision retains source relationship and immutable old snapshot',
    () async {
      final r = FirestoreDraftRepository(
        FakeFirebaseFirestore(),
        Authorization(),
      );
      final a = await r.save(r.prepare(fixture()));
      final b = await r.save(
        r.prepare(
          fixture(incomplete: true),
          sourceId: a.scheduleId,
          sourceVersion: 1,
        ),
      );
      expect(b.scheduleId, isNot(a.scheduleId));
      expect(b.sourceId, a.scheduleId);
      expect(b.sourceVersion, 1);
      expect((await r.open(a.scheduleId)).snapshot.checked.canApprove, true);
    },
  );
  test(
    'archive prohibits future writes while revision stays available',
    () async {
      final r = FirestoreDraftRepository(
        FakeFirebaseFirestore(),
        Authorization(),
      );
      final a = await r.save(r.prepare(fixture()));
      final b = await r.save(
        r.prepare(
          fixture(),
          id: a.scheduleId,
          expectedVersion: 1,
          archive: true,
        ),
      );
      expect(b.status, 'archived');
      await expectLater(
        r.save(r.prepare(fixture(), id: a.scheduleId, expectedVersion: 2)),
        throwsA(isA<VersionConflict>()),
      );
    },
  );
  test('data access denies revoked admin even without UI gate', () async {
    final auth = Authorization();
    final r = FirestoreDraftRepository(FakeFirebaseFirestore(), auth);
    final a = await r.save(r.prepare(fixture()));
    auth.allowed = false;
    await expectLater(r.list(), throwsStateError);
    await expectLater(r.open(a.scheduleId), throwsStateError);
    await expectLater(r.save(r.prepare(fixture())), throwsStateError);
    await expectLater(r.rejectApproval(a.scheduleId, 1), throwsStateError);
  });
  test(
    'approval attempt writes rejection events but never approval status',
    () async {
      final db = FakeFirebaseFirestore();
      final r = FirestoreDraftRepository(db, Authorization());
      final a = await r.save(r.prepare(fixture(transition: true)));
      await expectLater(r.rejectApproval(a.scheduleId, 1), throwsStateError);
      expect((await r.open(a.scheduleId)).status, 'draft');
      final events = await db
          .collection('v2_schedules')
          .doc(a.scheduleId)
          .collection('events')
          .get();
      expect(
        events.docs.map((d) => d.data()['action']),
        containsAll(['approvalAttempt', 'approvalRejected']),
      );
    },
  );
  test('lost acknowledgment and edit after timeout preserve local state and safe retry', () async {
    final w = ScheduleWorkspace(initial: fixture().problem);
    addTearDown(w.dispose);
    w.restore(fixture());
    final r = LostAcknowledgment(FakeFirebaseFirestore(), Authorization());
    final s = DraftSession(w, r);
    addTearDown(s.dispose);
    await s.save();
    expect(s.error, isNotNull);
    expect(s.retry, isNotNull);
    w.edit((e) => e.remove(3));
    final local = [...w.editor.current.assignments];
    await s.save();
    expect(s.record!.version, 1);
    expect(w.editor.current.assignments, local);
    expect(s.dirty, true);
    await s.save();
    expect(s.record!.version, 2);
    expect(s.dirty, false);
  });
  test(
    'new revision and reopened locks never resurrect optimum proof',
    () async {
      final w = ScheduleWorkspace(initial: fixture().problem);
      addTearDown(w.dispose);
      w.restore(fixture());
      final s = DraftSession(
        w,
        FirestoreDraftRepository(FakeFirebaseFirestore(), Authorization()),
      );
      addTearDown(s.dispose);
      await s.save();
      final id = s.record!.scheduleId;
      w.edit((e) => e.remove(3));
      expect(s.dirty, true);
      await s.open(id);
      expect(w.currentLocks, {0: 0});
      expect(w.editor.current.optimalityProven, false);
      s.revision();
      await s.save();
      expect(s.record!.sourceId, id);
    },
  );
  test('restored B stays readonly and retains locks for new AB search', () {
    final w = ScheduleWorkspace(initial: fixture().problem);
    addTearDown(w.dispose);
    w.restore(fixture(transition: true));
    expect(w.loadedPreview, isNotNull);
    expect(w.currentLocks, {0: 1});
    w.edit((e) => e.remove(0));
    expect(w.editor.current.assignments[0], 1);
    expect(w.capture().locks, {0: 1});
  });
}
