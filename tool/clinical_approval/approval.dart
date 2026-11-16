// Server-only clinical policy. No client-provided proof is accepted.
import 'package:akys/modules/schedule_v2/data/draft_snapshot.dart';
import 'package:akys/solver_v2/solver.dart';
import 'package:akys/solver_v2/solution_validator.dart';

class ApprovalRejected implements Exception {
  const ApprovalRejected(this.code);
  final String code;
  @override
  String toString() => code;
}

DraftSnapshot validateForApproval(String storedPayload) {
  final DraftSnapshot snapshot;
  try {
    snapshot = DraftSnapshot.decode(storedPayload);
  } catch (_) {
    throw const ApprovalRejected('CORRUPT_SNAPSHOT');
  }
  if (snapshot.hasTransition) throw const ApprovalRejected('B_APPROVAL_CLOSED');
  final inspection = const SolutionValidator().inspectTransferredCandidate(
    snapshot.problem,
    Solution(snapshot.assignments, []),
  );
  if (inspection.prototypeQuality == null) {
    throw const ApprovalRejected('HARD_CONSTRAINT');
  }
  final validation = const SolutionValidator().validate(
    snapshot.problem,
    Solution(snapshot.assignments, inspection.prototypeQuality!),
  );
  if (!validation.permanentApprovalAllowed) {
    throw const ApprovalRejected('NOT_AUTHORIZED');
  }
  return snapshot;
  // DraftSnapshot verifies every stored lock equals its assignment. Zero junior
  // substitutions plus complete independent validation establishes A feasibility,
  // never A optimality. Old optimum/proof fields are rejected by the decoder.
}
