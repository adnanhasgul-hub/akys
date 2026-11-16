// Fault injection only: a loopback store stalls before any approval write.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'server.dart';

Future<void> main() async {
  final stub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var commits = 0;
  final pending = <HttpResponse>[];
  final listener = stub.listen((r) async {
    await r.drain<void>();
    if (r.uri.path.endsWith(':batchGet')) {
      pending.add(r.response);
      return;
    }
    if (r.uri.path.endsWith(':commit')) commits++;
    r.response.headers.contentType = ContentType.json;
    r.response.write(
      r.uri.path.endsWith(':beginTransaction')
          ? '{"transaction":"local-test"}'
          : '{}',
    );
    await r.response.close();
  });
  final store = EmulatorApprovalStore(stub.port);
  final clock = Stopwatch()..start();
  var timedOut = false;
  try {
    await store.approve('synthetic', 1, 'test_operation_0000000001', 'admin');
  } on TimeoutException {
    timedOut = true;
  } finally {
    store.client.close(force: true);
    for (final response in pending) {
      await response.close().catchError((Object _) {});
    }
    await listener.cancel();
    await stub.close(force: true);
  }
  if (!timedOut || commits != 0) {
    throw StateError('Timeout produced approval or was not bounded');
  }
  final result = {
    'pass': true,
    'timedOut': timedOut,
    'commitRequests': commits,
    'elapsedMs': clock.elapsedMilliseconds,
  };
  File('tool/solver_v2/results/stage_1_9e_approval_timeout.json')
      .writeAsStringSync('${jsonEncode(result)}\n');
  stdout.writeln(jsonEncode(result));
}
