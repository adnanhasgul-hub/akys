import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';

SearchSession legacySearch(Problem p, {bool enablePruning = true}) =>
    SearchSession(
      p,
      enablePruning: enablePruning,
      mode: OptimizationMode.prototypeLegacy,
    );

/// Independent exhaustive oracle: Cartesian product then separate checks.
List<(List<int>, List<int>)> oracle(Problem p) {
  final days = p.slotDays, answers = <(List<int>, List<int>)>[];
  void enumerate(List<int> x) {
    if (x.length < days.length) {
      for (var i = 0; i < p.doctors.length; i++) {
        enumerate([...x, i]);
      }
      return;
    }
    final counts = List<int>.filled(p.doctors.length, 0);
    for (var i = 0; i < x.length; i++) {
      final d = p.doctors[x[i]];
      if (d.unavailable.contains(days[i])) return;
      counts[x[i]]++;
      if (counts[x[i]] > d.maxDuties) return;
      for (var j = 0; j < i; j++) {
        if (x[i] == x[j] && (days[i] - days[j]).abs() < 3) return;
      }
    }
    final sorted = [...counts]..sort();
    answers.add((
      x,
      [
        sorted.isEmpty ? 0 : sorted.last - sorted.first,
        counts.fold<int>(0, (a, b) => a + b * b),
      ],
    ));
  }

  enumerate([]);
  answers.sort((a, b) {
    for (var i = 0; i < a.$2.length; i++) {
      final c = a.$2[i].compareTo(b.$2[i]);
      if (c != 0) return c;
    }
    return 0;
  });
  return answers;
}

void main() {
  final people = [for (var i = 0; i < 3; i++) Doctor(id: 'p$i', maxDuties: 2)];
  test('complete search matches independent enumeration and stable ties', () {
    final p = Problem(
      doctors: [for (var i = 0; i < 3; i++) Doctor(id: 'p$i', maxDuties: 3)],
      slotsPerDay: [1, 0, 0, 1, 0, 0, 1],
    );
    final expected = oracle(p);
    expect(expected.length, greaterThan(1));
    expect(expected.map((e) => e.$2.join(',')).toSet().length, greaterThan(1));
    final a = legacySearch(p).run(maxNodes: 100000);
    final b = legacySearch(p).run(maxNodes: 100000);
    expect(a.status, SearchStatus.optimal);
    expect(a.best!.quality, expected.first.$2);
    expect(
      expected.any((e) => e.$1.join(',') == a.best!.assignments.join(',')),
      isTrue,
    );
    expect(a.best!.assignments, b.best!.assignments);
    expect(
      expected
          .where((e) => e.$2.join(',') == expected.first.$2.join(','))
          .length,
      greaterThan(1),
    );
  });
  test('infeasibility is proven only after enumeration', () {
    final p = Problem(
      doctors: [Doctor(id: 'a', maxDuties: 5)],
      slotsPerDay: [1, 1],
    );
    expect(oracle(p), isEmpty);
    expect(legacySearch(p).run(maxNodes: 100).status, SearchStatus.infeasible);
  });
  test('availability, capacity and three calendar days', () {
    final p = Problem(
      doctors: [
        Doctor(id: 'a', maxDuties: 2, unavailable: {1}),
        Doctor(id: 'b', maxDuties: 1),
      ],
      slotsPerDay: [1, 1, 0, 1],
    );
    final answer = legacySearch(p).run(maxNodes: 1000);
    expect(answer.status, SearchStatus.optimal);
    expect(answer.best!.quality, oracle(p).first.$2);
  });
  test('pause resumes frontier without redoing completed branches', () {
    final p = Problem(doctors: people, slotsPerDay: [1, 1, 1, 1]);
    final one = legacySearch(p).run(maxNodes: 10000);
    final session = legacySearch(p);
    var r = session.run(maxNodes: 1);
    expect(r.status, SearchStatus.paused);
    expect(r.canResume, isTrue);
    expect(r.pauseReason, PauseReason.nodeBudget);
    while (r.status == SearchStatus.paused ||
        r.status == SearchStatus.feasibleNotProven) {
      r = session.run(maxNodes: 2);
    }
    expect(r.status, SearchStatus.optimal);
    expect(r.visitedNodes, one.visitedNodes);
    expect(r.best!.assignments, one.best!.assignments);
  });
  test('timeout is not infeasible; cancellation preserves incumbent', () {
    final p = Problem(doctors: people, slotsPerDay: [1, 1, 1, 1]);
    final session = legacySearch(p);
    expect(
      session.run(maxNodes: 100, timeLimit: Duration.zero).status,
      SearchStatus.timeoutWithoutSolution,
    );
    var r = session.run(maxNodes: 1);
    while (r.best == null) {
      r = session.run(maxNodes: 1);
    }
    final saved = r.best;
    final timed = session.run(maxNodes: 100, timeLimit: Duration.zero);
    expect(timed.status, SearchStatus.feasibleNotProven);
    expect(timed.best, same(saved));
    expect(timed.pauseReason, PauseReason.deadline);
    expect(timed.canResume, isTrue);
    expect(timed.toMessage()['status'], 'feasibleNotProven');
    session.cancel();
    r = session.run(maxNodes: 100);
    expect(r.status, SearchStatus.cancelled);
    expect(r.best, same(saved));
  });
  test('problem message roundtrip and zero-slot case', () {
    final p = Problem(doctors: people, slotsPerDay: [0]);
    final clone = Problem.fromMessage(p.toMessage());
    final r = legacySearch(clone).run(maxNodes: 1);
    expect(r.status, SearchStatus.optimal);
    expect(r.best!.quality, [0, 0]);
  });
}
