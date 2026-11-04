import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/domain/duty_positions.dart';
import 'package:akys/modules/work_schedule/engine/v13/constraint_validator.dart';

import 'engine_test.dart' show sample;

DutyPositions row(
  int day, {
  String? senior = 'p1',
  List<String> juniors = const ['p5'],
  bool sub = false,
  String group = 'senior',
  String? reason,
}) => DutyPositions(
  date: '2026-11-${day.toString().padLeft(2, '0')}',
  seniorDutyPersonId: senior,
  juniorDutyPersonIds: juniors,
  seniorRoleIsSubstitution: sub,
  seniorRoleOriginalGroup: group,
  juniorVacancyReason: reason,
);
Set<String> codes(ScheduleMonth m, List<DutyPositions> rows) =>
    const ConstraintValidator().validate(m, rows).map((e) => e.code).toSet();
void main() {
  test('Complete month normal composition, max8 and three-day rest', () {
    final m = sample(2026, 11, count: 8);
    final rows = [
      for (var d = 1; d <= 30; d++)
        row(d, senior: 'p${(d - 1) % 4 + 1}', juniors: ['p${(d - 1) % 4 + 5}']),
    ];
    expect(codes(m, rows), isEmpty);
  });
  test('Explicit positions roundtrip, immutable juniors', () {
    final r = row(1);
    expect(DutyPositions.fromJson(r.toJson()).toJson(), r.toJson());
    expect(() => r.juniorDutyPersonIds.add('p6'), throwsUnsupportedError);
  });
  test(
    'Legacy V1.2 JSON remains byte-for-byte unchanged and no roles inferred',
    () {
      final json = sample(2026, 11).toJson();
      final before = jsonEncode(json);
      final read = PositionReadResult.fromMonthJson(json);
      expect(read.positions, isEmpty);
      expect(read.issues.single.code, 'LEGACY_POSITIONS_UNKNOWN');
      expect(read.issues.single.warning, true);
      expect(jsonEncode(json), before);
    },
  );
  test('Explicit JSON reader and malformed data', () {
    expect(
      PositionReadResult.fromMonthJson({
        'dutyPositions': [row(1).toJson()],
      }).issues,
      isEmpty,
    );
    expect(
      PositionReadResult.fromMonthJson({
        'dutyPositions': [{}],
      }).issues.single.code,
      'INVALID_POSITION_DATA',
    );
  });
  test('Duplicate roles report date person and rule, count only once', () {
    final m = sample(2026, 11);
    final issues = const ConstraintValidator().validate(m, [
      row(1, juniors: ['p1']),
    ]);
    final e = issues.firstWhere((e) => e.code == 'DUPLICATE_POSITION');
    expect(e.date, '2026-11-01');
    expect(e.personId, 'p1');
    expect(e.rule, isNotEmpty);
    expect(e.message, isNotEmpty);
    expect(
      codes(m, [
        row(1, juniors: ['p1']),
      ]),
      contains('SENIOR_IN_JUNIOR_ROLE'),
    );
  });
  test(
    'Triple and temporary senior are representable without changing group',
    () {
      final m = sample(2026, 11);
      final before = jsonEncode(m.toJson());
      expect(
        codes(m, [
          row(
            1,
            senior: 'p5',
            juniors: ['p6', 'p7'],
            sub: true,
            group: 'junior',
          ),
        ]),
        {'MISSING_DAY'},
      );
      expect(jsonEncode(m.toJson()), before);
      expect(
        codes(m, [row(1, senior: 'p5')]),
        contains('INVALID_SUBSTITUTION'),
      );
      expect(
        codes(m, [
          row(1, juniors: ['p5', 'p6', 'p7']),
        ]),
        contains('TOO_MANY_JUNIORS'),
      );
    },
  );
  test('Substitution order is rank based and inactive excluded', () {
    final m = sample(2026, 11);
    expect(substitutionCandidates(m).map((p) => p.personId), [
      'p5',
      'p6',
      'p7',
    ]);
  });
  test('Missing senior vacancy reason and duplicate dates', () {
    expect(
      codes(sample(2026, 11), [row(1, senior: null, juniors: []), row(1)]),
      containsAll([
        'MISSING_SENIOR',
        'MISSING_VACANCY_REASON',
        'DUPLICATE_DATE',
      ]),
    );
  });
  test('Maximum eight and rest exact boundary', () {
    final m = sample(2026, 11);
    expect(
      codes(m, [
        for (final d in [1, 4, 7, 10, 13, 16, 19, 22, 25]) row(d),
      ]),
      contains('MAXIMUM_EIGHT'),
    );
    expect(codes(m, [row(1), row(4)]), isNot(contains('REST_INTERVAL')));
    expect(codes(m, [row(1), row(3)]), contains('REST_INTERVAL'));
  });
  test('Must cannot conflicts and missing must', () {
    final m = sample(2026, 11);
    m.constraints['p1'] = PersonalConstraints(must: {1, 2}, cannot: {1});
    expect(
      codes(m, [row(1)]),
      containsAll([
        'MUST_CANNOT_CONFLICT',
        'CANNOT_ASSIGNED',
        'MISSING_MUST',
        'REST_INTERVAL',
      ]),
    );
  });
  test('Boundary only affects rest, previous counts not added', () {
    final m = sample(2026, 11);
    m.boundary['p1'] = ['2026-10-31'];
    expect(codes(m, [row(1)]), contains('BOUNDARY_REST'));
    expect(codes(m, [row(3)]), isNot(contains('BOUNDARY_REST')));
  });
  test('Invalid calendar dates and unknown IDs produce structured errors', () {
    expect(
      codes(sample(2026, 11), [row(31), row(1, senior: 'unknown')]),
      containsAll(['INVALID_DATE', 'INVALID_PERSON']),
    );
  });
}
