import 'solver.dart';

class ValidationResult {
  ValidationResult(
    List<String> errors,
    List<int>? quality, {
    this.substitutionCount = 0,
    this.candidateOnly = false,
  }) : errors = List.unmodifiable(errors),
       quality = quality == null ? null : List.unmodifiable(quality);
  final List<String> errors;
  final List<int>? quality;
  final int substitutionCount;
  final bool candidateOnly;

  /// Substitution evidence is process-local and never an authorization to persist.
  bool get permanentApprovalAllowed =>
      isValid && substitutionCount == 0 && !candidateOnly;
  bool get isValid => errors.isEmpty;
}

/// Independent of the search implementation and its incremental checks.
class SolutionValidator {
  const SolutionValidator();
  ValidationResult validate(
    Problem problem,
    Solution solution, {
    TransitionSession? localEvidence,
  }) => _validate(problem, solution, localEvidence: localEvidence);

  /// Checks a candidate only in a genuine active phase B; never grants approval.
  ValidationResult validatePhaseBCandidate(
    Problem problem,
    Solution solution, {
    required TransitionSession session,
  }) {
    if (!session.permitsPhaseBCandidate(problem)) {
      return ValidationResult(
        ['Etkin B aşaması veya snapshot doğrulanamadı.'],
        null,
        candidateOnly: true,
      );
    }
    return _validate(
      problem,
      solution,
      localEvidence: session,
      candidateOnly: true,
    );
  }

  ValidationResult _validate(
    Problem problem,
    Solution solution, {
    TransitionSession? localEvidence,
    bool candidateOnly = false,
  }) {
    var substitutions = 0;
    final errors = <String>[], days = problem.slotDays;
    if (solution.assignments.length != days.length) {
      errors.add(
        'Slot sayısı eşleşmiyor: ${solution.assignments.length}/${days.length}.',
      );
    }
    final counts = List<int>.filled(problem.doctors.length, 0);
    final dates = <int, List<int>>{};
    for (var slot = 0; slot < solution.assignments.length; slot++) {
      final id = solution.assignments[slot];
      if (id == unfilledSlot && slot < days.length) {
        if (problem.slotRequirements[slot] == SlotRequirement.required) {
          errors.add('Zorunlu pozisyon boş: slot $slot.');
        }
        continue;
      }
      if (id < 0 || id >= problem.doctors.length) {
        errors.add('Geçersiz hekim indeksi: $id (slot $slot).');
        continue;
      }
      if (slot >= days.length) continue;
      final day = days[slot], doctor = problem.doctors[id];
      final role = problem.slotRoles?[slot];
      if (role != null && !doctor.eligibleRoles.contains(role)) {
        errors.add('${doctor.id}: pozisyon için uygun değil.');
      }
      if (role == DutyRole.senior && doctor.group != DutyGroup.senior) {
        substitutions++;
        if (localEvidence == null ||
            (candidateOnly
                ? !localEvidence.permitsPhaseBCandidate(problem)
                : !localEvidence.verifiesLocalTransition(problem, solution))) {
          errors.add('${doctor.id}: kanıtlanmamış kıdemsiz geçişi yasak.');
        }
      }
      if (role == DutyRole.junior && doctor.group != DutyGroup.junior) {
        errors.add('${doctor.id}: kıdemsiz pozisyonu için grup uygun değil.');
      }
      if (problem.startDate != null &&
          doctor.previousDuties.any(
            (x) =>
                problem.startDate!
                    .add(Duration(days: day))
                    .difference(x)
                    .inDays <
                3,
          )) {
        errors.add('${doctor.id}: önceki ay dinlenme aralığı ihlali.');
      }
      if (doctor.unavailable.contains(day)) {
        errors.add('${doctor.id}: $day günü uygun değil.');
      }
      counts[id]++;
      if (counts[id] > doctor.maxDuties) {
        errors.add('${doctor.id}: nöbet üst sınırı aşıldı.');
      }
      final previous = dates.putIfAbsent(id, () => []);
      if (previous.any((d) => (day - d).abs() < 3)) {
        errors.add('${doctor.id}: en az üç gün aralık ihlali.');
      }
      previous.add(day);
    }
    for (var i = 0; i < problem.doctors.length; i++) {
      for (final day in problem.doctors[i].must) {
        if (!(dates[i] ?? []).contains(day)) {
          errors.add('${problem.doctors[i].id}: zorunlu gün $day eksik.');
        }
      }
    }
    if (errors.isNotEmpty) {
      return ValidationResult(
        errors,
        null,
        substitutionCount: substitutions,
        candidateOnly: candidateOnly,
      );
    }
    final sorted = [...counts]..sort();
    final quality = [
      if (substitutions > 0) substitutions,
      sorted.isEmpty ? 0 : sorted.last - sorted.first,
      counts.fold<int>(0, (a, b) => a + b * b),
    ];
    if (solution.quality.length != quality.length ||
        List.generate(
          quality.length,
          (i) => solution.quality[i] == quality[i],
        ).any((same) => !same)) {
      errors.add('Bildirilen kalite vektörü hesaplanan değerle eşleşmiyor.');
    }
    return ValidationResult(
      errors,
      quality,
      substitutionCount: substitutions,
      candidateOnly: candidateOnly,
    );
  }
}
