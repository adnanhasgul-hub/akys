import '../solver.dart';
import '../solution_validator.dart';
import '../clinical_quality.dart';

enum EditCode {
  slotIndex,
  doctorIndex,
  locked,
  emptySource,
  occupiedTarget,
  noHistory,
  requiredMissing,
  mustMissing,
  unavailable,
  duplicateDay,
  rest,
  previousMonthRest,
  capacity,
  role,
  transitionEvidence,
  independentValidation,
}

enum DraftValidity { incomplete, valid, provisionalTransition, invalid }

final class EditIssue {
  const EditIssue(
    this.code,
    this.message, {
    this.slot,
    this.date,
    this.personId,
  });
  final EditCode code;
  final String message;
  final int? slot;
  final DateTime? date;
  final String? personId;
  bool get isIncomplete =>
      code == EditCode.requiredMissing || code == EditCode.mustMissing;
}

/// Locks are independent slot->doctor data, suitable for a future optimization adapter.
/// ReoptimizationRequest.fromEditor explicitly snapshots them as solver constraints.
final class EditedSchedule {
  EditedSchedule._(
    List<int> assignments,
    Map<int, int> locks,
    List<EditIssue> issues,
    this.solution,
    this.validity,
  ) : assignments = List.unmodifiable(assignments),
      locks = Map.unmodifiable(locks),
      issues = List.unmodifiable(issues);
  final List<int> assignments;
  final Map<int, int> locks;
  final List<EditIssue> issues;
  final Solution? solution;
  final DraftValidity validity;
  ClinicalQuality? get quality => solution?.clinicalQuality;
  bool get optimalityProven => false;

  /// Clinical eligibility only; does not grant app/Firestore publication permission.
  bool get canApprove => validity == DraftValidity.valid;
}

final class EditResult {
  EditResult(this.accepted, this.before, this.after, List<EditIssue> issues)
    : issues = List.unmodifiable(issues);
  final bool accepted;
  final EditedSchedule before, after;
  final List<EditIssue> issues;

  /// Negative means improvement; null means one endpoint is incomplete/unverified.
  int? get qualityComparison => before.quality == null || after.quality == null
      ? null
      : after.quality!.compareTo(before.quality!);
}

final class _Revision {
  _Revision(EditedSchedule state)
    : assignments = state.assignments,
      locks = state.locks;
  final List<int> assignments;
  final Map<int, int> locks;
}

/// Synchronous pure Dart editing. No search, persistence, or portable proof creation.
final class ScheduleEditor {
  ScheduleEditor(this.problem, {List<int>? assignments, this.localEvidence}) {
    if (problem.startDate == null ||
        problem.slotRoles == null ||
        problem.dayDifficulties == null ||
        !problem.hasExplicitSlotRequirements ||
        problem.doctors.any(
          (d) => d.group == DutyGroup.senior && d.seniorityLevel == null,
        )) {
      throw ArgumentError('Eksiksiz klinik snapshot gerekli.');
    }
    final initial =
        assignments ?? List.filled(problem.slotDays.length, unfilledSlot);
    if (initial.length != problem.slotDays.length) {
      throw ArgumentError('Pozisyon sayısı uyuşmuyor.');
    }
    _current = _evaluate(initial, {});
  }
  final Problem problem;

  /// Genuine process-local session, never a serialized boolean. The exact snapshot
  /// identity must match. Completed sessions authorize only their own incumbent.
  final TransitionSession? localEvidence;
  late EditedSchedule _current;
  final _undo = <_Revision>[], _redo = <_Revision>[];

  /// Recheck mutable session authorization; undo must not resurrect expired evidence.
  /// Without session evidence the problem and evaluated revision are immutable.
  /// Every mutation/undo already evaluates the new revision before publishing it.
  EditedSchedule get current => localEvidence == null
      ? _current
      : _current = _evaluate(_current.assignments, _current.locks);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  EditResult assign(int slot, int doctor) => _change((a, locks) {
    _slot(slot);
    _doctor(doctor);
    _unlocked(slot, locks);
    a[slot] = doctor;
  });
  EditResult remove(int slot) => _change((a, locks) {
    _slot(slot);
    _unlocked(slot, locks);
    a[slot] = unfilledSlot;
  });
  EditResult move(int from, int to) => _change((a, locks) {
    _slot(from);
    _slot(to);
    _unlocked(from, locks);
    _unlocked(to, locks);
    if (a[from] == unfilledSlot) {
      throw const EditIssue(EditCode.emptySource, 'Taşınacak atama yok.');
    }
    if (a[to] != unfilledSlot) {
      throw const EditIssue(
        EditCode.occupiedTarget,
        'Hedef dolu; takas kullanın.',
      );
    }
    a[to] = a[from];
    a[from] = unfilledSlot;
  });
  EditResult swap(int first, int second) => _change((a, locks) {
    _slot(first);
    _slot(second);
    _unlocked(first, locks);
    _unlocked(second, locks);
    if (a[first] == unfilledSlot || a[second] == unfilledSlot) {
      throw const EditIssue(
        EditCode.emptySource,
        'Takas için iki dolu pozisyon gerekli.',
      );
    }
    final old = a[first];
    a[first] = a[second];
    a[second] = old;
  });
  EditResult lock(int slot) => _change((a, locks) {
    _slot(slot);
    if (a[slot] == unfilledSlot) {
      throw const EditIssue(EditCode.emptySource, 'Boş pozisyon kilitlenemez.');
    }
    locks[slot] = a[slot];
  });
  EditResult unlock(int slot) => _change((a, locks) {
    _slot(slot);
    if (problem.fixedAssignments.containsKey(slot)) {
      throw EditIssue(
        EditCode.locked,
        'Sabit snapshot değiştirilemez; kaynak taslakta kilidi kaldırıp yeni istek oluşturun.',
        slot: slot,
      );
    }
    locks.remove(slot);
  });

  void _slot(int slot) {
    if (slot < 0 || slot >= problem.slotDays.length) {
      throw const EditIssue(EditCode.slotIndex, 'Geçersiz pozisyon.');
    }
  }

  void _doctor(int doctor) {
    if (doctor < 0 || doctor >= problem.doctors.length) {
      throw const EditIssue(EditCode.doctorIndex, 'Geçersiz hekim.');
    }
  }

  void _unlocked(int slot, Map<int, int> locks) {
    if (locks.containsKey(slot) || problem.fixedAssignments.containsKey(slot)) {
      throw EditIssue(
        EditCode.locked,
        'Önce atamanın kilidini kaldırın.',
        slot: slot,
      );
    }
  }

  EditResult _change(void Function(List<int>, Map<int, int>) edit) {
    final before = current;
    final assignments = [...before.assignments], locks = {...before.locks};
    try {
      edit(assignments, locks);
    } on EditIssue catch (issue) {
      return EditResult(false, before, before, [issue]);
    }
    final candidate = _evaluate(assignments, locks);
    final errors = candidate.issues.where((e) => !e.isIncomplete).toList();
    if (errors.isNotEmpty) return EditResult(false, before, before, errors);
    _undo.add(_Revision(before));
    _redo.clear();
    _current = candidate;
    return EditResult(true, before, candidate, candidate.issues);
  }

  EditResult undo() => _restore(_undo, _redo);
  EditResult redo() => _restore(_redo, _undo);
  EditResult _restore(List<_Revision> source, List<_Revision> destination) {
    final before = current;
    if (source.isEmpty) {
      return EditResult(false, before, before, [
        const EditIssue(
          EditCode.noHistory,
          'Geri alınacak/yenilenecek işlem yok.',
        ),
      ]);
    }
    final revision = source.last;
    final restored = _evaluate(revision.assignments, revision.locks);
    // History may contain an imported invalid draft. Restore it honestly, never
    // restoring a stale proof or a stale quality vector.
    source.removeLast();
    destination.add(_Revision(before));
    _current = restored;
    return EditResult(true, before, restored, restored.issues);
  }

  EditedSchedule _evaluate(List<int> a, Map<int, int> locks) {
    final issues = <EditIssue>[];
    final days = problem.slotDays,
        counts = List.filled(problem.doctors.length, 0);
    final dates = <int, List<int>>{};
    var substitutions = 0;
    for (final fixed in problem.fixedAssignments.entries) {
      if (a[fixed.key] != fixed.value) {
        issues.add(
          EditIssue(
            EditCode.locked,
            'Snapshot içindeki sabit atama korunmalı.',
            slot: fixed.key,
          ),
        );
      }
    }
    void issue(EditCode code, String message, int slot, [int? doctor]) =>
        issues.add(
          EditIssue(
            code,
            message,
            slot: slot,
            date: problem.dateForDay(days[slot]),
            personId: doctor == null ? null : problem.doctors[doctor].id,
          ),
        );
    for (var slot = 0; slot < a.length; slot++) {
      final id = a[slot], day = days[slot];
      if (id == unfilledSlot) {
        if (problem.slotRequirements[slot] == SlotRequirement.required) {
          issue(EditCode.requiredMissing, 'Zorunlu nöbet pozisyonu boş.', slot);
        }
        continue;
      }
      if (id < 0 || id >= counts.length) {
        issue(EditCode.doctorIndex, 'Geçersiz hekim indeksi.', slot);
        continue;
      }
      final doctor = problem.doctors[id], role = problem.slotRoles![slot];
      counts[id]++;
      if (!doctor.eligibleRoles.contains(role) ||
          (role == DutyRole.junior && doctor.group != DutyGroup.junior)) {
        issue(
          EditCode.role,
          'Hekimin grubu/yetkinliği pozisyona uygun değil.',
          slot,
          id,
        );
      }
      if (role == DutyRole.senior && doctor.group == DutyGroup.junior) {
        substitutions++;
      }
      if (doctor.unavailable.contains(day)) {
        issue(EditCode.unavailable, 'Hekim bu gün nöbet tutamaz.', slot, id);
      }
      if (doctor.previousDuties.any(
        (d) => problem.dateForDay(day).difference(d).inDays < 3,
      )) {
        issue(
          EditCode.previousMonthRest,
          'Önceki ay nöbetinden sonra üç gün geçmeli.',
          slot,
          id,
        );
      }
      final prior = dates.putIfAbsent(id, () => []);
      if (prior.contains(day)) {
        issue(
          EditCode.duplicateDay,
          'Hekim aynı gün iki pozisyona atanamaz.',
          slot,
          id,
        );
      } else if (prior.any((d) => (day - d).abs() < 3)) {
        issue(
          EditCode.rest,
          'Nöbet başlangıçları arasında en az üç gün olmalı.',
          slot,
          id,
        );
      }
      prior.add(day);
      if (counts[id] > doctor.maxDuties ||
          counts[id] > problem.clinicMaxDuties) {
        issue(EditCode.capacity, 'Aylık nöbet üst sınırı aşıldı.', slot, id);
      }
    }
    for (var id = 0; id < counts.length; id++) {
      for (final day in problem.doctors[id].must) {
        if (!(dates[id] ?? []).contains(day)) {
          issues.add(
            EditIssue(
              EditCode.mustMissing,
              'Tutacak günü henüz karşılanmadı.',
              date: problem.dateForDay(day),
              personId: problem.doctors[id].id,
            ),
          );
        }
      }
    }
    final sorted = [...counts]..sort();
    final bare = Solution(a, [
      if (substitutions > 0) substitutions,
      sorted.isEmpty ? 0 : sorted.last - sorted.first,
      counts.fold<int>(0, (v, c) => v + c * c),
    ]);
    final activeB = localEvidence?.permitsPhaseBCandidate(problem) ?? false;
    if (substitutions > 0 &&
        !activeB &&
        !(localEvidence?.verifiesLocalTransition(problem, bare) ?? false)) {
      issues.add(
        const EditIssue(
          EditCode.transitionEvidence,
          'Kıdemsiz geçişi için bu snapshot ve adayı yetkilendiren süreç içi B kanıtı yok.',
        ),
      );
    }
    Solution? solution;
    if (issues.isEmpty) {
      const validator = SolutionValidator();
      final validation = activeB
          ? validator.validatePhaseBCandidate(
              problem,
              bare,
              session: localEvidence!,
            )
          : validator.validate(problem, bare, localEvidence: localEvidence);
      if (!validation.isValid) {
        issues.addAll(
          validation.errors.map(
            (e) => EditIssue(EditCode.independentValidation, e),
          ),
        );
      } else {
        const evaluator = ClinicalQualityEvaluator();
        final quality = activeB
            ? evaluator.evaluatePhaseBCandidate(
                problem,
                bare,
                session: localEvidence!,
              )
            : evaluator.evaluate(problem, bare, localEvidence: localEvidence);
        solution = Solution(a, bare.quality, clinicalQuality: quality);
      }
    }
    final validity = issues.any((e) => !e.isIncomplete)
        ? DraftValidity.invalid
        : issues.isNotEmpty
        ? DraftValidity.incomplete
        : substitutions > 0
        ? DraftValidity.provisionalTransition
        : DraftValidity.valid;
    return EditedSchedule._(a, locks, issues, solution, validity);
  }
}
