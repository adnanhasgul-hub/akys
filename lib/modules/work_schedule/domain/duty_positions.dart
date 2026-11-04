/// Explicit V1.3 positions. This model never infers roles from legacy personIds.
class DutyPositions {
  DutyPositions({
    required this.date,
    required this.seniorDutyPersonId,
    required List<String> juniorDutyPersonIds,
    required this.seniorRoleIsSubstitution,
    required this.seniorRoleOriginalGroup,
    this.juniorVacancyReason,
  }) : juniorDutyPersonIds = List.unmodifiable(juniorDutyPersonIds);
  final String date;
  final String? seniorDutyPersonId;
  final List<String> juniorDutyPersonIds;
  final bool seniorRoleIsSubstitution;
  final String? seniorRoleOriginalGroup;
  final String? juniorVacancyReason;
  Map<String, dynamic> toJson() => {
    'date': date,
    'seniorDutyPersonId': seniorDutyPersonId,
    'juniorDutyPersonIds': juniorDutyPersonIds,
    'seniorRoleIsSubstitution': seniorRoleIsSubstitution,
    'seniorRoleOriginalGroup': seniorRoleOriginalGroup,
    'juniorVacancyReason': juniorVacancyReason,
  };
  factory DutyPositions.fromJson(Map<String, dynamic> j) => DutyPositions(
    date: j['date'] as String,
    seniorDutyPersonId: j['seniorDutyPersonId'] as String?,
    juniorDutyPersonIds: List<String>.from(j['juniorDutyPersonIds'] as List),
    seniorRoleIsSubstitution: j['seniorRoleIsSubstitution'] as bool,
    seniorRoleOriginalGroup: j['seniorRoleOriginalGroup'] as String?,
    juniorVacancyReason: j['juniorVacancyReason'] as String?,
  );
}

class ConstraintIssue {
  const ConstraintIssue(
    this.code,
    this.rule,
    this.message, {
    this.date,
    this.personId,
    this.warning = false,
  });
  final String code, rule, message;
  final String? date, personId;
  final bool warning;
}

/// Read-only adapter: no serialization of the source month and no migration.
class PositionReadResult {
  PositionReadResult(this.positions, this.issues);
  final List<DutyPositions> positions;
  final List<ConstraintIssue> issues;
  factory PositionReadResult.fromMonthJson(Map<String, dynamic> json) {
    final positions = <DutyPositions>[];
    final issues = <ConstraintIssue>[];
    final raw = json['dutyPositions'];
    if (raw == null) {
      issues.add(
        const ConstraintIssue(
          'LEGACY_POSITIONS_UNKNOWN',
          'positionSchema',
          'Eski kayıtta nöbet pozisyonları belirtilmemiş. Açık doğrulama gerekir.',
          warning: true,
        ),
      );
    } else if (raw is! List) {
      issues.add(
        const ConstraintIssue(
          'INVALID_POSITION_DATA',
          'positionSchema',
          'Pozisyon verisi liste olmalıdır.',
        ),
      );
    } else {
      for (final row in raw) {
        try {
          positions.add(
            DutyPositions.fromJson(Map<String, dynamic>.from(row as Map)),
          );
        } catch (_) {
          issues.add(
            const ConstraintIssue(
              'INVALID_POSITION_DATA',
              'positionSchema',
              'Nöbet pozisyon kaydı okunamadı.',
            ),
          );
        }
      }
    }
    return PositionReadResult(
      List.unmodifiable(positions),
      List.unmodifiable(issues),
    );
  }
}
