import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

void main() {
  const validator = SolutionValidator();
  final start = DateTime.utc(2026, 11, 1);
  test('clinical model message round-trip', () {
    final p = Problem(
      startDate: start,
      doctors: [
        Doctor(id: 's', seniorityLevel: SeniorityLevel.k3, must: {0}),
      ],
      slotsPerDay: [1],
      slotRoles: [DutyRole.senior],
    );
    final restored = Problem.fromMessage(p.toMessage());
    expect(restored.startDate, start);
    expect(restored.slotRoles, [DutyRole.senior]);
    expect(restored.doctors.single.seniorityLevel, SeniorityLevel.k3);
    expect(restored.doctors.single.must, {0});
    expect(restored.clinicMaxDuties, 8);
  });
  test(
    'senior only, forced junior substitution remains safely unavailable',
    () {
      final p = Problem(
        startDate: start,
        doctors: [
          Doctor(id: 's', group: DutyGroup.senior),
          Doctor(id: 'j', group: DutyGroup.junior),
        ],
        slotsPerDay: [1, 0, 0, 1],
        slotRoles: [DutyRole.senior, DutyRole.senior],
      );
      final r = SearchSession(p).run(maxNodes: 100);
      expect(r.status, SearchStatus.optimal);
      expect(r.best!.assignments, [0, 0]);
      expect(validator.validate(p, r.best!).isValid, isTrue);
      final forced = Problem(
        startDate: start,
        doctors: [Doctor(id: 'j', group: DutyGroup.junior)],
        slotsPerDay: [1],
        slotRoles: [DutyRole.senior],
      );
      expect(
        SearchSession(forced).run(maxNodes: 100).status,
        SearchStatus.infeasible,
      );
      expect(
        SearchSession(forced)
            .run(maxNodes: 100, timeLimit: Duration.zero)
            .status,
        SearchStatus.timeoutWithoutSolution,
      );
      expect(
        validator.validate(forced, Solution([0], [0, 1])).isValid,
        isFalse,
      );
    },
  );
  test('contradictions, bounds, previous month and duplicate day', () {
    expect(
      () => Doctor(id: 'a', must: {0}, unavailable: {0}),
      throwsArgumentError,
    );
    expect(
      () => Problem(
        doctors: [Doctor(id: 'a', maxDuties: 9)],
        slotsPerDay: [1],
      ),
      throwsArgumentError,
    );
    final p = Problem(
      startDate: start,
      doctors: [
        Doctor(
          id: 's',
          maxDuties: 1,
          must: {2},
          previousDuties: [DateTime.utc(2026, 10, 31)],
        ),
        Doctor(id: 'j', group: DutyGroup.junior),
      ],
      slotsPerDay: [1, 0, 1],
      slotRoles: [DutyRole.senior, DutyRole.senior],
    );
    expect(SearchSession(p).run(maxNodes: 100).status, SearchStatus.infeasible);
    expect(validator.validate(p, Solution([0, 0], [0, 4])).isValid, isFalse);
    final dup = Problem(
      startDate: start,
      doctors: [Doctor(id: 's')],
      slotsPerDay: [2],
      slotRoles: [DutyRole.senior, DutyRole.senior],
    );
    expect(validator.validate(dup, Solution([0, 0], [0, 4])).isValid, isFalse);
  });
  test(
    'small clinical problems match independent complete enumeration and resume',
    () {
      for (var mask = 0; mask < 32; mask++) {
        final p = Problem(
          startDate: start,
          doctors: [
            Doctor(
              id: 's1',
              maxDuties: 2,
              unavailable: {if (mask & 1 != 0) 0},
              must: {if (mask & 2 != 0) 3},
            ),
            Doctor(
              id: 's2',
              maxDuties: 2,
              unavailable: {if (mask & 4 != 0) 3},
              previousDuties: [if (mask & 8 != 0) DateTime.utc(2026, 10, 30)],
            ),
            Doctor(
              id: 'j',
              maxDuties: 2,
              group: DutyGroup.junior,
              unavailable: {if (mask & 16 != 0) 1},
            ),
          ],
          slotsPerDay: [1, 1, 0, 1],
          slotRoles: [DutyRole.senior, DutyRole.junior, DutyRole.senior],
        );
        final qualities = <List<int>>[];
        for (var a = 0; a < 3; a++) {
          for (var b = 0; b < 3; b++) {
            for (var c = 0; c < 3; c++) {
              final x = [a, b, c],
                  days = [0, 1, 3],
                  counts = List<int>.filled(3, 0);
              var valid = true;
              for (var i = 0; i < 3; i++) {
                final d = p.doctors[x[i]];
                counts[x[i]]++;
                if (d.unavailable.contains(days[i]) ||
                    counts[x[i]] > d.maxDuties ||
                    (i == 1
                        ? d.group != DutyGroup.junior
                        : d.group != DutyGroup.senior) ||
                    d.previousDuties.any(
                      (date) =>
                          start
                              .add(Duration(days: days[i]))
                              .difference(date)
                              .inDays <
                          3,
                    )) {
                  valid = false;
                }
                for (var j = 0; j < i; j++) {
                  if (x[i] == x[j] && (days[i] - days[j]).abs() < 3) {
                    valid = false;
                  }
                }
              }
              for (var i = 0; i < 3; i++) {
                for (final d in p.doctors[i].must) {
                  if (!List.generate(
                    3,
                    (j) => j,
                  ).any((j) => x[j] == i && days[j] == d)) {
                    valid = false;
                  }
                }
              }
              if (valid) {
                final sorted = [...counts]..sort();
                qualities.add([
                  sorted.last - sorted.first,
                  counts.fold<int>(0, (a, b) => a + b * b),
                ]);
              }
            }
          }
        }
        qualities.sort(
          (a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]),
        );
        final session = SearchSession(p);
        var r = session.run(maxNodes: 1);
        while (r.canResume) {
          r = session.run(maxNodes: 1);
        }
        final unpruned = SearchSession(
          p,
          enablePruning: false,
        ).run(maxNodes: 10000);
        expect(r.status, unpruned.status, reason: 'case $mask');
        if (qualities.isEmpty) {
          expect(r.status, SearchStatus.infeasible);
        } else {
          expect(r.status, SearchStatus.optimal);
          expect(r.best!.quality, qualities.first);
          expect(validator.validate(p, r.best!).isValid, isTrue);
        }
      }
    },
  );
}
