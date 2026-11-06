import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/clinical_quality.dart';

Solution solution(Problem p, List<int> ids) {
  final counts = List<int>.filled(p.doctors.length, 0);
  for (final id in ids) {
    counts[id]++;
  }
  final ordered = [...counts]..sort();
  return Solution(ids, [
    ordered.isEmpty ? 0 : ordered.last - ordered.first,
    counts.fold<int>(0, (a, b) => a + b * b),
  ]);
}

Problem make({
  required List<Doctor> doctors,
  required List<int> slots,
  required List<DutyRole> roles,
  List<DayDifficulty>? scores,
}) => Problem(
  startDate: DateTime.utc(2026, 11, 1),
  doctors: doctors,
  slotsPerDay: slots,
  slotRoles: roles,
  dayDifficulties:
      scores ?? [for (final _ in slots) const DayDifficulty(weekdayScore: 3)],
);
void main() {
  const evaluator = ClinicalQualityEvaluator();
  final seniors = [
    for (var i = 0; i < 4; i++)
      Doctor(id: 's$i', seniorityLevel: SeniorityLevel.values[i]),
  ];
  final juniors = [
    Doctor(id: 'j1', group: DutyGroup.junior),
    Doctor(id: 'j2', group: DutyGroup.junior),
  ];
  test('snapshot date, weekdays and holiday maximum survive roundtrip', () {
    final p = make(
      doctors: [seniors[0]],
      slots: [1, 0],
      roles: [DutyRole.senior],
      scores: [
        const DayDifficulty(
          weekdayScore: 9,
          holidayName: 'Tatil',
          holidayScore: 6,
        ),
        const DayDifficulty(
          weekdayScore: 2,
          holidayName: 'Bayram',
          holidayScore: 8,
        ),
      ],
    );
    final clone = Problem.fromMessage(p.toMessage());
    expect(clone.startDate, p.startDate);
    expect(clone.startDate!.weekday, DateTime.sunday);
    expect(clone.dayDifficulties!.map((d) => d.effectiveScore), [9, 8]);
    expect(clone.dayDifficulties!.last.holidayName, 'Bayram');
    expect(
      () => make(
        doctors: [seniors[0]],
        slots: [1],
        roles: [DutyRole.senior],
        scores: [const DayDifficulty(weekdayScore: 3, holidayName: 'Tatil')],
      ),
      throwsArgumentError,
    );
  });
  test('coverage, second junior and K4 solo quality', () {
    final p = make(
      doctors: [...seniors, ...juniors],
      slots: [3, 1, 0, 0, 1],
      roles: [
        DutyRole.senior,
        DutyRole.junior,
        DutyRole.junior,
        DutyRole.senior,
        DutyRole.senior,
      ],
    );
    final q = evaluator.evaluate(p, solution(p, [0, 4, 5, 3, 2]));
    expect(q.components.take(7).map((e) => e.toString()), [
      '0',
      '-1',
      '-1',
      '-1',
      '-1',
      '0',
      '-1',
    ]);
    expect(
      evaluator.evaluate(p, solution(p, [0, 4, 5, 3, 2])).components,
      q.components,
    );
  });
  test('K4 and coverage higher objectives outrank lower objectives', () {
    final p = make(doctors: seniors, slots: [1], roles: [DutyRole.senior]);
    final k4 = evaluator.evaluate(p, solution(p, [3]));
    final k1 = evaluator.evaluate(p, solution(p, [0]));
    expect(k4.compareTo(k1), lessThan(0));
    final a = ClinicalQuality([
          Exact.integer(0),
          Exact.integer(-2),
          Exact.integer(999),
        ]),
        b = ClinicalQuality([
          Exact.integer(0),
          Exact.integer(-1),
          Exact.integer(0),
        ]);
    expect(a.compareTo(b), lessThan(0));
  });
  test('category group fairness and exact personal capacity ratio', () {
    final docs = [
      Doctor(id: 'a', maxDuties: 2, seniorityLevel: SeniorityLevel.k1),
      Doctor(id: 'b', maxDuties: 4, seniorityLevel: SeniorityLevel.k2),
      Doctor(id: 'zero', maxDuties: 0, group: DutyGroup.junior),
    ];
    // Sunday, Wednesday, Saturday: two duties for b, one for a.
    final p = make(
      doctors: docs,
      slots: [1, 0, 0, 1, 0, 0, 1],
      roles: [DutyRole.senior, DutyRole.senior, DutyRole.senior],
    );
    final q = evaluator.evaluate(p, solution(p, [0, 1, 1]));
    // category pairs start at index 7: Saturday, Friday, Sunday, Thursday.
    expect(q.components.sublist(7, 15).map((x) => x.toString()), [
      '1',
      '1',
      '0',
      '0',
      '1',
      '1',
      '0',
      '0',
    ]);
    expect(q.components.sublist(15, 17).map((x) => x.toString()), ['0', '0']);
  });
  test('difficulty group range and maximum use effective daily score', () {
    final p = make(
      doctors: [seniors[0], seniors[1]],
      slots: [1, 0, 0, 1],
      roles: [DutyRole.senior, DutyRole.senior],
      scores: [
        const DayDifficulty(
          weekdayScore: 3,
          holidayName: 'Tatil',
          holidayScore: 9,
        ),
        const DayDifficulty(weekdayScore: 3),
        const DayDifficulty(weekdayScore: 3),
        const DayDifficulty(weekdayScore: 5),
      ],
    );
    final q = evaluator.evaluate(p, solution(p, [0, 1]));
    expect(q.components.sublist(17).map((x) => x.toString()), ['4', '9']);
  });
  test('capacity-normalized fairness uses exact sixth and zero capacity is excluded', () {
    final p = make(
      doctors: [
        Doctor(id: 'a', maxDuties: 2, seniorityLevel: SeniorityLevel.k1),
        Doctor(id: 'b', maxDuties: 3, seniorityLevel: SeniorityLevel.k2),
        Doctor(id: 'z', maxDuties: 0, group: DutyGroup.junior),
      ],
      slots: [1, 0, 0, 1],
      roles: [DutyRole.senior, DutyRole.senior],
    );
    final q = evaluator.evaluate(p, solution(p, [0, 1]));
    expect(q.components[15].toString(), '1/6');
    expect(q.components[16].toString(), '1/6');
  });
  test('all four calendar categories and group symmetry', () {
    final p = make(
      doctors: [seniors[0], seniors[1], seniors[2]],
      slots: [1, 0, 0, 0, 1, 1, 1],
      roles: [
        DutyRole.senior,
        DutyRole.senior,
        DutyRole.senior,
        DutyRole.senior,
      ],
    );
    final q = evaluator.evaluate(p, solution(p, [0, 1, 0, 2]));
    expect(q.components.sublist(7, 15).map((x) => x.toString()), [
      '1',
      '1',
      '1',
      '1',
      '1',
      '1',
      '1',
      '1',
    ]);
  });
  test(
    'proven local substitution evaluated but never grants permanent approval',
    () {
      final input = make(
        doctors: [Doctor(id: 'j', group: DutyGroup.junior)],
        slots: [1],
        roles: [DutyRole.senior],
      );
      final session = TransitionSession(input);
      var r = session.run(maxNodes: 100);
      while (r.canResume) {
        r = session.run(maxNodes: 100);
      }
      expect(r.status, SearchStatus.optimal);
      expect(
        () => evaluator.evaluate(session.problem, r.best!),
        throwsArgumentError,
      );
      final q = evaluator.evaluate(
        session.problem,
        r.best!,
        localEvidence: session,
      );
      expect(q.components.first.toString(), '1');
      expect(session.problem.dayDifficulties!.single.effectiveScore, 3);
    },
  );
  test('invalid assignment and missing clinical snapshot rejected', () {
    final p = make(
      doctors: [seniors[0]],
      slots: [1, 1],
      roles: [DutyRole.senior, DutyRole.senior],
    );
    expect(
      () => evaluator.evaluate(p, solution(p, [0, 0])),
      throwsArgumentError,
    );
    final old = Problem(doctors: [seniors[0]], slotsPerDay: [1]);
    expect(
      () => evaluator.evaluate(old, solution(old, [0])),
      throwsArgumentError,
    );
    expect(
      Exact(
        BigInt.one,
        BigInt.from(3),
      ).compareTo(Exact(BigInt.from(2), BigInt.from(6))),
      0,
    );
  });
}
