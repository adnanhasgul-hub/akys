import '../../domain/difficulty.dart';

/// Transcribed from TBB's published 2025–2032 annual table. No lunar-date
/// prediction or remote service is used at runtime. See docs/HOLIDAY_CALENDAR_SOURCES.md.
abstract final class TurkeyHolidayCalendar {
  static const source =
      'https://www.tbb.org.tr/sites/default/files/docs/tatil-gunleri-2025-2032.pdf';
  static const religious = {
    2025: ['03-29', '03-30', '06-05', '06-06'],
    2026: ['03-19', '03-20', '05-26', '05-27'],
    2027: ['03-08', '03-09', '05-15', '05-16'],
    2028: ['02-25', '02-26', '05-04', '05-05'],
    2029: ['02-13', '02-14', '04-23', '04-24'],
    2030: ['02-03', '02-04', '04-12', '04-13'],
    2031: ['01-23', '01-24', '04-01', '04-02'],
    2032: ['01-13', '01-14', '03-21', '03-22'],
  };
  static List<int> get supportedYears => religious.keys.toList();
  static List<HolidayDay> year(int year) {
    final dates = religious[year];
    if (dates == null) {
      throw StateError(
        '$year yılı için doğrulanmış Türkiye tatil takvimi yok. Takvim doğrulaması gerekiyor; ay oluşturulmadı.',
      );
    }
    final entries = <HolidayDay>[];
    void add(String md, String name, {bool half = false}) => entries.add(
      HolidayDay(
        date: '$year-$md',
        name: name,
        isHalfDay: half,
        source: source,
        calendarYear: year,
        triggersPreHoliday: !half,
      ),
    );
    add('01-01', 'Yılbaşı');
    add('04-23', 'Ulusal Egemenlik ve Çocuk Bayramı');
    add('05-01', 'Emek ve Dayanışma Günü');
    add('05-19', 'Atatürk’ü Anma, Gençlik ve Spor Bayramı');
    add('07-15', 'Demokrasi ve Millî Birlik Günü');
    add('08-30', 'Zafer Bayramı');
    add('10-28', 'Cumhuriyet Bayramı Arifesi', half: true);
    add('10-29', 'Cumhuriyet Bayramı');
    add(dates[0], 'Ramazan Bayramı Arefesi', half: true);
    add(dates[2], 'Kurban Bayramı Arefesi', half: true);
    for (final (start, count, name) in [
      (dates[1], 3, 'Ramazan Bayramı'),
      (dates[3], 4, 'Kurban Bayramı'),
    ]) {
      final first = holidayCalendarDate('$year-$start');
      for (var day = 0; day < count; day++) {
        final d = first.add(Duration(days: day));
        add(holidayDateKey(d).substring(5), '$name ${day + 1}. Gün');
      }
    }
    return _merge(entries);
  }

  static List<HolidayDay> month(
    int year,
    int month, {
    List<HolidayDay> custom = const [],
  }) {
    final start = DateTime.utc(year, month, 1),
        end = DateTime.utc(year, month + 1, 1);
    final entries = TurkeyHolidayCalendar.year(year);
    // December's boundary only needs the legally fixed January 1; no unknown
    // religious calendar for the following year is inferred.
    if (month == 12) {
      entries.add(
        HolidayDay(
          date: holidayDateKey(end),
          name: 'Yılbaşı',
          isHalfDay: false,
          source: source,
          calendarYear: year + 1,
          triggersPreHoliday: true,
        ),
      );
    }
    entries.addAll(custom);
    return _merge(
      entries.where((h) {
        final d = holidayCalendarDate(h.date);
        return !d.isBefore(start) && !d.isAfter(end);
      }).toList(),
    );
  }

  static List<HolidayDay> _merge(List<HolidayDay> entries) {
    final result = <String, HolidayDay>{};
    for (final h in entries) {
      final old = result[h.date];
      result[h.date] = old == null
          ? h
          : HolidayDay(
              date: h.date,
              name: '${old.name} / ${h.name}',
              isHalfDay: old.isHalfDay && h.isHalfDay,
              source: old.source == h.source
                  ? old.source
                  : '${old.source}; ${h.source}',
              calendarYear: h.calendarYear,
              custom: old.custom || h.custom,
              triggersPreHoliday:
                  old.triggersPreHoliday || h.triggersPreHoliday,
            );
    }
    return result.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }
}
