import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/clinical_quality.dart';
import 'package:akys/solver_v2/solution_validator.dart';

Solution build(Problem p, List<int> assignments) {
  final counts = List<int>.filled(p.doctors.length, 0);
  for (final i in assignments) {
    if (i >= 0 && i < counts.length) counts[i]++;
  }
  final sorted = [...counts]..sort();
  return Solution(assignments, [
    sorted.isEmpty ? 0 : sorted.last - sorted.first,
    counts.fold<int>(0, (a, b) => a + b * b),
  ]);
}

void main() {
  const v = SolutionValidator(), q = ClinicalQualityEvaluator();
  final doctors = [
    Doctor(id: 'k4', seniorityLevel: SeniorityLevel.k4),
    Doctor(id: 'k3', seniorityLevel: SeniorityLevel.k3),
    Doctor(id: 'j1', group: DutyGroup.junior),
    Doctor(id: 'j2', group: DutyGroup.junior),
  ];
  Problem p(
    List<int> slots,
    List<DutyRole> roles,
    List<SlotRequirement> requirements, {
    List<Doctor>? people,
  }) => Problem(
    startDate: DateTime.utc(2026, 11, 1),
    doctors: people ?? doctors,
    slotsPerDay: slots,
    slotRoles: roles,
    slotRequirements: requirements,
    dayDifficulties: [
      for (final _ in slots) const DayDifficulty(weekdayScore: 3),
    ],
  );
  test('one senior with zero, one or two juniors is one senior day', () {
    final m = p([3], [DutyRole.senior, DutyRole.junior, DutyRole.junior], [
      SlotRequirement.required,
      SlotRequirement.optional,
      SlotRequirement.optional,
    ]);
    for (final row in [
      [0, -1, -1],
      [0, 2, -1],
      [0, 2, 3],
    ]) {
      final solution = build(m, row);
      expect(v.validate(m, solution).isValid, isTrue);
      final quality = q.evaluate(m, solution).components;
      expect(quality[3].toString(), '-1');
      expect(quality[1].toString(), row[1] == -1 ? '0' : '-1');
      expect(quality[2].toString(), row[2] == -1 ? '0' : '-1');
    }
  });
  test('two seniors and a junior is not a single senior day', () {
    final m = p(
      [3],
      [DutyRole.senior, DutyRole.senior, DutyRole.junior],
      List.filled(3, SlotRequirement.required),
    );
    final s = build(m, [0, 1, 2]);
    expect(v.validate(m, s).isValid, isTrue);
    expect(q.evaluate(m, s).components.sublist(3, 7).map((x) => x.toString()), [
      '0',
      '0',
      '0',
      '0',
    ]);
  });
  test('required vacancy and duplicate invalid; optional filled counts', () {
    final m = p([3], [DutyRole.senior, DutyRole.junior, DutyRole.junior], [
      SlotRequirement.required,
      SlotRequirement.optional,
      SlotRequirement.optional,
    ]);
    expect(v.validate(m, build(m, [-1, 2, -1])).isValid, isFalse);
    expect(v.validate(m, build(m, [0, 2, 2])).isValid, isFalse);
    final r = v.validate(m, build(m, [0, 2, -1]));
    expect(r.isValid, isTrue);
    expect(r.quality, [1, 2]);
    expect(v.validate(m, build(m, [0, -2, -1])).isValid, isFalse);
  });
  test('optional assignments obey rest and maximum', () {
    final rest = p(
      [2, 1],
      [DutyRole.senior, DutyRole.junior, DutyRole.junior],
      [
        SlotRequirement.required,
        SlotRequirement.optional,
        SlotRequirement.optional,
      ],
    );
    expect(v.validate(rest, build(rest, [0, 2, 2])).isValid, isFalse);
    final capped = p(
      [2, 0, 0, 1],
      [DutyRole.senior, DutyRole.junior, DutyRole.junior],
      [
        SlotRequirement.required,
        SlotRequirement.optional,
        SlotRequirement.optional,
      ],
      people: [
        doctors[0],
        doctors[1],
        Doctor(id: 'j', group: DutyGroup.junior, maxDuties: 1),
      ],
    );
    expect(v.validate(capped, build(capped, [0, 2, 2])).isValid, isFalse);
  });
  test(
    'requirements survive snapshot roundtrip and legacy default required',
    () {
      final m = p([2], [DutyRole.senior, DutyRole.junior], [
        SlotRequirement.required,
        SlotRequirement.optional,
      ]);
      final copy = Problem.fromMessage(m.toMessage());
      expect(copy.slotRequirements, [
        SlotRequirement.required,
        SlotRequirement.optional,
      ]);
      final json = m.toMessage()..remove('slotRequirements');
      final legacy = Problem.fromMessage(json);
      expect(legacy.slotRequirements, [
        SlotRequirement.required,
        SlotRequirement.required,
      ]);
      expect(
        () => Problem(doctors: doctors, slotsPerDay: [1], slotRequirements: []),
        throwsArgumentError,
      );
      expect(() => SearchSession(m), throwsUnsupportedError);
      expect(() => TransitionSession(m), throwsUnsupportedError);
    },
  );
}
