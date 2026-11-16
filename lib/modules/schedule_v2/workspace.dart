import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../solver_v2/solver.dart';
import '../../solver_v2/editing/schedule_editor.dart';
import '../../solver_v2/editing/reoptimization.dart';
import '../../solver_v2/runtime/lifecycle.dart';
import 'data/draft_snapshot.dart';

/// In-memory application workspace. Never persists a proof or contacts Firebase.
class ScheduleWorkspace extends ChangeNotifier {
  ScheduleWorkspace({Problem? initial, OptimizationController? runtime})
    : runtime =
          runtime ??
          (OptimizationController.webSupported
              ? OptimizationController.web(
                  workerUri: Uri.parse('akys_v2_worker.js'),
                )
              : OptimizationController()) {
    problem = initial ?? emptyMonth(DateTime.now().year, DateTime.now().month);
    editor = ScheduleEditor(problem);
    subscription = this.runtime.events.listen((_) {
      if (!closed) notifyListeners();
    });
  }
  final OptimizationController runtime;
  late final StreamSubscription<OptimizationSnapshot> subscription;
  late Problem problem;
  late ScheduleEditor editor;
  Problem? searchProblem;
  ReoptimizationRequest? request;
  bool closed = false;
  String? error;
  DraftSnapshot? loadedPreview;
  Map<int, int> get currentLocks =>
      loadedPreview?.locks ?? editor.current.locks;
  DraftSnapshot capture({bool preview = false}) => DraftSnapshot(
    problem,
    {for (final d in problem.doctors) d.id: names[d.id] ?? d.id},
    preview ? progress.best!.assignments : editor.current.assignments,
    currentLocks,
  );
  Problem? _encodedProblem;
  EditedSchedule? _encodedSchedule;
  DraftSnapshot? _encodedPreview;
  Map<String, String>? _encodedNames;
  String? _encodedDraft;

  /// Progress notifications do not change a draft. Reuse its serialization only
  /// while immutable problem/editor identities and all mutable names match.
  /// Saving/restoring still runs the independent validator at the boundary.
  String get draftPayload {
    if (_encodedDraft == null ||
        !identical(_encodedProblem, problem) ||
        !identical(_encodedSchedule, editor.current) ||
        !identical(_encodedPreview, loadedPreview) ||
        !mapEquals(_encodedNames, names)) {
      final payload = capture().encode();
      _encodedProblem = problem;
      _encodedSchedule = editor.current;
      _encodedPreview = loadedPreview;
      _encodedNames = Map.of(names);
      _encodedDraft = payload;
    }
    return _encodedDraft!;
  }

  void restore(DraftSnapshot snapshot) {
    if (pending) throw StateError('Önce arama sonucunu kapatın.');
    final replacement = ScheduleEditor(
      snapshot.problem,
      assignments: snapshot.assignments,
    );
    final readOnly =
        snapshot.hasTransition ||
        replacement.current.validity == DraftValidity.invalid;
    if (!readOnly) {
      for (final e in snapshot.locks.entries) {
        if (!replacement.lock(e.key).accepted) {
          throw StateError('Kilit geri yüklenemedi.');
        }
      }
    }
    problem = snapshot.problem;
    editor = replacement;
    loadedPreview = readOnly ? snapshot : null;
    names
      ..clear()
      ..addAll(snapshot.names);
    lastEdit = null;
    error = snapshot.warnings.isEmpty ? null : snapshot.warnings.join('\n');
    notifyListeners();
  }

  EditResult? lastEdit;
  final Map<String, String> names = {};
  OptimizationSnapshot get progress => runtime.value;
  bool get busy => [
    OptimizationState.preparing,
    OptimizationState.running,
    OptimizationState.feasible,
  ].contains(progress.state);
  bool get pending => searchProblem != null;
  String name(int i) =>
      i < 0 ? 'Boş' : names[problem.doctors[i].id] ?? problem.doctors[i].id;
  static Problem emptyMonth(int year, int month) {
    final days = DateTime.utc(year, month + 1, 0).day;
    return Problem(
      doctors: [],
      startDate: DateTime.utc(year, month),
      slotsPerDay: List.filled(days, 2),
      slotRoles: [
        for (var d = 0; d < days; d++) ...[DutyRole.senior, DutyRole.junior],
      ],
      slotRequirements: [
        for (var d = 0; d < days; d++) ...[
          SlotRequirement.required,
          SlotRequirement.optional,
        ],
      ],
      dayDifficulties: [
        for (var d = 1; d <= days; d++)
          DayDifficulty(
            weekdayScore: [
              3,
              3,
              3,
              1,
              6,
              9,
              5,
            ][DateTime.utc(year, month, d).weekday - 1],
          ),
      ],
    );
  }

  void replace(Problem next) {
    if (pending) {
      throw StateError('Önce hesaplama sonucunu kabul edin veya reddedin.');
    }
    final nextEditor = ScheduleEditor(next);
    lastEdit = null;
    loadedPreview = null;
    problem = next;
    editor = nextEditor;
    error = null;
    notifyListeners();
  }

  void edit(EditResult Function(ScheduleEditor) operation) {
    if (pending || loadedPreview != null) return;
    final result = operation(editor);
    if (result.accepted) lastEdit = result;
    error = result.accepted
        ? null
        : result.issues.map((i) => i.message).join('\n');
    notifyListeners();
  }

  Future<void> start({
    bool reoptimize = false,
    Duration budget = const Duration(seconds: 30),
  }) async {
    if (pending) return;
    try {
      request = loadedPreview != null
          ? ReoptimizationRequest(
              problem,
              reference: loadedPreview!.assignments,
              locks: loadedPreview!.locks,
            )
          : reoptimize || currentLocks.isNotEmpty
          ? ReoptimizationRequest.fromEditor(editor)
          : null;
      searchProblem = request?.problem ?? problem;
      error = null;
      notifyListeners();
      await runtime.start(
        searchProblem!,
        options: OptimizationOptions(budget: budget),
      );
    } catch (e) {
      error = 'Hesaplama başlatılamadı: $e';
      searchProblem = null;
      notifyListeners();
    }
  }

  bool get previewOnly =>
      progress.best != null &&
      searchProblem != null &&
      List.generate(searchProblem!.slotDays.length, (i) => i).any((i) {
        final d = progress.best!.assignments[i];
        return d >= 0 &&
            searchProblem!.slotRoles![i] == DutyRole.senior &&
            searchProblem!.doctors[d].group == DutyGroup.junior;
      });
  Future<bool> accept() async {
    final best = progress.best;
    if (searchProblem == null || best == null || previewOnly) return false;
    // Revalidate under the editable source snapshot, never transfer worker proof.
    final replacement = ScheduleEditor(problem, assignments: best.assignments);
    if (!replacement.current.canApprove) {
      error = 'Sonuç bağımsız doğrulamadan geçmedi.';
      notifyListeners();
      return false;
    }
    for (final lock in currentLocks.entries) {
      if (best.assignments[lock.key] != lock.value) {
        error = 'Kilit korunmadı.';
        notifyListeners();
        return false;
      }
      replacement.lock(lock.key);
    }
    await runtime.cancel();
    lastEdit = null;
    loadedPreview = null;
    editor = replacement;
    searchProblem = null;
    request = null;
    error = null;
    notifyListeners();
    return true;
  }

  Future<void> reject() async {
    await runtime.cancel();
    searchProblem = null;
    request = null;
    notifyListeners();
  }

  ReoptimizationDiff? get difference =>
      searchProblem == null || progress.best == null || request == null
      ? null
      : ReoptimizationDiff(searchProblem!, progress.best!);
  @override
  void dispose() {
    closed = true;
    unawaited(subscription.cancel());
    unawaited(runtime.dispose());
    super.dispose();
  }
}
