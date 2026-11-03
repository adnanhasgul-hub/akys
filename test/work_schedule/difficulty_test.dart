import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:akys/modules/work_schedule/domain/models.dart';
import 'package:akys/modules/work_schedule/domain/difficulty.dart';
import 'package:akys/modules/work_schedule/data/calendar/turkey_holidays.dart';
import 'package:akys/modules/work_schedule/engine/duty_engine.dart';
import 'package:akys/modules/work_schedule/application/schedule_export.dart';

import 'engine_test.dart' show sample;
import 'group_engine_test.dart' show criticalFixture;

DifficultySnapshot scoring(
  int year,
  int month, {
  DifficultySettings? settings,
  List<HolidayDay> custom = const [],
  Map<String, int>? overrides,
}) {
  final calendar = TurkeyHolidayCalendar.month(year, month, custom: custom);
  final values =
      overrides ??
      {
        for (final h in calendar)
          if (DateTime.parse(h.date).month == month &&
              DateTime.parse(h.date).year == year)
            h.date: 8,
      };
  return DifficultySnapshot(
    settings: settings ?? DifficultySettings.defaults(),
    calendar: calendar,
    overrides: values,
  );
}

ScheduleMonth weightedMonth(ScheduleMonth base, DifficultySnapshot snapshot) =>
    ScheduleMonth.fromJson({
      ...base.toJson(),
      'difficultySchemaVersion': 1,
      'difficultySettingsSnapshot': snapshot.settings.toJson(),
      'holidayCalendarSnapshot': snapshot.calendar
          .map((h) => h.toJson())
          .toList(),
      'holidayDifficultyOverrides': snapshot.overrides,
    });
int difficultyRange(ScheduleMonth m) {
  final values = statistics(m).values.map((s) => s.totalDifficulty).toList()
    ..sort();
  return values.last - values.first;
}

void main() {
  test('Default weekday and pre-holiday scores', () {
    final s = DifficultySettings.defaults();
    expect(s.weekdayScores, [3, 3, 3, 1, 6, 9, 5]);
    expect(s.preHolidayDifficultyScore, 6);
  });
  test('Scores must be integer 1..10, exactly seven weekdays', () {
    for (final n in [0, 11, -1]) {
      expect(
        () => DifficultySettings(
          weekdayScores: [n, 3, 3, 1, 6, 9, 5],
          preHolidayDifficultyScore: 6,
        ),
        throwsArgumentError,
      );
      expect(
        () => DifficultySettings(
          weekdayScores: [3, 3, 3, 1, 6, 9, 5],
          preHolidayDifficultyScore: n,
        ),
        throwsArgumentError,
      );
    }
    expect(validDifficultyScore(3.5), false);
    expect(validDifficultyScore('6'), false);
    expect(
      () =>
          DifficultySettings(weekdayScores: [3], preHolidayDifficultyScore: 6),
      throwsArgumentError,
    );
  });
  test(
    'TBB verified years and exact religious dates; no estimated fallback',
    () {
      expect(TurkeyHolidayCalendar.supportedYears, [
        2025,
        2026,
        2027,
        2028,
        2029,
        2030,
        2031,
        2032,
      ]);
      expect(
        TurkeyHolidayCalendar.year(2026)
            .firstWhere((h) => h.name == 'Ramazan Bayramı 1. Gün')
            .date,
        '2026-03-20',
      );
      expect(
        TurkeyHolidayCalendar.year(2027)
            .firstWhere((h) => h.name == 'Ramazan Bayramı 1. Gün')
            .date,
        '2027-03-09',
      );
      expect(
        TurkeyHolidayCalendar.year(2026)
            .firstWhere((h) => h.date == '2026-05-26')
            .isHalfDay,
        true,
      );
      expect(() => TurkeyHolidayCalendar.month(2040, 11), throwsStateError);
    },
  );
  test(
    'Overlapping national/religious days merge and full-day wins over half-day',
    () {
      final h = TurkeyHolidayCalendar.year(2029)
          .firstWhere((h) => h.date == '2029-04-23');
      expect(h.isHalfDay, false);
      expect(h.name, contains('Kurban'));
      expect(h.name, contains('Çocuk'));
      final overlapping = TurkeyHolidayCalendar.year(2027)
          .where((h) => h.date == '2027-05-19');
      expect(overlapping, hasLength(1));
    },
  );
  test(
    'Every required holiday needs its own score and supports different values',
    () {
      final base = scoring(2026, 3, overrides: {});
      expect(() => base.validateMonth(2026, 3), throwsArgumentError);
      final selected = scoring(
        2026,
        3,
        overrides: {
          '2026-03-19': 1,
          '2026-03-20': 5,
          '2026-03-21': 9,
          '2026-03-22': 3,
        },
      );
      selected.validateMonth(2026, 3);
      expect(
        [
          for (var d = 19; d <= 22; d++)
            selected.score(DateTime.utc(2026, 3, d)),
        ],
        [1, 5, 9, 3],
      );
    },
  );
  test('Pre-holiday Thursday is configured pre-holiday score, including month boundary', () {
    final s = scoring(2026, 4);
    expect(s.score(DateTime.utc(2026, 4, 30)), 6);
    expect(s.isPreHoliday(DateTime.utc(2026, 4, 30)), true);
  });
  test('Pre-holiday Sunday is six', () {
    expect(scoring(2027, 8).score(DateTime.utc(2027, 8, 29)), 6);
  });
  test(
    'Pre-holiday Saturday uses current Saturday snapshot, never fixed six',
    () {
      final settings = DifficultySettings(
        weekdayScores: [3, 3, 3, 1, 6, 10, 5],
        preHolidayDifficultyScore: 2,
      );
      expect(
        scoring(2026, 8, settings: settings).score(DateTime.utc(2026, 8, 29)),
        10,
      );
    },
  );
  test('Consecutive holiday override wins, scores are not added', () {
    final s = scoring(
      2026,
      5,
      overrides: {
        '2026-05-01': 1,
        '2026-05-19': 2,
        '2026-05-26': 3,
        '2026-05-27': 10,
        '2026-05-28': 4,
        '2026-05-29': 7,
        '2026-05-30': 9,
      },
    );
    expect(s.score(DateTime.utc(2026, 5, 27)), 10);
    expect(s.score(DateTime.utc(2026, 5, 28)), 4);
  });
  test('December end sees fixed next-year New Year without predicting unknown religious dates', () {
    expect(scoring(2032, 12).score(DateTime.utc(2032, 12, 31)), 6);
  });
  test('Half-day holidays do not automatically trigger the previous day', () {
    final s = scoring(2026, 10);
    expect(s.holiday(DateTime.utc(2026, 10, 28))!.isHalfDay, true);
    expect(s.isPreHoliday(DateTime.utc(2026, 10, 27)), false);
    expect(s.score(DateTime.utc(2026, 10, 27)), 3);
    expect(s.score(DateTime.utc(2026, 10, 28)), 8);
    expect(s.isPreHoliday(DateTime.utc(2026, 10, 28)), true);
  });
  test(
    'Month beginning holiday remains present under calendar-only UTC semantics',
    () {
      final s = scoring(2026, 1);
      s.validateMonth(2026, 1);
      expect(s.score(DateTime.utc(2026, 1, 1)), 8);
      expect(holidayCalendarDate('2026-01-01').isUtc, true);
    },
  );
  test('Custom days have source/year/half-day metadata and cannot downgrade public holidays', () {
    final h = HolidayDay(
      date: '2026-11-05',
      name: 'Doğrulanmış özel gün',
      isHalfDay: false,
      source: 'Kullanıcı: Klinik kararı',
      calendarYear: 2026,
      custom: true,
      triggersPreHoliday: true,
    );
    final s = scoring(2026, 11, custom: [h]);
    expect(s.calendar.single.custom, true);
    expect(s.score(DateTime.utc(2026, 11, 4)), 6);
    final overlap = HolidayDay(
      date: '2026-01-01',
      name: 'Özel not',
      isHalfDay: true,
      source: 'Kullanıcı',
      calendarYear: 2026,
      custom: true,
      triggersPreHoliday: false,
    );
    expect(
      TurkeyHolidayCalendar.month(2026, 1, custom: [overlap]).first.isHalfDay,
      false,
    );
  });
  test('Holiday Thursday keeps Thursday category and contributes its selected difficulty', () {
    final m = weightedMonth(sample(2026, 4), scoring(2026, 4));
    m.duties[23] = ['p1'];
    final s = statistics(m)['p1']!;
    expect(s.categories[1], 1);
    expect(s.holidayDuties, 1);
    expect(s.totalDifficulty, 8);
  });
  test(
    'Manual valid swap updates total difficulty and preserves hard constraints',
    () {
      final base = const DutyEngine()
          .generate(sample(2026, 11, total: 54))
          .month!;
      final m = weightedMonth(base, scoring(2026, 11));
      ScheduleMonth? changed;
      search:
      for (final a in m.duties.entries) {
        for (final b in m.duties.entries) {
          if (a.key >= b.key ||
              m.difficultyScore(a.key) == m.difficultyScore(b.key)) {
            continue;
          }
          for (final x in a.value) {
            for (final y in b.value) {
              if (x == y) continue;
              try {
                final candidate = editDuty(m, a.key, b.key, x, swap: y);
                if (statistics(candidate)[x]!.totalDifficulty !=
                    statistics(m)[x]!.totalDifficulty) {
                  changed = candidate;
                  break search;
                }
              } on StateError {
                /* Try next independent hard-feasible move. */
              }
            }
          }
        }
      }
      expect(changed, isNotNull);
      expect(validateDuties(changed!), isEmpty);
      expect(changed.manuallyEdited, isNotEmpty);
    },
  );
  test('November 2026 hard-valid high-spread regression is improved deterministically', () {
    final m = ScheduleMonth.fromJson(
      jsonDecode(
        File('test/fixtures/november_2026_difficulty_regression.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    expect(validateDuties(m), isEmpty);
    expect(difficultyRange(m), greaterThanOrEqualTo(15));
    final r = const DutyEngine().optimize(m);
    expect(r.errors, isEmpty);
    expect(validateDuties(r.month!), isEmpty);
    expect(difficultyRange(r.month!), lessThan(difficultyRange(m)));
    expect(
      objective(r.month!)[DutyObjective.saturdayExcess.index],
      lessThanOrEqualTo(objective(m)[DutyObjective.saturdayExcess.index]),
    );
    expect(
      jsonEncode(r.month!.toJson()),
      jsonEncode(const DutyEngine().optimize(m).month!.toJson()),
    );
  });
  test('Saturday protection outranks a favorable difficulty score', () {
    final balanced = weightedMonth(sample(2026, 11), scoring(2026, 11));
    balanced.duties.addAll({
      7: ['p1'],
      14: ['p2'],
      2: ['p1'],
      9: ['p2'],
    });
    final bad = balanced.clone();
    bad.duties[14] = ['p1'];
    bad.duties[2] = ['p2'];
    expect(
      objective(balanced)[DutyObjective.totalFairness.index],
      objective(bad)[DutyObjective.totalFairness.index],
    );
    expect(compareScore(objective(balanced), objective(bad)), lessThan(0));
  });
  test('Difficulty cannot override fixed senior K2/junior versus K4 solo preference', () {
    final (input, high, low, junior) = criticalFixture();
    final m = weightedMonth(input, scoring(2026, 11));
    final out = const DutyEngine().optimize(m).month!;
    expect(out.duties[high], containsAll(['p2', junior]));
    expect(out.duties[low], ['p4']);
    expect(validateDuties(out), isEmpty);
  });
  test(
    'Excel contains daily difficulty, holiday markers and person totals',
    () {
      final m = weightedMonth(sample(2026, 10), scoring(2026, 10))
        ..status = MonthStatus.finalised;
      final zip = ZipDecoder().decodeBytes(exportExcel(m));
      final xml = utf8.decode(
        zip.findFile('xl/worksheets/sheet1.xml')!.content,
      );
      expect(xml, contains('Zorluk Puanı'));
      expect(xml, contains('Cumhuriyet Bayramı'));
      expect(xml, contains('Yarım gün'));
      expect(xml, contains('Resmî Tatil'));
    },
  );
}
