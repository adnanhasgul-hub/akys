import 'dart:async';

import '../solver.dart';
import '../solution_validator.dart';

/// Process-local engine shared by VM isolate and DedicatedWorker transports.
/// Commands are serviced between finite slices, never during one solver call.
final class WorkerEngine {
  WorkerEngine(this.output);
  final void Function(Map<String, Object?>) output;
  TransitionSession? session;
  final watch = Stopwatch();
  Timer? timer;
  int id = 0,
      sequence = 0,
      budget = 0,
      slice = 5000,
      interval = 100000,
      lastProgress = 0;
  int? first;
  Solution? incumbent;
  bool terminal = false, timedOut = false;
  TransitionPhase phase = TransitionPhase.restricted;
  void command(Map<String, Object?> c) {
    switch (c['command']) {
      case 'start':
        if (session != null) throw StateError('Already started');
        id = c['runId'] as int;
        final o = Map<String, Object?>.from(c['options'] as Map);
        budget = o['budget'] as int;
        slice = o['slice'] as int;
        interval = o['progress'] as int;
        session = TransitionSession(
          Problem.fromMessage(Map<String, dynamic>.from(c['problem'] as Map)),
          candidateOrdering: o['ordering'] as bool,
          earlyDeadEnds: o['deadends'] as bool,
          experimentalTwoPhase: o['twoPhase'] as bool,
          clinicalBounds: o['bounds'] as bool,
          forwardChecking: o['forward'] as bool,
        );
        watch.start();
        emit('running');
        schedule();
      case 'extend':
      case 'extendDeadline':
        if (terminal) return;
        final extra = c['extra'] as int;
        if (extra <= 0) throw ArgumentError('Positive extension required');
        budget += extra;
        if (timedOut) {
          timedOut = false;
          watch.start();
          emit(incumbent == null ? 'running' : 'feasible');
          schedule();
        }
      case 'cancel':
        if (terminal) return;
        session?.cancel();
        terminal = true;
        watch.stop();
        timer?.cancel();
        emit('cancelled');
      case 'dispose':
        terminal = true;
        session?.cancel();
        watch.stop();
        timer?.cancel();
      default:
        throw ArgumentError('Unknown command');
    }
  }

  void schedule() {
    if (!terminal && !timedOut) timer = Timer(Duration.zero, step);
  }

  void step() {
    if (terminal || timedOut) return;
    try {
      final sliceWatch = Stopwatch()..start();
      while (sliceWatch.elapsedMicroseconds < slice) {
        final remaining = budget - watch.elapsedMicroseconds;
        if (remaining <= 0) {
          timedOut = true;
          watch.stop();
          emit('timedOut');
          return;
        }
        final room = slice - sliceWatch.elapsedMicroseconds;
        if (room <= 0) break;
        final r = session!.run(
          maxNodes: 1,
          timeLimit: Duration(
            microseconds: remaining < room ? remaining : room,
          ),
        );
        if (session!.phase != TransitionPhase.done && session!.phase != phase) {
          phase = session!.phase;
          emit(incumbent == null ? 'running' : 'feasible');
        }
        final best = r.best;
        if (best != null && !identical(best, incumbent)) {
          final checked = const SolutionValidator().validate(
            session!.problem,
            best,
            localEvidence: session,
          );
          if (!checked.isValid) {
            throw StateError('Invalid incumbent: ${checked.errors}');
          }
          if (incumbent != null &&
              session!.problem.compareClinicalCandidates(best, incumbent!) >=
                  0) {
            throw StateError('Non-improving incumbent');
          }
          incumbent = best;
          first ??= watch.elapsedMicroseconds;
          emit('feasible');
        }
        if (r.status == SearchStatus.optimal ||
            r.status == SearchStatus.infeasible) {
          terminal = true;
          watch.stop();
          emit(r.status == SearchStatus.optimal ? 'optimal' : 'infeasible');
          return;
        }
        if (r.status == SearchStatus.cancelled) {
          terminal = true;
          watch.stop();
          emit('cancelled');
          return;
        }
      }
      if (watch.elapsedMicroseconds - lastProgress >= interval) {
        lastProgress = watch.elapsedMicroseconds;
        emit(incumbent == null ? 'running' : 'feasible');
      }
      schedule();
    } catch (e) {
      fail(e);
    }
  }

  void fail(Object error) {
    if (terminal) return;
    terminal = true;
    watch.stop();
    timer?.cancel();
    emit('failed', error: error.toString());
  }

  void emit(String state, {String? error}) {
    final s = session;
    output({
      'runId': id,
      'sentAtMicros': DateTime.now().microsecondsSinceEpoch,
      'sequence': sequence++,
      'state': state,
      'elapsed': watch.elapsedMicroseconds,
      'nodes': s?.totalVisitedNodes ?? 0,
      'pruned': s == null
          ? 0
          : s.mandatoryPruned +
                s.feasibilityPruned +
                s.clinicalPruned +
                s.forwardPruned,
      'phase': phase.name,
      'verdict': (s?.restrictedVerdict ?? RestrictedVerdict.pending).name,
      'first': first,
      'best': incumbent?.toMessage(),
      'error': error,
    });
  }
}
