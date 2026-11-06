import '../../domain/models.dart';
import '../../domain/duty_positions.dart';
import 'constraint_validator.dart';
import 'fairness_optimizer.dart';
import 'solver_result.dart';

class DifficultyRepairResult {
  const DifficultyRepairResult(
    this.positions,
    this.candidates,
    this.elapsedMilliseconds,
    this.limitReached,
    this.timedOut,
  );
  final List<DutyPositions> positions;
  final int candidates, elapsedMilliseconds;
  final bool limitReached, timedOut;
}

/// Deterministic order: chronological (a,b) pairs, first improvement, restart.
/// At most candidateLimit valid pair attempts; optional timeout marks partial output.
/// A timeout can truncate the search;
/// no global optimality is inferred. Candidates preserve position metadata.
Future<DifficultyRepairResult> improveDifficultyLocally(
  ScheduleMonth month,
  List<DutyPositions> initial, {
  SolverCancellation? cancellation,
  int candidateLimit = 2000,
  Duration? timeLimit,
  int yieldEvery = 32,
  void Function(List<num> before, List<num> after)? onAccepted,
}) async {
  final watch = Stopwatch()..start();
  var best = initial;
  var bestObjective = FairnessReport(month, best).objective;
  var candidates = 0;
  var changed = true;
  bool timedOut() => timeLimit != null && watch.elapsed >= timeLimit;
  bool better(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return false;
  }

  DutyPositions junior(DutyPositions r, String id) => DutyPositions(
    date: r.date,
    seniorDutyPersonId: r.seniorDutyPersonId,
    juniorDutyPersonIds: [id],
    seniorRoleIsSubstitution: r.seniorRoleIsSubstitution,
    seniorRoleOriginalGroup: r.seniorRoleOriginalGroup,
    juniorVacancyReason: r.juniorVacancyReason,
  );
  while (changed &&
      candidates < candidateLimit &&
      !timedOut() &&
      !(cancellation?.cancelled ?? false)) {
    changed = false;
    outer:
    for (var a = 0; a < best.length; a++) {
      for (var b = a + 1; b < best.length; b++) {
        final x = best[a], y = best[b];
        if (x.juniorDutyPersonIds.length != 1 ||
            y.juniorDutyPersonIds.length != 1) {
          continue;
        }
        final first = x.juniorDutyPersonIds.single,
            second = y.juniorDutyPersonIds.single;
        if (first == second) continue;
        if (candidates >= candidateLimit ||
            timedOut() ||
            (cancellation?.cancelled ?? false)) {
          break outer;
        }
        candidates++;
        if (yieldEvery > 0 && candidates % yieldEvery == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        if ((cancellation?.cancelled ?? false) || timedOut()) {
          break outer;
        }
        final candidate = [...best];
        candidate[a] = junior(x, second);
        candidate[b] = junior(y, first);
        if (const ConstraintValidator().validate(month, candidate).isNotEmpty) {
          continue;
        }
        final value = FairnessReport(month, candidate).objective;
        if (better(value, bestObjective)) {
          onAccepted?.call(
            List.unmodifiable(bestObjective),
            List.unmodifiable(value),
          );
          best = candidate;
          bestObjective = value;
          changed = true;
          break outer;
        }
      }
    }
  }
  return DifficultyRepairResult(
    best,
    candidates,
    watch.elapsedMilliseconds,
    candidates >= candidateLimit ||
        timedOut() ||
        (cancellation?.cancelled ?? false),
    timedOut(),
  );
}
