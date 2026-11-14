import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';
import 'package:akys/solver_v2/clinical_quality.dart';

import 'schedule_editor_test.dart' as f;

void main() {
  test('inspection never authorizes a structurally valid B preview', () {
    final p = f.fixture(
      doctors: [Doctor(id: 'j', group: DutyGroup.junior)],
      days: [1],
    );
    final s = Solution([0], [1, 0, 1]);
    final inspection = const SolutionValidator().inspectTransferredCandidate(
      p,
      s,
    );
    expect(inspection.structuralConstraintsSatisfied, true);
    expect(inspection.requiresTransitionProof, true);
    expect(inspection.permanentApprovalAllowed, false);
    expect(const SolutionValidator().validate(p, s).isValid, false);
    expect(
      () => const ClinicalQualityEvaluator().evaluate(p, s),
      throwsArgumentError,
    );
    final q = const ClinicalQualityEvaluator().inspectTransferredPreview(p, s);
    expect(q.components.length, 19);
    expect(q.components.first.toString(), '1');
    expect(
      const SolutionValidator()
          .validate(p, Solution([0], [1, 0, 1], clinicalQuality: q))
          .isValid,
      false,
    );
  });
  test('inspection rejects required emptiness, duplicate rest and fixed lock mismatch', () {
    final data = f.fixture(days: [2]).toMessage()
      ..['fixedAssignments'] = {'0': 0};
    final p = Problem.fromMessage(data);
    for (final a in [
      [-1, 1],
      [0, 0],
      [1, 0],
    ]) {
      expect(
        const SolutionValidator()
            .inspectTransferredCandidate(p, Solution(a, [0, 2]))
            .structuralConstraintsSatisfied,
        false,
      );
      expect(
        () => const ClinicalQualityEvaluator().inspectTransferredPreview(
          p,
          Solution(a, [0, 2]),
        ),
        throwsArgumentError,
      );
    }
  });
  test('inspection preserves eligibility, unavailable and previous month constraints', () {
    for (final doctor in [
      f.senior('s', roles: {DutyRole.junior}),
      f.senior('s', cannot: {0}),
      f.senior('s', previous: [DateTime.utc(2026, 10, 31)]),
      f.senior('s', cap: 0),
    ]) {
      final p = f.fixture(doctors: [doctor], days: [1]);
      expect(
        const SolutionValidator()
            .inspectTransferredCandidate(p, Solution([0], [0, 1]))
            .structuralConstraintsSatisfied,
        false,
      );
    }
  });
  test(
    'normal valid solution independently recomputes exact clinical arithmetic',
    () {
      final p = f.fixture(days: [1]);
      final s = Solution([0], [1, 1]);
      final inspection = const SolutionValidator().inspectTransferredCandidate(
        p,
        s,
      );
      expect(inspection.structuralConstraintsSatisfied, true);
      expect(inspection.requiresTransitionProof, false);
      final expected = const ClinicalQualityEvaluator().evaluate(p, s);
      expect(
        const ClinicalQualityEvaluator()
            .inspectTransferredPreview(p, s)
            .compareTo(expected),
        0,
      );
    },
  );
}
