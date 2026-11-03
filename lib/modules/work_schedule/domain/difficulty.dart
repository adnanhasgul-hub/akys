/// Pure domain types. Scores are snapshots, never reads of live settings.
String holidayDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime holidayCalendarDate(String value) {
  final d = DateTime.parse(value);
  return DateTime.utc(d.year, d.month, d.day);
}

bool validDifficultyScore(Object? score) =>
    score is int && score >= 1 && score <= 10;

class DifficultySettings {
  DifficultySettings({
    required List<int> weekdayScores,
    required this.preHolidayDifficultyScore,
    this.revision = 0,
    List<HolidayDay> customHolidays = const [],
  }) : weekdayScores = List.unmodifiable(weekdayScores),
       customHolidays = List.unmodifiable(customHolidays) {
    validate();
  }
  factory DifficultySettings.defaults() => DifficultySettings(
    weekdayScores: [3, 3, 3, 1, 6, 9, 5],
    preHolidayDifficultyScore: 6,
  );
  final List<HolidayDay> customHolidays;
  final List<int> weekdayScores;
  final int preHolidayDifficultyScore, revision;
  void validate() {
    if (weekdayScores.length != 7 ||
        weekdayScores.any((n) => !validDifficultyScore(n)) ||
        !validDifficultyScore(preHolidayDifficultyScore)) {
      throw ArgumentError('Puanlar 1–10 arasında tam sayı olmalı.');
    }
    if (customHolidays.length > 100 ||
        customHolidays.map((h) => h.date).toSet().length !=
            customHolidays.length) {
      throw ArgumentError(
        'Özel günler tekil olmalı; en fazla 100 kayıt eklenebilir.',
      );
    }
    for (final h in customHolidays) {
      final d = holidayCalendarDate(h.date);
      if (holidayDateKey(d) != h.date ||
          h.calendarYear != d.year ||
          !h.custom ||
          h.name.trim().isEmpty ||
          h.name.length > 120 ||
          h.source.trim().isEmpty ||
          h.source.length > 320 ||
          h.triggersPreHoliday == h.isHalfDay) {
        throw ArgumentError(
          'Özel gün tarihi, kaynağı veya yarım gün kuralı geçersiz.',
        );
      }
    }
  }

  DifficultySettings withRevision(int revision) => DifficultySettings(
    weekdayScores: weekdayScores,
    preHolidayDifficultyScore: preHolidayDifficultyScore,
    revision: revision,
    customHolidays: customHolidays,
  );
  Map<String, dynamic> toJson() => {
    'weekdayScores': weekdayScores,
    'preHolidayDifficultyScore': preHolidayDifficultyScore,
    'revision': revision,
    'schemaVersion': 1,
    'customHolidays': customHolidays.map((h) => h.toJson()).toList(),
  };
  factory DifficultySettings.fromJson(Map<String, dynamic> j) =>
      DifficultySettings(
        weekdayScores: List<int>.from(j['weekdayScores'] as List),
        preHolidayDifficultyScore: j['preHolidayDifficultyScore'] as int,
        revision: j['revision'] as int? ?? 0,
        customHolidays: [
          for (final h in j['customHolidays'] as List? ?? [])
            HolidayDay.fromJson(Map<String, dynamic>.from(h as Map)),
        ],
      );
}

class HolidayDay {
  const HolidayDay({
    required this.date,
    required this.name,
    required this.isHalfDay,
    required this.source,
    required this.calendarYear,
    this.custom = false,
    required this.triggersPreHoliday,
  });
  final String date, name, source;
  final int calendarYear;
  final bool isHalfDay, custom, triggersPreHoliday;
  Map<String, dynamic> toJson() => {
    'date': date,
    'name': name,
    'isHalfDay': isHalfDay,
    'source': source,
    'calendarYear': calendarYear,
    'custom': custom,
    'triggersPreHoliday': triggersPreHoliday,
  };
  factory HolidayDay.fromJson(Map<String, dynamic> j) => HolidayDay(
    date: j['date'] as String,
    name: j['name'] as String,
    isHalfDay: j['isHalfDay'] as bool,
    source: j['source'] as String,
    calendarYear: j['calendarYear'] as int,
    custom: j['custom'] as bool? ?? false,
    triggersPreHoliday:
        j['triggersPreHoliday'] as bool? ?? !(j['isHalfDay'] as bool),
  );
}

class DifficultySnapshot {
  DifficultySnapshot({
    required this.settings,
    required List<HolidayDay> calendar,
    required Map<String, int> overrides,
  }) : calendar = List.unmodifiable(calendar),
       overrides = Map.unmodifiable(overrides);
  final DifficultySettings settings;
  final List<HolidayDay> calendar;
  final Map<String, int> overrides;
  HolidayDay? holiday(DateTime date) {
    final key = holidayDateKey(date);
    for (final day in calendar) {
      if (day.date == key) return day;
    }
    return null;
  }

  bool isPreHoliday(DateTime date) =>
      holiday(date.add(const Duration(days: 1)))?.triggersPreHoliday ?? false;
  int score(DateTime date) {
    final key = holidayDateKey(date);
    if (holiday(date) != null) {
      final n = overrides[key];
      if (!validDifficultyScore(n)) {
        throw StateError('Resmî tatil puanı seçilmedi: $key');
      }
      return n!;
    }
    if (isPreHoliday(date) && date.weekday != 6) {
      return settings.preHolidayDifficultyScore;
    }
    return settings.weekdayScores[date.weekday - 1];
  }

  void validateMonth(int year, int month) {
    settings.validate();
    final end = DateTime.utc(year, month + 1, 0);
    final start = DateTime.utc(year, month, 1);
    final required = {
      for (final h in calendar)
        if (!holidayCalendarDate(h.date).isBefore(start) &&
            !holidayCalendarDate(h.date).isAfter(end))
          h.date,
    };
    if (overrides.keys.any((key) => !required.contains(key)) ||
        required.any((key) => !validDifficultyScore(overrides[key]))) {
      throw ArgumentError('Her resmî tatil için ayrı 1–10 puan seçin.');
    }
    if (calendar.map((h) => h.date).toSet().length != calendar.length) {
      throw ArgumentError('Aynı tarih için birden fazla tatil kaydı var.');
    }
  }
}
