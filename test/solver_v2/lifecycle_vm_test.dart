@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/runtime/lifecycle.dart';

import '../../tool/solver_v2/clinical_resilience.dart';

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
const longOptions = OptimizationOptions(
  budget: Duration(seconds: 1),
  candidateOrdering: true,
  earlyDeadEnds: true,
  experimentalTwoPhase: true,
  clinicalBounds: true,
);
Future<OptimizationSnapshot> until(
  OptimizationController c,
  bool Function(OptimizationSnapshot) predicate,
) async {
  if (predicate(c.value)) return c.value;
  return c.events.firstWhere(predicate).timeout(const Duration(seconds: 10));
}

void main() {
  test('idle -> preparing -> running -> feasible -> optimal; ordered validated incumbent', () async {
    final c = OptimizationController();
    addTearDown(c.dispose);
    final seen = <OptimizationSnapshot>[];
    final sub = c.events.listen(seen.add);
    addTearDown(sub.cancel);
    expect(c.value.state, OptimizationState.idle);
    await c.start(small());
    await until(c, (s) => s.state == OptimizationState.optimal);
    await Future<void>.delayed(Duration.zero);
    expect(
      seen.map((s) => s.state),
      containsAllInOrder([
        OptimizationState.preparing,
        OptimizationState.running,
        OptimizationState.feasible,
        OptimizationState.optimal,
      ]),
    );
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i].sequence, greaterThan(seen[i - 1].sequence));
      expect(seen[i].nodes, greaterThanOrEqualTo(seen[i - 1].nodes));
      expect(
        OptimizationController.canTransition(seen[i - 1].state, seen[i].state),
        true,
      );
    }
    expect(c.value.proof, OptimizationProof.optimalProven);
    expect(c.value.best!.clinicalQuality!.components.length, 19);
    expect(c.hasWorker, false);
  });
  test('A root proof opens B, substitution remains preview-only', () async {
    final c = OptimizationController();
    addTearDown(c.dispose);
    final seen = <OptimizationSnapshot>[];
    final sub = c.events.listen(seen.add);
    addTearDown(sub.cancel);
    await c.start(
      small(junior: true),
      options: const OptimizationOptions(forwardChecking: true),
    );
    await until(c, (s) => s.state == OptimizationState.optimal);
    expect(
      seen.any(
        (s) =>
            s.phase == TransitionPhase.substitution &&
            s.restrictedVerdict == RestrictedVerdict.provenInfeasible,
      ),
      true,
    );
    expect(c.value.best!.clinicalQuality!.components.first.toString(), '1');
    expect(c.value.permanentApprovalAllowed, false);
  });
  test('proven infeasible differs from timeout, both A/B evaluated', () async {
    final c = OptimizationController();
    addTearDown(c.dispose);
    await c.start(
      small(blocked: true),
      options: const OptimizationOptions(forwardChecking: true),
    );
    await until(c, (s) => s.state == OptimizationState.infeasible);
    expect(c.value.proof, OptimizationProof.infeasibleProven);
    expect(c.value.best, isNull);
    expect(c.hasWorker, false);
  });
  test(
    'zero budget times out without proof; extend resumes same run',
    () async {
      final c = OptimizationController();
      addTearDown(c.dispose);
      await c.start(
        small(),
        options: const OptimizationOptions(budget: Duration.zero),
      );
      await until(c, (s) => s.state == OptimizationState.timedOut);
      expect(c.value.proof, OptimizationProof.none);
      expect(c.value.nodes, 0);
      expect(c.hasWorker, true);
      final id = c.value.runId;
      c.extend(const Duration(seconds: 1));
      await until(c, (s) => s.state == OptimizationState.optimal);
      expect(c.value.runId, id);
      expect(c.value.nodes, greaterThan(0));
    },
  );
  test('cancel during preparing never launches a search', () async {
    final c = OptimizationController();
    addTearDown(c.dispose);
    final start = c.start(resilienceProblem('6-open'), options: longOptions);
    await c.cancel();
    await start;
    expect(c.value.state, OptimizationState.cancelled);
    expect(c.value.best, isNull);
    expect(c.hasWorker, false);
    expect(c.value.proof, OptimizationProof.none);
  });
  test(
    'cancel after first solution preserves incumbent and clears worker',
    () async {
      final c = OptimizationController();
      addTearDown(c.dispose);
      await c.start(resilienceProblem('6-open'), options: longOptions);
      await until(c, (s) => s.best != null);
      final best = c.value.best!;
      await c.cancel();
      expect(c.value.state, OptimizationState.cancelled);
      expect(
        c.value.best!.clinicalQuality!.compareTo(best.clinicalQuality!),
        lessThanOrEqualTo(0),
      );
      expect(c.value.proof, OptimizationProof.feasibleUnproven);
      expect(c.hasWorker, false);
    },
  );
  test('forced cancellation preserves last delivered solution', () async {
    final c = OptimizationController();
    addTearDown(c.dispose);
    await c.start(resilienceProblem('6-open'), options: longOptions);
    await until(c, (s) => s.best != null);
    final best = c.value.best!;
    await c.cancel(grace: Duration.zero);
    expect(c.value.forcedTermination, true);
    expect(c.value.state, OptimizationState.cancelled);
    expect(c.hasWorker, false);
    expect(
      c.value.best!.clinicalQuality!.compareTo(best.clinicalQuality!),
      lessThanOrEqualTo(0),
    );
  });
  test(
    'timeout retains solution; extension preserves nodes and quality',
    () async {
      final c = OptimizationController();
      addTearDown(c.dispose);
      await c.start(resilienceProblem('6-open'), options: longOptions);
      await until(c, (s) => s.state == OptimizationState.timedOut);
      final old = c.value;
      expect(old.best, isNotNull);
      expect(old.proof, OptimizationProof.feasibleUnproven);
      c.extend(const Duration(milliseconds: 100));
      await until(c, (s) => s.state != OptimizationState.timedOut);
      await until(c, (s) => s.state == OptimizationState.timedOut);
      expect(c.value.runId, old.runId);
      expect(c.value.nodes, greaterThan(old.nodes));
      expect(c.value.elapsed, greaterThan(old.elapsed));
      expect(
        c.value.best!.clinicalQuality!.compareTo(old.best!.clinicalQuality!),
        lessThanOrEqualTo(0),
      );
    },
  );
  test(
    'extension while running increases original budget without reset',
    () async {
      final c = OptimizationController();
      addTearDown(c.dispose);
      await c.start(
        resilienceProblem('6-open'),
        options: const OptimizationOptions(
          budget: Duration(milliseconds: 200),
          candidateOrdering: true,
          earlyDeadEnds: true,
        ),
      );
      await until(c, (s) => s.state == OptimizationState.running);
      final id = c.value.runId;
      c.extend(const Duration(milliseconds: 200));
      await until(c, (s) => s.state == OptimizationState.timedOut);
      expect(c.value.runId, id);
      expect(c.value.elapsed.inMilliseconds, greaterThanOrEqualTo(400));
    },
  );
  test(
    'restart isolates late events and pending starts by generation',
    () async {
      final c = OptimizationController();
      addTearDown(c.dispose);
      final first = c.start(resilienceProblem('6-open'), options: longOptions);
      final second = c.start(small());
      await Future.wait([first, second]);
      await until(
        c,
        (s) => s.runId == 2 && s.state == OptimizationState.optimal,
      );
      final stable = c.value;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.value, same(stable));
      expect(c.value.best!.assignments, [0]);
      expect(c.hasWorker, false);
    },
  );
  test(
    'restarting a live worker discards its queued progress and best',
    () async {
      final c = OptimizationController();
      addTearDown(c.dispose);
      await c.start(resilienceProblem('6-open'), options: longOptions);
      await until(c, (s) => s.best != null);
      final oldId = c.value.runId;
      await c.start(small());
      await until(c, (s) => s.state == OptimizationState.optimal);
      final stable = c.value;
      expect(stable.runId, oldId + 1);
      expect(stable.best!.assignments, [0]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.value, same(stable));
    },
  );
  test(
    'dispose waits for overlapping pending startups to be cleaned',
    () async {
      final c = OptimizationController();
      final a = c.start(resilienceProblem('6-open'), options: longOptions);
      await Future<void>.delayed(Duration.zero);
      final b = c.start(small());
      await c.dispose();
      await Future.wait([a, b]);
      expect(c.hasWorker, false);
    },
  );
  test(
    'invalid clinical snapshot fails cleanly and controller recovers',
    () async {
      final c = OptimizationController();
      addTearDown(c.dispose);
      await c.start(
        Problem(
          doctors: [Doctor(id: 'legacy')],
          slotsPerDay: [1],
        ),
      );
      await until(c, (s) => s.state == OptimizationState.failed);
      expect(c.value.error, isNotEmpty);
      expect(c.hasWorker, false);
      await c.start(small());
      await until(c, (s) => s.state == OptimizationState.optimal);
    },
  );
  test('VM main event loop stays responsive during optimization', () async {
    final c = OptimizationController();
    addTearDown(c.dispose);
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    addTearDown(timer.cancel);
    await c.start(resilienceProblem('20-open'), options: longOptions);
    await until(c, (s) => s.state == OptimizationState.running);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(ticks, greaterThan(10));
    await c.cancel();
  });
  test(
    'fatal host failure retains a validated incumbent and releases resources',
    () async {
      final c = OptimizationController();
      addTearDown(c.dispose);
      await c.start(resilienceProblem('6-open'), options: longOptions);
      await until(c, (s) => s.best != null);
      final best = c.value.best;
      await c.abort('Simulated host execution failure');
      expect(c.value.state, OptimizationState.failed);
      expect(c.value.best, same(best));
      expect(c.value.proof, OptimizationProof.feasibleUnproven);
      expect(c.hasWorker, false);
    },
  );
  test('progress cadence avoids per-node messages and every delivered best improves', () async {
    final c = OptimizationController();
    addTearDown(c.dispose);
    final seen = <OptimizationSnapshot>[];
    final sub = c.events.listen(seen.add);
    addTearDown(sub.cancel);
    await c.start(
      resilienceProblem('6-open'),
      options: const OptimizationOptions(
        budget: Duration(milliseconds: 200),
        candidateOrdering: true,
        earlyDeadEnds: true,
        progressInterval: Duration(milliseconds: 50),
      ),
    );
    await until(c, (s) => s.state == OptimizationState.timedOut);
    expect(c.value.nodes, greaterThan(seen.length));
    Solution? best;
    for (final event in seen) {
      if (event.best != null && !identical(event.best, best)) {
        if (best != null) {
          expect(
            event.best!.clinicalQuality!.compareTo(best.clinicalQuality!),
            lessThan(0),
          );
        }
        best = event.best;
      }
    }
  });
  test('dispose clears timeout frontier and rejects reuse', () async {
    final c = OptimizationController();
    await c.start(
      small(),
      options: const OptimizationOptions(budget: Duration.zero),
    );
    await until(c, (s) => s.state == OptimizationState.timedOut);
    await c.dispose();
    expect(c.hasWorker, false);
    expect(() => c.start(small()), throwsStateError);
  });
}
