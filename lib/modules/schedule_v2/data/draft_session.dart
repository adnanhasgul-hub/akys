import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../workspace.dart';
import 'draft_repository.dart';
import 'draft_snapshot.dart';
import '../recovery/store.dart';

/// A failed/uncertain request retains its exact operation id for safe retry.
class DraftSession extends ChangeNotifier {
  DraftSession(
    this.workspace,
    this.repository, {
    this.recoveryStore,
    this.owner,
  }) {
    _lastObservedPayload = workspace.draftPayload;
    workspace.addListener(_changed);
    if (recoveryStore != null && owner != null) unawaited(_loadRecovery());
  }
  final ScheduleWorkspace workspace;
  final DraftRepository repository;
  final RecoveryStore? recoveryStore;
  final String? owner;
  Map<String, dynamic>? recoveryCandidate;
  String? recoveryError;
  bool _loadingRecovery = true;
  Timer? _recoveryTimer;
  String? _lastObservedPayload;
  Future<void> _writes = Future.value();

  Future<void> _loadRecovery() async {
    try {
      final raw = await recoveryStore!.read(owner!);
      if (closed) return;
      if (raw != null) {
        final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (data['owner'] != owner || data['schema'] != 1) {
          throw const FormatException('Kurtarma sahibi/şeması geçersiz.');
        }
        DraftSnapshot.decode(data['payload'] as String);
        recoveryCandidate = data;
      }
    } catch (_) {
      if (!closed) {
        recoveryError =
            'Şifreli yerel kurtarma okunamadı. Sunucu kayıtları etkilenmedi.';
      }
    } finally {
      _loadingRecovery = false;
      if (!closed) notifyListeners();
    }
  }

  /// Restore only after a fresh server version check, never trust saved proof.
  Future<void> recover() async {
    final candidate = recoveryCandidate;
    if (candidate == null || saving || workspace.pending) return;
    final before = workspace.draftPayload;
    DraftRecord? base;
    if (candidate['id'] != null) {
      base = await repository.open(candidate['id'] as String);
      if (closed) return;
      if (base.version != candidate['version'] || base.status != 'draft') {
        throw VersionConflict();
      }
    }
    if (workspace.draftPayload != before) {
      throw StateError(
        'Kurtarma kontrolü sırasında yerel taslak değişti; yeniden deneyin.',
      );
    }
    final snapshot = DraftSnapshot.decode(candidate['payload'] as String);
    if (closed) return;
    final saved = candidate['savedPayload'] as String?;
    final source = candidate['sourceId'] as String?;
    final sourceNumber = candidate['sourceVersion'] as int?;
    final command = candidate['retry'];
    final restoredRetry = command == null
        ? null
        : SaveDraft(
            id: command['id'] as String,
            operationId: command['operationId'] as String,
            expectedVersion: command['expectedVersion'] as int,
            payload: command['payload'] as String,
            summary: command['summary'] as String,
            archive: command['archive'] as bool,
            sourceId: command['sourceId'] as String?,
            sourceVersion: command['sourceVersion'] as int?,
          );
    if (restoredRetry != null) DraftSnapshot.decode(restoredRetry.payload);
    // Decode every field before mutating the workspace: malformed recovery is atomic.
    workspace.restore(snapshot);
    record = base;
    savedPayload = saved;
    sourceId = source;
    sourceVersion = sourceNumber;
    retry = restoredRetry;
    recoveryCandidate = null;
    _lastObservedPayload = workspace.draftPayload;
    notifyListeners();
  }

  Future<void> discardRecovery() async {
    if (recoveryStore == null || owner == null) return;
    _writes = _writes
        .catchError((Object _) {})
        .then((_) => recoveryStore!.delete(owner!));
    await _writes;
    if (!closed) {
      recoveryCandidate = null;
      recoveryError = null;
      notifyListeners();
    }
  }

  Future<void> flushRecovery() async {
    _recoveryTimer?.cancel();
    if (closed ||
        _loadingRecovery ||
        recoveryError != null ||
        recoveryCandidate != null ||
        recoveryStore == null ||
        owner == null) {
      return;
    }
    final command = retry;
    final payload = workspace.draftPayload;
    final clean = payload == savedPayload && command == null;
    final encoded = jsonEncode({
      'schema': 1,
      'owner': owner,
      'payload': payload,
      'savedPayload': savedPayload,
      'id': record?.scheduleId,
      'version': record?.version,
      'sourceId': sourceId,
      'sourceVersion': sourceVersion,
      'retry': command == null
          ? null
          : {
              'id': command.id,
              'operationId': command.operationId,
              'expectedVersion': command.expectedVersion,
              'payload': command.payload,
              'summary': command.summary,
              'archive': command.archive,
              'sourceId': command.sourceId,
              'sourceVersion': command.sourceVersion,
            },
    });
    // Capture before queuing; an old UID write can never use a new UID's draft.
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (clean) {
        await recoveryStore!.delete(owner!);
      } else {
        await recoveryStore!.write(owner!, encoded);
      }
    });
    try {
      await _writes;
    } catch (_) {
      if (!closed) {
        recoveryError = 'Yerel kurtarma kaydedilemedi; sunucuya kaydedin.';
        notifyListeners();
      }
    }
  }

  DraftRecord? record;
  SaveDraft? retry;
  String? savedPayload, error;
  bool saving = false, closed = false;
  String? sourceId;
  int? sourceVersion;
  bool get dirty =>
      savedPayload == null || workspace.draftPayload != savedPayload;
  void _changed() {
    if (!closed) {
      final payload = workspace.draftPayload;
      if (payload != _lastObservedPayload) {
        _lastObservedPayload = payload;
        _recoveryTimer?.cancel();
        _recoveryTimer = Timer(
          const Duration(milliseconds: 300),
          () => unawaited(flushRecovery()),
        );
      }
      notifyListeners();
    }
  }

  Future<void> save({bool archive = false, bool preview = false}) async {
    if (saving) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final captured = workspace.capture(preview: preview);
      if (retry == null &&
          record != null &&
          captured.problem.startDate != record!.snapshot.problem.startDate) {
        record = null;
        savedPayload = null;
        sourceId = null;
        sourceVersion = null;
      }
      retry ??= repository.prepare(
        captured,
        id: record?.scheduleId,
        expectedVersion: record?.version ?? 0,
        archive: archive,
        sourceId: sourceId,
        sourceVersion: sourceVersion,
        summary: archive
            ? 'Arşivlendi'
            : preview
            ? 'B aşaması önizlemesi'
            : record == null
            ? 'Yeni taslak'
            : 'Taslak güncellendi',
      );
      final command = retry!;
      await flushRecovery();
      if (closed) return;
      final saved = await repository.save(command);
      if (closed) return;
      record = saved;
      savedPayload = command.payload;
      retry = null;
    } catch (e) {
      if (!closed) {
        error =
            'Kayıt tamamlanamadı veya sonucu belirsiz. Yerel taslak korundu. Aynı isteği yeniden deneyin. $e';
      }
    } finally {
      saving = false;
      if (!closed) {
        notifyListeners();
        await flushRecovery();
      }
    }
  }

  Future<void> open(String id, {int? version}) async {
    if (saving || workspace.pending) {
      throw StateError('Önce aktif işlemi kapatın.');
    }
    final loaded = await repository.open(id, version: version);
    if (closed) return;
    workspace.restore(loaded.snapshot);
    record = loaded;
    savedPayload = loaded.snapshot.encode();
    sourceId = loaded.sourceId;
    sourceVersion = loaded.sourceVersion;
    retry = null;
    error = null;
    notifyListeners();
  }

  void revision() {
    if (saving || record == null || workspace.pending) {
      throw StateError('Önce kaydedilmiş sürümü açın.');
    }
    sourceId = record!.scheduleId;
    sourceVersion = record!.version;
    record = null;
    savedPayload = null;
    retry = null;
    error = null;
    unawaited(flushRecovery());
    notifyListeners();
  }

  void newDraft() {
    if (saving || workspace.pending) {
      throw StateError('Önce aktif işlemi kapatın.');
    }
    final p = workspace.problem;
    workspace.replace(
      ScheduleWorkspace.emptyMonth(p.startDate!.year, p.startDate!.month),
    );
    record = null;
    savedPayload = null;
    sourceId = null;
    sourceVersion = null;
    retry = null;
    error = null;
    notifyListeners();
  }

  Future<void> approval() async {
    if (record == null) throw StateError('Önce taslağı kaydedin.');
    await repository.rejectApproval(record!.scheduleId, record!.version);
  }

  @override
  void dispose() {
    if (_recoveryTimer?.isActive == true) unawaited(flushRecovery());
    _recoveryTimer?.cancel();
    closed = true;
    workspace.removeListener(_changed);
    super.dispose();
  }
}
