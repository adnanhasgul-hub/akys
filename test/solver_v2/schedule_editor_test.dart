import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';
import 'package:akys/solver_v2/clinical_quality.dart';
import 'package:akys/solver_v2/editing/schedule_editor.dart';

Doctor senior(
  String id, {
  int cap = 8,
  Set<int> must = const {},
  Set<int> cannot = const {},
  List<DateTime> previous = const [],
  Set<DutyRole> roles = const {DutyRole.senior, DutyRole.junior},
}) => Doctor(
  id: id,
  maxDuties: cap,
  must: must,
  unavailable: cannot,
  previousDuties: previous,
  eligibleRoles: roles,
  seniorityLevel: SeniorityLevel.k1,
);
Problem fixture({
  List<Doctor>? doctors,
  List<int> days = const [1, 0, 0, 1],
  List<DutyRole>? roles,
  List<SlotRequirement>? requirements,
}) {
  final n = days.fold<int>(0, (a, b) => a + b);
  return Problem(
    startDate: DateTime.utc(2026, 11),
    doctors: doctors ?? [senior('s1'), senior('s2')],
    slotsPerDay: days,
    slotRoles: roles ?? List.filled(n, DutyRole.senior),
    slotRequirements: requirements ?? List.filled(n, SlotRequirement.required),
    dayDifficulties: List.generate(
      days.length,
      (i) => DayDifficulty(weekdayScore: i % 10 + 1),
    ),
  );
}

void crossCheck(ScheduleEditor editor) {
  final s = editor.current;
  expect(s.validity, DraftValidity.valid);
  expect(
    const SolutionValidator().validate(editor.problem, s.solution!).isValid,
    true,
  );
  expect(
    const ClinicalQualityEvaluator()
        .evaluate(editor.problem, Solution(s.assignments, s.solution!.quality))
        .compareTo(s.quality!),
    0,
  );
  expect(s.optimalityProven, false);
}

void main() {
  test(
    'assignment builds draft then validated full schedule with 19 components',
    () {
      final e = ScheduleEditor(fixture());
      expect(e.current.canApprove, false);
      expect(e.assign(0, 0).accepted, true);
      expect(e.current.validity, DraftValidity.incomplete);
      expect(e.assign(1, 1).accepted, true);
      crossCheck(e);
      expect(e.current.quality!.components.length, 19);
    },
  );
  test(
    'invalid index and forbidden assignment are atomic with structured dates',
    () {
      final e = ScheduleEditor(
        fixture(
          doctors: [
            senior('s', cannot: {0}),
          ],
        ),
      );
      expect(e.assign(-1, 0).issues.single.code, EditCode.slotIndex);
      expect(e.assign(0, 7).issues.single.code, EditCode.doctorIndex);
      final r = e.assign(0, 0);
      expect(r.accepted, false);
      expect(r.after, same(r.before));
      expect(r.issues.single.code, EditCode.unavailable);
      expect(r.issues.single.date, DateTime.utc(2026, 11));
      expect(r.issues.single.personId, 's');
      expect(e.canUndo, false);
    },
  );
  test(
    'remove required creates incomplete draft; optional empty remains valid',
    () {
      final e = ScheduleEditor(
        fixture(
          requirements: [SlotRequirement.required, SlotRequirement.optional],
        ),
        assignments: [0, 1],
      );
      expect(e.remove(1).accepted, true);
      crossCheck(e);
      expect(e.remove(0).accepted, true);
      expect(e.current.quality, isNull);
      expect(e.current.issues.single.code, EditCode.requiredMissing);
      expect(e.current.canApprove, false);
    },
  );
  test('move is atomic and occupied target requires swap', () {
    final e = ScheduleEditor(fixture(), assignments: [0, -1]);
    expect(e.move(0, 1).accepted, true);
    expect(e.current.assignments, [-1, 0]);
    expect(e.move(0, 1).issues.single.code, EditCode.emptySource);
    e.assign(0, 1);
    expect(e.move(0, 1).issues.single.code, EditCode.occupiedTarget);
    crossCheck(e);
  });
  test('swap validates final simultaneous assignment, recomputes quality', () {
    final e = ScheduleEditor(fixture(), assignments: [0, 1]);
    final r = e.swap(0, 1);
    expect(r.accepted, true);
    expect(e.current.assignments, [1, 0]);
    expect(r.qualityComparison, isNotNull);
    crossCheck(e);
  });
  test('invalid swap leaves both assignments unchanged', () {
    final e = ScheduleEditor(
      fixture(
        doctors: [
          senior('a', cannot: {3}),
          senior('b'),
        ],
      ),
      assignments: [0, 1],
    );
    final r = e.swap(0, 1);
    expect(r.accepted, false);
    expect(r.after, same(r.before));
    expect(e.current.assignments, [0, 1]);
    expect(e.canUndo, false);
  });
  test('locks block assignment removal move and swap; explicit unlock permits edit', () {
    final e = ScheduleEditor(fixture(), assignments: [0, 1]);
    expect(e.lock(0).accepted, true);
    expect(e.current.locks, {0: 0});
    for (final r in [e.assign(0, 1), e.remove(0), e.move(0, 1), e.swap(1, 0)]) {
      expect(r.accepted, false);
      expect(r.issues.single.code, EditCode.locked);
    }
    expect(e.unlock(0).accepted, true);
    expect(e.swap(0, 1).accepted, true);
    crossCheck(e);
  });
  test('empty cannot lock; public assignments and locks immutable', () {
    final e = ScheduleEditor(fixture());
    expect(e.lock(0).issues.single.code, EditCode.emptySource);
    expect(() => e.current.assignments[0] = 0, throwsUnsupportedError);
    expect(() => e.current.locks[0] = 0, throwsUnsupportedError);
  });
  test(
    'undo redo restores locks assignments validity and resets redo on new edit',
    () {
      final e = ScheduleEditor(fixture(), assignments: [0, 1]);
      e.lock(0);
      e.unlock(0);
      e.remove(0);
      expect(e.current.validity, DraftValidity.incomplete);
      e.undo();
      crossCheck(e);
      e.undo();
      expect(e.current.locks, {0: 0});
      e.redo();
      expect(e.current.locks, isEmpty);
      e.redo();
      expect(e.current.validity, DraftValidity.incomplete);
      e.undo();
      expect(e.canRedo, true);
      e.assign(0, 1);
      expect(e.canRedo, false);
      expect(e.redo().issues.single.code, EditCode.noHistory);
    },
  );
  test('failed edit does not clear redo', () {
    final e = ScheduleEditor(fixture());
    e.assign(0, 0);
    e.undo();
    expect(e.assign(0, 99).accepted, false);
    expect(e.canRedo, true);
    e.redo();
    expect(e.current.assignments, [0, -1]);
  });
  test(
    'rest and same-day duplication rejected for optional assignments too',
    () {
      for (final days in [
        [1, 1],
        [2],
      ]) {
        final e = ScheduleEditor(
          fixture(
            days: days,
            requirements: [SlotRequirement.required, SlotRequirement.optional],
          ),
          assignments: [0, -1],
        );
        final r = e.assign(1, 0);
        expect(r.accepted, false);
        expect(
          r.issues.any(
            (x) =>
                x.code ==
                (days.length == 1 ? EditCode.duplicateDay : EditCode.rest),
          ),
          true,
        );
        crossCheck(e);
      }
    },
  );
  test(
    'three calendar day boundary accepted; previous month rest rejected',
    () {
      final e = ScheduleEditor(fixture(), assignments: [0, 0]);
      crossCheck(e);
      final p = fixture(
        doctors: [
          senior('a', previous: [DateTime.utc(2026, 10, 31)]),
        ],
      );
      final other = ScheduleEditor(p);
      expect(other.assign(0, 0).issues.single.code, EditCode.previousMonthRest);
      expect(other.assign(1, 0).accepted, true);
    },
  );
  test('optional counts toward individual and clinic capacity', () {
    final e = ScheduleEditor(
      fixture(
        doctors: [senior('s', cap: 1)],
        requirements: [SlotRequirement.required, SlotRequirement.optional],
      ),
      assignments: [0, -1],
    );
    expect(e.assign(1, 0).issues.single.code, EditCode.capacity);
    crossCheck(e);
  });
  test(
    'must requirement remains incomplete until filled on any eligible slot',
    () {
      final e = ScheduleEditor(
        fixture(
          doctors: [
            senior('s', must: {3}),
          ],
          requirements: [SlotRequirement.optional, SlotRequirement.optional],
        ),
      );
      expect(e.current.issues.single.code, EditCode.mustMissing);
      e.assign(1, 0);
      crossCheck(e);
      e.remove(1);
      expect(e.current.validity, DraftValidity.incomplete);
    },
  );
  test('role eligibility and senior-to-junior mismatch rejected', () {
    final e = ScheduleEditor(
      fixture(roles: [DutyRole.junior, DutyRole.senior]),
    );
    expect(e.assign(0, 0).issues.single.code, EditCode.role);
    final q = ScheduleEditor(
      fixture(
        doctors: [
          senior('s', roles: {DutyRole.junior}),
        ],
      ),
    );
    expect(q.assign(0, 0).issues.single.code, EditCode.role);
  });
  test('junior substitution cannot be inferred from imported schedule', () {
    final p = fixture(
      doctors: [Doctor(id: 'j', group: DutyGroup.junior)],
    );
    final e = ScheduleEditor(p, assignments: [0, 0]);
    expect(e.current.validity, DraftValidity.invalid);
    expect(e.current.canApprove, false);
    expect(e.current.issues.single.code, EditCode.transitionEvidence);
    expect(e.assign(0, 0).accepted, false);
  });
  test('completed B incumbent is preview only; different snapshot rejects evidence', () {
    final p = fixture(
      doctors: [Doctor(id: 'j', group: DutyGroup.junior)],
      days: [1],
    );
    final session = TransitionSession(p);
    session.run(maxNodes: 10000, timeLimit: const Duration(seconds: 1));
    expect(
      session
          .run(maxNodes: 10000, timeLimit: const Duration(seconds: 1))
          .status,
      SearchStatus.optimal,
    );
    final e = ScheduleEditor(
      session.problem,
      assignments: [0],
      localEvidence: session,
    );
    expect(e.current.validity, DraftValidity.provisionalTransition);
    expect(e.current.quality, isNotNull);
    expect(e.current.canApprove, false);
    expect(
      const SolutionValidator()
          .validate(
            session.problem,
            e.current.solution!,
            localEvidence: session,
          )
          .isValid,
      true,
      reason: const SolutionValidator()
          .validate(
            session.problem,
            e.current.solution!,
            localEvidence: session,
          )
          .errors
          .join('; '),
    );
    final copy = Problem.fromMessage(session.problem.toMessage());
    expect(
      ScheduleEditor(
        copy,
        assignments: [0],
        localEvidence: session,
      ).current.validity,
      DraftValidity.invalid,
    );
  });
  test('active B candidate can edit but cancellation invalidates context and undo rechecks', () {
    final p = fixture(
      doctors: [
        Doctor(id: 'j', group: DutyGroup.junior),
        Doctor(id: 'j2', group: DutyGroup.junior),
      ],
      days: [1, 0, 0, 1],
    );
    final session = TransitionSession(p);
    for (
      var i = 0;
      i < 1000 && !session.permitsPhaseBCandidate(session.problem);
      i++
    ) {
      session.run(maxNodes: 1, timeLimit: const Duration(seconds: 1));
    }
    expect(session.permitsPhaseBCandidate(session.problem), true);
    final e = ScheduleEditor(session.problem, localEvidence: session);
    expect(e.assign(0, 1).accepted, true);
    expect(e.assign(1, 0).accepted, true);
    expect(e.current.validity, DraftValidity.provisionalTransition);
    expect(
      const SolutionValidator()
          .validatePhaseBCandidate(
            session.problem,
            e.current.solution!,
            session: session,
          )
          .isValid,
      true,
    );
    e.lock(0);
    session.cancel();
    expect(e.current.validity, DraftValidity.invalid);
    e.undo();
    expect(e.current.validity, DraftValidity.invalid);
    expect(e.current.quality, isNull);
  });
  test('manual change loses solver proof and quality delta matches exact evaluator', () {
    final p = fixture();
    final session = TransitionSession(p);
    final result = session.run(
      maxNodes: 10000,
      timeLimit: const Duration(seconds: 1),
    );
    expect(result.status, SearchStatus.optimal);
    final e = ScheduleEditor(p, assignments: result.best!.assignments);
    expect(e.current.optimalityProven, false);
    final r = e.assign(0, 1);
    expect(r.accepted, true);
    crossCheck(e);
    expect(r.qualityComparison, r.after.quality!.compareTo(r.before.quality!));
    e.undo();
    expect(e.current.optimalityProven, false);
  });
  test('missing snapshot and slot count fail explicitly without search', () {
    expect(
      () => ScheduleEditor(Problem(doctors: [], slotsPerDay: [0])),
      throwsArgumentError,
    );
    expect(
      () => ScheduleEditor(fixture(), assignments: []),
      throwsArgumentError,
    );
  });
  test(
    'completed B evidence cannot authorize a different manual assignment',
    () {
      final session = TransitionSession(
        fixture(
          doctors: [
            Doctor(id: 'j1', group: DutyGroup.junior),
            Doctor(id: 'j2', group: DutyGroup.junior),
          ],
          days: [1],
        ),
      );
      session.run(maxNodes: 1000);
      final result = session.run(maxNodes: 1000);
      expect(result.status, SearchStatus.optimal);
      final e = ScheduleEditor(
        session.problem,
        assignments: result.best!.assignments,
        localEvidence: session,
      );
      final r = e.assign(0, 1 - result.best!.assignments[0]);
      expect(r.accepted, false);
      expect(r.issues.single.code, EditCode.transitionEvidence);
      expect(r.after, same(r.before));
      expect(e.current.canApprove, false);
    },
  );

  test('pending or cancelled A session grants no substitution authority', () {
    for (final cancel in [false, true]) {
      final session = TransitionSession(
        fixture(
          doctors: [Doctor(id: 'j', group: DutyGroup.junior)],
          days: [1],
        ),
      );
      session.run(maxNodes: 0, timeLimit: Duration.zero);
      if (cancel) session.cancel();
      final e = ScheduleEditor(session.problem, localEvidence: session);
      expect(e.assign(0, 0).issues.single.code, EditCode.transitionEvidence);
      expect(e.current.assignments, [-1]);
    }
  });

  test('move across same-day positions is atomic and leaves required source incomplete', () {
    final e = ScheduleEditor(
      fixture(
        days: [2],
        requirements: [SlotRequirement.required, SlotRequirement.optional],
      ),
      assignments: [0, -1],
    );
    expect(e.move(0, 1).accepted, true);
    expect(e.current.assignments, [-1, 0]);
    expect(e.current.issues.single.code, EditCode.requiredMissing);
    expect(e.move(1, 0).accepted, true);
    crossCheck(e);
  });

  test('optional addition produces nonzero quality change and undo restores full vector', () {
    final p = fixture(
      doctors: [
        senior('s'),
        Doctor(id: 'j', group: DutyGroup.junior),
      ],
      days: [2],
      roles: [DutyRole.senior, DutyRole.junior],
      requirements: [SlotRequirement.required, SlotRequirement.optional],
    );
    final e = ScheduleEditor(p, assignments: [0, -1]);
    final old = e.current.quality!;
    final r = e.assign(1, 1);
    expect(r.qualityComparison, lessThan(0));
    crossCheck(e);
    e.undo();
    expect(e.current.quality!.compareTo(old), 0);
    expect(e.current.optimalityProven, false);
  });
}
