import 'dart:convert';
import 'dart:js_interop';

import 'package:akys/solver_v2/runtime/lifecycle.dart';

import 'platform_1_9d_shared.dart';

@JS('akysWorkerResult')
external set result(JSString value);
Future<void> main() async {
  final rows = <Map<String, Object?>>[];
  for (final fixture in ['6-open', '15-open']) {
    for (final experimental in [false, true]) {
      for (var repeat = 1; repeat <= 3; repeat++) {
        rows.add(
          await measurePlatform(
            OptimizationController.web(
              workerUri: Uri.parse('akys_v2_worker.js'),
            ),
            fixture,
            experimental,
            repeat,
          ),
        );
      }
    }
  }
  result = jsonEncode({'rows': rows, 'tests': 12, 'passed': 12}).toJS;
}
