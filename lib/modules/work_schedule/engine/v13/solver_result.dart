import '../../domain/duty_positions.dart';

enum SolverStatus { feasible, infeasible, searchLimitReached, error }

enum VacancyProof { provenUnavoidable, notProven }

class SolverCancellation {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class SolverResult {
  SolverResult({
    required this.status,
    required this.positions,
    required this.visitedStates,
    required this.elapsedMilliseconds,
    this.optimalityProven = false,
    this.infeasibilityProven = false,
    this.realSeniorInfeasibilityProven = false,
    this.cancelled = false,
    this.message = '',
    this.vacancies = const {},
  });
  final SolverStatus status;
  String get statusCode => switch (status) {
    SolverStatus.feasible => 'FEASIBLE',
    SolverStatus.infeasible => 'INFEASIBLE',
    SolverStatus.searchLimitReached => 'SEARCH_LIMIT_REACHED',
    SolverStatus.error => 'ERROR',
  };
  final List<DutyPositions> positions;
  final int visitedStates, elapsedMilliseconds;
  final bool optimalityProven,
      infeasibilityProven,
      realSeniorInfeasibilityProven,
      cancelled;
  final String message;
  final Map<String, VacancyProof> vacancies;
  bool get hasValidIncumbent => positions.isNotEmpty;
  int get seniorSubstitutionCount =>
      positions.where((p) => p.seniorRoleIsSubstitution).length;
  int get juniorVacancyCount =>
      positions.where((p) => p.juniorDutyPersonIds.isEmpty).length;
}
