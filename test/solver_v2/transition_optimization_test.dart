import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';

import 'solver_test.dart' show oracle;

void main() {
  Problem input() => Problem(
    startDate: DateTime.utc(2026, 11, 1),
    doctors: [
      Doctor(id: 's1'),
      Doctor(id: 's2'),
    ],
    slotsPerDay: [1, 0, 0, 1, 0, 0, 1],
    slotRoles: [DutyRole.senior, DutyRole.senior, DutyRole.senior],
  );
  test('restricted first incumbent is provisional and optimization resumes without reruns', () {
    final p = input(), expected = oracle(p);
    final session = TransitionSession(p);
    var r = session.run(maxNodes: 1);
    while (r.best == null) {
      r = session.run(maxNodes: 1);
    }
    final first = r.best!;
    final firstNodes = r.visitedNodes;
    expect(first.quality, [3, 9]);
    expect(r.status, SearchStatus.feasibleNotProven);
    expect(r.canResume, isTrue);
    expect(session.phase, TransitionPhase.restricted);
    expect(session.restrictedVerdict, RestrictedVerdict.feasible);
    final timed = session.run(maxNodes: 100, timeLimit: Duration.zero);
    expect(timed.status, SearchStatus.feasibleNotProven);
    expect(timed.best, same(first));
    expect(timed.pauseReason, PauseReason.deadline);
    expect(timed.canResume, isTrue);
    while (r.canResume) {
      r = session.run(maxNodes: 1);
    }
    expect(r.status, SearchStatus.optimal);
    expect(r.best!.quality, expected.first.$2);
    expect(r.best!.quality, [1, 5]);
    expect(r.visitedNodes, greaterThan(firstNodes));
    expect(session.phase, TransitionPhase.done);
    expect(session.restrictedVerdict, RestrictedVerdict.feasible);
    final uninterrupted = TransitionSession(p).run(maxNodes: 1000);
    expect(uninterrupted.status, SearchStatus.optimal);
    expect(r.visitedNodes, uninterrupted.visitedNodes);
    expect(r.best!.assignments, uninterrupted.best!.assignments);
    final unpruned = TransitionSession(
      p,
      enablePruning: false,
    ).run(maxNodes: 1000);
    expect(unpruned.status, SearchStatus.optimal);
    expect(unpruned.best!.quality, r.best!.quality);
  });
  test(
    'cancellation after incumbent preserves it and never opens substitution',
    () {
      final session = TransitionSession(input());
      var r = session.run(maxNodes: 1);
      while (r.best == null) {
        r = session.run(maxNodes: 1);
      }
      final held = r.best;
      session.cancel();
      r = session.run(maxNodes: 100);
      expect(r.status, SearchStatus.cancelled);
      expect(r.best, same(held));
      expect(session.restrictedVerdict, RestrictedVerdict.feasible);
      expect(session.phase, TransitionPhase.done);
    },
  );
  test(
    'timeout without incumbent and infeasibility have different outcomes',
    () {
      final impossible = Problem(
        startDate: DateTime.utc(2026, 11, 1),
        doctors: [Doctor(id: 'j', group: DutyGroup.junior)],
        slotsPerDay: [1],
        slotRoles: [DutyRole.senior],
      );
      final s = TransitionSession(impossible);
      expect(
        s.run(maxNodes: 100, timeLimit: Duration.zero).status,
        SearchStatus.timeoutWithoutSolution,
      );
      expect(s.restrictedVerdict, RestrictedVerdict.pending);
      expect(s.phase, TransitionPhase.restricted);
      final proof = s.run(maxNodes: 100);
      expect(proof.pauseReason, PauseReason.stageTransition);
      expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
      expect(s.phase, TransitionPhase.substitution);
    },
  );
}
