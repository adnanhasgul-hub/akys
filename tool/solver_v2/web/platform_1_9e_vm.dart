import 'dart:convert';
import 'dart:io';

import 'package:akys/solver_v2/runtime/lifecycle.dart';

import 'platform_1_9d_shared.dart';

Future<void> main() async {
  final rows = <Map<String, Object?>>[];
  for (final fixture in ['6-open', '15-open']) {
    for (final experimental in [false, true]) {
      for (var repeat = 1; repeat <= 3; repeat++) {
        rows.add(
          await measurePlatform(
            OptimizationController(),
            fixture,
            experimental,
            repeat,
          ),
        );
      }
    }
  }
  File('tool/solver_v2/results/stage_1_9e_vm.json').writeAsStringSync(
    jsonEncode({
      'runtime': Platform.version,
      'rows': rows,
      'processRssBytes': ProcessInfo.currentRss,
      'maxRssBytes': ProcessInfo.maxRss,
    }),
  );
}
