import 'dart:convert';
import 'dart:js_interop';

import 'package:akys/solver_v2/runtime/lifecycle.dart';

import 'benchmark_shared.dart';

@JS('akysWorkerResult')
external set browserResult(JSString value);
@JS('akysBenchmarkCase')
external set currentCase(JSString value);
Future<void> main() async {
  final rows = <Map<String, Object?>>[];
  for (var rep = 1; rep <= 3; rep++) {
    currentCase = 'web-$rep'.toJS;
    rows.add(
      await measureController(
        OptimizationController.web(workerUri: Uri.parse('akys_v2_worker.js')),
        'Chromium Worker',
        rep,
      ),
    );
  }
  browserResult = jsonEncode({
    'fixture': '6-open',
    'seed': 160600,
    'windowMs': 1000,
    'rows': rows,
  }).toJS;
}
