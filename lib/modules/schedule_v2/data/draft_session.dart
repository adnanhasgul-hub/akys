import 'package:flutter/foundation.dart';

import '../workspace.dart';
import 'draft_repository.dart';

/// A failed/uncertain request retains its exact operation id for safe retry.
class DraftSession extends ChangeNotifier {
  DraftSession(this.workspace, this.repository) {
    workspace.addListener(_changed);
  }
  final ScheduleWorkspace workspace;
  final DraftRepository repository;
  DraftRecord? record;
  SaveDraft? retry;
  String? savedPayload, error;
  bool saving = false, closed = false;
  String? sourceId;
  int? sourceVersion;
  bool get dirty =>
      savedPayload == null || workspace.capture().encode() != savedPayload;
  void _changed() {
    if (!closed) notifyListeners();
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
      if (!closed) notifyListeners();
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
    closed = true;
    workspace.removeListener(_changed);
    super.dispose();
  }
}
