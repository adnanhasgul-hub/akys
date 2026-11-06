import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

SearchSession legacySearch(Problem p, {bool enablePruning = true}) =>
    SearchSession(
      p,
      enablePruning: enablePruning,
      mode: OptimizationMode.prototypeLegacy,
    );
TransitionSession legacyTransition(Problem p, {bool enablePruning = true}) =>
    TransitionSession(
      p,
      enablePruning: enablePruning,
      mode: OptimizationMode.prototypeLegacy,
    );

/// Independent complete enumeration and constraints, without solver or validator internals.
List<(List<int>, List<int>)> oracle(Problem p, {required bool substitutions}) {
  final days = p.slotDays, found = <(List<int>, List<int>)>[];
  void visit(List<int> ids) {
    if (ids.length < days.length) {
      final k = ids.length;
      for (var i = 0; i < p.doctors.length; i++) {
        visit([...ids, i]);
      }
      if (p.slotRequirements[k] == SlotRequirement.optional) {
        visit([...ids, -1]);
      }
      return;
    }
    final counts = List<int>.filled(p.doctors.length, 0);
    var transitions = 0;
    for (var k = 0; k < ids.length; k++) {
      final i = ids[k];
      if (i < 0) {
        if (p.slotRequirements[k] == SlotRequirement.required) return;
        continue;
      }
      final d = p.doctors[i], day = days[k], role = p.slotRoles![k];
      if (!d.eligibleRoles.contains(role) || d.unavailable.contains(day)) {
        return;
      }
      if (role == DutyRole.senior && d.group == DutyGroup.junior) {
        if (!substitutions) return;
        transitions++;
      }
      if (role == DutyRole.junior && d.group != DutyGroup.junior) return;
      if (d.previousDuties.any(
        (x) => p.startDate!.add(Duration(days: day)).difference(x).inDays < 3,
      )) {
        return;
      }
      if (++counts[i] > d.maxDuties) return;
      for (var j = 0; j < k; j++) {
        if (ids[j] == i && (days[j] - day).abs() < 3) return;
      }
    }
    for (var i = 0; i < p.doctors.length; i++) {
      for (final day in p.doctors[i].must) {
        var matched = false;
        for (var k = 0; k < ids.length; k++) {
          if (ids[k] == i && days[k] == day) matched = true;
        }
        if (!matched) return;
      }
    }
    final sorted = [...counts]..sort();
    found.add((
      ids,
      [
        if (substitutions) transitions,
        sorted.isEmpty ? 0 : sorted.last - sorted.first,
        counts.fold<int>(0, (a, b) => a + b * b),
      ],
    ));
  }

  visit([]);
  found.sort((a, b) {
    for (var i = 0; i < a.$2.length; i++) {
      final c = a.$2[i].compareTo(b.$2[i]);
      if (c != 0) return c;
    }
    return 0;
  });
  return found;
}

SearchResult finish(TransitionSession s) {
  var r = s.run(maxNodes: 2);
  while (r.canResume) {
    r = s.run(maxNodes: 2);
  }
  return r;
}

void main() {
  test('generated optional models match exhaustive oracle with and without pruning', () {
    for (var mask = 0; mask < 64; mask++) {
      final p = Problem(
        startDate: DateTime.utc(2026, 11, 1),
        doctors: [
          Doctor(id: 's', maxDuties: 2, unavailable: {if (mask & 1 != 0) 0}),
          Doctor(
            id: 'j',
            group: DutyGroup.junior,
            maxDuties: 2,
            must: {if (mask & 2 != 0) 3},
            previousDuties: [if (mask & 4 != 0) DateTime.utc(2026, 10, 31)],
          ),
        ],
        slotsPerDay: [2, 0, 0, 2],
        slotRoles: [
          DutyRole.senior,
          DutyRole.junior,
          DutyRole.senior,
          DutyRole.junior,
        ],
        slotRequirements: [
          for (var i = 0; i < 4; i++)
            (mask & (8 << (i % 3))) != 0
                ? SlotRequirement.optional
                : SlotRequirement.required,
        ],
      );
      final a = oracle(p, substitutions: false),
          b = oracle(p, substitutions: true);
      for (final prune in [false, true]) {
        final s = legacyTransition(p, enablePruning: prune), result = finish(s);
        if (a.isNotEmpty) {
          expect(s.restrictedVerdict, RestrictedVerdict.feasible);
          expect(result.status, SearchStatus.optimal);
          expect(result.best!.quality, a.first.$2, reason: 'A $mask');
          expect(
            const SolutionValidator().validate(s.problem, result.best!).isValid,
            isTrue,
          );
        } else if (b.isNotEmpty) {
          expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
          expect(result.status, SearchStatus.optimal);
          expect(result.best!.quality, b.first.$2, reason: 'B $mask');
          expect(
            const SolutionValidator()
                .validate(s.problem, result.best!, localEvidence: s)
                .isValid,
            isTrue,
          );
        } else {
          expect(result.status, SearchStatus.infeasible, reason: '$mask');
        }
      }
    }
  });
  test('all optional with zero doctors is feasible and must may force optional filling', () {
    final empty = Problem(
      doctors: [],
      slotsPerDay: [2],
      slotRequirements: [SlotRequirement.optional, SlotRequirement.optional],
    );
    final r = legacySearch(empty).run(maxNodes: 100);
    expect(r.status, SearchStatus.optimal);
    expect(r.best!.assignments, [-1, -1]);
    expect(const SolutionValidator().validate(empty, r.best!).isValid, isTrue);
    final must = Problem(
      startDate: DateTime.utc(2026, 11, 1),
      doctors: [
        Doctor(id: 's', must: {0}),
      ],
      slotsPerDay: [1],
      slotRoles: [DutyRole.senior],
      slotRequirements: [SlotRequirement.optional],
    );
    final solution = legacySearch(must).run(maxNodes: 100);
    expect(solution.best!.assignments, [0]);
    expect(
      const SolutionValidator().validate(must, solution.best!).isValid,
      isTrue,
    );
  });
  test(
    'B opens only after optional-aware A proof and proves minimum transition',
    () {
      final p = Problem(
        startDate: DateTime.utc(2026, 11, 1),
        doctors: [Doctor(id: 'j', group: DutyGroup.junior)],
        slotsPerDay: [2],
        slotRoles: [DutyRole.senior, DutyRole.junior],
        slotRequirements: [SlotRequirement.required, SlotRequirement.optional],
      );
      final s = legacyTransition(p);
      expect(
        s.run(maxNodes: 10, timeLimit: Duration.zero).status,
        SearchStatus.timeoutWithoutSolution,
      );
      expect(s.restrictedVerdict, RestrictedVerdict.pending);
      final r = finish(s);
      expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
      expect(r.status, SearchStatus.optimal);
      expect(r.best!.assignments, [0, -1]);
      expect(r.best!.quality.first, 1);
      expect(
        const SolutionValidator()
            .validate(s.problem, r.best!, localEvidence: s)
            .isValid,
        isTrue,
      );
    },
  );
  test('two optional juniors satisfy must without opening phase B', () {
    final p = Problem(
      startDate: DateTime.utc(2026, 11, 1),
      doctors: [
        Doctor(id: 's'),
        Doctor(id: 'j1', group: DutyGroup.junior, must: {0}),
        Doctor(id: 'j2', group: DutyGroup.junior, must: {0}),
      ],
      slotsPerDay: [3],
      slotRoles: [DutyRole.senior, DutyRole.junior, DutyRole.junior],
      slotRequirements: [
        SlotRequirement.required,
        SlotRequirement.optional,
        SlotRequirement.optional,
      ],
    );
    final s = legacyTransition(p);
    final paused = s.run(maxNodes: 0);
    expect(paused.status, SearchStatus.paused);
    expect(s.restrictedVerdict, RestrictedVerdict.pending);
    final result = finish(s);
    expect(result.status, SearchStatus.optimal);
    expect(result.best!.assignments, [0, 1, 2]);
    expect(s.restrictedVerdict, RestrictedVerdict.feasible);
    expect(
      const SolutionValidator().validate(s.problem, result.best!).isValid,
      isTrue,
    );
  });
  test('bounded optional benchmark proves same quality', () {
    final p = Problem(
      doctors: [for (var i = 0; i < 3; i++) Doctor(id: 'p$i', maxDuties: 2)],
      slotsPerDay: [1, 1, 0, 1],
      slotRequirements: [
        SlotRequirement.required,
        SlotRequirement.optional,
        SlotRequirement.optional,
      ],
    );
    for (final prune in [false, true]) {
      final w = Stopwatch()..start();
      final r = legacySearch(p, enablePruning: prune).run(maxNodes: 100000);
      w.stop();
      expect(r.status, SearchStatus.optimal);
      expect(const SolutionValidator().validate(p, r.best!).isValid, isTrue);
      // ignore: avoid_print
      print(
        'OPTIONAL_BENCH pruning=$prune nodes=${r.visitedNodes} us=${w.elapsedMicroseconds} quality=${r.best!.quality} status=${r.status.name}',
      );
    }
  });
}
