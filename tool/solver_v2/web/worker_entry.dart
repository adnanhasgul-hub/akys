// Compile separately with dart compile js. No Flutter, Firebase or DOM dependency.
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:akys/solver_v2/runtime/worker_engine.dart';

@JS('self')
external web.DedicatedWorkerGlobalScope get scope;
void main() {
  var activeRun = 0;
  String? previousBest;
  final engine = WorkerEngine((event) {
    final best = event['best'] == null ? null : jsonEncode(event['best']);
    final state = event['state'];
    final kind = state == 'cancelled'
        ? 'cancelled'
        : state == 'failed'
        ? 'failed'
        : ['optimal', 'infeasible', 'timedOut'].contains(state)
        ? 'completed'
        : best != null && best != previousBest
        ? 'incumbentUpdated'
        : event['sequence'] == 0
        ? 'started'
        : 'progress';
    previousBest = best;
    scope.postMessage(
      jsonEncode({...event, 'version': 1, 'type': 'event', 'event': kind}).toJS,
    );
  });
  scope.onmessage = ((web.MessageEvent event) {
    try {
      final c = Map<String, Object?>.from(
        jsonDecode((event.data as JSString).toDart) as Map,
      );
      if (c['version'] != 1) throw StateError('Unsupported command protocol');
      if (c['command'] == 'start' && activeRun == 0) {
        activeRun = c['runId'] as int;
      }
      if (c['runId'] != activeRun) return;
      if (c['command'] == 'ping') {
        scope.postMessage(
          jsonEncode({'version': 1, 'type': 'pong', 'runId': activeRun}).toJS,
        );
      } else {
        engine.command(c);
        if (c['command'] == 'dispose') scope.close();
      }
    } catch (e) {
      engine.fail(e);
    }
  }).toJS;
  scope.postMessage(
    jsonEncode({'version': 1, 'type': 'ready', 'runId': 0}).toJS,
  );
}
