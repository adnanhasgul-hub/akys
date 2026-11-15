import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/schedule_v2/workspace.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/runtime/lifecycle.dart';

Problem fixture({bool transition = false}) => Problem(
  doctors: [
    Doctor(
      id: 'S',
      seniorityLevel: SeniorityLevel.k4,
      unavailable: transition ? {0} : {},
    ),
    Doctor(id: 'J', group: DutyGroup.junior),
  ],
  startDate: DateTime.utc(2026, 11, 1),
  slotsPerDay: [2, 0, 0, 2],
  slotRoles: [
    DutyRole.senior,
    DutyRole.junior,
    DutyRole.senior,
    DutyRole.junior,
  ],
  slotRequirements: [
    SlotRequirement.required,
    SlotRequirement.optional,
    SlotRequirement.required,
    SlotRequirement.optional,
  ],
  dayDifficulties: List.filled(4, const DayDifficulty(weekdayScore: 3)),
);
Future<void> finish(ScheduleWorkspace w) async {
  await w.runtime.events
      .firstWhere(
        (s) => [
          OptimizationState.optimal,
          OptimizationState.infeasible,
          OptimizationState.failed,
          OptimizationState.timedOut,
        ].contains(s.state),
      )
      .timeout(const Duration(seconds: 10));
}

void main() {
  test('month construction covers UTC leap years and 30/31 days', () {
    for (final item in [
      (2024, 2, 29),
      (2026, 2, 28),
      (2026, 11, 30),
      (2026, 12, 31),
    ]) {
      final p = ScheduleWorkspace.emptyMonth(item.$1, item.$2);
      expect(p.startDate!.isUtc, true);
      expect(p.slotsPerDay.length, item.$3);
      expect(p.slotDays.length, item.$3 * 2);
    }
  });
  test('manual moves swaps locks undo redo and atomic failure', () {
    final w = ScheduleWorkspace(initial: fixture());
    addTearDown(w.dispose);
    w.edit((e) => e.assign(0, 0));
    w.edit((e) => e.assign(1, 1));
    w.edit((e) => e.lock(0));
    w.edit((e) => e.remove(0));
    expect(w.editor.current.assignments[0], 0);
    expect(w.error, isNotNull);
    w.edit((e) => e.unlock(0));
    w.edit((e) => e.move(0, 2));
    expect(w.editor.current.assignments, [-1, 1, 0, -1]);
    w.edit((e) => e.undo());
    expect(w.editor.current.assignments, [0, 1, -1, -1]);
    w.edit((e) => e.redo());
    expect(w.editor.current.assignments, [-1, 1, 0, -1]);
    w.edit((e) => e.assign(0, 0));
    w.edit((e) => e.swap(0, 1));
    expect(w.error, isNotNull);
    expect(w.editor.current.assignments, [0, 1, 0, -1]);
  });
  test(
    'real VM result stays separate until accepted and loses proof in editor',
    () async {
      final w = ScheduleWorkspace(initial: fixture());
      addTearDown(w.dispose);
      await w.start();
      await finish(w);
      expect(w.progress.state, OptimizationState.optimal);
      expect(w.editor.current.assignments.every((x) => x == -1), true);
      expect(await w.accept(), true);
      expect(w.editor.current.canApprove, true);
      expect(w.editor.current.optimalityProven, false);
      expect(w.pending, false);
    },
  );
  test(
    'locked reoptimization uses runtime and preserves locks and source',
    () async {
      final w = ScheduleWorkspace(initial: fixture());
      addTearDown(w.dispose);
      w.edit((e) => e.assign(0, 0));
      w.edit((e) => e.lock(0));
      final before = [...w.editor.current.assignments];
      await w.start(reoptimize: true);
      await finish(w);
      expect(w.editor.current.assignments, before);
      expect(w.difference!.preservedLocks, {0: 0});
      expect(await w.accept(), true);
      expect(w.editor.current.locks, {0: 0});
      w.edit((e) => e.unlock(0));
      expect(w.editor.current.locks, isEmpty);
    },
  );
  test('B worker result is preview only and cannot authorize editor', () async {
    final w = ScheduleWorkspace(initial: fixture(transition: true));
    addTearDown(w.dispose);
    await w.start();
    await finish(w);
    expect(w.previewOnly, true);
    expect(await w.accept(), false);
    expect(w.editor.current.assignments.every((x) => x == -1), true);
    await w.reject();
    expect(w.pending, false);
  });
  test('timeout, genuine extension and reject preserve draft', () async {
    final w = ScheduleWorkspace(initial: fixture());
    addTearDown(w.dispose);
    await w.start(budget: Duration.zero);
    await finish(w);
    expect(w.progress.state, OptimizationState.timedOut);
    w.runtime.extend(const Duration(seconds: 1));
    await finish(w);
    expect(w.progress.best, isNotNull);
    await w.reject();
    expect(w.editor.current.assignments.every((x) => x == -1), true);
  });
  test('configuration cannot mutate an active snapshot', () async {
    final w = ScheduleWorkspace(initial: fixture());
    addTearDown(w.dispose);
    await w.start(budget: Duration.zero);
    await finish(w);
    expect(() => w.replace(fixture()), throwsStateError);
    await w.reject();
    w.replace(fixture());
  });
}
