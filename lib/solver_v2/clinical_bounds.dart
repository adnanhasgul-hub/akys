import 'solver.dart';

/// An optimistic minimization prefix for Q1–Q3, not a feasibility proof.
/// Remaining availability, rest, musts and assignment collisions are relaxed.
List<int> optimisticClinicalPrefix(
  Problem problem,
  List<int> prefix, {
  required bool allowSubstitution,
}) {
  final days = problem.slotDays;
  if (problem.slotRoles == null || prefix.length > days.length) {
    throw ArgumentError('Clinical slots required');
  }
  final juniors = List<int>.filled(problem.slotsPerDay.length, 0);
  final used = List<int>.filled(problem.doctors.length, 0);
  var substitutions = 0;
  for (var i = 0; i < prefix.length; i++) {
    final id = prefix[i];
    if (id == unfilledSlot) continue;
    if (id < 0 || id >= problem.doctors.length) {
      throw ArgumentError('Invalid doctor index');
    }
    used[id]++;
    if (problem.doctors[id].group == DutyGroup.junior) {
      juniors[days[i]]++;
      if (problem.slotRoles![i] == DutyRole.senior) substitutions++;
    }
  }
  var capacity = 0;
  for (var i = 0; i < used.length; i++) {
    final d = problem.doctors[i];
    if (d.group == DutyGroup.junior && d.maxDuties > used[i]) {
      capacity += d.maxDuties - used[i];
    }
  }
  final remaining = List<int>.filled(problem.slotsPerDay.length, 0);
  for (var i = prefix.length; i < days.length; i++) {
    if (problem.slotRoles![i] == DutyRole.junior || allowSubstitution) {
      remaining[days[i]]++;
    }
  }
  var covered = 0, doubled = 0, coverageCandidates = 0, doubleCandidates = 0;
  for (var d = 0; d < juniors.length; d++) {
    if (juniors[d] >= 1) {
      covered++;
    } else if (remaining[d] >= 1) {
      coverageCandidates++;
    }
    if (juniors[d] >= 2) {
      doubled++;
    } else if (juniors[d] + remaining[d] >= 2) {
      doubleCandidates++;
    }
  }
  final maxCovered =
      covered + (coverageCandidates < capacity ? coverageCandidates : capacity);
  final maxDoubled =
      doubled + (doubleCandidates < capacity ? doubleCandidates : capacity);
  return [substitutions, -maxCovered, -maxDoubled];
}
