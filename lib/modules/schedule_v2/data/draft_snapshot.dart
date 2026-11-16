import 'dart:convert';

import '../../../solver_v2/solver.dart';
import '../../../solver_v2/clinical_quality.dart';
import '../../../solver_v2/solution_validator.dart';
import '../../../solver_v2/editing/schedule_editor.dart';

/// Storage carries data, never transferable authorization or optimum proof.
class DraftSnapshot {
  DraftSnapshot(
    Problem source,
    Map<String, String> names,
    List<int> assignments,
    Map<int, int> locks,
  ) : problem = Problem.fromMessage(source.toMessage()),
      names = Map.unmodifiable(names),
      assignments = List.unmodifiable(assignments),
      locks = Map.unmodifiable(locks) {
    final start = problem.startDate;
    if (start == null ||
        start.day != 1 ||
        !start.isUtc ||
        problem.slotsPerDay.length !=
            DateTime.utc(start.year, start.month + 1, 0).day) {
      throw const FormatException('Tam UTC takvim ayı gerekli.');
    }
    if (assignments.length != problem.slotDays.length ||
        assignments.any((d) => d < -1 || d >= problem.doctors.length) ||
        names.keys.any((id) => !problem.doctors.any((d) => d.id == id)) ||
        names.values.any((s) => s.length > 200) ||
        locks.entries.any(
          (e) =>
              e.key < 0 ||
              e.key >= assignments.length ||
              e.value < 0 ||
              e.value >= problem.doctors.length ||
              assignments[e.key] != e.value,
        )) {
      throw const FormatException(
        'Hekim, pozisyon veya kilit verisi geçersiz.',
      );
    }
    // Validates clinical snapshot completeness; incomplete and invalid drafts remain drafts.
    ScheduleEditor(problem, assignments: assignments);
  }
  final Problem problem;
  final Map<String, String> names;
  final List<int> assignments;
  final Map<int, int> locks;
  bool get optimalityProven => false;
  bool get approvalAllowed => false;
  EditedSchedule get checked =>
      ScheduleEditor(problem, assignments: assignments).current;
  ClinicalQuality? get quality {
    final inspection = const SolutionValidator().inspectTransferredCandidate(
      problem,
      Solution(assignments, []),
    );
    if (inspection.prototypeQuality == null) return null;
    return const ClinicalQualityEvaluator().inspectTransferredPreview(
      problem,
      Solution(assignments, inspection.prototypeQuality!),
    );
  }

  bool get hasTransition =>
      [for (var s = 0; s < assignments.length; s++) s].any(
        (s) =>
            assignments[s] >= 0 &&
            problem.slotRoles![s] == DutyRole.senior &&
            problem.doctors[assignments[s]].group == DutyGroup.junior,
      );
  final List<String> _warnings = [];
  List<String> get warnings => List.unmodifiable(_warnings);
  List<String> get slotIds {
    final ordinal = <int, int>{};
    return [
      for (var s = 0; s < problem.slotDays.length; s++)
        '${problem.dateForDay(problem.slotDays[s]).toIso8601String().split('T').first}/${problem.slotRoles![s].name}/${ordinal.update(problem.slotDays[s], (n) => n + 1, ifAbsent: () => 0)}',
    ];
  }

  String encode() => jsonEncode({
    'schema': 1,
    'problem': problem.toMessage(),
    'names': names,
    'assignments': assignments,
    'locks': {for (final e in locks.entries) '${e.key}': e.value},
    'slotIds': slotIds,
    'quality': quality?.toMessage(),
  });
  static DraftSnapshot decode(String payload) {
    final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    if (data.length != 7 ||
        !data.keys.every(
          [
            'schema',
            'problem',
            'names',
            'assignments',
            'locks',
            'slotIds',
            'quality',
          ].contains,
        ) ||
        data['schema'] != 1) {
      throw const FormatException('Bilinmeyen taslak şeması veya kanıt alanı.');
    }
    final result = DraftSnapshot(
      Problem.fromMessage(Map<String, dynamic>.from(data['problem'] as Map)),
      Map<String, String>.from(data['names'] as Map),
      List<int>.from(data['assignments'] as List),
      (data['locks'] as Map).map(
        (k, v) => MapEntry(int.parse(k as String), v as int),
      ),
    );
    if (jsonEncode(data['slotIds']) != jsonEncode(result.slotIds)) {
      throw const FormatException('Pozisyon kimlikleri uyuşmuyor.');
    }
    // Stored quality is advisory only. Recompute through the independent validator/editor.
    if (data['quality'] != null) {
      ClinicalQuality.fromMessage(
        Map<String, dynamic>.from(data['quality'] as Map),
      );
    }
    if (jsonEncode(data['quality']) !=
        jsonEncode(result.quality?.toMessage())) {
      result._warnings.add(
        'Kaydedilmiş kalite güvenilir sayılmadı; bağımsız hesap yeniden yapıldı.',
      );
    }
    return result;
  }
}
