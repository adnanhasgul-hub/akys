import '../../domain/models.dart';
import '../../domain/duty_positions.dart';
import 'feasibility_solver.dart';
import 'solver_result.dart';
import 'incumbent_repair.dart';

class PersonFairness {
  PersonFairness(this.person);
  final PersonSnapshot person;
  int total = 0,
      seniorRoles = 0,
      juniorRoles = 0,
      solo = 0,
      paired = 0,
      points = 0,
      holidays = 0,
      easyThursday = 0;
  final categories = List<int>.filled(5, 0);
  double get average => total == 0 ? 0 : points / total;
}

class FairnessReport {
  FairnessReport(ScheduleMonth month, List<DutyPositions> positions) {
    final ordered = month.people.where((p) => p.activeAtCreation).toList()
      ..sort((a, b) {
        final c = a.seniorityRank.compareTo(b.seniorityRank);
        return c != 0 ? c : a.personId.compareTo(b.personId);
      });
    people = {for (final p in ordered) p.personId: PersonFairness(p)};
    final roleOrder = [
      ...ordered.where(
        (p) => p.dutySeniorityGroup == DutySeniorityGroup.senior,
      ),
      ...ordered.where(
        (p) => p.dutySeniorityGroup == DutySeniorityGroup.junior,
      ),
    ];
    final rank = {
      for (var i = 0; i < roleOrder.length; i++) roleOrder[i].personId: i,
    };
    final difficulty = month.difficulty;
    for (final row in positions) {
      final day = int.parse(row.date.substring(8));
      final date = month.date(day);
      final score = difficulty.score(date);
      final holiday = difficulty.holiday(date) != null;
      final senior = people[row.seniorDutyPersonId]!;
      senior.seniorRoles++;
      if (row.seniorRoleIsSubstitution) {
        substitutions++;
      }
      if (row.juniorDutyPersonIds.isEmpty) {
        senior.solo++;
        vacancies++;
      } else {
        senior.paired++;
      }
      for (final id in row.juniorDutyPersonIds) {
        people[id]!.juniorRoles++;
      }
      for (final id in {row.seniorDutyPersonId!, ...row.juniorDutyPersonIds}) {
        final p = people[id]!;
        p.total++;
        p.points += score;
        p.categories[date.weekday <= 3 ? 0 : date.weekday - 3]++;
        if (holiday) {
          p.holidays++;
        }
        if (date.weekday == 4 && !holiday && !difficulty.isPreHoliday(date)) {
          p.easyThursday++;
        }
      }
    }
    hierarchyByRank = [
      for (final p in roleOrder)
        people[p.personId]!.solo *
            roleOrder
                .where((q) => rank[q.personId]! > rank[p.personId]!)
                .fold<int>(0, (n, q) => n + people[q.personId]!.paired),
    ];
    hierarchyViolations = hierarchyByRank.fold(0, (a, b) => a + b);
    List<num> groupValues(List<num> Function(List<PersonFairness>) f) => [
      for (final group in DutySeniorityGroup.values)
        ...f(
          people.values
              .where((p) => p.person.dutySeniorityGroup == group)
              .toList(),
        ),
    ];
    num spread(Iterable<num> values) {
      final v = values.toList()..sort();
      return v.isEmpty ? 0 : v.last - v.first;
    }

    // Squared prefix deviation from a uniform monthly vacancy distribution.
    // Integer arithmetic keeps the comparison deterministic; it is below all
    // capacity, hierarchy, senior solo and group duty-count objectives.
    var prefix = 0, temporalSpread = 0;
    final soloDates = positions
        .where((r) => r.juniorDutyPersonIds.isEmpty)
        .map((r) => r.date)
        .toSet();
    for (var day = 1; day <= month.days; day++) {
      if (soloDates.contains(dateKey(month.date(day)))) prefix++;
      final deviation = prefix * month.days - vacancies * day;
      temporalSpread += deviation * deviation;
    }
    stages = {
      'seniorSubstitutions': [substitutions],
      'juniorVacancies': [vacancies],
      'monthlyHierarchy': hierarchyByRank,
      'seniorSolo': [
        for (final p in people.values.where(
          (p) => p.person.dutySeniorityGroup == DutySeniorityGroup.senior,
        ))
          p.solo,
      ],
      'groupDutyCounts': groupValues(
        (g) => [spread(g.map((p) => p.total)), ...g.map((p) => p.total)],
      ),
      'soloCalendarSpread': [temporalSpread],
      'saturday': groupValues(
        (g) => [
          spread(g.map((p) => p.categories[3])),
          ...g.map((p) => p.categories[3]),
        ],
      ),
      'friday': groupValues(
        (g) => [
          spread(g.map((p) => p.categories[2])),
          ...g.map((p) => p.categories[2]),
        ],
      ),
      'sunday': groupValues(
        (g) => [
          spread(g.map((p) => p.categories[4])),
          ...g.map((p) => p.categories[4]),
        ],
      ),
      'thursday': groupValues(
        (g) => [
          spread(g.map((p) => p.easyThursday)),
          ...g.map((p) => -p.easyThursday),
        ],
      ),
      'averageDifficulty': groupValues(
        (g) => [spread(g.map((p) => p.average))],
      ),
      'totalDifficulty': groupValues((g) => [spread(g.map((p) => p.points))]),
      'monTueWed': groupValues((g) => [spread(g.map((p) => p.categories[0]))]),
      'holidayCounts': groupValues((g) => [spread(g.map((p) => p.holidays))]),
    };
  }
  late final Map<String, PersonFairness> people;
  late final List<int> hierarchyByRank;
  late final int hierarchyViolations;
  int substitutions = 0, vacancies = 0;
  late final Map<String, List<num>> stages;
  List<num> get objective => stages.values.expand((s) => s).toList();
}

class OptimizationStage {
  OptimizationStage(this.values, this.optimalityProven);
  final List<num> values;
  final bool optimalityProven;
}

class FairnessResult {
  FairnessResult(this.solver, this.report)
    : stages = {
        if (report != null)
          for (final entry in report.stages.entries)
            entry.key: OptimizationStage(
              List.unmodifiable(entry.value),
              solver.optimalityProven ||
                  (entry.key == 'seniorSubstitutions' &&
                      report.substitutions == 0),
            ),
      };
  final SolverResult solver;
  final FairnessReport? report;
  final Map<String, OptimizationStage> stages;
  bool get optimalityProven =>
      solver.hasValidIncumbent &&
      stages.values.every((s) => s.optimalityProven);
  bool get hierarchyExceptionAccepted =>
      report != null &&
      report!.hierarchyViolations > 0 &&
      (stages['monthlyHierarchy']?.optimalityProven ?? false);
}

class FairnessOptimizer {
  const FairnessOptimizer({this.nodeLimit = 100000, this.yieldEvery = 32});
  final int nodeLimit, yieldEvery;
  Future<FairnessResult> optimize(
    ScheduleMonth input, {
    SolverCancellation? cancellation,
    void Function(int, int, int?)? onProgress,
  }) async {
    final m = input.clone();
    final result =
        await FeasibilitySolver(
          nodeLimit: nodeLimit,
          yieldEvery: yieldEvery,
        ).solve(
          m,
          cancellation: cancellation,
          onProgress: onProgress,
          lexicographicObjective: (rows) => FairnessReport(m, rows).objective,
          improveIncumbent: (rows, checkpoint) => repairIncumbent(
            m,
            rows,
            (r) => FairnessReport(m, r).objective,
            checkpoint,
            nodeLimit ~/ 2,
          ),
        );
    return FairnessResult(
      result,
      result.hasValidIncumbent ? FairnessReport(m, result.positions) : null,
    );
  }
}
