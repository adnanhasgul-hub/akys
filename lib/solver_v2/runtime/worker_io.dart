import 'dart:async';
import 'dart:isolate';

import 'worker_engine.dart';
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
  final engine = WorkerEngine(output.send);
  control.listen((message) {
    try {
      engine.command(Map<String, Object?>.from(message as Map));
    } catch (e) {
      engine.fail(e);
    }
  });
  output.send(control.sendPort);
}
