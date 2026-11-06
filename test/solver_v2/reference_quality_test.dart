import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/clinical_quality.dart';

import 'support/reference_clinical_quality.dart';

Solution raw(Problem p, List<int> xs, {bool phaseB = false}) {
  final counts = List<int>.filled(p.doctors.length, 0);
  var transitions = 0;
  for (var i = 0; i < xs.length; i++) {
    if (xs[i] < 0) continue;
    counts[xs[i]]++;
    if (p.slotRoles![i] == DutyRole.senior &&
        p.doctors[xs[i]].group == DutyGroup.junior) {
      transitions++;
    }
  }
  final sorted = [...counts]..sort();
  return Solution(xs, [
    if (phaseB) transitions,
    if (counts.isEmpty) 0 else sorted.last - sorted.first,
    counts.fold<int>(0, (a, b) => a + b * b),
  ]);
}

void compare(
  Problem p,
  Solution s, {
  TransitionSession? phaseB,
  String seed = 'manual',
}) {
  final expected = const ReferenceClinicalQualityCalculator().calculate(
    p,
    s.assignments,
  );
  final actual = phaseB == null
      ? const ClinicalQualityEvaluator().evaluate(p, s)
      : const ClinicalQualityEvaluator().evaluatePhaseBCandidate(
          p,
          s,
          session: phaseB,
        );
  expect(actual.components.length, 19);
  expect(expected.length, 19);
  for (var i = 0; i < 19; i++) {
    expect(
      actual.components[i].toString(),
      expected[i].toString(),
      reason:
          'seed=$seed snapshot=${jsonEncode(p.toMessage())} assignments=${s.assignments} component=$i expected=${expected[i]} actual=${actual.components[i]}',
    );
  }
}

(Problem, Solution) generated(Random r, int index) {
  final ns = r.nextInt(5), nj = r.nextInt(4), days = 1 + r.nextInt(8);
  final doctors = [
    for (var i = 0; i < ns; i++)
      Doctor(
        id: 's$i',
        group: DutyGroup.senior,
        seniorityLevel: SeniorityLevel.values[i],
        maxDuties: r.nextInt(9),
      ),
    for (var i = 0; i < nj; i++)
      Doctor(id: 'j$i', group: DutyGroup.junior, maxDuties: r.nextInt(9)),
  ];
  final slots = <int>[],
      roles = <DutyRole>[],
      requirements = <SlotRequirement>[],
      assignments = <int>[];
  final counts = List<int>.filled(doctors.length, 0),
      last = List<int>.filled(doctors.length, -100);
  for (var d = 0; d < days; d++) {
    final length = r.nextInt(4);
    slots.add(length);
    for (var k = 0; k < length; k++) {
      final role = k == 0 ? DutyRole.senior : DutyRole.junior;
      roles.add(role);
      final candidates = <int>[
        for (var i = 0; i < doctors.length; i++)
          if (doctors[i].group ==
                  (role == DutyRole.senior
                      ? DutyGroup.senior
                      : DutyGroup.junior) &&
              counts[i] < doctors[i].maxDuties &&
              d - last[i] >= 3)
            i,
      ];
      final selected = candidates.isEmpty || r.nextInt(4) == 0
          ? -1
          : candidates[r.nextInt(candidates.length)];
      assignments.add(selected);
      requirements.add(
        selected == -1 || r.nextBool()
            ? SlotRequirement.optional
            : SlotRequirement.required,
      );
      if (selected >= 0) {
        counts[selected]++;
        last[selected] = d;
      }
    }
  }
  final p = Problem(
    startDate: DateTime.utc(2026, 1, 1 + r.nextInt(28)),
    doctors: doctors,
    slotsPerDay: slots,
    slotRoles: roles,
    slotRequirements: requirements,
    dayDifficulties: [
      for (var d = 0; d < days; d++)
        DayDifficulty(
          weekdayScore: 1 + r.nextInt(10),
          holidayName: (index + d) % 4 == 0 ? 'Tatil' : null,
          holidayScore: (index + d) % 4 == 0 ? 1 + r.nextInt(10) : null,
        ),
    ],
  );
  return (p, raw(p, assignments));
}

void main() {
  test('hand calculated weekdays and both group gaps', () {
    final p = Problem(
      startDate: DateTime.utc(2026, 1, 1),
      doctors: [
        for (var i = 0; i < 3; i++)
          Doctor(id: 's$i', seniorityLevel: SeniorityLevel.values[i]),
        for (var i = 0; i < 3; i++) Doctor(id: 'j$i', group: DutyGroup.junior),
      ],
      slotsPerDay: [2, 2, 2, 2],
      slotRoles: [
        for (var i = 0; i < 4; i++) ...[DutyRole.senior, DutyRole.junior],
      ],
      slotRequirements: List.filled(8, SlotRequirement.required),
      dayDifficulties: [
        for (final score in [1, 6, 9, 5]) DayDifficulty(weekdayScore: score),
      ],
    );
    final xs = [0, 3, 1, 4, 2, 5, 0, 3];
    final expected = [
      '0',
      '-4',
      '0',
      '0',
      '-1',
      '-1',
      '-2',
      '1',
      '2',
      '1',
      '2',
      '1',
      '2',
      '1',
      '2',
      '1/8',
      '1/4',
      '3',
      '9',
    ];
    compare(p, raw(p, xs));
    expect(
      const ReferenceClinicalQualityCalculator()
          .calculate(p, xs)
          .map((v) => v.toString()),
      expected,
    );
    expect(
      const ClinicalQualityEvaluator()
          .evaluate(p, raw(p, xs))
          .components
          .map((v) => v.toString()),
      expected,
    );
  });
  test('hand calculated full 19-component examples', () {
    final cases = <(Problem, List<int>, List<String>)>[
      (
        Problem(
          startDate: DateTime.utc(2026, 11, 1),
          doctors: [
            Doctor(id: 's', seniorityLevel: SeniorityLevel.k4),
            Doctor(id: 'j1', group: DutyGroup.junior),
            Doctor(id: 'j2', group: DutyGroup.junior),
          ],
          slotsPerDay: [3],
          slotRoles: [DutyRole.senior, DutyRole.junior, DutyRole.junior],
          slotRequirements: List.filled(3, SlotRequirement.required),
          dayDifficulties: [
            const DayDifficulty(
              weekdayScore: 3,
              holidayName: 'Tatil',
              holidayScore: 5,
            ),
          ],
        ),
        [0, 1, 2],
        [
          '0',
          '-1',
          '-1',
          '-1',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '5',
        ],
      ),
      (
        Problem(
          startDate: DateTime.utc(2026, 11, 1),
          doctors: [
            Doctor(id: 's1', seniorityLevel: SeniorityLevel.k1, maxDuties: 2),
            Doctor(id: 's2', seniorityLevel: SeniorityLevel.k2, maxDuties: 4),
            Doctor(id: 'j1', group: DutyGroup.junior, maxDuties: 2),
            Doctor(id: 'j2', group: DutyGroup.junior, maxDuties: 4),
          ],
          slotsPerDay: [2],
          slotRoles: [DutyRole.senior, DutyRole.junior],
          slotRequirements: List.filled(2, SlotRequirement.required),
          dayDifficulties: [
            const DayDifficulty(
              weekdayScore: 5,
              holidayName: 'Tatil',
              holidayScore: 2,
            ),
          ],
        ),
        [0, 2],
        [
          '0',
          '-1',
          '0',
          '0',
          '0',
          '0',
          '-1',
          '0',
          '0',
          '0',
          '0',
          '1',
          '2',
          '0',
          '0',
          '1/2',
          '1',
          '5',
          '5',
        ],
      ),
      (
        Problem(
          startDate: DateTime.utc(2026, 11, 1),
          doctors: [],
          slotsPerDay: [1],
          slotRoles: [DutyRole.junior],
          slotRequirements: [SlotRequirement.optional],
          dayDifficulties: [const DayDifficulty(weekdayScore: 1)],
        ),
        [-1],
        List.filled(19, '0'),
      ),
    ];
    for (final (p, xs, expected) in cases) {
      final s = raw(p, xs);
      compare(p, s);
      expect(
        const ReferenceClinicalQualityCalculator()
            .calculate(p, xs)
            .map((e) => e.toString()),
        expected,
      );
      expect(
        const ClinicalQualityEvaluator()
            .evaluate(p, s)
            .components
            .map((e) => e.toString()),
        expected,
      );
    }
  });
  test('500 seeded valid schedules agree on all components and ordering', () {
    const seed = 140500;
    final r = Random(seed);
    ClinicalQuality? previous;
    List<ReferenceFraction>? previousRef;
    final seenWeekdays = <int>{};
    final seenGroups = <String>{};
    var vacant = 0, holidays = 0, zeroCaps = 0;
    for (var i = 0; i < 500; i++) {
      final (p, s) = generated(r, i);
      compare(p, s, seed: '$seed case=$i');
      final ref = const ReferenceClinicalQualityCalculator().calculate(
            p,
            s.assignments,
          ),
          q = const ClinicalQualityEvaluator().evaluate(p, s);
      if (previous != null) {
        var cmp = 0;
        for (var j = 0; j < 19; j++) {
          cmp = ref[j].compareTo(previousRef![j]);
          if (cmp != 0) break;
        }
        expect(
          q.compareTo(previous).sign,
          cmp.sign,
          reason:
              'seed=$seed case=$i snapshot=${jsonEncode(p.toMessage())} assignments=${s.assignments}',
        );
      }
      previous = q;
      previousRef = ref;
      seenGroups.add(
        '${p.doctors.where((d) => d.group == DutyGroup.senior).length}/${p.doctors.where((d) => d.group == DutyGroup.junior).length}',
      );
      for (var d = 0; d < p.slotsPerDay.length; d++) {
        seenWeekdays.add(p.startDate!.add(Duration(days: d)).weekday);
        if (p.dayDifficulties![d].holidayName != null) holidays++;
      }
      vacant += s.assignments.where((x) => x == -1).length;
      zeroCaps += p.doctors.where((d) => d.maxDuties == 0).length;
    }
    expect(seenWeekdays.length, 7);
    expect(seenGroups.length, greaterThan(10));
    expect(vacant, greaterThan(0));
    expect(holidays, greaterThan(0));
    expect(zeroCaps, greaterThan(0));
  });
  test('phase B substitution component uses proven local session', () {
    final p = Problem(
      startDate: DateTime.utc(2026),
      doctors: [Doctor(id: 'j', group: DutyGroup.junior)],
      slotsPerDay: [1],
      slotRoles: [DutyRole.senior],
      slotRequirements: [SlotRequirement.required],
      dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
    );
    final s = TransitionSession(p);
    expect(s.run(maxNodes: 100).pauseReason, PauseReason.stageTransition);
    final candidate = raw(s.problem, [0], phaseB: true);
    compare(s.problem, candidate, phaseB: s);
    expect(
      const ReferenceClinicalQualityCalculator()
          .calculate(s.problem, [0])
          .map((e) => e.toString()),
      [
        '1',
        '-1',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '3',
      ],
    );
  });
  test(
    'large exact fractions, negative values and serialization are lossless',
    () {
      final n = BigInt.parse('123456789012345678901234567890123456789');
      final d = BigInt.parse('987654321098765432109876543210987654321');
      final a = ReferenceFraction(n, d),
          b = ReferenceFraction(n * BigInt.from(2), d * BigInt.from(2));
      expect(a.compareTo(b), 0);
      final x = Exact(-n, d),
          y = Exact(-n * BigInt.from(2), d * BigInt.from(2));
      expect(x.compareTo(y), 0);
      final values = ClinicalQuality([
        x,
        for (var i = 1; i < 19; i++) Exact.integer(-i),
      ]);
      expect(
        ClinicalQuality.fromMessage(values.toMessage()).compareTo(values),
        0,
      );
      expect(x.toString(), ReferenceFraction(-n, d).toString());
    },
  );
}
