import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

import '../../tool/solver_v2/clinical_benchmark.dart' as benchmark;

void main() {
  for (final (people, days) in [(6, 30), (10, 30), (15, 31), (20, 31)]) {
    for (final variant in ['standard', 'tight', 'hard']) {
      test('$variant $people/$days has an independently validated witness', () {
        final p = benchmark.snapshot(people, days, variant);
        final xs = <int>[], counts = List<int>.filled(people, 0);
        for (var d = 0; d < days; d++) {
          final doctor = [3, 1, 2, 0][d % 4];
          xs.addAll([doctor, unfilledSlot]);
          counts[doctor]++;
        }
        final sorted = [...counts]..sort();
        final s = Solution(xs, [
          sorted.last - sorted.first,
          counts.fold<int>(0, (a, b) => a + b * b),
        ]);
        expect(const SolutionValidator().validate(p, s).isValid, isTrue);
        expect(
          p.slotRequirements.where((x) => x == SlotRequirement.required).length,
          days,
        );
        expect(
          p.slotRequirements.where((x) => x == SlotRequirement.optional).length,
          days,
        );
      });
    }
    test('impossible $people/$days is proven by total capacity', () {
      final p = benchmark.snapshot(people, days, 'impossible');
      expect(p.doctors.fold<int>(0, (a, d) => a + d.maxDuties), lessThan(days));
      expect(
        SearchSession(p).run(maxNodes: 1000).status,
        SearchStatus.infeasible,
      );
    });
    test('deterministic node budget $people/$days preserves frontier', () {
      final p = benchmark.snapshot(people, days, 'standard');
      final first = SearchSession(p), resumed = SearchSession(p);
      final a = first.run(maxNodes: 10000);
      resumed.run(maxNodes: 4000);
      final b = resumed.run(maxNodes: 6000);
      expect(b.status, a.status);
      expect(b.visitedNodes, a.visitedNodes);
      expect(b.best?.assignments, a.best?.assignments);
      expect(
        b.best?.clinicalQuality?.toMessage(),
        a.best?.clinicalQuality?.toMessage(),
      );
    });
  }
}
