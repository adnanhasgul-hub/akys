import 'solver.dart';

class ValidationResult {
  ValidationResult(List<String> errors, List<int>? quality)
    : errors = List.unmodifiable(errors),
      quality = quality == null ? null : List.unmodifiable(quality);
  final List<String> errors;
  final List<int>? quality;
  bool get isValid => errors.isEmpty;
}

/// Independent of the search implementation and its incremental checks.
class SolutionValidator {
  const SolutionValidator();
  ValidationResult validate(Problem problem, Solution solution) {
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
        errors.add('${doctor.id}: kanıtlanmamış kıdemsiz geçişi yasak.');
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
    if (errors.isNotEmpty) return ValidationResult(errors, null);
    final sorted = [...counts]..sort();
    final quality = [
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
    return ValidationResult(errors, quality);
  }
}
