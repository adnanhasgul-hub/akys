import 'package:flutter_test/flutter_test.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';
import 'package:akys/solver_v2/clinical_quality.dart';

Problem input() => Problem(
  startDate: DateTime.utc(2026, 11, 1),
  doctors: [
    Doctor(id: 'j1', group: DutyGroup.junior, maxDuties: 1),
    Doctor(id: 'j2', group: DutyGroup.junior, maxDuties: 2),
  ],
  slotsPerDay: [1],
  slotRoles: [DutyRole.senior],
  dayDifficulties: [const DayDifficulty(weekdayScore: 3)],
);
void main() {
  const validator = SolutionValidator(), evaluator = ClinicalQualityEvaluator();
  test('non-incumbent phase B candidates validated and ranked without authorizing publication', () {
    final s = TransitionSession(input());
    final a = s.run(maxNodes: 100);
    expect(a.pauseReason, PauseReason.stageTransition);
    expect(s.phase, TransitionPhase.substitution);
    expect(s.restrictedVerdict, RestrictedVerdict.provenInfeasible);
    final high = Solution([0], [1, 1, 1]), low = Solution([1], [1, 1, 1]);
    expect(
      validator.validate(s.problem, high, localEvidence: s).isValid,
      isFalse,
    );
    final checked = validator.validatePhaseBCandidate(
      s.problem,
      high,
      session: s,
    );
    expect(checked.isValid, isTrue);
    final fakeSession = TransitionSession(s.problem);
    expect(
      validator
          .validatePhaseBCandidate(s.problem, high, session: fakeSession)
          .isValid,
      isFalse,
    );
    expect(checked.candidateOnly, isTrue);
    expect(checked.permanentApprovalAllowed, isFalse);
    var run = s.run(maxNodes: 1);
    while (run.best == null) {
      run = s.run(maxNodes: 1);
    }
    expect(run.best!.assignments, [0]);
    expect(
      validator.validate(s.problem, run.best!, localEvidence: s).isValid,
      isTrue,
    );
    final x = evaluator.evaluatePhaseBCandidate(s.problem, high, session: s),
        y = evaluator.evaluatePhaseBCandidate(s.problem, low, session: s);
    expect(y.compareTo(x), lessThan(0));
    expect(x.compareTo(y), greaterThan(0));
    expect(
      evaluator.evaluatePhaseBCandidate(s.problem, low, session: s).components,
      y.components,
    );
    expect(
      () => evaluator.evaluate(s.problem, low, localEvidence: s),
      throwsArgumentError,
    );
    expect(
      () => evaluator.evaluatePhaseBCandidate(input(), low, session: s),
      throwsArgumentError,
    );
    expect(
      () => evaluator.evaluatePhaseBCandidate(
        s.problem,
        Solution([1], [1, 0, 0]),
        session: s,
      ),
      throwsArgumentError,
    );
    s.cancel();
    expect(
      () => evaluator.evaluatePhaseBCandidate(s.problem, low, session: s),
      throwsArgumentError,
    );
  });
  test(
    'unproved timeout and forged serialized proof do not authorize candidates',
    () {
      final source = input();
      final s = TransitionSession(source);
      s.run(maxNodes: 100, timeLimit: Duration.zero);
      final fake = source.toMessage()..['proved'] = true;
      final fakeProblem = Problem.fromMessage(fake);
      final candidate = Solution([0], [1, 1, 1]);
      expect(
        validator
            .validatePhaseBCandidate(fakeProblem, candidate, session: s)
            .isValid,
        isFalse,
      );
      expect(
        validator
            .validatePhaseBCandidate(s.problem, candidate, session: s)
            .isValid,
        isFalse,
      );
      expect(
        () =>
            evaluator.evaluatePhaseBCandidate(s.problem, candidate, session: s),
        throwsArgumentError,
      );
    },
  );
  test('exact fraction and typed clinical quality round-trip', () {
    final n = BigInt.parse('100000000000000000000000000000000000001');
    final a = Exact(n, BigInt.from(3)),
        b = Exact(n + BigInt.one, BigInt.from(3));
    expect(a.compareTo(b), lessThan(0));
    final vector = ClinicalQuality([
      a,
      for (var i = 1; i < 19; i++) Exact.integer(i),
    ]);
    final restored = ClinicalQuality.fromMessage(vector.toMessage());
    expect(restored.components, vector.components);
    expect(restored.compareTo(vector), 0);
    expect(
      () => ClinicalQuality.fromMessage({
        'type': 'prototypeQuality',
        'components': [],
      }),
      throwsFormatException,
    );
    expect(
      () => Exact.fromMessage({'numerator': '1', 'denominator': '0'}),
      throwsFormatException,
    );
    final solution = Solution([0], [1, 2]);
    expect(solution.prototypeQuality, isA<PrototypeQuality>());
    expect(
      PrototypeQuality.fromMessage(solution.prototypeQuality.toMessage())
          .values,
      [1, 2],
    );
    expect(
      () => PrototypeQuality.fromMessage(vector.toMessage()),
      throwsFormatException,
    );
    expect(solution.prototypeQuality, isNot(isA<ClinicalQuality>()));
  });
}
