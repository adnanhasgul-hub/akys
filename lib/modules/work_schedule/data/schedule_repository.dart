import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models.dart';
import '../domain/difficulty.dart';
import '../engine/duty_engine.dart';
import '../engine/task_engine.dart';

String canonical(Object? value) {
  Object? ordered(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final key in keys) key: ordered(v[key])};
    }
    if (v is List) return v.map(ordered).toList();
    return v;
  }

  return jsonEncode(ordered(value));
}

abstract class ScheduleRepository {
  Future<DifficultySettings> loadDifficultySettings();
  Future<DifficultySettings> saveDifficultySettings(
    DifficultySettings before,
    DifficultySettings after,
  );
  Future<void> initialize();
  Stream<List<Personnel>> watchPersonnel();
  Future<void> replacePersonnel(List<Personnel> before, List<Personnel> after);
  Stream<List<ScheduleMonth>> watchMonths();
  Future<ScheduleMonth?> loadMonth(String id);
  Future<ScheduleMonth> saveMonth(ScheduleMonth month, {bool create = false});
  Future<ScheduleMonth> refreshMonthDutyGroups(ScheduleMonth month);
  Future<String> share(ScheduleMonth month);
  Future<void> revoke(ScheduleMonth month, String token);
  Stream<Map<String, dynamic>?> watchShared(String token);
}

class ScheduleConflict implements Exception {
  const ScheduleConflict(this.message);
  final String message;
}

Map<String, dynamic> publicProjection(ScheduleMonth m) => {
  'schemaVersion': 1,
  'monthId': m.id,
  'title': m.title,
  'year': m.year,
  'month': m.month,
  'days': m.days,
  'people': [
    for (final p in m.people)
      {
        'personId': p.personId,
        'displayName': p.displayName,
        'seniorityRank': p.seniorityRank,
      },
  ],
  'duties': {for (var d = 1; d <= m.days; d++) '$d': m.duties[d] ?? <String>[]},
  'dailyTasks': {
    for (var d = 1; d <= m.days; d++)
      '$d': [
        for (final t in dailyTasks(m, d))
          if (t.active)
            {
              'task': t.task.name,
              if (t.halfDay) 'halfDay': true,
              'personId': t.personId,
              'manual': t.manual,
              'warnings': t.warnings,
            },
      ],
  },
  'revoked': false,
};

class FirestoreScheduleRepository implements ScheduleRepository {
  FirestoreScheduleRepository([FirebaseFirestore? firestore])
    : _provided = firestore;
  final FirebaseFirestore? _provided;
  FirebaseFirestore get db => _provided ?? FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get root =>
      db.doc('work_schedule/main');
  CollectionReference<Map<String, dynamic>> get months =>
      root.collection('months');
  CollectionReference<Map<String, dynamic>> get shares =>
      db.collection('shared_schedules');
  DocumentReference<Map<String, dynamic>> get difficultyRef =>
      root.collection('settings').doc('difficulty');
  @override
  Future<DifficultySettings> loadDifficultySettings() async {
    final doc = await difficultyRef.get(
      const GetOptions(source: Source.server),
    );
    return doc.exists
        ? DifficultySettings.fromJson(doc.data()!)
        : DifficultySettings.defaults();
  }

  @override
  Future<DifficultySettings> saveDifficultySettings(
    DifficultySettings before,
    DifficultySettings after,
  ) async {
    after.validate();
    return db.runTransaction((tx) async {
      final doc = await tx.get(difficultyRef);
      final current = doc.exists
          ? DifficultySettings.fromJson(doc.data()!)
          : DifficultySettings.defaults();
      if (canonical(current.toJson()) != canonical(before.toJson())) {
        throw const ScheduleConflict(
          'Puanlama ayarları başka bir oturumda değişti. Yeniden yükleyin.',
        );
      }
      final next = after.withRevision(current.revision + 1);
      tx.set(difficultyRef, next.toJson());
      return next;
    });
  }

  @override
  Future<void> initialize() async {
    // Existing personnel are never replaced by seeding. The registry document is
    // the transaction lock for seeding and rank changes across all clients.
    final existing = await root
        .collection('personnel')
        .get(const GetOptions(source: Source.server));
    final found = [
      for (final d in existing.docs)
        Personnel.fromJson({...d.data(), 'id': d.id}),
    ]..sort((a, b) => a.seniorityRank.compareTo(b.seniorityRank));
    await db.runTransaction((tx) async {
      final registry = await tx.get(root);
      final stored = registry.data()?['personnel'] as List?;
      if (stored != null) {
        final migrated = [
          for (final raw in stored)
            {
              ...Map<String, dynamic>.from(raw as Map),
              'dutySeniorityGroup': readDutyGroup(
                raw['dutySeniorityGroup'],
                raw['seniorityRank'] as int,
              ).name,
            },
        ];
        if (canonical(stored) != canonical(migrated)) {
          tx.update(root, {'personnel': migrated});
          for (final raw in migrated) {
            tx.set(
              root.collection('personnel').doc(raw['id'] as String),
              Personnel.fromJson(raw).toJson(),
              SetOptions(merge: true),
            );
          }
        }
        return;
      }
      final people = seedPersonnel(
        found,
        DateTime.now().toUtc().toIso8601String(),
      );
      final ranked = reorderPersonnel(people, people.map((p) => p.id).toList());
      tx.set(root, {
        'personnel': ranked.map((p) => p.toJson()).toList(),
      }, SetOptions(merge: true));
      for (final p in ranked) {
        tx.set(root.collection('personnel').doc(p.id), p.toJson());
      }
    });
  }

  @override
  Stream<List<Personnel>> watchPersonnel() => root.snapshots().map(
    (s) => [
      for (final p in s.data()?['personnel'] as List? ?? [])
        Personnel.fromJson(Map<String, dynamic>.from(p as Map)),
    ]..sort((a, b) => a.seniorityRank.compareTo(b.seniorityRank)),
  );
  @override
  Future<void> replacePersonnel(
    List<Personnel> before,
    List<Personnel> after,
  ) async {
    if (after.length > 400) {
      throw const ScheduleConflict('En fazla 400 personel kaydedilebilir.');
    }
    final ids = after.map((p) => p.id).toSet();
    if (ids.length != after.length ||
        after.any(
          (p) => p.displayName.trim().isEmpty || p.displayName.length > 120,
        ) ||
        !ids.containsAll(before.map((p) => p.id))) {
      throw const ScheduleConflict('Geçersiz personel değişikliği.');
    }
    final ranked = reorderPersonnel(after, after.map((p) => p.id).toList());
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(root);
      final current = [
        for (final raw in snapshot.data()?['personnel'] as List? ?? [])
          Personnel.fromJson(Map<String, dynamic>.from(raw as Map)),
      ]..sort((a, b) => a.seniorityRank.compareTo(b.seniorityRank));
      if (canonical(current.map((p) => p.toJson()).toList()) !=
          canonical(before.map((p) => p.toJson()).toList())) {
        throw const ScheduleConflict(
          'Personel başka bir oturumda değişti. Listeyi yeniden yükleyin.',
        );
      }
      tx.update(root, {'personnel': ranked.map((p) => p.toJson()).toList()});
      for (final p in ranked) {
        tx.set(root.collection('personnel').doc(p.id), p.toJson());
      }
    });
  }

  @override
  Stream<List<ScheduleMonth>> watchMonths() => months.snapshots().map(
    (s) =>
        [for (final d in s.docs) ScheduleMonth.fromJson(d.data())]
          ..sort((a, b) => b.id.compareTo(a.id)),
  );
  @override
  Future<ScheduleMonth?> loadMonth(String id) async {
    final d = await months.doc(id).get(const GetOptions(source: Source.server));
    return d.exists ? ScheduleMonth.fromJson(d.data()!) : null;
  }

  @override
  Future<ScheduleMonth> saveMonth(
    ScheduleMonth month, {
    bool create = false,
  }) async {
    final next = month.clone()
      ..revision = month.revision + 1
      ..updatedAt = DateTime.now().toUtc().toIso8601String();
    return db.runTransaction((tx) async {
      final ref = months.doc(next.id);
      final old = await tx.get(ref);
      if (create && next.difficultySchemaVersion > 0) {
        final settingsDoc = await tx.get(difficultyRef);
        final current = settingsDoc.exists
            ? DifficultySettings.fromJson(settingsDoc.data()!)
            : DifficultySettings.defaults();
        if (current.revision != next.difficultySettingsSnapshot?.revision) {
          throw const ScheduleConflict(
            'Puanlama ayarları değişti. Tatil puanlarını yeniden doğrulayın.',
          );
        }
        next.difficulty.validateMonth(next.year, next.month);
      }
      if (create ? old.exists : !old.exists) {
        throw const ScheduleConflict(
          'Ay zaten var veya silinmiş. Yeniden yükleyin.',
        );
      }
      if (old.exists) {
        final prior = ScheduleMonth.fromJson(old.data()!);
        if (prior.revision != month.revision) {
          throw const ScheduleConflict(
            'Bu ay başka bir oturumda değişti. Kaydetmeden yeniden yükleyin.',
          );
        }
        if (prior.taskWorkdaySchemaVersion != next.taskWorkdaySchemaVersion ||
            canonical(
                  prior.taskHolidayCalendarSnapshot
                      .map((h) => h.toJson())
                      .toList(),
                ) !=
                canonical(
                  next.taskHolidayCalendarSnapshot
                      .map((h) => h.toJson())
                      .toList(),
                )) {
          if (!prior.editable ||
              prior.taskWorkdaySchemaVersion != 0 ||
              next.taskWorkdaySchemaVersion != 1) {
            throw const ScheduleConflict(
              'Görev iş günü snapshot’ı yalnız eski taslakta etkinleştirilebilir.',
            );
          }
        }
        final beforeDifficulty = {
          for (final key in [
            'difficultySchemaVersion',
            'difficultySettingsSnapshot',
            'holidayCalendarSnapshot',
            'holidayDifficultyOverrides',
          ])
            key: prior.toJson()[key],
        };
        final afterDifficulty = {
          for (final key in beforeDifficulty.keys) key: next.toJson()[key],
        };
        if (canonical(beforeDifficulty) != canonical(afterDifficulty)) {
          throw const ScheduleConflict(
            'Aylık puan snapshot’ı değiştirilemez. Yeni ay güncel ayarları kullanır.',
          );
        }
        if (canonical(prior.people.map((p) => p.toJson()).toList()) !=
            canonical(next.people.map((p) => p.toJson()).toList())) {
          throw const ScheduleConflict(
            'Geçmiş ayın personel snapshot’ı değiştirilemez.',
          );
        }
        if (!prior.editable) {
          final priorContent = prior.toJson()
            ..remove('status')
            ..remove('revision')
            ..remove('updatedAt');
          final nextContent = month.toJson()
            ..remove('status')
            ..remove('revision')
            ..remove('updatedAt');
          if (canonical(priorContent) != canonical(nextContent)) {
            throw const ScheduleConflict(
              'Kesin ayı değiştirmeden önce düzenlemeye açın.',
            );
          }
          if (next.status == MonthStatus.draft) {
            next.shareTokens.clear();
            next.publishedAt = null;
            for (final token in prior.shareTokens) {
              tx.update(shares.doc(token), {'revoked': true});
            }
          }
        }
      }
      if (!next.editable && validateDuties(next).isNotEmpty) {
        throw const ScheduleConflict(
          'Kesinleştirmeden önce nöbet hatalarını düzeltin.',
        );
      }
      tx.set(ref, next.toJson());
      return next;
    });
  }

  /// The only operation allowed to explicitly change groups in an existing
  /// snapshot. Rank/name/activeAtCreation stay frozen; a draft is required.
  @override
  Future<ScheduleMonth> refreshMonthDutyGroups(ScheduleMonth month) async {
    return db.runTransaction((tx) async {
      final stored = await tx.get(months.doc(month.id));
      final registry = await tx.get(root);
      if (!stored.exists) throw const ScheduleConflict('Ay bulunamadı.');
      final next = ScheduleMonth.fromJson(stored.data()!);
      if (next.revision != month.revision) {
        throw const ScheduleConflict(
          'Ay başka bir oturumda değişti. Yeniden yükleyin.',
        );
      }
      if (!next.editable) {
        throw const ScheduleConflict('Önce ayı düzenlemeye açın.');
      }
      final current = {
        for (final raw in registry.data()?['personnel'] as List? ?? [])
          (raw as Map)['id'] as String: Personnel.fromJson(
            Map<String, dynamic>.from(raw),
          ),
      };
      if (next.people.any((p) => !current.containsKey(p.personId))) {
        throw const ScheduleConflict(
          'Snapshot personeli güncel listede bulunamadı; grup güncellemesi yapılamadı.',
        );
      }
      final before = {
        for (final p in next.people) p.personId: p.dutySeniorityGroup.name,
      };
      final after = {
        for (final p in next.people)
          p.personId: current[p.personId]!.dutySeniorityGroup.name,
      };
      if (canonical(before) == canonical(after)) return next;
      final now = DateTime.now().toUtc().toIso8601String();
      for (var i = 0; i < next.people.length; i++) {
        final p = next.people[i];
        next.people[i] = PersonSnapshot(
          p.personId,
          p.displayName,
          p.seniorityRank,
          activeAtCreation: p.activeAtCreation,
          dutySeniorityGroup: current[p.personId]!.dutySeniorityGroup,
        );
      }
      next.duties.clear();
      next.manuallyEdited.clear();
      next.snapshotGroupUpdates.add({
        'at': now,
        'before': before,
        'after': after,
      });
      next.schemaVersion = next.difficultySchemaVersion > 0 ? 3 : 2;
      next.revision++;
      next.updatedAt = now;
      tx.set(months.doc(next.id), next.toJson());
      return next;
    });
  }

  @override
  Future<String> share(ScheduleMonth month) async {
    final token = randomId();
    await db.runTransaction((tx) async {
      final ref = months.doc(month.id);
      final snap = await tx.get(ref);
      if (!snap.exists) throw const ScheduleConflict('Ay bulunamadı.');
      final m = ScheduleMonth.fromJson(snap.data()!);
      if (m.revision != month.revision) {
        throw const ScheduleConflict('Ay değişti. Yeniden yükleyin.');
      }
      if (m.status != MonthStatus.finalised &&
          m.status != MonthStatus.published) {
        throw const ScheduleConflict('Yalnızca kesin ay paylaşılabilir.');
      }
      if (m.shareTokens.length >= 10) {
        throw const ScheduleConflict(
          'Bu ay için en fazla 10 bağlantı oluşturulabilir.',
        );
      }
      if (validateDuties(m).isNotEmpty) {
        throw const ScheduleConflict('Çizelge doğrulanamadı.');
      }
      tx.set(shares.doc(token), {
        ...publicProjection(m),
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().add(const Duration(days: 366)),
        ),
      });
      m.shareTokens.add(token);
      m.status = MonthStatus.published;
      m.publishedAt = DateTime.now().toUtc().toIso8601String();
      m.updatedAt = m.publishedAt!;
      m.revision++;
      tx.update(ref, m.toJson());
    });
    return token;
  }

  @override
  Future<void> revoke(ScheduleMonth month, String token) async {
    await db.runTransaction((tx) async {
      final snap = await tx.get(months.doc(month.id));
      if (!snap.exists) throw const ScheduleConflict('Ay bulunamadı.');
      final m = ScheduleMonth.fromJson(snap.data()!);
      if (m.revision != month.revision || !m.shareTokens.contains(token)) {
        throw const ScheduleConflict('Ay değişti. Yeniden yükleyin.');
      }
      tx.update(shares.doc(token), {'revoked': true});
      m.shareTokens.remove(token);
      m.revision++;
      m.updatedAt = DateTime.now().toUtc().toIso8601String();
      tx.update(months.doc(m.id), m.toJson());
    });
  }

  @override
  Stream<Map<String, dynamic>?> watchShared(String token) => shares
      .doc(token)
      .snapshots(includeMetadataChanges: true)
      .map((s) => s.metadata.isFromCache ? null : s.data());
}
