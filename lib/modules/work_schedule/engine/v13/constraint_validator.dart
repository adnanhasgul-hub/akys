import '../../domain/models.dart';
import '../../domain/duty_positions.dart';

/// Ranked candidates only; selection/feasibility proof belongs to later stages.
List<PersonSnapshot> substitutionCandidates(ScheduleMonth month) =>
    month.people
        .where(
          (p) =>
              p.activeAtCreation &&
              p.dutySeniorityGroup == DutySeniorityGroup.junior,
        )
        .toList()
      ..sort((a, b) {
        final rank = a.seniorityRank.compareTo(b.seniorityRank);
        return rank != 0 ? rank : a.personId.compareTo(b.personId);
      });

class ConstraintValidator {
  const ConstraintValidator();
  List<ConstraintIssue> validate(
    ScheduleMonth month,
    List<DutyPositions> positions,
  ) {
    final issues = <ConstraintIssue>[];
    void add(
      String code,
      String rule,
      String text, {
      String? date,
      String? person,
    }) => issues.add(
      ConstraintIssue(code, rule, text, date: date, personId: person),
    );
    final people = {for (final p in month.people) p.personId: p};
    if (people.length != month.people.length) {
      add('DUPLICATE_PERSON', 'personnel', 'Personel kimliği yineleniyor.');
    }
    final dates = <String>{};
    final assigned = <String, Set<int>>{};
    for (final row in positions) {
      final parsed = DateTime.tryParse(row.date);
      if (parsed == null ||
          dateKey(parsed) != row.date ||
          parsed.year != month.year ||
          parsed.month != month.month) {
        add(
          'INVALID_DATE',
          'calendar',
          'Nöbet tarihi seçilen ayda geçerli bir gün olmalıdır.',
          date: row.date,
        );
        continue;
      }
      if (!dates.add(row.date)) {
        add(
          'DUPLICATE_DATE',
          'dailyCoverage',
          'Aynı tarih birden fazla kaydedilmiş.',
          date: row.date,
        );
      }
      final senior = row.seniorDutyPersonId;
      if (senior == null || senior.isEmpty) {
        add(
          'MISSING_SENIOR',
          'dailyCoverage',
          'Senior pozisyonu dolu olmalıdır.',
          date: row.date,
        );
      }
      if (row.juniorDutyPersonIds.length > 2) {
        add(
          'TOO_MANY_JUNIORS',
          'composition',
          'En fazla iki junior pozisyonu olabilir.',
          date: row.date,
        );
      }
      if (row.juniorDutyPersonIds.isEmpty &&
          (row.juniorVacancyReason?.trim().isEmpty ?? true)) {
        add(
          'MISSING_VACANCY_REASON',
          'juniorCoverage',
          'Boş junior pozisyonu için gerekçe gerekir.',
          date: row.date,
        );
      }
      final ids = [?senior, ...row.juniorDutyPersonIds];
      if (ids.toSet().length != ids.length) {
        add(
          'DUPLICATE_POSITION',
          'onePositionPerDay',
          'Bir hekim aynı gün birden fazla pozisyonda olamaz.',
          date: row.date,
          person: ids.firstWhere((id) => ids.where((x) => x == id).length > 1),
        );
      }
      for (final id in ids.toSet()) {
        final p = people[id];
        if (p == null || !p.activeAtCreation) {
          add(
            'INVALID_PERSON',
            'personnel',
            'Personel bulunamadı veya ay snapshot’ında aktif değil.',
            date: row.date,
            person: id,
          );
          continue;
        }
        assigned.putIfAbsent(id, () => {}).add(parsed.day);
      }
      final p = people[senior];
      if (p != null) {
        final substituted = p.dutySeniorityGroup == DutySeniorityGroup.junior;
        if (row.seniorRoleIsSubstitution != substituted ||
            row.seniorRoleOriginalGroup != p.dutySeniorityGroup.name) {
          add(
            'INVALID_SUBSTITUTION',
            'roleMetadata',
            'Senior pozisyonu ve geçici atama bilgisi personelin snapshot grubuyla uyuşmuyor.',
            date: row.date,
            person: senior,
          );
        }
      }
      for (final id in row.juniorDutyPersonIds) {
        if (people[id]?.dutySeniorityGroup == DutySeniorityGroup.senior) {
          add(
            'SENIOR_IN_JUNIOR_ROLE',
            'composition',
            'Senior grubundaki kişi junior pozisyonuna atanamaz.',
            date: row.date,
            person: id,
          );
        }
      }
    }
    for (var d = 1; d <= month.days; d++) {
      if (!dates.contains(dateKey(month.date(d)))) {
        add(
          'MISSING_DAY',
          'dailyCoverage',
          'Günün senior pozisyon kaydı eksik.',
          date: dateKey(month.date(d)),
        );
      }
    }
    for (final p in month.people) {
      final c = month.constraints[p.personId] ?? PersonalConstraints();
      final days = assigned[p.personId] ?? <int>{};
      void problem(String code, String rule, String text, [int? d]) => add(
        code,
        rule,
        text,
        person: p.personId,
        date: d == null ? null : dateKey(month.date(d)),
      );
      for (final d in {...c.must, ...c.cannot}) {
        if (d < 1 || d > month.days) {
          problem(
            'INVALID_CONSTRAINT_DATE',
            'personalConstraints',
            'Kişisel kısıt tarihi ay dışında.',
          );
        }
      }
      for (final d in c.must.intersection(c.cannot)) {
        problem(
          'MUST_CANNOT_CONFLICT',
          'personalConstraints',
          'Aynı gün Tutacak ve Tutamaz olamaz.',
          d,
        );
      }
      if (c.must.length > 8) {
        problem(
          'TOO_MANY_MUST',
          'maximumEight',
          'Sekizden fazla zorunlu nöbet var.',
        );
      }
      if (days.length > 8) {
        problem(
          'MAXIMUM_EIGHT',
          'maximumEight',
          'Aylık nöbet sayısı sekizi aşıyor.',
        );
      }
      for (final d in c.must.difference(days)) {
        problem('MISSING_MUST', 'mustDutyDates', 'Zorunlu nöbet atanmamış.', d);
      }
      for (final d in days.intersection(c.cannot)) {
        problem(
          'CANNOT_ASSIGNED',
          'cannotDutyDates',
          'Tutamaz gününe nöbet atanmış.',
          d,
        );
      }
      final combined = {...days, ...c.must}.toList()..sort();
      for (var i = 1; i < combined.length; i++) {
        if (combined[i] - combined[i - 1] < 3) {
          problem(
            'REST_INTERVAL',
            'minimumThreeDays',
            'Nöbet tarihleri arasında en az üç takvim günü olmalıdır.',
            combined[i],
          );
        }
      }
      for (final b in month.boundary[p.personId] ?? <String>[]) {
        final date = DateTime.tryParse(b);
        if (date == null ||
            dateKey(date) != b ||
            !date.isBefore(month.date(1))) {
          problem(
            'INVALID_BOUNDARY',
            'boundary',
            'Önceki ay sınır tarihi geçersiz.',
          );
          continue;
        }
        for (final d in combined) {
          if (month
                  .date(d)
                  .difference(DateTime.utc(date.year, date.month, date.day))
                  .inDays <
              3) {
            problem(
              'BOUNDARY_REST',
              'boundary',
              'Önceki ay nöbetinden sonra dinlenme aralığı sağlanmıyor.',
              d,
            );
          }
        }
      }
    }
    return List.unmodifiable(issues);
  }
}
