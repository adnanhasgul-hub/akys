import '../solver.dart';
import '../solution_validator.dart';
import 'schedule_editor.dart';

final class ReoptimizationInputException implements Exception {
  ReoptimizationInputException(List<EditIssue> issues)
    : issues = List.unmodifiable(issues);
  final List<EditIssue> issues;
  @override
  String toString() =>
      issues.map((e) => '${e.code.name}: ${e.message}').join('; ');
}

/// Immutable request: no reference solution or previous proof is seeded into DFS.
/// [problem] can also be submitted to OptimizationController for VM isolate work.
final class ReoptimizationRequest {
  ReoptimizationRequest._(this.problem);
  final Problem problem;
  List<int> get reference => problem.referenceAssignments!;
  Map<int, int> get locks => problem.fixedAssignments;

  factory ReoptimizationRequest.fromEditor(ScheduleEditor editor) {
    final state = editor.current;
    return ReoptimizationRequest(
      editor.problem,
      reference: state.assignments,
      locks: state.locks,
    );
  }

  factory ReoptimizationRequest(
    Problem source, {
    required List<int> reference,
    required Map<int, int> locks,
  }) {
    final issues = <EditIssue>[];
    final n = source.slotDays.length;
    if (reference.length != n ||
        reference.any((d) => d < unfilledSlot || d >= source.doctors.length)) {
      throw ReoptimizationInputException([
        const EditIssue(
          EditCode.doctorIndex,
          'Referans pozisyon/hekim indeksleri geçersiz.',
        ),
      ]);
    }
    final combined = {...source.fixedAssignments};
    for (final e in locks.entries) {
      if (e.key < 0 || e.key >= n) {
        issues.add(
          const EditIssue(EditCode.slotIndex, 'Kilit pozisyonu geçersiz.'),
        );
        continue;
      }
      if (e.value < 0 || e.value >= source.doctors.length) {
        issues.add(
          EditIssue(
            EditCode.doctorIndex,
            'Kilit hekimi geçersiz.',
            slot: e.key,
          ),
        );
        continue;
      }
      if (combined.containsKey(e.key) && combined[e.key] != e.value) {
        issues.add(
          EditIssue(
            EditCode.locked,
            'Aynı pozisyon için çelişen kilitler.',
            slot: e.key,
          ),
        );
      }
      combined[e.key] = e.value;
    }
    for (final e in combined.entries) {
      if (reference[e.key] != e.value) {
        issues.add(
          EditIssue(
            EditCode.locked,
            'Kilit referans atamayla eşleşmiyor.',
            slot: e.key,
          ),
        );
      }
    }
    if (issues.isNotEmpty) throw ReoptimizationInputException(issues);
    final data = source.toMessage();
    data['fixedAssignments'] = {
      for (final e in combined.entries) '${e.key}': e.value,
    };
    data['referenceAssignments'] = [...reference];
    final problem = Problem.fromMessage(data);
    final partial = List.filled(n, unfilledSlot);
    for (final e in combined.entries) {
      partial[e.key] = e.value;
    }
    // This is only lock-conflict preflight, NOT substitution authorization.
    // Fresh A/B search below is still mandatory even for a locked junior senior.
    final checked = ScheduleEditor(problem, assignments: partial).current;
    issues.addAll(
      checked.issues.where(
        (i) => !i.isIncomplete && i.code != EditCode.transitionEvidence,
      ),
    );
    for (var doctor = 0; doctor < problem.doctors.length; doctor++) {
      final d = problem.doctors[doctor];
      final obligations = {
        ...d.must,
        for (final e in combined.entries)
          if (e.value == doctor) problem.slotDays[e.key],
      }.toList()..sort();
      if (obligations.length > d.maxDuties) {
        issues.add(
          EditIssue(
            EditCode.capacity,
            'Kilitler ve Tutacak günleri kişisel kapasiteyi aşıyor.',
            personId: d.id,
          ),
        );
      }
      for (var i = 1; i < obligations.length; i++) {
        if (obligations[i] - obligations[i - 1] < 3) {
          issues.add(
            EditIssue(
              EditCode.rest,
              'Kilitler ve Tutacak günleri arasında üç gün yok.',
              personId: d.id,
              date: problem.dateForDay(obligations[i]),
            ),
          );
        }
      }
    }
    if (issues.isNotEmpty) throw ReoptimizationInputException(issues);
    return ReoptimizationRequest._(problem);
  }
}

final class AssignmentChange {
  AssignmentChange(
    this.slot,
    this.date,
    this.role,
    this.beforePersonId,
    this.afterPersonId,
  );
  final int slot;
  final DateTime date;
  final DutyRole role;
  final String? beforePersonId, afterPersonId;
}

final class ReoptimizationDiff {
  ReoptimizationDiff._(
    List<AssignmentChange> changes,
    Map<int, int> locks,
    List<int> empty,
  ) : changes = List.unmodifiable(changes),
      preservedLocks = Map.unmodifiable(locks),
      emptyOptionalSlots = List.unmodifiable(empty);
  factory ReoptimizationDiff(Problem problem, Solution solution) {
    final ref = problem.referenceAssignments!;
    final changes = <AssignmentChange>[];
    String? person(int id) =>
        id == unfilledSlot ? null : problem.doctors[id].id;
    for (var slot = 0; slot < ref.length; slot++) {
      if (ref[slot] != solution.assignments[slot]) {
        changes.add(
          AssignmentChange(
            slot,
            problem.dateForDay(problem.slotDays[slot]),
            problem.slotRoles![slot],
            person(ref[slot]),
            person(solution.assignments[slot]),
          ),
        );
      }
    }
    return ReoptimizationDiff._(
      changes,
      {
        for (final e in problem.fixedAssignments.entries)
          if (solution.assignments[e.key] == e.value) e.key: e.value,
      },
      [
        for (var i = 0; i < ref.length; i++)
          if (problem.slotRequirements[i] == SlotRequirement.optional &&
              solution.assignments[i] == unfilledSlot)
            i,
      ],
    );
  }
  final List<AssignmentChange> changes;
  final Map<int, int> preservedLocks;
  final List<int> emptyOptionalSlots;
  int get changedPositions => changes.length;
}

final class ReoptimizationResult {
  ReoptimizationResult._(
    this.status,
    this.pauseReason,
    this.best,
    this.diff,
    this.phase,
    this.restrictedVerdict,
    this.visitedNodes,
    this.error,
  );
  final SearchStatus? status; // null only for a technical failure
  final PauseReason? pauseReason;
  final Solution? best;
  final ReoptimizationDiff? diff;
  final TransitionPhase phase;
  final RestrictedVerdict restrictedVerdict;
  final int visitedNodes;
  final String? error;
  bool get optimalityProven => error == null && status == SearchStatus.optimal;

  /// Minimum changes among clinical optima of THIS lock-constrained snapshot.
  bool get minimumChangesProven => optimalityProven;
  bool get permanentApprovalAllowed => false;
}

/// Synchronous, resumable adapter. Use a background executor for lengthy work.
final class ReoptimizationSession {
  ReoptimizationSession(
    ReoptimizationRequest request, {
    bool enablePruning = true,
    bool candidateOrdering = false,
    bool earlyDeadEnds = false,
    bool experimentalTwoPhase = false,
    bool clinicalBounds = false,
    bool forwardChecking = false,
  }) : localEvidence = TransitionSession(
         request.problem,
         enablePruning: enablePruning,
         candidateOrdering: candidateOrdering,
         earlyDeadEnds: earlyDeadEnds,
         experimentalTwoPhase: experimentalTwoPhase,
         clinicalBounds: clinicalBounds,
         forwardChecking: forwardChecking,
       );
  final TransitionSession localEvidence;
  Problem get problem => localEvidence.problem;
  Solution? _best;
  String? _error;
  void cancel() => localEvidence.cancel();

  ReoptimizationResult run({required int maxNodes, Duration? timeLimit}) {
    SearchResult? result;
    if (_error == null) {
      try {
        result = localEvidence.run(maxNodes: maxNodes, timeLimit: timeLimit);
        final candidate = result.best;
        if (candidate != null) {
          final validation = const SolutionValidator().validate(
            problem,
            candidate,
            localEvidence: localEvidence,
          );
          if (!validation.isValid) {
            throw StateError(validation.errors.join('; '));
          }
          if (_best != null &&
              problem.compareClinicalCandidates(candidate, _best!) > 0) {
            throw StateError('Incumbent objective regressed');
          }
          _best = candidate;
        }
      } catch (e) {
        _error = e.toString();
        localEvidence.cancel();
      }
    }
    return ReoptimizationResult._(
      result?.status,
      result?.pauseReason,
      _best,
      _best == null ? null : ReoptimizationDiff(problem, _best!),
      localEvidence.phase,
      localEvidence.restrictedVerdict,
      localEvidence.totalVisitedNodes,
      _error,
    );
  }
}
