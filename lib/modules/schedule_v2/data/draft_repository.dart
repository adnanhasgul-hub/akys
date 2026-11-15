import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'draft_snapshot.dart';

abstract class DraftAuthorization {
  Future<String> requireAdmin();
}

class FirebaseDraftAuthorization implements DraftAuthorization {
  FirebaseDraftAuthorization(this.auth);
  final FirebaseAuth auth;
  @override
  Future<String> requireAdmin() async {
    final user = auth.currentUser;
    if (user == null) throw StateError('Giriş gerekli.');
    final token = await user.getIdTokenResult();
    if (auth.currentUser?.uid != user.uid || token.claims?['admin'] != true) {
      throw StateError('Admin yetkisi doğrulanamadı.');
    }
    return user.uid;
  }
}

class VersionConflict implements Exception {
  @override
  String toString() =>
      'Sürüm çakışması. Yerel taslak korundu; son sürümü açın veya yeni revizyon oluşturun.';
}

class DraftRecord {
  DraftRecord(
    this.scheduleId,
    this.version,
    this.status,
    this.snapshot,
    this.actor,
    this.updatedAt,
    this.summary,
    this.sourceId,
    this.sourceVersion,
  );
  final String scheduleId, status, actor, summary;
  final int version;
  final DraftSnapshot snapshot;
  final DateTime? updatedAt;
  final String? sourceId;
  final int? sourceVersion;
}

class SaveDraft {
  SaveDraft({
    required this.id,
    required this.operationId,
    required this.expectedVersion,
    required this.payload,
    required this.summary,
    this.archive = false,
    this.sourceId,
    this.sourceVersion,
  });
  final String id, operationId, payload, summary;
  final int expectedVersion;
  final bool archive;
  final String? sourceId;
  final int? sourceVersion;
}

abstract class DraftRepository {
  SaveDraft prepare(
    DraftSnapshot snapshot, {
    String? id,
    int expectedVersion = 0,
    String summary = 'Taslak kaydı',
    bool archive = false,
    String? sourceId,
    int? sourceVersion,
  });
  Future<DraftRecord> save(SaveDraft request);
  Future<List<DraftRecord>> list();
  Future<DraftRecord> open(String id, {int? version});
  Future<List<DraftRecord>> history(String id);
  Future<void> rejectApproval(String id, int version);
}

class FirestoreDraftRepository implements DraftRepository {
  FirestoreDraftRepository(this.db, this.authorization);
  final FirebaseFirestore db;
  final DraftAuthorization authorization;
  CollectionReference<Map<String, dynamic>> get root =>
      db.collection('v2_schedules');
  @override
  SaveDraft prepare(
    DraftSnapshot snapshot, {
    String? id,
    int expectedVersion = 0,
    String summary = 'Taslak kaydı',
    bool archive = false,
    String? sourceId,
    int? sourceVersion,
  }) {
    final payload = snapshot.encode();
    if (utf8.encode(payload).length > 650000) {
      throw StateError('Taslak 650 KB güvenli belge sınırını aşıyor.');
    }
    if (summary.length > 500) {
      throw StateError('Özet en fazla 500 karakter olabilir.');
    }
    return SaveDraft(
      id: id ?? root.doc().id,
      operationId: root.doc().id,
      expectedVersion: expectedVersion,
      payload: payload,
      summary: summary,
      archive: archive,
      sourceId: sourceId,
      sourceVersion: sourceVersion,
    );
  }

  DraftRecord record(String id, Map<String, dynamic> d) {
    final snapshot = DraftSnapshot.decode(d['payload'] as String);
    if (d['schema'] != 1 ||
        d['year'] != snapshot.problem.startDate!.year ||
        d['month'] != snapshot.problem.startDate!.month ||
        d['version'] is! int ||
        d['version'] < 1 ||
        !['draft', 'archived', 'approved'].contains(d['status'])) {
      throw const FormatException('Çizelge başlığı ve snapshot uyuşmuyor.');
    }
    return DraftRecord(
      id,
      d['version'] as int,
      d['status'] as String,
      snapshot,
      d['actor'] as String,
      (d['at'] as Timestamp?)?.toDate(),
      d['summary'] as String,
      d['sourceId'] as String?,
      d['sourceVersion'] as int?,
    );
  }

  @override
  Future<DraftRecord> save(SaveDraft request) async {
    final uid = await authorization.requireAdmin();
    final snapshot = DraftSnapshot.decode(request.payload);
    final ref = root.doc(request.id),
        event = root
            .doc(request.id)
            .collection('events')
            .doc(request.operationId);
    final version = request.expectedVersion + 1;
    await db.runTransaction((tx) async {
      if (await authorization.requireAdmin() != uid) {
        throw StateError('Kullanıcı değişti.');
      }
      final prior = await tx.get(event);
      if (prior.exists) {
        final saved = await tx.get(ref.collection('versions').doc('$version'));
        if (saved.data()?['operationId'] != request.operationId ||
            saved.data()?['payload'] != request.payload ||
            saved.data()?['actor'] != uid ||
            saved.data()?['summary'] != request.summary ||
            saved.data()?['status'] !=
                (request.archive ? 'archived' : 'draft')) {
          throw StateError('Yeniden deneme kimliği uyuşmuyor.');
        }
        return;
      }
      final current = await tx.get(ref);
      if ((current.data()?['version'] ?? 0) != request.expectedVersion ||
          current.data()?['status'] == 'archived' ||
          current.data()?['status'] == 'approved') {
        throw VersionConflict();
      }
      if (request.sourceId != null) {
        final source = await tx.get(
          root
              .doc(request.sourceId)
              .collection('versions')
              .doc('${request.sourceVersion}'),
        );
        if (!source.exists) throw StateError('Kaynak sürüm bulunamadı.');
      }
      final stamp = FieldValue.serverTimestamp();
      final status = request.archive ? 'archived' : 'draft';
      final action = request.archive
          ? 'archived'
          : version > 1
          ? 'draftUpdated'
          : request.sourceId == null
          ? 'draftCreated'
          : 'revisionCreated';
      final data = <String, dynamic>{
        'schema': 1,
        'version': version,
        'status': status,
        'year': snapshot.problem.startDate!.year,
        'month': snapshot.problem.startDate!.month,
        'actor': uid,
        'at': stamp,
        'operationId': request.operationId,
        'summary': request.summary,
        'sourceId': current.data()?['sourceId'] ?? request.sourceId,
        'sourceVersion':
            current.data()?['sourceVersion'] ?? request.sourceVersion,
        'createdBy': current.data()?['createdBy'] ?? uid,
        'createdAt': current.data()?['createdAt'] ?? stamp,
      };
      tx.set(ref, data);
      tx.set(ref.collection('versions').doc('$version'), {
        ...data,
        'payload': request.payload,
      });
      tx.set(event, {
        'action': action,
        'actor': uid,
        'at': stamp,
        'version': version,
        'operationId': request.operationId,
      });
    });
    return open(request.id, version: version);
  }

  @override
  Future<DraftRecord> open(String id, {int? version}) async {
    await authorization.requireAdmin();
    final ref = root.doc(id);
    final number =
        version ??
        (await ref.get(const GetOptions(source: Source.server)))
                .data()?['version']
            as int?;
    if (number == null) throw StateError('Taslak bulunamadı.');
    final data =
        (await ref
                .collection('versions')
                .doc('$number')
                .get(const GetOptions(source: Source.server)))
            .data();
    if (data == null) throw StateError('Sürüm bulunamadı.');
    return record(id, data);
  }

  @override
  Future<List<DraftRecord>> list() async {
    await authorization.requireAdmin();
    final heads = await root
        .orderBy('at', descending: true)
        .limit(100)
        .get(const GetOptions(source: Source.server));
    return Future.wait(
      heads.docs.map((d) => open(d.id, version: d.data()['version'] as int)),
    );
  }

  @override
  Future<List<DraftRecord>> history(String id) async {
    await authorization.requireAdmin();
    final docs = await root
        .doc(id)
        .collection('versions')
        .orderBy('version', descending: true)
        .limit(100)
        .get(const GetOptions(source: Source.server));
    return docs.docs.map((d) => record(id, d.data())).toList();
  }

  @override
  Future<void> rejectApproval(String id, int version) async {
    final uid = await authorization.requireAdmin();
    final batch = db.batch();
    for (final action in ['approvalAttempt', 'approvalRejected']) {
      final ref = root.doc(id).collection('events').doc();
      batch.set(ref, {
        'action': action,
        'actor': uid,
        'at': FieldValue.serverTimestamp(),
        'version': version,
        'operationId': ref.id,
      });
    }
    await batch.commit();
    throw StateError(
      'Sunucu tarafında klinik doğrulama yok. Kalıcı onay tüm çizelgeler için kapalıdır.',
    );
  }
}
