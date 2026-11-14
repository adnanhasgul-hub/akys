import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'transport.dart';

const webWorkerSupported = true;

Future<WorkerConnection> createWebWorker(
  Uri uri,
  Duration startupTimeout,
  Duration heartbeatInterval,
  Duration responseTimeout,
) async {
  final resolved = Uri.base.resolveUri(uri);
  if (resolved.origin != Uri.base.origin ||
      !['http', 'https'].contains(resolved.scheme)) {
    throw ArgumentError('Worker URL must be same-origin HTTP(S)');
  }
  if (startupTimeout <= Duration.zero ||
      heartbeatInterval <= Duration.zero ||
      responseTimeout <= heartbeatInterval) {
    throw ArgumentError('Invalid worker watchdog intervals');
  }
  final connection = _WebConnection(web.Worker(resolved.toString().toJS));
  try {
    await connection.ready.future.timeout(startupTimeout);
    connection.watch(heartbeatInterval, responseTimeout);
    return connection;
  } catch (_) {
    await connection.terminate();
    rethrow;
  }
}

final class _WebConnection implements WorkerConnection {
  _WebConnection(this.worker) {
    ready.future.ignore();
    worker.onmessage = ((web.MessageEvent event) {
      if (closed) return;
      try {
        final data = Map<String, Object?>.from(
          jsonDecode((event.data as JSString).toDart) as Map,
        );
        if (data['version'] != 1) {
          throw StateError('Worker protocol version mismatch');
        }
        if (data['type'] == 'ready' &&
            data['runId'] == 0 &&
            !ready.isCompleted) {
          ready.complete();
        } else if (data['runId'] == runId && ready.isCompleted) {
          lastResponse = clock.elapsedMilliseconds;
          if (data['type'] == 'event') {
            eventsController.add(data);
          } else if (data['type'] != 'pong') {
            throw StateError('Unexpected worker message');
          }
        }
      } catch (e) {
        fail(e);
      }
    }).toJS;
    worker.onerror = ((web.Event event) {
      event.preventDefault();
      final message = event.isA<web.ErrorEvent>()
          ? (event as web.ErrorEvent).message
          : 'Script yükleme hatası (${event.type})';
      fail(StateError('Web Worker error: $message'));
    }).toJS;
    worker.onmessageerror = ((web.MessageEvent event) {
      fail(StateError('Web Worker message could not be decoded'));
    }).toJS;
  }
  final web.Worker worker;
  final ready = Completer<void>();
  final eventsController = StreamController<Map<String, Object?>>();
  final clock = Stopwatch()..start();
  Timer? watchdog;
  int runId = 0, lastResponse = 0;
  bool closed = false, failed = false;
  @override
  Stream<Map<String, Object?>> get events => eventsController.stream;
  void fail(Object error) {
    if (closed || failed) return;
    failed = true;
    if (!ready.isCompleted) {
      ready.completeError(error);
    } else {
      eventsController.addError(error);
    }
  }

  void watch(Duration interval, Duration timeout) {
    lastResponse = clock.elapsedMilliseconds;
    watchdog = Timer.periodic(interval, (_) {
      if (clock.elapsedMilliseconds - lastResponse > timeout.inMilliseconds) {
        fail(StateError('Web Worker unresponsive or unexpectedly terminated'));
      } else {
        send({'command': 'ping'});
      }
    });
  }

  @override
  void send(Map<String, Object?> command) {
    if (closed || failed) return;
    if (command['command'] == 'start') runId = command['runId'] as int;
    final payload = {...command, 'version': 1, 'runId': runId};
    if (payload['command'] == 'extend') payload['command'] = 'extendDeadline';
    worker.postMessage(jsonEncode(payload).toJS);
  }

  @override
  Future<void> terminate() async {
    if (closed) return;
    send({'command': 'dispose'});
    closed = true;
    watchdog?.cancel();
    worker.terminate();
    unawaited(eventsController.close());
  }
}
