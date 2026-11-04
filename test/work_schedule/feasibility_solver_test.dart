import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/engine/v13/feasibility_solver.dart';
import 'package:akys/modules/work_schedule/engine/v13/solver_result.dart';
import 'package:akys/modules/work_schedule/engine/v13/constraint_validator.dart';

import 'engine_test.dart' show sample;

void main() {
  for (final days in [11, 12]) {
    test('Seven doctors month $days valid deterministic incumbent', () async {
      final m = sample(2026, days);
      final solver = FeasibilitySolver(nodeLimit: 2000);
      final a = await solver.solve(m), b = await solver.solve(m);
      expect(a.hasValidIncumbent, true);
      expect(const ConstraintValidator().validate(m, a.positions), isEmpty);
      expect(a.seniorSubstitutionCount, 0);
      expect(
        jsonEncode(a.positions.map((r) => r.toJson()).toList()),
        jsonEncode(b.positions.map((r) => r.toJson()).toList()),
      );
      expect(a.juniorVacancyCount, greaterThanOrEqualTo(m.days - 24));
    });
  }
  test('Five cannot dates and event loop heartbeat', () async {
    final m = sample(2026, 11);
    m.constraints['p1']!.cannot.addAll([1, 5, 9, 13, 17]);
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    final r = await const FeasibilitySolver(
      nodeLimit: 2000,
      yieldEvery: 8,
    ).solve(m);
    timer.cancel();
    expect(ticks, greaterThan(0));
    expect(r.hasValidIncumbent, true);
    expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
  });
  test('Must cannot proves infeasible', () async {
    final m = sample(2026, 11);
    m.constraints['p1']!.must.add(1);
    m.constraints['p1']!.cannot.add(1);
    final r = await const FeasibilitySolver().solve(m);
    expect(r.status, SolverStatus.infeasible);
    expect(r.infeasibilityProven, true);
  });
  test('No available doctor proves infeasible', () async {
    final m = sample(2026, 11);
    for (final c in m.constraints.values) {
      c.cannot.add(1);
    }
    final r = await const FeasibilitySolver().solve(m);
    expect(r.infeasibilityProven, true);
    expect(r.hasValidIncumbent, false);
  });
  test('Zero budget is not an impossibility proof', () async {
    final r = await const FeasibilitySolver(nodeLimit: 0)
        .solve(sample(2026, 11));
    expect(r.status, SolverStatus.searchLimitReached);
    expect(r.infeasibilityProven, false);
  });
  test('Cancellation yields control and preserves proof distinction', () async {
    final cancel = SolverCancellation();
    Timer.run(cancel.cancel);
    final r = await const FeasibilitySolver().solve(
      sample(2026, 11),
      cancellation: cancel,
    );
    expect(r.cancelled, true);
    expect(r.status, SolverStatus.searchLimitReached);
    expect(r.infeasibilityProven, false);
  });
  test(
    'All seniors unavailable allows ranked substitution after proof',
    () async {
      final m = sample(2026, 11);
      for (var i = 1; i <= 6; i++) {
        m.constraints['p$i']!.cannot.add(1);
      }
      final r = await const FeasibilitySolver(nodeLimit: 3000).solve(m);
      expect(r.hasValidIncumbent, true);
      expect(r.realSeniorInfeasibilityProven, true);
      expect(r.positions.first.seniorDutyPersonId, 'p7');
      expect(r.positions.first.seniorRoleIsSubstitution, true);
      expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
    },
  );
  test('Boundary rest respected', () async {
    final m = sample(2026, 11);
    m.boundary['p1'] = ['2026-10-31'];
    final r = await const FeasibilitySolver(nodeLimit: 2000).solve(m);
    expect(r.hasValidIncumbent, true);
    expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
  });

  test('Saturated first junior permits next junior substitution', () async {
    final m = sample(2026, 11);
    for (var i = 1; i <= 4; i++) {
      m.constraints['p$i']!.cannot.add(2);
    }
    m.constraints['p5']!.must.addAll([1, 4, 7, 10, 13, 16, 19, 22]);
    final r = await const FeasibilitySolver(nodeLimit: 5000).solve(m);
    expect(r.hasValidIncumbent, true);
    expect(r.positions[1].seniorDutyPersonId, 'p6');
    expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
  });
  test('Unavailable juniors prove a date vacancy', () async {
    final m = sample(2026, 11);
    for (var i = 5; i <= 7; i++) {
      m.constraints['p$i']!.cannot.add(1);
    }
    final r = await const FeasibilitySolver(nodeLimit: 5000).solve(m);
    expect(r.hasValidIncumbent, true);
    expect(r.vacancies['2026-11-01'], VacancyProof.provenUnavoidable);
    expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
  });
  test('Incumbent retained when coverage proof budget expires', () async {
    final m = sample(2026, 11);
    final r = await const FeasibilitySolver(nodeLimit: 31).solve(m);
    expect(r.hasValidIncumbent, true);
    expect(r.status, SolverStatus.searchLimitReached);
    expect(r.infeasibilityProven, false);
    expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
  });

  test('Two junior must obligations allow required triple without false infeasibility', () async {
    final m = sample(2026, 11);
    m.constraints['p5']!.must.add(1);
    m.constraints['p6']!.must.add(1);
    final r = await const FeasibilitySolver(nodeLimit: 3000).solve(m);
    expect(r.hasValidIncumbent, true);
    expect(r.positions.first.juniorDutyPersonIds.length, 2);
    expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
  });
  test(
    'Multiple unavailable seniors still use remaining real senior',
    () async {
      final m = sample(2026, 11);
      for (var i = 1; i <= 3; i++) {
        m.constraints['p$i']!.cannot.add(1);
      }
      final r = await const FeasibilitySolver(nodeLimit: 3000).solve(m);
      expect(r.hasValidIncumbent, true);
      expect(r.positions.first.seniorDutyPersonId, 'p4');
      expect(r.seniorSubstitutionCount, 0);
      expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
    },
  );
  test(
    'Global shortage does not prove any particular vacancy unavoidable',
    () async {
      final m = sample(2026, 11);
      final r = await const FeasibilitySolver(nodeLimit: 5000).solve(m);
      expect(r.hasValidIncumbent, true);
      expect(r.juniorVacancyCount, greaterThanOrEqualTo(6));
      expect(
        r.vacancies.values.every((v) => v == VacancyProof.notProven),
        true,
      );
      expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
    },
  );
  test('Must rest contradiction is proven before search', () async {
    final m = sample(2026, 11);
    m.constraints['p1']!.must.addAll([1, 2]);
    final r = await const FeasibilitySolver().solve(m);
    expect(r.infeasibilityProven, true);
    expect(r.visitedStates, 0);
  });

  test(
    'Valid incumbent with unproven coverage is explicitly provisional',
    () async {
      final m = sample(2026, 11);
      for (var i = 5; i <= 7; i++) {
        m.constraints['p$i']!.cannot.addAll(List.generate(12, (i) => i + 1));
      }
      final r = await const FeasibilitySolver(nodeLimit: 31).solve(m);
      expect(r.hasValidIncumbent, true);
      expect(r.status, SolverStatus.searchLimitReached);
      expect(r.optimalityProven, false);
      expect(r.infeasibilityProven, false);
      expect(const ConstraintValidator().validate(m, r.positions), isEmpty);
    },
  );
}
