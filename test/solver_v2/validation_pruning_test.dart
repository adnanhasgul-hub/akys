import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import 'solver_test.dart' show oracle;

void main() {
  const validator = SolutionValidator();
  test(
    'rejects malformed slots, indices, availability, maximum, rest and quality',
    () {
      final p = Problem(
        doctors: [
          Doctor(id: 'a', maxDuties: 1, unavailable: {1}),
          Doctor(id: 'b', maxDuties: 3),
        ],
        slotsPerDay: [1, 1, 1],
      );
      for (final solution in [
        Solution([0, 1], [0, 0]),
        Solution([0, -1, 1], [0, 0]),
        Solution([0, 4, 1], [0, 0]),
        Solution([1, 0, 1], [0, 0]),
        Solution([0, 0, 1], [0, 0]),
        Solution([1, 1, 0], [0, 0]),
        Solution([0, 1, 1], [99, 99]),
      ]) {
        final r = validator.validate(p, solution);
        expect(r.isValid, isFalse);
        expect(r.errors, isNotEmpty);
      }
      final good = Problem(
        doctors: [
          Doctor(id: 'a', maxDuties: 2),
          Doctor(id: 'b', maxDuties: 1),
        ],
        slotsPerDay: [1, 1, 0, 1],
      );
      expect(
        validator.validate(good, Solution([0, 1, 0], [1, 5])).isValid,
        isTrue,
      );
      final incorrect = validator.validate(good, Solution([0, 1, 0], [0, 0]));
      expect(incorrect.isValid, isFalse);
      expect(incorrect.quality, [1, 5]);
    },
  );
  test('generated finite problems match independent exhaustive oracle, including resumed search', () {
    var cases = 0;
    for (var n = 0; n <= 3; n++) {
      for (var slots = 0; slots < 32; slots++) {
        for (var pattern = 0; pattern < 4; pattern++) {
          final p = Problem(
            doctors: [
              for (var i = 0; i < n; i++)
                Doctor(
                  id: 'p$i',
                  maxDuties: (i + pattern) % 3,
                  unavailable: {
                    if ((pattern + i) % 2 == 0) 1,
                    if (pattern == 3) 3,
                  },
                ),
            ],
            slotsPerDay: [for (var d = 0; d < 5; d++) (slots >> d) & 1],
          );
          final expected = oracle(p);
          final s = SearchSession(p);
          var r = s.run(maxNodes: 3);
          while (r.status == SearchStatus.paused ||
              r.status == SearchStatus.feasibleNotProven) {
            r = s.run(maxNodes: 3);
          }
          if (expected.isEmpty) {
            expect(
              r.status,
              SearchStatus.infeasible,
              reason: 'case $n/$slots/$pattern',
            );
          } else {
            expect(r.status, SearchStatus.optimal);
            expect(
              r.best!.quality,
              expected.first.$2,
              reason: 'case $n/$slots/$pattern',
            );
            expect(validator.validate(p, r.best!).isValid, isTrue);
          }
          final raw = SearchSession(
            p,
            enablePruning: false,
          ).run(maxNodes: 100000);
          expect(r.status, raw.status);
          expect(r.best?.quality, raw.best?.quality);
          cases++;
        }
      }
    }
    expect(cases, 512);
  });
  test('zero slots and doctors, insufficient capacity', () {
    final empty = Problem(doctors: [], slotsPerDay: [0]);
    final r = SearchSession(empty).run(maxNodes: 5);
    expect(r.status, SearchStatus.optimal);
    expect(validator.validate(empty, r.best!).isValid, isTrue);
    final none = Problem(doctors: [], slotsPerDay: [1]);
    expect(
      SearchSession(none).run(maxNodes: 5).status,
      SearchStatus.infeasible,
    );
    final shortage = Problem(
      doctors: [Doctor(id: 'a', maxDuties: 0)],
      slotsPerDay: [1],
    );
    expect(
      SearchSession(shortage).run(maxNodes: 5).status,
      SearchStatus.infeasible,
    );
  });
  test('synthetic baseline versus branch and bound benchmark', () {
    final p = Problem(
      doctors: [for (var i = 0; i < 4; i++) Doctor(id: 'p$i', maxDuties: 3)],
      slotsPerDay: [1, 1, 1, 1, 1, 1, 1],
    );
    final times = <int>[], results = <SearchResult>[];
    for (final enabled in [false, true]) {
      final watch = Stopwatch()..start();
      final r = SearchSession(p, enablePruning: enabled).run(maxNodes: 1000000);
      watch.stop();
      times.add(watch.elapsedMicroseconds);
      results.add(r);
      expect(r.status, SearchStatus.optimal);
      expect(validator.validate(p, r.best!).isValid, isTrue);
    }
    expect(results[0].best!.quality, results[1].best!.quality);
    expect(results[1].visitedNodes, lessThan(results[0].visitedNodes));
    // ignore: avoid_print
    print(
      'BENCH baseline nodes=${results[0].visitedNodes} us=${times[0]} quality=${results[0].best!.quality}; bounded nodes=${results[1].visitedNodes} us=${times[1]} quality=${results[1].best!.quality}',
    );
  });
}
