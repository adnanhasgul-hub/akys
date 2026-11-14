import 'dart:async';
import 'dart:isolate';

import '../solver.dart';
import '../solution_validator.dart';
import 'transport.dart';

const bool workerSupported = true;
const String workerPlatform =
    'Dart VM isolate (Android/VM; device validation separate)';

Future<WorkerConnection> createWorker() async {
  final channel = _Connection();
  channel.ready.future
      .ignore(); // Startup failure may arrive before spawn awaits ready.
  try {
    channel.isolate = await Isolate.spawn(
      _entry,
      channel.data.sendPort,
      onError: channel.errors.sendPort,
      onExit: channel.exits.sendPort,
      errorsAreFatal: true,
    );
    channel.commands = await channel.ready.future.timeout(
      const Duration(seconds: 10),
    );
    return channel;
  } catch (_) {
    await channel.terminate();
    rethrow;
  }
}

final class _Connection implements WorkerConnection {
  _Connection() {
    data.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is Map && !closed) {
        stream.add(Map<String, Object?>.from(message));
      }
    });
    errors.listen((error) {
      if (!closed) {
        final failure = StateError('Isolate error: $error');
        if (!ready.isCompleted) {
          ready.completeError(failure);
        } else {
          stream.addError(failure);
        }
      }
    });
    exits.listen((_) {
      if (!closed) {
        final failure = StateError('Unexpected isolate exit');
        if (!ready.isCompleted) {
          ready.completeError(failure);
        } else {
          stream.addError(failure);
        }
      }
    });
  }
  final data = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
  final ready = Completer<SendPort>();
  final stream = StreamController<Map<String, Object?>>();
  Isolate? isolate;
  SendPort? commands;
  bool closed = false;
  @override
  Stream<Map<String, Object?>> get events => stream.stream;
  @override
  void send(Map<String, Object?> command) {
    if (!closed) commands!.send(command);
  }

  @override
  Future<void> terminate() async {
    if (closed) return;
    closed = true;
    isolate?.kill(priority: Isolate.immediate);
    data.close();
    errors.close();
    exits.close();
    // No wait for an unlistened stream during cancelled startup.
    unawaited(stream.close());
  }
}

void _entry(SendPort output) {
  final control = ReceivePort();
  final engine = _Engine(output);
  control.listen((message) {
    try {
      engine.command(Map<String, Object?>.from(message as Map));
    } catch (e) {
      engine.fail(e);
    }
  });
  output.send(control.sendPort);
}

final class _Engine {
  _Engine(this.output);
  final SendPort output;
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
              best.clinicalQuality!.compareTo(incumbent!.clinicalQuality!) >=
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
    output.send({
      'runId': id,
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
