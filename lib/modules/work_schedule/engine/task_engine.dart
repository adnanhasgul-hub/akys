import '../domain/models.dart';

class DailyTask {
  const DailyTask(
    this.task,
    this.personId, {
    this.active = true,
    this.halfDay = false,
    this.manual = false,
    this.backup = false,
    this.warnings = const [],
  });
  final ClinicTask task;
  final String? personId;
  final bool active, halfDay;
  final bool manual, backup;
  String get workPeriodLabel => !active
      ? 'Görev yok (resmî iş günü değil)'
      : halfDay
      ? '13.00 öncesi'
      : 'Tam iş günü';
  final List<String> warnings;
  DailyTask warning(String text) => DailyTask(
    task,
    personId,
    active: active,
    halfDay: halfDay,
    manual: manual,
    backup: backup,
    warnings: [...warnings, text],
  );
}

bool postDuty(ScheduleMonth m, String id, int day) => day == 1
    ? (m.boundary[id] ?? []).contains(
        dateKey(m.date(1).subtract(const Duration(days: 1))),
      )
    : (m.duties[day - 1] ?? []).contains(id);
List<DailyTask> dailyTasks(ScheduleMonth m, int day) {
  final result = <DailyTask>[];
  var halfDay = false;
  if (m.taskWorkdaySchemaVersion > 0) {
    final date = m.date(day);
    final holidays = m.taskHolidayCalendarSnapshot.where(
      (h) => h.date == dateKey(date),
    );
    final inactive =
        date.weekday >= DateTime.saturday || holidays.any((h) => !h.isHalfDay);
    if (inactive) {
      return [
        for (final task in ClinicTask.values)
          DailyTask(task, null, active: false),
      ];
    }
    halfDay = holidays.any((h) => h.isHalfDay);
  }
  for (final task in ClinicTask.values) {
    final override = m.overrides['${dateKey(m.date(day))}|${task.name}'];
    if (override != null) {
      final exists = m.people.any((p) => p.personId == override.personId);
      result.add(
        DailyTask(
          task,
          exists ? override.personId : null,
          halfDay: halfDay,
          manual: true,
          warnings: [
            if (!exists) 'Geçersiz personel.',
            if (exists && postDuty(m, override.personId, day))
              'Manuel atanan kişi nöbet ertesi.',
          ],
        ),
      );
      continue;
    }
    final assignment = m.tasks[task];
    if (assignment == null) {
      result.add(
        DailyTask(
          task,
          null,
          halfDay: halfDay,
          warnings: ['Asıl / yedek seçilmedi.'],
        ),
      );
      continue;
    }
    final ids = m.people.map((p) => p.personId).toSet();
    String? person;
    var backup = false;
    if (ids.contains(assignment.primary) &&
        !postDuty(m, assignment.primary, day)) {
      person = assignment.primary;
    } else if (ids.contains(assignment.backup) &&
        !postDuty(m, assignment.backup, day)) {
      person = assignment.backup;
      backup = true;
    }
    result.add(
      DailyTask(
        task,
        person,
        halfDay: halfDay,
        backup: backup,
        warnings: [
          if (person == null)
            'Görev karşılanamıyor: asıl ve yedek uygun değil.',
        ],
      ),
    );
  }
  return [
    for (final r in result)
      if (r.personId != null &&
          result.where((x) => x.personId == r.personId).length > 1)
        r.warning('Aynı kişiye birden fazla görev atanmış.')
      else
        r,
  ];
}
