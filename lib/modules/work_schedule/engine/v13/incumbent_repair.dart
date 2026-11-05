import '../../domain/models.dart';
import '../../domain/duty_positions.dart';
import 'constraint_validator.dart';

/// Bounded deterministic neighborhood search, never an optimality proof.
/// Every candidate uses the CSP's shared budget/cancellation/yield checkpoint.
Future<List<DutyPositions>> repairIncumbent(
  ScheduleMonth m,
  List<DutyPositions> initial,
  List<num> Function(List<DutyPositions>) objective,
  Future<bool> Function() checkpoint,
  int limit,
) async {
  var best = List<DutyPositions>.from(initial);
  var score = objective(best);
  var attempts = 0;
  var stopped = false;
  bool better(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return false;
  }

  DutyPositions row(DutyPositions old, String senior, List<String> juniors) {
    final group = m.person(senior).dutySeniorityGroup;
    return DutyPositions(
      date: old.date,
      seniorDutyPersonId: senior,
      juniorDutyPersonIds: juniors,
      seniorRoleIsSubstitution: group == DutySeniorityGroup.junior,
      seniorRoleOriginalGroup: group.name,
      juniorVacancyReason: juniors.isEmpty
          ? 'NOT_PROVEN: Bu tarihte boşluk zorunluluğu kanıtlanmadı.'
          : null,
    );
  }

  Future<bool> consider(List<DutyPositions> candidate) async {
    attempts++;
    if (!await checkpoint()) {
      stopped = true;
      return false;
    }
    if (const ConstraintValidator().validate(m, candidate).isNotEmpty) {
      return false;
    }
    final value = objective(candidate);
    if (!better(value, score)) return false;
    best = candidate;
    score = value;
    return true;
  }

  // Rebuild the junior layer across the whole month before pairwise repair.
  // This is a candidate search, not a claim that this vacancy pattern is forced.
  // Preserve explicit senior roles; complex substitution/triple cases keep the
  // generic validated neighborhood below.
  final vacancyCount = best.where((r) => r.juniorDutyPersonIds.isEmpty).length;
  if (vacancyCount > 0 &&
      best.every(
        (r) => !r.seniorRoleIsSubstitution && r.juniorDutyPersonIds.length <= 1,
      )) {
    final eligible = <int>[
      for (var i = 0; i < best.length; i++)
        if (!m.people.any(
          (p) =>
              p.dutySeniorityGroup == DutySeniorityGroup.junior &&
              (m.constraints[p.personId]?.must.contains(i + 1) ?? false),
        ))
          i,
    ];
    final vacant = <int>{};
    for (var k = 0; k < vacancyCount && eligible.isNotEmpty; k++) {
      final target = (k + .5) * m.days / vacancyCount;
      eligible.sort((a, b) {
        final rank = m
            .person(best[b].seniorDutyPersonId!)
            .seniorityRank
            .compareTo(m.person(best[a].seniorDutyPersonId!).seniorityRank);
        if (rank != 0) return rank;
        final distance = (a + 1 - target).abs().compareTo(
          (b + 1 - target).abs(),
        );
        return distance != 0 ? distance : a.compareTo(b);
      });
      vacant.add(eligible.removeAt(0));
    }
    final juniors =
        m.people
            .where(
              (p) =>
                  p.activeAtCreation &&
                  p.dutySeniorityGroup == DutySeniorityGroup.junior,
            )
            .toList()
          ..sort(
            (a, b) => a.seniorityRank != b.seniorityRank
                ? a.seniorityRank.compareTo(b.seniorityRank)
                : a.personId.compareTo(b.personId),
          );
    final used = {for (final p in juniors) p.personId: <int>[]};
    final candidate = <DutyPositions>[];
    Future<bool> assign(int day) async {
      if (attempts >= limit || stopped) return false;
      attempts++;
      if (!await checkpoint()) {
        stopped = true;
        return false;
      }
      if (day > m.days) {
        if (const ConstraintValidator().validate(m, candidate).isNotEmpty) {
          return false;
        }
        final value = objective(candidate);
        if (better(value, score)) {
          best = [...candidate];
          score = value;
        }
        return true;
      }
      final old = initial[day - 1];
      if (vacant.contains(day - 1)) {
        candidate.add(row(old, old.seniorDutyPersonId!, []));
        final found = await assign(day + 1);
        candidate.removeLast();
        return found;
      }
      final required = juniors
          .where((p) => m.constraints[p.personId]?.must.contains(day) ?? false)
          .map((p) => p.personId)
          .toSet();
      final choices = [...juniors]
        ..sort((a, b) {
          final load = used[a.personId]!.length.compareTo(
            used[b.personId]!.length,
          );
          return load != 0
              ? load
              : a.seniorityRank != b.seniorityRank
              ? a.seniorityRank.compareTo(b.seniorityRank)
              : a.personId.compareTo(b.personId);
        });
      for (final p in choices) {
        final days = used[p.personId]!;
        final c = m.constraints[p.personId] ?? PersonalConstraints();
        if (required.any((id) => id != p.personId) ||
            c.cannot.contains(day) ||
            days.length >= 8 ||
            days.any((d) => (day - d).abs() < 3) ||
            c.must.any((d) => d != day && (day - d).abs() < 3) ||
            {...days, ...c.must, day}.length > 8 ||
            (m.boundary[p.personId] ?? []).any(
              (d) => m.date(day).difference(calendarDate(d)).inDays < 3,
            )) {
          continue;
        }
        days.add(day);
        candidate.add(row(old, old.seniorDutyPersonId!, [p.personId]));
        final found = await assign(day + 1);
        candidate.removeLast();
        days.removeLast();
        if (found) return true;
        if (stopped || attempts >= limit) return false;
      }
      return false;
    }

    if (vacant.length == vacancyCount) await assign(1);
  }
  var changed = true;
  while (changed && attempts < limit) {
    changed = false;
    final order = List<int>.generate(best.length, (i) => i)
      ..sort((a, b) {
        final rank = m
            .person(best[a].seniorDutyPersonId!)
            .seniorityRank
            .compareTo(m.person(best[b].seniorDutyPersonId!).seniorityRank);
        return rank != 0 ? rank : a.compareTo(b);
      });
    // First repair upper-rank solo duty using lower-rank paired dates.
    outer:
    for (final target in order) {
      for (final source in order.reversed) {
        if (source == target) continue;
        final a = best[source], b = best[target];
        if (b.juniorDutyPersonIds.length < 2) {
          for (final junior in a.juniorDutyPersonIds) {
            if (attempts >= limit || stopped) return best;
            final candidate = [...best];
            candidate[source] = row(
              a,
              a.seniorDutyPersonId!,
              a.juniorDutyPersonIds.where((id) => id != junior).toList(),
            );
            candidate[target] = row(b, b.seniorDutyPersonId!, [
              ...b.juniorDutyPersonIds,
              junior,
            ]);
            if (await consider(candidate)) {
              changed = true;
              break outer;
            }
          }
        }
        if (a.seniorDutyPersonId != b.seniorDutyPersonId) {
          if (attempts >= limit || stopped) return best;
          final candidate = [...best];
          candidate[source] = row(
            a,
            b.seniorDutyPersonId!,
            a.juniorDutyPersonIds,
          );
          candidate[target] = row(
            b,
            a.seniorDutyPersonId!,
            b.juniorDutyPersonIds,
          );
          if (await consider(candidate)) {
            changed = true;
            break outer;
          }
        }
      }
    }
  }
  return best;
}
