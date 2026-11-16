import 'dart:async';

import '../solver.dart';
import '../solution_validator.dart';
import '../clinical_quality.dart';
import 'transport.dart';
import 'web_stub.dart'
    if (dart.library.js_interop) 'worker_web.dart'
    as web_backend;
import 'worker_stub.dart' if (dart.library.io) 'worker_io.dart' as backend;

enum OptimizationState {
  idle,
  preparing,
  running,
  feasible,
  optimal,
  infeasible,
  timedOut,
  cancelled,
  failed,
}

enum OptimizationProof {
  none,
  feasibleUnproven,
  optimalProven,
  infeasibleProven,
}

final class OptimizationOptions {
  const OptimizationOptions({
    this.budget = const Duration(seconds: 30),
    this.slice = const Duration(milliseconds: 5),
    this.progressInterval = const Duration(milliseconds: 100),
    this.candidateOrdering = false,
    this.earlyDeadEnds = false,
    this.experimentalTwoPhase = false,
    this.clinicalBounds = false,
    this.forwardChecking = false,
  });
  final Duration budget, slice, progressInterval;
  final bool candidateOrdering,
      earlyDeadEnds,
      experimentalTwoPhase,
      clinicalBounds,
      forwardChecking;
  Map<String, Object?> toMessage() {
    if (budget.isNegative ||
        slice.inMicroseconds <= 0 ||
        slice > const Duration(milliseconds: 50) ||
        progressInterval.inMicroseconds <= 0) {
      throw ArgumentError('Invalid runtime budget/interval');
    }
    return {
      'budget': budget.inMicroseconds,
      'slice': slice.inMicroseconds,
      'progress': progressInterval.inMicroseconds,
      'ordering': candidateOrdering,
      'deadends': earlyDeadEnds,
      'twoPhase': experimentalTwoPhase,
      'bounds': clinicalBounds,
      'forward': forwardChecking,
    };
  }
}

/// Immutable observation, NOT a portable A/B certificate or persistence approval.
final class OptimizationSnapshot {
  const OptimizationSnapshot({
    required this.runId,
    required this.sequence,
    required this.state,
    this.elapsed = Duration.zero,
    this.nodes = 0,
    this.pruned = 0,
    this.phase = TransitionPhase.restricted,
    this.restrictedVerdict = RestrictedVerdict.pending,
    this.firstFeasible,
    this.best,
    this.error,
    this.forcedTermination = false,
    this.transportDelay,
  });
  final int runId, sequence, nodes, pruned;
  final OptimizationState state;
  final Duration elapsed;

  /// Same-machine wall-clock delivery delay; excludes host validation time.
  final Duration? transportDelay;
  final TransitionPhase phase;
  final RestrictedVerdict restrictedVerdict;
  final Duration? firstFeasible;
  final Solution? best;
  final String? error;
  final bool forcedTermination;
  bool get permanentApprovalAllowed => false;
  bool get canExtend => [
    OptimizationState.running,
    OptimizationState.feasible,
    OptimizationState.timedOut,
  ].contains(state);
  OptimizationProof get proof => switch (state) {
    OptimizationState.optimal => OptimizationProof.optimalProven,
    OptimizationState.infeasible => OptimizationProof.infeasibleProven,
    _ =>
      best == null
          ? OptimizationProof.none
          : OptimizationProof.feasibleUnproven,
  };
}

/// One private worker channel per run. No UI, Firebase, or solver-default changes.
final class OptimizationController {
  OptimizationController() : _spawn = backend.createWorker;

  /// Explicit opt-in; URL is trusted application code, never user-provided input.
  OptimizationController.web({
    required Uri workerUri,
    Duration startupTimeout = const Duration(seconds: 10),
    Duration heartbeatInterval = const Duration(seconds: 1),
    Duration responseTimeout = const Duration(seconds: 5),
  }) : _spawn = (() => web_backend.createWebWorker(
         workerUri,
         startupTimeout,
         heartbeatInterval,
         responseTimeout,
       ));
  final Future<WorkerConnection> Function() _spawn;
  static bool get webSupported => web_backend.webWorkerSupported;
  static bool get supported => backend.workerSupported;
  static String get platform => backend.workerPlatform;
  final _events = StreamController<OptimizationSnapshot>.broadcast();
  OptimizationSnapshot _value = const OptimizationSnapshot(
    runId: 0,
    sequence: 0,
    state: OptimizationState.idle,
  );
  OptimizationSnapshot get value => _value;
  Stream<OptimizationSnapshot> get events => _events.stream;
  WorkerConnection? _worker;
  Problem? _problem;
  final _pendingSpawns = <Future<WorkerConnection>>{};
  StreamSubscription<Map<String, Object?>>? _subscription;
  int _generation = 0, _workerSequence = -1;
  bool _disposed = false;
  Timer? _cancelTimer;
  Completer<void>? _cancelled;
  bool get hasWorker => _worker != null;

  Future<void> start(
    Problem problem, {
    OptimizationOptions options = const OptimizationOptions(),
  }) async {
    if (_disposed) throw StateError('Controller disposed');
    final id = ++_generation;
    final cleanup = _release();
    _workerSequence = -1;
    _value = OptimizationSnapshot(
      runId: id,
      sequence: 0,
      state: OptimizationState.preparing,
    );
    _events.add(_value);
    await cleanup;
    if (id != _generation || _disposed || _terminal) {
      return;
    }
    try {
      final snapshot = Problem.fromMessage(problem.toMessage());
      _problem = snapshot;
      final input = snapshot.toMessage();
      final settings = options.toMessage();
      final pending = _spawn();
      _pendingSpawns.add(pending);
      late final WorkerConnection worker;
      try {
        worker = await pending;
      } finally {
        _pendingSpawns.remove(pending);
      }
      if (id != _generation || _disposed || _terminal) {
        await worker.terminate();
        return;
      }
      _worker = worker;
      _subscription = worker.events.listen(
        (event) {
          if (id != _generation || _disposed) return;
          try {
            _accept(id, event);
          } catch (e) {
            _local(
              OptimizationState.failed,
              error: 'Worker protokol hatası: $e',
            );
            unawaited(_release());
          }
        },
        onError: (Object error) {
          if (id != _generation || _disposed || _terminal) return;
          _local(
            OptimizationState.failed,
            error: 'Arka plan hesaplaması sonlandı: $error',
          );
          unawaited(_release());
        },
      );
      worker.send({
        'command': 'start',
        'runId': id,
        'problem': input,
        'options': settings,
      });
    } catch (e) {
      if (id == _generation && !_disposed && !_terminal) {
        _local(OptimizationState.failed, error: e.toString());
        await _release();
      }
    }
  }

  bool get _terminal => [
    OptimizationState.optimal,
    OptimizationState.infeasible,
    OptimizationState.cancelled,
    OptimizationState.failed,
  ].contains(_value.state);
  static bool canTransition(OptimizationState from, OptimizationState to) =>
      switch (from) {
        OptimizationState.idle => to == OptimizationState.preparing,
        OptimizationState.preparing => {
          OptimizationState.running,
          OptimizationState.failed,
          OptimizationState.cancelled,
        }.contains(to),
        OptimizationState.running => {
          OptimizationState.running,
          OptimizationState.feasible,
          OptimizationState.optimal,
          OptimizationState.infeasible,
          OptimizationState.timedOut,
          OptimizationState.cancelled,
          OptimizationState.failed,
        }.contains(to),
        OptimizationState.feasible => {
          OptimizationState.feasible,
          OptimizationState.optimal,
          OptimizationState.timedOut,
          OptimizationState.cancelled,
          OptimizationState.failed,
        }.contains(to),
        OptimizationState.timedOut => {
          OptimizationState.running,
          OptimizationState.feasible,
          OptimizationState.cancelled,
          OptimizationState.failed,
        }.contains(to),
        _ => false,
      };
  void _accept(int id, Map<String, Object?> event) {
    if (_terminal || event['runId'] != id) return;
    final sentAt = event['sentAtMicros'] as int?;
    final delay = sentAt == null
        ? null
        : Duration(
            microseconds: (DateTime.now().microsecondsSinceEpoch - sentAt)
                .clamp(0, 1 << 52),
          );
    final seq = event['sequence'] as int;
    if (seq <= _workerSequence) return;
    _workerSequence = seq;
    final state = OptimizationState.values.byName(event['state'] as String);
    if (!canTransition(value.state, state)) {
      throw StateError('Invalid state transition');
    }
    if ((event['nodes'] as int) < value.nodes ||
        (event['elapsed'] as int) < value.elapsed.inMicroseconds) {
      throw StateError('Progress regressed');
    }
    var best = _value.best;
    if (event['best'] != null) {
      final incoming = Solution.fromMessage(
        Map<String, dynamic>.from(event['best'] as Map),
      );
      if (incoming.clinicalQuality == null) {
        throw StateError('Missing clinical quality');
      }
      // Independent main-layer check, not trust in the worker's 'valid' boolean.
      final inspection = const SolutionValidator().inspectTransferredCandidate(
        _problem!,
        incoming,
      );
      if (!inspection.structuralConstraintsSatisfied) {
        throw StateError('Invalid transferred incumbent: ${inspection.errors}');
      }
      final expected = const ClinicalQualityEvaluator()
          .inspectTransferredPreview(_problem!, incoming);
      if (expected.compareTo(incoming.clinicalQuality!) != 0) {
        throw StateError('Transferred clinical quality mismatch');
      }
      // B's proof remains in the worker's genuine session. The private trusted
      // application worker channel supplies a preview observation, NOT a portable
      // certificate. Local validate() still rejects B without local evidence.

      if (incoming.clinicalQuality!.components.first.toString() != '0' &&
          (event['verdict'] != 'provenInfeasible' ||
              event['phase'] != 'substitution')) {
        throw StateError('Missing trusted B-stage observation');
      }
      if (best == null ||
          _problem!.compareClinicalCandidates(incoming, best) < 0) {
        best = incoming;
      } else if (_problem!.compareClinicalCandidates(incoming, best) > 0) {
        throw StateError('Worse incumbent from worker');
      }
    }
    if ((state == OptimizationState.optimal ||
            state == OptimizationState.feasible) &&
        best == null) {
      throw StateError('Missing incumbent');
    }
    if (state == OptimizationState.infeasible && best != null) {
      throw StateError('Contradictory proof');
    }
    _value = OptimizationSnapshot(
      runId: id,
      sequence: _value.sequence + 1,
      state: state,
      elapsed: Duration(microseconds: event['elapsed'] as int),
      transportDelay: delay,
      nodes: event['nodes'] as int,
      pruned: event['pruned'] as int,
      phase: TransitionPhase.values.byName(event['phase'] as String),
      restrictedVerdict: RestrictedVerdict.values.byName(
        event['verdict'] as String,
      ),
      firstFeasible: event['first'] == null
          ? null
          : Duration(microseconds: event['first'] as int),
      best: best,
      error: event['error'] as String?,
    );
    _events.add(_value);
    if (_terminal) unawaited(_release());
  }

  void extend(Duration extra) {
    if (_disposed || !value.canExtend || _worker == null) {
      throw StateError('Run cannot be extended');
    }
    if (extra.inMicroseconds <= 0) {
      throw ArgumentError('Positive extension required');
    }
    _worker!.send({'command': 'extend', 'extra': extra.inMicroseconds});
  }

  Future<void> cancel({
    Duration grace = const Duration(milliseconds: 500),
  }) async {
    if (grace.isNegative) throw ArgumentError('Negative grace');
    if (_terminal || value.state == OptimizationState.idle) return;
    if (_worker == null) {
      _local(OptimizationState.cancelled);
      await _release();
      return;
    }
    if (grace == Duration.zero) {
      _local(OptimizationState.cancelled, forced: true);
      await _release();
      return;
    }
    final completion = _cancelled ??= Completer<void>();
    _worker!.send({'command': 'cancel'});
    _cancelTimer ??= Timer(grace, () {
      if (!_terminal) {
        _local(OptimizationState.cancelled, forced: true);
        unawaited(_release());
      }
    });
    await completion.future;
  }

  /// Host-detected fatal failure (e.g. app execution service unavailable).
  /// Retains the last worker-validated incumbent; does not create proof.
  Future<void> abort(String reason) async {
    if (_disposed || _terminal || value.state == OptimizationState.idle) return;
    _local(OptimizationState.failed, error: reason);
    await _release();
  }

  void _local(OptimizationState state, {String? error, bool forced = false}) {
    _value = OptimizationSnapshot(
      runId: value.runId,
      sequence: value.sequence + 1,
      state: state,
      elapsed: value.elapsed,
      transportDelay: value.transportDelay,
      nodes: value.nodes,
      pruned: value.pruned,
      phase: value.phase,
      restrictedVerdict: value.restrictedVerdict,
      firstFeasible: value.firstFeasible,
      best: value.best,
      error: error,
      forcedTermination: forced,
    );
    if (!_disposed) _events.add(_value);
  }

  Future<void> _release() async {
    final pendingSpawns = [..._pendingSpawns];
    final completion = _cancelled;
    _cancelled = null;
    _cancelTimer?.cancel();
    _cancelTimer = null;
    final subscription = _subscription;
    _subscription = null;
    final worker = _worker;
    _worker = null;
    await subscription?.cancel();
    await worker?.terminate();
    for (final pending in pendingSpawns) {
      try {
        await (await pending).terminate();
      } catch (_) {}
    }
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await cancel();
    _disposed = true;
    ++_generation;
    await _release();
    for (final pending in [..._pendingSpawns]) {
      try {
        await (await pending).terminate();
      } catch (_) {}
    }
    await _events.close();
  }
}
