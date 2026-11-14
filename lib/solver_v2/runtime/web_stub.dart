import 'transport.dart';

const webWorkerSupported = false;
Future<WorkerConnection> createWebWorker(
  Uri uri,
  Duration startupTimeout,
  Duration heartbeatInterval,
  Duration responseTimeout,
) async => throw UnsupportedError(
  'DedicatedWorker yalnız Web üzerinde kullanılabilir.',
);
