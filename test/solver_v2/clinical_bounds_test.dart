import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/clinical_bounds.dart';

import 'clinical_reliability_test.dart' as fixture;
import 'optional_search_test.dart' as oracle;
import 'support/reference_clinical_quality.dart';

int cmp(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}

void main() {
  test('500 seeded problems: every prefix lower bound is no worse than independent exhaustive completion', () {
    final random = Random(150500);
    var checked = 0, dead = 0, solutions = 0;
    for (var i = 0; i < 500; i++) {
      final src = fixture.generated(random, i);
      final p = Problem(
        startDate: src.startDate,
        doctors: [
          for (var d = 0; d < src.doctors.length; d++)
            Doctor(
              id: src.doctors[d].id,
              group: src.doctors[d].group,
              seniorityLevel: src.doctors[d].seniorityLevel,
              maxDuties: src.doctors[d].maxDuties,
              previousDuties: src.doctors[d].previousDuties,
              unavailable: src.doctors[d].unavailable,
              must: {
                if ((i + d) % 5 == 0 && !src.doctors[d].unavailable.contains(0))
                  0,
              },
            ),
        ],
        slotsPerDay: src.slotsPerDay,
        slotRoles: src.slotRoles,
        slotRequirements: src.slotRequirements,
        dayDifficulties: src.dayDifficulties,
      );
      for (final allow in [false, true]) {
        final best = <String, List<int>>{};
        final componentMinima = <String, List<int>>{};
        for (final (ids, _) in oracle.oracle(p, substitutions: allow)) {
          solutions++;
          final q = const ReferenceClinicalQualityCalculator()
              .calculate(p, ids)
              .take(3)
              .map((x) => x.n.toInt())
              .toList();
          for (var n = 0; n <= ids.length; n++) {
            final key = ids.take(n).join(',');
            final old = best[key];
            if (old == null || cmp(q, old) < 0) best[key] = q;
            final minima = componentMinima.putIfAbsent(key, () => [...q]);
            for (var k = 0; k < 3; k++) {
              if (q[k] < minima[k]) minima[k] = q[k];
            }
          }
        }
        void enumerate(List<int> prefix) {
          final bound = optimisticClinicalPrefix(
                p,
                prefix,
                allowSubstitution: allow,
              ),
              actual = best[prefix.join(',')];
          if (actual == null) {
            dead++;
          } else {
            checked++;
            expect(
              cmp(bound, actual),
              lessThanOrEqualTo(0),
              reason:
                  'seed=150500 case=$i allow=$allow prefix=$prefix bound=$bound actual=$actual snapshot=${p.toMessage()}',
            );
            for (var k = 0; k < 3; k++) {
              expect(
                bound[k],
                lessThanOrEqualTo(componentMinima[prefix.join(',')]![k]),
                reason: 'component=$k case=$i allow=$allow prefix=$prefix',
              );
            }
          }
          if (prefix.length == p.slotDays.length) return;
          for (var d = 0; d < p.doctors.length; d++) {
            enumerate([...prefix, d]);
          }
          if (p.slotRequirements[prefix.length] == SlotRequirement.optional) {
            enumerate([...prefix, unfilledSlot]);
          }
        }

        enumerate([]);
      }
    }
    expect(checked, greaterThan(500));
    expect(dead, greaterThan(0));
    expect(solutions, greaterThan(0));
    // Printed counts allow exact reporting without deriving them from the solver.
    // ignore: avoid_print
    print(
      'BOUND_ORACLE seed=150500 problems=500 prefixes=$checked dead=$dead solutions=$solutions',
    );
  });
}
