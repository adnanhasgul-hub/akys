/// Standalone, exact enumerator for small synthetic schedules.
/// Day numbers are consecutive calendar-day indices starting at zero.
class Doctor {
  Doctor({
    required this.id,
    required this.maxDuties,
    Set<int> unavailable = const {},
  }) : unavailable = Set.unmodifiable(unavailable) {
    if (id.isEmpty || maxDuties < 0 || unavailable.any((d) => d < 0)) {
      throw ArgumentError('Invalid doctor');
    }
  }
  final String id;
  final int maxDuties;
  final Set<int> unavailable;
}

class Problem {
  Problem({required List<Doctor> doctors, required List<int> slotsPerDay})
    : doctors = List.unmodifiable(doctors),
      slotsPerDay = List.unmodifiable(slotsPerDay) {
    if (doctors.map((d) => d.id).toSet().length != doctors.length ||
        slotsPerDay.any((s) => s < 0) ||
        slotsPerDay.isEmpty) {
      throw ArgumentError('Invalid problem');
    }
  }
  final List<Doctor> doctors;
  final List<int> slotsPerDay;
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
          'unavailable': d.unavailable.toList()..sort(),
        },
    ],
    'slotsPerDay': slotsPerDay,
  };
  factory Problem.fromMessage(Map<String, dynamic> data) => Problem(
    doctors: [
      for (final raw in data['doctors'] as List)
        Doctor(
          id: raw['id'] as String,
          maxDuties: raw['maxDuties'] as int,
          unavailable: Set<int>.from(raw['unavailable'] as List),
        ),
    ],
    slotsPerDay: List<int>.from(data['slotsPerDay'] as List),
  );
}

class Solution {
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

class SearchResult {
  const SearchResult(this.status, this.best, this.visitedNodes);
  final SearchStatus status;
  final Solution? best;
  final int visitedNodes;
  Map<String, Object?> toMessage() => {
    'status': status.name,
    'best': best?.toMessage(),
    'visitedNodes': visitedNodes,
  };
}

/// Complete DFS frontier: next candidate cursor per depth and current prefix.
/// Kept in memory; stepping is synchronous and must be run off the UI thread.
class SearchSession {
  SearchSession(this.problem)
    : _days = problem.slotDays,
      _next = List.filled(problem.slotDays.length + 1, 0);
  final Problem problem;
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
    var count = 0;
    for (var i = 0; i < _prefix.length; i++) {
      if (_prefix[i] == doctor) {
        count++;
        if ((day - _days[i]).abs() < 3) return false;
      }
    }
    return count < d.maxDuties;
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
        );
      }
      if (stepNodes >= maxNodes) {
        return SearchResult(
          _best == null ? SearchStatus.paused : SearchStatus.feasibleNotProven,
          _best,
          visitedNodes,
        );
      }
      final depth = _prefix.length;
      if (depth == _days.length) {
        _evaluate();
        if (depth == 0) {
          _complete = true;
          return SearchResult(SearchStatus.optimal, _best, visitedNodes);
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
        _next[depth + 1] = 0;
      }
    }
  }
}
