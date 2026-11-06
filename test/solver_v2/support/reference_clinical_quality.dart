import 'package:akys/solver_v2/solver.dart';

/// Test-only rational implementation, deliberately independent of production Exact.
final class ReferenceFraction implements Comparable<ReferenceFraction> {
  ReferenceFraction(BigInt numerator, BigInt denominator)
    : n = numerator ~/ numerator.gcd(denominator),
      d = denominator ~/ numerator.gcd(denominator) {
    if (denominator <= BigInt.zero) {
      throw ArgumentError('positive denominator required');
    }
  }
  factory ReferenceFraction.integer(int value) =>
      ReferenceFraction(BigInt.from(value), BigInt.one);
  final BigInt n, d;
  ReferenceFraction operator +(ReferenceFraction other) =>
      ReferenceFraction(n * other.d + other.n * d, d * other.d);
  ReferenceFraction operator -(ReferenceFraction other) =>
      ReferenceFraction(n * other.d - other.n * d, d * other.d);
  @override
  int compareTo(ReferenceFraction other) =>
      (n * other.d).compareTo(other.n * d);
  @override
  String toString() => d == BigInt.one ? '$n' : '$n/$d';
}

/// Computes from snapshot and assignment directly. Inputs are independently
/// checked valid by the caller; no production validator or quality helper used.
final class ReferenceClinicalQualityCalculator {
  const ReferenceClinicalQualityCalculator();
  List<ReferenceFraction> calculate(Problem p, List<int> assignments) {
    final groups = <DutyGroup, List<int>>{
      for (final g in DutyGroup.values) g: [],
    };
    final duties = List.filled(p.doctors.length, 0),
        difficulty = List.filled(p.doctors.length, 0);
    final byWeekday = [for (var i = 0; i < p.doctors.length; i++) <int, int>{}];
    final seniorsByLevel = List.filled(4, 0);
    for (var i = 0; i < p.doctors.length; i++) {
      groups[p.doctors[i].group]!.add(i);
    }
    var slot = 0, substitutions = 0, coverage = 0, doubleJunior = 0;
    for (var day = 0; day < p.slotsPerDay.length; day++) {
      var juniorCount = 0;
      final daySenior = <int>[];
      final weekday = p.startDate!.add(Duration(days: day)).weekday;
      final score = p.dayDifficulties![day];
      final daily =
          score.holidayScore != null && score.holidayScore! > score.weekdayScore
          ? score.holidayScore!
          : score.weekdayScore;
      for (var k = 0; k < p.slotsPerDay[day]; k++, slot++) {
        final doctor = assignments[slot];
        if (doctor == -1) continue;
        duties[doctor]++;
        difficulty[doctor] += daily;
        byWeekday[doctor][weekday] = (byWeekday[doctor][weekday] ?? 0) + 1;
        if (p.doctors[doctor].group == DutyGroup.junior) {
          juniorCount++;
          if (p.slotRoles![slot] == DutyRole.senior) substitutions++;
        } else {
          daySenior.add(doctor);
        }
      }
      if (juniorCount > 0) coverage++;
      if (juniorCount > 1) doubleJunior++;
      if (daySenior.length == 1) {
        seniorsByLevel[p.doctors[daySenior.single].seniorityLevel!.index]++;
      }
    }
    final result = <ReferenceFraction>[];
    void addInt(int value) => result.add(ReferenceFraction.integer(value));
    addInt(substitutions);
    addInt(-coverage);
    addInt(-doubleJunior);
    for (var i = 3; i >= 0; i--) {
      addInt(-seniorsByLevel[i]);
    }
    int groupRange(List<int> group, int Function(int) value) {
      if (group.length < 2) return 0;
      var lo = value(group.first), hi = lo;
      for (final i in group.skip(1)) {
        final v = value(i);
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      return hi - lo;
    }

    for (final weekday in [6, 5, 7, 4]) {
      final a = groupRange(
        groups[DutyGroup.senior]!,
        (i) => byWeekday[i][weekday] ?? 0,
      );
      final b = groupRange(
        groups[DutyGroup.junior]!,
        (i) => byWeekday[i][weekday] ?? 0,
      );
      addInt(a > b ? a : b);
      addInt(a + b);
    }
    ReferenceFraction ratioRange(List<int> ids) {
      ReferenceFraction? low, high;
      for (final i in ids) {
        if (p.doctors[i].maxDuties == 0) continue;
        final ratio = ReferenceFraction(
          BigInt.from(duties[i]),
          BigInt.from(p.doctors[i].maxDuties),
        );
        if (low == null || ratio.compareTo(low) < 0) low = ratio;
        if (high == null || ratio.compareTo(high) > 0) high = ratio;
      }
      return low == null ? ReferenceFraction.integer(0) : high! - low;
    }

    final senior = ratioRange(groups[DutyGroup.senior]!),
        junior = ratioRange(groups[DutyGroup.junior]!);
    result.add(senior.compareTo(junior) >= 0 ? senior : junior);
    result.add(senior + junior);
    final a = groupRange(groups[DutyGroup.senior]!, (i) => difficulty[i]);
    final b = groupRange(groups[DutyGroup.junior]!, (i) => difficulty[i]);
    addInt(a > b ? a : b);
    var maxDifficulty = 0;
    for (final value in difficulty) {
      if (value > maxDifficulty) maxDifficulty = value;
    }
    addInt(maxDifficulty);
    return result;
  }
}
