/// Standalone, exact enumerator for small synthetic schedules.
/// Day numbers are consecutive calendar-day indices starting at zero.
enum DutyGroup { senior, junior }

enum DutyRole { senior, junior }

enum SeniorityLevel { k1, k2, k3, k4 }

class Doctor {
  Doctor({
    required this.id,
    this.maxDuties = 8,
    Set<int> unavailable = const {},
    Set<int> must = const {},
    this.group = DutyGroup.senior,
    this.seniorityRank = 1,
    this.seniorityLevel,
    Set<DutyRole> eligibleRoles = const {DutyRole.senior, DutyRole.junior},
    List<DateTime> previousDuties = const [],
  }) : unavailable = Set.unmodifiable(unavailable),
       must = Set.unmodifiable(must),
       eligibleRoles = Set.unmodifiable(eligibleRoles),
       previousDuties = List.unmodifiable(previousDuties) {
    if (id.isEmpty ||
        maxDuties < 0 ||
        unavailable.any((d) => d < 0) ||
        must.any((d) => d < 0) ||
        seniorityRank < 1 ||
        (seniorityLevel != null && group != DutyGroup.senior) ||
        must.intersection(unavailable).isNotEmpty) {
      throw ArgumentError('Invalid doctor');
    }
  }
  final String id;
  final int maxDuties;
  final Set<int> unavailable, must;
  final DutyGroup group;
  final int seniorityRank;
  final SeniorityLevel? seniorityLevel;
  final Set<DutyRole> eligibleRoles;
  final List<DateTime> previousDuties;
}

/// Daily admin scores; a holiday never adds to the weekday score.
final class DayDifficulty {
  const DayDifficulty({
    required this.weekdayScore,
    this.holidayName,
    this.holidayScore,
  });
  final int weekdayScore;
  final String? holidayName;
  final int? holidayScore;
  int get effectiveScore => holidayScore != null && holidayScore! > weekdayScore
      ? holidayScore!
      : weekdayScore;
  Map<String, Object?> toMessage() => {
    'weekdayScore': weekdayScore,
    'holidayName': holidayName,
    'holidayScore': holidayScore,
  };
}

class Problem {
  Problem({
    required List<Doctor> doctors,
    required List<int> slotsPerDay,
    this.startDate,
    List<DutyRole>? slotRoles,
    List<DayDifficulty>? dayDifficulties,
    this.clinicMaxDuties = 8,
  }) : doctors = List.unmodifiable(doctors),
       slotsPerDay = List.unmodifiable(slotsPerDay),
       slotRoles = slotRoles == null ? null : List.unmodifiable(slotRoles),
       dayDifficulties = dayDifficulties == null
           ? null
           : List.unmodifiable(dayDifficulties) {
    if (doctors.map((d) => d.id).toSet().length != doctors.length ||
        slotsPerDay.any((s) => s < 0) ||
        slotsPerDay.isEmpty ||
        clinicMaxDuties < 0 ||
        (dayDifficulties != null &&
            (startDate == null ||
                dayDifficulties.length != slotsPerDay.length ||
                dayDifficulties.any(
                  (d) =>
                      d.weekdayScore < 1 ||
                      d.weekdayScore > 10 ||
                      ((d.holidayName == null) != (d.holidayScore == null)) ||
                      (d.holidayName != null &&
                          d.holidayName!.trim().isEmpty) ||
                      (d.holidayScore != null &&
                          (d.holidayScore! < 1 || d.holidayScore! > 10)),
                ))) ||
        doctors.any(
          (d) =>
              d.maxDuties > clinicMaxDuties ||
              d.must.any((day) => day >= slotsPerDay.length),
        ) ||
        (slotRoles != null &&
            slotRoles.length != slotsPerDay.fold<int>(0, (a, b) => a + b)) ||
        (startDate != null &&
            (!startDate!.isUtc ||
                startDate!.hour != 0 ||
                startDate!.minute != 0 ||
                startDate!.second != 0 ||
                startDate!.millisecond != 0 ||
                startDate!.microsecond != 0)) ||
        doctors.any((d) => d.previousDuties.isNotEmpty && startDate == null) ||
        doctors.any(
          (d) => d.previousDuties.any(
            (x) =>
                !x.isUtc ||
                x.hour != 0 ||
                x.minute != 0 ||
                x.second != 0 ||
                x.millisecond != 0 ||
                x.microsecond != 0 ||
                !x.isBefore(startDate!),
          ),
        )) {
      throw ArgumentError('Invalid problem');
    }
  }
  final List<Doctor> doctors;
  final List<int> slotsPerDay;
  final DateTime? startDate;
  final List<DutyRole>? slotRoles;
  final List<DayDifficulty>? dayDifficulties;
  final int clinicMaxDuties;
  DateTime dateForDay(int day) {
    if (startDate == null || day < 0 || day >= slotsPerDay.length) {
      throw RangeError('Clinical day/date unavailable');
    }
    return startDate!.add(Duration(days: day));
  }

  int weekdayForDay(int day) => dateForDay(day).weekday;
  int difficultyForDay(int day) {
    dateForDay(day);
    if (dayDifficulties == null) throw StateError('Daily scores unavailable');
    return dayDifficulties![day].effectiveScore;
  }

  List<int> get slotDays => [
    for (var day = 0; day < slotsPerDay.length; day++)
      for (var i = 0; i < slotsPerDay[day]; i++) day,
  ];
  Map<String, Object> toMessage() => {
    'doctors': [
      for (final d in doctors)
        {
          'id': d.id,
          'maxDuties': d.maxDuties,
          'group': d.group.name,
          'seniorityRank': d.seniorityRank,
          'seniorityLevel': d.seniorityLevel?.name ?? '',
          'must': d.must.toList()..sort(),
          'eligibleRoles': (d.eligibleRoles.map((r) => r.name).toList()
            ..sort()),
          'previousDuties': d.previousDuties
              .map((x) => x.toIso8601String())
              .toList(),
          'unavailable': d.unavailable.toList()..sort(),
        },
    ],
    'slotsPerDay': slotsPerDay,
    'startDate': startDate?.toIso8601String() ?? '',
    'slotRoles': slotRoles?.map((r) => r.name).toList() ?? <String>[],
    'hasSlotRoles': slotRoles != null,
    'clinicMaxDuties': clinicMaxDuties,
    'hasDayDifficulties': dayDifficulties != null,
    'dayDifficulties':
        dayDifficulties?.map((d) => d.toMessage()).toList() ?? [],
  };
  factory Problem.fromMessage(Map<String, dynamic> data) => Problem(
    doctors: [
      for (final raw in data['doctors'] as List)
        Doctor(
          id: raw['id'] as String,
          maxDuties: raw['maxDuties'] as int,
          unavailable: Set<int>.from(raw['unavailable'] as List),
          must: Set<int>.from(raw['must'] as List? ?? []),
          group: DutyGroup.values.byName(raw['group'] as String? ?? 'senior'),
          seniorityRank: raw['seniorityRank'] as int? ?? 1,
          seniorityLevel: (raw['seniorityLevel'] as String? ?? '').isEmpty
              ? null
              : SeniorityLevel.values.byName(raw['seniorityLevel'] as String),
          eligibleRoles: (raw['eligibleRoles'] as List? ?? ['senior', 'junior'])
              .map((x) => DutyRole.values.byName(x as String))
              .toSet(),
          previousDuties: (raw['previousDuties'] as List? ?? [])
              .map((x) => DateTime.parse(x as String))
              .toList(),
        ),
    ],
    slotsPerDay: List<int>.from(data['slotsPerDay'] as List),
    startDate: (data['startDate'] as String? ?? '').isEmpty
        ? null
        : DateTime.parse(data['startDate'] as String),
    slotRoles: data['hasSlotRoles'] == true
        ? (data['slotRoles'] as List)
              .map((x) => DutyRole.values.byName(x as String))
              .toList()
        : null,
    clinicMaxDuties: data['clinicMaxDuties'] as int? ?? 8,
    dayDifficulties: data['hasDayDifficulties'] == true
        ? [
            for (final raw in data['dayDifficulties'] as List)
              DayDifficulty(
                weekdayScore: raw['weekdayScore'] as int,
                holidayName: raw['holidayName'] as String?,
                holidayScore: raw['holidayScore'] as int?,
              ),
          ]
        : null,
  );
}

final class Solution {
  Solution(List<int> assignments, List<int> quality)
    : assignments = List.unmodifiable(assignments),
      quality = List.unmodifiable(quality);

  /// Doctor indices in slot order. Quality: load range, then sum of squared loads.
  final List<int> assignments, quality;
  Map<String, Object> toMessage() => {
    'assignments': assignments,
    'quality': quality,
  };
}

enum SearchStatus {
  paused,
  optimal,
  feasibleNotProven,
  infeasible,
  timeoutWithoutSolution,
  cancelled,
}

enum PauseReason { nodeBudget, deadline, stageTransition }

class SearchResult {
  const SearchResult(
    this.status,
    this.best,
    this.visitedNodes, {
    this.pauseReason,
  });
  final SearchStatus status;
  final Solution? best;
  final int visitedNodes;
  final PauseReason? pauseReason;
  bool get canResume => pauseReason != null;
  Map<String, Object?> toMessage() => {
    'status': status.name,
    'best': best?.toMessage(),
    'visitedNodes': visitedNodes,
    'pauseReason': pauseReason?.name,
  };
}

/// Complete DFS frontier: next candidate cursor per depth and current prefix.
/// Kept in memory; stepping is synchronous and must be run off the UI thread.
class SearchSession {
  SearchSession(this.problem, {this.enablePruning = true})
    : _allowSubstitution = false,
      _days = problem.slotDays,
      _next = List.filled(problem.slotDays.length + 1, 0);
  SearchSession._substitution(this.problem, {this.enablePruning = true})
    : _allowSubstitution = true,
      _days = problem.slotDays,
      _next = List.filled(problem.slotDays.length + 1, 0);
  final Problem problem;
  final bool enablePruning;
  final bool _allowSubstitution;
  final List<int> _days, _next;
  final List<int> _prefix = [];
  Solution? _best;
  int visitedNodes = 0;
  bool _complete = false;
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  Solution? get best => _best;

  bool _allowed(int doctor, int depth) {
    final d = problem.doctors[doctor], day = _days[depth];
    if (d.unavailable.contains(day)) return false;
    final role = problem.slotRoles?[depth];
    if (role != null &&
        (!d.eligibleRoles.contains(role) ||
            (role == DutyRole.senior &&
                d.group != DutyGroup.senior &&
                !_allowSubstitution) ||
            (role == DutyRole.junior && d.group != DutyGroup.junior))) {
      return false;
    }
    if (problem.startDate != null &&
        d.previousDuties.any(
          (x) =>
              problem.startDate!.add(Duration(days: day)).difference(x).inDays <
              3,
        )) {
      return false;
    }
    var count = 0;
    for (var i = 0; i < _prefix.length; i++) {
      if (_prefix[i] == doctor) {
        count++;
        if ((day - _days[i]).abs() < 3) return false;
      }
    }
    return count < d.maxDuties;
  }

  // Relax spacing and availability: this enlarges the feasible set, so the
  // resulting load bounds can never be greater than a real completion's score.
  bool _prune() {
    final counts = List<int>.filled(problem.doctors.length, 0);
    for (final p in _prefix) {
      counts[p]++;
    }
    final remaining = _days.length - _prefix.length;
    var capacity = 0;
    for (var i = 0; i < counts.length; i++) {
      capacity += problem.doctors[i].maxDuties - counts[i];
    }
    if (capacity < remaining) return true;
    if (_best == null || counts.isEmpty || _allowSubstitution) return false;
    final total = _days.length;
    final maxCurrent = counts.reduce((a, b) => a > b ? a : b);
    final lowerRange = (maxCurrent - total ~/ counts.length).clamp(0, total);
    // Water-filling without individual upper bounds gives minimum sum of squares.
    final relaxed = [...counts];
    for (var i = 0; i < remaining; i++) {
      var minIndex = 0;
      for (var j = 1; j < relaxed.length; j++) {
        if (relaxed[j] < relaxed[minIndex]) minIndex = j;
      }
      relaxed[minIndex]++;
    }
    final lowerSquares = relaxed.fold<int>(0, (a, b) => a + b * b);
    final incumbent = _best!.quality;
    return lowerRange > incumbent[0] ||
        (lowerRange == incumbent[0] && lowerSquares >= incumbent[1]);
  }

  bool _better(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return false;
  }

  void _evaluate() {
    final counts = List<int>.filled(problem.doctors.length, 0);
    for (final p in _prefix) {
      counts[p]++;
    }
    final sorted = [...counts]..sort();
    final q = [
      if (_allowSubstitution)
        for (final n in [
          List.generate(_prefix.length, (i) => i)
              .where(
                (i) =>
                    problem.slotRoles?[i] == DutyRole.senior &&
                    problem.doctors[_prefix[i]].group == DutyGroup.junior,
              )
              .length,
        ])
          n,
      if (sorted.isEmpty) 0 else sorted.last - sorted.first,
      counts.fold<int>(0, (sum, n) => sum + n * n),
    ];
    if (_best == null || _better(q, _best!.quality)) {
      _best = Solution(_prefix, q);
    }
  }

  /// [maxNodes] provides deterministic cooperative pauses. A deadline is a
  /// per-call safety limit, not a proof; it can yield different partial results.
  SearchResult run({required int maxNodes, Duration? timeLimit}) {
    if (maxNodes < 0 || (timeLimit != null && timeLimit.isNegative)) {
      throw ArgumentError('Invalid budget');
    }
    if (_cancelled) {
      return SearchResult(SearchStatus.cancelled, _best, visitedNodes);
    }
    if (_complete) {
      return SearchResult(
        _best == null ? SearchStatus.infeasible : SearchStatus.optimal,
        _best,
        visitedNodes,
      );
    }
    final watch = Stopwatch()..start();
    var stepNodes = 0;
    while (true) {
      if (_cancelled) {
        return SearchResult(SearchStatus.cancelled, _best, visitedNodes);
      }
      if (timeLimit != null && watch.elapsed >= timeLimit) {
        return SearchResult(
          _best == null
              ? SearchStatus.timeoutWithoutSolution
              : SearchStatus.feasibleNotProven,
          _best,
          visitedNodes,
          pauseReason: PauseReason.deadline,
        );
      }
      if (stepNodes >= maxNodes) {
        return SearchResult(
          _best == null ? SearchStatus.paused : SearchStatus.feasibleNotProven,
          _best,
          visitedNodes,
          pauseReason: PauseReason.nodeBudget,
        );
      }
      final depth = _prefix.length;
      if (depth == _days.length) {
        if (problem.doctors.asMap().entries.every(
          (entry) => entry.value.must.every(
            (day) => List.generate(
              _prefix.length,
              (i) => i,
            ).any((i) => _prefix[i] == entry.key && _days[i] == day),
          ),
        )) {
          _evaluate();
        }
        if (depth == 0) {
          _complete = true;
          return SearchResult(
            _best == null ? SearchStatus.infeasible : SearchStatus.optimal,
            _best,
            visitedNodes,
          );
        }
        _prefix.removeLast();
        continue;
      }
      if (_next[depth] >= problem.doctors.length) {
        _next[depth] = 0;
        if (depth == 0) {
          _complete = true;
        } else {
          _prefix.removeLast();
        }
        if (_complete) {
          return SearchResult(
            _best == null ? SearchStatus.infeasible : SearchStatus.optimal,
            _best,
            visitedNodes,
          );
        }
        continue;
      }
      final candidate = _next[depth]++;
      visitedNodes++;
      stepNodes++;
      if (_allowed(candidate, depth)) {
        _prefix.add(candidate);
        if (enablePruning && _prune()) {
          _prefix.removeLast();
        } else {
          _next[depth + 1] = 0;
        }
      }
    }
  }
}

/// Process-local two-phase capability. A client-provided serialized claim cannot
/// construct the private phase-B engine or change a completed phase-A verdict.
enum TransitionPhase { restricted, substitution, done }

enum RestrictedVerdict { pending, feasible, provenInfeasible, cancelled }

final class TransitionSession {
  TransitionSession(Problem input, {this.enablePruning = true})
    : problem = Problem.fromMessage(input.toMessage()) {
    if (problem.startDate == null || problem.slotRoles == null) {
      throw ArgumentError('Clinical date and roles required');
    }
    _restricted = SearchSession(problem, enablePruning: enablePruning);
  }
  final Problem problem;
  final bool enablePruning;
  late final SearchSession _restricted;
  SearchSession? _substitution;
  RestrictedVerdict _verdict = RestrictedVerdict.pending;
  RestrictedVerdict get restrictedVerdict => _verdict;
  TransitionPhase get phase => _substitution == null
      ? (_restrictedDone || _cancelled
            ? TransitionPhase.done
            : TransitionPhase.restricted)
      : (_phaseBDone || _cancelled
            ? TransitionPhase.done
            : TransitionPhase.substitution);
  bool _restrictedDone = false;
  bool _phaseBDone = false;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _restricted.cancel();
    _substitution?.cancel();
    if (_verdict == RestrictedVerdict.pending) {
      _verdict = RestrictedVerdict.cancelled;
    }
  }

  SearchResult run({required int maxNodes, Duration? timeLimit}) {
    if (_cancelled) {
      return SearchResult(
        SearchStatus.cancelled,
        _substitution?.best ?? _restricted.best,
        _substitution?.visitedNodes ?? _restricted.visitedNodes,
      );
    }
    if (_substitution != null) {
      final result = _substitution!.run(
        maxNodes: maxNodes,
        timeLimit: timeLimit,
      );
      if (result.status == SearchStatus.optimal ||
          result.status == SearchStatus.infeasible) {
        _phaseBDone = true;
      }
      return result;
    }
    final result = _restricted.run(maxNodes: maxNodes, timeLimit: timeLimit);
    if (result.best != null) {
      _verdict = RestrictedVerdict.feasible;
      if (result.status == SearchStatus.optimal) _restrictedDone = true;
      return result;
    }
    if (result.status == SearchStatus.infeasible) {
      _verdict = RestrictedVerdict.provenInfeasible;
      _substitution = SearchSession._substitution(
        problem,
        enablePruning: enablePruning,
      );
      return SearchResult(
        SearchStatus.paused,
        null,
        result.visitedNodes,
        pauseReason: PauseReason.stageTransition,
      );
    }
    return result;
  }

  /// Process-local check only: not a portable certificate, and never authorizes
  /// durable writes. Bind both the exact snapshot and phase-B assignment.
  bool verifiesLocalTransition(Problem snapshot, Solution solution) {
    if (!identical(snapshot, problem) ||
        _verdict != RestrictedVerdict.provenInfeasible ||
        _substitution?.best == null) {
      return false;
    }
    final b = _substitution!.best!;
    return b.assignments.length == solution.assignments.length &&
        b.quality.length == solution.quality.length &&
        List.generate(
          b.assignments.length,
          (i) => b.assignments[i] == solution.assignments[i],
        ).every((v) => v) &&
        List.generate(
          b.quality.length,
          (i) => b.quality[i] == solution.quality[i],
        ).every((v) => v);
  }
}
