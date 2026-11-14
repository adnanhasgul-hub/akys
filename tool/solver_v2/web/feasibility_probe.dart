// First technical probe: actual Dart DFS in a browser DedicatedWorker.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../clinical_resilience.dart';

import 'package:akys/solver_v2/solver.dart';

@JS('self')
external web.DedicatedWorkerGlobalScope get scope;
void main() {
  final s = TransitionSession(
    resilienceProblem('6-open'),
    candidateOrdering: true,
    earlyDeadEnds: true,
  );
  final clock = Stopwatch();
  var budget = 500000, cancelled = false;
  Timer? timer;
  void send(String type) => scope.postMessage(
    jsonEncode({
      'type': type,
      'nodes': s.totalVisitedNodes,
      'elapsed': clock.elapsedMicroseconds,
    }).toJS,
  );
  void step() {
    if (cancelled) return;
    if (clock.elapsedMicroseconds >= budget) {
      send('timeout');
      return;
    }
    s.run(maxNodes: 1000, timeLimit: const Duration(milliseconds: 2));
    timer = Timer(const Duration(milliseconds: 1), step);
  }

  scope.onmessage = ((web.MessageEvent e) {
    final c = jsonDecode((e.data as JSString).toDart) as Map;
    switch (c['command']) {
      case 'start':
        clock.start();
        step();
        send('started');
      case 'extendDeadline':
        budget += 500000;
        send('extended');
      case 'cancel':
        cancelled = true;
        timer?.cancel();
        s.cancel();
        send('cancelled');
    }
  }).toJS;
  send('ready');
}
