import 'solver.dart';
import 'solution_validator.dart';

/// Normalized exact rational; no floating-point comparisons.
final class Exact implements Comparable<Exact> {
  Exact(BigInt n, BigInt d)
    : assert(d > BigInt.zero),
      numerator = n ~/ n.gcd(d),
      denominator = d ~/ n.gcd(d);
  factory Exact.integer(int n) => Exact(BigInt.from(n), BigInt.one);
  final BigInt numerator, denominator;
  Exact operator +(Exact o) => Exact(
    numerator * o.denominator + o.numerator * denominator,
    denominator * o.denominator,
  );
  Exact operator -(Exact o) => Exact(
    numerator * o.denominator - o.numerator * denominator,
    denominator * o.denominator,
  );
  @override
  int compareTo(Exact o) =>
      (numerator * o.denominator).compareTo(o.numerator * denominator);
  @override
  bool operator ==(Object other) =>
      other is Exact &&
      numerator == other.numerator &&
      denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  @override
  String toString() =>
      denominator == BigInt.one ? '$numerator' : '$numerator/$denominator';
}

final class ClinicalQuality implements Comparable<ClinicalQuality> {
  ClinicalQuality(List<Exact> components)
    : components = List.unmodifiable(components);

  /// Every component is minimized, including negated maximization objectives.
  final List<Exact> components;
  @override
  int compareTo(ClinicalQuality other) {
    if (components.length != other.components.length) {
      throw ArgumentError('Incompatible vectors');
    }
    for (var i = 0; i < components.length; i++) {
      final c = components[i].compareTo(other.components[i]);
      if (c != 0) return c;
    }
    return 0;
  }
}

/// Consumes validated assignments only; does not call solver's objective.
class ClinicalQualityEvaluator {
  const ClinicalQualityEvaluator();
  ClinicalQuality evaluate(
    Problem problem,
    Solution solution, {
    TransitionSession? localEvidence,
  }) {
    if (problem.startDate == null ||
        problem.slotRoles == null ||
        problem.dayDifficulties == null) {
      throw ArgumentError(
        'Clinical snapshot requires date, roles and daily scores',
      );
    }
    if (problem.doctors.any(
      (d) => d.group == DutyGroup.senior && d.seniorityLevel == null,
    )) {
      throw ArgumentError('Senior K1–K4 level required');
    }
    final validation = const SolutionValidator().validate(
      problem,
      solution,
      localEvidence: localEvidence,
    );
    if (!validation.isValid) {
      throw ArgumentError('Invalid solution: ${validation.errors.join('; ')}');
    }
    final n = problem.doctors.length, days = problem.slotDays;
    final counts = List<int>.filled(n, 0), points = List<int>.filled(n, 0);
    final weekday = List.generate(n, (_) => List<int>.filled(4, 0));
    final perDay = List.generate(problem.slotsPerDay.length, (_) => <int>[]);
    for (var i = 0; i < solution.assignments.length; i++) {
      final doctor = solution.assignments[i], day = days[i];
      if (doctor == unfilledSlot) continue;
      counts[doctor]++;
      perDay[day].add(doctor);
      points[doctor] += problem.dayDifficulties![day].effectiveScore;
      final dayOfWeek = problem.startDate!.add(Duration(days: day)).weekday;
      final category = const [6, 5, 7, 4].indexOf(dayOfWeek);
      if (category >= 0) weekday[doctor][category]++;
    }
    var coverage = 0, doubleJunior = 0;
    final solo = List<int>.filled(4, 0);
    for (final assigned in perDay) {
      final juniors = assigned
          .where((id) => problem.doctors[id].group == DutyGroup.junior)
          .length;
      if (juniors >= 1) coverage++;
      if (juniors >= 2) doubleJunior++;
      final seniors = assigned
          .where((id) => problem.doctors[id].group == DutyGroup.senior)
          .toList();
      if (seniors.length == 1) {
        solo[problem.doctors[seniors.single].seniorityLevel!.index]++;
      }
    }
    List<int> group(DutyGroup g) => [
      for (var i = 0; i < n; i++)
        if (problem.doctors[i].group == g) i,
    ];
    final senior = group(DutyGroup.senior), junior = group(DutyGroup.junior);
    int gap(List<int> ids, int Function(int) value) {
      if (ids.length < 2) return 0;
      final xs = ids.map(value).toList()..sort();
      return xs.last - xs.first;
    }

    final q = <Exact>[
      Exact.integer(validation.substitutionCount),
      Exact.integer(-coverage),
      Exact.integer(-doubleJunior),
      for (final index in [3, 2, 1, 0]) Exact.integer(-solo[index]),
    ];
    for (var category = 0; category < 4; category++) {
      final a = gap(senior, (i) => weekday[i][category]),
          b = gap(junior, (i) => weekday[i][category]);
      q.add(Exact.integer(a > b ? a : b));
      q.add(Exact.integer(a + b));
    }
    Exact loadGap(List<int> ids) {
      final ratios = [
        for (final i in ids)
          if (problem.doctors[i].maxDuties > 0)
            Exact(
              BigInt.from(counts[i]),
              BigInt.from(problem.doctors[i].maxDuties),
            ),
      ]..sort();
      return ratios.length < 2 ? Exact.integer(0) : ratios.last - ratios.first;
    }

    final a = loadGap(senior), b = loadGap(junior);
    q.add(a.compareTo(b) >= 0 ? a : b);
    q.add(a + b);
    final x = gap(senior, (i) => points[i]), y = gap(junior, (i) => points[i]);
    q.add(Exact.integer(x > y ? x : y));
    q.add(
      Exact.integer(
        points.isEmpty ? 0 : points.reduce((a, b) => a > b ? a : b),
      ),
    );
    return ClinicalQuality(q);
  }
}
