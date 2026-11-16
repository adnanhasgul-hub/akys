// Real browser acceptance harness. No test doubles for the normal worker path.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';
import 'package:akys/solver_v2/runtime/lifecycle.dart';
import 'package:akys/solver_v2/editing/reoptimization.dart';

import '../clinical_resilience.dart';

@JS('akysWorkerResult')
external set browserResult(JSString value);
void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Problem small({bool junior = false, bool blocked = false}) => Problem(
  startDate: DateTime.utc(2026, 11),
  doctors: [
    Doctor(
      id: 'd',
      group: junior ? DutyGroup.junior : DutyGroup.senior,
      seniorityLevel: junior ? null : SeniorityLevel.k1,
      unavailable: blocked ? {0} : {},
    ),
  ],
  slotsPerDay: [1],
  slotRoles: [DutyRole.senior],
  slotRequirements: [SlotRequirement.required],
  dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
);
const longRun = OptimizationOptions(
  budget: Duration(seconds: 3),
  candidateOrdering: true,
  earlyDeadEnds: true,
  experimentalTwoPhase: true,
  clinicalBounds: true,
);
OptimizationController controller([String path = 'akys_v2_worker.js']) =>
    OptimizationController.web(
      workerUri: Uri.parse(path),
      startupTimeout: const Duration(seconds: 2),
      heartbeatInterval: const Duration(milliseconds: 50),
      responseTimeout: const Duration(milliseconds: 600),
    );
Future<OptimizationSnapshot> until(
  OptimizationController c,
  bool Function(OptimizationSnapshot) f,
) async {
  if (f(c.value)) return c.value;
  return c.events.firstWhere(f).timeout(const Duration(seconds: 8));
}

Future<void> terminal(OptimizationController c) async {
  await until(
    c,
    (s) => [
      OptimizationState.optimal,
      OptimizationState.infeasible,
      OptimizationState.failed,
    ].contains(s.state),
  );
}

Future<void> main() async {
  final rows = <Map<String, Object?>>[];
  Future<void> test(String name, Future<void> Function() body) async {
    final watch = Stopwatch()..start();
    try {
      await body();
      rows.add({'test': name, 'pass': true, 'ms': watch.elapsedMilliseconds});
    } catch (e, st) {
      rows.add({'test': name, 'pass': false, 'error': '$e', 'stack': '$st'});
    }
  }

  await test('real worker starts and completes with main validator', () async {
    final c = controller();
    try {
      check(OptimizationController.webSupported, 'backend capability');
      final p = small();
      await c.start(p);
      await terminal(c);
      check(
        c.value.state == OptimizationState.optimal,
        'optimal: ${c.value.error}',
      );
      check(
        const SolutionValidator().validate(p, c.value.best!).isValid,
        'main independent validator',
      );
      check(
        c.value.best!.clinicalQuality!.components.length == 19,
        '19 components',
      );
      check(!c.value.permanentApprovalAllowed, 'no durable approval');
    } finally {
      await c.dispose();
    }
  });
  await test('main event loop responsive; extend during active search preserves frontier', () async {
    final c = controller();
    final watch = Stopwatch()..start();
    var ticks = 0, prior = 0, maxGap = 0;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final t = watch.elapsedMicroseconds;
      if (prior != 0 && t - prior > maxGap) maxGap = t - prior;
      prior = t;
      ticks++;
    });
    final events = <OptimizationSnapshot>[];
    final sub = c.events.listen(events.add);
    try {
      await c.start(
        resilienceProblem('6-open'),
        options: const OptimizationOptions(
          budget: Duration(milliseconds: 800),
          candidateOrdering: true,
          earlyDeadEnds: true,
          experimentalTwoPhase: true,
          clinicalBounds: true,
        ),
      );
      await until(
        c,
        (s) => s.best != null || s.state == OptimizationState.failed,
      );
      check(c.value.best != null, 'first incumbent: ${c.value.error}');
      final id = c.value.runId,
          nodes = c.value.nodes,
          first = c.value.firstFeasible;
      c.extend(const Duration(milliseconds: 300));
      await until(
        c,
        (s) =>
            s.state == OptimizationState.timedOut ||
            s.state == OptimizationState.failed,
      );
      check(c.value.state == OptimizationState.timedOut, 'timeout state');
      check(
        c.value.elapsed.inMilliseconds >= 1100,
        'deadline actually extended',
      );
      check(
        c.value.runId == id &&
            c.value.nodes > nodes &&
            c.value.firstFeasible == first,
        'same frontier',
      );
      check(ticks > 50 && maxGap < 250000, 'UI heartbeat $ticks / $maxGap');
      check(events.length < c.value.nodes, 'throttled progress');
      for (var i = 1; i < events.length; i++) {
        check(events[i].sequence > events[i - 1].sequence, 'sequence');
      }
      rows.add({
        'measurement': 'uiHeartbeat',
        'ticks': ticks,
        'maxGapUs': maxGap,
        'events': events.length,
        'nodes': c.value.nodes,
      });
    } finally {
      heartbeat.cancel();
      await sub.cancel();
      await c.dispose();
    }
  });
  await test('timeout without solution then true continuation', () async {
    final c = controller();
    try {
      await c.start(
        small(),
        options: const OptimizationOptions(budget: Duration.zero),
      );
      await until(c, (s) => s.state == OptimizationState.timedOut);
      check(
        c.value.best == null &&
            c.value.nodes == 0 &&
            c.value.proof == OptimizationProof.none,
        'no false proof',
      );
      final id = c.value.runId;
      c.extend(const Duration(seconds: 1));
      await terminal(c);
      check(
        c.value.runId == id && c.value.state == OptimizationState.optimal,
        'continued',
      );
    } finally {
      await c.dispose();
    }
  });
  await test(
    'cooperative cancel before first solution in a running worker',
    () async {
      final c = controller();
      try {
        await c.start(
          resilienceProblem('15-blocked'),
          options: const OptimizationOptions(budget: Duration(seconds: 3)),
        );
        await until(c, (s) => s.state == OptimizationState.running);
        await c.cancel();
        check(
          c.value.state == OptimizationState.cancelled &&
              !c.value.forcedTermination,
          'cooperative pre-solution cancel',
        );
        check(
          c.value.best == null && c.value.proof == OptimizationProof.none,
          'no fabricated solution or proof',
        );
      } finally {
        await c.dispose();
      }
    },
  );
  await test(
    'timeout with incumbent resumes nonempty frontier without restart',
    () async {
      final c = controller();
      try {
        await c.start(
          resilienceProblem('6-open'),
          options: const OptimizationOptions(
            budget: Duration(milliseconds: 400),
            candidateOrdering: true,
            earlyDeadEnds: true,
            experimentalTwoPhase: true,
            clinicalBounds: true,
          ),
        );
        await until(c, (s) => s.state == OptimizationState.timedOut);
        final old = c.value;
        check(old.best != null && old.nodes > 0, 'nonempty frontier');
        c.extend(const Duration(milliseconds: 300));
        await until(c, (s) => s.state != OptimizationState.timedOut);
        await until(c, (s) => s.state == OptimizationState.timedOut);
        check(
          c.value.nodes > old.nodes &&
              c.value.elapsed > old.elapsed &&
              c.value.runId == old.runId,
          'same frontier continuation',
        );
        check(
          c.value.firstFeasible == old.firstFeasible,
          'first incumbent timestamp retained',
        );
        check(
          c.value.best!.clinicalQuality!.compareTo(
                old.best!.clinicalQuality!,
              ) <=
              0,
          'incumbent never worsens',
        );
      } finally {
        await c.dispose();
      }
    },
  );
  await test('cancel before solution', () async {
    final c = controller();
    try {
      final start = c.start(resilienceProblem('6-open'), options: longRun);
      await c.cancel();
      await start;
      check(
        c.value.state == OptimizationState.cancelled && c.value.best == null,
        'cancel preparing',
      );
      check(
        !c.hasWorker && c.value.proof == OptimizationProof.none,
        'released',
      );
    } finally {
      await c.dispose();
    }
  });
  await test(
    'cooperative cancel after first solution retains validated incumbent',
    () async {
      final c = controller();
      try {
        await c.start(resilienceProblem('6-open'), options: longRun);
        await until(c, (s) => s.best != null);
        final before = c.value.best!;
        final watch = Stopwatch()..start();
        await c.cancel();
        check(
          c.value.state == OptimizationState.cancelled &&
              !c.value.forcedTermination,
          'cooperative',
        );
        check(
          c.value.best!.clinicalQuality!.compareTo(before.clinicalQuality!) <=
              0,
          'retained',
        );
        check(
          c.value.proof == OptimizationProof.feasibleUnproven && !c.hasWorker,
          'no false optimal',
        );
        rows.add({
          'measurement': 'cancelLatency',
          'us': watch.elapsedMicroseconds,
        });
      } finally {
        await c.dispose();
      }
    },
  );
  await test('forced cancel retains last delivered solution', () async {
    final c = controller();
    try {
      await c.start(resilienceProblem('6-open'), options: longRun);
      await until(c, (s) => s.best != null);
      final best = c.value.best;
      await c.cancel(grace: Duration.zero);
      check(
        c.value.forcedTermination && identical(c.value.best, best),
        'forced last delivered',
      );
    } finally {
      await c.dispose();
    }
  });
  await test(
    'blocked worker command queue triggers forced cancellation',
    () async {
      final c = controller('fixtures/blocked.js');
      try {
        await c.start(small());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await c.cancel(grace: const Duration(milliseconds: 50));
        check(
          c.value.forcedTermination &&
              c.value.state == OptimizationState.cancelled,
          'fallback',
        );
        check(c.value.best == null && !c.hasWorker, 'no fabricated incumbent');
      } finally {
        await c.dispose();
      }
    },
  );
  for (final fixture in ['crash', 'close']) {
    await test(
      'real worker $fixture after incumbent preserves preview',
      () async {
        final c = controller('fixtures/$fixture.js');
        try {
          await c.start(resilienceProblem('6-open'), options: longRun);
          await until(c, (s) => s.state == OptimizationState.failed);
          check(
            c.value.best != null,
            'last validated best retained ${c.value.error}',
          );
          check(
            c.value.proof == OptimizationProof.feasibleUnproven && !c.hasWorker,
            'no proof from failure',
          );
        } finally {
          await c.dispose();
        }
      },
    );
  }
  for (final fixture in ['invalid', 'quality']) {
    await test(
      'main independent validator rejects $fixture worker data',
      () async {
        final c = controller('fixtures/$fixture.js');
        try {
          await c.start(small());
          await terminal(c);
          check(
            c.value.state == OptimizationState.failed && c.value.best == null,
            'reject corrupt data: ${c.value.error}',
          );
        } finally {
          await c.dispose();
        }
      },
    );
  }
  await test(
    'late old-run and duplicate events cannot alter new run',
    () async {
      final c = controller('fixtures/stale.js');
      try {
        await c.start(resilienceProblem('6-open'), options: longRun);
        await until(c, (s) => s.best != null);
        final old = c.value.runId;
        await c.start(small());
        await terminal(c);
        final stable = c.value;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        check(
          identical(c.value, stable) &&
              stable.runId == old + 1 &&
              stable.state == OptimizationState.optimal,
          'stale rejection',
        );
        check(stable.nodes < 999999999, 'no forged nodes');
      } finally {
        await c.dispose();
      }
    },
  );
  await test('fresh A infeasibility precedes B; main inspection is not transferable proof', () async {
    final p = small(junior: true), c = controller();
    try {
      final seen = <OptimizationSnapshot>[];
      final sub = c.events.listen(seen.add);
      await c.start(p);
      await terminal(c);
      await sub.cancel();
      check(
        c.value.state == OptimizationState.optimal,
        'B solved ${c.value.error}',
      );
      check(
        c.value.restrictedVerdict == RestrictedVerdict.provenInfeasible,
        'A proof',
      );
      check(c.value.phase == TransitionPhase.substitution, 'B phase');
      final inspection = const SolutionValidator().inspectTransferredCandidate(
        p,
        c.value.best!,
      );
      check(
        inspection.structuralConstraintsSatisfied &&
            inspection.requiresTransitionProof,
        'main structural check',
      );
      check(
        !inspection.permanentApprovalAllowed &&
            !c.value.permanentApprovalAllowed,
        'preview only',
      );
      check(
        !const SolutionValidator().validate(p, c.value.best!).isValid,
        'serialized proof grants no local authority',
      );
      check(
        seen
            .where((s) => s.best != null)
            .every(
              (s) => s.restrictedVerdict == RestrictedVerdict.provenInfeasible,
            ),
        'no premature B',
      );
    } finally {
      await c.dispose();
    }
  });
  await test('both stages infeasible is distinct from timeout', () async {
    final c = controller();
    try {
      await c.start(small(junior: true, blocked: true));
      await terminal(c);
      check(
        c.value.state == OptimizationState.infeasible && c.value.best == null,
        'infeasible',
      );
    } finally {
      await c.dispose();
    }
  });
  await test(
    'exact fractional quality and reference tie survive JSON transport',
    () async {
      final p = Problem(
        startDate: DateTime.utc(2026, 11),
        doctors: [
          Doctor(id: 'a', maxDuties: 3, seniorityLevel: SeniorityLevel.k1),
          Doctor(id: 'b', maxDuties: 7, seniorityLevel: SeniorityLevel.k1),
        ],
        slotsPerDay: [1],
        slotRoles: [DutyRole.senior],
        slotRequirements: [SlotRequirement.required],
        dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
      );
      final c = controller();
      try {
        await c.start(
          ReoptimizationRequest(p, reference: [0], locks: {}).problem,
        );
        await terminal(c);
        check(
          c.value.best!.assignments.single == 1,
          'clinical precedes reference',
        );
        check(
          c.value.best!.clinicalQuality!.components[15].toString() == '1/7',
          'exact rational',
        );
      } finally {
        await c.dispose();
      }
    },
  );
  await test('missing worker asset fails explicitly', () async {
    final c = controller('missing.js');
    try {
      await c.start(small());
      check(
        c.value.state == OptimizationState.failed &&
            c.value.best == null &&
            !c.hasWorker,
        'startup failure',
      );
    } finally {
      await c.dispose();
    }
  });
  browserResult = jsonEncode({
    'tests': rows.where((r) => r.containsKey('test')).length,
    'passed': rows.where((r) => r['pass'] == true).length,
    'rows': rows,
  }).toJS;
}
